extends Node3D

# Pooled, purely visual weapon pieces of stage 4 (new weapons and evolutions):
# coloured streaks (bullets, flame tongues), jagged lightning bolts, glowing
# orbs and burning ground discs. Each kind is ONE MultiMesh (combat/fx_batch.gd)
# in world space with fixed capacity, so a whole volley costs 1-3 draw calls and
# nothing is allocated per frame (entries are made only when spawned).
# Lives as a top-level child of a weapon; the weapon calls step(delta), so it
# freezes with the run (pause, choices, hitstop).
#   streak(from, to, color, width, life)  runs out from `from` like a tracer
#   bolt(from, to, color, width, life)    jagged lightning, flickers, fades
#   orb(at, radius, color, life)          expanding glow ball
#   pool(at, radius, color, life)         flat burning disc on the ground

const FX_BATCH := preload("res://scripts/combat/fx_batch.gd")
const LINE_CAP := 96
const ORB_CAP := 32
const POOL_CAP := 8
const BOLT_SEGMENTS := 5

var lines: Array[Dictionary] = []
var orbs: Array[Dictionary] = []
var pools: Array[Dictionary] = []
var _lines: MultiMeshInstance3D
var _orbs: MultiMeshInstance3D
var _pools: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 99
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 12
	ball.rings = 6
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	_lines = _batch(box, LINE_CAP * 2, "Streaks")
	_orbs = _batch(ball, ORB_CAP, "Orbs")
	_pools = _batch(disc, POOL_CAP * 2, "Pools")


func _batch(mesh: Mesh, capacity: int, node_name: String) -> MultiMeshInstance3D:
	var batch := FX_BATCH.create(mesh, capacity, true, true, node_name)
	add_child(batch)
	batch.top_level = true
	batch.global_transform = Transform3D.IDENTITY
	return batch


# ---------------------------------------------------------------- spawning

func streak(from: Vector3, to: Vector3, color: Color, width: float = 0.16, life: float = 0.12) -> void:
	_push(lines, {"a": from, "b": to, "color": color, "width": width, "life": life, "age": 0.0, "run": true}, LINE_CAP)


## Jagged bolt: BOLT_SEGMENTS pieces with random sideways kinks.
func bolt(from: Vector3, to: Vector3, color: Color, width: float = 0.16, life: float = 0.2) -> void:
	var span := to - from
	var length := span.length()
	if length < 0.05:
		return
	var side := Vector3(-span.z, 0.0, span.x).normalized()
	var kink := minf(0.45, length * 0.12)
	var prev := from
	for k in BOLT_SEGMENTS:
		var u := float(k + 1) / float(BOLT_SEGMENTS)
		var next := to if k == BOLT_SEGMENTS - 1 else from + span * u + side * _rng.randf_range(-kink, kink) + Vector3.UP * _rng.randf_range(-0.12, 0.12)
		_push(lines, {"a": prev, "b": next, "color": color, "width": width, "life": life, "age": 0.0, "run": false}, LINE_CAP)
		prev = next


func orb(at: Vector3, radius: float, color: Color, life: float = 0.25) -> void:
	_push(orbs, {"at": at, "radius": radius, "color": color, "life": life, "age": 0.0}, ORB_CAP)


func pool(at: Vector3, radius: float, color: Color, life: float = 3.0) -> void:
	_push(pools, {"at": Vector3(at.x, 0.05, at.z), "radius": radius, "color": color, "life": life, "age": 0.0}, POOL_CAP)


func clear() -> void:
	lines.clear()
	orbs.clear()
	pools.clear()
	_draw()


func active() -> int:
	return lines.size() + orbs.size() + pools.size()


func _push(list: Array[Dictionary], entry: Dictionary, capacity: int) -> void:
	if list.size() >= capacity:
		list.pop_front()
	list.append(entry)


# ---------------------------------------------------------------- update

func step(delta: float) -> void:
	_clock += delta
	if _lines == null:
		return
	if active() == 0 and not _lines.visible and not _orbs.visible and not _pools.visible:
		return
	_age(lines, delta)
	_age(orbs, delta)
	_age(pools, delta)
	_draw()


func _age(list: Array[Dictionary], delta: float) -> void:
	for index in range(list.size() - 1, -1, -1):
		list[index].age += delta
		if list[index].age >= list[index].life:
			list.remove_at(index)


func _draw() -> void:
	if _lines == null:
		return
	_lines.begin()
	for entry in lines:
		var t: float = entry.age / entry.life
		var a: Vector3 = entry.a
		var b: Vector3 = entry.b
		if entry.run:
			# Like a tracer: the head runs out, the tail catches up.
			var head := a.lerp(b, minf(1.0, t * 3.0 + 0.4))
			var tail := a.lerp(b, clampf(t * 1.5 - 0.1, 0.0, 1.0))
			a = tail
			b = head
		var span := b - a
		var length := span.length()
		if length < 0.04:
			continue
		var dir := span / length
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
		var width: float = entry.width * (1.0 - t * 0.5)
		# Bolts flicker (brightness jumps every frame).
		var flicker := 1.0 if entry.run else (0.65 + 0.35 * sin(_clock * 90.0 + a.x * 7.0))
		var tint: Color = entry.color
		var mid := (a + b) * 0.5
		_lines.add(Transform3D(basis.scaled_local(Vector3(width, width * 0.6, length + width * 0.5)), mid), Color(tint, tint.a * flicker * (1.0 - t * t)))
		_lines.add(Transform3D(basis.scaled_local(Vector3(width * 0.32, width * 0.3, length)), mid + Vector3.UP * 0.02), Color(tint.lightened(0.55), flicker * (1.0 - t)))
	_lines.finish()
	_orbs.begin()
	for entry in orbs:
		var t: float = entry.age / entry.life
		var r: float = float(entry.radius) * lerpf(0.45, 1.0, 1.0 - pow(1.0 - t, 3.0)) * 2.0
		var tint: Color = entry.color
		_orbs.add(Transform3D(Basis.from_scale(Vector3(r, r * 0.75, r)), entry.at), Color(tint.lerp(Color(0.4, 0.08, 0.04), maxf(0.0, t - 0.5)), tint.a * (1.0 - smoothstep(0.4, 1.0, t))))
	_orbs.finish()
	_pools.begin()
	for entry in pools:
		var t: float = entry.age / entry.life
		var grow := minf(1.0, entry.age / 0.15)
		var fade := 1.0 - smoothstep(0.75, 1.0, t)
		var r: float = float(entry.radius) * 2.0 * lerpf(0.6, 1.0, grow)
		var tint: Color = entry.color
		var pulse := 0.85 + 0.15 * sin(_clock * 14.0 + float(entry.at.x))
		_pools.add(Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), entry.at), Color(tint, tint.a * fade * pulse))
		# Hot core.
		_pools.add(Transform3D(Basis.from_scale(Vector3(r * 0.62, 1.0, r * 0.62)), entry.at + Vector3.UP * 0.01), Color(1.0, 0.8, 0.3, 0.32 * fade * pulse))
	_pools.finish()
