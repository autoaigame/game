## Decides which map chunks the client builds and frees around the player. Bookkeeping only (no
## nodes), so tests can check it. Builds are spread over frames, a fixed number per frame: the web
## build has no threads, and building every chunk at once would freeze the game.
class_name ChunkStreamer
extends RefCounted

var load_radius: int  ## chunks within this Chebyshev distance of the player's chunk are built
var unload_radius: int  ## loaded chunks farther than this are freed (> load_radius: no flicker)
var builds_per_frame: int

var _loaded := {}  ## chunk -> true
var _pending: Array[Vector2i] = []  ## nearest first
var _center := Vector2i(1 << 30, 1 << 30)


func _init(load_r := 2, unload_r := 3, per_frame := 1) -> void:
	load_radius = load_r
	unload_radius = maxi(unload_r, load_r)
	builds_per_frame = per_frame


## Chunks within `radius` of the chunk holding `cell`, nearest first (ties in a fixed order).
static func wanted_chunks(cell: Vector2i, radius: int) -> Array[Vector2i]:
	var center := MapData.chunk_of(cell)
	var out: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			out.append(center + Vector2i(dx, dy))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return out


## The player is at `cell`: queues missing chunks, and returns the loaded chunks to free.
func update(cell: Vector2i) -> Array[Vector2i]:
	var freed: Array[Vector2i] = []
	var center := MapData.chunk_of(cell)
	if center == _center:
		return freed
	_center = center
	for c in _loaded.keys():
		if _dist(c) > unload_radius:
			_loaded.erase(c)
			freed.append(c)
	var pending: Array[Vector2i] = []
	for c in wanted_chunks(cell, load_radius):
		if not _loaded.has(c):
			pending.append(c)
	_pending = pending
	return freed


## The chunks to build this frame (at most builds_per_frame). They count as loaded from now on.
func take_builds() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	while out.size() < builds_per_frame and not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		_loaded[c] = true
		out.append(c)
	return out


func is_loaded(chunk: Vector2i) -> bool:
	return _loaded.has(chunk)


func loaded_count() -> int:
	return _loaded.size()


func pending_count() -> int:
	return _pending.size()


func _dist(c: Vector2i) -> int:
	return maxi(absi(c.x - _center.x), absi(c.y - _center.y))
