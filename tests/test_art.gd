extends TestCase

## The art is drawn at 4x the original 32x16 tile / 16x24 character size.


func test_tiles_are_high_resolution() -> void:
	assert_eq(IsoLayer.TILE_SIZE, Vector2i(128, 64))


func test_tiles_atlas_matches_tile_size() -> void:
	var tex: Texture2D = load("res://assets/tiles.png")
	assert_eq(tex.get_height(), IsoLayer.TILE_SIZE.y)
	assert_eq(tex.get_width() % IsoLayer.TILE_SIZE.x, 0)
	assert_eq(tex.get_width() / IsoLayer.TILE_SIZE.x, 3, "one tile per MapData.TILE_*")


func test_player_frames_are_high_resolution() -> void:
	var tex: Texture2D = load("res://assets/player.png")
	# 4 directions x 2 walk frames of 64x96
	assert_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(64 * 4, 96 * 2))
