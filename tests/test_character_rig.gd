extends TestCase

## Building a character from parts (client/character_rig.gd): rigid parts on bone attachments, skinned parts
## on the body's skeleton, hidden regions and parts.


func _look(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		var cs: Array = CharacterParts.part(p[0]).get("colors", ["none"])
		out.append({"id": p[0], "color": cs[p[1]] if p[1] is int and p[1] >= 0 and p[1] < cs.size() else str(p[1])})
	return out


func _skeleton(root: Node) -> Skeleton3D:
	return root.find_children("*", "Skeleton3D", true, false)[0]


func _part_node(root: Node, id: String) -> Node:
	for n in [root] + root.find_children("*", "", true, false):
		if n.get_meta("part_id", "") == id:
			return n
	return null


func test_rigid_parts_hang_from_their_bone() -> void:
	var root := CharacterRig.build(_look([["body_standard", 0], ["hat_cap", 0], ["back_bag", 0]]))
	var sk := _skeleton(root)
	var cap := _part_node(root, "hat_cap")
	assert_true(cap is BoneAttachment3D, "cap on %s" % cap)
	assert_eq(cap.bone_name, "DEF-head")
	assert_eq(cap.get_parent(), sk)
	assert_eq(_part_node(root, "back_bag").bone_name, "DEF-spine.003")
	root.free()


## In the rest pose a rigid part sits where it was modelled: bone head + offset, in model axes.
func test_rigid_part_keeps_its_modelled_place_at_rest() -> void:
	var root := CharacterRig.build(_look([["body_standard", 0], ["hat_cap", 0]]))
	var sk := _skeleton(root)
	var cap: BoneAttachment3D = _part_node(root, "hat_cap")
	var mi: MeshInstance3D = cap.find_children("*", "MeshInstance3D", true, false)[0]
	var head := sk.get_bone_global_rest(sk.find_bone("DEF-head"))
	var to_mesh: Transform3D = head * (cap.get_child(0) as Node3D).transform
	assert_true(to_mesh.basis.is_equal_approx(Basis.IDENTITY), "model axes: %s" % to_mesh.basis)
	assert_true(to_mesh.origin.is_equal_approx(head.origin), "origin at the bone head")
	assert_true(mi != null)
	root.free()


## Skinned parts share the body's skeleton and bind to its bones by name, so any body with the same bone
## names fits, whatever the bone order.
func test_skinned_parts_use_the_body_skeleton_by_bone_name() -> void:
	var root := CharacterRig.build(_look([["body_standard", 0], ["top_tshirt", 0], ["jacket_field", 0], ["bottom_jeans", 0], ["feet_boots", 0]]))
	var sk := _skeleton(root)
	for id in ["top_tshirt", "jacket_field", "bottom_jeans", "feet_boots"]:
		var mi: MeshInstance3D = _part_node(root, id)
		assert_true(mi != null, "%s built" % id)
		assert_eq(mi.get_parent(), sk, "%s under the body skeleton" % id)
		assert_eq(mi.get_node(mi.skeleton), sk)
		assert_true(mi.skin != null and mi.skin.get_bind_count() > 0)
		for b in mi.skin.get_bind_count():
			var bname := mi.skin.get_bind_name(b)
			assert_true(bname != "" and sk.find_bone(bname) >= 0, "%s bind %d: '%s'" % [id, b, bname])
	assert_eq(root.find_children("*", "Skeleton3D", true, false).size(), 1, "the parts' own rigs are dropped")
	root.free()


func test_garments_hide_the_skin_under_them() -> void:
	var root := CharacterRig.build(_look([["body_standard", 0], ["top_tshirt", 0], ["bottom_shorts", 0]]))
	var sk := _skeleton(root)
	assert_false(sk.get_node("body_torso").visible)
	assert_false(sk.get_node("body_hips").visible)
	assert_true(sk.get_node("body_legs_lower").visible, "bare shins under shorts")
	assert_false(sk.get_node("body_arms_upper").visible)
	assert_true(sk.get_node("body_arms_lower").visible, "bare forearms")
	assert_true(sk.get_node("body_head").visible)
	root.free()


func test_hidden_parts_are_not_built_and_alternates_are() -> void:
	var root := CharacterRig.build(_look([["body_standard", 0], ["hair_short", 0], ["hat_cap", 0]]))
	assert_eq(_part_node(root, "hair_short"), null)
	root.free()
	root = CharacterRig.build(_look([["body_standard", 0], ["hair_long", 0], ["hat_cap", 0]]))
	var hair := _part_node(root, "hair_long")
	assert_true(hair != null)
	assert_eq(hair.get_meta("glb"), "res://assets/character/parts/hair_long_under.glb")
	root.free()


## The chosen colour goes on the "main" materials; the others keep theirs.
func test_colour_goes_on_main_materials_only() -> void:
	var root := CharacterRig.build(_look([["body_standard", 2], ["back_bag", 1]]))
	var bag := _part_node(root, "back_bag")
	var mains := 0
	var fixed := 0
	for mi in bag.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: BaseMaterial3D = mi.get_surface_override_material(s)
			if mi.mesh.surface_get_material(s).resource_name.begins_with("main"):
				mains += 1
				assert_true(m.albedo_color.is_equal_approx(CharacterParts.base_colour(CharacterParts.part("back_bag")["colors"][1])))
			else:
				fixed += 1
				assert_true(m == null, "fixed material left alone")
	assert_true(mains >= 1 and fixed >= 1, "bag: %d main, %d fixed surfaces" % [mains, fixed])
	var sk := _skeleton(root)
	var head: MeshInstance3D = sk.get_node("body_head")
	assert_true(head.get_surface_override_material(0).albedo_color.is_equal_approx(CharacterParts.base_colour("skin_dark")))
	root.free()


func test_every_part_of_every_slot_builds() -> void:
	for id in CharacterParts.part_ids():
		var look := CharacterParts.default_look()
		var slot_id: String = CharacterParts.part(id)["slot"]
		look = look.filter(func(e): return CharacterParts.part(e["id"])["slot"] != slot_id)
		look.append({"id": id, "color": CharacterParts.part(id)["colors"][0]})
		var root := CharacterRig.build(look)
		if CharacterParts.part(id)["kind"] == "texture":
			var head: Node = _skeleton(root).get_node("body_head")
			assert_eq(head.get_meta(slot_id, {}).get("texture", ""), CharacterParts.part(id)["texture"], "%s on the head" % id)
		else:
			assert_true(_part_node(root, id) != null, "%s built" % id)
		root.free()


## Under a hat the top of the skull is not drawn at all, so a hat that sits a little off cannot show skin.
func test_hats_hide_the_top_of_the_skull() -> void:
	for hat in CharacterParts.parts_for("hat"):
		var root := CharacterRig.build(_look([["body_standard", 0], [hat, 0]]))
		var sk := _skeleton(root)
		assert_true(sk.has_node("body_scalp"), "the body has a scalp region")
		if sk.has_node("body_scalp"):
			assert_false(sk.get_node("body_scalp").visible, "%s hides the scalp" % hat)
		assert_true(sk.get_node("body_head").visible, "%s leaves the face" % hat)
		root.free()
	var bare := CharacterRig.build(_look([["body_standard", 0]]))
	assert_true(_skeleton(bare).get_node("body_scalp").visible)
	bare.free()
