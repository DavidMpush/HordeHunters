extends SceneTree

# A boxer run starts (stage 3, Teil B §3 + §5): Session.config.hero_id =
# "boxer" before main.tscn loads -> Brine with the boxer model, 130 LP, the
# fists as own weapon and build start; 40 s of a real fight (director on,
# every level-up takes the first card) deal fists damage and kill; NOCHMAL
# keeps the hero. The config is restored at the end.

const T := preload("res://scripts/core/tuning.gd")
const HEROES := preload("res://scripts/hero/heroes.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session: Variant = load(HEROES.SESSION_PATH) if ResourceLoader.exists(HEROES.SESSION_PATH) else null
	var keep: Dictionary = session.config if session != null else {}
	if session != null:
		session.config = {"hero_id": "boxer"}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.sfx.enabled = false
	battle.progression.auto_pick = true
	if session == null:
		battle.set_hero("boxer")
	var hero: Node3D = battle.hero
	check(hero.hero_id == "boxer", "Brine from the run config (%s)" % hero.hero_id)
	check(hero.model.get_script() == load("res://scripts/hero/boxer_model.gd") and hero.model.name == "Brine", "boxer model")
	check(is_equal_approx(hero.max_health, 130.0) and is_equal_approx(hero.health, 130.0), "130 LP")
	check(String(battle.shotgun.id) == "fists" and battle.weapons.size() == 1, "fists as own weapon")
	check(battle.progress.weapons == ["fists"] and battle.progress.start_weapon == "fists", "build starts with the fists")
	# A real fight.
	var t := 0.0
	var angle := 0.0
	while t < 40.0 and not battle.run.dead:
		# Walk slow circles so the horde comes into reach.
		angle += DT * 0.35
		battle.controls.movement_pointer = 7
		battle.controls.movement_vector = Vector2(cos(angle), sin(angle)) * 0.35
		battle.tick(DT)
		battle.arena.sync(hero.position)
		t += DT
	check(battle.run.kills >= 5, "the boxer kills (%d)" % battle.run.kills)
	check(float(battle.run.damage_by_source.get("Fäuste", 0.0)) > 0.0, "damage per source: Fäuste")
	check(not battle.run.damage_by_source.has("Schrotflinte"), "no shotgun damage on the boxer")
	check(battle.shotgun.strikes > 10, "many strikes (%d)" % battle.shotgun.strikes)
	var summary := "kills %d, level %d, Fäuste %.0f dmg" % [battle.run.kills, battle.run.level, float(battle.run.damage_by_source.get("Fäuste", 0.0))]
	# NOCHMAL keeps Brine and his numbers.
	battle.restart()
	check(hero.hero_id == "boxer" and is_equal_approx(hero.max_health, 130.0) and String(battle.shotgun.id) == "fists", "NOCHMAL: still Brine")
	if session != null:
		session.config = keep
	if failures.is_empty():
		print("PASS boxer_run (%s)" % summary)
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
