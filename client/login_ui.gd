## Name prompt shown until the server welcomes us.
extends CanvasLayer

var client: Node  ## client/client.gd
var _name_edit := LineEdit.new()
var _button := Button.new()
var _status := Label.new()
var _panel := PanelContainer.new()


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "autoaigame"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = Protocol.NAME_MAX_LEN
	_name_edit.custom_minimum_size = Vector2(220, 0)
	_name_edit.text_submitted.connect(func(_t): _submit())
	box.add_child(_name_edit)
	_button.text = "Join"
	_button.pressed.connect(_submit)
	box.add_child(_button)
	_status.text = "Connecting…"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(220, 0)
	box.add_child(_status)
	client.welcomed.connect(func(_c): visible = false)
	client.join_rejected.connect(func(reason): _status.text = reason; _button.disabled = false)
	client.connection_lost.connect(func(): visible = true; _status.text = "Connection lost. Reload the page.")
	multiplayer.connected_to_server.connect(func(): _status.text = "Enter a name to play.")
	_name_edit.grab_focus()


func _submit() -> void:
	var problem := Protocol.validate_name(_name_edit.text)
	if problem != "":
		_status.text = problem
		return
	_button.disabled = true
	_status.text = "Joining…"
	client.join_with(_name_edit.text)
