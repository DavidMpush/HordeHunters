extends SceneTree

# Fists of Brine the boxer (stage 3, Teil B §3): auto-target within 2.2 m,
# combo cycle jab -> cross -> uppercut, arcs (+-50 deg, uppercut wider),
# knockback by mass (uppercut moves medium enemies, bosses never), the 3-frame
# hitstop on a landed uppercut, the track (wider arcs, faster combo, shockwave,
# life steal, Hammerfaust), damage booked on "Fäuste", hero numbers.

const T := preload("res://scripts/core/tuning.gd")
const FISTS := preload("res://scripts/weapons/fists.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []
var battle: Node
var hero: Node3D
var horde: Node3D
var fists: Node


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
	battle.sfx.enabled = false
	battle.set_hero("boxer")
	hero = battle.hero
	horde = battle.horde
	fists = battle.shotgun
	_hero_numbers()
	_targeting()
	_combo_cycle()
	_arcs()
	_knockback()
	_boss_immune()
	_hitstop()
	_track()
	_finish("fists")


func _reset() -> void:
	horde.clear()
	fists.reset()
	fists.rank_override = -1
	hero.position = Vector3.ZERO
	hero.invulnerable = 0.0
	hero.dead = false
	hero.health = hero.max_health
	battle.hitstop_frames = 0


func _spawn(kind: int, at: Vector3, hp := 100000.0) -> int:
	var i: int = horde.spawn(kind, at)
	horde._hp[i] = hp
	horde._appear[i] = 1.0
	return i


func _hero_numbers() -> void:
	check(hero.hero_id == "boxer" and hero.model.get_script() == load("res://scripts/hero/boxer_model.gd"), "Brine with the boxer model")
	check(is_equal_approx(hero.max_health, 130.0) and is_equal_approx(hero.health, 130.0), "130 LP (%.0f)" % hero.max_health)
	check(fists.get_script() == FISTS and battle.weapons.size() == 1 and String(battle.progress.start_weapon) == "fists", "fists are the own weapon")
	var before: float = hero.health
	hero.take_hit(10.0, hero.position + Vector3(1, 0, 0))
	check(is_equal_approx(before - hero.health, 9.0), "10 %% armor: 10 -> 9 (%.2f)" % (before - hero.health))
	_reset()


func _targeting() -> void:
	_reset()
	var far := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -3.4))
	for k in 30:
		fists.step(DT)
	check(fists.strikes == 0 and fists.target < 0, "nothing within 2.2 m: no strike")
	horde._pos[far] = Vector3(1.6, 0, -1.2)
	for k in 30:
		fists.step(DT)
	check(fists.strikes >= 1, "enemy within 2.2 m: strikes")
	var to := Vector3(1.6, 0, -1.2).normalized()
	check(absf(wrapf(hero.aim_yaw - atan2(to.x, to.z), -PI, PI)) < 0.05, "the boxer turns to the target")
	# A Brocken counts from its body edge (reach + radius).
	_reset()
	_spawn(T.Kind.BROCKEN, Vector3(0, 0, -2.9))
	for k in 20:
		fists.step(DT)
	check(fists.strikes >= 1, "a Brocken in reach of its body edge is punched")


func _combo_cycle() -> void:
	_reset()
	_spawn(T.Kind.BROCKEN, Vector3(0, 0, -1.8))
	var steps: Array[int] = []
	var times: Array[float] = []
	var t := 0.0
	var last := 0
	while t < 3.0:
		fists.step(DT)
		horde._pos[0] = Vector3(0, 0, -1.8)
		if fists.strikes > last:
			last = fists.strikes
			steps.append(int(fists.last_strike.step))
			times.append(t)
		t += DT
	check(steps.size() >= 6, "at least two combos in 3 s (%d strikes)" % steps.size())
	if steps.size() >= 6:
		check(steps.slice(0, 6) == [0, 1, 2, 0, 1, 2], "jab, cross, uppercut, repeat (%s)" % str(steps.slice(0, 6)))
		var cycle := times[3] - times[0]
		var wanted := 3.0 * FISTS.WIND + FISTS.GAPS[0] + FISTS.GAPS[1] + FISTS.RECOVER
		check(absf(cycle - wanted) < 5.0 * DT, "combo cycle %.2f s (want %.2f)" % [cycle, wanted])
		check(times[1] - times[0] < times[3] - times[2], "recovery after the uppercut is the longest pause")
	check(fists.combos >= 2, "combos counted")
	check(float(battle.run.damage_by_source.get("Fäuste", 0.0)) > 0.0, "damage booked on Fäuste")


func _arcs() -> void:
	_reset()
	var inside := _spawn(T.Kind.WICHTEL, Vector3(sin(deg_to_rad(40.0)), 0, -cos(deg_to_rad(40.0))) * 1.6)
	var wide := _spawn(T.Kind.WICHTEL, Vector3(sin(deg_to_rad(72.0)), 0, -cos(deg_to_rad(72.0))) * 1.6)
	var behind := _spawn(T.Kind.WICHTEL, Vector3(0, 0, 1.6))
	horde.step(DT)
	fists.aim = Vector3(0, 0, -1)
	fists.target = -1
	fists.strike(0)
	var hits: Dictionary = fists.last_strike.hits
	check(is_equal_approx(float(fists.last_strike.half), deg_to_rad(50.0)), "jab arc +-50 deg")
	check(hits.has(inside) and not hits.has(wide) and not hits.has(behind), "jab: 40 deg hit, 72 deg and behind missed")
	fists.strike(2)
	hits = fists.last_strike.hits
	check(float(fists.last_strike.half) > deg_to_rad(50.0) and float(fists.last_strike.reach) > fists.reach(), "uppercut: wider and longer")
	check(hits.has(inside) and hits.has(wide) and not hits.has(behind), "uppercut: 72 deg hit too, behind missed")
	var dmg_jab := float(FISTS.DAMAGE[0])
	check(float(FISTS.DAMAGE[2]) >= 1.7 * dmg_jab, "uppercut hits much harder than a jab")
	# A jab lands on the two nearest bodies only; the uppercut takes all.
	_reset()
	var row: Array[int] = []
	for k in 4:
		row.append(_spawn(T.Kind.WICHTEL, Vector3(-0.9 + 0.6 * k, 0, -1.0 - 0.25 * k)))
	horde.step(DT)
	fists.aim = Vector3(0, 0, -1)
	fists.target = -1
	fists.strike(0)
	check(fists.last_strike.hits.size() == 2 and fists.last_strike.hits.has(row[0]) and fists.last_strike.hits.has(row[1]), "jab: the 2 nearest of 4 (%d)" % fists.last_strike.hits.size())
	fists.strike(2)
	check(fists.last_strike.hits.size() == 4, "uppercut: all 4")


func _knockback() -> void:
	_reset()
	var light := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -1.4))
	var heavy := _spawn(T.Kind.BROCKEN, Vector3(0.0, 0, -2.4))
	horde._mass[T.Kind.RENNER] = T.Mass.MEDIUM
	var medium := _spawn(T.Kind.RENNER, Vector3(-0.6, 0, -1.4))
	horde.step(DT)
	fists.aim = Vector3(0, 0, -1)
	fists.target = -1
	fists.strike(0)
	var jab_light: float = horde.knock_of(light).length()
	check(jab_light > 0.3 and jab_light < 2.0, "jab: small knock on light (%.1f)" % jab_light)
	horde._knock[light] = Vector3.ZERO
	horde._knock[medium] = Vector3.ZERO
	horde._knock[heavy] = Vector3.ZERO
	fists.strike(2)
	var k_light: float = horde.knock_of(light).length()
	var k_medium: float = horde.knock_of(medium).length()
	var k_heavy: float = horde.knock_of(heavy).length()
	check(k_light >= 6.0 and k_light > T.KNOCK_LIGHT, "uppercut: light enemies fly, more than a shotgun blast (%.1f m/s)" % k_light)
	check(k_medium >= 3.5 and k_medium < k_light and k_medium > T.KNOCK_MEDIUM, "uppercut: medium enemies knocked too (%.1f)" % k_medium)
	check(k_heavy < 2.0 and k_heavy < k_medium, "uppercut: heavy only nudged (%.1f)" % k_heavy)
	horde._mass[T.Kind.RENNER] = T.Mass.LIGHT


func _boss_immune() -> void:
	_reset()
	var boss: Node3D = battle.pressure.spawn_boss()
	check(boss != null, "boss spawned")
	if boss == null:
		return
	boss.state = boss.State.CHASE
	boss.position = Vector3(0, 0, -2.6)
	var health: float = boss.health
	fists.aim = Vector3(0, 0, -1)
	fists.target = -1
	fists.strike(2)
	check(boss.health < health, "uppercut damages the boss")
	check(boss.position.distance_to(Vector3(0, 0, -2.6)) < 0.001, "boss is not moved")
	battle.pressure.reset()
	horde.boss = null


func _hitstop() -> void:
	_reset()
	_spawn(T.Kind.BROCKEN, Vector3(0, 0, -1.8))
	var stops: Array[int] = []
	var t := 0.0
	var elapsed_before := 0.0
	var frozen := 0
	while t < 2.0 and fists.combos < 1:
		elapsed_before = battle.run.elapsed
		battle.tick(DT)
		horde._pos[0] = Vector3(0, 0, -1.8)
		if battle.hitstop_frames > 0:
			stops.append(int(fists.last_strike.step))
			break
		t += DT
	check(stops == [2], "hitstop only after the uppercut (%s)" % str(stops))
	check(battle.hitstop_frames == FISTS.HITSTOP_FRAMES and FISTS.HITSTOP_FRAMES >= 2 and FISTS.HITSTOP_FRAMES <= 3, "2-3 frames of hitstop")
	var at: float = battle.run.elapsed
	for k in FISTS.HITSTOP_FRAMES:
		battle.tick(DT)
		if is_equal_approx(battle.run.elapsed, at):
			frozen += 1
	check(frozen == FISTS.HITSTOP_FRAMES, "the run stands still during the hitstop (%d)" % frozen)
	battle.tick(DT)
	check(battle.run.elapsed > at, "and goes on afterwards")
	# A whiffed uppercut does not stop the game.
	_reset()
	fists.aim = Vector3(0, 0, -1)
	fists.strike(2)
	check(battle.hitstop_frames == 0, "no hitstop when the uppercut misses")


func _track() -> void:
	_reset()
	fists.rank_override = 2
	check(is_equal_approx(fists.half_angle(0), deg_to_rad(65.0)) and is_equal_approx(fists.half_angle(2), deg_to_rad(100.0)), "level 2: wider arcs")
	fists.rank_override = 3
	check(fists.gap_after(0) < float(FISTS.GAPS[0]) * 0.85, "level 3: faster combo")
	# Rank 3: uppercut shockwave reaches an enemy behind the boxer.
	fists.rank_override = 4
	var back := _spawn(T.Kind.WICHTEL, Vector3(0, 0, 2.2))
	fists.aim = Vector3(0, 0, -1)
	var hp: float = horde.health_of(back)
	fists.strike(2)
	check(horde.health_of(back) < hp, "level 4: shockwave hits behind")
	# Rank 4: life steal on a landed strike.
	fists.rank_override = 5
	hero.health = 50.0
	fists.aim = Vector3(0, 0, 1)
	fists.strike(0)
	check(hero.health > 50.0, "level 5: life steal (%.1f)" % hero.health)
	# Rank 5: a fourth strike all round.
	fists.rank_override = 6
	check(fists.combo_length() == 4, "level 6: four strikes")
	var behind := _spawn(T.Kind.WICHTEL, Vector3(0, 0, 1.5))
	fists.aim = Vector3(0, 0, -1)
	fists.strike(3)
	check(fists.last_strike.hits.has(behind), "Hammerfaust hits all round")
	# A fists card raises the build level by one.
	fists.rank_override = -1
	var progress: RefCounted = battle.progress
	var card: Dictionary = progress.own_weapon_entry("epic")
	check(String(card.type) == "weapon" and String(card.id) == "fists" and int(card.to) == 2, "fists card (level 1 -> 2, epic only adds power)")
	progress.apply(card)
	check(fists.rank() == 2, "build level 2 seen by the fists")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
