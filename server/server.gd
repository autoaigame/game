## Dedicated server: `godot --headless --path . -- --server --port 9000 --db game.db [--bind 127.0.0.1]`.
## Server-authoritative positions, broadcast at Protocol.TICK_HZ, persisted in SQLite.
extends Node

const SAVE_INTERVAL_S := 10.0
const DOG := preload("res://server/dog.gd")
const MARKS := preload("res://server/marks.gd")
const HUNGER := preload("res://server/hunger.gd")

var _db: RefCounted
var _net: Node
## peer_id -> {name, pos: Vector2, target: Vector2i, stopped: bool, dog: server/dog.gd record,
## hunger: float, sent: what the client was last told of its status}
var _players := {}
var _marks: Dictionary = MARKS.new_marks()
var _marks_changed := false
var _tick_acc := 0.0
var _save_acc := 0.0


func _ready() -> void:
	var args := _parse_args()
	_db = load("res://server/db.gd").new()
	if not _db.open(args.get("db", "user://game.db")):
		get_tree().quit(1)
		return
	_net = get_parent().get_node("Net")
	_net.set_handler(self)
	var peer := WebSocketMultiplayerPeer.new()
	var port := int(args.get("port", Protocol.DEFAULT_PORT))
	var err := peer.create_server(port, args.get("bind", "127.0.0.1"))
	if err != OK:
		push_error("server: cannot listen on %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("server: listening on %d" % port)


func _process(delta: float) -> void:
	_tick_acc += delta
	var tick := 1.0 / Protocol.TICK_HZ
	if _tick_acc >= tick:
		_step(_tick_acc)
		_tick_acc = 0.0
	_save_acc += delta
	if _save_acc >= SAVE_INTERVAL_S:
		_save_acc = 0.0
		for p in _players.values():
			_save(p)


func on_join(peer_id: int, player_name: String) -> void:
	if _players.has(peer_id):
		return
	var problem := Protocol.validate_name(player_name)
	if problem == "" and _players.values().any(func(p): return p["name"] == player_name):
		problem = "Someone named %s is already playing." % player_name
	if problem != "":
		_net.rejected.rpc_id(peer_id, problem)
		return
	var cell := join_cell(_db.load_player(player_name))
	_players[peer_id] = _new_player(player_name, cell, _db.load_stats(player_name))
	_net.welcome.rpc_id(peer_id, peer_id, cell)
	_net.marks.rpc_id(peer_id, MARKS.snapshot(_marks))
	_net.status.rpc_id(peer_id, _status_to_send(_players[peer_id]))
	print("server: %s joined at %s" % [player_name, cell])


## A joined player's record at `cell`, with their dog and their saved stats (hunger: full if none).
func _new_player(player_name: String, cell: Vector2i, stats: Dictionary) -> Dictionary:
	var dog_pos := Vector2(DOG.spot_near(cell, cell + Vector2i(1, 1)))
	return {"name": player_name, "pos": Vector2(cell), "target": Vector2(cell), "stopped": false,
			"dog": DOG.new_dog(dog_pos, hash(player_name)), "hunger": float(stats.get("hunger", HUNGER.MAX)),
			"sent": {}}


func _save(p: Dictionary) -> void:
	_db.save_player(p["name"], Protocol.cell_of(p["pos"]))
	_db.save_stats(p["name"], {"hunger": p["hunger"]})


## Where a joining player appears: its saved cell, or the walkable cell nearest to it if the map
## changed under it (old saves), or the spawn for a new player.
static func join_cell(saved: Variant) -> Vector2i:
	if saved == null:
		return MapData.spawn_cell()
	if MapData.is_walkable(saved):
		return saved
	var near: Variant = MapData.nearest_walkable(saved)
	return near if near != null else MapData.spawn_cell()


## target is any point in cell units. Refused unless it is a real number on a walkable cell.
func on_move_to(peer_id: int, target: Vector2) -> void:
	if _players.has(peer_id) and target.is_finite() and MapData.is_walkable(Protocol.cell_of(target)):
		_players[peer_id]["target"] = target
		_players[peer_id]["stopped"] = false


## The player stays where it is until its next move_to.
func on_stop(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id]["stopped"] = true


func _on_peer_disconnected(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var p: Dictionary = _players[peer_id]
	_save(p)
	_players.erase(peer_id)
	print("server: %s left" % p["name"])


func _step(dt: float) -> void:
	_tick_hunger(dt)
	_move_players(dt)
	_move_dogs(dt)
	if MARKS.tick(_marks, dt):
		_marks_changed = true
	var snap: Array = []
	for id in _players:
		var p: Dictionary = _players[id]
		snap.append({"id": id, "name": p["name"], "pos": p["pos"]})
	var creatures := _creature_snapshot()
	for id in _players:
		_net.snapshot.rpc_id(id, snap)
		_net.creatures.rpc_id(id, creatures)
		var status := _status_to_send(_players[id])
		if not status.is_empty():
			_net.status.rpc_id(id, status)
	if _marks_changed:
		_marks_changed = false
		var marks := MARKS.snapshot(_marks)
		for id in _players:
			_net.marks.rpc_id(id, marks)


func _move_dogs(dt: float) -> void:
	for p in _players.values():
		_add_events(DOG.update(p["dog"], p["pos"], dt))


## Turns creature events into marks on the ground.
func _add_events(events: Array) -> void:
	for e in events:
		match e["kind"]:
			"pee":
				MARKS.add(_marks, "pee", e["pos"], DOG.PEE_MARK_S)
			"hole":
				MARKS.add(_marks, "hole", e["pos"], DOG.HOLE_MARK_S)
			_:
				continue
		_marks_changed = true


## The creatures clients draw: {id, kind, owner (peer id or 0), pos, state}. A dog's id is its owner's peer id.
func _creature_snapshot() -> Array:
	var out: Array = []
	for id in _players:
		var dog: Dictionary = _players[id]["dog"]
		out.append({"id": id, "kind": "dog", "owner": id, "pos": dog["pos"], "state": dog["state"]})
	return out


func _move_players(dt: float) -> void:
	for p in _players.values():
		if not p["stopped"]:
			p["pos"] = Protocol.step_towards(p["pos"], p["target"], dt * HUNGER.speed_factor(p.get("hunger", HUNGER.MAX)))


func _tick_hunger(dt: float) -> void:
	for p in _players.values():
		p["hunger"] = HUNGER.tick(p.get("hunger", HUNGER.MAX), dt)


## What the player's client should be told of their own status ({hunger: int}), or {} if it already
## shows it. Remembers what was sent.
func _status_to_send(p: Dictionary) -> Dictionary:
	var now := {"hunger": roundi(p["hunger"])}
	if now == p["sent"]:
		return {}
	p["sent"] = now
	return now


func _exit_tree() -> void:
	if _db != null:
		for p in _players.values():
			_save(p)
		_db.close()


func _parse_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size() and not a[i + 1].begins_with("--"):
			out[a[i].substr(2)] = a[i + 1]
	return out
