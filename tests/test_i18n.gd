extends TestCase

## The languages of the UI (client/i18n.gd): the gettext files i18n/<locale>.po, read here as text so that
## what Godot drops without a word (a fuzzy entry, a missing plural form) is seen.

const KEY_RE := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"
const SETTINGS := "user://test_i18n_settings.cfg"


## {header: {name: value}, entries: {msgid: {plural: bool, forms: [String], fuzzy: bool}}} of a .po file.
func _parse(path: String) -> Dictionary:
	var entries := {}
	var header := {}
	var cur := {}
	var field := ""
	var lines := FileAccess.get_file_as_string(path).split("\n")
	lines.append("")
	for raw in lines:
		var line := raw.strip_edges()
		if line == "":
			if cur.has("msgid"):
				if cur["msgid"] == "":
					for h in "".join(cur["forms"]).split("\n", false):
						header[h.get_slice(":", 0).strip_edges()] = h.substr(h.find(":") + 1).strip_edges()
				else:
					entries[cur["msgid"]] = {"plural": cur.has("msgid_plural"), "forms": cur["forms"],
							"fuzzy": cur.get("fuzzy", false)}
			cur = {}
			continue
		if line.begins_with("#,"):
			cur["fuzzy"] = line.contains("fuzzy")
			continue
		if line.begins_with("#"):
			continue
		if line.begins_with("\""):
			_append(cur, field, _unquote(line))
			continue
		var word := line.get_slice(" ", 0)
		var value := _unquote(line.substr(word.length() + 1))
		if word.begins_with("msgstr"):
			cur.get_or_add("forms", []).append("")
			field = "forms"
			_append(cur, field, value)
		else:
			cur[word] = value
			field = word
	return {"header": header, "entries": entries}


func _append(cur: Dictionary, field: String, text: String) -> void:
	if field == "forms":
		cur["forms"][-1] += text
	else:
		cur[field] += text


func _unquote(s: String) -> String:
	return s.substr(1, s.length() - 2).c_unescape()


func _po(locale: String) -> Dictionary:
	return _parse("%s/%s.po" % [I18n.DIR, locale])


## The placeholders of a text, sorted: %d, %s, %.1f… and {name} (%% is the percent sign itself).
func _placeholders(text: String) -> Array:
	var out := []
	for m in RegEx.create_from_string("%%|%[-+ 0#]*[0-9]*(\\.[0-9]+)?[dsfx]|\\{[a-z_]+\\}").search_all(text):
		if m.get_string() != "%%":
			out.append(m.get_string())
	out.sort()
	return out


## The number of plural forms the header's Plural-Forms gives, or -1.
func _nplurals(header: Dictionary) -> int:
	var m := RegEx.create_from_string("nplurals\\s*=\\s*(\\d+)").search(header.get("Plural-Forms", ""))
	return int(m.get_string(1)) if m != null else -1


## Every text key the code names: UiText's constants (keys and tables of keys) and any key-like string
## written in client/*.gd.
func _keys_in_code() -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string(KEY_RE)
	var values: Array = UiText.new().get_script().get_script_constant_map().values()
	while not values.is_empty():
		var v: Variant = values.pop_back()
		if v is Dictionary:
			values.append_array(v.values())
		elif v is Array:
			values.append_array(v)
		elif v is String and re.search(v) != null:
			out[v] = "client/ui_text.gd"
	var literal := RegEx.create_from_string("\"((?:ui|menu|hud|bag|notice|settings|sound|control|key|look|status|name|credits|debug|meta)\\.[a-z0-9_.]+)\"")
	for f in DirAccess.get_files_at("res://client"):
		if f.get_extension() != "gd":
			continue
		for m in literal.search_all(FileAccess.get_file_as_string("res://client/" + f)):
			out[m.get_string(1)] = "client/" + f
	return out


## English and French are both complete: the same keys, none empty, and each language names itself.
func test_english_and_french_have_the_same_keys() -> void:
	var en: Dictionary = _po("en")["entries"]
	var fr: Dictionary = _po("fr")["entries"]
	assert_true(en.size() > 50, "i18n/en.po read: %d keys" % en.size())
	for k in en:
		assert_true(fr.has(k), "fr.po lacks %s" % k)
	for k in fr:
		assert_true(en.has(k), "fr.po has %s, en.po not" % k)
	for e in [en, fr]:
		for k in e:
			for f in e[k]["forms"]:
				assert_true(f != "", "empty text for %s" % k)
	assert_eq(en["meta.language_name"]["forms"], ["English"])
	assert_eq(fr["meta.language_name"]["forms"], ["Français"])


## Every key is lowercase words with dots: never a player's name (no dots in names, Protocol).
func test_keys_are_lowercase_with_dots() -> void:
	var re := RegEx.create_from_string(KEY_RE)
	for k in _po("en")["entries"]:
		assert_true(re.search(k) != null, k)
		assert_true(Protocol.validate_name(k) != "", "%s could be a player's name" % k)


## Each language (one added later too): only keys English has, the same placeholders, as many plural
## forms as its Plural-Forms says, no fuzzy entry (Godot drops it), Language: its file name.
func test_every_language_matches_english() -> void:
	var base: Dictionary = _po("en")["entries"]
	var langs := I18n.available()
	assert_true("en" in langs and "fr" in langs, str(langs))
	for l in langs:
		var po := _po(l)
		var header: Dictionary = po["header"]
		assert_eq(header.get("Language", ""), l, "Language: of %s.po" % l)
		var n := _nplurals(header)
		assert_true(n >= 1, "Plural-Forms of %s.po: %s" % [l, header.get("Plural-Forms", "")])
		assert_true(header.get("Content-Type", "").contains("UTF-8"), "%s.po in UTF-8" % l)
		var entries: Dictionary = po["entries"]
		for k in entries:
			var e: Dictionary = entries[k]
			assert_false(e["fuzzy"], "%s.po: %s is fuzzy" % [l, k])
			if not base.has(k):
				failures.append("%s.po: unknown key %s" % [l, k])
				continue
			assert_eq(e["plural"], base[k]["plural"], "%s.po: %s plural or not as in en.po" % [l, k])
			if e["plural"]:
				assert_eq(e["forms"].size(), n, "%s.po: plural forms of %s" % [l, k])
			for f in e["forms"]:
				if f != "":
					assert_eq(_placeholders(f), _placeholders(base[k]["forms"][-1]), "%s.po: %s" % [l, k])


## Godot reads each file as the language its name says.
func test_godot_loads_each_file_as_its_language() -> void:
	for l in I18n.available():
		var t: Translation = load("%s/%s.po" % [I18n.DIR, l])
		assert_true(t != null, l)
		if t != null:
			assert_eq(t.locale, l)
			assert_true(t.get_message_list().has("meta.language_name"), l)


## Every text the code shows has its key in en.po (the reference, and the fallback of the others).
func test_every_key_the_code_uses_exists() -> void:
	var en: Dictionary = _po("en")["entries"]
	var used := _keys_in_code()
	assert_true(used.size() > 50, "keys found in the code: %d" % used.size())
	assert_true(used.has(UiText.PLAY) and used.has("notice.too_far"), str(used.keys()))
	for k in used:
		assert_true(en.has(k), "%s (%s) has no text in i18n/en.po" % [k, used[k]])


## English is the fallback, so a text missing from a language shows in English.
func test_english_is_the_fallback() -> void:
	assert_eq(ProjectSettings.get_setting("internationalization/locale/fallback"), "en")
	assert_eq(I18n.BASE, "en")


## A new language is one more file in the folder.
func test_languages_are_found_in_the_folder() -> void:
	var dir := "user://test_i18n_langs"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["en.po", "pt_BR.po", "notes.txt"]:
		FileAccess.open(dir.path_join(f), FileAccess.WRITE).store_string("")
	assert_eq(I18n.available(dir), ["en", "pt_BR"] as Array[String])
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


## The language to start in: --language, else the saved choice, else the system's matched to a file
## (fr_CA plays in fr), else English.
func test_start_language_choice() -> void:
	var langs := ["en", "fr"]
	assert_eq(I18n.pick("", "", "fr_FR", langs), "fr")
	assert_eq(I18n.pick("", "", "fr_CA", langs), "fr")
	assert_eq(I18n.pick("", "", "en_US", langs), "en")
	assert_eq(I18n.pick("", "", "de_DE", langs), "en", "no German: English")
	assert_eq(I18n.pick("", "", "", langs), "en")
	assert_eq(I18n.pick("", "en", "fr_FR", langs), "en", "the saved choice wins")
	assert_eq(I18n.pick("", "de", "fr_FR", langs), "fr", "a saved language gone: the system's")
	assert_eq(I18n.pick("en", "fr", "fr_FR", langs), "en", "--language wins")
	assert_eq(I18n.closest("pt_BR", langs), "")


## The choice is kept in settings.cfg next to the other settings; nothing usable reads as "".
func test_language_choice_is_saved() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	assert_eq(ClientSettings.load_language(SETTINGS), "")
	ClientSettings.save_name("Testeur", SETTINGS)
	ClientSettings.save_language("fr", SETTINGS)
	assert_eq(ClientSettings.load_language(SETTINGS), "fr")
	assert_eq(ClientSettings.load_name(SETTINGS), "Testeur", "other settings kept")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "language", 3)
	cfg.save(SETTINGS)
	assert_eq(ClientSettings.load_language(SETTINGS), "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## At launch the saved choice sets the locale, whatever the system's language.
func test_start_uses_the_saved_language() -> void:
	ClientSettings.save_language("fr", SETTINGS)
	assert_eq(I18n.start(SETTINGS), "fr")
	assert_eq(TranslationServer.get_locale(), "fr")
	assert_eq(UiText.t(UiText.PLAY), "Jouer")
	ClientSettings.save_language("en", SETTINGS)
	assert_eq(I18n.start(SETTINGS), "en")
	assert_eq(UiText.t(UiText.PLAY), "Play")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## The texts in English, with their numbers and plurals.
func test_texts_in_english() -> void:
	I18n.use("en")
	assert_eq(UiText.t(UiText.PLAY), "Play")
	assert_eq(UiText.t(UiText.TAB_SOUND), "Sound")
	assert_eq(UiText.notice("too_far", {}), "Too far.")
	assert_eq(UiText.notice("need_sticks", {}), "You need %d sticks to make a fire." % Protocol.FIRE_STICKS)
	assert_eq(UiText.notice("gathered", {"item": "berries", "count": 2}), "+2 %s" % ItemData.item("berries")["name"])
	assert_eq(UiText.notice("nope", {}), "")
	assert_eq(UiText.name_problem(""), "Type a name to enter.")
	assert_eq(UiText.rejection("", "ann"), "The name ann is already in the game. Pick another one.")
	assert_eq(UiText.percent(80), "80%")
	assert_eq(UiText.cap_text(KEY_SHIFT), "Shift")
	assert_eq(UiText.tn(UiText.NAME_TOO_LONG, 1) % 1, "1 character at most.")


## French plurals: 0 and 1 take the singular.
func test_french_plurals() -> void:
	I18n.use("fr")
	assert_eq(UiText.tn(UiText.NAME_TOO_LONG, 1) % 1, "1 caractère au plus.")
	assert_eq(UiText.tn(UiText.NAME_TOO_LONG, 0) % 0, "0 caractère au plus.")
	assert_eq(UiText.tn(UiText.NAME_TOO_LONG, 16) % 16, "16 caractères au plus.")
	assert_eq(UiText.notice("need_sticks", {}), "Il te faut %d bâtons pour faire un feu." % Protocol.FIRE_STICKS)
	I18n.use("en")


## A text built in code (the credits) is built again when the language changes; a key in a Label's
## text stays the key, the Label translating it as it draws. The tests run before the SceneTree does,
## so the notification the engine sends every node in the tree is sent here by hand.
func test_built_texts_follow_a_language_change() -> void:
	var screen: Control = preload("res://client/credits_screen.gd").new({"people": [{"name": "M3t4Data",
			"files": 2, "kinds": {"objects": 2}, "licenses": ["CC0-1.0"]}]})
	I18n.use("en")
	screen.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_true(screen.body_text().contains("Contributors"), screen.body_text())
	assert_true(screen.body_text().contains("2 files: scenery (2)"), screen.body_text())
	I18n.use("fr")
	screen.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_true(screen.body_text().contains("Contributeurs"), screen.body_text())
	assert_true(screen.body_text().contains("2 fichiers : décor (2)"), screen.body_text())
	assert_eq(screen.back_button().text, UiText.BACK)
	assert_eq(screen.back_button().atr(screen.back_button().text), "Retour")
	I18n.use("en")
	assert_eq(screen.back_button().atr(screen.back_button().text), "Back")
	screen.free()
