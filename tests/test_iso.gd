extends TestCase

const CELLS := [Vector2i(0, 0), Vector2i(16, 16), Vector2i(3, 27), Vector2i(31, 0), Vector2i(10, 5)]


func test_map_local_round_trip() -> void:
	var layer: TileMapLayer = IsoLayer.new_layer(null)
	for c in CELLS:
		assert_eq(layer.local_to_map(layer.map_to_local(c)), c, str(c))
	layer.free()


func test_cell_to_local_matches_tilemap() -> void:
	var layer: TileMapLayer = IsoLayer.new_layer(null)
	for c in CELLS:
		assert_eq(IsoLayer.cell_to_local(Vector2(c)), layer.map_to_local(c), str(c))
	layer.free()


func test_cell_to_local_interpolates() -> void:
	var a := IsoLayer.cell_to_local(Vector2(4, 4))
	var b := IsoLayer.cell_to_local(Vector2(5, 4))
	assert_eq(IsoLayer.cell_to_local(Vector2(4.5, 4)), (a + b) / 2.0)
