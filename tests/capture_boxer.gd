extends SceneTree

# Review frames of stage 3 Teil B (heroes and the fists):
#   preview_heroes_lineup.png   - Brann and Brine side by side (close-up, lab)
#   preview_boxer_poses.png     - Brine: guard, jab, cross, uppercut, Hammerfaust
#   preview_boxer_jab.png       - game camera: the jab lands in a Wichtel pack
#   preview_boxer_uppercut.png  - game camera: uppercut hit frame (hitstop)
#   preview_boxer_after.png     - a few frames later: bodies flying, dust
#   preview_boxer_close.png     - closer camera on the uppercut
# Run with a window (never --headless): tools/capture.ps1 -Only boxer

const T := preload("res://scripts/core/tuning.gd")
const BRANN := preload("res://scripts/hero/brann_model.gd")
const BOXER := preload("res://scripts/hero/boxer_model.gd")
const DT := 1.0 / 60.0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(720, 1280)
	await _lab_frames()
	await _game_frames()
	print("Saved boxer review frames")
	quit()


func _lab_frames() -> void:
	var lab: Node = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab)
	for k in 3:
		await process_frame
	lab.set_process(false)
	var battle: Node = lab.get_node("Battle")
	battle.auto = false
	battle.sfx.enabled = false
	battle.director_enabled = false
	battle.set_hero("boxer")
	var camera: Camera3D = lab.get_node("Camera3D")
	var hero: Node3D = battle.hero
	hero.position = Vector3(1.0, 0, 0)
	var brann: Node3D = BRANN.new()
	lab.add_child(brann)
	brann.position = Vector3(-1.0, 0, 0)
	camera.position = Vector3(0.0, 3.4, 7.6)
	camera.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
	for k in 20:
		hero.model.aim_yaw = 0.25
		brann.aim_yaw = -0.25
		hero.model.animate(DT)
		brann.animate(DT)
		await process_frame
	await _save("preview_heroes_lineup")
	brann.queue_free()
	# Poses (one model, frames stitched): guard, jab, cross, uppercut wind,
	# uppercut, Hammerfaust. Toon parts use instance uniforms (limited buffer),
	# so no crowd of models here.
	hero.position = Vector3.ZERO
	camera.position = Vector3(1.6, 3.3, 4.6)
	camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	var sheet := Image.create(720, 1280, false, Image.FORMAT_RGBA8)
	var model: Node3D = hero.model
	var poses := [[-1, 0.0], [0, 0.04], [1, 0.04], [-2, 0.0], [2, 0.045], [3, 0.05]]
	for k in poses.size():
		model.punch_step = -1
		model.punch_time = 99.0
		model.wind = 0.0
		model.snap_aim(0.5)
		model.aim_yaw = 0.5
		for f in 3:
			model.animate(DT)
		var step: int = poses[k][0]
		if step == -2:
			model.wind_punch(2)
			for f in 5:
				model.animate(DT)
		elif step >= 0:
			model.punch(step)
			model.animate(float(poses[k][1]))
		await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		var cell := Rect2i(Vector2i(150, 300), Vector2i(420, 497))
		var small := shot.get_region(cell)
		small.resize(360, 426)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i((k % 2) * 360, (k / 2) * 426))
	sheet.save_png("res://previews/preview_boxer_poses.png")
	print("saved preview_boxer_poses")
	lab.queue_free()
	await process_frame


func _game_frames() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	battle.set_hero("boxer")
	var hero: Node3D = battle.hero
	var fists: Node = battle.shotgun
	for k in 10:
		_tick(battle)
		await process_frame
	var at := hero.position
	# A pack in front (north-east) and a few at the side.
	var aim := Vector3(0.4, 0, -1).normalized()
	for k in 7:
		var spot := at + aim * (1.6 + 0.5 * float(k % 2)) + Vector3(float(k) * 0.55 - 1.6, 0, float(k % 3) * 0.25)
		battle.horde.spawn(T.Kind.WICHTEL, battle.arena.safe_spawn(spot, 0.45))
	battle.horde.spawn(T.Kind.RENNER, battle.arena.safe_spawn(at + Vector3(2.0, 0, 0.4), 0.45))
	battle.horde.spawn(T.Kind.BROCKEN, battle.arena.safe_spawn(at + aim * 3.4, 0.9))
	battle.horde.step(DT)
	for i in battle.horde.count():
		battle.horde._appear[i] = 1.0
		battle.horde._hp[i] = 26.0 if battle.horde.kind_of(i) != T.Kind.BROCKEN else 400.0
	# Jab: first strike frame.
	for k in 60:
		_tick(battle)
		await process_frame
		if fists.strikes >= 1:
			break
	for k in 2:
		_tick(battle)
		await process_frame
	await _save("preview_boxer_jab")
	# Uppercut hit frame.
	for k in 120:
		_tick(battle)
		await process_frame
		if fists.strikes >= 3:
			break
	await _save("preview_boxer_uppercut")
	var camera: Camera3D = main.get_node("Camera3D")
	for k in 8:
		_tick(battle)
		await process_frame
	await _save("preview_boxer_after")
	# Closer look at the next uppercut.
	main.set_process(false)
	var target: int = fists.combos
	for k in 240:
		_tick(battle)
		var c := hero.position + Vector3(0, 9.5, 6.5)
		camera.position = c
		camera.look_at(hero.position + Vector3(0, 0.8, 0), Vector3.UP)
		await process_frame
		if fists.combos > target and fists.step_index == 0:
			break
		if fists.last_strike.get("step", -1) == 2 and fists.cooldown_left > 0.4:
			break
	await _save("preview_boxer_close")
	main.queue_free()
	await process_frame


func _tick(battle: Node) -> void:
	# Hits would make the hero blink (invisible frames): keep him just out of reach.
	battle.hero.invulnerable = 0.11
	battle.tick(DT)
	if battle.paused():
		battle.progression.choose(0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
	print("saved ", name)
