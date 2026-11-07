## Smooth walking on screen: in-between positions and the walk cycle. Pure functions, so tests can
## check them. Display only: the server still decides every position (docs/invariants.md, rule 1).
class_name WalkAnim
extends RefCounted

## The drawn player catches up with the last snapshot at this multiple of the walking speed, so it
## glides between snapshots and never falls behind while walking.
const CATCH_UP := 1.5
## Farther than this from the snapshot (spawn, reconnect, lost snapshots): jump there at once.
const SNAP_CELLS := 3.0
## Walk rows of the sheet play one cycle (two steps) over this distance, so the feet keep pace with
## the ground at Protocol.SPEED_CELLS_PER_S.
const WALK_CYCLE_CELLS := 1.25
## Standing still, the idle rows play at this many frames per second.
const IDLE_FPS := 4.0


## Next drawn position, in cells: towards the server's position, never past it.
static func follow(shown: Vector2, server: Vector2, dt: float) -> Vector2:
	var to_server := server - shown
	var dist := to_server.length()
	if dist > SNAP_CELLS:
		return server
	var step := Protocol.SPEED_CELLS_PER_S * CATCH_UP * dt
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
## frames (one cycle of two steps).
const FRAME_SIZE := Vector2i(112, 112)
const SHEET_COLUMNS := 8
const FACING_COLUMN: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const IDLE_FRAMES := 4
const WALK_FRAMES := 6
const WALK_FIRST_ROW := IDLE_FRAMES
const SHEET_ROWS := IDLE_FRAMES + WALK_FRAMES
## The feet stand this many px above the bottom of a frame, horizontally centred.
const FOOT_PX := 2
## The top of the head is this many px above the feet: the name is drawn just above it.
const HEAD_PX := 100
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


## Sprite row (walk frame) after walking this many cells.
static func walk_row(walked: float) -> int:
	return WALK_FIRST_ROW + int(walked / WALK_CYCLE_CELLS * WALK_FRAMES) % WALK_FRAMES


## Sprite row (idle frame) after standing still for this many seconds.
static func idle_row(still_s: float) -> int:
	return int(still_s * IDLE_FPS) % IDLE_FRAMES
