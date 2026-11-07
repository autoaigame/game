extends TestCase

## The ground atlas, the player sheet and the generated sprites.


func test_tiles_are_96_by_48() -> void:
	# PixelLab's isometric tiles are 96x48, drawn at 1 texel per pixel (integer camera zoom).
	assert_eq(IsoLayer.TILE_SIZE, Vector2i(96, 48))
	assert_eq(IsoLayer.CAMERA_ZOOM, float(int(IsoLayer.CAMERA_ZOOM)), "the camera zoom must be an integer")


## One row per ground (data/tiles "atlas"), one column per DualGrid corner mask, then full variants.
func test_tiles_atlas_has_a_row_per_ground_and_a_column_per_mask() -> void:
	var tex: Texture2D = load("res://assets/tiles.png")
	assert_eq(tex.get_width(), IsoLayer.TILE_SIZE.x * IsoLayer.ATLAS_COLUMNS)
	assert_eq(tex.get_height(), IsoLayer.TILE_SIZE.y * WorldData.tiles().size())
	var rows := {}
	for t in WorldData.tiles():
		assert_false(rows.has(t["atlas"]), "two tiles on atlas row %d" % t["atlas"])
		rows[t["atlas"]] = true
		assert_true(t["atlas"] >= 0 and t["atlas"] < WorldData.tiles().size(), t["id"])


## Mask 0 is empty. Near each corner of the diamond, a tile is opaque exactly when the mask has that
## corner's bit (DualGrid: top = NW, right = NE, bottom = SE, left = SW).
func test_mask_tiles_follow_the_corner_bits() -> void:
	var img: Image = load("res://assets/tiles.png").get_image()
	var w := IsoLayer.TILE_SIZE.x
	var h := IsoLayer.TILE_SIZE.y
	var probes := [Vector2i(w / 2, h / 8), Vector2i(w - w / 7, h / 2), Vector2i(w / 2, h - h / 7), Vector2i(w / 7, h / 2)]
	var bits := [DualGrid.NW, DualGrid.NE, DualGrid.SE, DualGrid.SW]
	var lowest_row: int = WorldData.tiles()[0]["atlas"]
	for row in img.get_height() / h:
		var empty := img.get_region(Rect2i(0, row * h, w, h))
		assert_true(empty.is_invisible(), "row %d mask 0 is not empty" % row)
		if row == lowest_row:
			continue  # the lowest ground is always drawn full: its mask columns are not used
		for mask in range(1, IsoLayer.MASK_COLUMNS):
			for i in 4:
				var p: Vector2i = probes[i] + Vector2i(mask * w, row * h)
				var opaque := img.get_pixelv(p).a == 1.0
				assert_eq(opaque, mask & bits[i] != 0, "row %d mask %d corner %d" % [row, mask, i])


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


## Each ground has its declared number of full tile variants, all different; the unused variant
## columns are empty. Every full tile covers every point of the tile lattice, so neighbours leave no
## gap. PixelLab's tiles also draw one extra row on their edge, so overlaps are allowed (the old
## "exactly once" rule held for the generated art only).
func test_full_variants_are_drawn_and_leave_no_gap() -> void:
	var img: Image = load("res://assets/tiles.png").get_image()
	var w := IsoLayer.TILE_SIZE.x
	var h := IsoLayer.TILE_SIZE.y
	for t in WorldData.tiles():
		var row: int = t["atlas"]
		var seen_tiles := {}
		for v in IsoLayer.MAX_FULL_VARIANTS:
			var col := IsoLayer.atlas_column(DualGrid.FULL, v)
			var tile := img.get_region(Rect2i(col * w, row * h, w, h))
			if v >= t["full_variants"]:
				assert_true(tile.is_invisible(), "%s variant %d should be empty" % [t["id"], v])
				continue
			assert_false(seen_tiles.has(tile.get_data()), "%s variant %d repeats another" % [t["id"], v])
			seen_tiles[tile.get_data()] = true
			var covered := {}
			for y in h:
				for x in w:
					if tile.get_pixel(x, y).a == 0.0:
						continue
					# lattice coordinates of the texel centre, relative to the tile centre
					var a := (x + 0.5 - w / 2.0) / w + (y + 0.5 - h / 2.0) / h
					var b := (y + 0.5 - h / 2.0) / h - (x + 0.5 - w / 2.0) / w
					covered[Vector2i(x - (roundi(a) - roundi(b)) * w / 2, y - (roundi(a) + roundi(b)) * h / 2)] = true
			assert_eq(covered.size(), w * h / 2, "%s variant %d leaves gaps" % [t["id"], v])
