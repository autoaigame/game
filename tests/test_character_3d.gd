extends TestCase

## The 3D character (client/character_3d.gd): gait blend, stride sync, footsteps, facing, scale, palette.
## Display only.

const Pose := preload("res://tests/character_pose.gd")


func test_gait_weights_sum_to_one_and_follow_speed() -> void:
	for v in [0.0, 0.3, 1.0, 1.8, 2.5, 3.0, 4.1, 9.0]:
		var w := Character3D.gait_weights(v)
		var total := 0.0
		for k in w:
			total += w[k]
		assert_almost(total, 1.0, 0.0001, "at %.1f m/s" % v)
	assert_eq(Character3D.gait_weights(0.0)["idle"], 1.0)
	var walk_v: float = Character3D.clips()["clips"]["walk"]["ground_speed_m_s"]
	assert_almost(Character3D.gait_weights(walk_v)["walk"], 1.0, 0.0001, "pure walk at its own speed")
	assert_eq(Character3D.gait_weights(20.0)["sprint"], 1.0, "fastest gait above its speed")


## The planted foot moves with the ground: per cycle the body travels each pure gait's measured stride.
func test_phase_advances_by_stride() -> void:
	var c: Dictionary = Character3D.clips()["clips"]
	for g in Character3D.GAITS:
		var v: float = c[g]["ground_speed_m_s"]
		var stride: float = c[g]["stride_m"]
		var p := 0.0
		var dist := 0.0
		var dt := 1.0 / 60.0
		var cycles := 0.0
		while dist < 3.0 * stride:
			var np := Character3D.advance_phase(p, v, dt)
			cycles += fposmod(np - p, 1.0)
			p = np
			dist += v * dt
		assert_almost(cycles, dist / stride, 0.02, g)
		# At its own speed, one cycle lasts exactly the clip: played at normal rate.
		assert_almost(stride / v, float(c[g]["duration_s"]), 0.01, g + " plays at 1x at its speed")


## Phase 0 is the left foot's mid-stance in every gait, so blending two gaits never crosses the legs.
func test_gaits_share_the_phase() -> void:
	var c: Dictionary = Character3D.clips()["clips"]
	for g in Character3D.GAITS:
		var t := Character3D.clip_time(g, 0.0)
		assert_almost(t / float(c[g]["duration_s"]), float(c[g]["left_mid_stance"]), 0.0001, g)
		var right := Character3D.clip_time(g, 0.5) / float(c[g]["duration_s"])
		assert_almost(right, float(c[g]["right_mid_stance"]), 0.07, g + ": right foot half a cycle later")


## Footsteps land on the clips' measured contacts: each foot lands a little before its mid-stance.
func test_footsteps_on_the_feet_contacts() -> void:
	var c: Dictionary = Character3D.clips()["clips"]
	for g in Character3D.GAITS:
		var v: float = c[g]["ground_speed_m_s"]
		var pts := Character3D.contact_phases(v)
		assert_eq(pts.size(), 2, g)
		var left := fposmod(float(c[g]["left_contact"]) - float(c[g]["left_mid_stance"]), 1.0)
		assert_almost(pts[0], left, 0.0001, g + ": left contact in the shared phase")
		assert_true(pts[0] > 0.6, g + ": the left foot lands before its mid-stance (phase 0)")
		assert_true(pts[1] > 0.1 and pts[1] < 0.5, g + ": the right foot lands before its own mid-stance")
		# Two steps per cycle, wherever the cycle starts.
		var n := 0
		var p := 0.137
		for i in 200:
			var np := fposmod(p + 1.0 / 100.0, 1.0)
			n += Character3D.contacts_between(p, np, v)
			p = np
		assert_eq(n, 4, g + ": two cycles, four footsteps")
	assert_eq(Character3D.contacts_between(0.3, 0.3, 1.0), 0, "standing: no footstep")


## A model walking a straight line makes about two footsteps per measured stride, and none standing.
func test_walking_model_makes_footsteps() -> void:
	var m := Character3D.new()
	var steps := 0
	var cells_per_s := Protocol.SPEED_CELLS_PER_S
	var dt := 1.0 / 60.0
	for i in 120:  # 2 s at the server's speed
		steps += m.step(Vector2(cells_per_s * dt, 0.0), dt)
	var v := cells_per_s * m.cell_m
	var expected := 2.0 * v * 2.0 / Character3D.stride_at(v)
	assert_true(absf(steps - expected) <= 2.0, "%d footsteps, about %.1f expected" % [steps, expected])
	var still := 0
	for i in 120:
		still += m.step(Vector2.ZERO, dt)
	assert_true(still <= 1, "stopping: at most the step in progress")
	m.free()


## Cell axes to yaw: cell +y is the model's forward (+Z), cell +x is +X.
func test_yaw_of_cell_directions() -> void:
	assert_almost(Character3D.yaw_of(Vector2(0, 1)), 0.0, 0.0001)
	assert_almost(Character3D.yaw_of(Vector2(1, 0)), PI / 2, 0.0001)
	assert_almost(Character3D.yaw_of(Vector2(1, 1)), PI / 4, 0.0001, "screen south faces the camera")


func test_turn_is_continuous_and_half_turns_face_the_camera() -> void:
	assert_almost(Character3D.turn_towards(0.0, 1.0, 0.1), 0.1, 0.0001, "limited step")
	assert_almost(Character3D.turn_towards(0.0, 0.05, 0.1), 0.05, 0.0001, "reaches the target")
	# From screen east (cell (1, -1)) to screen west (cell (-1, 1)): through south (yaw PI/4).
	var east := Character3D.yaw_of(Vector2(1, -1))
	var west := Character3D.yaw_of(Vector2(-1, 1))
	var y := Character3D.turn_towards(east, west, 0.2)
	assert_true(absf(angle_difference(y, PI / 4)) < absf(angle_difference(east, PI / 4)), "turns towards the camera")


## The head is at HEAD_PX on screen, under the name.
func test_scale_puts_the_head_under_the_name() -> void:
	var s := Character3D.new()
	var head: float = Character3D.clips()["height_m"] * cos(deg_to_rad(Character3D.ELEVATION_DEG)) * s.px_per_m
	assert_almost(head, Character3D.HEAD_PX, 0.01, "head at HEAD_PX")
	assert_true(Character3D.HEAD_PX <= WalkAnim.HEAD_PX, "under the name")
	assert_true(s.cell_m > 0.85 and s.cell_m < 1.05, "about a metre per cell")
	assert_true(ResourceLoader.exists(Character3D.MODEL), "body imported")
	s.free()


## The shaders get the palette from data/palette.json; the darker tone of the inner lines is darker.
func test_palette_and_dark_tones() -> void:
	var pal := Character3D.palette()
	assert_eq(pal.size(), 52, "the kit's 40 colours and 12 for characters")
	assert_true(pal.size() <= Character3D.MAX_COLOURS, "fits the shaders' uniform arrays")
	assert_eq(Character3D.palette_uniform().size(), Character3D.MAX_COLOURS)
	var dark := Character3D.dark_of()
	assert_eq(dark.size(), pal.size())
	for i in pal.size():
		assert_true(dark[i] == i or pal[dark[i]].get_luminance() < pal[i].get_luminance(), "darker: %d" % i)
	var khaki := pal.find(Color.html("8f8a63"))
	assert_true(khaki >= 0 and dark[khaki] != khaki, "the jacket colour has a darker tone")


## Each palette index comes back from the render as itself, even a unit off: the red code written by
## pixel_3d_lit.gdshader (Character3D.red_code) survives the renderer's round trip (_render_red) and the 2D
## pass reads the same index (Character3D.red_index).
func test_red_codes_survive_the_render() -> void:
	for i in Character3D.MAX_COLOURS:
		var code := Character3D.red_code(i)
		assert_true(code <= 255, "index %d: code %d fits a byte" % [i, code])
		var back := _render_red(code)
		for d in [-1, 0, 1]:
			assert_eq(Character3D.red_index(back + d), i, "index %d: code %d comes back %d" % [i, code, back])
	var model := Character3D.new()
	var m := model.lit_material(Color.WHITE)
	assert_eq(m.get_shader_parameter("red_base"), Character3D.RED_BASE, "the 3D pass gets the code")
	assert_eq(m.get_shader_parameter("red_step"), Character3D.RED_STEP)
	model.free()


## The red byte k written by an unshaded spatial shader, as the SubViewport gives it back with the
## Compatibility renderer: sRGB to linear by a polynomial approximation, then back to sRGB without the
## linear segment. Read back from the game's own viewport on the desktop (OpenGL 3) and the web
## (WebGL 2), it gives these 256 values exactly: 0 to 7 come back 0, 8 comes back 2, 18 comes back 14, and
## 56 and over come back unchanged.
static func _render_red(k: int) -> int:
	var c := k / 255.0
	var l := c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878)
	return roundi(clampf(1.055 * pow(l, 1.0 / 2.4) - 0.055, 0.0, 1.0) * 255.0)


## Every colour of the body's default outfit is a palette colour.
func test_body_colours_are_in_the_palette() -> void:
	var scene: Node = load(Character3D.MODEL).instantiate()
	var pal := Character3D.palette()
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	assert_true(meshes.size() >= 10, "one mesh per body region")
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			var m: BaseMaterial3D = mi.mesh.surface_get_material(s)
			var c := m.albedo_color
			var found := false
			for p in pal:
				found = found or (absf(p.r - c.r) < 0.003 and absf(p.g - c.g) < 0.003 and absf(p.b - c.b) < 0.003)
			assert_true(found, "%s: %s" % [mi.name, c.to_html(false)])
	scene.free()


## The palette starts with the kit's 40 colours, unchanged (the world's art uses only those), then the
## characters' colours: four skin tones from deep to fair, and faded reds.
func test_palette_keeps_the_kit_and_adds_skin_and_reds() -> void:
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Character3D.PALETTE_JSON))
	var kit := ["olive_grass", "dry_grass", "dirt_mud", "sand", "water", "bark_wood", "stone", "skin", "denim", "khaki_cloth"]
	assert_eq(rec["ramps"].keys().slice(0, kit.size()), kit, "the kit's ramps first, in order")
	var pal := Character3D.palette()
	assert_eq(pal[0], Color.html("2c3324"))
	assert_eq(pal[39], Color.html("8f8a63"), "the kit's last colour stays at 39")
	for i in range(40, pal.size()):
		var c := pal[i]
		assert_true(c.s < 0.6, "%s: muted" % c.to_html(false))
		assert_true(pal.find(c) == i, "%s: added once" % c.to_html(false))
	var skins := ["skin_deep", "skin_dark", "skin_medium", "skin_light"]
	var lum := -1.0
	for s in skins:
		var r := CharacterParts.ramp(s)
		assert_true(r["colours"].size() >= 3, s)
		var l: float = r["colours"][1].get_luminance()
		assert_true(l > lum, s + ": lighter than the one before")
		lum = l
	assert_true(CharacterParts.ramp("hair_red")["colours"][1].r > CharacterParts.ramp("hair_red")["colours"][1].g * 1.3, "red hair is red")



## Poses `sk` like Character3D's animation tree at phase `p` and ground speed `v`: each gait's clip at the
## shared phase, blended by gait weight (positions lerped, rotations slerped), then the body shape.
static func _pose_moving(sk: Skeleton3D, anims: Dictionary, p: float, v: float, morph: CharacterMorph) -> void:
	var w := Character3D.gait_weights(v)
	var pos := {}
	var rot := {}
	var total := 0.0
	for g in Character3D.GAITS:
		if w[g] <= 0.0:
			continue
		total += w[g]
		var t: float = w[g] / total  # the share of this gait in the blend so far
		var a: Animation = anims[g]
		var time := minf(Character3D.clip_time(g, p), a.length - 0.0001)
		for k in a.get_track_count():
			var bone := sk.find_bone(String(a.track_get_path(k).get_concatenated_subnames()))
			if bone < 0:
				continue
			match a.track_get_type(k):
				Animation.TYPE_POSITION_3D:
					var x := a.position_track_interpolate(k, time)
					pos[bone] = x if not pos.has(bone) else (pos[bone] as Vector3).lerp(x, t)
				Animation.TYPE_ROTATION_3D:
					var q := a.rotation_track_interpolate(k, time)
					rot[bone] = q if not rot.has(bone) else (rot[bone] as Quaternion).slerp(q, t)
	sk.reset_bone_poses()
	for b in pos:
		sk.set_bone_pose_position(b, pos[b])
	for b in rot:
		sk.set_bone_pose_rotation(b, rot[b])
	morph.apply(sk)


## How fast a planted foot slides on the map (m/s, median; + = forwards) when the body goes straight
## ahead at v m/s for 4 s: the ball of each foot (the toe bone's head) counts as planted within 1.5 cm of
## its lowest point. Also returns how many frames a foot was planted.
static func _planted_slip(body: String, v: float) -> Vector2:
	var root := CharacterRig.build(Pose.look([[body, 0]]))
	var sk := Pose.skeleton(root)
	var morph := CharacterMorph.new(sk, root.get_meta("morph"))
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var anims := {}
	for g in Character3D.GAITS:
		anims[g] = player.get_animation(g)
	var to_model := Transform3D.IDENTITY  # skeleton space to the model's (faces +Z)
	var n: Node = sk
	while n != root:
		to_model = (n as Node3D).transform * to_model
		n = n.get_parent()
	var dt := 1.0 / 60.0
	var p := 0.0
	var body_z := 0.0
	var feet := [[], []]  ## per foot, each frame: (height, position along the way on the map)
	for i in 240:
		p = Character3D.advance_phase(p, v, dt, morph.stride_scale)
		body_z += v * dt
		_pose_moving(sk, anims, p, v, morph)
		var gl := Pose.globals(sk)
		for f in 2:
			var ball: Vector3 = to_model * gl[sk.find_bone("DEF-toe." + ["L", "R"][f])].origin
			feet[f].append(Vector2(ball.y, body_z + ball.z))
	root.free()
	var slips := []
	for f in 2:
		var low := INF
		for s in feet[f]:
			low = minf(low, s.x)
		for i in range(1, feet[f].size()):
			var a: Vector2 = feet[f][i - 1]
			var b: Vector2 = feet[f][i]
			if a.x <= low + 0.015 and b.x <= low + 0.015:
				slips.append((b.y - a.y) / dt)
	slips.sort()
	return Vector2(slips[slips.size() / 2], slips.size())


## The feet do not slide: at the server's speed (between the walk and the jog), sprinting (Shift), at each gait's own speed
## and for every body shape, a foot on the ground stays where it landed on the map.
func test_planted_feet_stay_on_the_ground() -> void:
	var c: Dictionary = Character3D.clips()["clips"]
	var probe := Character3D.new()
	var server_v := Protocol.SPEED_CELLS_PER_S * probe.cell_m
	probe.free()
	var cases := []
	for body in CharacterParts.parts_for("body"):
		cases.append([body, server_v])
		cases.append([body, server_v * Protocol.SPRINT_FACTOR])
		if CharacterParts.part(body)["morph"] == CharacterMorph.BASE:
			for g in Character3D.GAITS:
				cases.append([body, float(c[g]["ground_speed_m_s"])])
	for case in cases:
		var v: float = case[1]
		var r := _planted_slip(case[0], v)
		var what := "%s at %.2f m/s" % [case[0], v]
		assert_true(r.y >= 10.0, "%s: feet on the ground for %d frames" % [what, r.y])
		assert_true(absf(r.x) <= 0.15 * v, "%s: a planted foot slides at %+.2f m/s on the map" % [what, r.x])
