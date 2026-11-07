extends TestCase

## The bag window (client/bag_view.gd): a grid of slots with item icons and counts; picking a slot shows
## the item and what can be done with it; cooking needs a fire nearby; a recipe card builds a fire.


func _bag() -> BagView:
	var bag := BagView.new()
	bag.theme = UiTheme.build()
	return bag


func test_slots_show_icons_and_counts() -> void:
	var bag := _bag()
	bag.set_items({"sticks": 4, "berries": 12})
	assert_eq(bag.shown(), [["berries", 12], ["sticks", 4]], "sorted by id")
	var slot := bag.slot_of("berries")
	assert_true(slot != null)
	assert_true(slot.get_node("Icon").texture != null, "has an icon")
	assert_eq((slot.get_node("Count") as Label).text, "12")
	assert_true(bag.slot_count() >= BagView.MIN_SLOTS, "empty slots fill the grid")
	assert_true(bag.slot_count() % BagView.COLUMNS == 0, "full rows")
	bag.free()


## Each item has its own drawn icon (assets/items/<id>.png); an unknown one falls back to its colour.
func test_every_item_has_a_drawn_icon() -> void:
	for it in ItemData.items():
		assert_true(ResourceLoader.exists(BagView.ICON_DIR + it["id"] + ".png"), "icon for %s" % it["id"])
		assert_true(BagView.icon_of(it["id"]) != null)


func test_first_item_is_picked_and_detail_shows_it() -> void:
	var bag := _bag()
	bag.set_items({"raw_meat": 2, "berries": 3})
	assert_eq(bag.picked(), "berries", "first slot picked at first")
	assert_true(bag.detail_name().text.contains(ItemData.item("berries")["name"]))
	assert_true(bag.detail_text().text.contains(str(ItemData.item("berries")["food"])), bag.detail_text().text)
	bag.pick("raw_meat")
	assert_eq(bag.picked(), "raw_meat")
	assert_true(bag.detail_name().text.contains(ItemData.item("raw_meat")["name"]))
	bag.free()


## Picking a slot is a click on it.
func test_click_on_a_slot_picks_it() -> void:
	var bag := _bag()
	bag.set_items({"raw_meat": 2, "berries": 3})
	bag.slot_of("raw_meat").pressed.emit()
	assert_eq(bag.picked(), "raw_meat")
	bag.free()


## The pick survives an update while the item is still there, and moves on when it is gone.
func test_pick_follows_the_inventory() -> void:
	var bag := _bag()
	bag.set_items({"raw_meat": 2, "berries": 3})
	bag.pick("raw_meat")
	bag.set_items({"raw_meat": 1, "berries": 3})
	assert_eq(bag.picked(), "raw_meat", "kept")
	bag.set_items({"berries": 3})
	assert_eq(bag.picked(), "berries", "moved on")
	bag.set_items({})
	assert_eq(bag.picked(), "")
	assert_true(bag.empty_label().visible, "says the bag is empty")
	assert_false(bag.eat_button().visible)
	bag.free()


## Eat and cook act on the picked item; they show only for items that can.
func test_actions_follow_the_pick() -> void:
	var bag := _bag()
	var eaten := []
	var cooked := []
	bag.eat.connect(func(id): eaten.append(id))
	bag.cook.connect(func(id): cooked.append(id))
	bag.set_items({"raw_meat": 2, "sticks": 3})
	bag.pick("sticks")
	assert_false(bag.eat_button().visible, "sticks are not food")
	assert_false(bag.cook_button().visible, "sticks do not cook")
	bag.pick("raw_meat")
	assert_true(bag.eat_button().visible)
	assert_true(bag.cook_button().visible)
	bag.eat_button().pressed.emit()
	bag.set_near_fire(true)
	bag.cook_button().pressed.emit()
	assert_eq(eaten, ["raw_meat"])
	assert_eq(cooked, ["raw_meat"])
	bag.free()


## Cooking needs a fire nearby: without one the button is off and the bag says why.
func test_cook_needs_a_fire() -> void:
	var bag := _bag()
	bag.set_items({"raw_meat": 2})
	assert_true(bag.cook_button().disabled, "no fire yet")
	assert_true(bag.fire_hint().visible, "says a fire is needed")
	bag.set_near_fire(true)
	assert_false(bag.cook_button().disabled)
	assert_false(bag.fire_hint().visible)
	bag.free()


func test_fire_recipe() -> void:
	var bag := _bag()
	var built := [0]
	bag.build_fire.connect(func(): built[0] += 1)
	bag.set_items({"sticks": Protocol.FIRE_STICKS - 1})
	assert_true(bag.fire_button().disabled, "not enough sticks")
	assert_true(bag.recipe_count().text.contains(str(Protocol.FIRE_STICKS)), bag.recipe_count().text)
	bag.set_items({"sticks": Protocol.FIRE_STICKS})
	assert_false(bag.fire_button().disabled)
	bag.fire_button().pressed.emit()
	assert_eq(built[0], 1)
	bag.free()


## The committed icons are what art/ui_icons.gd draws: change it, then run `make art`.
func test_icons_match_their_generator() -> void:
	var drawn: Dictionary = load("res://art/ui_icons.gd").all()
	for path in drawn:
		var a: Image = drawn[path]
		var b: Image = load(path).get_image()
		b.convert(Image.FORMAT_RGBA8)
		assert_eq(b.get_size(), a.get_size(), path)
		var diff := 0
		for y in a.get_height():
			for x in a.get_width():
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.a - cb.a) > 0.01 or (ca.a > 0.0 and not ca.is_equal_approx(cb)):
					diff += 1
		assert_eq(diff, 0, "%s is out of date: run make art" % path)
