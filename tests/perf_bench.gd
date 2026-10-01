extends SceneTree

# Stage 4 Teil D: reproducible stress bench of the real game scene.
# Run in a WINDOW (never --headless, nothing would render): tools/perf.ps1.
#   -- hero=brann|boxer   hero of the run (default brann)
#   -- secs=30            measuring time after the warm-up
#   -- enemies=200        enemies kept alive around the hero (director off)
#   -- vsync=off          unlocked frame rate (real frame cost; default off)
#   -- quality=high|medium|low   quality tier override (default: game choice)
#   -- cache=clear        delete the shader cache first (first-run hitches)
#   -- out=res://previews/perf_brann.txt   report file
#   -- mobile=on          phone settings (3D render scale, adaptive tiers)
#   -- off=hud,fx,horde,world,overlay   ablations; hudprof=on: HUD draw parts; dmg=off
# The hero walks a slow circle, cannot die, owns every weapon (axe, sword,
# grenade on top of his own), damage numbers are on, level-ups pick at once,
# the boss spawns at half time. Per frame: frame time (ticks), process time,
# battle.tick time, draw calls, objects, primitives and what happened (first
# shot, explosion, level-up, boss, damage number ...). Spikes > 33 ms are listed
# with the events of that frame. Values are desktop values of this machine:
# for the S25 read the costs (draw calls, script ms, pixels) not the fps.

const T := preload("res://scripts/core/tuning.gd")
const SESSION := preload("res://scripts/core/session.gd")
const QUALITY := preload("res://scripts/world/quality.gd")

const EXTRA_WEAPONS := ["axe", "sword", "grenade"]
const SPIKE_MS := 33.0

var args := {}
var battle: Node
var main: Node
var frame_events: PackedStringArray = PackedStringArray()
var seen := {}
var tick_us := 0


class TickProbe extends Node:
	var bench: SceneTree
	var target: Node

	func _process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		target.tick(minf(delta, target.max_delta))
		bench.tick_us = Time.get_ticks_usec() - start


## First (priority -1000) and last (+1000) node of the process step: the time
## between them is the whole _process work (tick, HUD, map, camera).
class EdgeProbe extends Node:
	var bench: SceneTree
	var first := false

	func _process(_delta: float) -> void:
		if first:
			bench.proc_start = Time.get_ticks_usec()
		else:
			bench.proc_us = Time.get_ticks_usec() - bench.proc_start


var proc_start := 0
var proc_us := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).split("=")
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PERF needs a window (no --headless)")
		quit(1)
		return
	if args.get("cache", "") == "clear":
		_clear_shader_cache()
	var hero_id := String(args.get("hero", "brann"))
	var secs := float(args.get("secs", "30"))
	var wanted := int(args.get("enemies", "200"))
	SESSION.config = {"hero_id": hero_id}
	SESSION.profile().set_setting("damage_numbers", args.get("dmg", "on") == "on")
	SESSION.profile().set_setting("show_fps", args.get("overlay", "on") == "on")
	# mobile=on: phone settings on this machine (3D scale, adaptive tiers).
	QUALITY.force_mobile = args.get("mobile", "off") == "on"
	var tier := QUALITY.parse(String(args.get("quality", "")))
	if tier >= 0:
		QUALITY.set_override(tier)
	var size_text := String(args.get("res", "900x1600")).split("x")
	DisplayServer.window_set_size(Vector2i(int(size_text[0]), int(size_text[1])))
	var t_load := Time.get_ticks_usec()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var load_ms := (Time.get_ticks_usec() - t_load) / 1000.0
	for k in 3:
		await process_frame
	battle = main.get_node("Battle")
	battle.director_enabled = false
	battle.sfx.enabled = false
	battle.progression.auto_pick = true
	var hero: Node3D = battle.hero
	hero.max_health = 1.0e9
	hero.health = 1.0e9
	for id in EXTRA_WEAPONS:
		if not battle.progress.has_weapon(id):
			battle.progress.apply(battle.progress.weapon_entry(id, "common"))
	battle.sync_weapons()
	_connect_events()
	if args.get("vsync", "off") == "off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0 if args.get("vsync", "off") == "off" else 60
	battle.auto = false
	var probe := TickProbe.new()
	probe.bench = self
	probe.target = battle
	probe.name = "TickProbe"
	main.add_child(probe)
	for first in [true, false]:
		var edge := EdgeProbe.new()
		edge.bench = self
		edge.first = first
		edge.process_priority = -1000 if first else 1000
		root.add_child(edge)
	_ablate(String(args.get("off", "")))
	if args.get("hudprof", "") == "on":
		battle.hud.draw.connect(_profile_hud)
	var vp_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var rows: Array[Dictionary] = []
	var start := Time.get_ticks_usec()
	var last := start
	var boss_done := false
	var horde_before: int = battle.horde.usec_step
	var draw_before: int = battle.horde.usec_draw
	var levels_before: int = battle.progression.choices_taken
	var frame := 0
	while Time.get_ticks_usec() - start < int(secs * 1000000.0):
		var t := (Time.get_ticks_usec() - start) / 1000000.0
		_steer(t)
		hero.health = hero.max_health
		# Focus loss (other windows) pauses the run: the bench keeps it running.
		if battle.user_paused:
			battle.set_paused(false)
		_refill(wanted)
		if not boss_done and t > secs * 0.5:
			boss_done = true
			battle.pressure.spawn_boss()
			_event("boss_spawn")
		if battle.progression.choices_taken != levels_before:
			levels_before = battle.progression.choices_taken
			_event("level_up")
		var warm: Node = main.get_node_or_null("ShaderWarmup")
		if warm != null and warm.busy():
			_event("warmup")
		await process_frame
		var now := Time.get_ticks_usec()
		rows.append({
			"t": t,
			"ms": (now - last) / 1000.0,
			"proc": proc_us / 1000.0,
			"tick": tick_us / 1000.0,
			"gpu": RenderingServer.viewport_get_measured_render_time_gpu(vp_rid),
			"rcpu": RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
			"dc": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"obj": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"prim": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"n": battle.horde.count(),
			"ev": frame_events,
		})
		frame_events = PackedStringArray()
		last = now
		frame += 1
	var horde_ms: float = (battle.horde.usec_step - horde_before) / 1000.0 / maxf(1.0, rows.size())
	var draw_ms: float = (battle.horde.usec_draw - draw_before) / 1000.0 / maxf(1.0, rows.size())
	_report(rows, hero_id, load_ms, horde_ms, draw_ms)
	quit()


var hud_us := {}
var hud_calls := 0


## hudprof=on: times the HUD's world-anchored painters a second time inside its
## draw (doubles their drawing, so only the per-part times are meaningful).
func _profile_hud() -> void:
	var hud: Control = battle.hud
	var camera := hud.get_viewport().get_camera_3d()
	hud_calls += 1
	for part in ["_draw_vignette", "_draw_cocoon_tags", "_draw_brocken_bars", "_draw_overhead", "_draw_popups"]:
		if not hud.has_method(part):
			continue
		var s := Time.get_ticks_usec()
		if part == "_draw_vignette":
			hud.call(part)
		else:
			hud.call(part, camera)
		hud_us[part] = int(hud_us.get(part, 0)) + Time.get_ticks_usec() - s


## Ablations (what costs the frame): off=hud,fx,horde,world (comma list).
func _ablate(what: String) -> void:
	for part in what.split(",", false):
		match part:
			"hud":
				battle.hud.visible = false
				battle.hud.set_process(false)
			"fx":
				battle.effects.visible = false
			"horde":
				battle.horde.visible = false
			"world":
				main.get_node("Arena").visible = false
			"overlay":
				var overlay: Node = battle.hud_layer.get_node_or_null("FpsOverlay")
				if overlay != null:
					overlay.queue_free()


func _clear_shader_cache() -> void:
	var removed := 0
	for dir_path in ["user://shader_cache", "user://vulkan", "user://shader_cache_gles3"]:
		removed += _remove_tree(dir_path)
	print("shader cache cleared (%d files)" % removed)


func _remove_tree(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var count := 0
	for sub in dir.get_directories():
		count += _remove_tree(path.path_join(sub))
	for file in dir.get_files():
		if DirAccess.remove_absolute(path.path_join(file)) == OK:
			count += 1
	return count


func _connect_events() -> void:
	battle.horde.enemy_damaged.connect(func(_a = null, _b = null, _c = null, _d = null) -> void: _event("damage_number"))
	battle.horde.enemy_killed.connect(func(_a = null, _b = null) -> void: _event("kill"))
	battle.horde.windup_started.connect(func(_a = null, _b = null) -> void: _event("enemy_windup"))
	for weapon in battle.weapons:
		var id := String(weapon.id)
		for info in weapon.get_signal_list():
			var signal_name := String(info.name)
			if signal_name in ["hitstop_requested", "ready", "tree_entered", "tree_exiting", "tree_exited", "renamed", "child_entered_tree", "child_exiting_tree", "child_order_changed", "replacing_by", "editor_description_changed", "editor_state_changed", "script_changed", "property_list_changed"]:
				continue
			var label := "%s.%s" % [id, signal_name]
			weapon.connect(signal_name, func(_a = null, _b = null, _c = null, _d = null) -> void: _event(label))
	if battle.pressure.has_signal("boss_spawned"):
		battle.pressure.announced.connect(func(_a = null, _b = null) -> void: _event("announce"))


func _event(what: String) -> void:
	if not seen.has(what):
		seen[what] = true
		what = "FIRST " + what
	if frame_events.size() < 12 and not frame_events.has(what):
		frame_events.append(what)


## Slow circle walk (streams the map, turns the aim).
func _steer(t: float) -> void:
	var controls: Control = battle.controls
	controls.movement_pointer = 77
	controls.movement_vector = Vector2(cos(t * 0.35), sin(t * 0.35)) * 0.85


func _refill(wanted: int) -> void:
	var at: Vector3 = battle.hero.position
	var budget := 14
	var k: int = battle.horde.count()
	while battle.horde.count() < mini(wanted, T.ENEMY_CAP) and budget > 0:
		var angle := float(k) * 2.39996
		var r := 6.0 + fposmod(float(k) * 0.7548, 1.0) * 11.0
		var kind := T.Kind.WICHTEL
		if k % 4 == 0:
			kind = T.Kind.RENNER
		if k % 25 == 0:
			kind = T.Kind.BROCKEN
		var spot: Vector3 = battle.arena.safe_spawn(at + Vector3(cos(angle) * r, 0, sin(angle) * r), 1.0)
		battle.horde.spawn(kind, spot)
		k += 1
		budget -= 1


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(sorted.size() * p), 0, sorted.size() - 1)])


static func _avg(rows: Array, key: String) -> float:
	var total := 0.0
	for row in rows:
		total += float(row[key])
	return total / maxf(1.0, rows.size())


static func _max(rows: Array, key: String) -> float:
	var best := 0.0
	for row in rows:
		best = maxf(best, float(row[key]))
	return best


func _report(rows: Array[Dictionary], hero_id: String, load_ms: float, horde_ms: float, draw_ms: float) -> void:
	var times := []
	for row in rows:
		times.append(float(row.ms))
	var sorted := times.duplicate()
	sorted.sort()
	var avg := _avg(rows, "ms")
	var median := _pct(sorted, 0.5)
	var lines := PackedStringArray()
	var size := DisplayServer.window_get_size()
	var vp := root.get_visible_rect().size
	lines.append("Horde Hunters perf bench (Etappe 4 Teil D) %s" % Time.get_datetime_string_from_system())
	lines.append("hero=%s secs=%.0f frames=%d window=%dx%d quality=%s msaa=%d scale3d=%.2f adapter=%s" % [hero_id, rows.back().t if not rows.is_empty() else 0.0, rows.size(), size.x, size.y, QUALITY.tier_id(QUALITY.current_tier()), root.msaa_3d, root.scaling_3d_scale, RenderingServer.get_video_adapter_name()])
	lines.append("frame ms: avg %.2f (%.0f fps) p50 %.2f p95 %.2f p99 %.2f max %.2f" % [avg, 1000.0 / maxf(0.01, avg), median, _pct(sorted, 0.95), _pct(sorted, 0.99), _pct(sorted, 1.0)])
	lines.append("cpu ms: process avg %.2f max %.2f | battle.tick avg %.2f max %.2f | horde.step avg %.2f (draw %.2f) | render cpu avg %.2f gpu avg %.2f" % [_avg(rows, "proc"), _max(rows, "proc"), _avg(rows, "tick"), _max(rows, "tick"), horde_ms, draw_ms, _avg(rows, "rcpu"), _avg(rows, "gpu")])
	lines.append("draw calls avg %.0f max %.0f | objects avg %.0f max %.0f | primitives avg %.0f max %.0f | enemies avg %.0f" % [_avg(rows, "dc"), _max(rows, "dc"), _avg(rows, "obj"), _max(rows, "obj"), _avg(rows, "prim"), _max(rows, "prim"), _avg(rows, "n")])
	lines.append("scene load (instantiate + first frame) %.0f ms" % load_ms)
	var overlay: Node = battle.hud_layer.get_node_or_null("FpsOverlay")
	if overlay != null and overlay.get("governor") != null:
		lines.append("adaptive quality: %s, steps: %s" % ["on" if QUALITY.adaptive_enabled() else "off", ", ".join(PackedStringArray(overlay.governor.steps)) if not overlay.governor.steps.is_empty() else "none"])
	if hud_calls > 0:
		var parts := PackedStringArray()
		for part in hud_us:
			parts.append("%s %.3f" % [part, float(hud_us[part]) / 1000.0 / hud_calls])
		lines.append("hud draw ms per frame: " + ", ".join(parts))
	var spikes := 0
	for row in rows:
		if float(row.ms) > SPIKE_MS:
			spikes += 1
	lines.append("spikes > %.0f ms: %d (%.2f %% of frames)" % [SPIKE_MS, spikes, 100.0 * spikes / maxf(1.0, rows.size())])
	lines.append("")
	lines.append("first occurrences (worst frame of the 3 frames from the event, median %.2f ms):" % median)
	for index in rows.size():
		for ev in rows[index].ev:
			if not String(ev).begins_with("FIRST "):
				continue
			var worst := 0.0
			for j in range(index, mini(rows.size(), index + 4)):
				worst = maxf(worst, float(rows[j].ms))
			lines.append("  t=%6.2f s  %-28s worst %.2f ms" % [rows[index].t, String(ev).substr(6), worst])
	lines.append("")
	lines.append("spike frames (> %.0f ms, max 25; events of this and the previous frame):" % SPIKE_MS)
	var listed := 0
	for index in rows.size():
		var row: Dictionary = rows[index]
		if float(row.ms) <= SPIKE_MS or listed >= 25:
			continue
		listed += 1
		var events := PackedStringArray(row.ev)
		if index > 0:
			for ev in rows[index - 1].ev:
				events.append("prev:" + String(ev))
		lines.append("  t=%6.2f s  %.1f ms  proc %.1f tick %.1f dc %d n %d  %s" % [row.t, row.ms, row.proc, row.tick, int(row.dc), int(row.n), ", ".join(events)])
	var text := "\n".join(lines)
	print(text)
	print("PERF %s frames=%d avg_ms=%.2f fps=%.1f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f tick_ms=%.2f proc_ms=%.2f dc=%.0f obj=%.0f spikes=%d" % [hero_id, rows.size(), avg, 1000.0 / maxf(0.01, avg), _pct(sorted, 0.95), _pct(sorted, 0.99), _pct(sorted, 1.0), _avg(rows, "tick"), _avg(rows, "proc"), _avg(rows, "dc"), _avg(rows, "obj"), spikes])
	var out := String(args.get("out", "res://previews/perf_%s.txt" % hero_id))
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file != null:
		file.store_string(text + "\n")
		file.close()
