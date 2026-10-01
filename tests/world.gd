extends SceneTree

# Stage 01 Teil A: the world ported from Mawlings. Checks on scenes/main.tscn:
#   - the same seed builds the same map (wall field, stones, start point), a
#     different seed a different one; every biome builds;
#   - motion into a wall slides along it (never enters, keeps moving);
#   - safe_spawn / spawn_point_near / spawn_points land on open ground;
#   - flow_direction leads a body around a wall to the focus (straight line
#     blocked, walking it arrives).

const SEED := 4242
const OTHER_SEED := 777
const RADIUS := 0.6

var failures: Array[String] = []
var scene: Node
var arena: Variant


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	arena = scene.get_node("Arena")
	check(scene.get("hero") is Node3D and scene.get("arena") == arena, "Main exposes hero and arena")
	_check_determinism()
	var slide := _check_slide()
	var spawns := _check_spawns()
	var detour := _check_flow()
	_check_biomes()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS world: seed %d deterministic, slide %s, spawns %s, flow detour %s, biomes verdant/glutsumpf/duerrschlund build" % [SEED, slide, spawns, detour])
	quit(0)


# Fingerprint of a map: wall distances on a coarse raster, stones, start point.
func _fingerprint() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var rect: Rect2 = arena.playable_rect()
	for iz in 24:
		for ix in 24:
			var point := Vector3(rect.position.x + (float(ix) + 0.5) * rect.size.x / 24.0, 0.0, rect.position.y + (float(iz) + 0.5) * rect.size.y / 24.0)
			values.append(snappedf(arena.wall_distance(point), 0.001))
	for stone in arena.layout.stones:
		values.append(snappedf(stone.x, 0.001))
		values.append(snappedf(stone.z, 0.001))
	var start: Vector3 = arena.spawn_points(1)[0]
	values.append(start.x)
	values.append(start.z)
	return values


func _check_determinism() -> void:
	arena.set_seed(SEED)
	check(arena.has_layout(), "Seed %d builds a layout" % SEED)
	var first := _fingerprint()
	arena.set_seed(OTHER_SEED)
	var other := _fingerprint()
	arena.set_seed(SEED)
	var again := _fingerprint()
	check(first == again, "Same seed, same map")
	check(first != other, "Other seed, other map")
	arena.set_seed(0)
	check(not arena.has_layout(), "Seed 0 is the classic open map")
	arena.set_seed(SEED)
	var rect: Rect2 = arena.playable_rect()
	check(rect.size.x > 300.0 and rect.has_point(Vector2(arena.map_center().x, arena.map_center().z)), "Playable rect around the map centre")


# Walk diagonally into walls from many spots next to them: the body never
# ends inside (wall distance >= radius - 0.1) and keeps sliding along.
func _check_slide() -> String:
	var tested := 0
	var slid := 0
	var rect: Rect2 = arena.playable_rect()
	for step in 3000:
		if tested >= 40:
			break
		var point := Vector3(rect.position.x + fmod(float(step) * 37.3, rect.size.x), 0.0, rect.position.y + fmod(float(step) * 61.7, rect.size.y))
		var distance: float = arena.wall_distance(point)
		if distance < 1.2 or distance > 1.6 or not arena.is_open(point, RADIUS):
			continue
		var slope: Vector2 = arena.layout.gradient(point.x, point.z)
		if slope.length_squared() < 0.0001:
			continue
		slope = slope.normalized()
		# 45 degrees into the wall: half against it, half along it.
		var into := Vector3(-slope.x, 0.0, -slope.y)
		var along := Vector3(-slope.y, 0.0, slope.x)
		var heading := (into + along).normalized()
		tested += 1
		var body := point
		var inside := false
		for frame in 90:
			body = arena.resolve_motion(body, heading * 6.0 / 60.0, RADIUS)
			if arena.wall_distance(body) < RADIUS - 0.1 or not arena.playable_rect().has_point(Vector2(body.x, body.z)):
				inside = true
		check(not inside, "Body entered a wall near %s" % point)
		# 9 m of input; at least 2 m of progress along the wall.
		if (body - point).length() > 2.0:
			slid += 1
	check(tested >= 20, "Enough wall spots tested (%d)" % tested)
	check(slid >= int(tested * 0.8), "Bodies slide along walls (%d of %d)" % [slid, tested])
	return "%d/%d" % [slid, tested]


func _check_spawns() -> String:
	var rect: Rect2 = arena.playable_rect()
	var tested := 0
	var in_wall := 0
	for step in 400:
		var point := Vector3(rect.position.x + fmod(float(step) * 53.1, rect.size.x), 0.0, rect.position.y + fmod(float(step) * 29.9, rect.size.y))
		if arena.wall_distance(point) < 0.0:
			in_wall += 1
		var spot: Vector3 = arena.safe_spawn(point, RADIUS)
		tested += 1
		check(arena.is_open(spot, RADIUS - 0.05), "safe_spawn %s -> %s is open" % [point, spot])
	check(in_wall > 20, "Some safe_spawn probes started inside walls (%d)" % in_wall)
	var start: Vector3 = arena.spawn_points(1)[0]
	check(arena.is_open(start, 3.0), "Start point open")
	arena.sync(start)
	arena.finish_flow(start)
	var found := 0
	for index in 12:
		var spot: Vector3 = arena.spawn_point_near(start, 16.0, TAU * float(index) / 12.0, RADIUS)
		if spot.is_finite():
			found += 1
			check(arena.is_open(spot, RADIUS), "spawn_point_near open")
	check(found >= 8, "spawn_point_near finds ring spots (%d of 12)" % found)
	return "%d safe (%d from walls), ring %d/12" % [tested, in_wall, found]


# Pairs where a wall blocks the straight line (walk 16-40 m for 12 m apart):
# following flow_direction must arrive.
func _check_flow() -> String:
	var rect: Rect2 = arena.playable_rect()
	var cases := 0
	var arrived := 0
	var detours := PackedFloat32Array()
	var fields := 0
	for step in 6000:
		if cases >= 6 or fields >= 24:
			break
		var target := Vector3(rect.position.x + 20.0 + fmod(float(step) * 41.3, rect.size.x - 40.0), 0.0, rect.position.y + 20.0 + fmod(float(step) * 67.9, rect.size.y - 40.0))
		if arena.wall_distance(target) < 2.0:
			continue
		# Cheap filters first: start points 12 m away, open, with solid wall
		# (not just a grazed corner) on the straight line.
		var starts: Array[Vector3] = []
		for index in 24:
			var angle := TAU * float(index) / 24.0
			var from: Vector3 = target + Vector3(cos(angle), 0.0, sin(angle)) * 12.0
			if not arena.is_open(from, 1.0) or arena.wall_distance(from) < 2.0:
				continue
			var deepest := INF
			for sample in 25:
				var probe: Vector3 = from.lerp(target, float(sample) / 24.0)
				deepest = minf(deepest, arena.wall_distance(probe))
			if deepest <= -1.0:
				starts.append(from)
		if starts.is_empty():
			continue
		fields += 1
		arena.sync(target)
		arena.finish_flow(target)
		var used := 0
		for from in starts:
			if used >= 2 or cases >= 6:
				break
			var walk: float = arena.flow_distance(from)
			if not is_finite(walk) or walk > 60.0:
				continue
			used += 1
			cases += 1
			var body := from
			var travelled := 0.0
			var lowest := INF
			for frame in 1200:
				var direction: Vector3 = arena.flow_direction(body, RADIUS)
				if direction == Vector3.ZERO:
					break
				var moved: Vector3 = arena.resolve_motion(body, direction * 5.0 / 60.0, RADIUS)
				travelled += (moved - body).length()
				body = moved
				lowest = minf(lowest, arena.wall_distance(body))
				if Vector2(body.x - target.x, body.z - target.z).length() < 1.5:
					break
			var left := Vector2(body.x - target.x, body.z - target.z).length()
			check(left < 1.5, "flow_direction from %s reaches %s (stopped %.1f m away)" % [from, target, left])
			if left < 1.5:
				arrived += 1
				detours.append(travelled)
				check(travelled > 11.0 and lowest >= RADIUS - 0.1, "Walk went around the wall, not through it (%.1f m for 10.5 m straight, wall distance >= %.2f)" % [travelled, lowest])
	check(cases >= 4, "Enough blocked pairs for the flow check (%d)" % cases)
	var mean := 0.0
	for value in detours:
		mean += value
	mean /= maxf(1.0, float(detours.size()))
	return "%d/%d arrive (12 m apart, mean walk %.1f m)" % [arrived, cases, mean]


func _check_biomes() -> void:
	arena.chunk_budget = 0
	for id in ["glutsumpf", "duerrschlund", "verdant_maw"]:
		arena.set_biome(id)
		arena.set_seed(SEED)
		arena.finish_rebuild()
		var start: Vector3 = arena.spawn_points(1)[0]
		arena.sync(start)
		arena.finish_rebuild()
		check(arena.chunks.size() >= 4, "%s builds chunks" % id)
		check(arena.has_layout() and arena.is_open(start, 2.0), "%s start open" % id)
