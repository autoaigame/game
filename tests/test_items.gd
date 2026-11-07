extends TestCase

## Item data (data/items, shared/item_data.gd) and clicking things to gather them (client/interact.gd).


func test_berries_are_food() -> void:
	var b: Dictionary = ItemData.item("berries")
	assert_eq(b["id"], "berries")
	assert_true(b["food"] > 0, "berries feed")
	assert_true(String(b["name"]) != "")
	assert_eq(ItemData.item("nope"), {})


func test_every_item_has_a_name_and_colour() -> void:
	for it in ItemData.items():
		assert_true(String(it["name"]) != "", "%s has a name" % it["id"])
		assert_true(it["color"] is Color, "%s has a colour" % it["id"])


func _bush() -> Vector2i:
	var s := MapData.spawn_cell()
	for r in 300:
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := s + Vector2i(dx, dy)
				if MapData.object_at(c) == "bush":
					return c
	return s


## Clicking on a bush, or just above it (on its leaves), picks that bush.
func test_click_finds_the_bush() -> void:
	var bush := _bush()
	assert_eq(Interact.gatherable_at(bush), bush)
	assert_eq(Interact.gatherable_at(bush - Vector2i(1, 1)), bush, "click on its leaves, one cell up on screen")


func test_click_on_plain_ground_finds_nothing() -> void:
	var s := MapData.spawn_cell()
	for r in 50:
		var c := s + Vector2i(r, 0)
		var around := [c, c + Vector2i(1, 1), c + Vector2i(1, 0), c + Vector2i(0, 1)]
		if around.all(func(x): return MapData.object_at(x) == ""):
			assert_eq(Interact.gatherable_at(c), null)
			return
	assert_true(false, "no plain ground found")


func test_reached_within_reach() -> void:
	assert_true(Interact.reached(Vector2(5, 5), Vector2i(5, 6)))
	assert_false(Interact.reached(Vector2(5, 5), Vector2i(5, 8)))
