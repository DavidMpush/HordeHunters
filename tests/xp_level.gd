extends SceneTree

# XP and level (stage 2, Teil A §1-2) in the real scene: the level curve, gems
# drop on kills and stay until collected, the magnet radius, XP arrives on
# pick-up, a level-up pauses the run with a 1-of-3 choice, several level-ups
# chain, and the XP bar share follows.

const T := preload("res://scripts/core/tuning.gd")
const RUN := preload("res://scripts/core/run.gd")
const LOOT := preload("res://scripts/progression/loot.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Level curve (Mawlings: 60 + 25 L + 6 L², first level-up 60 XP).
	check(RUN.xp_needed(1) == 60, "first level-up costs 60 XP (%d)" % RUN.xp_needed(1))
	check(RUN.xp_needed(2) == 91 and RUN.xp_needed(3) == 134, "curve 91, 134 (%d, %d)" % [RUN.xp_needed(2), RUN.xp_needed(3)])
	check(RUN.xp_needed(10) == 60 + 25 * 9 + 6 * 81, "curve at level 10")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	_quiet(battle)
	var hero: Node3D = battle.hero
	var run: RefCounted = battle.run
	var loot: Node3D = battle.loot
	var horde: Node3D = battle.horde
	check(run.level == 1 and run.xp == 0.0, "run starts at level 1 without XP")
	# A kill drops a gem that hops out and stays (hero far away, gun quiet).
	var far := hero.position + Vector3(0, 0, -9)
	var i: int = horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(far, 0.5))
	horde._appear[i] = 1.0
	var spot: Vector3 = horde.position_of(i)
	horde.hurt(i, 1000.0, Vector3.FORWARD)
	check(loot.count_of(LOOT.Sort.XP) == 1, "a kill drops one XP gem (%d)" % loot.count_of(LOOT.Sort.XP))
	check(is_equal_approx(loot.total(LOOT.Sort.XP), 4.0), "Wichtel gem worth 4 XP")
	_jam(battle)
	for k in 300:
		battle.tick(DT)
	check(loot.count() == 1 and loot.lying == 1, "the gem stays on the ground (10 s)")
	check(run.xp == 0.0, "no XP before pick-up")
	var gem: Vector3 = loot.nearest_lying(spot, 5.0)
	check(gem.is_finite() and gem.distance_to(Vector3(spot.x, gem.y, spot.z)) < 2.0, "gem lies near the kill")
	# Outside the magnet (2.5 m): nothing. Inside: it flies in and counts.
	hero.position = Vector3(gem.x + 3.2, 0.0, gem.z)
	for k in 20:
		battle.tick(DT)
		hero.position = Vector3(gem.x + 3.2, 0.0, gem.z)
	check(loot.lying == 1, "3.2 m away: the gem stays")
	hero.position = Vector3(gem.x + 2.2, 0.0, gem.z)
	for k in 40:
		battle.tick(DT)
		hero.position = Vector3(gem.x + 2.2, 0.0, gem.z)
	check(loot.count() == 0, "2.2 m away: the magnet pulls the gem in")
	check(is_equal_approx(run.xp, 4.0), "4 XP credited (%.1f)" % run.xp)
	check(battle.hud.get("battle") != null and is_equal_approx(run.xp_share(), 4.0 / 60.0), "XP bar share 4/60")
	# Gem sizes by value: Brocken gems are big.
	check(LOOT.tier_of(4.0) == 0 and LOOT.tier_of(20.0) == 2, "gem tiers small/big")
	# Level-up: the choice opens and the run stands still.
	run.add_xp(56.0)
	check(run.level == 2 and run.pending_levels == 1, "60 XP -> level 2, one pending choice")
	check(is_equal_approx(run.xp, 0.0), "XP carries into the new level")
	battle.tick(DT)
	check(battle.paused(), "the level-up choice pauses the run")
	check(battle.progression.choice.is_open(), "choice screen open")
	check(battle.progression.offers.size() == 3, "three cards (%d)" % battle.progression.offers.size())
	var elapsed: float = run.elapsed
	var at := hero.position
	var w: int = horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(at + Vector3(0, 0, -6), 0.5))
	horde._appear[w] = 1.0
	var enemy_at: Vector3 = horde.position_of(w)
	for k in 30:
		battle.tick(DT)
	check(is_equal_approx(run.elapsed, elapsed), "time stops while choosing")
	check(horde.position_of(w).distance_to(enemy_at) < 0.001, "enemies freeze while choosing")
	check(hero.position.distance_to(at) < 0.001, "hero freezes while choosing")
	battle.progression.choose(0)
	check(not battle.paused() and run.pending_levels == 0, "choosing resumes the run")
	battle.tick(DT)
	check(run.elapsed > elapsed, "time runs again")
	# Several level-ups at once chain their choices.
	run.add_xp(float(RUN.xp_needed(2) + RUN.xp_needed(3)) + 1.0)
	check(run.level == 4 and run.pending_levels == 2, "two level-ups at once (level %d, pending %d)" % [run.level, run.pending_levels])
	battle.tick(DT)
	check(battle.paused(), "first of two choices")
	battle.progression.choose(1)
	check(battle.paused() and run.pending_levels == 1, "second choice follows")
	battle.progression.choose(2)
	check(not battle.paused() and run.pending_levels == 0, "both choices taken")
	check(battle.progress.picks.size() == 3, "three picks logged (%d)" % battle.progress.picks.size())
	# Keyboard: 1-3 choose.
	run.add_xp(float(RUN.xp_needed(4)))
	battle.tick(DT)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	battle.progression.choice._input(key)
	check(not battle.paused(), "key 2 picks a card")
	# XP bonus stat multiplies picked-up XP.
	battle.progress.ranks["xp"] = 1
	battle.progress.units["xp"] = 2.0
	battle.progress._cache.clear()
	var before: float = run.xp_total
	loot.drop_xp(hero.position + Vector3(0.5, 0, 0), 10.0)
	for k in 30:
		battle.tick(DT)
	check(is_equal_approx(run.xp_total - before, 10.0 * 1.16), "XP bonus +16 %% (%.2f)" % (run.xp_total - before))
	# Restart: level, XP and gems reset.
	loot.drop_xp(hero.position + Vector3(8, 0, 0), 5.0)
	battle.restart()
	check(run.level == 1 and run.xp == 0.0 and run.pending_levels == 0, "restart resets level and XP")
	check(loot.count() == 0, "restart clears the gems")
	check(battle.progress.picks.is_empty(), "restart clears the build")
	_finish("xp_level")


func _quiet(battle: Node) -> void:
	battle.sfx.enabled = false


func _jam(battle: Node) -> void:
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 1000.0


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
