extends TestCase

## Hats must cover the skull and the hair they leave drawn (client/character_rig.gd, data/character/parts):
## nothing of the head pokes through a hat, in any pose of the clips, on every body shape.
## Method: in the hat's own mesh space, a ray from the middle of the hat's rim towards each vertex of the
## skin of the head (skinned on the CPU, shape key included) and of the hair drawn with the hat; a vertex
## pokes through when the ray meets the hat before reaching it (MARGIN_M of slack, the hat is a single
## surface). Vertices whose ray misses the hat are below the rim and not counted.

const Pose := preload("res://tests/character_pose.gd")
const MARGIN_M := 0.004
const SAMPLES := 4  ## poses per clip


static func _triangles(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			out.append_array(v)
		else:
			for i in idx:
				out.append(v[i])
	return out


## Nearest hit distance of a ray on a triangle soup, or INF.
static func _ray_hit(from: Vector3, dir: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	for t in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, tris[t], tris[t + 1], tris[t + 2])
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best


## How many of `points` (hat mesh space) poke through the hat whose triangles are `tris`.
static func poking(points: PackedVector3Array, tris: PackedVector3Array) -> int:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in tris:
		lo = lo.min(p)
		hi = hi.max(p)
	var centre := Vector3((lo.x + hi.x) / 2.0, lo.y, (lo.z + hi.z) / 2.0)
	var n := 0
	for p in points:
		var d := p - centre
		if d.y <= 0.0:
			continue  # below the rim
		var t := _ray_hit(centre, d.normalized(), tris)
		if t < INF and d.length() > t - MARGIN_M:
			n += 1
	return n


## {"skull": worst count over the poses, "hair": worst count, "poses": n} for a look with `hat`.
static func measure(look: Array, hat: String) -> Dictionary:
	var root := CharacterRig.build(look)
	var sk := Pose.skeleton(root)
	var morph := CharacterMorph.new(sk, root.get_meta("morph"))
	var att: BoneAttachment3D = Pose.part(root, hat)
	var hat_mi: MeshInstance3D = att.find_children("*", "MeshInstance3D", true, false)[0]
	var tris := _triangles(hat_mi)
	var hair_nodes: Array = []
	for e in look:
		if CharacterParts.part(e["id"])["slot"] == "hair":
			var h := Pose.part(root, e["id"])
			if h != null:
				hair_nodes.append(h)
	var worst := {"skull": 0, "hair": 0, "poses": 0}
	for pose in Pose.poses(root, SAMPLES):
		Pose.pose_at(sk, pose[0], pose[1], morph)
		var to_hat := Pose.rigid_to_skeleton(att, hat_mi, sk).affine_inverse()
		var skull := PackedVector3Array()
		for r in ["body_head", "body_scalp", "body_nape"]:  # measured even though hats hide some: the fit must hold alone
			if sk.has_node(r):
				skull.append_array(Pose.skinned(sk.get_node(r), sk)["points"])
		for k in skull.size():
			skull[k] = to_hat * skull[k]
		worst["skull"] = maxi(worst["skull"], poking(skull, tris))
		var hair := PackedVector3Array()
		for h: BoneAttachment3D in hair_nodes:
			for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
				var xf := to_hat * Pose.rigid_to_skeleton(h, mi, sk)
				for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					hair.append(xf * v)
		worst["hair"] = maxi(worst["hair"], poking(hair, tris))
		worst["poses"] += 1
	root.free()
	return worst


func _check(body: String, hair: String, hat: String) -> void:
	var look := Pose.look([[body, 0], [hat, 0]] + ([[hair, 0]] if hair != "" else []))
	var m := measure(look, hat)
	assert_eq(m["skull"], 0, "%s, %s: skull vertices through the hat (worst pose of %d)" % [body, hat, m["poses"]])
	assert_eq(m["hair"], 0, "%s, %s with %s: hair vertices through the hat" % [body, hat, hair])


func test_every_hat_covers_the_bare_skull_on_every_body() -> void:
	for body in CharacterParts.parts_for("body"):
		for hat in CharacterParts.parts_for("hat"):
			_check(body, "", hat)


func test_every_hat_covers_the_hair_it_leaves_drawn() -> void:
	for body in CharacterParts.parts_for("body"):
		for hat in CharacterParts.parts_for("hat"):
			for hair in CharacterParts.parts_for("hair"):
				_check(body, hair, hat)
