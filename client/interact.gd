## Clicking on things in the world: which gatherable object a click means, and when the player is
## close enough to gather it. Pure functions, so tests can check them.
class_name Interact
extends RefCounted

## Objects the player can gather from (server/gather.gd has their rules).
const GATHERABLE: Array[String] = ["bush"]


## The gatherable object a click on `cell` means: on that cell, or one cell below it on screen (a
## click on the leaves of a bush lands on the cell behind it). null if none.
static func gatherable_at(cell: Vector2i) -> Variant:
	for c in [cell, cell + Vector2i(1, 1), cell + Vector2i(1, 0), cell + Vector2i(0, 1)]:
		if MapData.object_at(c) in GATHERABLE:
			return c
	return null


## Whether the player at `pos` is close enough to gather from `cell` (a little inside the server's reach).
static func reached(pos: Vector2, cell: Vector2i) -> bool:
	return pos.distance_to(Vector2(cell)) <= Protocol.GATHER_REACH - 0.1
