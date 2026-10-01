extends Node

# Placeholder sound effects: pooled, rate-limited players. Recorded sounds come
# from Mawlings (assets/audio, see LICENSES_mawlings.md); the shotgun, its
# clicks, the shell tings and the dash whoosh are synthesised at start-up
# (no files). Automated runs use --audio-driver Dummy, so nothing is heard.

const AUDIO_DIR := "res://assets/audio/"
const POOL_SIZE := 14
const RATE := 22050

## id: files (base names), gap ms between starts, voices, db.
const RULES := {
	"shot": {"synth": "shot", "gap": 40, "voices": 2, "db": -2.0},
	"open": {"synth": "click", "gap": 60, "voices": 1, "db": -8.0},
	"close": {"synth": "clack", "gap": 60, "voices": 1, "db": -6.0},
	"shell": {"synth": "ting", "gap": 50, "voices": 2, "db": -14.0},
	"dash": {"synth": "whoosh", "gap": 120, "voices": 1, "db": -6.0},
	"hit": {"files": ["hit_1", "hit_2", "hit_3"], "gap": 45, "voices": 3, "db": -9.0},
	"kill": {"files": ["kill_1", "kill_2", "kill_3", "kill_4"], "gap": 40, "voices": 3, "db": -8.0},
	"hurt": {"files": ["leader_hit_1", "leader_hit_2"], "gap": 200, "voices": 1, "db": -3.0},
	"warn": {"files": ["warn_1", "warn_2"], "gap": 250, "voices": 1, "db": -9.0},
	"slam": {"files": ["stomp_1"], "gap": 150, "voices": 2, "db": -4.0},
	"death": {"files": ["extinct_1", "extinct_2"], "gap": 1000, "voices": 1, "db": -3.0},
	"ui": {"files": ["ui_1", "ui_2"], "gap": 40, "voices": 2, "db": -10.0},
}

var enabled := true
var _streams := {}
var _last := {}
var _pool: Array[AudioStreamPlayer] = []
var _owner := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Headless runs (tests) stay silent: playing voices would leak at exit.
	if DisplayServer.get_name() == "headless":
		enabled = false
	for k in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)


func _exit_tree() -> void:
	for player in _pool:
		player.stop()
		player.stream = null
	_streams.clear()


func play(id: String, pitch: float = 1.0) -> void:
	if not enabled or not RULES.has(id) or _pool.is_empty():
		return
	var rule: Dictionary = RULES[id]
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < int(rule.gap):
		return
	var busy := 0
	for player in _pool:
		if player.playing and _owner.get(player.get_instance_id(), "") == id:
			busy += 1
	if busy >= int(rule.voices):
		return
	var stream := _stream(id)
	if stream == null:
		return
	var free: AudioStreamPlayer = null
	for player in _pool:
		if not player.playing:
			free = player
			break
	if free == null:
		return
	_last[id] = now
	_owner[free.get_instance_id()] = id
	free.stream = stream
	free.volume_db = float(rule.db)
	free.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	free.play()


func _stream(id: String) -> AudioStream:
	var rule: Dictionary = RULES[id]
	if rule.has("synth"):
		var key := String(rule.synth)
		if not _streams.has(key):
			_streams[key] = _synth(key)
		return _streams[key]
	var files: Array = rule.files
	var name := String(files[_rng.randi_range(0, files.size() - 1)])
	if not _streams.has(name):
		var path := AUDIO_DIR + name + ".wav"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


# ---------------------------------------------------------------- synthesis

func _synth(kind: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	match kind:
		"shot":
			# Crack (bright noise, very short) + boom (low-passed noise) + thump.
			var n := int(RATE * 0.55)
			samples.resize(n)
			var low := 0.0
			var low2 := 0.0
			for i in n:
				var t := float(i) / RATE
				var noise := rng.randf_range(-1.0, 1.0)
				low += (noise - low) * 0.18
				low2 += (low - low2) * 0.25
				var crack := noise * exp(-t * 90.0) * 0.8
				var boom := low2 * 3.2 * exp(-t * 9.0)
				var thump := sin(TAU * lerpf(85.0, 38.0, minf(1.0, t * 6.0)) * t) * exp(-t * 14.0) * 0.9
				samples[i] = clampf(crack + boom + thump, -1.0, 1.0)
		"click", "clack":
			var n := int(RATE * 0.09)
			samples.resize(n)
			var freq := 1900.0 if kind == "click" else 1300.0
			for i in n:
				var t := float(i) / RATE
				var tick := rng.randf_range(-1.0, 1.0) * exp(-t * 400.0)
				var ping := sin(TAU * freq * t) * exp(-t * 60.0) * 0.5
				var knock := sin(TAU * 220.0 * t) * exp(-t * 80.0) * (0.8 if kind == "clack" else 0.3)
				samples[i] = clampf(tick + ping + knock, -1.0, 1.0)
		"ting":
			var n := int(RATE * 0.18)
			samples.resize(n)
			for i in n:
				var t := float(i) / RATE
				samples[i] = (sin(TAU * 2350.0 * t) * 0.5 + sin(TAU * 3720.0 * t) * 0.3) * exp(-t * 28.0)
		_:
			var n := int(RATE * 0.25)
			samples.resize(n)
			var low := 0.0
			for i in n:
				var t := float(i) / RATE
				low += (rng.randf_range(-1.0, 1.0) - low) * lerpf(0.05, 0.3, t / 0.25)
				samples[i] = low * 2.5 * sin(PI * t / 0.25)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
