extends TestCase

## The nodes that draw a chunk (client/chunk_view.gd).


func test_built_node_has_one_layer_per_ground_in_priority_order() -> void:
	var tex: Texture2D = load("res://assets/tiles.png")
	var chunk := Vector2i(1, 1)
	var g := ChunkView.ground_tiles(chunk)
	var node := ChunkView.build(chunk, tex)
	var layers := node.get_children().filter(func(n): return n is TileMapLayer)
	assert_eq(layers.size(), g.size())
	var last_z := -1000
	for layer: TileMapLayer in layers:
		assert_true(layer.z_index > last_z, "layers not in priority order")
		last_z = layer.z_index
		assert_true(layer.z_index < 0, "ground must be under the players")
		assert_eq(layer.position, DualGrid.OFFSET)
	var cells := 0
	for t in g:
		cells += g[t].size()
	var used := 0
	for layer: TileMapLayer in layers:
		used += layer.get_used_cells().size()
	assert_eq(used, cells)
	node.free()


## The drawn tile (x, y) is centred on the corner shared by cells (x - 1, y - 1) and (x, y).
func test_offset_puts_drawn_tiles_on_cell_corners() -> void:
	var d := Vector2i(3, 7)
	var drawn := IsoLayer.cell_to_local(Vector2(d)) + DualGrid.OFFSET
	var corner := IsoLayer.cell_to_local(Vector2(d) - Vector2(0.5, 0.5))
	assert_eq(drawn, corner)


## Object sprites stand on their cell centre, inside a y-sorted chunk, so they sort with the players
## (a player one cell north of a tree is drawn before it, behind it).
func test_objects_are_y_sorted_sprites_on_their_cells() -> void:
	var chunk := Vector2i(5, -3)
	var obj := ChunkView.objects(chunk)
	assert_true(obj.size() > 0, "no object in the test chunk")
	var node := ChunkView.build(chunk, null)
	assert_true(node.y_sort_enabled)
	var sprites := node.get_children().filter(func(n): return n is Sprite2D)
	assert_eq(sprites.size(), obj.size())
	var positions := {}
	for sp: Sprite2D in sprites:
		positions[sp.position] = true
		assert_true(sp.texture != null, "missing sprite texture")
		assert_true(sp.z_index == 0 and sp.z_index > ChunkView.GROUND_Z + 16, "sprites above the ground")
	for cell in obj:
		assert_true(positions.has(IsoLayer.cell_to_local(Vector2(cell))), "no sprite at %s" % cell)
	node.free()


## Every object id has its sprite file, with room for the foot offset.
func test_every_object_has_a_sprite() -> void:
	for o in WorldData.objects():
		assert_true(ResourceLoader.exists(o["sprite"]), o["sprite"])
		var tex: Texture2D = load(o["sprite"])
		if tex != null:
			assert_true(tex.get_height() > IsoLayer.OBJECT_FOOT_PX, o["id"])
