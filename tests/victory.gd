extends SceneTree

# Stage 4 Teil A: the run can be won.
#   - world 3 (Glutsumpf) has the Aschenkröte: more health than the Sandwurm,
#     the Glutregen spots are shown before they burst
#   - its death: no portal, signal run_won, enemies gone, run.won
#   - the result screen shows SIEG! (time, kills, level, build) with NOCHMAL
#     and MENÜ; NOCHMAL starts over in world 1

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BOSS := preload("res://scripts/enemies/boss_king.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []
var won := 0


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
	if battle.sfx.get("enabled") != null:
		battle.sfx.enabled = false
	var hero: Node3D = battle.hero
	var run: RefCounted = battle.run
	var pressure: Node = battle.pressure
	var horde: Node3D = battle.horde
	var worlds: Node = battle.worlds
	main.snap_camera()
	battle.director.camera = main.get_node("Camera3D")
	battle.run_won.connect(func() -> void: won += 1)
	await process_frame
	var first_seed: int = main.world_seed
	# Straight to world 3 (two portal trips).
	run.elapsed = 300.0
	worlds.travel()
	run.elapsed = 600.0
	worlds.travel()
	check(battle.world_index == 2 and main.biome_id == "glutsumpf", "world 3 is Glutsumpf (%s)" % main.biome_id)
	check(pressure.final_world, "world 3 is the last world")
	check(is_equal_approx(battle.director.world_hp, 2.4) and is_equal_approx(horde.damage_mult, 2.4), "world 3: enemy health and damage x2.4")
	# --- the Aschenkröte
	run.elapsed = pressure.world_start + PT.BOSS_AT + 1.0
	var boss: Node3D = pressure.spawn_boss()
	var boss_hp: float = boss.max_health
	check(boss.title == "ASCHENKRÖTE" and boss.max_health > float(PT.BOSSES[1].hp), "world 3 boss: Aschenkröte with %.0f health" % boss.max_health)
	hero.max_health = 100000.0
	hero.health = 100000.0
	for k in 60:
		boss.step(DT)
	boss.state = boss.State.CHASE
	boss.cycle_index = boss.cycle.find(BOSS.Pattern.ERUPT)
	hero.position = battle.arena.safe_spawn(boss.position + Vector3(7.0, 0, 0), 0.45)
	_until(boss, hero, func() -> bool: return boss.state == boss.State.WINDUP)
	check(boss.pattern == BOSS.Pattern.ERUPT and boss.zones_visible() == PT.ERUPT_COUNT, "Glutregen shows %d spots (%d)" % [PT.ERUPT_COUNT, boss.zones_visible()])
	check(boss.erupt_spots.size() > 0 and boss.erupt_spots[0].distance_to(Vector3(hero.position.x, 0, hero.position.z)) < 0.6, "one spot on the hero")
	var shown: float = boss.clock
	var hp0: float = hero.health
	_until(boss, hero, func() -> bool: return boss.state != boss.State.WINDUP)
	check(boss.clock - shown >= PT.ERUPT_WINDUP - 0.05, "spots shown for the wind-up before they burst")
	check(hero.health < hp0, "a hero on a spot gets hit")
	# --- some enemies around, then the boss dies
	for k in 6:
		horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(hero.position + Vector3(5.0 + k, 0, 3.0), 0.4))
	_kill(boss, horde)
	for k in 60:
		pressure.step(DT, run.elapsed, true)
		worlds.step(DT)
	check(won == 1, "signal run_won (%d)" % won)
	check(run.won and run.dead, "run won")
	check(worlds.portal == null, "no portal after the last boss")
	check(horde.count() == 0, "all enemies gone")
	check(pressure.drops.filter(func(d: Dictionary) -> bool: return d.kind == "boss").is_empty(), "no boss cocoon on the victory")
	check(pressure.banner == "SIEG!", "SIEG! banner")
	# --- result screen
	var hud: Control = battle.hud
	for k in 75:
		battle.tick(DT)
	check(hud.result_visible(), "victory result shown")
	check(battle.controls.show_result and battle.controls.dead, "NOCHMAL / MENÜ buttons live")
	check(hud.result_button_rect().size.x > 0.0 and hud.result_menu_rect().size.x > 0.0, "NOCHMAL and MENÜ buttons")
	check(hud._world_line(true) == "ALLE 3 WELTEN BEZWUNGEN", "victory line")
	check(not hero.is_dead(), "the hero lives")
	# --- NOCHMAL: world 1 again
	battle.controls.restart_requested.emit()
	await process_frame
	check(battle.world_index == 0 and main.biome_id == "verdant_maw", "NOCHMAL: back in world 1 (%s)" % main.biome_id)
	check(main.world_seed == first_seed, "NOCHMAL: the first map again")
	check(not run.won and not run.dead and run.elapsed == 0.0, "NOCHMAL: fresh run")
	check(pressure.world_index == 0 and pressure.world_start == 0.0 and not pressure.final_world, "NOCHMAL: world 1 timeline")
	check(is_equal_approx(battle.director.world_hp, 1.0) and is_equal_approx(horde.damage_mult, 1.0) and battle.director.clock_offset == 0.0, "NOCHMAL: world 1 scaling")
	check(not hud.result_visible() and worlds.fade == 0.0, "NOCHMAL: result and fade gone")
	print("victory: boss %.0f hp, won %d" % [boss_hp, won])
	_finish("victory")


func _kill(boss: Node3D, horde: Node3D) -> void:
	for k in 60:
		if boss.is_targetable():
			break
		boss.step(DT)
	boss.state = boss.State.RECOVER
	boss.timer = 5.0
	horde.apply_hits({horde.BOSS_SLOT: {"damage": 1000000.0, "dir": Vector3.RIGHT}})


func _until(boss: Node3D, hero: Node3D, done: Callable, limit := 600) -> void:
	for k in limit:
		if done.call():
			return
		boss.step(DT)
		hero.step(DT, Vector2.ZERO)


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
