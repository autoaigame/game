extends TestCase

## Footstep sounds (client/footsteps.gd): two per walk cycle, by the ground under the feet.


func test_every_walkable_ground_has_step_sounds() -> void:
	var table := Footsteps.load_table()
	for i in WorldData.tiles().size():
		var t := WorldData.tile(i)
		if not t["walkable"]:
			continue
		var variants: Array = table.get(i, [])
		assert_true(variants.size() >= 2, "ground %s" % t["id"])
		for s in variants:
			assert_true(ResourceLoader.exists(Footsteps.sound_path(s)), s)


func test_forest_and_grass_sound_different() -> void:
	var table := Footsteps.load_table()
	assert_true(table[WorldData.tile_index("forest_floor")] != table[WorldData.tile_index("grass")])


func test_variant_never_repeats_twice_in_a_row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var last := -1
	var seen := {}
	for i in 100:
		var v: int = Footsteps.pick_variant(rng, 4, last)
		assert_true(v != last and v >= 0 and v < 4)
		seen[v] = true
		last = v
	assert_eq(seen.size(), 4)
	assert_eq(Footsteps.pick_variant(rng, 1, 0), 0)
