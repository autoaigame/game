extends TestCase

## The dog pees on trees near its owner and leaves a wet mark (server/dog.gd, server/marks.gd).

const DOG := preload("res://server/dog.gd")
const DT := 1.0 / 15.0


## A walkable cell with a tree within PEE_RADIUS, near the spawn.
func _owner_near_tree() -> Vector2i:
	var s := MapData.spawn_cell()
	for r in 200:
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := s + Vector2i(dx, dy)
				if MapData.is_walkable(c) and DOG.tree_near(c) != null:
					return c
	return s


## A walkable cell with no tree within PEE_RADIUS.
func _owner_far_from_trees() -> Vector2i:
	var s := MapData.spawn_cell()
	for r in 200:
		for dx in range(-r, r + 1):
			var c := s + Vector2i(dx, r)
			if MapData.is_walkable(c) and DOG.tree_near(c) == null:
				return c
	return s


func test_tree_near_finds_a_tree() -> void:
	var c := _owner_near_tree()
	var t: Variant = DOG.tree_near(c)
	assert_true(t != null, "test needs a tree")
	assert_true(MapData.object_at(t) in DOG.TREE_IDS, "a tree: %s" % MapData.object_at(t))
	assert_true(Vector2(t - c).length() <= DOG.PEE_RADIUS + 0.01)


## The dog walks next to the tree, lifts its leg for a while, and leaves a mark there.
func test_pees_next_to_a_tree() -> void:
	var owner := _owner_near_tree()
	var dog: Dictionary = DOG.new_dog(Vector2(owner), 3)
	assert_true(DOG.start_pee(dog, Vector2(owner)), "starts towards a tree")
	assert_eq(dog["state"], "to_pee")
	var tree: Vector2i = dog["tree"]
	var events := []
	var states := {}
	for i in int(10.0 / DT):
		events.append_array(DOG.update(dog, Vector2(owner), DT))
		states[dog["state"]] = true
		assert_true(MapData.is_walkable(Protocol.cell_of(dog["pos"])))
		if not events.is_empty():
			break
	assert_true(states.has("pee"), "lifted its leg")
	assert_eq(events.size(), 1)
	assert_eq(events[0]["kind"], "pee")
	var at: Vector2 = events[0]["pos"]
	assert_true(at.distance_to(Vector2(tree)) <= 1.6, "mark next to the tree: %s, tree %s" % [at, tree])
	assert_true(dog["state"] in ["idle", "sniff", "sit"], "done: %s" % dog["state"])


func test_no_tree_no_pee() -> void:
	var owner := _owner_far_from_trees()
	var dog: Dictionary = DOG.new_dog(Vector2(owner), 3)
	assert_false(DOG.start_pee(dog, Vector2(owner)))
	assert_eq(dog["state"], "idle")


## Left alone near trees, dogs pee now and then on their own (some of several seeds).
func test_dogs_pee_on_their_own() -> void:
	var owner := _owner_near_tree()
	var peed := 0
	for seed_value in 12:
		var dog: Dictionary = DOG.new_dog(Vector2(owner) + Vector2(1, 0), seed_value)
		for i in int(DOG.SIT_AFTER / DT):
			for e in DOG.update(dog, Vector2(owner), DT):
				if e["kind"] == "pee":
					peed += 1
	assert_true(peed >= 2, "peed %d times over 12 dogs" % peed)


## The dog leaves for its owner if they walk off while it is busy with a tree.
func test_owner_walking_off_interrupts() -> void:
	var owner := _owner_near_tree()
	var dog: Dictionary = DOG.new_dog(Vector2(owner), 3)
	DOG.start_pee(dog, Vector2(owner))
	DOG.update(dog, Vector2(owner) + Vector2(DOG.WAKE_GAP + 4.0, 0), DT)
	assert_eq(dog["state"], "follow")
