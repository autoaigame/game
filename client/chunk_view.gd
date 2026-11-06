## Builds the nodes that draw one map chunk. Tile ids are computed here and set with set_cell
## (never set_cells_terrain_connect), so the result depends only on MapData.
class_name ChunkView
extends RefCounted


## Atlas coordinates of every ground cell of a chunk: cell -> atlas coords.
static func ground_cells(chunk: Vector2i) -> Dictionary:
	var out := {}
	var o := chunk * MapData.CHUNK
	for y in MapData.CHUNK:
		for x in MapData.CHUNK:
			var cell := o + Vector2i(x, y)
			out[cell] = Vector2i(WorldData.tile(MapData.tile_at(cell))["atlas"], 0)
	return out


## A node drawing the chunk. Its layers use world cell coordinates, so it sits at the origin.
static func build(chunk: Vector2i, tiles: Texture2D) -> Node2D:
	var node := Node2D.new()
	node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	var ground := IsoLayer.new_layer(tiles)
	ground.name = "Ground"
	ground.z_index = -1
	var cells := ground_cells(chunk)
	for cell in cells:
		ground.set_cell(cell, 0, cells[cell])
	node.add_child(ground)
	return node
