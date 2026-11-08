extends TestCase

const Client := preload("res://client/client.gd")


func test_name_is_read_from_the_query() -> void:
	assert_eq(Client.name_from_query("?name=screenshot-bot"), "screenshot-bot")
	assert_eq(Client.name_from_query("?x=1&name=Corbeau_42&y=2"), "Corbeau_42")
	assert_eq(Client.name_from_query("name=ann"), "ann", "without the leading ?")


func test_name_is_url_decoded() -> void:
	assert_eq(Client.name_from_query("?name=%61nn"), "ann")


func test_no_name_gives_an_empty_name() -> void:
	assert_eq(Client.name_from_query(""), "")
	assert_eq(Client.name_from_query("?"), "")
	assert_eq(Client.name_from_query("?commit=abc"), "")
	assert_eq(Client.name_from_query("?name="), "")
	assert_eq(Client.name_from_query("?name"), "")
	assert_eq(Client.name_from_query("?username=ann"), "", "only the exact key")


## A name the server would refuse is ignored, so the start menu shows as usual.
func test_invalid_name_is_ignored() -> void:
	assert_eq(Client.name_from_query("?name=a+b"), "")
	assert_eq(Client.name_from_query("?name=a%20b"), "")
	assert_eq(Client.name_from_query("?name=%3Cscript%3E"), "")
	assert_eq(Client.name_from_query("?name=" + "x".repeat(Protocol.NAME_MAX_LEN + 1)), "")


## The first name wins when the key is repeated.
func test_first_name_wins() -> void:
	assert_eq(Client.name_from_query("?name=ann&name=bob"), "ann")


## The page is told the world is ready once the player joined and the 3 x 3 chunks around them, which
## cover the screen at the default zoom, are built.
func test_world_ready_once_joined_and_the_near_chunks_built() -> void:
	var View := load("res://client/world_view.gd")
	assert_true(View.world_ready(true, 0))
	assert_false(View.world_ready(false, 0), "not joined: the chunks are the spawn's, behind the menu")
	assert_false(View.world_ready(true, 1), "a near chunk not built yet")


func test_missing_near_chunks() -> void:
	var View := load("res://client/world_view.gd")
	var cell := Vector2i(MapData.CHUNK * 3 + 5, MapData.CHUNK * -2 + 9)  # inside chunk (3, -2)
	assert_eq(View.missing_near_chunks(cell, {}), 9)
	var built := {}
	for x in range(2, 5):
		for y in range(-3, 0):
			built[Vector2i(x, y)] = true
	assert_eq(View.missing_near_chunks(cell, built), 0)
	built.erase(Vector2i(4, -1))
	built[Vector2i(5, -2)] = true  # a farther chunk does not count
	assert_eq(View.missing_near_chunks(cell, built), 1)
