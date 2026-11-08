extends TestCase

## Choosing the language (client/language_list.gd, client/language_screen.gd): on the title's Langue
## screen and in the settings' Langue tab, applied at once and kept.

const LanguageList := preload("res://client/language_list.gd")
const LanguageScreen := preload("res://client/language_screen.gd")
const SettingsMenu := preload("res://client/settings_menu.gd")
const LoginUi := preload("res://client/login_ui.gd")
const PATH := "user://test_language_screen.cfg"


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _list() -> LanguageList:
	var l := LanguageList.new()
	l.settings_path = PATH
	return l


## One entry per file of i18n/, each named in its own language whatever the language shown.
func test_each_language_is_named_in_itself() -> void:
	for shown in ["fr", "en"]:
		I18n.use(shown)
		assert_eq(I18n.languages(), [{"locale": "en", "name": "English"}, {"locale": "fr", "name": "Français"}],
				"shown in %s" % shown)
		var list := _list()
		assert_eq(list.locales(), I18n.available())
		for l in list.locales():
			var b := list.button(l)
			assert_eq(b.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, l)
			assert_eq(b.atr(b.text) if b.can_auto_translate() else b.text, {"en": "English", "fr": "Français"}[l])
		list.free()
	I18n.use("en")


## The language shown is pressed and ticked, and only it.
func test_the_language_shown_is_marked() -> void:
	I18n.use("fr")
	var list := _list()
	assert_true(list.button("fr").button_pressed)
	assert_true(list.button("fr").icon != null)
	assert_false(list.button("en").button_pressed)
	assert_true(list.button("en").icon == null)
	assert_eq(list.current_button(), list.button("fr"))
	I18n.use("en")
	list.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)  # changed elsewhere: the mark follows
	assert_true(list.button("en").button_pressed)
	assert_false(list.button("fr").button_pressed)
	assert_eq(list.current_button(), list.button("en"))
	list.free()


## Pressing a language shows the UI in it at once and saves it for the next launch.
func test_choosing_applies_and_saves() -> void:
	_clean()
	I18n.use("en")
	var list := _list()
	var got := []
	list.chosen.connect(func(l: String): got.append(l))
	list.button("fr").pressed.emit()
	assert_eq(TranslationServer.get_locale(), "fr")
	assert_eq(UiText.t(UiText.PLAY), "Jouer")
	assert_eq(ClientSettings.load_language(PATH), "fr")
	assert_eq(I18n.start(PATH), "fr", "kept for the next launch")
	assert_eq(got, ["fr"])
	assert_true(list.button("fr").button_pressed)
	list.button("en").pressed.emit()
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(ClientSettings.load_language(PATH), "en")
	list.free()
	_clean()


## Choosing the language shown already saves it too: an explicit choice beats the system's next time.
func test_choosing_the_language_shown_saves_it() -> void:
	_clean()
	I18n.use("en")
	var list := _list()
	list.button("en").pressed.emit()
	assert_eq(ClientSettings.load_language(PATH), "en")
	list.free()
	_clean()


## The screen: a title, the languages, Retour. The focus starts on the language shown; up and down go
## round the languages and Retour; Retour says so.
func test_screen_focus_and_back() -> void:
	I18n.use("fr")
	var screen := LanguageScreen.new(null, PATH)
	var list := screen.list()
	assert_eq(screen.first_focus(), list.button("fr"))
	var en := list.button("en")
	var fr := list.button("fr")
	var back := screen.back_button()
	assert_eq(en.get_node(en.focus_neighbor_bottom), fr)
	assert_eq(fr.get_node(fr.focus_neighbor_bottom), back)
	assert_eq(back.get_node(back.focus_neighbor_bottom), en)
	assert_eq(en.get_node(en.focus_neighbor_top), back)
	assert_eq(back.get_node(back.focus_neighbor_top), fr)
	assert_eq(back.text, UiText.BACK)
	var backs := []
	screen.back_pressed.connect(func(): backs.append(1))
	back.pressed.emit()
	assert_eq(backs, [1])
	I18n.use("en")
	assert_eq(screen.first_focus(), en, "after a change, the focus goes to the new language")
	screen.free()


## The title's Langue button opens the screen; Retour goes back with the focus on Langue. Opened
## again, the screen gives the focus to the language shown.
func test_title_language_button_opens_the_screen() -> void:
	I18n.use("en")
	var ui: CanvasLayer = LoginUi.new()
	ui._build()
	assert_true(ui.has_screen(LoginUi.LANGUAGE_SCREEN))
	assert_eq(LoginUi.screen_for("language"), LoginUi.LANGUAGE_SCREEN)
	ui._title.button("language").pressed.emit()
	assert_eq(ui.top_screen(), LoginUi.LANGUAGE_SCREEN)
	var screen: Control = ui._screens[LoginUi.LANGUAGE_SCREEN]
	assert_eq(ui._focus_next, screen.list().button("en"))
	I18n.use("fr")
	screen.list().notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	ui._show_top(false)
	assert_eq(ui._focus_next, screen.list().button("fr"))
	screen.back_button().pressed.emit()
	assert_eq(ui.top_screen(), LoginUi.ROOT_SCREEN)
	assert_eq(ui._focus_next, ui._title.button("language"))
	assert_eq(LoginUi.title_button_after_back(LoginUi.LANGUAGE_SCREEN), "language")
	assert_eq(LoginUi.escape_action(["title", LoginUi.LANGUAGE_SCREEN]), LoginUi.ESCAPE_BACK)
	ui.free()
	I18n.use("en")


## The settings menu has a Langue tab with the same choice, saved where the menu keeps its settings.
func test_settings_language_tab() -> void:
	_clean()
	I18n.use("en")
	var ids := []
	for t in SettingsMenu.TABS:
		ids.append(t["id"])
	assert_true("language" in ids, str(ids))
	var menu: CanvasLayer = SettingsMenu.new()
	menu.settings_path = PATH
	menu._build()
	var list: LanguageList = menu.language_list()
	assert_true(menu._tab_pages["language"] == list)
	assert_eq(menu._tab_buttons["language"].text, UiText.LANGUAGE)
	assert_eq(list.locales(), I18n.available())
	list.button("fr").pressed.emit()
	assert_eq(TranslationServer.get_locale(), "fr")
	assert_eq(ClientSettings.load_language(PATH), "fr")
	assert_eq(menu._tab_buttons["language"].atr(UiText.LANGUAGE), "Langue")
	menu.free()
	I18n.use("en")
	_clean()


## A name refused by the server is said again in the new language.
func test_refused_name_follows_a_language_change() -> void:
	I18n.use("fr")
	var start: CanvasLayer = LoginUi.new()
	start._build()
	start._show_hint(func(): return UiText.rejection("taken", "Testeur"))
	assert_eq(start._hint.text, "Le nom Testeur est déjà en jeu. Choisis-en un autre.")
	I18n.use("en")
	start.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_eq(start._hint.text, "The name Testeur is already in the game. Pick another one.")
	start.free()
