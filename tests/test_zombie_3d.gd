extends TestCase

## The zombie model (art/models/zombie.py, client/zombie_3d.gd): its clips and their checks, the scale
## next to the player, the blend of walk, attack and death. Display only.


func test_clips_are_there_with_their_timings() -> void:
	var c: Dictionary = Zombie3D.clips()["clips"]
	for name in ["idle", "walk", "attack", "death"]:
		assert_true(c.has(name), name)
		assert_true(float(c[name]["duration_s"]) > 0.0, name)
	assert_true(float(c["walk"]["ground_speed_m_s"]) > 0.0)
	assert_almost(float(c["walk"]["stride_m"]) / float(c["walk"]["ground_speed_m_s"]), float(c["walk"]["duration_s"]),
			0.01, "the walk plays at 1x at its own speed")
	assert_true(float(c["attack"]["hit_s"]) < float(c["attack"]["duration_s"]))


## What art/models/zombie.py measured on the deformed mesh: soles on the ground, planted feet that do not
## slide, no arm in the torso, no leg through the other, every IK target reached.
func test_script_checks_hold() -> void:
	var checks: Dictionary = Zombie3D.clips()["checks"]
	for name in ["idle", "walk", "attack"]:
		var c: Dictionary = checks[name]
		assert_true(absf(float(c["sole_min_m"])) <= 0.01, "%s: sole at %.3f m" % [name, c["sole_min_m"]])
		assert_true(float(c["slide_max_m"]) <= 0.02, "%s: planted foot slides %.3f m" % [name, c["slide_max_m"]])
		assert_true(float(c["ik_miss_m"]) <= 0.005, "%s: foot misses its target by %.3f m" % [name, c["ik_miss_m"]])
		for k in c:
			if String(k).begins_with("arm_in_") or String(k).begins_with("leg_in_"):
				assert_eq(int(c[k]["poses"]), 0, "%s: %s" % [name, k])
	assert_true(float(checks["death"]["sole_min_m"]) >= -0.01, "lying on the ground, not in it")


## No crack at a joint: where two volumes overlap round a joint, they stay overlapped in every pose of every
## clip (rig_kit.joint_gaps, notches wider than half a pixel).
func test_joints_stay_closed() -> void:
	var checks: Dictionary = Zombie3D.clips()["checks"]
	for name in ["idle", "walk", "attack", "death"]:
		var joints: Dictionary = checks[name]["joints"]
		assert_true(joints.size() > 10, "%s: joints measured" % name)
		for j in joints:
			assert_eq(int(joints[j]["poses"]), 0, "%s: %s opens by %.3f m" % [name, j, joints[j]["max_m"]])


## Same scale as the player: in metres, about a player's size, inside its viewport in every clip.
func test_zombie_has_the_player_scale() -> void:
	var z := Zombie3D.new()
	var p := Character3D.new()
	assert_almost(z.px_per_m, p.px_per_m, 0.0001, "one scale for every model")
	var h := float(Zombie3D.clips()["height_m"])
	assert_true(h > 1.5 and h < 1.9, "standing height %.2f m" % h)
	z.free()
	p.free()


func test_model_has_the_clips_and_named_bones() -> void:
	var root: Node = load(Zombie3D.MODEL).instantiate()
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	for name in ["idle", "walk", "attack", "death"]:
		assert_true(player.has_animation(name), name)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	for b in ["DEF-hips", "DEF-head", "DEF-hand.L", "DEF-foot.R"]:
		assert_true(sk.find_bone(b) >= 0, b)
	root.free()


func test_walk_weight_follows_speed() -> void:
	var v := float(Zombie3D.clips()["clips"]["walk"]["ground_speed_m_s"])
	assert_eq(Zombie3D.walk_weight(0.0), 0.0)
	assert_almost(Zombie3D.walk_weight(v / 2.0), 0.5, 0.0001)
	assert_eq(Zombie3D.walk_weight(v * 3.0), 1.0)


## The planted foot moves with the ground: one cycle per stride.
func test_phase_advances_by_stride() -> void:
	var c: Dictionary = Zombie3D.clips()["clips"]["walk"]
	var v := float(c["ground_speed_m_s"])
	var p := 0.0
	var cycles := 0.0
	var dt := 1.0 / 60.0
	for i in 600:
		var np := Zombie3D.advance_phase(p, v, dt)
		cycles += fposmod(np - p, 1.0)
		p = np
	assert_almost(cycles, 600 * dt * v / float(c["stride_m"]), 0.01)


## An action clip fades in, plays once, fades out; death fades in and stays.
func test_action_weight_fades_in_and_out() -> void:
	assert_eq(Zombie3D.action_weight(-1.0, 1.2, false), 0.0, "not playing")
	assert_eq(Zombie3D.action_weight(0.0, 1.2, false), 0.0, "starts from the current pose")
	assert_almost(Zombie3D.action_weight(Zombie3D.FADE_S, 1.2, false), 1.0, 0.0001)
	assert_almost(Zombie3D.action_weight(0.6, 1.2, false), 1.0, 0.0001)
	assert_eq(Zombie3D.action_weight(1.2, 1.2, false), 0.0, "over")
	assert_almost(Zombie3D.action_weight(5.0, 1.6, true), 1.0, 0.0001, "death holds its last pose")


func test_attack_hits_once_then_ends() -> void:
	var z := Zombie3D.new()
	z.attack()
	assert_true(z.is_attacking())
	var hits := 0
	for i in 120:
		hits += 1 if z.step(Vector2.ZERO, 1.0 / 60.0) else 0
	assert_eq(hits, 1, "one hit per attack")
	assert_false(z.is_attacking(), "over after its clip")
	z.free()


func test_dead_zombie_neither_walks_nor_attacks() -> void:
	var z := Zombie3D.new()
	z.die()
	z.attack()
	assert_false(z.is_attacking())
	for i in 30:
		z.step(Vector2(0.05, 0.0), 1.0 / 60.0)
	assert_eq(z.speed_m_s, 0.0, "a dead zombie does not walk")
	assert_true(z.is_dead())
	z.free()
