extends Node3D

# Stub arena for the combat lab (stage 1, Teil B): flat ground with a few box
# walls and the same API as the real arena of Teil A (scripts/world/arena.gd),
# so hero, enemies and director run against either one.
#
#   sync(focus), resolve_motion(start, motion, radius), is_open(point, radius),
#   safe_spawn(point, radius), spawn_point_near(center, radius, angle, clearance),
#   playable_rect(), map_center(), set_seed(seed), has_layout(), flow_direction(from, radius)

const HALF_SIZE := 60.0
const WALL_HEIGHT := 1.6

## Walls as Rect2 in the XZ plane (x, z, width, depth).
var walls: Array[Rect2] = [
	Rect2(-14.0, -9.0, 7.0, 1.4),
	Rect2(8.0, 6.0, 1.4, 8.0),
	Rect2(-3.0, 15.0, 10.0, 1.4),
	Rect2(18.0, -16.0, 6.0, 6.0),
	Rect2(-24.0, 12.0, 5.0, 5.0),
]
var focus := Vector3.ZERO
var _seed := 0
var _built := false


func _ready() -> void:
	_build()


func sync(point: Vector3) -> void:
	focus = point


func set_seed(value: int) -> void:
	_seed = value


func has_layout() -> bool:
	return false


func playable_rect() -> Rect2:
	return Rect2(-HALF_SIZE, -HALF_SIZE, HALF_SIZE * 2.0, HALF_SIZE * 2.0)


func map_center() -> Vector3:
	return Vector3.ZERO


## Moves a circle of `radius` from `start` by `motion`, sliding along walls.
func resolve_motion(start: Vector3, motion: Vector3, radius: float) -> Vector3:
	var p := Vector3(start.x + motion.x, 0.0, start.z + motion.z)
	for wall in walls:
		p = _push_out(p, wall, radius)
	var lim := HALF_SIZE - radius
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	return p


func is_open(point: Vector3, radius: float) -> bool:
	if absf(point.x) > HALF_SIZE - radius or absf(point.z) > HALF_SIZE - radius:
		return false
	for wall in walls:
		if _distance_to_rect(point, wall) < radius:
			return false
	return true


func safe_spawn(point: Vector3, radius: float) -> Vector3:
	if is_open(point, radius):
		return point
	for ring in range(1, 12):
		for k in 12:
			var a := TAU * float(k) / 12.0
			var candidate := point + Vector3(cos(a), 0.0, sin(a)) * float(ring) * 0.8
			if is_open(candidate, radius):
				return candidate
	return point


func spawn_point_near(center: Vector3, radius: float, angle: float, clearance: float) -> Vector3:
	for attempt in 6:
		var a := angle + float(attempt) * 0.37
		var r := radius + float(attempt) * 0.9
		var candidate := Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
		if is_open(candidate, clearance):
			return candidate
	return Vector3.INF


## Straight line to the focus, bent around a wall that is directly in the way.
func flow_direction(from: Vector3, _radius := 0.6) -> Vector3:
	var to := Vector3(focus.x - from.x, 0.0, focus.z - from.z)
	if to.length_squared() < 0.0001:
		return Vector3.ZERO
	var dir := to.normalized()
	var probe := from + dir * 2.0
	for wall in walls:
		if _distance_to_rect(probe, wall) < 0.8:
			var side := Vector3(-dir.z, 0.0, dir.x)
			var centre := Vector3(wall.get_center().x, 0.0, wall.get_center().y)
			if side.dot(from - centre) < 0.0:
				side = -side
			return (dir * 0.3 + side).normalized()
	return dir


func _push_out(p: Vector3, wall: Rect2, radius: float) -> Vector3:
	var nearest := Vector2(clampf(p.x, wall.position.x, wall.end.x), clampf(p.z, wall.position.y, wall.end.y))
	var offset := Vector2(p.x, p.z) - nearest
	var d := offset.length()
	if d >= radius:
		return p
	if d > 0.0001:
		var out := nearest + offset / d * radius
		return Vector3(out.x, 0.0, out.y)
	# Centre inside the box: leave by the nearest side.
	var left := p.x - wall.position.x
	var right := wall.end.x - p.x
	var top := p.z - wall.position.y
	var bottom := wall.end.y - p.z
	var least := minf(minf(left, right), minf(top, bottom))
	if least == left:
		return Vector3(wall.position.x - radius, 0.0, p.z)
	if least == right:
		return Vector3(wall.end.x + radius, 0.0, p.z)
	if least == top:
		return Vector3(p.x, 0.0, wall.position.y - radius)
	return Vector3(p.x, 0.0, wall.end.y + radius)


func _distance_to_rect(p: Vector3, wall: Rect2) -> float:
	var nearest := Vector2(clampf(p.x, wall.position.x, wall.end.x), clampf(p.z, wall.position.y, wall.end.y))
	return (Vector2(p.x, p.z) - nearest).length()


func _build() -> void:
	if _built:
		return
	_built = true
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF_SIZE * 2.0, HALF_SIZE * 2.0)
	ground.mesh = plane
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 cell = floor(wp.xz / 4.0);
	float check = mod(cell.x + cell.y, 2.0);
	vec2 g = abs(fract(wp.xz / 4.0) - 0.5);
	float line = smoothstep(0.485, 0.5, max(g.x, g.y));
	vec3 base = mix(vec3(0.34, 0.52, 0.27), vec3(0.31, 0.48, 0.25), check);
	ALBEDO = mix(base, vec3(0.25, 0.4, 0.2), line * 0.6);
	ROUGHNESS = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	ground.material_override = material
	add_child(ground)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.46, 0.4, 0.36)
	wall_material.roughness = 1.0
	for wall in walls:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(wall.size.x, WALL_HEIGHT, wall.size.y)
		box.mesh = mesh
		box.material_override = wall_material
		box.position = Vector3(wall.get_center().x, WALL_HEIGHT * 0.5, wall.get_center().y)
		add_child(box)
