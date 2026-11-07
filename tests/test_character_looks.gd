extends TestCase

## Faces, flat beards and colours of the 3D character: index textures and ramps (docs/character-parts.md).


## Every face and flat beard is an index texture of the face zone: 24x16, kept exact on import (no
## compression), each texel transparent or a zone 0-2 with a shade -2..2.
func test_texture_parts_are_exact_index_textures() -> void:
	var n := 0
	for id in CharacterParts.part_ids():
		var p := CharacterParts.part(id)
		if p["kind"] != "texture":
			continue
		n += 1
		var img: Image = (load(p["texture"]) as Texture2D).get_image()
		assert_false(img.is_compressed(), id + ": not compressed")
		assert_eq(img.get_size(), Vector2i(int(Character3D.FACE_RECT.z), int(Character3D.FACE_RECT.w)), id)
		img.convert(Image.FORMAT_RGBA8)
		var opaque := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a8 == 0:
					continue
				opaque += 1
				assert_eq(c.a8, 255, "%s (%d, %d): alpha" % [id, x, y])
				assert_true(c.r8 % 64 == 0 and c.r8 / 64 <= 2, "%s (%d, %d): zone %d" % [id, x, y, c.r8])
				assert_true(c.g8 % 50 == 0 and c.g8 / 50 <= 4, "%s (%d, %d): shade %d" % [id, x, y, c.g8])
		assert_true(opaque > 0, id + ": draws something")
	assert_true(n >= 10, "8 faces and 2 flat beards: %d" % n)


## Every face has two eyes at least 2 texels wide (one texel wide drops out on screen at some angles).
func test_faces_have_eyes_two_texels_wide() -> void:
	for id in CharacterParts.parts_for("face"):
		var img: Image = (load(CharacterParts.part(id)["texture"]) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var eye_cols := {}
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a8 == 255 and c.r8 == 128 and c.g8 == 0:
					eye_cols[x] = true
		var left := eye_cols.keys().filter(func(x): return x < 12).size()
		var right := eye_cols.keys().filter(func(x): return x >= 12).size()
		assert_true(left >= 2 and right >= 2, "%s: eyes %d and %d texels wide" % [id, left, right])


## A part's colours are ramps of palette colours, the renderer finds each in the palette, and every
## ramp a part may use has at least the three light bands.
func test_ramps_map_to_palette_indices() -> void:
	var pal := Character3D.palette()
	for name in CharacterParts.ramp_names():
		var idx := Character3D.ramp_indices(name)
		var cs: Array = CharacterParts.ramp(name)["colours"]
		assert_eq(idx.size(), cs.size(), name)
		for i in idx.size():
			assert_eq(pal[idx[i]], cs[i], "%s %d" % [name, i])
		assert_true(cs.size() >= 3, name + ": shade, plain and full light")
		for i in range(1, cs.size()):
			assert_true(cs[i].get_luminance() >= cs[i - 1].get_luminance(), "%s: dark to light" % name)


## The body's skin goes from deep to fair, and hair can be red.
func test_choices_cover_skin_tones_and_red_hair() -> void:
	var skins: Array = CharacterParts.part("body_standard")["colors"]
	assert_true(skins.size() >= 4, "four skin tones: %s" % [skins])
	for id in CharacterParts.parts_for("hair") + CharacterParts.parts_for("face"):
		assert_true("hair_red" in CharacterParts.part(id)["colors"], id + " can be red")


## The face and a flat beard go on the head together, each with its own colour.
func test_face_and_flat_beard_on_the_head() -> void:
	var look := [{"id": "body_standard", "color": "skin_deep"}, {"id": "face_scar", "color": "hair_red"},
			{"id": "beard_stubble", "color": "hair_grey"}, {"id": "top_tshirt", "color": "brick"},
			{"id": "bottom_jeans", "color": "brown"}]
	assert_eq(CharacterParts.validate(look), "")
	var root := CharacterRig.build(look)
	var head: Node = root.find_children("body_head", "MeshInstance3D", true, false)[0]
	assert_eq(head.get_meta("face"), {"texture": "res://assets/character/faces/face_scar.png", "ramp": "hair_red"})
	assert_eq(head.get_meta("beard"), {"texture": "res://assets/character/faces/beard_stubble.png", "ramp": "hair_grey"})
	root.free()


## The face zone fits in the head's texture, and the head is raised over the clips so the face shows from
## the camera's 30 degrees above (Character3D.lift_head).
func test_face_zone_and_raised_head() -> void:
	var r := Character3D.FACE_RECT
	assert_true(r.x >= 0 and r.y >= 0 and r.x + r.z <= Character3D.HEAD_TEXTURE.x and r.y + r.w <= Character3D.HEAD_TEXTURE.y)
	var root := CharacterRig.build(CharacterParts.default_look())
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	sk.reset_bone_poses()
	var b := sk.find_bone("DEF-head")
	var before := sk.get_bone_pose_rotation(b) * Vector3(0, 0, 1)
	Character3D.lift_head(sk)
	var after := sk.get_bone_pose_rotation(b) * Vector3(0, 0, 1)
	var parent := sk.get_bone_global_rest(sk.get_bone_parent(b)).basis
	assert_true((parent * after).y > (parent * before).y, "the face turns up")
	root.free()
