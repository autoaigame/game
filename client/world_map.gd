## What the player has explored of the world, for the minimap and the big map (client/map_view.gd).
## The player reveals the cells within a radius as they walk; each explored cell remembers a colour
## code (its ground, or the blocking object on it), read from MapData. Kept in the browser (IndexedDB on
## the web) or user:// on desktop, one file per player name. Client only: the server knows nothing of it.
class_name WorldMap
extends RefCounted

## Cells within this many cells of the player are revealed as they walk.
const REVEAL_RADIUS := 16
## Colour of each ground on the map (data/tiles ids), from the game's palette (data/palette.json).
const GROUND_COLORS := {
	"deep_water": Color8(0x28, 0x3a, 0x3b),
	"shallow_water": Color8(0x45, 0x60, 0x5d),
	"sand": Color8(0xbd, 0xb5, 0x9f),
	"packed_dirt": Color8(0x6a, 0x5c, 0x49),
	"forest_floor": Color8(0x4d, 0x56, 0x38),
	"grass": Color8(0x76, 0x7d, 0x52),
	"dry_grass": Color8(0x9e, 0x92, 0x68),
}
## Colour of the objects that block the way (data/objects ids): trees, rocks, walls.
const OBJECT_COLORS := {
	"oak": Color8(0x2c, 0x33, 0x24),
	"birch": Color8(0x3b, 0x45, 0x30),
	"pine": Color8(0x2c, 0x33, 0x24),
	"stump": Color8(0x51, 0x43, 0x3a),
	"rock": Color8(0x93, 0x8f, 0x84),
	"standing_stone": Color8(0xb0, 0xab, 0x9e),
	"stone_wall": Color8(0xb0, 0xab, 0x9e),
}
const UNKNOWN_COLOR := Color8(0x77, 0x75, 0x6c)  ## a ground or object missing from the lists above
const _HEADER := "autoaigame-map-1"

var _chunks := {}  ## chunk -> PackedByteArray of CHUNK * CHUNK codes: 0 unexplored, else _palette index + 1
var _palette: Array[Color] = []  ## colours by code - 1, filled as cells are revealed
var _codes := {}  ## Color -> code


## The map colour of what stands on `cell` (its blocking object, else its ground).
static func color_of(cell: Vector2i) -> Color:
	var obj := MapData.object_at(cell)
	if obj != "" and WorldData.object(WorldData.object_index(obj)).get("blocks", false):
		return OBJECT_COLORS.get(obj, UNKNOWN_COLOR)
	return GROUND_COLORS.get(WorldData.tile(MapData.tile_at(cell))["id"], UNKNOWN_COLOR)


## Where player `player_name`'s map is kept.
static func path_for(player_name: String) -> String:
	return "user://map_%s.bin" % player_name


## Reveals the cells within `radius` of `center`, in chunks already generated (the map never generates
## one: that is the chunk streamer's job, spread over frames). Returns the chunks that changed.
func reveal(center: Vector2i, radius := REVEAL_RADIUS) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var r2 := radius * radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var cell := center + Vector2i(dx, dy)
			var c := MapData.chunk_of(cell)
			if not MapData.is_generated(c):
				continue
			var codes: PackedByteArray = _chunks.get(c, PackedByteArray())
			if codes.is_empty():
				codes.resize(MapData.CHUNK * MapData.CHUNK)
			var i := _index(cell, c)
			if codes[i] != 0:
				continue
			codes[i] = _code(color_of(cell))
			_chunks[c] = codes
			if not c in changed:
				changed.append(c)
	return changed


func is_explored(cell: Vector2i) -> bool:
	var codes: PackedByteArray = _chunks.get(MapData.chunk_of(cell), PackedByteArray())
	return not codes.is_empty() and codes[_index(cell, MapData.chunk_of(cell))] != 0


## The colour of an explored cell, transparent if unexplored.
func color_at(cell: Vector2i) -> Color:
	var c := MapData.chunk_of(cell)
	var codes: PackedByteArray = _chunks.get(c, PackedByteArray())
	if codes.is_empty() or codes[_index(cell, c)] == 0:
		return Color(0, 0, 0, 0)
	return _palette[codes[_index(cell, c)] - 1]


func has_chunk(c: Vector2i) -> bool:
	return _chunks.has(c)


func chunk_count() -> int:
	return _chunks.size()


## A CHUNK x CHUNK image of chunk `c`, one pixel per cell, transparent where unexplored.
func chunk_image(c: Vector2i) -> Image:
	var img := Image.create_empty(MapData.CHUNK, MapData.CHUNK, false, Image.FORMAT_RGBA8)
	var codes: PackedByteArray = _chunks.get(c, PackedByteArray())
	if codes.is_empty():
		return img
	for y in MapData.CHUNK:
		for x in MapData.CHUNK:
			var code := codes[y * MapData.CHUNK + x]
			if code != 0:
				img.set_pixel(x, y, _palette[code - 1])
	return img


## Writes the map to `path`; false if storage is missing (the map is then lost when the page closes).
func save(path: String) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_DEFLATE)
	if f == null:
		return false
	var colors := PackedColorArray(_palette)
	f.store_var({"header": _HEADER, "palette": colors, "chunks": _chunks})
	f.close()
	return true


## Replaces the map with the one at `path`; false (and an empty map) if it is missing or unreadable.
func load(path: String) -> bool:
	_chunks = {}
	_palette = []
	_codes = {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_DEFLATE)
	if f == null:
		return false
	var data: Variant = f.get_var()
	f.close()
	if typeof(data) != TYPE_DICTIONARY or data.get("header") != _HEADER \
			or typeof(data.get("palette")) != TYPE_PACKED_COLOR_ARRAY or typeof(data.get("chunks")) != TYPE_DICTIONARY:
		return false
	var palette: PackedColorArray = data["palette"]
	if palette.size() > 255:
		return false
	for c in data["chunks"]:
		var codes: Variant = data["chunks"][c]
		if typeof(c) != TYPE_VECTOR2I or typeof(codes) != TYPE_PACKED_BYTE_ARRAY \
				or codes.size() != MapData.CHUNK * MapData.CHUNK:
			continue
		var ok := true
		for code in codes:
			if code > palette.size():
				ok = false
				break
		if ok:
			_chunks[c] = codes
	for color in palette:
		_codes[color] = _palette.size() + 1
		_palette.append(color)
	return true


func _code(color: Color) -> int:
	if not _codes.has(color):
		_palette.append(color)
		_codes[color] = _palette.size()
	return _codes[color]


static func _index(cell: Vector2i, c: Vector2i) -> int:
	var local := cell - c * MapData.CHUNK
	return local.y * MapData.CHUNK + local.x
