## The start menu's Crédits screen: how the game is made, then who made its assets, read from
## ASSETS.toml (client/credits.gd) when the screen first shows. The text scrolls in a ScrollContainer that takes the
## focus: up and down (keys, a pad's d-pad or stick) scroll it, and past the bottom go to Retour.
## Retour, Escape and a pad's B go back (client/login_ui.gd).
extends PanelContainer

signal back_pressed

const Credits := preload("res://client/credits.gd")
const LEAVE := -1  ## scroll_step(): the text is at its end, the focus moves on
const STEP := 40  ## pixels scrolled by one press of up or down
const VIEW_SIZE := Vector2(540, 284)
const FRAME_PAD := 4  ## room for the focus frame around the text

var sounds: Node  ## client/sound_director.gd, or null (no sound)
var source := Credits.SOURCE  ## the ASSETS.toml read when the screen first shows without data
var _scroll := ScrollContainer.new()
var _body := VBoxContainer.new()
var _back := Button.new()
var _data: Variant = null  ## what the text shows (lines()), kept to build it again in a new language


## The lines of the screen for `data` (client/credits.gd build()), top to bottom: {text, style},
## style "heading", "name" or "", in the current language. Empty `data` (ASSETS.toml missing or
## unreadable) gives a short line.
static func lines(data: Dictionary) -> Array:
	var out := [{"text": UiText.t(UiText.CREDITS_COMMUNITY), "style": ""}]
	if data.is_empty():
		out.append({"text": UiText.t(UiText.CREDITS_MISSING), "style": ""})
		return out
	out.append({"text": UiText.t(UiText.CREDITS_PEOPLE), "style": "heading"})
	for e in data.get("people", []):
		out.append_array(_entry_lines(e))
	if not data.get("third_party", []).is_empty():
		out.append({"text": UiText.t(UiText.CREDITS_THIRD_PARTY), "style": "heading"})
		for e in data["third_party"]:
			out.append_array(_entry_lines(e))
	if not data.get("tools", []).is_empty():
		out.append({"text": UiText.t(UiText.CREDITS_TOOLS), "style": "heading"})
		out.append({"text": ", ".join(data["tools"]), "style": ""})
	return out


## The words for `id` in the current language (`keys`: id -> text key), or the id itself when unknown.
static func _words(keys: Dictionary, id: String) -> String:
	return UiText.t(keys[id]) if keys.has(id) else id


## Where up (`dir` -1) or down (+1) takes the text scrolled to `value` of `max_scroll`: `step` further,
## kept within the text, or LEAVE going down from its end.
static func scroll_step(value: int, max_scroll: int, step: int, dir: int) -> int:
	if dir > 0 and value >= max_scroll:
		return LEAVE
	return clampi(value + dir * step, 0, maxi(max_scroll, 0))


## Whether down at the end of the text leaves it: a new press of a key or button does; a held key
## (echo) or the stick, which sends no echo while held, stops there (Tab or the d-pad go on).
static func leaves(event: InputEvent) -> bool:
	return not event.is_echo() and not event is InputEventJoypadMotion


static func _entry_lines(e: Dictionary) -> Array:
	var kinds := []
	for k in e.get("kinds", {}):
		kinds.append("%s (%d)" % [_words(UiText.CREDITS_KINDS, k), int(e["kinds"][k])])
	var files := int(e.get("files", 0))
	var licenses := []
	for l in e.get("licenses", []):
		licenses.append(_words(UiText.CREDITS_LICENSES, l))
	var out := [{"text": String(e.get("name", "?")), "style": "name"},
			{"text": UiText.tn(UiText.CREDITS_FILES, files).format({"count": files, "kinds": ", ".join(kinds)}),
					"style": ""},
			{"text": UiText.tn(UiText.CREDITS_LICENSE, licenses.size()) % "; ".join(licenses), "style": ""}]
	for s in e.get("sources", []):
		out.append({"text": UiText.t(UiText.CREDITS_SOURCE) % s, "style": ""})
	return out


func _init(data: Variant = null) -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = UiText.CREDITS
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_scroll.custom_minimum_size = VIEW_SIZE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_ALL
	# the kit's focus frame around the text while it has the focus (ScrollContainer draws none here)
	var holder := PanelContainer.new()
	var focused := UiTheme.box("focus", 0)
	var unfocused := StyleBoxEmpty.new()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		focused.set_content_margin(side, FRAME_PAD)
		unfocused.set_content_margin(side, FRAME_PAD)
	holder.add_theme_stylebox_override("panel", unfocused)
	_scroll.focus_entered.connect(func(): holder.add_theme_stylebox_override("panel", focused))
	_scroll.focus_exited.connect(func(): holder.add_theme_stylebox_override("panel", unfocused))
	_scroll.gui_input.connect(func(event: InputEvent): if scroll_input(event): _scroll.accept_event())
	holder.add_child(_scroll)
	box.add_child(holder)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	_scroll.add_child(_body)
	if data == null:  # read when the screen first shows
		visibility_changed.connect(_on_visibility_changed)
	else:
		_fill(data)

	var hint := Label.new()
	hint.text = UiText.CREDITS_HINT
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_back.text = UiText.BACK
	_back.custom_minimum_size = Vector2(0, 36)
	_back.theme_type_variation = "TabButton"
	_back.pressed.connect(func(): back_pressed.emit())
	_back.mouse_entered.connect(func(): _play("hover"))
	_back.button_down.connect(func(): _play("click"))
	box.add_child(_back)
	# the text and Retour, both ways round
	var to_back := _scroll.get_path_to(_back)
	var to_scroll := _back.get_path_to(_scroll)
	for side in ["focus_next", "focus_previous", "focus_neighbor_bottom", "focus_neighbor_top"]:
		_scroll.set(side, to_back)
		_back.set(side, to_scroll)


func first_focus() -> Control:
	return _scroll


func scroll() -> ScrollContainer:
	return _scroll


func back_button() -> Button:
	return _back


## Every line of the text, for tests.
func body_text() -> String:
	var parts := []
	for c in _body.get_children():
		parts.append((c as Label).text)
	return "\n".join(parts)


## Up, down, page up and page down on the focused text; true when used. Down pressed again at the
## end of the text gives the focus to Retour (held down, it stays on the text).
func scroll_input(event: InputEvent) -> bool:
	var dir := 0
	var step := STEP
	var bar := _scroll.get_v_scroll_bar()
	if event.is_action_pressed("ui_down", true):
		dir = 1
	elif event.is_action_pressed("ui_up", true):
		dir = -1
	elif event.is_action_pressed("ui_page_down", true):
		dir = 1
		step = int(bar.page)
	elif event.is_action_pressed("ui_page_up", true):
		dir = -1
		step = int(bar.page)
	if dir == 0:
		return false
	var to := scroll_step(_scroll.scroll_vertical, int(bar.max_value - bar.page), step, dir)
	if to == LEAVE:
		if leaves(event):
			_back.grab_focus()
	else:
		_scroll.scroll_vertical = to
	return true


func _on_visibility_changed() -> void:
	if visible and _body.get_child_count() == 0:
		_fill(Credits.load_from(source))


func _fill(data: Dictionary) -> void:
	_data = data
	for c in _body.get_children():
		c.free()
	for l in lines(data):
		_body.add_child(_line(l))


## The text is built in the current language: it is built again in a new one.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _data != null:
		_fill(_data)


func _line(l: Dictionary) -> Label:
	var label := Label.new()
	label.text = l["text"]
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated already; names, links
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match l["style"]:
		"heading":
			label.add_theme_font_size_override("font_size", UiTheme.BUTTON_SIZE)
			label.add_theme_color_override("font_color", Color8(0xe0, 0xa8, 0x45))  # the kit's light amber
			label.add_theme_constant_override("outline_size", 4)
			label.add_theme_color_override("font_outline_color", UiTheme.TEXT_DARK)
		"name":
			label.add_theme_constant_override("outline_size", 4)
			label.add_theme_color_override("font_outline_color", UiTheme.TEXT_DARK)
		_:
			label.theme_type_variation = "HintLabel"
	return label


func _play(kind: String) -> void:
	if sounds != null:
		sounds.ui(kind)
