## Clicking on things in the world: which gatherable object a click means, and when the player is
## close enough to gather it. Pure functions, so tests can check them.
class_name Interact
extends RefCounted



## The gatherable object (shared/gather_rules.gd) a click on `cell` means: on that cell, or one cell
## below it on screen (a click on the leaves of a bush or tree lands on the cell behind it). null if none.
static func gatherable_at(cell: Vector2i) -> Variant:
	for c in [cell, cell + Vector2i(1, 1), cell + Vector2i(1, 0), cell + Vector2i(0, 1)]:
		if GatherRules.RULES.has(MapData.object_at(c)):
			return c
	return null


## Whether the player at `pos` is close enough to gather from `cell` (a little inside the server's reach).
static func reached(pos: Vector2, cell: Vector2i) -> bool:
	return pos.distance_to(Vector2(cell)) <= Protocol.GATHER_REACH - 0.1


## Where to walk to gather from `cell`: the cell itself if walkable (a bush), else the nearest
## walkable cell (a tree blocks).
static func walk_target(cell: Vector2i) -> Vector2i:
	var near: Variant = MapData.nearest_walkable(cell)
	return near if near != null else cell
