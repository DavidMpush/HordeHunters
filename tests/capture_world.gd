extends SceneTree

# Review frames of the ported Mawlings world from the game camera. Run WITHOUT
# --headless:
#   Godot --screen 1 --audio-driver Dummy --path . --script res://tests/capture_world.gd
# Output previews/preview_world_<name>.png. The spots match Mawlings
# tests/capture_walls.gd (same seeds and search), so the frames compare 1:1
# with Mawlings previews/preview_walls_*.png:
#   start, ridge, thicket, forest   Verdant meadow with walls (seed 4242)
#   lake                            Verdant lake (water shader)
#   edge_north                      map edge
#   glut_ridge, glut_lake           Glutsumpf (basalt walls, lava)
#   desert_cliffs, desert_cactus    Dürrschlund (seed 31337)

const SEED := 4242
const DESERT_SEED := 31337

var scene: Node
var arena: Variant
var hero: Node3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	arena = scene.get_node("Arena")
	hero = scene.get_node("Hero")
	arena.chunk_budget = 0
	_world(SEED, "verdant_maw")
	var start: Vector3 = arena.spawn_points(1)[0]
	_frame_at(start)
	await _save("start")
	for name in ["ridge", "thicket", "forest"]:
		_frame_at(_find_land(name, start))
		await _save(name)
	var lake := _lake_spot()
	if lake.is_finite():
		_frame_at(lake)
		await _save("lake")
	var rect: Rect2 = arena.playable_rect()
	var mid := rect.get_center()
	_frame_at(Vector3(mid.x + 20.0, 0.0, rect.position.y + 4.0))
	await _save("edge_north")
	_world(SEED, "glutsumpf")
	start = arena.spawn_points(1)[0]
	_frame_at(_find_land("ridge", start))
	await _save("glut_ridge")
	lake = _lake_spot()
	if lake.is_finite():
		_frame_at(lake)
		await _save("glut_lake")
	_world(DESERT_SEED, "duerrschlund")
	start = arena.spawn_points(1)[0]
	var cliffs := _find_land("cliffs", start)
	if cliffs == start:
		cliffs = _find_land("ridge", start)
	_frame_at(cliffs)
	await _save("desert_cliffs")
	_frame_at(_find_land("cactus", start))
	await _save("desert_cactus")
	print("Saved world review frames (previews/preview_world_*.png)")
	quit()


func _world(seed_value: int, biome: String) -> void:
	scene.start_world(seed_value, biome)


func _frame_at(point: Vector3) -> void:
	hero.position = arena.safe_spawn(point, 1.0)
	arena.sync(hero.position)
	arena.finish_rebuild()
	scene.snap_camera()


func _save(name: String) -> void:
	for frame in 30:
		arena.sync(hero.position)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/preview_world_%s.png" % name)


# A spot on the shore of the largest lake (south of it, so the camera looks
# over the water).
func _lake_spot() -> Vector3:
	var basins: Variant = arena.layout.get("basins")
	if not basins is Array or (basins as Array).is_empty():
		return Vector3.INF
	var best: Dictionary = basins[0]
	for basin in basins:
		if float(basin.radius) > float(best.radius):
			best = basin
	var center: Vector3 = best.center
	for step in 40:
		var probe := center + Vector3(0.0, 0.0, float(best.radius) * 0.6 + float(step) * 0.5)
		if arena.is_open(probe, 1.0):
			return probe + Vector3(0.0, 0.0, 1.5)
	return center


# Same search as Mawlings tests/capture_walls.gd: a point of land `name` 2.5-5 m
# from a wall with walls on a few sides.
func _find_land(name: String, start: Vector3) -> Vector3:
	var layout: RefCounted = arena.layout
	var best := start
	var best_score := -INF
	for step in 4000:
		var point := Vector3(fmod(float(step) * 37.3, 300.0) - 150.0, 0.0, fmod(float(step) * 61.7, 300.0) - 150.0)
		if layout.land_at(point.x, point.z) != name:
			continue
		var wall: float = arena.wall_distance(point)
		if wall < 2.5 or wall > 5.0:
			continue
		var score := 0.0
		for angle in 8:
			var probe := point + Vector3(cos(angle * TAU / 8.0), 0.0, sin(angle * TAU / 8.0)) * 8.0
			if arena.wall_distance(probe) < 0.0:
				score += 1.0
		if score > best_score and score <= 5.0:
			best_score = score
			best = point
	return best
