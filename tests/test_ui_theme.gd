extends TestCase


## Every 9-slice of the theme has its PNG, with margins that leave a middle to repeat.
func test_every_slice_has_its_art() -> void:
	for key in UiTheme.SLICES:
		var path: String = UiTheme.DIR + key + ".png"
		assert_true(ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var size: Vector2 = (load(path) as Texture2D).get_size()
		var m: Array = UiTheme.SLICES[key]
		assert_true(m[0] + m[2] < size.x and m[1] + m[3] < size.y, "%s margins %s in %s" % [key, m, size])
		assert_true(UiTheme.box(key, 4) is StyleBoxTexture, key)


func test_status_icons_exist() -> void:
	for key in ["wait", "ok", "error"]:
		assert_true(UiTheme.icon(key) != null, key)


## The title band is drawn at the height of its art, so its torn ends are never repeated.
func test_title_band_is_shown_at_its_own_height() -> void:
	var tex: Texture2D = load(UiTheme.DIR + "title_band.png")
	assert_eq(int(tex.get_size().y), UiTheme.TITLE_BAND_H)
	var band: StyleBox = UiTheme.build().get_stylebox("panel", "TitleBand")
	var title_h := UiTheme.build().default_font.get_height(UiTheme.TITLE_SIZE) if UiTheme.build().default_font else ThemeDB.fallback_font.get_height(UiTheme.TITLE_SIZE)
	assert_true(band.get_minimum_size().y + title_h <= UiTheme.TITLE_BAND_H,
			"band %s + title %s > %d" % [band.get_minimum_size().y, title_h, UiTheme.TITLE_BAND_H])


func test_pressed_button_moves_its_text_down() -> void:
	var t := UiTheme.build()
	assert_true(t.get_stylebox("pressed", "Button").content_margin_top
			> t.get_stylebox("normal", "Button").content_margin_top)
