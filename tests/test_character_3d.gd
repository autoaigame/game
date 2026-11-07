extends TestCase

## The 3D character (client/character_3d.gd): gait blend, stride sync, footsteps, facing, scale, palette.
## Display only.


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
