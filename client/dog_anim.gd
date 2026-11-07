## Layout of the dog sprite sheet (assets/dog.png, drawn by art/dog_sheet.gd) and which frame to show.
## One facing, right; the view mirrors the sprite to face left.
class_name DogAnim
extends RefCounted

const FRAME_SIZE := Vector2i(64, 48)
const FOOT_PX := 3  ## feet this many px above the bottom of a frame
const COLUMNS := 4  ## frames per pose
## One row per pose, top to bottom.
const ROWS: Array[String] = ["idle", "walk", "run", "sit", "sleep", "pee", "dig"]
const IDLE_FPS := 3.0
const POSE_FPS := 2.0  ## sit, sleep, pee, dig
const WALK_CYCLE_CELLS := 1.0  ## distance of one walk cycle (4 frames)
const RUN_FROM := 4.6  ## speed in cells per second from which the dog shows its run


## Offset of the sprite (centered = false) so the feet stand on the node's position.
static func sprite_offset() -> Vector2:
	return Vector2(-FRAME_SIZE.x / 2.0, -(FRAME_SIZE.y - FOOT_PX))


static func row_of(pose: String) -> int:
	return maxi(ROWS.find(pose), 0)


## The frame (column, row) to draw: walking or running by distance walked and speed, otherwise the
## pose (idle when the server says nothing) by time.
static func frame(pose: String, moving: bool, speed: float, walked: float, t: float) -> Vector2i:
	if moving:
		var col := int(floor(walked / WALK_CYCLE_CELLS * COLUMNS)) % COLUMNS
		return Vector2i(col, row_of("run" if speed >= RUN_FROM else "walk"))
	var fps := IDLE_FPS if pose == "idle" else POSE_FPS
	return Vector2i(int(floor(t * fps)) % COLUMNS, row_of(pose))
