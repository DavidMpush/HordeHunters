extends SceneTree

# Profile (stage 3, Teil A §4): user://profile.json save/load round trip,
# robust loading (missing, broken JSON, wrong types, out-of-range values ->
# defaults per field), run records and bests, settings applied to the audio
# buses, and the run configuration seen by scripts/hero/heroes.gd.
# Uses its own file (user://test_profile.json), never the player's profile.

const SESSION := preload("res://scripts/core/session.gd")
const PROFILE := preload("res://scripts/core/profile.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")
const RUN := preload("res://scripts/core/run.gd")
const TEST_PATH := "user://test_profile.json"

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	SESSION.profile_path = TEST_PATH
	SESSION.reload_profile()
	# Missing file -> defaults.
	var profile: RefCounted = SESSION.profile()
	check(profile.load_state == "missing", "missing file -> state missing (%s)" % profile.load_state)
	check(profile.hero_id == "brann" and profile.runs_total == 0, "missing file -> defaults")
	check(profile.flag("vibration") and profile.flag("damage_numbers"), "default toggles on")
	# Round trip.
	profile.hero_id = "boxer"
	profile.set_setting("volume_music", 0.35)
	profile.set_setting("damage_numbers", false)
	var best: Dictionary = profile.record_run("boxer", 125.5, 210, 7)
	check(best.has("time") and best.has("kills") and best.has("level"), "first run sets every best")
	best = profile.record_run("boxer", 80.0, 300, 5)
	check(best.has("kills") and not best.has("time") and not best.has("level"), "second run: only kills is a new best")
	check(SESSION.save_profile() and FileAccess.file_exists(TEST_PATH), "profile saved to the test file")
	SESSION.reload_profile()
	var loaded: RefCounted = SESSION.profile()
	check(loaded.load_state == "ok", "saved file loads clean (%s)" % loaded.load_state)
	check(loaded.hero_id == "boxer", "hero kept")
	check(is_equal_approx(float(loaded.get_setting("volume_music")), 0.35), "music volume kept")
	check(not loaded.flag("damage_numbers") and loaded.flag("vibration"), "toggles kept")
	var rec: Dictionary = loaded.record("boxer")
	check(is_equal_approx(float(rec.best_time), 125.5) and int(rec.best_kills) == 300 and int(rec.best_level) == 7 and int(rec.runs) == 2, "boxer record kept (%s)" % str(rec))
	check(loaded.runs_total == 2 and int(loaded.record("brann").runs) == 0, "runs total 2, brann none")
	# Session.record_run books a run.gd run for the configured hero.
	SESSION.config = {"hero_id": "brann", "seed": 99}
	var run: RefCounted = RUN.new()
	run.elapsed = 61.0
	run.kills = 42
	run.level = 3
	SESSION.record_run(run)
	SESSION.reload_profile()
	check(int(SESSION.profile().record("brann").runs) == 1 and SESSION.profile().runs_total == 3, "Session.record_run saved a brann run")
	# Broken files -> defaults, never an error.
	for broken in ["{not json", "", "[1, 2, 3]", "null", "42"]:
		_write(broken)
		var p: RefCounted = PROFILE.load_from(TEST_PATH)
		check(p.load_state == "corrupt" and p.hero_id == "brann" and p.runs_total == 0, "broken '%s' -> defaults" % broken)
	_write(JSON.stringify({"hero_id": 5, "settings": {"volume_master": "laut", "volume_sfx": 7.0, "vibration": "ja", "damage_numbers": false}, "records": {"brann": {"best_time": "lang", "runs": 3}, "x": 4}, "runs_total": -4}))
	var odd: RefCounted = PROFILE.load_from(TEST_PATH)
	check(odd.load_state == "corrupt", "wrong types flagged as corrupt")
	check(odd.hero_id == "brann", "bad hero id -> brann")
	check(is_equal_approx(float(odd.get_setting("volume_master")), 1.0) and is_equal_approx(float(odd.get_setting("volume_sfx")), 1.0), "bad/out-of-range volumes -> default/clamped")
	check(odd.flag("vibration") and not odd.flag("damage_numbers"), "bad toggle -> default, good toggle kept")
	check(int(odd.record("brann").runs) == 3 and float(odd.record("brann").best_time) == 0.0, "partial record kept, bad field zeroed")
	check(odd.runs_total == 0, "negative runs total -> 0")
	# Settings drive the buses.
	SESSION.reload_profile()
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "Music and SFX buses exist")
	SESSION.set_setting("volume_sfx", 0.5, false)
	check(absf(AUDIO.bus_db("SFX") - (-12.04)) < 0.2, "SFX 50 %% -> about -12 dB (%.2f)" % AUDIO.bus_db("SFX"))
	SESSION.set_setting("volume_master", 0.0, false)
	check(AUDIO.bus_muted("Master"), "Gesamt 0 mutes Master")
	SESSION.set_setting("volume_master", 1.0, false)
	SESSION.set_setting("volume_sfx", 1.0, false)
	check(not AUDIO.bus_muted("Master") and absf(AUDIO.bus_db("SFX")) < 0.01, "volumes back to full")
	# The run configuration as the hero catalogue sees it.
	if ResourceLoader.exists("res://scripts/hero/heroes.gd"):
		var heroes: Script = load("res://scripts/hero/heroes.gd")
		SESSION.config = {"hero_id": "boxer"}
		check(String(heroes.call("current_id")) == "boxer", "heroes.current_id() reads Session.config (boxer)")
		SESSION.config = {}
		check(String(heroes.call("current_id")) == "brann", "no config -> brann")
	check(SESSION.hero_id() == "brann" and SESSION.world_seed(4242) == 4242, "Session defaults without config")
	SESSION.config = {"hero_id": "boxer", "seed": 77, "biome": "desert"}
	check(SESSION.hero_id() == "boxer" and SESSION.world_seed(4242) == 77 and SESSION.biome("x") == "desert", "Session reads config")
	SESSION.config = {}
	DirAccess.remove_absolute(TEST_PATH)
	SESSION.profile_path = PROFILE.DEFAULT_PATH
	SESSION.reload_profile()
	_finish("profile")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
