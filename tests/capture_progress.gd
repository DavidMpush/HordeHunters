extends SceneTree

# Review frames of the stage 2 progression from the real game camera:
#   preview_progress_xpbar.png   - mid-run: XP bar, level, gold, gems + coins on
#                                  the ground, a map cocoon with its price pill
#   preview_progress_levelup.png - LEVEL-UP! 1-of-3 cards (shotgun track, stats)
#   preview_progress_cocoon.png  - KOKON! relic/stat cards after buying a cocoon
#   preview_progress_result.png  - GEFALLEN with DEIN BUILD and damage per source
# Run with a window (never --headless): tools/capture.ps1 -Only progress

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 60.0

var main: Node
var battle: Node


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(720, 1280)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	battle = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	var hero: Node3D = battle.hero
	var run: RefCounted = battle.run
	var progress: RefCounted = battle.progress
	var progression: Node = battle.progression
	battle.tick(DT)
	await _settle(10)
	# Stand 4.5 m south of the nearest map cocoon.
	var cocoon: Dictionary = battle.chests.nearest(hero.position, 1000.0, "map")
	var spot: Vector3 = battle.arena.safe_spawn(cocoon.at + Vector3(0.6, 0, 5.0), 0.6)
	hero.position = spot
	main.snap_camera()
	battle.arena.sync(spot)
	battle.arena.finish_rebuild()
	await _settle(10)
	# Gems and coins from a few kills around, a pack coming in.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 14:
		var angle := rng.randf() * TAU
		var at: Vector3 = spot + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(3.0, 7.5)
		var kind := T.Kind.BROCKEN if k % 7 == 0 else T.Kind.WICHTEL
		var i: int = battle.horde.spawn(kind, battle.arena.safe_spawn(at, 0.5))
		battle.horde.hurt(i, 10000.0, Vector3(cos(angle), 0, sin(angle)))
	battle.drop_gold(spot + Vector3(-3.5, 0, 1.0), 6)
	for k in 8:
		var angle := -PI * 0.5 + rng.randf_range(-0.6, 0.6)
		var i: int = battle.horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(spot + Vector3(cos(angle) * 11.0 + 3.0, 0, sin(angle) * 6.0 + 3.0), 0.5))
		battle.horde._appear[i] = 1.0
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 30.0
	run.level = 4
	run.xp = float(run.xp_needed(4)) * 0.62
	run.gold = 14
	run.elapsed = 96.0
	run.kills = 58
	for k in 40:
		battle.horde.step(DT)
		battle.loot.step(DT, Vector3(9999, 0, 9999), 0.0)
		battle.chests.step(DT, Vector3(9999, 0, 9999))
		battle.effects.step(DT)
		await process_frame
	battle.hud.clear()
	await _settle(2)
	await _save("preview_progress_xpbar")
	# Level-up choice with a mix of cards.
	battle.horde.clear()
	run.add_xp(float(run.xp_needed(run.level)))
	battle.shotgun.reload_left = 0.0
	battle.tick(DT)
	progress.ranks["damage"] = 1
	progress.units["damage"] = 1.0
	progress._cache.clear()
	progression.offers = [progress.weapon_entry("shotgun", "rare"), progress.stat_entry("damage", "epic"), progress.stat_entry("magnet", "common")]
	progression.choice.open("level", progression.offers, {"level": run.level, "rerolls": progress.rerolls})
	await _settle(50)
	await _save("preview_progress_levelup")
	progression.choose(0)
	# Buy the cocoon.
	run.gold = 40
	for k in 150:
		hero.position = Vector3(cocoon.at.x, 0, cocoon.at.z + 0.8)
		battle.tick(DT)
		await process_frame
		if battle.paused():
			break
	if not battle.paused():
		push_error("cocoon did not open")
	progression.open_chest("map", [progress.relic_entry("dornenweste"), progress.stat_entry("regen", "rare"), progress.relic_entry("ahnenamulett")])
	await _settle(50)
	await _save("preview_progress_cocoon")
	progression.choose(2)
	# A short fight, a few more picks, then death and the result.
	for pick in [progress.stat_entry("crit", "uncommon"), progress.stat_entry("speed", "common"), progress.weapon_entry("shotgun", "common")]:
		progress.apply(pick, "level", run.elapsed)
	progress.apply(progress.relic_entry("lockstein"), "map", run.elapsed)
	progress.apply(progress.relic_entry("dornenweste"), "free", run.elapsed)
	run.damage_by_source = {"Schrotflinte": 18450.0, "Dornenweste": 1240.0}
	run.damage_dealt = 19690.0
	run.kills = 412
	run.elapsed = 263.0
	run.level = 11
	hero.take_hit(10000.0, hero.position + Vector3(1, 0, 0))
	for k in 75:
		battle.tick(DT)
		await process_frame
	await _save("preview_progress_result")
	print("Saved progress review frames")
	quit()


func _settle(frames: int) -> void:
	for k in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
