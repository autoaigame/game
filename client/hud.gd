## In-game HUD, shown once joined, in the menu's style (client/ui_theme.gd): the hunger bar in a
## framed box (bottom left) with a warning when starving and the key hints as key caps; the bag
## window (client/bag_view.gd: E opens and closes it, Escape closes it); short notices from the
## server on a parchment band (top centre), with the item's icon when there is one.
## Values come from the server (status, inventory, marks); the HUD only shows them.
extends CanvasLayer

const HUNGER_MAX := 100.0
const BAR_SIZE := Vector2(170, 14)
const FULL := Color8(0xb8, 0x8a, 0x4a)
const FULL_LIT := Color8(0xd0, 0xa4, 0x62)
const BAR_BACK := Color8(0x2c, 0x31, 0x24)
const BAR_RIM := Color8(0x1f, 0x22, 0x1a)
const NOTICE_S := 3.0
const BAG_MARGIN := 16.0
const BAG_W := 300.0

var client: Node  ## client/client.gd

var _bar: ProgressBar
var _starving: Label
var _bag: BagView
var _notice: PanelContainer
var _notice_icon: TextureRect
var _notice_label: Label
var _notice_left := 0.0
var _notice_shown := []  ## [key, args] of the notice shown, to build it again in a new language
var _my_pos: Variant = null  ## where I stand (last snapshot), or null before the first
var _fires: Array = []  ## positions of the fires the server sent
var _seen_labels := {}  ## physical key -> its label, for every key the player pressed
var _hint_caps := {}  ## physical key -> the Label of its key cap


func _ready() -> void:
	layer = 5
	visible = false
	_build()
	client.welcomed.connect(func(_cell: Vector2i): visible = true)
	client.status_received.connect(_on_status)
	client.inventory_received.connect(func(items: Dictionary): _bag.set_items(items))
	client.notice_received.connect(_on_notice)
	client.snapshot_received.connect(_on_snapshot)
	client.marks_received.connect(_on_marks)


func hunger_bar() -> ProgressBar:
	return _bar


func starving_label() -> Label:
	return _starving


func bag() -> BagView:
	return _bag


func notice_label() -> Label:
	return _notice_label


func notice_icon() -> TextureRect:
	return _notice_icon


func toggle_bag() -> void:
	_bag.visible = not _bag.visible


## The letter shown on the key cap of a hinted physical key.
func key_hint(physical: Key) -> String:
	return _hint_caps[physical].text


## Learns the layout from every key press (the browser cannot tell it), and renames the hints.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var label: Key = event.key_label if event.key_label != KEY_NONE else event.keycode
	if label == KEY_NONE or _seen_labels.get(event.physical_keycode) == label:
		return
	_seen_labels[event.physical_keycode] = label
	for k in _hint_caps:
		_hint_caps[k].text = UiText.key_name(k, _seen_labels)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_E:
			toggle_bag()
		KEY_Q:
			client.request_whistle()
		KEY_ESCAPE:
			if not _bag.visible:
				return
			_bag.visible = false
		_:
			return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_age_notice(delta)


func _age_notice(dt: float) -> void:
	if _notice_left <= 0.0:
		return
	_notice_left -= dt
	_notice.modulate.a = clampf(_notice_left, 0.0, 1.0)
	_notice.visible = _notice_left > 0.0
	_notice_label.visible = _notice.visible


func _on_notice(key: String, args: Dictionary) -> void:
	var text := UiText.notice(key, args)
	if text == "":
		return
	_notice_label.text = text
	_notice_shown = [key, args]
	var item := String(args.get("item", ""))
	_notice_icon.visible = item != "" and not ItemData.item(item).is_empty()
	_notice_icon.texture = BagView.icon_of(item) if _notice_icon.visible else null
	_notice.visible = true
	_notice_label.visible = true
	_notice.modulate.a = 1.0
	_notice_left = NOTICE_S


## The notice is built in the current language: it is built again in a new one. The other texts are
## keys that their Label translates by itself.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _notice_shown.is_empty():
		_notice_label.text = UiText.notice(_notice_shown[0], _notice_shown[1])


func _on_snapshot(players: Array) -> void:
	for p in players:
		if p["id"] == client.my_peer_id:
			_my_pos = p["pos"]
	_update_fire()


func _on_marks(marks: Array) -> void:
	_fires = []
	for m in marks:
		if m["kind"] == "fire":
			_fires.append(m["pos"])
	_update_fire()


## Tells the bag whether a fire is within Protocol.COOK_REACH (the server checks the same).
func _update_fire() -> void:
	var near := false
	if _my_pos != null:
		for f in _fires:
			if (_my_pos as Vector2).distance_to(f) <= Protocol.COOK_REACH:
				near = true
	_bag.set_near_fire(near)


func _on_status(status: Dictionary) -> void:
	if not status.has("hunger"):
		return
	_bar.value = float(status["hunger"])
	_starving.visible = _bar.value <= 0.0


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)

	var corner := VBoxContainer.new()
	corner.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	corner.offset_left = 16
	corner.offset_bottom = -16
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", 6)
	root.add_child(corner)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiTheme.box("panel", 0))
	corner.add_child(frame)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	frame.add_child(line)
	var icon := TextureRect.new()
	icon.texture = UiTheme.icon("hunger")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	line.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(col)
	var label := Label.new()
	label.text = UiText.HUNGER
	label.add_theme_font_size_override("font_size", 14)
	col.add_child(label)
	_bar = ProgressBar.new()
	_bar.max_value = HUNGER_MAX
	_bar.value = HUNGER_MAX
	_bar.show_percentage = false
	_bar.custom_minimum_size = BAR_SIZE
	_bar.add_theme_stylebox_override("fill", _bar_box(FULL, FULL_LIT))
	_bar.add_theme_stylebox_override("background", _bar_box(BAR_BACK, BAR_RIM))
	col.add_child(_bar)
	_starving = Label.new()
	_starving.text = UiText.STARVING
	_starving.visible = false
	_starving.add_theme_font_size_override("font_size", 14)
	_starving.add_theme_color_override("font_color", Color8(0xd9, 0x8a, 0x6a))
	col.add_child(_starving)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_child(keys)
	for k in UiText.KEYS:
		var cap := _key_cap(UiText.key_name(k[0]))
		_hint_caps[k[0]] = cap.get_child(0)
		keys.add_child(cap)
		var what := Label.new()
		what.text = k[1]
		what.add_theme_font_size_override("font_size", 14)
		what.add_theme_constant_override("outline_size", 4)
		what.add_theme_color_override("font_outline_color", UiTheme.TEXT_DARK)
		keys.add_child(what)

	_bag = BagView.new()
	_bag.anchor_left = 1.0
	_bag.anchor_right = 1.0
	_bag.anchor_top = 0.5
	_bag.anchor_bottom = 0.5
	_bag.offset_right = -BAG_MARGIN
	_bag.offset_left = -BAG_MARGIN - BAG_W
	_bag.offset_top = -230.0
	_bag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bag.grow_vertical = Control.GROW_DIRECTION_END
	_bag.custom_minimum_size = Vector2(BAG_W, 0)
	_bag.visible = false
	_bag.eat.connect(func(id): client.request_eat(id))
	_bag.cook.connect(func(id): client.request_cook(id))
	_bag.build_fire.connect(func(): client.request_build_fire())
	root.add_child(_bag)

	_notice = PanelContainer.new()
	_notice.theme_type_variation = "TitleBand"
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.offset_top = 20
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.custom_minimum_size = Vector2(0, UiTheme.TITLE_BAND_H)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	root.add_child(_notice)
	var notice_line := HBoxContainer.new()
	notice_line.add_theme_constant_override("separation", 6)
	notice_line.alignment = BoxContainer.ALIGNMENT_CENTER
	_notice.add_child(notice_line)
	_notice_icon = TextureRect.new()
	_notice_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_notice_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_notice_icon.custom_minimum_size = Vector2(32, 32)
	_notice_icon.visible = false
	notice_line.add_child(_notice_icon)
	_notice_label = Label.new()
	_notice_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # built by UiText.notice
	_notice_label.add_theme_color_override("font_color", UiTheme.TEXT_LIGHT)  # on the title band, outlined
	_notice_label.add_theme_constant_override("outline_size", 4)
	_notice_label.add_theme_color_override("font_outline_color", UiTheme.TEXT_DARK)
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_line.add_child(_notice_label)


## A key cap: the key's letter on a small parchment square (the name field's box).
func _key_cap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := UiTheme.box("field_normal", 0)
	b.content_margin_left = 7
	b.content_margin_right = 7
	b.content_margin_top = 1
	b.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", b)
	var l := Label.new()
	l.text = key
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiTheme.TEXT_DARK)
	cap.add_child(l)
	return cap


## A bar part: `c` inside a 1 px `rim`.
static func _bar_box(c: Color, rim: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = rim
	s.set_border_width_all(1)
	s.border_width_bottom = 2
	return s
