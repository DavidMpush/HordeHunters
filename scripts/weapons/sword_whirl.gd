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

const FX := preload("res://scripts/weapons/weapon_fx.gd")

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
	_build_blade()
	_blade.visible = false


func reset() -> void:
	super()
	spins = 0
	last_hits = {}
	orbit_left = -1.0
	_second_left = -1.0
	if fx != null:
		fx.clear()


func radius() -> float:
	return RADIUS * (1.25 if rank() >= 3 else 1.0) * (1.2 if rank() >= 6 else 1.0) * range_mult()


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
		return
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


# Blade along local +Z from the hilt at 0.45 m to the tip at RADIUS.
func _build_blade() -> void:
	var length := RADIUS - 0.5
	part(_blade, box(Vector3(0.1, 0.12, 0.34)), Color("5a3420"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.35)))
	part(_blade, box(Vector3(0.5, 0.1, 0.1)), Color("e8b64a"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.55)))
	part(_blade, box(Vector3(0.22, 0.05, length)), Color("dfe7f2"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.6 + length * 0.5)))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.22, 0.3, 0.05)
	part(_blade, tip, Color("ffffff"), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.6 + length + 0.15)))
