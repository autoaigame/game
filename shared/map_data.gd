## The world map: fixed, deterministic, shared by client and server.
class_name MapData
extends RefCounted

const SIZE := Vector2i(32, 32)
const TILE_GRASS := 0
const TILE_PATH := 1
const TILE_WATER := 2

const _POND_CENTER := Vector2i(8, 8)
const _POND_RADIUS := 3


static func tile_at(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return TILE_WATER
	if cell.x == 0 or cell.y == 0 or cell.x == SIZE.x - 1 or cell.y == SIZE.y - 1:
		return TILE_WATER
	if (cell - _POND_CENTER).length_squared() <= _POND_RADIUS * _POND_RADIUS:
		return TILE_WATER
	if cell.x == 16 or cell.y == 16:
		return TILE_PATH
	return TILE_GRASS


static func is_walkable(cell: Vector2i) -> bool:
	return _in_bounds(cell) and tile_at(cell) != TILE_WATER


static func spawn_cell() -> Vector2i:
	return Vector2i(16, 16)


static func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE.x and cell.y < SIZE.y
