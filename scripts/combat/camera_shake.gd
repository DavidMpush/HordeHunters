extends Node

# Camera feedback without touching the camera transform (main.gd / the lab
# move the camera): directional kicks and trauma shake go into the camera's
# h_offset / v_offset, which shift the view in screen space.
#   kick(direction, strength) - shotgun recoil: view jolts against the shot
#   shake(amount)             - hits, Brocken slams (0..1 trauma, stacks)

const KICK_RETURN := 18.0      # 1/s spring back of the kick
const SHAKE_DECAY := 2.6       # trauma per second
const SHAKE_SIZE := 0.45       # metres at full trauma
const SHAKE_RATE := 38.0

var camera: Camera3D
var enabled := true
var _kick := Vector2.ZERO
var _trauma := 0.0
var _time := 0.0


## direction: world xz of the shot. The view moves against it (screen x = world
## x, screen up = world -z).
func kick(direction: Vector3, strength: float = 0.22) -> void:
	var d := Vector2(direction.x, -direction.z)
	if d.length_squared() > 0.0001:
		_kick -= d.normalized() * strength
	_kick = _kick.limit_length(0.6)


func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func reset() -> void:
	_kick = Vector2.ZERO
	_trauma = 0.0
	_apply(Vector2.ZERO)


func _process(delta: float) -> void:
	_time += delta
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-KICK_RETURN * delta))
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	var amount := _trauma * _trauma * SHAKE_SIZE
	var jitter := Vector2(sin(_time * SHAKE_RATE * 1.13) + sin(_time * SHAKE_RATE * 2.31) * 0.5,
		cos(_time * SHAKE_RATE * 0.97) + sin(_time * SHAKE_RATE * 1.71) * 0.5) * amount * 0.67
	_apply(_kick + jitter if enabled else Vector2.ZERO)


func _apply(offset: Vector2) -> void:
	if camera == null or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera == null:
			return
	camera.h_offset = offset.x
	camera.v_offset = offset.y
