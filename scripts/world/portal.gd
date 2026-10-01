extends Node3D

# Stage 4 Teil A: portal to the next world. Opens where the world's boss fell
# (worlds.gd places it on open ground), after Mawlings migration_maw.gd: the
# toothed SandPortal maw as the lip, a swirling vortex in the destination
# biome's colours and a tall light column, so it reads from far away and never
# like a danger telegraph (those are magenta fills with a bright contour).
# No collision, never hurts.
#
# API (worlds.gd):
#   setup(target_biome)         before add_child
#   contains(point)
#   step(delta, hero_at) -> bool   true exactly once: the hero stood inside for
#                                  PORTAL_HOLD s (hold 0..1 falls twice as fast
#                                  outside)
#   hold, opened, entered, radius, target_biome

const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BIOMES := preload("res://scripts/world/biomes.gd")
const VORTEX_SHADER := preload("res://shaders/portal_vortex.gdshader")
const LIP_SHADER := preload("res://shaders/boss.gdshader")
const SAND_PORTAL := "res://assets/props/SandPortal_game.glb"
const OPEN_SECONDS := 0.9
const BEAM_HEIGHT := 11.0
const SAND_LIP_OUT := 1.08       # tooth ring radius in portal radii
const SAND_LIP_HEIGHT := 0.9     # metres (teeth tips)
const SAND_TEETH := 0.27         # tooth ring radius of the model (units)
const SAND_THROAT := 0.2         # inside this the model is pressed flat
static var _sand_cache: ArrayMesh

var radius := PT.PORTAL_RADIUS
var target_biome := "duerrschlund"
var hold := 0.0
var opened := 0.0
var entered := false
var inside := false
var rim: Node3D
var vortex: MeshInstance3D
var vortex_material: ShaderMaterial
var lip: MeshInstance3D
var beam: MeshInstance3D
var halo: MeshInstance3D
var _time := 0.0


func setup(target: String) -> void:
	target_biome = target


func _ready() -> void:
	rim = Node3D.new()
	rim.name = "Rim"
	add_child(rim)
	vortex_material = ShaderMaterial.new()
	vortex_material.shader = VORTEX_SHADER
	vortex_material.set_shader_parameter("radius", radius)
	vortex_material.render_priority = 1
	var core := _apply_target_colors()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	vortex = _part(self, "Vortex", plane, vortex_material, Vector3(0, 0.12, 0))
	var mesh := _sand_mesh()
	if mesh != null:
		var lip_material := ShaderMaterial.new()
		lip_material.shader = LIP_SHADER
		lip_material.set_shader_parameter("brightness", 1.2)
		lip_material.set_shader_parameter("saturation", 1.0)
		lip_material.set_shader_parameter("shape_light", 0.45)
		lip_material.set_shader_parameter("body_tint", Color(0.9, 0.78, 0.6, 0.2))
		lip_material.set_shader_parameter("rim_color", core.lightened(0.3))
		lip_material.set_shader_parameter("rim_strength", 0.7)
		lip = _part(rim, "Lip", mesh, lip_material, Vector3.ZERO)
		var box: AABB = mesh.get_aabb()
		var k := radius * SAND_LIP_OUT / SAND_TEETH
		var placed := Transform3D(Basis.from_scale(Vector3(k, SAND_LIP_HEIGHT / maxf(0.01, box.size.y), k)), Vector3.ZERO)
		var bounds: AABB = placed * box
		placed.origin -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		lip.transform = placed
	# Light column: soft additive glow in the destination colour.
	var column := CylinderMesh.new()
	column.top_radius = radius * 0.3
	column.bottom_radius = radius * 0.7
	column.height = BEAM_HEIGHT
	column.radial_segments = 20
	column.rings = 1
	column.cap_top = false
	column.cap_bottom = false
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.no_depth_test = false
	glow.albedo_color = Color(core, 0.45)
	beam = _part(self, "Beam", column, glow, Vector3(0, BEAM_HEIGHT * 0.5, 0))
	# Ground halo: a bright ring just outside the lip (reads on every ground).
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 1.18
	torus.outer_radius = radius * 1.32
	torus.rings = 40
	torus.ring_segments = 4
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.albedo_color = core.lightened(0.25)
	halo = _part(self, "Halo", torus, halo_material, Vector3(0, 0.08, 0))
	halo.scale = Vector3(1.0, 0.15, 1.0)
	_animate(0.0)


func _apply_target_colors() -> Color:
	var data: Dictionary = BIOMES.get_data(target_biome)
	var core: Color = Color(data.get("pool", Color("3fc0c4"))).lightened(0.45)
	var mid: Color = data.get("pool", Color("3fc0c4"))
	var deep: Color = Color(data.get("ground", Color("80a04c"))).darkened(0.7)
	if data.has("ember"):
		core = data.ember.lava_core
		mid = data.ember.lava_mid
		deep = Color("2a0c22")
	vortex_material.set_shader_parameter("core_color", core)
	vortex_material.set_shader_parameter("mid_color", mid)
	vortex_material.set_shader_parameter("deep_color", deep)
	vortex_material.set_shader_parameter("hold_color", Color("fff6e0"))
	return core


func contains(point: Vector3) -> bool:
	return Vector2(point.x - position.x, point.z - position.z).length() <= radius


## Opening, hold and animation; true exactly once when the hero went in.
func step(delta: float, hero_at: Vector3) -> bool:
	opened = minf(1.0, opened + delta / OPEN_SECONDS)
	inside = contains(hero_at)
	if not entered and opened >= 1.0:
		if inside:
			hold = minf(1.0, hold + delta / PT.PORTAL_HOLD)
		else:
			hold = maxf(0.0, hold - 2.0 * delta / PT.PORTAL_HOLD)
	_animate(delta)
	if not entered and hold >= 1.0:
		entered = true
		return true
	return false


func _animate(delta: float) -> void:
	_time += delta
	var grow := 1.0 - pow(1.0 - opened, 3.0)
	var breath := 1.0 + 0.045 * sin(_time * 2.4) + 0.08 * hold
	rim.scale = Vector3(breath, 1.0, breath) * maxf(0.01, grow)
	rim.rotation.y = 0.05 * sin(_time * 1.3)
	vortex.scale = Vector3.ONE * maxf(0.01, grow)
	vortex_material.set_shader_parameter("open", grow)
	vortex_material.set_shader_parameter("hold", hold)
	vortex_material.set_shader_parameter("time", _time)
	beam.scale = Vector3(1.0 + 0.3 * hold, maxf(0.01, grow), 1.0 + 0.3 * hold)
	beam.position.y = BEAM_HEIGHT * 0.5 * grow
	var pulse := 1.0 + 0.06 * sin(_time * 4.0)
	halo.scale = Vector3(pulse, 0.15, pulse) * maxf(0.01, grow)


# SandPortal in node space with its throat opened: everything inside the tooth
# ring is pressed flat to the ground, so the vortex shows inside the teeth.
static func _sand_mesh() -> ArrayMesh:
	if _sand_cache != null:
		return _sand_cache
	if not ResourceLoader.exists(SAND_PORTAL):
		return null
	var root: Node = (load(SAND_PORTAL) as PackedScene).instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		root.free()
		return null
	var model: MeshInstance3D = found[0]
	var base := Transform3D.IDENTITY
	var node: Node = model
	while node != root and node is Node3D:
		base = (node as Node3D).transform * base
		node = node.get_parent()
	var source: Mesh = model.mesh
	var arrays := source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var box: AABB = base * source.get_aabb()
	var center := box.get_center()
	for i in points.size():
		var v: Vector3 = base * points[i]
		v -= Vector3(center.x, box.position.y, center.z)
		if Vector2(v.x, v.z).length() < SAND_THROAT:
			v.y = minf(v.y, 0.004) * 0.2
		points[i] = v
	arrays[Mesh.ARRAY_VERTEX] = points
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	if normals is PackedVector3Array:
		var turned: PackedVector3Array = normals
		var inverse := base.basis.inverse().transposed()
		for i in turned.size():
			turned[i] = (inverse * turned[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = turned
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	root.free()
	_sand_cache = mesh
	return mesh


func _part(parent: Node3D, label: String, mesh: Mesh, material: Material, location: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
