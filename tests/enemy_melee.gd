extends SceneTree

# Enemy melee (stage 1, Teil B §4): approach -> stop and wind up -> hit only if
# the hero is still in reach at the end -> recover. Running away or dashing
# saves; the Brocken shows a magenta arc and only hits inside it; a light
# enemy shot during its wind-up staggers. Separation keeps bodies apart.

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []
var battle: Node
var hero: Node3D
var horde: Node3D
const HOME := Vector3(-10, 0, 30)


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
	_wichtel_hits_when_standing()
	_running_away_saves()
	_dash_saves()
	_brocken_arc()
	_stagger()
	_separation()
	_renner_fast()
	_finish("enemy_melee")


func _reset() -> void:
	horde.clear()
	hero.reset(HOME)
	battle.arena.sync(HOME)


func _spawn(kind: int, offset: Vector3) -> int:
	var i: int = horde.spawn(kind, HOME + offset)
	horde._appear[i] = 1.0
	return i


## Steps the horde (and the hero with `move`) until `done` or `limit` seconds.
func _run_until(done: Callable, limit: float, move := Vector2.ZERO) -> float:
	var t := 0.0
	while t < limit and not done.call():
		hero.step(DT, move)
		horde.step(DT)
		t += DT
	return t


func _wichtel_hits_when_standing() -> void:
	_reset()
	var stats: Dictionary = T.enemy(T.Kind.WICHTEL)
	_spawn(T.Kind.WICHTEL, Vector3(0, 0, -6))
	_run_until(func() -> bool: return horde.state_of(0) != horde.State.APPROACH, 5.0)
	check(horde.state_of(0) == horde.State.WINDUP, "Wichtel stops and winds up in reach")
	var gap: float = horde.position_of(0).distance_to(hero.position)
	check(gap <= float(stats.reach) + T.HERO_RADIUS + 0.05, "wind-up starts within reach (%.2f m)" % gap)
	var stand: Vector3 = horde.position_of(0)
	var windup_time := _run_until(func() -> bool: return horde.state_of(0) != horde.State.WINDUP, 2.0)
	check(absf(windup_time - float(stats.windup)) <= DT * 1.5, "wind-up lasts 0.35 s (%.3f)" % windup_time)
	check(horde.position_of(0).distance_to(stand) < 0.15, "Wichtel holds still while winding up")
	check(is_equal_approx(hero.health, hero.max_health - float(stats.damage)), "standing hero takes 8 damage")
	check(horde.strikes == 1 and horde.strikes_hit == 1, "exactly one strike landed")
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.RECOVER, 1.0)
	check(horde.state_of(0) == horde.State.RECOVER, "recovers after the strike")
	var health: float = hero.health
	_run_until(func() -> bool: return false, float(stats.recover) * 0.8)
	check(hero.health == health, "no free hit while recovering")


func _running_away_saves() -> void:
	_reset()
	_spawn(T.Kind.WICHTEL, Vector3(0, 0, -6))
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.WINDUP, 5.0)
	# Run straight away (south) for the whole wind-up.
	_run_until(func() -> bool: return horde.state_of(0) != horde.State.WINDUP, 2.0, Vector2(0, 1))
	check(hero.health == hero.max_health, "running away during the wind-up saves")
	check(horde.strikes == 1 and horde.strikes_hit == 0, "strike swung and missed")


func _dash_saves() -> void:
	_reset()
	_spawn(T.Kind.WICHTEL, Vector3(0, 0, -6))
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.WINDUP, 5.0)
	_run_until(func() -> bool: return horde._timer[0] < 0.05, 1.0)
	# Dash sideways right at the end: still in reach for a frame, but invulnerable.
	hero.dash(Vector3.RIGHT)
	_run_until(func() -> bool: return horde.state_of(0) != horde.State.WINDUP, 1.0)
	check(hero.health == hero.max_health, "dash at the last moment saves")


func _brocken_arc() -> void:
	_reset()
	var stats: Dictionary = T.enemy(T.Kind.BROCKEN)
	_spawn(T.Kind.BROCKEN, Vector3(0, 0, -7))
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.WINDUP, 8.0)
	check(horde.state_of(0) == horde.State.WINDUP, "Brocken winds up")
	check(horde.arcs_visible() == 1, "magenta arc shown during the wind-up")
	var t := _run_until(func() -> bool: return horde.state_of(0) != horde.State.WINDUP, 2.0)
	check(absf(t - float(stats.windup)) <= DT * 1.5 + 0.02, "Brocken wind-up 0.8 s (%.3f)" % t)
	check(is_equal_approx(hero.health, hero.max_health - float(stats.damage)), "standing in the arc costs 22")
	# Sidestep out of the arc but stay within reach distance: the swing misses.
	_reset()
	_spawn(T.Kind.BROCKEN, Vector3(0, 0, -7))
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.WINDUP, 8.0)
	var brocken: Vector3 = horde.position_of(0)
	var dir: Vector3 = horde._dir[0]
	var side := Vector3(-dir.z, 0, dir.x)
	# 85 deg off the swing direction, 1.6 m from the Brocken: in reach, outside the arc.
	hero.position = brocken + (side * 0.996 + dir * 0.087).normalized() * 1.6
	horde._timer[0] = 0.01
	horde.step(DT)
	check(hero.health == hero.max_health, "outside the arc is safe even in reach")
	check(horde.strikes_hit == 0, "arc strike missed")
	check(horde.arcs_visible() <= 1, "arc only while striking")
	for k in 30:
		horde.step(DT)
	check(horde.arcs_visible() == 0, "arc gone after the strike")


func _stagger() -> void:
	_reset()
	_spawn(T.Kind.WICHTEL, Vector3(0, 0, -6))
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.WINDUP, 5.0)
	horde._hp[0] = 1000.0
	horde.hurt(0, 5.0, Vector3(0, 0, -1))
	check(horde.state_of(0) == horde.State.STAGGER, "shot during the wind-up staggers a light enemy")
	_run_until(func() -> bool: return horde.state_of(0) != horde.State.STAGGER, 1.0)
	check(hero.health == hero.max_health, "staggered strike never lands")
	_reset()
	_spawn(T.Kind.BROCKEN, Vector3(0, 0, -7))
	_run_until(func() -> bool: return horde.state_of(0) == horde.State.WINDUP, 8.0)
	horde.hurt(0, 5.0, Vector3(0, 0, -1))
	check(horde.state_of(0) == horde.State.WINDUP, "Brocken keeps winding up when shot")


func _separation() -> void:
	_reset()
	for k in 30:
		_spawn(T.Kind.WICHTEL, Vector3(float(k % 6) * 0.1 - 0.3, 0, -9.0 - float(k / 6) * 0.1))
	hero.position = HOME + Vector3(0, 0, 14)
	battle.arena.sync(hero.position)
	for k in 120:
		horde.step(DT)
	var closest := INF
	for i in horde.count():
		for j in range(i + 1, horde.count()):
			closest = minf(closest, horde.position_of(i).distance_to(horde.position_of(j)))
	var r: float = horde.radius_of_kind(T.Kind.WICHTEL)
	check(closest > r * 1.0, "separation spreads a clump (closest %.2f m)" % closest)


func _renner_fast() -> void:
	_reset()
	_spawn(T.Kind.WICHTEL, Vector3(-1.5, 0, -12))
	_spawn(T.Kind.RENNER, Vector3(1.5, 0, -12))
	hero.position = HOME
	for k in 60:
		horde.step(DT)
	var wichtel: float = horde.position_of(0).distance_to(HOME)
	var renner: float = horde.position_of(1).distance_to(HOME)
	check(renner < wichtel - 1.5, "Renner closes in faster than Wichtel")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
