## Natural objects of the world (trees, rocks, bushes), from data/objects/*.json. Each object type
## cuts the world into square cells of its cell_size; each cell holds at most one object of that type,
## whose position and presence come from a hash of (world seed, cell, type) and from the density of the
## biome under it. Pure functions of world coordinates: any chunk sees the same objects.
class_name WorldObjects
extends RefCounted


## Index of the natural object on a cell (WorldData.objects()), or -1. Where several types land on the
## same cell, the first in id order wins.
static func object_at(cell: Vector2i) -> int:
	var objects := WorldData.objects()
	for i in objects.size():
		var obj: Dictionary = objects[i]
		if obj["max_density"] <= 0.0:
			continue  # only placed by hand-made places
		var size: int = obj["cell_size"]
		var g := Vector2i(floori(cell.x / float(size)), floori(cell.y / float(size)))
		var h := _hash(obj, g)
		if _position(h, g, size) == cell and _present(obj, h, cell):
			return i
	return -1


## The cell where object type `index` would stand in its grid cell `g` (present or not).
static func position_in(index: int, g: Vector2i) -> Vector2i:
	var obj := WorldData.object(index)
	return _position(_hash(obj, g), g, obj["cell_size"])


## Whether grid cell `g` holds an object of type `index`: a hash under the density of the biome at
## its position, never in the starting meadow for objects that block.
static func is_present(index: int, g: Vector2i) -> bool:
	var obj := WorldData.object(index)
	var h := _hash(obj, g)
	return _present(obj, h, _position(h, g, obj["cell_size"]))


static func _position(h: int, g: Vector2i, size: int) -> Vector2i:
	return g * size + Vector2i(WorldNoise.mix32(h ^ 1) % size, WorldNoise.mix32(h ^ 2) % size)


static func _present(obj: Dictionary, h: int, cell: Vector2i) -> bool:
	var roll := WorldNoise.unit(h)
	if roll >= obj["max_density"]:
		return false  # cheap early out: no biome needed
	if obj["blocks"] and Terrain.meadow_t(cell.x, cell.y) < 1.0:
		return false
	return roll < obj["density"][Terrain.biome(cell.x, cell.y)]


static var _seed := -1


static func _hash(obj: Dictionary, g: Vector2i) -> int:
	if _seed < 0:
		_seed = int(WorldData.gen()["seed"])
	return WorldNoise.hash3(_seed, g.x, g.y, obj["salt"])
