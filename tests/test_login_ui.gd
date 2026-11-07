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
