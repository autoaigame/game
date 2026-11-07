## Smooth walking on screen: in-between positions and the walk cycle. Pure functions, so tests can
## check them. Display only: the server still decides every position (docs/invariants.md, rule 1).
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
## The drawn player catches up with each snapshot before the next one arrives, then waits for it: a
## walker counts as stopped only after standing still this long (over two snapshot intervals, plus
## network jitter), so the standing pose never flashes between walk frames.
const STOP_GRACE_S := 0.15
## Standing still, the idle rows play at this many frames per second.
const IDLE_FPS := 4.0


## Next drawn position, in cells: towards the server's position, never past it, faster the farther behind.
static func follow(shown: Vector2, server: Vector2, dt: float) -> Vector2:
	var to_server := server - shown
	var dist := to_server.length()
	if dist > SNAP_CELLS:
		return server
	var pace := clampf(1.0 + FOLLOW_GAIN * (dist - FOLLOW_LAG_CELLS) / FOLLOW_LAG_CELLS, FOLLOW_MIN, CATCH_UP)
	var step := Protocol.SPEED_CELLS_PER_S * pace * dt
	if step >= dist:
		return server
	return shown + to_server / dist * step


## Facings, defined on screen, in the order and with the names of PixelLab's 8 directions.
const FACINGS: Array[String] = ["south", "south-east", "east", "north-east", "north", "north-west", "west",
		"south-west"]
## Past the edge of its sector, a facing holds for this many more degrees, so drawn positions landing a
## hair either side of a direction never flicker between two facings.
const FACING_HYSTERESIS_DEG := 10.0

## Player sprite sheet (assets/player.png, from the PixelLab kit): one FRAME_SIZE frame per column and
## row. Columns: the 8 facings in FACINGS order. Rows: IDLE_FRAMES idle frames, then WALK_FRAMES walk
## frames (one cycle of two steps). Idle and walk were posed on the same skeleton, at the same size.
const FRAME_SIZE := Vector2i(128, 128)
const SHEET_COLUMNS := 8
const FACING_COLUMN: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const IDLE_FRAMES := 4
const WALK_FRAMES := 8
const WALK_FIRST_ROW := IDLE_FRAMES
const SHEET_ROWS := IDLE_FRAMES + WALK_FRAMES
## The feet stand this many px above the bottom of a frame, horizontally centred.
const FOOT_PX := 14
## The top of the head is at most this many px above the feet: the name is drawn just above it.
const HEAD_PX := 105
## Walk frames with both feet on the ground, side by side: a walk starts and ends on one of them.
const REST_FRAMES: Array[int] = [0, 4]
## One walk cycle (two steps) per this many cells walked, per facing (FACINGS order): the stride drawn
## on the sheet, measured on screen through the game's projection, plus up to 10 % (ASSETS.toml). The
## sprite's own perspective flattens depth more than the 2:1 view, so north and south take shorter
## cycles than east and west.
const CYCLE_CELLS: Array[float] = [0.85, 1.35, 1.1, 1.35, 0.85, 1.35, 1.1, 1.35]
## A turn of more than one sector shows each facing in between for this long.
const TURN_STEP_S := 0.05
const NAME_GAP_PX := 4
const NAME_SIZE := Vector2(240, 24)


## Offset of a non-centred sprite that puts the feet on the node's position.
static func sprite_offset() -> Vector2:
	return Vector2(-FRAME_SIZE.x / 2.0, FOOT_PX - FRAME_SIZE.y)


## Where the name label goes, relative to the feet.
static func name_rect() -> Rect2:
	return Rect2(Vector2(-NAME_SIZE.x / 2.0, -HEAD_PX - NAME_GAP_PX - NAME_SIZE.y), NAME_SIZE)


## Facing (index in FACINGS) from a screen movement. Angles are measured with the screen's height doubled,
## so the 2:1 view counts as flat: grid axes fall at 45 degrees, in the middle of their sector like the
## pure screen directions. previous: the facing last frame (-1: none); kept within the hysteresis margin,
## and when nothing moved.
static func facing(screen_delta: Vector2, previous: int = -1) -> int:
	if screen_delta == Vector2.ZERO:
		return maxi(previous, 0)
	var deg := rad_to_deg(atan2(-screen_delta.y * 2.0, screen_delta.x))  # counter-clockwise from east
	if previous >= 0 and absf(angle_difference(deg_to_rad(deg), deg_to_rad(_facing_deg(previous)))) \
			<= deg_to_rad(22.5 + FACING_HYSTERESIS_DEG):
		return previous
	return posmod(roundi((deg + 90.0) / 45.0), FACINGS.size())


## Centre of a facing's sector, in degrees counter-clockwise from east (south is -90).
static func _facing_deg(f: int) -> float:
	return -90.0 + 45.0 * f


## Sprite sheet column for a facing.
static func sheet_column(f: int) -> int:
	return FACING_COLUMN[f]


## Drawing state of a player standing at pos (cells): server and shown positions, walk phase (cycles,
## 0..1), facing shown and heading (FACINGS index, -1: none yet), time since the last turn step, time
## still and time standing (s).
static func new_state(pos: Vector2) -> Dictionary:
	return {"server": pos, "shown": pos, "phase": 0.0, "facing": -1, "heading": -1, "turn_t": TURN_STEP_S,
			"still": STOP_GRACE_S, "idle_t": 0.0}


## Updates w (see new_state) for a frame of dt seconds. Returns the sheet frame to draw.
## Walking: the phase follows the distance at the heading's CYCLE_CELLS. Stopped: the step in progress
## finishes at walking pace up to a feet-together frame, which holds until the stop is sure, then the
## idle rows start. Turning: the facing shown moves one sector per TURN_STEP_S towards the heading.
static func animate(w: Dictionary, dt: float) -> Vector2i:
	var before: Vector2 = w["shown"]
	w["shown"] = follow(before, w["server"], dt)
	var moved: float = (w["shown"] - before).length()
	if moved > 0.0:
		var screen := IsoLayer.cell_to_local(w["shown"]) - IsoLayer.cell_to_local(before)
		w["heading"] = facing(screen, w["heading"])
		w["phase"] = fposmod(w["phase"] + moved / CYCLE_CELLS[w["heading"]], 1.0)
		w["still"] = 0.0
	else:
		w["still"] += dt
		if w["heading"] >= 0:
			w["phase"] = finish_step(w["phase"], Protocol.SPEED_CELLS_PER_S / CYCLE_CELLS[w["heading"]] * dt)
	_turn(w, dt)
	var standing: bool = w["still"] >= STOP_GRACE_S and walk_frame(w["phase"]) in REST_FRAMES
	if not standing:
		w["idle_t"] = 0.0
		return Vector2i(sheet_column(maxi(w["facing"], 0)), WALK_FIRST_ROW + walk_frame(w["phase"]))
	var row := idle_row(w["idle_t"])
	w["idle_t"] += dt
	return Vector2i(sheet_column(maxi(w["facing"], 0)), row)


## Moves the facing shown towards the heading: one sector at once, then one per TURN_STEP_S. The
## shorter way round; a half-turn passes the side facing the camera (south).
static func _turn(w: Dictionary, dt: float) -> void:
	var target: int = w["heading"]
	if target < 0:
		return
	if w["facing"] < 0 or w["facing"] == target:
		w["facing"] = target
		w["turn_t"] = TURN_STEP_S
		return
	w["turn_t"] += dt
	while w["facing"] != target and w["turn_t"] >= TURN_STEP_S:
		w["turn_t"] -= TURN_STEP_S
		w["facing"] = turn_step(w["facing"], target)


## Next facing from f towards target, one sector.
static func turn_step(f: int, target: int) -> int:
	var d := posmod(target - f, 8)
	if d == 0:
		return f
	if d == 4:  # half-turn: through whichever neighbour is closer to south
		var cw := posmod(f + 1, 8)
		var ccw := posmod(f - 1, 8)
		return ccw if _from_south(ccw) < _from_south(cw) else cw
	return posmod(f + (1 if d < 4 else -1), 8)


static func _from_south(f: int) -> int:
	return mini(f, 8 - f)


## Walk frame (0..WALK_FRAMES-1) at a phase of the cycle.
static func walk_frame(phase: float) -> int:
	return int(phase * WALK_FRAMES) % WALK_FRAMES


## Phase after finishing the step in progress by at most advance cycles: it stops on the start of the
## next REST_FRAMES frame. On one already, it goes back to its start (the same picture), so the next
## walk shows the whole frame.
static func finish_step(phase: float, advance: float) -> float:
	if walk_frame(phase) in REST_FRAMES:
		return float(walk_frame(phase)) / WALK_FRAMES
	var next := 1.0
	for r in REST_FRAMES:
		var at := float(r) / WALK_FRAMES
		if at > phase and at < next:
			next = at
	return fposmod(minf(phase + advance, next), 1.0)


## Sprite row (idle frame) after standing still for this many seconds.
static func idle_row(still_s: float) -> int:
	return int(still_s * IDLE_FPS) % IDLE_FRAMES
