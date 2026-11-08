extends TestCase

## The tree sprites assembled from PixelLab pieces (art/tree_assembler.gd, assets/objects/oak_NN,
## birch_NN, fir_NN): their colours, their anchors, and that they are what the assembler draws.

const ASSEMBLER := preload("res://art/tree_assembler.gd")
const SHADOWS := preload("res://art/object_shadows.gd")


## Every sprite of the tree species (data/objects oak, birch, pine): [file, anchor_px].
func _tree_sprites() -> Array:
	var out := []
	for id in ["oak", "birch", "pine"]:
		for sp in WorldData.object(WorldData.object_index(id))["sprites"]:
			out.append([sp["file"], Vector2i(sp["anchor_px"])])
	return out


## The raw PNG, as committed (not through the importer, which recolours transparent pixels).
func _raw(file: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(file))
	img.convert(Image.FORMAT_RGBA8)
	return img


## Each species lists between 15 and 20 sprites: every variant the assembler draws, in order (and
## the young tree drawn by hand).
func test_each_species_has_its_variants() -> void:
	for id in ["oak", "birch", "pine"]:
		var sprites: Array = WorldData.object(WorldData.object_index(id))["sprites"]
		assert_true(sprites.size() >= 15 and sprites.size() <= 20, "%s: %d sprites" % [id, sprites.size()])
	for species in ASSEMBLER.SPECIES:
		var spec: Dictionary = ASSEMBLER.SPECIES[species]
		var listed := 0
		for sp in WorldData.object(WorldData.object_index(spec["data"]))["sprites"]:
			if ASSEMBLER.parse_name(sp["file"]) == [species, listed]:
				listed += 1
		assert_eq(listed, int(spec["variants"]), species + ": every variant listed, in order")


## Every pixel is fully transparent, one of the kit's 40 colours and opaque, or the ground shadow
## (its one colour, at its two alphas, give or take the rounding of 8-bit alpha).
func test_tree_pixels_are_kit_colours_or_shadow() -> void:
	var kit := ASSEMBLER.ramps()
	assert_eq(kit.size(), 40, "the kit has 40 colours")
	var shadow_rgb := SHADOWS.SHADOW_RGB.to_rgba32() >> 8
	var shadow_alphas := [Color(SHADOWS.SHADOW_RGB, SHADOWS.OUTER_ALPHA).a8, Color(SHADOWS.SHADOW_RGB, SHADOWS.CONTACT_ALPHA).a8]
	for e in _tree_sprites():
		var file: String = e[0]
		var data := _raw(file).get_data()
		var bad := 0
		for i in range(0, data.size(), 4):
			var a := data[i + 3]
			if a == 0:
				continue
			var rgb := (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
			if a == 255:
				if not kit.has(rgb):
					bad += 1
			elif rgb != shadow_rgb or (absi(a - shadow_alphas[0]) > 1 and absi(a - shadow_alphas[1]) > 1):
				bad += 1
		assert_eq(bad, 0, "%s: pixels outside the kit or the shadow" % file)


## The committed PNGs and their anchors are what the assembler draws for their seed: change
## art/tree_assembler.gd or its pieces, then run it.
func test_trees_match_the_assembler() -> void:
	for e in _tree_sprites():
		var name: String = (e[0] as String).get_file()
		var which := ASSEMBLER.parse_name(name)
		if which.is_empty():
			continue
		var t := ASSEMBLER.assemble(which[1], which[0])
		var drawn: Image = t["image"]
		var file := _raw(e[0])
		assert_eq(file.get_size(), drawn.get_size(), name)
		assert_true(file.get_data() == drawn.get_data(), "%s is out of date: run art/tree_assembler.gd" % name)
		assert_eq(e[1], t["anchor"], name + ": anchor_px")
		assert_eq(SHADOWS.RADII.get(name), t["radii"], name + ": radii in art/object_shadows.gd")


## The anchor is the foot of the trunk: opaque within 2 px of it and the trunk 10 px above it, and
## nothing opaque more than a few pixels below.
func test_anchor_is_the_foot_of_the_trunk() -> void:
	for e in _tree_sprites():
		var file: String = e[0]
		var img := _raw(file)
		var a: Vector2i = e[1]
		var near := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				near = near or img.get_pixel(a.x + dx, a.y + dy).a8 == 255
		assert_true(near, "%s: opaque at the anchor %s" % [file, a])
		assert_eq(img.get_pixel(a.x, a.y - 10).a8, 255, "%s: trunk above the anchor" % file)
		var lowest := -1
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a8 == 255:
					lowest = y
		assert_true(lowest - a.y <= 8, "%s: opaque down to row %d, anchor at %d" % [file, lowest, a.y])


## Same seed, same tree; another seed, another tree.
func test_assembly_is_a_function_of_the_seed() -> void:
	for species in ASSEMBLER.SPECIES:
		var a: Image = ASSEMBLER.assemble(3, species)["image"]
		var b: Image = ASSEMBLER.assemble(3, species)["image"]
		var c: Image = ASSEMBLER.assemble(4, species)["image"]
		assert_true(a.get_data() == b.get_data(), species + ": same seed")
		assert_true(a.get_size() != c.get_size() or a.get_data() != c.get_data(), species + ": other seed")
