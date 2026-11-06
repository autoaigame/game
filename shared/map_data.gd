## The world map: infinite, generated from the world seed (shared/terrain.gd), deterministic,
## shared by client and server. Cells are computed by chunks of CHUNK x CHUNK and cached; the cache
## only remembers results, so the answer never depends on what was asked before.
class_name MapData
extends RefCounted

const CHUNK := 16
## Chunks kept in memory before the cache is emptied (a few players' surroundings).
const CACHE_MAX_CHUNKS := 4096
## How far nearest_walkable() looks, in cells.
const SEARCH_RADIUS := 128

static var _chunks := {}  ## chunk coords -> {tiles, walk, objects, places: PackedByteArray}
static var _spawn: Variant = null


## Tile index (WorldData.tiles()) of a cell. Any cell exists: the world has no edge.
static func tile_at(cell: Vector2i) -> int:
	var c := chunk_of(cell)
	return _chunk(c)["tiles"][_index_in_chunk(cell, c)]


## Index of the object on a cell (WorldData.objects()), or -1.
static func object_index_at(cell: Vector2i) -> int:
	var c := chunk_of(cell)
	return _chunk(c)["objects"][_index_in_chunk(cell, c)] - 1


## Id of the object on a cell, or "".
static func object_at(cell: Vector2i) -> String:
	var i := object_index_at(cell)
	return WorldData.object(i)["id"] if i >= 0 else ""


## Id of the hand-made place covering a cell, or "".
static func place_at(cell: Vector2i) -> String:
	var c := chunk_of(cell)
	var i: int = _chunk(c)["places"][_index_in_chunk(cell, c)] - 1
	return WorldData.places()[i]["id"] if i >= 0 else ""


## Walkable ground and no blocking object.
static func is_walkable(cell: Vector2i) -> bool:
	var c := chunk_of(cell)
	return _chunk(c)["walk"][_index_in_chunk(cell, c)] == 1


## The chunk that holds a cell (floor division, also for negative cells).
static func chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))


## The walkable cell nearest to the origin.
static func spawn_cell() -> Vector2i:
	if _spawn == null:
		_spawn = nearest_walkable(Vector2i.ZERO)
	return _spawn


## The walkable cell nearest to `from`, or null if none lies within SEARCH_RADIUS.
static func nearest_walkable(from: Vector2i) -> Variant:
	return _nearest(from, {})


## The cell of `cells` (a set: cell -> true) nearest to `from`, or null: the same search as
## nearest_walkable, on given cells (tests check the search with it).
static func nearest_of(from: Vector2i, cells: Dictionary) -> Variant:
	return null if cells.is_empty() else _nearest(from, cells)


## The cell nearest to `from` (Euclidean distance) that is in `cells`, or walkable if `cells` is
## empty; null if none lies within SEARCH_RADIUS. Searches square rings of growing size, and goes on
## while a farther ring may still hold a closer cell, so the result is exact. Ties go to the first
## cell in a fixed scan order.
static func _nearest(from: Vector2i, cells: Dictionary) -> Variant:
	var best: Variant = null
	var best_d2 := 0
	for r in SEARCH_RADIUS + 1:
		if best != null and r * r > best_d2:
			break
		for dy in range(-r, r + 1):
			var step := 1 if absi(dy) == r else 2 * r
			for dx in range(-r, r + 1, maxi(step, 1)):
				var d2 := dx * dx + dy * dy
				if best != null and d2 >= best_d2:
					continue
				var c := from + Vector2i(dx, dy)
				if cells.has(c) if not cells.is_empty() else is_walkable(c):
					best = c
					best_d2 = d2
	return best


## Forgets every cached chunk (tests use it to check that results do not depend on the cache).
static func clear_cache() -> void:
	_chunks.clear()
	_spawn = null
	WorldPlaces.clear_cache()


static func _index_in_chunk(cell: Vector2i, chunk: Vector2i) -> int:
	return (cell.y - chunk.y * CHUNK) * CHUNK + (cell.x - chunk.x * CHUNK)


static func _chunk(c: Vector2i) -> Dictionary:
	var data: Variant = _chunks.get(c)
	if data != null:
		return data
	if _chunks.size() >= CACHE_MAX_CHUNKS:
		_chunks.clear()
	data = _generate(c)
	_chunks[c] = data
	return data


static func _generate(c: Vector2i) -> Dictionary:
	var tiles := PackedByteArray()
	var walk := PackedByteArray()
	var objects := PackedByteArray()  ## object index + 1, 0 = none
	var places := PackedByteArray()  ## place index + 1, 0 = none
	tiles.resize(CHUNK * CHUNK)
	walk.resize(CHUNK * CHUNK)
	objects.resize(CHUNK * CHUNK)
	places.resize(CHUNK * CHUNK)
	var biomes := WorldData.biomes()
	for y in CHUNK:
		for x in CHUNK:
			var cell := c * CHUNK + Vector2i(x, y)
			tiles[y * CHUNK + x] = biomes[Terrain.biome(cell.x, cell.y)]["tile"]
			objects[y * CHUNK + x] = WorldObjects.object_at(cell) + 1
	# hand-made places replace the ground and the objects under their footprint
	var rect := Rect2i(c * CHUNK, Vector2i(CHUNK, CHUNK))
	for p in WorldPlaces.places_in(rect):
		var place: Dictionary = WorldData.places()[p["index"]]
		for pc in place["cells"]:
			var cell: Vector2i = p["origin"] + pc[0]
			if not rect.has_point(cell):
				continue
			var i := _index_in_chunk(cell, c)
			if pc[1] >= 0:
				tiles[i] = pc[1]
			objects[i] = pc[2] + 1
			places[i] = p["index"] + 1
	for i in CHUNK * CHUNK:
		var ob := objects[i] - 1
		var blocked: bool = ob >= 0 and WorldData.object(ob)["blocks"]
		walk[i] = 1 if WorldData.tile(tiles[i])["walkable"] and not blocked else 0
	return {"tiles": tiles, "walk": walk, "objects": objects, "places": places}
