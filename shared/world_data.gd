## Game data for world generation, read once from res://data/ (tiles, biomes, objects, places, decals). Shared by the server
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
static var _objects: Array[Dictionary] = []  ## sorted by id; index = object index
static var _object_index := {}  ## id -> index
static var _places: Array[Dictionary] = []  ## sorted by id; index = place index
static var _decals: Array[Dictionary] = []  ## sorted by id; index = decal index


## Tile records: {id, name, walkable, priority, atlas, full_variants, mask_variants}, lowest priority
## first. full_variants: how many versions of the full tile the atlas row holds (picked per drawn tile).
## mask_variants: reserved for versions of each transition tile, only 1 is supported for now.
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


## Object records, sorted by id: {id, name, blocks, cell_size, sprites: [{file, anchor_px}], density: PackedFloat64Array by
## biome index, max_density, salt: hash of the id (seeds its placement, so adding an object moves no
## other)}.
static func objects() -> Array[Dictionary]:
	_ensure()
	return _objects


static func object(index: int) -> Dictionary:
	_ensure()
	return _objects[index]


## Index of an object id, or -1.
static func object_index(id: String) -> int:
	_ensure()
	return _object_index.get(id, -1)


## Hand-made places, sorted by id: {id, name, size: Vector2i, cells: [[offset, tile, object], ...]
## (tile and object are indices or -1 to keep the natural one; every footprint cell loses its natural
## object), biomes: {biome index: true}, max_altitude_range, chance, min_distance}.
static func places() -> Array[Dictionary]:
	_ensure()
	return _places


## Ground decals, sorted by id: {id, name, sprites: [file, ...], grounds: {tile index: true}, cell_size, density,
## salt}. Drawing only: decals never block and the server ignores them.
static func decals() -> Array[Dictionary]:
	_ensure()
	return _decals


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
				"walkable": bool(rec["walkable"]), "priority": int(rec["priority"]), "atlas": int(rec["atlas"]),
				"full_variants": maxi(1, int(rec.get("full_variants", 1))),
				"mask_variants": maxi(1, int(rec.get("mask_variants", 1)))})
		if _tiles.back()["mask_variants"] != 1:
			push_error("data: tile %s: mask_variants other than 1 is not supported yet" % rec["id"])
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
	for rec in _read_dir(DATA_DIR.path_join("objects")):
		var density := PackedFloat64Array()
		density.resize(_biomes.size())
		for b in rec["densities"]:
			if not _biome_index.has(b):
				push_error("data: object %s names unknown biome %s" % [rec["id"], b])
				continue
			density[_biome_index[b]] = float(rec["densities"][b])
		_objects.append({"id": String(rec["id"]), "name": String(rec["name"]), "blocks": bool(rec["blocks"]),
				"cell_size": maxi(1, int(rec["cell_size"])), "sprites": _sprites(rec), "density": density,
				"max_density": Array(density).max() if density.size() > 0 else 0.0,
				"salt": WorldNoise.hash_text(rec["id"])})
	for i in _objects.size():
		_object_index[_objects[i]["id"]] = i
	for rec in _read_dir(DATA_DIR.path_join("places")):
		_places.append(_place(rec))
	for rec in _read_dir(DATA_DIR.path_join("decals")):
		var grounds := {}
		for g in rec["grounds"]:
			if tile_index(g) < 0:
				push_error("data: decal %s names unknown ground %s" % [rec["id"], g])
			grounds[tile_index(g)] = true
		_decals.append({"id": String(rec["id"]), "name": String(rec["name"]), "sprites": Array(rec["sprites"]),
				"grounds": grounds, "cell_size": maxi(1, int(rec["cell_size"])), "density": float(rec["density"]),
				"salt": WorldNoise.hash_text("decal:" + String(rec["id"]))})


## An object's sprites: [{file, anchor_px: Vector2i (the point standing on the cell centre)}].
static func _sprites(rec: Dictionary) -> Array:
	var out := []
	for sp in rec["sprites"]:
		out.append({"file": String(sp["file"]), "anchor_px": Vector2i(int(sp["anchor_px"][0]), int(sp["anchor_px"][1]))})
	return out


## A place record from its JSON: the plan is rows of characters, " " is outside the place.
static func _place(rec: Dictionary) -> Dictionary:
	var plan: Array = rec["plan"]
	var legend: Dictionary = rec["legend"]
	var cells := []
	var width := 0
	for y in plan.size():
		var row: String = plan[y]
		width = maxi(width, row.length())
		for x in row.length():
			var ch := row[x]
			if ch == " ":
				continue
			if not legend.has(ch):
				push_error("data: place %s uses %s, missing from its legend" % [rec["id"], ch])
				continue
			var entry: Dictionary = legend[ch]
			var t := tile_index(entry.get("tile", "")) if entry.has("tile") else -1
			var o := object_index(entry.get("object", "")) if entry.has("object") else -1
			if (entry.has("tile") and t < 0) or (entry.has("object") and o < 0):
				push_error("data: place %s legend %s names an unknown tile or object" % [rec["id"], ch])
			cells.append([Vector2i(x, y), t, o])
	var rules: Dictionary = rec["rules"]
	var biomes := {}
	for b in rules["biomes"]:
		if not _biome_index.has(b):
			push_error("data: place %s names unknown biome %s" % [rec["id"], b])
		biomes[_biome_index.get(b, -1)] = true
	return {"id": String(rec["id"]), "name": String(rec["name"]), "size": Vector2i(width, plan.size()),
			"cells": cells, "biomes": biomes, "max_altitude_range": float(rules["max_altitude_range"]),
			"chance": float(rules["chance"]), "min_distance": float(rules["min_distance"])}


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
