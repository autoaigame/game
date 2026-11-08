extends TestCase

const Menu := preload("res://client/settings_menu.gd")
const LookPanel := preload("res://client/look_panel.gd")


## These tests check French words: the UI is shown in French whatever the system's language.
func _init() -> void:
	I18n.use("fr")


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
## Tabs are data: sound first, then display, language and controls, each with a title and a builder.

## Tabs are data: sound first, then display and controls, each with a title and a builder.
func test_tabs_have_an_id_and_a_title() -> void:
	var ids := []
	for t in Menu.TABS:
		ids.append(t["id"])
		assert_true(t["title"] != "", t["id"])
	assert_eq(ids, ["sound", "display", "language", "controls"])
	assert_eq(UiText.t(UiText.TAB_DISPLAY), "Affichage")
	assert_eq(UiText.t(UiText.TAB_CONTROLS), "Commandes")
	var menu := _built()
	for t in Menu.TABS:
		assert_true(menu.has_method("_build_%s_tab" % t["id"]), t["id"])
		assert_true(menu._tab_pages.has(t["id"]), t["id"])
	menu.free()


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


func _built() -> CanvasLayer:
	var menu: CanvasLayer = Menu.new()
	menu.settings_path = PATH
	menu._build()
	return menu


const PATH := "user://test_settings_menu.cfg"


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Ticking Plein écran asks for it and remembers the choice; unticking goes back to a window.
func test_fullscreen_box_is_remembered() -> void:
	_clean()
	var menu := _built()
	var box: CheckBox = menu.fullscreen_box()
	assert_eq(box.text, UiText.FULLSCREEN)
	box.button_pressed = true
	assert_eq(ClientSettings.load_fullscreen(PATH), true)
	box.button_pressed = false
	assert_eq(ClientSettings.load_fullscreen(PATH), false)
	menu.free()
	_clean()


## The display tab holds the fullscreen box and nothing else to set.
func test_display_tab_has_only_the_fullscreen_box() -> void:
	var menu := _built()
	var page: Control = menu._tab_pages["display"]
	var controls := page.find_children("*", "BaseButton", true, false)
	controls.append_array(page.find_children("*", "Range", true, false))
	assert_eq(controls, [menu.fullscreen_box()])
	menu.free()


func _press(physical: Key, label: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	e.keycode = label
	e.key_label = label
	e.pressed = true
	return e


func _caps_of(row: Dictionary, seen := {}) -> Array:
	var out := []
	for c in row["caps"]:
		out.append(UiText.cap_text(c, seen))
	return out


func _row(action: String) -> Dictionary:
	for r in UiText.controls():
		if r["action"] == action:
			return r
	return {}


## The controls list takes the HUD's key hints as they are (one list for both), and adds the others.
func test_controls_reuse_the_hud_hints() -> void:
	for k in UiText.KEYS:
		assert_eq(_row(k[1])["caps"], [k[0]], k[1])
	for action in [UiText.CONTROL_MOVE, UiText.CONTROL_SPRINT, UiText.CONTROL_CLICK, UiText.CONTROL_LOOK, UiText.CONTROL_MUTE,
			UiText.CONTROL_VOLUME, UiText.CONTROL_ZOOM, UiText.CONTROL_SETTINGS]:
		assert_false(_row(action).is_empty(), action)


## The listed keys are the ones the game reacts to.
func test_listed_keys_are_the_handled_keys() -> void:
	var look: Key = _row(UiText.CONTROL_LOOK)["caps"][0]
	assert_true(LookPanel.is_toggle(_key(look)))
	var esc: Key = _row(UiText.CONTROL_SETTINGS)["caps"][0]
	assert_true(Menu.is_toggle(_key(esc)))
	assert_eq(_row(UiText.CONTROL_MOVE)["caps"], [KEY_W, KEY_A, KEY_S, KEY_D])
	assert_eq(_row(UiText.CONTROL_MUTE)["caps"], [KEY_M])
	assert_eq(_row(UiText.CONTROL_VOLUME)["caps"], [KEY_MINUS, KEY_EQUAL])


## Shift held makes the player run (client/world_view.gd); its cap reads "Maj", as on a French keyboard.
func test_sprint_key_is_listed() -> void:
	assert_eq(_row(UiText.CONTROL_SPRINT)["caps"], [KEY_SHIFT])
	assert_eq(UiText.cap_text(KEY_SHIFT), "Maj")
	assert_eq(UiText.cap_text(KEY_SHIFT, {KEY_SHIFT: KEY_SHIFT}), "Maj")


## Keys are named as printed on the player's keyboard: Z Q S D on AZERTY, W A S D on QWERTY.
func test_caps_follow_the_layout() -> void:
	var move := _row(UiText.CONTROL_MOVE)
	assert_eq(_caps_of(move, {KEY_W: KEY_W}), ["W", "A", "S", "D"])
	assert_eq(_caps_of(move, {KEY_W: KEY_Z}), ["Z", "Q", "S", "D"])
	assert_eq(_caps_of(_row(UiText.KEYS[1][1]), {KEY_W: KEY_Z}), ["A"])
	assert_eq(UiText.cap_text(KEY_ESCAPE), "Échap")
	assert_eq(UiText.cap_text(KEY_MINUS, {KEY_MINUS: KEY_PARENRIGHT}), ")")
	assert_eq(UiText.cap_text(KEY_EQUAL, {KEY_EQUAL: KEY_EQUAL}), "=")
	assert_eq(UiText.cap_text(UiText.MOUSE_WHEEL), "Molette")


func _page_texts(menu: CanvasLayer) -> Array:
	var out := []
	for l in menu._tab_pages["controls"].find_children("*", "Label", true, false):
		out.append(l.text)
	return out


## The controls tab shows one line per control, and renames its keys once a key press shows the layout.
func test_controls_tab_learns_the_layout() -> void:
	var menu := _built()
	var texts := _page_texts(menu)
	for r in UiText.controls():
		assert_true(r["action"] in texts, r["action"])
	assert_true("W" in texts and not "Z" in texts)
	menu._input(_press(KEY_W, KEY_Z))
	texts = _page_texts(menu)
	assert_true("Z" in texts and not "W" in texts)
	menu.free()


## At launch the menu goes fullscreen as saved, on desktop only.
func test_menu_restores_fullscreen_at_launch() -> void:
	_clean()
	var menu := _built()
	assert_false(menu.restore_fullscreen(false))
	ClientSettings.save_fullscreen(true, PATH)
	assert_true(menu.restore_fullscreen(false))
	assert_false(menu.restore_fullscreen(true))
	menu.free()
	_clean()
