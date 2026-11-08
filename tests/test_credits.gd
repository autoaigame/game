extends TestCase

## The credits, read from ASSETS.toml by client/credits.gd when the Crédits screen opens.

const Credits := preload("res://client/credits.gd")
const CreditsScreen := preload("res://client/credits_screen.gd")


## These tests check French words: the UI is shown in French whatever the system's language.
func _init() -> void:
	I18n.use("fr")


func _assets_text() -> String:
	return FileAccess.get_file_as_string("res://ASSETS.toml")


func _credits() -> Dictionary:
	return Credits.load_from("res://ASSETS.toml")


## The text of a Crédits screen that read `source` when it showed.
func _shown_text(source: String) -> String:
	var screen := CreditsScreen.new()
	screen.source = source
	screen.visible = false
	screen.visible = true
	var text := screen.body_text()
	screen.free()
	return text


## Read without the parser: every author named in the game's ASSETS.toml, and every licence in words,
## shows on the Crédits screen.
func test_every_author_and_licence_of_assets_toml_is_shown() -> void:
	var text := _shown_text("res://ASSETS.toml")
	var re := RegEx.create_from_string("(?m)^(author|license) = \"(.*)\"$")
	var seen := 0
	for m in re.search_all(_assets_text()):
		if m.get_string(1) == "license":
			var l := m.get_string(2)
			var words: String = UiText.t(UiText.CREDITS_LICENSES[l]) if UiText.CREDITS_LICENSES.has(l) else l
			assert_true(text.contains(words), "licence %s" % m.get_string(2))
			continue
		seen += 1
		for part in m.get_string(2).split(";"):
			var who := part.get_slice("(", 0).strip_edges()
			assert_true(who in text.split("\n"), "author %s on a line of its own" % who)
	assert_true(seen > 100, "ASSETS.toml read")


## Without ASSETS.toml (or with nothing readable in it), the screen says so in a line and no credits.
func test_missing_or_unreadable_file() -> void:
	assert_eq(Credits.load_from("res://no_such_assets.toml"), {})
	var path := "user://test_credits_unreadable.toml"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not toml at all\n")
	f.close()
	assert_eq(Credits.load_from(path), {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var text := _shown_text("res://no_such_assets.toml")
	assert_true(text.contains(UiText.t(UiText.CREDITS_MISSING)), text)
	assert_false(text.contains(UiText.t(UiText.CREDITS_PEOPLE)), text)


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
				"license": "CC0-1.0", "source": "kit-page (also other-page)",
				"tool": "Blender 5"},
		{"path": "assets/objects/a.png", "author": "M3t4Data", "origin": "generated", "license": "CC0-1.0",
				"tool": "PixelLab x"},
		{"path": "assets/objects/b.png", "author": "vitteloil", "origin": "generated", "license": "Other",
				"tool": "PixelLab y"},
	])
	assert_eq(c["third_party"], [{"name": "Quaternius", "files": 1, "kinds": {"character": 1},
			"licenses": ["CC0-1.0"], "sources": ["kit-page"]}])
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
