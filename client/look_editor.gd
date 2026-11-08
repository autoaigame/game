## Character editor: a turning 3D preview and, for each slot, arrows to change the part and a swatch for
## its colour (click: next colour, right click: previous). In the start menu and in game (key C, without
## the preview: the player's own character shows the look). Emits look_changed after every change.
class_name LookEditor
extends HBoxContainer

signal look_changed(look: Array)

const PREVIEW_SCALE := 2
const TURN_RAD_S := 0.9

var look: Array = []
## false in game, where the player's own character shows the look.
var with_preview := true
var _preview: Character3D
var _yaw := PI / 4.0
var _names := {}  ## slot id -> Label
var _swatches := {}  ## slot id -> Button showing the colour


## Text of a slot's row: the part's name, or a dash for an empty slot.
static func part_label(the_look: Array, slot_id: String) -> String:
	for e in the_look:
		var p := CharacterParts.part(e["id"])
		if p.get("slot", "") == slot_id:
			return p["name"]
	return UiText.LOOK_NONE


## Colour of a slot's part in the look, or transparent for an empty slot.
static func part_color(the_look: Array, slot_id: String) -> Color:
	for e in the_look:
		var p := CharacterParts.part(e["id"])
		if p.get("slot", "") == slot_id:
			return CharacterParts.base_colour(e["color"])
	return Color.TRANSPARENT


func _init(start_look: Array = [], preview := true) -> void:
	look = CharacterParts.normalize(start_look)
	with_preview = preview


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	if with_preview:
		_add_preview()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(rows)
	for s in CharacterParts.slots():
		rows.add_child(_row(s))
	_refresh()


func _add_preview() -> void:
	var frame := Control.new()
	var vs := Vector2(Character3D.VIEW_SIZE * PREVIEW_SCALE)
	frame.custom_minimum_size = vs
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_preview = Character3D.new()
	_preview.look = look
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview.position = Vector2(vs.x / 2.0, vs.y - Character3D.FOOT_PX * PREVIEW_SCALE)
	frame.add_child(_preview)


func _row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = s["name"]
	title.custom_minimum_size = Vector2(80, 0)
	title.theme_type_variation = "HintLabel"
	row.add_child(title)
	row.add_child(_arrow("<", func(): _change(CharacterParts.cycle_part(look, s["id"], -1))))
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(118, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	row.add_child(name_label)
	_names[s["id"]] = name_label
	row.add_child(_arrow(">", func(): _change(CharacterParts.cycle_part(look, s["id"], 1))))
	var sw := Button.new()
	sw.custom_minimum_size = Vector2(26, 22)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.focus_mode = Control.FOCUS_NONE
	sw.tooltip_text = UiText.LOOK_COLOUR
	sw.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_change(CharacterParts.cycle_color(look, s["id"], -1)))
	sw.pressed.connect(func(): _change(CharacterParts.cycle_color(look, s["id"], 1)))
	row.add_child(sw)
	_swatches[s["id"]] = sw
	return row


func _arrow(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(24, 24)
	for st in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(st, UiTheme.box("button_small_" + st, 2))
	b.add_theme_stylebox_override("pressed", UiTheme.box("button_small_pressed", 2, 2))
	b.add_theme_stylebox_override("hover_pressed", UiTheme.box("button_small_pressed", 2, 2))
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


## Shows another look (the one worn, when the in-game editor opens), without emitting.
func set_look(new_look: Array) -> void:
	if CharacterParts.validate(new_look) != "":
		return
	look = new_look.duplicate(true)
	if is_node_ready():
		_refresh()


func _change(new_look: Array) -> void:
	set_look(new_look)
	look_changed.emit(look)


func _refresh() -> void:
	for id in _names:
		_names[id].text = part_label(look, id)
		var c := part_color(look, id)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.border_color = Color8(0x2e, 0x28, 0x22) if c.a > 0.0 else Color(0, 0, 0, 0)
		sb.set_border_width_all(2)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			_swatches[id].add_theme_stylebox_override(st, sb)
		_swatches[id].disabled = c.a == 0.0
	if _preview != null:
		_preview.set_look(look)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _preview == null:
		return
	_yaw = wrapf(_yaw + TURN_RAD_S * delta, -PI, PI)
	_preview.face(_yaw)
	_preview.step(Vector2.ZERO, delta)  # idle breathing
