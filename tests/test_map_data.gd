extends TestCase


func test_spawn_is_walkable() -> void:
	assert_true(MapData.is_walkable(MapData.spawn_cell()))
	assert_eq(MapData.spawn_cell(), Vector2i(16, 16))


func test_border_is_water() -> void:
	for i in MapData.SIZE.x:
		for cell in [Vector2i(i, 0), Vector2i(i, MapData.SIZE.y - 1), Vector2i(0, i), Vector2i(MapData.SIZE.x - 1, i)]:
			assert_eq(MapData.tile_at(cell), MapData.TILE_WATER, str(cell))
			assert_false(MapData.is_walkable(cell), str(cell))


func test_outside_map_not_walkable() -> void:
	for cell in [Vector2i(-1, 5), Vector2i(5, -1), Vector2i(32, 5), Vector2i(5, 32)]:
		assert_false(MapData.is_walkable(cell), str(cell))


func test_map_is_deterministic() -> void:
	for y in MapData.SIZE.y:
		for x in MapData.SIZE.x:
			assert_eq(MapData.tile_at(Vector2i(x, y)), MapData.tile_at(Vector2i(x, y)))
