extends "res://scripts/weapons/weapon.gd"

# Granate (stage 3, Teil B §4): extra weapon for every hero.
#   Every COOLDOWN s (fire rate) the hero lobs a grenade onto the densest
#   enemy group within AIM_RANGE. It flies FLIGHT s on a high arc while a warm
#   yellow ring marks where it lands (not magenta: magenta means danger for
#   the hero), then explodes: damage to everything within RADIUS, knockback
#   outwards by mass, fireball, ring, dust, sparks, camera shake.
#   Rank 1 base, 2 more damage + faster, 3 radius +25 %, 4 more damage +
#   faster, 5 two grenades, 6 three. Damage x power_factor().

signal exploded(at: Vector3, hits: int, kills: int)

const FX := preload("res://scripts/weapons/weapon_fx.gd")

const COOLDOWN := 3.2
const AIM_RANGE := 9.0
const RADIUS := 2.6
const DAMAGE := 30.0
const KNOCK := [8.0, 4.0, 0.0]
const FLIGHT := 0.6
const APEX := 3.4
const MARK_COLOR := Color(1.0, 0.82, 0.3, 0.85)

var grenades: Array[Dictionary] = []
var throws := 0
var explosions := 0
var last_hits: Dictionary = {}
var fx: Node3D
var _root: Node3D
var _bombs: Array[Node3D] = []
var _marks: Array[MeshInstance3D] = []


func _init() -> void:
	super()
	id = "grenade"
	source = "Granate"


func _ready() -> void:
	fx = FX.new()
	fx.name = "GrenadeFx"
	add_child(fx)
	_root = Node3D.new()
	_root.name = "Grenades"
	add_child(_root)
	_root.top_level = true


func reset() -> void:
	super()
	grenades.clear()
	throws = 0
	explosions = 0
	last_hits = {}
	if fx != null:
		fx.clear()
	_draw()


func radius() -> float:
	return RADIUS * (1.25 if rank() >= 3 else 1.0)


func cooldown() -> float:
	return cooldown_time(COOLDOWN - (0.3 if rank() >= 2 else 0.0) - (0.3 if rank() >= 4 else 0.0))


func damage() -> float:
	return DAMAGE * power_factor()


func count() -> int:
	return 3 if rank() >= 6 else (2 if rank() >= 5 else 1)


func step(delta: float) -> void:
	if fx != null:
		fx.step(delta)
	_fly(delta)
	if not can_act():
		_draw()
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if cooldown_left <= 0.0:
		var spots := best_spots(count())
		if not spots.is_empty():
			for spot in spots:
				throw_at(spot)
			cooldown_left = cooldown()
			throws += 1
			attacks += 1
	_draw()


## Up to `wanted` landing points: enemies (within AIM_RANGE) with the most
## neighbours inside the blast; a second point keeps clear of the first blast.
func best_spots(wanted: int) -> Array[Vector3]:
	var at := hero_at()
	var reach := AIM_RANGE * range_mult()
	var r := radius()
	var candidates: Array[int] = []
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		if Vector2(p.x - at.x, p.z - at.z).length() <= reach:
			candidates.append(i)
	var out: Array[Vector3] = []
	if candidates.is_empty():
		var boss_index: int = horde.nearest_index(at, reach)
		if boss_index == BOSS_SLOT:
			out.append(horde.position_of(BOSS_SLOT))
		return out
	var scores := {}
	for i in candidates:
		var p: Vector3 = horde.position_of(i)
		var score := 0.0
		for j in candidates:
			var q: Vector3 = horde.position_of(j)
			if Vector2(p.x - q.x, p.z - q.z).length_squared() <= r * r * 0.8:
				score += 1.0
		# Prefer groups a bit away from the hero (no blast in the face).
		score -= 0.05 * absf(Vector2(p.x - at.x, p.z - at.z).length() - 5.0)
		scores[i] = score
	for k in wanted:
		var best := -1
		var best_score := -INF
		for i in candidates:
			var p: Vector3 = horde.position_of(i)
			var clear := true
			for taken in out:
				if Vector2(p.x - taken.x, p.z - taken.z).length() < r * 1.4:
					clear = false
			if clear and float(scores[i]) > best_score:
				best_score = float(scores[i])
				best = i
		if best < 0:
			break
		out.append(horde.position_of(best))
	return out


func throw_at(point: Vector3) -> void:
	var from := hero_at() + Vector3.UP * 1.4
	grenades.append({"from": from, "to": Vector3(point.x, 0.0, point.z), "age": 0.0, "spin": 0.0})
	_sound("dash", 0.9)


func _fly(delta: float) -> void:
	for index in range(grenades.size() - 1, -1, -1):
		var g: Dictionary = grenades[index]
		g.age += delta
		g.spin += delta * 14.0
		if float(g.age) >= FLIGHT:
			grenades.remove_at(index)
			explode(g.to)


## Explosion at `at`: returns the kills.
func explode(at: Vector3) -> int:
	var r := radius()
	var hits := {}
	if horde != null:
		for index in enemies_in_circle(at, r):
			var p: Vector3 = horde.position_of(index)
			var out := Vector3(p.x - at.x, 0.0, p.z - at.z)
			var d := out.length()
			out = out / d if d > 0.0001 else Vector3.FORWARD
			# Full damage in the core, 60 % at the rim.
			var falloff := lerpf(1.0, 0.6, clampf(d / r, 0.0, 1.0))
			hits[index] = {"damage": roll_damage(damage() * falloff), "dir": out, "knock": knock_by_mass(index, KNOCK)}
	last_hits = hits.duplicate(true)
	explosions += 1
	var killed := apply(hits) if horde != null else 0
	if fx != null:
		fx.fireball(at, r * 0.95, 0.34)
	if _fx():
		effects.ring(at, Color(1.0, 1.0, 0.85, 0.95), 0.3, r * 1.1, 0.2)
		effects.ring(at, Color(1.0, 0.5, 0.12, 0.95), 0.4, r, 0.4)
		effects.dust(at, 10, 1.3, Color(0.3, 0.26, 0.24, 0.75))
		effects.muzzle_flash(at + Vector3.UP * 0.4, Vector3.FORWARD)
		effects.hit_sparks(at + Vector3.UP * 0.5, Vector3.FORWARD, 6)
		effects.hit_sparks(at + Vector3.UP * 0.5, Vector3.BACK, 6)
		effects.splat(at, Color(0.12, 0.1, 0.09, 0.55), r * 0.7)
	_shake(0.22)
	_sound("shot", 0.62)
	_sound("slam", 0.9)
	exploded.emit(at, hits.size(), killed)
	return killed


func _draw() -> void:
	if _root == null or not _root.is_inside_tree():
		return
	while _bombs.size() < grenades.size():
		_bombs.append(_make_bomb())
		var mark := ground_ring(_root, MARK_COLOR)
		mark.top_level = true
		_marks.append(mark)
	for index in _bombs.size():
		var bomb := _bombs[index]
		var mark := _marks[index]
		if index >= grenades.size():
			bomb.visible = false
			mark.visible = false
			continue
		var g: Dictionary = grenades[index]
		var u: float = clampf(float(g.age) / FLIGHT, 0.0, 1.0)
		var from: Vector3 = g.from
		var to: Vector3 = g.to
		var pos := from.lerp(to, u)
		pos.y = lerpf(from.y, 0.25, u) + APEX * 4.0 * u * (1.0 - u)
		bomb.visible = true
		bomb.global_transform = Transform3D(Basis(Vector3(1, 0, 1).normalized(), float(g.spin)).scaled(Vector3.ONE * 1.6), pos)
		mark.visible = true
		var pulse := 1.0 + 0.06 * sin(float(g.age) * 30.0)
		var size := radius() * lerpf(1.15, 1.0, u) * pulse
		mark.global_transform = Transform3D(Basis.from_scale(Vector3(size, 0.25, size)), Vector3(to.x, 0.08, to.z))


func _make_bomb() -> Node3D:
	var node := Node3D.new()
	node.name = "Grenade"
	_root.add_child(node)
	node.top_level = true

	part(node, ball(0.26), Color("3f5a2c"), Transform3D.IDENTITY)
	part(node, box(Vector3(0.14, 0.14, 0.14)), Color("9aa3ad"), Transform3D(Basis.IDENTITY, Vector3(0, 0.26, 0)))
	part(node, ball(0.07), Color("ffd24a"), Transform3D(Basis.IDENTITY, Vector3(0.04, 0.38, 0)))
	return node
