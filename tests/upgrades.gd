extends SceneTree

# Upgrades (stage 2, Teil A §2-3): a chosen card applies its effect, stat
# slots (6) and ranks (5), rarity factors, the shotgun track (pellets, pierce,
# knockback, magazine, tighter fan + range) as seen by the real shotgun, one
# reroll per run, relics (Dornenweste strikes back, booked on its own source).

const T := preload("res://scripts/core/tuning.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_unit()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	_scene(battle)
	_finish("upgrades")


# ---------------------------------------------------------------- build model

func _unit() -> void:
	var p: RefCounted = PROGRESS.new()
	check(p.stat("damage_mult") == 1.0 and p.stat("pellets_bonus") == 0.0, "neutral build")
	p.apply(p.stat_entry("damage", "common"))
	check(p.rank("damage") == 1 and is_equal_approx(p.stat("damage_mult"), 1.08), "common Schaden: +8 %")
	p.apply(p.stat_entry("damage", "rare"))
	check(p.rank("damage") == 2 and is_equal_approx(p.units_of("damage"), 2.5), "rare adds 1.5 units")
	check(is_equal_approx(p.stat("damage_mult"), 1.2), "Schaden +20 % after common + rare")
	# Rank cap 5.
	for k in 6:
		p.apply(p.stat_entry("speed", "common"))
	check(p.rank("speed") == 5, "rank capped at 5")
	check(not p.stat_candidates().has("speed"), "maxed stat no longer offered")
	# Slots: 6 different stats, then only owned ones are offered.
	for id in ["range", "maxhp", "regen", "armor"]:
		p.apply(p.stat_entry(id, "common"))
	check(p.owned_stats() == 6, "six stat slots taken (%d)" % p.owned_stats())
	for id in p.stat_candidates():
		check(p.rank(id) > 0, "full slots: only owned stats (%s)" % id)
	for k in 40:
		for entry in p.roll_level_offers():
			if entry.type == "stat":
				check(p.rank(String(entry.id)) > 0, "no 7th stat in a level offer")
	# Level offers: three distinct cards; the shotgun track shows up.
	var q: RefCounted = PROGRESS.new()
	var shotgun_seen := 0
	for k in 60:
		var offers: Array = q.roll_level_offers()
		check(offers.size() == 3, "three level cards")
		var ids := {}
		for entry in offers:
			ids[String(entry.type) + String(entry.id)] = true
			if entry.type == "shotgun":
				shotgun_seen += 1
			check(entry.type != "relic", "level-ups never offer relics")
		check(ids.size() == 3, "level cards are distinct")
	check(shotgun_seen >= 20, "shotgun track offered often (%d / 60)" % shotgun_seen)
	# Shotgun track in order; epic = +2 ranks.
	var s: RefCounted = PROGRESS.new()
	s.apply(s._shotgun_entry("common"))
	check(s.shotgun_rank == 1 and s.stat("pellets_bonus") == 1.0 and s.stat("pierce") == 0.0, "rank 1: +1 pellet")
	s.apply(s._shotgun_entry("epic"))
	check(s.shotgun_rank == 3 and s.stat("pierce") == 1.0 and is_equal_approx(s.stat("knockback_mult"), 1.5), "epic: +2 ranks (pierce, knockback)")
	s.apply(s._shotgun_entry("legendary"))
	check(s.shotgun_rank == 5 and s.stat("mag_bonus") == 1.0 and is_equal_approx(s.stat("fan_mult"), 0.7) and is_equal_approx(s.stat("range_mult"), 1.25), "rank 5: magazine, tight fan, range")
	# Rarity rolls: luck shifts the odds, floors hold.
	var low: Dictionary = PROGRESS.rarity_chances(0.0)
	var lucky: Dictionary = PROGRESS.rarity_chances(5.0)
	check(float(lucky.legendary) > float(low.legendary) and float(lucky.common) < float(low.common), "luck raises the rare tiers")
	var floored: Dictionary = PROGRESS.rarity_chances(0.0, "epic")
	check(float(floored.common) == 0.0 and float(floored.rare) == 0.0 and is_equal_approx(float(floored.epic) + float(floored.legendary), 1.0), "floor cuts lower tiers")
	# Relic effects.
	var r: RefCounted = PROGRESS.new()
	r.apply(r.relic_entry("bleihagel"))
	r.apply(r.relic_entry("pulverhorn"))
	r.apply(r.relic_entry("lockstein"))
	check(r.stat("pellets_bonus") == 2.0 and is_equal_approx(r.stat("reload_mult"), 1.15) and is_equal_approx(r.stat("magnet_mult"), 1.4), "relics feed pellets, reload, magnet")
	r.apply(r.relic_entry("bleihagel"))
	r.apply(r.relic_entry("bleihagel"))
	check(r.stacks("bleihagel") == 2, "Bleihagel stacks at most twice")
	check(not r.relic_candidates().has("bleihagel"), "maxed relic no longer offered")
	check(r.relic_candidates().size() == PROGRESS.RELICS.size() - 1, "other relics still offered")
	# Reroll: one per run.
	check(r.use_reroll() and not r.use_reroll(), "one reroll per run")


# ---------------------------------------------------------------- in the scene

func _scene(battle: Node) -> void:
	var hero: Node3D = battle.hero
	var gun: Node = battle.shotgun
	var horde: Node3D = battle.horde
	var progression: Node = battle.progression
	var progress: RefCounted = battle.progress
	check(hero.stat("damage_mult") == 1.0, "hero reads the build (neutral)")
	check(gun.pellet_count() == T.GUN_PELLETS and gun.max_shells() == T.GUN_SHELLS, "base gun: 7 pellets, 2 shells")
	# Without pierce a pellet stops at the first Wichtel of a line.
	var line := _line(battle)
	gun.reset()
	gun.fire(Vector3.FORWARD)
	check(gun.last_hits.has(line[0]) and not gun.last_hits.has(line[1]), "no pierce: the rear Wichtel is safe")
	check(gun.last_pellets.size() == T.GUN_PELLETS, "7 pellets fired")
	# Choice applies: a level-up offering the shotgun track (rank 1 -> 2 at once: rare = +1).
	battle.run.add_xp(60.0)
	battle.tick(DT)
	check(battle.paused(), "level choice open")
	progression.offers = [progress._shotgun_entry("common"), progress.stat_entry("damage", "common"), progress.stat_entry("maxhp", "rare")]
	progression.choice.offers = progression.offers
	progression.choose(0)
	check(progress.shotgun_rank == 1 and gun.pellet_count() == T.GUN_PELLETS + 1, "shotgun card: +1 pellet in the gun (%d)" % gun.pellet_count())
	line = _line(battle)
	gun.reset()
	gun.fire(Vector3.FORWARD)
	check(gun.last_pellets.size() == T.GUN_PELLETS + 1, "8 pellets fired")
	# Rank 2: pierce - the pellet goes on into the rear Wichtel.
	progress.apply(progress._shotgun_entry("common"))
	line = _line(battle)
	gun.reset()
	gun.fire(Vector3.FORWARD)
	check(gun.last_hits.has(line[0]) and gun.last_hits.has(line[1]), "pierce: front and rear Wichtel hit")
	# Rank 3: knockback x1.5 on light enemies.
	progress.apply(progress._shotgun_entry("common"))
	line = _line(battle)
	gun.reset()
	gun.fire(Vector3.FORWARD)
	var hit: Dictionary = gun.last_hits.get(line[0], {})
	check(is_equal_approx(float(hit.get("knock", -1.0)), T.KNOCK_LIGHT * 1.5), "knockback x1.5 (%.2f)" % float(hit.get("knock", -1.0)))
	# Rank 4: a third shell.
	progress.apply(progress._shotgun_entry("common"))
	gun.reset()
	check(gun.max_shells() == 3 and gun.shells == 3, "magazine: 3 shells")
	# Rank 5: tighter fan, longer reach.
	_line(battle)
	gun.fire(Vector3.FORWARD)
	var wide: float = _fan_width(gun)
	gun.reset()
	progress.apply(progress._shotgun_entry("common"))
	_line(battle)
	gun.reset()
	gun.fire(Vector3.FORWARD)
	check(_fan_width(gun) < wide * 0.8, "tighter fan (%.2f < %.2f)" % [_fan_width(gun), wide])
	check(is_equal_approx(gun.gun_range(), T.GUN_RANGE * 1.25), "range +25 %")
	# Damage stat scales pellet damage.
	horde.clear()
	var lone: int = horde.spawn(T.Kind.BROCKEN, hero.position + Vector3(0, 0, -2.5))
	horde._appear[lone] = 1.0
	gun.reset()
	gun.fire(Vector3.FORWARD)
	var base: float = float(gun.last_pellets[0].damage) if gun.last_pellets[0].index >= 0 else 0.0
	progress.apply(progress.stat_entry("damage", "epic"))
	gun.reset()
	gun.fire(Vector3.FORWARD)
	var boosted: float = float(gun.last_pellets[0].damage)
	check(base > 0.0 and is_equal_approx(boosted, base * 1.16), "Schaden epic: +16 %% pellet damage (%.2f -> %.2f)" % [base, boosted])
	# Max-LP card raises the maximum and heals by the gain.
	hero.health = 50.0
	battle.run.add_xp(float(battle.run.xp_needed(battle.run.level)))
	battle.tick(DT)
	progression.offers = [progress.stat_entry("maxhp", "common")]
	progression.choose(0)
	check(is_equal_approx(hero.max_health, T.HERO_HP + 15.0) and is_equal_approx(hero.health, 65.0), "Max-LP +15 heals 15 (%.0f / %.0f)" % [hero.health, hero.max_health])
	# Speed and armor reach the hero.
	progress.apply(progress.stat_entry("speed", "common"))
	progress.apply(progress.stat_entry("armor", "common"))
	check(is_equal_approx(hero.move_speed(), T.HERO_SPEED * 1.05), "Tempo +5 %")
	hero.invulnerable = 0.0
	var hp: float = hero.health
	hero.take_hit(10.0, hero.position + Vector3(1, 0, 0))
	check(is_equal_approx(hp - hero.health, 9.4), "Rüstung -6 %% damage (%.2f)" % (hp - hero.health))
	# Reroll in the choice: once per run.
	battle.run.add_xp(float(battle.run.xp_needed(battle.run.level)))
	battle.tick(DT)
	var first: Array = progression.offers.duplicate()
	check(progression.reroll(), "reroll works once")
	check(progression.offers.size() > 0 and progression.offers != first, "reroll deals new cards")
	check(not progression.reroll(), "second reroll refused")
	progression.choose(0)
	# Dornenweste: the attacker takes damage, booked on its own source.
	progress.apply(progress.relic_entry("dornenweste"))
	horde.clear()
	var biter: int = horde.spawn(T.Kind.BROCKEN, hero.position + Vector3(1.6, 0, 0))
	horde._appear[biter] = 1.0
	var max_hp: float = horde.health_of(biter)
	hero.invulnerable = 0.0
	gun.shells = 0
	gun.reload_left = 100.0
	hero.take_hit(5.0, horde.position_of(biter))
	battle.tick(DT)
	check(horde.count() > 0 and horde.health_of(0) <= max_hp - 19.9, "Dornenweste strikes back")
	check(float(battle.run.damage_by_source.get("Dornenweste", 0.0)) >= 19.9, "thorns damage booked as Dornenweste")
	check(float(battle.run.damage_by_source.get("Schrotflinte", 0.0)) > 0.0, "shotgun damage booked")


# Two Wichtel straight north of the hero at 2 m and 3.6 m; returns their indices.
func _line(battle: Node) -> Array:
	var horde: Node3D = battle.horde
	horde.clear()
	var at: Vector3 = battle.hero.position
	var a: int = horde.spawn(T.Kind.WICHTEL, at + Vector3(0, 0, -2.0))
	var b: int = horde.spawn(T.Kind.WICHTEL, at + Vector3(0, 0, -3.6))
	horde._appear[a] = 1.0
	horde._appear[b] = 1.0
	return [a, b]


func _fan_width(gun: Node) -> float:
	var low := INF
	var high := -INF
	for pellet in gun.last_pellets:
		low = minf(low, float(pellet.angle))
		high = maxf(high, float(pellet.angle))
	return high - low


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
