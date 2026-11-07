## The one Theme of the client UI. Uses the pixel art in assets/ui/ when present (9-slice
## StyleBoxTexture, nearest filter), flat boxes in the same colours otherwise.
class_name UiTheme
extends RefCounted

const DIR := "res://assets/ui/"
const TEXT_LIGHT := Color8(0xd3, 0xcc, 0xb7)
const TEXT_DARK := Color8(0x2e, 0x28, 0x22)
const TEXT_DIM := Color8(0x93, 0x8f, 0x84)
const FONT_SIZE := 16
const TITLE_SIZE := 26
## The title band art is made to be shown exactly this high (its torn ends do not tile vertically).
const TITLE_BAND_H := 40
const BUTTON_SIZE := 20

## file -> [margin left, top, right, bottom], content padding added inside.
const SLICES := {
	"panel": [16, 16, 16, 16],
	"button_normal": [8, 8, 8, 8],
	"button_hover": [8, 8, 8, 8],
	"button_pressed": [8, 8, 8, 8],
	"button_disabled": [8, 8, 8, 8],
	"focus": [8, 8, 8, 8],
	"field_normal": [6, 6, 6, 6],
	"field_focus": [6, 6, 6, 6],
	"title_band": [24, 8, 24, 8],
}
const FLAT := {
	"panel": [Color8(0x3b, 0x45, 0x30), Color8(0x51, 0x43, 0x3a)],
	"button_normal": [Color8(0x5d, 0x5c, 0x55), Color8(0x2e, 0x28, 0x22)],
	"button_hover": [Color8(0x77, 0x75, 0x6c), Color8(0x2e, 0x28, 0x22)],
	"button_pressed": [Color8(0x44, 0x44, 0x3f), Color8(0x2e, 0x28, 0x22)],
	"button_disabled": [Color8(0x4d, 0x56, 0x38), Color8(0x44, 0x44, 0x3f)],
	"focus": [Color(0, 0, 0, 0), TEXT_LIGHT],
	"field_normal": [Color8(0xbd, 0xb5, 0x9f), Color8(0x54, 0x48, 0x3a)],
	"field_focus": [Color8(0xd3, 0xcc, 0xb7), Color8(0x54, 0x48, 0x3a)],
	"title_band": [Color8(0xa3, 0x9b, 0x86), Color8(0x6a, 0x5c, 0x49)],
}


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT_LIGHT)
	t.set_stylebox("panel", "PanelContainer", box("panel", 20))
	t.set_stylebox("normal", "Button", box("button_normal", 12))
	t.set_stylebox("hover", "Button", box("button_hover", 12))
	t.set_stylebox("pressed", "Button", box("button_pressed", 12, 2))
	t.set_stylebox("hover_pressed", "Button", box("button_pressed", 12, 2))
	t.set_stylebox("disabled", "Button", box("button_disabled", 12))
	t.set_stylebox("focus", "Button", box("focus", 0))
	t.set_font_size("font_size", "Button", BUTTON_SIZE)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color"]:
		t.set_color(c, "Button", TEXT_LIGHT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_constant("outline_size", "Button", 4)
	t.set_color("font_outline_color", "Button", TEXT_DARK)
	t.set_stylebox("normal", "LineEdit", box("field_normal", 8))
	t.set_stylebox("read_only", "LineEdit", box("field_normal", 8))
	t.set_stylebox("focus", "LineEdit", box("focus", 0))
	t.set_color("font_color", "LineEdit", TEXT_DARK)
	t.set_color("font_uneditable_color", "LineEdit", Color8(0x54, 0x48, 0x3a))
	t.set_color("font_placeholder_color", "LineEdit", Color8(0x6a, 0x5c, 0x49))
	t.set_color("caret_color", "LineEdit", TEXT_DARK)
	t.set_color("selection_color", "LineEdit", Color8(0x8d, 0x90, 0x64))
	t.set_font_size("font_size", "LineEdit", 18)
	t.set_type_variation("TitleBand", "PanelContainer")
	var band := box("title_band", 10)
	band.content_margin_top = 2
	band.content_margin_bottom = 2
	t.set_stylebox("panel", "TitleBand", band)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", TITLE_SIZE)
	t.set_color("font_color", "TitleLabel", TEXT_DARK)
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 14)
	t.set_color("font_color", "HintLabel", TEXT_DIM)
	t.set_type_variation("ErrorLabel", "Label")
	t.set_color("font_color", "ErrorLabel", Color8(0xc0, 0x95, 0x76))
	t.set_type_variation("TaglineLabel", "Label")
	t.set_constant("outline_size", "TaglineLabel", 6)
	t.set_color("font_outline_color", "TaglineLabel", TEXT_DARK)
	_settings_controls(t)
	return t


## Sliders, check boxes and tab buttons of the settings menu, from the same boxes and colours.
static func _settings_controls(t: Theme) -> void:
	var track := box("field_normal", 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color8(0x8d, 0x90, 0x64)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := fill.duplicate()
	fill_hi.bg_color = Color8(0xa8, 0xab, 0x77)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_stylebox("focus", "HSlider", box("focus", 0))
	t.set_icon("grabber", "HSlider", square_icon(16, Color8(0x5d, 0x5c, 0x55), TEXT_DARK))
	t.set_icon("grabber_highlight", "HSlider", square_icon(16, Color8(0x77, 0x75, 0x6c), TEXT_LIGHT))
	t.set_icon("grabber_disabled", "HSlider", square_icon(16, Color8(0x44, 0x44, 0x3f), TEXT_DARK))
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", box("focus", 0))
	t.set_icon("unchecked", "CheckBox", square_icon(18, Color8(0xbd, 0xb5, 0x9f), Color8(0x54, 0x48, 0x3a)))
	t.set_icon("checked", "CheckBox", square_icon(18, Color8(0xbd, 0xb5, 0x9f), Color8(0x54, 0x48, 0x3a), TEXT_DARK))
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_font_size("font_size", "CheckBox", FONT_SIZE)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "CheckBox", TEXT_LIGHT)
	t.set_type_variation("TabButton", "Button")
	t.set_font_size("font_size", "TabButton", FONT_SIZE)
	t.set_stylebox("pressed", "TabButton", box("button_hover", 10))
	t.set_stylebox("hover_pressed", "TabButton", box("button_hover", 10))


## A square `size` px icon: `fill` inside a 2 px `border`, and a `mark` square in the middle if given.
static func square_icon(size: int, fill: Color, border: Color, mark := Color(0, 0, 0, 0)) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(border)
	img.fill_rect(Rect2i(2, 2, size - 4, size - 4), fill)
	if mark.a > 0.0:
		img.fill_rect(Rect2i(5, 5, size - 10, size - 10), mark)
	return ImageTexture.create_from_image(img)


## The style for `key`: its 9-slice PNG if it exists, a flat box otherwise. `pad` is the room
## between the border and the content; `shift` moves the content down (pressed button).
static func box(key: String, pad: int, shift := 0) -> StyleBox:
	var path: String = DIR + key + ".png"
	var m: Array = SLICES[key]
	var sb: StyleBox
	if ResourceLoader.exists(path):
		var st := StyleBoxTexture.new()
		st.texture = load(path)
		st.texture_margin_left = m[0]
		st.texture_margin_top = m[1]
		st.texture_margin_right = m[2]
		st.texture_margin_bottom = m[3]
		st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb = st
	else:
		var flat := StyleBoxFlat.new()
		var colors: Array = FLAT[key]
		flat.bg_color = colors[0]
		flat.border_color = colors[1]
		flat.set_border_width_all(2 if key != "focus" else 3)
		flat.draw_center = key != "focus"
		if key == "focus":
			flat.expand_margin_left = 3
			flat.expand_margin_right = 3
			flat.expand_margin_top = 3
			flat.expand_margin_bottom = 3
		sb = flat
	if pad > 0:
		sb.content_margin_left = m[0] + pad - 4
		sb.content_margin_right = m[2] + pad - 4
		sb.content_margin_top = m[1] + shift
		sb.content_margin_bottom = m[3] - shift
	return sb


## The status icon `key` ("wait", "ok" or "error"), or null if its PNG is missing.
static func icon(key: String) -> Texture2D:
	var path: String = DIR + "icon_" + key + ".png"
	return load(path) if ResourceLoader.exists(path) else null
