extends TestCase

## Hand-made places dropped into regions (shared/world_places.gd, data/places/).

const AREA := 6  ## regions -AREA..AREA on both axes


func _accepted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ry in range(-AREA, AREA + 1):
		for rx in range(-AREA, AREA + 1):
			if WorldPlaces.is_accepted(Vector2i(rx, ry)):
				out.append(WorldPlaces.candidate(Vector2i(rx, ry)))
	return out


func _place(c: Dictionary) -> Dictionary:
	return WorldData.places()[c["index"]]


func test_places_are_loaded() -> void:
	var ids := WorldData.places().map(func(p): return p["id"])
	assert_eq(ids, ["camp", "ruin"])
	var camp: Dictionary = WorldData.places()[0]
	assert_eq(camp["size"], Vector2i(11, 11))
	var fire: Array = camp["cells"].filter(func(pc): return pc[2] == WorldData.object_index("campfire"))
	assert_eq(fire.size(), 1)
	assert_eq(fire[0][0], Vector2i(5, 5))
	for p in WorldData.places():
		assert_true(p["size"].x <= WorldPlaces.REGION and p["size"].y <= WorldPlaces.REGION, p["id"])


func test_places_are_deterministic() -> void:
	var first := _accepted().map(func(c): return [c["index"], c["origin"]])
	assert_true(first.size() >= 3, "only %d places in the sample" % first.size())
	MapData.clear_cache()
	var again := _accepted().map(func(c): return [c["index"], c["origin"]])
	assert_eq(again, first)


## Every kept place stands on allowed land (never water), off the meadow, on gentle ground, and far
## enough from the others.
func test_rules_hold() -> void:
	var kept := _accepted()
	for c in kept:
		var p := _place(c)
		var lo := 1.0
		var hi := 0.0
		for pc in p["cells"]:
			var cell: Vector2i = c["origin"] + pc[0]
			var b := Terrain.biome(cell.x, cell.y)
			assert_true(p["biomes"].has(b), "%s on biome %s at %s" % [p["id"], WorldData.biomes()[b]["id"], cell])
			assert_true(WorldData.tile(WorldData.biomes()[b]["tile"])["walkable"], "%s over water at %s" % [p["id"], cell])
			assert_eq(Terrain.meadow_t(cell.x, cell.y), 1.0, "%s on the meadow at %s" % [p["id"], cell])
			var alt := Terrain.altitude(cell.x, cell.y)
			lo = minf(lo, alt)
			hi = maxf(hi, alt)
		assert_true(hi - lo <= p["max_altitude_range"], "%s altitude range %f" % [p["id"], hi - lo])
	for i in kept.size():
		for j in range(i + 1, kept.size()):
			var a: Dictionary = kept[i]
			var b: Dictionary = kept[j]
			var ca := Vector2(a["origin"]) + Vector2(_place(a)["size"]) / 2.0
			var cb := Vector2(b["origin"]) + Vector2(_place(b)["size"]) / 2.0
			var limit := maxf(_place(a)["min_distance"], _place(b)["min_distance"])
			assert_true(ca.distance_to(cb) >= limit, "%s and %s are %f apart" % [a["origin"], b["origin"], ca.distance_to(cb)])


## A place across a chunk border is whole and identical whichever chunk is generated first.
func test_place_across_chunks_is_the_same_from_both_sides() -> void:
	var across: Variant = null
	for c in _accepted():
		var size: Vector2i = _place(c)["size"]
		if MapData.chunk_of(c["origin"]) != MapData.chunk_of(c["origin"] + size - Vector2i.ONE):
			across = c
			break
	assert_true(across != null, "no place across a chunk border in the sample")
	if across == null:
		return
	var p := _place(across)
	var views := []
	for order in 2:
		MapData.clear_cache()
		var cells: Array = p["cells"].duplicate()
		if order == 1:
			cells.reverse()  # generate the chunks in the other order
		var seen := {}
		for pc in cells:
			var cell: Vector2i = across["origin"] + pc[0]
			seen[cell] = [MapData.tile_at(cell), MapData.object_index_at(cell), MapData.place_at(cell)]
		views.append(seen)
	assert_eq(views[1], views[0])
	for pc in p["cells"]:
		var cell: Vector2i = across["origin"] + pc[0]
		var v: Array = views[0][cell]
		if pc[1] >= 0:
			assert_eq(v[0], pc[1], "ground at %s" % cell)
		assert_eq(v[1], pc[2], "object at %s" % cell)
		assert_eq(v[2], p["id"], "place at %s" % cell)


func test_walls_block_and_cleared_cells_have_no_natural_object() -> void:
	var checked := 0
	for c in _accepted():
		var p := _place(c)
		for pc in p["cells"]:
			var cell: Vector2i = c["origin"] + pc[0]
			if pc[2] >= 0 and WorldData.object(pc[2])["blocks"]:
				assert_false(MapData.is_walkable(cell), "%s at %s" % [WorldData.object(pc[2])["id"], cell])
				checked += 1
			elif pc[2] < 0:
				assert_eq(MapData.object_index_at(cell), -1, "natural object left at %s" % cell)
	assert_true(checked > 0)


func test_no_place_on_the_spawn() -> void:
	for y in range(-40, 41, 2):
		for x in range(-40, 41, 2):
			if x * x + y * y <= 40 * 40:
				assert_eq(MapData.place_at(Vector2i(x, y)), "", "%d,%d" % [x, y])
	assert_eq(MapData.spawn_cell(), Vector2i.ZERO)


## The meadow rule alone: the camp fits on the plain grassland near some kept place, but not on the
## (equally flat grassland) meadow around the origin.
func test_meadow_refuses_places() -> void:
	var camp: Dictionary = WorldData.places()[WorldData.places().find_custom(func(p): return p["id"] == "camp")]
	assert_false(WorldPlaces.fits(camp, Vector2i(-5, -5)))
	assert_false(WorldPlaces.fits(camp, Vector2i(10, 10)))
	var kept := _accepted().filter(func(c): return _place(c)["id"] == "camp")
	assert_true(kept.size() > 0)
	if kept.size() > 0:
		assert_true(WorldPlaces.fits(camp, kept[0]["origin"]), "a kept camp fits")


## A footprint stays inside the region that drew it, so the chunks of that region see all of it.
func test_footprints_stay_inside_their_region() -> void:
	for ry in range(-12, 13):
		for rx in range(-12, 13):
			var c := WorldPlaces.candidate(Vector2i(rx, ry))
			if c.is_empty():
				continue
			var far: Vector2i = c["origin"] + _place(c)["size"] - Vector2i.ONE
			assert_eq(WorldPlaces._region_of(c["origin"]), c["region"], str(c["origin"]))
			assert_eq(WorldPlaces._region_of(far), c["region"], str(far))
