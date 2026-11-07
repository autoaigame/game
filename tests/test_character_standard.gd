extends TestCase

## Every character part's files follow the standard (tests/character_standard.gd, docs/character-parts.md):
## a CC0 ASSETS.toml entry, PNGs without metadata, glbs with one mesh, the right skin and shape keys,
## the slot's triangle budget and palette colours. Then each rule on a broken file, so the checker is
## seen to fail.

const Std := preload("res://tests/character_standard.gd")


## A glb holding only `json` (no binary chunk): enough for the structure checks.
static func _glb(json: Dictionary) -> PackedByteArray:
	var text := JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546c67)  # "glTF"
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + text.size())
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4e4f534a)  # "JSON"
	out.append_array(text)
	return out


## A rigid part of `tris` triangles with one material.
static func _rigid(tris: int, material: Dictionary) -> Dictionary:
	return {"asset": {"version": "2.0"}, "nodes": [{"name": "hat_x", "mesh": 0}],
			"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
			"accessors": [{"count": 3}, {"count": tris * 3}], "materials": [material]}


func test_every_part_follows_the_standard() -> void:
	assert_true(CharacterParts.part_ids().size() >= 20, "parts: %d" % CharacterParts.part_ids().size())
	for id in CharacterParts.part_ids():
		var p := Std.problems(id)
		assert_true(p.is_empty(), "\n".join(p))


func test_every_slot_with_meshes_has_a_triangle_budget() -> void:
	for s in CharacterParts.slots():
		if s["id"] in ["body", "face"]:
			continue
		assert_true(s["triangles"] > 0, "%s: triangles in data/character/slots.json" % s["id"])


func test_assets_entry_needs_cc0_and_an_author() -> void:
	var a := Std.parse_assets('[[asset]]\npath = "assets/a.glb"\nauthor = "x"\nlicense = "CC0-1.0" # ok\n'
			+ '\n[[asset]]\npath = "assets/b.glb"\nauthor = "y"\nlicense = "CC-BY-4.0"\n')
	assert_eq(a["assets/a.glb"]["license"], "CC0-1.0")
	assert_eq(a["assets/b.glb"]["license"], "CC-BY-4.0")
	assert_eq(Std.asset_problem("assets/character/parts/hat_cap.glb"), "")
	assert_true(Std.asset_problem("assets/character/parts/hat_nothing.glb") != "", "no entry")


func test_png_metadata_is_refused() -> void:
	var good := FileAccess.get_file_as_bytes("res://assets/character/faces/face_adult.png")
	assert_true(Std.png_problems(good).is_empty(), "%s" % Std.png_problems(good))
	# The same PNG with a tEXt chunk after IHDR (8 + 25 bytes).
	var chunk := PackedByteArray([0, 0, 0, 4, 0x74, 0x45, 0x58, 0x74, 0x61, 0, 0x62, 0x21, 0, 0, 0, 0])
	var bad := good.slice(0, 33) + chunk + good.slice(33)
	var p := Std.png_problems(bad)
	assert_eq(p.size(), 1)
	assert_true("tEXt" in p[0], p[0] if p.size() > 0 else "")
	assert_eq(Std.png_problems(PackedByteArray([1, 2, 3])), PackedStringArray(["not a PNG"]))


func test_glb_checker_accepts_a_plain_rigid_part() -> void:
	var p := Std.glb_problems(_glb(_rigid(100, {"name": "main.hat"})), "rigid", "hat")
	assert_true(p.is_empty(), "%s" % p)


func test_glb_over_budget_says_by_how_much() -> void:
	var p := Std.glb_problems(_glb(_rigid(650, {"name": "main.hat"})), "rigid", "hat")
	assert_eq(p.size(), 1)
	assert_true("650 triangles, 150 over" in p[0], "%s" % p)


func test_glb_fixed_colour_must_be_in_the_palette() -> void:
	var pal := Character3D.palette()
	var c := pal[3].srgb_to_linear()
	var ok := Std.glb_problems(_glb(_rigid(10, {"name": "fixed.band", "pbrMetallicRoughness": {"baseColorFactor": [c.r, c.g, c.b, 1]}})), "rigid", "hat")
	assert_true(ok.is_empty(), "%s" % ok)
	var bad := Std.glb_problems(_glb(_rigid(10, {"name": "fixed.band", "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 1, 1]}})), "rigid", "hat")
	assert_eq(bad.size(), 1)
	assert_true("not in the palette" in bad[0], "%s" % bad)
	var main := Std.glb_problems(_glb(_rigid(10, {"name": "main.hat", "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 1, 1]}})), "rigid", "hat")
	assert_true(main.is_empty(), "main takes the player's colour: %s" % main)


func test_glb_animations_skins_and_moved_nodes_are_refused() -> void:
	var j := _rigid(10, {"name": "main.hat"})
	j["animations"] = [{"name": "spin"}]
	assert_true(" ".join(Std.glb_problems(_glb(j), "rigid", "hat")).contains("animations"))
	j = _rigid(10, {"name": "main.hat"})
	j["skins"] = [{"joints": [0]}]
	assert_true(" ".join(Std.glb_problems(_glb(j), "rigid", "hat")).contains("no skin"))
	j = _rigid(10, {"name": "main.hat"})
	j["nodes"][0]["scale"] = [2, 2, 2]
	assert_true(" ".join(Std.glb_problems(_glb(j), "rigid", "hat")).contains("apply the transform"))


func test_skinned_part_needs_body_bones_and_every_shape_key() -> void:
	var good := FileAccess.get_file_as_bytes("res://assets/character/parts/top_tshirt.glb")
	assert_true(Std.glb_problems(good, "skinned", "top").is_empty())
	var j: Dictionary = Std.glb_json(good)
	j["meshes"][0]["extras"]["targetNames"] = ["morph_lean"]
	j["nodes"][int(j["skins"][0]["joints"][0])]["name"] = "DEF-tail"
	var p := " ".join(Std.glb_problems(_glb(j), "skinned", "top"))
	assert_true(p.contains("no shape key morph_stocky"), p)
	assert_true(p.contains("bone DEF-tail"), p)
	assert_true(" ".join(Std.glb_problems(good, "rigid", "hat")).contains("no skin"), "a skinned glb is not rigid")
