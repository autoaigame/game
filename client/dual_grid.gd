## Ground drawn on a grid offset by half a cell from the game grid ("dual grid"). Each drawn tile sits
## on the corner shared by 4 cells and is chosen from their grounds, so transitions between grounds
## need 16 tiles per ground (one per corner mask) instead of one per combination of neighbours.
## Game cells stay the logical grid: walkability and the server never see this.
class_name DualGrid
extends RefCounted

## Mask bits, one per corner cell of a drawn tile at (x, y): NW << 3 | NE << 2 | SW << 1 | SE.
const NW := 8  ## cell (x - 1, y - 1), the top corner on screen
const NE := 4  ## cell (x, y - 1), the right corner on screen
const SW := 2  ## cell (x - 1, y), the left corner on screen
const SE := 1  ## cell (x, y), the bottom corner on screen
const FULL := 15
## Bit of each corner, in corner_cells() order.
const BITS := [NW, NE, SW, SE]
## Drawn tile (x, y) is centred on the corner between its 4 cells: half a cell up the game grid.
const OFFSET := Vector2(0, -IsoLayer.TILE_SIZE.y / 2.0)


## The 4 cells around drawn tile `d`: NW, NE, SW, SE.
static func corner_cells(d: Vector2i) -> Array[Vector2i]:
	return [d + Vector2i(-1, -1), d + Vector2i(0, -1), d + Vector2i(-1, 0), d]


## Which of `count` variants a full tile drawn at `d` uses: a hash of the world seed and `d`, so it
## never depends on which chunk is built first.
static func full_variant(d: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	return WorldNoise.hash3(int(WorldData.gen()["seed"]), d.x, d.y, 0x7A41A7) % count


## Layers of one drawn tile from the priorities of its 4 corners (corner_cells() order): [[priority, mask], ...],
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
			m |= BITS[i]
	return m
