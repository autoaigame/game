extends TestCase

## The dog digs holes near its owner (server/dog.gd); holes are marks (server/marks.gd).

const DOG := preload("res://server/dog.gd")
const DT := 1.0 / 15.0


func _ground_cell(diggable: bool) -> Vector2i:
	var s := MapData.spawn_cell()
	for r in 300:
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := s + Vector2i(dx, dy)
				if MapData.is_walkable(c) and MapData.object_at(c) == "" and DOG.can_dig(c) == diggable:
					return c
	return s


func test_digs_a_hole_where_it_stands() -> void:
	var at := _ground_cell(true)
	var dog: Dictionary = DOG.new_dog(Vector2(at), 5)
	assert_true(DOG.start_dig(dog))
	assert_eq(dog["state"], "dig")
	var events := []
	var ticks := 0
	while events.is_empty() and ticks < int(10.0 / DT):
		events.append_array(DOG.update(dog, Vector2(at) + Vector2(1, 0), DT))
		ticks += 1
	assert_eq(events.size(), 1)
	assert_eq(events[0]["kind"], "hole")
	assert_eq(events[0]["pos"], Vector2(at))
	assert_almost(ticks * DT, DOG.DIG_S, DT * 1.5)
	assert_eq(dog["pos"], Vector2(at), "did not move while digging")
	assert_true(dog["state"] in ["idle", "sniff"], "done: %s" % dog["state"])


## Only natural ground: not on water, and not on ground that is not in DIG_GROUNDS.
func test_can_dig_only_natural_ground() -> void:
	for id in DOG.DIG_GROUNDS:
		assert_true(WorldData.tile(WorldData.tile_index(id))["walkable"], "%s is walkable ground" % id)
	var c := _ground_cell(true)
	assert_true(WorldData.tile(MapData.tile_at(c))["id"] in DOG.DIG_GROUNDS)


func test_dogs_dig_on_their_own() -> void:
	var at := _ground_cell(true)
	var holes := 0
	for seed_value in 16:
		var dog: Dictionary = DOG.new_dog(Vector2(at) + Vector2(1, 0), seed_value)
		for i in int(DOG.SIT_AFTER / DT):
			for e in DOG.update(dog, Vector2(at), DT):
				if e["kind"] == "hole":
					holes += 1
	assert_true(holes >= 1, "dug %d holes over 16 dogs" % holes)


func test_owner_walking_off_interrupts_digging() -> void:
	var at := _ground_cell(true)
	var dog: Dictionary = DOG.new_dog(Vector2(at), 5)
	DOG.start_dig(dog)
	var events: Array = DOG.update(dog, Vector2(at) + Vector2(DOG.WAKE_GAP + 3.0, 0), DT)
	assert_eq(dog["state"], "follow")
	assert_eq(events, [])


func test_server_turns_a_hole_into_a_mark() -> void:
	var server: Node = load("res://server/server.gd").new()
	server._add_events([{"kind": "hole", "pos": Vector2(2, 2)}])
	var list: Array = load("res://server/marks.gd").snapshot(server._marks)
	assert_eq(list[0]["kind"], "hole")
	assert_eq(list[0]["left"], DOG.HOLE_MARK_S)
	server.free()
