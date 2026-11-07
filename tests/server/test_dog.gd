extends TestCase

## Each player has a dog that follows them (server/dog.gd, server/server.gd). Invariants 1 and 2.

const SERVER_SCRIPT := "res://server/server.gd"
const DOG := preload("res://server/dog.gd")
const DT := 1.0 / 15.0


func _server(owner_pos: Vector2, dog_pos: Vector2) -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = {"name": "ann", "pos": owner_pos, "target": Protocol.cell_of(owner_pos), "stopped": false,
			"dog": DOG.new_dog(dog_pos)}
	return server


func _dog(server: Node) -> Dictionary:
	return server._players[1]["dog"]


## A meadow cell with walkable cells all around (the spawn area).
func _open_cell() -> Vector2i:
	return MapData.spawn_cell()


func test_new_dog_stands_next_to_its_owner() -> void:
	var at := _open_cell()
	var dog: Dictionary = DOG.new_dog(Vector2(DOG.spot_near(at, at + Vector2i(1, 1))))
	var cell := Protocol.cell_of(dog["pos"])
	assert_true(MapData.is_walkable(cell), "dog on a walkable cell")
	assert_true(cell != at and (cell - at).abs().x <= 1 and (cell - at).abs().y <= 1, "next to its owner: %s" % cell)


## Close to its owner, the dog does not follow (it may sniff around nearby).
func test_dog_stays_when_owner_is_close() -> void:
	var at := Vector2(_open_cell())
	var server := _server(at, at + Vector2(1, 0))
	for i in 30:
		server._move_dogs(DT)
		assert_true(_dog(server)["state"] != "follow", "does not follow a close owner")
	assert_true(_dog(server)["pos"].distance_to(at) <= DOG.WANDER_RADIUS + 1.5, "stays near")
	server.free()


## When its owner walks away, the dog follows and stays close, always on walkable cells.
func test_dog_follows_its_walking_owner() -> void:
	var start := _open_cell()
	var server := _server(Vector2(start), Vector2(start) + Vector2(1, 0))
	server._players[1]["target"] = start + Vector2i(0, 10)
	var max_gap := 0.0
	for i in 15 * 6:
		server._move_players(DT)
		server._move_dogs(DT)
		var pos: Vector2 = _dog(server)["pos"]
		assert_true(MapData.is_walkable(Protocol.cell_of(pos)), "dog on a walkable cell at %s" % pos)
		max_gap = maxf(max_gap, pos.distance_to(server._players[1]["pos"]))
	var gap: float = _dog(server)["pos"].distance_to(server._players[1]["pos"])
	assert_true(gap <= DOG.FOLLOW_START + 0.5, "dog close after the walk: %s cells" % gap)
	assert_true(max_gap < DOG.LOST, "never lost on the way: %s cells" % max_gap)
	server.free()


## Far behind, the dog runs faster than a walking player, so it catches up.
func test_dog_runs_to_catch_up() -> void:
	var at := Vector2(_open_cell())
	var server := _server(at, at + Vector2(0, 6))
	var before: Vector2 = _dog(server)["pos"]
	server._move_dogs(0.25)
	var ran: float = before.distance_to(_dog(server)["pos"])
	assert_true(ran > Protocol.SPEED_CELLS_PER_S * 0.25 + 0.01, "ran %s cells in 0.25 s" % ran)
	server.free()


## A dog left far behind (its owner was moved far away) comes back next to its owner.
func test_lost_dog_comes_back() -> void:
	var at := _open_cell()
	var server := _server(Vector2(at), Vector2(at) + Vector2(DOG.LOST + 5, 0))
	server._move_dogs(DT)
	var cell := Protocol.cell_of(_dog(server)["pos"])
	assert_true((cell - at).abs().x <= 1 and (cell - at).abs().y <= 1, "back next to its owner: %s" % cell)
	assert_true(MapData.is_walkable(cell))
	server.free()


## A dog that cannot get closer (blocked) is put back next to its owner after a while.
func test_stuck_dog_is_put_back() -> void:
	var at := _open_cell()
	var dog: Dictionary = DOG.new_dog(Vector2(at) + Vector2(5, 0))
	var owner := Vector2(at)
	# Pretend every step is blocked: call update with the dog unable to move.
	for i in int(DOG.STUCK_S * 15) + 2:
		DOG.track_progress(dog, dog["pos"], owner, DT)
	assert_true(dog["stuck"] >= DOG.STUCK_S, "counted as stuck")
	DOG.update(dog, owner, DT)
	var cell := Protocol.cell_of(dog["pos"])
	assert_true((cell - at).abs().x <= 1 and (cell - at).abs().y <= 1, "put back next to its owner: %s" % cell)


## Every player's dog goes out to clients as a creature, with its owner.
func test_dogs_are_sent_as_creatures() -> void:
	var at := Vector2(_open_cell())
	var server := _server(at, at + Vector2(1, 0))
	var list: Array = server._creature_snapshot()
	assert_eq(list.size(), 1)
	assert_eq(list[0]["kind"], "dog")
	assert_eq(list[0]["owner"], 1)
	assert_eq(list[0]["pos"], at + Vector2(1, 0))
	server.free()
