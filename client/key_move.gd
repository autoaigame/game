## Turns held movement keys into move_to targets. Pure functions, so tests can check them.
class_name KeyMove
extends RefCounted

## How many cells ahead of the last known position a held key aims. It must cover
## the distance walked while a snapshot and the next move_to are in flight,
## otherwise the player reaches its target and stops before the next one arrives.
const LOOKAHEAD := 3
## Spacing of the points checked along a held line, in cells. Smaller than a cell, so no cell is skipped.
const SAMPLE := 0.05


## Grid direction from the four keys. Keys follow the screen: in the 2:1 view (IsoLayer.cell_to_local)
## up is grid (-1, -1), down (1, 1), left (-1, 1) and right (1, -1). Two keys give a grid axis
## (up + right is (0, -1)); opposite keys cancel.
static func direction(up: bool, down: bool, left: bool, right: bool) -> Vector2i:
	var sx := int(right) - int(left)
	var sy := int(down) - int(up)
	return Vector2i(signi(sx + sy), signi(sy - sx))


## Target while a key is held: the point LOOKAHEAD cells ahead of pos along dir, so the server keeps
## moving the player between updates. It is a point, not a cell center: every target then lies on the
## same straight line through pos, and a player who starts off center walks that line instead of
## zigzagging back to the cell centers. Where water is closer, the target is the last point of that
## line still on a walkable cell, with the same rule as Protocol.can_enter: a diagonal cell change
## needs both cells beside it walkable, so the player never slips through the corner of a water cell.
static func held_target(pos: Vector2, dir: Vector2i) -> Vector2:
	var end := pos + Vector2(dir) * LOOKAHEAD
	var samples := ceili(pos.distance_to(end) / SAMPLE)
	var at := pos
	for i in samples:
		var next := end if i == samples - 1 else pos.lerp(end, float(i + 1) / samples)
		if not Protocol.can_enter(Protocol.cell_of(at), Protocol.cell_of(next)):
			return _last_point_in_cell(at, next)
		at = next
	return end


## The point of segment [a, b] closest to b that is still on a's cell. The cell borders do not depend
## on where the player stands on the line, so neither does this point: the target stays put while
## the player walks up to the water, and the client does not resend it.
static func _last_point_in_cell(a: Vector2, b: Vector2) -> Vector2:
	var cell := Protocol.cell_of(a)
	var lo := 0.0
	var hi := 1.0
	for i in 16:
		var mid := (lo + hi) * 0.5
		if Protocol.cell_of(a.lerp(b, mid)) == cell:
			lo = mid
		else:
			hi = mid
	return a.lerp(b, lo)
