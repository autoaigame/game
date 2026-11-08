## Smooth walking on screen: the in-between positions of a walker (player or creature) between server
## updates, and where a player's name goes. Pure functions, so tests can check them. Display only: the
## server still decides every position (docs/invariants.md, rule 1). A player's walk itself is drawn by
## client/character_3d.gd.
class_name WalkAnim
extends RefCounted

## The drawn player follows the last snapshot about FOLLOW_LAG_CELLS behind (just over a snapshot at
## walking speed), at the walking speed give or take FOLLOW_GAIN per FOLLOW_LAG_CELLS of difference,
## so it glides evenly instead of rushing to each snapshot and waiting for the next.
const FOLLOW_LAG_CELLS := 0.3
const FOLLOW_GAIN := 0.25
## Never slower than this multiple of the walking speed, so it still reaches a stopped player.
const FOLLOW_MIN := 0.5
## Never faster than this multiple of the walking speed, so it still catches up after a delay.
const CATCH_UP := 1.5
## Farther than this from the snapshot (spawn, reconnect, lost snapshots): jump there at once.
const SNAP_CELLS := 3.0


## Next drawn position, in cells: towards the server's position, never past it, faster the farther behind.
## `speed` is how fast the walker goes on the server, in cells per second (at least the walking speed):
## the lag it follows at and the gap it snaps from grow with it, so a fast runner glides too.
static func follow(shown: Vector2, server: Vector2, dt: float, speed := Protocol.SPEED_CELLS_PER_S) -> Vector2:
	var to_server := server - shown
	var dist := to_server.length()
	var factor := maxf(speed, Protocol.SPEED_CELLS_PER_S) / Protocol.SPEED_CELLS_PER_S
	if dist > SNAP_CELLS * factor:
		return server
	var lag := FOLLOW_LAG_CELLS * factor
	var pace := clampf(1.0 + FOLLOW_GAIN * (dist - lag) / lag, FOLLOW_MIN, CATCH_UP)
	var step := Protocol.SPEED_CELLS_PER_S * factor * pace * dt
	if step >= dist:
		return server
	return shown + to_server / dist * step


## A drawn walker: {"server": last snapshot position, "shown": drawn position, "speed": cells/s between
## its last two snapshots}, at `pos` (it appears there).
static func walker(pos: Vector2) -> Dictionary:
	return {"server": pos, "shown": pos, "speed": 0.0}


## A new snapshot of a walker, one server tick after the previous one: where to go and how fast it went,
## so a sprinter (Protocol.SPRINT_FACTOR) is drawn as smoothly as a walker.
static func snapshot(w: Dictionary, pos: Vector2) -> void:
	w["speed"] = speed_between(w["server"], pos)
	w["server"] = pos


## Draws a walker dt seconds later (follow at its measured speed). Returns the new drawn position.
static func advance(w: Dictionary, dt: float) -> Vector2:
	w["shown"] = follow(w["shown"], w["server"], dt, w["speed"])
	return w["shown"]


## How fast a walker went between two updates one server tick apart, in cells per second. A jump (a
## put-back, a lost update) reads as very fast, which follow() turns into a snap.
static func speed_between(before: Vector2, after: Vector2) -> float:
	return before.distance_to(after) * Protocol.TICK_HZ


## The top of a player's head is at most this many px above the feet: the name is drawn just above it.
const HEAD_PX := 105
const NAME_GAP_PX := 4
const NAME_SIZE := Vector2(240, 24)


## Where the name label goes, relative to the feet.
static func name_rect() -> Rect2:
	return Rect2(Vector2(-NAME_SIZE.x / 2.0, -HEAD_PX - NAME_GAP_PX - NAME_SIZE.y), NAME_SIZE)
