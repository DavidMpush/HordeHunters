extends SceneTree

# Title menu (stage 3, Teil A §1, §5): menu.tscn is the main scene and loads
# with key art and logo; the hero card opens the hero choice, Brine can be
# chosen (silhouette tiles cannot), settings toggles and sliders work and
# drive the buses, the statistics sheet opens, Esc returns; SPIELEN starts
# main.tscn with the chosen hero and seed through Session.config.
# The profile stays in memory (Session keeps tests away from the real file).

const SESSION := preload("res://scripts/core/session.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")
const SLIDERS := preload("res://scripts/ui/volume_sliders.gd")

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	SESSION.config = {}
	SESSION.reload_profile()
	check(String(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/menu.tscn", "menu.tscn is the main scene")
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for k in 3:
		await process_frame
	check(menu.screen == "title", "opens on the title")
	check(menu._art != null and menu._logo != null, "key art and logo loaded")
	check(menu.hero_id() == "brann", "default hero Brann")
	var view := Rect2(Vector2.ZERO, menu.size)
	for rect in [menu.hero_card_rect(), menu.play_rect(), menu.stats_rect(), menu.settings_rect()]:
		check(view.encloses(rect), "title element inside the screen %s" % str(rect))
	check(menu.play_rect().size.y >= 96.0 and menu.stats_rect().size.y >= 96.0, "touch targets >= 96 px")
	# Hero choice.
	menu.tap(menu.hero_card_rect().get_center())
	check(menu.screen == "heroes" and menu.sheets.heroes.visible, "hero card opens the hero choice")
	var sheet: Control = menu.sheets.heroes
	var tiles: Array = sheet.tiles()
	check(tiles.has("brann") and tiles.has("boxer"), "Brann and Brine listed (%s)" % str(tiles))
	var coming := -1
	for index in tiles.size():
		if String(tiles[index]).begins_with("coming:"):
			coming = index
	check(coming >= 0, "upcoming heroes as BALD tiles")
	sheet.tap(sheet.tile_rect(tiles.find("boxer")).get_center())
	check(menu.hero_id() == "boxer" and SESSION.profile().hero_id == "boxer", "Brine chosen")
	if coming >= 0:
		sheet.tap(sheet.tile_rect(coming).get_center())
		check(menu.hero_id() == "boxer", "a BALD tile cannot be chosen")
	sheet.key(KEY_LEFT)
	check(menu.hero_id() == "brann", "arrow keys cycle heroes")
	sheet.key(KEY_RIGHT)
	check(menu.hero_id() == "boxer", "arrow keys cycle back")
	sheet.tap(sheet.done_rect().get_center())
	check(menu.screen == "title" and not sheet.visible, "FERTIG returns to the title")
	# Settings.
	menu.tap(menu.settings_rect().get_center())
	check(menu.screen == "settings", "settings open")
	var settings: Control = menu.sheets.settings
	settings.tap(settings.toggle_row(1).get_center())
	check(not SESSION.flag("damage_numbers"), "damage numbers off")
	settings.tap(settings.toggle_row(1).get_center())
	check(SESSION.flag("damage_numbers"), "damage numbers on again")
	settings.tap(settings.toggle_row(0).get_center())
	check(not SESSION.flag("vibration"), "vibration off")
	settings.tap(settings.toggle_row(0).get_center())
	var row: Rect2 = settings.slider_rect(2)
	var bar: Rect2 = SLIDERS.track(row)
	settings.tap(Vector2(bar.position.x + bar.size.x * 0.5, row.get_center().y))
	settings.drag(Vector2(bar.position.x + bar.size.x * 0.25, row.get_center().y))
	settings.release()
	check(is_equal_approx(float(SESSION.setting("volume_sfx")), 0.25), "SFX slider dragged to 25 %% (%.2f)" % float(SESSION.setting("volume_sfx")))
	check(absf(AUDIO.bus_db("SFX") - linear_to_db(0.0625)) < 0.2, "SFX bus follows the slider")
	settings.tap(Vector2(bar.end.x + 20.0, row.get_center().y))
	settings.release()
	check(is_equal_approx(float(SESSION.setting("volume_sfx")), 1.0), "slider clamps at 100 %")
	menu._key(KEY_ESCAPE)
	check(menu.screen == "title", "Esc closes the settings")
	# Statistics.
	menu.tap(menu.stats_rect().get_center())
	check(menu.screen == "stats" and menu.sheets.stats.visible, "statistics open")
	await process_frame
	menu._key(KEY_ESCAPE)
	check(menu.screen == "title", "Esc closes the statistics")
	# SPIELEN -> main.tscn with Brine and the seed.
	menu.fixed_seed = 777
	menu.tap(menu.play_rect().get_center())
	check(menu.starting, "SPIELEN starts")
	var main: Node = null
	for k in 120:
		await process_frame
		if current_scene != null and current_scene != menu and is_instance_valid(current_scene) and current_scene.name == "Main":
			main = current_scene
			break
	check(main != null, "main.tscn loaded after SPIELEN")
	check(SESSION.hero_id() == "boxer" and int(SESSION.config.get("seed", 0)) == 777, "Session.config carries hero and seed (%s)" % str(SESSION.config))
	if main != null:
		for k in 3:
			await process_frame
		check(int(main.world_seed) == 777, "main uses the seed (%d)" % int(main.world_seed))
		var battle: Node = main.get_node_or_null("Battle")
		check(battle != null and battle.hero != null, "the run has a hero")
		if battle != null and battle.hero != null and battle.hero.get("hero_id") != null:
			check(String(battle.hero.hero_id) == "boxer", "the run's hero is Brine (%s)" % String(battle.hero.hero_id))
		check(main.get_node_or_null("Battle/HUD/Pause") != null, "pause screen in the run")
	SESSION.config = {}
	SESSION.reload_profile()
	_finish("menu")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
