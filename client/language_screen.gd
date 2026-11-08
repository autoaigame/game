## The start menu's Langue screen: one button per language (client/language_list.gd), then Retour.
## Choosing a language shows the menu in it at once and keeps the choice; the screen stays, with the
## focus on the language chosen. Retour, Escape and a pad's B go back (client/login_ui.gd).
extends PanelContainer

signal back_pressed

const LanguageList := preload("res://client/language_list.gd")

var _list: LanguageList
var _back := Button.new()


func _init(sounds: Node = null, settings_path := ClientSettings.PATH) -> void:
	custom_minimum_size = Vector2(300, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = UiText.LANGUAGE
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_list = LanguageList.new()
	_list.sounds = sounds
	_list.settings_path = settings_path
	box.add_child(_list)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(gap)
	_back.text = UiText.BACK
	_back.custom_minimum_size = Vector2(0, 36)
	_back.theme_type_variation = "TabButton"
	_back.pressed.connect(func(): back_pressed.emit())
	_back.mouse_entered.connect(func(): if sounds != null: sounds.ui("hover"))
	_back.button_down.connect(func(): if sounds != null: sounds.ui("click"))
	box.add_child(_back)
	# up and down go round the languages and Retour
	var order: Array = []
	for l in _list.locales():
		order.append(_list.button(l))
	order.append(_back)
	for i in order.size():
		var b: Control = order[i]
		var up: Control = order[i - 1]
		var down: Control = order[(i + 1) % order.size()]
		b.focus_neighbor_top = b.get_path_to(up)
		b.focus_previous = b.get_path_to(up)
		b.focus_neighbor_bottom = b.get_path_to(down)
		b.focus_next = b.get_path_to(down)


## The language shown now takes the focus when the screen opens.
func first_focus() -> Control:
	var b := _list.current_button()
	return b if b != null else _back


func list() -> LanguageList:
	return _list


func back_button() -> Button:
	return _back
