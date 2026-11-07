## In game, key C opens the character editor at the left of the screen; every change is worn at once and
## seen by the other players. Not while the settings menu is open or a text field has the keys.
extends CanvasLayer

var client: Node  ## client/client.gd
var menu: Node  ## client/settings_menu.gd, or null
var _panel := PanelContainer.new()
var _editor: LookEditor


## C pressed (not a repeat).
static func is_toggle(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C


func _ready() -> void:
	layer = 9
	_panel.theme = UiTheme.build()
	_panel.position = Vector2(12, 60)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var hint := Label.new()
	hint.text = UiText.LOOK_TITLE
	hint.theme_type_variation = "HintLabel"
	box.add_child(hint)
	_editor = LookEditor.new(client.look, false)
	_editor.look_changed.connect(func(l: Array): client.set_look(l))
	box.add_child(_editor)


func is_open() -> bool:
	return _panel.visible


func _unhandled_input(event: InputEvent) -> void:
	if client.my_peer_id == 0 or not is_toggle(event) or (menu != null and menu.is_open()):
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_editor.set_look(client.look)
	get_viewport().set_input_as_handled()
