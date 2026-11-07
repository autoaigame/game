extends TestCase

## Chunks are built in small steps (client/chunk_job.gd) so walking into new chunks never freezes a frame.


## A chunk whose cells include a hand-made place, so sliced generation is checked on places too.
func _chunk_with_place() -> Vector2i:
	for r in 40:
		for rx in range(-r, r + 1):
			for ry in [-r, r]:
				var rect := Rect2i(Vector2i(rx, ry) * WorldPlaces.REGION, Vector2i.ONE * WorldPlaces.REGION)
				var p := WorldPlaces.places_in(rect)
				if not p.is_empty():
					return MapData.chunk_of(p[0]["origin"])
	return Vector2i(0, 0)


func _cells(c: Vector2i) -> Array:
	var out := []
	for y in MapData.CHUNK:
		for x in MapData.CHUNK:
			var cell := c * MapData.CHUNK + Vector2i(x, y)
			out.append([MapData.tile_at(cell), MapData.object_index_at(cell), MapData.is_walkable(cell), MapData.place_at(cell)])
	return out


## Generating a chunk a few rows per call gives exactly what generating it at once gives.
func test_sliced_generation_matches_whole_generation() -> void:
	for c in [Vector2i(0, 0), Vector2i(-3, 5), _chunk_with_place()]:
		MapData.clear_cache()
		var whole := _cells(c)
		MapData.clear_cache()
		var calls := 1
		while not MapData.generate_step(c):
			assert_false(MapData.is_generated(c), "not generated before the last step")
			calls += 1
		assert_true(MapData.is_generated(c))
		assert_true(calls > 1, "generation is spread over several calls")
		assert_true(MapData.ROWS_PER_STEP < MapData.CHUNK)
		assert_eq(_cells(c), whole, "chunk %s" % c)
	MapData.clear_cache()


## A chunk read halfway through its sliced generation is generated whole, with the same result.
func test_reading_a_half_generated_chunk() -> void:
	var c := Vector2i(4, 4)
	MapData.clear_cache()
	var whole := _cells(c)
	MapData.clear_cache()
	MapData.generate_step(c)
	assert_eq(_cells(c), whole)
	assert_true(MapData.generate_step(c), "already generated")
	MapData.clear_cache()


func _describe(node: Node) -> Array:
	var out := ["" if String(node.name).begins_with("@") else String(node.name), node.get_class(), node.z_index]
	if node is Node2D:
		out.append(node.position)
	if node is Sprite2D:
		out.append_array([node.texture, node.flip_h, node.offset])
	if node is TileMapLayer:
		var cells := []
		for d in node.get_used_cells():
			cells.append([d, node.get_cell_atlas_coords(d)])
		cells.sort()
		out.append_array([cells, node.material])
	for ch in node.get_children():
		out.append(_describe(ch))
	return out


## The chunk node built all at once, the way ChunkView.build did before chunks were built in steps.
func _reference(c: Vector2i, tex: Texture2D) -> Node2D:
	var node := ChunkView.new_node(c)
	ChunkView.add_objects(node, c)
	var decals := ChunkView.new_decals_node()
	for d in Decals.in_chunk(c):
		decals.add_child(ChunkView.decal_sprite(d[0], d[1]))
	node.add_child(decals)
	var ground := ChunkView.ground_tiles(c)
	var order := ground.keys()
	order.sort()
	for t in order:
		node.add_child(ChunkView.ground_layer(t, ground[t], tex))
	return node


## The job builds exactly the node the whole-chunk functions give, in many small steps.
func test_job_builds_the_chunk_in_many_steps() -> void:
	var tex: Texture2D = load(IsoLayer.TILES_ATLAS)
	var c := _chunk_with_place()
	var want := _reference(c, tex)
	MapData.clear_cache()
	WorldPlaces.clear_cache()
	var job := ChunkJob.new(c, tex)
	var steps := 1
	while not job.step():
		steps += 1
	assert_true(steps >= 2 * MapData.CHUNK, "a chunk takes many small steps: %d" % steps)
	assert_true(job.is_done())
	assert_eq(_describe(job.node), _describe(want))
	want.free()
	job.node.free()


## Every ground layer of every chunk uses the same TileSet, instead of building one per layer.
func test_layers_share_one_tileset() -> void:
	var tex: Texture2D = load(IsoLayer.TILES_ATLAS)
	var a := ChunkView.build(Vector2i(0, 0), tex)
	var b := ChunkView.build(Vector2i(1, 0), tex)
	var sets := {}
	for n in [a, b]:
		for l in n.get_children():
			if l is TileMapLayer:
				sets[l.tile_set] = true
	assert_eq(sets.size(), 1)
	a.free()
	b.free()


## A finished or dropped job is freed with its last reference (its steps must not keep it alive).
func test_jobs_do_not_leak() -> void:
	var job := ChunkJob.new(Vector2i(0, 0), null)
	var node := job.run_all()
	var ref: WeakRef = weakref(job)
	job = null
	assert_true(ref.get_ref() == null, "finished job freed")
	node.free()
	job = ChunkJob.new(Vector2i(0, 0), null)
	job.step()
	job.cancel()
	ref = weakref(job)
	job = null
	assert_true(ref.get_ref() == null, "cancelled job freed")
