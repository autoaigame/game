## The credits of the Crédits screen (client/credits_screen.gd), read from ASSETS.toml when it opens.
## ASSETS.toml goes in the web build (export_presets.cfg include_filter).
##
## Grouping: one entry per contributor (files made, by kind, and their licences), one per third party
## (an asset of origin "third-party" names its source's author first in `author`, before the
## contributors who changed it), and the generation tools named in the `tool` fields, each once.
extends RefCounted

const SOURCE := "res://ASSETS.toml"
## Word found in a `tool` field -> the tool's name in the credits. A tool missing here is not credited:
## add it when ASSETS.toml names a new one.
const TOOLS := {"PixelLab": "PixelLab", "ElevenLabs": "ElevenLabs", "Suno": "Suno", "Blender": "Blender",
		"ImageMagick": "ImageMagick", "Godot": "Godot", "Claude": "Claude"}


## The credits read from the ASSETS.toml at `path` (see build()), or {} when the file is missing or
## holds no asset that can be read. Quiet: the screen says the credits are missing.
static func load_from(path: String = SOURCE) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var assets := parse(f.get_as_text())
	f.close()
	return {} if assets.is_empty() else build(assets)


## The [[asset]] tables of an ASSETS.toml text, as dictionaries of their `key = "value"` lines.
## Only what ASSETS.toml uses is read: one-line basic strings, comments and blank lines. Any other
## line is skipped (tests/test_credits.gd checks that every author of the game's file is shown).
static func parse(text: String) -> Array:
	var assets := []
	var json := JSON.new()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line == "[[asset]]":
			assets.append({})
			continue
		var eq := line.find("=")
		if eq < 0 or assets.is_empty():
			continue
		# a TOML basic string reads as a JSON string; JSON.parse() reports no engine error
		if json.parse(line.substr(eq + 1).strip_edges()) != OK or not json.data is String:
			continue
		assets.back()[line.substr(0, eq).strip_edges()] = json.data
	return assets


## The names in an `author` field, in order: "Quaternius (the mesh); M3t4Data (the part)" gives
## ["Quaternius", "M3t4Data"]. A ";" inside the brackets is not supported.
static func authors(field: String) -> Array:
	var names := []
	for part in field.split(";"):
		var name := part.get_slice("(", 0).strip_edges()
		if name != "" and not name in names:
			names.append(name)
	return names


## What an asset file is, for the credits: its folder under assets/ (sounds/music is "music"), the
## file's name for a file directly in assets/, "ui" for the menu art's sources (art/ui_menu/src/).
static func kind(path: String) -> String:
	if path.begins_with("art/ui_menu/"):
		return "ui"
	var rest := path.trim_prefix("assets/")
	if rest.begins_with("sounds/music/"):
		return "music"
	if rest.contains("/"):
		return rest.get_slice("/", 0)
	return rest.get_basename()


## The credits of `assets` (from parse()): {people, third_party, tools, licenses}. People and third
## parties come by number of files, then by name; their kinds and licences, the tools and licences
## sorted.
static func build(assets: Array) -> Dictionary:
	var people := {}  # name -> {files, kinds, licenses}
	var third := {}  # name -> {files, kinds, licenses, sources}
	var tools := {}
	var licenses := {}
	for a in assets:
		var names := authors(String(a.get("author", "")))
		var license := String(a.get("license", ""))
		licenses[license] = true
		var k := kind(String(a.get("path", "")))
		for i in names.size():
			var outside: bool = i == 0 and a.get("origin", "") == "third-party"
			var group: Dictionary = third if outside else people
			if not group.has(names[i]):
				group[names[i]] = {"files": 0, "kinds": {}, "licenses": {}, "sources": {}}
			var g: Dictionary = group[names[i]]
			g["files"] += 1
			g["kinds"][k] = g["kinds"].get(k, 0) + 1
			g["licenses"][license] = true
			var source := String(a.get("source", "")).get_slice(" ", 0)
			if outside and source != "":
				g["sources"][source] = true
		for word in TOOLS:
			if String(a.get("tool", "")).contains(word):
				tools[TOOLS[word]] = true
	return {"people": _entries(people, false), "third_party": _entries(third, true),
			"tools": _sorted(tools.keys()), "licenses": _sorted(licenses.keys())}


static func _entries(group: Dictionary, with_sources: bool) -> Array:
	var names := group.keys()
	names.sort_custom(func(a, b): return group[a]["files"] > group[b]["files"] \
			or (group[a]["files"] == group[b]["files"] and a < b))
	var out := []
	for n in names:
		var g: Dictionary = group[n]
		var kinds := {}
		for k in _sorted(g["kinds"].keys()):
			kinds[k] = g["kinds"][k]
		var e := {"name": n, "files": g["files"], "kinds": kinds, "licenses": _sorted(g["licenses"].keys())}
		if with_sources:
			e["sources"] = _sorted(g["sources"].keys())
		out.append(e)
	return out


static func _sorted(a: Array) -> Array:
	var s := a.duplicate()
	s.sort()
	return s
