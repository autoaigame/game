extends TestCase

## Trees are drawn ChunkView.TREE_SCALE times their sprites' size, standing on their cell; a tree can
## tell which of its pixels hide what is behind (client/chunk_view.gd). Display only.


## A test tree: a 21 x 101 px sprite, opaque but for a translucent shadow row at the bottom and a
## transparent left half above y 50; its anchor is the bottom centre of the opaque part.
static func hand_tree(pos: Vector2, scale: float) -> Sprite2D:
	var img := Image.create(21, 101, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.1, 1.0))
	for x in 21:
		img.set_pixel(x, 100, Color(0.08, 0.09, 0.06, 0.3))  # ground shadow
		if x < 10:
			for y in 50:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var sp := Sprite2D.new()
	sp.texture = ImageTexture.create_from_image(img)
	sp.centered = false
	sp.offset = -Vector2(10, 99)
	sp.position = pos
	sp.scale = Vector2.ONE * scale
	sp.set_meta("tree", true)
	return sp


## Every species is a tree, young sprites included; rocks, bushes, stumps, walls and stones are not.
func test_which_objects_are_trees() -> void:
	for id in ["oak", "birch", "pine"]:
		assert_true(ChunkView.is_tree(WorldData.object_index(id)), id)
	for id in ["rock", "bush", "stump", "stone_wall", "standing_stone"]:
		assert_false(ChunkView.is_tree(WorldData.object_index(id)), id)
	assert_false(ChunkView.is_tree(-1), "no object")


## A tree is drawn at TREE_SCALE with its foot (anchor) still on the cell centre, and sorts by that
## centre like before; other objects keep their size.
func test_trees_are_scaled_around_their_foot() -> void:
	assert_true(ChunkView.TREE_SCALE > 1.0, "trees drawn bigger than their sprites")
	for id in ["oak", "birch", "pine"]:
		var index := WorldData.object_index(id)
		for v in WorldData.object(index)["sprites"].size():
			var cell := Vector2i(v * 3, -v)
			var tree := ChunkView.object_sprite(cell, index)
			var sp: Dictionary = WorldData.object(index)["sprites"][ChunkView.sprite_variant(cell, index)]
			assert_eq(tree.scale, Vector2.ONE * ChunkView.TREE_SCALE, id)
			assert_eq(tree.position, IsoLayer.cell_to_local(Vector2(cell)), id + ": sorts by its cell centre")
			var foot := tree.position + (tree.offset + Vector2(sp["anchor_px"])) * tree.scale
			assert_eq(foot, IsoLayer.cell_to_local(Vector2(cell)), id + ": foot on the cell centre")
			tree.free()
	var rock := ChunkView.object_sprite(Vector2i(0, 0), WorldData.object_index("rock"))
	assert_eq(rock.scale, Vector2.ONE, "a rock keeps its size")
	rock.free()


## hides(): opaque pixels hide, the transparent margin and the translucent shadow do not, at any scale.
func test_hides_on_opaque_pixels_only() -> void:
	for s in [1.0, ChunkView.TREE_SCALE]:
		var t := hand_tree(Vector2(100, 200), s)
		assert_true(ChunkView.hides(t, Vector2(100, 200 - 10 * s)), "trunk at x%.2f" % s)
		assert_true(ChunkView.hides(t, Vector2(100 + 9 * s, 200 - 90 * s)), "right of the crown at x%.2f" % s)
		assert_false(ChunkView.hides(t, Vector2(100 - 8 * s, 200 - 90 * s)), "transparent left at x%.2f" % s)
		assert_false(ChunkView.hides(t, Vector2(100, 200 + 1.5 * s)), "shadow row at x%.2f" % s)
		assert_false(ChunkView.hides(t, Vector2(100, 200 - 105 * s)), "above the top at x%.2f" % s)
		assert_false(ChunkView.hides(t, Vector2(100 + 12 * s, 200 - 10 * s)), "beside at x%.2f" % s)
		t.free()
	# the scale counts: 140 px above the foot is above an unscaled tree, inside a scaled one
	var small := hand_tree(Vector2(0, 0), 1.0)
	var big := hand_tree(Vector2(0, 0), 1.75)
	assert_false(ChunkView.hides(small, Vector2(5, -140)))
	assert_true(ChunkView.hides(big, Vector2(5, -140)))
	small.free()
	big.free()


## A mirrored sprite is read mirrored.
func test_hides_reads_a_mirrored_sprite() -> void:
	var t := hand_tree(Vector2(0, 0), 1.0)
	t.flip_h = true
	t.offset = -Vector2(10, 99)  # 21 px wide: the anchor stays at x 10 once mirrored
	assert_true(ChunkView.hides(t, Vector2(-8, -90)), "the transparent half is now on the right")
	assert_false(ChunkView.hides(t, Vector2(8, -90)))
	t.free()


## The fade goes down to TREE_FADE_ALPHA gradually, and back to 1.
func test_fade_goes_and_comes_back() -> void:
	var a := 1.0
	var b := ChunkView.fade_step(1.0, true, 1.0 / 60.0)
	assert_true(b < 1.0 and b > ChunkView.TREE_FADE_ALPHA, "gradual")
	for i in 60:
		a = ChunkView.fade_step(a, true, 1.0 / 60.0)
	assert_almost(a, ChunkView.TREE_FADE_ALPHA, 0.0001, "faded within a second")
	for i in 60:
		a = ChunkView.fade_step(a, false, 1.0 / 60.0)
	assert_eq(a, 1.0, "opaque again")
