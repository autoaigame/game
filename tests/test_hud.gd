extends TestCase

## The in-game HUD (client/hud.gd): the hunger bar.


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal status_received(status: Dictionary)
	signal inventory_received(items: Dictionary)
	signal notice_received(key: String, args: Dictionary)
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


func test_bag_lists_items_and_toggles() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"berries": 3})
	assert_false(hud.bag().visible, "closed at first")
	hud.toggle_bag()
	assert_true(hud.bag().visible)
	var rows: Array = hud.bag_rows()
	assert_eq(rows.size(), 1)
	assert_true(rows[0].contains("3"), "shows the count: %s" % rows[0])
	assert_true(rows[0].contains(ItemData.item("berries")["name"]), "shows the name: %s" % rows[0])
	hud.client.inventory_received.emit({})
	assert_eq(hud.bag_rows().size(), 0)
	assert_true(hud.bag_empty_label().visible, "says the bag is empty")
	hud.toggle_bag()
	assert_false(hud.bag().visible)
	hud.free()


func test_notice_shows_then_fades() -> void:
	var hud := _hud()
	hud.client.notice_received.emit("gathered", {"item": "berries", "count": 2})
	assert_true(hud.notice_label().visible)
	assert_true(hud.notice_label().text.contains("2"), hud.notice_label().text)
	hud._age_notice(hud.NOTICE_S + 0.1)
	assert_false(hud.notice_label().visible)
	hud.free()


## Food rows have an "eat" button that asks the server; other items do not.
func test_eat_button_on_food() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"berries": 3})
	var btn: Button = hud.eat_button("berries")
	assert_true(btn != null, "berries can be eaten")
	btn.pressed.emit()
	assert_eq(hud.client.eaten, ["berries"])
	hud.free()


## With enough sticks, the bag offers to build a fire.
func test_build_fire_button() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"sticks": Protocol.FIRE_STICKS - 1})
	assert_true(hud.fire_button().disabled, "not enough sticks")
	hud.client.inventory_received.emit({"sticks": Protocol.FIRE_STICKS})
	assert_false(hud.fire_button().disabled)
	hud.fire_button().pressed.emit()
	assert_eq(hud.client.fires, 1)
	hud.free()


## H whistles the dog to hunt, once joined.
func test_h_whistles() -> void:
	var hud := _hud()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_H
	key.pressed = true
	hud._unhandled_input(key)
	assert_eq(hud.client.whistles, 0, "not before joining")
	hud.client.welcomed.emit(Vector2i.ZERO)
	hud._unhandled_input(key)
	assert_eq(hud.client.whistles, 1)
	hud.free()


## Raw meat has a "cook" button; berries do not.
func test_cook_button() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"raw_meat": 1, "berries": 2})
	assert_true(hud.cook_button("berries") == null, "berries do not cook")
	hud.cook_button("raw_meat").pressed.emit()
	assert_eq(hud.client.cooked, ["raw_meat"])
	hud.free()


## The bag sits against the right edge and grows to the left, so it never leaves the screen; each
## item's buttons sit under its name, and every line of buttons fits the bag's width (real font).
func test_bag_stays_on_screen_and_its_buttons_fit() -> void:
	var hud := _hud()
	hud.client.inventory_received.emit({"raw_meat": 3, "berries": 12, "sticks": 4, "cooked_meat": 1})
	var bag: PanelContainer = hud.bag()
	assert_eq(bag.anchor_left, 1.0)
	assert_eq(bag.anchor_right, 1.0)
	assert_eq(bag.grow_horizontal, Control.GROW_DIRECTION_BEGIN, "grows to the left")
	assert_almost(bag.offset_right, -hud.BAG_MARGIN)
	assert_almost(bag.offset_right - bag.offset_left, hud.BAG_W)
	var inner: float = hud.BAG_W - 2.0 * hud.BAG_PAD
	assert_true(hud.buttons_width([UiText.EAT, UiText.COOK]) <= inner,
			"eat + cook fit: %f" % hud.buttons_width([UiText.EAT, UiText.COOK]))
	assert_true(hud.buttons_width([UiText.BUILD_FIRE]) <= inner, "fire button fits")
	assert_true(hud.cook_button("raw_meat") != null and hud.eat_button("raw_meat") != null, "both shown for raw meat")
	assert_eq(hud.cook_button("raw_meat").get_parent(), hud.eat_button("raw_meat").get_parent())
	assert_true(hud.cook_button("raw_meat").get_parent().name == "Actions", "on their own line")
	hud.free()


## The width measure is real: a long text does not fit.
func test_buttons_width_grows_with_text() -> void:
	var hud := _hud()
	assert_true(hud.buttons_width([UiText.EAT]) < hud.buttons_width([UiText.EAT, UiText.COOK]))
	assert_true(hud.buttons_width(["Un très très long bouton qui ne tient pas"]) > hud.BAG_W)
	hud.free()
