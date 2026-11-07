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


## Every object has one or more sprites, each file present with its anchor (the point standing on
## the cell centre) inside the image.
func test_every_object_has_sprites_with_anchors() -> void:
	for o in WorldData.objects():
		assert_true(o["sprites"].size() > 0, o["id"])
		for sp in o["sprites"]:
			assert_true(ResourceLoader.exists(sp["file"]), sp["file"])
			var tex: Texture2D = load(sp["file"]) if ResourceLoader.exists(sp["file"]) else null
			if tex != null:
				var a: Vector2i = sp["anchor_px"]
				assert_true(Rect2i(Vector2i.ZERO, Vector2i(tex.get_size())).has_point(a), "%s anchor %s" % [sp["file"], a])


## A sprite's anchor lands exactly on its cell centre.
func test_object_anchor_on_the_cell_centre() -> void:
	var oak := WorldData.object_index("oak")
	var cell := Vector2i(7, -3)
	var sprite := ChunkView.object_sprite(cell, oak)
	var sp: Dictionary = WorldData.object(oak)["sprites"][ChunkView.sprite_variant(cell, oak)]
	assert_false(sprite.centered)
	assert_eq(sprite.position + sprite.offset + Vector2(sp["anchor_px"]), IsoLayer.cell_to_local(Vector2(cell)))
	sprite.free()


## Objects with several sprites pick one per cell from a hash: stable, all of them used.
func test_sprite_variant_is_stable_and_spread() -> void:
	var rock := WorldData.object_index("rock")
	var n: int = WorldData.object(rock)["sprites"].size()
	assert_true(n >= 2)
	var seen := {}
	for i in 200:
		var c := Vector2i(i * 3, -i)
		var v := ChunkView.sprite_variant(c, rock)
		assert_eq(ChunkView.sprite_variant(c, rock), v)
		assert_true(v >= 0 and v < n)
		seen[v] = true
	assert_eq(seen.size(), n)


## Trees, bushes and stumps come in several shapes so a forest is not one tree repeated, and every
## shape shows up among the objects the world actually places.
func test_trees_have_several_shapes_all_placed() -> void:
	var wanted := {"oak": 5, "pine": 5, "birch": 5, "bush": 5, "stump": 5}
	for id in wanted:
		var i := WorldData.object_index(id)
		var obj := WorldData.object(i)
		var n: int = obj["sprites"].size()
		assert_true(n >= wanted[id], "%s has %d sprites" % [id, n])
		var seen := {}
		for k in 6000:
			var g := Vector2i(k % 80 - 40, k / 80 - 40)
			if not WorldObjects.is_present(i, g):
				continue
			var cell := WorldObjects.position_in(i, g)
			if MapData.object_index_at(cell) == i:
				seen[ChunkView.sprite_variant(cell, i)] = true
		assert_eq(seen.size(), n, "%s: shapes placed %s" % [id, seen.keys()])


## No sprite floats or sinks: an opaque pixel stands within a few pixels of the anchor (the foot
## of the trunk, the base of a rock), and nothing opaque hangs more than a few pixels below it. The
## translucent ground shadow does not count.
func test_object_sprites_stand_on_their_anchor() -> void:
	for o in WorldData.objects():
		for sp in o["sprites"]:
			var img: Image = load(sp["file"]).get_image()
			var a: Vector2i = sp["anchor_px"]
			var near := false
			var lowest := -1
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a < 0.5:
						continue
					lowest = maxi(lowest, y)
					if absi(x - a.x) <= 12 and absi(y - a.y) <= 4:
						near = true
			assert_true(near, "%s: nothing opaque at its anchor %s" % [sp["file"], a])
			assert_true(lowest - a.y <= 8, "%s: opaque down to row %d, anchor at %d" % [sp["file"], lowest, a.y])


## Wall sprites run along the y axis of the grid; a wall continuing along x is mirrored.
func test_walls_follow_their_neighbours() -> void:
	var wall := WorldData.object_index("stone_wall")
	assert_true(ChunkView.mirror_wall(true, false), "x run")
	assert_false(ChunkView.mirror_wall(false, true), "y run")
	assert_false(ChunkView.mirror_wall(true, true), "corner")
	assert_false(ChunkView.mirror_wall(false, false), "alone")
	var sprite := ChunkView.object_sprite(Vector2i(0, 0), wall, true)
	assert_true(sprite.flip_h)
	var sp: Dictionary = WorldData.object(wall)["sprites"][ChunkView.sprite_variant(Vector2i(0, 0), wall)]
	# mirrored around the anchor: the anchor still lands on the cell centre
	var w: float = sprite.texture.get_width()
	assert_eq(sprite.position + sprite.offset + Vector2(w - sp["anchor_px"].x, sp["anchor_px"].y),
			IsoLayer.cell_to_local(Vector2(0, 0)))
	sprite.free()


## On a real ruin, wall_neighbours sees the run of its plan: the top row runs along x, the left
## column along y.
func test_wall_neighbours_follow_the_ruin_plan() -> void:
	var ruin := -1
	for i in WorldData.places().size():
		if WorldData.places()[i]["id"] == "ruin":
			ruin = i
	var origin: Variant = null
	for ry in range(-12, 13):
		for rx in range(-12, 13):
			var r := Vector2i(rx, ry)
			if origin == null and WorldPlaces.is_accepted(r) and WorldPlaces.candidate(r)["index"] == ruin:
				origin = WorldPlaces.candidate(r)["origin"]
	assert_true(origin != null, "no ruin found")
	if origin == null:
		return
	var wall := WorldData.object_index("stone_wall")
	assert_eq(ChunkView.wall_neighbours(origin + Vector2i(1, 0), wall), [true, false] as Array[bool], "top row")
	assert_eq(ChunkView.wall_neighbours(origin + Vector2i(0, 2), wall), [false, true] as Array[bool], "left column")
