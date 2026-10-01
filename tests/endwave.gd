extends SceneTree

# Stage 2 Teil B §5 on the real map: the Endwelle from 6:00 - announced, pack
# sizes grow exponentially, enemies get tougher, the living count stays at
# the 250 cap (performance), waves come faster.

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")

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
	var director: RefCounted = battle.director
	var horde: Node3D = battle.horde
	var hero: Node3D = battle.hero
	var pressure: Node = battle.pressure
	main.snap_camera()
	director.camera = main.get_node("Camera3D")
	await process_frame
	var at: Vector3 = hero.position
	# Nothing before 6:00.
	pressure.boss_state = pressure.Boss.DEFEATED
	pressure.step(0.1, PT.END_AT - 1.0, true)
	check(not pressure.endwave_on and director.endwave == 0.0, "no Endwelle before 6:00")
	pressure.step(0.1, PT.END_AT + 0.05, true)
	check(pressure.endwave_on and pressure.banner == "ENDWELLE!", "ENDWELLE! announced at 6:00")
	check(director.wanted(PT.END_AT + 1.0) == T.ENEMY_CAP, "wanted = cap during the Endwelle")
	# Pack size: average spawned per pack early vs. 90 s in.
	var early := _pack_average(director, horde, at, PT.END_AT, 0.0)
	var late := _pack_average(director, horde, at, PT.END_AT + 90.0, 90.0)
	print("pack average %.1f -> %.1f" % [early, late])
	check(late >= early * 3.0, "packs grow exponentially (%.1f -> %.1f)" % [early, late])
	director.endwave = 0.0
	var hp0: float = director.hp_mult()
	director.endwave = 90.0
	check(director.hp_mult() > 1.6 and hp0 == 1.0, "enemies get tougher (x%.2f)" % director.hp_mult())
	var i: int = horde.spawn(T.Kind.WICHTEL, at + Vector3(30, 0, 0), false, director.hp_mult(), director.speed_mult())
	check(horde.health_of(i) > T.enemy(T.Kind.WICHTEL).hp * 1.6, "spawned with more health")
	check(horde.speed_of(i) < T.HERO_SPEED, "Wichtel stay slower than the hero")
	# Performance cap: 60 s of Endwelle spawning never exceeds 250 living.
	horde.clear()
	var most := 0
	var t := 0.0
	while t < 60.0:
		director.endwave = 120.0 + t
		director.step(0.1, PT.END_AT + 120.0 + t, at)
		most = maxi(most, horde.count())
		t += 0.1
	check(most <= T.ENEMY_CAP and most >= T.ENEMY_CAP - 20, "living count held at the cap (%d)" % most)
	# Waves come every END_WAVE_INTERVAL s.
	horde.clear()
	pressure.wave_state = 0
	pressure.wave_next = PT.END_AT + 10.0
	var spawned := []
	t = PT.END_AT + 5.0
	while t < PT.END_AT + 60.0:
		var before: int = pressure.wave_index
		pressure.step(0.1, t, true)
		if pressure.wave_index > before:
			spawned.append(t)
			horde.clear()
		t += 0.1
	print("endwave waves at ", spawned)
	check(spawned.size() >= 2 and absf(float(spawned[1]) - float(spawned[0]) - PT.END_WAVE_INTERVAL) < 0.3, "waves every %.0f s" % PT.END_WAVE_INTERVAL)
	_finish("endwave")


func _pack_average(director: RefCounted, horde: Node3D, at: Vector3, elapsed: float, endwave: float) -> float:
	var made := 0
	var packs := 0
	for k in 30:
		horde.clear()
		director.endwave = endwave
		director.pack_clock = 0.0
		var before: int = director.packs
		director.step(0.05, elapsed, at)
		if director.packs > before:
			packs += 1
			made += horde.count()
	return float(made) / maxf(1.0, float(packs))


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
