extends Node

# Brann's double-barrelled shotgun (stage 1 spec, Teil B §3):
# - auto-aim on the nearest enemy within GUN_RANGE (8 m)
# - 2 shells, 0.35 s between the two shots, then a 0.7 s reload
#   (a half-empty gun tops up after GUN_TOPUP_IDLE s without a target)
# - 7 pellets in a 34 deg fan; each pellet stops at the first body it touches
# - pellet damage full up to 3 m, then linear down to 40 % at 8 m
# - knockback by mass, once per shot and enemy (horde.hurt)
# Pellet hits are gathered per enemy and applied together, so one number per
# enemy and shot pops up and the knock is not multiplied by the pellet count.

signal fired(direction: Vector3, pellets_hit: int, kills: int)
signal reload_started
signal shells_ejected
signal reload_finished

const T := preload("res://scripts/core/tuning.gd")

var hero: Node3D
var horde: Node3D
var effects: Node3D

var shells := T.GUN_SHELLS
var gap := 0.0
var reload_left := 0.0
var idle := 0.0
var aim := Vector3.ZERO
var target := -1
var shots := 0
var reloads := 0
var _ejected := false
var _rng := RandomNumberGenerator.new()
## Last shot (tests): [{"from", "to", "index", "damage"}] per pellet.
var last_pellets: Array[Dictionary] = []
var last_hits: Dictionary = {}


func _init() -> void:
	_rng.seed = 1234


func reset() -> void:
	shells = T.GUN_SHELLS
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
	return 1.0 - reload_left / T.GUN_RELOAD


func step(delta: float) -> void:
	if hero == null or horde == null:
		return
	if hero.has_method("is_dead") and hero.is_dead():
		return
	var at := Vector3(hero.position.x, 0.0, hero.position.z)
	target = horde.nearest_index(at, T.GUN_RANGE)
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
			shells = T.GUN_SHELLS
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
	elif shells < T.GUN_SHELLS and target < 0 and idle >= T.GUN_TOPUP_IDLE:
		start_reload()


func start_reload() -> void:
	if reload_left > 0.0:
		return
	reload_left = T.GUN_RELOAD
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
	gap = T.GUN_SHOT_GAP
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
	var fan := deg_to_rad(T.GUN_FAN_DEG)
	for p in T.GUN_PELLETS:
		var share := float(p) / float(T.GUN_PELLETS - 1) - 0.5
		var angle := share * fan + deg_to_rad(_rng.randf_range(-T.GUN_PELLET_JITTER_DEG, T.GUN_PELLET_JITTER_DEG))
		var pellet := dir.rotated(Vector3.UP, angle)
		var result: Dictionary = horde.raycast(origin, pellet, T.GUN_RANGE)
		var index: int = result.index
		var distance: float = result.distance
		var end := origin + pellet * distance
		var damage := 0.0
		if index >= 0:
			pellets_hit += 1
			damage = T.pellet_damage(distance)
			var to_enemy: Vector3 = horde.position_of(index) - origin
			to_enemy.y = 0.0
			var push_dir := to_enemy.normalized() if to_enemy.length_squared() > 0.0001 else dir
			if not hits.has(index):
				hits[index] = {"damage": 0.0, "dir": push_dir, "pellets": 0}
			hits[index].damage += damage
			hits[index].pellets += 1
			if effects != null and is_instance_valid(effects):
				effects.hit_sparks(end + Vector3.UP * 0.45, pellet, 3)
		last_pellets.append({"from": origin, "to": end, "index": index, "damage": damage, "angle": angle})
		if effects != null and is_instance_valid(effects):
			effects.tracer(muzzle, end + Vector3.UP * (0.45 if index >= 0 else 0.6))
	last_hits = hits.duplicate(true)
	var kills: int = horde.apply_hits(hits)
	if model != null:
		model.recoil = 1.0
	if effects != null and is_instance_valid(effects):
		effects.muzzle_flash(muzzle, dir)
		effects.blast(origin + dir * 0.4, dir, T.GUN_RANGE - 0.4, fan * 0.5)
	fired.emit(dir, pellets_hit, kills)
	return kills


func _eject() -> void:
	var model: Node3D = hero.get("model")
	if effects != null and is_instance_valid(effects):
		var at := Vector3(hero.position.x, 1.2, hero.position.z)
		if model != null and model.has_method("breech_position") and model.is_inside_tree():
			at = model.breech_position()
		effects.eject_shells(at, -aim if aim != Vector3.ZERO else Vector3.BACK, T.GUN_SHELLS - shells)
	shells_ejected.emit()


func _set_model_reload(value: float) -> void:
	var model: Node3D = hero.get("model") if hero != null else null
	if model != null:
		model.reload = value
