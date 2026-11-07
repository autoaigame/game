## A player's dog: follows its owner and lives its life near them. Pure functions on a dog record, run
## by the server each tick (server only: the web build never loads this file). The dog moves like a
## player, through Protocol.step_towards, so it never stands on a non-walkable cell (invariant 2).
## States (sent to clients as its pose): follow, idle, sniff, sit, sleep, to_pee, pee, dig, hunt, fetch.
## update() returns events for the server: {kind: "pee" or "hole", pos} when it leaves a mark, and
## {kind: "deliver", carry} when it brings its catch to its owner.
## While hunting the server calls hunt() instead, which returns {kind: "catch", prey, pos}. The dog then
## fetches: the server sets its "carry" (the prey's kind) and the dog runs it back to its owner.
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

## Now and then, instead of sniffing, the dog pees on a tree (TREE_IDS) within PEE_RADIUS cells of its
## owner: it walks next to it and lifts its leg for PEE_S seconds. The wet mark lasts PEE_MARK_S.
const TREE_IDS: Array[String] = ["oak", "birch", "pine"]
const PEE_RADIUS := 4
const PEE_CHANCE := 0.3
const PEE_S := 2.0
const PEE_MARK_S := 60.0

## Now and then, instead of sniffing, the dog digs where it stands for DIG_S seconds, on natural
## ground (DIG_GROUNDS) with no object. The hole lasts HOLE_MARK_S.
const DIG_GROUNDS: Array[String] = ["grass", "dry_grass", "forest_floor", "packed_dirt", "sand"]
const DIG_CHANCE := 0.15
const DIG_S := 4.0
const HOLE_MARK_S := 180.0

## When its owner whistles, the dog runs after a wild animal within HUNT_RADIUS of its owner, at
## HUNT_SPEED (faster than any prey flees). It catches it within CATCH_DIST, and gives up after
## HUNT_MAX_S, when the prey is gone, or when it gets HUNT_LEASH far from its owner.
const HUNT_RADIUS := 12.0
const HUNT_SPEED := 9.0
const HUNT_LEASH := 30.0
const HUNT_MAX_S := 12.0
const CATCH_DIST := 0.6
## While hunting, the dog runs around obstacles: it follows the shortest walkable path (path_to) to
## the prey's cell, looking at most PATH_MAX_CELLS cells, and recomputes it when the prey changes cell.
## With no path found it runs straight at the prey.
const PATH_MAX_CELLS := 2048

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


## One tick of the dog near its owner at `owner_pos`, `dt` seconds. Returns its events (marks it left).
static func update(dog: Dictionary, owner_pos: Vector2, dt: float) -> Array:
	var events: Array = []
	var gap := (dog["pos"] as Vector2).distance_to(owner_pos)
	if gap <= LOST:
		dog.erase("returning")
	if gap > (HUNT_LEASH if dog.has("returning") else LOST) or dog["stuck"] >= STUCK_S:
		_put_back(dog, owner_pos)
		return events
	if dog["state"] == "fetch":
		_fetch(dog, owner_pos, gap, dt, events)
		return events
	_track_rest(dog, owner_pos, dt)
	_choose_state(dog, gap)
	match dog["state"]:
		"follow":
			_follow(dog, owner_pos, gap, dt)
		"sit", "sleep":
			dog["stuck"] = 0.0
			if dog["rest"] >= SLEEP_AFTER:
				dog["state"] = "sleep"
		"to_pee", "pee":
			dog["stuck"] = 0.0
			_pee(dog, dt, events)
		"dig":
			dog["stuck"] = 0.0
			_dig(dog, dt, events)
		_:
			dog["stuck"] = 0.0
			_awake_near(dog, owner_pos, dt)
	return events


## Sends the dog after the wild animal `prey_id`.
static func start_hunt(dog: Dictionary, prey_id: int) -> void:
	dog["state"] = "hunt"
	dog["prey"] = prey_id
	dog["hunt_left"] = HUNT_MAX_S
	dog["goal"] = null
	dog["stuck"] = 0.0
	dog.erase("path")


## One step of a hunt: runs to `prey_pos` (null if the prey is gone). Returns [{kind: "catch", prey,
## pos}] when it catches it; the dog then fetches it back to its owner. When it gives up, it follows
## its owner again.
static func hunt(dog: Dictionary, owner_pos: Vector2, prey_pos: Variant, dt: float) -> Array:
	dog["hunt_left"] -= dt
	if prey_pos == null or dog["hunt_left"] <= 0.0 or (dog["pos"] as Vector2).distance_to(owner_pos) > HUNT_LEASH:
		_end_hunt(dog)
		return []
	_run_to(dog, Protocol.cell_of(prey_pos), dt * HUNT_SPEED / Protocol.SPEED_CELLS_PER_S)
	if (dog["pos"] as Vector2).distance_to(prey_pos) > CATCH_DIST:
		return []
	var caught := {"kind": "catch", "prey": dog["prey"], "pos": prey_pos}
	_end_hunt(dog)
	dog["state"] = "fetch"
	return [caught]


## After a hunt the dog runs back to its owner (update() lets it be up to HUNT_LEASH away until then).
static func _end_hunt(dog: Dictionary) -> void:
	dog["state"] = "follow"
	dog["returning"] = true
	dog["rest"] = 0.0
	dog.erase("prey")
	dog.erase("path")


## Runs towards cell `target` along a walkable path (kept in dog["path"] while the target stays the
## same), for `dt` seconds at Protocol.SPEED_CELLS_PER_S. Straight at it when there is no path.
static func _run_to(dog: Dictionary, target: Vector2i, dt: float) -> void:
	var path: Variant = dog.get("path")
	if path == null or path["to"] != target:
		path = {"to": target, "cells": path_to(Protocol.cell_of(dog["pos"]), target)}
		dog["path"] = path
	var cells: Array = path["cells"]
	if cells.is_empty():
		dog["pos"] = Protocol.step_towards(dog["pos"], target, dt)
		return
	while dt > 0.0 and not cells.is_empty():
		var before: Vector2 = dog["pos"]
		dog["pos"] = Protocol.step_towards(before, cells[0], dt)
		if dog["pos"] != Vector2(cells[0]):
			if dog["pos"] == before:
				dog.erase("path")  # blocked: look for a new path next tick
			return
		dt -= before.distance_to(dog["pos"]) / Protocol.SPEED_CELLS_PER_S
		cells.pop_front()


## The cells of a shortest walkable path from `from` to `to` (8 directions, no corner cutting:
## Protocol.can_enter), without `from` and ending on `to`. Empty when `to` cannot be reached within
## PATH_MAX_CELLS visited cells, or when `from` == `to`.
static func path_to(from: Vector2i, to: Vector2i) -> Array:
	if from == to or not MapData.is_walkable(to):
		return []
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size() and came.size() < PATH_MAX_CELLS:
		var c := queue[head]
		head += 1
		for n in _NEIGHBOURS:
			var next := c + n
			if came.has(next) or not Protocol.can_enter(c, next):
				continue
			came[next] = c
			if next == to:
				var path := [to]
				while came[path[0]] != from:
					path.push_front(came[path[0]])
				return path
			queue.append(next)
	return []


## Runs its catch back to its owner, as fast as it follows, and hands it over once within
## FOLLOW_START of them. With nothing to carry (the server found no prey), it just follows.
static func _fetch(dog: Dictionary, owner_pos: Vector2, gap: float, dt: float, events: Array) -> void:
	if not dog.has("carry"):
		dog["state"] = "follow"
		return
	if gap <= FOLLOW_START:
		events.append({"kind": "deliver", "carry": dog["carry"]})
		dog.erase("carry")
		dog["state"] = "idle"
		dog["stuck"] = 0.0
		return
	_follow(dog, owner_pos, gap, dt)


## The nearest tree within PEE_RADIUS of `cell` (ties in a fixed order), or null.
static func tree_near(cell: Vector2i) -> Variant:
	var best: Variant = null
	var best_d := INF
	for dy in range(-PEE_RADIUS, PEE_RADIUS + 1):
		for dx in range(-PEE_RADIUS, PEE_RADIUS + 1):
			var d := Vector2(dx, dy).length()
			if d > PEE_RADIUS or d >= best_d:
				continue
			var c := cell + Vector2i(dx, dy)
			if MapData.object_at(c) in TREE_IDS:
				best = c
				best_d = d
	return best


## Sends the dog to pee on a tree near its owner; false if there is none it can stand next to.
static func start_pee(dog: Dictionary, owner_pos: Vector2) -> bool:
	var tree: Variant = tree_near(Protocol.cell_of(owner_pos))
	if tree == null:
		return false
	var spot := spot_near(tree, Protocol.cell_of(dog["pos"]))
	if spot == tree:
		return false
	dog["state"] = "to_pee"
	dog["tree"] = tree
	dog["goal"] = spot
	return true


## Whether the dog may dig on `cell`: natural ground (DIG_GROUNDS) with no object on it.
static func can_dig(cell: Vector2i) -> bool:
	return WorldData.tile(MapData.tile_at(cell))["id"] in DIG_GROUNDS and MapData.object_at(cell) == ""


## Starts digging where the dog stands; false if the ground there cannot be dug.
static func start_dig(dog: Dictionary) -> bool:
	if not can_dig(Protocol.cell_of(dog["pos"])):
		return false
	dog["state"] = "dig"
	dog["dig_left"] = DIG_S
	dog["goal"] = null
	return true


static func _dig(dog: Dictionary, dt: float, events: Array) -> void:
	dog["dig_left"] -= dt
	if dog["dig_left"] > 0.0:
		return
	events.append({"kind": "hole", "pos": dog["pos"]})
	dog["state"] = "idle"
	dog["wander_in"] = (dog["rng"] as RandomNumberGenerator).randf_range(WANDER_MIN_S, WANDER_MAX_S)


## Walks next to the tree, then lifts its leg for PEE_S and leaves a mark between it and the tree.
static func _pee(dog: Dictionary, dt: float, events: Array) -> void:
	if dog["state"] == "to_pee":
		var before: Vector2 = dog["pos"]
		var goal: Vector2i = dog["goal"]
		dog["pos"] = Protocol.step_towards(before, goal, dt)
		if dog["pos"] == Vector2(goal) or dog["pos"] == before:
			dog["state"] = "pee"
			dog["pee_left"] = PEE_S
		return
	dog["pee_left"] -= dt
	if dog["pee_left"] > 0.0:
		return
	var at: Vector2 = (dog["pos"] as Vector2).lerp(Vector2(dog["tree"]), 0.4)
	events.append({"kind": "pee", "pos": at})
	dog["state"] = "idle"
	dog["goal"] = null
	dog["wander_in"] = (dog["rng"] as RandomNumberGenerator).randf_range(WANDER_MIN_S, WANDER_MAX_S)


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
		"to_pee", "pee", "dig":
			if gap > WAKE_GAP:
				dog["state"] = "follow"
				dog["goal"] = null
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
	var roll := rng.randf()
	if roll < PEE_CHANCE and start_pee(dog, owner_pos):
		return
	if roll >= 1.0 - DIG_CHANCE and start_dig(dog):
		return
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
	dog["state"] = "fetch" if dog.has("carry") else "idle"
	dog["goal"] = null
	dog["stuck"] = 0.0
