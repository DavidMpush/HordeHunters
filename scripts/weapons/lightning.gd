extends "res://scripts/weapons/weapon.gd"

# Blitzkette (stage 4, Teil B): extra weapon for every hero.
#   Every COOLDOWN s (fire rate), while an enemy is within AIM_RANGE, a bolt
#   leaps from the hero's hand to the nearest enemy and from there on to the
#   nearest enemy not hit yet within JUMP_RANGE, `jumps()` times; each jump
#   deals JUMP_FALLOFF less. Every hit interrupts a wind-up (horde.hurt
#   staggers medium and light enemies), so the chain is a defensive tool in a
#   dense horde, and the bright cyan zigzag reads well from the top camera.
#   Rank 1 three jumps, 2 +1 jump and +20 % jump range, 3 +30 % damage and
#   faster, 4 the chain forks at the first target, 5 +2 jumps, 6 two chains
#   per discharge. Damage x power_factor().
#   Evolution "Gewittersturm" (partner relic Lockstein): a lightning strike
#   from the sky at the first target (area damage with knockback), +3 jumps,
#   violet bolts.

const STREAKS := preload("res://scripts/weapons/streaks.gd")

const COOLDOWN := 1.7
const AIM_RANGE := 8.0
const JUMP_RANGE := 3.4
const JUMPS := 3
const DAMAGE := 16.0
const JUMP_FALLOFF := 0.9
const KNOCK := [1.2, 0.4, 0.0]
const STRIKE_RADIUS := 2.0
const STRIKE_DAMAGE := 26.0
const STRIKE_KNOCK := [6.0, 2.5, 0.0]
const HAND_HEIGHT := 1.3
const HIT_HEIGHT := 1.05
const COLOR := Color(0.45, 0.85, 1.0, 0.95)
const EVO_COLOR := Color(0.78, 0.55, 1.0, 0.95)

var casts := 0
var chains := 0
var strikes := 0
## Enemies hit by the last discharge (tests): {index: data}; the order of the
## hops in last_path (positions, hero first).
var last_hits: Dictionary = {}
var last_path: Array[Vector3] = []
var fx: Node3D


func _init() -> void:
	super()
	id = "lightning"
	source = "Blitzkette"


func _ready() -> void:
	fx = STREAKS.new()
	fx.name = "LightningFx"
	add_child(fx)


func reset() -> void:
	super()
	casts = 0
	chains = 0
	strikes = 0
	last_hits = {}
	last_path.clear()
	if fx != null:
		fx.clear()


func jumps() -> int:
	return JUMPS + (1 if rank() >= 2 else 0) + (2 if rank() >= 5 else 0) + (3 if evolved() else 0)


func jump_range() -> float:
	return JUMP_RANGE * (1.2 if rank() >= 2 else 1.0) * range_mult()


func damage() -> float:
	return DAMAGE * power_factor() * (1.3 if rank() >= 3 else 1.0)


func cooldown() -> float:
	return cooldown_time(COOLDOWN - (0.3 if rank() >= 3 else 0.0))


func chain_count() -> int:
	return 2 if rank() >= 6 else 1


func forks() -> bool:
	return rank() >= 4


func step(delta: float) -> void:
	if fx != null:
		fx.step(delta)
	if not can_act():
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if cooldown_left > 0.0:
		return
	var first := nearest_target(AIM_RANGE * range_mult())
	if first < 0:
		return
	discharge(first)
	cooldown_left = cooldown()


## One discharge starting at enemy `first`: chain_count() chains (the second
## starts at the nearest enemy the first chain missed), fork, evolution
## strike. All hits are gathered and applied at once. Returns the kills.
func discharge(first: int) -> int:
	var hits := {}
	var hand := hero_at() + Vector3.UP * HAND_HEIGHT
	last_path.clear()
	last_path.append(hero_at())
	var start := first
	for c in chain_count():
		if start < 0:
			break
		_chain(hand, start, jumps(), hits)
		chains += 1
		if forks():
			var next := _next_target(horde.position_of(start), hits)
			if next >= 0:
				_chain(_lift(horde.position_of(start)), next, maxi(1, jumps() >> 1), hits)
		start = _next_target(hero_at(), hits, AIM_RANGE * range_mult())
	if evolved():
		_strike(horde.position_of(first), hits)
	last_hits = hits.duplicate(true)
	casts += 1
	attacks += 1
	var killed := apply(hits)
	_sound("shot", 1.6)
	_sound("hit", 1.8)
	_shake(0.05)
	return killed


# Bolt from `from` to `target`, then `hops` jumps on to the nearest new enemy.
func _chain(from: Vector3, target: int, hops: int, hits: Dictionary) -> void:
	var base := damage()
	var at := from
	var current := target
	var scale := 1.0
	var tint := EVO_COLOR if evolved() else COLOR
	var width := 0.34 if evolved() else 0.3
	for hop in hops + 1:
		if current < 0:
			break
		var p: Vector3 = horde.position_of(current)
		var to := _lift(p)
		var push := Vector3(p.x - at.x, 0.0, p.z - at.z)
		push = push.normalized() if push.length_squared() > 0.0001 else Vector3.FORWARD
		if not hits.has(current):
			hits[current] = {"damage": 0.0, "dir": push, "knock": knock_by_mass(current, KNOCK)}
		hits[current].damage += roll_damage(base * scale)
		if fx != null:
			fx.bolt(at, to, tint, width, 0.28)
			fx.orb(to, 0.32, Color(tint, 0.7), 0.16)
		if _fx():
			effects.hit_sparks(to, push, 3)
		last_path.append(Vector3(p.x, 0.0, p.z))
		at = to
		scale *= JUMP_FALLOFF
		current = _next_target(p, hits)


# Nearest living enemy to `point` within `max_range` (default jump range)
# that `hits` does not hold yet; the boss counts too. -1 when none.
func _next_target(point: Vector3, hits: Dictionary, max_range: float = -1.0) -> int:
	var reach := jump_range() if max_range < 0.0 else max_range
	var best := -1
	var best_d := reach * reach
	for i in horde.count():
		if hits.has(i):
			continue
		var p: Vector3 = horde.position_of(i)
		var d := (p.x - point.x) * (p.x - point.x) + (p.z - point.z) * (p.z - point.z)
		if d < best_d:
			best_d = d
			best = i
	if not hits.has(BOSS_SLOT) and boss_in_circle(Vector3(point.x, 0.0, point.z), reach):
		var b: Vector3 = horde.position_of(BOSS_SLOT)
		if best < 0 or Vector2(b.x - point.x, b.z - point.z).length_squared() < best_d:
			best = BOSS_SLOT
	return best


# Gewittersturm: a bolt from the sky onto `at`, area damage with knockback.
func _strike(at: Vector3, hits: Dictionary) -> void:
	var center := Vector3(at.x, 0.0, at.z)
	var radius := STRIKE_RADIUS * range_mult()
	for index in enemies_in_circle(center, radius):
		var p: Vector3 = horde.position_of(index)
		var out := Vector3(p.x - center.x, 0.0, p.z - center.z)
		out = out.normalized() if out.length_squared() > 0.0001 else Vector3.FORWARD
		if not hits.has(index):
			hits[index] = {"damage": 0.0, "dir": out, "knock": 0.0}
		hits[index].damage += roll_damage(STRIKE_DAMAGE * power_factor())
		hits[index].dir = out
		hits[index].knock = knock_by_mass(index, STRIKE_KNOCK)
	strikes += 1
	if fx != null:
		fx.bolt(center + Vector3.UP * 9.0, center + Vector3.UP * 0.2, EVO_COLOR, 0.5, 0.3)
		fx.bolt(center + Vector3.UP * 9.0 + Vector3(0.6, 0, 0.3), center + Vector3.UP * 0.2, Color(1.0, 1.0, 1.0, 0.8), 0.22, 0.24)
		fx.orb(center + Vector3.UP * 0.3, radius * 0.8, Color(0.85, 0.7, 1.0, 0.75), 0.24)
	if _fx():
		effects.ring(center, Color(0.85, 0.7, 1.0, 0.9), 0.3, radius, 0.3)
		effects.dust(center, 5, 0.8, Color(0.75, 0.7, 0.9, 0.6))
	_shake(0.12)
	_sound("slam", 1.6)


static func _lift(p: Vector3) -> Vector3:
	return Vector3(p.x, HIT_HEIGHT, p.z)
