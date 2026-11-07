extends TestCase

## Cooking raw food on a campfire (server/server.gd).

const SERVER_SCRIPT := "res://server/server.gd"
const INV := preload("res://server/inventory.gd")


func _server(inventory: Dictionary, fire_offset: Variant) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	var at := MapData.spawn_cell()
	server._players[1] = server._new_player("ann", at, {}, inventory)
	if fire_offset != null:
		server.MARKS.add(server._marks, "fire", Vector2(at) + fire_offset, 60.0)
	return server


func test_cooked_meat_feeds_much_more() -> void:
	assert_eq(ItemData.item("raw_meat")["cooks_into"], "cooked_meat")
	assert_true(ItemData.item("cooked_meat")["food"] >= 4 * ItemData.item("raw_meat")["food"])
	assert_eq(ItemData.item("berries")["cooks_into"], "", "berries are not cooked")


func test_cook_next_to_a_fire() -> void:
	var server := _server({"raw_meat": 2}, Vector2(1, 1))
	assert_eq(server._cook(1, "raw_meat"), {"notice": "cooked", "item": "cooked_meat"})
	assert_eq(server._players[1]["inventory"], {"raw_meat": 1, "cooked_meat": 1})
	server.free()


func test_no_fire_near() -> void:
	var server := _server({"raw_meat": 1}, Vector2(Protocol.COOK_REACH + 1.0, 0))
	assert_eq(server._cook(1, "raw_meat"), {"notice": "no_fire"})
	assert_eq(server._players[1]["inventory"], {"raw_meat": 1})
	server.free()


func test_only_what_you_have_and_what_cooks() -> void:
	var server := _server({"berries": 3}, Vector2.ZERO)
	assert_eq(server._cook(1, "raw_meat"), {})
	assert_eq(server._cook(1, "berries"), {})
	assert_eq(server._players[1]["inventory"], {"berries": 3})
	assert_eq(server._cook(2, "raw_meat"), {}, "unknown player")
	server.free()


func test_a_full_stack_of_cooked_meat_keeps_the_raw_one() -> void:
	var server := _server({"raw_meat": 1, "cooked_meat": INV.MAX_STACK}, Vector2.ZERO)
	assert_eq(server._cook(1, "raw_meat"), {"notice": "bag_full"})
	assert_eq(INV.count(server._players[1]["inventory"], "raw_meat"), 1)
	server.free()
