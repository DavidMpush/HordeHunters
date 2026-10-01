extends SceneTree

# Stage 2 Teil B §4 on the real map: the Moorkönig
#   - is announced and rises at 4:00 (schedule)
#   - cycles STOMP -> LEAP -> SWEEP, every attack telegraphed before damage
#   - the leap lands where the zone was shown; a hero far away gets a leap
#   - takes shotgun damage (BOSS_SLOT) but never knockback
#   - its death drops a boss cocoon + gold and starts a breather

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BOSS := preload("res://scripts/enemies/boss_king.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	var horde: Node3D = battle.horde
	var hero: Node3D = battle.hero
	var pressure: Node = battle.pressure
	main.snap_camera()
	battle.director.camera = main.get_node("Camera3D")
	await process_frame
	var start: Vector3 = hero.position
	# --- schedule: announced at 3:57, rises at 4:00, waves held back
	var t := 230.0
	var announced_at := -1.0
	while t < 241.0 and pressure.boss == null:
		pressure.step(0.1, t, true)
		if announced_at < 0.0 and pressure.boss_state == pressure.Boss.ANNOUNCED:
			announced_at = t
		t += 0.1
	check(absf(announced_at - (PT.BOSS_AT - PT.BOSS_WARNING)) < 0.15, "boss announced 3 s before 4:00 (%.1f)" % announced_at)
	check(pressure.boss != null and absf(t - PT.BOSS_AT) < 0.25, "boss rises at 4:00")
	var boss: Node3D = pressure.boss
	check(horde.boss == boss, "boss joins the shotgun queries")
	check(not boss.is_targetable(), "not targetable while rising")
	check(battle.director.density_scale < 1.0, "director density lowered while the boss lives")
	await process_frame
	# --- pattern cycle and telegraph before damage (tough hero next to him)
	hero.max_health = 100000.0
	hero.health = 100000.0
	hero.position = battle.arena.safe_spawn(boss.position + Vector3(3.2, 0, 0), 0.45)
	var hits: Array[float] = []
	var hp_before: float = hero.health
	var visible_since := -1.0
	var shown_before_hit := true
	for k in 30 * 26:
		boss.step(DT)
		hero.step(DT, Vector2.ZERO)
		if boss.zones_visible() > 0 and visible_since < 0.0:
			visible_since = boss.clock
		if hero.health < hp_before:
			hits.append(boss.clock)
			# Damage only after the matching telegraph was on screen long enough.
			if visible_since < 0.0 or boss.clock - visible_since < PT.SWEEP_WINDUP * 0.9:
				shown_before_hit = false
			hp_before = hero.health
		if boss.zones_visible() == 0:
			visible_since = -1.0
		# Stay close (no running away): back next to the boss after every attack.
		if boss.state == boss.State.RECOVER and boss.position.distance_to(hero.position) > 3.6:
			hero.position = battle.arena.safe_spawn(boss.position + (hero.position - boss.position).normalized() * 3.0, 0.45)
		if boss.attacks.size() >= 5 and boss.state == boss.State.CHASE:
			break
	var patterns: Array = []
	for attack in boss.attacks:
		patterns.append(int(attack.pattern))
	print("patterns ", patterns, " hits at ", hits)
	check(patterns.size() >= 4 and patterns.slice(0, 4) == [BOSS.Pattern.STOMP, BOSS.Pattern.LEAP, BOSS.Pattern.SWEEP, BOSS.Pattern.STOMP], "cycle STOMP, LEAP, SWEEP, STOMP")
	check(hits.size() >= 3, "a hero standing next to him gets hit (%d)" % hits.size())
	check(shown_before_hit, "every hit came after its telegraph was shown")
	var all_telegraphed := true
	for attack in boss.attacks:
		if float(attack.struck) >= 0.0 and float(attack.struck) - float(attack.shown) < PT.SWEEP_WINDUP - 0.05:
			all_telegraphed = false
	check(all_telegraphed, "every attack shown >= its wind-up before the strike")
	# --- dodge: leaving the leap zone during the telegraph avoids the damage
	hero.health = hero.max_health
	hero.invulnerable = 0.0
	_until(boss, hero, func() -> bool: return boss.state == boss.State.CHASE)
	boss.cycle_index = 1  # next: LEAP
	hero.position = battle.arena.safe_spawn(boss.position + Vector3(6.0, 0, 0), 0.45)
	_until(boss, hero, func() -> bool: return boss.state == boss.State.WINDUP)
	check(boss.pattern == BOSS.Pattern.LEAP and boss.zones_visible() == 1, "leap shows its landing zone")
	var zone: Vector3 = boss.zone_center
	check(zone.distance_to(hero.position) < 0.6, "landing zone on the hero")
	var away: Vector3 = battle.arena.safe_spawn(zone + Vector3(0, 0, PT.LEAP_RADIUS + 1.5), 0.45)
	hero.position = away
	var hp0: float = hero.health
	_until(boss, hero, func() -> bool: return boss.state == boss.State.RECOVER)
	check(boss.position.distance_to(zone) < 0.6, "the boss lands in the shown zone")
	check(hero.health == hp0, "leaving the zone in time avoids the leap")
	# A hero far away gets a leap, not a walk.
	_until(boss, hero, func() -> bool: return boss.state == boss.State.CHASE)
	boss.cycle_index = 0  # next would be STOMP
	hero.position = battle.arena.safe_spawn(boss.position + Vector3(0, 0, PT.LEAP_FAR + 3.0), 0.45)
	_until(boss, hero, func() -> bool: return boss.state == boss.State.WINDUP)
	check(boss.pattern == BOSS.Pattern.LEAP, "far hero: the boss leaps after him")
	_until(boss, hero, func() -> bool: return boss.state == boss.State.RECOVER)
	# --- shotgun damage, no knockback
	var at: Vector3 = boss.position
	var health: float = boss.health
	horde.apply_hits({horde.BOSS_SLOT: {"damage": 40.0, "dir": Vector3.RIGHT, "knock": 30.0}})
	boss.step(DT)
	check(boss.health < health, "shotgun hits hurt the boss")
	check(boss.position.distance_to(at) < 0.001, "no knockback on the boss")
	horde.clear()
	hero.position = battle.arena.safe_spawn(boss.position + Vector3(0, 0, 4.0), 0.45)
	battle.shotgun.reset()
	var h0: float = boss.health
	for k in 60:
		if boss.state == boss.State.AIR:
			break
		battle.shotgun.step(DT)
	check(boss.health < h0, "the real shotgun aims at and hits the boss (%.0f -> %.0f)" % [h0, boss.health])
	# --- death: boss cocoon, gold, breather
	boss.state = boss.State.RECOVER
	boss.timer = 5.0
	horde.apply_hits({horde.BOSS_SLOT: {"damage": 100000.0, "dir": Vector3.RIGHT}})
	check(boss.state == boss.State.DYING and not boss.is_targetable(), "boss dies")
	for k in 60:
		pressure.step(DT, 300.0, true)
	check(pressure.boss_state == pressure.Boss.DEFEATED and horde.boss == null, "boss gone after dying")
	var boss_drops: Array = pressure.drops.filter(func(d: Dictionary) -> bool: return d.kind == "boss")
	check(boss_drops.size() == 1 and int(boss_drops[0].gold) == PT.BOSS_GOLD, "boss cocoon + gold logged")
	if battle.has_method("drop_chest"):
		check(bool(boss_drops[0].chest_called), "battle.drop_chest(at, \"boss\") called")
	check(pressure.breather > 0.0 and battle.director.paused, "breather: the director pauses")
	check(pressure.banner == "SIEG!", "SIEG! banner")
	check(pressure.wave_state == 0, "no wave during the breather")
	print("boss drops ", boss_drops)
	hero.position = start
	_finish("boss")


func _until(boss: Node3D, hero: Node3D, done: Callable, limit := 600) -> void:
	for k in limit:
		if done.call():
			return
		boss.step(DT)
		hero.step(DT, Vector2.ZERO)


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
