extends SceneTree

# Stage 2 Teil B §3 on the real map: the champion Brocken comes from 1:30,
# has double health, a gold look, a telegraphed stomp ring (shown before it
# hits, all around him), no knockback, and its death asks the battle for a
# free cocoon and gold.

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
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
	var horde: Node3D = battle.horde
	var hero: Node3D = battle.hero
	var pressure: Node = battle.pressure
	main.snap_camera()
	battle.director.camera = main.get_node("Camera3D")
	await process_frame
	var at: Vector3 = hero.position
	# Schedule: none before 1:30, one right after, the next ~75 s later.
	var t := 60.0
	var first := -1.0
	while t < 100.0:
		pressure.step(0.1, t, true)
		if first < 0.0 and horde.count_elite() > 0:
			first = t
		t += 0.1
	check(first >= PT.ELITE_FROM and first < PT.ELITE_FROM + 3.0, "first champion at 1:30 (%.1f)" % first)
	check(horde.count_elite() == 1 and pressure.banner == "CHAMPION!", "one champion, announced")
	check(absf(pressure.elite_next - first - PT.ELITE_INTERVAL) < 0.2, "next champion ~75 s later")
	var e := -1
	for i in horde.count():
		if horde.is_elite(i):
			e = i
	check(e >= 0 and horde.kind_of(e) == T.Kind.BROCKEN, "champion is a Brocken")
	check(is_equal_approx(horde.health_of(e), T.enemy(T.Kind.BROCKEN).hp * PT.ELITE_HP_MULT), "double health (%.0f)" % horde.health_of(e))
	check(not battle.director.in_view(horde.position_of(e), at), "champion spawns off-screen")
	# Gold look: custom.w of its instance.
	horde.step(DT)
	check(float(horde._pose(e)[1].a) > 0.9, "gold shimmer channel set")
	# Stomp: next to the hero, telegraph first, then the hit lands all around.
	horde.clear()
	hero.health = hero.max_health
	e = horde.spawn(T.Kind.BROCKEN, battle.arena.safe_spawn(at + Vector3(0, 0, -2.6), 1.2), true)
	horde._appear[e] = 1.0
	var shown_at := -1.0
	var hit_at := -1.0
	var time := 0.0
	var hp0: float = hero.health
	for k in 120:
		horde.step(DT)
		hero.step(DT, Vector2.ZERO)
		time += DT
		if shown_at < 0.0 and horde.elite_arcs_visible() > 0:
			shown_at = time
		if hit_at < 0.0 and hero.health < hp0:
			hit_at = time
			break
	print("stomp shown %.2f hit %.2f damage %.0f" % [shown_at, hit_at, hp0 - hero.health])
	check(shown_at >= 0.0 and hit_at > shown_at + PT.ELITE_WINDUP * 0.9, "stomp ring is shown a full wind-up before the hit")
	check(is_equal_approx(hp0 - hero.health, PT.ELITE_DAMAGE), "stomp damage")
	check(horde.arcs_visible() == 0, "no forward arc for the champion (ring instead)")
	# Behind him is not safe: the stomp hits all around.
	horde.clear()
	hero.health = hero.max_health
	hero.invulnerable = 0.0
	e = horde.spawn(T.Kind.BROCKEN, battle.arena.safe_spawn(at + Vector3(0, 0, -2.4), 1.2), true)
	horde._appear[e] = 1.0
	for k in 30:
		horde.step(DT)
		if horde.state_of(e) == horde.State.WINDUP:
			break
	# The hero steps behind him during the wind-up (still within the ring).
	var behind: Vector3 = horde.position_of(e) + (horde.position_of(e) - hero.position).normalized() * 2.2
	hero.position = battle.arena.safe_spawn(behind, 0.45)
	hp0 = hero.health
	for k in 45:
		horde.step(DT)
	check(hero.health < hp0, "the stomp also hits behind him")
	# No knockback, and the death asks for a free cocoon and gold.
	var before: Vector3 = horde.position_of(e)
	horde.apply_hits({e: {"damage": 5.0, "dir": Vector3.RIGHT, "knock": -1.0}})
	check(horde.knock_of(e).length() < 0.01, "champion is not knocked back")
	var chests_before := _chests(battle)
	horde.hurt(e, 10000.0, Vector3.RIGHT)
	check(horde.count_elite() == 0, "champion dies")
	check(pressure.drops.size() == 1 and pressure.drops[0].kind == "elite" and pressure.drops[0].gold == PT.ELITE_GOLD, "drop logged (cocoon + gold)")
	if battle.has_method("drop_chest"):
		check(bool(pressure.drops[0].chest_called) and bool(pressure.drops[0].gold_called), "battle.drop_chest / drop_gold called")
		if chests_before >= 0:
			check(_chests(battle) == chests_before + 1, "a cocoon lies on the ground (%d -> %d)" % [chests_before, _chests(battle)])
	print("drop ", pressure.drops, " knock pos ", before)
	_finish("elite")


func _chests(battle: Node) -> int:
	var chests: Variant = battle.get("chests")
	if chests is Node and chests.has_method("closed_count"):
		return int(chests.closed_count())
	return -1


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
