## A body shape (morphology) on the common skeleton: the base body ("standard") is the rest pose every part
## is modelled on; another shape moves and scales bones of that same skeleton (data/character/morphs.json,
## written by art/character/body.py) while the meshes take the shape key morph_<id> (CharacterRig). Bones
## keep their rest rotations, so every animation and every part works on every shape.
## apply() goes after each animation update: the clips move only the hips and rotate the bones, so the
## other bones' positions and scales are set as they are, the hips' shift is added and the upper arms get
## the shape's extra outward turn. Display only.
class_name CharacterMorph
extends RefCounted

const DATA := "res://data/character/morphs.json"
const BASE := "standard"

static var _data := {}

var id := BASE
## How much longer this shape's stride is than the base's (its legs), so its feet do not slide.
var stride_scale := 1.0
var _pos := {}  ## bone -> pose position
var _scale := {}  ## bone -> pose scale
var _hips := -1
var _hips_shift := Vector3.ZERO
var _turn := {}  ## bone -> rotation put before the animated one


## {id: record} of morphs.json, without the base (which changes nothing).
static func shapes() -> Dictionary:
	if _data.is_empty():
		var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = rec["morphs"] if rec is Dictionary else {}
	return _data


## Every body shape's id, the base first.
static func ids() -> Array[String]:
	var out: Array[String] = [BASE]
	var others: Array = shapes().keys()
	others.sort()
	out.append_array(others)
	return out


static func exists(morph_id: String) -> bool:
	return morph_id == BASE or shapes().has(morph_id)


## The bone changes of `morph_id` for this skeleton (its rest pose is the base's). An unknown id or the
## base changes nothing.
func _init(sk: Skeleton3D, morph_id: String) -> void:
	var m: Dictionary = shapes().get(morph_id, {})
	if m.is_empty():
		return
	id = morph_id
	stride_scale = float(m.get("stride_scale", 1.0))
	var heads: Dictionary = m["heads"]
	var scales: Dictionary = m.get("scales", {})
	var shaped := {}  ## bone -> its skeleton-space transform at rest in this shape
	for b in _parents_first(sk):
		var bname := sk.get_bone_name(b)
		var rest := sk.get_bone_rest(b)
		var h: Array = heads.get(bname, [])
		var head := Vector3(h[0], h[1], h[2]) if h.size() == 3 else sk.get_bone_global_rest(b).origin
		var p := sk.get_bone_parent(b)
		var local_pos := head if p < 0 else (shaped[p] as Transform3D).affine_inverse() * head
		var s := float(scales.get(bname, 1.0))
		var parent: Transform3D = shaped[p] if p >= 0 else Transform3D.IDENTITY
		shaped[b] = parent * Transform3D(rest.basis * Basis.from_scale(Vector3.ONE * s), local_pos)
		if bname == "DEF-hips":
			_hips = b
			_hips_shift = local_pos - rest.origin
		elif not local_pos.is_equal_approx(rest.origin):
			_pos[b] = local_pos
		if s != 1.0:
			_scale[b] = Vector3.ONE * s
	# The upper arms swing a little further out (or in) than the clips, turned around the skeleton's
	# forward axis in the parent's frame: the left arm towards +Y from +X, the right one the other way.
	var deg := float(m.get("arm_out_deg", 0.0))
	for side in ["L", "R"]:
		var b := sk.find_bone("DEF-upper_arm." + side)
		if b < 0 or deg == 0.0:
			continue
		var pb := sk.get_bone_global_rest(sk.get_bone_parent(b)).basis
		var turn := Basis(Vector3(0, 0, 1), deg_to_rad(deg) * (1.0 if side == "L" else -1.0))
		_turn[b] = (pb.inverse() * turn * pb).get_rotation_quaternion()


## After each animation update of `sk`.
func apply(sk: Skeleton3D) -> void:
	for b in _pos:
		sk.set_bone_pose_position(b, _pos[b])
	for b in _scale:
		sk.set_bone_pose_scale(b, _scale[b])
	if _hips >= 0:
		sk.set_bone_pose_position(_hips, sk.get_bone_pose_position(_hips) + _hips_shift)
	for b in _turn:
		sk.set_bone_pose_rotation(b, _turn[b] * sk.get_bone_pose_rotation(b))


static func _parents_first(sk: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	var todo: Array = Array(sk.get_parentless_bones())
	while not todo.is_empty():
		var b: int = todo.pop_front()
		out.append(b)
		todo.append_array(Array(sk.get_bone_children(b)))
	return out
