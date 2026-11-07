## A player's dog: follows its owner and lives its life near them. Pure functions on a dog record, run
## by the server each tick (server only: the web build never loads this file). The dog moves like a
## player, through Protocol.step_towards, so it never stands on a non-walkable cell (invariant 2).
## States (sent to clients as its pose): follow, idle, sniff, sit, sleep.
extends RefCounted

## The dog starts after its owner farther than this, in cells, and stops once within FOLLOW_STOP.
const FOLLOW_START := 2.5
const FOLLOW_STOP := 1.5
## Farther than RUN_FROM cells, the dog runs at RUN_SPEED cells per second to catch up.
const RUN_FROM := 4.0
const RUN_SPEED := 6.5
## Farther than this, or stuck this long, the dog is put back next to its owner.
const LOST := 14.0
const STUCK_S := 2.0
## Moving less than this per second while following counts as stuck.
const STUCK_SPEED := 0.2

## The owner "stays" while within AREA_RADIUS cells of where they settled. After SIT_AFTER seconds
## of that, the dog sits; after SLEEP_AFTER, it sleeps. A resting dog wakes up when its owner leaves
## the area or is farther than WAKE_GAP cells.
const AREA_RADIUS := 4.0
const SIT_AFTER := 8.0
const SLEEP_AFTER := 25.0
const WAKE_GAP := 6.0
## Awake near its owner, the dog sniffs around a spot within WANDER_RADIUS cells of them, every
## WANDER_MIN_S to WANDER_MAX_S seconds, at SNIFF_SPEED cells per second.
const WANDER_RADIUS := 3
const WANDER_MIN_S := 1.5
const WANDER_MAX_S := 4.0
const SNIFF_SPEED := 2.0

const _NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


## A new dog at `pos` (cells). `seed_value` seeds its randomness (where it sniffs, and when).
static func new_dog(pos: Vector2, seed_value := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {"pos": pos, "state": "idle", "stuck": 0.0, "rest": 0.0, "anchor": null, "goal": null,
			"wander_in": rng.randf_range(WANDER_MIN_S, WANDER_MAX_S), "rng": rng}


## The walkable cell next to `owner` nearest to `from` (ties in a fixed order), or `owner` itself.
static func spot_near(owner: Vector2i, from: Vector2i) -> Vector2i:
	var best := owner
	var best_d := INF
	for n in _NEIGHBOURS:
		var c := owner + n
		if not MapData.is_walkable(c):
			continue
		var d := Vector2(c - from).length_squared()
		if d < best_d:
			best = c
			best_d = d
	return best


## One tick of the dog near its owner at `owner_pos`, `dt` seconds.
static func update(dog: Dictionary, owner_pos: Vector2, dt: float) -> void:
	var gap := (dog["pos"] as Vector2).distance_to(owner_pos)
	if gap > LOST or dog["stuck"] >= STUCK_S:
		_put_back(dog, owner_pos)
		return
	_track_rest(dog, owner_pos, dt)
	_choose_state(dog, gap)
	match dog["state"]:
		"follow":
			_follow(dog, owner_pos, gap, dt)
		"sit", "sleep":
			dog["stuck"] = 0.0
			if dog["rest"] >= SLEEP_AFTER:
				dog["state"] = "sleep"
		_:
			dog["stuck"] = 0.0
			_awake_near(dog, owner_pos, dt)


## Counts how long the owner has stayed within AREA_RADIUS of where they settled.
static func _track_rest(dog: Dictionary, owner_pos: Vector2, dt: float) -> void:
	if dog["anchor"] == null or owner_pos.distance_to(dog["anchor"]) > AREA_RADIUS:
		dog["anchor"] = owner_pos
		dog["rest"] = 0.0
	else:
		dog["rest"] += dt


static func _choose_state(dog: Dictionary, gap: float) -> void:
	match dog["state"]:
		"follow":
			if gap <= FOLLOW_STOP:
				dog["state"] = "idle"
		"sit", "sleep":
			if gap > WAKE_GAP or dog["rest"] == 0.0:
				dog["state"] = "follow" if gap > FOLLOW_START else "idle"
		_:
			if gap > FOLLOW_START:
				dog["state"] = "follow"
				dog["goal"] = null


static func _follow(dog: Dictionary, owner_pos: Vector2, gap: float, dt: float) -> void:
	var pos: Vector2 = dog["pos"]
	var target := spot_near(Protocol.cell_of(owner_pos), Protocol.cell_of(pos))
	var speed := RUN_SPEED if gap > RUN_FROM else Protocol.SPEED_CELLS_PER_S
	dog["pos"] = Protocol.step_towards(pos, target, dt * speed / Protocol.SPEED_CELLS_PER_S)
	if dog["pos"] == Vector2(target):
		dog["stuck"] = 0.0  # arrived: waiting for its owner is not being stuck
	else:
		track_progress(dog, pos, owner_pos, dt)


## Idle or sniffing near its owner: settles down after a while, otherwise sniffs around now and then.
static func _awake_near(dog: Dictionary, owner_pos: Vector2, dt: float) -> void:
	if dog["rest"] >= SIT_AFTER:
		dog["state"] = "sleep" if dog["rest"] >= SLEEP_AFTER else "sit"
		dog["goal"] = null
		return
	var rng: RandomNumberGenerator = dog["rng"]
	if dog["state"] == "sniff":
		var before: Vector2 = dog["pos"]
		var goal: Vector2i = dog["goal"]
		dog["pos"] = Protocol.step_towards(before, goal, dt * SNIFF_SPEED / Protocol.SPEED_CELLS_PER_S)
		if dog["pos"] == Vector2(goal) or dog["pos"] == before:
			dog["state"] = "idle"
			dog["goal"] = null
			dog["wander_in"] = rng.randf_range(WANDER_MIN_S, WANDER_MAX_S)
		return
	dog["wander_in"] -= dt
	if dog["wander_in"] > 0.0:
		return
	dog["wander_in"] = rng.randf_range(WANDER_MIN_S, WANDER_MAX_S)
	var owner_cell := Protocol.cell_of(owner_pos)
	for i in 8:
		var c := owner_cell + Vector2i(rng.randi_range(-WANDER_RADIUS, WANDER_RADIUS),
				rng.randi_range(-WANDER_RADIUS, WANDER_RADIUS))
		if MapData.is_walkable(c) and c != Protocol.cell_of(dog["pos"]):
			dog["goal"] = c
			dog["state"] = "sniff"
			return


## Counts the time the following dog has not got closer to its owner (it was at `before`).
static func track_progress(dog: Dictionary, before: Vector2, owner_pos: Vector2, dt: float) -> void:
	var gained := before.distance_to(owner_pos) - (dog["pos"] as Vector2).distance_to(owner_pos)
	var moved := before.distance_to(dog["pos"])
	if moved < STUCK_SPEED * dt and gained <= 0.0:
		dog["stuck"] += dt
	else:
		dog["stuck"] = 0.0


static func _put_back(dog: Dictionary, owner_pos: Vector2) -> void:
	var owner_cell := Protocol.cell_of(owner_pos)
	dog["pos"] = Vector2(spot_near(owner_cell, Protocol.cell_of(dog["pos"])))
	dog["state"] = "idle"
	dog["goal"] = null
	dog["stuck"] = 0.0
