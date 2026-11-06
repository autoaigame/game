## Turns held movement keys into move_to targets. Pure functions, so tests can check them.
class_name KeyMove
extends RefCounted

## How many cells ahead of the last known position a held key aims. It must cover
## the distance walked while a snapshot and the next move_to are in flight,
## otherwise the player reaches its target and stops before the next one arrives.
const LOOKAHEAD := 3


## Grid direction from the four keys. Keys follow the screen: in the 2:1 view (IsoLayer.cell_to_local)
## up is grid (-1, -1), down (1, 1), left (-1, 1) and right (1, -1). Two keys give a grid axis
## (up + right is (0, -1)); opposite keys cancel.
static func direction(up: bool, down: bool, left: bool, right: bool) -> Vector2i:
	var sx := int(right) - int(left)
	var sy := int(down) - int(up)
	return Vector2i(signi(sx + sy), signi(sy - sx))


## Target while a key is held: the farthest walkable cell, up to LOOKAHEAD cells
## ahead in a straight line, so the server keeps moving the player between updates. A diagonal step
## needs both cells beside it walkable, so the player never slips through the corner of a water cell.
static func held_target(pos: Vector2, dir: Vector2i) -> Vector2i:
	return _walk(Protocol.cell_of(pos), dir, LOOKAHEAD)


static func _walk(cell: Vector2i, dir: Vector2i, steps: int) -> Vector2i:
	for i in steps:
		if not MapData.is_walkable(cell + dir):
			break
		if not (MapData.is_walkable(cell + Vector2i(dir.x, 0)) and MapData.is_walkable(cell + Vector2i(0, dir.y))):
			break
		cell += dir
	return cell
