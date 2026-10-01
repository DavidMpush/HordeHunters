extends Node3D

# XP gems and gold coins (stage 2, Teil A §1 + §3), after Mawlings loot.gd:
# a kill drops gems that hop out in a short arc and stay on the ground until
# they are collected (no decay). Inside the magnet radius around the hero they
# fly in, accelerating, and are credited on arrival.
#
#   loot.drop_xp(at, amount)      # one gem (size by value: small/medium/big)
#   loot.drop_gold(at, amount)    # coins (1 coin per 5 gold, at most 4)
#   loot.step(delta, centre, radius) -> {"xp": float, "gold": int, "items": int}
#   loot.take_all() / loot.clear()
#
# Performance like Mawlings: no node per item, packed arrays with a free list,
# two MultiMeshes (gems, coins) plus one additive glow MultiMesh written from
# one buffer each; spinning and bobbing run in the vertex shader. Above
# SOFT_CAP lying gems a new gem joins the nearest lying gem (bundling).

enum Sort { XP, GOLD }
enum State { FREE, HOP, LYING, FLY }

const MAGNET_RADIUS := 2.5
const COLLECT_DISTANCE := 0.55
const HOP_SECONDS := 0.34
const HOP_HEIGHT := 1.1
const FLY_KICK := 3.0            # first moves away a little (reads as "snatched")
const FLY_ACCEL := 46.0
const FLY_MAX := 24.0
const LIFT := 0.25
const SOFT_CAP := 240
const MERGE_REACH := 3.0
## Value thresholds: below [0] small, below [1] medium, else big.
const XP_TIERS := [5.0, 14.0]
const XP_COLORS := [Color("3cc8ff"), Color("4ff07a"), Color("c26bff")]
const XP_SIZES := [0.72, 0.92, 1.25]
const GOLD_COLOR := Color("ffc52e")
const GOLD_SIZE := 0.8
const GOLD_PER_COIN := 5
const STRIDE := 20

var arena: Node3D
var pos := PackedVector3Array()
var start := PackedVector3Array()
var goal := PackedVector3Array()
var value := PackedFloat32Array()
var sort := PackedInt32Array()
var state := PackedInt32Array()
var timer := PackedFloat32Array()
var speed := PackedFloat32Array()
var phase := PackedFloat32Array()
var _free: Array[int] = []
var rng := RandomNumberGenerator.new()
var lying := 0
var moving := 0
## Statistics (tests, bot).
var spawned := 0
var merged := 0
var collected := 0
var _dirty := true
var _gems: MultiMeshInstance3D
var _coins: MultiMeshInstance3D
var _glow: MultiMeshInstance3D
var _gem_buffer := PackedFloat32Array()
var _coin_buffer := PackedFloat32Array()
var _glow_buffer := PackedFloat32Array()
var _capacity := 0
var _slot := PackedInt32Array()
var _slot_free: Array = [[], []]
var _slot_top: Array = [0, 0]


func _init() -> void:
	rng.seed = 16016


func _ready() -> void:
	_gems = _make_layer("Gems", _gem_mesh(), _item_material())
	_coins = _make_layer("Coins", _coin_mesh(), _item_material())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_glow = _make_layer("Glow", quad, _glow_material())
	_ensure_capacity(64)
	_redraw()


func setup(arena_node: Node3D) -> void:
	arena = arena_node


func clear() -> void:
	pos.clear(); start.clear(); goal.clear(); value.clear(); sort.clear()
	state.clear(); timer.clear(); speed.clear(); phase.clear()
	_free.clear()
	_slot.clear()
	_slot_free = [[], []]
	_slot_top = [0, 0]
	lying = 0
	moving = 0
	_dirty = true
	_redraw()


# ---------------------------------------------------------------- drops

## One XP gem worth `amount`, hopping out of `at`.
func drop_xp(at: Vector3, amount: float) -> int:
	if amount <= 0.0:
		return -1
	return _drop(Sort.XP, amount, at, _landing(at, 0.6, 1.3))


## Gold as coins (one per GOLD_PER_COIN, 1..4 coins), hopping out of `at`.
func drop_gold(at: Vector3, amount: int) -> void:
	if amount <= 0:
		return
	var coins := clampi(ceili(float(amount) / float(GOLD_PER_COIN)), 1, 4)
	var left := amount
	for index in coins:
		var share := left if index == coins - 1 else amount / coins
		left -= share
		_drop(Sort.GOLD, float(share), at, _landing(at, 0.8, 1.6))


func _landing(at: Vector3, near: float, far: float) -> Vector3:
	var angle := rng.randf() * TAU
	var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(near, far)
	spot.y = 0.0
	if arena != null and is_instance_valid(arena) and arena.has_method("is_open") and not arena.is_open(spot, 0.2):
		if arena.has_method("safe_spawn"):
			spot = arena.safe_spawn(spot, 0.25)
		else:
			spot = Vector3(at.x, 0.0, at.z)
		spot.y = 0.0
	return spot


func _drop(kind: int, amount: float, from: Vector3, landing: Vector3) -> int:
	# Too many gems lying around: join the nearest one of the same sort.
	if kind == Sort.XP and lying >= SOFT_CAP:
		var host := _nearest_lying(landing, MERGE_REACH, kind)
		if host < 0:
			host = _nearest_lying(landing, 40.0, kind)
		if host >= 0:
			value[host] += amount
			merged += 1
			spawned += 1
			_dirty = true
			_write(host)
			return host
	var id := _alloc()
	sort[id] = kind
	_slot[id] = _take_slot(kind)
	value[id] = amount
	phase[id] = rng.randf()
	start[id] = Vector3(from.x, 0.7, from.z)
	goal[id] = landing
	pos[id] = start[id]
	state[id] = State.HOP
	timer[id] = 0.0
	speed[id] = 0.0
	moving += 1
	spawned += 1
	_dirty = true
	_write(id)
	return id


func _alloc() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	var id := pos.size()
	pos.append(Vector3.ZERO); start.append(Vector3.ZERO); goal.append(Vector3.ZERO)
	value.append(0.0); sort.append(0); state.append(State.FREE)
	timer.append(0.0); speed.append(0.0); phase.append(0.0)
	_slot.append(-1)
	return id


func _release(id: int) -> void:
	state[id] = State.FREE
	value[id] = 0.0
	_free.append(id)
	_dirty = true
	_write(id)
	var own := _slot[id]
	if own >= 0:
		_zero(_gem_buffer if sort[id] == Sort.XP else _coin_buffer, own * STRIDE)
		(_slot_free[sort[id]] as Array).append(own)
		_slot[id] = -1


## Gems and coins draw from their own slot ranges (a coin layer never walks
## over the gem slots).
func _take_slot(kind: int) -> int:
	var free: Array = _slot_free[kind]
	if not free.is_empty():
		return free.pop_back()
	_slot_top[kind] = int(_slot_top[kind]) + 1
	return int(_slot_top[kind]) - 1


func _nearest_lying(at: Vector3, reach: float, kind: int) -> int:
	var best := -1
	var best_d := reach * reach
	for id in pos.size():
		if state[id] != State.LYING or sort[id] != kind:
			continue
		var d := Vector2(pos[id].x - at.x, pos[id].z - at.z).length_squared()
		if d < best_d:
			best_d = d
			best = id
	return best


static func tier_of(amount: float) -> int:
	if amount < XP_TIERS[0]:
		return 0
	return 1 if amount < XP_TIERS[1] else 2


# ---------------------------------------------------------------- magnet

## Hops, magnet and flights. `centre` = hero position, `radius` = magnet (m).
## Returns what arrived this step.
func step(delta: float, centre: Vector3, radius: float = MAGNET_RADIUS) -> Dictionary:
	var result := {"xp": 0.0, "gold": 0, "items": 0}
	var reach := radius * radius
	var aim := Vector3(centre.x, 0.8, centre.z)
	for id in pos.size():
		match state[id]:
			State.HOP:
				timer[id] += delta
				var t := clampf(timer[id] / HOP_SECONDS, 0.0, 1.0)
				var flat: Vector3 = start[id].lerp(goal[id], 1.0 - (1.0 - t) * (1.0 - t))
				flat.y = lerpf(start[id].y, LIFT, t) + 4.0 * HOP_HEIGHT * t * (1.0 - t)
				pos[id] = flat
				if t >= 1.0:
					state[id] = State.LYING
					pos[id] = Vector3(goal[id].x, LIFT, goal[id].z)
					moving -= 1
					lying += 1
				_dirty = true
				_write(id)
			State.LYING:
				var dx: float = pos[id].x - centre.x
				var dz: float = pos[id].z - centre.z
				if dx * dx + dz * dz <= reach:
					state[id] = State.FLY
					speed[id] = -FLY_KICK
					lying -= 1
					moving += 1
					_dirty = true
					_write(id)
			State.FLY:
				var here: Vector3 = pos[id]
				var offset := aim - here
				var distance := offset.length()
				speed[id] = minf(FLY_MAX, speed[id] + FLY_ACCEL * delta)
				var travel: float = speed[id] * delta
				if distance <= COLLECT_DISTANCE or travel >= distance:
					if sort[id] == Sort.XP:
						result.xp += value[id]
					else:
						result.gold += int(round(value[id]))
					result.items += 1
					collected += 1
					moving -= 1
					_release(id)
				else:
					pos[id] = here + offset / distance * travel
					_write(id)
				_dirty = true
	if _dirty:
		_dirty = false
		_commit_all()
	return result


## Credits everything at once (tests, captures).
func take_all() -> Dictionary:
	var result := {"xp": 0.0, "gold": 0, "items": 0}
	for id in pos.size():
		if state[id] == State.FREE:
			continue
		if sort[id] == Sort.XP:
			result.xp += value[id]
		else:
			result.gold += int(round(value[id]))
		result.items += 1
		collected += 1
		_release(id)
	lying = 0
	moving = 0
	_redraw()
	return result


# ---------------------------------------------------------------- queries

func count() -> int:
	return pos.size() - _free.size()


func count_of(kind: int) -> int:
	var total := 0
	for id in pos.size():
		if state[id] != State.FREE and sort[id] == kind:
			total += 1
	return total


func total(kind: int) -> float:
	var sum := 0.0
	for id in pos.size():
		if state[id] != State.FREE and sort[id] == kind:
			sum += value[id]
	return sum


## Nearest lying item (INF when none) within `reach` (bot, tests).
func nearest_lying(at: Vector3, reach: float = 40.0, kind: int = -1) -> Vector3:
	var best := Vector3.INF
	var best_d := reach * reach
	for id in pos.size():
		if state[id] != State.LYING or (kind >= 0 and sort[id] != kind):
			continue
		var d := Vector2(pos[id].x - at.x, pos[id].z - at.z).length_squared()
		if d < best_d:
			best_d = d
			best = pos[id]
	return best


# ---------------------------------------------------------------- drawing

func _redraw() -> void:
	# Full rewrite of every slot (clear, take_all); per step only changed slots.
	_dirty = false
	if _gems == null:
		return
	_ensure_capacity(pos.size())
	for id in pos.size():
		_write(id)
	_commit_all()


## Teil E (CPU): every item keeps fixed slots: its id in the glow MultiMesh and
## a slot of its sort's own range in the gem or coin MultiMesh; freed slots are
## zero-scaled.
## A step only rewrites the items that moved or changed and uploads each
## buffer once (no per-frame arrays).
func _ensure_capacity(wanted: int) -> void:
	if wanted <= _capacity:
		return
	var grown := maxi(64, _capacity)
	while grown < wanted:
		grown *= 2
	_capacity = grown
	for buffer_index in 3:
		var buffer: PackedFloat32Array = [_gem_buffer, _coin_buffer, _glow_buffer][buffer_index]
		var before := buffer.size()
		buffer.resize(grown * STRIDE)
		for index in range(before, buffer.size()):
			buffer[index] = 0.0
		match buffer_index:
			0: _gem_buffer = buffer
			1: _coin_buffer = buffer
			2: _glow_buffer = buffer
	for node in [_gems, _coins, _glow]:
		(node as MultiMeshInstance3D).multimesh.instance_count = grown


## Writes item `id` into its slot (zeroes the slots it does not use).
func _write(id: int) -> void:
	if _gems == null:
		return
	_ensure_capacity(pos.size())
	var k := id * STRIDE
	# Packed arrays are shared by reference: the helpers write in place.
	var gems := _gem_buffer
	var coins := _coin_buffer
	var glows := _glow_buffer
	var st := state[id]
	var own := _slot[id] * STRIDE if id < _slot.size() else -1
	if st == State.FREE:
		_zero(glows, k)
	elif own >= 0:
		var flying := 1.0 if st == State.FLY else (0.5 if st == State.HOP else 0.0)
		var at := pos[id]
		var ph := phase[id]
		var tint: Color
		var size: float
		if sort[id] == Sort.XP:
			var tier := tier_of(value[id])
			tint = XP_COLORS[tier]
			size = XP_SIZES[tier]
			_put(gems, own, at, size, size * (1.0 + 0.3 * flying), tint, ph, flying, 0.0)
		else:
			tint = GOLD_COLOR
			size = GOLD_SIZE
			_put(coins, own, at, size, size, tint, ph, flying, 1.0)
		var glow := size * (1.7 + 0.5 * flying)
		_put(glows, k, Vector3(at.x, at.y + size * 0.45, at.z), glow, glow, tint, ph, flying, 0.0)


## One instance at offset k: transform (rows), colour, custom (phase, flight, coin).
static func _put(buffer: PackedFloat32Array, k: int, at: Vector3, width: float, height: float, tint: Color, ph: float, flying: float, coin: float) -> void:
	buffer[k] = width
	buffer[k + 1] = 0.0
	buffer[k + 2] = 0.0
	buffer[k + 3] = at.x
	buffer[k + 4] = 0.0
	buffer[k + 5] = height
	buffer[k + 6] = 0.0
	buffer[k + 7] = at.y
	buffer[k + 8] = 0.0
	buffer[k + 9] = 0.0
	buffer[k + 10] = width
	buffer[k + 11] = at.z
	buffer[k + 12] = tint.r
	buffer[k + 13] = tint.g
	buffer[k + 14] = tint.b
	buffer[k + 15] = 1.0
	buffer[k + 16] = ph
	buffer[k + 17] = flying
	buffer[k + 18] = coin
	buffer[k + 19] = 0.0


static func _zero(buffer: PackedFloat32Array, k: int) -> void:
	if buffer[k] == 0.0 and buffer[k + 5] == 0.0:
		return
	for c in 12:
		buffer[k + c] = 0.0


func _commit_all() -> void:
	for pair in [[_gems, _gem_buffer, int(_slot_top[Sort.XP])], [_coins, _coin_buffer, int(_slot_top[Sort.GOLD])], [_glow, _glow_buffer, pos.size()]]:
		var node: MultiMeshInstance3D = pair[0]
		var used: int = pair[2]
		node.multimesh.buffer = pair[1]
		node.multimesh.visible_instance_count = used
		node.visible = used > 0 and count() > 0

func _make_layer(layer_name: String, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 64
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = layer_name
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	# Items spread over the whole map: never culled by the batch box.
	node.custom_aabb = AABB(Vector3(-100000.0, -10.0, -100000.0), Vector3(200000.0, 40.0, 200000.0))
	add_child(node)
	node.top_level = true
	node.transform = Transform3D.IDENTITY
	return node


# Faceted gem: an octahedron with a taller top (height 1, base at y 0).
static func _gem_mesh() -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 1.0, 0.0)
	var bottom := Vector3(0.0, 0.0, 0.0)
	var ring: Array[Vector3] = []
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		ring.append(Vector3(cos(a) * 0.36, 0.42, sin(a) * 0.36))
	for k in 4:
		var a := ring[k]
		var b := ring[(k + 1) % 4]
		for tri in [[top, b, a], [bottom, a, b]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				tool.set_normal(n)
				tool.add_vertex(v)
	return tool.commit()


# Coin: a thick disc standing upright (spins in the shader), height 1.
static func _coin_mesh() -> Mesh:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.14
	disc.radial_segments = 14
	disc.rings = 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tilted back towards the steep game camera so the face reads as a coin.
	tool.append_from(disc, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.85), Vector3(0.0, 0.5, 0.0)))
	return tool.commit()


static var _materials := {}


static func _item_material() -> ShaderMaterial:
	if _materials.has("item"):
		return _materials["item"]
	var shader := Shader.new()
	shader.code = ITEM_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_materials["item"] = material
	return material


static func _glow_material() -> ShaderMaterial:
	if _materials.has("glow"):
		return _materials["glow"]
	var shader := Shader.new()
	shader.code = GLOW_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_materials["glow"] = material
	return material


# INSTANCE_CUSTOM: x = phase, y = flight (0 lying, 0.5 hopping, 1 flying),
# z = coin (coins rock towards the camera instead of spinning edge-on).
const ITEM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
varying vec4 info;
varying vec3 tint;
void vertex() {
	info = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
	float a = TIME * (1.4 + 4.0 * info.y) + info.x * 6.2832;
	a = mix(a, 0.55 * sin(TIME * 2.2 + info.x * 6.2832) + 3.0 * info.y * TIME, info.z);
	mat2 turn = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xz = turn * VERTEX.xz;
	NORMAL.xz = turn * NORMAL.xz;
	VERTEX.y += 0.16 * (1.0 - info.y) * (0.5 + 0.5 * sin(TIME * 2.6 + info.x * 6.2832));
}
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float pulse = 0.5 + 0.5 * sin(TIME * 3.0 + info.x * 6.2832);
	vec3 light = mix(tint, vec3(1.0), 0.55);
	vec3 col = tint * (0.62 + 0.5 * facing);
	col += light * pow(1.0 - facing, 2.0) * (0.45 + 0.25 * pulse);
	col = mix(col, light, 0.3 * info.y);
	ALBEDO = col;
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 info;
varying vec3 tint;
void vertex() {
	info = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float fall = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0 + info.x * 6.2832);
	ALBEDO = tint;
	ALPHA = clamp(fall * pulse * (0.32 + 0.35 * info.y), 0.0, 1.0);
}
"""
