## In-game HUD, shown once joined: the hunger bar (bottom left), with a warning when starving; the
## bag (I opens and closes it); short notices from the server (top centre).
## Values come from the server (status message); the HUD only shows them.
extends CanvasLayer

const HUNGER_MAX := 100.0
const BAR_SIZE := Vector2(160, 14)
const FULL := Color8(0xb8, 0x8a, 0x4a)
const EMPTY := Color8(0x2e, 0x28, 0x22, 0xc0)
const NOTICE_S := 3.0

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
			out.append((row.get_child(1) as Label).text)
	return out


## The "eat" button of an item's row, or null.
func eat_button(item: String) -> Button:
	for row in _bag_list.get_children():
		if row.get_meta("item", "") == item and not row.is_queued_for_deletion():
			return row.get_node_or_null("Eat")
	return null


func fire_button() -> Button:
	return _fire


func toggle_bag() -> void:
	_bag.visible = not _bag.visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I:
		toggle_bag()
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
		var row := HBoxContainer.new()
		var icon := ColorRect.new()
		icon.color = it["color"]
		icon.custom_minimum_size = Vector2(14, 14)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var label := Label.new()
		label.text = "%d × %s" % [int(items[id]), it["name"]]
		row.add_child(label)
		if it["food"] > 0:
			var eat := Button.new()
			eat.name = "Eat"
			eat.text = UiText.EAT
			eat.focus_mode = Control.FOCUS_NONE
			var item_id := String(id)
			eat.pressed.connect(func(): client.request_eat(item_id))
			row.add_child(eat)
		row.set_meta("item", String(id))
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
	_bag = PanelContainer.new()
	_bag.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_bag.position = Vector2(-216, -80)
	_bag.custom_minimum_size = Vector2(200, 0)
	_bag.add_theme_stylebox_override("panel", _flat(EMPTY))
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
	_fire = Button.new()
	_fire.text = UiText.BUILD_FIRE
	_fire.focus_mode = Control.FOCUS_NONE
	_fire.disabled = true
	_fire.pressed.connect(func(): client.request_build_fire())
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


static func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(2)
	return s
