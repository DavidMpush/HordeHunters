extends SceneTree

# Dash (stage 1, Teil B §2): 5 m in 0.18 s, invulnerable while dashing,
# 2.5 s cooldown; walls stop it; short invulnerability after a normal hit.

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []


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
	var battle: Node = lab.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	var hero: Node3D = battle.hero
	# Distance and duration.
	hero.reset(Vector3(0, 0, 20))
	check(hero.dash(Vector3.RIGHT), "dash starts when ready")
	var start: Vector3 = hero.position
	var frames := 0
	var hit_while_dashing := false
	while hero.is_dashing() and frames < 60:
		if frames == 4:
			hit_while_dashing = hero.take_hit(10.0, hero.position + Vector3(1, 0, 0))
		hero.step(DT, Vector2.ZERO)
		frames += 1
	var travelled: float = hero.position.distance_to(start)
	check(absf(travelled - T.DASH_DISTANCE) < 0.15, "dash covers 5 m (got %.2f)" % travelled)
	check(absf(frames * DT - T.DASH_SECONDS) <= DT * 1.5, "dash lasts 0.18 s (got %.3f)" % (frames * DT))
	check(not hit_while_dashing and hero.health == hero.max_health, "invulnerable while dashing")
	# Cooldown.
	check(not hero.dash(Vector3.LEFT), "no second dash during cooldown")
	var waited := float(frames) * DT
	while waited < T.DASH_COOLDOWN - 0.1:
		hero.step(DT, Vector2.ZERO)
		waited += DT
	check(not hero.dash_ready(), "still cooling down at 2.4 s")
	while waited < T.DASH_COOLDOWN + DT:
		hero.step(DT, Vector2.ZERO)
		waited += DT
	check(hero.dash_ready(), "ready again after 2.5 s")
	# Dash along the stick, otherwise along the facing.
	hero.reset(Vector3(-10, 0, 28))
	for k in 10:
		hero.step(DT, Vector2(0, -1))
	hero.dash_cooldown = 0.0
	var before: Vector3 = hero.position
	hero.dash()
	for k in 15:
		hero.step(DT, Vector2.ZERO)
	check(hero.position.z < before.z - 4.5 and absf(hero.position.x - before.x) < 0.2, "dash without stick follows facing")
	# A wall stops the dash (lab wall x 8..9.4, z 6..14).
	hero.reset(Vector3(5, 0, 10))
	hero.dash(Vector3.RIGHT)
	for k in 15:
		hero.step(DT, Vector2.ZERO)
	check(hero.position.x <= 8.0 - hero.radius + 0.02, "wall stops the dash (x = %.2f)" % hero.position.x)
	# Dash from the controls (button / Space) goes through battle.
	hero.reset(Vector3(0, 0, 20))
	battle.controls.request_dash()
	check(hero.is_dashing() and hero.dash_count == 1, "dash button starts a dash")
	# Normal hit: damage, then a short invulnerability.
	hero.reset(Vector3(0, 0, 20))
	check(hero.take_hit(8.0, Vector3(1, 0, 20)), "hit lands when not dashing")
	check(is_equal_approx(hero.health, hero.max_health - 8.0), "hit costs its damage")
	check(not hero.take_hit(8.0, Vector3(1, 0, 20)), "no second hit inside the invulnerability")
	for k in int(ceil(T.HERO_HURT_INVULN / DT)) + 1:
		hero.step(DT, Vector2.ZERO)
	check(hero.take_hit(8.0, Vector3(1, 0, 20)), "hits land again after the invulnerability")
	_finish("dash")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
