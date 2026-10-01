extends Node

# Sound effects: pooled, rate-limited players on the SFX bus. Recorded sounds
# come from Mawlings (assets/audio, see LICENSES_mawlings.md); the shotgun,
# its clicks, the shell tings, the dash whoosh and the gem tick are
# synthesised at start-up (no files). Every stream is loaded in _ready, so a
# play() never loads or allocates.
#
# Stage 4 (Teil C): pick-ups, level-up, card pick, cocoon, boss roar, portal
# (open + a hum loop that swells near the portal), world travel, fanfare,
# evolution and a low-HP heartbeat. watch(battle) (battle.gd _connect_audio)
# lets the node poll the run cheaply each frame:
#   gem    run.xp_total grew   -> "gem" tick, pitch ladder for combos
#   gold   run.gold_total grew -> "gold"
#   card   progression.choices_taken grew -> "card"
#   hum    portal_at set       -> hum volume by hero distance
#   heart  hero below LOW_HP   -> "heartbeat"
# Automated runs (headless, --audio-driver Dummy) play nothing; requests are
# still counted (requests / accepted) so tests can assert them.

const AUDIO_DIR := "res://assets/audio/"
const POOL_SIZE := 16
const RATE := 22050

## id: files (base names) or synth, gap ms between starts, voices, db,
## jitter (random pitch spread, default 0.05).
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
	# Stage 4 (Teil C).
	"gem": {"synth": "gem", "gap": 55, "voices": 2, "db": -15.0, "jitter": 0.0},
	"gold": {"files": ["collect_coin_1", "collect_coin_2", "collect_coin_3"], "gap": 90, "voices": 2, "db": -10.0},
	"levelup": {"files": ["milestone_1", "milestone_2"], "gap": 400, "voices": 1, "db": -6.0, "jitter": 0.0},
	"card": {"files": ["mutate_1", "mutate_2", "mutate_3"], "gap": 120, "voices": 1, "db": -8.0},
	"cocoon": {"files": ["cocoon_open_1", "cocoon_open_2"], "gap": 200, "voices": 1, "db": -5.0},
	"roar": {"files": ["boss_roar_1", "boss_roar_2"], "gap": 800, "voices": 1, "db": -2.0, "jitter": 0.03},
	"portal": {"files": ["portal_open_1", "portal_open_2"], "gap": 1000, "voices": 1, "db": -4.0, "jitter": 0.0},
	"whoosh": {"files": ["migration_whoosh_1"], "gap": 1000, "voices": 1, "db": -4.0, "jitter": 0.0},
	"fanfare": {"files": ["fanfare_1"], "gap": 2000, "voices": 1, "db": -4.0, "jitter": 0.0},
	"evolve": {"files": ["evolve_1", "evolve_2"], "gap": 600, "voices": 1, "db": -4.0, "jitter": 0.0},
	"heartbeat": {"files": ["heartbeat_1", "heartbeat_2"], "gap": 900, "voices": 1, "db": -8.0, "jitter": 0.0},
}
## Gem combo: pickups closer than COMBO_GAP ms climb this ladder (semitones,
## major pentatonic), a pause starts it again.
const GEM_LADDER: Array[float] = [0.0, 2.0, 4.0, 7.0, 9.0, 12.0, 14.0, 16.0, 19.0, 21.0, 24.0]
const COMBO_GAP := 420
const HUM_FILE := "portal_hum_1"
const HUM_NEAR := 3.0
const HUM_FAR := 16.0
const HUM_DB := -8.0
const SILENT_DB := -60.0
const LOW_HP := 0.3

var enabled := true
## Tests: requests per id, accepted (passed gap + voices) per id, last accepted.
var requests := {}
var accepted := {}
var last_id := ""
var last_pitch := 1.0
var gem_step := 0
## Portal position for the hum (INF: no portal).
var portal_at := Vector3.INF
var battle: Node = null

var _streams := {}
var _variants := {}
var _last := {}
var _pool: Array[AudioStreamPlayer] = []
var _owner: Array[String] = []
var _hum: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _last_gem := -100000
var _seen_xp := 0.0
var _seen_gold := 0
var _seen_choices := 0


func _ready() -> void:
	# Headless runs (tests) stay silent: playing voices would leak at exit.
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		enabled = false
	for k in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		# Stage 3: effects follow the EFFEKTE volume (bus from audio_settings.gd).
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)
		_owner.append("")
	_hum = AudioStreamPlayer.new()
	_hum.name = "PortalHum"
	_hum.bus = &"SFX"
	_hum.volume_db = SILENT_DB
	add_child(_hum)
	preload_all()


func _exit_tree() -> void:
	for player in _pool:
		player.stop()
		player.stream = null
	if _hum != null:
		_hum.stop()
		_hum.stream = null
	_streams.clear()


## Loads and synthesises every sound once (no hitch at the first play).
func preload_all() -> void:
	for id: String in RULES:
		var rule: Dictionary = RULES[id]
		if rule.has("synth"):
			var key := String(rule.synth)
			if not _streams.has(key):
				_streams[key] = _synth(key)
			_variants[id] = [_streams[key]]
		else:
			var list: Array = []
			for file: String in rule.files:
				if not _streams.has(file):
					var path := AUDIO_DIR + file + ".wav"
					_streams[file] = load(path) if ResourceLoader.exists(path) else null
				if _streams[file] != null:
					list.append(_streams[file])
			_variants[id] = list
	var hum_path := AUDIO_DIR + HUM_FILE + ".wav"
	if ResourceLoader.exists(hum_path) and _hum != null:
		var wav := load(hum_path) as AudioStreamWAV
		if wav != null:
			wav = wav.duplicate() as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
			_hum.stream = wav


func loaded_count() -> int:
	var count := 0
	for id: String in _variants:
		if not (_variants[id] as Array).is_empty():
			count += 1
	return count


func play(id: String, pitch: float = 1.0) -> void:
	if not RULES.has(id):
		return
	requests[id] = int(requests.get(id, 0)) + 1
	var rule: Dictionary = RULES[id]
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < int(rule.gap):
		return
	var busy := 0
	var free := -1
	for index in _pool.size():
		var player := _pool[index]
		if player.playing:
			if _owner[index] == id:
				busy += 1
		elif free < 0:
			free = index
	if busy >= int(rule.voices):
		return
	_last[id] = now
	accepted[id] = int(accepted.get(id, 0)) + 1
	last_id = id
	last_pitch = pitch
	if not enabled or free < 0:
		return
	var variants: Array = _variants.get(id, [])
	if variants.is_empty():
		return
	var player := _pool[free]
	_owner[free] = id
	player.stream = variants[_rng.randi_range(0, variants.size() - 1)]
	player.volume_db = float(rule.db)
	var jitter := float(rule.get("jitter", 0.05))
	player.pitch_scale = pitch * (_rng.randf_range(1.0 - jitter, 1.0 + jitter) if jitter > 0.0 else 1.0)
	player.play()


## Gem pick-up: one soft tick; quick pick-ups climb the pentatonic ladder.
func play_gem() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_gem > COMBO_GAP:
		gem_step = 0
	elif now - int(_last.get("gem", -100000)) >= int(RULES.gem.gap):
		gem_step = mini(gem_step + 1, GEM_LADDER.size() - 1)
	_last_gem = now
	play("gem", pow(2.0, GEM_LADDER[gem_step] / 12.0))


# ---------------------------------------------------------------- run watch

## Battle to poll (null: none). Counters start from the battle's state.
func watch(battle_node: Node) -> void:
	battle = battle_node
	resync()


## Takes the current counters as seen (new run, new world).
func resync() -> void:
	gem_step = 0
	if battle == null:
		return
	var run: Variant = battle.get("run")
	if run != null:
		_seen_xp = float(run.xp_total)
		_seen_gold = int(run.gold_total)
	var progression: Variant = battle.get("progression")
	if progression != null:
		_seen_choices = int(progression.get("choices_taken"))


func portal_opened(at: Vector3) -> void:
	portal_at = at
	play("portal")
	if enabled and _hum != null and _hum.stream != null and not _hum.playing:
		_hum.volume_db = SILENT_DB
		_hum.play()


func portal_closed() -> void:
	portal_at = Vector3.INF
	if _hum != null:
		_hum.stop()
		_hum.volume_db = SILENT_DB


## Hum level (dB) for a hero at `from`; SILENT_DB without a portal.
func hum_db(from: Vector3) -> float:
	if not portal_at.is_finite():
		return SILENT_DB
	var d := Vector2(from.x - portal_at.x, from.z - portal_at.z).length()
	var near := clampf((HUM_FAR - d) / (HUM_FAR - HUM_NEAR), 0.0, 1.0)
	return SILENT_DB if near <= 0.0 else HUM_DB + linear_to_db(near * near)


func _process(_delta: float) -> void:
	if battle == null:
		return
	if not is_instance_valid(battle):
		battle = null
		return
	var run: Variant = battle.get("run")
	if run == null:
		return
	var xp_total := float(run.xp_total)
	var gold_total := int(run.gold_total)
	if xp_total < _seen_xp or gold_total < _seen_gold:
		resync()
		return
	if xp_total > _seen_xp:
		_seen_xp = xp_total
		play_gem()
	if gold_total > _seen_gold:
		_seen_gold = gold_total
		play("gold")
	var progression: Variant = battle.get("progression")
	if progression != null:
		var taken := int(progression.get("choices_taken"))
		if taken > _seen_choices:
			play("card")
		_seen_choices = taken
	var hero: Variant = battle.get("hero")
	if hero == null:
		return
	if portal_at.is_finite() and _hum != null:
		_hum.volume_db = hum_db(hero.position)
	var max_hp := float(hero.max_health)
	if not run.dead and max_hp > 0.0 and float(hero.health) / max_hp < LOW_HP and float(hero.health) > 0.0:
		var paused: bool = battle.has_method("paused") and battle.paused()
		if not paused:
			play("heartbeat")


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
		"gem":
			# Soft glassy tick: sine at E6 with a quiet fifth above, 3 ms
			# attack (no click), quick decay.
			var n := int(RATE * 0.12)
			samples.resize(n)
			for i in n:
				var t := float(i) / RATE
				var env := minf(1.0, t / 0.003) * exp(-t * 38.0)
				samples[i] = (sin(TAU * 1318.5 * t) * 0.7 + sin(TAU * 1975.5 * t) * 0.18 + sin(TAU * 2637.0 * t) * 0.08 * exp(-t * 60.0)) * env
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
