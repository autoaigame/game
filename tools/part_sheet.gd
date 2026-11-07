## A sheet of one character part as the game draws it: the default look wearing the part, on every body
## shape (rows), from the front, three-quarters, the side and the back, then running (columns). Writes
## <out>.png at game size and <out>_x3.png enlarged 3 times. Needs a renderer (not --headless):
##   godot --path . --rendering-driver opengl3 -s res://tools/part_sheet.gd -- <id> <out.png>
## On Linux without a display: xvfb-run. make check-part runs it.
extends SceneTree

const CELL := Vector2i(110, 150)
const TOP := 16  ## a line for the column names
const GROUND := Color8(0x54, 0x48, 0x3a)  ## dirt_mud of data/palette.json
## [name, facing (radians; PI/4 faces the camera), running direction in cells (zero: standing)]
const VIEWS := [["face", PI / 4, Vector2.ZERO], ["3/4", PI / 2, Vector2.ZERO], ["side", -PI / 4, Vector2.ZERO],
		["back", PI / 4 + PI, Vector2.ZERO], ["run", 0.0, Vector2(1, 0)]]
const FRAMES := 40  ## frames of running before the picture

var out := ""
var frame := 0
var models: Array = []
var sheet := Vector2i.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or CharacterParts.part(args[0]).is_empty():
		print("usage: part_sheet.gd -- <part id> <out.png>")
		quit(2)
		return
	var id: String = args[0]
	out = args[1]
	var slot: String = CharacterParts.part(id)["slot"]
	var bodies: Array = Array(CharacterParts.parts_for("body")) if slot != "body" else [id]
	var size := Vector2i(CELL.x * VIEWS.size(), TOP + CELL.y * bodies.size())
	sheet = size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED  # one game pixel per screen pixel
	var world := Node2D.new()
	root.add_child(world)
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.size = size
	world.add_child(bg)
	for c in VIEWS.size():
		var l := Label.new()
		l.text = VIEWS[c][0]
		l.position = Vector2(CELL.x * c + 4, 0)
		l.add_theme_font_size_override("font_size", 11)
		world.add_child(l)
	for r in bodies.size():
		var look := []
		for e in CharacterParts.normalize(CharacterParts.default_look()):
			var s: String = CharacterParts.part(e["id"])["slot"]
			if s == slot or (s == "body" and slot != "body"):
				continue
			look.append(e)
		if slot != "body":
			look.append({"id": bodies[r], "color": CharacterParts.part(bodies[r])["colors"][0]})
		look.append({"id": id, "color": CharacterParts.part(id)["colors"][0]})
		look = CharacterParts.normalize(look)
		for c in VIEWS.size():
			var m := Character3D.new()
			m.look = look
			world.add_child(m)
			m.face(VIEWS[c][1])
			m.set_meta("at", Vector2(CELL.x * c + CELL.x / 2, TOP + CELL.y * (r + 1) - 14))
			m.set_meta("run", VIEWS[c][2])
			models.append(m)
		var l := Label.new()
		l.text = bodies[r].trim_prefix("body_")
		l.position = Vector2(4, TOP + CELL.y * r + 2)
		l.add_theme_font_size_override("font_size", 11)
		world.add_child(l)


func _process(_dt: float) -> bool:
	frame += 1
	for m in models:
		m.place(m.get_meta("at"))
		var d: Vector2 = m.get_meta("run")
		if d != Vector2.ZERO and frame <= FRAMES:
			m.step(d.normalized() * Protocol.SPEED_CELLS_PER_S / 60.0, 1.0 / 60.0)
	if frame == FRAMES + 5:
		var img := root.get_texture().get_image().get_region(Rect2i(Vector2i.ZERO, sheet))
		img.save_png(out)
		var big := img.duplicate()
		big.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		big.save_png(out.get_basename() + "_x3.png")
		print("sheet: %s and %s" % [out, out.get_basename() + "_x3.png"])
		return true
	return false
