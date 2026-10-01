extends SceneTree

# Review frames of the stage 1 fight from the real game camera (main.tscn):
#   preview_fight_shot.png     - a blast into a Wichtel pack: flash, tracers, flying bodies
#   preview_fight_after.png    - a few frames later: corpses in the air, numbers, splats
#   preview_fight_brocken.png  - a Brocken mid wind-up with its magenta arc
#   preview_fight_reload.png   - Brann reloading (gun broken open, shells flying)
#   preview_fight_hit.png      - the Brocken swing lands (flash, vignette)
#   preview_fight_horde.png    - a dense mixed horde around the hero
#   preview_fight_result.png   - death: GEFALLEN, time, kills, NOCHMAL
# Run with a window (never --headless): tools/capture.ps1 -Only fight

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
	var at := hero.position
	await _settle(20)
	# 1) Blast into a Wichtel pack 4-5 m north-east of the hero.
	var aim := Vector3(0.45, 0, -1).normalized()
	for k in 9:
		var spot := at + aim * (4.0 + 0.5 * float(k % 3)) + Vector3(float(k / 3 - 1) * 0.85, 0, float(k % 3) * 0.3)
		battle.horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(spot, 0.5))
	for k in 3:
		battle.horde.spawn(T.Kind.RENNER, battle.arena.safe_spawn(at + Vector3(-5.5 + k, 0, 2.5), 0.5))
	battle.horde.step(DT)
	for i in battle.horde.count():
		battle.horde._appear[i] = 1.0
	var shots: int = battle.shotgun.shots
	for k in 60:
		_tick()
		await process_frame
		if battle.shotgun.shots > shots:
			break
	_tick()
	await process_frame
	await _save("preview_fight_shot")
	for k in 9:
		_tick()
		await process_frame
	await _save("preview_fight_after")
	# 2) Reload pose: run until the gun is open.
	for k in 90:
		_tick()
		await process_frame
		var p: float = battle.shotgun.reload_progress()
		if p >= 0.42:
			break
	await _save("preview_fight_reload")
	# 3) Brocken wind-up: clear, place one Brocken next to the hero.
	battle.horde.clear()
	battle.effects.clear()
	battle.shotgun.reset()
	battle.hero.health = battle.hero.max_health
	at = hero.position
	var brocken: int = battle.horde.spawn(T.Kind.BROCKEN, battle.arena.safe_spawn(at + Vector3(4.5, 0, -0.8), 1.0))
	battle.horde._appear[brocken] = 1.0
	# Keep the gun quiet so the pose stays readable.
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 30.0
	for k in 120:
		battle.horde.step(DT)
		battle.hero.step(DT, Vector2.ZERO)
		battle.effects.step(DT)
		await process_frame
		if battle.horde.count() > 0 and battle.horde.state_of(0) == battle.horde.State.WINDUP and battle.horde._timer[0] < T.enemy(T.Kind.BROCKEN).windup * 0.35:
			break
	battle.shotgun.reload_left = 0.0
	battle.shotgun.shells = 2
	battle.hero.model.reload = -1.0
	battle.hero.model.animate(DT)
	await _save("preview_fight_brocken")
	# The swing lands: hero flash, red vignette, camera shake.
	for k in 40:
		battle.horde.step(DT)
		battle.hero.step(DT, Vector2.ZERO)
		battle.effects.step(DT)
		await process_frame
		if battle.hero.hits_taken > 0:
			break
	for k in 2:
		battle.horde.step(DT)
		battle.hero.step(DT, Vector2.ZERO)
		battle.effects.step(DT)
		await process_frame
	await _save("preview_fight_hit")
	# 4) Dense horde: 120 mixed enemies around the hero, a few seconds of fight.
	battle.horde.clear()
	battle.effects.clear()
	battle.shotgun.reset()
	battle.hero.health = battle.hero.max_health
	at = hero.position
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 120:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(5.0, 16.0)
		var kind := T.Kind.WICHTEL if k % 5 != 0 else T.Kind.RENNER
		if k % 30 == 0:
			kind = T.Kind.BROCKEN
		battle.horde.spawn(kind, battle.arena.safe_spawn(at + Vector3(cos(angle) * r, 0, sin(angle) * r), 0.9))
	for k in 70:
		_tick()
		await process_frame
	await _save("preview_fight_horde")
	# Death and the result screen.
	battle.run.kills = 137
	battle.run.kills_by_kind = PackedInt32Array([98, 33, 6])
	battle.run.elapsed = 151.0
	battle.hero.take_hit(10000.0, battle.hero.position + Vector3(1, 0, 0))
	for k in 75:
		_tick()
		await process_frame
	await _save("preview_fight_result")
	print("Saved fight review frames")
	quit()


func _tick() -> void:
	battle.tick(DT)


func _settle(frames: int) -> void:
	for k in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
