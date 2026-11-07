## In-game HUD, shown once joined: the hunger bar (bottom left), with a warning when starving; the
## bag (I opens and closes it); short notices from the server (top centre).
## Values come from the server (status message); the HUD only shows them.
extends CanvasLayer

const HUNGER_MAX := 100.0
const BAR_SIZE := Vector2(160, 14)
const FULL := Color8(0xb8, 0x8a, 0x4a)
const EMPTY := Color8(0x2e, 0x28, 0x22, 0xc0)
const NOTICE_S := 3.0
## The bag is BAG_W wide against the right edge (BAG_MARGIN from it) and grows to the left if it must;
## each item's buttons sit on their own line under its name, in BUTTON_FONT, so they always fit.
const BAG_W := 240.0
const BAG_MAX_W := 300.0
const BAG_MARGIN := 16.0
const BAG_PAD := 10.0
const BUTTON_FONT := 15
const BUTTON_PAD := 12.0  ## each side of a button's text (client/ui_theme.gd)
const BUTTON_GAP := 4.0

var client: Node  ## client/client.gd

var _bar: ProgressBar
var _starving: Label
var _bag: PanelContainer
var _bag_list: VBoxContainer
var _bag_empty: Label
var _fire: Button
var _notice: Label
var _notice_left := 0.0


func _ready() -> void:
	layer = 5
	visible = false
	_build()
	client.welcomed.connect(func(_cell: Vector2i): visible = true)
	client.status_received.connect(_on_status)
	client.inventory_received.connect(_on_inventory)
	client.notice_received.connect(_on_notice)


func hunger_bar() -> ProgressBar:
	return _bar


func starving_label() -> Label:
	return _starving


func bag() -> PanelContainer:
	return _bag


func bag_empty_label() -> Label:
	return _bag_empty


func notice_label() -> Label:
	return _notice


## The bag's rows as shown ("3 × Baies").
func bag_rows() -> Array:
	var out := []
	for row in _bag_list.get_children():
		if not row.is_queued_for_deletion():
			out.append((row.get_node("Name").get_child(1) as Label).text)
	return out


## The "eat" button of an item's row, or null.
func eat_button(item: String) -> Button:
	return _row_button(item, "Eat")


## The "cook" button of an item's row, or null.
func cook_button(item: String) -> Button:
	return _row_button(item, "Cook")


func _row_button(item: String, button: String) -> Button:
	for row in _bag_list.get_children():
		if row.get_meta("item", "") == item and not row.is_queued_for_deletion():
			return row.get_node_or_null("Actions/" + button)
	return null


func fire_button() -> Button:
	return _fire


func toggle_bag() -> void:
	_bag.visible = not _bag.visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_I:
			toggle_bag()
		KEY_H:
			client.request_whistle()
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


func _on_notice(key: String, args: Dictionary) -> void:
	var text := UiText.notice(key, args)
	if text == "":
		return
	_notice.text = text
	_notice.visible = true
	_notice.modulate.a = 1.0
	_notice_left = NOTICE_S


func _on_inventory(items: Dictionary) -> void:
	for row in _bag_list.get_children():
		_bag_list.remove_child(row)
		row.queue_free()
	var ids := items.keys()
	ids.sort()
	for id in ids:
		var it := ItemData.item(String(id))
		if it.is_empty():
			continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var line := HBoxContainer.new()
		line.name = "Name"
		var icon := ColorRect.new()
		icon.color = it["color"]
		icon.custom_minimum_size = Vector2(14, 14)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(icon)
		var label := Label.new()
		label.text = "%d × %s" % [int(items[id]), it["name"]]
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		row.add_child(line)
		var actions := HBoxContainer.new()
		actions.name = "Actions"
		actions.add_theme_constant_override("separation", int(BUTTON_GAP))
		var item_id := String(id)
		if it["food"] > 0:
			actions.add_child(_small_button("Eat", UiText.EAT, func(): client.request_eat(item_id)))
		if it["cooks_into"] != "":
			actions.add_child(_small_button("Cook", UiText.COOK, func(): client.request_cook(item_id)))
		if actions.get_child_count() > 0:
			row.add_child(actions)
		row.set_meta("item", item_id)
		_bag_list.add_child(row)
	_bag_empty.visible = _bag_list.get_child_count() == 0
	_fire.disabled = int(items.get("sticks", 0)) < Protocol.FIRE_STICKS


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
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(16, -64)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var label := Label.new()
	label.text = UiText.HUNGER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	box.add_child(label)
	_bar = ProgressBar.new()
	_bar.max_value = HUNGER_MAX
	_bar.value = HUNGER_MAX
	_bar.show_percentage = false
	_bar.custom_minimum_size = BAR_SIZE
	_bar.add_theme_stylebox_override("fill", _flat(FULL))
	_bar.add_theme_stylebox_override("background", _flat(EMPTY))
	box.add_child(_bar)
	_starving = Label.new()
	_starving.text = UiText.STARVING
	_starving.visible = false
	_starving.add_theme_color_override("font_color", Color8(0xd9, 0x8a, 0x6a))
	_starving.add_theme_color_override("font_outline_color", Color.BLACK)
	_starving.add_theme_constant_override("outline_size", 4)
	box.add_child(_starving)
	var keys := Label.new()
	keys.text = UiText.KEYS_HINT
	keys.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	keys.add_theme_color_override("font_outline_color", Color.BLACK)
	keys.add_theme_constant_override("outline_size", 4)
	box.add_child(keys)
	_bag = PanelContainer.new()
	_bag.anchor_left = 1.0
	_bag.anchor_right = 1.0
	_bag.anchor_top = 0.5
	_bag.anchor_bottom = 0.5
	_bag.offset_right = -BAG_MARGIN
	_bag.offset_left = -BAG_MARGIN - BAG_W
	_bag.offset_top = -120.0
	_bag.offset_bottom = -120.0
	_bag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bag.grow_vertical = Control.GROW_DIRECTION_END
	_bag.custom_minimum_size = Vector2(BAG_W, 0)
	var panel := _flat(EMPTY)
	panel.set_content_margin_all(BAG_PAD)
	_bag.add_theme_stylebox_override("panel", panel)
	_bag.visible = false
	root.add_child(_bag)
	var inner := VBoxContainer.new()
	_bag.add_child(inner)
	var title := Label.new()
	title.text = UiText.BAG
	inner.add_child(title)
	_bag_list = VBoxContainer.new()
	inner.add_child(_bag_list)
	_bag_empty = Label.new()
	_bag_empty.text = UiText.BAG_EMPTY
	_bag_empty.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	inner.add_child(_bag_empty)
	_fire = _small_button("Fire", UiText.BUILD_FIRE, func(): client.request_build_fire())
	_fire.disabled = true
	inner.add_child(_fire)
	_notice = Label.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position = Vector2(-200, 24)
	_notice.custom_minimum_size = Vector2(400, 0)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_outline_color", Color.BLACK)
	_notice.add_theme_constant_override("outline_size", 4)
	_notice.visible = false
	root.add_child(_notice)


func _small_button(node_name: String, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", BUTTON_FONT)
	b.pressed.connect(on_press)
	return b


## How wide a line of the bag's buttons with these texts is, in pixels (the theme's font).
static func buttons_width(texts: Array) -> float:
	var font := ThemeDB.fallback_font
	var w := 0.0
	for t in texts:
		w += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, BUTTON_FONT).x + 2.0 * BUTTON_PAD
	return w + BUTTON_GAP * maxi(texts.size() - 1, 0)


static func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(2)
	return s
