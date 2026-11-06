## Game data for world generation, read once from res://data/ (tiles, biomes). Shared by the server
## and the client, so both build the same world. Ids are text and never renamed: saves and other data
## refer to them. Tile indices (what MapData.tile_at returns) follow the tiles' priorities.
class_name WorldData
extends RefCounted

const DATA_DIR := "res://data"

static var _loaded := false
static var _tiles: Array[Dictionary] = []  ## sorted by priority; index = tile index
static var _tile_index := {}  ## id -> index
static var _biomes: Array[Dictionary] = []  ## sorted by id; index = biome index
static var _biome_index := {}  ## id -> index
static var _gen := {}  ## the rest of biomes.json (seed, noise settings, table)


## Tile records: {id, name, walkable, priority, atlas}, lowest priority first.
static func tiles() -> Array[Dictionary]:
	_ensure()
	return _tiles


static func tile(index: int) -> Dictionary:
	_ensure()
	return _tiles[index]


## Index of a tile id, or -1.
static func tile_index(id: String) -> int:
	_ensure()
	return _tile_index.get(id, -1)


static func biomes() -> Array[Dictionary]:
	_ensure()
	return _biomes


static func biome_index(id: String) -> int:
	_ensure()
	return _biome_index.get(id, -1)


## Generation settings from biomes.json.
static func gen() -> Dictionary:
	_ensure()
	return _gen


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for rec in _read_dir(DATA_DIR.path_join("tiles")):
		_tiles.append({"id": String(rec["id"]), "name": String(rec["name"]),
				"walkable": bool(rec["walkable"]), "priority": int(rec["priority"]), "atlas": int(rec["atlas"])})
	_tiles.sort_custom(func(a, b): return a["priority"] < b["priority"])
	for i in _tiles.size():
		_tile_index[_tiles[i]["id"]] = i
		if i > 0 and _tiles[i]["priority"] == _tiles[i - 1]["priority"]:
			push_error("data: tiles %s and %s share priority %d" % [_tiles[i - 1]["id"], _tiles[i]["id"], _tiles[i]["priority"]])
	_gen = _read_json(DATA_DIR.path_join("biomes.json"))
	var ids: Array = _gen.get("biomes", {}).keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = _gen["biomes"][id]
		var t := tile_index(b["tile"])
		if t < 0:
			push_error("data: biome %s uses unknown tile %s" % [id, b["tile"]])
		_biome_index[id] = _biomes.size()
		_biomes.append({"id": String(id), "tile": t})


## Every *.json record of a folder, in file name order (DirAccess order differs between platforms).
static func _read_dir(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var files := Array(DirAccess.get_files_at(path))
	files.sort()
	for f in files:
		if f.ends_with(".json"):
			var rec := _read_json(path.path_join(f))
			if rec.get("id", "") != f.get_basename():
				push_error("data: %s must have \"id\": \"%s\"" % [path.path_join(f), f.get_basename()])
			out.append(rec)
	return out


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("data: cannot read %s" % path)
		return {}
	return parsed
