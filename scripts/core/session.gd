extends RefCounted

# Session state across scene changes (stage 3, Teil A §5). A static class (no
# autoload): preload it and use the static members.
#   config   run configuration the menu hands to main.tscn:
#            {hero_id, seed, biome, disabled_weapons}. Empty = defaults (Brann,
#            main.gd's seed, every weapon). disabled_weapons: weapon ids
#            switched off in the Arsenal (profile), read by the battle.
#            scripts/hero/heroes.gd current_id() reads config.hero_id.
#   profile  user://profile.json (scripts/core/profile.gd), loaded lazily.
#            Automated runs (a custom SceneTree, i.e. --script tests and
#            captures) never touch the real profile: they get defaults in
#            memory and saving is skipped, unless a test points profile_path
#            to its own file.
# Helpers: start_run(), to_menu(), apply_settings(), vibrate(), record_run().

const PROFILE := preload("res://scripts/core/profile.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const DEFAULT_HERO := "brann"

static var config: Dictionary = {}
static var profile_path := PROFILE.DEFAULT_PATH
static var _profile: RefCounted = null


## The loaded profile (defaults in memory for automated runs).
static func profile() -> RefCounted:
	if _profile == null or String(_profile.path) != profile_path:
		if _hermetic():
			_profile = PROFILE.new()
			_profile.path = profile_path
		else:
			_profile = PROFILE.load_from(profile_path)
	return _profile


## Drops the cached profile (next profile() reads the file again).
static func reload_profile() -> void:
	_profile = null


static func save_profile() -> bool:
	if _hermetic():
		return true
	return profile().save()


# Tests and captures run under their own SceneTree script: keep the player's
# profile out of them unless they chose a file themselves.
static func _hermetic() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null and profile_path == PROFILE.DEFAULT_PATH


# ---------------------------------------------------------------- run config

static func hero_id() -> String:
	var id: Variant = config.get("hero_id", DEFAULT_HERO)
	return String(id) if id is String and String(id) != "" else DEFAULT_HERO


static func world_seed(fallback: int) -> int:
	var value: Variant = config.get("seed", fallback)
	return int(value) if (value is int or value is float) and int(value) != 0 else fallback


static func biome(fallback: String) -> String:
	var value: Variant = config.get("biome", fallback)
	return String(value) if value is String and String(value) != "" else fallback


## Starts a run of `id` (the menu's SPIELEN): sets config, saves the choice,
## switches to main.tscn.
static func start_run(tree: SceneTree, id: String, seed_value: int = 0, biome_id: String = "") -> void:
	config = run_config(id, seed_value, biome_id)
	profile().hero_id = id
	save_profile()
	if tree != null:
		tree.change_scene_to_file(MAIN_SCENE)


## The run configuration start_run hands to main.tscn.
static func run_config(id: String, seed_value: int = 0, biome_id: String = "") -> Dictionary:
	return {"hero_id": id, "seed": seed_value, "biome": biome_id, "disabled_weapons": profile().disabled_weapons.duplicate()}


static func to_menu(tree: SceneTree) -> void:
	if tree != null:
		tree.paused = false
		tree.change_scene_to_file(MENU_SCENE)


# ---------------------------------------------------------------- settings

static func setting(key: String) -> Variant:
	return profile().get_setting(key)


static func flag(key: String) -> bool:
	return bool(profile().get_setting(key))


## Changes a setting, applies it (volumes) and optionally saves.
static func set_setting(key: String, value: Variant, save: bool = true) -> void:
	profile().set_setting(key, value)
	if key.begins_with("volume_"):
		AUDIO.apply(profile().settings)
	if save:
		save_profile()


static func apply_settings() -> void:
	AUDIO.apply(profile().settings)


## Short rumble on phones if vibration is on.
static func vibrate(ms: int) -> void:
	if not flag("vibration"):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- records

## Books the run of `run` (scripts/core/run.gd) for the current hero and saves.
static func record_run(run: RefCounted) -> Dictionary:
	if run == null:
		return {}
	var best: Dictionary = profile().record_run(hero_id(), float(run.elapsed), int(run.kills), int(run.level))
	save_profile()
	return best
