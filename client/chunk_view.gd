## Builds the nodes that draw one map chunk. Tile ids are computed here and set with set_cell
## (never set_cells_terrain_connect), so the result depends only on MapData.
class_name ChunkView
extends RefCounted

## Ground layers are drawn under everything else, lowest priority first.
const GROUND_Z := -32
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


## A sprite for an object standing on `cell`. Its position is the cell centre, so it sorts by y with
## the players (y_sort): a player north of a tree walks behind it.
static func object_sprite(cell: Vector2i, index: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _texture(WorldData.object(index)["sprite"])
	sprite.centered = false
	var size := sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO
	sprite.offset = Vector2(-size.x / 2.0, IsoLayer.OBJECT_FOOT_PX - size.y)
	sprite.position = IsoLayer.cell_to_local(Vector2(cell))
	return sprite


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
	for cell in obj:
		node.add_child(object_sprite(cell, obj[cell]))
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
		var cells: Dictionary = ground[t]
		for d in cells:
			layer.set_cell(d, 0, cells[d])
		node.add_child(layer)
	return node
