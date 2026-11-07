## Checks one character part against the standard (docs/character-parts.md) and says what to fix.
##   make check-part ID=<id>   (godot --headless --path . -s res://tools/check_part.gd -- <id>)
## Runs the same checks as make check, narrowed to the part where they can be: its files
## (tests/character_standard.gd), the character test files that cover every part, and the anti-traversal
## measures on every body shape (hats over the head and hair, garments over what they cover).
extends SceneTree

const Std := preload("res://tests/character_standard.gd")
const Heads := preload("res://tests/test_character_head_parts.gd")
const Garments := preload("res://tests/test_character_garments.gd")
const Pose := preload("res://tests/character_pose.gd")
## Test files whose tests cover every part and run in seconds.
const TESTS := ["res://tests/test_character_parts.gd", "res://tests/test_character_rig.gd",
		"res://tests/test_character_looks.gd", "res://tests/test_character_standard.gd"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		print("usage: make check-part ID=<id>")
		quit(2)
		return
	var id: String = args[0]
	var bad := PackedStringArray()
	bad.append_array(Std.problems(id))
	if not bad.is_empty() or not id in CharacterParts.part_ids():
		_report(id, bad if not bad.is_empty() else PackedStringArray(["%s: not loaded (see the errors above)" % id]))
		return
	print("files: ok")
	for path in TESTS:
		var script: GDScript = load(path)
		for m in script.get_script_method_list():
			if not String(m["name"]).begins_with("test_"):
				continue
			var t: TestCase = script.new()
			t.call(m["name"])
			for f in t.failures:
				bad.append("%s::%s: %s" % [path.get_file(), m["name"], f])
	print("records, rig, faces: %s" % ("ok" if bad.is_empty() else "see below"))
	var p := CharacterParts.part(id)
	var bodies := CharacterParts.parts_for("body")
	if p["slot"] == "hat" or p["slot"] == "hair":
		var hats := [id] if p["slot"] == "hat" else Array(CharacterParts.parts_for("hat"))
		var hairs := ([""] + Array(CharacterParts.parts_for("hair"))) if p["slot"] == "hat" else [id]
		for body in bodies:
			for hat in hats:
				for hair in hairs:
					var look := Pose.look([[body, 0], [hat, 0]] + ([[hair, 0]] if hair != "" else []))
					var m := Heads.measure(look, hat)
					if m["skull"] > 0:
						bad.append("%s: %d vertices of the head come through %s (worst of %d poses)" % [body, m["skull"], hat, m["poses"]])
					if m["hair"] > 0:
						bad.append("%s: %d vertices of %s come through %s (worst of %d poses)" % [body, m["hair"], hair, hat, m["poses"]])
		print("hats over head and hair, on %s: done" % ", ".join(bodies))
	elif p["kind"] == "skinned":
		for body in bodies:
			for look in Garments.looks_for(body, id):
				bad.append_array(Garments.problems(look))
		print("garments over what they cover, on %s: done" % ", ".join(bodies))
	_report(id, bad)


func _report(id: String, bad: PackedStringArray) -> void:
	if bad.is_empty():
		print("%s follows the standard" % id)
		quit(0)
		return
	var seen := {}
	for b in bad:
		if not seen.has(b):
			seen[b] = true
			print("FAIL " + b)
	print("%s: %d problems" % [id, seen.size()])
	quit(1)
