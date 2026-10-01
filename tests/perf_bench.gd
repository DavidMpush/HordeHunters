extends SceneTree

# Performance bench of stage 1 (tools/perf.ps1; a window, never --headless for
# frame times). Worst case: 250 enemies of all three kinds pressing on Brann on
# the real map, the gun firing, effects and HUD on. The hero cannot die.
#   -- scene=worst secs=20     PERF line with frame times and script cost
#   -- vsync=off               unlocked frame rate (real frame cost)
#   -- steps=600               headless: only the script cost of battle.tick
# Values are desktop values of this machine, not Android values.

const T := preload("res://scripts/core/tuning.gd")

var args := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).split("=")
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 5:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.director_enabled = false
	battle.sfx.enabled = false
	var hero: Node3D = battle.hero
	hero.max_health = 1.0e9
	hero.health = 1.0e9
	_fill(battle)
	var headless := DisplayServer.get_name() == "headless"
	if headless or args.has("steps"):
		battle.auto = false
		var steps := int(args.get("steps", "600"))
		var horde: Node3D = battle.horde
		horde.usec_step = 0
		horde.usec_draw = 0
		if args.get("off", "") == "walls":
			horde.walls_enabled = false
		var t0 := Time.get_ticks_usec()
		var worst := 0
		for k in steps:
			var s := Time.get_ticks_usec()
			battle.tick(1.0 / 60.0)
			_refill(battle)
			worst = maxi(worst, Time.get_ticks_usec() - s)
		var total := Time.get_ticks_usec() - t0
		print("PERF steps enemies=%d tick_ms=%.3f horde_ms=%.3f draw_ms=%.3f worst_tick_ms=%.2f" % [horde.count(), total / 1000.0 / steps, horde.usec_step / 1000.0 / steps, horde.usec_draw / 1000.0 / steps, worst / 1000.0])
		quit()
		return
	var secs := float(args.get("secs", "20"))
	# vsync=off measures the real frame cost instead of the 60 Hz lock.
	if args.get("vsync", "on") == "off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	# off=hud / off=horde / off=battle: ablations (what costs the frame).
	match String(args.get("off", "")):
		"hud":
			battle.hud_layer.visible = false
			battle.hud.set_process(false)
			battle.controls.set_process(false)
		"horde":
			battle.horde.visible = false
		"battle":
			battle.horde.clear()
			battle.auto = false
			battle.hud_layer.visible = false
	# Warm-up, then measure frame times in real time.
	for k in 60:
		_refill(battle)
		await process_frame
	var frames: Array[float] = []
	var horde_before: int = battle.horde.usec_step
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(secs * 1000000.0):
		await process_frame
		if args.get("off", "") != "battle":
			_refill(battle)
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	frames.sort()
	var total := 0.0
	for f in frames:
		total += f
	var avg := total / frames.size()
	var p95: float = frames[int(frames.size() * 0.95)]
	var p99: float = frames[int(frames.size() * 0.99)]
	var horde_ms: float = (battle.horde.usec_step - horde_before) / 1000.0 / frames.size()
	print("PERF %s enemies=%d frames=%d avg_ms=%.2f fps=%.1f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f horde_ms=%.3f" % [args.get("scene", "worst"), battle.horde.count(), frames.size(), avg, 1000.0 / avg, p95, p99, frames[frames.size() - 1], horde_ms])
	quit()


func _fill(battle: Node) -> void:
	var at: Vector3 = battle.hero.position
	var k := 0
	while battle.horde.count() < T.ENEMY_CAP and k < 2000:
		var angle := float(k) * 2.39996
		var r := 3.0 + fposmod(float(k) * 0.7548, 1.0) * 16.0
		var kind := T.Kind.WICHTEL
		if k % 4 == 0:
			kind = T.Kind.RENNER
		if k % 25 == 0:
			kind = T.Kind.BROCKEN
		var spot: Vector3 = battle.arena.safe_spawn(at + Vector3(cos(angle) * r, 0, sin(angle) * r), 1.0)
		battle.horde.spawn(kind, spot)
		k += 1


## Keeps the count at the cap while the gun kills (worst case stays worst).
func _refill(battle: Node) -> void:
	if battle.horde.count() < T.ENEMY_CAP - 10:
		_fill(battle)
