## Redraws the ground shadow baked into each object sprite (assets/objects/*.png) so the object
## stands on it instead of floating above it.
##
## The shadow is the only translucent part of these sprites (one colour, SHADOW_RGB), so it is
## removed and drawn again under the opaque pixels:
## - a wide ellipse, centred a little above and to the right of the anchor (the foot of the trunk,
##   the base of a rock): most of it stays hidden behind the object, and the visible part falls to
##   the bottom right, away from the top-left light;
## - a smaller, darker ellipse around the anchor: the contact shadow where the object meets the
##   ground.
## Hard pixel edges and two flat steps, as the art guide asks (no anti-aliasing, no gradient).
##
## Usage: godot --headless --path . -s res://art/object_shadows.gd
## Safe to run again: it always starts from the opaque pixels alone.
extends SceneTree

const SHADOW_RGB := Color8(20, 22, 16)
const OUTER_ALPHA := 0.30
const CONTACT_ALPHA := 0.46
## The wide ellipse's centre, in its own radii, from the anchor (right, down).
const OUTER_SHIFT := Vector2(0.14, -0.38)
## The contact ellipse, in the wide ellipse's radii: its size, and its centre from the anchor.
const CONTACT_SCALE := Vector2(0.52, 0.5)
const CONTACT_SHIFT := Vector2(0.06, -0.12)

## Radii (x, y) of each sprite's shadow, kept from the sprites as they came from the kit (about
## 0.42 x the sprite's width, scaled per species). The assembled trees (<species>_NN.png) take the
## radii art/tree_assembler.gd prints for them.
const RADII := {
	"birch_00.png": Vector2(29.5, 10.5),
	"birch_01.png": Vector2(35.5, 12.5),
	"birch_02.png": Vector2(37.5, 13.5),
	"birch_03.png": Vector2(48.5, 17.5),
	"birch_04.png": Vector2(31.5, 11.5),
	"birch_05.png": Vector2(37.5, 13.5),
	"birch_06.png": Vector2(42.5, 15.5),
	"birch_07.png": Vector2(48.5, 17.5),
	"birch_08.png": Vector2(32.5, 11.5),
	"birch_09.png": Vector2(38.5, 13.5),
	"birch_10.png": Vector2(41.5, 14.5),
	"birch_11.png": Vector2(54.5, 19.5),
	"birch_12.png": Vector2(28.5, 10.5),
	"birch_13.png": Vector2(35.5, 12.5),
	"birch_14.png": Vector2(39.5, 14.5),
	"birch_15.png": Vector2(53.5, 19.5),
	"birch_16.png": Vector2(31.5, 11.5),
	"birch_17.png": Vector2(38.5, 13.5),
	"birch_4.png": Vector2(26.5, 11.5),
	"boulder_0.png": Vector2(22.5, 8.5),
	"boulder_1.png": Vector2(24.5, 9.5),
	"bush_0.png": Vector2(22.5, 8.5),
	"bush_1.png": Vector2(24.5, 9.5),
	"bush_2.png": Vector2(26.5, 10.5),
	"bush_3.png": Vector2(21.5, 9.5),
	"bush_4.png": Vector2(20.5, 8.5),
	"fir_00.png": Vector2(24.5, 8.5),
	"fir_01.png": Vector2(34.5, 12.5),
	"fir_02.png": Vector2(24.5, 8.5),
	"fir_03.png": Vector2(30.5, 10.5),
	"fir_04.png": Vector2(24.5, 8.5),
	"fir_05.png": Vector2(34.5, 12.5),
	"fir_06.png": Vector2(24.5, 8.5),
	"fir_07.png": Vector2(30.5, 10.5),
	"fir_08.png": Vector2(24.5, 8.5),
	"fir_09.png": Vector2(34.5, 12.5),
	"fir_10.png": Vector2(24.5, 8.5),
	"fir_11.png": Vector2(30.5, 10.5),
	"fir_12.png": Vector2(24.5, 8.5),
	"fir_13.png": Vector2(34.5, 12.5),
	"fir_14.png": Vector2(24.5, 8.5),
	"fir_15.png": Vector2(30.5, 10.5),
	"fir_16.png": Vector2(24.5, 8.5),
	"fir_17.png": Vector2(34.5, 12.5),
	"fir_4.png": Vector2(20.5, 8.5),
	"fir_dead_00.png": Vector2(36.5, 13.5),
	"oak_00.png": Vector2(55.5, 19.5),
	"oak_01.png": Vector2(55.5, 19.5),
	"oak_02.png": Vector2(38.5, 13.5),
	"oak_03.png": Vector2(55.5, 19.5),
	"oak_04.png": Vector2(51.5, 18.5),
	"oak_05.png": Vector2(56.5, 20.5),
	"oak_06.png": Vector2(52.5, 18.5),
	"oak_07.png": Vector2(36.5, 13.5),
	"oak_08.png": Vector2(56.5, 20.5),
	"oak_09.png": Vector2(51.5, 18.5),
	"oak_10.png": Vector2(54.5, 19.5),
	"oak_11.png": Vector2(53.5, 19.5),
	"oak_12.png": Vector2(37.5, 13.5),
	"oak_13.png": Vector2(52.5, 18.5),
	"oak_14.png": Vector2(51.5, 18.5),
	"oak_15.png": Vector2(55.5, 19.5),
	"oak_16.png": Vector2(53.5, 19.5),
	"oak_17.png": Vector2(38.5, 13.5),
	"oak_4.png": Vector2(28.5, 12.5),
	"stump_0.png": Vector2(24.5, 10.5),
	"stump_1.png": Vector2(24.5, 10),
	"stump_2.png": Vector2(21.5, 9),
	"stump_3.png": Vector2(23.5, 10),
	"stump_4.png": Vector2(22.5, 9.5),
	"wall_0.png": Vector2(26.5, 11),
	"wall_1.png": Vector2(26.5, 11),
	"wall_2.png": Vector2(26.5, 11),
	"wall_3.png": Vector2(26.5, 11),
}


func _initialize() -> void:
	var failed := false
	for path in sprites():
		var name: String = path.get_file()
		if not RADII.has(name):
			push_error("object_shadows: no radii for %s" % name)
			failed = true
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		img.convert(Image.FORMAT_RGBA8)
		var out := rebake(img, sprites()[path], RADII[name])
		var err := out.save_png(path)
		if err != OK:
			push_error("object_shadows: cannot write %s (%s)" % [path, error_string(err)])
			failed = true
	print("object_shadows: redrew %d shadows" % sprites().size())
	quit(1 if failed else 0)


## Every object sprite and its anchor, from data/objects.
static func sprites() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://data/objects")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var o: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/objects/" + f))
		for sp in o["sprites"]:
			out[sp["file"]] = Vector2(sp["anchor_px"][0], sp["anchor_px"][1])
	return out


## The sprite without its old shadow, with the new one drawn under its opaque pixels.
static func rebake(img: Image, anchor: Vector2, radii: Vector2) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	var outer_c := anchor + OUTER_SHIFT * radii
	var contact_r := CONTACT_SCALE * radii
	var contact_c := anchor + CONTACT_SHIFT * radii
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 == 255:
				out.set_pixel(x, y, c)
				continue
			var p := Vector2(x + 0.5, y + 0.5)
			var a := 0.0
			if _inside(p, contact_c, contact_r):
				a = CONTACT_ALPHA
			elif _inside(p, outer_c, radii):
				a = OUTER_ALPHA
			if a > 0.0:
				out.set_pixel(x, y, Color(SHADOW_RGB, a))
	return out


static func _inside(p: Vector2, centre: Vector2, radii: Vector2) -> bool:
	var d := (p - centre) / radii
	return d.length_squared() <= 1.0
