## Builds the nodes that draw one map chunk. Tile ids are computed here and set with set_cell
## (never set_cells_terrain_connect), so the result depends only on MapData.
class_name ChunkView
extends RefCounted

## Ground layers are drawn under everything else, lowest priority first.
const GROUND_Z := -32


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
				out[t][d] = Vector2i(layer[1], tiles[t]["atlas"])
	return out


## A node drawing the chunk. Its layers use world coordinates, so it sits at the origin.
static func build(chunk: Vector2i, tiles: Texture2D) -> Node2D:
	var node := Node2D.new()
	node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
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
