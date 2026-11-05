extends TestCase

## The art is drawn at 4x the original 32x16 tile / 16x24 character size.


func test_tiles_are_high_resolution() -> void:
	assert_eq(IsoLayer.TILE_SIZE, Vector2i(128, 64))


func test_tiles_atlas_matches_tile_size() -> void:
	var tex: Texture2D = load("res://assets/tiles.png")
	assert_eq(tex.get_height(), IsoLayer.TILE_SIZE.y)
	assert_eq(tex.get_width() % IsoLayer.TILE_SIZE.x, 0)
	assert_eq(tex.get_width() / IsoLayer.TILE_SIZE.x, 3, "one tile per MapData.TILE_*")


func test_player_frames_are_high_resolution() -> void:
	var tex: Texture2D = load("res://assets/player.png")
	# 4 directions x (standing + the walk cycle) of 64x96
	assert_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(64 * 4, 96 * (1 + WalkAnim.WALK_FRAMES)))


## Every walk frame of every direction is drawn, and differs from the standing pose and from each other.
func test_walk_frames_are_all_different() -> void:
	var img: Image = load("res://assets/player.png").get_image()
	var rows := img.get_height() / 96
	for dir in 4:
		var seen := {}
		for row in rows:
			var frame := img.get_region(Rect2i(dir * 64, row * 96, 64, 96))
			assert_false(frame.is_invisible(), "direction %d row %d is empty" % [dir, row])
			var key := frame.get_data()
			assert_false(seen.has(key), "direction %d row %d repeats an earlier frame" % [dir, row])
			seen[key] = true


## Neighbouring tiles are offset by (w/2, h/2) and (-w/2, h/2). Each tile must
## cover exactly one texel per point of that lattice: no gaps, no overlaps.
func test_tiles_cover_the_plane_exactly_once() -> void:
	var img: Image = load("res://assets/tiles.png").get_image()
	var w := IsoLayer.TILE_SIZE.x
	var h := IsoLayer.TILE_SIZE.y
	for t in img.get_width() / w:
		var seen := {}
		var overlaps := 0
		for y in h:
			for x in w:
				if img.get_pixel(t * w + x, y).a == 0.0:
					continue
				# lattice coordinates of the texel centre, relative to the tile centre
				var a := (x + 0.5 - w / 2.0) / w + (y + 0.5 - h / 2.0) / h
				var b := (y + 0.5 - h / 2.0) / h - (x + 0.5 - w / 2.0) / w
				var na := roundi(a)
				var nb := roundi(b)
				var key := Vector2i(x - (na - nb) * w / 2, y - (na + nb) * h / 2)
				if seen.has(key):
					overlaps += 1
				seen[key] = true
		assert_eq(overlaps, 0, "tile %d overlaps itself" % t)
		assert_eq(seen.size(), w * h / 2, "tile %d leaves gaps" % t)
