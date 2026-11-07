extends TestCase

## Ground transitions on the dual grid (client/dual_grid.gd, client/chunk_view.gd).


func test_corner_cells_are_nw_ne_sw_se() -> void:
	assert_eq(DualGrid.corner_cells(Vector2i(5, -2)),
			[Vector2i(4, -3), Vector2i(5, -3), Vector2i(4, -2), Vector2i(5, -2)] as Array[Vector2i])


func test_mask_bits_are_nw3_ne2_sw1_se0() -> void:
	assert_eq([DualGrid.NW, DualGrid.NE, DualGrid.SW, DualGrid.SE], [8, 4, 2, 1])
	assert_eq(DualGrid.mask_at_least([1, 0, 0, 0], 1), 8)
	assert_eq(DualGrid.mask_at_least([0, 0, 0, 1], 1), 1)
	assert_eq(DualGrid.mask_at_least([0, 1, 1, 0], 1), 6)


func test_one_ground_is_one_full_tile() -> void:
	assert_eq(DualGrid.layers([2, 2, 2, 2]), [[2, DualGrid.FULL]])


func test_higher_ground_covers_its_corners() -> void:
	# the two north corners are priority 3 over a priority 0 ground
	assert_eq(DualGrid.layers([3, 3, 0, 0]), [[0, DualGrid.FULL], [3, DualGrid.NW | DualGrid.NE]])
	assert_eq(DualGrid.layers([0, 0, 0, 4]), [[0, DualGrid.FULL], [4, DualGrid.SE]])


## Each layer covers the corners at or above its priority: a middle ground also fills under the top one.
func test_three_grounds_stack() -> void:
	assert_eq(DualGrid.layers([0, 5, 3, 5]), [
		[0, DualGrid.FULL],
		[3, DualGrid.NE | DualGrid.SW | DualGrid.SE],
		[5, DualGrid.NE | DualGrid.SE],
	])


## The drawn tiles of neighbouring chunks never overlap and leave no gap: every drawn tile of the area
## has exactly one full base tile, from exactly one chunk.
func test_chunks_partition_the_drawn_tiles() -> void:
	var owner := {}
	for cy in range(-1, 1):
		for cx in range(-1, 1):
			var g := ChunkView.ground_tiles(Vector2i(cx, cy))
			for t in g:
				for d in g[t]:
					if IsoLayer.mask_of_column(g[t][d].x) != DualGrid.FULL:
						continue
					assert_false(owner.has(d), "%s drawn twice" % d)
					owner[d] = Vector2i(cx, cy)
	assert_eq(owner.size(), 4 * MapData.CHUNK * MapData.CHUNK)


## Built separately, in any order and with or without the neighbours cached, a chunk is the same.
func test_chunk_does_not_depend_on_build_order() -> void:
	var a := Vector2i(7, -3)
	var b := Vector2i(6, -3)
	MapData.clear_cache()
	var a_alone := ChunkView.ground_tiles(a)
	MapData.clear_cache()
	ChunkView.ground_tiles(b)
	var a_after_b := ChunkView.ground_tiles(a)
	assert_eq(a_after_b, a_alone)


## On a chunk's left edge, drawn tiles take the grounds of the chunk on the left into account.
func test_edge_tiles_use_the_neighbour_chunk() -> void:
	var found := false
	for cx in range(0, 60):
		var chunk := Vector2i(cx, 4)
		var o := chunk * MapData.CHUNK
		for y in MapData.CHUNK:
			var d := o + Vector2i(0, y)
			var left_t := MapData.tile_at(d + Vector2i(-1, 0))  # in the chunk on the left
			if left_t == MapData.tile_at(d) or left_t == MapData.tile_at(d + Vector2i(-1, -1)) \
					or left_t == MapData.tile_at(d + Vector2i(0, -1)):
				continue
			found = true
			var g := ChunkView.ground_tiles(chunk)
			assert_true(g.has(left_t) and g[left_t].has(d), "%s ignores ground %d of its left cell" % [d, left_t])
			if g.has(left_t) and g[left_t].has(d) and left_t > MapData.tile_at(d):
				assert_true(g[left_t][d].x & DualGrid.SW != 0, "SW corner not covered at %s" % d)
			break
		if found:
			break
	assert_true(found, "no chunk edge with a distinct ground on its left")


func test_layers_use_the_tile_atlas_row() -> void:
	var g := ChunkView.ground_tiles(Vector2i(0, 0))
	for t in g:
		for d in g[t]:
			assert_eq(g[t][d].y, WorldData.tile(t)["atlas"])



## Full tiles pick one of the ground's variants from a hash of the drawn tile: stable, in range, all used.
func test_full_variant_is_stable_and_spread() -> void:
	var seen := {}
	for i in 2000:
		var d := Vector2i(i * 7 - 7000, 300 - i * 3)
		var v := DualGrid.full_variant(d, 4)
		assert_true(v >= 0 and v < 4, str(v))
		assert_eq(DualGrid.full_variant(d, 4), v)
		seen[v] = seen.get(v, 0) + 1
	for v in 4:
		assert_true(seen.get(v, 0) > 350, "variant %d used %d times" % [v, seen.get(v, 0)])
	assert_eq(DualGrid.full_variant(Vector2i(5, 5), 1), 0)


## Neighbouring full tiles do not all share a variant (no visible stripes).
func test_neighbouring_variants_differ() -> void:
	var same := 0
	for i in 400:
		if DualGrid.full_variant(Vector2i(i, 0), 4) == DualGrid.full_variant(Vector2i(i + 1, 0), 4):
			same += 1
	assert_true(same < 160, "%d of 400 neighbours share a variant" % same)


func test_atlas_columns_for_masks_and_variants() -> void:
	assert_eq(IsoLayer.atlas_column(5, 0), 5)
	assert_eq(IsoLayer.atlas_column(DualGrid.FULL, 0), DualGrid.FULL)
	assert_eq(IsoLayer.atlas_column(DualGrid.FULL, 1), IsoLayer.MASK_COLUMNS)
	assert_eq(IsoLayer.atlas_column(DualGrid.FULL, 3), IsoLayer.MASK_COLUMNS + 2)
	for v in IsoLayer.MAX_FULL_VARIANTS:
		assert_eq(IsoLayer.mask_of_column(IsoLayer.atlas_column(DualGrid.FULL, v)), DualGrid.FULL)
	assert_eq(IsoLayer.mask_of_column(6), 6)


## A chunk's full tiles use the variant chosen for their drawn tile; masked tiles keep their mask column.
func test_chunk_full_tiles_use_their_variant() -> void:
	var chunk := Vector2i(2, 2)  # meadow: mostly full grass tiles
	var g := ChunkView.ground_tiles(chunk)
	var full := 0
	for t in g:
		var count: int = WorldData.tile(t)["full_variants"]
		for d in g[t]:
			var col: int = g[t][d].x
			if IsoLayer.mask_of_column(col) == DualGrid.FULL:
				assert_eq(col, IsoLayer.atlas_column(DualGrid.FULL, DualGrid.full_variant(d, count)), str(d))
				full += 1
			else:
				assert_true(col < DualGrid.FULL, "masked tile at %s in column %d" % [d, col])
	assert_true(full > 100)


func test_tiles_declare_variants() -> void:
	for t in WorldData.tiles():
		assert_true(t["full_variants"] >= 1 and t["full_variants"] <= IsoLayer.MAX_FULL_VARIANTS, t["id"])
		assert_eq(t["mask_variants"], 1, "variants per mask are not implemented yet: " + t["id"])
	assert_eq(WorldData.tile(WorldData.tile_index("grass"))["full_variants"], 13)
