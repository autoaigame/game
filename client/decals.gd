## Small ground details (tufts, pebbles, flowers, leaves) from data/decals/*.json. Drawing only: they
## never block, the server never sees them. Each decal type cuts the world into cells of its
## cell_size (a finer grid than objects); each cell holds at most one, at a position and with a
## presence drawn from a hash of (world seed, cell, type), kept on its allowed walkable grounds and
## never under a blocking object. Pure functions of world coordinates: chunks always agree.
class_name Decals
extends RefCounted

## How far a decal may sit from its cell centre, in cells.
const MAX_OFFSET := 0.3

static var _seed := -1


## The decal drawn on a cell: {} or {index, sprite: index in its sprites, offset: Vector2 in cells}. Where several types land on the
## same cell, the first in id order wins.
static func decal_at(cell: Vector2i) -> Dictionary:
	var decals := WorldData.decals()
	for i in decals.size():
		var size: int = decals[i]["cell_size"]
		var g := Vector2i(floori(cell.x / float(size)), floori(cell.y / float(size)))
		if position_in(i, g) == cell and is_present(i, g):
			var h := _hash(i, g)
			var off := Vector2(WorldNoise.unit(WorldNoise.mix32(h ^ 3)), WorldNoise.unit(WorldNoise.mix32(h ^ 4)))
			var n: int = decals[i]["sprites"].size()
			return {"index": i, "sprite": WorldNoise.mix32(h ^ 5) % n, "offset": (off * 2.0 - Vector2.ONE) * MAX_OFFSET}
	return {}


## The decals of a chunk's cells: [[cell, {index, offset}], ...] in cell order.
static func in_chunk(chunk: Vector2i) -> Array:
	var out := []
	for y in MapData.CHUNK:
		out.append_array(in_row(chunk, y))
	return out


## The decals of row `y` of a chunk, as in_chunk gives them.
static func in_row(chunk: Vector2i, y: int) -> Array:
	var out := []
	var o := chunk * MapData.CHUNK
	for x in MapData.CHUNK:
		var d := decal_at(o + Vector2i(x, y))
		if not d.is_empty():
			out.append([o + Vector2i(x, y), d])
	return out


## The cell where decal type `index` would sit in its grid cell `g`.
static func position_in(index: int, g: Vector2i) -> Vector2i:
	var size: int = WorldData.decals()[index]["cell_size"]
	var h := _hash(index, g)
	return g * size + Vector2i(WorldNoise.mix32(h ^ 1) % size, WorldNoise.mix32(h ^ 2) % size)


## Whether grid cell `g` holds a decal of type `index`.
static func is_present(index: int, g: Vector2i) -> bool:
	var rec: Dictionary = WorldData.decals()[index]
	if WorldNoise.unit(_hash(index, g)) >= rec["density"]:
		return false
	var cell := position_in(index, g)
	var t := MapData.tile_at(cell)
	if not rec["grounds"].has(t) or not WorldData.tile(t)["walkable"]:
		return false
	var o := MapData.object_index_at(cell)
	return not (o >= 0 and WorldData.object(o)["blocks"])


static func _hash(index: int, g: Vector2i) -> int:
	if _seed < 0:
		_seed = int(WorldData.gen()["seed"])
	return WorldNoise.hash3(_seed, g.x, g.y, WorldData.decals()[index]["salt"])
