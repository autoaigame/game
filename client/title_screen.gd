## The start menu's first screen: Jouer, Paramètres, Langue, Crédits, Quitter (not on the web, a tab cannot close
## itself). It only says which button was chosen; client/login_ui.gd acts on it.
extends PanelContainer

signal chosen(id: String)

var sounds: Node  ## client/sound_director.gd, or null (no sound)
var _buttons := {}  ## id -> Button
var _order: Array = []


## The ids of the buttons, top to bottom.
static func buttons(web: bool) -> Array:
	return ["play", "settings", "language", "credits"] if web else ["play", "settings", "language", "credits", "quit"]


static func label(id: String) -> String:
	return {"play": UiText.PLAY, "settings": UiText.SETTINGS, "language": UiText.LANGUAGE, "credits": UiText.CREDITS,
			"quit": UiText.QUIT}.get(id, "")


func _init(web := OS.has_feature("web")) -> void:
	custom_minimum_size = Vector2(300, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_order = buttons(web)
	for id in _order:
		var b := Button.new()
		b.text = label(id)
		b.custom_minimum_size = Vector2(0, 44 if id == "play" else 36)
		if id != "play":
			b.theme_type_variation = "TabButton"
		b.pressed.connect(func(): chosen.emit(id))
		b.mouse_entered.connect(func(): _play("hover"))
		b.button_down.connect(func(): _play("click"))
		box.add_child(b)
		_buttons[id] = b
	# up and down wrap around the list
	for i in _order.size():
		var b: Button = _buttons[_order[i]]
		var up: Button = _buttons[_order[i - 1]]
		var down: Button = _buttons[_order[(i + 1) % _order.size()]]
		b.focus_neighbor_top = b.get_path_to(up)
		b.focus_previous = b.get_path_to(up)
		b.focus_neighbor_bottom = b.get_path_to(down)
		b.focus_next = b.get_path_to(down)


## The button `id`, or null when this platform has none.
func button(id: String) -> Button:
	return _buttons.get(id)


func first_button() -> Button:
	return _buttons[_order[0]]


func _play(kind: String) -> void:
	if sounds != null:
		sounds.ui(kind)
