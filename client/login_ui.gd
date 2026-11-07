## Start menu, drawn over the world until the server welcomes us: name, one button, connection state.
## Texts are in client/ui_text.gd, looks in client/ui_theme.gd.
extends CanvasLayer

enum State { CONNECTING, READY, JOINING, LOST }
const FOCUS_FIELD := 0
const FOCUS_BUTTON := 1
const FADE_IN_S := 0.3
const FADE_OUT_S := 0.4

var client: Node  ## client/client.gd
var sounds: Node  ## client/sound_director.gd, or null (no sound)
var settings: Node  ## client/settings_menu.gd, or null
var state := State.CONNECTING
var _root := Control.new()
var _name_edit := LineEdit.new()
var _button := Button.new()
var _settings_button := Button.new()
var _hint := Label.new()
var _hint_icon := TextureRect.new()
var _status := Label.new()
var _status_icon := TextureRect.new()
var _in_game := false
var _tween: Tween
var _focus_next: Control = null  ## control to focus on the next frame (once in the tree)


## Where the focus starts: on the button when a remembered name fills the field.
static func initial_focus(remembered: String) -> int:
	return FOCUS_BUTTON if remembered != "" else FOCUS_FIELD


static func button_enabled(s: State) -> bool:
	return s == State.READY


## [icon key, text] of the status line in state `s`.
static func status_of(s: State) -> Array:
	match s:
		State.READY:
			return ["ok", UiText.READY]
		State.JOINING:
			return ["wait", UiText.JOINING]
		State.LOST:
			return ["error", UiText.LOST]
	return ["wait", UiText.CONNECTING]


func _ready() -> void:
	layer = 10
	_build()
	var remembered := ClientSettings.load_name()
	_name_edit.text = remembered
	_name_edit.caret_column = remembered.length()
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		_set_state(State.LOST)
	elif peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_set_state(State.READY)
	else:
		_set_state(State.CONNECTING)
	multiplayer.connected_to_server.connect(_on_connected)
	client.welcomed.connect(func(_c): _on_welcomed())
	client.join_rejected.connect(_on_rejected)
	client.connection_lost.connect(_on_lost)
	if settings != null:
		settings.opened.connect(_on_settings_opened)
		settings.closed.connect(_on_settings_closed)
	_root.modulate.a = 0.0
	_fade_to(1.0, FADE_IN_S)
	# focused on the first frame, once every control is in the tree
	_focus_next = _button if initial_focus(remembered) == FOCUS_BUTTON else _name_edit


func _process(_delta: float) -> void:
	if _focus_next != null:
		_focus_next.grab_focus()
		_focus_next = null


func _build() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	add_child(_root)
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://client/menu_veil.gdshader")
	veil.material = mat
	_root.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var band := PanelContainer.new()
	band.theme_type_variation = "TitleBand"
	band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	band.custom_minimum_size = Vector2(300, UiTheme.TITLE_BAND_H)
	column.add_child(band)
	var title := _label(UiText.TITLE, "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title)
	var tagline := _label(UiText.TAGLINE, "TaglineLabel")
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_label(UiText.NAME_LABEL, ""))
	_name_edit.placeholder_text = UiText.NAME_PLACEHOLDER
	_name_edit.max_length = Protocol.NAME_MAX_LEN
	_name_edit.custom_minimum_size = Vector2(0, 36)
	_name_edit.text_submitted.connect(func(_t): _submit())
	_name_edit.text_changed.connect(func(_t): _show_hint(""))
	box.add_child(_name_edit)
	box.add_child(_icon_row(_hint_icon, _hint))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_show_hint("")
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)
	_button.text = UiText.ENTER
	_button.custom_minimum_size = Vector2(0, 44)
	_button.pressed.connect(_submit)
	_button.mouse_entered.connect(func(): _play("hover"))
	_button.button_down.connect(func(): _play("click"))
	box.add_child(_button)
	_settings_button.text = UiText.SETTINGS
	_settings_button.custom_minimum_size = Vector2(0, 36)
	_settings_button.theme_type_variation = "TabButton"
	_settings_button.pressed.connect(_open_settings)
	_settings_button.mouse_entered.connect(func(): if sounds != null: sounds.ui("hover"))
	_settings_button.button_down.connect(func(): if sounds != null: sounds.ui("click"))
	box.add_child(_settings_button)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 2)
	box.add_child(gap2)
	box.add_child(_icon_row(_status_icon, _status))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD

	var field_path := _name_edit.get_path_to(_button)
	_name_edit.focus_neighbor_bottom = field_path
	_name_edit.focus_next = field_path
	var button_path := _button.get_path_to(_name_edit)
	_button.focus_neighbor_top = button_path
	_button.focus_previous = button_path
	_button.focus_neighbor_bottom = _button.get_path_to(_settings_button)
	_button.focus_next = _button.get_path_to(_settings_button)
	_settings_button.focus_neighbor_top = _settings_button.get_path_to(_button)
	_settings_button.focus_previous = _settings_button.get_path_to(_button)
	_settings_button.focus_neighbor_bottom = _settings_button.get_path_to(_name_edit)
	_settings_button.focus_next = _settings_button.get_path_to(_name_edit)


func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _icon_row(icon: TextureRect, label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(12, 12)
	row.add_child(icon)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _open_settings() -> void:
	if settings != null:
		settings.open()


## The settings menu takes this one's place while it is open.
func _on_settings_opened() -> void:
	_root.visible = false


## Back from the settings menu while this menu shows: the focus returns to its button.
func _on_settings_closed() -> void:
	_root.visible = true
	if visible and not _in_game:
		_focus_next = _settings_button


func _play(kind: String) -> void:
	if sounds != null and not _button.disabled:
		sounds.ui(kind)


func _set_state(s: State) -> void:
	state = s
	var st := status_of(s)
	_set_icon(_status_icon, st[0])
	_status.text = (UiText.LOST_IN_GAME if _in_game else UiText.LOST) if s == State.LOST else st[1]
	_button.disabled = not button_enabled(s)
	_name_edit.editable = s != State.JOINING and s != State.LOST


func _set_icon(rect: TextureRect, key: String) -> void:
	rect.texture = UiTheme.icon(key) if key != "" else null


## Shows `error` under the field, or the naming rule when it is "".
func _show_hint(error: String) -> void:
	_hint.text = error if error != "" else UiText.NAME_HINT % Protocol.NAME_MAX_LEN
	_hint.theme_type_variation = "ErrorLabel" if error != "" else "HintLabel"
	_set_icon(_hint_icon, "error" if error != "" else "")


func _submit() -> void:
	if state != State.READY:
		return
	var problem := UiText.name_problem(_name_edit.text)
	if problem != "":
		_show_hint(problem)
		_name_edit.grab_focus()
		return
	_show_hint("")
	_set_state(State.JOINING)
	client.join_with(_name_edit.text)


func _on_connected() -> void:
	if state == State.CONNECTING:
		_set_state(State.READY)


func _on_rejected(reason: String) -> void:
	_set_state(State.READY)
	_show_hint(UiText.rejection(reason, client.player_name))
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_welcomed() -> void:
	_in_game = true
	ClientSettings.save_name(client.player_name)
	_button.release_focus()
	_name_edit.release_focus()
	_fade_to(0.0, FADE_OUT_S).finished.connect(func(): visible = false)


func _on_lost() -> void:
	visible = true
	_set_state(State.LOST)
	_fade_to(1.0, FADE_IN_S)


func _fade_to(alpha: float, seconds: float) -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", alpha, seconds)
	return _tween
