## Dedicated server: `godot --headless --path . -- --server --port 9000 --db game.db [--bind 127.0.0.1]`.
## Server-authoritative positions, broadcast at Protocol.TICK_HZ, persisted in SQLite.
extends Node

const SAVE_INTERVAL_S := 10.0
const DOG := preload("res://server/dog.gd")
const MARKS := preload("res://server/marks.gd")
const HUNGER := preload("res://server/hunger.gd")
const INV := preload("res://server/inventory.gd")
const GATHER := preload("res://server/gather.gd")
const WILD := preload("res://server/wildlife.gd")

var _db: RefCounted
var _net: Node
## peer_id -> {name, pos: Vector2, target: Vector2i, stopped: bool, dog: server/dog.gd record,
## hunger: float, sent: what the client was last told of its status, inventory: item id -> count}
var _players := {}
var _marks: Dictionary = MARKS.new_marks()
var _marks_changed := false
var _wild: Dictionary = WILD.new_wild()
var _picked := {}  ## gathered object cell -> seconds until it regrows
var _rng := RandomNumberGenerator.new()
var _tick_acc := 0.0
var _save_acc := 0.0


func _ready() -> void:
	_rng.randomize()
	_wild = WILD.new_wild(_rng.randi())
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
	_players[peer_id] = _new_player(player_name, cell, _db.load_stats(player_name), _db.load_inventory(player_name))
	_net.welcome.rpc_id(peer_id, peer_id, cell)
	_net.marks.rpc_id(peer_id, MARKS.snapshot(_marks))
	_net.status.rpc_id(peer_id, _status_to_send(_players[peer_id]))
	_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	print("server: %s joined at %s" % [player_name, cell])


## A joined player's record at `cell`, with their dog and their saved stats (hunger: full if none).
func _new_player(player_name: String, cell: Vector2i, stats: Dictionary, inventory := {}) -> Dictionary:
	var dog_pos := Vector2(DOG.spot_near(cell, cell + Vector2i(1, 1)))
	return {"name": player_name, "pos": Vector2(cell), "target": Vector2(cell), "stopped": false,
			"dog": DOG.new_dog(dog_pos, hash(player_name)), "hunger": float(stats.get("hunger", HUNGER.MAX)),
			"sent": {}, "inventory": inventory.duplicate()}


func _save(p: Dictionary) -> void:
	_db.save_player(p["name"], Protocol.cell_of(p["pos"]))
	_db.save_stats(p["name"], {"hunger": p["hunger"]})
	_db.save_inventory(p["name"], p.get("inventory", {}))


## The player asks to gather from the object on `cell` (a bush).
func on_gather(peer_id: int, cell: Vector2i) -> void:
	var r := _gather(peer_id, cell)
	if r.is_empty():
		return
	if r["notice"] == "gathered":
		_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	var args := r.duplicate()
	args.erase("notice")
	_net.notice.rpc_id(peer_id, r["notice"], args)


## Gathers for a player from the object on `cell`: {notice: gathered (with item, count), the rule's
## empty notice or too_far}, or {} for a request to ignore (unknown player, nothing gatherable there).
func _gather(peer_id: int, cell: Vector2i) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var rule: Dictionary = GATHER.RULES.get(MapData.object_at(cell), {})
	if rule.is_empty():
		return {}
	var p: Dictionary = _players[peer_id]
	if (p["pos"] as Vector2).distance_to(Vector2(cell)) > GATHER.REACH:
		return {"notice": "too_far"}
	if _picked.has(cell):
		return {"notice": rule["empty"]}
	var n := INV.add(p["inventory"], rule["item"], _rng.randi_range(rule["min"], rule["max"]))
	_picked[cell] = rule["regrow_s"]
	return {"notice": "gathered", "item": rule["item"], "count": n}


## The player eats one of an item from their bag.
func on_eat(peer_id: int, item: String) -> void:
	var r := _eat(peer_id, item)
	if r.is_empty():
		return
	_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	_net.notice.rpc_id(peer_id, "ate", {"item": item})


## Eats one `item` (food the player has): {notice: ate, item}, or {} for a request to ignore.
func _eat(peer_id: int, item: String) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var food: int = ItemData.item(item).get("food", 0)
	var p: Dictionary = _players[peer_id]
	if food <= 0 or not INV.remove(p["inventory"], item, 1):
		return {}
	p["hunger"] = HUNGER.fed(p["hunger"], food)
	return {"notice": "ate", "item": item}


## The player builds a campfire where they stand.
func on_build_fire(peer_id: int) -> void:
	var r := _build_fire(peer_id)
	if r.is_empty():
		return
	if r["notice"] == "fire_built":
		_net.inventory.rpc_id(peer_id, _players[peer_id]["inventory"])
	_net.notice.rpc_id(peer_id, r["notice"], {})


## Builds a campfire (a "fire" mark lasting Protocol.FIRE_S) on the player's cell for FIRE_STICKS
## sticks: {notice: fire_built, need_sticks or fire_here (a fire is already there)}, or {}.
func _build_fire(peer_id: int) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	var p: Dictionary = _players[peer_id]
	var cell := Protocol.cell_of(p["pos"])
	if not _fires_near(Vector2(cell), 1.0).is_empty():
		return {"notice": "fire_here"}
	if not INV.remove(p["inventory"], "sticks", Protocol.FIRE_STICKS):
		return {"notice": "need_sticks"}
	MARKS.add(_marks, "fire", Vector2(cell), Protocol.FIRE_S)
	_marks_changed = true
	return {"notice": "fire_built"}


## Burning campfires within `radius` cells of `pos`: their positions.
func _fires_near(pos: Vector2, radius: float) -> Array:
	var out := []
	for m in MARKS.snapshot(_marks):
		if m["kind"] == "fire" and (m["pos"] as Vector2).distance_to(pos) <= radius:
			out.append(m["pos"])
	return out


## Picked objects regrow.
func _tick_gathering(dt: float) -> void:
	for cell in _picked.keys():
		_picked[cell] -= dt
		if _picked[cell] <= 0.0:
			_picked.erase(cell)


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
	_tick_gathering(dt)
	_move_players(dt)
	_move_dogs(dt)
	_move_wildlife(dt)
	if MARKS.tick(_marks, dt):
		_marks_changed = true
	for id in _players:
		_net.snapshot.rpc_id(id, _snapshot_for(id))
		_net.creatures.rpc_id(id, _creatures_for(id))
		var status := _status_to_send(_players[id])
		if not status.is_empty():
			_net.status.rpc_id(id, status)
	if _marks_changed:
		_marks_changed = false
		var marks := MARKS.snapshot(_marks)
		for id in _players:
			_net.marks.rpc_id(id, marks)


func _move_wildlife(dt: float) -> void:
	WILD.populate(_wild, _players.values().map(func(p): return p["pos"]), dt)
	WILD.update(_wild, _threats(), dt)


## What wild animals flee from: every player and every dog.
func _threats() -> Array:
	var out := []
	for p in _players.values():
		out.append(p["pos"])
		out.append(p["dog"]["pos"])
	return out


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


## The players a player is sent: {id, name, pos}, those within Protocol.INTEREST_RADIUS (and itself).
func _snapshot_for(viewer: int) -> Array:
	var at: Vector2 = _players[viewer]["pos"]
	var out: Array = []
	for id in _players:
		var p: Dictionary = _players[id]
		if id == viewer or at.distance_to(p["pos"]) <= Protocol.INTEREST_RADIUS:
			out.append({"id": id, "name": p["name"], "pos": p["pos"]})
	return out


## The creatures a player is sent: {id, kind, owner (peer id or 0), pos, state}, those within
## Protocol.INTEREST_RADIUS (and its own dog). A dog's id is its owner's peer id; wild animals have
## negative ids (server/wildlife.gd).
func _creatures_for(viewer: int) -> Array:
	var at: Vector2 = _players[viewer]["pos"]
	var out: Array = []
	for id in _players:
		var dog: Dictionary = _players[id]["dog"]
		if id == viewer or at.distance_to(dog["pos"]) <= Protocol.INTEREST_RADIUS:
			out.append({"id": id, "kind": "dog", "owner": id, "pos": dog["pos"], "state": dog["state"]})
	out.append_array(WILD.snapshot_near(_wild, at, Protocol.INTEREST_RADIUS))
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
