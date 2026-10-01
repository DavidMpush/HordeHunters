extends "res://scripts/weapons/weapon.gd"

# Doppelpistolen (stage 4, Teil B): extra weapon for every hero.
#   Two pistols fire in turns every COOLDOWN s (fire rate): the left one at the
#   nearest enemy within RANGE, the right one at the second nearest (or the
#   nearest again). Hitscan bullets (horde.raycast) stop at the first body or
#   go on through `pierce` more; a small knock on light enemies only.
#   Picks off runners and stragglers far away - the counterpart of the close
#   shotgun fan - and the alternating thin streaks read well from above.
#   Rank 1 base, 2 fires 25 % faster, 3 pierce 1, 4 +35 % damage, 5 two
#   bullets per shot, 6 pierce +1 and +25 % range. Damage x power_factor().
#   Evolution "Kugelhagel" (partner relic Kriegstrommel): three bullets in a
#   tight fan, 1.8x fire rate, +2 pierce, +25 % damage, hot red streaks.

const STREAKS := preload("res://scripts/weapons/streaks.gd")

const COOLDOWN := 0.42
const RANGE := 10.0
const DAMAGE := 9.0
const KNOCK := [1.6, 0.5, 0.0]
const SPREAD := 0.06
const EVO_SPREAD := 0.05
const MUZZLE_SIDE := 0.38
const MUZZLE_HEIGHT := 1.15
const COLOR := Color(1.0, 0.92, 0.55, 0.95)
const EVO_COLOR := Color(1.0, 0.32, 0.18, 0.95)

var hand := 0
var shots := 0
var bullets_fired := 0
var last_hits: Dictionary = {}
var fx: Node3D


func _init() -> void:
	super()
	id = "pistols"
	source = "Doppelpistolen"


func _ready() -> void:
	fx = STREAKS.new()
	fx.name = "PistolFx"
	add_child(fx)


func reset() -> void:
	super()
	hand = 0
	shots = 0
	bullets_fired = 0
	last_hits = {}
	if fx != null:
		fx.clear()


func cooldown() -> float:
	var base := COOLDOWN * (0.8 if rank() >= 2 else 1.0) / (1.8 if evolved() else 1.0)
	return cooldown_time(base)


func reach() -> float:
	return RANGE * (1.25 if rank() >= 6 else 1.0) * range_mult()


func pierce() -> int:
	return (1 if rank() >= 3 else 0) + (1 if rank() >= 6 else 0) + (2 if evolved() else 0)


func bullets() -> int:
	if evolved():
		return 3
	return 2 if rank() >= 5 else 1


func damage() -> float:
	return DAMAGE * power_factor() * (1.35 if rank() >= 4 else 1.0) * (1.25 if evolved() else 1.0)


func step(delta: float) -> void:
	if fx != null:
		fx.step(delta)
	if not can_act():
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if cooldown_left > 0.0:
		return
	var targets := _two_nearest(reach())
	var first: int = targets.x
	if first < 0:
		return
	var target: int = first if hand == 0 or targets.y < 0 else targets.y
	var to: Vector3 = horde.position_of(target) - hero_at()
	to.y = 0.0
	if to.length_squared() < 0.0001:
		to = Vector3.FORWARD
	shoot(to.normalized())
	cooldown_left = cooldown()


## One shot of the current hand along `direction`; the hands alternate.
## Returns the kills.
func shoot(direction: Vector3) -> int:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var origin := hero_at()
	var side := Vector3(-dir.z, 0.0, dir.x) * (MUZZLE_SIDE if hand == 0 else -MUZZLE_SIDE)
	var muzzle := origin + side + dir * 0.55 + Vector3.UP * MUZZLE_HEIGHT
	var hits := {}
	var count := bullets()
	var spread := EVO_SPREAD if evolved() else SPREAD
	var reach_now := reach()
	var through := pierce()
	var base := damage()
	var tint := EVO_COLOR if evolved() else COLOR
	for b in count:
		var angle := (float(b) - float(count - 1) * 0.5) * spread
		var ray := dir.rotated(Vector3.UP, angle) if angle != 0.0 else dir
		var travelled := 0.0
		var from := origin
		var end := origin + ray * reach_now
		for body in through + 1:
			var result: Dictionary = horde.raycast(from, ray, reach_now - travelled)
			var index: int = result.index
			var distance: float = travelled + float(result.distance)
			end = origin + ray * distance
			if index < 0:
				end = origin + ray * reach_now
				break
			if not hits.has(index):
				hits[index] = {"damage": 0.0, "dir": ray, "knock": knock_by_mass(index, KNOCK)}
			hits[index].damage += roll_damage(base)
			if _fx():
				effects.hit_sparks(end + Vector3.UP * 0.5, ray, 2)
			var p: Vector3 = horde.position_of(index)
			var along := Vector3(p.x - origin.x, 0.0, p.z - origin.z).dot(ray)
			travelled = along + float(horde.radius_of_kind(horde.kind_of(index))) + 0.1
			from = origin + ray * travelled
			if travelled >= reach_now:
				break
		if fx != null:
			fx.streak(muzzle, Vector3(end.x, 0.55, end.z), tint, 0.24 if evolved() else 0.2, 0.14)
		bullets_fired += 1
	if fx != null:
		fx.orb(muzzle + dir * 0.15, 0.22 if evolved() else 0.17, Color(1.0, 0.9, 0.5, 0.95), 0.07)
	last_hits = hits.duplicate(true)
	var killed := apply(hits)
	hand = 1 - hand
	shots += 1
	attacks += 1
	_sound("shot", 2.1 + 0.15 * float(hand))
	if not hits.is_empty():
		_sound("hit", 1.4)
	return killed


# Nearest and second nearest living enemy (boss included) within max_range:
# Vector2i(first, second), -1 when missing. No allocation (runs every shot).
func _two_nearest(max_range: float) -> Vector2i:
	var at := hero_at()
	var best := -1
	var second := -1
	var best_d := max_range * max_range
	var second_d := best_d
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var d := (p.x - at.x) * (p.x - at.x) + (p.z - at.z) * (p.z - at.z)
		if d < best_d:
			second = best
			second_d = best_d
			best = i
			best_d = d
		elif d < second_d:
			second = i
			second_d = d
	if horde.nearest_index(at, max_range) == BOSS_SLOT:
		second = best
		best = BOSS_SLOT
	return Vector2i(best, second)
