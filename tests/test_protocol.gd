extends TestCase


func test_valid_name() -> void:
	assert_eq(Protocol.validate_name("Henri"), "")
	assert_eq(Protocol.validate_name("a_b-9"), "")


func test_invalid_names() -> void:
	for bad in ["", "abcdefghijklmnopq", "a b", "é"]:
		assert_true(Protocol.validate_name(bad) != "", "should reject %s" % bad)
