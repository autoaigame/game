extends TestCase

const TitleScreen := preload("res://client/title_screen.gd")


## Quitter closes a desktop game; a browser tab cannot close itself, so the web build has no Quitter.
## Crédits sits between Paramètres and Quitter.
func test_quit_only_off_the_web() -> void:
	assert_eq(TitleScreen.buttons(false), ["play", "settings", "credits", "quit"])
	assert_eq(TitleScreen.buttons(true), ["play", "settings", "credits"])


func test_buttons_are_named_in_french() -> void:
	assert_eq(TitleScreen.label("play"), UiText.PLAY)
	assert_eq(TitleScreen.label("settings"), UiText.SETTINGS)
	assert_eq(TitleScreen.label("credits"), UiText.CREDITS)
	assert_eq(TitleScreen.label("quit"), UiText.QUIT)
	assert_eq(UiText.PLAY, "Jouer")
	assert_eq(UiText.QUIT, "Quitter")


## The screen builds one button per id, Jouer first (it takes the focus).
func test_screen_builds_its_buttons_in_order() -> void:
	for web in [false, true]:
		var screen := TitleScreen.new(web)
		var ids: Array = TitleScreen.buttons(web)
		assert_eq(screen.first_button().text, UiText.PLAY, "web %s" % web)
		for id in ["play", "settings", "credits", "quit"]:
			assert_eq(screen.button(id) != null, id in ids, "%s on web %s" % [id, web])
		screen.free()


## A button press says which one, for the start menu to act on.
func test_pressing_a_button_emits_its_id() -> void:
	var screen := TitleScreen.new(false)
	var got := []
	screen.chosen.connect(func(id: String): got.append(id))
	for id in ["play", "settings", "credits", "quit"]:
		screen.button(id).pressed.emit()
	assert_eq(got, ["play", "settings", "credits", "quit"])
	screen.free()


## Up and down go round the buttons: from Crédits, up is Paramètres and down is Quitter (Jouer on the web).
func test_credits_sits_between_settings_and_quit() -> void:
	for web in [false, true]:
		var screen := TitleScreen.new(web)
		var c := screen.button("credits")
		assert_eq(c.get_node(c.focus_neighbor_top), screen.button("settings"), "web %s" % web)
		assert_eq(c.get_node(c.focus_neighbor_bottom), screen.button("play" if web else "quit"), "web %s" % web)
		screen.free()
