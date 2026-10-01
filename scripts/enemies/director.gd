extends RefCounted

# Spawn director (stage 1, Teil B §5): small packs appear outside the camera
# view; the wanted number of living enemies rises over 5 minutes
# (tuning.gd DENSITY), Wichtel from 0 s, Renner from 40 s, Brocken from 90 s,
# never more than ENEMY_CAP living. Enemies left far behind are moved to a
# fresh off-screen spot near the hero, so the pressure stays around him.

const T := preload("res://scripts/core/tuning.gd")

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
	_renner_shown = false
	_brocken_shown = false
	_rng.seed = seed_value


func wanted(elapsed: float) -> int:
	return mini(T.ENEMY_CAP, int(round(T.curve(T.DENSITY, elapsed))))


func step(delta: float, elapsed: float, hero_at: Vector3) -> void:
	if horde == null:
		return
	pack_clock -= delta
	var alive: int = horde.count()
	var want := wanted(elapsed)
	if alive < want and pack_clock <= 0.0:
		# Far below the wanted density: packs come twice as fast.
		var interval := T.curve(T.PACK_INTERVAL, elapsed)
		if alive < want / 2:
			interval *= 0.5
		pack_clock = interval
		var size := int(round(T.curve(T.PACK_SIZE, elapsed) * _rng.randf_range(0.75, 1.25)))
		# A whole pack even if that overshoots the wanted number a little.
		spawn_pack(elapsed, hero_at, maxi(2, size))
	recycle_clock -= delta
	if recycle_clock <= 0.0:
		recycle_clock = RECYCLE_INTERVAL
		_recycle(hero_at)


## One pack of `size` around a point outside the view. Returns spawned count.
func spawn_pack(elapsed: float, hero_at: Vector3, size: int) -> int:
	size = mini(size, T.ENEMY_CAP - horde.count())
	if size <= 0:
		return 0
	var center := find_spawn_point(hero_at)
	if not center.is_finite():
		return 0
	packs += 1
	var made := 0
	var kind := _pick_kind(elapsed)
	for k in size:
		# A Brocken leads at most one per pack; the rest of a pack is light.
		if k > 0 and kind == T.Kind.BROCKEN:
			kind = T.Kind.WICHTEL if _rng.randf() < 0.7 or elapsed < T.RENNER_FROM else T.Kind.RENNER
		var angle := _rng.randf() * TAU
		var spot := center + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.0, 1.6 + 0.25 * float(size))
		var radius: float = horde.radius_of_kind(kind)
		if arena != null and is_instance_valid(arena) and arena.has_method("safe_spawn"):
			spot = arena.safe_spawn(spot, radius + 0.1)
		if not spot.is_finite() or in_view(spot, hero_at) or spot.distance_to(hero_at) < T.SPAWN_MIN_DISTANCE - 3.0:
			continue
		if horde.spawn(kind, spot) >= 0:
			made += 1
			spawned += 1
	return made


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


## An open point outside the view (Vector3.INF if none was found).
func find_spawn_point(hero_at: Vector3) -> Vector3:
	for attempt in 16:
		var angle := _rng.randf() * TAU
		# Half of the packs come from where the hero is running to.
		if heading != Vector3.ZERO and attempt < 8 and _rng.randf() < 0.5:
			angle = atan2(heading.z, heading.x) + _rng.randf_range(-0.9, 0.9)
		var radius := T.SPAWN_MIN_DISTANCE + _rng.randf_range(0.0, 6.0)
		var point := Vector3.INF
		# Walk outwards along the ray until the point leaves the view.
		for push in 10:
			var r := radius + float(push) * 3.0
			if r > RECYCLE_DISTANCE - 4.0:
				break
			var candidate := hero_at + Vector3(cos(angle), 0.0, sin(angle)) * r
			if arena != null and is_instance_valid(arena) and arena.has_method("spawn_point_near"):
				candidate = arena.spawn_point_near(hero_at, r, angle, 1.0)
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
	var limit2 := RECYCLE_DISTANCE * RECYCLE_DISTANCE
	var moved := 0
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var dx := p.x - hero_at.x
		var dz := p.z - hero_at.z
		if dx * dx + dz * dz > limit2 and moved < 8:
			var spot := find_spawn_point(hero_at)
			if spot.is_finite():
				horde.relocate(i, spot)
				moved += 1
