extends Node

# Adaptive music (stage 4, Teil C), after Mawlings scripts/music.gd.
# One node under the scene root ("Music", see ensure()): it survives the
# scene change menu -> run -> menu, so the two themes cross-fade.
#
#   menu      menu_theme (play_menu, from scripts/menu/menu.gd)
#   run       four stems of one set, started in the same frame so they stay
#             sample-aligned; only their volumes change:
#               base     always
#               tension  grows with the alive enemy count (TENSION_FROM..TO)
#               flood    Endwelle or a packed screen (FLOOD_ALIVE)
#               boss     while a boss lives
#             Sets per biome: verdant_maw = run_*, duerrschlund = desert_*
#             (D Hijaz, frame drums), glutsumpf = run_* a little lower and
#             darker (GLUT_PITCH). A biome change cross-fades the sets.
#   stingers  boss (announcement), world (new world), victory (fanfare),
#             defeat; levelup only ducks the loops briefly (the SFX bus
#             plays the level-up sound). Stingers duck the loops.
#   victory / defeat: stinger, then the loops fade out.
#
# All players use the Music bus (audio_settings.gd, MUSIK slider). Files are
# 22.05 kHz mono WAV (imported as QOA), loaded once at start.
# With the Dummy audio driver (automated runs) nothing is ever started: all
# state (targets, gains, stingers) is only bookkept, so tests can assert it.
#
# The battle hands itself over with watch(battle) (battle.gd _connect_audio);
# the node then polls alive enemies, boss and biome every POLL_SECONDS.

const AUDIO_SETTINGS := preload("res://scripts/core/audio_settings.gd")
const MUSIC_DIR := "res://assets/music/"
const NODE_NAME := "Music"
const MENU_ID := "menu_theme"
const SETS := {
	"run": ["run_base", "run_tension", "run_flood", "run_boss"],
	"desert": ["desert_base", "desert_tension", "desert_flood", "desert_boss"],
}
## Mix level (dB) of each layer at full gain (files peak at -3 dBFS).
const LAYER_DB: Array[float] = [-9.0, -11.0, -9.0, -8.0]
## Biome id (scripts/world/biomes.gd) -> stem set and pitch.
const BIOME_SET := {"verdant_maw": "run", "duerrschlund": "desert", "glutsumpf": "run"}
const GLUT_PITCH := 0.92
## Stinger id -> file (res path without .wav). "levelup" has no file (duck only).
const STINGERS := {
	"boss": MUSIC_DIR + "sting_boss",
	"world": MUSIC_DIR + "sting_king",
	"defeat": MUSIC_DIR + "sting_extinct",
	"victory": "res://assets/audio/fanfare_1",
	"levelup": "",
}
const MENU_DB := -8.0
const STINGER_DB := -5.0
const SILENT_DB := -60.0
const FADE_SECONDS := 2.0
const START_FADE_SECONDS := 1.5
const STOP_FADE_SECONDS := 1.2
const DUCK_DB := -7.0
const DUCK_RELEASE_SECONDS := 0.8
const LEVELUP_DUCK_SECONDS := 0.5
## Alive enemies: tension 0 at TENSION_FROM, full at TENSION_TO.
const TENSION_FROM := 25.0
const TENSION_TO := 110.0
const FLOOD_ALIVE := 170
const POLL_SECONDS := 0.25

enum Mode { NONE, MENU, RUN }

static var _instance: Node = null

var enabled := true
var mode := Mode.NONE
## Bookkeeping for tests: number of stingers per id, last stinger.
var stinger_counts := {}
var last_stinger := ""
## "", "victory" or "defeat": how the last run ended (cleared by play_run).
var ending := ""
## Watched battle (scripts/core/battle.gd) or null.
var battle: Node = null

var _streams := {}
var _menu_player: AudioStreamPlayer
var _stinger_player: AudioStreamPlayer
## Players and gains per set (set name -> array of 4).
var _players := {}
var _gain := {}
var _target := {}
var _set := "run"
var _biome := "verdant_maw"
var _alive := 0
var _boss := false
var _flood := false
var _menu_gain := 0.0
var _menu_target := 0.0
var _fade_rate := 1.0 / FADE_SECONDS
var _duck := 0.0
var _duck_hold := 0.0
var _stopping := false
var _silent := false
var _poll := 0.0


## The one music node under the root; created (and added deferred) on first use.
static func ensure(tree: SceneTree) -> Node:
	if _instance != null and is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	if tree == null:
		return null
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null:
		_instance = existing
		return existing
	var script: GDScript = load("res://scripts/core/music.gd")
	var node: Node = script.new()
	node.name = NODE_NAME
	tree.root.add_child.call_deferred(node)
	_instance = node
	return node


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = AudioServer.get_driver_name() == "Dummy"
	AUDIO_SETTINGS.ensure_buses()
	_load(MENU_ID, MUSIC_DIR + MENU_ID, true)
	for set_name: String in SETS:
		var list: Array[AudioStreamPlayer] = []
		for id: String in SETS[set_name]:
			_load(id, MUSIC_DIR + id, true)
			var player := _make_player(id)
			player.stream = _streams.get(id)
			list.append(player)
		_players[set_name] = list
		_gain[set_name] = [0.0, 0.0, 0.0, 0.0]
		_target[set_name] = [0.0, 0.0, 0.0, 0.0]
	for id: String in STINGERS:
		if String(STINGERS[id]) != "":
			_load("sting:" + id, String(STINGERS[id]), false)
	_menu_player = _make_player("Menu")
	_menu_player.stream = _streams.get(MENU_ID)
	_stinger_player = _make_player("Stinger")
	_apply_volumes()


func _process(delta: float) -> void:
	advance(delta / maxf(0.01, Engine.time_scale))


## One fade step of `seconds` (real time); _process calls it, tests may too.
func advance(seconds: float) -> void:
	if battle != null:
		_poll -= seconds
		if _poll <= 0.0:
			_poll = POLL_SECONDS
			_poll_battle()
	var step := _fade_rate * seconds
	for set_name: String in SETS:
		var gains: Array = _gain[set_name]
		var targets: Array = _target[set_name]
		for i in 4:
			gains[i] = move_toward(float(gains[i]), float(targets[i]), step)
		# A silent set that is not needed stops; it restarts in sync later.
		var players: Array = _players[set_name]
		if (set_name != _set or mode != Mode.RUN) and _max(gains) <= 0.0 and players[0].playing:
			for player: AudioStreamPlayer in players:
				player.stop()
	_menu_gain = move_toward(_menu_gain, _menu_target, step)
	if _menu_gain <= 0.0 and _menu_target <= 0.0 and _menu_player.playing:
		_menu_player.stop()
	if _duck_hold > 0.0:
		_duck_hold -= seconds
	else:
		_duck = move_toward(_duck, 0.0, seconds / DUCK_RELEASE_SECONDS)
	_apply_volumes()
	if _stopping and _menu_gain <= 0.0 and _max_all() <= 0.0:
		_stopping = false
		_halt_loops()
		mode = Mode.NONE


# ---------------------------------------------------------------- public API

func play_menu() -> void:
	watch(null)
	if mode == Mode.MENU and not _stopping:
		return
	_stopping = false
	_clear_targets()
	_menu_target = 1.0
	_fade_rate = 1.0 / START_FADE_SECONDS
	mode = Mode.MENU
	if enabled and not _silent and _menu_player.stream != null and not _menu_player.playing:
		_menu_player.play()


## Starts the stems of the current biome in sync; base fades in.
func play_run() -> void:
	ending = ""
	if mode == Mode.RUN and not _stopping:
		return
	_stopping = false
	_menu_target = 0.0
	_alive = 0
	_boss = false
	_flood = false
	_update_targets()
	_fade_rate = 1.0 / START_FADE_SECONDS
	mode = Mode.RUN
	_start_set()


## Battle to follow (null: none). A battle starts the run music.
func watch(battle_node: Node) -> void:
	if battle != null and is_instance_valid(battle) and battle.tree_exiting.is_connected(_on_battle_exiting):
		battle.tree_exiting.disconnect(_on_battle_exiting)
	battle = battle_node
	_poll = 0.0
	if battle == null:
		return
	battle.tree_exiting.connect(_on_battle_exiting)
	_biome = _battle_biome()
	_set = _set_of(_biome)
	play_run()


## alive: living enemies; boss / flood switch their layers on.
func set_intensity(alive: int, boss: bool, flood: bool) -> void:
	if alive == _alive and boss == _boss and flood == _flood:
		return
	_alive = alive
	_boss = boss
	_flood = flood
	if mode != Mode.RUN or _stopping:
		return
	_update_targets()
	_fade_rate = 1.0 / FADE_SECONDS


## Biome id of scripts/world/biomes.gd ("desert" is taken as duerrschlund).
func set_biome(biome_id: String) -> void:
	var id := "duerrschlund" if biome_id == "desert" else biome_id
	if not BIOME_SET.has(id) or id == _biome:
		return
	_biome = id
	_set = _set_of(id)
	if mode != Mode.RUN or _stopping:
		return
	_update_targets()
	_fade_rate = 1.0 / FADE_SECONDS
	_start_set()


## "boss", "world", "victory", "defeat" or "levelup". Unknown ids are ignored.
func stinger(id: String) -> void:
	if not STINGERS.has(id):
		return
	last_stinger = id
	stinger_counts[id] = int(stinger_counts.get(id, 0)) + 1
	if not enabled:
		return
	var stream: AudioStream = _streams.get("sting:" + id)
	_duck = 1.0
	if stream == null:
		_duck_hold = maxf(_duck_hold, LEVELUP_DUCK_SECONDS)
		_apply_volumes()
		return
	_duck_hold = maxf(0.0, stream.get_length() - DUCK_RELEASE_SECONDS)
	_apply_volumes()
	_stinger_player.stream = stream
	_stinger_player.volume_db = STINGER_DB
	if not _silent:
		_stinger_player.play()


## A quiet moment (boss down): loops duck for `seconds`.
func hush(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_duck = 1.0
	_duck_hold = maxf(_duck_hold, seconds)
	_apply_volumes()


## Run won: fanfare, the loops fade out.
func victory() -> void:
	ending = "victory"
	stinger("victory")
	stop()


## Hero died: defeat stinger, the loops fade out.
func defeat() -> void:
	ending = "defeat"
	stinger("defeat")
	stop()


## Fades everything out (immediate: at once), then stops the loops.
func stop(immediate := false) -> void:
	_clear_targets()
	_menu_target = 0.0
	_fade_rate = 1.0 / STOP_FADE_SECONDS
	if immediate or mode == Mode.NONE:
		_menu_gain = 0.0
		for set_name: String in SETS:
			_gain[set_name] = [0.0, 0.0, 0.0, 0.0]
		_halt_loops()
		_stinger_player.stop()
		_stopping = false
		mode = Mode.NONE
		_apply_volumes()
	else:
		_stopping = true


func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	if not enabled:
		_halt_loops()
		_stinger_player.stop()
	elif mode == Mode.MENU and not _silent and _menu_player.stream != null:
		_menu_player.play()
	elif mode == Mode.RUN:
		_start_set()


# ---------------------------------------------------------------- inspection (tests)

func current_set() -> String:
	return _set


func biome() -> String:
	return _biome


## Layer 0..3 (base, tension, flood, boss) of `set_name` (default: current).
func layer_target(layer: int, set_name: String = "") -> float:
	return float(_target[set_name if set_name != "" else _set][layer])


func layer_gain(layer: int, set_name: String = "") -> float:
	return float(_gain[set_name if set_name != "" else _set][layer])


func menu_target() -> float:
	return _menu_target


func menu_gain() -> float:
	return _menu_gain


func ducking() -> float:
	return _duck


func stopping() -> bool:
	return _stopping


func players() -> Array[AudioStreamPlayer]:
	var list: Array[AudioStreamPlayer] = [_menu_player, _stinger_player]
	for set_name: String in SETS:
		for player: AudioStreamPlayer in _players[set_name]:
			list.append(player)
	return list


func stream(id: String) -> AudioStream:
	return _streams.get(id)


func is_silent_driver() -> bool:
	return _silent


# ---------------------------------------------------------------- internals

func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	for player in players():
		player.stop()
		player.stream = null


func _on_battle_exiting() -> void:
	battle = null


func _poll_battle() -> void:
	if not is_instance_valid(battle):
		battle = null
		return
	var horde: Variant = battle.get("horde")
	var pressure: Variant = battle.get("pressure")
	var alive := 0
	if horde != null and is_instance_valid(horde) and horde.has_method("count"):
		alive = int(horde.count())
	var boss := false
	var endwave := false
	if pressure != null and is_instance_valid(pressure):
		boss = pressure.has_method("boss_alive") and bool(pressure.boss_alive())
		endwave = bool(pressure.get("endwave_on"))
	set_intensity(alive, boss, endwave or alive >= FLOOD_ALIVE)
	set_biome(_battle_biome())


func _battle_biome() -> String:
	if battle == null or battle.get_parent() == null:
		return _biome
	var id: Variant = battle.get_parent().get("biome_id")
	return String(id) if id is String and BIOME_SET.has(String(id)) else _biome


func _set_of(biome_id: String) -> String:
	return String(BIOME_SET.get(biome_id, "run"))


func _update_targets() -> void:
	var tension := clampf((float(_alive) - TENSION_FROM) / (TENSION_TO - TENSION_FROM), 0.0, 1.0)
	var wanted: Array = [1.0, 1.0 if _flood else tension, 1.0 if _flood else 0.0, 1.0 if _boss else 0.0]
	for set_name: String in SETS:
		_target[set_name] = wanted.duplicate() if set_name == _set else [0.0, 0.0, 0.0, 0.0]


func _clear_targets() -> void:
	for set_name: String in SETS:
		_target[set_name] = [0.0, 0.0, 0.0, 0.0]


func _start_set() -> void:
	if not enabled or _silent:
		return
	var players_now: Array = _players[_set]
	var pitch := GLUT_PITCH if _biome == "glutsumpf" else 1.0
	for player: AudioStreamPlayer in players_now:
		player.pitch_scale = pitch
	if players_now[0].playing:
		return
	# Every stem from position 0 in the same frame: they stay aligned.
	for player: AudioStreamPlayer in players_now:
		if player.stream != null:
			player.play(0.0)


func _halt_loops() -> void:
	_menu_player.stop()
	for set_name: String in SETS:
		for player: AudioStreamPlayer in _players[set_name]:
			player.stop()


func _load(key: String, path_base: String, loop: bool) -> void:
	var path := path_base + ".wav"
	if not ResourceLoader.exists(path):
		return
	var loaded := load(path) as AudioStream
	if loaded == null:
		return
	if loop and loaded is AudioStreamWAV and (loaded as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var wav := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		loaded = wav
	_streams[key] = loaded


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = AUDIO_SETTINGS.MUSIC
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func _max(values: Array) -> float:
	var best := 0.0
	for v in values:
		best = maxf(best, float(v))
	return best


func _max_all() -> float:
	var best := 0.0
	for set_name: String in SETS:
		best = maxf(best, _max(_gain[set_name]))
	return best


func _apply_volumes() -> void:
	if _menu_player == null:
		return
	var duck_db := DUCK_DB * _duck
	_menu_player.volume_db = _gain_db(_menu_gain, MENU_DB + duck_db)
	for set_name: String in SETS:
		var players_now: Array = _players[set_name]
		var gains: Array = _gain[set_name]
		for i in 4:
			players_now[i].volume_db = _gain_db(float(gains[i]), LAYER_DB[i] + duck_db)


func _gain_db(gain: float, base_db: float) -> float:
	if gain <= 0.001:
		return SILENT_DB
	return maxf(SILENT_DB, base_db + linear_to_db(gain))
