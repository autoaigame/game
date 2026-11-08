## Plays the game's sound: layered ambience (client/ambience_mix.gd), footsteps (client/footsteps.gd) and menu
## sounds, on the buses Musique, Ambiance, Effets and UI under Master. The start menu's music plays from the
## start (once the browser allows sound) and fades out when the player enters the world. Silent until start(), called once the
## player enters the world (browsers only allow sound after a click). Client display only.
## Keys in the world: M mutes, - and + change the master level, F3 shows the ambience layers, F4 forces an
## ambience (auto, then each one, debug-only ones included). The levels of every bus and the mute are the
## settings (client/audio_settings.gd), set here or from the settings menu and remembered.
extends Node

## The settings changed (from a key or the menu); `settings` is a copy.
signal settings_changed(settings: Dictionary)

const BUSES: Array[String] = ["Musique", "Ambiance", "Effets", "UI"]
const UI_DIR := "res://assets/sounds/ui"
const WHISTLE_DIR := "res://assets/sounds/whistle"
const MUSIC_DIR := "res://assets/sounds/music"
const MUSIC_BUS := "Musique"
## How often the grounds around the player are counted again, in seconds.
const PICK_EVERY_S := 0.5
const VOLUME_STEP := 0.1
## Settings are written this long after the last change, so dragging a slider saves once.
const SAVE_DELAY_S := 0.5
## Another player's footsteps fade out over this distance, in px.
const OTHERS_STEP_RANGE_PX := 900.0
## Another player's whistle fades out over this distance, in px: Protocol.INTEREST_RADIUS cells across the
## screen (96 px a cell), so every player told of a whistle hears it.
const OTHERS_WHISTLE_RANGE_PX := 2200.0
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
var _whistle_last := {}  ## peer id -> last whistle variant
var _sounds_cfg := {}
var _streams := {}  ## path -> AudioStream
var _settings := AudioSettings.defaults()
var _save_in := -1.0  ## s until the pending save, < 0 = none
var _music: CrossfadeLoop  ## the start menu's music while it plays
var _music_waits := false  ## on the web: the music starts with the first press
var _music_cfg := {}
var _music_fade_t := -1.0  ## s into the music's fade out, < 0 = not fading
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
	_start_menu_music()
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
	if _music != null and _music_fade_t < 0.0:
		_music_fade_t = 0.0


## {path, bus, volume_db, fade_out_s, loop_begin, crossfade_s} of the start menu's music (data/sounds.json
## "menu_music"; loop_begin is the stream's loop_offset, set in its .import).
static func menu_music() -> Dictionary:
	var m: Dictionary = Footsteps.read_data().get("menu_music", {})
	var path := MUSIC_DIR.path_join(str(m.get("file", "menu")) + ".ogg")
	var begin := 0.0
	if ResourceLoader.exists(path):
		begin = (load(path) as AudioStreamOggVorbis).loop_offset
	return {"path": path, "bus": MUSIC_BUS, "volume_db": float(m.get("volume_db", 0.0)),
			"fade_out_s": float(m.get("fade_out_s", 3.0)), "loop_begin": begin,
			"crossfade_s": float(m.get("crossfade_s", 0.2))}


## A press that lets a browser play sound.
static func is_gesture(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton \
			or event is InputEventScreenTouch:
		return event.pressed
	return false


## Gain of the music `t` s into a fade out of `fade_s` s (constant power, silent at the end).
static func fade_out_db(t: float, fade_s: float) -> float:
	return AmbienceMix.fade_db(clampf(1.0 - t / fade_s, 0.0, 1.0))


## The intro plays once, then the rest loops (CrossfadeLoop: the web's sample playback ignores loop_offset).
## On the web it waits for the first press: before it the browser holds sound, while the loop keeps time on
## the wall clock, so it would hand over too early.
func _start_menu_music() -> void:
	_music_cfg = menu_music()
	if not ResourceLoader.exists(_music_cfg["path"]):
		return
	var stream: AudioStreamOggVorbis = (load(_music_cfg["path"]) as AudioStreamOggVorbis).duplicate()
	_music = CrossfadeLoop.new(self, stream, StringName(_music_cfg["bus"]), _music_cfg["loop_begin"],
			_music_cfg["crossfade_s"])
	_music_waits = OS.has_feature("web")
	if not _music_waits:
		_music.play(0.0)


func _input(event: InputEvent) -> void:
	if _music_waits and is_gesture(event):
		_music_waits = false
		if _music != null and _music_fade_t < 0.0:
			_music.play(0.0)


func _update_music(delta: float) -> void:
	var db: float = _music_cfg["volume_db"]
	if _music_fade_t >= 0.0:
		_music_fade_t += delta
		db += fade_out_db(_music_fade_t, _music_cfg["fade_out_s"])
		if _music_fade_t >= _music_cfg["fade_out_s"]:
			_music.stop()
			_music = null
			_music_waits = false
			return
	_music.update(db)


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
	if _music != null:
		_update_music(delta)
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


## The whistles' files, from `cfg` (data/sounds.json) "whistle".
static func whistle_paths(cfg: Dictionary) -> Array:
	return Array(cfg.get("whistle", [])).map(func(s): return WHISTLE_DIR.path_join(s + ".ogg"))


## Player `peer_id` whistles: one of the whistles, never the one it whistled last. Mine plays flat; another's
## from `at` (the node on that player's feet), fading with distance. Returns the player node, or null.
func whistle(peer_id: int, is_me: bool, at: Node2D) -> Node:
	var paths := whistle_paths(_sounds_cfg)
	if not started or paths.is_empty():
		return null
	var v := Footsteps.pick_variant(_rng, paths.size(), _whistle_last.get(peer_id, -1))
	_whistle_last[peer_id] = v
	var q: float = _sounds_cfg.get("whistle_pitch", 0.0)
	var p: Node
	if is_me:
		p = AudioStreamPlayer.new()
		p.volume_db = _sounds_cfg.get("whistle_volume_db", 0.0)
	else:
		p = AudioStreamPlayer2D.new()
		p.volume_db = _sounds_cfg.get("whistle_others_volume_db", 0.0)
		p.max_distance = OTHERS_WHISTLE_RANGE_PX
	p.stream = _stream(paths[v], false)
	p.bus = "Effets"
	p.pitch_scale = 1.0 + _rng.randf_range(-q, q)
	p.autoplay = true  # starts as it enters the tree
	p.finished.connect(p.queue_free)
	(self if is_me else at).add_child(p)
	return p


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
	var state := UiText.t(UiText.DEBUG_SOUND_MUTED if _settings["muted"] else UiText.DEBUG_SOUND_ON)
	var lines := [UiText.t(UiText.DEBUG_SOUND).format({"state": state,
			"volume": AudioSettings.to_percent(_settings["master"])}),
			UiText.t(UiText.DEBUG_AMBIENCE_FORCED).format({"current": _current}) if forced != ""
			else UiText.t(UiText.DEBUG_AMBIENCE_AUTO).format({"current": _current, "radius": AmbienceMix.RADIUS_CELLS})]
	var counts := AmbienceMix.ground_counts(_cell)
	for a in _ambiences:
		var id: String = a["id"]
		lines.append(UiText.t(UiText.DEBUG_AMBIENCE_ROW).format({"mark": ">" if id == _current else " ",
				"name": a["name"], "weight": "%.2f" % _weights.get(id, 0.0),
				"score": "%.2f" % AmbienceMix.score(a, counts)}))
		if _weights.get(id, 0.0) <= 0.0:
			continue
		var beds: Array = _beds.get(id, [])
		for i in beds.size():
			lines.append(UiText.t(UiText.DEBUG_BED).format({"sound": a["beds"][i]["sound"],
					"at": "%.1f" % beds[i].position()}))
		var timers: Array = _timers.get(id, [])
		for i in timers.size():
			lines.append(UiText.t(UiText.DEBUG_EVENT).format({"sound": a["events"][i]["sounds"][0],
					"in": "%.1f" % timers[i]}))
	return "\n".join(lines)


func _unhandled_key_input(event: InputEvent) -> void:
	if not started or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_N:  # M is the map (client/hud.gd)
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
	if is_inside_tree():
		get_viewport().set_input_as_handled()
