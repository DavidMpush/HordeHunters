extends Node3D

# Visuals shared by the melee and thrown weapons (stage 3): pooled swipe
# crescents (shaders/swipe.gdshader) and short expanding fireballs. Lives as
# a top-level Node3D under a weapon; step(delta) ages everything (paused
# with the run because battle.gd steps the weapons).
#   swipe(at, dir, reach, half_angle, seconds, side, tint, inner)
#   fireball(at, radius, seconds)

const SWIPE_SHADER := preload("res://shaders/swipe.gdshader")
const POOL := 8

var swipes: Array[Dictionary] = []
var fireballs: Array[Dictionary] = []
var _swipe_meshes: Array[MeshInstance3D] = []
var _ball_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY


## A white crescent sweeping round `at` towards `dir` (side -1 sweeps the other
## way). half_angle in rad; reach = outer radius in metres.
func swipe(at: Vector3, dir: Vector3, reach: float, half_angle: float, seconds: float = 0.16, side: float = 1.0,
		tint := Color(0.78, 0.9, 1.0), inner: float = -1.0, height: float = 0.9, lead: float = 0.0) -> void:
	if swipes.size() >= POOL:
		swipes.pop_front()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if flat == Vector3.ZERO:
		flat = Vector3.FORWARD
	# lead: share of the life already passed (a strike that lands on its hit
	# frame shows most of its arc at once, also through a hit stop).
	swipes.append({"at": Vector3(at.x, height, at.z), "dir": flat, "reach": reach, "half": half_angle, "life": seconds,
		"side": side, "tint": tint, "inner": inner if inner >= 0.0 else reach * 0.45, "age": seconds * clampf(lead, 0.0, 0.9)})
	_draw()


func fireball(at: Vector3, radius: float, seconds: float = 0.28) -> void:
	if fireballs.size() >= POOL:
		fireballs.pop_front()
	fireballs.append({"at": at, "radius": radius, "life": seconds, "age": 0.0})
	_draw()


func clear() -> void:
	swipes.clear()
	fireballs.clear()
	_draw()


func step(delta: float) -> void:
	for list in [swipes, fireballs]:
		for index in range(list.size() - 1, -1, -1):
			list[index].age += delta
			if list[index].age >= list[index].life:
				list.remove_at(index)
	_draw()


func active() -> int:
	return swipes.size() + fireballs.size()


func _draw() -> void:
	if not is_inside_tree():
		return
	while _swipe_meshes.size() < swipes.size():
		_swipe_meshes.append(_make_swipe())
	for index in _swipe_meshes.size():
		var part := _swipe_meshes[index]
		if index >= swipes.size():
			part.visible = false
			continue
		var entry: Dictionary = swipes[index]
		var t: float = entry.age / entry.life
		var reach: float = entry.reach
		var plane := part.mesh as PlaneMesh
		var size := (reach + 0.4) * 2.0
		if not is_equal_approx(plane.size.x, size):
			plane.size = Vector2.ONE * size
		var dir: Vector3 = entry.dir
		part.visible = true
		part.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), entry.at)
		var material := part.material_override as ShaderMaterial
		# The head sweeps through in the first 55 % of the life, then it fades.
		var sweep := 1.0 - pow(1.0 - minf(1.0, t / 0.55), 2.0)
		material.set_shader_parameter("outer", reach)
		material.set_shader_parameter("inner", float(entry.inner))
		material.set_shader_parameter("half_angle", float(entry.half))
		material.set_shader_parameter("sweep", sweep)
		material.set_shader_parameter("trail", maxf(1.2, float(entry.half) * 1.6))
		material.set_shader_parameter("side", float(entry.side))
		material.set_shader_parameter("fade", 1.0 - clampf((t - 0.5) / 0.5, 0.0, 1.0))
		material.set_shader_parameter("edge_color", entry.tint)
	while _ball_meshes.size() < fireballs.size():
		_ball_meshes.append(_make_ball())
	for index in _ball_meshes.size():
		var ball := _ball_meshes[index]
		if index >= fireballs.size():
			ball.visible = false
			continue
		var entry: Dictionary = fireballs[index]
		var t: float = entry.age / entry.life
		var r: float = float(entry.radius) * lerpf(0.5, 1.0, 1.0 - pow(1.0 - t, 3.0))
		ball.visible = true
		ball.global_transform = Transform3D(Basis.from_scale(Vector3(r, r * 0.7, r)), Vector3(entry.at.x, 0.35, entry.at.z))
		var material := ball.material_override as StandardMaterial3D
		# Yellow flash, saturated orange fire, then a dark red fade.
		var hot := Color(1.0, 0.86, 0.3).lerp(Color(1.0, 0.42, 0.04), minf(1.0, t * 4.0)).lerp(Color(0.45, 0.1, 0.04), maxf(0.0, t - 0.45) * 1.8)
		material.albedo_color = Color(hot, 1.0 - smoothstep(0.45, 1.0, t))


func _make_swipe() -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "Swipe"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 4.0
	part.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = SWIPE_SHADER
	material.render_priority = 3
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	part.top_level = true
	return part


func _make_ball() -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.name = "Fireball"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	ball.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 2
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.top_level = true
	return ball
