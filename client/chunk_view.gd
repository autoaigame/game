## Builds the nodes that draw one map chunk. Tile ids are computed here and set with set_cell
## (never set_cells_terrain_connect), so the result depends only on MapData.
class_name ChunkView
extends RefCounted

## Ground layers are drawn under everything else, lowest priority first.
const GROUND_Z := -32
## The ground tint never changes brightness by more than this (data/biomes.json "ground_tint").
const TINT_MAX_AMOUNT := 0.15
const TINT_SHADER := "res://client/ground_tint.gdshader"
static var _tint: Variant = false  ## ShaderMaterial or null once built from the data; false before

## Decals: flat on the ground, above every ground layer, under objects and players (z 0).
const DECALS_Z := -8


## The drawn ground tiles of a chunk (DualGrid), by layer: tile index -> {drawn tile -> atlas coords}.
## A chunk draws the tiles (x, y) of its own cells; those on its top and left edges also look at the
## neighbouring chunks' cells, through MapData, so separately built chunks always meet.
static func ground_tiles(chunk: Vector2i) -> Dictionary:
	var out := {}
	var o := chunk * MapData.CHUNK
	var tiles := WorldData.tiles()
	for y in MapData.CHUNK:
		for x in MapData.CHUNK:
			var d := o + Vector2i(x, y)
			var corners := DualGrid.corner_cells(d).map(func(c): return MapData.tile_at(c))
			for layer in DualGrid.layers(corners):
				var t: int = layer[0]
				if not out.has(t):
					out[t] = {}
				var variant := DualGrid.full_variant(d, tiles[t]["full_variants"]) if layer[1] == DualGrid.FULL else 0
				out[t][d] = Vector2i(IsoLayer.atlas_column(layer[1], variant), tiles[t]["atlas"])
	return out


static var _sprites := {}  ## sprite path -> Texture2D


## The objects of a chunk: cell -> object index, for the cells of the chunk.
static func objects(chunk: Vector2i) -> Dictionary:
	var out := {}
	var o := chunk * MapData.CHUNK
	for y in MapData.CHUNK:
		for x in MapData.CHUNK:
			var i := MapData.object_index_at(o + Vector2i(x, y))
			if i >= 0:
				out[o + Vector2i(x, y)] = i
	return out


## Which of an object's sprites stands on `cell`: a hash of the world seed, the cell and the object.
static func sprite_variant(cell: Vector2i, index: int) -> int:
	var n: int = WorldData.object(index)["sprites"].size()
	if n <= 1:
		return 0
	return WorldNoise.hash3(int(WorldData.gen()["seed"]), cell.x, cell.y, WorldData.object(index)["salt"]) % n


## Wall sprites run along the grid's y axis: a wall continuing along x (is_wall says where walls are)
## is drawn mirrored.
static func mirror_wall(cell: Vector2i, is_wall: Callable) -> bool:
	var along_x: bool = is_wall.call(cell + Vector2i(1, 0)) or is_wall.call(cell + Vector2i(-1, 0))
	var along_y: bool = is_wall.call(cell + Vector2i(0, 1)) or is_wall.call(cell + Vector2i(0, -1))
	return along_x and not along_y


## A sprite for an object standing on `cell`: its anchor (data/objects "anchor_px") on the cell centre.
## The position is the cell centre, so it sorts by y with the players (y_sort): a player north of a
## tree walks behind it. mirrored: flipped left to right around its anchor.
static func object_sprite(cell: Vector2i, index: int, mirrored := false) -> Sprite2D:
	var sp: Dictionary = WorldData.object(index)["sprites"][sprite_variant(cell, index)]
	var sprite := Sprite2D.new()
	sprite.texture = _texture(sp["file"])
	sprite.centered = false
	var anchor := Vector2(sp["anchor_px"])
	if mirrored and sprite.texture != null:
		sprite.flip_h = true
		anchor.x = sprite.texture.get_width() - anchor.x
	sprite.offset = -anchor
	sprite.position = IsoLayer.cell_to_local(Vector2(cell))
	return sprite


## The material that tints ground layers, from settings {enabled, amount, scale (cells per feature),
## warmth}, or null when disabled.
static func tint_material(settings: Dictionary) -> ShaderMaterial:
	if not settings.get("enabled", false):
		return null
	var m := ShaderMaterial.new()
	m.shader = load(TINT_SHADER)
	m.set_shader_parameter("amount", clampf(float(settings.get("amount", 0.06)), 0.0, TINT_MAX_AMOUNT))
	m.set_shader_parameter("warmth", clampf(float(settings.get("warmth", 0.5)), 0.0, 1.0))
	m.set_shader_parameter("scale_px", maxf(1.0, float(settings.get("scale", 40))) * IsoLayer.TILE_SIZE.x)
	var h := WorldNoise.hash2(int(WorldData.gen()["seed"]), 0x7147, 0)
	m.set_shader_parameter("offset", Vector2(h & 0xFFF, (h >> 12) & 0xFFF))
	return m


## The ground tint of this world (one material shared by every ground layer), or null.
static func ground_tint() -> ShaderMaterial:
	if typeof(_tint) == TYPE_BOOL:
		_tint = tint_material(WorldData.gen().get("ground_tint", {}))
	return _tint


## A flat sprite for a decal, centred on its cell centre moved by the decal's offset.
static func decal_sprite(cell: Vector2i, d: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _texture(WorldData.decals()[d["index"]]["sprite"])
	sprite.position = IsoLayer.cell_to_local(Vector2(cell) + d["offset"]).round()
	return sprite


static func _texture(path: String) -> Texture2D:
	if not _sprites.has(path):
		_sprites[path] = load(path) if ResourceLoader.exists(path) else null
	return _sprites[path]


## A node drawing the chunk. Its layers use world coordinates, so it sits at the origin. It is y-sorted
## so its object sprites sort together with the players in the parent view.
static func build(chunk: Vector2i, tiles: Texture2D) -> Node2D:
	var node := Node2D.new()
	node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	node.y_sort_enabled = true
	var obj := objects(chunk)
	var wall := WorldData.object_index("stone_wall")
	var is_wall := func(c: Vector2i) -> bool: return MapData.object_index_at(c) == wall
	for cell in obj:
		node.add_child(object_sprite(cell, obj[cell], obj[cell] == wall and mirror_wall(cell, is_wall)))
	var decals := Node2D.new()
	decals.name = "Decals"
	decals.z_index = DECALS_Z
	for d in Decals.in_chunk(chunk):
		decals.add_child(decal_sprite(d[0], d[1]))
	node.add_child(decals)
	var ground := ground_tiles(chunk)
	var order := ground.keys()
	order.sort()
	for t in order:
		var layer := IsoLayer.new_layer(tiles)
		layer.name = "Ground_%s" % WorldData.tile(t)["id"]
		layer.position = DualGrid.OFFSET
		layer.z_index = GROUND_Z + t
		layer.material = ground_tint()
		var cells: Dictionary = ground[t]
		for d in cells:
			layer.set_cell(d, 0, cells[d])
		node.add_child(layer)
	return node
