extends SceneTree

# Death and restart (stage 1, Teil B §6) in the real scene (main.tscn): enemies
# beat the idle hero down, time stops, the result screen shows time and kills,
# NOCHMAL starts a fresh run on the same map.

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	var hero: Node3D = battle.hero
	var horde: Node3D = battle.horde
	var run: RefCounted = battle.run
	var start: Vector3 = hero.position
	check(not run.dead and hero.health == T.HERO_HP, "run starts alive with 100 LP")
	# A ring of Wichtel around the idle hero; the gun is jammed (endless reload).
	for k in 14:
		var a := TAU * float(k) / 14.0
		var i: int = horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(start + Vector3(cos(a), 0, sin(a)) * 4.0, 0.5))
		horde._appear[i] = 1.0
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 1000.0
	var t := 0.0
	while not run.dead and t < 60.0:
		battle.tick(DT)
		battle.shotgun.reload_left = 1000.0
		t += DT
	check(run.dead and hero.is_dead(), "enemies kill the idle hero (%.1f s)" % t)
	check(hero.health <= 0.0, "health at zero")
	var elapsed: float = run.elapsed
	check(absf(elapsed - t) < 0.1, "run time counted until death")
	# Dead: time stops, nothing moves the hero, the gun stays quiet.
	var at: Vector3 = hero.position
	battle.shotgun.reload_left = 0.0
	battle.shotgun.shells = 2
	var shots: int = battle.shotgun.shots
	for k in 45:
		battle.tick(DT)
	check(is_equal_approx(run.elapsed, elapsed), "timer stops at death")
	check(hero.position.distance_to(at) < 0.01, "dead hero stays down")
	check(battle.shotgun.shots == shots, "no shots after death")
	check(battle.hud.result_visible(), "result screen after a short beat")
	check(battle.controls.dead and battle.controls.show_result, "controls switch to the result")
	check(battle.hud.result_button_rect().size.x >= 96.0, "NOCHMAL button has a real touch size")
	# Kills on the result: count one kill first (restart wipes it).
	# NOCHMAL (tap on the button) restarts on the same map.
	var button: Rect2 = battle.hud.result_button_rect()
	var tap := InputEventScreenTouch.new()
	tap.index = 0
	tap.pressed = true
	tap.position = button.get_center()
	battle.controls._input(tap)
	check(not run.dead and not hero.is_dead(), "NOCHMAL revives")
	check(hero.health == T.HERO_HP, "full health again")
	check(horde.count() == 0 and horde.corpses.is_empty(), "enemies cleared")
	check(run.elapsed == 0.0 and run.kills == 0, "time and kills reset")
	check(run.runs == 2, "second run counted")
	check(hero.position.distance_to(start) < 0.5, "back at the start point")
	check(not battle.controls.dead, "controls live again")
	# The new run plays: kill counter and timer move again.
	var i2: int = horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(hero.position + Vector3(0, 0, -4), 0.5))
	horde._appear[i2] = 1.0
	battle.shotgun.reset()
	for k in 60:
		battle.tick(DT)
	check(run.kills >= 1, "kills count in the new run")
	check(run.elapsed > 1.5, "timer runs in the new run")
	# Keyboard restart works too.
	hero.take_hit(1000.0, hero.position)
	for k in 40:
		battle.tick(DT)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	battle.controls._input(key)
	check(not run.dead and run.runs == 3, "Enter restarts from the result")
	_finish("death_restart")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
