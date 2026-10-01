extends RefCounted

# Volume settings on three audio buses: Master, Music and SFX (after Mawlings
# audio_settings.gd). default_bus_layout.tres defines Music and SFX (both send
# to Master); ensure_buses() adds them at runtime if the layout is missing.
#
# Profile values volume_master / volume_music / volume_sfx are linear 0..1 in
# 5 % steps. The level follows a loudness curve: dB = 20 log10(v^2), so
# 50 % ~ -12 dB, 25 % ~ -24 dB; 0 mutes the bus.

const MASTER := "Master"
const MUSIC := "Music"
const SFX := "SFX"
const KEYS := {"volume_master": MASTER, "volume_music": MUSIC, "volume_sfx": SFX}
## Slider order in the pause panel and the settings sheet, with German names.
const ORDER := ["volume_master", "volume_music", "volume_sfx"]
const NAMES := {"volume_master": "GESAMT", "volume_music": "MUSIK", "volume_sfx": "EFFEKTE"}
const STEP := 0.05
const DEFAULT := 1.0


## Adds Music and SFX (once per process) if the bus layout did not.
static func ensure_buses() -> void:
	for bus_name in [MUSIC, SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, MASTER)


## Snaps to 5 % steps, clamped to 0..1.
static func snap(value: float) -> float:
	return clampf(roundf(value / STEP) * STEP, 0.0, 1.0)


## Linear slider value -> dB (loudness curve), 0 -> -80 dB.
static func to_db(value: float) -> float:
	var v := clampf(value, 0.0, 1.0)
	if v <= 0.001:
		return -80.0
	return linear_to_db(v * v)


## Slider value of `key` from a settings dictionary (default 1.0).
static func volume(settings: Dictionary, key: String) -> float:
	var value: Variant = settings.get(key)
	if value is float or value is int:
		return snap(float(value))
	return DEFAULT


## Sets level and mute of the three buses.
static func apply(settings: Dictionary) -> void:
	ensure_buses()
	for key in KEYS:
		var index := AudioServer.get_bus_index(KEYS[key])
		if index < 0:
			continue
		var v := volume(settings, key)
		AudioServer.set_bus_volume_db(index, to_db(v))
		AudioServer.set_bus_mute(index, v <= 0.001)


## Level (dB) of a bus, for tests.
static func bus_db(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	return AudioServer.get_bus_volume_db(index) if index >= 0 else 0.0


static func bus_muted(bus_name: String) -> bool:
	var index := AudioServer.get_bus_index(bus_name)
	return index >= 0 and AudioServer.is_bus_mute(index)
