## Plays the game's sound: layered ambience (client/ambience_mix.gd), footsteps (client/footsteps.gd) and menu
## sounds, on the buses Musique (empty for now), Ambiance, Effets and UI under Master. Silent until start(), called once the
## player enters the world (browsers only allow sound after a click). Client display only.
## Keys in the world: M mutes, - and + change the master level, F3 shows the ambience layers, F4 forces an
## ambience (auto, then each one, debug-only ones included). The levels of every bus and the mute are the
## settings (client/audio_settings.gd), set here or from the settings menu and remembered.
extends Node

## The settings changed (from a key or the menu); `settings` is a copy.
signal settings_changed(settings: Dictionary)

const BUSES: Array[String] = ["Musique", "Ambiance", "Effets", "UI"]
const UI_DIR := "res://assets/sounds/ui"
## How often the grounds around the player are counted again, in seconds.
const PICK_EVERY_S := 0.5
const VOLUME_STEP := 0.1
## Settings are written this long after the last change, so dragging a slider saves once.
const SAVE_DELAY_S := 0.5
## Another player's footsteps fade out over this distance, in px.
const OTHERS_STEP_RANGE_PX := 900.0
## One-shots play this far either side of the screen centre at full pan, in px of the screen.
const PAN_PX := 600.0

var client: Node  ## client/client.gd
var started := false
var forced := ""  ## ambience id forced from the debug key, "" = automatic
var _ambiences: Array[Dictionary] = []
var _current := ""
var _weights := {}  ## ambience id -> fade weight 0..1
var _beds := {}  ## ambience id -> [CrossfadeLoop] in its "beds" order
var _timers := {}  ## ambience id -> [s until each event's next one-shot]
var _last_sound := {}  ## "id/event" -> last one-shot played
var _cell := Vector2i.ZERO
var _cell_dirty := true
var _pick_t := 0.0
var _rng := RandomNumberGenerator.new()
var _steps := {}  ## tile index -> [sound names]
var _step_last := {}  ## peer id -> last variant
var _sounds_cfg := {}
var _streams := {}  ## path -> AudioStream
var _settings := AudioSettings.defaults()
var _save_in := -1.0  ## s until the pending save, < 0 = none
var _debug := CanvasLayer.new()
var _debug_label := Label.new()


func _ready() -> void:
	ensure_buses()
	_rng.randomize()
	_ambiences = AmbienceMix.load_all()
	_steps = Footsteps.load_table()
	_sounds_cfg = Footsteps.read_data()
	_settings = ClientSettings.load_audio()
	AudioSettings.apply(_settings)
	_debug.layer = 20
	_debug.visible = false
	_debug_label.position = Vector2(12, 12)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color.WHITE)
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 4)
	_debug.add_child(_debug_label)
	add_child(_debug)
	if client != null:
		client.welcomed.connect(func(_c): _on_entered())


func _on_entered() -> void:
	start()
	ui("enter")


## Adds the Ambiance, Effets and UI buses under Master if they are missing.
static func ensure_buses() -> void:
	# Grown with bus_count, not add_bus(): on the web (sample playback) add_bus() reaches Godot's JS as
	# Bus.addAt(-1), which moves the new bus before Master; the JS bus graph then cuts Master from the
	# speakers and loops it through the new buses, and nothing is heard. bus_count appends in place.
	var missing: Array[String] = []
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			missing.append(b)
	var first := AudioServer.bus_count
	AudioServer.bus_count = first + missing.size()
	for k in missing.size():
		AudioServer.set_bus_name(first + k, missing[k])
		AudioServer.set_bus_send(first + k, "Master")


## Starts the ambience (once the player has entered the world).
func start() -> void:
	if started:
		return
	started = true
	for a in _ambiences:
		_weights[a["id"]] = 0.0
		var beds := []
		for b in a["beds"]:
			beds.append(CrossfadeLoop.new(self, _stream(AmbienceMix.sound_path(b["sound"]), false), &"Ambiance"))
		_beds[a["id"]] = beds
		var timers := []
		for e in a["events"]:
			timers.append(AmbienceMix.next_delay(_rng, e) * 0.5)  # the first one comes sooner
		_timers[a["id"]] = timers


## The player's cell, for the ambience (called by the world view when it changes).
func set_listener_cell(cell: Vector2i) -> void:
	if cell != _cell:
		_cell = cell
		_cell_dirty = true


func _process(delta: float) -> void:
	if _save_in >= 0.0:
		_save_in -= delta
		if _save_in < 0.0:
			ClientSettings.save_audio(_settings)
	if not started:
		return
	_pick_t -= delta
	if _pick_t <= 0.0 and (_cell_dirty or forced != ""):
		_pick_t = PICK_EVERY_S
		_cell_dirty = false
		_current = forced if forced != "" else AmbienceMix.choose(_ambiences, AmbienceMix.ground_counts(_cell), _current)
	for a in _ambiences:
		var id: String = a["id"]
		var target := 1.0 if id == _current else 0.0
		var w := AmbienceMix.approach(_weights[id], target, delta, a["fade_s"])
		_weights[id] = w
		var beds: Array = _beds[id]
		for i in beds.size():
			var bed: CrossfadeLoop = beds[i]
			if w > 0.0 and not bed.playing:
				bed.play(_rng.randf() * bed.length() * 0.5)  # each bed from its own point
			elif w <= 0.0 and bed.playing:
				bed.stop()
			bed.update(a["beds"][i]["volume_db"] + AmbienceMix.fade_db(w))
		if w > 0.05:
			_tick_events(a, w, delta)
	if _debug.visible:
		_debug_label.text = _debug_text()


func _tick_events(a: Dictionary, w: float, delta: float) -> void:
	var timers: Array = _timers[a["id"]]
	for i in timers.size():
		timers[i] -= delta
		if timers[i] > 0.0:
			continue
		var e: Dictionary = a["events"][i]
		timers[i] = AmbienceMix.next_delay(_rng, e)
		var key := "%s/%d" % [a["id"], i]
		var r := AmbienceMix.roll(_rng, e, _last_sound.get(key, ""))
		_last_sound[key] = r["sound"]
		_one_shot(AmbienceMix.sound_path(r["sound"]), r["volume_db"] + AmbienceMix.fade_db(w), r["pitch"], r["pan"])


## A one-shot placed left or right of the screen centre, so it pans; distance does not soften it.
func _one_shot(path: String, volume_db: float, pitch: float, pan: float) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = _stream(path, false)
	p.bus = "Ambiance"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.attenuation = 0.0
	p.max_distance = 100000.0
	var cam := get_viewport().get_camera_2d()
	var centre := cam.global_position if cam != null else Vector2.ZERO
	var zoom := cam.zoom.x if cam != null else 1.0
	p.position = centre + Vector2(pan * PAN_PX / zoom, 0.0)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## A footstep of player `peer_id` on ground `tile`. Mine plays flat; another's is positional and softer,
## from `at` (a node standing on that player's feet).
func footstep(peer_id: int, tile: int, is_me: bool, at: Node2D) -> void:
	if not started or not _steps.has(tile):
		return
	var variants: Array = _steps[tile]
	var v := Footsteps.pick_variant(_rng, variants.size(), _step_last.get(peer_id, -1))
	_step_last[peer_id] = v
	var path := Footsteps.sound_path(variants[v])
	var q: float = _sounds_cfg.get("footstep_pitch", 0.0)
	var pitch := 1.0 + _rng.randf_range(-q, q)
	if is_me:
		var p := AudioStreamPlayer.new()
		p.stream = _stream(path, false)
		p.bus = "Effets"
		p.volume_db = _sounds_cfg.get("footstep_volume_db", 0.0)
		p.pitch_scale = pitch
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
		return
	var p2 := AudioStreamPlayer2D.new()
	p2.stream = _stream(path, false)
	p2.bus = "Effets"
	p2.volume_db = _sounds_cfg.get("footstep_others_volume_db", 0.0)
	p2.pitch_scale = pitch
	p2.max_distance = OTHERS_STEP_RANGE_PX
	at.add_child(p2)
	p2.finished.connect(p2.queue_free)
	p2.play()


## A menu sound: "hover", "click" or "enter" (data/sounds.json "ui").
func ui(kind: String) -> void:
	var names: Dictionary = _sounds_cfg.get("ui", {})
	if not names.has(kind):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _stream(UI_DIR.path_join(names[kind] + ".ogg"), false)
	p.bus = "UI"
	p.volume_db = _sounds_cfg.get("ui_volume_db", {}).get(kind, 0.0)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _stream(path: String, loop: bool) -> AudioStream:
	if not _streams.has(path):
		var s: AudioStream = load(path)
		if s is AudioStreamOggVorbis:
			s.loop = loop
		_streams[path] = s
	return _streams[path]


## A copy of the current settings.
func settings() -> Dictionary:
	return _settings.duplicate()


## Sets `channel` (AudioSettings.CHANNELS) to `level` 0..1, heard at once.
func set_level(channel: String, level: float) -> void:
	if not AudioSettings.BUS.has(channel):
		return
	_settings[channel] = clampf(level, 0.0, 1.0)
	_changed()


func set_muted(muted: bool) -> void:
	_settings["muted"] = muted
	_changed()


func toggle_mute() -> void:
	set_muted(not _settings["muted"])


func change_volume(step: float) -> void:
	set_level("master", AudioSettings.stepped(_settings["master"], step))


func _changed() -> void:
	AudioSettings.apply(_settings)
	_save_in = SAVE_DELAY_S
	settings_changed.emit(settings())


## Writes a pending change now (the page may close before the delay).
func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE) and _save_in >= 0.0:
		_save_in = -1.0
		ClientSettings.save_audio(_settings)


## Debug: cycles the forced ambience: automatic, then each ambience in id order.
func cycle_forced() -> void:
	var ids := [""]
	for a in _ambiences:
		ids.append(a["id"])
	forced = ids[(ids.find(forced) + 1) % ids.size()]
	_pick_t = 0.0
	_cell_dirty = true


func _debug_text() -> String:
	var lines := ["Son %s, volume %d %%   [M] muet  [-/+] volume  [F4] forcer" % ["coupé" if _settings["muted"] else "actif",
			AudioSettings.to_percent(_settings["master"])],
			"Ambiance : %s (%s)" % [_current, "forcée" if forced != "" else "auto, sols à %d cases" % AmbienceMix.RADIUS_CELLS]]
	var counts := AmbienceMix.ground_counts(_cell)
	for a in _ambiences:
		var id: String = a["id"]
		lines.append("%s %s  poids %.2f  score %.2f" % [">" if id == _current else " ", a["name"], _weights.get(id, 0.0),
				AmbienceMix.score(a, counts)])
		if _weights.get(id, 0.0) <= 0.0:
			continue
		var beds: Array = _beds.get(id, [])
		for i in beds.size():
			lines.append("      fond %s  à %.1f s" % [a["beds"][i]["sound"], beds[i].position()])
		var timers: Array = _timers.get(id, [])
		for i in timers.size():
			lines.append("      ponctuel %s…  dans %.1f s" % [a["events"][i]["sounds"][0], timers[i]])
	return "\n".join(lines)


func _unhandled_key_input(event: InputEvent) -> void:
	if not started or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_M:
			toggle_mute()
		KEY_MINUS, KEY_KP_SUBTRACT:
			change_volume(-VOLUME_STEP)
		KEY_EQUAL, KEY_KP_ADD:
			change_volume(VOLUME_STEP)
		KEY_F3:
			_debug.visible = not _debug.visible
		KEY_F4:
			cycle_forced()
		_:
			return
	get_viewport().set_input_as_handled()
