extends TestCase

## Eating food from the bag (server/server.gd, server/hunger.gd).

const SERVER_SCRIPT := "res://server/server.gd"
const HUNGER := preload("res://server/hunger.gd")


func _server(hunger: float, inventory: Dictionary) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", MapData.spawn_cell(), {"hunger": hunger}, inventory)
	return server


func test_eating_berries_feeds_and_uses_one() -> void:
	var server := _server(50.0, {"berries": 2})
	assert_eq(server._eat(1, "berries"), {"notice": "ate", "item": "berries"})
	assert_almost(server._players[1]["hunger"], 50.0 + ItemData.item("berries")["food"])
	assert_eq(server._players[1]["inventory"], {"berries": 1})
	server.free()


func test_never_above_full() -> void:
	var server := _server(HUNGER.MAX - 1.0, {"berries": 1})
	server._eat(1, "berries")
	assert_eq(server._players[1]["hunger"], HUNGER.MAX)
	server.free()


func test_cannot_eat_what_you_do_not_have() -> void:
	var server := _server(50.0, {})
	assert_eq(server._eat(1, "berries"), {})
	assert_eq(server._players[1]["hunger"], 50.0)
	server.free()


func test_cannot_eat_what_is_not_food_or_unknown() -> void:
	var server := _server(50.0, {"stone": 1})
	assert_eq(server._eat(1, "stone"), {})
	assert_eq(server._players[1]["inventory"], {"stone": 1})
	assert_eq(server._eat(2, "berries"), {}, "unknown player")
	server.free()


func test_hunger_add_caps() -> void:
	assert_eq(HUNGER.fed(90.0, 30), HUNGER.MAX)
	assert_eq(HUNGER.fed(10.0, 8), 18.0)
