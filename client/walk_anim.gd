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


## Screen moves count as sideways only when clearly flatter than a grid axis (which is exactly 2:1 on
## screen), so walking along an axis never flickers between two facings.
const SIDEWAYS_RATIO := 2.5


## Sprite column from a screen movement: 0 down, 1 left, 2 right, 3 up.
static func facing(screen_delta: Vector2) -> int:
	if absf(screen_delta.x) > absf(screen_delta.y) * SIDEWAYS_RATIO:
		return 1 if screen_delta.x < 0 else 2
	return 3 if screen_delta.y < 0 else 0


## Sprite row (walk frame) after walking this many cells.
static func walk_row(walked: float) -> int:
	return 1 + int(walked / (STRIDE_CELLS * 2.0) * WALK_FRAMES) % WALK_FRAMES


## Vertical offset of the sprite, in pixels: a small hop each stride while walking, none when still.
static func bob(walked: float, walking: bool) -> float:
	if not walking:
		return 0.0
	return -absf(sin(walked / STRIDE_CELLS * PI)) * BOB_PX
