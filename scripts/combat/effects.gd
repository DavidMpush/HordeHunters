extends Node3D

# Purely visual combat effects (never touch game state): pellet tracers,
# muzzle flash and smoke, hit sparks, empty shells, dust puffs, rings and goo
# splats. Each kind is ONE pooled MultiMesh (fx_batch.gd) in world space, so
# a full shotgun blast costs a handful of draw calls.

const FX_BATCH := preload("res://scripts/combat/fx_batch.gd")
const ARC_SHADER := preload("res://shaders/telegraph_arc.gdshader")
const BLAST_LIFE := 0.12

const TRACER_LIFE := 0.13
const FLASH_LIFE := 0.07
const SMOKE_LIFE := 0.5
const SPARK_LIFE := 0.24
const SHELL_LIFE := 1.6
const PUFF_LIFE := 0.45
const SPLAT_LIFE := 3.0
const GRAVITY := 22.0

const TRACER_COLOR := Color(1.0, 0.93, 0.6, 1.0)
const TRACER_TAIL := Color(1.0, 0.55, 0.15, 1.0)
const FLASH_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const FLASH_CORE := Color(1.0, 1.0, 0.9, 1.0)
const SMOKE_COLOR := Color(0.85, 0.82, 0.78, 0.5)
const SPARK_COLOR := Color(1.0, 0.85, 0.3, 1.0)
const SHELL_COLOR := Color(1.0, 0.2, 0.14, 1.0)

var tracers: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var shells: Array[Dictionary] = []
var puffs: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var splats: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var _blast_meshes: Array[MeshInstance3D] = []
var _tracer_core_batch: MultiMeshInstance3D

var _tracer_batch: MultiMeshInstance3D
var _flash_batch: MultiMeshInstance3D
var _core_batch: MultiMeshInstance3D
var _smoke_batch: MultiMeshInstance3D
var _spark_batch: MultiMeshInstance3D
var _shell_batch: MultiMeshInstance3D
var _puff_batch: MultiMeshInstance3D
var _ring_batch: MultiMeshInstance3D
var _splat_batch: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = 7
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 5
	var shell := CylinderMesh.new()
	shell.top_radius = 0.5
	shell.bottom_radius = 0.5
	shell.height = 1.0
	shell.radial_segments = 8
	shell.rings = 1
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	disc.radial_segments = 14
	disc.rings = 1
	_splat_batch = _batch(disc, 120, true, true, "Splats")
	_tracer_batch = _batch(box, 48, true, true, "Tracers")
	_tracer_core_batch = _batch(box, 48, true, true, "Tracer cores")
	_smoke_batch = _batch(ball, 40, true, true, "Smoke")
	_flash_batch = _batch(ball, 24, true, true, "Muzzle flash")
	_core_batch = _batch(ball, 8, true, true, "Muzzle core")
	_spark_batch = _batch(box, 200, true, true, "Sparks")
	_shell_batch = _batch(shell, 24, false, false, "Shells")
	_puff_batch = _batch(ball, 60, true, true, "Puffs")
	_ring_batch = _batch(torus, 24, true, true, "Rings")


func _batch(mesh: Mesh, capacity: int, transparent: bool, unshaded: bool, node_name: String) -> MultiMeshInstance3D:
	var batch := FX_BATCH.create(mesh, capacity, transparent, unshaded, node_name)
	add_child(batch)
	batch.top_level = true
	batch.global_transform = Transform3D.IDENTITY
	return batch


# ---------------------------------------------------------------- spawning

func tracer(from: Vector3, to: Vector3) -> void:
	_push(tracers, {"a": from, "b": to, "age": 0.0}, 48)


## Short warm wedge on the ground: shows the fan and the reach of one shot.
func blast(origin: Vector3, direction: Vector3, reach: float, half_angle: float) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	_push(blasts, {"at": Vector3(origin.x, 0.06, origin.z), "dir": dir, "reach": reach, "half": half_angle, "age": 0.0}, 4)


func muzzle_flash(at: Vector3, direction: Vector3) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	_push(flashes, {"at": at, "dir": dir, "age": 0.0}, 8)
	# Ground flash under the muzzle.
	_push(puffs, {"at": Vector3(at.x, 0.05, at.z) + dir * 0.8, "vel": Vector3.ZERO, "age": 0.15, "size": 2.2, "color": Color(1.0, 0.85, 0.4, 0.35)}, 60)
	for k in 4:
		var drift := dir * _rng.randf_range(1.2, 2.6) + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.3, 1.0), _rng.randf_range(-0.6, 0.6))
		_push(smokes, {"at": at + dir * 0.25, "vel": drift, "age": _rng.randf_range(0.0, 0.08), "size": _rng.randf_range(0.25, 0.4)}, 40)


func hit_sparks(at: Vector3, direction: Vector3, amount: int = 4) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	for k in amount:
		var side := Vector3(-dir.z, 0.0, dir.x) * _rng.randf_range(-3.0, 3.0)
		var vel := dir * _rng.randf_range(2.0, 6.0) + side + Vector3.UP * _rng.randf_range(1.5, 4.5)
		_push(sparks, {"at": at, "vel": vel, "age": 0.0}, 200)
	_push(puffs, {"at": at, "vel": Vector3.UP * 0.5, "age": 0.1, "size": 0.55, "color": Color(1.0, 0.97, 0.85, 0.8)}, 60)


func eject_shells(at: Vector3, backwards: Vector3, count: int = 2) -> void:
	var back := Vector3(backwards.x, 0.0, backwards.z).normalized()
	for k in count:
		var side := Vector3(-back.z, 0.0, back.x) * _rng.randf_range(-1.2, 1.2)
		var vel := back * _rng.randf_range(2.8, 4.2) + side + Vector3.UP * _rng.randf_range(6.0, 7.5)
		var spin := Vector3(_rng.randf_range(-16, 16), _rng.randf_range(-6, 6), _rng.randf_range(-16, 16))
		_push(shells, {"at": at, "vel": vel, "rot": Basis(Vector3.RIGHT, PI * 0.5), "spin": spin, "age": 0.0, "rest": false}, 24)


func dust(at: Vector3, count: int = 3, size: float = 0.5, tint := Color(0.86, 0.8, 0.66, 0.55)) -> void:
	for k in count:
		var vel := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.2, 0.8), _rng.randf_range(-1.0, 1.0))
		_push(puffs, {"at": at + Vector3(0, 0.15, 0), "vel": vel, "age": 0.0, "size": size * _rng.randf_range(0.7, 1.2), "color": tint}, 60)


func ring(at: Vector3, tint: Color, from_radius: float, to_radius: float, seconds: float) -> void:
	_push(rings, {"at": Vector3(at.x, 0.12, at.z), "color": tint, "from": from_radius, "to": to_radius, "life": seconds, "age": 0.0}, 24)


func splat(at: Vector3, tint: Color, size: float) -> void:
	# A few overlapping blots read as a splash, one disc reads as a hole.
	for k in 4:
		var offset := Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5)) * size * (0.0 if k == 0 else 0.8)
		var blot := size * (0.6 if k == 0 else _rng.randf_range(0.2, 0.36))
		_push(splats, {"at": Vector3(at.x + offset.x, 0.03 + 0.002 * k, at.z + offset.z), "color": tint, "size": blot, "age": 0.0}, 120)


func clear() -> void:
	for list in [tracers, flashes, smokes, sparks, shells, puffs, rings, splats, blasts]:
		list.clear()
	_draw()


func active_count() -> int:
	return tracers.size() + flashes.size() + smokes.size() + sparks.size() + shells.size() + puffs.size() + rings.size() + splats.size()


func _push(list: Array[Dictionary], entry: Dictionary, capacity: int) -> void:
	if list.size() >= capacity:
		list.pop_front()
	list.append(entry)


# ---------------------------------------------------------------- update

func step(delta: float) -> void:
	_build()
	_age(tracers, delta, TRACER_LIFE)
	_age(flashes, delta, FLASH_LIFE)
	_age(smokes, delta, SMOKE_LIFE)
	_age(sparks, delta, SPARK_LIFE)
	_age(shells, delta, SHELL_LIFE)
	_age(puffs, delta, PUFF_LIFE)
	_age(splats, delta, SPLAT_LIFE)
	_age(blasts, delta, BLAST_LIFE)
	for index in range(rings.size() - 1, -1, -1):
		rings[index].age += delta
		if rings[index].age >= rings[index].life:
			rings.remove_at(index)
	for entry in smokes:
		entry.at += entry.vel * delta
		entry.vel *= exp(-3.0 * delta)
	for entry in sparks:
		entry.vel.y -= GRAVITY * delta
		entry.at += entry.vel * delta
		if entry.at.y < 0.05:
			entry.at.y = 0.05
			entry.vel *= 0.3
	for entry in puffs:
		entry.at += entry.vel * delta
		entry.vel *= exp(-4.0 * delta)
	for entry in shells:
		if entry.rest:
			continue
		entry.vel.y -= GRAVITY * delta
		entry.at += entry.vel * delta
		entry.rot = (entry.rot as Basis).rotated(Vector3(entry.spin).normalized(), Vector3(entry.spin).length() * delta).orthonormalized()
		if entry.at.y < 0.05:
			entry.at.y = 0.05
			if absf(entry.vel.y) < 1.2:
				entry.rest = true
				entry.rot = Basis(Vector3.UP, entry.at.x * 3.0) * Basis(Vector3.RIGHT, PI * 0.5)
			else:
				entry.vel = Vector3(entry.vel.x * 0.5, -entry.vel.y * 0.4, entry.vel.z * 0.5)
				entry.spin = Vector3(entry.spin) * 0.6
	_draw()


func _age(list: Array[Dictionary], delta: float, life: float) -> void:
	for index in range(list.size() - 1, -1, -1):
		list[index].age += delta
		if list[index].age >= life:
			list.remove_at(index)


func _draw() -> void:
	if not _built:
		return
	_draw_blasts()
	_tracer_batch.begin()
	_tracer_core_batch.begin()
	for entry in tracers:
		var t: float = entry.age / TRACER_LIFE
		var a: Vector3 = entry.a
		var b: Vector3 = entry.b
		# The streak runs out from the muzzle and its tail catches up.
		var head := a.lerp(b, minf(1.0, t * 3.0 + 0.35))
		var tail := a.lerp(b, clampf(t * 1.6 - 0.1, 0.0, 1.0))
		var length := tail.distance_to(head)
		if length < 0.05:
			continue
		var width := 0.22 * (1.0 - t * 0.6)
		var look := Basis.looking_at((head - tail).normalized(), Vector3.UP)
		var tint := TRACER_COLOR.lerp(TRACER_TAIL, t)
		_tracer_batch.add(Transform3D(look.scaled_local(Vector3(width, width * 0.5, length)), (head + tail) * 0.5), Color(tint, 0.85 * (1.0 - t * t)))
		_tracer_core_batch.add(Transform3D(look.scaled_local(Vector3(width * 0.35, width * 0.35, length)), (head + tail) * 0.5 + Vector3.UP * 0.02), Color(1, 1, 1, 1.0 - t))
	_tracer_batch.finish()
	_tracer_core_batch.finish()
	_flash_batch.begin()
	_core_batch.begin()
	for entry in flashes:
		var t: float = entry.age / FLASH_LIFE
		var dir: Vector3 = entry.dir
		var grow := lerpf(1.0, 1.5, t)
		var basis := Basis.looking_at(dir, Vector3.UP)
		var side := Vector3(-dir.z, 0.0, dir.x)
		_flash_batch.add(Transform3D(basis.scaled_local(Vector3(1.1, 0.7, 2.4) * grow), entry.at + dir * 0.8), Color(FLASH_COLOR, 0.95 * (1.0 - t)))
		_flash_batch.add(Transform3D(basis.rotated(Vector3.UP, 0.5).scaled_local(Vector3(0.5, 0.4, 1.5) * grow), entry.at + dir * 0.5 + side * 0.25), Color(FLASH_COLOR, 0.85 * (1.0 - t)))
		_flash_batch.add(Transform3D(basis.rotated(Vector3.UP, -0.5).scaled_local(Vector3(0.5, 0.4, 1.5) * grow), entry.at + dir * 0.5 - side * 0.25), Color(FLASH_COLOR, 0.85 * (1.0 - t)))
		_core_batch.add(Transform3D(basis.scaled_local(Vector3(0.6, 0.5, 1.3)), entry.at + dir * 0.5), Color(FLASH_CORE, 1.0 - t))
	_flash_batch.finish()
	_core_batch.finish()
	_smoke_batch.begin()
	for entry in smokes:
		var t: float = entry.age / SMOKE_LIFE
		var size: float = entry.size * lerpf(0.6, 1.8, 1.0 - (1.0 - t) * (1.0 - t))
		_smoke_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * size), entry.at), Color(SMOKE_COLOR, SMOKE_COLOR.a * (1.0 - t)))
	_smoke_batch.finish()
	_spark_batch.begin()
	for entry in sparks:
		var t: float = entry.age / SPARK_LIFE
		var vel: Vector3 = entry.vel
		var speed := vel.length()
		var basis := Basis.IDENTITY
		if speed > 0.1:
			basis = Basis.looking_at(vel / speed, Vector3.UP if absf(vel.y) < speed * 0.99 else Vector3.RIGHT)
		basis = basis.scaled_local(Vector3(0.07, 0.07, clampf(speed * 0.05, 0.08, 0.35)) * (1.0 - t * 0.5))
		_spark_batch.add(Transform3D(basis, entry.at), Color(SPARK_COLOR.lerp(Color(1.0, 0.45, 0.1), t), 1.0 - t * t))
	_spark_batch.finish()
	_shell_batch.begin()
	for entry in shells:
		var t: float = entry.age / SHELL_LIFE
		var fade := 1.0 - clampf((t - 0.8) / 0.2, 0.0, 1.0)
		var basis: Basis = (entry.rot as Basis).scaled_local(Vector3(0.16, 0.3, 0.16) * fade)
		_shell_batch.add(Transform3D(basis, entry.at), SHELL_COLOR)
	_shell_batch.finish()
	_puff_batch.begin()
	for entry in puffs:
		var t: float = entry.age / PUFF_LIFE
		var size: float = entry.size * lerpf(0.5, 1.3, 1.0 - (1.0 - t) * (1.0 - t))
		var tint: Color = entry.color
		_puff_batch.add(Transform3D(Basis.from_scale(Vector3(size, size * 0.7, size)), entry.at), Color(tint, tint.a * (1.0 - t)))
	_puff_batch.finish()
	_ring_batch.begin()
	for entry in rings:
		var t: float = entry.age / entry.life
		var r := lerpf(entry.from, entry.to, 1.0 - pow(1.0 - t, 3.0))
		var tint: Color = entry.color
		_ring_batch.add(Transform3D(Basis.from_scale(Vector3(r, 0.3, r)), entry.at), Color(tint, tint.a * (1.0 - t)))
	_ring_batch.finish()
	_splat_batch.begin()
	for entry in splats:
		var t: float = entry.age / SPLAT_LIFE
		var pop := minf(1.0, entry.age / 0.08)
		var size: float = entry.size * lerpf(0.4, 1.0, pop)
		var tint: Color = entry.color
		_splat_batch.add(Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), entry.at), Color(tint, tint.a * clampf((1.0 - t) / 0.3, 0.0, 1.0)))
	_splat_batch.finish()


func _draw_blasts() -> void:
	while _blast_meshes.size() < blasts.size():
		var part := MeshInstance3D.new()
		part.name = "Blast"
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * 2.0
		part.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = ARC_SHADER
		material.set_shader_parameter("fill_color", Color(1.0, 0.86, 0.45))
		material.set_shader_parameter("edge_color", Color(1.0, 0.97, 0.8))
		material.set_shader_parameter("dark_color", Color(0.55, 0.3, 0.05))
		material.set_shader_parameter("inner", 0.3)
		material.set_shader_parameter("progress", 1.0)
		material.render_priority = 2
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(part)
		part.top_level = true
		_blast_meshes.append(part)
	for index in _blast_meshes.size():
		var part := _blast_meshes[index]
		if index >= blasts.size():
			part.visible = false
			continue
		var entry: Dictionary = blasts[index]
		var t: float = entry.age / BLAST_LIFE
		var reach: float = entry.reach
		var dir: Vector3 = entry.dir
		part.visible = true
		var plane := part.mesh as PlaneMesh
		if not is_equal_approx(plane.size.x, (reach + 0.3) * 2.0):
			plane.size = Vector2.ONE * (reach + 0.3) * 2.0
		part.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), entry.at)
		var material := part.material_override as ShaderMaterial
		material.set_shader_parameter("outer", reach * lerpf(0.7, 1.0, minf(1.0, t * 4.0)))
		material.set_shader_parameter("inner", 0.3)
		material.set_shader_parameter("half_angle", float(entry.half))
		material.set_shader_parameter("opacity", 0.55 * (1.0 - t))