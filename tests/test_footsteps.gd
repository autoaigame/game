extends TestCase

## Footstep sounds (client/footsteps.gd): two per walk cycle, by the ground under the feet.


## Walking along: each footstep sounds on the frame where a foot lands (WalkAnim.CONTACT_FRAMES),
## two per cycle, and none once the walker has stopped.
func test_step_falls_on_a_contact_frame() -> void:
	var w := WalkAnim.new_state(Vector2(10, 10))
	var frames := []
	for i in 240:  # 4 s at 60 fps, walking east then standing
		if i < 150:
			w["server"] = Vector2(10, 10) + Vector2(Protocol.SPEED_CELLS_PER_S * (i + 1) / 60.0, 0)
		var before: float = w["phase"]
		WalkAnim.animate(w, 1.0 / 60.0)
		var n := Footsteps.steps(before, w["phase"])
		for k in n:
			frames.append(WalkAnim.walk_frame(w["phase"]) if i < 160 else -1)
	assert_true(frames.size() >= 4, str(frames))
	for k in frames.size():
		assert_eq(frames[k], WalkAnim.CONTACT_FRAMES[k % 2], "step %d: %s" % [k, frames])


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
