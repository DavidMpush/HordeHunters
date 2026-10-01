extends "res://scripts/weapons/weapon.gd"

# Wurfaxt (stage 3, Teil B §4): extra weapon for every hero.
#   Every COOLDOWN s (fire rate) while an enemy is within AIM_RANGE the hero
#   throws axes at it. An axe flies out on a curved loop (ellipse: out along
#   the aim, bowing to one side) and comes back to the hero; it spins and goes
#   through everything (each enemy at most once per pass: out and back). Light enemies are knocked along its flight.
#   Rank 1 one axe, 2 more damage + reach, 3 two axes, 4 more damage + faster,
#   5 three axes, 6 Riesenaxt (+40 % damage, reach). Damage x power_factor().
#   Evolution "Blutmond-Axt" (partner relic Jagdtrophäe): +1 axe, +50 % damage,
#   1.45x size and hit radius, blood-red blades and spin disc, hits heal.

const COOLDOWN := 1.8
const AIM_RANGE := 9.0
const OUT_RANGE := 6.5
const FLIGHT := 1.05
const BOW := 0.9
const DAMAGE := 14.0
const HIT_RADIUS := 0.55
const KNOCK := [3.0, 1.0, 0.0]
const HEIGHT := 1.0
const SPIN := 22.0
const REHIT := 0.3
const SIZE := 1.7
## Blutmond-Axt (evolution).
const BLOOD_MULT := 1.5
const BLOOD_SIZE := 1.45
const BLOOD_HEAL := 0.4
const BLOOD_HEAL_HITS := 4

var axes: Array[Dictionary] = []
var throws := 0
var hits_total := 0
var _root: Node3D
var _meshes: Array[Node3D] = []
var _mesh_blood := false
var healed := 0.0


func _init() -> void:
	super()
	id = "axe"
	source = "Wurfaxt"


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Axes"
	add_child(_root)
	_root.top_level = true


func reset() -> void:
	super()
	axes.clear()
	throws = 0
	hits_total = 0
	healed = 0.0
	_draw()


func axe_count() -> int:
	var r := rank()
	return (3 if r >= 5 else (2 if r >= 3 else 1)) + (1 if evolved() else 0)


func out_range() -> float:
	return (OUT_RANGE + (0.8 if rank() >= 2 else 0.0) + (0.8 if rank() >= 6 else 0.0)) * range_mult()


func cooldown() -> float:
	return cooldown_time(COOLDOWN - (0.3 if rank() >= 4 else 0.0))


func damage() -> float:
	return DAMAGE * power_factor() * (1.4 if rank() >= 6 else 1.0) * (BLOOD_MULT if evolved() else 1.0)


func hit_radius() -> float:
	return HIT_RADIUS * (BLOOD_SIZE if evolved() else 1.0)


func step(delta: float) -> void:
	_fly(delta)
	if not can_act():
		_draw()
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if cooldown_left <= 0.0:
		var target := nearest_target(AIM_RANGE * range_mult())
		if target >= 0:
			var to: Vector3 = horde.position_of(target) - hero_at()
			to.y = 0.0
			throw(to.normalized() if to.length_squared() > 0.0001 else Vector3.FORWARD)
	_draw()


## Throws axe_count() axes fanned round `direction`.
func throw(direction: Vector3) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var count := axe_count()
	for k in count:
		var spread := (float(k) - float(count - 1) * 0.5) * 0.32
		var d := dir.rotated(Vector3.UP, spread)
		# Alternate the bow side so two axes draw a heart shape.
		var side := 1.0 if k % 2 == 0 else -1.0
		axes.append({"start": hero_at(), "dir": d, "side": side, "age": 0.0, "range": out_range(),
			"done": {}, "pos": hero_at(), "spin": 0.0})
	cooldown_left = cooldown()
	throws += 1
	attacks += 1
	_sound("dash", 1.35)


func _fly(delta: float) -> void:
	for index in range(axes.size() - 1, -1, -1):
		var axe: Dictionary = axes[index]
		axe.age += delta
		var u: float = clampf(axe.age / FLIGHT, 0.0, 1.0)
		var dir: Vector3 = axe.dir
		var side := Vector3(-dir.z, 0.0, dir.x) * float(axe.side)
		var reach: float = axe.range
		var theta := TAU * u
		var centre: Vector3 = axe.start + dir * reach * 0.5
		var pos := centre - dir * reach * 0.5 * cos(theta) + side * BOW * sin(theta)
		# On the way back it homes onto the hero where he is now.
		if hero != null:
			pos = pos.lerp(hero_at(), smoothstep(0.55, 1.0, u))
		var travel: Vector3 = pos - axe.pos
		axe.pos = pos
		axe.spin += SPIN * delta
		if horde != null:
			_hit(axe, travel)
		if u >= 1.0:
			axes.remove_at(index)


func _hit(axe: Dictionary, travel: Vector3) -> void:
	# One hit per enemy and pass: an index stays blocked for REHIT s (an axe
	# crosses a body in < 0.1 s; out and back are separate passes).
	var done: Dictionary = axe.done
	for key in done.keys():
		if float(done[key]) <= float(axe.age):
			done.erase(key)
	var hits := {}
	var flight := Vector3(travel.x, 0.0, travel.z)
	flight = flight.normalized() if flight.length_squared() > 0.00001 else Vector3(axe.dir)
	for index in enemies_in_circle(axe.pos, hit_radius()):
		if done.has(index):
			continue
		done[index] = float(axe.age) + REHIT
		hits[index] = {"damage": roll_damage(damage()), "dir": flight, "knock": knock_by_mass(index, KNOCK)}
		if _fx():
			var p: Vector3 = horde.position_of(index)
			effects.hit_sparks(Vector3(p.x, 0.8, p.z), flight, 4)
	if not hits.is_empty():
		hits_total += hits.size()
		apply(hits)
		_sound("hit", 1.3)
		if evolved() and not hero.is_dead():
			var before: float = hero.health
			hero.health = minf(hero.max_health, hero.health + BLOOD_HEAL * float(mini(hits.size(), BLOOD_HEAL_HITS)))
			healed += hero.health - before


func _draw() -> void:
	if _root == null or not _root.is_inside_tree():
		return
	# The evolution swaps the look: the pooled meshes are built again once.
	if evolved() != _mesh_blood:
		_mesh_blood = evolved()
		for node in _meshes:
			node.queue_free()
		_meshes.clear()
	while _meshes.size() < axes.size():
		_meshes.append(_make_axe())
	for index in _meshes.size():
		var node := _meshes[index]
		if index >= axes.size():
			node.visible = false
			continue
		var axe: Dictionary = axes[index]
		node.visible = true
		var p: Vector3 = axe.pos
		# Flat spin round the vertical axis, tilted a little towards the camera.
		node.global_transform = Transform3D((Basis(Vector3.UP, float(axe.spin)) * Basis(Vector3.RIGHT, -0.35)).scaled(Vector3.ONE * SIZE * (BLOOD_SIZE if _mesh_blood else 1.0)), Vector3(p.x, HEIGHT, p.z))


func _make_axe() -> Node3D:
	var node := Node3D.new()
	node.name = "Axe"
	_root.add_child(node)
	node.top_level = true

	# Handle along local +Z, blade at the far end facing sideways.
	part(node, box(Vector3(0.1, 0.1, 0.9)), Color("8c4f26"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.1)))
	part(node, box(Vector3(0.12, 0.12, 0.14)), Color("4a4f57"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.3)))
	var blade := PrismMesh.new()
	blade.size = Vector3(0.62, 0.5, 0.08)
	part(node, blade, Color("d01c34") if _mesh_blood else Color("d9e0ea"), Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(0.28, 0, 0.3)))
	part(node, box(Vector3(0.08, 0.06, 0.52)), Color("ffb4a8") if _mesh_blood else Color("ffffff"), Transform3D(Basis.IDENTITY, Vector3(0.56, 0, 0.3)))
	# Spin blur: a pale disc the size of the swing (cartoon motion blur).
	var disc := CylinderMesh.new()
	disc.top_radius = 0.62
	disc.bottom_radius = 0.62
	disc.height = 0.02
	disc.radial_segments = 20
	disc.rings = 1
	var blur := MeshInstance3D.new()
	blur.mesh = disc
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.18, 0.24, 0.5) if _mesh_blood else Color(0.92, 0.96, 1.0, 0.38)
	material.render_priority = 1
	blur.material_override = material
	blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blur.position = Vector3(0, 0, 0.1)
	node.add_child(blur)
	return node
