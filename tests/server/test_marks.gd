extends TestCase

## Short-lived marks on the ground (server/marks.gd): pee spots, holes.

const MARKS := preload("res://server/marks.gd")


func test_add_and_send() -> void:
	var m: Dictionary = MARKS.new_marks()
	MARKS.add(m, "pee", Vector2(3, 4), 60.0)
	MARKS.add(m, "pee", Vector2(5, 6), 30.0)
	var list: Array = MARKS.snapshot(m)
	assert_eq(list.size(), 2)
	assert_eq(list[0]["kind"], "pee")
	assert_eq(list[0]["pos"], Vector2(3, 4))
	assert_eq(list[0]["left"], 60.0)
	assert_true(list[0]["id"] != list[1]["id"], "distinct ids")


## Marks age and go away; tick says when the list changed.
func test_marks_expire() -> void:
	var m: Dictionary = MARKS.new_marks()
	MARKS.add(m, "pee", Vector2(3, 4), 1.0)
	MARKS.add(m, "pee", Vector2(5, 6), 3.0)
	assert_false(MARKS.tick(m, 0.5), "nothing removed yet")
	assert_true(MARKS.tick(m, 0.6), "first one gone")
	assert_eq(MARKS.snapshot(m).size(), 1)
	assert_almost(MARKS.snapshot(m)[0]["left"], 1.9)
	assert_true(MARKS.tick(m, 2.0))
	assert_eq(MARKS.snapshot(m).size(), 0)


## There is a cap: the oldest marks go first.
func test_marks_are_capped() -> void:
	var m: Dictionary = MARKS.new_marks()
	for i in MARKS.MAX_MARKS + 5:
		MARKS.add(m, "pee", Vector2(i, 0), 60.0)
	var list: Array = MARKS.snapshot(m)
	assert_eq(list.size(), MARKS.MAX_MARKS)
	assert_eq(list[0]["pos"], Vector2(5, 0))


## The server turns a dog's pee into a mark and sends the marks.
func test_server_adds_dog_marks() -> void:
	var server: Node = load("res://server/server.gd").new()
	server._add_events([{"kind": "pee", "pos": Vector2(2, 2)}])
	var list: Array = MARKS.snapshot(server._marks)
	assert_eq(list.size(), 1)
	assert_eq(list[0]["kind"], "pee")
	assert_true(server._marks_changed)
	server.free()


func test_find_and_remove() -> void:
	var marks := MARKS.new_marks()
	MARKS.add(marks, "hole", Vector2(1, 1), 10.0)
	MARKS.add(marks, "pee", Vector2(2, 2), 10.0)
	assert_eq(MARKS.find(marks, 2)["kind"], "pee")
	assert_eq(MARKS.find(marks, 9), {})
	MARKS.remove(marks, 1)
	assert_eq(MARKS.snapshot(marks).map(func(m): return m["id"]), [2])
