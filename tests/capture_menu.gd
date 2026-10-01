extends SceneTree

# Review frames of the stage 3 menu and pause (Teil A), 540 x 960 window:
#   preview_menu_title.png     - logo over the key art, hero card, SPIELEN
#   preview_menu_heroes.png    - hero choice (Brine chosen, BALD tiles)
#   preview_menu_settings.png  - volumes, vibration, damage numbers
#   preview_menu_stats.png     - runs in total, best run per hero
#   preview_menu_pause.png     - pause panel over a fight with a small build
#   preview_menu_result.png    - result with MENÜ next to NOCHMAL
# Run with a window (never --headless): tools/capture.ps1 -Only menu
# Pass "-- menu" to skip the run frames (pause, result).

const T := preload("res://scripts/core/tuning.gd")
const SESSION := preload("res://scripts/core/session.gd")
const DT := 1.0 / 60.0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	SESSION.config = {}
	SESSION.reload_profile()
	var profile: RefCounted = SESSION.profile()
	profile.record_run("brann", 263.0, 412, 11)
	profile.record_run("brann", 190.0, 280, 9)
	profile.record_run("boxer", 148.0, 233, 8)
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await _settle(20)
	await _save("preview_menu_title")
	menu.show_screen("heroes")
	menu.choose_hero("boxer")
	await _settle(4)
	await _save("preview_menu_heroes")
	menu.show_screen("settings")
	SESSION.set_setting("volume_music", 0.6, false)
	SESSION.set_setting("vibration", false, false)
	await _settle(4)
	await _save("preview_menu_settings")
	menu.show_screen("stats")
	await _settle(4)
	await _save("preview_menu_stats")
	menu.show_screen("title")
	await _settle(4)
	await _save("preview_menu_title_boxer")
	SESSION.set_setting("vibration", true, false)
	menu.queue_free()
	if "menu" in OS.get_cmdline_user_args():
		print("Saved menu review frames")
		quit()
		return
	await _settle(2)
	SESSION.config = {"hero_id": "brann"}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	var hero: Node3D = battle.hero
	var progress: RefCounted = battle.progress
	battle.tick(DT)
	for k in 10:
		var angle := -PI * 0.5 + (float(k) - 4.5) * 0.22
		var i: int = battle.horde.spawn(T.Kind.WICHTEL if k % 4 != 0 else T.Kind.BROCKEN, battle.arena.safe_spawn(hero.position + Vector3(cos(angle), 0, sin(angle)) * 7.0, 0.5))
		battle.horde._appear[i] = 1.0
	for k in 20:
		battle.horde.step(DT)
		battle.effects.step(DT)
		await process_frame
	for pick in [progress.stat_entry("damage", "rare"), progress.stat_entry("speed", "common"), progress.stat_entry("magnet", "uncommon")]:
		progress.apply(pick, "level", 30.0)
	progress.apply(progress.relic_entry("lockstein"), "map", 40.0)
	progress.apply(progress.relic_entry("dornenweste"), "free", 50.0)
	battle.run.elapsed = 154.0
	battle.run.kills = 187
	battle.run.level = 6
	await _settle(4)
	await _save("preview_menu_hud")
	battle.set_paused(true)
	await _settle(30)
	await _save("preview_menu_pause")
	battle.set_paused(false)
	battle.run.damage_by_source = {"Schrotflinte": 9450.0, "Dornenweste": 640.0}
	battle.run.damage_dealt = 10090.0
	hero.take_hit(10000.0, hero.position + Vector3(1, 0, 0))
	for k in 75:
		battle.tick(DT)
		await process_frame
	await _save("preview_menu_result")
	SESSION.config = {}
	print("Saved menu review frames")
	quit()


func _settle(frames: int) -> void:
	for k in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
