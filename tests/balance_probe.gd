extends SceneTree

# Balance probe (not in the suite): a bot plays the real scene headless.
#   -- idle   stands still (must die quickly)
#   -- kite   flees from the nearest enemy, dashes when one is close
# Prints survival time, kills, hits. Godot --headless --script res://tests/balance_probe.gd -- kite

const T := preload("res://scripts/core/tuning.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	var mode := "idle"
	for arg in OS.get_cmdline_user_args():
		mode = arg
	var hero: Node3D = battle.hero
	var t := 0.0
	var dt := 1.0 / 30.0
	var angle := 0.0
	var max_alive := 0
	while t < 360.0 and not battle.run.dead:
		var move := Vector2.ZERO
		if mode == "kite":
			# Run away from the nearest enemy, sideways a bit; dash when crowded.
			var i: int = battle.horde.nearest_index(hero.position, 6.0)
			if i >= 0:
				var away: Vector3 = (hero.position - battle.horde.position_of(i)).normalized()
				var side := Vector3(-away.z, 0, away.x)
				var dir := (away + side * 0.6).normalized()
				move = Vector2(dir.x, dir.z)
				if hero.position.distance_to(battle.horde.position_of(i)) < 2.0 and hero.dash_ready():
					hero.dash(dir)
			else:
				angle += dt * 0.4
				move = Vector2(cos(angle), sin(angle)) * 0.5
		battle.controls.movement_pointer = 7
		battle.controls.movement_vector = move
		battle.tick(dt)
		max_alive = maxi(max_alive, battle.horde.count())
		t += dt
		if int(t * 30.0) % 900 == 0:
			print("t=%d alive=%d kills=%d hp=%.0f shots=%d" % [int(t), battle.horde.count(), battle.run.kills, hero.health, battle.run.shots])
	print("BOT %s survived %.1f s kills %d max_alive %d hits %d dmg %.0f" % [mode, battle.run.elapsed, battle.run.kills, max_alive, hero.hits_taken, hero.damage_taken])
	quit()
