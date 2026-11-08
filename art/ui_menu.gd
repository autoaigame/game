## Draws the menu art (run by `make art`) from PixelLab images kept in art/ui_menu/src/ (prompts and
## seeds in ASSETS.toml): the title screen's backdrop, the logo, the button and panel frames, the title
## band and the focus frame (assets/ui/). Every pixel is a colour of the kit (the first ten ramps of
## data/palette.json) or one of the three AMBER tones of the colossus's eye, the lenses and the rust.
## The frames are 9-slices: corners kept, and between them one short period of each edge (one rivet),
## which the theme repeats (client/ui_theme.gd SLICES).
extends RefCounted

const SRC := "res://art/ui_menu/src/"
const OUT := "res://assets/ui/"
## Dark to light. Only warm pixels (more red than green) may take them, so leaves stay green.
const AMBER := ["7a4a1e", "b8762a", "e0a845"]
const KIT_RAMPS := 10

## Opaque part of each source image: everything outside (stray leaves) is dropped.
const BUTTON_CROP := Rect2i(9, 3, 110, 35)
const PANEL_CROP := Rect2i(8, 8, 112, 112)
const PLATE_CROP := Rect2i(20, 12, 216, 40)
## Kept margins [left, top, right, bottom] and the period repeated between them, in cropped pixels.
const BUTTON_MARGINS := [22, 15, 28, 19]
const BUTTON_PERIOD := Rect2i(46, 15, 14, 1)  ## one rivet of the top and bottom strips; one row below the lens
const PANEL_MARGINS := [17, 17, 17, 17]
const PANEL_PERIOD := Rect2i(33, 36, 16, 15)  ## one rivet of each edge, clear of the vines
## The lens at the button's left end: dim at rest, lit under the pointer and when pressed.
const LENS := Rect2i(0, 0, 14, 15)
## Title band: the plate without its eye. Its grassy right end, mirrored for the left end, and one
## period of the slab between them.
const BAND_END := 186
const BAND_PERIOD := Rect2i(54, 0, 23, 40)
## The logo's plate keeps its eye; the letters go on the slab right of it.
const LOGO_TEXT := "AUTOAIGAME"
const LOGO_SLAB := Rect2i(52, 6, 156, 28)
const BACKDROP_SIZE := Vector2i(480, 270)  ## shown at x2 behind the start menu (960x540)
const FOCUS_SIZE := 12
const FOCUS_MARGIN := 4

## Letters of the logo, 15 rows, strokes 3 px wide. '#' is filled.
const GLYPHS := {
	"A": ["..#######..", ".#########.", "###.....###", "###.....###", "###.....###", "###.....###",
		"###########", "###########", "###########", "###.....###", "###.....###", "###.....###",
		"###.....###", "###.....###", "###.....###"],
	"U": ["###.....###", "###.....###", "###.....###", "###.....###", "###.....###", "###.....###",
		"###.....###", "###.....###", "###.....###", "###.....###", "###.....###", "###.....###",
		"###.....###", ".#########.", "..#######.."],
	"T": ["###########", "###########", "###########", "....###....", "....###....", "....###....",
		"....###....", "....###....", "....###....", "....###....", "....###....", "....###....",
		"....###....", "....###....", "....###...."],
	"O": ["..#######..", ".#########.", "###.....###", "###.....###", "###.....###", "###.....###",
		"###.....###", "###.....###", "###.....###", "###.....###", "###.....###", "###.....###",
		"###.....###", ".#########.", "..#######.."],
	"I": ["#######", "#######", "#######", "..###..", "..###..", "..###..", "..###..", "..###..",
		"..###..", "..###..", "..###..", "..###..", "#######", "#######", "#######"],
	"G": ["..#######..", ".#########.", "###.....###", "###.....###", "###........", "###........",
		"###...#####", "###...#####", "###...#####", "###.....###", "###.....###", "###.....###",
		"###.....###", ".#########.", "..#######.."],
	"M": ["####.....####", "#####...#####", "######.######", "###.#####.###", "###..###..###",
		"###...#...###", "###.......###", "###.......###", "###.......###", "###.......###",
		"###.......###", "###.......###", "###.......###", "###.......###", "###.......###"],
	"E": [".##########", "###########", "###########", "###........", "###........", "###........",
		"#########..", "#########..", "#########..", "###........", "###........", "###........",
		"###########", "###########", ".##########"],
}
const LETTER_GAP := 2  ## filled pixels between two letters; their outlines meet in the gap
## Flat bands from the top: light from above, like the rest of the art.
const LETTER_BANDS := [["d3ccb7", 5], ["bdb59f", 5], ["a39b86", 5]]
const LETTER_OUTLINE := "2c3324"
const LETTER_SHADOW := "44443f"


## Every image this script draws: res:// path -> Image.
static func all() -> Dictionary:
	var button := quantized(source("button.png").get_region(BUTTON_CROP))
	var normal: Image = button.duplicate()
	shift(normal, -1, LENS, true)
	var hover: Image = button.duplicate()
	shift(hover, 1)
	var pressed: Image = button.duplicate()
	shift(pressed, -1)
	var disabled: Image = button.duplicate()
	greyed(disabled)
	var plate := quantized(source("plate.png").get_region(PLATE_CROP))
	var out := {
		"title_bg.png": backdrop(),
		"logo.png": logo(plate),
		"title_band.png": band(plate),
		"panel.png": nine(quantized(source("panel.png").get_region(PANEL_CROP)), PANEL_MARGINS, PANEL_PERIOD),
		"focus.png": focus(),
	}
	for state in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled]]:
		out["button_%s.png" % state[0]] = nine(state[1], BUTTON_MARGINS, BUTTON_PERIOD)
	var paths := {}
	for k in out:
		paths[OUT + k] = out[k]
	return paths


static func source(file: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + file))
	img.convert(Image.FORMAT_RGBA8)
	return img


## [kit colours], [warm-allowed colours], {rgba32 -> [ramp, index]}: from data/palette.json + AMBER.
static func palette() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
	var ramps: Array = []
	var names: Array = data["ramps"].keys()
	for i in KIT_RAMPS:
		ramps.append((data["ramps"][names[i]] as Array).map(func(h): return Color.html(h)))
	var kit: Array = []
	for r in ramps:
		kit.append_array(r)
	var amber: Array = AMBER.map(func(h): return Color.html(h))
	ramps.append(amber)
	var where := {}
	for r in ramps:
		for i in r.size():
			where[(r[i] as Color).to_rgba32()] = [r, i]
	return {"kit": kit, "warm": kit + amber, "ramps": where}


## Colour distance weighted for the eye ("redmean"), on 0-255 channels.
static func distance(a: Color, b: Color) -> float:
	var r := (a.r8 + b.r8) / 2.0
	var dr := a.r8 - b.r8
	var dg := a.g8 - b.g8
	var db := a.b8 - b.b8
	return (2.0 + r / 256.0) * dr * dr + 4.0 * dg * dg + (2.0 + (255.0 - r) / 256.0) * db * db


## `img` with every pixel on the nearest palette colour, no dithering; alpha cut at 50 %.
static func quantized(img: Image) -> Image:
	var pal := palette()
	var out: Image = img.duplicate()
	var cache := {}
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a < 0.5:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			c.a = 1.0
			var key := c.to_rgba32()
			if not cache.has(key):
				var best: Color
				var best_d := INF
				for p in (pal["warm"] if c.r8 > c.g8 else pal["kit"]):
					var d := distance(c, p)
					if d < best_d:
						best_d = d
						best = p
				cache[key] = best
			out.set_pixel(x, y, cache[key])
	return out


## Moves every pixel `by` steps along its ramp (lighter when > 0), inside `rect` if given; with
## `amber_only`, only the amber pixels.
static func shift(img: Image, by: int, rect := Rect2i(), amber_only := false) -> void:
	var where: Dictionary = palette()["ramps"]
	var area := rect if rect.has_area() else Rect2i(Vector2i.ZERO, img.get_size())
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := img.get_pixel(x, y)
			if c.a == 0.0 or not where.has(c.to_rgba32()):
				continue
			var at: Array = where[c.to_rgba32()]
			var ramp: Array = at[0]
			if amber_only and ramp[0] != Color.html(AMBER[0]):
				continue
			img.set_pixel(x, y, ramp[clampi(at[1] + by, 0, ramp.size() - 1)])


## Every pixel on the stone ramp, one step darker than its brightness: a switched-off button.
static func greyed(img: Image) -> void:
	var stone: Array = []
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
	for h in data["ramps"]["stone"]:
		stone.append(Color.html(h))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var best := 0
			for i in stone.size():
				if absf(stone[i].get_luminance() - c.get_luminance()) < absf(stone[best].get_luminance() - c.get_luminance()):
					best = i
			img.set_pixel(x, y, stone[maxi(best - 1, 0)])


## A 9-slice image from `img`: its corners and edges `m` [l, t, r, b] wide, with only `period` (a
## rectangle of the middle) between them, so the edges repeat that period and nothing else.
static func nine(img: Image, m: Array, period: Rect2i) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var cols := [[0, m[0]], [period.position.x, period.size.x], [w - m[2], m[2]]]
	var rows := [[0, m[1]], [period.position.y, period.size.y], [h - m[3], m[3]]]
	var out := Image.create_empty(m[0] + period.size.x + m[2], m[1] + period.size.y + m[3], false, Image.FORMAT_RGBA8)
	var dy := 0
	for r in rows:
		var dx := 0
		for c in cols:
			out.blit_rect(img, Rect2i(c[0], r[0], c[1], r[1]), Vector2i(dx, dy))
			dx += c[1]
		dy += r[1]
	return out


## The title band: the plate's right end, the same end mirrored on the left, one period between.
static func band(plate: Image) -> Image:
	var end_w := plate.get_width() - BAND_END
	var right := plate.get_region(Rect2i(BAND_END, 0, end_w, plate.get_height()))
	var left: Image = right.duplicate()
	left.flip_x()
	var out := Image.create_empty(end_w * 2 + BAND_PERIOD.size.x, plate.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
	out.blit_rect(plate, BAND_PERIOD, Vector2i(end_w, 0))
	out.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(end_w + BAND_PERIOD.size.x, 0))
	return out


## The letters of `text`, filled in LETTER_BANDS, with a 1 px outline and a shadow 1 px down-right.
static func lettering(text: String) -> Image:
	var w := 0
	for ch in text:
		w += (GLYPHS[ch][0] as String).length() + LETTER_GAP
	w -= LETTER_GAP
	var h: int = GLYPHS["A"].size()
	var fill := Image.create_empty(w + 3, h + 3, false, Image.FORMAT_RGBA8)  # 1 px outline + 1 px shadow
	var x0 := 1
	for ch in text:
		var rows: Array = GLYPHS[ch]
		for y in rows.size():
			var band_y := y
			var col := Color.html(LETTER_BANDS[-1][0])
			for b in LETTER_BANDS:
				if band_y < b[1]:
					col = Color.html(b[0])
					break
				band_y -= b[1]
			for x in (rows[y] as String).length():
				if rows[y][x] == "#":
					fill.set_pixel(x0 + x, 1 + y, col)
		x0 += (rows[0] as String).length() + LETTER_GAP
	var out := Image.create_empty(fill.get_width(), fill.get_height(), false, Image.FORMAT_RGBA8)
	var outline := Color.html(LETTER_OUTLINE)
	var shadow := Color.html(LETTER_SHADOW)
	for y in out.get_height():
		for x in out.get_width():
			if fill.get_pixel(x, y).a > 0.0:
				continue
			if _near(fill, x, y, 1):
				out.set_pixel(x, y, outline)
			elif x > 0 and y > 0 and _near(fill, x - 1, y - 1, 1):
				out.set_pixel(x, y, shadow)
	out.blend_rect(fill, Rect2i(Vector2i.ZERO, fill.get_size()), Vector2i.ZERO)
	return out


## Whether a filled pixel of `img` is within `r` (8 neighbours) of (x, y).
static func _near(img: Image, x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var px := x + dx
			var py := y + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height() and img.get_pixel(px, py).a > 0.0:
				return true
	return false


## The plate with its amber eye, the name of the game on its slab.
static func logo(plate: Image) -> Image:
	var out: Image = plate.duplicate()
	var text := lettering(LOGO_TEXT)
	var at := LOGO_SLAB.position + (LOGO_SLAB.size - text.get_size()) / 2
	out.blend_rect(text, Rect2i(Vector2i.ZERO, text.get_size()), at)
	return out


## The colossus's valley, cut to BACKDROP_SIZE (one row off the top and the bottom).
static func backdrop() -> Image:
	var src := source("colossus_bg.png")
	var y := (src.get_height() - BACKDROP_SIZE.y) / 2
	return quantized(src.get_region(Rect2i(Vector2i(0, y), BACKDROP_SIZE)))


## The keyboard focus: a 2 px amber frame around the control, empty inside; 9-slice, FOCUS_MARGIN px corners.
static func focus() -> Image:
	var img := Image.create_empty(FOCUS_SIZE, FOCUS_SIZE, false, Image.FORMAT_RGBA8)
	var lit := Color.html(AMBER[2])
	var dark := Color.html(AMBER[0])
	var n := FOCUS_SIZE
	for i in n:
		for edge in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			img.set_pixelv(edge, dark)
		for edge in [Vector2i(i, 1), Vector2i(i, n - 2), Vector2i(1, i), Vector2i(n - 2, i)]:
			if i > 0 and i < n - 1:
				img.set_pixelv(edge, lit)
	# square corners cut, like the frames
	for c in [Vector2i(0, 0), Vector2i(n - 1, 0), Vector2i(0, n - 1), Vector2i(n - 1, n - 1)]:
		img.set_pixelv(c, Color(0, 0, 0, 0))
	return img
