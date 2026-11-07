extends TestCase

## Skinned parts stay over what they cover, on every body shape and in motion (client/character_rig.gd,
## art/character/parts.py): the skin under a garment, and a garment under another (a t-shirt under the
## jacket), never come out through it. A garment without a body shape's shape key, or with a wrong one, lets
## the body come through.
## Method: at rest, each vertex of the outer layer is tied to the point of the inner layer straight under
## it (a ray in along its normal, at most RAY_M deep, onto a triangle facing the same way: a triangle and the
## point's barycentric coordinates), when it sits at about the layer's usual height over it (folds, where
## the ray lands elsewhere, are left out). Both layers are skinned on the CPU (shape keys and the body
## shape's bones included) and the outer vertex counts as through when it is more than MARGIN_M under its
## point, along the inner layer's normal there. The skin a garment hides is never drawn, so it is checked
## in the rest pose of each body shape (the shape keys fit); two layers that are both drawn (the t-shirt
## under the jacket) are checked in every sampled pose of the four clips too.

const Pose := preload("res://tests/character_pose.gd")
static var _tied := {}  ## layer -> ties, the same for every body shape (made on the base shape at rest)
const SAMPLES := 3  ## poses per clip
const RAY_M := 0.035
const MARGIN_M := 0.004
const CELL_M := 0.035
const STEP := 2  ## every other outer vertex
## [inner, outer]: "body_<region>" for the skin, otherwise a part id.
const LAYERS := [
	["body_torso", "top_tshirt"], ["body_arms_upper", "top_tshirt"],
	["top_tshirt", "jacket_field"], ["body_arms_lower", "jacket_field"],
	["body_hips", "bottom_jeans"], ["body_legs_upper", "bottom_jeans"], ["body_legs_lower", "bottom_jeans"],
	["body_feet", "feet_boots"],
]
## A tie counts when its ray is between these fractions of the layer's median height over the inner one.
const HEIGHT_BAND := Vector2(0.6, 1.4)
## A tie counts when the inner layer there faces the same way as the outer vertex (cosine): folds do not.
const FACING := 0.9


static func _mesh(root: Node, sk: Skeleton3D, name: String) -> MeshInstance3D:
	if name.begins_with("body_"):
		return sk.get_node(name)
	return Pose.part(root, name)


## {outer vertex: [triangle start in "triangles", barycentric Vector3]} for the outer vertices over the
## inner layer, at rest.
static func ties(inner: Dictionary, outer: Dictionary) -> Dictionary:
	var ip: PackedVector3Array = inner["points"]
	var it: PackedInt32Array = inner["triangles"]
	var grid := {}
	for t in range(0, it.size(), 3):
		var c := Vector3i(((ip[it[t]] + ip[it[t + 1]] + ip[it[t + 2]]) / 3.0 / CELL_M).floor())
		if not grid.has(c):
			grid[c] = []
		grid[c].append(t)
	var out := {}
	var op: PackedVector3Array = outer["points"]
	var on: PackedVector3Array = outer["normals"]
	var height := {}
	for i in range(0, op.size(), STEP):
		var c := Vector3i((op[i] / CELL_M).floor())
		var best := RAY_M
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for t in grid.get(c + Vector3i(dx, dy, dz), []):
						var a := ip[it[t]]
						var b := ip[it[t + 1]]
						var d := ip[it[t + 2]]
						var hit: Variant = Geometry3D.ray_intersects_triangle(op[i], -on[i], a, b, d)
						var tn: Vector3 = inner["normals"][it[t]] + inner["normals"][it[t + 1]] + inner["normals"][it[t + 2]]
						if hit == null or tn.normalized().dot(on[i]) < FACING:
							continue
						if op[i].distance_to(hit) < best:
							best = op[i].distance_to(hit)
							out[i] = [t, Geometry3D.get_triangle_barycentric_coords(hit, a, b, d)]
							height[i] = best
	if height.is_empty():
		return out
	var hs: Array = height.values()
	hs.sort()
	var median: float = hs[hs.size() / 2]
	for i in height:
		if height[i] < HEIGHT_BAND.x * median or height[i] > HEIGHT_BAND.y * median:
			out.erase(i)
	return out


## {"[inner, outer]": worst count of outer vertices under the inner layer over the poses, "tied": counts}.
static func measure(look: Array) -> Dictionary:
	var root := CharacterRig.build(look)
	var sk := Pose.skeleton(root)
	var morph := CharacterMorph.new(sk, root.get_meta("morph"))
	sk.reset_bone_poses()
	if _tied.is_empty():
		for layer in LAYERS:
			var rest := []
			for name in layer:
				var mi := _mesh(root, sk, name)
				var keep := []
				for k in mi.get_blend_shape_count():  # tied on the base shape, the one the parts are modelled on
					keep.append(mi.get_blend_shape_value(k))
					mi.set_blend_shape_value(k, 0.0)
				rest.append(Pose.skinned(mi, sk))
				for k in keep.size():
					mi.set_blend_shape_value(k, keep[k])
			_tied[layer] = ties(rest[0], rest[1])
	var tied := _tied
	var worst := {}
	for pose in [null] + Pose.poses(root, SAMPLES):
		if pose == null:  # the rest pose of this body shape
			sk.reset_bone_poses()
			morph.apply(sk)
		else:
			Pose.pose_at(sk, pose[0], pose[1], morph)
		var now := {}
		for layer in LAYERS:
			if pose != null and layer[0].begins_with("body_"):
				continue  # hidden skin: the rest pose only
			for name in layer:
				if not now.has(name):
					now[name] = Pose.skinned(_mesh(root, sk, name), sk)
			var inner: Dictionary = now[layer[0]]
			var outer: PackedVector3Array = now[layer[1]]["points"]
			var it: PackedInt32Array = inner["triangles"]
			var through := 0
			var ts: Dictionary = tied[layer]
			for i in ts:
				var t: int = ts[i][0]
				var w: Vector3 = ts[i][1]
				var p: Vector3 = w.x * inner["points"][it[t]] + w.y * inner["points"][it[t + 1]] + w.z * inner["points"][it[t + 2]]
				var n: Vector3 = (w.x * inner["normals"][it[t]] + w.y * inner["normals"][it[t + 1]] + w.z * inner["normals"][it[t + 2]]).normalized()
				if (outer[i] - p).dot(n) < -MARGIN_M:
					through += 1
			worst[str(layer)] = maxi(worst.get(str(layer), 0), through)
	root.free()
	worst["tied"] = tied.values().map(func(d): return d.size())
	return worst


func test_garments_stay_over_what_they_cover_on_every_body() -> void:
	for body in CharacterParts.parts_for("body"):
		var m := measure(Pose.look([[body, 0], ["top_tshirt", 0], ["jacket_field", 0], ["bottom_jeans", 0], ["feet_boots", 0]]))
		for layer in LAYERS:
			assert_eq(m[str(layer)], 0, "%s: %s comes through %s (worst pose)" % [body, layer[0], layer[1]])
		for n in m["tied"]:
			assert_true(n > 20, "%s: layers tied %s" % [body, m["tied"]])
