extends TestCase

const SoundDirector := "res://client/sound_director.gd"


func _music() -> Dictionary:
	return (load(SoundDirector) as GDScript).menu_music()


## data/sounds.json names the start menu's music; it plays on the Musique bus.
func test_menu_music_is_in_the_data() -> void:
	var m := _music()
	assert_true(ResourceLoader.exists(m["path"]), m["path"])
	assert_eq(m["bus"], "Musique")
	assert_true(m["fade_out_s"] > 0.0)


## The intro plays once, then 31.4 s to the end loops (Godot ignores the file's LOOPSTART tag).
func test_menu_music_loops_after_its_intro() -> void:
	var s: AudioStreamOggVorbis = load(_music()["path"])
	assert_true(s.loop, "loop")
	assert_almost(s.loop_offset, 31.4, 0.001)
	assert_true(s.get_length() > 150.0, "the whole track")


## The fade out goes from full to silent over fade_out_s, never louder than the start.
func test_fade_out_curve() -> void:
	var d: GDScript = load(SoundDirector)
	assert_almost(d.fade_out_db(0.0, 3.0), 0.0, 0.001)
	assert_almost(d.fade_out_db(3.0, 3.0), AudioSettings.SILENT_DB, 0.001)
	assert_almost(d.fade_out_db(9.0, 3.0), AudioSettings.SILENT_DB, 0.001)
	var prev := 1.0
	for i in 11:
		var db: float = d.fade_out_db(i * 0.3, 3.0)
		assert_true(db <= prev, "falls at %d" % i)
		prev = db


## Each turn of the loop after the first starts at the end of the intro, with a short hand-over (the
## file already crossfades its end into the loop point).
func test_music_loop_turns_start_after_the_intro() -> void:
	var m := _music()
	assert_almost(m["loop_begin"], 31.4, 0.001)
	assert_true(m["crossfade_s"] > 0.0 and m["crossfade_s"] <= 0.5)
	var length := 192.17
	var next := CrossfadeLoop.next_position(length - m["crossfade_s"], length, m["loop_begin"], m["crossfade_s"])
	assert_almost(next, 31.4, 0.001)


## On the web the music starts with the first press (the browser holds sound until then, and the loop
## times itself on the wall clock); a move or a release does not count.
func test_first_press_starts_the_music() -> void:
	var d: GDScript = load(SoundDirector)
	var click := InputEventMouseButton.new()
	click.pressed = true
	assert_true(d.is_gesture(click))
	click.pressed = false
	assert_false(d.is_gesture(click))
	var key := InputEventKey.new()
	key.pressed = true
	assert_true(d.is_gesture(key))
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	assert_true(d.is_gesture(touch))
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	assert_true(d.is_gesture(pad))
	assert_false(d.is_gesture(InputEventMouseMotion.new()))
