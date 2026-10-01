extends MultiMeshInstance3D

# Etappe 07 (PERF_WORLD): many small, purely visual pieces with one mesh drawn in
# ONE draw call. Colour and alpha come per instance (MultiMesh colours × a shared
# vertex-colour material), so no piece needs its own material. Usage per frame:
#
#   batch.begin()
#   batch.add(transform, color)   # world space when top_level, else local
#   batch.finish()                # hides the node when nothing was added
#
# Also hosts small static helpers for shared resources (materials, merged meshes).

var _count := 0

# key -> StandardMaterial3D, shared by every batch/part with the same look.
static var _materials := {}


## New batch for `mesh` with room for `capacity` instances.
## transparent: alpha blending (colour alpha counts); unshaded: flat colour.
static func create(mesh: Mesh, capacity: int, transparent := true, unshaded := true, node_name := "FX batch") -> MultiMeshInstance3D:
	var batch: MultiMeshInstance3D = load("res://scripts/combat/fx_batch.gd").new()
	batch.name = node_name
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = maxi(1, capacity)
	multimesh.visible_instance_count = 0
	batch.multimesh = multimesh
	batch.material_override = vertex_color_material(transparent, unshaded)
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.visible = false
	return batch


## Shared material that takes its colour (and alpha) from vertex/instance colour.
static func vertex_color_material(transparent := true, unshaded := true, roughness := 0.8) -> StandardMaterial3D:
	var key := "vc:%s:%s:%.2f" % [transparent, unshaded, roughness]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if unshaded else BaseMaterial3D.CULL_BACK
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = material
	return material


## Shared plain material (never animate it: every user sees the change).
## Keeps the look of the per-instance materials it replaces.
static func shared_material(color: Color, unshaded := false, transparent := false, roughness := 1.0, cull_disabled := false) -> StandardMaterial3D:
	var key := "m:%s:%s:%s:%.2f:%s" % [color.to_html(true), unshaded, transparent, roughness, cull_disabled]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if cull_disabled:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material


## One ArrayMesh from several primitive meshes: `parts` = [[mesh, Transform3D], ...].
## Parts sharing one material become a single draw call instead of one each.
static func merge(parts: Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var mesh: Mesh = part[0]
		for surface in mesh.get_surface_count():
			tool.append_from(mesh, surface, part[1])
	return tool.commit()


func begin() -> void:
	_count = 0


func add(xform: Transform3D, color: Color) -> void:
	if _count >= multimesh.instance_count:
		return
	multimesh.set_instance_transform(_count, xform)
	multimesh.set_instance_color(_count, color)
	_count += 1


## auto_visibility: hide the node when empty (false = the caller owns `visible`).
func finish(auto_visibility := true) -> void:
	multimesh.visible_instance_count = _count
	if auto_visibility:
		visible = _count > 0


func count() -> int:
	return _count
