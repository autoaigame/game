extends TestCase

## The Crédits screen of the start menu (client/credits_screen.gd).

const CreditsScreen := preload("res://client/credits_screen.gd")

const DATA := {
	"people": [{"name": "M3t4Data", "files": 3, "kinds": {"objects": 2, "sounds": 1}, "licenses": ["CC0-1.0"]}],
	"third_party": [{"name": "Quaternius", "files": 1, "kinds": {"character": 1}, "licenses": ["CC0-1.0"],
			"sources": ["kit-page"]}],
	"tools": ["Blender", "PixelLab"],
	"licenses": ["CC0-1.0"],
}


func _text(lines: Array) -> String:
	var parts := []
	for l in lines:
		parts.append(l["text"])
	return "\n".join(parts)


## The screen says the game is built from voted pull requests, then credits each author with what they
## made and its licence, each third party with its source, and names each tool once.
func test_lines_credit_people_third_parties_and_tools() -> void:
	var text := _text(CreditsScreen.lines(DATA))
	assert_true(text.begins_with(UiText.CREDITS_COMMUNITY), text)
	for want in ["M3t4Data", "Quaternius", "kit-page", UiText.CREDITS_KINDS["objects"],
			UiText.CREDITS_KINDS["character"], UiText.CREDITS_LICENSES["CC0-1.0"], UiText.CREDITS_PEOPLE,
			UiText.CREDITS_THIRD_PARTY, UiText.CREDITS_TOOLS]:
		assert_true(text.contains(want), want)
	assert_eq(text.count("PixelLab"), 1)
	assert_eq(text.count("Blender"), 1)


func test_community_sentence_is_in_french() -> void:
	assert_true(UiText.CREDITS_COMMUNITY.contains("vot"), UiText.CREDITS_COMMUNITY)
	assert_eq(UiText.CREDITS, "Crédits")


## An unknown kind or licence shows as it is rather than vanishing.
func test_unknown_words_show_as_they_are() -> void:
	var data := DATA.duplicate(true)
	data["people"][0]["kinds"] = {"newkind": 1}
	data["people"][0]["licenses"] = ["LicenseRef-New"]
	var text := _text(CreditsScreen.lines(data))
	assert_true(text.contains("newkind"), text)
	assert_true(text.contains("LicenseRef-New"), text)


## Without data given, the screen reads the game's ASSETS.toml when it first shows, not before.
func test_screen_reads_assets_toml_when_it_opens() -> void:
	var screen := CreditsScreen.new()
	screen.visible = false
	assert_eq(screen.body_text(), "")
	screen.visible = true
	assert_true(screen.body_text().contains(UiText.CREDITS_PEOPLE), screen.body_text())
	assert_true(screen.body_text().contains("M3t4Data"), screen.body_text())
	screen.free()


## The text scrolls with up and down (keys, pad's d-pad or stick); past the bottom, the focus goes to Retour.
func test_scroll_step() -> void:
	assert_eq(CreditsScreen.scroll_step(0, 300, 40, 1), 40)
	assert_eq(CreditsScreen.scroll_step(280, 300, 40, 1), 300)
	assert_eq(CreditsScreen.scroll_step(300, 300, 40, 1), CreditsScreen.LEAVE)
	assert_eq(CreditsScreen.scroll_step(20, 300, 40, -1), 0)
	assert_eq(CreditsScreen.scroll_step(0, 300, 40, -1), 0)
	assert_eq(CreditsScreen.scroll_step(0, 0, 40, 1), CreditsScreen.LEAVE)


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func test_down_and_up_scroll_the_text() -> void:
	var screen := CreditsScreen.new(DATA)
	var bar := screen.scroll().get_v_scroll_bar()
	bar.max_value = 500
	bar.page = 100
	# through the text's own input, as a key, the d-pad or the stick sends it
	screen.scroll().gui_input.emit(_action("ui_down"))
	assert_eq(screen.scroll().scroll_vertical, CreditsScreen.STEP)
	screen.scroll().gui_input.emit(_action("ui_page_down"))
	assert_eq(screen.scroll().scroll_vertical, CreditsScreen.STEP + 100)
	screen.scroll().gui_input.emit(_action("ui_up"))
	assert_eq(screen.scroll().scroll_vertical, 100)
	assert_false(screen.scroll_input(_action("ui_accept")))
	screen.free()


## The text takes the focus first; Tab and the arrows go between it and Retour; Retour says so.
func test_focus_and_back_button() -> void:
	var screen := CreditsScreen.new(DATA)
	var scroll := screen.scroll()
	var back := screen.back_button()
	assert_eq(screen.first_focus(), scroll)
	assert_eq(scroll.focus_mode, Control.FOCUS_ALL)
	assert_eq(back.text, UiText.BACK)
	for side in ["focus_next", "focus_previous", "focus_neighbor_bottom", "focus_neighbor_top"]:
		assert_eq(scroll.get_node_or_null(scroll.get(side)), back, "scroll %s" % side)
		assert_eq(back.get_node_or_null(back.get(side)), scroll, "back %s" % side)
	var got := []
	screen.back_pressed.connect(func(): got.append(true))
	back.pressed.emit()
	assert_eq(got, [true])
	screen.free()



## Down held at the end of the text stays on it; a new press goes on to Retour.
func test_held_down_stays_on_the_text() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_DOWN
	e.pressed = true
	assert_true(CreditsScreen.leaves(e))
	e.echo = true
	assert_false(CreditsScreen.leaves(e))
	var stick := InputEventJoypadMotion.new()  # a held stick sends no echo
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 1.0
	assert_false(CreditsScreen.leaves(stick))


## The text shows the kit's focus frame while it has the focus, and none otherwise.
func test_text_shows_a_focus_frame() -> void:
	var screen := CreditsScreen.new(DATA)
	var holder: PanelContainer = screen.scroll().get_parent()
	assert_true(holder.get_theme_stylebox("panel") is StyleBoxEmpty)
	screen.scroll().focus_entered.emit()
	assert_true(holder.get_theme_stylebox("panel") is StyleBoxTexture or holder.get_theme_stylebox("panel") is StyleBoxFlat)
	screen.scroll().focus_exited.emit()
	assert_true(holder.get_theme_stylebox("panel") is StyleBoxEmpty)
	screen.free()
