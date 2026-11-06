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

static var _chunks := {}  ## chunk coords -> {tiles: PackedByteArray, walk: PackedByteArray}
static var _spawn: Variant = null


## Tile index (WorldData.tiles()) of a cell. Any cell exists: the world has no edge.
static func tile_at(cell: Vector2i) -> int:
	var c := chunk_of(cell)
	return _chunk(c)["tiles"][_index_in_chunk(cell, c)]


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
	return nearest_matching(from, is_walkable)


## The cell nearest to `from` (Euclidean distance) for which `test` is true, or null if none lies
## within SEARCH_RADIUS. Searches square rings of growing size, and goes on while a farther ring may
## still hold a closer cell, so the result is exact. Ties go to the first cell in a fixed scan order.
static func nearest_matching(from: Vector2i, test: Callable) -> Variant:
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
				if test.call(from + Vector2i(dx, dy)):
					best = from + Vector2i(dx, dy)
					best_d2 = d2
	return best


## Forgets every cached chunk (tests use it to check that results do not depend on the cache).
static func clear_cache() -> void:
	_chunks.clear()
	_spawn = null


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
	tiles.resize(CHUNK * CHUNK)
	walk.resize(CHUNK * CHUNK)
	var biomes := WorldData.biomes()
	for y in CHUNK:
		for x in CHUNK:
			var t: int = biomes[Terrain.biome(c.x * CHUNK + x, c.y * CHUNK + y)]["tile"]
			tiles[y * CHUNK + x] = t
			walk[y * CHUNK + x] = 1 if WorldData.tile(t)["walkable"] else 0
	return {"tiles": tiles, "walk": walk}
