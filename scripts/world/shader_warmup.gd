extends Node3D

# Etappe 4 Teil D: shader warm-up at the run start. Mobile GL drivers compile a
# shader the first time something is drawn with it (50-300 ms on a phone: the
# classic "first explosion / first boss" stutter). This node draws everything
# that would appear later ONCE in the first frames, below the ground under the
# hero (hidden by the depth test, so nothing is visible):
#   - every spatial shader in res://shaders on a plain mesh and on a MultiMesh
#     with colours + custom data (the horde / effect batch variant)
#   - the effect batches and the shot wedge (effects.warm_up)
#   - the enemy / boss / prop models (glb), loaded in a background thread and
#     kept in memory, so the boss spawn neither loads from disk nor compiles;
#     enemy models also once with the boss skin shader
#   - later: any mesh node added while hidden (weapons, cocoons, portal) gets
#     a twin drawn for two frames (once per material)
# Godot also keeps compiled shaders on disk (shader cache), so from the second
# start on most of this is a cache hit; the warm-up matters for the first run
# after an install / update.

const SHADER_DIR := "res://shaders"
## Enemy models: drawn with the boss skin (bosses use them that way; the horde
## draws its own MultiMesh at once). Extra models: drawn as they are.
const MODEL_DIRS := ["res://assets/enemies"]
const EXTRA_MODELS := ["res://assets/props/SandPortal_game.glb"]
const BOSS_SHADER_PATH := "res://shaders/boss.gdshader"
const DEPTH := 3.0
const FRAMES := 3

## Loaded model scenes stay referenced for the whole session (cache hits).
static var held: Dictionary = {}
static var _seen_materials: Dictionary = {}

var battle: Node
var effects: Node3D
var _pending_models: Array[String] = []
var _twins: Array = []          # [[node, frames_left], ...]
var _effect_frames := FRAMES
var started_usec := 0
## Number of things drawn for the warm-up (tests and the overlay read it).
var warmed := 0


func _ready() -> void:
	name = "ShaderWarmup"
	process_priority = 50        # after battle.tick (0), before Main (100)
	started_usec = Time.get_ticks_usec()
	for path in _shader_paths():
		var shader := load(path) as Shader
		if shader != null and shader.get_mode() == Shader.MODE_SPATIAL:
			var material := ShaderMaterial.new()
			material.shader = shader
			_twin_plain(QuadMesh.new(), material)
			_twin_multi(QuadMesh.new(), material)
	var models: Array[String] = []
	for dir in MODEL_DIRS:
		models.append_array(_list(dir, [".glb", ".scn", ".tscn"]))
	for path in EXTRA_MODELS:
		if ResourceLoader.exists(path):
			models.append(path)
	for path in models:
		if held.has(path):
			_spawn_model(path, held[path])
		elif ResourceLoader.load_threaded_request(path) == OK:
			_pending_models.append(path)
	# Mesh nodes built before this node (loot, cocoons, weapons of the start).
	var host := get_parent()
	if host != null:
		for node in host.find_children("*", "GeometryInstance3D", true, false):
			_on_node_added(node)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(_delta: float) -> void:
	if _effect_frames > 0 and effects != null and is_instance_valid(effects) and effects.has_method("warm_up"):
		_effect_frames -= 1
		effects.warm_up(_below())
		warmed += 1
	# At most one finished model per frame (instantiating is main-thread work).
	for index in _pending_models.size():
		var path := _pending_models[index]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending_models.remove_at(index)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(path)
			held[path] = scene
			_spawn_model(path, scene)
		break
	var at := _below()
	for index in range(_twins.size() - 1, -1, -1):
		var entry: Array = _twins[index]
		var node: Node3D = entry[0]
		entry[1] = int(entry[1]) - 1
		if int(entry[1]) < 0:
			node.queue_free()
			_twins.remove_at(index)
		else:
			node.global_position = at


## True while something is still being warmed (loading or drawing).
func busy() -> bool:
	return not _pending_models.is_empty() or not _twins.is_empty() or _effect_frames > 0


func _below() -> Vector3:
	var hero: Node3D = battle.hero if battle != null else null
	var at := hero.global_position if hero != null and hero.is_inside_tree() else Vector3.ZERO
	return at - Vector3(0.0, DEPTH, 0.0)


func _hold(node: Node3D) -> void:
	add_child(node)
	node.top_level = true
	node.global_position = _below()
	_twins.append([node, FRAMES])
	warmed += 1


func _twin_plain(mesh: Mesh, material: Material) -> void:
	var twin := MeshInstance3D.new()
	twin.mesh = mesh
	twin.material_override = material
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	twin.scale = Vector3.ONE * 0.05
	_hold(twin)


func _twin_multi(mesh: Mesh, material: Material, colors := true, custom := true, format := MultiMesh.TRANSFORM_3D) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = format
	multimesh.use_colors = colors
	multimesh.use_custom_data = custom
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.05), Vector3.ZERO))
	if colors:
		multimesh.set_instance_color(0, Color(1, 1, 1, 0.01))
	var twin := MultiMeshInstance3D.new()
	twin.multimesh = multimesh
	twin.material_override = material
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hold(twin)


## Enemy models with the boss skin, other models as they are.
func _spawn_model(path: String, scene: Resource) -> void:
	if not (scene is PackedScene):
		return
	if not path.begins_with("res://assets/enemies"):
		var model := (scene as PackedScene).instantiate() as Node3D
		if model != null:
			model.scale = Vector3.ONE * 0.05
			_hold(model)
		return
	if path.begins_with("res://assets/enemies") and ResourceLoader.exists(BOSS_SHADER_PATH):
		var skinned := (scene as PackedScene).instantiate() as Node3D
		if skinned == null:
			return
		var skin := ShaderMaterial.new()
		skin.shader = load(BOSS_SHADER_PATH)
		for mesh in skinned.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = skin
		skinned.scale = Vector3.ONE * 0.05
		_hold(skinned)


## Mesh nodes created hidden (weapons, cocoons, portal...) get a visible twin
## for a few frames, once per material.
func _on_node_added(node: Node) -> void:
	if not (node is GeometryInstance3D) or is_ancestor_of(node):
		return
	if node is MeshInstance3D:
		var source := node as MeshInstance3D
		if source.mesh == null:
			return
		var material := _material_of(source, source.mesh)
		if material == null or _seen_materials.has(material.get_rid()):
			return
		_seen_materials[material.get_rid()] = true
		if source.is_visible_in_tree():
			return
		_twin_plain(source.mesh, material)
	elif node is MultiMeshInstance3D:
		var batch := node as MultiMeshInstance3D
		if batch.multimesh == null or batch.multimesh.mesh == null:
			return
		var material := _material_of(batch, batch.multimesh.mesh)
		if material == null or _seen_materials.has(material.get_rid()):
			return
		_seen_materials[material.get_rid()] = true
		if batch.is_visible_in_tree() and batch.multimesh.visible_instance_count != 0:
			return
		_twin_multi(batch.multimesh.mesh, material, batch.multimesh.use_colors, batch.multimesh.use_custom_data, batch.multimesh.transform_format)


static func _material_of(node: GeometryInstance3D, mesh: Mesh) -> Material:
	if node.material_override != null:
		return node.material_override
	if node is MeshInstance3D and (node as MeshInstance3D).get_surface_override_material_count() > 0:
		var surface := (node as MeshInstance3D).get_surface_override_material(0)
		if surface != null:
			return surface
	if mesh.get_surface_count() > 0:
		return mesh.surface_get_material(0)
	return null


static func _shader_paths() -> Array[String]:
	return _list(SHADER_DIR, [".gdshader"])


## Files in `dir` with one of `extensions` (also in an exported build, where
## imported files are listed with .import / .remap suffixes).
static func _list(dir: String, extensions: Array) -> Array[String]:
	var out: Array[String] = []
	var names := PackedStringArray()
	if ClassDB.class_has_method("ResourceLoader", "list_directory"):
		names = ResourceLoader.call("list_directory", dir)
	else:
		var access := DirAccess.open(dir)
		if access != null:
			names = access.get_files()
	for file in names:
		var clean := String(file).trim_suffix(".import").trim_suffix(".remap")
		for ext in extensions:
			if clean.ends_with(String(ext)) and not out.has(dir.path_join(clean)):
				out.append(dir.path_join(clean))
	return out
