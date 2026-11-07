## Builds a 3D character from a look (CharacterParts). The body part's glb brings the skeleton, the
## animations and one skin mesh per region; regions some part hides are turned off. Skinned parts
## (clothes) move their meshes onto the body's Skeleton3D: their Skin binds by bone name, so any body with
## the same bone names fits. Rigid parts (hats, hair, beards, bags) go on a BoneAttachment3D of their
## bone, offset so that in the rest pose they sit where they were modelled (bone head + offset in model
## axes). The body part's shape (morph) turns on the shape key morph_<id> of the body and of every skinned
## part; the bones are changed by CharacterMorph once the model animates (metadata "morph" on the root).
## Texture parts (faces, flat beards) go on the head as metadata ("face", "beard": {texture, ramp}) for the
## renderer. Each part node carries the metadata part_id and glb; each tinted material the ramp name
## (metadata "ramp"). Display only.
class_name CharacterRig
extends RefCounted

static var _scenes := {}  ## glb path -> PackedScene
static var _tints := {}  ## [source material, ramp] -> tinted copy, shared by every character


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## A new model for a valid look, not yet in the tree. Its AnimationPlayer comes from the body glb.
static func build(look: Array) -> Node3D:
	var r := CharacterParts.resolve(look)
	var parts: Array = r["parts"]
	var body_i := parts.find_custom(func(e): return e["kind"] == "body")
	if body_i < 0:
		push_error("CharacterRig: look without a body")
		return Node3D.new()
	var body: Dictionary = parts[body_i]
	var root: Node3D = scene(body["glb"]).instantiate()
	_mark(root, body)
	root.set_meta("morph", body["morph"])
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	for mi in sk.get_children():
		if mi is MeshInstance3D and String(mi.name).begins_with("body_"):
			mi.visible = not r["hidden"].has(String(mi.name).trim_prefix("body_"))
			_tint(mi, body, true)
	for e in parts:
		if e["kind"] == "body":
			continue
		if e["kind"] == "texture":
			var head: Node = sk.get_node_or_null("body_head")
			if head != null:
				head.set_meta(e["slot"], {"texture": e["texture"], "ramp": e["ramp"]})
			continue
		var inst: Node3D = scene(e["glb"]).instantiate()
		if e["kind"] == "rigid":
			var idx := sk.find_bone(e["bone"])
			if idx < 0:
				push_warning("CharacterRig: %s hangs from %s, not in this body" % [e["id"], e["bone"]])
				inst.free()
				continue
			var att := BoneAttachment3D.new()
			att.name = "part_" + e["id"]
			att.bone_name = e["bone"]
			_mark(att, e)
			sk.add_child(att)
			att.add_child(inst)
			inst.transform = Transform3D(sk.get_bone_global_rest(idx).basis.inverse(), Vector3.ZERO)
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				_tint(mi, e)
		else:
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				mi.owner = null
				mi.get_parent().remove_child(mi)
				mi.name = "part_" + e["id"]
				sk.add_child(mi)
				mi.skeleton = NodePath("..")
				_mark(mi, e)
				_tint(mi, e)
			inst.free()
	if body["morph"] != CharacterMorph.BASE:
		for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
			var k := mi.find_blend_shape_by_name("morph_" + body["morph"])
			if k >= 0:
				mi.set_blend_shape_value(k, 1.0)
	return root


static func _mark(n: Node, e: Dictionary) -> void:
	n.set_meta("part_id", e["id"])
	n.set_meta("glb", e["glb"])


## The chosen ramp as a surface override on every surface whose material is named main* (all of them
## with `all`: the body's skin regions): its colour, and the ramp name for the renderer.
static func _tint(mi: MeshInstance3D, e: Dictionary, all := false) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m is BaseMaterial3D and (all or m.resource_name.begins_with("main")):
			var key := [m, e["ramp"]]
			if not _tints.has(key):
				var t: BaseMaterial3D = m.duplicate()
				t.albedo_color = e["color"]
				t.set_meta("ramp", e["ramp"])
				_tints[key] = t
			mi.set_surface_override_material(s, _tints[key])
