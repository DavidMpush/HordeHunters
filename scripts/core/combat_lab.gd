extends Node3D

# Combat lab (scenes/combat_lab.tscn): the stage 1 fight on the flat stub arena
# (scripts/core/flat_arena.gd) with the game camera, for tuning without the
# world. Keys: 1/2/3 spawn a Wichtel pack / Renner pack / a Brocken in front
# of the hero, 0 toggles the director, K kills the hero.

const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const CAMERA_FOLLOW := 5.0
const T := preload("res://scripts/core/tuning.gd")

@onready var arena: Node3D = $Arena
@onready var camera: Camera3D = $Camera3D
@onready var battle: Node = $Battle

var _camera_base := Vector3.ZERO


func _ready() -> void:
	process_priority = 100
	snap_camera()


func _process(delta: float) -> void:
	var hero: Node3D = battle.hero
	if hero == null:
		return
	var target := Vector3(hero.position.x, 0.0, hero.position.z)
	_camera_base = _camera_base.lerp(target + CAMERA_OFFSET, 1.0 - exp(-CAMERA_FOLLOW * delta))
	camera.position = _camera_base
	camera.look_at(_camera_base - CAMERA_OFFSET, Vector3.UP)


func snap_camera() -> void:
	var hero: Node3D = battle.hero if battle != null else null
	var target := Vector3.ZERO if hero == null else Vector3(hero.position.x, 0.0, hero.position.z)
	_camera_base = target + CAMERA_OFFSET
	camera.position = _camera_base
	camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var hero: Node3D = battle.hero
	var ahead: Vector3 = hero.position + Vector3(0, 0, -7)
	match event.keycode:
		KEY_1:
			for k in 8:
				battle.horde.spawn(T.Kind.WICHTEL, ahead + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		KEY_2:
			for k in 5:
				battle.horde.spawn(T.Kind.RENNER, ahead + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		KEY_3:
			battle.horde.spawn(T.Kind.BROCKEN, ahead)
		KEY_0:
			battle.director_enabled = not battle.director_enabled
		KEY_K:
			hero.take_hit(1000.0, hero.position)
