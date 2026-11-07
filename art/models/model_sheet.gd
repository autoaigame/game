## Renders a 3D model through the game's pixel-art pipeline (client/model_3d.gd), at game size, to PNGs:
## the frames of a render sheet, or the frames of a short animation. Needs a display (not --headless);
## without a GPU, run it under Xvfb:
##
##   xvfb-run -a godot --path . -s res://art/models/model_sheet.gd -- sheet <out_dir>
##   xvfb-run -a godot --path . -s res://art/models/model_sheet.gd -- circle <out_dir>
##
## sheet: zombie and player side by side, facing the camera (face), 3/4, profile and back, in idle, four
## walk phases, three attack moments and the end of the death; <out_dir>/<row>_<facing>.png.
## circle: the zombie walks once round the standing player, turns to it and attacks, 15 frames per
## second; <out_dir>/circle_<n>.png.
extends SceneTree

const FACINGS := {"face": PI / 4.0, "three_quarter": PI / 2.0, "profile": 3.0 * PI / 4.0, "back": -3.0 * PI / 4.0}
const CELL := Vector2i(200, 240)  ## one picture: zombie and player side by side
const GROUND := Color8(0x4d, 0x56, 0x38)  ## olive_grass, so the outline shows


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "sheet"
	var out := args[1] if args.size() > 1 else "user://sheet"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred(mode, out)


func _stage(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.size = Vector2(size)
	vp.add_child(bg)
	return vp


func _shot(vp: SubViewport, path: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)


## Nothing covers the models here: their see-through silhouettes (drawn where something hides them) are
## off. Each silhouette reads one copy of the screen, taken before the models drawn after it.
func _no_ghosts(models: Array) -> void:
	for m: Model3D in models:
		m._ghost.visible = false


func _run(mode: String, out: String) -> void:
	if mode == "circle":
		await _circle(out)
	else:
		await _sheet(out)
	quit()


func _sheet(out: String) -> void:
	var vp := _stage(CELL)
	var z := Zombie3D.new()
	var p := Character3D.new()
	vp.add_child(p)
	vp.add_child(z)
	_no_ghosts([z, p])
	z.place(Vector2(70, 150))
	p.place(Vector2(150, 150))
	var walk_s := float(Zombie3D.clips()["clips"]["walk"]["duration_s"])
	var rows := {"idle": {}, "walk_0": {"phase": 0.0}, "walk_1": {"phase": 0.25}, "walk_2": {"phase": 0.5},
			"walk_3": {"phase": 0.75}, "attack_raise": {"attack": 0.36}, "attack_hit": {"attack": 0.54},
			"attack_hold": {"attack": 0.72}, "death_end": {"dead": 3.0}}
	for row in rows:
		var r: Dictionary = rows[row]
		z.speed_m_s = float(Zombie3D.clips()["clips"]["walk"]["ground_speed_m_s"]) if r.has("phase") else 0.0
		z.phase = r.get("phase", 0.0)
		z.idle_t = 0.0
		z.attack_t = r.get("attack", -1.0)
		z.dead_t = r.get("dead", -1.0)
		var pv := float(Character3D.clips()["clips"]["walk"]["ground_speed_m_s"]) if r.has("phase") else 0.0
		p.speed_m_s = pv
		p.phase = r.get("phase", 0.0)
		for f in FACINGS:
			z.face(FACINGS[f])
			p.face(FACINGS[f])
			await _shot(vp, "%s/%s_%s.png" % [out, row, f])
	print("sheet: %d pictures, walk %.2f s" % [rows.size() * FACINGS.size(), walk_s])


func _circle(out: String) -> void:
	var vp := _stage(Vector2i(320, 240))
	var p := Character3D.new()
	var z := Zombie3D.new()
	vp.add_child(p)
	vp.add_child(z)
	_no_ghosts([z, p])
	var centre := Vector2(160, 140)
	p.place(centre)
	p.face(PI / 4.0)
	var dt := 1.0 / 15.0
	var v_cells := float(Zombie3D.clips()["clips"]["walk"]["ground_speed_m_s"]) / z.cell_m
	var radius := 1.1  # cells
	var steps := int(ceil(TAU * radius / v_cells / dt))
	var angle := 0.0
	var pos := Vector2(radius, 0.0)
	var n := 0
	for i in steps:
		angle -= v_cells * dt / radius
		var next := Vector2(cos(angle), sin(angle)) * radius
		z.step(next - pos, dt)
		pos = next
		z.place(centre + IsoLayer.cell_to_local(pos) - IsoLayer.cell_to_local(Vector2.ZERO))
		# Draw order: whoever is lower on screen in front.
		vp.move_child(z, -1 if IsoLayer.cell_to_local(pos).y > 0.0 else 1)
		await _shot(vp, "%s/circle_%03d.png" % [out, n])
		n += 1
	z.target_yaw = Model3D.yaw_of(-pos)
	for i in 6:
		z.step(Vector2.ZERO, dt)
		await _shot(vp, "%s/circle_%03d.png" % [out, n])
		n += 1
	z.attack()
	while z.is_attacking():
		z.step(Vector2.ZERO, dt)
		await _shot(vp, "%s/circle_%03d.png" % [out, n])
		n += 1
	for i in 8:
		z.step(Vector2.ZERO, dt)
		await _shot(vp, "%s/circle_%03d.png" % [out, n])
		n += 1
	print("circle: %d frames" % n)
