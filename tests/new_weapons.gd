extends SceneTree

# Extra weapons (stage 3, Teil B §2 + §4): NEUE WAFFE cards only while one of
# the 4 weapon slots is free, then only rank-ups; the boxer gets the fists
# track instead of the shotgun; picks create the weapon in the fight and a new
# run drops it; Wurfaxt, Schwert-Wirbel and Granate each hit, book their
# damage on their own source and grow with the rank (and rarity power).

const T := preload("res://scripts/core/tuning.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
const EXTRAS := ["axe", "sword", "grenade"]
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
	_offers()
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
	_in_fight()
	_axe()
	_sword()
	_grenade()
	_finish("new_weapons")


# ---------------------------------------------------------------- offers

func _offers() -> void:
	var p: RefCounted = PROGRESS.new()
	var fresh := 0
	for k in 200:
		for entry in p.roll_level_offers():
			if String(entry.type) == "new_weapon":
				fresh += 1
				check(int(entry.from) == 0 and int(entry.to) == 1, "NEUE WAFFE goes 0 -> 1")
				check(EXTRAS.has(String(entry.id)), "Brann: new weapons are axe, sword, grenade (never the fists)")
	check(fresh >= 40, "NEUE WAFFE offered while slots are free (%d)" % fresh)
	# Fill the slots: shotgun + 3 extras = 4.
	for id in EXTRAS:
		p.apply(p.weapon_entry(id, "common"))
	check(p.weapons.size() == PROGRESS.WEAPON_SLOTS and p.free_weapon_slots() == 0, "4 weapons fill the slots")
	var ups := 0
	for k in 200:
		for entry in p.roll_level_offers():
			check(String(entry.type) != "new_weapon", "no NEUE WAFFE with full slots")
			if String(entry.type) == "weapon":
				ups += 1
				check(p.has_weapon(String(entry.id)), "upgrades only for owned weapons")
	check(ups > 20, "upgrades still offered (%d)" % ups)
	# A fifth weapon cannot be forced in; the fists stay Brine's.
	var q: RefCounted = PROGRESS.new()
	q.apply(q.weapon_entry("fists", "common"))
	check(not q.has_weapon("fists"), "Brann cannot take the fists")
	q.set_start_weapon("fists")
	q.apply(q.weapon_entry("axe", "common"))
	q.apply(q.weapon_entry("sword", "common"))
	q.apply(q.weapon_entry("shotgun", "common"))
	q.apply(q.weapon_entry("grenade", "common"))
	check(q.weapons == ["fists", "axe", "sword", "shotgun"], "boxer build: fists + 3, no fifth (%s)" % str(q.weapons))
	# Brine: the shotgun is a normal new weapon, upgraded like every other one.
	var b: RefCounted = PROGRESS.new()
	b.set_start_weapon("fists")
	var own := 0
	var gun_new := 0
	for k in 120:
		for entry in b.roll_level_offers():
			if String(entry.id) == "fists":
				own += 1
				check(String(entry.type) == "weapon", "fists only as upgrade")
			if String(entry.id) == "shotgun":
				gun_new += 1
				check(String(entry.type) == "new_weapon", "shotgun only as NEUE WAFFE while not owned")
	check(own >= 25, "fists upgrades offered often (%d / 120)" % own)
	check(gun_new >= 5, "Brine may take the shotgun (%d / 120)" % gun_new)
	check(b.relic_candidates().has("bleihagel") == false and b.relic_candidates().has("pulverhorn") == false, "no shotgun relics without the shotgun")
	b.apply(b.weapon_entry("shotgun", "rare"))
	check(b.weapon_rank("shotgun") == 1 and is_equal_approx(b.weapon_power("shotgun"), 1.5) and b.relic_candidates().has("bleihagel"), "Brine took the shotgun: level 1, power 1.5, its relics open")
	var up: Dictionary = b.weapon_entry("shotgun", "common")
	check(String(up.type) == "weapon" and int(up.to) == 2 and String(up.label) == "+1 Kugel", "shotgun upgrade card for Brine")
	b.reset(5)
	check(b.weapons == ["fists"] and b.start_weapon == "fists", "reset keeps the own weapon only")
	# Arsenal: switched-off weapons never come as new weapons.
	var d: RefCounted = PROGRESS.new()
	d.set_start_weapon("fists")
	d.set_disabled(["shotgun", "grenade", "fists"])
	for k in 120:
		for entry in d.roll_level_offers():
			check(not (String(entry.id) in ["shotgun", "grenade"]), "disabled weapons are never dealt")
	d.reset(7)
	check(d.has_weapon("fists") and d.may_take("fists"), "the start weapon stays even if switched off")
	# Rarity like stats: a legendary upgrade adds 3 power units.
	var r: RefCounted = PROGRESS.new()
	r.apply(r.weapon_entry("axe", "common"))
	r.apply(r.weapon_entry("axe", "legendary"))
	check(r.weapon_rank("axe") == 2 and is_equal_approx(r.weapon_power("axe"), 4.0), "level +1, power + rarity factor (%.1f)" % r.weapon_power("axe"))
	var summary: Array = r.build_summary()
	check(summary.size() == 1 and String(summary[0].type) == "weapon" and int(summary[0].rank) == 2 and String(summary[0].rarity) == "legendary", "build lists the axe once, level 2, best rarity")


# ---------------------------------------------------------------- in the fight

func _in_fight() -> void:
	var progress: RefCounted = battle.progress
	battle.run.add_xp(60.0)
	battle.tick(DT)
	check(battle.paused(), "level-up open")
	battle.progression.offers = [progress.weapon_entry("sword", "common")]
	battle.progression.choose(0)
	battle.tick(DT)
	check(battle.weapons.size() == 2 and battle.weapon_of("sword") != null, "NEUE WAFFE creates the sword in the fight")
	battle.restart()
	check(battle.weapons.size() == 1 and battle.weapon_of("sword") == null and battle.weapons[0] == battle.shotgun, "a new run drops the extra weapon")


func _setup(id: String, rank: int, rarity := "common") -> Node:
	battle.restart()
	battle.director_enabled = false
	var progress: RefCounted = battle.progress
	for k in rank:
		progress.apply(progress.weapon_entry(id, rarity))
	battle.sync_weapons()
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 1000.0
	hero.position = Vector3.ZERO
	return battle.weapon_of(id)


func _spawn(kind: int, at: Vector3) -> int:
	var i: int = horde.spawn(kind, at)
	horde._hp[i] = 100000.0
	horde._appear[i] = 1.0
	return i


func _run_weapon(weapon: Node, seconds: float, pin: Dictionary = {}) -> void:
	var t := 0.0
	while t < seconds:
		hero.invulnerable = 1.0
		battle.shotgun.reload_left = 1000.0
		weapon.step(DT)
		for i in pin:
			if i < horde.count():
				horde._pos[i] = pin[i]
		t += DT


func _source(name: String) -> float:
	return float(battle.run.damage_by_source.get(name, 0.0))


func _axe() -> void:
	var axe: Node = _setup("axe", 1)
	check(axe != null and axe.axe_count() == 1, "Wurfaxt rank 1: one axe")
	var a := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -4.0))
	var b := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -5.5))
	horde.step(DT)
	_run_weapon(axe, 1.3, {a: Vector3(0, 0, -4.0), b: Vector3(0, 0, -5.5)})
	var low_a: float = 100000.0 - horde.health_of(a)
	var low_b: float = 100000.0 - horde.health_of(b)
	check(axe.throws >= 1 and low_a > 0.0 and low_b > 0.0, "the axe goes through both (%.0f, %.0f)" % [low_a, low_b])
	check(low_a >= 2.0 * axe.DAMAGE * 0.99, "hit out and back (%.0f)" % low_a)
	check(axe.axes.is_empty(), "the axe came back")
	check(_source("Wurfaxt") > 0.0, "damage booked on Wurfaxt")
	var axe5: Node = _setup("axe", 5)
	check(axe5.axe_count() == 3 and axe5.damage() > axe.DAMAGE * 1.9 and axe5.out_range() > axe.OUT_RANGE and axe5.cooldown() < axe.COOLDOWN, "rank 5: 3 axes, double damage, further, faster")


func _sword() -> void:
	var sword: Node = _setup("sword", 1)
	var near := _spawn(T.Kind.WICHTEL, Vector3(1.5, 0, 0))
	var back := _spawn(T.Kind.WICHTEL, Vector3(-1.0, 0, 1.6))
	var heavy := _spawn(T.Kind.BROCKEN, Vector3(0, 0, -2.2))
	var far := _spawn(T.Kind.WICHTEL, Vector3(0, 0, 6.0))
	horde.step(DT)
	_run_weapon(sword, 0.1)
	check(sword.spins == 1, "spins as soon as enemies are near")
	check(sword.last_hits.has(near) and sword.last_hits.has(back) and sword.last_hits.has(heavy) and not sword.last_hits.has(far), "hits all round, not far")
	check(horde.knock_of(near).length() > 5.0 and horde.knock_of(heavy).length() < 0.01, "knock: light flies, heavy stays")
	check(_source("Schwert-Wirbel") > 0.0, "damage booked on Schwert-Wirbel")
	_run_weapon(sword, 2.0)
	check(sword.spins == 1, "no second spin before the cooldown (2.5 s)")
	_run_weapon(sword, 0.6)
	check(sword.spins == 2, "second spin after 2.5 s")
	var r1: float = sword.radius()
	var d1: float = float(sword.last_hits[near].damage) if sword.last_hits.has(near) else 0.0
	var sword5: Node = _setup("sword", 5)
	_spawn(T.Kind.WICHTEL, Vector3(1.5, 0, 0))
	horde.step(DT)
	_run_weapon(sword5, 0.5)
	check(sword5.radius() > r1 * 1.2 and sword5.spins == 2, "rank 5: bigger and spins twice (%d)" % sword5.spins)
	check(sword5.damage() > d1 * 1.8, "rank 5: about double damage")


func _grenade() -> void:
	var grenade: Node = _setup("grenade", 1)
	var pack: Array[int] = []
	for k in 5:
		pack.append(_spawn(T.Kind.WICHTEL, Vector3(-0.6 + 0.3 * k, 0, -6.0 + 0.2 * float(k % 2))))
	var lone := _spawn(T.Kind.WICHTEL, Vector3(4.0, 0, 2.0))
	horde.step(DT)
	_run_weapon(grenade, 0.05)
	check(grenade.throws == 1 and grenade.grenades.size() == 1, "a grenade is in the air")
	if grenade.grenades.size() == 1:
		var to: Vector3 = grenade.grenades[0].to
		check(to.distance_to(Vector3(0, 0, -6.0)) < 1.0, "thrown at the group, not the lone one")
	_run_weapon(grenade, grenade.FLIGHT + 0.05)
	check(grenade.explosions == 1, "it explodes after the flight")
	var hit := 0
	for i in pack:
		if horde.health_of(i) < 100000.0:
			hit += 1
	check(hit == 5 and horde.health_of(lone) == 100000.0, "blast hits the group (%d / 5), not the lone one" % hit)
	check(_source("Granate") > 0.0, "damage booked on Granate")
	var base_radius: float = grenade.radius()
	var base_damage: float = grenade.damage()
	var base_cooldown: float = grenade.cooldown()
	var grenade5: Node = _setup("grenade", 5, "rare")
	check(grenade5.count() == 2 and grenade5.radius() > base_radius and grenade5.damage() > base_damage * 2.0 and grenade5.cooldown() < base_cooldown, "rank 5 (rare): 2 grenades, bigger, harder, faster")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
