extends TestCase

const Menu := preload("res://client/settings_menu.gd")


func _key(code: Key, pressed := true, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


## Escape and a pad's Start open and close the menu; nothing else does, nor a release or a repeat.
func test_toggle_keys() -> void:
	assert_true(Menu.is_toggle(_key(KEY_ESCAPE)))
	assert_false(Menu.is_toggle(_key(KEY_ESCAPE, false)))
	assert_false(Menu.is_toggle(_key(KEY_ESCAPE, true, true)))
	assert_false(Menu.is_toggle(_key(KEY_P)))
	assert_false(Menu.is_toggle(_key(KEY_M)))
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_START
	pad.pressed = true
	assert_true(Menu.is_toggle(pad))
	pad.button_index = JOY_BUTTON_A
	assert_false(Menu.is_toggle(pad))


## Tabs are data: the sound tab now, others (controls, display) are added to the list later.
func test_tabs_have_an_id_and_a_title() -> void:
	assert_true(Menu.TABS.size() >= 1)
	assert_eq(Menu.TABS[0]["id"], "sound")
	for t in Menu.TABS:
		assert_true(t["title"] != "", t["id"])


## One slider row per channel, in the channel order, with its label.
func test_sound_rows_follow_the_channels() -> void:
	var rows: Array = Menu.sound_rows()
	assert_eq(rows.size(), AudioSettings.CHANNELS.size())
	for i in rows.size():
		assert_eq(rows[i]["channel"], AudioSettings.CHANNELS[i])
		assert_eq(rows[i]["label"], AudioSettings.label(AudioSettings.CHANNELS[i]))


func test_value_text_is_a_percent() -> void:
	assert_eq(Menu.value_text(0.8), "80 %")
	assert_eq(Menu.value_text(0.0), "0 %")
	assert_eq(Menu.value_text(1.0), "100 %")
