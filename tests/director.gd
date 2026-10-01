extends SceneTree

# Director (stage 1, Teil B §5) on the real map (main.tscn): packs spawn
# outside the camera view, density rises over 5 minutes, Renner from 40 s,
# Brocken from 90 s, never more than 250 living enemies.

const T := preload("res://scripts/core/tuning.gd")

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
	var camera: Camera3D = main.get_node("Camera3D")
	main.snap_camera()
	director.camera = camera
	await process_frame
	var at: Vector3 = hero.position
	# The wanted density climbs and ends at the cap.
	check(director.wanted(0.0) < director.wanted(60.0), "density rises in minute one")
	check(director.wanted(60.0) < director.wanted(180.0), "density rises to minute three")
	check(director.wanted(180.0) < director.wanted(300.0), "density rises to minute five")
	check(director.wanted(300.0) == T.ENEMY_CAP and director.wanted(600.0) == T.ENEMY_CAP, "250 at 5 min and after")
	# Simulate 5 minutes of spawning (enemies stand still; nobody dies).
	var counts := {}
	var seen_in_view := 0
	var too_close := 0
	var first_renner := INF
	var first_brocken := INF
	var t := 0.0
	var dt := 0.1
	while t <= 300.0:
		var before: int = horde.count()
		director.step(dt, t, at)
		for i in range(before, horde.count()):
			var p: Vector3 = horde.position_of(i)
			if _visible(camera, p):
				seen_in_view += 1
			if p.distance_to(at) < T.SPAWN_MIN_DISTANCE - 3.0:
				too_close += 1
			var kind: int = horde.kind_of(i)
			if kind == T.Kind.RENNER:
				first_renner = minf(first_renner, t)
			elif kind == T.Kind.BROCKEN:
				first_brocken = minf(first_brocken, t)
		for mark in [30, 120, 240, 300]:
			if absf(t - float(mark)) < dt * 0.5:
				counts[mark] = horde.count()
		t += dt
	print("counts ", counts, " spawned ", director.spawned, " packs ", director.packs, " first renner ", first_renner, " first brocken ", first_brocken)
	check(int(counts.get(30, 0)) > 0, "enemies arrive in the first half minute")
	check(int(counts.get(30, 0)) < int(counts.get(120, 0)) and int(counts.get(120, 0)) < int(counts.get(240, 0)), "living count rises over time")
	check(int(counts.get(300, 0)) >= T.ENEMY_CAP - 15 and horde.count() <= T.ENEMY_CAP, "close to the 250 cap at 5 min, never above")
	check(seen_in_view == 0, "no spawn inside the camera view (%d)" % seen_in_view)
	check(too_close == 0, "no spawn near the hero (%d)" % too_close)
	check(first_renner >= T.RENNER_FROM and first_renner < T.RENNER_FROM + 10.0, "Renner from 40 s (first %.1f)" % first_renner)
	check(first_brocken >= T.BROCKEN_FROM and first_brocken < T.BROCKEN_FROM + 10.0, "Brocken from 90 s (first %.1f)" % first_brocken)
	var average := float(director.spawned) / maxf(1.0, float(director.packs))
	check(director.packs > 20 and average >= 2.5 and average <= 13.0, "small packs, not one flood (%d packs, %.1f each)" % [director.packs, average])
	# Hard cap even when asked for more.
	for k in 20:
		director.spawn_pack(300.0, at, 30)
	check(horde.count() <= T.ENEMY_CAP, "cap holds against extra packs")
	# Far enemies are moved back near the hero (recycling).
	horde.clear()
	var far: int = horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(at + Vector3(60, 0, 0), 0.5))
	var far_from: float = horde.position_of(far).distance_to(at)
	director.recycle_clock = 0.0
	director.step(0.1, 10.0, at)
	var far_to: float = horde.position_of(far).distance_to(at)
	check(far_from < director.RECYCLE_DISTANCE or far_to < director.RECYCLE_DISTANCE, "far enemies come back near the hero (%.1f -> %.1f m)" % [far_from, far_to])
	# The live director through battle.tick in the real scene.
	horde.clear()
	director.reset()
	battle.director_enabled = true
	for k in 120:
		battle.tick(1.0 / 30.0)
	check(horde.count() > 0, "battle tick spawns through the director")
	_finish("director")


func _visible(camera: Camera3D, p: Vector3) -> bool:
	for lift in [0.0, 1.0]:
		if camera.is_position_in_frustum(p + Vector3.UP * float(lift)):
			return true
	return false


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
