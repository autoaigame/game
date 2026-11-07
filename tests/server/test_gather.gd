extends TestCase

## Gathering berries from bushes into the inventory (server/server.gd, server/gather.gd, server/inventory.gd).

const SERVER_SCRIPT := "res://server/server.gd"
const GATHER := preload("res://server/gather.gd")
const INV := preload("res://server/inventory.gd")


func _bush() -> Vector2i:
	var s := MapData.spawn_cell()
	for r in 300:
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := s + Vector2i(dx, dy)
				if MapData.object_at(c) == "bush":
					return c
	return s


func _server_next_to(bush: Vector2i) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", bush, {})
	server._rng.seed = 11
	return server


func test_inventory_add_remove_cap() -> void:
	var inv := {}
	assert_eq(INV.add(inv, "berries", 3), 3)
	assert_eq(INV.count(inv, "berries"), 3)
	assert_true(INV.remove(inv, "berries", 2))
	assert_eq(INV.count(inv, "berries"), 1)
	assert_false(INV.remove(inv, "berries", 5), "not enough")
	assert_eq(INV.count(inv, "berries"), 1)
	assert_true(INV.remove(inv, "berries", 1))
	assert_false(inv.has("berries"), "empty stacks go")
	assert_eq(INV.add(inv, "berries", INV.MAX_STACK + 10), INV.MAX_STACK)
	assert_eq(INV.add(inv, "berries", 1), 0, "full")


func test_gather_berries_next_to_a_bush() -> void:
	var bush := _bush()
	assert_eq(MapData.object_at(bush), "bush", "test needs a bush")
	var server := _server_next_to(bush)
	var r: Dictionary = server._gather(1, bush)
	var n := INV.count(server._players[1]["inventory"], "berries")
	assert_true(n >= GATHER.RULES["bush"]["min"] and n <= GATHER.RULES["bush"]["max"], "picked %d" % n)
	assert_eq(r, {"notice": "gathered", "item": "berries", "count": n})
	server.free()


func test_a_picked_bush_is_empty_until_it_regrows() -> void:
	var bush := _bush()
	var server := _server_next_to(bush)
	server._gather(1, bush)
	var n := INV.count(server._players[1]["inventory"], "berries")
	assert_eq(server._gather(1, bush)["notice"], "bush_empty")
	assert_eq(INV.count(server._players[1]["inventory"], "berries"), n)
	server._tick_gathering(GATHER.RULES["bush"]["regrow_s"] - 1.0)
	assert_eq(server._gather(1, bush)["notice"], "bush_empty")
	server._tick_gathering(2.0)
	assert_eq(server._gather(1, bush)["notice"], "gathered")
	server.free()


func test_too_far_gathers_nothing() -> void:
	var bush := _bush()
	var server := _server_next_to(bush)
	server._players[1]["pos"] = Vector2(bush) + Vector2(GATHER.REACH + 0.5, 0)
	assert_eq(server._gather(1, bush)["notice"], "too_far")
	assert_eq(server._players[1]["inventory"], {})
	server.free()


## A client cannot make berries from anything but a bush, nor gather for someone else.
func test_not_a_bush_or_unknown_player() -> void:
	var bush := _bush()
	var server := _server_next_to(bush)
	var empty := bush
	for c in [bush + Vector2i(1, 0), bush + Vector2i(0, 1), bush + Vector2i(-1, 0), bush + Vector2i(0, -1)]:
		if MapData.object_at(c) != "bush":
			empty = c
	assert_eq(server._gather(1, empty), {})
	assert_eq(server._gather(2, bush), {})
	assert_eq(server._players[1]["inventory"], {})
	server.free()


func test_inventory_is_saved() -> void:
	var db: Object = load("res://server/db.gd").new()
	db.open(OS.get_cache_dir().path_join("autoaigame_inv_%d.db" % Time.get_ticks_usec()))
	assert_eq(db.load_inventory("ann"), {})
	db.save_inventory("ann", {"berries": 4})
	assert_eq(db.load_inventory("ann"), {"berries": 4})
	db.save_inventory("ann", {})
	assert_eq(db.load_inventory("ann"), {})
	db.close()


func test_new_player_gets_saved_inventory() -> void:
	var server: Node = load(SERVER_SCRIPT).new()
	assert_eq(server._new_player("ann", Vector2i.ZERO, {}, {"berries": 2})["inventory"], {"berries": 2})
	assert_eq(server._new_player("bob", Vector2i.ZERO, {})["inventory"], {})
	server.free()
