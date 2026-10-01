extends SceneTree

# Review frames of stage 4 Teil A (worlds) from the real game camera:
#   preview_portal.png       - world 1 boss fell: portal, PORTAL OFFEN banner
#   preview_world2.png       - arrived in Dürrschlund: WELT 2 banner, tinted enemies
#   preview_world2_boss.png  - Sandwurm winding up its Sandsturz lane
#   preview_world3_boss.png  - Aschenkröte winding up its Glutregen spots
#   preview_victory.png      - SIEG! result after the last boss
# Run with a window (never --headless): tools/capture.ps1 -Only worlds

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BOSS := preload("res://scripts/enemies/boss_king.gd")
const DT := 1.0 / 60.0

var main: Node
var battle: Node
var pressure: Node
var hero: Node3D


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
	pressure = battle.pressure
	hero = battle.hero
	hero.max_health = 100000.0
	hero.health = 100000.0
	battle.progression.auto_pick = true
	await _frames(20)
	# 1) World 1 boss falls next to the hero: the portal opens.
	battle.run.elapsed = PT.BOSS_AT + 20.0
	var boss: Node3D = pressure.spawn_boss()
	boss.position = battle.arena.safe_spawn(hero.position + Vector3(1.5, 0, -6.0), 1.6)
	await _boss_until(boss, func() -> bool: return boss.is_targetable(), 200)
	_kill(boss)
	_scatter(7, 7.0, 11.0)
	_quiet_gun()
	for k in 200:
		_tick()
		await process_frame
		if battle.worlds.portal != null and pressure.banner == "PORTAL OFFEN" and pressure.banner_age > 0.5:
			break
	# Step back so the portal sits in the middle of the view.
	if battle.worlds.portal != null:
		hero.position = battle.arena.safe_spawn(battle.worlds.portal.position + Vector3(-1.0, 0, 7.5), 0.45)
		main.snap_camera()
		for k in 10:
			_tick()
			await process_frame
	await _save("preview_portal")
	# 2) Into the portal: Dürrschlund.
	var portal: Node3D = battle.worlds.portal
	for k in 200:
		if portal != null and is_instance_valid(portal) and battle.worlds.phase == battle.worlds.Phase.NONE and battle.world_index == 0:
			hero.position = portal.position
		_tick()
		await process_frame
		if battle.world_index == 1 and not battle.worlds.busy():
			break
	_scatter(12, 6.0, 11.0)
	_quiet_gun()
	for k in 30:
		_tick()
		await process_frame
	await _save("preview_world2")
	# 3) The Sandwurm: Sandsturz lane.
	_clear_enemies()
	battle.run.elapsed = pressure.world_start + PT.BOSS_AT
	boss = pressure.spawn_boss()
	boss.position = battle.arena.safe_spawn(hero.position + Vector3(-3.0, 0, -7.0), 1.8)
	await _boss_until(boss, func() -> bool: return boss.state == boss.State.CHASE, 200)
	boss.cycle_index = boss.cycle.find(BOSS.Pattern.CHARGE)
	_scatter(6, 8.0, 11.0)
	await _boss_until(boss, func() -> bool: return boss.state == boss.State.WINDUP and boss.pattern == BOSS.Pattern.CHARGE and boss.timer < PT.CHARGE_WINDUP * 0.45, 400)
	await _save("preview_world2_boss")
	# 4) Glutsumpf and the Aschenkröte: Glutregen.
	_kill(boss)
	await _boss_until(boss, func() -> bool: return boss.is_dead(), 200)
	battle.worlds.travel()
	battle.worlds.fade = 0.0
	battle.worlds.phase = battle.worlds.Phase.NONE
	_clear_enemies()
	battle.run.elapsed = pressure.world_start + PT.BOSS_AT
	boss = pressure.spawn_boss()
	boss.position = battle.arena.safe_spawn(hero.position + Vector3(3.0, 0, -7.5), 1.9)
	await _boss_until(boss, func() -> bool: return boss.state == boss.State.CHASE, 200)
	boss.cycle_index = boss.cycle.find(BOSS.Pattern.ERUPT)
	_scatter(8, 7.0, 11.0)
	await _boss_until(boss, func() -> bool: return boss.state == boss.State.WINDUP and boss.pattern == BOSS.Pattern.ERUPT and boss.timer < PT.ERUPT_WINDUP * 0.45, 400)
	await _save("preview_world3_boss")
	# 5) Victory.
	_kill(boss)
	for k in 260:
		_tick()
		await process_frame
		if battle.hud.result_visible() and battle.run.since_death > 2.3:
			break
	await _save("preview_victory")
	print("Saved worlds review frames")
	quit()


func _boss_until(boss: Node3D, done: Callable, limit: int) -> void:
	for k in limit:
		if done.call():
			return
		hero.step(DT, Vector2.ZERO)
		battle.horde.step(DT)
		battle.effects.step(DT)
		pressure.step(DT, battle.run.elapsed, false)
		battle.run.elapsed += DT
		await process_frame


func _kill(boss: Node3D) -> void:
	boss.state = boss.State.RECOVER
	boss.timer = 5.0
	battle.horde.apply_hits({battle.horde.BOSS_SLOT: {"damage": 1000000.0, "dir": Vector3.RIGHT}})


func _tick() -> void:
	# A focus change of the capture window must not pause the run.
	battle.set_paused(false)
	battle.tick(DT)


func _quiet_gun() -> void:
	for weapon in battle.weapons:
		if weapon.get("shells") != null:
			weapon.shells = 0
			weapon.reload_left = 1000.0


func _clear_enemies() -> void:
	battle.horde.clear()
	battle.effects.clear()


func _scatter(count: int, near: float, far: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + battle.world_index
	var at: Vector3 = hero.position
	for k in count:
		var a := rng.randf() * TAU
		var kind := T.Kind.WICHTEL if k % 4 != 0 else (T.Kind.RENNER if k % 8 != 0 else T.Kind.BROCKEN)
		var i: int = battle.horde.spawn(kind, battle.arena.safe_spawn(at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(near, far), 0.6), false, 100.0)
		if i >= 0:
			battle.horde._appear[i] = 1.0


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _save(name: String) -> void:
	battle.set_paused(false)
	hero.model.visible = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
	print("saved ", name)
