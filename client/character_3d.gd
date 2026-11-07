## A player drawn as a 3D model rendered as pixel art. The model is rendered alone in a small SubViewport,
## one texel per screen pixel, by an orthographic camera at the game's 2:1 angle, lit in flat bands and
## snapped to the palette (client/pixel_3d_lit.gdshader), then drawn as a Sprite2D that adds a 1 px outline
## (client/pixel_3d.gdshader). The model never moves inside its viewport (the Sprite2D moves, on whole
## pixels), so walking never shimmers; only turning and the animation change texels.
## Display only: positions still come from the server (docs/invariants.md, rule 1).
class_name Character3D
extends Node2D

const MODEL := "res://assets/character/body.glb"
const CLIPS_JSON := "res://assets/character/body_clips.json"
const PALETTE_JSON := "res://data/palette.json"
const SHADER := "res://client/pixel_3d.gdshader"
const GHOST_SHADER := "res://client/pixel_3d_ghost.gdshader"
const LIT_SHADER := "res://client/pixel_3d_lit.gdshader"
## Most palette colours the shaders take (uniform array size; red code = index * 4).
const MAX_COLOURS := 64
## Viewport size in texels, and where the feet stand in it.
const VIEW_SIZE := Vector2i(112, 128)
const FOOT_PX := 14
## Screen height of the top of the head: a little under WalkAnim.HEAD_PX (the name sits above that), so
## the body does not look heavier than the former sprite and a taller body shape stays under the name.
const HEAD_PX := 100.0
## Camera elevation of the game's 2:1 view: asin(1/2).
const ELEVATION_DEG := 30.0
## Locomotion clips, slowest first. Each plants its feet at its own ground speed (body_clips.json).
const GAITS: Array[String] = ["walk", "jog", "sprint"]
## Turning speed of the body, degrees per second.
const TURN_DEG_S := 540.0
## Speed shown is smoothed over about this long (s), so starts and stops blend instead of popping.
const SPEED_TAU_S := 0.12

## Look of the render. Light in TOON_LEVELS flat bands; the shaded side at AMBIENT of the colour, the lit
## side at AMBIENT + SUN; HUE_LOCK keeps each surface on palette colours of its own hue (without it, skin
## falls on sand or grey-green: the palette has few skin tones).
const TOON_LEVELS := 3
const AMBIENT := 0.7
const SUN := 0.6
const HUE_LOCK := 30.0
## Light from the screen's left and a little from the front (world space, towards the light): the side
## facing the camera is lit.
const LIGHT_DIR := Vector3(-0.17, 0.766, 0.62)
## Ground shadow: an ellipse like the objects' shadows, pushed away from the top-left light.
const SHADOW_SIZE := Vector2(38.0, 14.0)
const SHADOW_SHIFT := Vector2(5.0, 2.0)
const SHADOW_COLOR := Color8(20, 22, 16, 97)  ## the objects' shadow colour and opacity
## The head is raised this much over the clips (which look down a little), so the face shows under the
## camera's 30 degrees from above.
const HEAD_LIFT_DEG := 12.0
## The head's texture and the face zone in it, in texels (art/character/body.py, HEAD_TEXTURE, FACE_RECT).
const HEAD_TEXTURE := Vector2(48, 22)
const FACE_RECT := Vector4(12, 6, 24, 16)
## The eyes' ramp on a face (data/character/ramps.json).
const EYE_RAMP := "eyes"

static var _clips := {}
static var _palette := PackedColorArray()
static var _dark_of := PackedInt32Array()
static var _models := {}  ## path -> PackedScene

## The parts worn (CharacterParts look); [] draws the bare body glb. Change it with set_look().
var look: Array = []
var px_per_m := 0.0  ## texels per metre, so the head lands HEAD_PX above the feet
var cell_m := 0.0  ## metres per game cell at that scale
var phase := 0.0  ## locomotion cycle, 0..1, 0 = left foot under the hips in every gait
var speed_m_s := 0.0  ## smoothed ground speed
var yaw := PI / 4.0  ## facing, radians around +Y (0 = towards +Z = cell +y; PI/4 faces the camera)
var target_yaw := PI / 4.0
var idle_t := 0.0

var viewport: SubViewport
var sprite: Sprite2D
var camera: Camera3D
var _pivot: Node3D
var _model: Node3D
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _morph: CharacterMorph  ## the body shape's bone changes, after each animation update
var _lengths := {}
var _materials: Array[ShaderMaterial] = []
var _shadow: Polygon2D
var _ghost: Sprite2D  ## silhouette copy drawn above the world, where a tree hides the model


static func clips() -> Dictionary:
	if _clips.is_empty():
		_clips = JSON.parse_string(FileAccess.get_file_as_string(CLIPS_JSON))
	return _clips


## The palette (data/palette.json), every ramp in file order: the colours the 3D render may use.
static func palette() -> PackedColorArray:
	if _palette.is_empty():
		var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_JSON))
		for ramp in rec["ramps"]:
			for hex in rec["ramps"][ramp]:
				_palette.append(Color.html(hex))
	return _palette


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


## Yaw (radians around +Y) of a movement in cells: cell x is 3D +X, cell y is 3D +Z, the model faces +Z.
static func yaw_of(cell_delta: Vector2) -> float:
	return atan2(cell_delta.x, cell_delta.y)


## Next yaw towards a target at most max_step radians, the short way; a half-turn turns through the side
## facing the camera (yaw PI/4, towards cell (+1, +1)).
static func turn_towards(from: float, to: float, max_step: float) -> float:
	var d := angle_difference(from, to)
	if absf(absf(d) - PI) < 0.01:
		var to_cam := angle_difference(from, PI / 4.0)
		d = absf(d) * (1.0 if to_cam >= 0.0 else -1.0)
	if absf(d) <= max_step:
		return wrapf(from + d, -PI, PI)
	return wrapf(from + signf(d) * max_step, -PI, PI)


## For each palette colour, a darker one of a close hue (inner lines): the nearest palette colour to the
## colour scaled by 0.62, among the darker ones (itself when none is darker).
static func dark_of() -> PackedInt32Array:
	if not _dark_of.is_empty():
		return _dark_of
	var pal := palette()
	for i in pal.size():
		var c := pal[i]
		var target := Color(c.r * 0.62, c.g * 0.62, c.b * 0.62)
		var best := i
		var best_e := INF
		for j in pal.size():
			if pal[j].get_luminance() >= c.get_luminance() - 0.02:
				continue
			var e := redmean(pal[j], target)
			if e < best_e:
				best_e = e
				best = j
		_dark_of.append(best)
	return _dark_of


## Weighted RGB distance, close enough to perceptual for a small palette.
static func redmean(a: Color, b: Color) -> float:
	var r := (a.r + b.r) * 0.5
	return (2.0 + r) * pow(a.r - b.r, 2) + 4.0 * pow(a.g - b.g, 2) + (3.0 - r) * pow(a.b - b.b, 2)


## The palette as shader uniforms: colours padded to MAX_COLOURS, and its size.
static func palette_uniform() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in palette():
		out.append(Vector3(c.r, c.g, c.b))
	out.resize(MAX_COLOURS)
	return out


static func _dark_uniform() -> PackedInt32Array:
	var out := dark_of().duplicate()
	out.resize(MAX_COLOURS)
	return out


func _init() -> void:
	var cos_el := cos(deg_to_rad(ELEVATION_DEG))
	px_per_m = HEAD_PX / (float(clips()["height_m"]) * cos_el)
	cell_m = Vector2(IsoLayer.TILE_SIZE).x / (sqrt(2.0) * px_per_m)


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	# No lights: pixel_3d_lit.gdshader lights each surface itself. The environment keeps the output as
	# written (linear tonemap): without one, colours come out lighter.
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(env)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = VIEW_SIZE.y / px_per_m
	camera.near = 0.1
	camera.far = 20.0
	var el := deg_to_rad(ELEVATION_DEG)
	var back := Vector3(cos(el) / sqrt(2.0), sin(el), cos(el) / sqrt(2.0))
	camera.look_at_from_position(back * 8.0, Vector3.ZERO, Vector3.UP)
	camera.v_offset = (VIEW_SIZE.y / 2.0 - FOOT_PX) / px_per_m
	viewport.add_child(camera)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	_build_model()
	sprite = _view_sprite(SHADER)
	_shadow = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * SHADOW_SIZE.x / 2.0, sin(a) * SHADOW_SIZE.y / 2.0).round())
	_shadow.polygon = pts
	_shadow.color = SHADOW_COLOR
	_shadow.position = SHADOW_SHIFT
	add_child(_shadow)
	add_child(sprite)
	# The silhouette is drawn after everything else (top_level, outside the y-sorting), placed by place().
	_ghost = _view_sprite(GHOST_SHADER)
	_ghost.top_level = true
	add_child(_ghost)
	_pose()


func _view_sprite(shader_path: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = viewport.get_texture()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = false
	s.offset = Vector2(-VIEW_SIZE.x / 2.0, FOOT_PX - VIEW_SIZE.y)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("palette", palette_uniform())
	mat.set_shader_parameter("dark_of", _dark_uniform())
	s.material = mat
	return s


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


## Each surface drawn by pixel_3d_lit.gdshader: in the ramp the player chose (CharacterRig's override
## material says which), with the face and beard textures on the head; or in its own glTF colour.
func _matte(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			var c: Color = m.albedo_color if m is BaseMaterial3D else Color.WHITE
			var sm := lit_material(c)
			if m != null and m.has_meta("ramp"):
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
			mi.set_surface_override_material(s, sm)


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


## A material of pixel_3d_lit.gdshader in a colour (sRGB, as in the glTF material), with the render look.
func lit_material(colour: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load(LIT_SHADER)
	sm.set_shader_parameter("albedo", colour)
	sm.set_shader_parameter("material_id", _materials.size() % 16)
	sm.set_shader_parameter("palette", palette_uniform())
	sm.set_shader_parameter("palette_size", palette().size())
	sm.set_shader_parameter("toon_levels", TOON_LEVELS)
	sm.set_shader_parameter("hue_lock", HUE_LOCK)
	sm.set_shader_parameter("ambient", AMBIENT)
	sm.set_shader_parameter("sun", SUN)
	sm.set_shader_parameter("light_dir", LIGHT_DIR.normalized())
	_materials.append(sm)
	return sm


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
	yaw = turn_towards(yaw, target_yaw, deg_to_rad(TURN_DEG_S) * dt)
	var before := phase
	phase = advance_phase(phase, speed_m_s, dt, _morph.stride_scale if _morph != null else 1.0)
	idle_t = idle_t + dt if speed_m_s < 0.05 else 0.0
	_pose()
	return contacts_between(before, phase, speed_m_s) if speed_m_s >= 0.05 else 0


## Faces this way at once (no turn).
func face(y: float) -> void:
	yaw = y
	target_yaw = y
	_pose()


## Puts the feet at canvas_pos, snapped to whole screen pixels: parent_pos is where the parent node is,
## camera_pos the 2D camera's position (at zoom 1 a whole number of pixels from the screen).
func place(canvas_pos: Vector2, parent_pos := Vector2.ZERO, camera_pos := Vector2.ZERO) -> void:
	position = camera_pos + (canvas_pos - camera_pos).round() - parent_pos
	if _ghost != null and is_inside_tree():
		var p := get_parent()
		_ghost.global_position = p.get_global_transform() * position if p is Node2D else position


func _pose() -> void:
	if _tree == null:
		return
	_pivot.rotation.y = yaw
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
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
