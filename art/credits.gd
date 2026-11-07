## The credits screen's data (data/credits.json), drawn from ASSETS.toml: ASSETS.toml stays out of the
## web build, data/credits.json goes in. Written by `make art` (art/gen_art.gd); tests/test_credits.gd
## checks that the file matches ASSETS.toml.
##
## Grouping: one entry per contributor (files made, by kind, and their licences), one per third party
## (an asset of origin "third-party" names its source's author first in `author`, before the
## contributors who changed it), and the generation tools named in the `tool` fields, each once.
extends RefCounted

const SOURCE := "res://ASSETS.toml"
const OUT := "res://data/credits.json"
## Word found in a `tool` field -> the tool's name in the credits.
const TOOLS := {"PixelLab": "PixelLab", "ElevenLabs": "ElevenLabs", "Suno": "Suno", "Blender": "Blender",
		"ImageMagick": "ImageMagick", "Godot": "Godot", "Claude": "Claude"}


## The [[asset]] tables of an ASSETS.toml text, as dictionaries of their `key = "value"` lines.
## Only what ASSETS.toml uses is read: one-line basic strings, comments and blank lines.
static func parse(text: String) -> Array:
	var assets := []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line == "[[asset]]":
			assets.append({})
			continue
		var eq := line.find("=")
		if eq < 0 or assets.is_empty():
			push_error("credits: cannot read ASSETS.toml line: %s" % line)
			continue
		var value: Variant = JSON.parse_string(line.substr(eq + 1).strip_edges())  # TOML basic string
		if not value is String:
			push_error("credits: not a one-line string in ASSETS.toml: %s" % line)
			continue
		assets.back()[line.substr(0, eq).strip_edges()] = value
	return assets


## The names in an `author` field, in order: "Quaternius (the mesh); M3t4Data (the part)" gives
## ["Quaternius", "M3t4Data"].
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
## sorted, so the file only changes when ASSETS.toml does.
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


## The data/credits.json text for `assets`.
static func json_text(assets: Array) -> String:
	return JSON.stringify(build(assets), "\t", false) + "\n"


## Writes data/credits.json from ASSETS.toml; OK or the error.
static func write() -> Error:
	var text := FileAccess.get_file_as_string(SOURCE)
	if text == "":
		return ERR_FILE_CANT_READ
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(json_text(parse(text)))
	f.close()
	return OK


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
