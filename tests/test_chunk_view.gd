extends TestCase

## The nodes that draw a chunk (client/chunk_view.gd).


func test_ground_covers_exactly_the_chunk() -> void:
	var chunk := Vector2i(-3, 2)
	var cells := ChunkView.ground_cells(chunk)
	assert_eq(cells.size(), MapData.CHUNK * MapData.CHUNK)
	for cell in cells:
		assert_eq(MapData.chunk_of(cell), chunk, str(cell))


func test_ground_follows_the_map() -> void:
	var cells := ChunkView.ground_cells(Vector2i(4, -1))
	for cell in cells:
		assert_eq(cells[cell].x, WorldData.tile(MapData.tile_at(cell))["atlas"], str(cell))


func test_built_node_holds_the_ground_cells() -> void:
	var tex: Texture2D = load("res://assets/tiles.png")
	var node := ChunkView.build(Vector2i(1, 1), tex)
	var ground: TileMapLayer = node.get_node("Ground")
	assert_eq(ground.get_used_cells().size(), MapData.CHUNK * MapData.CHUNK)
	node.free()
