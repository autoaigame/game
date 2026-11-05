## Turns held movement keys into move_to targets. Pure functions, so tests can check them.
class_name KeyMove
extends RefCounted

## How many cells ahead of the last known position a held key aims. It must cover
## the distance walked while a snapshot and the next move_to are in flight,
## otherwise the player reaches its target and stops before the next one arrives.
const LOOKAHEAD := 3


## Grid direction from the four keys. Two keys give a diagonal; opposite keys cancel.
static func direction(up: bool, down: bool, left: bool, right: bool) -> Vector2i:
	return Vector2i(int(right) - int(left), int(down) - int(up))


## Target while a key is held: the farthest walkable cell, up to LOOKAHEAD cells
## ahead in a straight line, so the server keeps moving the player between updates.
static func held_target(pos: Vector2, dir: Vector2i) -> Vector2i:
	return _walk(Protocol.cell_of(pos), dir, LOOKAHEAD)


static func _walk(cell: Vector2i, dir: Vector2i, steps: int) -> Vector2i:
	for i in steps:
		if not MapData.is_walkable(cell + dir):
			break
		cell += dir
	return cell
