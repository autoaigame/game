extends TestCase

## The menu art drawn by art/ui_menu.gd (assets/ui/) and how client/ui_theme.gd and the start menu
## (client/login_ui.gd) show it.

const UiMenu := preload("res://art/ui_menu.gd")
const LoginUi := preload("res://client/login_ui.gd")


## The committed PNGs are what art/ui_menu.gd draws: change it, then run `make art`.
func test_menu_art_matches_its_generator() -> void:
	var drawn: Dictionary = UiMenu.all()
	for path in drawn:
		assert_true(ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var a: Image = drawn[path]
		var b: Image = load(path).get_image()
		b.convert(Image.FORMAT_RGBA8)
		assert_eq(b.get_size(), a.get_size(), path)
		if b.get_size() != a.get_size():
			continue
		var diff := 0
		for y in a.get_height():
			for x in a.get_width():
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.a - cb.a) > 0.01 or (ca.a > 0.0 and not ca.is_equal_approx(cb)):
					diff += 1
		assert_eq(diff, 0, "%s is out of date: run make art" % path)


## Every pixel is opaque or clear, and a colour of the kit or one of the three ambers.
func test_menu_art_stays_in_the_palette() -> void:
	var allowed := {}
	for c in UiMenu.palette()["warm"]:
		allowed[(c as Color).to_rgba32()] = true
	var drawn: Dictionary = UiMenu.all()
	for path in drawn:
		var img: Image = drawn[path]
		var off := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				if c.a < 1.0 or not allowed.has(c.to_rgba32()):
					off += 1
		assert_eq(off, 0, "%s has pixels off the palette" % path)


## Each frame holds its kept corners and ends plus exactly one period of its edges, and the theme
## slices it at those margins, so only that period repeats.
func test_frames_are_sliced_at_their_ends() -> void:
	var frames := {
		"panel": [UiMenu.PANEL_MARGINS, UiMenu.PANEL_PERIOD.size],
		"title_band": [null, UiMenu.BAND_PERIOD.size],
	}
	for state in ["normal", "hover", "pressed", "disabled"]:
		frames["button_" + state] = [UiMenu.BUTTON_MARGINS, UiMenu.BUTTON_PERIOD.size]
	for key in frames:
		var tex: Texture2D = load(UiTheme.DIR + key + ".png")
		var m: Array = UiTheme.SLICES[key]
		var period: Vector2i = frames[key][1]
		if frames[key][0] != null:
			assert_eq(m, frames[key][0], key)
		assert_eq(int(tex.get_width()), m[0] + period.x + m[2], "%s width" % key)
		if key != "title_band":  # shown at its own height (test_ui_theme.gd)
			assert_eq(int(tex.get_height()), m[1] + period.y + m[3], "%s height" % key)
	var band: Texture2D = load(UiTheme.DIR + "title_band.png")
	var bm: Array = UiTheme.SLICES["title_band"]
	assert_eq(bm[0], bm[2], "the band's ends are mirrored")
	assert_eq(int(band.get_width()) - bm[0] - bm[2], UiMenu.BAND_PERIOD.size.x)


## The tiles repeat at one texel per pixel (TILE_FIT would stretch the rivets).
func test_frames_tile_without_stretching() -> void:
	for key in ["panel", "button_normal", "title_band"]:
		var sb: StyleBoxTexture = UiTheme.box(key, 4)
		assert_eq(sb.axis_stretch_horizontal, StyleBoxTexture.AXIS_STRETCH_MODE_TILE, key)
		assert_eq(sb.axis_stretch_vertical, StyleBoxTexture.AXIS_STRETCH_MODE_TILE, key)


## The button's kept ends fit the smallest buttons of the menus (the settings tabs, 34 px high), and its
## text stays clear of the lens and the mossy end.
func test_buttons_fit_their_ends() -> void:
	var m: Array = UiTheme.SLICES["button_normal"]
	assert_true(m[1] + m[3] <= 34, "button ends %s" % [m])
	var t := UiTheme.build()
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = t.get_stylebox(state, "Button")
		assert_true(sb.content_margin_left >= m[0], "%s text clear of the lens" % state)
		assert_true(sb.content_margin_right >= m[2], "%s text clear of the end" % state)
	var h := ThemeDB.fallback_font.get_height(UiTheme.BUTTON_SIZE)
	assert_true(t.get_stylebox("normal", "Button").get_minimum_size().y + h <= 44, "Jouer stays 44 px high")


## The four states of a button differ; the lens is dim at rest and lit under the pointer.
func test_button_states_differ() -> void:
	var imgs := {}
	for state in ["normal", "hover", "pressed", "disabled"]:
		imgs[state] = (load(UiTheme.DIR + "button_" + state + ".png") as Texture2D).get_image().get_data()
	for a in imgs:
		for b in imgs:
			if a < b:
				assert_true(imgs[a] != imgs[b], "%s and %s look the same" % [a, b])
	var normal: Image = load(UiTheme.DIR + "button_normal.png").get_image()
	var hover: Image = load(UiTheme.DIR + "button_hover.png").get_image()
	var lit := Color.html(UiMenu.AMBER[2])
	var lit_normal := 0
	var lit_hover := 0
	for y in UiMenu.LENS.size.y:
		for x in UiMenu.LENS.size.x:
			lit_normal += int(normal.get_pixel(x, y).is_equal_approx(lit))
			lit_hover += int(hover.get_pixel(x, y).is_equal_approx(lit))
	assert_eq(lit_normal, 0, "the lens is dim at rest")
	assert_true(lit_hover > 0, "the lens lights up under the pointer")


## The keyboard focus is a frame just outside the control.
func test_focus_frame_sits_outside() -> void:
	var sb := UiTheme.box("focus", 0)
	assert_true(sb is StyleBoxTexture)
	assert_false((sb as StyleBoxTexture).draw_center)
	assert_true((sb as StyleBoxTexture).get_expand_margin(SIDE_LEFT) > 0.0)


## The backdrop fills the 960x540 view at a whole number of pixels per texel.
func test_backdrop_fills_the_view() -> void:
	var tex := UiTheme.picture("title_bg")
	assert_true(tex != null, "assets/ui/title_bg.png")
	if tex == null:
		return
	var view := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	assert_eq(Vector2i(tex.get_size()) * UiTheme.BACKDROP_SCALE, view)


## The logo is shown at LOGO_SCALE whole pixels per texel on the title screen, at 1 above the other
## screens; the tagline and the gap that sends the buttons down only show on the title screen.
func test_logo_on_the_title_screen_only_at_its_scale() -> void:
	var tex := UiTheme.picture("logo")
	assert_true(tex != null, "assets/ui/logo.png")
	if tex == null:
		return
	assert_true(UiTheme.LOGO_SCALE >= 2)
	var ui: CanvasLayer = LoginUi.new()
	ui._build()
	ui._lay_out(true)
	assert_eq(ui._logo_art.custom_minimum_size, tex.get_size() * UiTheme.LOGO_SCALE)
	assert_true(ui._tagline.visible and ui._title_gap.visible)
	ui._lay_out(false)
	assert_eq(ui._logo_art.custom_minimum_size, tex.get_size())
	assert_false(ui._tagline.visible or ui._title_gap.visible)
	ui.free()


## The settings opened from the start menu hide its column, not the backdrop behind it.
func test_backdrop_stays_behind_the_settings() -> void:
	var ui: CanvasLayer = LoginUi.new()
	ui._build()
	var backdrop: Control = ui._root.get_child(0)
	assert_true(backdrop is TextureRect, "the colossus, not the world")
	ui._on_settings_opened()
	assert_true(ui._root.visible and backdrop.visible)
	assert_false(ui._center.visible)
	ui.free()
