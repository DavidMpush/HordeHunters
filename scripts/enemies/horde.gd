extends Node3D

# Melee enemies of stage 1 (Wichtel, Renner, Brocken) as pure data in packed
# arrays, drawn with one MultiMesh per kind (crowd technique of Mawlings
# horde.gd). Behaviour per enemy:
#   APPROACH -> (hero within ENGAGE_SHARE of the reach) WINDUP: stop, lean back,
#   glow magenta (Brocken: magenta arc on the ground) -> at the end STRIKE: hits
#   only if the hero is still within reach (and inside the arc) -> RECOVER.
# Separation keeps them apart (spatial grid around the hero), far enemies follow
# the arena flow field. Shotgun hits come in through apply_hits(): damage,
# knockback by mass, a light enemy hit during its wind-up staggers. Killed
# enemies are flung as corpses (same MultiMesh) and leave a splat.
#
# Reach is measured from the enemy centre to the hero's body edge.
#
# Stage 2 (Teil B, Druck):
#   - champion Brocken (elite flag): bigger, gold shimmer, more health, a
#     telegraphed stomp ring instead of the forward swing; elite_killed on death
#   - encircle ring: members flagged `_ring` walk to their slot on a shrinking
#     ring (ring_center / ring_radius, driven by pressure.gd) until it dissolves
#   - boss slot: an external big target (boss_king.gd) joins the shotgun queries
#     (nearest_index, raycast, position_of, apply_hits) under BOSS_SLOT; it takes
#     damage but never knockback.

signal enemy_killed(kind: int, at: Vector3)
signal enemy_damaged(at: Vector3, amount: float, kind: int, killed: bool)
signal windup_started(kind: int, at: Vector3)
## Every strike, hit or not (at = strike point).
signal swing_landed(kind: int, at: Vector3, hit: bool)
## A champion Brocken died (after enemy_killed).
signal elite_killed(at: Vector3)

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const ENEMY_SHADER := preload("res://shaders/enemy.gdshader")
const ARC_SHADER := preload("res://shaders/telegraph_arc.gdshader")
## Index the boss answers to in the shotgun queries (never a living slot).
const BOSS_SLOT := T.ENEMY_CAP + 1

enum State { APPROACH, WINDUP, STRIKE, RECOVER, STAGGER }

const CAP := T.ENEMY_CAP
const KINDS := 3
const CORPSE_CAP := 60
const CORPSE_LIFE := 0.8
const STRIKE_SECONDS := 0.16
const APPEAR_SECONDS := 0.3
const STEER := 10.0
const TURN := 14.0
const SEPARATION_SPEED := 5.0
const SEPARATION_BUDGET := 12
const FLOW_NEAR := 8.0
const FLOW_REFRESH := 6
const FLASH_DECAY := 7.0
const GAIT_RATE := 13.0
const CELL := 1.0
const GRID := 80
const STRIDE := 20           # 12 transform + 4 colour + 4 custom
const NEAR_CHECK := 10       # frames between wall-proximity probes per enemy
const NEAR_MARGIN := 1.2     # > NEAR_CHECK frames of the fastest motion (5.5 m/s + knock)

# Models (Mawlings creatures as placeholders), fitted to `length` metres along
# the head axis; `yaw` turns the fitted mesh so the head points along +Z.
const MODELS := {
	T.Kind.WICHTEL: {"path": "res://assets/enemies/Moorbrut_game.glb", "length": 1.25, "yaw": 0.0,
		"tint": Color(0.3, 0.42, 0.95, 0.7), "rim": Color("ffe36b"), "bright": 1.35},
	T.Kind.RENNER: {"path": "res://assets/enemies/Skitter_game.glb", "length": 1.5, "yaw": PI * 0.5,
		"tint": Color(1.0, 0.25, 0.18, 0.8), "rim": Color("ffe0a0"), "bright": 1.45},
	T.Kind.BROCKEN: {"path": "res://assets/enemies/HunterBeetle_game.glb", "length": 2.7, "yaw": 0.0,
		"tint": Color(0.5, 0.52, 0.58, 0.85), "rim": Color("fff1c8"), "bright": 1.3},
}
const SPLAT := {T.Kind.WICHTEL: Color(0.2, 0.25, 0.6, 0.75), T.Kind.RENNER: Color(0.62, 0.12, 0.1, 0.75),
	T.Kind.BROCKEN: Color(0.3, 0.3, 0.34, 0.8)}

var arena: Node3D
var hero: Node3D
var effects: Node3D

# Living enemies: indices 0.._n-1 (removal swaps with the last).
var _n := 0
var _kind := PackedInt32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _knock := PackedVector3Array()
var _push := PackedVector3Array()
var _flow := PackedVector3Array()
var _dir := PackedVector3Array()
var _hp := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _gait := PackedFloat32Array()
var _walk := PackedFloat32Array()
var _flash := PackedFloat32Array()
var _appear := PackedFloat32Array()
var _near := PackedByteArray()
var _elite := PackedByteArray()
var _hp_max := PackedFloat32Array()
var _ring := PackedByteArray()
var _ring_angle := PackedFloat32Array()
var _next := PackedInt32Array()
var _head := PackedInt32Array()
var _anchor := Vector3.ZERO
var _frame := 0

# Per-kind constants (arrays indexed by kind).
var _radius := PackedFloat32Array()
var _reach := PackedFloat32Array()
var _engage := PackedFloat32Array()
var _windup := PackedFloat32Array()
var _recover := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _arc_cos := PackedFloat32Array()
var _mass := PackedInt32Array()
var _max_hp := PackedFloat32Array()
var _lead := PackedFloat32Array()

# Corpses: {kind, pos, vel, yaw, axis, spin, angle, age, landed}
var corpses: Array[Dictionary] = []

# Statistics (tests, result screen)
var total_kills := 0
var kills_by_kind := PackedInt32Array([0, 0, 0])
var strikes := 0
var strikes_hit := 0
var usec_step := 0
var usec_draw := 0
## Bench switch: no wall collision (measures its cost).
var walls_enabled := true

# Encircle ring (pressure.gd drives centre and radius; members keep formation
# while ring_active, then chase normally).
var ring_active := false
var ring_center := Vector3.ZERO
var ring_radius := 0.0
## Gap direction (rad, xz: cos, sin) and width (m, kept while closing).
var ring_gap := 0.0
var ring_gap_width := 4.0
## External boss target (boss_king.gd) or null.
var boss: Node3D
var _elite_arcs: Array[MeshInstance3D] = []

# Drawing
var _built := false
var _bodies: Array[MultiMeshInstance3D] = []
var _buffers: Array[PackedFloat32Array] = []
var _base: Array[Transform3D] = []
var _shadows: MultiMeshInstance3D
var _shadow_buffer := PackedFloat32Array()
var _arcs: Array[MeshInstance3D] = []


func _init() -> void:
	_allocate()


func setup(arena_node: Node3D, hero_node: Node3D, effects_node: Node3D) -> void:
	arena = arena_node
	hero = hero_node
	effects = effects_node
	_build()


func count() -> int:
	return _n


func count_kind(kind: int) -> int:
	var total := 0
	for i in _n:
		if _kind[i] == kind:
			total += 1
	return total


func position_of(i: int) -> Vector3:
	if i == BOSS_SLOT:
		return _boss_position()
	return _pos[i]


func is_elite(i: int) -> bool:
	return _elite[i] == 1


func max_health_of(i: int) -> float:
	return _hp_max[i]


func speed_of(i: int) -> float:
	return _speed[i]


func in_ring(i: int) -> bool:
	return _ring[i] == 1


func count_elite() -> int:
	var total := 0
	for i in _n:
		total += _elite[i]
	return total


func count_ring() -> int:
	var total := 0
	for i in _n:
		total += _ring[i]
	return total


## Ring members leave the formation (they chase normally from now on).
func release_ring() -> void:
	ring_active = false
	for i in _n:
		_ring[i] = 0


func kind_of(i: int) -> int:
	# The boss counts as heavy (Brocken): no knockback, big body.
	if i == BOSS_SLOT:
		return T.Kind.BROCKEN
	return _kind[i]


func state_of(i: int) -> int:
	return _state[i]


func health_of(i: int) -> float:
	return _hp[i]


func knock_of(i: int) -> Vector3:
	return _knock[i]


func radius_of_kind(kind: int) -> float:
	return _radius[kind]


func reach_of_kind(kind: int) -> float:
	return _reach[kind]


func positions() -> PackedVector3Array:
	return _pos.slice(0, _n)


## elite: champion Brocken (only for the Brocken kind). hp_mult / speed_mult
## scale this one enemy (Endwelle).
func spawn(kind: int, at: Vector3, elite := false, hp_mult := 1.0, speed_mult := 1.0) -> int:
	if _n >= CAP:
		return -1
	var i := _n
	_n += 1
	var stats: Dictionary = T.enemy(kind)
	elite = elite and kind == T.Kind.BROCKEN
	_kind[i] = kind
	_elite[i] = 1 if elite else 0
	_ring[i] = 0
	_ring_angle[i] = 0.0
	_pos[i] = Vector3(at.x, 0.0, at.z)
	_vel[i] = Vector3.ZERO
	_knock[i] = Vector3.ZERO
	_push[i] = Vector3.ZERO
	_flow[i] = Vector3.ZERO
	_dir[i] = Vector3.FORWARD
	_hp[i] = float(stats.hp) * hp_mult * (PT.ELITE_HP_MULT if elite else 1.0)
	_hp_max[i] = _hp[i]
	# A little speed variety so packs string out instead of marching in step.
	var base_speed: float = PT.ELITE_SPEED if elite else float(stats.speed)
	_speed[i] = base_speed * speed_mult * (0.92 + 0.16 * fposmod(float(total_kills + i) * 0.618034 + float(_frame) * 0.1, 1.0))
	_state[i] = State.APPROACH
	_timer[i] = 0.0
	var to_hero := _hero_position() - at
	_yaw[i] = atan2(to_hero.x, to_hero.z)
	_gait[i] = fposmod(float(i) * 1.3247, 1.0) * TAU
	_walk[i] = 0.0
	_flash[i] = 0.0
	_appear[i] = 0.0
	_near[i] = 1
	return i


## Ring member at slot `share` (0..1 from one gap edge round to the other) of
## the active ring.
func spawn_ring_member(kind: int, share: float, hp_mult := 1.0) -> int:
	var g := minf(PI, ring_gap_width / maxf(0.5, ring_radius))
	var angle := ring_gap + g * 0.5 + (TAU - g) * share
	var at := ring_center + Vector3(cos(angle), 0.0, sin(angle)) * ring_radius
	if arena != null and is_instance_valid(arena) and arena.has_method("safe_spawn"):
		at = arena.safe_spawn(at, radius_of_kind(kind) + 0.1)
	if not at.is_finite():
		return -1
	var i := spawn(kind, at, false, hp_mult)
	if i >= 0:
		_ring[i] = 1
		_ring_angle[i] = share
	return i


func relocate(i: int, at: Vector3) -> void:
	_pos[i] = Vector3(at.x, 0.0, at.z)
	_vel[i] = Vector3.ZERO
	_knock[i] = Vector3.ZERO
	_state[i] = State.APPROACH
	_appear[i] = 0.0
	_near[i] = 1
	_ring[i] = 0


func clear() -> void:
	_n = 0
	ring_active = false
	corpses.clear()
	total_kills = 0
	kills_by_kind = PackedInt32Array([0, 0, 0])
	strikes = 0
	strikes_hit = 0
	_draw()


## Nearest living enemy within max_range of point (xz), -1 if none.
func nearest_index(point: Vector3, max_range: float) -> int:
	var best := -1
	var best_d2 := max_range * max_range
	for i in _n:
		var p := _pos[i]
		var dx := p.x - point.x
		var dz := p.z - point.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = i
	if _boss_targetable():
		# The boss counts from its body edge (a big body is "near" sooner).
		var b := _boss_position()
		var reach := sqrt(pow(b.x - point.x, 2.0) + pow(b.z - point.z, 2.0)) - _boss_radius()
		if reach < max_range and maxf(0.0, reach) * maxf(0.0, reach) < best_d2:
			best = BOSS_SLOT
	return best


func _boss_targetable() -> bool:
	return boss != null and is_instance_valid(boss) and boss.has_method("is_targetable") and boss.is_targetable()


func _boss_position() -> Vector3:
	if boss == null or not is_instance_valid(boss):
		return Vector3.INF
	return Vector3(boss.position.x, 0.0, boss.position.z)


func _boss_radius() -> float:
	return float(boss.get("body_radius")) if boss != null and is_instance_valid(boss) else 0.0


## First enemy body a ray (xz) touches within max_distance:
## {"index": i or -1, "distance": metres along the ray}.
func raycast(from: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var best := -1
	var best_t := max_distance
	for i in _n:
		var r := _radius[_kind[i]] * (PT.ELITE_SCALE if _elite[i] == 1 else 1.0) + 0.08
		var p := _pos[i]
		var rx := p.x - from.x
		var rz := p.z - from.z
		var along := rx * dir.x + rz * dir.z
		if along < -r or along - r > best_t:
			continue
		var perp2 := rx * rx + rz * rz - along * along
		if perp2 > r * r:
			continue
		var t := maxf(0.0, along - sqrt(r * r - perp2))
		if t < best_t:
			best_t = t
			best = i
	if _boss_targetable():
		var r := _boss_radius()
		var b := _boss_position()
		var rx := b.x - from.x
		var rz := b.z - from.z
		var along := rx * dir.x + rz * dir.z
		var perp2 := rx * rx + rz * rz - along * along
		if along >= -r and along - r <= best_t and perp2 <= r * r:
			var t := maxf(0.0, along - sqrt(r * r - perp2))
			if t < best_t:
				best_t = t
				best = BOSS_SLOT
	return {"index": best, "distance": best_t}


## Applies gathered hits {index: {"damage", "dir", "knock"}}; returns kills.
## Processed from the highest index down, so swap-removal never moves an
## index that is still waiting.
func apply_hits(hits: Dictionary) -> int:
	var keys: Array = hits.keys()
	keys.sort()
	keys.reverse()
	var kills := 0
	for key in keys:
		var i := int(key)
		if i == BOSS_SLOT:
			if hurt_boss(float(hits[key].damage)):
				kills += 1
			continue
		if i < 0 or i >= _n:
			continue
		var hit: Dictionary = hits[key]
		if hurt(i, float(hit.damage), hit.dir, float(hit.get("knock", -1.0))):
			kills += 1
	return kills


## Damage + knockback on one enemy. knock < 0 = by mass. Returns true on kill.
func hurt(i: int, amount: float, direction: Vector3, knock := -1.0) -> bool:
	var kind := _kind[i]
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var speed := T.knock_for(_mass[kind]) if knock < 0.0 else knock
	if speed > 0.0 and dir != Vector3.ZERO:
		var current := _knock[i]
		var along := current.dot(dir)
		if along < speed:
			_knock[i] = current + dir * (speed - along)
	_hp[i] -= amount
	_flash[i] = 1.0
	if _state[i] == State.WINDUP and _mass[kind] != T.Mass.HEAVY:
		_state[i] = State.STAGGER
		_timer[i] = T.STAGGER_SECONDS
	var killed := _hp[i] <= 0.0
	enemy_damaged.emit(_pos[i], amount, kind, killed)
	if killed:
		_kill(i, dir, speed)
	return killed


## Damage on the boss: no knockback ever (bosses are immune). True on the kill.
func hurt_boss(amount: float) -> bool:
	if not _boss_targetable():
		return false
	var killed := bool(boss.take_damage(amount))
	enemy_damaged.emit(_boss_position(), amount, T.Kind.BROCKEN, killed)
	return killed


func _kill(i: int, dir: Vector3, knock: float) -> void:
	var kind := _kind[i]
	var at := _pos[i]
	var was_elite := _elite[i] == 1
	total_kills += 1
	kills_by_kind[kind] += 1
	# Fling: light bodies fly along the shot, the Brocken topples where it stands.
	var fling := Vector3.ZERO
	var up := 0.0
	match _mass[kind]:
		T.Mass.LIGHT:
			fling = dir * (5.5 + knock * 0.8)
			up = 5.0
		T.Mass.MEDIUM:
			fling = dir * 3.5
			up = 3.5
		_:
			fling = dir * 0.8
			up = 1.6
	var axis := Vector3(dir.z, 0.0, -dir.x) if dir != Vector3.ZERO else Vector3.RIGHT
	if corpses.size() >= CORPSE_CAP:
		corpses.pop_front()
	corpses.append({"kind": kind, "pos": at, "vel": fling + Vector3.UP * up, "yaw": _yaw[i], "axis": axis,
		"spin": 9.0 if _mass[kind] == T.Mass.LIGHT else 3.0, "angle": 0.0, "age": 0.0, "landed": false,
		"scale": PT.ELITE_SCALE if was_elite else 1.0})
	var last := _n - 1
	if i != last:
		_kind[i] = _kind[last]
		_elite[i] = _elite[last]
		_hp_max[i] = _hp_max[last]
		_ring[i] = _ring[last]
		_ring_angle[i] = _ring_angle[last]
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_knock[i] = _knock[last]
		_push[i] = _push[last]
		_flow[i] = _flow[last]
		_dir[i] = _dir[last]
		_hp[i] = _hp[last]
		_speed[i] = _speed[last]
		_state[i] = _state[last]
		_timer[i] = _timer[last]
		_yaw[i] = _yaw[last]
		_gait[i] = _gait[last]
		_walk[i] = _walk[last]
		_flash[i] = _flash[last]
		_appear[i] = _appear[last]
		_near[i] = _near[last]
	_n = last
	# Signals after the swap: listeners may spawn (drops) without breaking the arrays.
	enemy_killed.emit(kind, at)
	if was_elite:
		elite_killed.emit(at)


# ---------------------------------------------------------------- update

func step(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_build()
	_frame += 1
	var hero_at := _hero_position()
	var hero_r := T.HERO_RADIUS
	var hero_vel := Vector3.ZERO
	if hero != null and is_instance_valid(hero) and hero.get("velocity") is Vector3:
		hero_vel = hero.velocity
	_index(hero_at)
	var steer := 1.0 - exp(-STEER * delta)
	var turn := 1.0 - exp(-TURN * delta)
	var friction := exp(-T.KNOCK_FRICTION * delta)
	var walls := walls_enabled and arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion")
	var guided := arena != null and is_instance_valid(arena) and arena.has_method("flow_direction")
	var pos := _pos
	var vel := _vel
	var knocks := _knock
	var pushes := _push
	var kinds := _kind
	var states := _state
	var timers := _timer
	var yaws := _yaw
	var dirs := _dir
	var head := _head
	var nexts := _next
	var radius := _radius
	var ax := _anchor.x
	var az := _anchor.z
	for i in _n:
		var k := kinds[i]
		var p := pos[i]
		var r := radius[k]
		var tx := hero_at.x - p.x
		var tz := hero_at.z - p.z
		var d := sqrt(tx * tx + tz * tz)
		var nx := tx / d if d > 0.0001 else 0.0
		var nz := tz / d if d > 0.0001 else 1.0
		var speed := _speed[i]
		var want := Vector3.ZERO
		var state := states[i]
		var shown := _appear[i]
		var elite := _elite[i] == 1
		var reach := PT.ELITE_REACH if elite else _reach[k]
		match state:
			State.APPROACH:
				want = Vector3(nx * speed, 0.0, nz * speed)
				# Cut the runner off: aim where the hero will be (not when close).
				var lead := _lead[k]
				if lead > 0.0 and d > 2.5 and hero_vel != Vector3.ZERO:
					var aim := Vector3(tx + hero_vel.x * lead * minf(1.0, d / 8.0), 0.0, tz + hero_vel.z * lead * minf(1.0, d / 8.0))
					if aim.length_squared() > 0.0001:
						want = aim.normalized() * speed
				if _ring[i] == 1 and ring_active:
					# Formation: walk to the own slot on the shrinking ring; the
					# slots squeeze together so the gap keeps its width in metres.
					var g := minf(PI, ring_gap_width / maxf(0.5, ring_radius))
					var a := ring_gap + g * 0.5 + (TAU - g) * _ring_angle[i]
					var sx := ring_center.x + cos(a) * ring_radius - p.x
					var sz := ring_center.z + sin(a) * ring_radius - p.z
					var sd := sqrt(sx * sx + sz * sz)
					want = Vector3(sx, 0.0, sz) / sd * minf(speed, sd * 4.0) if sd > 0.05 else Vector3.ZERO
				elif guided and d > FLOW_NEAR:
					var flow := _flow[i]
					if (i + _frame) % FLOW_REFRESH == 0 or flow == Vector3.ZERO:
						flow = arena.flow_direction(p, r)
						_flow[i] = flow
					if flow != Vector3.ZERO:
						want = flow * speed
				if shown >= 1.0 and d <= reach * T.ENGAGE_SHARE + hero_r and _hero_alive():
					states[i] = State.WINDUP
					timers[i] = PT.ELITE_WINDUP if elite else _windup[k]
					# Plant the feet: the wind-up is a clear stop, no sliding in.
					vel[i] = Vector3.ZERO
					dirs[i] = Vector3(nx, 0.0, nz)
					windup_started.emit(k, p)
			State.WINDUP:
				timers[i] -= delta
				if timers[i] <= 0.0:
					var dir := dirs[i]
					var in_reach := d <= reach + hero_r
					# The champion stomps all around; the others swing forward.
					if in_reach and not elite and _arc_cos[k] > -1.0 and d > 0.0001:
						in_reach = dir.x * nx + dir.z * nz >= _arc_cos[k]
					var landed := false
					strikes += 1
					if in_reach and _hero_alive() and hero.has_method("take_hit"):
						landed = bool(hero.take_hit(PT.ELITE_DAMAGE if elite else _damage[k], p))
					if landed:
						strikes_hit += 1
					swing_landed.emit(k, p if elite else p + dir * minf(d, _reach[k]), landed)
					states[i] = State.STRIKE
					timers[i] = STRIKE_SECONDS
			State.STRIKE:
				timers[i] -= delta
				if timers[i] <= 0.0:
					states[i] = State.RECOVER
					timers[i] = PT.ELITE_RECOVER if elite else _recover[k]
			State.RECOVER:
				# Shuffle closer slowly while recovering (no free hits, no full stop).
				want = Vector3(nx * speed * 0.25, 0.0, nz * speed * 0.25)
				timers[i] -= delta
				if timers[i] <= 0.0:
					states[i] = State.APPROACH
			State.STAGGER:
				timers[i] -= delta
				if timers[i] <= 0.0:
					states[i] = State.APPROACH
		# Separation (every second frame per enemy; the push holds in between).
		if ((i + _frame) & 1) == 0:
			var px := 0.0
			var pz := 0.0
			var gx := int((p.x - ax) / CELL)
			var gz := int((p.z - az) / CELL)
			if p.x >= ax and p.z >= az and gx < GRID and gz < GRID:
				var span := 1 if r < 0.6 else 2
				var budget := SEPARATION_BUDGET
				for cz in range(maxi(0, gz - span), mini(GRID, gz + span + 1)):
					var row := cz * GRID
					for cx in range(maxi(0, gx - span), mini(GRID, gx + span + 1)):
						var j := head[row + cx]
						while j >= 0 and budget > 0:
							if j != i:
								var q := pos[j]
								var dx := p.x - q.x
								var dz := p.z - q.z
								var rj := radius[kinds[j]]
								var least := r + rj
								var d2 := dx * dx + dz * dz
								if d2 < least * least:
									budget -= 1
									# Heavier bodies yield less.
									var share := rj / (r + rj) * 2.0
									if d2 > 0.000001:
										var dd := sqrt(d2)
										var w := (least - dd) / (least * dd) * share
										px += dx * w
										pz += dz * w
									else:
										var a := float(i) * 2.39996
										px += cos(a) * share
										pz += sin(a) * share
							j = nexts[j]
			# Capped: a dense clump spreads at walking pace instead of exploding.
			pushes[i] = (Vector3(px, 0.0, pz) * SEPARATION_SPEED).limit_length(speed * 0.9 + 1.2)
		var v := vel[i]
		v.x += (want.x - v.x) * steer
		v.z += (want.z - v.z) * steer
		vel[i] = v
		var kn := knocks[i]
		var push := pushes[i]
		var motion := (v + push + kn) * delta
		knocks[i] = kn * friction if kn.length_squared() > 0.0004 else Vector3.ZERO
		var next := Vector3(p.x + motion.x, 0.0, p.z + motion.z)
		if walls:
			# Collision is costly on the real map: every NEAR_CHECK frames a fat
			# probe (body + NEAR_MARGIN) tells whether anything solid is close;
			# only then the full resolve runs every frame.
			if (i + _frame) % NEAR_CHECK == 0:
				var probe: Vector3 = arena.resolve_motion(p, Vector3.ZERO, r + NEAR_MARGIN)
				_near[i] = 1 if (probe.x - p.x) * (probe.x - p.x) + (probe.z - p.z) * (probe.z - p.z) > 0.000001 else 0
			if _near[i] == 1 and motion.length_squared() > 0.0:
				next = arena.resolve_motion(p, motion, r)
		# Never inside the hero's body.
		var hx := next.x - hero_at.x
		var hz := next.z - hero_at.z
		var least_h := r + hero_r * 0.9
		var dh2 := hx * hx + hz * hz
		if dh2 < least_h * least_h and _hero_alive():
			var dh := sqrt(dh2)
			if dh > 0.0001:
				next.x = hero_at.x + hx / dh * least_h
				next.z = hero_at.z + hz / dh * least_h
		pos[i] = next
		# Facing: the locked attack direction while striking, else the movement.
		if state == State.WINDUP or state == State.STRIKE:
			var lock := dirs[i]
			yaws[i] = lerp_angle(yaws[i], atan2(lock.x, lock.z), turn * 1.6)
		else:
			var mx := next.x - p.x
			var mz := next.z - p.z
			if mx * mx + mz * mz > 0.000025 and kn.length_squared() < 1.0:
				yaws[i] = lerp_angle(yaws[i], atan2(mx, mz), turn)
			elif state == State.RECOVER:
				yaws[i] = lerp_angle(yaws[i], atan2(nx, nz), turn * 0.5)
		var real := Vector2(next.x - p.x, next.z - p.z).length() / maxf(delta, 0.0001)
		var walk := _walk[i]
		walk += (clampf(real / maxf(speed, 0.1), 0.0, 1.0) - walk) * steer
		_walk[i] = walk
		_gait[i] = fposmod(_gait[i] + delta * GAIT_RATE * walk * (speed / 3.2), TAU * 8.0)
		if shown < 1.0:
			_appear[i] = minf(1.0, shown + delta / APPEAR_SECONDS)
		var flash := _flash[i]
		if flash > 0.0:
			_flash[i] = maxf(0.0, flash - FLASH_DECAY * delta)
	_pos = pos
	_vel = vel
	_knock = knocks
	_push = pushes
	_state = states
	_timer = timers
	_yaw = yaws
	_dir = dirs
	_step_corpses(delta)
	var t1 := Time.get_ticks_usec()
	_draw()
	usec_draw += Time.get_ticks_usec() - t1
	usec_step += Time.get_ticks_usec() - t0


func _hero_position() -> Vector3:
	if hero != null and is_instance_valid(hero):
		var at := hero.global_position if hero.is_inside_tree() else hero.position
		return Vector3(at.x, 0.0, at.z)
	return Vector3.ZERO


func _hero_alive() -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	return not (hero.has_method("is_dead") and hero.is_dead())


func _index(center: Vector3) -> void:
	var half := float(GRID) * CELL * 0.5
	_anchor = Vector3(floor(center.x / CELL) * CELL - half, 0.0, floor(center.z / CELL) * CELL - half)
	_head.fill(-1)
	for i in _n:
		var p := _pos[i]
		if p.x < _anchor.x or p.z < _anchor.z:
			_next[i] = -1
			continue
		var gx := int((p.x - _anchor.x) / CELL)
		var gz := int((p.z - _anchor.z) / CELL)
		if gx >= GRID or gz >= GRID:
			_next[i] = -1
			continue
		var cell := gz * GRID + gx
		_next[i] = _head[cell]
		_head[cell] = i


func _step_corpses(delta: float) -> void:
	for index in range(corpses.size() - 1, -1, -1):
		var c: Dictionary = corpses[index]
		c.age += delta
		var vel: Vector3 = c.vel
		var at: Vector3 = c.pos
		if not c.landed:
			vel.y -= 24.0 * delta
			at += vel * delta
			c.angle += float(c.spin) * delta
			if at.y <= 0.0 and vel.y < 0.0:
				at.y = 0.0
				c.landed = true
				vel = Vector3(vel.x * 0.25, 0.0, vel.z * 0.25)
				if effects != null and is_instance_valid(effects):
					effects.dust(at, 2, 0.4)
		else:
			at += vel * delta
			vel *= exp(-6.0 * delta)
		if (index + _frame) % 3 == 0 and arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
			var flat: Vector3 = arena.resolve_motion(Vector3(c.pos.x, 0.0, c.pos.z), Vector3(at.x - c.pos.x, 0.0, at.z - c.pos.z), 0.2)
			at = Vector3(flat.x, at.y, flat.z)
		c.vel = vel
		c.pos = at
		if c.age >= CORPSE_LIFE:
			if effects != null and is_instance_valid(effects):
				effects.splat(Vector3(at.x, 0.0, at.z), SPLAT[int(c.kind)], _radius[int(c.kind)] * 2.6)
				effects.dust(Vector3(at.x, 0.0, at.z), 3, 0.55, Color(SPLAT[int(c.kind)], 0.45))
			corpses.remove_at(index)


# ---------------------------------------------------------------- drawing

func _allocate() -> void:
	_kind.resize(CAP)
	_state.resize(CAP)
	_next.resize(CAP)
	_pos.resize(CAP)
	_vel.resize(CAP)
	_knock.resize(CAP)
	_push.resize(CAP)
	_flow.resize(CAP)
	_dir.resize(CAP)
	_hp.resize(CAP)
	_speed.resize(CAP)
	_timer.resize(CAP)
	_yaw.resize(CAP)
	_gait.resize(CAP)
	_walk.resize(CAP)
	_flash.resize(CAP)
	_appear.resize(CAP)
	_near.resize(CAP)
	_elite.resize(CAP)
	_hp_max.resize(CAP)
	_ring.resize(CAP)
	_ring_angle.resize(CAP)
	_head.resize(GRID * GRID)
	_radius.resize(KINDS)
	_reach.resize(KINDS)
	_engage.resize(KINDS)
	_windup.resize(KINDS)
	_recover.resize(KINDS)
	_damage.resize(KINDS)
	_arc_cos.resize(KINDS)
	_mass.resize(KINDS)
	_max_hp.resize(KINDS)
	_lead.resize(KINDS)
	for kind in KINDS:
		var stats: Dictionary = T.enemy(kind)
		_radius[kind] = float(stats.radius)
		_reach[kind] = float(stats.reach)
		_engage[kind] = float(stats.reach) * T.ENGAGE_SHARE
		_windup[kind] = float(stats.windup)
		_recover[kind] = float(stats.recover)
		_damage[kind] = float(stats.damage)
		_arc_cos[kind] = cos(deg_to_rad(float(stats.arc))) if float(stats.arc) > 0.0 else -2.0
		_mass[kind] = int(stats.mass)
		_max_hp[kind] = float(stats.hp)
		_lead[kind] = float(stats.get("lead", 0.0))


func _build() -> void:
	if _built:
		return
	_built = true
	for kind in KINDS:
		var info: Dictionary = MODELS[kind]
		var fitted := _fit_model(String(info.path), float(info.length), float(info.yaw))
		var mesh: Mesh = fitted[0]
		_base.append(fitted[1])
		var material := ShaderMaterial.new()
		material.shader = ENEMY_SHADER
		material.set_shader_parameter("brightness", float(info.bright))
		material.set_shader_parameter("saturation", 1.25)
		material.set_shader_parameter("shape_light", 0.38)
		material.set_shader_parameter("body_tint", info.tint)
		material.set_shader_parameter("rim_color", info.rim)
		material.set_shader_parameter("rim_strength", 0.7)
		material.set_shader_parameter("rim_power", 2.6)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = CAP + CORPSE_CAP
		multimesh.visible_instance_count = 0
		var body := MultiMeshInstance3D.new()
		body.name = "Enemies %s" % T.enemy(kind).name
		body.multimesh = multimesh
		body.material_override = material
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(body)
		body.top_level = true
		body.global_transform = Transform3D.IDENTITY
		_bodies.append(body)
		var buffer := PackedFloat32Array()
		buffer.resize((CAP + CORPSE_CAP) * STRIDE)
		buffer.fill(0.0)
		_buffers.append(buffer)
	# Soft blob shadows under every enemy (one MultiMesh).
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var shadow_mm := MultiMesh.new()
	shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	shadow_mm.mesh = plane
	shadow_mm.instance_count = CAP
	shadow_mm.visible_instance_count = 0
	_shadows = MultiMeshInstance3D.new()
	_shadows.name = "Enemy shadows"
	_shadows.multimesh = shadow_mm
	_shadows.material_override = _shadow_material()
	_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadows)
	_shadows.top_level = true
	_shadows.global_transform = Transform3D.IDENTITY
	_shadow_buffer.resize(CAP * 12)
	_shadow_buffer.fill(0.0)


## [mesh, base transform]: head along +Z, feet at y = 0, longest ground
## extent = length.
func _fit_model(path: String, length: float, yaw: float) -> Array:
	var mesh: Mesh = null
	var base := Transform3D.IDENTITY
	if ResourceLoader.exists(path):
		var root: Node = (load(path) as PackedScene).instantiate()
		var found := root.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var source: MeshInstance3D = found[0]
			var node: Node = source
			while node != root and node is Node3D:
				base = (node as Node3D).transform * base
				node = node.get_parent()
			mesh = source.mesh
		root.free()
	if mesh == null:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 0.9
		return [capsule, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.3, 0))]
	base = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * base
	var raw: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	var extent := maxf(raw.size.x, raw.size.z)
	var shape := Basis.from_scale(Vector3.ONE * (length / maxf(0.01, extent))) * base.basis
	var bounds: AABB = Transform3D(shape, Vector3.ZERO) * mesh.get_aabb()
	return [mesh, Transform3D(shape, Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z))]


func _draw() -> void:
	if not _built:
		return
	var shadow := _shadow_buffer
	_shadow_buffer = PackedFloat32Array()
	var shadows := 0
	for kind in KINDS:
		# Take the buffer out of the member so writes never copy it (COW).
		var buffer := _buffers[kind]
		_buffers[kind] = PackedFloat32Array()
		var slot := 0
		for i in _n:
			if _kind[i] != kind:
				continue
			var pose := _pose(i)
			var xform: Transform3D = pose[0]
			var custom: Color = pose[1]
			var b := xform.basis
			var k := slot * STRIDE
			buffer[k] = b.x.x
			buffer[k + 1] = b.y.x
			buffer[k + 2] = b.z.x
			buffer[k + 3] = xform.origin.x
			buffer[k + 4] = b.x.y
			buffer[k + 5] = b.y.y
			buffer[k + 6] = b.z.y
			buffer[k + 7] = xform.origin.y
			buffer[k + 8] = b.x.z
			buffer[k + 9] = b.y.z
			buffer[k + 10] = b.z.z
			buffer[k + 11] = xform.origin.z
			buffer[k + 12] = 1.0
			buffer[k + 13] = 1.0
			buffer[k + 14] = 1.0
			buffer[k + 15] = 1.0
			buffer[k + 16] = custom.r
			buffer[k + 17] = custom.g
			buffer[k + 18] = custom.b
			buffer[k + 19] = custom.a
			slot += 1
			var p := _pos[i]
			var size := _radius[kind] * 2.6 * float(pose[2])
			var m := shadows * 12
			shadow[m] = size
			shadow[m + 5] = 1.0
			shadow[m + 7] = 0.025
			shadow[m + 3] = p.x
			shadow[m + 10] = size
			shadow[m + 11] = p.z
			shadows += 1
		for c in corpses:
			if int(c.kind) != kind or slot >= CAP + CORPSE_CAP:
				continue
			var t: float = c.age / CORPSE_LIFE
			var fade := 1.0 - clampf((t - 0.75) / 0.25, 0.0, 1.0)
			var angle: float = minf(float(c.angle), PI * 0.5) if kind == T.Kind.BROCKEN else float(c.angle)
			var basis := Basis(c.axis, angle) * Basis(Vector3.UP, float(c.yaw)) * Basis.from_scale(Vector3.ONE * lerpf(0.4, 1.0, fade) * float(c.get("scale", 1.0)))
			var at: Vector3 = c.pos
			var xform := Transform3D(basis, at + Vector3(0, _radius[kind] * 0.4, 0)) * _base[kind]
			var b := xform.basis
			var k := slot * STRIDE
			buffer[k] = b.x.x
			buffer[k + 1] = b.y.x
			buffer[k + 2] = b.z.x
			buffer[k + 3] = xform.origin.x
			buffer[k + 4] = b.x.y
			buffer[k + 5] = b.y.y
			buffer[k + 6] = b.z.y
			buffer[k + 7] = xform.origin.y
			buffer[k + 8] = b.x.z
			buffer[k + 9] = b.y.z
			buffer[k + 10] = b.z.z
			buffer[k + 11] = xform.origin.z
			buffer[k + 12] = 1.0
			buffer[k + 13] = 1.0
			buffer[k + 14] = 1.0
			buffer[k + 15] = 1.0
			buffer[k + 16] = maxf(0.0, 1.0 - float(c.age) * 8.0)
			buffer[k + 17] = 0.0
			buffer[k + 18] = minf(0.55, float(c.age) * 1.2)
			buffer[k + 19] = 0.0
			slot += 1
		_buffers[kind] = buffer
		var body := _bodies[kind]
		body.multimesh.buffer = buffer
		body.multimesh.visible_instance_count = slot
		body.visible = slot > 0
	_shadow_buffer = shadow
	_shadows.multimesh.buffer = shadow
	_shadows.multimesh.visible_instance_count = shadows
	_shadows.visible = shadows > 0
	_draw_arcs()


## [transform, custom (flash, wind-up glow, corpse, 0), shadow scale] of enemy i.
func _pose(i: int) -> Array:
	var k := _kind[i]
	var p := _pos[i]
	var state := _state[i]
	var walk := _walk[i]
	var hop := absf(sin(_gait[i])) * 0.09 * walk * (0.5 if k == T.Kind.BROCKEN else 1.0)
	var lean := 0.0
	var sy := 1.0
	var sxz := 1.0
	var glow := 0.0
	var lunge := 0.0
	var elite := _elite[i] == 1
	var windup := PT.ELITE_WINDUP if elite else _windup[k]
	match state:
		State.WINDUP:
			var w := 1.0 - _timer[i] / windup
			var e := 1.0 - (1.0 - w) * (1.0 - w)
			lean = -0.42 * e
			sy = 1.0 + 0.16 * e
			sxz = 1.0 - 0.06 * e
			glow = 0.25 + 0.75 * w
			if elite:
				# Champion: rears up high for the stomp.
				lean = -0.6 * e
				sy = 1.0 + 0.22 * e
				hop += 0.45 * e
			# Shiver just before the strike.
			if w > 0.7:
				lunge = sin(_timer[i] * 90.0) * 0.03
		State.STRIKE:
			var s := 1.0 - _timer[i] / STRIKE_SECONDS
			lean = 0.38 * sin(s * PI)
			lunge = (0.55 if k == T.Kind.BROCKEN else 0.4) * sin(s * PI)
			sy = 0.86
			sxz = 1.12
			glow = 1.0 - s
			if elite:
				# Slams straight down (all around, not forward).
				lean = 0.15 * sin(s * PI)
				lunge = 0.0
				sy = 0.8
				sxz = 1.16
		State.STAGGER:
			lean = -0.25
			sy = 0.9
			sxz = 1.08
	# Knockback tips the body back and lifts it a little.
	var kn_len := _knock[i].length()
	if kn_len > 0.2:
		lean -= minf(0.5, kn_len * 0.09)
		hop += minf(0.25, kn_len * 0.04)
	var grow := _appear[i]
	if grow < 1.0:
		var g := grow - 1.0
		grow = 1.0 + 2.70158 * g * g * g + 1.70158 * g * g
	var yaw := _yaw[i]
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var size := PT.ELITE_SCALE if elite else 1.0
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean) * Basis.from_scale(Vector3(sxz, sy, sxz) * grow * size)
	var xform := Transform3D(basis, Vector3(p.x, hop, p.z) + fwd * lunge) * _base[k]
	return [xform, Color(_flash[i], glow, 0.0, 1.0 if elite else 0.0), grow * (1.0 - minf(hop, 0.6)) * size]

## Magenta ground arcs under every Brocken that winds up (pooled meshes).
func _draw_arcs() -> void:
	var used := 0
	var used_elite := 0
	for i in _n:
		var k := _kind[i]
		if _arc_cos[k] <= -1.0 or (_state[i] != State.WINDUP and _state[i] != State.STRIKE):
			continue
		var elite := _elite[i] == 1
		var arc: MeshInstance3D
		if elite:
			if used_elite >= _elite_arcs.size():
				_elite_arcs.append(_make_arc(k, true))
			arc = _elite_arcs[used_elite]
			used_elite += 1
		else:
			if used >= _arcs.size():
				_arcs.append(_make_arc(k))
			arc = _arcs[used]
			used += 1
		var dir := _dir[i]
		arc.visible = true
		arc.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(_pos[i].x, 0.05, _pos[i].z))
		var material := arc.material_override as ShaderMaterial
		if _state[i] == State.WINDUP:
			material.set_shader_parameter("progress", 1.0 - _timer[i] / (PT.ELITE_WINDUP if elite else _windup[k]))
			material.set_shader_parameter("opacity", 1.0)
		else:
			material.set_shader_parameter("progress", 1.0)
			material.set_shader_parameter("opacity", _timer[i] / STRIKE_SECONDS)
	for index in range(used, _arcs.size()):
		_arcs[index].visible = false
	for index in range(used_elite, _elite_arcs.size()):
		_elite_arcs[index].visible = false


## elite: the champion's full stomp ring instead of the forward arc.
func _make_arc(kind: int, elite := false) -> MeshInstance3D:
	var outer := (PT.ELITE_REACH if elite else _reach[kind]) + T.HERO_RADIUS
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (outer + 0.3) * 2.0
	var arc := MeshInstance3D.new()
	arc.name = "Champion stomp" if elite else "Brocken arc"
	arc.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = ARC_SHADER
	material.set_shader_parameter("outer", outer)
	material.set_shader_parameter("inner", _radius[kind] * (0.9 if elite else 0.6))
	material.set_shader_parameter("half_angle", PI if elite else acos(clampf(_arc_cos[kind], -1.0, 1.0)))
	material.render_priority = 2
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arc)
	arc.top_level = true
	return arc


## True while any Brocken arc is shown (tests, captures).
func arcs_visible() -> int:
	var shown := 0
	for arc in _arcs:
		if arc.visible:
			shown += 1
	return shown


## Champion stomp rings shown right now (tests, captures).
func elite_arcs_visible() -> int:
	var shown := 0
	for arc in _elite_arcs:
		if arc.visible:
			shown += 1
	return shown


func _shadow_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0, 0, 0, 0.4)
	material.albedo_texture = texture
	material.render_priority = 1
	return material
