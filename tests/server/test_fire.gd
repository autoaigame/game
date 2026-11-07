extends TestCase

## Sticks from trees, and building a campfire from sticks (server/server.gd).

const SERVER_SCRIPT := "res://server/server.gd"
const INV := preload("res://server/inventory.gd")


func _find(id: String) -> Vector2i:
	var s := MapData.spawn_cell()
	for r in 300:
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := s + Vector2i(dx, dy)
				if MapData.object_at(c) == id:
					return c
	return s


## A walkable cell next to `cell`.
func _beside(cell: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
		if MapData.is_walkable(cell + d):
			return cell + d
	return cell


func _server_at(cell: Vector2i, inventory := {}) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", cell, {}, inventory)
	return server


func test_trees_give_sticks() -> void:
	for id in ["oak", "birch", "pine"]:
		var tree := _find(id)
		assert_eq(MapData.object_at(tree), id, "test needs a %s" % id)
		var server := _server_at(_beside(tree))
		var r: Dictionary = server._gather(1, tree)
		assert_eq(r["notice"], "gathered", id)
		assert_eq(r["item"], "sticks")
		assert_true(INV.count(server._players[1]["inventory"], "sticks") >= 1)
		assert_eq(server._gather(1, tree)["notice"], "tree_empty")
		server.free()


func test_build_a_fire_with_sticks() -> void:
	var at := MapData.spawn_cell()
	var server := _server_at(at, {"sticks": Protocol.FIRE_STICKS + 1})
	assert_eq(server._build_fire(1), {"notice": "fire_built"})
	assert_eq(server._players[1]["inventory"], {"sticks": 1})
	var fires: Array = server._fires_near(Vector2(at), 0.5)
	assert_eq(fires.size(), 1)
	var marks: Array = server.MARKS.snapshot(server._marks)
	assert_eq(marks[0]["kind"], "fire")
	assert_eq(marks[0]["pos"], Vector2(at))
	assert_eq(marks[0]["left"], Protocol.FIRE_S)
	assert_true(server._marks_changed, "clients are told")
	server.free()


func test_not_enough_sticks() -> void:
	var server := _server_at(MapData.spawn_cell(), {"sticks": Protocol.FIRE_STICKS - 1})
	assert_eq(server._build_fire(1), {"notice": "need_sticks"})
	assert_eq(server._players[1]["inventory"], {"sticks": Protocol.FIRE_STICKS - 1})
	assert_eq(server.MARKS.snapshot(server._marks), [])
	server.free()


func test_one_fire_per_spot() -> void:
	var server := _server_at(MapData.spawn_cell(), {"sticks": Protocol.FIRE_STICKS * 2})
	server._build_fire(1)
	assert_eq(server._build_fire(1), {"notice": "fire_here"})
	assert_eq(server._players[1]["inventory"], {"sticks": Protocol.FIRE_STICKS}, "kept the sticks")
	server.free()


func test_fire_burns_out() -> void:
	var at := MapData.spawn_cell()
	var server := _server_at(at, {"sticks": Protocol.FIRE_STICKS})
	server._build_fire(1)
	server.MARKS.tick(server._marks, Protocol.FIRE_S + 1.0)
	assert_eq(server._fires_near(Vector2(at), 1.0), [])
	server.free()


func test_unknown_player() -> void:
	var server := _server_at(MapData.spawn_cell())
	assert_eq(server._build_fire(2), {})
	server.free()
