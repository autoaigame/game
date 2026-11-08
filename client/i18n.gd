## The languages of the client UI: one gettext file per language, i18n/<locale>.po, whose msgids are the
## keys of client/ui_text.gd. i18n/en.po is the reference and the fallback (project.godot
## internationalization/locale/fallback). The files are loaded as they are, without an import.
class_name I18n
extends RefCounted

const DIR := "res://i18n"
const BASE := "en"

static var _loaded := {}  ## locale -> Translation handed to the TranslationServer
static var _ready := false  ## DIR was loaded (ensure_loaded)
static var _launch_locale := ""  ## the engine's locale before this class changed it


## The locales that have a file in `dir`, sorted (a new language is one new file).
static func available(dir := DIR) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "po":
			out.append(f.get_basename())
	out.sort()
	return out


## Loads each language of `dir` once and gives it to the TranslationServer.
static func load_all(dir := DIR) -> void:
	for l in available(dir):
		if _loaded.has(l):
			continue
		var t: Translation = load(dir.path_join(l + ".po"))
		if t == null:
			push_error("i18n: cannot read %s.po" % l)
			continue
		TranslationServer.add_translation(t)
		_loaded[l] = t


## Loads DIR's languages the first time a text is asked for (UiText.t), so a text is never a bare key
## even before start() (tests, tools).
static func ensure_loaded() -> void:
	if not _ready:
		_ready = true
		_launch_locale = TranslationServer.get_locale()
		load_all()


## Of `langs`, the one nearest `wanted` (fr_CA gives fr), or "" when none shares its language.
static func closest(wanted: String, langs: Array) -> String:
	var best := ""
	var score := 0
	for l in langs:
		var s := TranslationServer.compare_locales(wanted, l)
		if s > score:
			best = l
			score = s
	return best


## The language to start in, among `langs`: the player's saved choice, else `launch` (the engine's
## locale at launch: --language if given, else the system's, the browser's on the web), else BASE.
static func pick(saved: String, launch: String, langs: Array) -> String:
	for wanted in [saved, launch]:
		if wanted != "":
			var l := closest(wanted, langs)
			if l != "":
				return l
	return BASE


## At launch, before the menus are built: loads the languages and sets the locale (see pick).
## The engine starts in the system's locale, or in the one --language gives, and keeps that option to
## itself (it is not in OS.get_cmdline_args()), so --language counts as the system's language: it
## gives the language of a player who never chose one, and a choice saved from the language menu
## (ClientSettings.save_language) beats it. To force a language, choose it in the menu.
static func start(settings_path := ClientSettings.PATH) -> String:
	ensure_loaded()
	var l := pick(ClientSettings.load_language(settings_path), _launch_locale, available())
	TranslationServer.set_locale(l)
	return l


## The languages to choose from, in file order: [{locale, name}], `name` being the language's name in
## itself (meta.language_name of its own file, never translated), else its locale.
static func languages() -> Array:
	ensure_loaded()
	var out := []
	for l in available():
		var t: Translation = _loaded.get(l)
		var name := String(t.get_message("meta.language_name")) if t != null else ""
		out.append({"locale": l, "name": name if name != "" else l})
	return out


## The language the UI shows now, as a locale of `langs` (fr_FR shows fr), else BASE.
static func current(langs: Array = available()) -> String:
	var l := closest(TranslationServer.get_locale(), langs)
	return l if l != "" else BASE


## The player chooses `locale`: the UI shows in it at once (the engine tells every node in the tree,
## NOTIFICATION_TRANSLATION_CHANGED) and it is the language of the next launches.
static func choose(locale: String, settings_path := ClientSettings.PATH) -> void:
	ensure_loaded()
	TranslationServer.set_locale(locale)
	ClientSettings.save_language(locale, settings_path)


## Shows the UI in `locale` from now on (tests use it to fix the language).
static func use(locale: String) -> void:
	ensure_loaded()
	TranslationServer.set_locale(locale)
