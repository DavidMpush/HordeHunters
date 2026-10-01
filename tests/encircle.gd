extends SceneTree

# Stage 2 Teil B §2 (Einkesselung) on the real map: from 2:00 every second
# wave is a ring of Wichtel with a bright gap; it is announced (banner, ring
# telegraph, arrow to the gap), the gap stays free while the ring closes, and
# the ring dissolves when the hero gets out through the gap.

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
	# Before 2:00 a wave is never an encircle.
	pressure.elapsed = 100.0
	pressure.announce_wave()
	check(pressure.wave_kind == "wave", "no encircle before 2:00")
	pressure.reset()
	# The first wave after 2:00 is one; the next is a normal wave again.
	pressure.elapsed = 130.0
	pressure.elite_next = 999.0
	pressure.boss_state = pressure.Boss.DEFEATED
	var living: int = horde.count()
	pressure.announce_wave()
	for k in 10:
		pressure.step(DT, 130.0 + float(k) * DT, true)
	check(pressure.wave_kind == "encircle", "first wave after 2:00 is an encircle")
	check(pressure.banner == "EINKESSELUNG!", "EINKESSELUNG! banner")
	check(pressure.ring_visible(), "ring telegraph shown during the warning")
	check(pressure.arrow_dir.dot(Vector3(cos(pressure.ring_gap), 0, sin(pressure.ring_gap))) > 0.99 and pressure.arrow_label == "LÜCKE", "edge arrow points at the gap")
	check(horde.count() == living, "nothing spawns during the warning (%d -> %d)" % [living, horde.count()])
	var made: int = pressure.spawn_wave()
	print("ring members ", made, " gap ", pressure.ring_gap)
	check(made >= 40, "a full ring of Wichtel (%d)" % made)
	check(horde.ring_active and horde.count_ring() == made, "members keep formation")
	var free_gap := _gap_clear(horde, pressure.ring_gap)
	check(free_gap, "the gap is free at the start")
	# Closing: hero stands (invulnerable) in the middle for 3 s.
	var r0: float = horde.ring_radius
	var mean0 := _mean_distance(horde, horde.ring_center)
	for k in 90:
		hero.invulnerable = 10.0
		horde.step(DT)
		pressure.step(DT, 133.0 + float(k) * DT, false)
	var mean1 := _mean_distance(horde, horde.ring_center)
	print("ring radius %.2f -> %.2f, mean distance %.2f -> %.2f" % [r0, horde.ring_radius, mean0, mean1])
	check(horde.ring_radius < r0 - 2.5, "the ring closes (%.1f -> %.1f)" % [r0, horde.ring_radius])
	check(mean1 < mean0 - 2.0, "members walk inwards (%.1f -> %.1f m)" % [mean0, mean1])
	check(_gap_clear(horde, pressure.ring_gap), "the gap stays free while closing")
	check(pressure.wave_kind == "encircle" and pressure.ring_visible(), "ring telegraph follows the ring")
	# Escape through the gap: the ring dissolves into a normal chase.
	var out: Vector3 = horde.ring_center + Vector3(cos(pressure.ring_gap), 0, sin(pressure.ring_gap)) * (horde.ring_radius + PT.RING_ESCAPE + 1.0)
	hero.position = battle.arena.safe_spawn(out, 0.5)
	for k in 3:
		horde.step(DT)
		pressure.step(DT, 136.0, false)
	check(not horde.ring_active and horde.count_ring() == 0, "escaping through the gap dissolves the ring")
	check(pressure.events_of("ring_end").size() == 1 and bool(pressure.events_of("ring_end")[0].escaped), "ring end logged as escape")
	# The next late wave is a normal one.
	pressure.elapsed = 190.0
	pressure.announce_wave()
	check(pressure.wave_kind == "wave", "every second late wave is an encircle")
	_finish("encircle")


## No ring member stands inside the gap sector (with a small tolerance).
func _gap_clear(horde: Node3D, gap: float) -> bool:
	var half: float = PT.RING_GAP * 0.5
	for i in horde.count():
		if not horde.in_ring(i):
			continue
		var offset: Vector3 = horde.position_of(i) - horde.ring_center
		var a := atan2(offset.z, offset.x)
		var along := absf(angle_difference(a, gap)) * offset.length()
		if along < half * 0.8:
			print("member %d in the gap: %.2f m from the gap centre line" % [i, along])
			return false
	return true


func _mean_distance(horde: Node3D, center: Vector3) -> float:
	var total := 0.0
	var n := 0
	for i in horde.count():
		if horde.in_ring(i):
			total += horde.position_of(i).distance_to(center)
			n += 1
	return total / maxf(1.0, float(n))


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
