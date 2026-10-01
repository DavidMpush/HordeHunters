extends SceneTree

# Pause (stage 3, Teil A §2-3): the pause button / Esc / P / focus loss pause
# the run through battle.set_paused(); everything freezes (enemies, weapons,
# hero, time) while frames keep running; WEITER, Esc, NEUSTART; volume slider
# in the pause panel; pause over an open level-up choice; no pause when dead;
# the result screen has MENÜ next to NOCHMAL and it returns to menu.tscn.

const T := preload("res://scripts/core/tuning.gd")
const SESSION := preload("res://scripts/core/session.gd")
const SLIDERS := preload("res://scripts/ui/volume_sliders.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _key(pause: Control, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	pause._input(event)


func _snapshot(battle: Node) -> Array:
	var positions := []
	for i in battle.horde.count():
		positions.append(battle.horde.position_of(i))
	var weapon: Node = battle.shotgun
	return [positions, battle.hero.position, battle.run.elapsed, weapon.get("shells"), weapon.get("cooldown"), weapon.get("reload_left"), battle.hero.health]


func _run() -> void:
	SESSION.config = {}
	SESSION.reload_profile()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.director_enabled = false
	battle.sfx.enabled = false
	var pause: Control = main.get_node_or_null("Battle/HUD/Pause")
	check(pause != null, "pause screen exists")
	if pause == null:
		_finish("pause")
		return
	var hero: Node3D = battle.hero
	# A pack in front of the hero, the run going (battle.auto: real frames).
	for k in 8:
		var i: int = battle.horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(hero.position + Vector3(-2.0 + 0.6 * k, 0, -5.0), 0.4))
		battle.horde._appear[i] = 1.0
	for k in 20:
		await process_frame
	check(battle.run.elapsed > 0.1, "run time advances before the pause")
	var top: Rect2 = pause.pause_button_rect()
	check(pause.button_visible() and Rect2(Vector2.ZERO, pause.size).encloses(top), "pause button visible at the top")
	check(top.position.x > pause.size.x * 0.75 and top.position.y < 120.0 and top.size.x >= 76.0, "pause button top right, big enough")
	var kills_pill_end: float = battle.hud.size.x - 20.0 - battle.hud.PAUSE_SLOT
	check(kills_pill_end <= top.position.x - 8.0, "kill counter leaves room for the button")
	# Button press pauses.
	pause.tap(top.get_center())
	check(battle.user_paused and battle.paused() and pause.is_open(), "button pauses the run")
	var before := _snapshot(battle)
	for k in 30:
		await process_frame
	battle.tick(DT)
	var after := _snapshot(battle)
	check(before == after, "paused: enemies, hero, time and weapon frozen")
	check(battle.controls.blocked, "stick and dash blocked while paused")
	check(not pause.button_visible(), "pause button hidden while paused")
	# The run's numbers on the panel stay inside the screen.
	var view := Rect2(Vector2.ZERO, pause.size)
	for rect in [pause.panel_rect(), pause.resume_rect(), pause.restart_rect(), pause.menu_rect(), pause.slider_rect(0), pause.slider_rect(2)]:
		check(view.encloses(rect), "pause element inside the screen %s" % str(rect))
	# Volume slider in the pause panel.
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var row: Rect2 = pause.slider_rect(1)
	var bar: Rect2 = SLIDERS.track(row)
	pause.tap(Vector2(bar.position.x + bar.size.x * 0.4, row.get_center().y))
	check(is_equal_approx(float(SESSION.setting("volume_music")), 0.4), "music slider in the pause (%.2f)" % float(SESSION.setting("volume_music")))
	pause._end_drag()
	# WEITER resumes.
	pause.tap(pause.resume_rect().get_center())
	check(not battle.paused(), "WEITER resumes")
	var t0: float = battle.run.elapsed
	for k in 10:
		await process_frame
	check(battle.run.elapsed > t0, "time runs again after WEITER")
	# Esc / P toggle.
	_key(pause, KEY_ESCAPE)
	check(battle.user_paused, "Esc pauses")
	_key(pause, KEY_ESCAPE)
	check(not battle.user_paused, "Esc resumes")
	_key(pause, KEY_P)
	check(battle.user_paused, "P pauses")
	_key(pause, KEY_P)
	check(not battle.user_paused, "P resumes")
	# Focus loss pauses (only while the battle runs by itself).
	pause._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(battle.user_paused, "focus loss pauses")
	_key(pause, KEY_ESCAPE)
	battle.auto = false
	pause._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not battle.user_paused, "no auto pause when tests step by hand")
	battle.auto = true
	# Pause over an open level-up choice: resume returns to the choice.
	battle.run.add_xp(float(battle.run.xp_needed(battle.run.level)))
	for k in 3:
		await process_frame
	check(battle.progression.paused(), "level-up choice open")
	check(not pause.button_visible(), "no pause button over the choice")
	_key(pause, KEY_ESCAPE)
	check(battle.user_paused, "Esc pauses over the choice")
	_key(pause, KEY_ESCAPE)
	check(not battle.user_paused and battle.paused(), "after the pause the choice still holds the run")
	battle.progression.choose(0)
	check(not battle.paused(), "choice taken, run goes on")
	# NEUSTART from the pause.
	for k in 10:
		await process_frame
	var runs: int = battle.run.runs
	_key(pause, KEY_P)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	pause.tap(pause.restart_rect().get_center())
	check(not battle.user_paused and battle.run.runs == runs + 1 and battle.run.elapsed < 0.2, "NEUSTART: new run, not paused")
	# MENÜ in the pause emits menu_requested (main would change scenes).
	pause.menu_requested.disconnect(main.go_to_menu)
	var asked := [false]
	pause.menu_requested.connect(func() -> void: asked[0] = true)
	_key(pause, KEY_P)
	for k in 5:
		await process_frame
	pause.tap(pause.menu_rect().get_center())
	check(asked[0], "MENÜ in the pause asks for the menu")
	pause.menu_requested.connect(main.go_to_menu)
	_key(pause, KEY_P)
	check(not battle.user_paused, "resumed")
	# Death: no pause, the result has MENÜ beside NOCHMAL.
	var runs_before: int = SESSION.profile().runs_total
	hero.take_hit(10000.0, hero.position + Vector3(1, 0, 0))
	for k in 90:
		await process_frame
		if battle.hud.result_visible():
			break
	for k in 5:
		await process_frame
	check(battle.run.dead and battle.hud.result_visible(), "result after death")
	check(SESSION.profile().runs_total == runs_before + 1, "the finished run is recorded")
	_key(pause, KEY_P)
	check(not battle.user_paused and not pause.button_visible(), "no pause while dead")
	var again: Rect2 = battle.hud.result_button_rect()
	var menu_button: Rect2 = battle.hud.result_menu_rect()
	check(view.encloses(menu_button) and view.encloses(again), "MENÜ and NOCHMAL inside the screen")
	check(not menu_button.intersects(again) and menu_button.size.y >= 96.0, "MENÜ separate from NOCHMAL, big enough")
	check(battle.controls.result_menu_button == menu_button, "controls know the MENÜ rect")
	var tap := InputEventScreenTouch.new()
	tap.index = 0
	tap.pressed = true
	tap.position = menu_button.get_center()
	battle.controls._input(tap)
	var menu: Node = null
	for k in 30:
		await process_frame
		if current_scene != null and is_instance_valid(current_scene) and current_scene.name == "Menu":
			menu = current_scene
			break
	check(menu != null, "MENÜ on the result returns to menu.tscn")
	SESSION.config = {}
	SESSION.reload_profile()
	_finish("pause")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
