extends "res://scripts/weapons/weapon.gd"

# Schwert-Wirbel (stage 3, Teil B §4): extra weapon for every hero.
#   Every COOLDOWN s (2.5 s, fire rate) - as soon as an enemy is inside the
#   circle - a sword spins once round the hero (SPIN_SECONDS) and hits
#   everything within RADIUS with knockback by mass (light far, medium a
#   little, heavy and bosses not). A steel-blue full-circle swipe and the
#   orbiting blade show the reach.
#   Rank 1 base, 2 more damage + faster, 3 radius +25 %, 4 more damage +
#   faster, 5 double spin, 6 Klingensturm (radius +20 %, +30 % damage).
#   Damage x power_factor().
#   Evolution "Klingenorkan" (partner relic Siebenmeilenstiefel): whirl +20 %
#   and two ice-blue blades orbit the hero all the time (ORBIT_SPEED); every
#   enemy they sweep takes ORBIT_SHARE of the damage, at most every
#   ORBIT_REHIT s. A faint ground ring shows their reach.

const FX := preload("res://scripts/weapons/weapon_fx.gd")
const ORBIT_SPEED := 7.0
const ORBIT_WINDOW := 0.35
const ORBIT_SHARE := 0.55
const ORBIT_REHIT := 0.5
const ORBIT_KNOCK := [4.0, 1.5, 0.0]
const STORM_RADIUS := 1.2
const STORM_STEEL := Color("9fe8ff")

const COOLDOWN := 2.5
const RADIUS := 2.7
const DAMAGE := 18.0
const KNOCK := [7.0, 3.0, 0.0]
const SPIN_SECONDS := 0.24
const SECOND_SPIN_DELAY := 0.3
const TINT := Color(0.6, 0.85, 1.0)

var spins := 0
var last_hits: Dictionary = {}
## Seconds left of the visible blade orbit (-1 = hidden) and its start angle.
var orbit_left := -1.0
var _orbit_angle := 0.0
var _second_left := -1.0
var fx: Node3D
var _blade: Node3D
## Klingenorkan: orbit angle, hits so far, rehit clock per enemy index.
var orbit_phase := 0.0
var orbit_hits := 0
var _orbit_clock := 0.0
var _orbit_prune := 0.0
var _orbit_last: Dictionary = {}
var _orbit_batch: Dictionary = {}
var _orbit_blades: Array[Node3D] = []
var _orbit_ring: MeshInstance3D


func _init() -> void:
	super()
	id = "sword"
	source = "Schwert-Wirbel"


func _ready() -> void:
	fx = FX.new()
	fx.name = "SwordFx"
	add_child(fx)
	_blade = Node3D.new()
	_blade.name = "Blade"
	add_child(_blade)
	_blade.top_level = true
	_build_blade(_blade, Color("dfe7f2"))
	_blade.visible = false


func reset() -> void:
	super()
	spins = 0
	last_hits = {}
	orbit_left = -1.0
	_second_left = -1.0
	orbit_phase = 0.0
	orbit_hits = 0
	_orbit_last.clear()
	if fx != null:
		fx.clear()
	_show_orbit(false)


func radius() -> float:
	return RADIUS * (1.25 if rank() >= 3 else 1.0) * (1.2 if rank() >= 6 else 1.0) * (STORM_RADIUS if evolved() else 1.0) * range_mult()


func cooldown() -> float:
	var base := COOLDOWN - (0.3 if rank() >= 2 else 0.0) - (0.3 if rank() >= 4 else 0.0)
	return cooldown_time(base)


func damage() -> float:
	return DAMAGE * power_factor() * (1.3 if rank() >= 6 else 1.0)


func step(delta: float) -> void:
	if fx != null:
		fx.step(delta)
	_animate(delta)
	if not can_act():
		_show_orbit(false)
		return
	if evolved():
		orbit(delta)
	else:
		_show_orbit(false)
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if _second_left > 0.0:
		_second_left -= delta
		if _second_left <= 0.0:
			_second_left = -1.0
			spin(-1.0)
	if cooldown_left <= 0.0 and not enemies_in_circle(hero_at(), radius()).is_empty():
		spin(1.0)
		cooldown_left = cooldown()
		if rank() >= 5:
			_second_left = SECOND_SPIN_DELAY


## One spin: hits everything in the circle. Returns the kills.
func spin(direction: float = 1.0) -> int:
	var at := hero_at()
	var r := radius()
	var hits := {}
	for index in enemies_in_circle(at, r):
		var p: Vector3 = horde.position_of(index)
		var out := Vector3(p.x - at.x, 0.0, p.z - at.z)
		out = out.normalized() if out.length_squared() > 0.0001 else Vector3.FORWARD
		# Pushed out and a little along the swing (tangent).
		var tangent := Vector3(-out.z, 0.0, out.x) * direction
		hits[index] = {"damage": roll_damage(damage()), "dir": (out + tangent * 0.35).normalized(), "knock": knock_by_mass(index, KNOCK)}
		if _fx():
			effects.hit_sparks(Vector3(p.x, 0.8, p.z), tangent, 3)
	last_hits = hits.duplicate(true)
	spins += 1
	attacks += 1
	var killed := apply(hits)
	var facing: Vector3 = hero.get("facing") if hero.get("facing") is Vector3 else Vector3.FORWARD
	if fx != null:
		fx.swipe(at, facing, r + 0.15, PI, SPIN_SECONDS + 0.12, direction, TINT, r * 0.5, 0.75)
	orbit_left = SPIN_SECONDS
	_orbit_angle = atan2(facing.x, facing.z) - PI * direction
	_blade.set_meta("dir", direction)
	_sound("dash", 1.1)
	if not hits.is_empty():
		_sound("hit", 0.9)
		_shake(0.06)
	return killed


func _animate(delta: float) -> void:
	if _blade == null:
		return
	if orbit_left < 0.0:
		_blade.visible = false
		return
	orbit_left -= delta
	var t := clampf(1.0 - orbit_left / SPIN_SECONDS, 0.0, 1.0)
	var direction := float(_blade.get_meta("dir", 1.0))
	var angle := _orbit_angle + TAU * t * direction
	_blade.visible = orbit_left > -0.05 and hero != null
	if hero == null:
		return
	var r := radius()
	_blade.global_transform = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(1.0, 1.0, r / RADIUS)), hero_at() + Vector3.UP * 0.85)
	if orbit_left <= 0.0:
		orbit_left = -1.0


## Klingenorkan: the two orbiting blades move on and sweep every enemy whose
## body they pass (each at most every ORBIT_REHIT s). No allocation unless
## something is hit. Returns the kills.
func orbit(delta: float) -> int:
	orbit_phase = fposmod(orbit_phase + ORBIT_SPEED * delta, TAU)
	_orbit_clock += delta
	_orbit_prune += delta
	if _orbit_prune > 2.0:
		_orbit_prune = 0.0
		_orbit_last.clear()
	var at := hero_at()
	var r := radius()
	_place_orbit(at, r)
	_orbit_batch.clear()
	var base := damage() * ORBIT_SHARE
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		if _swept(at, p, r + float(horde.radius_of_kind(horde.kind_of(i)))) and float(_orbit_last.get(i, -1.0)) <= _orbit_clock:
			_orbit_last[i] = _orbit_clock + ORBIT_REHIT
			var out := Vector3(p.x - at.x, 0.0, p.z - at.z).normalized()
			_orbit_batch[i] = {"damage": roll_damage(base), "dir": (out + Vector3(-out.z, 0.0, out.x) * 0.5).normalized(), "knock": knock_by_mass(i, ORBIT_KNOCK)}
	if boss_in_circle(at, r) and float(_orbit_last.get(BOSS_SLOT, -1.0)) <= _orbit_clock and _swept(at, horde.position_of(BOSS_SLOT), r + float(horde._boss_radius())):
		_orbit_last[BOSS_SLOT] = _orbit_clock + ORBIT_REHIT
		_orbit_batch[BOSS_SLOT] = {"damage": roll_damage(base), "dir": Vector3.FORWARD}
	if _orbit_batch.is_empty():
		return 0
	orbit_hits += _orbit_batch.size()
	if _fx():
		for i in _orbit_batch:
			var p: Vector3 = horde.position_of(i)
			effects.hit_sparks(Vector3(p.x, 0.8, p.z), _orbit_batch[i].dir, 2)
	_sound("hit", 1.25)
	return apply(_orbit_batch)


# Is `p` (reach = blade length + body) under one of the two blades?
func _swept(at: Vector3, p: Vector3, reach: float) -> bool:
	var dx := p.x - at.x
	var dz := p.z - at.z
	var d2 := dx * dx + dz * dz
	if d2 > reach * reach or d2 < 0.09:
		return false
	var diff := absf(wrapf(atan2(dx, dz) - orbit_phase, -PI, PI))
	return diff < ORBIT_WINDOW or PI - diff < ORBIT_WINDOW


func _place_orbit(at: Vector3, r: float) -> void:
	if _blade == null:
		return
	if _orbit_blades.is_empty():
		for k in 2:
			var node := Node3D.new()
			node.name = "OrbitBlade%d" % k
			add_child(node)
			node.top_level = true
			_build_blade(node, STORM_STEEL)
			_orbit_blades.append(node)
		_orbit_ring = ground_ring(_orbit_blades[0], Color(0.55, 0.9, 1.0, 0.35))
		_orbit_ring.top_level = true
	for k in 2:
		var node := _orbit_blades[k]
		node.visible = true
		node.global_transform = Transform3D(Basis(Vector3.UP, orbit_phase + PI * float(k)).scaled(Vector3(1.15, 1.0, r / RADIUS)), at + Vector3.UP * 0.8)
	_orbit_ring.visible = true
	_orbit_ring.global_transform = Transform3D(Basis.from_scale(Vector3(r, 0.25, r)), at + Vector3.UP * 0.07)


func _show_orbit(on: bool) -> void:
	for node in _orbit_blades:
		node.visible = on
	if _orbit_ring != null:
		_orbit_ring.visible = on


# Blade along local +Z from the hilt at 0.45 m to the tip at RADIUS.
func _build_blade(target: Node3D, steel: Color) -> void:
	var length := RADIUS - 0.5
	part(target, box(Vector3(0.1, 0.12, 0.34)), Color("5a3420"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.35)))
	part(target, box(Vector3(0.5, 0.1, 0.1)), Color("e8b64a"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.55)))
	part(target, box(Vector3(0.22, 0.05, length)), steel, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.6 + length * 0.5)))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.22, 0.3, 0.05)
	part(target, tip, Color("ffffff"), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.6 + length + 0.15)))
