extends TestCase


## These tests check French words: the UI is shown in French whatever the system's language.
func _init() -> void:
	I18n.use("fr")


## The menu accepts exactly the names the server accepts.
func test_name_problem_agrees_with_protocol() -> void:
	for n in ["Henri", "a_b-9", "", "abcdefghijklmnopq", "abcdefghijklmnop", "a b", "é", "x!"]:
		assert_eq(UiText.name_problem(n) == "", Protocol.validate_name(n) == "", n)


func test_name_problems_are_in_french() -> void:
	assert_eq(UiText.name_problem(""), "Écris un nom pour entrer.")
	assert_eq(UiText.name_problem("abcdefghijklmnopq"), "%d caractères au plus." % Protocol.NAME_MAX_LEN)
	assert_eq(UiText.name_problem("a b"), "Lettres, chiffres, _ et - seulement.")


## A locally valid name can only be refused because it is online already.
func test_rejection_of_a_valid_name_says_it_is_taken() -> void:
	assert_eq(UiText.rejection("Someone named ann is already playing.", "ann"), "Le nom ann est déjà en jeu. Choisis-en un autre.")


func test_rejection_of_an_invalid_name_shows_its_problem() -> void:
	assert_eq(UiText.rejection("whatever", "a b"), "Lettres, chiffres, _ et - seulement.")
