extends SceneTree

# Arsenal (menu weapon pool): profile disabled_weapons round trip incl. broken
# values, the title's ARSENAL button opens the sheet, a tap on a switch turns
# a weapon off and on (saved at once), the chosen hero's start weapon cannot
# be switched off, signature weapons of other heroes are locked (NUR BRINE),
# and Session's run config carries disabled_weapons.
# Uses its own file (user://test_arsenal_profile.json), never the player's.

const SESSION := preload("res://scripts/core/session.gd")
const PROFILE := preload("res://scripts/core/profile.gd")
const TEST_PATH := "user://test_arsenal_profile.json"

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
	SESSION.config = {}
	SESSION.profile_path = TEST_PATH
	SESSION.reload_profile()
	# Profile: default, helpers, round trip.
	var profile: RefCounted = SESSION.profile()
	check(profile.disabled_weapons.is_empty() and profile.is_weapon_enabled("axe"), "default: every weapon enabled")
	profile.set_weapon_enabled("axe", false)
	profile.set_weapon_enabled("axe", false)
	check(profile.disabled_weapons == ["axe"], "switching off twice keeps one entry (%s)" % str(profile.disabled_weapons))
	profile.set_weapon_enabled("grenade", false)
	check(SESSION.save_profile(), "profile saved")
	SESSION.reload_profile()
	profile = SESSION.profile()
	check(profile.load_state == "ok", "round trip loads clean (%s)" % profile.load_state)
	check(not profile.is_weapon_enabled("axe") and not profile.is_weapon_enabled("grenade") and profile.is_weapon_enabled("sword"), "round trip keeps disabled_weapons (%s)" % str(profile.disabled_weapons))
	profile.set_weapon_enabled("axe", true)
	check(profile.disabled_weapons == ["grenade"], "switching on removes the id")
	# Broken values.
	_write('{"hero_id": "brann", "disabled_weapons": ["axe", 3, null, "", "axe", {"x": 1}, "sword"]}')
	SESSION.reload_profile()
	profile = SESSION.profile()
	check(profile.disabled_weapons == ["axe", "sword"], "only valid strings, no duplicates (%s)" % str(profile.disabled_weapons))
	check(profile.load_state == "corrupt", "broken entries flag the file (%s)" % profile.load_state)
	_write('{"hero_id": "brann", "disabled_weapons": "axe"}')
	SESSION.reload_profile()
	check(SESSION.profile().disabled_weapons.is_empty(), "non-array -> default []")
	_write('{"hero_id": "brann"}')
	SESSION.reload_profile()
	check(SESSION.profile().disabled_weapons.is_empty() and SESSION.profile().load_state == "ok", "missing field -> default [] (old profiles)")
	SESSION.profile().set_weapon_enabled("axe", false)
	# Menu: ARSENAL button and sheet.
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for k in 3:
		await process_frame
	var view := Rect2(Vector2.ZERO, menu.size)
	check(view.encloses(menu.arsenal_rect()) and menu.arsenal_rect().size.y >= 96.0, "ARSENAL button on screen, touch target >= 96 px")
	check(not menu.arsenal_rect().intersects(menu.stats_rect()) and not menu.arsenal_rect().intersects(menu.settings_rect()) and not menu.arsenal_rect().intersects(menu.play_rect()), "ARSENAL button does not overlap the others")
	menu.tap(menu.arsenal_rect().get_center())
	check(menu.screen == "arsenal" and menu.sheets.arsenal.visible, "ARSENAL opens the sheet")
	var sheet: Control = menu.sheets.arsenal
	var ids: Array = []
	for entry in sheet.entries():
		ids.append(String(entry.id))
	check(ids == ["shotgun", "fists", "axe", "sword", "grenade", "pistols", "lightning"], "seven weapons in order (%s)" % str(ids))
	for k in ids.size():
		check(view.encloses(sheet.row_rect(k)) and not sheet.row_rect(k).intersects(sheet.done_rect()), "row %d inside the screen, clear of FERTIG" % k)
	# Brann: shotgun is the start weapon, fists are Brine's.
	menu.choose_hero("brann")
	var shotgun: int = ids.find("shotgun")
	var fists: int = ids.find("fists")
	var axe: int = ids.find("axe")
	check(sheet.state(shotgun) == "start", "Brann: shotgun STARTWAFFE (%s)" % sheet.state(shotgun))
	check(sheet.state(fists) == "locked" and sheet.locked_label(fists) == "NUR BRINE", "Brann: fists locked, NUR BRINE (%s)" % sheet.locked_label(fists))
	sheet.tap(sheet.switch_rect(shotgun).get_center())
	check(SESSION.profile().is_weapon_enabled("shotgun"), "start weapon cannot be switched off")
	sheet.tap(sheet.switch_rect(fists).get_center())
	check(SESSION.profile().is_weapon_enabled("fists"), "locked signature weapon not toggled")
	check(sheet.state(axe) == "off", "axe starts switched off (%s)" % sheet.state(axe))
	sheet.tap(sheet.switch_rect(axe).get_center())
	check(sheet.state(axe) == "on" and SESSION.profile().is_weapon_enabled("axe"), "tap on the switch turns the axe on")
	sheet.tap(sheet.switch_rect(ids.find("grenade")).get_center())
	check(not SESSION.profile().is_weapon_enabled("grenade"), "tap on the switch turns the grenade off")
	SESSION.reload_profile()
	check(not SESSION.profile().is_weapon_enabled("grenade") and SESSION.profile().is_weapon_enabled("axe"), "every toggle is saved at once (%s)" % str(SESSION.profile().disabled_weapons))
	# Brine: fists are the start weapon, the shotgun is free to switch.
	menu.choose_hero("boxer")
	check(sheet.state(fists) == "start", "Brine: fists STARTWAFFE (%s)" % sheet.state(fists))
	check(sheet.state(shotgun) == "on", "Brine: shotgun switchable (%s)" % sheet.state(shotgun))
	sheet.tap(sheet.switch_rect(shotgun).get_center())
	check(not SESSION.profile().is_weapon_enabled("shotgun"), "Brine: shotgun switched off")
	await process_frame
	sheet.tap(sheet.done_rect().get_center())
	check(menu.screen == "title" and not sheet.visible, "FERTIG returns to the title")
	menu._key(KEY_A)
	check(menu.screen == "arsenal", "A opens the arsenal")
	menu._key(KEY_ESCAPE)
	check(menu.screen == "title", "Esc closes the arsenal")
	# Run config.
	var cfg: Dictionary = SESSION.run_config("boxer", 55)
	check(cfg.get("hero_id") == "boxer" and int(cfg.get("seed", 0)) == 55 and cfg.has("biome"), "run config keeps hero, seed, biome (%s)" % str(cfg))
	var off: Variant = cfg.get("disabled_weapons")
	check(off is Array and off.has("shotgun") and off.has("grenade") and not off.has("axe"), "run config carries disabled_weapons (%s)" % str(off))
	SESSION.start_run(null, "boxer", 55)
	check(SESSION.config.get("disabled_weapons") is Array and SESSION.config.disabled_weapons.has("grenade") and SESSION.config.hero_id == "boxer", "start_run sets disabled_weapons (%s)" % str(SESSION.config))
	SESSION.config.disabled_weapons.append("sword")
	check(SESSION.profile().is_weapon_enabled("sword"), "config holds a copy, not the profile's array")
	menu.queue_free()
	await process_frame
	SESSION.config = {}
	SESSION.profile_path = PROFILE.DEFAULT_PATH
	SESSION.reload_profile()
	DirAccess.remove_absolute(TEST_PATH)
	_finish("arsenal")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
