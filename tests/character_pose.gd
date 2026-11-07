## Helpers for the character tests: put a built character (CharacterRig) in a pose of a clip with its body
## shape, and read where its meshes are, skinned on the CPU (shape keys included). Not a test file.
extends RefCounted

const CLIPS := ["idle", "walk", "jog", "sprint"]


static func skeleton(root: Node) -> Skeleton3D:
	return root.find_children("*", "Skeleton3D", true, false)[0]


## The node of a part (metadata part_id), or null.
static func part(root: Node, id: String) -> Node3D:
	for n in [root] + root.find_children("*", "", true, false):
		if n.get_meta("part_id", "") == id:
			return n
	return null


## Puts the skeleton in the pose of `anim` at `t` (bone tracks only, no AnimationPlayer needed), then the
## body shape's bone changes and the raised head, like Character3D does after each animation update.
static func pose_at(sk: Skeleton3D, anim: Animation, t: float, morph: CharacterMorph) -> void:
	sk.reset_bone_poses()
	for k in anim.get_track_count():
		var bone := sk.find_bone(String(anim.track_get_path(k).get_concatenated_subnames()))
		if bone < 0:
			continue
		match anim.track_get_type(k):
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, anim.position_track_interpolate(k, t))
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(k, t))
			Animation.TYPE_SCALE_3D:
				sk.set_bone_pose_scale(bone, anim.scale_track_interpolate(k, t))
	morph.apply(sk)
	Character3D.lift_head(sk)


## Each bone's skeleton-space transform in the current pose, chained from the local poses. The skeleton's
## own get_bone_global_pose() is a cache refreshed when the skeleton updates in a running scene: read
## between poses set by hand, it would keep giving the first one.
static func globals(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	var done := []
	done.resize(sk.get_bone_count())
	done.fill(false)
	for b in sk.get_bone_count():
		_global(sk, b, out, done)
	return out


static func _global(sk: Skeleton3D, b: int, out: Array[Transform3D], done: Array) -> Transform3D:
	if done[b]:
		return out[b]
	var p := sk.get_bone_parent(b)
	var local := sk.get_bone_pose(b)
	out[b] = local if p < 0 else _global(sk, p, out, done) * local
	done[b] = true
	return out[b]


## Every pose sampled for the checks: [clip, time], `per_clip` evenly spaced times in each clip.
static func poses(root: Node, per_clip: int) -> Array:
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var out := []
	for clip in CLIPS:
		var anim := player.get_animation(clip)
		for i in per_clip:
			out.append([anim, anim.length * i / per_clip])
	return out


## {"points", "normals", "triangles" (vertex indices, 3 per triangle)} of a skinned mesh in skeleton space,
## current pose, with its shape keys.
static func skinned(mi: MeshInstance3D, sk: Skeleton3D) -> Dictionary:
	var g := globals(sk)
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tri := PackedInt32Array()
	var skin := mi.skin
	var bind_to_bone := []
	for b in skin.get_bind_count():
		bind_to_bone.append(sk.find_bone(skin.get_bind_name(b)))
	var mesh: ArrayMesh = mi.mesh
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var first := pts.size()
		for i in arr[Mesh.ARRAY_INDEX]:
			tri.append(first + i)
		var shapes := mesh.surface_get_blend_shape_arrays(s)
		for k in shapes.size():
			var w := mi.get_blend_shape_value(k)
			if w == 0.0:
				continue
			var sv: PackedVector3Array = shapes[k][Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = shapes[k][Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] += w * (sv[i] - verts[i])
				if not sn.is_empty():
					norms[i] = norms[i].lerp(sn[i], w)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for i in verts.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			for k in per:
				var w := weights[i * per + k]
				if w <= 0.0:
					continue
				var bind := bones[i * per + k]
				var xf := g[bind_to_bone[bind]] * skin.get_bind_pose(bind)
				p += w * (xf * verts[i])
				n += w * (xf.basis * norms[i])
			pts.append(mi.transform * p)
			nrm.append((mi.transform.basis * n).normalized())
	return {"points": pts, "normals": nrm, "triangles": tri}


## Transform from a rigid part's MeshInstance3D space to skeleton space, current pose.
static func rigid_to_skeleton(att: BoneAttachment3D, mi: MeshInstance3D, sk: Skeleton3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var n: Node = mi
	while n != att:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	return globals(sk)[sk.find_bone(att.bone_name)] * chain


## A look with `pairs` [[id, colour index], ...]: each part in its colour of that index.
static func look(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		var cs: Array = CharacterParts.part(p[0]).get("colors", ["none"])
		out.append({"id": p[0], "color": cs[p[1]] if p[1] is int and p[1] >= 0 and p[1] < cs.size() else str(p[1])})
	return out
