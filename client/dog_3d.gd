## The dog drawn as one of the three cyborg Tripo models (assets/models/dog_tripo_*.glb, rigs repaired by
## a Blender script, see ASSETS.toml), rendered as pixel art like the player (client/model_3d.gd), at the
## size of the dog sprite. Clips: walk, trot and gallop (one cycle each, made by one parametric script for
## the three models, in place), a scripted sit, and the rest pose. The models have no lying, peeing,
## digging or waiting pose yet: those server states show the closest clip instead, marked "provisional"
## in STILL and WAIT, until a pose of their own is made.
## Display only: the dog's behaviour stays on the server (server/dog.gd).
class_name Dog3D
extends Model3D

## The 3D dogs: DogSkins id, model, key in GAITS_JSON. A: mechanical legs and spine, grey-brown coat;
## B: armoured skull, camera eye, cables; C: a combat dog, mostly machine.
const SKINS := [
	{"id": "cyborg_a", "model": "res://assets/models/dog_tripo_a.glb", "key": "a"},
	{"id": "cyborg_b", "model": "res://assets/models/dog_tripo_b.glb", "key": "b"},
	{"id": "cyborg_c", "model": "res://assets/models/dog_tripo_c.glb", "key": "c"},
]
## Each gait clip's stride S (metres the body goes per cycle, a planted paw going back at S per cycle),
## clip length, duty factor and paw offsets, and the model's leg length: the extras the script wrote into
## each clip of the GLB, copied here because Godot's glTF import drops animation extras.
const GAITS_JSON := "res://assets/models/dog_tripo_gaits.json"
const GAITS: Array[String] = ["walk", "trot", "gallop"]
## Froude numbers (v² / (g × leg length)) where the dog changes gait: dogs and other mammals go from walk
## to trot near 0.5 and from trot to gallop near 2.5 (Alexander and Jayes 1983, order of magnitude). The
## same for every skin; the speeds follow each model's legs.
const FROUDE_TROT := 0.5
const FROUDE_GALLOP := 2.5
const GRAVITY := 9.81
## Going down a gait waits until the speed is below this share of the speed it goes up at.
const HYSTERESIS := 0.85
## Cross-fade between two gaits, and between standing and moving (s).
const BLEND_S := 0.15
## Speed used to choose the gait, smoothed over about this long (s).
const SPEED_TAU_S := 0.15
## Faster than this (m/s), a drawn movement is a jump (snap to the server), not a step.
const JUMP_M_S := 20.0
## Standing only after this long without moving (s).
const STOP_S := 0.12
## What each server state shows when the dog stands still, and whether that is a stand-in.
## Walk "frozen" at a phase of the clip (0..1): the hind left paw up at 0.825, the front left at 0.075.
const STILL := {
	"sit": {"clip": "sit", "provisional": false},
	"sleep": {"clip": "sit", "provisional": true},  # lying down / asleep: no lying pose yet
	"pee": {"clip": "walk", "at": 0.825, "provisional": true},  # a hind paw up
	"to_pee": {"clip": "walk", "at": 0.825, "provisional": true},
	"dig": {"clip": "walk", "at": 0.075, "provisional": true},  # a front paw up
}
## Any other state standing still (idle, follow, sniff, fetch, hunt): the rest pose.
const WAIT := {"clip": "idle", "provisional": true}
const DOG_VIEW := Vector2i(112, 96)
const DOG_FOOT_PX := 32

static var _scenes := {}
static var _gaits := {}

var skin := 0  ## index in SKINS
var phase := 0.0  ## master phase of the gait cycle, 0..1 (0: the hind left paw lands, in every gait)
var pose := "idle"  ## server state
var moving := false
var speed_m_s := 0.0  ## smoothed ground speed
var gait := "walk"  ## gait chosen for the speed
var forced := ""  ## debug (F10, client/world_view.gd): a gait shown whatever the speed, still in step with the ground
var weights := {"walk": 1.0, "trot": 0.0, "gallop": 0.0}  ## cross-fade between gaits
var move_weight := 0.0  ## cross-fade from standing (0) to moving (1)
var still_s := 1.0  ## time since the drawn dog last moved (s)
var anim: AnimationPlayer
var _tree: AnimationTree
var _still: AnimationNodeAnimation


## Index in SKINS of a DogSkins id, -1 for the drawn dog (DogSkins.DEFAULT) or an unknown id.
static func skin_index(id: String) -> int:
	for i in SKINS.size():
		if SKINS[i]["id"] == id:
			return i
	return -1


## The gaits of a skin: {"leg_m", "gaits": {gait: {"stride_m", "duration_s", "duty", "offsets"}}}.
static func skin_gaits(skin_index: int) -> Dictionary:
	if _gaits.is_empty():
		_gaits = JSON.parse_string(FileAccess.get_file_as_string(GAITS_JSON))
	return _gaits["skins"][SKINS[skin_index]["key"]]


static func stride_of(skin_index: int, g: String) -> float:
	return float(skin_gaits(skin_index)["gaits"][g]["stride_m"])


static func clip_s(skin_index: int, g: String) -> float:
	return float(skin_gaits(skin_index)["gaits"][g]["duration_s"])


## Playback speed of a clip of stride S and length T at a ground speed v: v / (S / T). At 1 the clip's own
## speed; a planted paw then goes back exactly as fast as the ground.
static func speed_scale(v: float, stride_m: float, clip_len_s: float) -> float:
	return v / (stride_m / clip_len_s)


## Speeds (m/s) where a dog with legs this long starts to trot (x) and to gallop (y).
static func gait_speeds(leg_m: float) -> Vector2:
	return Vector2(sqrt(FROUDE_TROT * GRAVITY * leg_m), sqrt(FROUDE_GALLOP * GRAVITY * leg_m))


## The gait at a speed, from the current one: up at the gait speeds, down below HYSTERESIS of them.
static func choose_gait(current: String, v: float, leg_m: float) -> String:
	var up := gait_speeds(leg_m)
	var ups := [up.x, up.y]
	var i := GAITS.find(current)
	if i < 2 and v >= ups[i]:
		return choose_gait(GAITS[i + 1], v, leg_m)
	if i > 0 and v < ups[i - 1] * HYSTERESIS:
		return choose_gait(GAITS[i - 1], v, leg_m)
	return current


## Weights after dt seconds of a linear cross-fade towards `target` over BLEND_S (summing to 1).
static func blend_towards(w: Dictionary, target: String, dt: float) -> Dictionary:
	var out := {}
	var sum := 0.0
	for g in GAITS:
		out[g] = move_toward(float(w[g]), 1.0 if g == target else 0.0, dt / BLEND_S)
		sum += out[g]
	if sum <= 0.0:
		out[target] = 1.0
		return out
	for g in GAITS:
		out[g] /= sum
	return out


## Stride (m per cycle) of the blended gaits.
static func blended_stride(skin_index: int, w: Dictionary) -> float:
	var s := 0.0
	for g in GAITS:
		s += float(w[g]) * stride_of(skin_index, g)
	return s


## Master phase after dt seconds at ground speed v with a cycle of this stride: each clip's time goes at
## speed_scale, so the phase goes at v / S cycles per second.
static func advance(p: float, v: float, dt: float, stride_m: float) -> float:
	return fposmod(p + v / stride_m * dt, 1.0)


## What the dog shows: clip, time fraction in it, and whether it is a stand-in pose.
static func shown(state: String, is_moving: bool, moving_gait: String, master_phase: float) -> Dictionary:
	if is_moving:
		return {"clip": moving_gait, "at": master_phase, "provisional": false}
	var s: Dictionary = STILL.get(state, WAIT)
	return {"clip": s["clip"], "at": float(s.get("at", 0.0)), "provisional": s["provisional"]}


func _init(skin_index: int) -> void:
	super()
	skin = skin_index
	view_size = DOG_VIEW
	foot_px = DOG_FOOT_PX
	shadow_size = Vector2(34.0, 12.0)


func _build_model() -> void:
	var path: String = SKINS[skin]["model"]
	if not _scenes.has(path):
		_scenes[path] = load(path)
	_model = (_scenes[path] as PackedScene).instantiate()
	_pivot.add_child(_model)
	_matte(_model)
	anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_tree = _make_tree()
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(anim)
	_tree.active = true


## The still pose and each gait, each through a TimeSeek set every update: (walk + trot) + gallop, then
## still + that.
func _make_tree() -> AnimationTree:
	var bt := AnimationNodeBlendTree.new()
	_still = AnimationNodeAnimation.new()
	_still.animation = "idle"
	bt.add_node("still", _still)
	bt.add_node("seek_still", AnimationNodeTimeSeek.new())
	bt.connect_node("seek_still", 0, "still")
	for g in GAITS:
		var a := AnimationNodeAnimation.new()
		a.animation = g
		bt.add_node(g, a)
		bt.add_node("seek_" + g, AnimationNodeTimeSeek.new())
		bt.connect_node("seek_" + g, 0, g)
	bt.add_node("walk_trot", AnimationNodeBlend2.new())
	bt.connect_node("walk_trot", 0, "seek_walk")
	bt.connect_node("walk_trot", 1, "seek_trot")
	bt.add_node("run", AnimationNodeBlend2.new())
	bt.connect_node("run", 0, "walk_trot")
	bt.connect_node("run", 1, "seek_gallop")
	bt.add_node("move", AnimationNodeBlend2.new())
	bt.connect_node("move", 0, "seek_still")
	bt.connect_node("move", 1, "run")
	bt.connect_node("output", 0, "move")
	var tree := AnimationTree.new()
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return tree


## Phase after the body went dist_m forwards with a cycle of this stride: the paws keep pace with the
## distance actually drawn, so a planted paw stays put even when the drawn movement comes in jerks.
static func advance_by(p: float, dist_m: float, stride_m: float) -> float:
	return fposmod(p + dist_m / stride_m, 1.0)


## One frame: the drawn movement in cells, its duration, the server state. Turns towards the movement.
## A jump (the drawn dog snapping to the server, faster than JUMP_M_S) moves neither phase nor speed.
## The dog counts as standing only after STOP_S without moving: the drawn movement of a creature comes
## in steps between snapshots, with frames that do not move.
func step(cell_delta: Vector2, dt: float, state: String) -> void:
	pose = state
	if dt <= 0.0:
		return
	var dist_m := cell_delta.length() * cell_m
	var jump := dist_m / dt > JUMP_M_S
	if jump:
		dist_m = 0.0
	still_s = still_s + dt if dist_m < 0.0005 * cell_m else 0.0
	moving = still_s < STOP_S
	speed_m_s += (dist_m / dt - speed_m_s) * (1.0 - exp(-dt / SPEED_TAU_S))
	gait = choose_gait(gait, speed_m_s, float(skin_gaits(skin)["leg_m"]))
	weights = blend_towards(weights, forced if forced != "" else gait, dt)
	move_weight = move_toward(move_weight, 1.0 if moving else 0.0, dt / BLEND_S)
	if dist_m > 0.0:
		target_yaw = yaw_of(cell_delta)
		phase = advance_by(phase, dist_m, blended_stride(skin, weights))
	turn(dt)
	_pose()


## The gait shown now (the heaviest in the cross-fade).
func shown_gait() -> String:
	var best: String = GAITS[0]
	for g in GAITS:
		if weights[g] > weights[best]:
			best = g
	return best


func _animate() -> void:
	if _tree == null:
		return
	var s := shown(pose, false, "", 0.0)
	if _still.animation != s["clip"]:
		_still.animation = s["clip"]
	var still_len := anim.get_animation(s["clip"]).length
	_tree.set("parameters/seek_still/seek_request", minf(float(s["at"]) * still_len, still_len - 0.0001))
	for g in GAITS:
		var t := clip_s(skin, g)
		_tree.set("parameters/seek_%s/seek_request" % g, minf(phase * t, t - 0.0001))
	var wt: float = weights["walk"] + weights["trot"]
	_tree.set("parameters/walk_trot/blend_amount", weights["trot"] / wt if wt > 0.0 else 1.0)
	_tree.set("parameters/run/blend_amount", weights["gallop"])
	_tree.set("parameters/move/blend_amount", move_weight)
	_tree.advance(0.0)
