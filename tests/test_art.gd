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
	for row in img.get_height() / h:
		var empty := img.get_region(Rect2i(0, row * h, w, h))
		assert_true(empty.is_invisible(), "row %d mask 0 is not empty" % row)
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


## Neighbouring tiles are offset by (w/2, h/2) and (-w/2, h/2). Each full tile (mask 15) must
## cover exactly one texel per point of that lattice: no gaps, no overlaps.
func test_tiles_cover_the_plane_exactly_once() -> void:
	var img: Image = load("res://assets/tiles.png").get_image()
	var w := IsoLayer.TILE_SIZE.x
	var h := IsoLayer.TILE_SIZE.y
	for row in img.get_height() / h:
		var seen := {}
		var overlaps := 0
		var ox := DualGrid.FULL * w
		var oy := row * h
		for y in h:
			for x in w:
				if img.get_pixel(ox + x, oy + y).a == 0.0:
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
		assert_eq(overlaps, 0, "row %d overlaps itself" % row)
		assert_eq(seen.size(), w * h / 2, "row %d leaves gaps" % row)


## Each ground has its declared number of full tile variants, all different, each covering the plane
## exactly once; the unused variant columns are empty.
func test_full_variants_are_drawn() -> void:
	var img: Image = load("res://assets/tiles.png").get_image()
	var w := IsoLayer.TILE_SIZE.x
	var h := IsoLayer.TILE_SIZE.y
	for t in WorldData.tiles():
		var row: int = t["atlas"]
		var seen := {}
		for v in IsoLayer.MAX_FULL_VARIANTS:
			var col := IsoLayer.atlas_column(DualGrid.FULL, v)
			var tile := img.get_region(Rect2i(col * w, row * h, w, h))
			if v >= t["full_variants"]:
				assert_true(tile.is_invisible(), "%s variant %d should be empty" % [t["id"], v])
				continue
			assert_false(seen.has(tile.get_data()), "%s variant %d repeats another" % [t["id"], v])
			seen[tile.get_data()] = true
			var opaque := 0
			for y in h:
				for x in w:
					if tile.get_pixel(x, y).a > 0.0:
						opaque += 1
			assert_eq(opaque, w * h / 2, "%s variant %d does not fill its diamond" % [t["id"], v])


## Variants agree with variant 0 along the tile edges, so any two of them join without a seam.
func test_full_variants_share_their_edges() -> void:
	var img: Image = load("res://assets/tiles.png").get_image()
	var w := IsoLayer.TILE_SIZE.x
	var h := IsoLayer.TILE_SIZE.y
	for t in WorldData.tiles():
		var row: int = t["atlas"]
		for v in range(1, t["full_variants"]):
			var col := IsoLayer.atlas_column(DualGrid.FULL, v)
			var diff := 0
			for y in h:
				for x in w:
					var a := (x + 0.5 - w / 2.0) / w + (y + 0.5 - h / 2.0) / h
					var b := (y + 0.5 - h / 2.0) / h - (x + 0.5 - w / 2.0) / w
					if 0.5 - maxf(absf(a), absf(b)) > 0.02 or absf(a) >= 0.5 or absf(b) >= 0.5:
						continue
					if img.get_pixel(col * w + x, row * h + y) != img.get_pixel(15 * w + x, row * h + y):
						diff += 1
			assert_eq(diff, 0, "%s variant %d differs from variant 0 on its edge" % [t["id"], v])
