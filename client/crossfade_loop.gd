## Seamless looping of a sound on every platform. On the web (sample playback) Godot does not use Web
## Audio's own loop: when the buffer ends it starts it again from the position given to play(), ignoring
## loop_offset, and only once the end has been noticed, a frame or more later (a gap). Here two players
## take turns: near the end of the loop the other one starts at `loop_begin` and an equal-power crossfade
## hands over. Times come from the wall clock, so a low frame rate only delays the crossfade.
class_name CrossfadeLoop
extends RefCounted

var loop_begin := 0.0  ## where each new turn starts, in seconds into the stream
var crossfade_s := 1.5
var _players: Array[AudioStreamPlayer] = []
var _cur := 0
var _active := false
var _start_us := 0  ## wall clock (usec) at which the current player was at position 0


## Two players for `stream` (its own loop flag is turned off), added under `parent` on `bus`.
func _init(parent: Node, stream: AudioStream, bus: StringName, begin := 0.0, crossfade := 1.5) -> void:
	loop_begin = begin
	crossfade_s = crossfade
	if stream is AudioStreamOggVorbis:
		stream.loop = false
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = bus
		p.volume_db = -80.0
		parent.add_child(p)
		_players.append(p)


## Gains (current turn, next turn) `t` seconds into the stream: the current one alone, then an
## equal-power hand-over over its last `crossfade` seconds (at most half of the looped part).
static func gains(t: float, length: float, begin: float, crossfade: float) -> Vector2:
	var x := minf(crossfade, (length - begin) / 2.0)
	var p := clampf((t - (length - x)) / x, 0.0, 1.0)
	return Vector2(cos(p * PI / 2.0), sin(p * PI / 2.0))


## Position of the next turn when the current one is `t` seconds in: it started at `begin` when the
## hand-over began.
static func next_position(t: float, length: float, begin: float, crossfade: float) -> float:
	return begin + t - (length - minf(crossfade, (length - begin) / 2.0))


var playing: bool:
	get:
		return _active


func length() -> float:
	return _players[0].stream.get_length()


## Seconds into the stream of the current turn.
func position() -> float:
	return (Time.get_ticks_usec() - _start_us) / 1e6 if _active else 0.0


## Starts at `from` seconds (no-op when already playing).
func play(from := 0.0) -> void:
	if _active:
		return
	_active = true
	_start_us = Time.get_ticks_usec() - int(from * 1e6)
	_players[_cur].play(from)


func stop() -> void:
	_active = false
	for p in _players:
		p.stop()


## Call every frame while playing: hands over near the end, sets both players' volumes.
func update(volume_db: float) -> void:
	if not _active:
		return
	var cur := _players[_cur]
	var nxt := _players[1 - _cur]
	var length := cur.stream.get_length()
	var t := position()
	if t >= length:  # hand-over done: the next turn becomes the current one
		var into := next_position(t, length, loop_begin, crossfade_s)
		cur.stop()
		_cur = 1 - _cur
		_start_us = Time.get_ticks_usec() - int(into * 1e6)
		t = into
		cur = _players[_cur]
		nxt = _players[1 - _cur]
		if not cur.playing:  # frames so late that the hand-over was missed
			cur.play(t)
	var g := gains(t, length, loop_begin, crossfade_s)
	if g.y > 0.0 and not nxt.playing:
		nxt.play(maxf(loop_begin, next_position(t, length, loop_begin, crossfade_s)))
	cur.volume_db = volume_db + (linear_to_db(g.x) if g.x > 0.0 else -80.0)
	nxt.volume_db = volume_db + (linear_to_db(g.y) if g.y > 0.0 else -80.0)
