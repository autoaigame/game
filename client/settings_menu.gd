## Settings menu over the world or the start menu, opened and closed with Escape (or a pad's Start).
## While a HUD window is open (big map, bag), Escape closes that window instead.
## The world keeps running (multiplayer): only my keys stop moving me while it is open (world_view.gd).
## One tab per entry of TABS; only the sound tab exists for now. Texts in client/ui_text.gd.
extends CanvasLayer

signal opened
signal closed

## id -> title; a tab is built by _build_<id>_tab(). Later: "controls", "display".
const TABS := [{"id": "sound", "title": UiText.TAB_SOUND}]
const FADE_S := 0.15
## The Interface slider plays a menu sound at most this often while it moves, in ms.
const UI_PREVIEW_MS := 150

var sounds: Node  ## client/sound_director.gd, or null (no sound)
var windows: Node  ## client/hud.gd, or null: Escape first closes its open window (big map, bag)
var _root := Control.new()
var _tab_buttons := {}  ## tab id -> Button
var _tab_pages := {}  ## tab id -> Control
var _sliders := {}  ## channel -> HSlider
var _values := {}  ## channel -> Label
var _mute := CheckBox.new()
var _close := Button.new()
var _tween: Tween
var _ui_preview_at := 0
var _focus_next: Control = null


## Escape or a pad's Start, pressed (not a repeat).
static func is_toggle(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_START
	return false


## [{channel, label}] of the sound tab, one slider each, in the channel order.
static func sound_rows() -> Array:
	var rows := []
	for c in AudioSettings.CHANNELS:
		rows.append({"channel": c, "label": AudioSettings.label(c)})
	return rows


static func value_text(level: float) -> String:
	return "%d %%" % AudioSettings.to_percent(level)


func _ready() -> void:
	layer = 15
	_build()
	visible = false
	if sounds != null:
		sounds.settings_changed.connect(_show_settings)


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_show_settings(sounds.settings() if sounds != null else AudioSettings.defaults())
	_select_tab(TABS[0]["id"])
	_root.modulate.a = 0.0
	_fade_to(1.0)
	_focus_next = _sliders[AudioSettings.CHANNELS[0]]
	opened.emit()


func close() -> void:
	if not visible:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and _root.is_ancestor_of(f):
		f.release_focus()
	if _tween != null:
		_tween.kill()
	visible = false  # at once: the keys move me again on this frame
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if not visible and is_toggle(event) and windows != null and windows.close_window():
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	if is_toggle(event) or (visible and event.is_action_pressed("ui_cancel")):
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _focus_next != null:
		_focus_next.grab_focus()
		_focus_next = null


func _build() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks and the wheel do not reach the world
	_root.theme = UiTheme.build()
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var band := PanelContainer.new()
	band.theme_type_variation = "TitleBand"
	band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	band.custom_minimum_size = Vector2(260, UiTheme.TITLE_BAND_H)
	column.add_child(band)
	var title := _label(UiText.SETTINGS_TITLE, "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.text = t["title"]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.custom_minimum_size = Vector2(110, 34)
		var id: String = t["id"]
		b.pressed.connect(func(): _select_tab(id))
		_with_sounds(b)
		tabs.add_child(b)
		_tab_buttons[id] = b
		var page: Control = call("_build_%s_tab" % id)
		box.add_child(page)
		_tab_pages[id] = page

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	box.add_child(footer)
	var hint := _label(UiText.SETTINGS_HINT, "HintLabel")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)
	_close.text = UiText.CLOSE
	_close.custom_minimum_size = Vector2(140, 40)
	_close.pressed.connect(close)
	_with_sounds(_close)
	footer.add_child(_close)


func _build_sound_tab() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	page.add_child(grid)
	for row in sound_rows():
		var channel: String = row["channel"]
		var name_label := _label(row["label"], "")
		name_label.custom_minimum_size = Vector2(100, 0)
		grid.add_child(name_label)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 1
		s.custom_minimum_size = Vector2(240, 24)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(func(v: float): _on_slider(channel, v))
		grid.add_child(s)
		_sliders[channel] = s
		var value := _label("", "")
		value.custom_minimum_size = Vector2(56, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_values[channel] = value
	_mute.text = UiText.MUTE
	_mute.toggled.connect(func(on: bool): if sounds != null: sounds.set_muted(on))
	_with_sounds(_mute)
	page.add_child(_mute)
	return page


func _on_slider(channel: String, percent: float) -> void:
	var level := AudioSettings.from_percent(percent)
	_values[channel].text = value_text(level)
	if sounds == null:
		return
	sounds.set_level(channel, level)
	if channel == "ui" and Time.get_ticks_msec() - _ui_preview_at >= UI_PREVIEW_MS:
		_ui_preview_at = Time.get_ticks_msec()
		sounds.ui("hover")


## Shows `s` without sending it back (N, - and + while the menu is open move the controls too).
func _show_settings(s: Dictionary) -> void:
	for c in AudioSettings.CHANNELS:
		_sliders[c].set_value_no_signal(AudioSettings.to_percent(s[c]))
		_values[c].text = value_text(s[c])
	_mute.set_pressed_no_signal(s["muted"])


func _select_tab(id: String) -> void:
	for t in _tab_pages:
		_tab_pages[t].visible = t == id
		_tab_buttons[t].set_pressed_no_signal(t == id)


func _with_sounds(b: BaseButton) -> void:
	b.mouse_entered.connect(func(): _play("hover"))
	b.focus_entered.connect(func(): if visible and _root.modulate.a > 0.5: _play("hover"))
	b.button_down.connect(func(): _play("click"))


func _play(kind: String) -> void:
	if sounds != null:
		sounds.ui(kind)


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _fade_to(alpha: float) -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", alpha, FADE_S)
	return _tween
