extends Node

# Etappe 4 Teil D: measures every frame of the run and, on a phone with the
# automatic tier, steps the quality down when the game is too slow:
#   average frame time over Quality.ADAPT_WINDOW (3 s) > ADAPT_LIMIT_MS (20 ms)
#   and the frame is not only script time (render share > 8 ms: a lower render
#   scale only helps the GPU) -> Quality.step_down() + new viewport settings.
# MSAA and 3D scale change at once; wall detail and decor follow with the next
# map build (next world / run). Never steps up again within the session.
# Also the data source of fps_overlay.gd: frame times, script time per frame
# (two probe nodes at process priority -1000 / +1000 bracket all _process work).

const QUALITY := preload("res://scripts/world/quality.gd")
const HISTORY := 240
const SETTLE := 3.0
const RENDER_SHARE_MS := 8.0

## Real time between frames (ms), ring buffer, newest at `head - 1`.
var frame_ms := PackedFloat32Array()
var script_ms := PackedFloat32Array()
var head := 0
var filled := 0
## Steps taken this session ("HOCH -> MITTEL" ...), for the overlay.
var steps: Array[String] = []
## The run stands still (pause, level-up choice): nothing is judged.
var paused_check: Callable

var _last_usec := 0
var _script_start := 0
var _window_ms := 0.0
var _window_script := 0.0
var _window_frames := 0
var _window_time := 0.0
var _settle := SETTLE


class Probe extends Node:
	var governor: Node
	var first := false

	func _process(_delta: float) -> void:
		governor._probe(first)


func _ready() -> void:
	frame_ms.resize(HISTORY)
	script_ms.resize(HISTORY)
	for first in [true, false]:
		var probe := Probe.new()
		probe.name = "ProbeFirst" if first else "ProbeLast"
		probe.governor = self
		probe.first = first
		probe.process_priority = -1000 if first else 1000
		add_child(probe)


func _probe(first: bool) -> void:
	var now := Time.get_ticks_usec()
	if first:
		if _last_usec > 0:
			_record((now - _last_usec) / 1000.0)
		_last_usec = now
		_script_start = now
	else:
		script_ms[(head - 1 + HISTORY) % HISTORY] = (now - _script_start) / 1000.0


func _record(ms: float) -> void:
	frame_ms[head] = ms
	script_ms[head] = 0.0
	head = (head + 1) % HISTORY
	filled = mini(filled + 1, HISTORY)
	_judge(ms)


## Frame time `index` frames back (0 = newest complete frame).
func frame_at(back: int) -> float:
	return frame_ms[(head - 1 - back + HISTORY * 2) % HISTORY]


func script_at(back: int) -> float:
	return script_ms[(head - 1 - back + HISTORY * 2) % HISTORY]


func _judge(ms: float) -> void:
	var stalled := paused_check.is_valid() and bool(paused_check.call())
	if stalled or ms > 250.0 or not QUALITY.adaptive_enabled():
		_reset_window()
		return
	if _settle > 0.0:
		_settle -= ms / 1000.0
		return
	_window_ms += ms
	_window_script += script_at(1)
	_window_frames += 1
	_window_time += ms / 1000.0
	if _window_time < QUALITY.ADAPT_WINDOW:
		return
	var avg := _window_ms / _window_frames
	var script := _window_script / _window_frames
	_reset_window()
	if avg > QUALITY.ADAPT_LIMIT_MS and avg - script > RENDER_SHARE_MS:
		var before := QUALITY.current_tier()
		if QUALITY.step_down():
			QUALITY.apply_viewport(get_viewport(), QUALITY.settings())
			steps.append("%s -> %s (%.0f ms)" % [QUALITY.tier_name(before), QUALITY.tier_name(QUALITY.current_tier()), avg])
			print("quality: step down %s" % steps.back())
			_settle = SETTLE


func _reset_window() -> void:
	_window_ms = 0.0
	_window_script = 0.0
	_window_frames = 0
	_window_time = 0.0


func _notification(what: int) -> void:
	# Background / focus loss: the first frame after it is no measurement.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_last_usec = 0
		_reset_window()
		_settle = SETTLE
