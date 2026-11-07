extends TestCase

## Layered ambience (client/ambience_mix.gd): which ambience plays where, how it fades, when its
## one-shot sounds fire. Client display only: nothing here reaches the server.


func _amb(id: String, grounds: Array, debug_only := false) -> Dictionary:
	var g := {}
	for t in grounds:
		g[t] = true
	return {"id": id, "grounds": g, "debug_only": debug_only}


func test_data_loads_meadow_forest_and_debug_uneasy() -> void:
	var all := AmbienceMix.load_all()
	var ids := all.map(func(a): return a["id"])
	assert_eq(ids, ["forest", "meadow", "uneasy"])
	assert_false(AmbienceMix.find(all, "meadow")["debug_only"])
	assert_false(AmbienceMix.find(all, "forest")["debug_only"])
	assert_true(AmbienceMix.find(all, "uneasy")["debug_only"])


func test_every_ambience_sound_file_exists() -> void:
	for a in AmbienceMix.load_all():
		for b in a["beds"]:
			assert_true(ResourceLoader.exists(AmbienceMix.sound_path(b["sound"])), "%s bed %s" % [a["id"], b["sound"]])
		for e in a["events"]:
			assert_true(e["sounds"].size() > 0, a["id"])
			for s in e["sounds"]:
				assert_true(ResourceLoader.exists(AmbienceMix.sound_path(s)), "%s event %s" % [a["id"], s])


## Counting the grounds in a disc: every cell once, by its tile.
func test_ground_counts_cover_the_disc() -> void:
	var c := MapData.spawn_cell()
	var one := AmbienceMix.ground_counts(c, 0)
	assert_eq(one, {MapData.tile_at(c): 1})
	var counts := AmbienceMix.ground_counts(c, 3)
	var total := 0
	for k in counts:
		total += counts[k]
	assert_eq(total, 29)  # cells with dx² + dy² <= 9


func test_forest_ground_picks_forest_grass_picks_meadow() -> void:
	var all := AmbienceMix.load_all()
	var grass := WorldData.tile_index("grass")
	var forest := WorldData.tile_index("forest_floor")
	assert_eq(AmbienceMix.choose(all, {grass: 20, forest: 9}, ""), "meadow")
	assert_eq(AmbienceMix.choose(all, {grass: 5, forest: 24}, ""), "forest")


## Debug-only ambiences never play on their own, even when nothing else matches.
func test_debug_only_never_chosen_automatically() -> void:
	var list := [_amb("a", [1]), _amb("eerie", [2], true)]
	assert_eq(AmbienceMix.choose(list, {2: 30}, ""), "a")
	assert_eq(AmbienceMix.choose(list, {2: 30}, "a"), "a")


## Walking along a forest edge does not flip between ambiences: the new one must lead clearly.
func test_switch_needs_a_clear_lead() -> void:
	var list := [_amb("a", [1]), _amb("b", [2])]
	assert_eq(AmbienceMix.choose(list, {1: 14, 2: 15}, "a"), "a")
	assert_eq(AmbienceMix.choose(list, {1: 15, 2: 14}, "b"), "b")
	assert_eq(AmbienceMix.choose(list, {1: 8, 2: 21}, "a"), "b")


## Ground that no ambience lists (water) keeps the current one.
func test_unknown_ground_keeps_current() -> void:
	var list := [_amb("a", [1]), _amb("b", [2])]
	assert_eq(AmbienceMix.choose(list, {7: 29}, "b"), "b")
	assert_eq(AmbienceMix.choose(list, {7: 29}, ""), "a")


func test_fade_reaches_target_in_fade_time_and_stops_there() -> void:
	var w := 0.0
	for i in 10:
		w = AmbienceMix.approach(w, 1.0, 0.1, 2.0)
	assert_almost(w, 0.5, 0.001)
	for i in 30:
		w = AmbienceMix.approach(w, 1.0, 0.1, 2.0)
	assert_eq(w, 1.0)
	assert_eq(AmbienceMix.approach(0.02, 0.0, 0.5, 2.0), 0.0)


## Equal-power curve: full weight is the layer's own volume, half weight is -3 dB, zero is silent.
func test_fade_gain() -> void:
	assert_almost(AmbienceMix.fade_db(1.0), 0.0, 0.001)
	assert_almost(AmbienceMix.fade_db(0.5), -3.01, 0.05)
	assert_true(AmbienceMix.fade_db(0.0) <= -79.0)


func test_one_shot_delays_stay_in_their_interval() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ev := {"interval_s": [3.0, 10.0]}
	var lo := 99.0
	var hi := 0.0
	for i in 500:
		var d := AmbienceMix.next_delay(rng, ev)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	assert_true(lo >= 3.0 and hi <= 10.0, "%f..%f" % [lo, hi])
	assert_true(lo < 3.5 and hi > 9.5, "spread over the interval: %f..%f" % [lo, hi])


func test_one_shot_roll_varies_within_limits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ev := {"sounds": ["x", "y", "z"], "volume_db": -12.0, "volume_jitter_db": 4.0, "pan": 0.8, "pitch": 0.05}
	var seen := {}
	var pans := []
	for i in 300:
		var r := AmbienceMix.roll(rng, ev)
		seen[r["sound"]] = true
		assert_true(r["volume_db"] >= -16.0 and r["volume_db"] <= -8.0, str(r))
		assert_true(absf(r["pan"]) <= 0.8, str(r))
		assert_true(r["pitch"] >= 0.95 and r["pitch"] <= 1.05, str(r))
		pans.append(r["pan"])
	assert_eq(seen.size(), 3)
	assert_true(pans.min() < -0.5 and pans.max() > 0.5, "pans spread left and right")


## The same sound never plays twice in a row from one event (when it has several).
func test_one_shot_roll_avoids_immediate_repeat() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ev := {"sounds": ["x", "y"], "volume_db": 0.0, "volume_jitter_db": 0.0, "pan": 0.0, "pitch": 0.0}
	var last := ""
	for i in 50:
		var r := AmbienceMix.roll(rng, ev, last)
		assert_true(r["sound"] != last, "repeat at %d" % i)
		last = r["sound"]


## The sound director builds the Ambiance, Effets and UI buses under Master, once.
func test_buses_exist_under_master() -> void:
	var director: GDScript = load("res://client/sound_director.gd")
	assert_true(director != null and director.can_instantiate())
	director.ensure_buses()
	director.ensure_buses()
	for b in ["Ambiance", "Effets", "UI"]:
		var i := AudioServer.get_bus_index(b)
		assert_true(i > 0, b)
		assert_eq(AudioServer.get_bus_send(i), &"Master")
	var n := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "UI":
			n += 1
	assert_eq(n, 1)


## Beds loop by crossfading two plays of the file (the web's own sample loop restarts from the play
## offset after a gap): full volume until the last crossfade seconds, then equal-power hand-over.
func test_loop_crossfades_into_the_next_play() -> void:
	var x := 1.5
	assert_eq(CrossfadeLoop.gains(0.0, 20.0, 0.0, x), Vector2(1, 0))
	assert_eq(CrossfadeLoop.gains(20.0 - x - 0.01, 20.0, 0.0, x), Vector2(1, 0))
	var mid := CrossfadeLoop.gains(20.0 - x / 2.0, 20.0, 0.0, x)
	assert_almost(mid.x, sqrt(0.5), 0.001)
	assert_almost(mid.y, sqrt(0.5), 0.001)
	assert_true(CrossfadeLoop.gains(20.0, 20.0, 0.0, x).is_equal_approx(Vector2(0, 1)))
	for i in 31:
		var g := CrossfadeLoop.gains(20.0 - x + x * i / 30.0, 20.0, 0.0, x)
		assert_almost(g.x * g.x + g.y * g.y, 1.0, 0.001)


## The next play starts at the loop start when the hand-over begins, and runs with the current one; a
## late frame starts it further in.
func test_loop_next_position() -> void:
	assert_almost(CrossfadeLoop.next_position(18.5, 20.0, 0.0, 1.5), 0.0, 0.0001)
	assert_almost(CrossfadeLoop.next_position(20.0, 20.0, 0.0, 1.5), 1.5, 0.0001)
	assert_almost(CrossfadeLoop.next_position(20.3, 20.0, 0.0, 1.5), 1.8, 0.0001)
	# music looping back to 31.4 s with a short hand-over
	assert_almost(CrossfadeLoop.next_position(199.8, 200.0, 31.4, 0.2), 31.4, 0.0001)
	assert_almost(CrossfadeLoop.next_position(200.0, 200.0, 31.4, 0.2), 31.6, 0.0001)


## A loop shorter than two crossfades hands over during its second half at most.
func test_loop_short_file() -> void:
	assert_eq(CrossfadeLoop.gains(0.0, 2.0, 0.0, 1.5), Vector2(1, 0))
	assert_eq(CrossfadeLoop.gains(0.9, 2.0, 0.0, 1.5), Vector2(1, 0))
	assert_almost(CrossfadeLoop.gains(1.5, 2.0, 0.0, 1.5).length(), 1.0, 0.001)
	assert_true(CrossfadeLoop.gains(2.0, 2.0, 0.0, 1.5).is_equal_approx(Vector2(0, 1)))
	assert_eq(CrossfadeLoop.gains(10.9, 12.0, 10.0, 1.5), Vector2(1, 0))  # loop part is 2 s long


## Back from a pause longer than the loop (a hidden browser tab runs no frames), the next turn starts
## inside the loop, not past the end of the file.
func test_loop_resumes_inside_after_a_long_pause() -> void:
	for t in [20.0, 20.3, 45.0, 400.0, 12345.6]:
		var p := CrossfadeLoop.turn_position(t, 20.0, 0.0, 1.5)
		assert_true(p >= 0.0 and p < 20.0, "%f -> %f" % [t, p])
	assert_almost(CrossfadeLoop.turn_position(20.3, 20.0, 0.0, 1.5), 1.8, 0.0001, "a late frame is unchanged")
	var music := CrossfadeLoop.turn_position(5000.0, 200.0, 31.4, 0.2)
	assert_true(music >= 31.4 and music < 200.0, "music stays in its looped part: %f" % music)
