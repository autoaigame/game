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


## The language to start in, among `langs`: the one forced on the command line (--language), else the
## player's saved choice, else the system's (the browser's on the web), else BASE.
static func pick(forced: String, saved: String, system: String, langs: Array) -> String:
	for wanted in [forced, saved, system]:
		if wanted != "":
			var l := closest(wanted, langs)
			if l != "":
				return l
	return BASE


## At launch, before the menus are built: loads the languages and sets the locale (see pick). The
## engine starts in the system's locale unless --language (or the project's locale/test) says otherwise.
## The engine keeps --language to itself, so it is seen only when it differs from the system's language:
## --language with the system's own language does not beat a saved choice.
static func start(settings_path := ClientSettings.PATH) -> String:
	ensure_loaded()
	var system := TranslationServer.standardize_locale(OS.get_locale())
	var forced := _launch_locale if _launch_locale != system else ""
	var l := pick(forced, ClientSettings.load_language(settings_path), system, available())
	TranslationServer.set_locale(l)
	return l


## Shows the UI in `locale` from now on (tests use it to fix the language).
static func use(locale: String) -> void:
	ensure_loaded()
	TranslationServer.set_locale(locale)
