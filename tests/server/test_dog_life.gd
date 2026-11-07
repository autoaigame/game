extends TestCase

## The dog's life near its owner: sniffing around, sitting, sleeping, waking up (server/dog.gd).

const DOG := preload("res://server/dog.gd")
const DT := 1.0 / 15.0


func _dog(at: Vector2, seed_value := 7) -> Dictionary:
	var dog: Dictionary = DOG.new_dog(at + Vector2(1, 0), seed_value)
	return dog


func _run(dog: Dictionary, owner: Vector2, seconds: float) -> Array:
	var states := []
	for i in int(seconds / DT):
		DOG.update(dog, owner, DT)
		assert_true(MapData.is_walkable(Protocol.cell_of(dog["pos"])), "dog on a walkable cell")
		states.append(dog["state"])
	return states


## With its owner standing still, the dog sits, then falls asleep, and does not move while it does.
func test_sits_then_sleeps_near_a_still_owner() -> void:
	var owner := Vector2(MapData.spawn_cell())
	var dog := _dog(owner)
	_run(dog, owner, DOG.SIT_AFTER - 0.5)
	assert_true(dog["state"] in ["idle", "sniff"], "awake at first: %s" % dog["state"])
	_run(dog, owner, 1.5)
	assert_eq(dog["state"], "sit")
	var at: Vector2 = dog["pos"]
	_run(dog, owner, DOG.SLEEP_AFTER - DOG.SIT_AFTER)
	assert_eq(dog["state"], "sleep")
	assert_true(dog["pos"].distance_to(owner) <= DOG.WANDER_RADIUS + 1.5, "sleeps near its owner")
	var asleep_at: Vector2 = dog["pos"]
	_run(dog, owner, 10.0)
	assert_eq(dog["pos"], asleep_at, "does not move while asleep")
	assert_true(at.distance_to(owner) <= DOG.WANDER_RADIUS + 1.5)


## Awake near its owner, the dog sniffs around: it walks to spots near its owner, never far.
func test_sniffs_around_near_its_owner() -> void:
	var owner := Vector2(MapData.spawn_cell())
	var sniffed := 0
	for seed_value in 6:
		var dog := _dog(owner, seed_value)
		var states := _run(dog, owner, DOG.SIT_AFTER - 0.5)
		if states.has("sniff"):
			sniffed += 1
		assert_true(dog["pos"].distance_to(owner) <= DOG.PEE_RADIUS + 1.5, "stayed near: %s" % dog["pos"])
	assert_true(sniffed >= 3, "most dogs sniffed around: %d of 6" % sniffed)


## An owner pottering about in a small area still counts as staying: the dog ends up asleep.
func test_sleeps_while_owner_stays_in_an_area() -> void:
	var base := Vector2(MapData.spawn_cell())
	var dog := _dog(base)
	var t := 0.0
	while t < DOG.SLEEP_AFTER + 2.0:
		var owner := base + Vector2(sin(t * 0.5) * 2.0, 0.0)  # within the area
		DOG.update(dog, owner, DT)
		t += DT
	assert_eq(dog["state"], "sleep")


## The sleeping dog wakes up and follows when its owner walks off.
func test_wakes_up_and_follows_when_owner_leaves() -> void:
	var owner := Vector2(MapData.spawn_cell())
	var dog := _dog(owner)
	_run(dog, owner, DOG.SLEEP_AFTER + 1.0)
	assert_eq(dog["state"], "sleep")
	var away := owner + Vector2(0, DOG.AREA_RADIUS + 3.0)
	DOG.update(dog, away, DT)
	assert_eq(dog["state"], "follow")
	_run(dog, away, 4.0)
	assert_true(dog["pos"].distance_to(away) <= DOG.FOLLOW_START + 0.5, "caught up")
	assert_true(dog["state"] != "sleep", "awake")


## The same seed gives the same life (the server's randomness is reproducible in tests).
func test_same_seed_same_life() -> void:
	var owner := Vector2(MapData.spawn_cell())
	var a := _dog(owner, 42)
	var b := _dog(owner, 42)
	assert_eq(_run(a, owner, 12.0), _run(b, owner, 12.0))
	assert_eq(a["pos"], b["pos"])


func test_state_is_sent_to_clients() -> void:
	var server: Node = load("res://server/server.gd").new()
	var at := Vector2(MapData.spawn_cell())
	server._players[1] = {"name": "ann", "pos": at, "target": Protocol.cell_of(at), "stopped": false, "dog": _dog(at)}
	server._players[1]["dog"]["state"] = "sleep"
	assert_eq(server._creatures_for(1)[0]["state"], "sleep")
	server.free()
