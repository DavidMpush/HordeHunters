extends RefCounted

# Player profile (stage 3, Teil A §4), JSON under user://profile.json:
#   hero_id     hero chosen in the menu
#   settings    volume_master / volume_music / volume_sfx (0..1),
#               vibration, damage_numbers (bool), show_fps (bool, FPS overlay of
#               the run, Etappe 4 Teil D; on while we test on the phone)
#   records     per hero: best_time (s), best_kills, best_level, runs
#   runs_total  finished runs (death) over all heroes
#   disabled_weapons  weapon ids switched off in the menu's Arsenal (never
#               offered as NEUE WAFFE); default [] = every weapon in the pool
# Loading is robust: a missing, unreadable or broken file (bad JSON, wrong
# types, out-of-range numbers) falls back to defaults field by field, never
# throws. load_state tells what happened ("ok", "missing", "corrupt").

const DEFAULT_PATH := "user://profile.json"
const VERSION := 1
const DEFAULT_HERO := "brann"
const SETTING_DEFAULTS := {
	"volume_master": 1.0,
	"volume_music": 0.8,
	"volume_sfx": 1.0,
	"vibration": true,
	"damage_numbers": true,
	"show_fps": true,
}

var path := DEFAULT_PATH
var hero_id := DEFAULT_HERO
var settings: Dictionary = {}
var records: Dictionary = {}
var runs_total := 0
var disabled_weapons: Array = []
var load_state := "missing"


func _init() -> void:
	reset_defaults()


func reset_defaults() -> void:
	hero_id = DEFAULT_HERO
	settings = SETTING_DEFAULTS.duplicate()
	records = {}
	runs_total = 0
	disabled_weapons = []


## Profile from `file_path`; defaults when the file is missing or broken.
static func load_from(file_path: String = DEFAULT_PATH) -> RefCounted:
	var profile: RefCounted = load("res://scripts/core/profile.gd").new()
	profile.path = file_path
	profile.load_state = "missing"
	if not FileAccess.file_exists(file_path):
		return profile
	var text := FileAccess.get_file_as_string(file_path)
	var json := JSON.new()
	if text.strip_edges() == "" or json.parse(text) != OK or not (json.data is Dictionary):
		profile.load_state = "corrupt"
		return profile
	profile.load_state = "ok" if profile.apply_dict(json.data) else "corrupt"
	return profile


## Writes the profile. False when the file could not be opened.
func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("profile: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"hero_id": hero_id,
		"settings": settings.duplicate(),
		"records": records.duplicate(true),
		"runs_total": runs_total,
		"disabled_weapons": disabled_weapons.duplicate(),
	}


## Takes every valid field of `d`; returns false if something was invalid
## (that field keeps its default).
func apply_dict(d: Dictionary) -> bool:
	var clean := true
	var id: Variant = d.get("hero_id", DEFAULT_HERO)
	if id is String and String(id) != "":
		hero_id = String(id)
	else:
		clean = false
	var s: Variant = d.get("settings", {})
	if s is Dictionary:
		for key in SETTING_DEFAULTS:
			if not s.has(key):
				continue
			var value: Variant = s[key]
			var fallback: Variant = SETTING_DEFAULTS[key]
			if fallback is bool:
				if value is bool:
					settings[key] = value
				else:
					clean = false
			elif (value is float or value is int) and is_finite(float(value)):
				settings[key] = clampf(float(value), 0.0, 1.0)
			else:
				clean = false
	else:
		clean = false
	var r: Variant = d.get("records", {})
	if r is Dictionary:
		for key in r:
			var entry: Variant = r[key]
			if not (key is String) or not (entry is Dictionary):
				clean = false
				continue
			records[key] = {
				"best_time": maxf(0.0, _num(entry.get("best_time"), 0.0)),
				"best_kills": maxi(0, int(_num(entry.get("best_kills"), 0.0))),
				"best_level": maxi(0, int(_num(entry.get("best_level"), 0.0))),
				"runs": maxi(0, int(_num(entry.get("runs"), 0.0))),
			}
	else:
		clean = false
	runs_total = maxi(0, int(_num(d.get("runs_total"), 0.0)))
	var off: Variant = d.get("disabled_weapons", [])
	disabled_weapons = []
	if off is Array:
		for entry in off:
			if entry is String and String(entry) != "":
				if not disabled_weapons.has(String(entry)):
					disabled_weapons.append(String(entry))
			else:
				clean = false
	else:
		clean = false
	return clean


static func _num(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback


# ---------------------------------------------------------------- settings

func get_setting(key: String) -> Variant:
	return settings.get(key, SETTING_DEFAULTS.get(key))


func flag(key: String) -> bool:
	return bool(get_setting(key))


func set_setting(key: String, value: Variant) -> void:
	if not SETTING_DEFAULTS.has(key):
		return
	if SETTING_DEFAULTS[key] is bool:
		settings[key] = bool(value)
	else:
		settings[key] = clampf(float(value), 0.0, 1.0)


# ---------------------------------------------------------------- arsenal

## False when id is switched off in the Arsenal.
func is_weapon_enabled(id: String) -> bool:
	return not disabled_weapons.has(id)


## Switches id in (true) or out of the run's weapon pool; the caller saves.
func set_weapon_enabled(id: String, on: bool) -> void:
	if id == "":
		return
	if on:
		disabled_weapons.erase(id)
	elif not disabled_weapons.has(id):
		disabled_weapons.append(id)


# ---------------------------------------------------------------- records

## Best values of `id` ({best_time, best_kills, best_level, runs}).
func record(id: String) -> Dictionary:
	return records.get(id, {"best_time": 0.0, "best_kills": 0, "best_level": 0, "runs": 0})


## Books a finished run. Returns the fields that are new bests
## ({"time": true, ...}); the caller saves.
func record_run(id: String, seconds: float, kills: int, level: int) -> Dictionary:
	var entry := record(id).duplicate()
	var best := {}
	if seconds > float(entry.best_time):
		entry.best_time = seconds
		best["time"] = true
	if kills > int(entry.best_kills):
		entry.best_kills = kills
		best["kills"] = true
	if level > int(entry.best_level):
		entry.best_level = level
		best["level"] = true
	entry.runs = int(entry.runs) + 1
	records[id] = entry
	runs_total += 1
	return best
