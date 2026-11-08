extends TestCase

## The Tripo dog skins (client/dog_3d.gd).

const Pose := preload("res://tests/character_pose.gd")

## Paw joints (the head of each leg's last bone), by the gait scripts' leg names.
const PAWS := {"FL": "tripo__0_Left_Limb_3", "FR": "tripo__0_Right_Limb_3", "HL": "tripo__1_Left_Limb_3", "HR": "tripo__1_Right_Limb_3"}
## The game's dog speeds in cells per second (server/dog.gd): sniffing, following, catching up, hunting.
const SERVER_SPEEDS := [2.0, 4.0, 6.5, 9.0]
## A paw counts as planted within this height (m) of its lowest point.
const PLANTED_M := 0.003


## Every skin's model loads and has the clips Dog3D plays.
func test_every_skin_has_its_clips() -> void:
	for s in Dog3D.SKINS:
		var root: Node = (load(s["model"]) as PackedScene).instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, s["model"])
		for c in ["idle", "walk", "trot", "gallop", "sit"]:
			assert_true((players[0] as AnimationPlayer).has_animation(c), "%s has no %s" % [s["model"], c])
		root.free()


## The strides Dog3D reads are the ones written into each clip of the GLB (glTF animation extras).
func test_gait_json_matches_the_clips_extras() -> void:
	for i in Dog3D.SKINS.size():
		var path: String = Dog3D.SKINS[i]["model"]
		var f := FileAccess.open(path, FileAccess.READ)
		f.seek(12)
		var n := f.get_32()
		f.get_32()
		var doc: Dictionary = JSON.parse_string(f.get_buffer(n).get_string_from_utf8())
		var seen := 0
		for a in doc["animations"]:
			if a["name"] in Dog3D.GAITS:
				seen += 1
				var ex: Dictionary = a["extras"]
				assert_almost(float(ex["stride_m"]), Dog3D.stride_of(i, a["name"]), 1e-3, "%s %s" % [path, a["name"]])
				assert_almost(float(ex["leg_m"]), float(Dog3D.skin_gaits(i)["leg_m"]), 1e-3, path)
				assert_almost(float(ex["duration_s"]), Dog3D.clip_s(i, a["name"]), 1e-6, path)
				var gj: Dictionary = Dog3D.skin_gaits(i)["gaits"][a["name"]]
				assert_almost(float(ex["duty"]), float(gj["duty"]), 1e-6, path)
				for paw in PAWS:
					assert_almost(float(ex["offset_" + paw]), float(gj["offsets"][paw]), 1e-6, "%s %s" % [path, paw])
		assert_eq(seen, 3, path)


## Moving shows the gait at the master phase; sit is the real sit; the other states standing still are
## stand-ins.
func test_shown_pose() -> void:
	assert_eq(Dog3D.shown("follow", true, "trot", 0.4), {"clip": "trot", "at": 0.4, "provisional": false})
	assert_eq(Dog3D.shown("hunt", true, "gallop", 0.4), {"clip": "gallop", "at": 0.4, "provisional": false})
	assert_eq(Dog3D.shown("sit", false, "walk", 0.4), {"clip": "sit", "at": 0.0, "provisional": false})
	for st in ["sleep", "pee", "dig", "idle", "sniff"]:
		assert_true(Dog3D.shown(st, false, "walk", 0.0)["provisional"], st)


## speed_scale = v / (S / T): 1 at the clip's own speed, and the phase goes at v / S cycles per second.
func test_speed_scale() -> void:
	assert_almost(Dog3D.speed_scale(0.5, 1.0, 2.0), 1.0, 1e-6)
	assert_almost(Dog3D.speed_scale(3.0, 1.5, 2.0), 4.0, 1e-6)
	assert_almost(Dog3D.advance(0.0, 3.0, 0.1, 1.5), 0.2, 1e-6)
	assert_almost(Dog3D.advance(0.9, 3.0, 0.1, 1.5), 0.1, 1e-6)


## Gait by speed: walk, then trot, then gallop at the Froude speeds, coming back down a little lower. At the
## game's speeds every skin trots while sniffing and gallops when following, catching up and hunting.
func test_gait_follows_speed() -> void:
	var up := Dog3D.gait_speeds(0.35)
	assert_eq(Dog3D.choose_gait("walk", up.x * 0.99, 0.35), "walk")
	assert_eq(Dog3D.choose_gait("walk", up.x * 1.01, 0.35), "trot")
	assert_eq(Dog3D.choose_gait("walk", up.y * 1.01, 0.35), "gallop")
	assert_eq(Dog3D.choose_gait("gallop", up.y * 0.95, 0.35), "gallop", "hysteresis")
	assert_eq(Dog3D.choose_gait("gallop", up.y * 0.8, 0.35), "trot")
	assert_eq(Dog3D.choose_gait("gallop", 0.1, 0.35), "walk")
	var probe := Dog3D.new(0)
	var cell_m := probe.cell_m
	probe.free()
	for i in Dog3D.SKINS.size():
		var leg := float(Dog3D.skin_gaits(i)["leg_m"])
		var got := []
		for c in SERVER_SPEEDS:
			got.append(Dog3D.choose_gait("walk", c * cell_m, leg))
		assert_eq(got, ["trot", "gallop", "gallop", "gallop"], Dog3D.SKINS[i]["key"])


## A gait change fades over BLEND_S: halfway after half of it, done after it.
func test_gait_cross_fade() -> void:
	var w := {"walk": 1.0, "trot": 0.0, "gallop": 0.0}
	w = Dog3D.blend_towards(w, "trot", Dog3D.BLEND_S / 2.0)
	assert_almost(w["trot"], 0.5, 1e-4)
	assert_almost(w["walk"] + w["trot"] + w["gallop"], 1.0, 1e-6)
	w = Dog3D.blend_towards(w, "trot", Dog3D.BLEND_S / 2.0)
	assert_eq(w, {"walk": 0.0, "trot": 1.0, "gallop": 0.0})


## Poses `sk` with clip `a` at time t (the tracks interpolated as the AnimationTree does with one clip).
static func _pose(sk: Skeleton3D, a: Animation, t: float) -> void:
	sk.reset_bone_poses()
	for k in a.get_track_count():
		var bone := sk.find_bone(String(a.track_get_path(k).get_concatenated_subnames()))
		if bone < 0:
			continue
		match a.track_get_type(k):
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, a.position_track_interpolate(k, t))
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, a.rotation_track_interpolate(k, t))
			Animation.TYPE_SCALE_3D:
				sk.set_bone_pose_scale(bone, a.scale_track_interpolate(k, t))


## The model of a skin, its skeleton, its clips by name, and the transform from skeleton space to the
## model's (faces +Z, metres).
static func _rig(skin: int) -> Array:
	var root: Node = (load(Dog3D.SKINS[skin]["model"]) as PackedScene).instantiate()
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var clips := {}
	for g in Dog3D.GAITS:
		clips[g] = player.get_animation(g)
	var to_model := Transform3D.IDENTITY
	var n: Node = sk
	while n != root:
		to_model = (n as Node3D).transform * to_model
		n = n.get_parent()
	return [root, sk, clips, to_model]


## Appends each paw's (height, position along the way, sideways position) on the map, the body being
## `along` metres down its straight way, posed in gait g at phase p.
static func _add_paws(out: Dictionary, rig: Array, skin: int, g: String, p: float, along: float) -> void:
	var sk: Skeleton3D = rig[1]
	var a: Animation = rig[2][g]
	_pose(sk, a, minf(p * Dog3D.clip_s(skin, g), a.length - 0.0001))
	var gl := Pose.globals(sk)
	for paw in PAWS:
		var at: Vector3 = rig[3] * gl[sk.find_bone(PAWS[paw])].origin
		out[paw].append(Vector3(at.y, along + at.z, at.x))


## Each paw's track every 1/60 s while the dog goes straight ahead at v m/s for `seconds` in gait g, its
## phase advanced by Dog3D.advance.
static func _paw_tracks(skin: int, g: String, v: float, seconds: float) -> Dictionary:
	var rig := _rig(skin)
	var dt := 1.0 / 60.0
	var p := 0.0
	var along := 0.0
	var out := {}
	for paw in PAWS:
		out[paw] = []
	for i in int(seconds * 60.0):
		p = Dog3D.advance(p, v, dt, Dog3D.stride_of(skin, g))
		along += v * dt
		_add_paws(out, rig, skin, g, p, along)
	(rig[0] as Node).free()
	return out


## For one paw's track: how far it moved on the map (along and sideways) during each stance (frames
## within PLANTED_M of its lowest point; a frame of height INF is not measured and ends a stance), the
## largest of them, and the share of measured frames planted.
static func _stance_drift(track: Array) -> Vector2:
	var low := INF
	var measured := 0
	for s in track:
		if s.x < INF:
			low = minf(low, s.x)
			measured += 1
	var worst := 0.0
	var planted := 0
	var first := Vector2.INF
	for s in track:
		if s.x <= low + PLANTED_M:
			planted += 1
			var here := Vector2(s.y, s.z)
			if first == Vector2.INF:
				first = here
			worst = maxf(worst, here.distance_to(first))
		else:
			first = Vector2.INF
	return Vector2(worst, float(planted) / maxf(1.0, measured))


## The clips and their strides agree: at each game speed of the dog (in the gait Dog3D picks for it) and
## at each gait's own top speed, a planted paw moves less than half a screen pixel on the map while it is
## down, and is down about its duty factor of the cycle. Measured on the skeleton of every skin as
## imported (Godot's animation optimizer leaves a few mm), as for the player (test_character_3d).
func test_planted_paws_stay_on_the_ground() -> void:
	var probe := Dog3D.new(0)
	var cell_m := probe.cell_m
	var half_px := 0.5 / probe.px_per_m
	probe.free()
	for i in Dog3D.SKINS.size():
		var leg := float(Dog3D.skin_gaits(i)["leg_m"])
		var up := Dog3D.gait_speeds(leg)
		var cases := [["walk", up.x], ["trot", up.y], ["gallop", 10.0]]
		for c in SERVER_SPEEDS:
			cases.append([Dog3D.choose_gait("walk", c * cell_m, leg), c * cell_m])
		for case in cases:
			var tracks := _paw_tracks(i, case[0], case[1], 2.0)
			var duty := float(Dog3D.skin_gaits(i)["gaits"][case[0]]["duty"])
			for paw in PAWS:
				var d := _stance_drift(tracks[paw])
				var what := "%s %s %.2f m/s %s" % [Dog3D.SKINS[i]["key"], case[0], case[1], paw]
				assert_true(d.x < half_px, "%s: a planted paw slides %.1f mm" % [what, d.x * 1000.0])
				assert_true(d.y >= duty - 0.05, "%s: planted %.0f %% of the time, duty %.2f" % [what, d.y * 100.0, duty])


## In game: the server moves the dog at a speed and sends a snapshot TICK_HZ times a second; the client
## draws it with WalkAnim.follow (in steps, with frames that do not move) and feeds Dog3D.step, as
## world_view does. Each paw is measured on the map, the body being where it is drawn. A planted paw
## moves less than half a pixel, at each of the dog's speeds and when it speeds up from following to
## catching up. Frames in a cross-fade (two gaits, or standing and moving) are not measured.
func test_paws_stay_planted_in_game() -> void:
	var probe := Dog3D.new(0)
	var half_px := 0.5 / probe.px_per_m
	probe.free()
	var runs := [[2.0], [4.0], [6.5], [9.0], [4.0, 6.5]]
	for i in Dog3D.SKINS.size():
		var rig := _rig(i)
		for run in runs:
			var dog := Dog3D.new(i)
			var server := Vector2.ZERO
			var shown := Vector2.ZERO
			var speed := 0.0
			var tick := 0.0
			var out := {}
			for paw in PAWS:
				out[paw] = []
			var dt := 1.0 / 60.0
			for f in 240 * run.size():
				var c: float = run[f / 240]
				tick += dt
				if tick >= 1.0 / Protocol.TICK_HZ:
					tick -= 1.0 / Protocol.TICK_HZ
					var next := server + Vector2(1, -1).normalized() * c / Protocol.TICK_HZ
					speed = WalkAnim.speed_between(server, next)
					server = next
				var before := shown
				shown = WalkAnim.follow(before, server, dt, speed)
				dog.step(shown - before, dt, "follow")
				var g := dog.shown_gait()
				if f >= 60 and dog.move_weight >= 1.0 and dog.weights[g] >= 1.0:
					_add_paws(out, rig, i, g, dog.phase, shown.length() * dog.cell_m)
				else:
					for paw in PAWS:
						out[paw].append(Vector3(INF, 0, 0))
			dog.free()
			for paw in PAWS:
				var d := _stance_drift(out[paw])
				var what := "%s %s c/s %s" % [Dog3D.SKINS[i]["key"], run, paw]
				assert_true(d.x < half_px, "%s: a planted paw slides %.1f mm" % [what, d.x * 1000.0])
				assert_true(d.y > 0.1, "%s: planted %.0f %% of the measured frames" % [what, d.y * 100.0])
		(rig[0] as Node).free()


## Each gait sets its paws down in the dog's order (offsets in the JSON): walk hind left, front left,
## hind right, front right; trot by diagonals; rotary gallop hind left, hind right, front right, front
## left. Measured from the clip: the first planted frame after each swing, as a share of the cycle.
func test_footfall_order() -> void:
	var order := {"walk": ["HL", "FL", "HR", "FR"], "gallop": ["HL", "HR", "FR", "FL"]}
	for i in Dog3D.SKINS.size():
		for g in Dog3D.GAITS:
			var tracks := _paw_tracks(i, g, Dog3D.stride_of(i, g), 1.0)  # one cycle in 60 frames
			var land := {}
			for paw in PAWS:
				var tr: Array = tracks[paw]
				var low := INF
				for x in tr:
					low = minf(low, x.x)
				for f in range(1, tr.size()):
					if tr[f].x <= low + PLANTED_M and tr[f - 1].x > low + PLANTED_M:
						land[paw] = fposmod(float(f + 1) / 60.0, 1.0)
				var want := float(Dog3D.skin_gaits(i)["gaits"][g]["offsets"][paw])
				var off := absf(angle_difference(TAU * float(land.get(paw, -1.0)), TAU * want)) / TAU
				assert_true(off < 0.04, "%s %s %s lands at %.2f, not %.2f" % [Dog3D.SKINS[i]["key"], g, paw, land.get(paw, -1.0), want])
			if order.has(g) and land.size() == 4:
				var seq: Array = order[g].duplicate()
				seq.sort_custom(func(x, y): return fposmod(land[x] - land["HL"], 1.0) < fposmod(land[y] - land["HL"], 1.0))
				assert_eq(seq, order[g], "%s %s" % [Dog3D.SKINS[i]["key"], g])
