## Smooth walking on screen: in-between positions and the walk cycle. Pure functions, so tests can
## check them. Display only: the server still decides every position (docs/invariants.md, rule 1).
class_name WalkAnim
extends RefCounted

## The drawn player catches up with the last snapshot at this multiple of the walking speed, so it
## glides between snapshots and never falls behind while walking.
const CATCH_UP := 1.5
## Farther than this from the snapshot (spawn, reconnect, lost snapshots): jump there at once.
const SNAP_CELLS := 3.0
## Distance walked per walk frame.
const STRIDE_CELLS := 0.5
## Height of the step bob, in pixels.
const BOB_PX := 3.0  ## the drawn walk frames already move the body; this only softens the steps
## Walk frames in assets/player.png (rows 1..WALK_FRAMES, row 0 is standing): one cycle is two steps.
const WALK_FRAMES := 4


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

## Player sprite sheet (assets/player.png): one frame of FRAME_SIZE px per column and row. The one place
## to change for a new sheet: SHEET_COLUMNS columns, and the column drawn for each facing. An 8-column
## sheet in FACINGS order (docs/art-guide.md) takes SHEET_COLUMNS = 8 and FACING_COLUMN = [0, 1, ... 7].
const FRAME_SIZE := Vector2i(64, 96)
const SHEET_COLUMNS := 4
## Today's sheet: 0 down, 1 left, 2 right, 3 up. Diagonals show the back going up, the front going down.
const FACING_COLUMN: Array[int] = [0, 0, 2, 3, 3, 3, 1, 0]


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
	return 1 + int(walked / (STRIDE_CELLS * 2.0) * WALK_FRAMES) % WALK_FRAMES


## Vertical offset of the sprite, in pixels: a small hop each stride while walking, none when still.
static func bob(walked: float, walking: bool) -> float:
	if not walking:
		return 0.0
	return -absf(sin(walked / STRIDE_CELLS * PI)) * BOB_PX
