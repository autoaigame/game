extends TestCase

## The in-game HUD (client/hud.gd): the hunger bar.


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal status_received(status: Dictionary)
	signal inventory_received(items: Dictionary)
	signal notice_received(key: String, args: Dictionary)
	signal snapshot_received(players: Array)
	signal marks_received(marks: Array)
	var my_peer_id := 0
	var eaten: Array = []

	func request_eat(item: String) -> void:
		eaten.append(item)

	var fires := 0
	var whistles := 0
	var cooked: Array = []

	func request_cook(item: String) -> void:
		cooked.append(item)

	func request_whistle() -> void:
		whistles += 1

	func request_build_fire() -> void:
		fires += 1


func _hud() -> CanvasLayer:
	var hud: CanvasLayer = load("res://client/hud.gd").new()
	hud.client = FakeClient.new()
	hud.add_child(hud.client)
	hud._ready()
	return hud


func test_hidden_until_joined() -> void:
	var hud := _hud()
	assert_false(hud.visible)
	hud.client.welcomed.emit(Vector2i.ZERO)
	assert_true(hud.visible)
	hud.free()


func test_hunger_bar_follows_the_status() -> void:
	var hud := _hud()
	hud.client.status_received.emit({"hunger": 64})
	assert_eq(hud.hunger_bar().value, 64.0)
	assert_eq(hud.hunger_bar().max_value, 100.0)
	hud.client.status_received.emit({"other": 1})
	assert_eq(hud.hunger_bar().value, 64.0, "other keys leave it alone")
	hud.free()


func test_warns_when_starving() -> void:
	var hud := _hud()
	hud.client.status_received.emit({"hunger": 50})
	assert_false(hud.starving_label().visible)
	hud.client.status_received.emit({"hunger": 0})
	assert_true(hud.starving_label().visible)
	hud.free()


func test_bag_shows_items_and_toggles() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"berries": 3})
	assert_false(hud.bag().visible, "closed at first")
	hud.toggle_bag()
	assert_true(hud.bag().visible)
	assert_eq(hud.bag().shown(), [["berries", 3]])
	hud.client.inventory_received.emit({})
	assert_eq(hud.bag().shown(), [])
	hud.toggle_bag()
	assert_false(hud.bag().visible)
	hud.free()


## Escape closes the open bag.
func test_escape_closes_the_bag() -> void:
	var hud := _hud()
	hud.client.welcomed.emit(Vector2i.ZERO)
	hud.toggle_bag()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	hud._unhandled_input(key)
	assert_false(hud.bag().visible)
	hud.free()


## The bag's buttons ask the server.
func test_bag_actions_reach_the_server() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"raw_meat": 1, "sticks": Protocol.FIRE_STICKS})
	hud.bag().pick("raw_meat")
	hud.bag().eat_button().pressed.emit()
	hud.bag().set_near_fire(true)
	hud.bag().cook_button().pressed.emit()
	hud.bag().fire_button().pressed.emit()
	assert_eq(hud.client.eaten, ["raw_meat"])
	assert_eq(hud.client.cooked, ["raw_meat"])
	assert_eq(hud.client.fires, 1)
	hud.free()


## The bag knows a fire is near from the fires the server sends and where I stand.
func test_bag_knows_when_a_fire_is_near() -> void:
	var hud := _hud()
	hud.client.my_peer_id = 7
	hud.client.inventory_received.emit({"raw_meat": 1})
	hud.client.snapshot_received.emit([{"id": 7, "name": "me", "pos": Vector2(10, 10)}])
	hud.client.marks_received.emit([{"id": 1, "kind": "fire", "pos": Vector2(10 + Protocol.COOK_REACH + 0.5, 10), "left": 60.0}])
	assert_true(hud.bag().cook_button().disabled, "too far")
	hud.client.snapshot_received.emit([{"id": 7, "name": "me", "pos": Vector2(11, 10)}])
	assert_false(hud.bag().cook_button().disabled, "close enough")
	hud.client.marks_received.emit([])
	assert_true(hud.bag().cook_button().disabled, "the fire went out")
	hud.free()


func test_notice_shows_then_fades() -> void:
	var hud := _hud()
	hud.client.notice_received.emit("gathered", {"item": "berries", "count": 2})
	assert_true(hud.notice_label().visible)
	assert_true(hud.notice_label().text.contains("2"), hud.notice_label().text)
	hud._age_notice(hud.NOTICE_S + 0.1)
	assert_false(hud.notice_label().visible)
	hud.free()


func _press(hud: CanvasLayer, code: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = true
	hud._unhandled_input(key)


## The key next to the movement keys (Q on QWERTY, A on AZERTY) whistles the dog, once joined.
func test_q_key_whistles() -> void:
	var hud := _hud()
	_press(hud, KEY_Q)
	assert_eq(hud.client.whistles, 0, "not before joining")
	hud.client.welcomed.emit(Vector2i.ZERO)
	_press(hud, KEY_Q)
	assert_eq(hud.client.whistles, 1)
	_press(hud, KEY_H)
	assert_eq(hud.client.whistles, 1, "H no longer whistles")
	_press(hud, KEY_A)
	assert_eq(hud.client.whistles, 1, "the move-left key does not whistle")
	hud.free()


## E opens and closes the bag; I no longer does.
func test_e_toggles_the_bag() -> void:
	var hud := _hud()
	hud.client.welcomed.emit(Vector2i.ZERO)
	_press(hud, KEY_E)
	assert_true(hud.bag().visible)
	_press(hud, KEY_E)
	assert_false(hud.bag().visible)
	_press(hud, KEY_I)
	assert_false(hud.bag().visible, "I no longer opens it")
	hud.free()


## The key hints name the keys as printed on the player's keyboard.
func test_key_hints_follow_the_layout() -> void:
	var physical: Array = UiText.KEYS.map(func(k): return k[0])
	assert_eq(physical, [KEY_E, KEY_Q, KEY_M])
	if DisplayServer.get_name() in UiText.LAYOUT_AWARE:
		var label := DisplayServer.keyboard_get_label_from_physical(KEY_Q)
		assert_eq(UiText.key_name(KEY_Q), OS.get_keycode_string(label))
	else:
		assert_eq(UiText.key_name(KEY_Q), "Q", "QWERTY name without a known layout")
		assert_eq(UiText.key_name(KEY_E), "E")


func _keyboard_key(physical: Key, label: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = physical
	key.key_label = label
	key.pressed = true
	return key


## Without a layout lookup (browser), the keys the player presses teach the layout.
func test_key_names_learn_the_layout_from_presses() -> void:
	if DisplayServer.get_name() in UiText.LAYOUT_AWARE:
		return
	assert_eq(UiText.key_name(KEY_Q, {}), "Q")
	assert_eq(UiText.key_name(KEY_Q, {KEY_Q: KEY_A}), "A", "the key itself was pressed")
	assert_eq(UiText.key_name(KEY_Q, {KEY_W: KEY_Z}), "A", "Z up: AZERTY")
	assert_eq(UiText.key_name(KEY_Q, {KEY_A: KEY_Q}), "A", "Q left: AZERTY")
	assert_eq(UiText.key_name(KEY_Q, {KEY_W: KEY_W, KEY_A: KEY_A}), "Q", "QWERTY stays Q")
	assert_eq(UiText.key_name(KEY_E, {KEY_W: KEY_Z}), "E")


## Walking with Z on AZERTY renames the whistle hint to A.
func test_hint_updates_after_walking_on_azerty() -> void:
	if DisplayServer.get_name() in UiText.LAYOUT_AWARE:
		return
	var hud := _hud()
	assert_eq(hud.key_hint(KEY_Q), "Q")
	hud._input(_keyboard_key(KEY_W, KEY_Z))
	assert_eq(hud.key_hint(KEY_Q), "A")
	assert_eq(hud.key_hint(KEY_E), "E")
	hud.free()


## A notice about an item shows its icon.
func test_notice_shows_the_item_icon() -> void:
	var hud := _hud()
	hud.client.notice_received.emit("gathered", {"item": "berries", "count": 2})
	assert_true(hud.notice_icon().visible)
	assert_true(hud.notice_icon().texture != null)
	hud.client.notice_received.emit("no_prey", {})
	assert_false(hud.notice_icon().visible, "none without an item")
	hud.free()


## The physical M key (',' on AZERTY) opens and closes the big map, once joined; Escape closes it.
## The minimap hides while it is open.
func test_m_key_toggles_the_big_map() -> void:
	var hud := _hud()
	_press(hud, KEY_M)
	assert_false(hud.big_map().visible, "not before joining")
	hud.client.welcomed.emit(Vector2i.ZERO)
	assert_true(hud.minimap().visible)
	_press(hud, KEY_M)
	assert_true(hud.big_map().visible)
	assert_false(hud.minimap().visible)
	_press(hud, KEY_M)
	assert_false(hud.big_map().visible)
	assert_true(hud.minimap().visible)
	_press(hud, KEY_M)
	_press(hud, KEY_ESCAPE)
	assert_false(hud.big_map().visible, "Escape closes it")
	hud.free()


## The maps follow me and show the other players the server sends.
func test_maps_show_me_and_the_other_players() -> void:
	var hud := _hud()
	hud.client.my_peer_id = 7
	hud.client.welcomed.emit(Vector2i.ZERO)
	hud.client.snapshot_received.emit([{"id": 7, "name": "me", "pos": Vector2(3, 4)},
			{"id": 9, "name": "bob", "pos": Vector2(10, 4)}])
	assert_eq(hud.minimap().center, Vector2(3, 4))
	assert_eq(hud.big_map().center, Vector2(3, 4))
	assert_eq(hud.minimap().markers, [{"pos": Vector2(3, 4), "me": true}, {"pos": Vector2(10, 4), "me": false}])
	hud.free()


## On AZERTY the map key is printed ','.
func test_map_key_hint_on_azerty() -> void:
	if DisplayServer.get_name() in UiText.LAYOUT_AWARE:
		return
	assert_eq(UiText.key_name(KEY_M, {}), "M")
	assert_eq(UiText.key_name(KEY_M, {KEY_W: KEY_Z}), ",")
	assert_eq(UiText.key_name(KEY_M, {KEY_M: KEY_COMMA}), ",")


## The minimap (bottom right) is hidden while the bag is open, so it is never drawn over the bag.
func test_minimap_hidden_while_the_bag_is_open() -> void:
	var hud := _hud()
	hud.client.welcomed.emit(Vector2i.ZERO)
	var frame: Control = hud.minimap().get_parent()
	assert_true(frame.visible, "shown at first")
	hud.toggle_bag()
	assert_false(frame.visible, "hidden under the open bag")
	hud.toggle_bag()
	assert_true(frame.visible, "back once the bag is closed")
	hud.toggle_bag()
	assert_true(hud.close_window())
	assert_true(frame.visible, "back once Escape closes the bag")
	hud.toggle_bag()
	hud.toggle_big_map()
	hud.toggle_big_map()
	assert_false(frame.visible, "closing the big map keeps it hidden while the bag is open")
	hud.toggle_bag()
	assert_true(frame.visible)
	hud.free()
