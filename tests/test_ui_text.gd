extends TestCase


## The menu accepts exactly the names the server accepts.
func test_name_problem_agrees_with_protocol() -> void:
	for n in ["Henri", "a_b-9", "", "abcdefghijklmnopq", "abcdefghijklmnop", "a b", "é", "x!"]:
		assert_eq(UiText.name_problem(n) == "", Protocol.validate_name(n) == "", n)


func test_name_problems_are_in_french() -> void:
	assert_eq(UiText.name_problem(""), UiText.NAME_EMPTY)
	assert_eq(UiText.name_problem("abcdefghijklmnopq"), UiText.NAME_TOO_LONG % Protocol.NAME_MAX_LEN)
	assert_eq(UiText.name_problem("a b"), UiText.NAME_BAD_CHARS)


## A locally valid name can only be refused because it is online already.
func test_rejection_of_a_valid_name_says_it_is_taken() -> void:
	assert_eq(UiText.rejection("Someone named ann is already playing.", "ann"), UiText.NAME_TAKEN % "ann")


func test_rejection_of_an_invalid_name_shows_its_problem() -> void:
	assert_eq(UiText.rejection("whatever", "a b"), UiText.NAME_BAD_CHARS)
