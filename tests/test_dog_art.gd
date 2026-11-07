extends TestCase

## The dog sprite sheet (assets/dog.png, art/dog_sheet.gd) and its frames (client/dog_anim.gd).


func test_dog_sheet_layout() -> void:
	var tex: Texture2D = load("res://assets/dog.png")
	assert_eq(Vector2i(tex.get_width(), tex.get_height()),
			Vector2i(DogAnim.FRAME_SIZE.x * DogAnim.COLUMNS, DogAnim.FRAME_SIZE.y * DogAnim.ROWS.size()))


## The committed PNG is what the generator draws: change art/dog_sheet.gd, then run `make art`.
func test_dog_sheet_matches_its_generator() -> void:
	var drawn: Image = load("res://art/dog_sheet.gd").sheet()
	var file: Image = load("res://assets/dog.png").get_image()
	file.convert(Image.FORMAT_RGBA8)
	assert_eq(file.get_size(), drawn.get_size())
	var diff := 0
	for y in drawn.get_height():
		for x in drawn.get_width():
			var a := drawn.get_pixel(x, y)
			var b := file.get_pixel(x, y)
			# the importer recolours fully transparent pixels (fix_alpha_border): compare colour where visible
			if absf(a.a - b.a) > 0.01 or (a.a > 0.0 and not a.is_equal_approx(b)):
				diff += 1
	assert_eq(diff, 0, "assets/dog.png is out of date: run make art")


## Every frame is drawn, each pose differs from standing still, and moving poses change frame to frame.
func test_every_pose_is_drawn_and_distinct() -> void:
	var img: Image = load("res://art/dog_sheet.gd").sheet()
	var f := DogAnim.FRAME_SIZE
	var idle := img.get_region(Rect2i(0, 0, f.x, f.y)).get_data()
	for row in DogAnim.ROWS.size():
		var frames := {}
		for col in DogAnim.COLUMNS:
			var frame := img.get_region(Rect2i(col * f.x, row * f.y, f.x, f.y))
			assert_false(frame.is_invisible(), "%s frame %d is empty" % [DogAnim.ROWS[row], col])
			frames[frame.get_data()] = true
		var first := img.get_region(Rect2i(0, row * f.y, f.x, f.y)).get_data()
		if row > 0:
			assert_true(first != idle, "%s looks like idle" % DogAnim.ROWS[row])
		if DogAnim.ROWS[row] in ["walk", "run", "dig"]:
			assert_true(frames.size() >= 2, "%s is animated" % DogAnim.ROWS[row])


func test_frame_walks_and_runs_by_distance_and_speed() -> void:
	assert_eq(DogAnim.frame("idle", true, 4.0, 0.0, 0.0), Vector2i(0, DogAnim.row_of("walk")))
	assert_eq(DogAnim.frame("idle", true, 4.0, DogAnim.WALK_CYCLE_CELLS / 2.0, 0.0), Vector2i(2, DogAnim.row_of("walk")))
	assert_eq(DogAnim.frame("idle", true, 6.5, 0.0, 0.0).y, DogAnim.row_of("run"))


func test_frame_shows_the_pose_when_still() -> void:
	assert_eq(DogAnim.frame("idle", false, 0.0, 3.0, 0.0), Vector2i(0, DogAnim.row_of("idle")))
	assert_eq(DogAnim.frame("sleep", false, 0.0, 0.0, 1.0 / DogAnim.POSE_FPS), Vector2i(1, DogAnim.row_of("sleep")))
	assert_eq(DogAnim.frame("unknown", false, 0.0, 0.0, 0.0).y, DogAnim.row_of("idle"))


## Feet stand on the creature's position.
func test_feet_on_the_position() -> void:
	var o := DogAnim.sprite_offset()
	assert_eq(o.y + DogAnim.FRAME_SIZE.y - DogAnim.FOOT_PX, 0.0)
	assert_eq(o.x + DogAnim.FRAME_SIZE.x / 2.0, 0.0)
