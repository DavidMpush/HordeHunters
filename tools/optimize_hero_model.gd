extends SceneTree

# Turns a Hunyuan3D hero GLB (one static 50k mesh, 4K PBR maps) into a light
# game mesh: node transforms baked in, feet on y = 0, height normalised to 1,
# facing +Z, simplified with Godot's LOD generator (meshoptimizer) and the
# base colour downscaled. The source GLB is never modified.
# Usage (from the project folder):
#   Godot_console.exe --headless --audio-driver Dummy --path . --script tools/optimize_hero_model.gd -- <source.glb> <out_dir> <name> [triangles] [texture_size]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <source.glb> <out_dir> <name> [triangles] [texture_size]")
		quit(1)
		return
	var source := args[0]
	var out_dir := args[1]
	var model_name := args[2]
	var target := int(args[3]) if args.size() > 3 else 6000
	var texture_size := int(args[4]) if args.size() > 4 else 1024
	quit(_optimize(source, out_dir, model_name, target, texture_size))


func _optimize(source: String, out_dir: String, model_name: String, target: int, texture_size: int) -> int:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(source, state) != OK:
		push_error("cannot read " + source)
		return 1
	var scene: Node = doc.generate_scene(state)
	var found := _find_mesh(scene, Transform3D.IDENTITY)
	if found.is_empty():
		push_error("no mesh in " + source)
		return 1
	var mesh: Mesh = found["mesh"]
	var xform: Transform3D = found["xform"]
	var arrays := mesh.surface_get_arrays(0)
	var material := mesh.surface_get_material(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Bake the node transform, then put the feet on the ground, centre x/z and
	# scale to a height of 1.
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in verts.size():
		verts[i] = xform * verts[i]
		normals[i] = (xform.basis * normals[i]).normalized()
		lo = lo.min(verts[i])
		hi = hi.max(verts[i])
	var height := hi.y - lo.y
	var shift := Vector3(-(lo.x + hi.x) * 0.5, -lo.y, -(lo.z + hi.z) * 0.5)
	for i in verts.size():
		verts[i] = (verts[i] + shift) / height
	# Simplify: generate LODs and take the first one at or below the target.
	var importer := ImporterMesh.new()
	var clean := []
	clean.resize(Mesh.ARRAY_MAX)
	clean[Mesh.ARRAY_VERTEX] = verts
	clean[Mesh.ARRAY_NORMAL] = normals
	clean[Mesh.ARRAY_TEX_UV] = uvs
	clean[Mesh.ARRAY_INDEX] = indices
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, clean)
	importer.generate_lods(25.0, 60.0, [])
	var best := indices
	for lod in importer.get_surface_lod_count(0):
		var lod_indices := importer.get_surface_lod_indices(0, lod)
		best = lod_indices
		if lod_indices.size() / 3 <= target:
			break
	# Drop vertices the chosen LOD no longer uses.
	var remap := {}
	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_indices := PackedInt32Array()
	for index in best:
		if not remap.has(index):
			remap[index] = out_verts.size()
			out_verts.append(verts[index])
			out_normals.append(normals[index])
			out_uvs.append(uvs[index])
		out_indices.append(remap[index])
	var final := []
	final.resize(Mesh.ARRAY_MAX)
	final[Mesh.ARRAY_VERTEX] = out_verts
	final[Mesh.ARRAY_NORMAL] = out_normals
	final[Mesh.ARRAY_TEX_UV] = out_uvs
	final[Mesh.ARRAY_INDEX] = out_indices
	var game_mesh := ArrayMesh.new()
	game_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, final)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var mesh_path := out_dir.path_join(model_name + "_mesh.res")
	if ResourceSaver.save(game_mesh, mesh_path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("cannot save " + mesh_path)
		return 1
	# Base colour only (the toon look supplies light, rim and contour).
	var albedo: Texture2D = null
	if material is BaseMaterial3D:
		albedo = (material as BaseMaterial3D).albedo_texture
	if albedo != null:
		var image := albedo.get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(texture_size, texture_size, Image.INTERPOLATE_LANCZOS)
		image.save_png(out_dir.path_join(model_name + "_albedo.png"))
	print("%s: %d -> %d triangles, %d vertices, height %.3f, texture %d" % [model_name, indices.size() / 3, out_indices.size() / 3, out_verts.size(), height, texture_size if albedo != null else 0])
	return 0


func _find_mesh(node: Node, parent: Transform3D) -> Dictionary:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return {"mesh": (node as MeshInstance3D).mesh, "xform": xform}
	for child in node.get_children():
		var found := _find_mesh(child, xform)
		if not found.is_empty():
			return found
	return {}
