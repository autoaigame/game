extends TestCase

## Slow tint of the ground over the world (client/ground_tint.gdshader, data/biomes.json "ground_tint").


func test_material_follows_the_settings() -> void:
	var m := ChunkView.tint_material({"enabled": true, "amount": 0.05, "scale": 30, "warmth": 0.25})
	assert_true(m != null and m.shader != null)
	if m == null:
		return
	assert_almost(m.get_shader_parameter("amount"), 0.05, 1e-6)
	assert_almost(m.get_shader_parameter("warmth"), 0.25, 1e-6)
	# a feature spans `scale` cells: in world pixels, scale tile widths
	assert_almost(m.get_shader_parameter("scale_px"), 30.0 * IsoLayer.TILE_SIZE.x, 1e-3)


func test_disabled_or_missing_means_no_material() -> void:
	assert_eq(ChunkView.tint_material({"enabled": false, "amount": 0.06, "scale": 40}), null)
	assert_eq(ChunkView.tint_material({}), null)


func test_amount_is_capped() -> void:
	var m := ChunkView.tint_material({"enabled": true, "amount": 0.5, "scale": 40})
	assert_true(m.get_shader_parameter("amount") <= ChunkView.TINT_MAX_AMOUNT)


## With the shipped data, every ground layer of a chunk carries the tint, and only ground layers.
func test_ground_layers_carry_the_tint() -> void:
	var settings: Dictionary = WorldData.gen().get("ground_tint", {})
	assert_true(settings.get("enabled", false), "ground_tint should be on in data/biomes.json")
	assert_almost(float(settings.get("amount", 0.0)), 0.06, 1e-6)
	var node := ChunkView.build(Vector2i(0, 0), null)
	var layers := node.get_children().filter(func(n): return n is TileMapLayer)
	assert_true(layers.size() > 0)
	for layer: TileMapLayer in layers:
		assert_true(layer.material is ShaderMaterial, layer.name)
	for sp in node.get_children().filter(func(n): return n is Sprite2D):
		assert_true(sp.material == null, "objects are not tinted")
	node.free()
