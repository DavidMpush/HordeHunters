extends SceneTree

# Review frames of stage 2 Teil B (Druck) from the real game camera:
#   preview_pressure_wave.png       - WELLE! banner, edge arrow, danger rings on the incoming side
#   preview_pressure_encircle.png   - EINKESSELUNG: ring of Wichtel closing, bright gap
#   preview_pressure_elite.png      - champion Brocken (gold) winding up its stomp ring
#   preview_pressure_boss_stomp.png - Moorkönig stomp ring telegraph + boss bar
#   preview_pressure_boss_leap.png  - Moorkönig in the air over its landing zone
#   preview_pressure_boss_sweep.png - Moorkönig sweep arc telegraph
# Run with a window (never --headless): tools/capture.ps1 -Only pressure

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
	await _frames(20)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		only = arg
	# 1) Wave warning: a few Wichtel around, the warning runs.
	if only == "" or only == "wave":
		_scatter(10, 6.0, 11.0)
		battle.run.elapsed = PT.WAVE_FIRST - PT.WAVE_WARNING
		pressure.elapsed = battle.run.elapsed
		pressure.elite_next = 999.0
		pressure.announce_wave()
		for k in 50:
			_tick()
			pressure.elapsed = battle.run.elapsed
			pressure._wave_marks()
			await process_frame
		await _save("preview_pressure_wave")
	# 2) Encircle: ring with gap, closing for 2 s.
	if only == "" or only == "encircle":
		_clear()
		battle.run.elapsed = 150.0
		pressure.elapsed = 150.0
		pressure.late_waves = 0
		pressure.announce_wave()
		pressure.spawn_wave()
		pressure.banner_age = 0.6
		for k in 120:
			_tick()
			await process_frame
		await _save("preview_pressure_encircle")
	# 3) Champion winding up next to the hero.
	if only == "" or only == "elite":
		_clear()
		battle.run.elapsed = 95.0
		var at: Vector3 = hero.position
		var e: int = battle.horde.spawn(T.Kind.BROCKEN, battle.arena.safe_spawn(at + Vector3(2.6, 0, -1.4), 1.3), true)
		battle.horde._appear[e] = 1.0
		battle.horde._hp[e] = 100000.0
		_scatter(6, 6.0, 10.0)
		_quiet_gun()
		for k in 120:
			battle.horde.step(DT)
			hero.step(DT, Vector2.ZERO)
			battle.effects.step(DT)
			pressure.step(DT, 95.0, false)
			await process_frame
			if battle.horde.state_of(e) == battle.horde.State.WINDUP and battle.horde._timer[e] < PT.ELITE_WINDUP * 0.35:
				break
		await _save("preview_pressure_elite")
	# 4-6) The Moorkönig: stomp, leap, sweep.
	if only == "" or only.begins_with("boss"):
		_clear()
		battle.run.elapsed = PT.BOSS_AT
		pressure.elapsed = PT.BOSS_AT
		var boss: Node3D = pressure.spawn_boss()
		boss.position = hero.position + Vector3(3.6, 0, -2.0)
		_scatter(8, 7.0, 11.0)
		_quiet_gun()
		# Rise, then the stomp wind-up (hero next to him).
		await _boss_until(boss, func() -> bool: return boss.state == boss.State.WINDUP and boss.pattern == BOSS.Pattern.STOMP and boss.timer < PT.STOMP_WINDUP * 0.4, 400)
		await _save("preview_pressure_boss_stomp")
		# Leap: the hero walks away, the boss jumps after him.
		await _boss_until(boss, func() -> bool: return boss.state == boss.State.CHASE, 300)
		boss.cycle_index = 1
		var walk := 0
		await _boss_until(boss, func() -> bool: return boss.state == boss.State.AIR and boss.timer < PT.LEAP_AIR * 0.5, 400, Vector2(-0.6, 0.3))
		await _save("preview_pressure_boss_leap")
		await _boss_until(boss, func() -> bool: return boss.state == boss.State.CHASE, 300)
		hero.position = battle.arena.safe_spawn(boss.position + Vector3(-3.0, 0, 2.6), 0.45)
		boss.cycle_index = 2
		await _boss_until(boss, func() -> bool: return boss.state == boss.State.WINDUP and boss.pattern == BOSS.Pattern.SWEEP and boss.timer < PT.SWEEP_WINDUP * 0.35, 400)
		await _save("preview_pressure_boss_sweep")
	print("Saved pressure review frames")
	quit()


func _boss_until(boss: Node3D, done: Callable, limit: int, move := Vector2.ZERO) -> void:
	for k in limit:
		if done.call():
			return
		hero.step(DT, move)
		battle.horde.step(DT)
		battle.effects.step(DT)
		pressure.step(DT, battle.run.elapsed, false)
		battle.run.elapsed += DT
		await process_frame


func _tick() -> void:
	battle.tick(DT)


func _quiet_gun() -> void:
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 1000.0


func _clear() -> void:
	battle.horde.clear()
	battle.effects.clear()
	battle.shotgun.reset()
	pressure.reset()
	hero.health = hero.max_health
	hero.model.reload = -1.0


func _scatter(count: int, near: float, far: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var at: Vector3 = hero.position
	for k in count:
		var a := rng.randf() * TAU
		var i: int = battle.horde.spawn(T.Kind.WICHTEL if k % 4 != 0 else T.Kind.RENNER, battle.arena.safe_spawn(at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(near, far), 0.5))
		if i >= 0:
			battle.horde._appear[i] = 1.0


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _save(name: String) -> void:
	# No invulnerability blink in a review frame.
	hero.model.visible = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
	print("saved ", name)
