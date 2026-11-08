## Character editor: a turning 3D preview and, for each slot, arrows to change the part and a swatch for
## its colour (click: next colour, right click: previous). In the start menu and in game (key C, without
## the preview: the player's own character shows the look). Emits look_changed after every change.
## In the start menu it also has a Chien row, to choose the dog (DogSkins), with a preview of the dog
## trotting; it emits dog_changed.
class_name LookEditor
extends HBoxContainer

signal look_changed(look: Array)
signal dog_changed(dog: String)

const PREVIEW_SCALE := 2
const TURN_RAD_S := 0.9
const DOG_TEX := preload("res://assets/dog.png")
## The dog preview: its frame (px), where its feet stand in it, and how fast it trots in place (cells/s,
## the speed of a dog sniffing round its owner, server/dog.gd).
const DOG_FRAME := Vector2(176, 84)
const DOG_FOOT_Y := 72.0
const DOG_TROT_CELLS_S := 2.0
## Seen from the side, facing right: the way the dog sprite is drawn.
const DOG_DIR := Vector2(1, -1)

var look: Array = []
## false in game, where the player's own character shows the look.
var with_preview := true
var _preview: Character3D
var _previews: VBoxContainer  ## the left column: the character, then the dog
var _yaw := PI / 4.0
var _names := {}  ## slot id -> Label
var _swatches := {}  ## slot id -> Button showing the colour
var dog := DogSkins.DEFAULT
var with_dog := false  ## the Chien row (start menu only)
var _dog_name: Label
var _dog_frame: Control
var _dog_preview: Node2D  ## Sprite2D for the drawn dog, Dog3D for the others
var _dog_walked := 0.0  ## cells walked in place, for the sprite's walk frames


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


## The name of a dog (DogSkins id) in the Chien row: a text key, translated by the Label.
static func dog_label(id: String) -> String:
	return UiText.DOG_NAMES[DogSkins.valid(id)]


func _init(start_look: Array = [], preview := true, dog_row := false, start_dog := DogSkins.DEFAULT) -> void:
	look = CharacterParts.normalize(start_look)
	with_preview = preview
	with_dog = dog_row
	dog = DogSkins.valid(start_dog)


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	if with_preview:
		_previews = VBoxContainer.new()
		_previews.add_theme_constant_override("separation", 0)
		add_child(_previews)
		_add_preview()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(rows)
	for s in CharacterParts.slots():
		rows.add_child(_row(s))
	if with_dog:
		_add_dog_row(rows)
	_refresh()


func _add_preview() -> void:
	var frame := Control.new()
	var vs := Vector2(Character3D.VIEW_SIZE * PREVIEW_SCALE)
	frame.custom_minimum_size = vs
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_previews.add_child(frame)
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


func _add_dog_row(rows: VBoxContainer) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	rows.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = UiText.LOOK_DOG
	title.custom_minimum_size = Vector2(80, 0)
	title.theme_type_variation = "HintLabel"
	row.add_child(title)
	row.add_child(_arrow("<", func(): _change_dog(DogSkins.cycle(dog, -1))))
	_dog_name = Label.new()
	_dog_name.custom_minimum_size = Vector2(118, 0)
	_dog_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dog_name.clip_text = true
	row.add_child(_dog_name)
	row.add_child(_arrow(">", func(): _change_dog(DogSkins.cycle(dog, 1))))
	rows.add_child(row)
	if not with_preview:
		return
	_dog_frame = Control.new()
	_dog_frame.custom_minimum_size = DOG_FRAME
	_dog_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dog_frame.clip_contents = true
	_dog_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_previews.add_child(_dog_frame)


## The dog preview for the current dog, in place of the one shown.
func _show_dog() -> void:
	if _dog_frame == null:
		return
	if _dog_preview != null:
		_dog_frame.remove_child(_dog_preview)
		_dog_preview.queue_free()
		_dog_preview = null
	var index := Dog3D.skin_index(dog)
	if index < 0:
		var sprite := Sprite2D.new()
		sprite.texture = DOG_TEX
		sprite.hframes = DogAnim.COLUMNS
		sprite.vframes = DogAnim.ROWS.size()
		sprite.centered = false
		sprite.offset = DogAnim.sprite_offset()
		_dog_preview = sprite
	else:
		var model := Dog3D.new(index)
		model.show_silhouette(false)
		_dog_preview = model
	_dog_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_dog_preview.position = Vector2(DOG_FRAME.x / 2.0, DOG_FOOT_Y)
	_dog_frame.add_child(_dog_preview)
	if _dog_preview is Dog3D:
		(_dog_preview as Dog3D).face(Model3D.yaw_of(DOG_DIR))


## Shows another dog, without emitting.
func set_dog(id: String) -> void:
	var valid := DogSkins.valid(id)
	if valid == dog and _dog_preview != null:
		return
	dog = valid
	_refresh_dog()  # nothing to refresh before _ready built the row


func _change_dog(id: String) -> void:
	set_dog(id)
	dog_changed.emit(dog)


func _refresh_dog() -> void:
	if _dog_name != null:
		_dog_name.text = dog_label(dog)
	_show_dog()


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
	_refresh_dog()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_trot_dog(delta)
	if _preview == null:
		return
	_yaw = wrapf(_yaw + TURN_RAD_S * delta, -PI, PI)
	_preview.face(_yaw)
	_preview.step(Vector2.ZERO, delta)  # idle breathing


## The dog preview trots in place, side on: the 3D dogs' paws keep the pace of that speed.
func _trot_dog(delta: float) -> void:
	if _dog_preview == null or delta <= 0.0:
		return
	var cells := DOG_TROT_CELLS_S * delta
	_dog_walked += cells
	if _dog_preview is Dog3D:
		(_dog_preview as Dog3D).step(DOG_DIR.normalized() * cells, delta, "follow")
	else:
		(_dog_preview as Sprite2D).frame_coords = DogAnim.frame("follow", true, DOG_TROT_CELLS_S, _dog_walked, 0.0)
