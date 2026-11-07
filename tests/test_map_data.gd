extends TestCase

## The infinite generated map (shared/map_data.gd, shared/terrain.gd, data/).


func _tile_id(cell: Vector2i) -> String:
	return WorldData.tile(MapData.tile_at(cell))["id"]


## First cell from `from` along `dir` whose tile is `id`, within `limit` cells, or null.
func _find_along(from: Vector2i, dir: Vector2i, id: String, limit := 2000) -> Variant:
	for i in limit:
		var c := from + dir * i
		if _tile_id(c) == id:
			return c
	return null


func test_spawn_is_walkable_and_nearest_to_origin() -> void:
	var s := MapData.spawn_cell()
	assert_true(MapData.is_walkable(s))
	var r := int(ceil(Vector2(s).length()))
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y < s.length_squared():
				assert_false(MapData.is_walkable(Vector2i(x, y)), "%d,%d is closer than the spawn" % [x, y])


## The starting meadow around the origin is walkable land, so the spawn is pleasant. 25 cells at
## least: tools/smoke.sh walks in a straight line from the spawn to (18, 16).
func test_meadow_around_origin_is_walkable_grass() -> void:
	var radius := 25
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				assert_true(MapData.is_walkable(Vector2i(x, y)), "%d,%d" % [x, y])
				assert_eq(_tile_id(Vector2i(x, y)), "grass", "%d,%d" % [x, y])


func test_world_has_no_edge() -> void:
	for cell in [Vector2i(-1, 5), Vector2i(5, -1), Vector2i(100000, -100000), Vector2i(-77777, 31)]:
		var t := MapData.tile_at(cell)
		assert_true(t >= 0 and t < WorldData.tiles().size(), "%s -> %d" % [cell, t])


## Results never depend on the cache or on the order of the questions.
func test_map_is_deterministic_and_cache_independent() -> void:
	var cells: Array[Vector2i] = []
	for i in 300:  # a few chunks around a far place (every new chunk costs 256 cells)
		cells.append(Vector2i(5000 + (i * 7919) % 48, -3000 + (i * 104729) % 48))
	var first := cells.map(func(c): return MapData.tile_at(c))
	MapData.clear_cache()
	cells.reverse()
	var again := cells.map(func(c): return MapData.tile_at(c))
	again.reverse()
	assert_eq(again, first)


func test_chunk_of_floors_negative_cells() -> void:
	assert_eq(MapData.chunk_of(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(MapData.chunk_of(Vector2i(15, 16)), Vector2i(0, 1))
	assert_eq(MapData.chunk_of(Vector2i(-1, -16)), Vector2i(-1, -1))
	assert_eq(MapData.chunk_of(Vector2i(-17, 100000)), Vector2i(-2, 6250))


## Walkable: the ground is walkable and no blocking object stands there.
func test_walkable_follows_tile_data_and_objects() -> void:
	for i in 400:
		var c := Vector2i(-2600 + (i * 13) % 64, -5000 + (i * 29) % 64)
		var o := MapData.object_index_at(c)
		var blocked: bool = o >= 0 and WorldData.object(o)["blocks"]
		assert_eq(MapData.is_walkable(c), WorldData.tile(MapData.tile_at(c))["walkable"] and not blocked, str(c))


func test_water_is_not_walkable() -> void:
	var c: Variant = _find_along(Vector2i.ZERO, Vector2i(1, 0), "deep_water")
	if c == null:
		c = _find_along(Vector2i.ZERO, Vector2i(0, 1), "deep_water")
	assert_true(c != null, "no deep water found")
	if c != null:
		assert_false(MapData.is_walkable(c))


## Over a large area every ground type appears, and water stays a minority. Samples the terrain
## directly: through MapData every sample would generate a whole chunk.
func test_world_has_variety() -> void:
	var count := {}
	var n := 0
	for y in range(-1024, 1024, 16):
		for x in range(-1024, 1024, 16):
			var id: String = WorldData.tile(WorldData.biomes()[Terrain.biome(x, y)]["tile"])["id"]
			count[id] = count.get(id, 0) + 1
			n += 1
	for b in WorldData.biomes():  # natural grounds (places add more)
		var id: String = WorldData.tile(b["tile"])["id"]
		assert_true(count.get(id, 0) > 0, "no %s in the sample" % id)
	var water: float = count.get("deep_water", 0) + count.get("shallow_water", 0)
	assert_true(water / n > 0.08 and water / n < 0.35, "water share %f" % (water / n))
	assert_true(count.get("forest_floor", 0) / float(n) < 0.4, "forest share %f" % (count.get("forest_floor", 0) / float(n)))


func test_nearest_walkable_from_water() -> void:
	var water: Variant = _find_along(Vector2i.ZERO, Vector2i(1, 1), "deep_water")
	assert_true(water != null, "no deep water found")
	if water == null:
		return
	var w: Vector2i = water
	var near: Variant = MapData.nearest_walkable(w)
	assert_true(near != null and MapData.is_walkable(near), "got %s" % near)
	if near == null:
		return
	var d2: int = (near - w).length_squared()
	var r := int(ceil(sqrt(d2)))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy < d2:
				assert_false(MapData.is_walkable(w + Vector2i(dx, dy)), "%s is closer" % (w + Vector2i(dx, dy)))


## The nearest cell may lie in a farther square ring: (0, 4) is nearer than (3, 3).
func test_nearest_looks_beyond_the_first_ring_that_matches() -> void:
	assert_eq(MapData.nearest_of(Vector2i.ZERO, {Vector2i(3, 3): true, Vector2i(0, 4): true}), Vector2i(0, 4))
	assert_eq(MapData.nearest_of(Vector2i(10, 10), {Vector2i(13, 13): true, Vector2i(10, 14): true}),
			Vector2i(10, 14))


func test_nearest_ties_are_deterministic() -> void:
	var cells := {Vector2i(2, 0): true, Vector2i(-2, 0): true, Vector2i(0, 2): true, Vector2i(0, -2): true}
	assert_eq(MapData.nearest_of(Vector2i.ZERO, cells), Vector2i(0, -2))


func test_nearest_walkable_of_walkable_is_itself() -> void:
	assert_eq(MapData.nearest_walkable(Vector2i(3, -4)), Vector2i(3, -4))


func test_tiles_are_sorted_by_unique_priority() -> void:
	var tiles := WorldData.tiles()
	assert_true(tiles.size() >= 6)
	for i in range(1, tiles.size()):
		assert_true(tiles[i]["priority"] > tiles[i - 1]["priority"], tiles[i]["id"])
	for id in ["deep_water", "shallow_water", "sand", "grass", "dry_grass", "forest_floor"]:
		assert_true(WorldData.tile_index(id) >= 0, "missing tile " + id)
	assert_false(WorldData.tile(WorldData.tile_index("deep_water"))["walkable"])
	assert_false(WorldData.tile(WorldData.tile_index("shallow_water"))["walkable"])
	assert_true(WorldData.tile(WorldData.tile_index("forest_floor"))["walkable"])


## Golden cells: any change here changes every world. Update only on purpose, and say so in the PR.
func test_golden_tiles() -> void:
	for g in GOLDEN_TILES:
		assert_eq(_tile_id(g[0]), g[1], str(g[0]))


const GOLDEN_TILES := [
	[Vector2i(0, 0), "grass"],
	[Vector2i(40, -30), "forest_floor"],
	[Vector2i(67, -48), "dry_grass"],
	[Vector2i(106, -74), "grass"],
	[Vector2i(148, -102), "sand"],
	[Vector2i(178, -122), "deep_water"],
	[Vector2i(322, -218), "shallow_water"],
	[Vector2i(100000, -100000), "dry_grass"],
	[Vector2i(-1000, 1000), "dry_grass"],
	[Vector2i(0, -150), "deep_water"],
]
