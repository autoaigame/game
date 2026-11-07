extends TestCase

## The character editor (client/look_editor.gd, client/look_panel.gd): rows, clicks and the C key, without
## drawing it.

const LookPanel := preload("res://client/look_panel.gd")


func _look() -> Array:
	return [{"id": "body_standard", "color": "skin_medium"}, {"id": "face_old", "color": "hair_grey"},
			{"id": "hat_cap", "color": "rust"}, {"id": "top_tshirt", "color": "grey"},
			{"id": "bottom_jeans", "color": "workwear_blue"}]


func test_row_texts_name_the_part_or_a_dash() -> void:
	assert_eq(LookEditor.part_label(_look(), "hat"), "Casquette")
	assert_eq(LookEditor.part_label(_look(), "beard"), UiText.LOOK_NONE)
	assert_eq(LookEditor.part_color(_look(), "hat"), CharacterParts.base_colour("rust"))
	assert_eq(LookEditor.part_color(_look(), "beard"), Color.TRANSPARENT)


func test_a_click_emits_the_new_valid_look() -> void:
	var ed := LookEditor.new(_look())
	var got := []
	ed.look_changed.connect(func(l): got.append(l))
	ed._change(CharacterParts.cycle_part(ed.look, "beard", 1))
	ed._change(CharacterParts.cycle_color(ed.look, "body", 1))
	assert_eq(got.size(), 2)
	for l in got:
		assert_eq(CharacterParts.validate(l), "")
	assert_true(LookEditor.part_label(got[0], "beard") != UiText.LOOK_NONE, "a beard was put on")
	assert_eq(LookEditor.part_color(got[1], "body"), CharacterParts.base_colour("skin_dark"), "next skin tone")
	ed.free()


## A start look from an older save is repaired, not thrown away.
func test_a_start_look_is_repaired() -> void:
	var ed := LookEditor.new([{"id": "body_standard", "color": "skin_deep"}, {"id": "nope", "color": "x"}])
	assert_eq(CharacterParts.validate(ed.look), "")
	assert_eq(ed.look[0], {"id": "body_standard", "color": "skin_deep"})
	ed.free()
	var ed2 := LookEditor.new([42])
	assert_eq(CharacterParts.validate(ed2.look), "", "junk: the required parts at least")
	ed2.free()


## Showing the worn look when the panel opens does not send it again.
func test_set_look_does_not_emit() -> void:
	var ed := LookEditor.new()
	var got := []
	ed.look_changed.connect(func(l): got.append(l))
	ed.set_look(_look())
	assert_eq(ed.look, _look())
	assert_eq(got.size(), 0)
	ed.free()


func test_c_opens_the_panel_only_on_a_fresh_press() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_C
	e.pressed = true
	assert_true(LookPanel.is_toggle(e))
	e.echo = true
	assert_false(LookPanel.is_toggle(e), "a repeat")
	e.echo = false
	e.pressed = false
	assert_false(LookPanel.is_toggle(e), "a release")
	e.pressed = true
	e.physical_keycode = KEY_W
	assert_false(LookPanel.is_toggle(e))


## The Silhouette row goes through the body shapes, keeping the skin colour's place in the list.
func test_silhouette_row_changes_the_body_shape() -> void:
	assert_eq(CharacterParts.slot("body")["name"], "Silhouette")
	var ed := LookEditor.new(_look())
	var seen := {}
	for i in CharacterParts.parts_for("body").size():
		ed._change(CharacterParts.cycle_part(ed.look, "body", 1))
		seen[LookEditor.part_label(ed.look, "body")] = true
		assert_eq(CharacterParts.validate(ed.look), "")
		assert_eq(LookEditor.part_color(ed.look, "body"), CharacterParts.base_colour("skin_medium"), "same skin")
	assert_eq(seen.size(), 3, "three body shapes: %s" % [seen.keys()])
	ed.free()
