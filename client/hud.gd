## In-game HUD, shown once joined, in the menu's style (client/ui_theme.gd): the hunger bar in a
## framed box (bottom left) with a warning when starving and the key hints as key caps; the bag
## window (client/bag_view.gd: E opens and closes it, Escape closes it); short notices from the
## server on a parchment band (top centre), with the item's icon when there is one.
## The world map (client/world_map.gd): a minimap (bottom right) and a big map, opened and closed with
## the physical M key (',' on AZERTY) or closed with Escape. Both follow the player, show the other
## players the server sends, and zoom with the mouse wheel. The explored cells are kept per player name.
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
const MINIMAP_PX := 100.0
const MAP_MARGIN := 16.0
## Explored cells are saved this often (seconds) while they change, and when leaving.
const MAP_SAVE_S := 10.0
## The player's surroundings are revealed again this often (seconds) even standing still: the chunks
## around them keep being generated after they stop.
const MAP_REVEAL_S := 1.0

var client: Node  ## client/client.gd

var _bar: ProgressBar
var _starving: Label
var _bag: BagView
var _notice: PanelContainer
var _notice_icon: TextureRect
var _notice_label: Label
var _notice_left := 0.0
var _my_pos: Variant = null  ## where I stand (last snapshot), or null before the first
var _fires: Array = []  ## positions of the fires the server sent
var _seen_labels := {}  ## physical key -> its label, for every key the player pressed
var _hint_caps := {}  ## physical key -> the Label of its key cap
var _map := WorldMap.new()
var _map_path := ""  ## where the explored cells are kept ("" before joining)
var _map_dirty := false
var _map_save_in := MAP_SAVE_S
var _map_reveal_in := 0.0
var _revealed_at: Variant = null  ## the cell the map was last revealed around
var _minimap: MapView
var _big_map: MapView
var _big_frame: Control
var _map_help: Label  ## under the big map: how to zoom and close it


func _ready() -> void:
	layer = 5
	visible = false
	_build()
	client.welcomed.connect(_on_welcomed)
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


func minimap() -> MapView:
	return _minimap


func big_map() -> MapView:
	return _big_map


func toggle_big_map() -> void:
	_big_frame.visible = not _big_frame.visible
	_big_map.visible = _big_frame.visible
	_minimap.visible = not _big_frame.visible
	_minimap.get_parent().visible = _minimap.visible


## Closes the big map if it is open, else the bag. False if neither was open (Escape then opens the
## settings menu: client/settings_menu.gd).
func close_window() -> bool:
	if _big_frame.visible:
		toggle_big_map()
		return true
	if _bag.visible:
		_bag.visible = false
		return true
	return false


func _on_welcomed(_cell: Vector2i) -> void:
	visible = true
	var player_name: Variant = client.get("player_name")
	if typeof(player_name) == TYPE_STRING and player_name != "":
		_map_path = WorldMap.path_for(player_name)
		_map.load(_map_path)
		_minimap.refresh_all()
		_big_map.refresh_all()


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
	_map_help.text = UiText.MAP_HELP % UiText.key_name(KEY_M, _seen_labels)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_E:
			toggle_bag()
		KEY_Q:
			client.request_whistle()
		KEY_M:
			toggle_big_map()
		KEY_ESCAPE:
			if not close_window():
				return
		_:
			return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_age_notice(delta)
	_update_map(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_map()


## Reveals the cells around the player when they move (and now and then), and saves them now and then.
func _update_map(dt: float) -> void:
	if _my_pos == null or not visible:
		return
	var cell := Protocol.cell_of(_my_pos)
	_map_reveal_in -= dt
	if cell != _revealed_at or _map_reveal_in <= 0.0:
		_revealed_at = cell
		_map_reveal_in = MAP_REVEAL_S
		var changed := _map.reveal(cell)
		if not changed.is_empty():
			_map_dirty = true
			_minimap.refresh(changed)
			_big_map.refresh(changed)
	_map_save_in -= dt
	if _map_save_in <= 0.0:
		_map_save_in = MAP_SAVE_S
		_save_map()


func _save_map() -> void:
	if _map_dirty and _map_path != "":
		_map.save(_map_path)
		_map_dirty = false


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
	var item := String(args.get("item", ""))
	_notice_icon.visible = item != "" and not ItemData.item(item).is_empty()
	_notice_icon.texture = BagView.icon_of(item) if _notice_icon.visible else null
	_notice.visible = true
	_notice_label.visible = true
	_notice.modulate.a = 1.0
	_notice_left = NOTICE_S


func _on_snapshot(players: Array) -> void:
	var markers := []
	for p in players:
		var me: bool = p["id"] == client.my_peer_id
		if me:
			_my_pos = p["pos"]
		markers.append({"pos": p["pos"], "me": me})
	_update_fire()
	if _my_pos != null:
		_minimap.set_view(_my_pos, markers)
		_big_map.set_view(_my_pos, markers)


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

	_build_maps(root)

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
	_notice_label.add_theme_color_override("font_color", UiTheme.TEXT_DARK)
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_line.add_child(_notice_label)


## The minimap in a frame (bottom right), and the big map over most of the screen, hidden at first.
func _build_maps(root: Control) -> void:
	var mini_frame := PanelContainer.new()
	mini_frame.add_theme_stylebox_override("panel", UiTheme.box("panel", 4))
	mini_frame.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mini_frame.offset_right = -MAP_MARGIN
	mini_frame.offset_bottom = -MAP_MARGIN
	mini_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mini_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(mini_frame)
	_minimap = MapView.new(_map, 1.0, 8.0, 2.0)
	_minimap.custom_minimum_size = Vector2(MINIMAP_PX, MINIMAP_PX)
	mini_frame.add_child(_minimap)

	_big_frame = PanelContainer.new()
	_big_frame.add_theme_stylebox_override("panel", UiTheme.box("panel", 8))
	_big_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_frame.offset_left = 60
	_big_frame.offset_right = -60
	_big_frame.offset_top = 40
	_big_frame.offset_bottom = -40
	_big_frame.visible = false
	root.add_child(_big_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_big_frame.add_child(col)
	var title := Label.new()
	title.text = UiText.MAP_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_big_map = MapView.new(_map, 0.5, 16.0, 4.0)
	_big_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_big_map.visible = false
	col.add_child(_big_map)
	var help := Label.new()
	help.text = UiText.MAP_HELP % UiText.key_name(KEY_M)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	col.add_child(help)
	_map_help = help


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
