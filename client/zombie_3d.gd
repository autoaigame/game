## A zombie drawn as a 3D model rendered as pixel art (client/model_3d.gd), from assets/models/zombie.glb
## (made from scratch by art/models/zombie.py). Its clips: idle and walk blended by ground speed, the walk
## in step with the ground; attack and death played once over them, faded in and out.
## Display only: nothing here decides a position, a hit or a death (docs/invariants.md, rule 1).
class_name Zombie3D
extends Model3D

const MODEL := "res://assets/models/zombie.glb"
const CLIPS_JSON := "res://assets/models/zombie_clips.json"
## Wider and with more room below the feet than the player's: arms reach forward, and the death clip
## lies down towards the camera.
const ZOMBIE_VIEW := Vector2i(176, 176)
const ZOMBIE_FOOT_PX := 64
## How long attack and death take to blend in (and attack to blend out), seconds.
const FADE_S := 0.12
## Speed shown is smoothed over about this long (s).
const SPEED_TAU_S := 0.2

static var _clips := {}
static var _scene: PackedScene

var phase := 0.0  ## walk cycle, 0..1, 0 = the left foot lands
var speed_m_s := 0.0  ## smoothed ground speed
var idle_t := 0.0
var attack_t := -1.0  ## seconds into the attack, -1 when not attacking
var dead_t := -1.0  ## seconds since death, -1 while alive
var _tree: AnimationTree
var _lengths := {}


static func clips() -> Dictionary:
	if _clips.is_empty():
		_clips = JSON.parse_string(FileAccess.get_file_as_string(CLIPS_JSON))
	return _clips


static func _clip(name: String) -> Dictionary:
	return clips()["clips"][name]


## Weight of the walk over idle at a ground speed: full at the walk's own speed.
static func walk_weight(v: float) -> float:
	return clampf(v / float(_clip("walk")["ground_speed_m_s"]), 0.0, 1.0)


## Walk phase after dt seconds at a ground speed: one cycle per stride, so planted feet keep still.
static func advance_phase(p: float, v: float, dt: float) -> float:
	return fposmod(p + v / float(_clip("walk")["stride_m"]) * dt, 1.0)


## Weight of a clip played once, t seconds in (-1: not playing): fades in over FADE_S, then out over the
## last FADE_S unless it holds its last pose (death).
static func action_weight(t: float, duration: float, hold: bool) -> float:
	if t < 0.0 or (not hold and t >= duration):
		return 0.0
	var w := clampf(t / FADE_S, 0.0, 1.0)
	if not hold:
		w = minf(w, clampf((duration - t) / FADE_S, 0.0, 1.0))
	return w


func _init() -> void:
	super()
	view_size = ZOMBIE_VIEW
	foot_px = ZOMBIE_FOOT_PX


func attack() -> void:
	if dead_t < 0.0:
		attack_t = 0.0


func die() -> void:
	if dead_t < 0.0:
		dead_t = 0.0
		attack_t = -1.0


func is_attacking() -> bool:
	return attack_t >= 0.0


func is_dead() -> bool:
	return dead_t >= 0.0


## Feeds one frame: the drawn movement this frame in cells and its duration. Updates speed, phase, facing
## and the clip times. Returns true on the frame the attack's blow lands.
func step(cell_delta: Vector2, dt: float) -> bool:
	if dt <= 0.0:
		return false
	if is_dead():
		cell_delta = Vector2.ZERO
		speed_m_s = 0.0
		dead_t += dt
	var v := cell_delta.length() * cell_m / dt
	if not is_dead():
		speed_m_s += (v - speed_m_s) * (1.0 - exp(-dt / SPEED_TAU_S))
		if speed_m_s < 0.02 and v == 0.0:
			speed_m_s = 0.0
	if cell_delta.length() > 1e-5:
		target_yaw = yaw_of(cell_delta)
	turn(dt)
	phase = advance_phase(phase, speed_m_s, dt)
	idle_t += dt
	var hit := false
	if is_attacking():
		var hit_s := float(_clip("attack")["hit_s"])
		hit = attack_t < hit_s and attack_t + dt >= hit_s
		attack_t += dt
		if attack_t >= float(_clip("attack")["duration_s"]):
			attack_t = -1.0
	_pose()
	return hit


func _build_model() -> void:
	if _scene == null:
		_scene = load(MODEL)
	_model = _scene.instantiate()
	_pivot.add_child(_model)
	_matte(_model)
	var player: AnimationPlayer = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for c in ["idle", "walk", "attack", "death"]:
		_lengths[c] = player.get_animation(c).length
	_tree = _make_tree()
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.active = true


## Each clip through a TimeSeek set every update: (idle + walk), then attack over that, then death.
func _make_tree() -> AnimationTree:
	var bt := AnimationNodeBlendTree.new()
	var x := 0
	for c in ["idle", "walk", "attack", "death"]:
		var a := AnimationNodeAnimation.new()
		a.animation = c
		bt.add_node(c, a, Vector2(x, 0))
		bt.add_node("seek_" + c, AnimationNodeTimeSeek.new(), Vector2(x, 100))
		bt.connect_node("seek_" + c, 0, c)
		x += 200
	for blend in [["move", "seek_idle", "seek_walk"], ["act", "move", "seek_attack"], ["die", "act", "seek_death"]]:
		bt.add_node(blend[0], AnimationNodeBlend2.new())
		bt.connect_node(blend[0], 0, blend[1])
		bt.connect_node(blend[0], 1, blend[2])
	bt.connect_node("output", 0, "die")
	var tree := AnimationTree.new()
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return tree


func _animate() -> void:
	if _tree == null:
		return
	var end := func(c: String) -> float: return _lengths[c] - 0.0001
	_tree.set("parameters/move/blend_amount", walk_weight(speed_m_s))
	_tree.set("parameters/act/blend_amount", action_weight(attack_t, _lengths["attack"], false))
	_tree.set("parameters/die/blend_amount", action_weight(dead_t, _lengths["death"], true))
	_tree.set("parameters/seek_idle/seek_request", fposmod(idle_t, _lengths["idle"]))
	_tree.set("parameters/seek_walk/seek_request", minf(phase * _lengths["walk"], end.call("walk")))
	_tree.set("parameters/seek_attack/seek_request", clampf(attack_t, 0.0, end.call("attack")))
	_tree.set("parameters/seek_death/seek_request", clampf(dead_t, 0.0, end.call("death")))
	_tree.advance(0.0)
