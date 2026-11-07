extends TestCase

## Ground decals (client/decals.gd, data/decals/): drawn details that never block.

const AREA := Rect2i(60, -60, 64, 64)


func _all_in_area() -> Array:
	var out := []
	for y in range(AREA.position.y, AREA.end.y):
		for x in range(AREA.position.x, AREA.end.x):
			var d := Decals.decal_at(Vector2i(x, y))
			if not d.is_empty():
				out.append([Vector2i(x, y), d])
	return out


func test_decals_are_loaded_sorted_by_id() -> void:
	var ids := WorldData.decals().map(func(d): return d["id"])
	assert_eq(ids, ["dry_grass_tuft", "flowers", "forest_litter", "leaves", "mud", "pebble", "tuft", "twigs"])
	for d in WorldData.decals():
		assert_true(d["sprites"].size() > 0, d["id"])
		for f in d["sprites"]:
			assert_true(ResourceLoader.exists(f), f)


## A decal picks one of its type's sprites from a hash: in range, stable, every sprite used.
func test_sprite_choice() -> void:
	var seen := {}
	for y in range(AREA.position.y, AREA.end.y):
		for x in range(AREA.position.x, AREA.end.x):
			var d := Decals.decal_at(Vector2i(x, y))
			if d.is_empty():
				continue
			var n: int = WorldData.decals()[d["index"]]["sprites"].size()
			assert_true(d["sprite"] >= 0 and d["sprite"] < n)
			assert_eq(Decals.decal_at(Vector2i(x, y))["sprite"], d["sprite"])
			seen[[d["index"], d["sprite"]]] = true
	var tuft := WorldData.decals().find_custom(func(r): return r["id"] == "tuft")
	for s in WorldData.decals()[tuft]["sprites"].size():
		assert_true(seen.has([tuft, s]), "tuft sprite %d never used" % s)


## Decals sit on allowed, walkable grounds only, never under a blocking object, a little off the
## cell centre at most.
func test_placement_rules() -> void:
	var found := _all_in_area()
	assert_true(found.size() > 100, "only %d decals" % found.size())
	for f in found:
		var cell: Vector2i = f[0]
		var d: Dictionary = f[1]
		var rec: Dictionary = WorldData.decals()[d["index"]]
		var t := MapData.tile_at(cell)
		assert_true(WorldData.tile(t)["walkable"], "decal on %s at %s" % [WorldData.tile(t)["id"], cell])
		assert_true(rec["grounds"].has(t), "%s on %s at %s" % [rec["id"], WorldData.tile(t)["id"], cell])
		var o := MapData.object_index_at(cell)
		assert_false(o >= 0 and WorldData.object(o)["blocks"], "decal under %s at %s" % [MapData.object_at(cell), cell])
		var off: Vector2 = d["offset"]
		assert_true(absf(off.x) <= Decals.MAX_OFFSET and absf(off.y) <= Decals.MAX_OFFSET, str(off))


func test_placement_is_deterministic() -> void:
	var first := _all_in_area()
	MapData.clear_cache()
	assert_eq(_all_in_area(), first)


## On an allowed ground, the share of grid cells holding a decal follows its density.
func test_density() -> void:
	var tuft := WorldData.decals().find_custom(func(d): return d["id"] == "tuft")
	var grass := WorldData.tile_index("grass")
	var tries := 0
	var hits := 0
	for gy in range(-12, 12):  # the meadow: grass, nothing that blocks
		for gx in range(-12, 12):
			var g := Vector2i(gx, gy)
			var cell := Decals.position_in(tuft, g)
			if MapData.tile_at(cell) != grass:
				continue
			tries += 1
			if Decals.is_present(tuft, g):
				hits += 1
	assert_true(tries > 400)
	assert_almost(hits / float(tries), WorldData.decals()[tuft]["density"], 0.06)


## Decals are drawn above the ground and below objects and players, outside the y-sort.
func test_chunk_draws_decals_flat_above_the_ground() -> void:
	var chunk := Vector2i(1, 0)
	var expected := Decals.in_chunk(chunk)
	assert_true(expected.size() > 0)
	var node := ChunkView.build(chunk, null)
	var layer: Node2D = node.get_node("Decals")
	assert_false(layer.y_sort_enabled)
	assert_true(layer.z_index > ChunkView.GROUND_Z + IsoLayer.MASK_COLUMNS and layer.z_index < 0,
			"z %d" % layer.z_index)
	assert_eq(layer.get_child_count(), expected.size())
	for sp: Sprite2D in layer.get_children():
		assert_true(sp.texture != null)
	node.free()
