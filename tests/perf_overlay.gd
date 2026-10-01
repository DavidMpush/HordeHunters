extends SceneTree

# Etappe 4 Teil D: FPS overlay, quality tiers on phones, adaptive governor,
# merged Brann model, effect warm-up (headless; the frame costs themselves are
# measured by tests/perf_bench.gd in a window).

const QUALITY := preload("res://scripts/world/quality.gd")
const GOVERNOR := preload("res://scripts/world/quality_governor.gd")
const BRANN := preload("res://scripts/hero/brann_model.gd")
const PROFILE := preload("res://scripts/core/profile.gd")
const SESSION := preload("res://scripts/core/session.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Setting: default on, a known key of the profile.
	var profile := PROFILE.new()
	check(profile.flag("show_fps"), "show_fps defaults to on")
	profile.set_setting("show_fps", false)
	check(not profile.flag("show_fps"), "show_fps can be switched off")

	# Tiers: S25-like device HIGH; phones render 3D below screen resolution,
	# the desktop look stays.
	var s25 := {"os": "Android", "cores": 8, "adapter": "Adreno (TM) 830", "memory_mb": 11000, "screen": Vector2i(1080, 2340)}
	check(QUALITY.choose_tier(s25) == QUALITY.Tier.HIGH, "S25 -> HIGH")
	QUALITY.force_mobile = false
	check(is_equal_approx(float(QUALITY.settings(QUALITY.Tier.HIGH).scaling_3d_scale), 1.0), "desktop HIGH keeps scale 1.0")
	QUALITY.force_mobile = true
	check(is_equal_approx(float(QUALITY.settings(QUALITY.Tier.HIGH).scaling_3d_scale), 0.8), "phone HIGH renders 3D at 80 %")
	check(float(QUALITY.settings(QUALITY.Tier.LOW).scaling_3d_scale) < float(QUALITY.settings(QUALITY.Tier.MEDIUM).scaling_3d_scale), "phone LOW below MEDIUM")
	QUALITY._detected = QUALITY.Tier.HIGH
	QUALITY.adaptive_tier = -1
	check(QUALITY.adaptive_enabled(), "adaptive on a phone with the automatic tier")

	# Governor: slow render frames step down, slow script frames do not.
	var governor: Node = GOVERNOR.new()
	root.add_child(governor)
	_feed(governor, 30.0, 4.0, 8.0)
	check(QUALITY.current_tier() == QUALITY.Tier.MEDIUM and governor.steps.size() == 1, "30 ms frames (render-bound) -> MITTEL (%s)" % str(governor.steps))
	_feed(governor, 30.0, 26.0, 8.0)
	check(QUALITY.current_tier() == QUALITY.Tier.MEDIUM, "script-bound 30 ms frames keep the tier")
	_feed(governor, 12.0, 4.0, 8.0)
	check(QUALITY.current_tier() == QUALITY.Tier.MEDIUM, "fast frames never step down")
	check(governor.frame_at(0) > 0.0 and governor.filled > 0, "governor keeps a frame history")
	QUALITY.set_override(QUALITY.Tier.HIGH)
	check(not QUALITY.adaptive_enabled() and QUALITY.current_tier() == QUALITY.Tier.HIGH, "override disables the governor")
	QUALITY.set_override(-1)
	QUALITY.adaptive_tier = -1
	QUALITY.force_mobile = false
	governor.queue_free()

	# Brann: one merged mesh per animated pivot, flash on the shared material.
	var brann: Node3D = BRANN.new()
	root.add_child(brann)
	var meshes := brann.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() >= 6 and meshes.size() <= 12, "Brann merged into %d meshes (was ~60)" % meshes.size())
	check(brann.gun.get_child_count() > 0 and brann.hand_shells.get_child_count() > 0, "gun and hand shells keep their own meshes")
	brann.set_hurt(1.0)
	brann.animate(1.0 / 60.0)
	var material := (meshes[0] as MeshInstance3D).material_override as ShaderMaterial
	check(material != null and float(material.get_shader_parameter("hit_flash")) > 0.5, "hit flash on the shared material")
	brann.queue_free()

	# The run: overlay in the HUD layer, text lines, effect warm-up.
	SESSION.config = {"hero_id": "brann"}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 5:
		await process_frame
	var battle: Node = main.get_node("Battle")
	var overlay: Node = battle.hud_layer.get_node_or_null("FpsOverlay")
	check(overlay != null, "FPS overlay in the HUD layer")
	if overlay != null:
		overlay._refresh_text()
		check(overlay.lines.size() == 4 and String(overlay.lines[0]).contains("FPS"), "overlay text: %s" % " | ".join(overlay.lines))
		check(overlay.governor != null and overlay.governor.get_child_count() == 2, "overlay owns the governor with its probes")
	battle.effects.warm_up(Vector3(0, -3, 0))
	check(battle.effects.active_count() == 0, "warm-up draws no game effects")
	main.queue_free()
	await process_frame
	if failures == 0:
		print("PASS perf_overlay")
	else:
		print("FAIL perf_overlay: %d" % failures)
	quit(1 if failures > 0 else 0)


## Feeds 4 s of frames of `ms` with `script` ms script time (after the settle).
func _feed(governor: Node, ms: float, script: float, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		governor._record(ms)
		governor.script_ms[(governor.head - 1 + governor.HISTORY) % governor.HISTORY] = script
		t += ms / 1000.0
