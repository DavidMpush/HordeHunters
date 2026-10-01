extends SceneTree

# Weapon base (stage 3, Teil B §1): the shotgun runs on weapons/weapon.gd
# without a change in behaviour (tests/shotgun.gd stays the reference), the
# base helpers (rank from the build, power, cooldown by fire rate, arc and
# circle queries, knockback by mass, bosses immune, damage booked per source),
# and the hero catalogue (heroes.gd, Session.config.hero_id with fallbacks).

const T := preload("res://scripts/core/tuning.gd")
const WEAPON := preload("res://scripts/weapons/weapon.gd")
const SHOTGUN := preload("res://scripts/weapons/shotgun.gd")
const HEROES := preload("res://scripts/hero/heroes.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
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
	_shotgun_on_base()
	_helpers()
	_finish("weapon_base")


func _catalogue() -> void:
	for id in HEROES.ids():
		var data: Dictionary = HEROES.get_hero(id)
		for key in ["name", "title", "weapon", "hp", "armor", "model_script", "portrait"]:
			check(data.has(key), "hero %s has %s" % [id, key])
		check(ResourceLoader.exists(String(data.model_script)), "model script of %s exists" % id)
		check(PROGRESS.WEAPONS.has(String(data.weapon)), "weapon of %s is in the catalogue" % id)
	check(String(HEROES.get_hero("boxer").name) == "Brine" and float(HEROES.get_hero("boxer").hp) == 130.0 and is_equal_approx(float(HEROES.get_hero("boxer").armor), 0.1), "Brine: 130 LP, 10 % armor")
	check(String(HEROES.get_hero("nobody").name) == "Brann", "unknown id falls back to Brann")
	# Session config (static class of Teil A, read dynamically with fallbacks).
	var session: Variant = load(HEROES.SESSION_PATH) if ResourceLoader.exists(HEROES.SESSION_PATH) else null
	if session != null:
		var keep: Dictionary = session.config
		session.config = {}
		check(HEROES.current_id() == "brann", "no config: Brann")
		session.config = {"hero_id": "boxer"}
		check(HEROES.current_id() == "boxer", "config hero_id boxer")
		session.config = {"hero_id": "ghost"}
		check(HEROES.current_id() == "brann", "unknown hero_id: Brann")
		session.config = keep
	else:
		check(HEROES.current_id() == "brann", "without a session: Brann")


func _shotgun_on_base() -> void:
	var gun: Node = battle.shotgun
	var shotgun_script: Script = SHOTGUN
	check(shotgun_script.get_base_script() == WEAPON, "shotgun extends weapon.gd")
	check(gun.get_script() == SHOTGUN and String(gun.id) == "shotgun" and String(gun.source) == "Schrotflinte", "Brann carries the shotgun (id, source)")
	check(battle.weapons.size() == 1 and battle.weapons[0] == gun, "one weapon at the start")
	check(String(battle.progress.start_weapon) == "shotgun" and battle.progress.weapons == ["shotgun"], "build starts with the shotgun")
	check(hero.hero_id == "brann" and is_equal_approx(hero.max_health, T.HERO_HP) and hero.armor() == 0.0, "Brann: 100 LP, no armor")
	# Damage of a shot is booked on "Schrotflinte" through the base.
	gun.reset()
	battle.run.reset()
	var i: int = horde.spawn(T.Kind.BROCKEN, hero.position + Vector3(0, 0, -2.0))
	horde._hp[i] = 100000.0
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	check(float(battle.run.damage_by_source.get("Schrotflinte", 0.0)) > 0.0, "shotgun damage booked on Schrotflinte")
	check(String(battle.run.damage_source) == "Schrotflinte", "damage source restored after the shot")
	horde.clear()


func _helpers() -> void:
	var w: Node = WEAPON.new()
	w.id = "axe"
	w.hero = hero
	w.horde = horde
	w.run = battle.run
	battle.add_child(w)
	check(w.max_shells() == 0 and w.reload_progress() < 0.0, "no shells on a plain weapon (HUD)")
	# Rank and power from the build; rank_override wins.
	var progress: RefCounted = battle.progress
	check(w.rank() == 0, "rank 0 without a pick")
	progress.apply(progress.weapon_entry("axe", "rare"))
	check(w.rank() == 1 and is_equal_approx(w.power(), 1.5), "rare NEUE WAFFE: rank 1, power 1.5 (%d, %.2f)" % [w.rank(), w.power()])
	check(is_equal_approx(w.power_factor(), 1.125), "power factor 0.75 + 0.25 x 1.5")
	w.rank_override = 4
	check(w.rank() == 4, "rank override")
	w.rank_override = -1
	# Cooldown shrinks with the fire rate stat.
	var base: float = w.cooldown_time(2.0)
	progress.apply(progress.stat_entry("firerate", "common"))
	check(w.cooldown_time(2.0) < base, "fire rate shortens cooldowns")
	# Arc and circle queries.
	var at: Vector3 = hero.position
	var front: int = horde.spawn(T.Kind.WICHTEL, at + Vector3(0, 0, -1.5))
	var side: int = horde.spawn(T.Kind.WICHTEL, at + Vector3(1.5, 0, 0))
	var far: int = horde.spawn(T.Kind.WICHTEL, at + Vector3(0, 0, -5.0))
	var arc: Array = w.enemies_in_arc(at, Vector3(0, 0, -1), 2.2, deg_to_rad(50.0))
	check(arc.has(front) and not arc.has(side) and not arc.has(far), "arc: front in, side and far out")
	var circle: Array = w.enemies_in_circle(at, 2.0)
	check(circle.has(front) and circle.has(side) and not circle.has(far), "circle: both near ones in")
	# Knockback by mass: light, medium (champion = heavy), boss never.
	var brocken: int = horde.spawn(T.Kind.BROCKEN, at + Vector3(-3, 0, 0))
	check(w.knock_by_mass(front, [9.0, 5.0, 1.0]) == 9.0, "light knock")
	check(w.knock_by_mass(brocken, [9.0, 5.0, 1.0]) == 1.0, "heavy knock")
	check(w.knock_by_mass(WEAPON.BOSS_SLOT, [9.0, 5.0, 1.0]) == 0.0, "boss: no knock")
	horde._mass[T.Kind.RENNER] = T.Mass.MEDIUM
	var renner: int = horde.spawn(T.Kind.RENNER, at + Vector3(3, 0, 3))
	check(w.knock_by_mass(renner, [9.0, 5.0, 1.0]) == 5.0, "medium knock")
	horde._mass[T.Kind.RENNER] = T.Mass.LIGHT
	# apply() books on the weapon's source and restores the run's source.
	w.source = "Wurfaxt"
	var hits := {front: {"damage": 3.0, "dir": Vector3.FORWARD, "knock": 0.0}}
	w.apply(hits)
	check(float(battle.run.damage_by_source.get("Wurfaxt", 0.0)) == 3.0, "damage booked on Wurfaxt")
	horde.clear()
	w.queue_free()


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
