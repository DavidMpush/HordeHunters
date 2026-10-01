extends "res://scripts/weapons/weapon.gd"

# Brann's double-barrelled shotgun (stage 1 spec, Teil B §3):
# - auto-aim on the nearest enemy within GUN_RANGE (8 m)
# - 2 shells, 0.35 s between the two shots, then a 0.7 s reload
#   (a half-empty gun tops up after GUN_TOPUP_IDLE s without a target)
# - 7 pellets in a 34 deg fan; each pellet stops at the first body it touches
# - pellet damage full up to 3 m, then linear down to 40 % at 8 m
# - knockback by mass, once per shot and enemy (horde.hurt)
# Pellet hits are gathered per enemy and applied together, so one number per
# enemy and shot pops up and the knock is not multiplied by the pellet count.
# Stage 2 (Teil A): the build feeds in through hero.stat(id): damage_mult,
# fire_rate_mult (shot gap), reload_mult, range_mult (aim, reach, falloff),
# fan_mult, pellets_bonus, pierce (a pellet goes on through that many more
# bodies), knockback_mult, mag_bonus, crit (chance of double pellet damage).
# Stage 3 (Teil B §1): built on weapon.gd (hero/horde/effects, _stat, damage
# booked on "Schrotflinte"); behaviour unchanged.

signal fired(direction: Vector3, pellets_hit: int, kills: int)
signal reload_started
signal shells_ejected
signal reload_finished

var shells := T.GUN_SHELLS
var gap := 0.0
var reload_left := 0.0
var idle := 0.0
var aim := Vector3.ZERO
var target := -1
var shots := 0
var reloads := 0
var _ejected := false
## Last shot (tests): [{"from", "to", "index", "damage"}] per pellet.
var last_pellets: Array[Dictionary] = []
var last_hits: Dictionary = {}


func _init() -> void:
	super()
	id = "shotgun"
	source = "Schrotflinte"


func max_shells() -> int:
	return T.GUN_SHELLS + int(_stat("mag_bonus"))


func reload_time() -> float:
	return T.GUN_RELOAD / maxf(0.1, _stat("reload_mult"))


func gun_range() -> float:
	return T.GUN_RANGE * _stat("range_mult")


func pellet_count() -> int:
	return T.GUN_PELLETS + int(_stat("pellets_bonus"))


func reset() -> void:
	super()
	shells = max_shells()
	gap = 0.0
	reload_left = 0.0
	idle = 0.0
	target = -1
	shots = 0
	reloads = 0
	_ejected = false
	last_pellets.clear()
	last_hits.clear()
	_set_model_reload(-1.0)


func is_reloading() -> bool:
	return reload_left > 0.0


## 0..1 progress of the running reload (-1 = not reloading).
func reload_progress() -> float:
	if reload_left <= 0.0:
		return -1.0
	return 1.0 - reload_left / reload_time()


func step(delta: float) -> void:
	if hero == null or horde == null:
		return
	if hero.has_method("is_dead") and hero.is_dead():
		return
	var at := Vector3(hero.position.x, 0.0, hero.position.z)
	target = horde.nearest_index(at, gun_range())
	if target >= 0:
		var to: Vector3 = horde.position_of(target) - at
		to.y = 0.0
		if to.length_squared() > 0.0001:
			aim = to.normalized()
		hero.aim_yaw = atan2(aim.x, aim.z)
		idle = 0.0
	else:
		idle += delta
		# Keep looking at the last target for a moment, then follow the walk.
		if idle > 0.5:
			hero.aim_yaw = NAN
	if reload_left > 0.0:
		reload_left -= delta
		var progress := reload_progress()
		if not _ejected and (progress >= 0.22 or reload_left <= 0.0):
			_ejected = true
			_eject()
		if reload_left <= 0.0:
			reload_left = 0.0
			shells = max_shells()
			gap = 0.0
			_set_model_reload(-1.0)
			reload_finished.emit()
		else:
			_set_model_reload(progress)
		return
	gap = maxf(0.0, gap - delta)
	if target >= 0 and gap <= 0.0 and shells > 0:
		fire(aim)
	if shells <= 0 and gap <= 0.0:
		start_reload()
	elif shells < max_shells() and target < 0 and idle >= T.GUN_TOPUP_IDLE:
		start_reload()


func start_reload() -> void:
	if reload_left > 0.0:
		return
	reload_left = reload_time()
	reloads += 1
	_ejected = false
	_set_model_reload(0.0)
	reload_started.emit()


## Fires one shell along `direction` (xz). Returns the number of kills.
func fire(direction: Vector3) -> int:
	if shells <= 0 or reload_left > 0.0:
		return 0
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if dir == Vector3.ZERO:
		return 0
	shells -= 1
	gap = T.GUN_SHOT_GAP / maxf(0.1, _stat("fire_rate_mult"))
	shots += 1
	var origin := Vector3(hero.position.x, 0.0, hero.position.z)
	var muzzle := origin + dir * 1.0 + Vector3.UP * 1.2
	var model: Node3D = hero.get("model")
	if model != null and model.has_method("muzzle_position") and model.is_inside_tree():
		model.snap_aim(atan2(dir.x, dir.z))
		muzzle = model.muzzle_position()
	var hits := {}
	var pellets_hit := 0
	last_pellets.clear()
	var reach := gun_range()
	var range_mult := reach / T.GUN_RANGE
	var damage_mult := _stat("damage_mult") * power_factor()
	var crit := _stat("crit")
	var pierce := int(_stat("pierce"))
	var knock_mult := _stat("knockback_mult")
	var count := pellet_count()
	var fan := deg_to_rad(T.GUN_FAN_DEG * _stat("fan_mult"))
	for p in count:
		var share := float(p) / float(maxi(1, count - 1)) - 0.5
		var angle := share * fan + deg_to_rad(_rng.randf_range(-T.GUN_PELLET_JITTER_DEG, T.GUN_PELLET_JITTER_DEG))
		var pellet := dir.rotated(Vector3.UP, angle)
		# A pellet stops at the first body, or goes on through `pierce` more.
		var travelled := 0.0
		var from := origin
		var first := -1
		var first_damage := 0.0
		var end := origin + pellet * reach
		for body in pierce + 1:
			var result: Dictionary = horde.raycast(from, pellet, reach - travelled)
			var index: int = result.index
			var distance: float = travelled + float(result.distance)
			end = origin + pellet * distance
			if index < 0:
				break
			pellets_hit += 1
			var damage := T.pellet_damage(distance / range_mult) * damage_mult
			if crit > 0.0 and _rng.randf() < crit:
				damage *= 2.0
			var to_enemy: Vector3 = horde.position_of(index) - origin
			to_enemy.y = 0.0
			var push_dir := to_enemy.normalized() if to_enemy.length_squared() > 0.0001 else dir
			if not hits.has(index):
				hits[index] = {"damage": 0.0, "dir": push_dir, "pellets": 0}
				if not is_equal_approx(knock_mult, 1.0):
					hits[index]["knock"] = _knock_for(index) * knock_mult
			hits[index].damage += damage
			hits[index].pellets += 1
			if first < 0:
				first = index
				first_damage = damage
			if effects != null and is_instance_valid(effects):
				effects.hit_sparks(end + Vector3.UP * 0.45, pellet, 3)
			# Continue just behind the far side of this body.
			var along := to_enemy.dot(pellet)
			travelled = along + horde.radius_of_kind(horde.kind_of(index)) + 0.12
			from = origin + pellet * travelled
			if travelled >= reach:
				break
		last_pellets.append({"from": origin, "to": end, "index": first, "damage": first_damage, "angle": angle})
		if effects != null and is_instance_valid(effects):
			effects.tracer(muzzle, end + Vector3.UP * (0.45 if first >= 0 else 0.6))
	last_hits = hits.duplicate(true)
	var killed := apply(hits)
	if model != null:
		model.recoil = 1.0
	if effects != null and is_instance_valid(effects):
		effects.muzzle_flash(muzzle, dir)
		effects.blast(origin + dir * 0.4, dir, reach - 0.4, fan * 0.5)
	fired.emit(dir, pellets_hit, killed)
	return killed


func _eject() -> void:
	var model: Node3D = hero.get("model")
	if effects != null and is_instance_valid(effects):
		var at := Vector3(hero.position.x, 1.2, hero.position.z)
		if model != null and model.has_method("breech_position") and model.is_inside_tree():
			at = model.breech_position()
		effects.eject_shells(at, -aim if aim != Vector3.ZERO else Vector3.BACK, max_shells() - shells)
	shells_ejected.emit()


# Knock speed by the mass of enemy `index` (before the build multiplier).
func _knock_for(index: int) -> float:
	var masses: Variant = horde.get("_mass")
	var kind: int = horde.kind_of(index)
	if masses is PackedInt32Array and kind >= 0 and kind < (masses as PackedInt32Array).size():
		return T.knock_for((masses as PackedInt32Array)[kind])
	return T.knock_for(T.Mass.LIGHT)


func _set_model_reload(value: float) -> void:
	var model: Node3D = hero.get("model") if hero != null else null
	if model != null:
		model.reload = value
