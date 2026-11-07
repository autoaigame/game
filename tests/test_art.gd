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


## The player sheet: SHEET_COLUMNS facings x (idle frames + walk frames) of FRAME_SIZE.
func test_player_sheet_layout() -> void:
	var tex: Texture2D = load("res://assets/player.png")
	assert_eq(Vector2i(tex.get_width(), tex.get_height()),
			Vector2i(WalkAnim.FRAME_SIZE.x * WalkAnim.SHEET_COLUMNS, WalkAnim.FRAME_SIZE.y * WalkAnim.SHEET_ROWS))


## Every frame of every facing is drawn, and differs from the others of its facing.
func test_player_frames_are_all_different() -> void:
	var img: Image = load("res://assets/player.png").get_image()
	var f := WalkAnim.FRAME_SIZE
	for col in WalkAnim.SHEET_COLUMNS:
		var seen := {}
		for row in WalkAnim.SHEET_ROWS:
			var frame := img.get_region(Rect2i(col * f.x, row * f.y, f.x, f.y))
			assert_false(frame.is_invisible(), "column %d row %d is empty" % [col, row])
			var key := frame.get_data()
			assert_false(seen.has(key), "column %d row %d repeats an earlier frame" % [col, row])
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


## Top and bottom rows with an opaque pixel (alpha over half) in one frame of the player sheet.
static func _frame_rows(img: Image, col: int, row: int) -> Vector2i:
	var f := WalkAnim.FRAME_SIZE
	var top := -1
	var bottom := -1
	for y in f.y:
		for x in f.x:
			if img.get_pixel(col * f.x + x, row * f.y + y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	return Vector2i(top, bottom)


## Same character, same size: in every facing, the head of every walk frame is within 3 px of the
## height of the standing frames (the old sheet walked 5 px taller facing north and north-west).
func test_player_walks_at_the_size_it_stands() -> void:
	var img: Image = load("res://assets/player.png").get_image()
	for col in WalkAnim.SHEET_COLUMNS:
		var idle_top := 0.0
		for row in WalkAnim.IDLE_FRAMES:
			idle_top += _frame_rows(img, col, row).x
		idle_top /= WalkAnim.IDLE_FRAMES
		for i in WalkAnim.WALK_FRAMES:
			var top := _frame_rows(img, col, WalkAnim.WALK_FIRST_ROW + i).x
			assert_true(absf(top - idle_top) <= 3.0, "%s walk frame %d: head at %d, standing at %.1f" %
					[WalkAnim.FACINGS[col], i, top, idle_top])


## Standing, the feet are on the anchor (FOOT_PX above the frame's bottom) give or take the shape of
## the boots, and the head is no higher than HEAD_PX above it.
func test_player_stands_on_the_anchor() -> void:
	var img: Image = load("res://assets/player.png").get_image()
	var foot_y := WalkAnim.FRAME_SIZE.y - WalkAnim.FOOT_PX
	for col in WalkAnim.SHEET_COLUMNS:
		for row in WalkAnim.SHEET_ROWS:
			var r := _frame_rows(img, col, row)
			assert_true(foot_y - r.x <= WalkAnim.HEAD_PX, "%s row %d: head %d px above the feet" %
					[WalkAnim.FACINGS[col], row, foot_y - r.x])
			if row < WalkAnim.IDLE_FRAMES:
				assert_true(r.y >= foot_y and r.y <= foot_y + 10, "%s idle %d: bottom at %d, feet at %d" %
						[WalkAnim.FACINGS[col], row, r.y, foot_y])
