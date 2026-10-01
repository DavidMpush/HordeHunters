extends SceneTree

# Builds a light, animated game scene from Hunyuan3D / Tencent 3D Studio rig
# exports (FBX with "Bone Binding", optionally "Animation Effects"):
#   - the rig FBX gives skeleton + skinned mesh (50k tris, 4K maps),
#   - every further FBX contributes its animation (same skeleton),
#   - the mesh is simplified (skin weights kept), the base colour downscaled,
#   - result: <out_dir>/<name>_rig.scn (root -> Armature -> Skeleton3D -> Mesh,
#     AnimationPlayer with library "" holding the named clips) and
#     <name>_albedo.png. Source files are never modified.
# Usage (from the project folder):
#   Godot_console.exe --headless --audio-driver Dummy --path . --script tools/build_rigged_hero.gd --
#     <out_dir> <name> <triangles> <texture_size> <rig.fbx> [clip=anim.fbx ...]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("usage: -- <out_dir> <name> <triangles> <texture_size> <rig.fbx> [clip=anim.fbx ...]")
		quit(1)
		return
	quit(_build(args[0], args[1], int(args[2]), int(args[3]), args[4], args.slice(5)))


func _load(path: String) -> Node:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)


func _build(out_dir: String, model_name: String, target: int, texture_size: int, rig_path: String, clips: Array) -> int:
	var scene := _load(rig_path)
	if scene == null:
		push_error("cannot read " + rig_path)
		return 1
	var skeleton := _find(scene, "Skeleton3D") as Skeleton3D
	var item := _find(scene, "MeshInstance3D") as MeshInstance3D
	if skeleton == null or item == null:
		push_error("rig without skeleton or mesh")
		return 1
	var mesh: ArrayMesh = item.mesh
	var arrays := mesh.surface_get_arrays(0)
	var material := mesh.surface_get_material(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	# Simplify on the bind pose (skin weights ride along on the kept vertices).
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", mesh.surface_get_format(0))
	importer.generate_lods(25.0, 60.0, [])
	var best := indices
	for lod in importer.get_surface_lod_count(0):
		best = importer.get_surface_lod_indices(0, lod)
		if best.size() / 3 <= target:
			break
	# Compact: keep only used vertices, every per-vertex array remapped.
	var order := PackedInt32Array()
	var remap := {}
	var new_indices := PackedInt32Array()
	for index in best:
		if not remap.has(index):
			remap[index] = order.size()
			order.append(index)
		new_indices.append(remap[index])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		var data: Variant = arrays[slot]
		if data == null or slot == Mesh.ARRAY_INDEX:
			continue
		var size: int = data.size()
		if size == 0:
			continue
		var width := size / vertex_count
		var packed: Variant = data.duplicate()
		packed.resize(order.size() * width)
		for i in order.size():
			for k in width:
				packed[i * width + k] = data[order[i] * width + k]
		out[slot] = packed
	out[Mesh.ARRAY_INDEX] = new_indices
	var flags := mesh.surface_get_format(0) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	var game_mesh := ArrayMesh.new()
	game_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	item.mesh = game_mesh
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Base colour only (the game shader adds light, rim, contour).
	if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null:
		var image := (material as BaseMaterial3D).albedo_texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(texture_size, texture_size, Image.INTERPOLATE_LANCZOS)
		image.save_png(out_dir.path_join(model_name + "_albedo.png"))
	item.material_override = null
	# Animations: one AnimationPlayer at the root, clips renamed.
	for child in scene.get_children():
		if child is AnimationPlayer:
			scene.remove_child(child)
			child.free()
	var library := AnimationLibrary.new()
	for clip in clips:
		var parts := String(clip).split("=", true, 1)
		var source := _load(parts[1])
		if source == null:
			push_error("cannot read " + parts[1])
			return 1
		var player := _find(source, "AnimationPlayer") as AnimationPlayer
		if player == null or player.get_animation_list().is_empty():
			push_error("no animation in " + parts[1])
			return 1
		var animation: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
		library.add_animation(parts[0], animation)
		print("clip %s: %.2f s, %d tracks" % [parts[0], animation.length, animation.get_track_count()])
		source.free()
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	anim_player.add_animation_library("", library)
	scene.add_child(anim_player)
	_own(scene, scene)
	var packed_scene := PackedScene.new()
	packed_scene.pack(scene)
	var scene_path := out_dir.path_join(model_name + "_rig.scn")
	if ResourceSaver.save(packed_scene, scene_path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("cannot save " + scene_path)
		return 1
	print("%s: %d -> %d triangles, %d vertices, %d bones, aabb %s" % [model_name, indices.size() / 3, new_indices.size() / 3, order.size(), skeleton.get_bone_count(), game_mesh.get_aabb()])
	scene.free()
	return 0


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


func _find(node: Node, class_id: String) -> Node:
	if node.is_class(class_id):
		return node
	for child in node.get_children():
		var found := _find(child, class_id)
		if found != null:
			return found
	return null
