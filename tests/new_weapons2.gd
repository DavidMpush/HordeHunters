extends SceneTree

# New weapons of stage 4 (Teil B): Doppelpistolen and Blitzkette. Both come as
# NEUE WAFFE cards for every hero (no signature), are created in the fight by
# the card, grow over their 5 steps, deal and book damage in a short fight, and
# the menu's Arsenal switch keeps them out of a run.

const T := preload("res://scripts/core/tuning.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
const NEW := ["pistols", "lightning"]
const DT := 1.0 / 60.0

var failures: Array[String] = []
var battle: Node
var hero: Node3D
var horde: Node3D


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_catalogue()
	_arsenal()
	var lab: Node = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab)
	for k in 3:
		await process_frame
	battle = lab.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	hero = battle.hero
	horde = battle.horde
	_by_card()
	_pistols()
	_pistol_levels()
	_lightning()
	_lightning_levels()
	_finish("new_weapons2")


# ---------------------------------------------------------------- catalogue

func _catalogue() -> void:
	var order: Array = PROGRESS.WEAPON_ORDER
	check(order.find("pistols") > order.find("grenade") and order.find("lightning") > order.find("grenade"), "new weapons after the grenade")
	for id in NEW:
		var d: Dictionary = PROGRESS.weapon_def(id)
		check(String(d.signature) == "" and String(d.intro) != "" and d.steps.size() == PROGRESS.MAX_LEVEL - 1, "%s: every hero, intro + 5 steps" % id)
	var ids: Array = []
	for entry in PROGRESS.arsenal_catalog():
		ids.append(String(entry.id))
	check(ids.has("pistols") and ids.has("lightning"), "both in the Arsenal")
	# Dealt to Brann and to Brine.
	for start in ["shotgun", "fists"]:
		var p: RefCounted = PROGRESS.new()
		p.set_start_weapon(start)
		var seen := {}
		for k in 300:
			for entry in p.roll_level_offers():
				if NEW.has(String(entry.id)):
					seen[String(entry.id)] = true
					check(String(entry.type) == "new_weapon", "first as NEUE WAFFE")
		check(seen.size() == 2, "%s: both new weapons dealt (%s)" % [start, str(seen.keys())])


func _arsenal() -> void:
	var p: RefCounted = PROGRESS.new()
	p.set_disabled(["pistols", "lightning"])
	var dealt := 0
	for k in 300:
		for entry in p.roll_level_offers():
			if NEW.has(String(entry.id)):
				dealt += 1
	check(dealt == 0, "switched off in the Arsenal: never dealt (%d)" % dealt)
	check(not p.may_take("pistols") and not p.may_take("lightning"), "may_take says no")
	p.set_disabled(["pistols"])
	var lightning := 0
	for k in 300:
		for entry in p.roll_level_offers():
			check(String(entry.id) != "pistols", "pistols stay out")
			if String(entry.id) == "lightning":
				lightning += 1
	check(lightning > 0, "the other one still comes")


# ---------------------------------------------------------------- in the fight

func _by_card() -> void:
	for id in NEW:
		battle.restart()
		battle.run.add_xp(float(battle.run.xp_needed(battle.run.level)))
		battle.tick(DT)
		check(battle.paused(), "level-up open")
		battle.progression.offers = [battle.progress.weapon_entry(id, "rare")]
		battle.progression.choose(0)
		battle.tick(DT)
		var weapon: Node = battle.weapon_of(id)
		check(weapon != null and weapon.rank() == 1 and is_equal_approx(weapon.power(), 1.5), "%s: NEUE WAFFE creates it on level 1, power 1.5" % id)
		check(weapon != null and weapon.get_script() == battle.WEAPON_SCRIPTS[id], "%s: right script" % id)


func _setup(id: String, rank: int) -> Node:
	battle.restart()
	battle.director_enabled = false
	for k in rank:
		battle.progress.apply(battle.progress.weapon_entry(id, "common"))
	battle.sync_weapons()
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 1000.0
	hero.position = Vector3.ZERO
	return battle.weapon_of(id)


func _spawn(kind: int, at: Vector3, hp := 100000.0) -> int:
	var i: int = horde.spawn(kind, at)
	horde._hp[i] = hp
	horde._appear[i] = 1.0
	return i


func _run_weapon(weapon: Node, seconds: float) -> void:
	var spots: Array[Vector3] = []
	for i in horde.count():
		spots.append(horde.position_of(i))
	var t := 0.0
	while t < seconds:
		hero.invulnerable = 1.0
		battle.shotgun.reload_left = 1000.0
		weapon.step(DT)
		for i in mini(spots.size(), horde.count()):
			horde._pos[i] = spots[i]
		t += DT


func _lost(i: int) -> float:
	return 100000.0 - horde.health_of(i)


func _source(name: String) -> float:
	return float(battle.run.damage_by_source.get(name, 0.0))


func _pistols() -> void:
	var guns := _setup("pistols", 1)
	var near := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -4.0))
	var second := _spawn(T.Kind.WICHTEL, Vector3(5.0, 0, 2.0))
	var far := _spawn(T.Kind.WICHTEL, Vector3(-12.0, 0, 0))
	horde.step(DT)
	_run_weapon(guns, 1.0)
	check(guns.shots >= 2, "pistols fire (%d shots in 1 s)" % guns.shots)
	check(_lost(near) > 0.0 and _lost(second) > 0.0 and _lost(far) == 0.0, "alternating: nearest and second nearest, not beyond 10 m (%.0f, %.0f, %.0f)" % [_lost(near), _lost(second), _lost(far)])
	check(_source("Doppelpistolen") > 0.0, "damage booked on Doppelpistolen")
	check(horde.knock_of(near).length() > 0.5, "light enemies get a small knock")
	# Kill a weak runner in a short fight.
	horde.clear()
	var weak := _spawn(T.Kind.RENNER, Vector3(0, 0, -6.0), 15.0)
	horde.step(DT)
	_run_weapon(guns, 1.5)
	check(weak >= 0 and horde.total_kills == 1 and horde.count() == 0, "a weak runner falls to the pistols")


func _pistol_levels() -> void:
	var one := _setup("pistols", 1)
	var cd1: float = one.cooldown()
	var dmg1: float = one.damage()
	var reach1: float = one.reach()
	check(one.pierce() == 0 and one.bullets() == 1, "level 1: one bullet, no pierce")
	# Level 3: a bullet goes through the first body.
	var three := _setup("pistols", 3)
	var front := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -3.0))
	var back := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -5.0))
	horde.step(DT)
	three.shoot(Vector3(0, 0, -1))
	check(three.pierce() == 1 and _lost(front) > 0.0 and _lost(back) > 0.0, "level 3: pierces one (%.0f, %.0f)" % [_lost(front), _lost(back)])
	check(three.cooldown() < cd1 * 0.85, "level 2+: fires faster")
	var six := _setup("pistols", 6)
	check(six.bullets() == 2 and six.pierce() == 2 and six.reach() > reach1 * 1.2 and six.damage() > dmg1 * 2.0, "level 6: 2 bullets, pierce 2, further, harder")


func _lightning() -> void:
	var bolt := _setup("lightning", 1)
	var chain: Array[int] = []
	for k in 6:
		chain.append(_spawn(T.Kind.WICHTEL, Vector3(0.3 * float(k % 2), 0, -3.0 - 2.5 * k)))
	var lone := _spawn(T.Kind.WICHTEL, Vector3(9.0, 0, 6.0))
	horde.step(DT)
	_run_weapon(bolt, 0.1)
	check(bolt.casts == 1, "a discharge when an enemy is in reach")
	var hit := 0
	for i in chain:
		if _lost(i) > 0.0:
			hit += 1
	check(hit == 1 + bolt.JUMPS, "level 1: first target + 3 jumps (%d)" % hit)
	check(_lost(lone) == 0.0, "no jump to a far enemy")
	check(_lost(chain[0]) > _lost(chain[3]), "each jump hits a little softer")
	check(_source("Blitzkette") > 0.0, "damage booked on Blitzkette")
	_run_weapon(bolt, 1.0)
	check(bolt.casts == 1, "cooldown before the next discharge")
	_run_weapon(bolt, 0.8)
	check(bolt.casts == 2, "second discharge after %.1f s" % bolt.COOLDOWN)
	# Interrupts a wind-up.
	var striker := _setup("lightning", 1)
	var w := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -2.0))
	horde.step(DT)
	horde._state[w] = horde.State.WINDUP
	_run_weapon(striker, 0.05)
	check(horde.state_of(w) == horde.State.STAGGER, "a bolt interrupts a wind-up")


func _lightning_levels() -> void:
	var one := _setup("lightning", 1)
	var jumps1: int = one.jumps()
	var range1: float = one.jump_range()
	var dmg1: float = one.damage()
	var cd1: float = one.cooldown()
	var four := _setup("lightning", 4)
	# Fork: a star of enemies round the first target.
	var hub := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -3.0))
	for k in 6:
		var a := TAU * float(k) / 6.0
		_spawn(T.Kind.WICHTEL, Vector3(sin(a) * 2.6, 0, -3.0 + cos(a) * 2.6 - 0.0))
	horde.step(DT)
	_run_weapon(four, 0.05)
	check(four.jumps() == jumps1 + 1 and four.jump_range() > range1 * 1.15 and four.damage() > dmg1 * 1.25 and four.cooldown() < cd1, "levels 2-3: +1 jump, longer jumps, harder, faster")
	check(four.last_hits.size() == 7 and four.last_hits.has(hub), "level 4: the fork reaches the whole star (%d)" % four.last_hits.size())
	var six := _setup("lightning", 6)
	check(six.jumps() == jumps1 + 3 and six.chain_count() == 2, "level 6: +3 jumps, two chains")
	# Two separate groups: the second chain finds the other one.
	for k in 3:
		_spawn(T.Kind.WICHTEL, Vector3(-0.4 + 0.4 * k, 0, -3.0))
		_spawn(T.Kind.WICHTEL, Vector3(-0.4 + 0.4 * k, 0, 7.0))
	horde.step(DT)
	_run_weapon(six, 0.05)
	check(six.chains == 2 and six.last_hits.size() == 6, "two chains cover both groups (%d)" % six.last_hits.size())


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
