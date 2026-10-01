extends SceneTree

# Stage 2 Teil B §1/§2 on the real map (main.tscn):
#   - packs come from several sides (2 -> 4), light packs are mixed from 0:40
#   - Renner are faster than the hero
#   - a wave is announced (banner, edge arrow) before it spawns, comes from the
#     announced side, outside the view; the next one 45-60 s later

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
	var camera: Camera3D = main.get_node("Camera3D")
	main.snap_camera()
	director.camera = camera
	await process_frame
	var at: Vector3 = hero.position
	# --- pack sides
	check(director.side_count(20.0) == 2 and director.side_count(300.0) == 4, "2 sides early, 4 late")
	var sectors := {}
	var mixed_packs := 0
	var late_packs := 0
	var t := 0.0
	while t <= 200.0:
		var before: int = horde.count()
		var packs_before: int = director.packs
		director.step(0.1, t, at)
		if director.packs > packs_before and t >= 60.0:
			sectors[int(floor(fposmod(director.last_angle, TAU) / (TAU / 8.0)))] = true
		if director.packs > packs_before and t >= T.RENNER_FROM + 5.0:
			var kinds := {}
			for i in range(before, horde.count()):
				kinds[horde.kind_of(i)] = true
			if horde.count() - before >= 4:
				late_packs += 1
				if kinds.has(T.Kind.WICHTEL) and kinds.has(T.Kind.RENNER):
					mixed_packs += 1
		# Keep room: the living count stays below the wanted density.
		if horde.count() > 60:
			horde.clear()
		t += 0.1
	print("pack sectors ", sectors.keys(), " mixed ", mixed_packs, "/", late_packs)
	check(sectors.size() >= 4, "packs come from many sides (%d of 8 sectors)" % sectors.size())
	check(late_packs > 0 and mixed_packs * 3 >= late_packs, "light packs are mixed after 0:40 (%d/%d)" % [mixed_packs, late_packs])
	horde.clear()
	for k in 30:
		horde.spawn(T.Kind.RENNER, battle.arena.safe_spawn(at + Vector3(20, 0, 0), 0.5))
	var slowest := INF
	for i in horde.count():
		slowest = minf(slowest, horde.speed_of(i))
	check(slowest > T.HERO_SPEED, "every Renner is faster than the hero (%.2f > %.2f)" % [slowest, T.HERO_SPEED])
	horde.clear()
	# --- announced wave
	director.reset()
	pressure.reset()
	var announce_at := -1.0
	var spawn_at := -1.0
	var banner_seen := false
	var arrow_seen := false
	var lane_seen := false
	var spawned_from := -1
	t = 40.0
	while t < 70.0 and spawn_at < 0.0:
		var before: int = horde.count()
		pressure.step(0.05, t, true)
		if announce_at < 0.0 and pressure.wave_state == 1:
			announce_at = t
		if pressure.wave_state == 1:
			banner_seen = banner_seen or pressure.banner == "WELLE!"
			arrow_seen = arrow_seen or pressure.arrow_dir != Vector3.ZERO
			lane_seen = lane_seen or pressure.lane_visible()
		if horde.count() > before:
			spawn_at = t
			spawned_from = before
		t += 0.05
	print("wave announced %.2f spawned %.2f count %d" % [announce_at, spawn_at, horde.count()])
	check(announce_at >= PT.WAVE_FIRST - PT.WAVE_WARNING - 0.1 and announce_at < PT.WAVE_FIRST, "first wave announced before 0:50 (%.1f)" % announce_at)
	check(spawn_at - announce_at >= PT.WAVE_WARNING - 0.06, "warning runs before the spawn (%.2f s)" % (spawn_at - announce_at))
	check(banner_seen and arrow_seen, "WELLE! banner and edge arrow during the warning")
	check(lane_seen, "ground lane towards the incoming side during the warning")
	check(spawned_from >= 0 and horde.count() >= 10, "a wave is big (%d)" % horde.count())
	var wave_dir := Vector3(cos(pressure.wave_angle), 0.0, sin(pressure.wave_angle))
	var along := 0
	var in_view := 0
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		if (p - at).normalized().dot(wave_dir) > 0.6:
			along += 1
		if director.in_view(p, at):
			in_view += 1
	check(along >= horde.count() * 0.9, "the wave comes from the announced side (%d/%d)" % [along, horde.count()])
	check(in_view == 0, "wave spawns outside the view (%d)" % in_view)
	var gap: float = pressure.wave_next - spawn_at
	check(gap >= 45.0 - 0.2 and gap <= 60.0 + 0.2, "next wave in 45-60 s (%.1f)" % gap)
	check(pressure.events_of("announce").size() == 1 and pressure.events_of("spawn").size() == 1, "one announce, one spawn logged")
	_finish("waves")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
