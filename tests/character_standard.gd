## The standard of a character part's files (docs/character-parts.md), read from the files themselves:
## the ASSETS.toml entry and its licence, PNG chunks, and the glb's structure, triangles and colours.
## problems(id) lists what a part breaks, in words a contributor (or their agent) can act on. Used by
## tests/test_character_standard.gd (every part, in make check) and tools/check_part.gd (one part).
extends RefCounted

const ASSETS := "res://ASSETS.toml"
const BODY_GLB := "res://assets/character/body.glb"
## PNG chunks a part's texture may have: no text, time, colour profile or other metadata.
const PNG_CHUNKS := ["IHDR", "PLTE", "tRNS", "IDAT", "IEND"]
## What art/character/new_part.py writes for the contributor to replace.
const PLACEHOLDERS := ["<version>", "say how it is made", "TODO"]
const PLACEHOLDER_HELP := {"author": "your GitHub login", "tool": "the Blender version and how the part is made"}
## A colour is a palette colour when each channel is within this of it (8-bit sRGB steps).
const COLOUR_SLACK := 1.5 / 255.0

static var _assets := {}
static var _bones: Array = []


## What `id` breaks, one line each; empty when it follows the standard.
static func problems(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var file := CharacterParts.DATA_DIR.path_join("parts").path_join(id + ".json")
	if not FileAccess.file_exists(file):
		out.append("%s: no record %s" % [id, file])
		return out
	var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	var why := CharacterParts.check_record(rec, id + ".json")
	if why != "":
		out.append("%s: record: %s" % [id, why])
		return out
	if not id.begins_with(String(rec["slot"]) + "_"):
		out.append("%s: the id starts with its slot: %s_..." % [id, rec["slot"]])
	var files: Array[String] = []
	for key in ["glb", "texture"]:
		if typeof(rec.get(key)) == TYPE_STRING and rec[key] != "":
			files.append(rec[key])
	if typeof(rec.get("when_hidden")) == TYPE_DICTIONARY:
		files.append(String(rec["when_hidden"]["glb"]))
	for f in files:
		var entry: Dictionary = entries().get(f.trim_prefix("res://"), {})
		for p in placeholder_problems(rec, entry):
			if not ("%s: %s" % [id, p]) in out:
				out.append("%s: %s" % [id, p])
		var why_asset := asset_problem(f.trim_prefix("res://"))
		if why_asset != "":
			out.append("%s: %s" % [id, why_asset])
		if f.ends_with(".png"):
			for p in png_problems(FileAccess.get_file_as_bytes(f)):
				out.append("%s: %s: %s" % [id, f.get_file(), p])
		elif f.ends_with(".glb") and rec["kind"] != "body":
			for p in glb_problems(FileAccess.get_file_as_bytes(f), String(rec["kind"]), String(rec["slot"])):
				out.append("%s: %s: %s" % [id, f.get_file(), p])
	return out


## Placeholders art/character/new_part.py leaves for the contributor to fill, still in the record or the
## ASSETS.toml entry.
static func placeholder_problems(rec: Dictionary, entry: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if String(rec.get("name", "")).strip_edges().to_upper().begins_with("TODO"):
		out.append("record: name is still a placeholder (%s): the name players see, in French" % rec["name"])
	for key in ["author", "tool"]:
		var v := String(entry.get(key, ""))
		for mark in PLACEHOLDERS:
			if v.contains(mark):
				out.append("ASSETS.toml: %s still has the placeholder \"%s\": %s" % [key, mark, PLACEHOLDER_HELP[key]])
				break
	return out


## "" when ASSETS.toml has an entry for `path` (relative to the repository) with licence CC0-1.0.
static func asset_problem(path: String) -> String:
	if not entries().has(path):
		return "no ASSETS.toml entry for %s" % path
	var e: Dictionary = _assets[path]
	if e.get("license", "") != "CC0-1.0":
		return "%s: licence %s in ASSETS.toml, character parts are CC0-1.0" % [path, e.get("license", "(none)")]
	if String(e.get("author", "")) == "":
		return "%s: no author in ASSETS.toml" % path
	return ""


## The entries of ASSETS.toml by path, read once.
static func entries() -> Dictionary:
	if _assets.is_empty():
		_assets = parse_assets(FileAccess.get_file_as_string(ASSETS))
	return _assets


## {path: {key: value}} of the [[asset]] entries of an ASSETS.toml text (string values only).
static func parse_assets(text: String) -> Dictionary:
	var out := {}
	var cur := {}
	var line_re := RegEx.create_from_string('^([a-z_]+)\\s*=\\s*"(.*)"\\s*(#.*)?$')
	for raw in text.split("\n") + PackedStringArray(["[[asset]]"]):
		var line := raw.strip_edges()
		if line == "[[asset]]":
			if cur.has("path"):
				out[cur["path"]] = cur
			cur = {}
			continue
		var m := line_re.search(line)
		if m:
			cur[m.get_string(1)] = m.get_string(2)
	return out


## Chunks of a PNG that break the standard (metadata), or why it is not a PNG.
static func png_problems(bytes: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	if bytes.size() < 8 or bytes.slice(0, 8) != PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]):
		out.append("not a PNG")
		return out
	var at := 8
	while at + 8 <= bytes.size():
		var n := (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]
		var kind := bytes.slice(at + 4, at + 8).get_string_from_ascii()
		if not kind in PNG_CHUNKS:
			out.append("chunk %s: no metadata in a PNG (art/character/faces.py writes only IHDR, IDAT, IEND)" % kind)
		at += 12 + n
	return out


## The JSON part of a glb, or null.
static func glb_json(bytes: PackedByteArray) -> Variant:
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "glTF":
		return null
	var n := bytes.decode_u32(12)
	if bytes.slice(16, 20).get_string_from_ascii() != "JSON" or 20 + n > bytes.size():
		return null
	return JSON.parse_string(bytes.slice(20, 20 + n).get_string_from_utf8())


## Bone names of the body's skeleton.
static func body_bones() -> Array:
	if _bones.is_empty():
		var j: Dictionary = glb_json(FileAccess.get_file_as_bytes(BODY_GLB))
		for i in j["skins"][0]["joints"]:
			_bones.append(j["nodes"][int(i)].get("name", ""))
	return _bones


## Triangles of a glb's meshes.
static func glb_triangles(j: Dictionary) -> int:
	var n := 0
	for m in j.get("meshes", []):
		for p in m["primitives"]:
			var acc: int = p["indices"] if p.has("indices") else p["attributes"]["POSITION"]
			n += int(j["accessors"][acc]["count"]) / 3
	return n


## What a part's glb breaks: kind "rigid" or "skinned", slot for its triangle budget (slots.json).
static func glb_problems(bytes: PackedByteArray, kind: String, slot: String) -> PackedStringArray:
	var out := PackedStringArray()
	var j: Variant = glb_json(bytes)
	if typeof(j) != TYPE_DICTIONARY:
		out.append("not a glb")
		return out
	for key in ["animations", "cameras", "images", "textures"]:
		if not j.get(key, []).is_empty():
			out.append("has %s: export the mesh only (flat colours, no texture)" % key)
	if j.get("extensionsUsed", []).has("KHR_lights_punctual"):
		out.append("has lights: export the mesh only")
	var meshes: Array = j.get("meshes", [])
	var skins: Array = j.get("skins", [])
	if meshes.size() != 1:
		out.append("%d meshes: one per part (join them)" % meshes.size())
	if kind == "rigid":
		if not skins.is_empty():
			out.append("a rigid part has no skin: it hangs from its bone")
		for nd in j["nodes"]:
			if nd.has("mesh") and (nd.has("translation") or nd.has("rotation") or nd.has("scale") or nd.has("matrix")):
				if not _is_identity(nd):
					out.append("node %s is moved, turned or scaled: apply the transform (origin at the bone's head)" % nd.get("name", "?"))
	elif kind == "skinned":
		if skins.size() != 1:
			out.append("a skinned part has one skin (the body's skeleton): %d" % skins.size())
		else:
			var bones := body_bones()
			for i in skins[0]["joints"]:
				var name: String = j["nodes"][int(i)].get("name", "")
				if not name in bones:
					out.append("bone %s is not in the body's skeleton" % name)
		var want: Array = CharacterParts.morph_ids().slice(1).map(func(m): return "morph_" + m)
		for m in meshes:
			var names: Array = m.get("extras", {}).get("targetNames", [])
			for w in want:
				if not w in names:
					out.append("no shape key %s: run the part through part_kit.transfer_morphs" % w)
			for p in m["primitives"]:
				if p["attributes"].has("JOINTS_1"):
					out.append("more than 4 bones on a vertex")
	var budget := int(CharacterParts.slot(slot).get("triangles", 0))
	var tris := glb_triangles(j)
	if budget > 0 and tris > budget:
		out.append("%d triangles, %d over the %s budget of %d (data/character/slots.json)" % [tris, tris - budget, slot, budget])
	var pal := Character3D.palette()
	for m in j.get("materials", []):
		var name: String = m.get("name", "")
		var pbr: Dictionary = m.get("pbrMetallicRoughness", {})
		if pbr.has("baseColorTexture"):
			out.append("material %s has a texture: flat colours only" % name)
		if name.begins_with("main"):
			continue  # takes the colour the player chooses
		var c: Array = pbr.get("baseColorFactor", [1, 1, 1, 1])
		var srgb := Color(c[0], c[1], c[2]).linear_to_srgb()
		if not _in_palette(srgb, pal):
			out.append("material %s: colour #%s is not in the palette (data/palette.json); nearest #%s" % [
					name, srgb.to_html(false), _nearest(srgb, pal).to_html(false)])
	return out


static func _is_identity(nd: Dictionary) -> bool:
	var t: Array = nd.get("translation", [0, 0, 0])
	var r: Array = nd.get("rotation", [0, 0, 0, 1])
	var s: Array = nd.get("scale", [1, 1, 1])
	var ok := Vector3(t[0], t[1], t[2]).is_zero_approx() and Quaternion(r[0], r[1], r[2], r[3]).is_equal_approx(Quaternion.IDENTITY)
	return ok and Vector3(s[0], s[1], s[2]).is_equal_approx(Vector3.ONE) and not nd.has("matrix")


static func _in_palette(c: Color, pal: PackedColorArray) -> bool:
	for p in pal:
		if absf(p.r - c.r) <= COLOUR_SLACK and absf(p.g - c.g) <= COLOUR_SLACK and absf(p.b - c.b) <= COLOUR_SLACK:
			return true
	return false


static func _nearest(c: Color, pal: PackedColorArray) -> Color:
	var best := pal[0]
	for p in pal:
		if Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length() < Vector3(best.r - c.r, best.g - c.g, best.b - c.b).length():
			best = p
	return best
