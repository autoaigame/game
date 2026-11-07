extends TestCase

const LoginUi := preload("res://client/login_ui.gd")


func test_remembered_name_focuses_the_button() -> void:
	assert_eq(LoginUi.initial_focus("ann"), LoginUi.FOCUS_BUTTON)


func test_empty_name_focuses_the_field() -> void:
	assert_eq(LoginUi.initial_focus(""), LoginUi.FOCUS_FIELD)


## The button only works once the server can hear the join.
func test_button_enabled_only_when_ready() -> void:
	for s in LoginUi.State.values():
		assert_eq(LoginUi.button_enabled(s), s == LoginUi.State.READY, "state %d" % s)


## Every state carries an icon and a text, never colour alone.
func test_each_state_has_an_icon_and_a_text() -> void:
	for s in [LoginUi.State.CONNECTING, LoginUi.State.READY, LoginUi.State.JOINING, LoginUi.State.LOST]:
		var st: Array = LoginUi.status_of(s)
		assert_true(st[0] != "", "icon of %d" % s)
		assert_true(st[1] != "", "text of %d" % s)


func _key(code: Key, pressed := true, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


## The menu opens on the title screen.
func test_starts_on_the_title_screen() -> void:
	assert_eq(LoginUi.ROOT_SCREEN, "title")


## Screens stack: Jouer pushes the play screen, Retour pops it, the title screen always stays.
func test_screens_push_and_pop() -> void:
	var s: Array = LoginUi.pushed([LoginUi.ROOT_SCREEN], "play")
	assert_eq(s, ["title", "play"])
	assert_eq(LoginUi.pushed(s, "play"), ["title", "play"], "the top screen is not pushed twice")
	assert_eq(LoginUi.pushed(s, "credits"), ["title", "play", "credits"])
	assert_eq(LoginUi.popped(s), ["title"])
	assert_eq(LoginUi.popped(["title"]), ["title"], "the title screen is never popped")
	assert_eq(s, ["title", "play"], "the stack given is not changed")


## Escape opens the settings on the title screen, and goes back a screen anywhere else.
func test_escape_depends_on_the_screen() -> void:
	assert_eq(LoginUi.escape_action(["title"]), LoginUi.ESCAPE_SETTINGS)
	assert_eq(LoginUi.escape_action(["title", "play"]), LoginUi.ESCAPE_BACK)
	assert_eq(LoginUi.escape_action(["title", "play", "credits"]), LoginUi.ESCAPE_BACK)


## Escape and a pad's cancel button go back; a release, a repeat or another key do not.
func test_back_events() -> void:
	assert_true(LoginUi.is_back(_key(KEY_ESCAPE)))
	assert_false(LoginUi.is_back(_key(KEY_ESCAPE, false)))
	assert_false(LoginUi.is_back(_key(KEY_ESCAPE, true, true)))
	assert_false(LoginUi.is_back(_key(KEY_C)))
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	assert_true(LoginUi.is_back(pad), "B on a pad")
	pad.pressed = false
	assert_false(LoginUi.is_back(pad), "B released")
	pad.pressed = true
	pad.button_index = JOY_BUTTON_START
	assert_false(LoginUi.is_back(pad), "Start opens the settings")


## The settings menu lets the start menu use Escape first: on the play screen it goes back, and the
## settings stay closed.
func test_settings_let_the_start_menu_use_escape_first() -> void:
	var menu: CanvasLayer = preload("res://client/settings_menu.gd").new()
	menu.visible = false
	var seen := []
	menu.escape_first = func(e: InputEvent) -> bool:
		seen.append(e)
		return true
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	assert_true(menu.handle(pad), "the start menu used the event")
	assert_eq(seen, [pad])
	assert_false(menu.is_open())
	for n in [menu._root, menu._mute, menu._close]:  # built in _ready, which never ran
		n.free()
	menu.free()


## Closing the settings gives the focus back to the title's Paramètres button, or to the first control
## of another screen (the settings open from it with a pad's Start).
func test_focus_after_the_settings() -> void:
	assert_eq(LoginUi.focus_after_settings(["title"]), LoginUi.FOCUS_SETTINGS_BUTTON)
	assert_eq(LoginUi.focus_after_settings(["title", "play"]), LoginUi.FOCUS_FIRST)


## The connection lost in game brings the menu back on its title screen; lost before joining, the
## screen shown stays.
func test_stack_after_a_lost_connection() -> void:
	assert_eq(LoginUi.stack_after_lost(["title", "play"], true), ["title"])
	assert_eq(LoginUi.stack_after_lost(["title", "play"], false), ["title", "play"])
	assert_eq(LoginUi.stack_after_lost(["title"], true), ["title"])


## A refused name shows on the play screen, even if Retour was pressed while joining.
func test_stack_after_a_refused_name() -> void:
	assert_eq(LoginUi.stack_after_rejected(["title"]), ["title", "play"])
	assert_eq(LoginUi.stack_after_rejected(["title", "play"]), ["title", "play"])
