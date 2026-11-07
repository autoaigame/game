## The bag window, in the menu's style (client/ui_theme.gd): a title band over a panel holding a grid
## of slots (item icon and count), the picked item's name, what it does and its actions (eat, cook),
## and a recipe card to build a fire. Display only: its buttons emit signals and the HUD asks the
## server, which decides (docs/invariants.md, rule 1). Cooking is offered only near a fire
## (set_near_fire), as the server requires; the server still checks.
class_name BagView
extends VBoxContainer

signal eat(item: String)
signal cook(item: String)
signal build_fire

const COLUMNS := 4
const MIN_SLOTS := 12  ## the grid always shows at least this many slots, in full rows
const SLOT_PX := 52
const SLOT_GAP := 6
const ICON_DIR := "res://assets/items/"
const SMALL_FONT := 14
const BUTTON_FONT := 16

var _items := {}
var _picked := ""
var _near_fire := false
var _grid: GridContainer
var _slots: Array[Button] = []
var _detail: VBoxContainer
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_text: Label
var _eat: Button
var _cook: Button
var _fire_hint: Label
var _empty: Label
var _recipe_count: Label
var _fire: Button


func _init() -> void:
	name = "Bag"
	add_theme_constant_override("separation", -10)  # the band overlaps the panel's top edge
	_build()
	set_items({})


## Shows these items (id -> count).
func set_items(items: Dictionary) -> void:
	_items = {}
	for id in items:
		if not ItemData.item(String(id)).is_empty() and int(items[id]) > 0:
			_items[String(id)] = int(items[id])
	if not _items.has(_picked):
		var ids := _sorted_ids()
		_picked = ids[0] if not ids.is_empty() else ""
	_refresh()


## Whether a fire is close enough to cook on.
func set_near_fire(near: bool) -> void:
	_near_fire = near
	_refresh_detail()


## Picks the item `id` (if the bag has it): the detail and actions show it.
func pick(id: String) -> void:
	if _items.has(id):
		_picked = id
		_refresh()


func picked() -> String:
	return _picked


## The items shown, in slot order: [[id, count], ...].
func shown() -> Array:
	return _sorted_ids().map(func(id): return [id, _items[id]])


func slot_of(id: String) -> Button:
	for s in _slots:
		if s.get_meta("item", "") == id:
			return s
	return null


func slot_count() -> int:
	return _slots.size()


func detail_name() -> Label:
	return _detail_name


func detail_text() -> Label:
	return _detail_text


func eat_button() -> Button:
	return _eat


func cook_button() -> Button:
	return _cook


func fire_hint() -> Label:
	return _fire_hint


func empty_label() -> Label:
	return _empty


func fire_button() -> Button:
	return _fire


func recipe_count() -> Label:
	return _recipe_count


## The icon of item `id`: its drawn PNG, or a square of its colour.
static func icon_of(id: String) -> Texture2D:
	var path := ICON_DIR + id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	var it := ItemData.item(id)
	return UiTheme.square_icon(24, it.get("color", Color.GRAY), UiTheme.TEXT_DARK)


func _sorted_ids() -> Array:
	var ids := _items.keys()
	ids.sort()
	return ids


func _refresh() -> void:
	var ids := _sorted_ids()
	var want := maxi(MIN_SLOTS, ceili(float(ids.size()) / COLUMNS) * COLUMNS)
	while _slots.size() < want:
		_add_slot()
	while _slots.size() > want:
		var s: Button = _slots.pop_back()
		_grid.remove_child(s)
		s.queue_free()
	for i in _slots.size():
		var s := _slots[i]
		var id: String = ids[i] if i < ids.size() else ""
		s.set_meta("item", id)
		s.disabled = id == ""
		s.button_pressed = id != "" and id == _picked
		s.tooltip_text = ItemData.item(id).get("name", "") if id != "" else ""
		(s.get_node("Icon") as TextureRect).texture = icon_of(id) if id != "" else null
		(s.get_node("Count") as Label).text = str(_items[id]) if id != "" else ""
	var sticks := int(_items.get("sticks", 0))
	_fire.disabled = sticks < Protocol.FIRE_STICKS
	_recipe_count.text = "%d / %d" % [mini(sticks, Protocol.FIRE_STICKS), Protocol.FIRE_STICKS]
	_refresh_detail()


func _refresh_detail() -> void:
	var it := ItemData.item(_picked)
	_empty.visible = it.is_empty()
	_detail.visible = not it.is_empty()
	_eat.visible = not it.is_empty() and it["food"] > 0
	_cook.visible = not it.is_empty() and it["cooks_into"] != ""
	_cook.disabled = not _near_fire
	_fire_hint.visible = _cook.visible and not _near_fire
	if it.is_empty():
		return
	_detail_icon.texture = icon_of(_picked)
	_detail_name.text = "%s  ×%d" % [it["name"], _items[_picked]]
	var lines := []
	if it["food"] > 0:
		lines.append(UiText.FOOD_DESC % it["food"])
	if it["cooks_into"] != "":
		lines.append(UiText.COOKS_DESC % ItemData.item(it["cooks_into"]).get("name", it["cooks_into"]))
	if _picked == "sticks":
		lines.append(UiText.STICKS_DESC)
	_detail_text.text = "\n".join(lines)


func _build() -> void:
	var band := PanelContainer.new()
	band.theme_type_variation = "TitleBand"
	band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	band.custom_minimum_size = Vector2(150, UiTheme.TITLE_BAND_H)
	band.z_index = 1
	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = UiText.BAG
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title)
	add_child(band)

	var panel := PanelContainer.new()
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(top_gap)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_grid)

	_empty = _small_label(UiText.BAG_EMPTY)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_empty)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	box.add_child(_detail)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_detail.add_child(head)
	_detail_icon = TextureRect.new()
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_detail_icon.custom_minimum_size = Vector2(36, 36)
	head.add_child(_detail_icon)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	_detail_name = Label.new()
	_detail_name.clip_text = true
	words.add_child(_detail_name)
	_detail_text = _small_label("")
	words.add_child(_detail_text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_detail.add_child(actions)
	_eat = _button(UiText.EAT, func(): eat.emit(_picked))
	actions.add_child(_eat)
	_cook = _button(UiText.COOK, func(): cook.emit(_picked))
	actions.add_child(_cook)
	_fire_hint = _small_label(UiText.NOTICES["no_fire"])
	_fire_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.add_child(_fire_hint)

	box.add_child(_rule())
	box.add_child(_small_label(UiText.CRAFT))
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	box.add_child(card)
	card.add_child(_icon_rect(icon_of("sticks")))
	_recipe_count = _small_label("")
	_recipe_count.custom_minimum_size = Vector2(38, 0)
	card.add_child(_recipe_count)
	var arrow := _small_label("→")
	card.add_child(arrow)
	card.add_child(_icon_rect(UiTheme.icon("fire")))
	_fire = _button(UiText.FIRE_RECIPE, func(): build_fire.emit())
	_fire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_fire)


func _add_slot() -> void:
	var s := Button.new()
	s.toggle_mode = true
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
	var normal := _slot_box("slot")
	var picked := _slot_box("slot_selected")
	for state in ["normal", "disabled", "hover", "focus"]:
		s.add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		s.add_theme_stylebox_override(state, picked)
	var icon := _icon_rect(null)
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(icon)
	var count := Label.new()
	count.name = "Count"
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -SLOT_PX
	count.offset_top = -22
	count.offset_right = -5
	count.offset_bottom = -1
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", SMALL_FONT)
	count.add_theme_constant_override("outline_size", 4)
	count.add_theme_color_override("font_outline_color", UiTheme.TEXT_DARK)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(count)
	s.pressed.connect(func(): _on_slot(s))
	_slots.append(s)
	_grid.add_child(s)


func _on_slot(s: Button) -> void:
	var id: String = s.get_meta("item", "")
	if id == "":
		return
	pick(id)
	s.button_pressed = true  # picking the picked slot again keeps it picked


## The slot frame `key` (assets/ui/<key>.png, art/ui_icons.gd) as a 9-slice, or a flat box.
static func _slot_box(key: String) -> StyleBox:
	var path := UiTheme.DIR + key + ".png"
	if not ResourceLoader.exists(path):
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color8(0x2c, 0x31, 0x24)
		flat.border_color = UiTheme.TEXT_LIGHT if key == "slot_selected" else Color8(0x51, 0x43, 0x3a)
		flat.set_border_width_all(2)
		return flat
	var st := StyleBoxTexture.new()
	st.texture = load(path)
	var m := 5
	st.texture_margin_left = m
	st.texture_margin_top = m
	st.texture_margin_right = m
	st.texture_margin_bottom = m
	return st


func _icon_rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(32, 32)
	return r


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HintLabel"
	l.add_theme_font_size_override("font_size", SMALL_FONT)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", BUTTON_FONT)
	b.pressed.connect(on_press)
	return b


## A thin dark line across the panel, between the bag and the recipes.
func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.25)
	r.custom_minimum_size = Vector2(0, 2)
	return r
