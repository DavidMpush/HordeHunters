extends SceneTree

# Close-up review frames of the placeholder models (combat lab, flat ground):
#   preview_models_lineup.png  - Brann (aiming) with Wichtel, Renner, Brocken
#   preview_models_poses.png   - Brann reloading, enemies in wind-up
# Run with a window: tools/capture.ps1 -Only models

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 60.0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(720, 1280)
	var lab: Node = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab)
	for k in 3:
		await process_frame
	lab.set_process(false)
	var battle: Node = lab.get_node("Battle")
	battle.auto = false
	battle.sfx.enabled = false
	battle.director_enabled = false
	var camera: Camera3D = lab.get_node("Camera3D")
	var hero: Node3D = battle.hero
	hero.position = Vector3.ZERO
	camera.position = Vector3(0.5, 7.5, 6.5)
	camera.look_at(Vector3(0.5, 0.6, 0.2), Vector3.UP)
	var horde: Node3D = battle.horde
	horde.spawn(T.Kind.WICHTEL, Vector3(-2.6, 0, -1.2))
	horde.spawn(T.Kind.RENNER, Vector3(2.4, 0, -1.4))
	horde.spawn(T.Kind.BROCKEN, Vector3(0.8, 0, -4.2))
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 100.0
	for i in horde.count():
		horde._appear[i] = 1.0
	hero.model.aim_yaw = atan2(-0.6, -1.0)
	for k in 30:
		hero.model.animate(DT)
		horde._draw()
		await process_frame
	await _save("preview_models_lineup")
	# Poses: reload at 45 %, enemies mid wind-up facing the hero.
	hero.model.reload = 0.45
	for i in horde.count():
		horde._state[i] = horde.State.WINDUP
		horde._timer[i] = float(T.enemy(horde.kind_of(i)).windup) * 0.25
		var to: Vector3 = (hero.position - horde.position_of(i)).normalized()
		horde._dir[i] = to
		horde._yaw[i] = atan2(to.x, to.z)
	for k in 4:
		hero.model.animate(DT)
		horde._draw()
		await process_frame
	await _save("preview_models_poses")
	# Reload sequence seen from the game camera angle, hero aiming to the right.
	horde.clear()
	camera.position = Vector3(0.0, 9.2, 6.0)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	hero.model.aim_yaw = PI * 0.5
	hero.model.snap_aim(PI * 0.5)
	var steps := [0.1, 0.25, 0.45, 0.7, 0.9]
	for index in steps.size():
		hero.model.reload = steps[index]
		hero.model.animate(DT)
		if index == 1:
			battle.effects.eject_shells(hero.model.breech_position(), Vector3.LEFT, 2)
		for k in 6:
			battle.effects.step(DT)
			await process_frame
		await _save("preview_models_reload_%d" % index)
	print("Saved model review frames")
	quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
