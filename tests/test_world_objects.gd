extends TestCase

## Natural objects on a jittered grid (shared/world_objects.gd, data/objects/).


func _find_object(id: String) -> Variant:
	for i in 4000:
		var c := Vector2i(40 + i, -30 - (i * 7) % 300)
		if MapData.object_at(c) == id:
			return c
	return null


func test_objects_are_loaded_sorted_by_id() -> void:
	var ids := WorldData.objects().map(func(o): return o["id"])
	assert_eq(ids, ["bush", "campfire", "oak", "pine", "rock", "standing_stone", "stone_wall"])
	assert_true(WorldData.object(WorldData.object_index("oak"))["blocks"])
	assert_false(WorldData.object(WorldData.object_index("bush"))["blocks"])


## The position stays inside its grid cell, and the same grid cell always gives the same answer.
func test_placement_is_deterministic_and_inside_its_grid_cell() -> void:
	for i in WorldData.objects().size():
		var size: int = WorldData.object(i)["cell_size"]
		for k in 200:
			var g := Vector2i(k * 13 - 900, 400 - k * 7)
			var p := WorldObjects.position_in(i, g)
			assert_eq(Vector2i(floori(p.x / float(size)), floori(p.y / float(size))), g, "%d %s" % [i, g])
			assert_eq(WorldObjects.position_in(i, g), p)
			assert_eq(WorldObjects.is_present(i, g), WorldObjects.is_present(i, g))


func test_objects_do_not_depend_on_the_cache() -> void:
	var cells: Array[Vector2i] = []
	for i in 400:
		cells.append(Vector2i(300 + (i * 7919) % 40, 200 + (i * 104729) % 40))
	var first := cells.map(func(c): return MapData.object_at(c))
	MapData.clear_cache()
	cells.reverse()
	var again := cells.map(func(c): return MapData.object_at(c))
	again.reverse()
	assert_eq(again, first)
	assert_true(first.any(func(o): return o != ""), "no object in the sample")


## Over many grid cells, the share holding an oak follows the density of the biome at its position.
func test_density_follows_the_biome() -> void:
	var oak := WorldData.object_index("oak")
	var hits := {}
	var tries := {}
	for gy in range(-60, 60, 2):
		for gx in range(-60, 60, 2):
			var g := Vector2i(gx, gy) + Vector2i(40, 40)  # away from the meadow
			var p := WorldObjects.position_in(oak, g)
			var b: String = WorldData.biomes()[Terrain.biome(p.x, p.y)]["id"]
			tries[b] = tries.get(b, 0) + 1
			if WorldObjects.is_present(oak, g):
				hits[b] = hits.get(b, 0) + 1
	assert_true(tries.get("forest", 0) > 200, "forest sample %d" % tries.get("forest", 0))
	assert_almost(hits.get("forest", 0) / float(tries["forest"]), 0.7, 0.08, "oaks in forest")
	if tries.get("grassland", 0) > 200:
		assert_almost(hits.get("grassland", 0) / float(tries["grassland"]), 0.05, 0.04, "oaks in grassland")
	for water in ["deep_water", "shallow_water", "river"]:
		assert_eq(hits.get(water, 0), 0, "oak in " + water)


func test_blocking_object_is_not_walkable() -> void:
	var c: Variant = _find_object("oak")
	assert_true(c != null, "no oak found")
	if c != null:
		assert_true(WorldData.tile(MapData.tile_at(c))["walkable"], "an oak stands on walkable ground")
		assert_false(MapData.is_walkable(c))


func test_bush_does_not_block() -> void:
	var c: Variant = _find_object("bush")
	assert_true(c != null, "no bush found")
	if c != null:
		assert_true(MapData.is_walkable(c))


## Nothing blocks the starting meadow: the spawn and the walk of tools/smoke.sh stay clear.
func test_meadow_has_no_blocking_object() -> void:
	for y in range(-26, 27):
		for x in range(-26, 27):
			if x * x + y * y <= 26 * 26:
				var o := MapData.object_index_at(Vector2i(x, y))
				assert_false(o >= 0 and WorldData.object(o)["blocks"], "%s on %d,%d" % [MapData.object_at(Vector2i(x, y)), x, y])
	assert_eq(MapData.spawn_cell(), Vector2i.ZERO)
