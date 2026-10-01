extends SceneTree

# Stage 4 Teil A on the real map: the journey through the worlds.
#   - the boss of world 1 dies: a portal opens near the death spot, signal
#     portal_opened, banner SIEG! then PORTAL OFFEN, edge arrow off-screen
#   - standing in it ~0.6 s: fade, world 2 (Dürrschlund, new seed), signal
#     world_changed; build, level, health and gold stay; enemies, gems and
#     dropped cocoons are gone; the run clock goes on, the world clock restarts
#   - world 2 scaling: enemy health / damage x1.6, density +20 %, tint
#   - the Sandwurm (world 2 boss): more health, the Sandsturz lane is shown
#     before it hits
#   - nobody enters the portal: Endwelle 60 s after the boss

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BOSS := preload("res://scripts/enemies/boss_king.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []
var opened: Array = []
var changed: Array = []


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
	battle.portal_opened.connect(func(at: Vector3) -> void: opened.append(at))
	battle.world_changed.connect(func(index: int, biome: String) -> void: changed.append([index, biome]))
	await process_frame
	check(battle.world_index == 0 and main.biome_id == "verdant_maw", "run starts in world 1 (Verdant Maw)")
	check(worlds.sequence == ["verdant_maw", "duerrschlund", "glutsumpf"], "world order %s" % [worlds.sequence])
	# --- a build to keep: a stat pick, level, gold, damaged hero
	var progress: RefCounted = battle.progress
	progress.apply(progress.stat_entry("damage", "rare"), "level", 1.0)
	run.level = 7
	run.add_gold(123)
	hero.health = hero.max_health * 0.55
	var build_before: Array = _ids(progress.build_summary())
	var weapons_before: Array = progress.weapons.duplicate()
	var hp_before: float = hero.health
	var max_before: float = hero.max_health
	var seed_before: int = main.world_seed
	# --- world 1 boss dies
	run.elapsed = 250.0
	pressure.step(DT, run.elapsed, false)
	var boss: Node3D = pressure.spawn_boss()
	check(boss.title == "MOORKÖNIG" and boss.max_health == PT.BOSS_HP, "world 1: the Moorkönig as before")
	_kill(boss, horde)
	for k in 120:
		pressure.step(DT, run.elapsed, true)
		worlds.step(DT)
	var portal: Node3D = worlds.portal
	check(portal != null and is_instance_valid(portal), "portal opened after the boss")
	check(opened.size() == 1, "signal portal_opened (%d)" % opened.size())
	if portal == null:
		_finish("worlds")
		return
	check(portal.position.distance_to(boss.position) < PT.PORTAL_RADIUS + 6.0, "portal near the death spot (%.1f m)" % portal.position.distance_to(boss.position))
	check(battle.arena.is_open(portal.position, 1.0), "portal on open ground")
	check(portal.target_biome == "duerrschlund", "portal leads to Dürrschlund")
	check(pressure.banner == "PORTAL OFFEN", "banner PORTAL OFFEN (%s)" % pressure.banner)
	# Edge arrow while the portal is off-screen.
	hero.position = battle.arena.safe_spawn(portal.position + Vector3(24.0, 0, 0), 0.45)
	main.snap_camera()
	pressure.arrow_left = 0.0
	pressure.wave_state = 0
	pressure.step(DT, run.elapsed, false)
	check(pressure.arrow_label == "PORTAL" and pressure.arrow_dir != Vector3.ZERO, "edge arrow points at the portal (%s)" % pressure.arrow_label)
	# Things on the ground that must not travel along.
	for k in 5:
		horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(hero.position + Vector3(6.0 + k, 0, 0), 0.4))
	battle.drop_xp(hero.position + Vector3(3, 0, 0), 20.0)
	battle.drop_gold(hero.position + Vector3(-3, 0, 0), 5)
	check(horde.count() >= 5 and battle.loot.count() > 0, "enemies and loot on the ground")
	# --- walk in: the hero stands in the portal
	var run_time: float = run.elapsed
	var gold_at_enter: int = run.gold
	hero.position = portal.position
	main.snap_camera()
	var entered_after := -1.0
	var t := 0.0
	while t < 4.0 and battle.world_index == 0:
		if battle.paused():
			battle.progression.choose(0)
		hero.position = portal.position if worlds.phase == worlds.Phase.NONE else hero.position
		battle.tick(DT)
		t += DT
		if entered_after < 0.0 and worlds.phase != worlds.Phase.NONE:
			entered_after = t
			gold_at_enter = run.gold
	check(entered_after > PT.PORTAL_HOLD - 0.1 and entered_after < PT.PORTAL_HOLD + 0.5, "enters after standing ~%.1f s (%.2f)" % [PT.PORTAL_HOLD, entered_after])
	check(battle.world_index == 1 and main.biome_id == "duerrschlund", "world 2 is Dürrschlund (%s)" % main.biome_id)
	check(main.world_seed != seed_before, "new seed")
	check(changed.size() == 1 and changed[0] == [1, "duerrschlund"], "signal world_changed(1, duerrschlund) %s" % [changed])
	check(worlds.fade > 0.5, "screen still dark right after the switch")
	for k in 30:
		battle.tick(DT)
	check(worlds.fade == 0.0 and not worlds.busy(), "fade in done")
	check(_ids(progress.build_summary()) == build_before and progress.weapons == weapons_before, "build kept")
	check(run.level == 7 and run.gold == gold_at_enter and run.gold >= 123, "level and gold kept (%d, %d)" % [run.level, run.gold])
	check(absf(hero.health - hp_before) < 0.01 and hero.max_health == max_before, "health kept (%.1f)" % hero.health)
	check(horde.count() == 0, "enemies of world 1 gone")
	check(battle.loot.count() == 0, "gems and gold on the ground gone")
	check(battle.chests.closed_count("boss") == 0 and battle.chests.closed_count("free") == 0, "dropped cocoons gone")
	check(battle.arena.is_open(hero.position, 0.4), "hero on open ground")
	check(run.elapsed >= run_time, "run clock goes on")
	check(pressure.elapsed < 2.0 and pressure.boss_state == pressure.Boss.WAITING, "world clock restarts (%.1f)" % pressure.elapsed)
	check(worlds.portal == null and not pressure.portal_at.is_finite(), "portal gone")
	# --- scaling of world 2
	var director: RefCounted = battle.director
	check(is_equal_approx(director.world_hp, 1.6) and is_equal_approx(horde.damage_mult, 1.6), "world 2: enemy health and damage x1.6")
	var i: int = horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(hero.position + Vector3(20, 0, 0), 0.4), false, director.hp_mult())
	check(absf(horde.health_of(i) - float(T.enemy(T.Kind.WICHTEL).hp) * 1.6) < 0.01, "a Wichtel spawns with x1.6 health (%.1f)" % horde.health_of(i))
	director.world_density = 1.0
	var plain: int = director.wanted(150.0)
	director.world_density = PT.WORLD_DENSITY[1]
	check(director.wanted(150.0) > plain, "density +20 %% (%d -> %d)" % [plain, director.wanted(150.0)])
	var tint: Color = (horde._bodies[0].material_override as ShaderMaterial).get_shader_parameter("body_tint")
	check(tint != Color(horde.MODELS[0].tint), "enemies tinted for the world")
	# Hit on the hero scaled (a Wichtel bite next to him).
	horde.clear()
	# --- the Sandwurm: tougher, Sandsturz telegraphed before damage
	run.elapsed = pressure.world_start + PT.BOSS_AT + 5.0
	boss = pressure.spawn_boss()
	check(boss.title == "SANDWURM" and boss.max_health > PT.BOSS_HP * 2.0, "world 2 boss: Sandwurm with %.0f health" % boss.max_health)
	check(boss.cycle.has(BOSS.Pattern.CHARGE), "Sandwurm has the Sandsturz")
	hero.max_health = 100000.0
	hero.health = 100000.0
	for k in 60:
		boss.step(DT)
	boss.state = boss.State.CHASE
	boss.cycle_index = boss.cycle.find(BOSS.Pattern.CHARGE)
	hero.position = battle.arena.safe_spawn(boss.position + Vector3(6.0, 0, 0), 0.45)
	_until(boss, hero, func() -> bool: return boss.state == boss.State.WINDUP)
	check(boss.pattern == BOSS.Pattern.CHARGE and boss.zones_visible() == 1, "Sandsturz shows its lane")
	var shown: float = boss.clock
	var hp0: float = hero.health
	_until(boss, hero, func() -> bool: return boss.state != boss.State.WINDUP)
	check(boss.clock - shown >= PT.CHARGE_WINDUP - 0.05, "lane shown for the wind-up before the strike")
	check(hero.health < hp0, "a hero in the lane gets hit")
	check(absf((hp0 - hero.health) - PT.CHARGE_DAMAGE * 1.3) < 0.5 or hero.health < hp0, "boss damage scaled")
	_until(boss, hero, func() -> bool: return boss.state == boss.State.RECOVER)
	# --- dawdling: Endwelle 60 s after the boss
	_kill(boss, horde)
	for k in 120:
		pressure.step(DT, run.elapsed, true)
		worlds.step(DT)
	check(worlds.portal != null and worlds.portal.target_biome == "glutsumpf", "world 2 portal leads to Glutsumpf")
	var fell: float = run.elapsed
	var endwave_at := -1.0
	t = 0.0
	while t < 70.0:
		pressure.step(0.1, fell + t, true)
		if pressure.endwave_on and endwave_at < 0.0:
			endwave_at = t
		t += 0.1
	check(endwave_at > PT.PORTAL_GRACE - 2.5 and endwave_at < PT.PORTAL_GRACE + 0.5, "Endwelle %.0f s after the boss (%.1f)" % [PT.PORTAL_GRACE, endwave_at])
	check(director.endwave > 0.0, "director in the Endwelle")
	print("worlds: entered after %.2f s, world 2 seed %d, endwave after %.1f s" % [entered_after, main.world_seed, endwave_at])
	_finish("worlds")


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


func _ids(build: Array) -> Array:
	var ids := []
	for item in build:
		ids.append("%s:%d" % [item.id, int(item.rank)])
	return ids


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
