extends TestCase

## Whistling sends the dog after the nearest wild animal; it catches it and brings it back to its
## owner, whose bag gets the raw meat (server/dog.gd, server/server.gd).

const DOG := preload("res://server/dog.gd")
const WILD := preload("res://server/wildlife.gd")
const SERVER_SCRIPT := "res://server/server.gd"


## A grassland cell with open walkable ground around it (radius r).
func _meadow(r := 6) -> Vector2i:
	var want := WorldData.biome_index("grassland")
	var s := MapData.spawn_cell()
	for ring in 300:
		for dx in range(-ring, ring + 1, 4):
			for dy in [-ring, ring]:
				var c := s + Vector2i(dx, dy)
				if Terrain.biome(c.x, c.y) != want:
					continue
				var open := true
				for y in range(-r, r + 1):
					for x in range(-r, r + 1):
						var o := c + Vector2i(x, y)
						if not MapData.is_walkable(o) or MapData.object_at(o) != "":
							open = false
				if open:
					return c
	return s


func test_runs_faster_than_any_prey() -> void:
	for id in WILD.species():
		assert_true(DOG.HUNT_SPEED > WILD.species()[id]["flee_speed"], "outruns a %s" % id)


func test_catches_still_prey() -> void:
	var at := Vector2(_meadow())
	var dog := DOG.new_dog(at)
	DOG.start_hunt(dog, -7)
	assert_eq(dog["state"], "hunt")
	var prey := at + Vector2(3, 0)
	var events := []
	for i in 30:
		events = DOG.hunt(dog, at, prey, 1.0 / 15.0)
		if not events.is_empty():
			break
	assert_eq(events.size(), 1, "caught it")
	assert_eq(events[0]["kind"], "catch")
	assert_eq(events[0]["prey"], -7)
	assert_true(events[0]["pos"].distance_to(prey) <= DOG.CATCH_DIST + 0.01)
	assert_eq(dog["state"], "fetch", "brings it back")


func test_gives_up_when_prey_is_gone() -> void:
	var at := Vector2(_meadow())
	var dog := DOG.new_dog(at)
	DOG.start_hunt(dog, -1)
	assert_eq(DOG.hunt(dog, at, null, 0.1), [])
	assert_eq(dog["state"], "follow")


func test_gives_up_after_a_while() -> void:
	var at := Vector2(_meadow())
	var dog := DOG.new_dog(at)
	DOG.start_hunt(dog, -1)
	var far := at + Vector2(500, 0)  # out of reach; the owner keeps up, so only time ends it
	for i in int(DOG.HUNT_MAX_S * 10) - 2:
		DOG.hunt(dog, dog["pos"], far, 0.1)
	assert_eq(dog["state"], "hunt", "still running")
	for i in 4:
		DOG.hunt(dog, dog["pos"], far, 0.1)
	assert_eq(dog["state"], "follow")


func test_gives_up_far_from_its_owner() -> void:
	var at := Vector2(_meadow())
	var dog := DOG.new_dog(at)
	DOG.start_hunt(dog, -1)
	DOG.hunt(dog, at + Vector2(DOG.HUNT_LEASH + 1, 0), at + Vector2(1, 0), 0.1)
	assert_eq(dog["state"], "follow")


func _server_with_rabbit(offset: Vector2i) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	var at := _meadow()
	server._players[1] = server._new_player("ann", at, {})
	server._players[1]["dog"]["pos"] = Vector2(at)
	WILD.add(server._wild, "rabbit", Vector2(at + offset))
	return server


func test_whistle_sends_the_dog_after_the_nearest_animal() -> void:
	var server := _server_with_rabbit(Vector2i(5, 0))
	var near: int = server._wild["next_id"] + 1
	WILD.add(server._wild, "rabbit", Vector2(Protocol.cell_of(server._players[1]["pos"]) + Vector2i(-6, 6)))
	assert_eq(server._whistle(1), {"notice": "hunt"})
	assert_eq(server._players[1]["dog"]["state"], "hunt")
	assert_eq(server._players[1]["dog"]["prey"], near)
	server.free()


func test_whistle_with_nothing_near() -> void:
	var server := _server_with_rabbit(Vector2i(DOG.HUNT_RADIUS + 3, 0))
	assert_eq(server._whistle(1), {"notice": "no_prey"})
	assert_true(server._players[1]["dog"]["state"] != "hunt")
	assert_eq(server._whistle(2), {}, "unknown player")
	server.free()


## A whole chase: the rabbit flees, the dog catches it and carries it back to its owner, whose bag
## gets its raw meat. Nothing is left on the ground.
func test_chase_ends_with_meat_in_the_bag() -> void:
	var server := _server_with_rabbit(Vector2i(5, 0))
	var owner: Vector2 = server._players[1]["pos"]
	server._whistle(1)
	var told := []
	var carried := false
	for i in int((DOG.HUNT_MAX_S + 6.0) * Protocol.TICK_HZ):
		told.append_array(server._move_dogs(1.0 / Protocol.TICK_HZ))
		WILD.update(server._wild, server._threats(), 1.0 / Protocol.TICK_HZ)
		carried = carried or server._players[1]["dog"]["state"] == "fetch"
		if not told.is_empty():
			break
	assert_eq(server._wild["animals"].size(), 0, "rabbit caught")
	assert_true(carried, "carried it back")
	assert_eq(told, [[1, {"notice": "gathered", "item": "raw_meat", "count": 2}]])
	assert_eq(server._players[1]["inventory"], {"raw_meat": 2})
	assert_true(server._players[1]["dog"]["pos"].distance_to(owner) <= DOG.FOLLOW_START, "brought to its owner")
	assert_false(server._players[1]["dog"].has("carry"), "no longer carries it")
	assert_eq(server.MARKS.snapshot(server._marks), [], "nothing left on the ground")
	server.free()


## The dog runs back with its catch even when its owner walks away, and drops it once by them.
func test_fetch_follows_a_walking_owner() -> void:
	var at := Vector2(_meadow(8))
	var dog := DOG.new_dog(at + Vector2(6, 0))
	dog["state"] = "fetch"
	dog["carry"] = "rabbit"
	var owner := at
	var events := []
	for i in 60:
		owner += Vector2(0, 0.05)
		events = DOG.update(dog, owner, 0.1)
		if not events.is_empty():
			break
	assert_eq(events, [{"kind": "deliver", "carry": "rabbit"}])
	assert_true(dog["pos"].distance_to(owner) <= DOG.FOLLOW_START)
	assert_true(dog["state"] != "fetch")
	assert_false(dog.has("carry"))


## Put back next to its owner (stuck or lost), the dog still has its catch and hands it over.
func test_fetch_survives_a_put_back() -> void:
	var at := Vector2(_meadow(8))
	var dog := DOG.new_dog(at + Vector2(6, 0))
	dog["state"] = "fetch"
	dog["carry"] = "pheasant"
	dog["stuck"] = DOG.STUCK_S
	assert_eq(DOG.update(dog, at, 0.1), [], "put back")
	assert_eq(dog["carry"], "pheasant")
	assert_eq(DOG.update(dog, at, 0.1), [{"kind": "deliver", "carry": "pheasant"}])


## With a full stack of raw meat, the catch is dropped at the owner's feet instead (picked up later).
func test_catch_dropped_when_bag_is_full() -> void:
	var server := _server_with_rabbit(Vector2i(30, 0))
	server._players[1]["inventory"] = {"raw_meat": server.INV.MAX_STACK}
	server._players[1]["dog"]["carry"] = "rabbit"
	server._players[1]["dog"]["state"] = "fetch"
	var told: Array = server._move_dogs(1.0 / Protocol.TICK_HZ)
	assert_eq(told, [[1, {"notice": "bag_full"}]])
	var kinds: Array = server.MARKS.snapshot(server._marks).map(func(m): return m["kind"])
	assert_eq(kinds, ["carcass_rabbit"])
	assert_eq(server._players[1]["inventory"], {"raw_meat": server.INV.MAX_STACK})
	server.free()


## The dog's carried catch is sent to clients, so they draw it in its mouth.
func test_carried_catch_is_sent() -> void:
	var server := _server_with_rabbit(Vector2i(30, 0))
	server._players[1]["dog"]["carry"] = "rabbit"
	var dogs: Array = server._creatures_for(1).filter(func(c): return c["kind"] == "dog")
	assert_eq(dogs[0].get("carry"), "rabbit")
	server._players[1]["dog"].erase("carry")
	dogs = server._creatures_for(1).filter(func(c): return c["kind"] == "dog")
	assert_false(dogs[0].has("carry"))
	server.free()


## After a hunt far away, the dog runs back to its owner instead of appearing next to them.
func test_runs_back_after_a_hunt() -> void:
	var at := Vector2(_meadow(8))
	var dog := DOG.new_dog(at + Vector2(7, 0))
	DOG.start_hunt(dog, -1)
	var owner := at + Vector2(-DOG.LOST + 1.0, 0)  # the dog is LOST + 6 away
	DOG.hunt(dog, owner, null, 0.1)
	var before: float = dog["pos"].distance_to(owner)
	assert_true(before > DOG.LOST, "far")
	DOG.update(dog, owner, 0.2)
	var after: float = dog["pos"].distance_to(owner)
	assert_true(after < before and after > before - 3.0, "ran closer, did not jump: %f -> %f" % [before, after])
	for i in 40:
		DOG.update(dog, owner, 0.1)
	assert_true(dog["pos"].distance_to(owner) < DOG.FOLLOW_START + 1.0, "back by its owner")


## While the dog carries a catch, a whistle does not send it off again: the catch is never lost.
func test_no_new_hunt_while_carrying() -> void:
	var server := _server_with_rabbit(Vector2i(5, 0))
	server._players[1]["dog"]["state"] = "fetch"
	server._players[1]["dog"]["carry"] = "pheasant"
	assert_eq(server._whistle(1), {"notice": "dog_busy"})
	assert_eq(server._players[1]["dog"]["state"], "fetch")
	assert_eq(server._players[1]["dog"]["carry"], "pheasant")
	assert_true(UiText.notice("dog_busy", {}) != "", "the player is told why")
	server.free()


## Every wild animal the dog can catch gives raw meat when it brings it back.
func test_every_species_gives_meat() -> void:
	for id in WILD.species():
		assert_true(load(SERVER_SCRIPT).MEAT.get("carcass_" + id, 0) > 0, "%s gives meat" % id)
