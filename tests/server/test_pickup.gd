extends TestCase

## Picking up a caught animal gives raw meat (server/server.gd).

const SERVER_SCRIPT := "res://server/server.gd"
const INV := preload("res://server/inventory.gd")


func _server_with_carcass(kind: String, offset := Vector2.ZERO) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	var at := MapData.spawn_cell()
	server._players[1] = server._new_player("ann", at, {})
	server.MARKS.add(server._marks, kind, Vector2(at) + offset, 60.0)
	return server


func _mark_id(server: Node) -> int:
	return server.MARKS.snapshot(server._marks)[0]["id"]


func test_pick_up_a_rabbit() -> void:
	var server := _server_with_carcass("carcass_rabbit", Vector2(1, 0))
	var id := _mark_id(server)
	var r: Dictionary = server._pick_up(1, id)
	assert_eq(r, {"notice": "gathered", "item": "raw_meat", "count": server.MEAT["carcass_rabbit"]})
	assert_eq(INV.count(server._players[1]["inventory"], "raw_meat"), server.MEAT["carcass_rabbit"])
	assert_eq(server.MARKS.snapshot(server._marks), [], "gone from the ground")
	assert_true(server._marks_changed)
	assert_eq(server._pick_up(1, id), {}, "only once")
	server.free()


func test_every_carcass_gives_meat() -> void:
	for kind in ["carcass_rabbit", "carcass_pheasant"]:
		assert_true(server_meat(kind) > 0, kind)


func server_meat(kind: String) -> int:
	return load(SERVER_SCRIPT).MEAT.get(kind, 0)


func test_too_far() -> void:
	var server := _server_with_carcass("carcass_rabbit", Vector2(Protocol.GATHER_REACH + 1.0, 0))
	assert_eq(server._pick_up(1, _mark_id(server)), {"notice": "too_far"})
	assert_eq(server._players[1]["inventory"], {})
	server.free()


func test_not_a_carcass_or_unknown_player() -> void:
	var server := _server_with_carcass("hole")
	assert_eq(server._pick_up(1, _mark_id(server)), {})
	assert_eq(server.MARKS.snapshot(server._marks).size(), 1, "the hole stays")
	assert_eq(server._pick_up(2, _mark_id(server)), {})
	assert_eq(server._pick_up(1, 999), {})
	server.free()


func test_meat_items() -> void:
	assert_true(ItemData.item("raw_meat")["food"] > 0)
	assert_eq(ItemData.item("raw_meat")["cooks_into"], "cooked_meat")
