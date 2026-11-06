extends TestCase

## Where a joining player appears (server.gd join_cell), docs/invariants.md rules 2 and 5.

const SERVER_SCRIPT := "res://server/server.gd"


func _water_cell() -> Vector2i:
	for i in 4000:
		var c := Vector2i(i, i)
		if not MapData.is_walkable(c):
			return c
	return Vector2i.ZERO


func test_new_player_spawns_at_spawn() -> void:
	assert_eq(load(SERVER_SCRIPT).join_cell(null), MapData.spawn_cell())


func test_saved_walkable_cell_is_kept() -> void:
	assert_eq(load(SERVER_SCRIPT).join_cell(Vector2i(18, 16)), Vector2i(18, 16))


## A position saved on the old map that is now water moves to the nearest walkable cell.
func test_saved_cell_now_unwalkable_moves_to_nearest_walkable() -> void:
	var water := _water_cell()
	assert_false(MapData.is_walkable(water), "test needs a water cell")
	var cell: Vector2i = load(SERVER_SCRIPT).join_cell(water)
	assert_true(MapData.is_walkable(cell), "joined on %s" % cell)
	assert_eq(cell, MapData.nearest_walkable(water))
	assert_true(cell != MapData.spawn_cell(), "should stay near the saved cell, not go back to spawn")
