extends SceneTree

# Result after death (stage 2, Teil A §4): time, kills, level, the build
# ("DEIN BUILD": picks with rank, best rarity) and damage per source; the
# NOCHMAL button sits below the panel inside the screen; NOCHMAL resets the
# progression.

const T := preload("res://scripts/core/tuning.gd")
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
	battle.sfx.enabled = false
	var hero: Node3D = battle.hero
	var run: RefCounted = battle.run
	var progress: RefCounted = battle.progress
	var progression: Node = battle.progression
	# A small fight: the shotgun deals damage and kills.
	for k in 6:
		var i: int = battle.horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(hero.position + Vector3(-1.5 + 0.6 * k, 0, -4.0), 0.4))
		battle.horde._appear[i] = 1.0
	for k in 90:
		battle.tick(DT)
		if battle.paused():
			progression.choose(0)
	check(run.kills >= 3, "kills counted (%d)" % run.kills)
	# Picks through the real choice: two level-ups and a cocoon.
	for pick in [progress.stat_entry("damage", "rare"), progress.weapon_entry("shotgun", "epic"), progress.stat_entry("damage", "common")]:
		run.add_xp(float(run.xp_needed(run.level)))
		battle.tick(DT)
		progression.offers = [pick]
		progression.choose(0)
	progression.open_chest("free", [progress.relic_entry("lockstein")])
	progression.choose(0)
	var build: Array = progress.build_summary()
	check(build.size() == 3, "build lists 3 items (%d)" % build.size())
	var by_id := {}
	for item in build:
		by_id[String(item.id)] = item
	check(by_id.has("damage") and int(by_id.damage.rank) == 2 and String(by_id.damage.rarity) == "rare", "Schaden rank 2, best rarity rare")
	check(by_id.has("shotgun") and String(by_id.shotgun.type) == "weapon" and int(by_id.shotgun.rank) == 2, "Schrotflinte level 2 (one card, epic)")
	check(by_id.has("lockstein") and String(by_id.lockstein.type) == "relic" and int(by_id.lockstein.rank) == 1, "relic Lockstein x1")
	for item in build:
		check(String(item.get("icon", "")) != "" and String(item.get("name", "")) != "", "build item has icon and name")
	# Death -> result.
	var level: int = run.level
	hero.take_hit(10000.0, hero.position + Vector3(1, 0, 0))
	for k in 45:
		battle.tick(DT)
	check(run.dead and battle.hud.result_visible(), "result after death")
	check(run.level == level and level >= 4, "level kept on the result (%d)" % level)
	check(float(run.damage_by_source.get("Schrotflinte", 0.0)) > 0.0, "damage per source: Schrotflinte")
	check(is_equal_approx(float(run.damage_dealt), _sum(run.damage_by_source)), "sources add up to the damage dealt")
	var button: Rect2 = battle.hud.result_button_rect()
	var screen: Vector2 = battle.hud.size
	check(Rect2(Vector2.ZERO, screen).encloses(button), "NOCHMAL inside the screen")
	check(button.position.y >= battle.hud._result_top() + 152.0 + battle.hud.result_panel_height(), "NOCHMAL below the result panel")
	# Gems dropped after death are not collected; the run stays dead.
	battle.loot.drop_xp(hero.position, 50.0)
	var xp: float = run.xp_total
	for k in 30:
		battle.tick(DT)
	check(run.xp_total == xp and not battle.paused(), "no XP or choice after death")
	# NOCHMAL resets the progression.
	var tap := InputEventScreenTouch.new()
	tap.index = 0
	tap.pressed = true
	tap.position = button.get_center()
	battle.controls._input(tap)
	check(not run.dead and run.level == 1 and run.gold == 0, "NOCHMAL: level 1, no gold")
	check(progress.build_summary().is_empty() and progress.rerolls == 1, "NOCHMAL: empty build, reroll back")
	check(is_equal_approx(hero.max_health, T.HERO_HP) and hero.health == hero.max_health, "NOCHMAL: base health")
	check(run.damage_by_source.is_empty(), "NOCHMAL: damage sources cleared")
	_finish("result")


func _sum(values: Dictionary) -> float:
	var total := 0.0
	for key in values:
		total += float(values[key])
	return total


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
