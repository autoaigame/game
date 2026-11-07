## In-game HUD, shown once joined: the hunger bar (bottom left), with a warning when starving.
## Values come from the server (status message); the HUD only shows them.
extends CanvasLayer

const HUNGER_MAX := 100.0
const BAR_SIZE := Vector2(160, 14)
const FULL := Color8(0xb8, 0x8a, 0x4a)
const EMPTY := Color8(0x2e, 0x28, 0x22, 0xc0)

var client: Node  ## client/client.gd

var _bar: ProgressBar
var _starving: Label


func _ready() -> void:
	layer = 5
	visible = false
	_build()
	client.welcomed.connect(func(_cell: Vector2i): visible = true)
	client.status_received.connect(_on_status)


func hunger_bar() -> ProgressBar:
	return _bar


func starving_label() -> Label:
	return _starving


func _on_status(status: Dictionary) -> void:
	if not status.has("hunger"):
		return
	_bar.value = float(status["hunger"])
	_starving.visible = _bar.value <= 0.0


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(16, -64)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var label := Label.new()
	label.text = UiText.HUNGER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	box.add_child(label)
	_bar = ProgressBar.new()
	_bar.max_value = HUNGER_MAX
	_bar.value = HUNGER_MAX
	_bar.show_percentage = false
	_bar.custom_minimum_size = BAR_SIZE
	_bar.add_theme_stylebox_override("fill", _flat(FULL))
	_bar.add_theme_stylebox_override("background", _flat(EMPTY))
	box.add_child(_bar)
	_starving = Label.new()
	_starving.text = UiText.STARVING
	_starving.visible = false
	_starving.add_theme_color_override("font_color", Color8(0xd9, 0x8a, 0x6a))
	_starving.add_theme_color_override("font_outline_color", Color.BLACK)
	_starving.add_theme_constant_override("outline_size", 4)
	box.add_child(_starving)


static func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(2)
	return s
