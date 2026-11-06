## Ground drawn on a grid offset by half a cell from the game grid ("dual grid"). Each drawn tile sits
## on the corner shared by 4 cells and is chosen from their grounds, so transitions between grounds
## need 16 tiles per ground (one per corner mask) instead of one per combination of neighbours.
## Game cells stay the logical grid: walkability and the server never see this.
class_name DualGrid
extends RefCounted

## Mask bits, one per corner cell of a drawn tile at (x, y). On screen: top, right, bottom, left.
const TOP := 1  ## cell (x - 1, y - 1)
const RIGHT := 2  ## cell (x, y - 1)
const BOTTOM := 4  ## cell (x, y)
const LEFT := 8  ## cell (x - 1, y)
const FULL := 15
## Drawn tile (x, y) is centred on the corner between its 4 cells: half a cell up the game grid.
const OFFSET := Vector2(0, -IsoLayer.TILE_SIZE.y / 2.0)


## The 4 cells around drawn tile `d`, in bit order (top, right, bottom, left).
static func corner_cells(d: Vector2i) -> Array[Vector2i]:
	return [d + Vector2i(-1, -1), d + Vector2i(0, -1), d, d + Vector2i(-1, 0)]


## Layers of one drawn tile from the priorities of its 4 corners (bit order): [[priority, mask], ...],
## lowest first. The lowest ground fills the whole tile; each higher ground present covers the corners
## whose priority is at least its own.
static func layers(corners: Array) -> Array:
	var lowest: int = corners.min()
	var out := [[lowest, FULL]]
	var seen := {lowest: true}
	var present := corners.duplicate()
	present.sort()
	for p in present:
		if seen.has(p):
			continue
		seen[p] = true
		out.append([p, mask_at_least(corners, p)])
	return out


## Mask of the corners whose priority is >= p.
static func mask_at_least(corners: Array, p: int) -> int:
	var m := 0
	for i in 4:
		if corners[i] >= p:
			m |= 1 << i
	return m
