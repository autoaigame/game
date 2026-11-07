## A player's dog: walks after its owner. Pure functions on a dog record, run by the server each tick
## (server only: the web build never loads this file). The dog moves like a player, through
## Protocol.step_towards, so it never stands on a non-walkable cell (invariant 2).
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

const _NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


## A new dog at `pos` (cells).
static func new_dog(pos: Vector2) -> Dictionary:
	return {"pos": pos, "following": false, "stuck": 0.0}


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


## One tick of the dog after its owner at `owner_pos`, `dt` seconds.
static func update(dog: Dictionary, owner_pos: Vector2, dt: float) -> void:
	var pos: Vector2 = dog["pos"]
	var gap := pos.distance_to(owner_pos)
	if gap > LOST or dog["stuck"] >= STUCK_S:
		_put_back(dog, owner_pos)
		return
	if dog["following"] and gap <= FOLLOW_STOP:
		dog["following"] = false
	elif not dog["following"] and gap > FOLLOW_START:
		dog["following"] = true
	if not dog["following"]:
		dog["stuck"] = 0.0
		return
	var owner_cell := Protocol.cell_of(owner_pos)
	var target := spot_near(owner_cell, Protocol.cell_of(pos))
	var speed := RUN_SPEED if gap > RUN_FROM else Protocol.SPEED_CELLS_PER_S
	dog["pos"] = Protocol.step_towards(pos, target, dt * speed / Protocol.SPEED_CELLS_PER_S)
	if dog["pos"] == Vector2(target):
		dog["stuck"] = 0.0  # arrived: waiting for its owner is not being stuck
	else:
		track_progress(dog, pos, owner_pos, dt)


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
	dog["following"] = false
	dog["stuck"] = 0.0
