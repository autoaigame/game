extends TestCase

## The credits: data/credits.json, drawn from ASSETS.toml by art/credits.gd (make art).

const Credits := preload("res://art/credits.gd")


func _assets_text() -> String:
	return FileAccess.get_file_as_string("res://ASSETS.toml")


func _credits() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))


## data/credits.json is what make art writes from today's ASSETS.toml: run make art after changing it.
func test_credits_file_matches_assets_toml() -> void:
	var want := Credits.json_text(Credits.parse(_assets_text()))
	assert_eq(FileAccess.get_file_as_string("res://data/credits.json"), want,
			"data/credits.json is out of date: run make art")


## Read without the generator's parser: every author named in ASSETS.toml and every licence is credited.
func test_every_author_and_licence_of_assets_toml_is_credited() -> void:
	var c := _credits()
	var names := {}
	var licenses := {}
	for group in ["people", "third_party"]:
		for e in c[group]:
			names[e["name"]] = true
			for l in e["licenses"]:
				licenses[l] = true
	var re := RegEx.create_from_string("(?m)^(author|license) = \"(.*)\"$")
	var seen := 0
	for m in re.search_all(_assets_text()):
		if m.get_string(1) == "license":
			assert_true(licenses.has(m.get_string(2)), "licence %s" % m.get_string(2))
			assert_true(m.get_string(2) in c["licenses"], "licence list: %s" % m.get_string(2))
			continue
		seen += 1
		for part in m.get_string(2).split(";"):
			var who := part.get_slice("(", 0).strip_edges()
			assert_true(names.has(who), "author %s" % who)
	assert_true(seen > 100, "ASSETS.toml read")


## One table per [[asset]], each with its path, author and licence.
func test_parse_reads_every_asset() -> void:
	var text := _assets_text()
	var assets := Credits.parse(text)
	assert_eq(assets.size(), text.count("[[asset]]"))
	for a in assets:
		for key in ["path", "author", "license", "origin"]:
			assert_true(String(a.get(key, "")) != "", "%s of %s" % [key, a.get("path", "?")])


func test_parse_reads_escaped_quotes() -> void:
	var assets := Credits.parse("# c\n\n[[asset]]\npath = \"a.png\"\ntool = \"song \\\"Wind\\\"\"\n")
	assert_eq(assets, [{"path": "a.png", "tool": "song \"Wind\""}])


func test_authors_and_kinds() -> void:
	assert_eq(Credits.authors("Quaternius (the mesh); M3t4Data (the part)"), ["Quaternius", "M3t4Data"])
	assert_eq(Credits.authors("vitteloil"), ["vitteloil"])
	assert_eq(Credits.kind("assets/objects/oak.png"), "objects")
	assert_eq(Credits.kind("assets/sounds/music/menu.ogg"), "music")
	assert_eq(Credits.kind("assets/sounds/ui/click.ogg"), "sounds")
	assert_eq(Credits.kind("assets/tiles.png"), "tiles")
	assert_eq(Credits.kind("art/ui_menu/src/panel.png"), "ui")


## A third-party asset credits its source's author (first in `author`) apart, with the source and
## licence; the contributor who changed it stays among the people. Tools are named once.
func test_third_party_author_is_credited_apart() -> void:
	var c := Credits.build([
		{"path": "assets/character/body.glb", "author": "Quaternius (mesh); M3t4Data (cut)", "origin": "third-party",
				"license": "CC0-1.0", "source": "https://example.org/kit (also https://example.org/b)",
				"tool": "Blender 5"},
		{"path": "assets/objects/a.png", "author": "M3t4Data", "origin": "generated", "license": "CC0-1.0",
				"tool": "PixelLab x"},
		{"path": "assets/objects/b.png", "author": "vitteloil", "origin": "generated", "license": "Other",
				"tool": "PixelLab y"},
	])
	assert_eq(c["third_party"], [{"name": "Quaternius", "files": 1, "kinds": {"character": 1},
			"licenses": ["CC0-1.0"], "sources": ["https://example.org/kit"]}])
	assert_eq(c["people"], [{"name": "M3t4Data", "files": 2, "kinds": {"character": 1, "objects": 1},
			"licenses": ["CC0-1.0"]}, {"name": "vitteloil", "files": 1, "kinds": {"objects": 1}, "licenses": ["Other"]}])
	assert_eq(c["tools"], ["Blender", "PixelLab"])
	assert_eq(c["licenses"], ["CC0-1.0", "Other"])


## The screen names kinds and licences in French: each one in the credits has its words.
func test_every_kind_and_licence_has_french_words() -> void:
	var c := _credits()
	for l in c["licenses"]:
		assert_true(UiText.CREDITS_LICENSES.has(l), "licence %s has no words in UiText.CREDITS_LICENSES" % l)
	for group in ["people", "third_party"]:
		for e in c[group]:
			for k in e["kinds"]:
				assert_true(UiText.CREDITS_KINDS.has(k), "kind %s has no words in UiText.CREDITS_KINDS" % k)
