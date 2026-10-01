extends RefCounted

# Spawn director (stage 1, Teil B §5): small packs appear outside the camera
# view; the wanted number of living enemies rises over 5 minutes
# (tuning.gd DENSITY), Wichtel from 0 s, Renner from 40 s, Brocken from 90 s,
# never more than ENEMY_CAP living. Enemies left far behind are moved to a
# fresh off-screen spot near the hero, so the pressure stays around him.
#
# Stage 2 (Teil B, Druck; numbers in pressure_tuning.gd):
#   - packs come from 2-4 sides (a side set that turns every ~18 s) and, less
#     often than before, from where the hero runs to
#   - from 0:40 light packs are mixed (Wichtel with Renner and back)
#   - pressure.gd scales the density (boss fight), pauses it (breather) and
#     raises `endwave` from 6:00: pack size doubles every 45 s, the interval
#     halves every 60 s, enemies get tougher and a little faster.

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")

const RECYCLE_DISTANCE := 42.0
const RECYCLE_INTERVAL := 1.0
const VIEW_MARGIN := 2.0          # metres beyond the visible ground
# Visible ground around the hero for the game camera (offset (0, 23, 15),
# fov 58, portrait) when no camera is given (headless tests).
const FALLBACK_VIEW := Rect2(-10.5, -30.0, 21.0, 45.0)

var horde: Node3D
var arena: Node3D
var camera: Camera3D
## Hero running direction (xz, unit or zero); set by battle.gd each frame.
var heading := Vector3.ZERO
var pack_clock := 0.0
var recycle_clock := 0.0
var spawned := 0
var packs := 0
var rejected_in_view := 0
## Multiplier on the wanted density (pressure.gd: boss fight).
var density_scale := 1.0
## No new packs while true (pressure.gd: breather after the boss).
var paused := false
## Seconds into the Endwelle (0 = not yet).
var endwave := 0.0
## Stage 4 Teil A (worlds): the curves run on world time plus a head start
## (clock_offset = head start - world start, added to the elapsed time battle
## passes in); health and density factors of the current world.
var clock_offset := 0.0
var world_hp := 1.0
var world_density := 1.0
## Current pack sides (angles in rad) and the angle of the last pack (tests).
var sides: Array[float] = []
var last_angle := 0.0
var _sides_clock := 0.0
var _renner_shown := false
var _brocken_shown := false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 4242


func reset(seed_value: int = 4242) -> void:
	pack_clock = 0.0
	recycle_clock = 0.0
	spawned = 0
	packs = 0
	rejected_in_view = 0
	density_scale = 1.0
	paused = false
	endwave = 0.0
	sides.clear()
	_sides_clock = 0.0
	_renner_shown = false
	_brocken_shown = false
	_rng.seed = seed_value


func wanted(elapsed: float) -> int:
	if endwave > 0.0:
		return T.ENEMY_CAP
	return mini(T.ENEMY_CAP, int(round(T.curve(T.DENSITY, elapsed) * density_scale * world_density)))


## Stage 4 Teil A: scaling of world `index` (0..2) starting at run time `start`.
func set_world(index: int, start: float) -> void:
	index = clampi(index, 0, PT.WORLD_COUNT - 1)
	world_hp = float(PT.WORLD_HP[index])
	world_density = float(PT.WORLD_DENSITY[index])
	clock_offset = (PT.WORLD_HEAD_START if index > 0 else 0.0) - start


## Number of pack sides at this time (2..4).
func side_count(elapsed: float) -> int:
	return clampi(int(round(T.curve(PT.PACK_SIDES, elapsed))), 1, 4)


func step(delta: float, elapsed: float, hero_at: Vector3) -> void:
	if horde == null:
		return
	elapsed = maxf(0.0, elapsed + clock_offset)
	_step_sides(delta, elapsed)
	pack_clock -= delta
	var alive: int = horde.count()
	var want := wanted(elapsed)
	if not paused and alive < want and pack_clock <= 0.0:
		# Far below the wanted density: packs come twice as fast.
		var interval := T.curve(T.PACK_INTERVAL, elapsed)
		if alive < want / 2:
			interval *= 0.5
		if endwave > 0.0:
			interval = maxf(PT.END_INTERVAL_MIN, interval * pow(0.5, endwave / PT.END_INTERVAL_HALF))
		pack_clock = interval
		var size := T.curve(T.PACK_SIZE, elapsed) * _rng.randf_range(0.75, 1.25)
		if endwave > 0.0:
			size *= pow(2.0, endwave / PT.END_DOUBLING)
		# A whole pack even if that overshoots the wanted number a little.
		spawn_pack(elapsed, hero_at, maxi(2, int(round(size))))
	recycle_clock -= delta
	if recycle_clock <= 0.0:
		recycle_clock = RECYCLE_INTERVAL
		_recycle(hero_at)


func _step_sides(delta: float, elapsed: float) -> void:
	_sides_clock -= delta
	var want := side_count(elapsed)
	if _sides_clock > 0.0 and sides.size() == want:
		return
	_sides_clock = PT.PACK_SIDES_SHUFFLE
	# Evenly spread with a random turn and a little irregularity.
	var turn := _rng.randf() * TAU
	sides.clear()
	for k in want:
		sides.append(turn + TAU * float(k) / float(want) + _rng.randf_range(-0.3, 0.3))


## Enemy health / speed multipliers of the Endwelle (1 before 6:00).
func hp_mult() -> float:
	return world_hp * (pow(PT.END_HP_GROWTH, endwave / PT.END_HP_STEP) if endwave > 0.0 else 1.0)


func speed_mult() -> float:
	return 1.0 + minf(PT.END_SPEED_MAX, endwave / 300.0) if endwave > 0.0 else 1.0


## Direction (rad) of the next pack: from the hero's heading or one of the sides.
func pick_angle() -> float:
	if heading != Vector3.ZERO and _rng.randf() < PT.PACK_HEADING_SHARE:
		return atan2(heading.z, heading.x) + _rng.randf_range(-0.9, 0.9)
	if sides.is_empty():
		return _rng.randf() * TAU
	return sides[_rng.randi() % sides.size()] + _rng.randf_range(-0.35, 0.35)


## One pack of `size` around a point outside the view. Returns spawned count.
func spawn_pack(elapsed: float, hero_at: Vector3, size: int, angle := NAN) -> int:
	size = mini(size, T.ENEMY_CAP - horde.count())
	if size <= 0:
		return 0
	if is_nan(angle):
		angle = pick_angle()
	var center := find_spawn_point(hero_at, angle)
	if not center.is_finite():
		return 0
	last_angle = atan2(center.z - hero_at.z, center.x - hero_at.x)
	packs += 1
	var made := 0
	var lead_kind := _pick_kind(elapsed)
	for k in size:
		var kind := lead_kind
		# A Brocken leads at most one per pack; the rest of a pack is light.
		if k > 0 and kind == T.Kind.BROCKEN:
			kind = T.Kind.WICHTEL if _rng.randf() < 0.7 or elapsed < T.RENNER_FROM else T.Kind.RENNER
		elif k > 0 and elapsed >= T.RENNER_FROM and _rng.randf() < PT.PACK_MIX:
			# Mixed light packs: a few of the other light kind.
			kind = T.Kind.RENNER if kind == T.Kind.WICHTEL else T.Kind.WICHTEL
		var a := _rng.randf() * TAU
		var spot := center + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.0, 1.6 + 0.25 * float(mini(size, 16)))
		if place(kind, spot, hero_at) >= 0:
			made += 1
	return made


## Spawns one enemy near `spot` if that is open, off-screen and not too close
## to the hero. Returns its index or -1.
func place(kind: int, spot: Vector3, hero_at: Vector3, elite := false) -> int:
	var radius: float = horde.radius_of_kind(kind) * (PT.ELITE_SCALE if elite else 1.0)
	if arena != null and is_instance_valid(arena) and arena.has_method("safe_spawn"):
		spot = arena.safe_spawn(spot, radius + 0.1)
	if not spot.is_finite() or in_view(spot, hero_at) or spot.distance_to(hero_at) < T.SPAWN_MIN_DISTANCE - 3.0:
		return -1
	var index: int = horde.spawn(kind, spot, elite, hp_mult(), speed_mult())
	if index >= 0:
		spawned += 1
	return index


func _pick_kind(elapsed: float) -> int:
	# Each new kind gets its own entrance: the first pack after its start time.
	if elapsed >= T.BROCKEN_FROM and not _brocken_shown:
		_brocken_shown = true
		return T.Kind.BROCKEN
	if elapsed >= T.RENNER_FROM and not _renner_shown:
		_renner_shown = true
		return T.Kind.RENNER
	var brocken_weight := 0.0
	if elapsed >= T.BROCKEN_FROM:
		brocken_weight = lerpf(0.1, 0.22, clampf((elapsed - T.BROCKEN_FROM) / 150.0, 0.0, 1.0))
		# Few at a time: 2 at 1:30, one more every minute.
		if horde.count_kind(T.Kind.BROCKEN) >= 2 + int((elapsed - T.BROCKEN_FROM) / 60.0):
			brocken_weight = 0.0
	var renner_weight := 0.0
	if elapsed >= T.RENNER_FROM:
		renner_weight = lerpf(0.2, 0.35, clampf((elapsed - T.RENNER_FROM) / 120.0, 0.0, 1.0))
	var roll := _rng.randf()
	if roll < brocken_weight:
		return T.Kind.BROCKEN
	if roll < brocken_weight + renner_weight:
		return T.Kind.RENNER
	return T.Kind.WICHTEL


## An open point outside the view (Vector3.INF if none was found). With an
## angle the point lies in that direction (rad, xz) within `spread`.
func find_spawn_point(hero_at: Vector3, angle := NAN, spread := 0.25) -> Vector3:
	for attempt in 16:
		var a := _rng.randf() * TAU
		if not is_nan(angle):
			# Widen the search a little after failures (walls, map edge).
			a = angle + _rng.randf_range(-spread, spread) * (1.0 + float(attempt) * 0.25)
		elif heading != Vector3.ZERO and attempt < 8 and _rng.randf() < 0.5:
			a = atan2(heading.z, heading.x) + _rng.randf_range(-0.9, 0.9)
		var radius := T.SPAWN_MIN_DISTANCE + _rng.randf_range(0.0, 6.0)
		var point := Vector3.INF
		# Walk outwards along the ray until the point leaves the view.
		for push in 10:
			var r := radius + float(push) * 3.0
			if r > RECYCLE_DISTANCE - 4.0:
				break
			var candidate := hero_at + Vector3(cos(a), 0.0, sin(a)) * r
			if arena != null and is_instance_valid(arena) and arena.has_method("spawn_point_near"):
				candidate = arena.spawn_point_near(hero_at, r, a, 1.0)
				if not candidate.is_finite() or candidate.distance_to(hero_at) > RECYCLE_DISTANCE - 3.0:
					continue
			if arena != null and is_instance_valid(arena) and arena.has_method("playable_rect"):
				var rect: Rect2 = arena.playable_rect()
				if rect.size.x > 0.0 and not rect.grow(-1.0).has_point(Vector2(candidate.x, candidate.z)):
					break
			if not in_view(candidate, hero_at):
				point = candidate
				break
			rejected_in_view += 1
		if point.is_finite():
			return point
	return Vector3.INF


## True when the point (with a body margin) would be on screen.
func in_view(point: Vector3, hero_at: Vector3) -> bool:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		for lift in [0.0, 1.5]:
			for offset in [Vector3.ZERO, Vector3(VIEW_MARGIN, 0, 0), Vector3(-VIEW_MARGIN, 0, 0), Vector3(0, 0, VIEW_MARGIN), Vector3(0, 0, -VIEW_MARGIN)]:
				if camera.is_position_in_frustum(point + offset + Vector3.UP * float(lift)):
					return true
		return false
	var local := Vector2(point.x - hero_at.x, point.z - hero_at.z)
	return FALLBACK_VIEW.grow(VIEW_MARGIN).has_point(local)


func _recycle(hero_at: Vector3) -> void:
	var distance := PT.END_RECYCLE if endwave > 0.0 else RECYCLE_DISTANCE
	var limit2 := distance * distance
	var moved := 0
	var budget := 16 if endwave > 0.0 else 8
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var dx := p.x - hero_at.x
		var dz := p.z - hero_at.z
		if dx * dx + dz * dz > limit2 and moved < budget and not horde.in_ring(i):
			var spot := find_spawn_point(hero_at, pick_angle())
			if spot.is_finite():
				horde.relocate(i, spot)
				moved += 1
