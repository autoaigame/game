extends TestCase

## The ground shadows baked into the object sprites (assets/objects, art/object_shadows.gd).

const SHADOWS := preload("res://art/object_shadows.gd")


## A shadow that hangs below the base makes the object look like it floats: the shadow must sit
## mostly behind the base and only peek out below it, and touch the base.
func test_shadows_sit_under_the_base() -> void:
	for path in SHADOWS.sprites():
		var img: Image = load(path).get_image()
		var anchor: Vector2 = SHADOWS.sprites()[path]
		var lowest := -1
		var left := img.get_width()
		var right := -1
		var touches := false
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				if a <= 0.0 or a >= 1.0:
					continue
				lowest = maxi(lowest, y)
				left = mini(left, x)
				right = maxi(right, x)
				if absf(y - anchor.y) <= 4 and _next_to_opaque(img, x, y):
					touches = true
		assert_true(lowest >= 0, "%s has no shadow" % path)
		var below := lowest - anchor.y
		var width := right - left + 1
		assert_true(below <= 0.18 * width,
				"%s: shadow reaches %d px below the base for a %d px wide shadow" % [path, below, width])
		assert_true(touches, "%s: the shadow does not touch the base" % path)


## The committed PNGs carry the shadow the script draws: change art/object_shadows.gd, then run it.
func test_sprites_match_the_shadow_script() -> void:
	for path in SHADOWS.sprites():
		var file: Image = load(path).get_image()
		file.convert(Image.FORMAT_RGBA8)
		var name: String = path.get_file()
		assert_true(SHADOWS.RADII.has(name), "%s has no shadow radii in art/object_shadows.gd" % name)
		if not SHADOWS.RADII.has(name):
			continue
		var drawn: Image = SHADOWS.rebake(file, SHADOWS.sprites()[path], SHADOWS.RADII[name])
		var diff := 0
		for y in drawn.get_height():
			for x in drawn.get_width():
				var a := drawn.get_pixel(x, y)
				var b := file.get_pixel(x, y)
				# the importer recolours fully transparent pixels (fix_alpha_border): compare colour where visible
				if absf(a.a - b.a) > 0.01 or (a.a > 0.0 and not a.is_equal_approx(b)):
					diff += 1
		assert_eq(diff, 0, "%s is out of date: run art/object_shadows.gd" % path)


func _next_to_opaque(img: Image, x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var p: Vector2i = Vector2i(x, y) + d
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height() \
				and img.get_pixel(p.x, p.y).a >= 1.0:
			return true
	return false
