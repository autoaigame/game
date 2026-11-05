## Dedicated server: `godot --headless --path . -- --server --port 9000 --db game.db [--bind 127.0.0.1]`.
## Server-authoritative positions, broadcast at Protocol.TICK_HZ, persisted in SQLite.
extends Node

const SAVE_INTERVAL_S := 10.0

var _db: RefCounted
var _net: Node
## peer_id -> {name: String, pos: Vector2, target: Vector2i, stopped: bool}
var _players := {}
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
			_db.save_player(p["name"], Protocol.cell_of(p["pos"]))


func on_join(peer_id: int, player_name: String) -> void:
	if _players.has(peer_id):
		return
	var problem := Protocol.validate_name(player_name)
	if problem == "" and _players.values().any(func(p): return p["name"] == player_name):
		problem = "Someone named %s is already playing." % player_name
	if problem != "":
		_net.rejected.rpc_id(peer_id, problem)
		return
	var saved: Variant = _db.load_player(player_name)
	var cell: Vector2i = saved if saved != null and MapData.is_walkable(saved) else MapData.spawn_cell()
	_players[peer_id] = {"name": player_name, "pos": Vector2(cell), "target": cell, "stopped": false}
	_net.welcome.rpc_id(peer_id, peer_id, cell)
	print("server: %s joined at %s" % [player_name, cell])


func on_move_to(peer_id: int, cell: Vector2i) -> void:
	if _players.has(peer_id) and MapData.is_walkable(cell):
		_players[peer_id]["target"] = cell
		_players[peer_id]["stopped"] = false


## The player stays where it is until its next move_to.
func on_stop(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id]["stopped"] = true


func _on_peer_disconnected(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var p: Dictionary = _players[peer_id]
	_db.save_player(p["name"], Protocol.cell_of(p["pos"]))
	_players.erase(peer_id)
	print("server: %s left" % p["name"])


func _step(dt: float) -> void:
	_move_players(dt)
	var snap: Array = []
	for id in _players:
		var p: Dictionary = _players[id]
		snap.append({"id": id, "name": p["name"], "pos": p["pos"]})
	for id in _players:
		_net.snapshot.rpc_id(id, snap)


func _move_players(dt: float) -> void:
	for p in _players.values():
		if not p["stopped"]:
			p["pos"] = Protocol.step_towards(p["pos"], p["target"], dt)


func _exit_tree() -> void:
	if _db != null:
		for p in _players.values():
			_db.save_player(p["name"], Protocol.cell_of(p["pos"]))
		_db.close()


func _parse_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size() and not a[i + 1].begins_with("--"):
			out[a[i].substr(2)] = a[i + 1]
	return out
