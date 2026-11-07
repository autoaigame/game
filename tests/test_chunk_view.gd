extends TestCase

## The nodes that draw a chunk (client/chunk_view.gd).


func test_built_node_has_one_layer_per_ground_in_priority_order() -> void:
	var tex: Texture2D = load("res://assets/tiles.png")
	var chunk := Vector2i(1, 1)
	var g := ChunkView.ground_tiles(chunk)
	var node := ChunkView.build(chunk, tex)
	assert_eq(node.get_child_count(), g.size())
	var last_z := -1000
	for layer: TileMapLayer in node.get_children():
		assert_true(layer.z_index > last_z, "layers not in priority order")
		last_z = layer.z_index
		assert_true(layer.z_index < 0, "ground must be under the players")
		assert_eq(layer.position, DualGrid.OFFSET)
	var cells := 0
	for t in g:
		cells += g[t].size()
	var used := 0
	for layer: TileMapLayer in node.get_children():
		used += layer.get_used_cells().size()
	assert_eq(used, cells)
	node.free()


## The drawn tile (x, y) is centred on the corner shared by cells (x - 1, y - 1) and (x, y).
func test_offset_puts_drawn_tiles_on_cell_corners() -> void:
	var d := Vector2i(3, 7)
	var drawn := IsoLayer.cell_to_local(Vector2(d)) + DualGrid.OFFSET
	var corner := IsoLayer.cell_to_local(Vector2(d) - Vector2(0.5, 0.5))
	assert_eq(drawn, corner)
