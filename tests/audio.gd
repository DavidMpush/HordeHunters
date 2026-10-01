extends SceneTree

# Stage 4 Teil C: music and sounds. Automated runs use the Dummy driver, so
# nothing is heard; music.gd and sfx.gd bookkeep their state instead.
#   - menu theme in the menu, run stems when a battle starts (cross-fade)
#   - tension grows with alive enemies, boss layer while the boss lives
#   - stingers: boss announcement, level-up, world, victory, defeat
#   - sounds fire on level-up, pick-ups (gem ladder, gold), card pick, cocoon,
#     boss, portal (hum by distance), world travel, evolution
#   - desert set in the Dürrschlund, players on the Music / SFX buses,
#     bus levels follow the profile volumes
#   - every sound and music file is loaded at start

const SESSION := preload("res://scripts/core/session.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")
const SFX := preload("res://scripts/core/sfx.gd")
const MUSIC := preload("res://scripts/core/music.gd")
const T := preload("res://scripts/core/tuning.gd")

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	SESSION.config = {}
	SESSION.reload_profile()
	# --- menu: the theme fades in
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for k in 3:
		await process_frame
	var music: Node = root.get_node_or_null("Music")
	check(music != null, "music node under the root")
	if music == null:
		_finish()
		return
	check(music.is_silent_driver(), "Dummy driver: bookkeeping only")
	check(music.mode == MUSIC.Mode.MENU and music.menu_target() == 1.0, "menu theme in the menu")
	music.advance(2.0)
	check(music.menu_gain() >= 0.99, "menu theme faded in (%.2f)" % music.menu_gain())
	check(music.stream("menu_theme") != null, "menu theme loaded")
	for id in ["run_base", "run_tension", "run_flood", "run_boss", "desert_base", "desert_boss"]:
		check(music.stream(id) != null, "stem %s loaded" % id)
	for id in ["boss", "world", "victory", "defeat"]:
		check(music.stream("sting:" + id) != null, "stinger %s loaded" % id)
	for player: AudioStreamPlayer in music.players():
		check(player.bus == &"Music", "music player %s on the Music bus" % player.name)
	# --- run: battle hands itself to the music
	menu.queue_free()
	await process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	var sfx: Node = battle.sfx
	check(root.get_node("Music") == music, "one music node across scenes")
	check(music.battle == battle and music.mode == MUSIC.Mode.RUN, "run music on run start")
	check(music.menu_target() == 0.0 and music.layer_target(0) == 1.0, "menu fades out, base stem in")
	check(music.current_set() == "run", "verdant set on the first world")
	check(sfx.loaded_count() == SFX.RULES.size(), "every sound loaded at start (%d/%d)" % [sfx.loaded_count(), SFX.RULES.size()])
	for player in sfx.get_children():
		check((player as AudioStreamPlayer).bus == &"SFX", "sfx player %s on the SFX bus" % player.name)
	music.advance(2.0)
	check(music.layer_gain(0) >= 0.99 and music.menu_gain() <= 0.0, "cross-fade menu -> run done")
	check(music.layer_target(1) == 0.0 and music.layer_target(3) == 0.0, "calm start: no tension, no boss")
	# --- intensity: many enemies raise the tension layer
	var hero: Node3D = battle.hero
	for k in 130:
		var a := TAU * float(k) / 130.0
		battle.horde.spawn(T.Kind.WICHTEL, hero.position + Vector3(cos(a), 0.0, sin(a)) * (9.0 + float(k % 5)))
	music.advance(0.3)
	check(music.layer_target(1) >= 0.99, "tension follows the alive count (%d alive, %.2f)" % [battle.horde.count(), music.layer_target(1)])
	battle.horde.clear()
	music.advance(0.3)
	check(music.layer_target(1) == 0.0, "tension falls with the horde")
	# --- boss: announcement stinger, roar, boss layer, hush on defeat
	battle.pressure.announced.emit("boss", Vector3.ZERO)
	check(music.last_stinger == "boss" and music.ducking() > 0.9, "boss announcement stinger ducks the loops")
	battle.pressure.spawn_boss()
	check(int(sfx.accepted.get("roar", 0)) == 1, "boss roar")
	music.advance(0.3)
	check(music.layer_target(3) == 1.0, "boss music while the boss lives")
	battle.pressure.boss.queue_free()
	await process_frame
	battle.pressure.boss_defeated.emit(Vector3.ZERO)
	music.advance(0.3)
	check(music.layer_target(3) == 0.0, "boss layer off after the boss")
	check(int(sfx.requests.get("roar", 0)) == 2, "death roar requested")
	# --- level-up, pick-ups, card pick
	battle.run.add_xp(100.0)
	check(int(sfx.accepted.get("levelup", 0)) == 1, "level-up sound")
	check(music.last_stinger == "levelup", "level-up stinger (duck)")
	await process_frame
	check(int(sfx.accepted.get("gem", 0)) >= 1, "gem pick-up tick")
	battle.run.add_gold(5)
	await process_frame
	check(int(sfx.accepted.get("gold", 0)) == 1, "gold pick-up sound")
	var climbed := 0
	for k in 5:
		await create_timer(0.08).timeout
		battle.run.add_xp(1.0)
		await process_frame
		climbed = maxi(climbed, int(sfx.gem_step))
	check(climbed >= 2 and sfx.last_pitch > 1.05, "quick pick-ups climb the pitch ladder (step %d)" % climbed)
	await create_timer(0.5).timeout
	sfx.play_gem()
	check(sfx.gem_step == 0, "a pause restarts the ladder")
	battle.progression.open_level()
	battle.progression.choose(0)
	await process_frame
	await process_frame
	check(int(sfx.accepted.get("card", 0)) == 1, "card pick sound")
	# --- cocoon
	var entry: Dictionary = battle.progression.drop_chest(hero.position + Vector3(2, 0, 0), "free")
	battle.chests.open_now(entry)
	check(int(sfx.accepted.get("cocoon", 0)) == 1, "cocoon opening sound")
	if battle.progression.paused():
		battle.progression.choose(0)
	# --- portal and world travel (signals of Teil A if present)
	if battle.has_signal("portal_opened"):
		check(not battle.get_signal_connection_list("portal_opened").is_empty(), "portal_opened connected")
	sfx.portal_opened(hero.position + Vector3(20, 0, 0))
	check(int(sfx.accepted.get("portal", 0)) == 1, "portal opening sound")
	check(sfx.hum_db(hero.position) <= -59.0, "hum silent far from the portal")
	check(sfx.hum_db(hero.position + Vector3(18, 0, 0)) > -20.0, "hum swells near the portal")
	if battle.has_signal("world_changed"):
		check(not battle.get_signal_connection_list("world_changed").is_empty(), "world_changed connected")
	main.set("biome_id", "duerrschlund")
	battle._audio("world", "duerrschlund")
	check(not sfx.portal_at.is_finite(), "hum stops on world change")
	check(int(sfx.accepted.get("whoosh", 0)) == 1, "world travel whoosh")
	check(music.last_stinger == "world", "world stinger")
	check(music.current_set() == "desert" and music.layer_target(0, "desert") == 1.0, "desert set in the Dürrschlund")
	check(music.layer_target(0, "run") == 0.0, "verdant set fades out")
	music.advance(0.3)
	check(music.current_set() == "desert", "poll keeps the world's biome")
	main.set("biome_id", "glutsumpf")
	music.advance(0.3)
	check(music.biome() == "glutsumpf" and music.current_set() == "run", "Glutsumpf: darker verdant set")
	# --- evolution (signal of Teil B if present)
	for source: Object in [battle.progression, battle.progress]:
		if source.has_signal("evolved"):
			check(not source.get_signal_connection_list("evolved").is_empty(), "evolved connected")
	battle._audio("evolve")
	check(int(sfx.accepted.get("evolve", 0)) == 1, "evolution sound")
	# --- victory: fanfare, loops fade out; restart brings the run music back
	if battle.has_signal("run_won"):
		check(not battle.get_signal_connection_list("run_won").is_empty(), "run_won connected")
	battle._audio("victory")
	check(music.ending == "victory" and music.last_stinger == "victory", "victory fanfare")
	music.advance(2.0)
	check(music.mode == MUSIC.Mode.NONE, "loops stopped after the victory")
	main.set("biome_id", "verdant_maw")
	battle.restart()
	check(music.mode == MUSIC.Mode.RUN and music.ending == "", "restart: run music again")
	check(music.current_set() == "run", "restart on the first world")
	# --- defeat
	hero.died.emit()
	check(music.ending == "defeat" and music.last_stinger == "defeat", "defeat stinger on death")
	check(int(music.stinger_counts.get("defeat", 0)) == 1, "one defeat stinger")
	# --- volumes follow the buses
	SESSION.set_setting("volume_music", 0.5, false)
	check(absf(AUDIO.bus_db("Music") - AUDIO.to_db(0.5)) < 0.01, "MUSIK slider sets the Music bus")
	SESSION.set_setting("volume_music", 0.0, false)
	check(AUDIO.bus_muted("Music"), "MUSIK 0 mutes the Music bus")
	SESSION.set_setting("volume_sfx", 0.25, false)
	check(absf(AUDIO.bus_db("SFX") - AUDIO.to_db(0.25)) < 0.01, "EFFEKTE slider sets the SFX bus")
	SESSION.set_setting("volume_music", 1.0, false)
	SESSION.set_setting("volume_sfx", 1.0, false)
	# --- back to the menu: theme again, battle released
	main.queue_free()
	await process_frame
	var menu2: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu2)
	current_scene = menu2
	for k in 2:
		await process_frame
	check(music.mode == MUSIC.Mode.MENU and music.battle == null, "menu theme back in the menu")
	menu2.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS audio")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
