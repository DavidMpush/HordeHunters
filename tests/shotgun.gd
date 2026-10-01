extends SceneTree

# Shotgun (stage 1, Teil B §3): auto-aim within 8 m, 2 shells 0.35 s apart,
# 0.7 s reload, 7 pellets in a 34 deg fan, damage falloff 3 m -> 40 % at 8 m,
# first body stops a pellet, knockback by mass once per shot.

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []
var battle: Node
var hero: Node3D
var horde: Node3D
var gun: Node


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab: Node = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab)
	for k in 3:
		await process_frame
	battle = lab.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	hero = battle.hero
	horde = battle.horde
	gun = battle.shotgun
	_rhythm()
	_fan_and_falloff()
	_first_hit_stops()
	_knockback()
	_range_and_topup()
	_finish("shotgun")


## Shot times: 0, 0.35, reload 0.7 s, next shot at 1.05 s.
func _rhythm() -> void:
	_reset()
	var target := _spawn(T.Kind.BROCKEN, Vector3(0, 0, -3.5), 100000.0)
	var times: Array[float] = []
	var reload_seen := false
	var t := 0.0
	while t < 1.5:
		var shots_before: int = gun.shots
		gun.step(DT)
		if gun.shots > shots_before:
			times.append(t)
		horde.step(DT)
		horde._pos[target] = Vector3(0, 0, -3.5)
		reload_seen = reload_seen or gun.is_reloading()
		t += DT
	check(times.size() >= 3, "three shots in 1.5 s (got %d)" % times.size())
	if times.size() >= 3:
		check(absf(times[0]) < DT * 1.5, "first shot at once")
		check(absf(times[1] - times[0] - T.GUN_SHOT_GAP) <= DT * 1.5, "0.35 s between the two shells (got %.3f)" % (times[1] - times[0]))
		check(absf(times[2] - times[1] - (T.GUN_SHOT_GAP + T.GUN_RELOAD)) <= DT * 2.5, "reload 0.7 s after the gap (got %.3f)" % (times[2] - times[1]))
	check(reload_seen, "reload state seen")
	check(gun.reloads >= 1, "reload counted")


func _fan_and_falloff() -> void:
	_reset()
	var target := _spawn(T.Kind.BROCKEN, Vector3(0, 0, -2.0), 100000.0)
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	check(gun.last_pellets.size() == T.GUN_PELLETS, "7 pellets")
	var low := INF
	var high := -INF
	for pellet in gun.last_pellets:
		low = minf(low, float(pellet.angle))
		high = maxf(high, float(pellet.angle))
	var spread := rad_to_deg(high - low)
	check(absf(spread - T.GUN_FAN_DEG) <= T.GUN_PELLET_JITTER_DEG * 2.0 + 0.1, "fan of 34 deg (got %.1f)" % spread)
	check(is_equal_approx(T.pellet_damage(1.0), T.GUN_PELLET_DAMAGE), "full damage close")
	check(is_equal_approx(T.pellet_damage(3.0), T.GUN_PELLET_DAMAGE), "full damage up to 3 m")
	check(is_equal_approx(T.pellet_damage(8.0), T.GUN_PELLET_DAMAGE * 0.4), "40 % at 8 m")
	check(is_equal_approx(T.pellet_damage(5.5), T.GUN_PELLET_DAMAGE * 0.7), "linear in between")
	# Applied damage matches the falloff at the hit distance.
	var hit: Dictionary = gun.last_hits.get(target, {})
	var expected := 0.0
	for pellet in gun.last_pellets:
		if int(pellet.index) == target:
			expected += T.pellet_damage(Vector3(pellet.from).distance_to(Vector3(pellet.to)))
	check(not hit.is_empty() and absf(float(hit.damage) - expected) < 0.01, "damage = sum of pellet falloff")
	check(absf(horde.health_of(target) - (100000.0 - expected)) < 0.01, "enemy lost that damage")
	# Far target takes less per pellet.
	_reset()
	var far := _spawn(T.Kind.BROCKEN, Vector3(0, 0, -7.0), 100000.0)
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	var far_hit: Dictionary = gun.last_hits.get(far, {})
	check(not far_hit.is_empty() and float(far_hit.damage) / float(far_hit.pellets) < T.GUN_PELLET_DAMAGE * 0.7, "pellets lose damage far away")


func _first_hit_stops() -> void:
	_reset()
	var front := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -2.0), 100000.0)
	var back := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -4.0), 100000.0)
	horde.step(DT)
	front = horde.nearest_index(Vector3(0, 0, -2.0), 0.5)
	back = horde.nearest_index(Vector3(0, 0, -4.0), 0.5)
	var ray: Dictionary = horde.raycast(Vector3.ZERO, Vector3(0, 0, -1), T.GUN_RANGE)
	check(int(ray.index) == front, "a ray stops at the first body")
	gun.fire(Vector3(0, 0, -1))
	var centre: Dictionary = gun.last_pellets[T.GUN_PELLETS / 2]
	check(int(centre.index) == front, "centre pellet hits the front enemy")
	check(Vector3(centre.to).distance_to(Vector3.ZERO) < 2.0, "centre pellet ends at the front body")
	var back_hits := 0
	for pellet in gun.last_pellets:
		if int(pellet.index) == back:
			back_hits += 1
			# Only pellets that pass beside the front body may reach the back one.
			var side := absf(sin(float(pellet.angle))) * 2.0
			check(side > horde.radius_of_kind(T.Kind.WICHTEL), "pellet behind the front body passed it")
	check(back_hits < T.GUN_PELLETS, "not every pellet reaches the back enemy")


func _knockback() -> void:
	_reset()
	var light := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -2.5), 100000.0)
	horde._speed[light] = 0.0
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	var pellets := int(gun.last_hits.get(light, {}).get("pellets", 0))
	var knock: Vector3 = horde.knock_of(light)
	check(pellets >= 2, "several pellets hit the close Wichtel (%d)" % pellets)
	check(absf(knock.length() - T.KNOCK_LIGHT) < 0.05, "light knock 4 m/s once per shot (got %.2f)" % knock.length())
	check(knock.z < -3.5, "knock pushes away from the hero")
	var before: Vector3 = horde.position_of(light)
	for k in 30:
		horde.step(DT)
	check(horde.position_of(light).z < before.z - 0.4, "Wichtel slides back (%.2f m)" % (before.z - horde.position_of(light).z))
	_reset()
	var heavy := _spawn(T.Kind.BROCKEN, Vector3(0, 0, -2.5), 100000.0)
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	check(horde.knock_of(heavy).length() < 0.001, "heavy (Brocken) is not knocked")
	check(is_equal_approx(T.knock_for(T.Mass.MEDIUM), 1.5) and is_equal_approx(T.knock_for(T.Mass.LIGHT), 4.0) and T.knock_for(T.Mass.HEAVY) == 0.0, "knock table 4 / 1.5 / 0")
	# Medium mass path through horde.hurt.
	_reset()
	var mid := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -3.0), 100000.0)
	horde.hurt(mid, 1.0, Vector3(0, 0, -1), T.knock_for(T.Mass.MEDIUM))
	check(absf(horde.knock_of(mid).length() - 1.5) < 0.01, "medium knock 1.5 m/s")
	# A kill flings the body (corpse) along the shot.
	_reset()
	_spawn(T.Kind.WICHTEL, Vector3(0, 0, -2.0), 1.0)
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	check(horde.count() == 0 and horde.corpses.size() == 1, "kill leaves a flying corpse")
	if horde.corpses.size() == 1:
		var vel: Vector3 = horde.corpses[0].vel
		check(vel.z < -4.0 and vel.y > 3.0, "corpse flies away and up")


func _range_and_topup() -> void:
	_reset()
	var far := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -(T.GUN_RANGE + 1.5)), 100000.0)
	for k in 20:
		gun.step(DT)
		horde._pos[far] = Vector3(0, 0, -(T.GUN_RANGE + 1.5))
	check(gun.shots == 0, "no shot beyond 8 m")
	horde._pos[far] = Vector3(0, 0, -(T.GUN_RANGE - 1.0))
	gun.step(DT)
	check(gun.shots == 1 and gun.shells == 1, "auto-aim shoots inside 8 m")
	horde.clear()
	var waited := 0.0
	while waited < T.GUN_TOPUP_IDLE + 0.2 and not gun.is_reloading():
		gun.step(DT)
		waited += DT
	check(gun.is_reloading(), "half-empty gun tops up when idle")
	for k in 60:
		gun.step(DT)
	check(gun.shells == T.GUN_SHELLS, "two shells after the top-up")


func _reset() -> void:
	horde.clear()
	gun.reset()
	hero.reset(Vector3.ZERO)


func _spawn(kind: int, at: Vector3, hp: float) -> int:
	var i: int = horde.spawn(kind, at)
	horde._hp[i] = hp
	horde._appear[i] = 1.0
	return i


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
