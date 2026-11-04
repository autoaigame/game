## Headless test client for tools/smoke.sh. Exits 0 when its expectation holds, 1 otherwise.
## Args (after --): --url U --name N [--move x,y [--hold S]] | --expect-rejected | --expect-absent NAME | --expect-present NAME | --expect-welcome x,y
extends SceneTree

const TIMEOUT_S := 8.0

var _client: Node
var _args := {}
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--"):
			_args[a[i].substr(2)] = a[i + 1] if i + 1 < a.size() and not a[i + 1].begins_with("--") else ""
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	var net: Node = load("res://shared/net.gd").new()
	net.name = "Net"
	main.add_child(net)
	_client = load("res://client/client.gd").new()
	_client.name = "Role"
	_client.server_url = _args["url"]
	_client.player_name = _args["name"]
	main.add_child(_client)
	_client.welcomed.connect(_on_welcomed)
	_client.join_rejected.connect(_on_rejected)
	_client.snapshot_received.connect(_on_snapshot)


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_S and not _args.has("hold"):
		_finish(false, "timeout")
	return false


func _on_welcomed(cell: Vector2i) -> void:
	print("WELCOME %d,%d" % [cell.x, cell.y])
	if _args.has("expect-welcome"):
		_finish(cell == _parse_cell(_args["expect-welcome"]), "welcome at %s" % cell)
	elif _args.has("expect-rejected"):
		_finish(false, "was welcomed")
	elif _args.has("move"):
		_client.request_move(_parse_cell(_args["move"]))


func _on_rejected(reason: String) -> void:
	print("REJECTED %s" % reason)
	_finish(_args.has("expect-rejected"), reason)


func _on_snapshot(players: Array) -> void:
	if _done:
		return
	if _args.has("move"):
		for p in players:
			if p["name"] == _args["name"] and Protocol.cell_of(p["pos"]) == _parse_cell(_args["move"]):
				print("REACHED")
				if not _args.has("hold"):
					_finish(true, "reached")
				else:
					_done = true
	elif _args.has("expect-present"):
		for p in players:
			if p["name"] == _args["expect-present"]:
				_finish(true, "present at %s" % Protocol.cell_of(p["pos"]))
	elif _args.has("expect-absent") and _elapsed > 0.5:
		var names := players.map(func(p): return p["name"])
		if not names.has(_args["expect-absent"]):
			_finish(true, "absent")


func _finish(ok: bool, why: String) -> void:
	if _done and ok:
		return
	_done = true
	print(("PASS " if ok else "FAIL ") + why)
	quit(0 if ok else 1)


func _parse_cell(s: String) -> Vector2i:
	var parts := s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
