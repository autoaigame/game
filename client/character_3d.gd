## A player drawn as a 3D model rendered as pixel art (client/model_3d.gd draws it): the body glb or the
## look's parts (CharacterRig), animated by idle and gait clips blended by ground speed, the feet kept in
## step with the ground, the head lifted for the camera.
## Display only: positions still come from the server (docs/invariants.md, rule 1).
class_name Character3D
extends Model3D

const MODEL := "res://assets/character/body.glb"
const CLIPS_JSON := "res://assets/character/body_clips.json"
## Locomotion clips, slowest first. Each plants its feet at its own ground speed (body_clips.json).
const GAITS: Array[String] = ["walk", "jog", "sprint"]
## Speed shown is smoothed over about this long (s), so starts and stops blend instead of popping.
const SPEED_TAU_S := 0.12

## The head is raised this much over the clips (which look down a little), so the face shows under the
## camera's 30 degrees from above.
const HEAD_LIFT_DEG := 12.0
## The head's texture and the face zone in it, in texels (art/character/body.py, HEAD_TEXTURE, FACE_RECT).
const HEAD_TEXTURE := Vector2(48, 22)
const FACE_RECT := Vector4(12, 6, 24, 16)
## The eyes' ramp on a face (data/character/ramps.json).
const EYE_RAMP := "eyes"

static var _clips := {}
static var _models := {}  ## path -> PackedScene

## The parts worn (CharacterParts look); [] draws the bare body glb. Change it with set_look().
var look: Array = []
var phase := 0.0  ## locomotion cycle, 0..1, 0 = left foot under the hips in every gait
var speed_m_s := 0.0  ## smoothed ground speed
var idle_t := 0.0
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _morph: CharacterMorph  ## the body shape's bone changes, after each animation update
var _lengths := {}


static func clips() -> Dictionary:
	if _clips.is_empty():
		_clips = JSON.parse_string(FileAccess.get_file_as_string(CLIPS_JSON))
	return _clips


## Gait weights at a ground speed (m/s): {"idle", "walk", "jog", "sprint"} summing to 1. Between two
## gaits' speeds, a linear blend; below the walk, towards idle; above the sprint, sprint only.
static func gait_weights(v: float) -> Dictionary:
	var c: Dictionary = clips()["clips"]
	var w := {"idle": 0.0, "walk": 0.0, "jog": 0.0, "sprint": 0.0}
	var speeds: Array[float] = [0.0]
	var names: Array[String] = ["idle"]
	for g in GAITS:
		speeds.append(float(c[g]["ground_speed_m_s"]))
		names.append(g)
	if v >= speeds[-1]:
		w[names[-1]] = 1.0
		return w
	for i in range(1, speeds.size()):
		if v < speeds[i]:
			var t := clampf((v - speeds[i - 1]) / (speeds[i] - speeds[i - 1]), 0.0, 1.0)
			w[names[i - 1]] = 1.0 - t
			w[names[i]] = t
			return w
	return w


## Metres the body travels per locomotion cycle at a ground speed: the blend of the gaits' strides. The
## phase advances by speed / stride, so the planted foot moves with the ground.
static func stride_at(v: float) -> float:
	var c: Dictionary = clips()["clips"]
	var w := gait_weights(v)
	var moving := 0.0
	var s := 0.0
	for g in GAITS:
		s += w[g] * float(c[g]["stride_m"])
		moving += w[g]
	if moving <= 0.0:
		return float(c["walk"]["stride_m"])
	return s / moving


## Phase after dt seconds at a ground speed; stride_scale: how much longer the body shape's stride is.
static func advance_phase(p: float, v: float, dt: float, stride_scale := 1.0) -> float:
	return fposmod(p + v / (stride_at(v) * stride_scale) * dt, 1.0)


## Clip time (s) of a gait at a shared phase: phase 0 is that clip's left mid-stance.
static func clip_time(gait: String, p: float) -> float:
	var c: Dictionary = clips()["clips"][gait]
	return fposmod(p + float(c["left_mid_stance"]), 1.0) * float(c["duration_s"])


## Shared phases (0..1) where the left and the right foot land at a ground speed: each gait's measured
## contacts, moved into the shared phase, blended by gait weight (on the circle).
static func contact_phases(v: float) -> Array[float]:
	var c: Dictionary = clips()["clips"]
	var w := gait_weights(v)
	var out: Array[float] = []
	for side in ["left", "right"]:
		var sum := Vector2.ZERO
		for g in GAITS:
			var p := float(c[g][side + "_contact"]) - float(c[g]["left_mid_stance"])
			sum += Vector2.from_angle(TAU * p) * maxf(w[g], 0.0)
		if sum == Vector2.ZERO:  # standing: the walk's
			sum = Vector2.from_angle(TAU * (float(c["walk"][side + "_contact"]) - float(c["walk"]["left_mid_stance"])))
		out.append(fposmod(sum.angle() / TAU, 1.0))
	return out


## Feet landing while the phase goes from `from` to `to` (forwards, less than half a cycle) at speed v.
## A contact reached exactly counts once, on arrival.
static func contacts_between(from: float, to: float, v: float) -> int:
	var span := fposmod(to - from, 1.0)
	if span >= 0.5 or span == 0.0:
		return 0
	var n := 0
	for c in contact_phases(v):
		var ahead := fposmod(c - from, 1.0)
		if ahead > 0.0 and ahead <= span:
			n += 1
	return n


## The model under the pivot: the look's parts (or the bare body glb), its surfaces drawn by
## pixel_3d_lit.gdshader, and the animation tree on its AnimationPlayer.
func _build_model() -> void:
	if look.is_empty():
		if not _models.has(MODEL):
			_models[MODEL] = load(MODEL)
		_model = _models[MODEL].instantiate()
	else:
		_model = CharacterRig.build(look)
	_pivot.add_child(_model)
	_matte(_model)
	var player: AnimationPlayer = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for g in ["idle"] + GAITS:
		_lengths[g] = player.get_animation(g).length
	_tree = _make_tree(player)
	_model.add_child(_tree)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_morph = CharacterMorph.new(_skeleton, _model.get_meta("morph", CharacterMorph.BASE))
	_tree.anim_player = _tree.get_path_to(player)
	_tree.active = true


## Turns the head up by HEAD_LIFT_DEG, around the skeleton's left-right axis, after an animation update.
static func lift_head(sk: Skeleton3D) -> void:
	var b := sk.find_bone("DEF-head")
	if b < 0:
		return
	var pb := sk.get_bone_global_rest(sk.get_bone_parent(b)).basis
	var up := Basis(Vector3(1, 0, 0), deg_to_rad(-HEAD_LIFT_DEG))
	sk.set_bone_pose_rotation(b, (pb.inverse() * up * pb).get_rotation_quaternion() * sk.get_bone_pose_rotation(b))


## Wears another look: the model is rebuilt from its parts, keeping facing, phase and speed.
func set_look(new_look: Array) -> void:
	if new_look == look:
		return
	look = new_look.duplicate(true)
	if _pivot == null:
		return
	_pivot.remove_child(_model)
	_model.queue_free()
	_materials.clear()
	_build_model()
	_pose()


## A surface in the ramp the player chose (CharacterRig's override material says which), with the face
## and beard textures on the head; without one, its own glTF colour (Model3D._matte).
func _decorate(sm: ShaderMaterial, mi: MeshInstance3D, m: Material) -> void:
	if m == null or not m.has_meta("ramp"):
		return
	_set_ramp(sm, "ramp", m.get_meta("ramp"))
	_set_ramp(sm, "eye_ramp", EYE_RAMP)
	for slot in ["face", "beard"]:
		if mi.has_meta(slot):
			var t: Dictionary = mi.get_meta(slot)
			sm.set_shader_parameter("use_" + slot, true)
			sm.set_shader_parameter(slot + "_tex", load(t["texture"]))
			_set_ramp(sm, slot + "_ramp", t["ramp"])
	sm.set_shader_parameter("face_rect", FACE_RECT)
	sm.set_shader_parameter("head_tex", HEAD_TEXTURE)


## A ramp of data/character/ramps.json as palette indices, into the shader's `param` and `param`_len.
static func _set_ramp(sm: ShaderMaterial, param: String, ramp_name: String) -> void:
	var idx := ramp_indices(ramp_name)
	var len := idx.size()
	idx.resize(8)
	sm.set_shader_parameter(param, idx)
	sm.set_shader_parameter(param + "_len", len)


## The palette indices of a ramp's colours (data/character/ramps.json), dark to light.
static func ramp_indices(ramp_name: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pal := palette()
	for c in CharacterParts.ramp(ramp_name).get("colours", []):
		var i := pal.find(c)
		out.append(i if i >= 0 else 0)
	return out


## idle and each gait, each through a TimeSeek set every update, blended by gait_weights.
func _make_tree(player: AnimationPlayer) -> AnimationTree:
	var bt := AnimationNodeBlendTree.new()
	var x := 0
	for g in ["idle"] + GAITS:
		var a := AnimationNodeAnimation.new()
		a.animation = g
		bt.add_node(g, a, Vector2(x, 0))
		bt.add_node("seek_" + g, AnimationNodeTimeSeek.new(), Vector2(x, 100))
		bt.connect_node("seek_" + g, 0, g)
		x += 200
	# ((walk + jog) + sprint), then idle + that.
	bt.add_node("walk_jog", AnimationNodeBlend2.new())
	bt.connect_node("walk_jog", 0, "seek_walk")
	bt.connect_node("walk_jog", 1, "seek_jog")
	bt.add_node("run", AnimationNodeBlend2.new())
	bt.connect_node("run", 0, "walk_jog")
	bt.connect_node("run", 1, "seek_sprint")
	bt.add_node("move", AnimationNodeBlend2.new())
	bt.connect_node("move", 0, "seek_idle")
	bt.connect_node("move", 1, "run")
	bt.connect_node("output", 0, "move")
	var tree := AnimationTree.new()
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return tree


## Feeds one frame: the drawn movement this frame in cells and its duration. Updates speed, phase and
## facing. Returns how many feet landed (footsteps).
func step(cell_delta: Vector2, dt: float) -> int:
	if dt <= 0.0:
		return 0
	var v := cell_delta.length() * cell_m / dt
	speed_m_s += (v - speed_m_s) * (1.0 - exp(-dt / SPEED_TAU_S))
	if speed_m_s < 0.02 and v == 0.0:
		speed_m_s = 0.0
	if cell_delta.length() > 1e-5:
		target_yaw = yaw_of(cell_delta)
	turn(dt)
	var before := phase
	phase = advance_phase(phase, speed_m_s, dt, _morph.stride_scale if _morph != null else 1.0)
	idle_t = idle_t + dt if speed_m_s < 0.05 else 0.0
	_pose()
	return contacts_between(before, phase, speed_m_s) if speed_m_s >= 0.05 else 0


## The clips blended by gait weight at the current phase, then the body shape and the head lift.
func _animate() -> void:
	if _tree == null:
		return
	var w := gait_weights(speed_m_s)
	var moving: float = w["walk"] + w["jog"] + w["sprint"]
	_tree.set("parameters/move/blend_amount", moving)
	var run: float = w["sprint"] / moving if moving > 0.0 else 0.0
	_tree.set("parameters/run/blend_amount", run)
	var wj: float = w["jog"] / (w["walk"] + w["jog"]) if w["walk"] + w["jog"] > 0.0 else 1.0
	_tree.set("parameters/walk_jog/blend_amount", wj)
	_tree.set("parameters/seek_idle/seek_request", fposmod(idle_t, _lengths["idle"]))
	for g in GAITS:
		_tree.set("parameters/seek_%s/seek_request" % g, minf(clip_time(g, phase), _lengths[g] - 0.0001))
	_tree.advance(0.0)
	_morph.apply(_skeleton)
	lift_head(_skeleton)
