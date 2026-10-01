extends Node3D

# Brine, the boxer (V5 concept 01_unarmed_boxer, V2 toon look). With the
# delivered rig (assets/heroes/brine/brine_rig.scn, built by
# tools/build_rigged_hero.gd from Konzepte und Ideen/Brine Rig.fbx and the
# animation FBX files) the skinned model is shown and posed bone by bone:
# the guard and the strikes are sampled from the "double_punch" clip (guard
# at 0 s, left hit 0.35 s, right hit 0.6 s), running legs, aim twist, lean,
# head snap and bob are added procedurally. The primitive placeholder below
# still runs invisibly (same timing curves). Without the rig it is shown:
# broad, heavy-shouldered brawler, red sleeveless hoodie over a black tank
# top, green shorts with cream trim, black/cream boots, huge bandaged fists,
# dark spiky hair with a grey streak, stubble beard. Built from primitives and
# animated procedurally (same driving interface as brann_model.gd):
#   run     legs swing, body bobs, the guard stays up (fists bounce)
#   guard   idle boxer bounce, fists in front of the chin
#   punch   wind_punch(step) pulls a fist back, punch(step) fires it:
#           0 left jab, 1 right cross (both straight, torso twist),
#           2 left uppercut (dip, then the fist swings up, body rises),
#           3 Hammerfaust (both fists over the head, slam down, squat)
#   dash    leans in, fists tucked
#   hit     every part flashes (instance uniform of toon_part), head snaps
#   death   staggers and tips over backwards
# The model faces local +Z.

const TOON := preload("res://shaders/toon_part.gdshader")
const TEXTURED := preload("res://shaders/hero_textured.gdshader")
const RIG_SCENE := "res://assets/heroes/brine/brine_rig.scn"
const RIG_TEXTURE := "res://assets/heroes/brine/brine_albedo.png"
## Rig height (sole to hair, m) and the height it gets in model units
## (matches the placeholder).
const RIG_HEIGHT := 1.763
const BODY_HEIGHT := 2.15
const CLIP := "double_punch"
const GUARD_TIME := 0.0
## Strike segments in the clip per side: [start of wind-up, hit frame].
const CLIP_LEFT := [0.15, 0.35]
const CLIP_RIGHT := [0.42, 0.6]
## Rig axes in skeleton space (the armature is Z-up, faces -Y).
const RIG_SIDE := Vector3(1, 0, 0)
const RIG_UP := Vector3(0, 0, 1)

const SCALE := 1.35
const SKIN := Color("c27a48")
const SKIN_DARK := Color("98552f")
const HOODIE := Color("d8382e")
const HOODIE_DARK := Color("a3241e")
const TANK := Color("27242b")
const SHORTS := Color("2f6b3a")
const TRIM := Color("eadfc4")
const UNDER := Color("1f1d22")
const BANDAGE := Color("f3e9d2")
const BANDAGE_SHADE := Color("d6c6a4")
const HAIR := Color("2a1d18")
const GREY := Color("aab0b8")
const BEARD := Color("3d2b20")
const BOOT := Color("2b2730")

const HIP_HEIGHT := 0.8
const RUN_RATE := 11.0
const LEG_SWING := 0.7
const BOB := 0.07
const AIM_TURN := 24.0
const LEG_TURN := 14.0
const UPPER := 0.34
const FORE := 0.32
## Strike shape over the time since the hit frame (s).
const PUNCH_LIFE := 0.26

var hips: Node3D
var torso: Node3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
## Arms: [shoulder pivot, elbow pivot, fist] per side (0 left, 1 right).
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var fists: Array[Node3D] = []
var _parts: Array[GeometryInstance3D] = []
## Skinned rig (null: primitive placeholder visible).
var body: Node3D
var _skeleton: Skeleton3D
var _clip: Animation
## Animated bones: [bone index, rotation track of the clip].
var _clip_bones: Array = []
var _bone := {}
var _rig_mesh: MeshInstance3D
var _materials := {}

# Animation state (driven by hero.gd and fists.gd)
var move_amount := 0.0
var move_yaw := 0.0
var aim_yaw := 0.0
var gait := 0.0
var recoil := 0.0                # unused (shared interface with Brann)
var reload := -1.0               # unused (shared interface with Brann)
var dash := 0.0
var hurt := 0.0
var dead := 0.0
## Current strike: step 0..3 (-1 none), seconds since its hit frame, wind 0..1.
var punch_step := -1
var punch_time := 99.0
var wind := 0.0
var wind_step := -1
var _torso_yaw := 0.0
var _leg_yaw := 0.0
var _clock := 0.0
var _flash_shown := -1.0


func _ready() -> void:
	if hips == null:
		build()


func build() -> void:
	if hips != null:
		return
	scale = Vector3.ONE * SCALE
	hips = _pivot(self, "Hips", Vector3(0, HIP_HEIGHT, 0))
	for side in [-1.0, 1.0]:
		var leg := _pivot(hips, "Leg", Vector3(side * 0.22, 0, 0))
		# Shorts leg (green, cream hem), black compression, calf, boot.
		_box(leg, SHORTS, Vector3(0.34, 0.36, 0.36), Vector3(side * 0.02, -0.12, 0))
		_box(leg, TRIM, Vector3(0.36, 0.06, 0.38), Vector3(side * 0.02, -0.31, 0))
		_box(leg, UNDER, Vector3(0.27, 0.12, 0.29), Vector3(0, -0.38, 0))
		_limb(leg, SKIN, Vector3(0, -0.42, 0), Vector3(0, -0.56, 0.0), 0.13)
		# High boot: black shaft with a cream cuff, cream toe cap, dark sole.
		_box(leg, BOOT, Vector3(0.29, 0.26, 0.31), Vector3(0, -0.68, 0.02))
		_box(leg, TRIM, Vector3(0.31, 0.07, 0.33), Vector3(0, -0.56, 0.02))
		_box(leg, TRIM, Vector3(0.29, 0.13, 0.2), Vector3(0, -0.74, 0.2))
		_box(leg, BOOT, Vector3(0.31, 0.05, 0.46), Vector3(0, -0.81, 0.08))
		if side < 0.0:
			leg_l = leg
		else:
			leg_r = leg
	torso = _pivot(self, "Torso", Vector3(0, HIP_HEIGHT, 0))
	# Waistband with drawstring, black tank top chest, broad.
	_box(torso, TRIM, Vector3(0.74, 0.1, 0.46), Vector3(0, 0.04, 0))
	_box(torso, TRIM, Vector3(0.04, 0.16, 0.03), Vector3(-0.04, -0.03, 0.24))
	_box(torso, TRIM, Vector3(0.04, 0.14, 0.03), Vector3(0.04, -0.02, 0.24))
	_sphere(torso, TANK, 0.42, Vector3(0, 0.42, 0.0), Vector3(1.18, 0.95, 0.78))
	# Red hoodie: back, two open front panels, shoulders, hood bunched behind.
	_sphere(torso, HOODIE, 0.43, Vector3(0, 0.44, -0.07), Vector3(1.22, 0.98, 0.7))
	for side in [-1.0, 1.0]:
		_sphere(torso, HOODIE, 0.3, Vector3(side * 0.31, 0.4, 0.14), Vector3(0.62, 1.22, 0.55))
		_box(torso, HOODIE_DARK, Vector3(0.035, 0.56, 0.05), Vector3(side * 0.16, 0.4, 0.28), Vector3(0.06, 0, side * -0.08))
		# Drawstrings.
		_box(torso, TRIM, Vector3(0.035, 0.3, 0.03), Vector3(side * 0.13, 0.62, 0.33), Vector3(0.1, 0, 0))
		_box(torso, TRIM, Vector3(0.06, 0.06, 0.04), Vector3(side * 0.13, 0.46, 0.34))
		# Shoulder caps of the hoodie (sleeveless: the cut edge).
		_sphere(torso, HOODIE, 0.2, Vector3(side * 0.46, 0.7, -0.02), Vector3(1.1, 0.7, 1.1))
	_sphere(torso, HOODIE_DARK, 0.24, Vector3(0, 0.83, -0.24), Vector3(1.4, 0.75, 0.8))
	_sphere(torso, HOODIE, 0.22, Vector3(0, 0.86, -0.22), Vector3(1.35, 0.7, 0.75))
	# Head: neck, jaw with stubble, nose bandage, spiky hair with a grey streak.
	_limb(torso, SKIN, Vector3(0, 0.72, 0.02), Vector3(0, 0.9, 0.04), 0.13)
	head = _pivot(torso, "Head", Vector3(0, 1.04, 0.05))
	_sphere(head, SKIN, 0.24, Vector3.ZERO, Vector3(0.95, 1.05, 1.0))
	_sphere(head, BEARD, 0.2, Vector3(0, -0.1, 0.07), Vector3(1.05, 0.8, 0.85))
	_sphere(head, SKIN, 0.16, Vector3(0, -0.02, 0.12), Vector3(1.0, 0.75, 0.8))
	# Eyes and heavy angled brows (a scowl), the nose with its plaster.
	for side in [-1.0, 1.0]:
		_sphere(head, Color("f4eee6"), 0.035, Vector3(side * 0.085, 0.05, 0.215), Vector3(1.2, 0.8, 0.5))
		_sphere(head, HAIR, 0.02, Vector3(side * 0.08, 0.05, 0.232), Vector3.ONE)
		_box(head, HAIR, Vector3(0.13, 0.045, 0.06), Vector3(side * 0.085, 0.105, 0.21), Vector3(0, 0, side * 0.32))
	_sphere(head, SKIN_DARK, 0.055, Vector3(0, -0.01, 0.25), Vector3(1.0, 1.0, 1.0))
	_box(head, BANDAGE, Vector3(0.12, 0.04, 0.03), Vector3(0, 0.01, 0.29))
	for side in [-1.0, 1.0]:
		_sphere(head, SKIN, 0.06, Vector3(side * 0.23, -0.01, 0), Vector3(0.6, 1.0, 1.0))
	# Hair: a dark cap, swept-back spikes; a grey streak over the left temple.
	_sphere(head, HAIR, 0.245, Vector3(0, 0.1, -0.04), Vector3(1.0, 0.6, 1.0))
	var spikes := [[-0.1, 0.06, 0.3], [0.03, 0.08, -0.1], [0.13, 0.02, -0.4], [-0.04, -0.07, 0.1], [0.08, -0.1, -0.2], [0.0, -0.18, 0.0]]
	for s in spikes:
		_box(head, HAIR, Vector3(0.1, 0.18, 0.1), Vector3(float(s[0]), 0.24, float(s[1])), Vector3(-0.7, 0, float(s[2])))
	_sphere(head, GREY, 0.09, Vector3(-0.135, 0.2, 0.05), Vector3(0.75, 0.42, 1.75))
	# Arms: bare shoulders and big arms, bandaged forearms and fists.
	for side in [-1.0, 1.0]:
		var shoulder := _pivot(torso, "Shoulder", Vector3(side * 0.56, 0.66, 0.02))
		_sphere(shoulder, SKIN, 0.17, Vector3.ZERO, Vector3.ONE)
		_limb(shoulder, SKIN, Vector3.ZERO, Vector3(0, -UPPER, 0), 0.14)
		var elbow := _pivot(shoulder, "Elbow", Vector3(0, -UPPER, 0))
		_limb(elbow, SKIN, Vector3.ZERO, Vector3(0, -FORE * 0.45, 0), 0.12)
		_limb(elbow, BANDAGE, Vector3(0, -FORE * 0.45, 0), Vector3(0, -FORE, 0), 0.13)
		_limb(elbow, BANDAGE_SHADE, Vector3(0, -FORE * 0.62, 0), Vector3(0, -FORE * 0.66, 0), 0.135)
		var fist := _pivot(elbow, "Fist", Vector3(0, -FORE - 0.1, 0))
		# The fist: a big bandaged block with knuckles and a skin thumb.
		_sphere(fist, BANDAGE, 0.19, Vector3.ZERO, Vector3(1.0, 1.05, 1.1))
		_box(fist, BANDAGE_SHADE, Vector3(0.32, 0.05, 0.3), Vector3(0, 0.02, 0), Vector3(0.0, 0.0, 0.0))
		_sphere(fist, SKIN, 0.07, Vector3(-side * 0.13, 0.02, 0.1), Vector3.ONE)
		for k in 4:
			_sphere(fist, BANDAGE, 0.06, Vector3(-0.1 + 0.067 * k, -0.15, 0.08), Vector3(1.0, 0.8, 1.0))
		shoulders.append(shoulder)
		elbows.append(elbow)
		fists.append(fist)
	for item in _parts:
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_build_body()


## Skinned rig over the invisible placeholder (when the rig exists).
func _build_body() -> void:
	if not ResourceLoader.exists(RIG_SCENE) or not ResourceLoader.exists(RIG_TEXTURE):
		return
	body = (load(RIG_SCENE) as PackedScene).instantiate()
	body.name = "Rig"
	body.scale = Vector3.ONE * (BODY_HEIGHT / RIG_HEIGHT)
	add_child(body)
	_skeleton = body.find_child("Skeleton3D", true, false) as Skeleton3D
	_rig_mesh = body.find_child("*Mesh*", true, false) as MeshInstance3D
	var player := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null or _rig_mesh == null or player == null or not player.has_animation(CLIP):
		body.queue_free()
		body = null
		return
	# The pose is set bone by bone below; the player only carries the clips.
	_clip = player.get_animation(CLIP)
	player.queue_free()
	for track in _clip.get_track_count():
		if _clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := _skeleton.find_bone(String(_clip.track_get_path(track).get_concatenated_subnames()))
		if bone >= 0:
			_clip_bones.append([bone, track])
	for bone_name in ["Hips", "Spine", "Spine1", "Spine2", "Head", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]:
		_bone[bone_name] = _skeleton.find_bone(bone_name)
	var material := ShaderMaterial.new()
	material.shader = TEXTURED
	material.set_shader_parameter("albedo_texture", load(RIG_TEXTURE))
	material.set_shader_parameter("brightness", 1.08)
	material.set_shader_parameter("saturation", 1.1)
	material.set_shader_parameter("shape_light", 0.3)
	material.set_shader_parameter("rim_color", Color("ffd9a0"))
	material.set_shader_parameter("rim_strength", 0.45)
	material.set_shader_parameter("rim_power", 3.0)
	_rig_mesh.material_override = material
	_rig_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for item in _parts:
		item.visible = false


func snap_aim(yaw: float) -> void:
	aim_yaw = yaw
	_torso_yaw = yaw
	torso.rotation.y = yaw


func set_hurt(amount: float) -> void:
	hurt = maxf(hurt, amount)


## The fist of `step` pulls back (anticipation before the hit frame).
func wind_punch(step: int) -> void:
	wind_step = step
	wind = 0.001


## Hit frame of strike `step` (0 jab, 1 cross, 2 uppercut, 3 Hammerfaust).
func punch(step: int) -> void:
	punch_step = step
	punch_time = 0.0
	wind = 0.0
	wind_step = -1


## World position of a fist (0 left, 1 right) - effects and tests.
func fist_position(side: int) -> Vector3:
	if body != null and is_inside_tree():
		var hand: int = _bone["LeftHand" if side == 0 else "RightHand"]
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(hand).origin
	return fists[clampi(side, 0, 1)].global_position


func animate(delta: float) -> void:
	_clock += delta
	gait = fposmod(gait + delta * RUN_RATE * (0.35 + 0.65 * move_amount) * signf(move_amount), TAU * 4.0)
	if move_amount > 0.05:
		_leg_yaw = lerp_angle(_leg_yaw, move_yaw, 1.0 - exp(-LEG_TURN * delta))
	_torso_yaw = lerp_angle(_torso_yaw, aim_yaw, 1.0 - exp(-AIM_TURN * delta))
	var leg_view := _leg_yaw
	var twist_legs := wrapf(_torso_yaw - _leg_yaw, -PI, PI)
	var backwards := absf(twist_legs) > PI * 0.6
	if backwards:
		leg_view = _leg_yaw + PI
	hips.rotation.y = lerp_angle(_torso_yaw, leg_view, 0.7)
	if wind > 0.0:
		wind = minf(1.0, wind + delta / 0.07)
	punch_time += delta
	dash = maxf(0.0, dash - delta * 5.0)
	hurt = maxf(0.0, hurt - delta * 5.0)
	# Strike curves: e = extension (fast out, slower back), s = the step.
	var e := 0.0
	if punch_step >= 0 and punch_time < PUNCH_LIFE:
		e = minf(1.0, punch_time / 0.035) * (1.0 - _ramp(punch_time, 0.07, PUNCH_LIFE))
	elif punch_time >= PUNCH_LIFE:
		punch_step = -1
	var step := punch_step if e > 0.0 else -1
	# Body: run bob or the boxer's idle bounce; strikes twist and lift it.
	var idle := 1.0 - move_amount
	var bounce := absf(sin(_clock * 6.5)) * 0.045 * idle
	var bob := absf(sin(gait)) * BOB * move_amount + bounce
	var swing := sin(gait) * LEG_SWING * move_amount * (-1.0 if backwards else 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	var twist := 0.0
	var lean := 0.12 * move_amount + 0.5 * dash
	var lift := 0.0
	var squat := 0.0
	match step:
		0:
			twist = -0.38 * e
			lean += 0.12 * e
		1:
			twist = 0.45 * e
			lean += 0.16 * e
		2:
			twist = -0.3 * e
			lean -= 0.18 * e
			lift = 0.1 * e
		3:
			lean += 0.35 * e
			squat = 0.14 * e
	# Wind-up: twist away from the coming strike.
	if wind > 0.0 and wind_step >= 0:
		var w := wind
		match wind_step:
			0:
				twist += 0.12 * w
			1:
				twist -= 0.2 * w
			2:
				twist += 0.15 * w
				squat += 0.08 * w
			3:
				lean -= 0.2 * w
	# A stance: legs a little apart while not running.
	leg_l.rotation.z = -0.08 * idle - squat * 0.6
	leg_r.rotation.z = 0.08 * idle + squat * 0.6
	hips.position.y = HIP_HEIGHT + bob + lift - squat
	torso.position.y = HIP_HEIGHT + bob + lift - squat
	torso.rotation.y = _torso_yaw + twist
	torso.rotation.x = lean
	torso.rotation.z = sin(gait) * 0.05 * move_amount
	head.rotation.x = -hurt * 0.5
	# Arms: guard, then the strike pose of the active arm blended in by e.
	for side in 2:
		var shoulder_x := -0.55
		var elbow_x := -2.25
		var shoulder_y := (0.38 if side == 0 else -0.38)
		var shoulder_z := (0.25 if side == 0 else -0.25)
		# Guard bounce and dash tuck.
		shoulder_x += sin(_clock * 6.5 + float(side) * 1.4) * 0.06 * idle + 0.25 * dash
		var arm_e := 0.0
		var arm_w := 0.0
		if step >= 0:
			arm_e = e if _arm_of(step, side) else 0.0
		if wind > 0.0 and wind_step >= 0 and _arm_of(wind_step, side):
			arm_w = wind
		var pose_step := step if arm_e > 0.0 else wind_step
		match pose_step:
			0, 1:
				# Straight punch: shoulder forward to horizontal, elbow opens.
				shoulder_x = lerpf(shoulder_x, -1.62, arm_e) + 0.25 * arm_w
				elbow_x = lerpf(elbow_x, -0.05, arm_e) - 0.25 * arm_w
				shoulder_y = lerpf(shoulder_y, (0.1 if side == 0 else -0.1), arm_e)
				shoulder_z = lerpf(shoulder_z, 0.0, arm_e)
			2:
				# Uppercut: dips low, then swings up past the chin.
				shoulder_x = lerpf(shoulder_x, -2.55, arm_e) + 0.45 * arm_w
				elbow_x = lerpf(elbow_x, -1.15, arm_e) + 0.9 * arm_w
				shoulder_y = lerpf(shoulder_y, (0.15 if side == 0 else -0.15), arm_e)
			3:
				# Hammerfaust: both fists high (wind), then down in front.
				shoulder_x = lerpf(shoulder_x - 2.2 * arm_w, -1.25, arm_e)
				elbow_x = lerpf(elbow_x + 1.0 * arm_w, -0.35, arm_e)
				shoulder_y = lerpf(shoulder_y, (0.3 if side == 0 else -0.3), arm_e)
		shoulders[side].rotation = Vector3(shoulder_x, shoulder_y, shoulder_z)
		elbows[side].rotation = Vector3(elbow_x, 0.0, 0.0)
		# The striking fist swells a little (reads as impact from far away).
		var pop := 1.0 + 0.25 * arm_e
		fists[side].scale = Vector3.ONE * pop
	if body != null:
		_animate_rig(swing, bob + lift - squat, lean, squat)
	# Death: stagger back and tip over.
	rotation.x = -dead * PI * 0.48
	position.y = dead * 0.25
	_apply_flash()


## Poses the skinned rig: clip guard blended toward the strike segment of the
## active side, then running legs, torso twist toward the aim, lean and the
## head snap on top. Strikes: 0 jab and 2 uppercut use the left segment,
## 1 cross and 3 Hammerfaust the right one (until own clips arrive).
func _animate_rig(swing: float, rise: float, lean: float, squat: float) -> void:
	var clip_time := GUARD_TIME
	var blend := 0.0
	if punch_step >= 0 and punch_time < PUNCH_LIFE:
		var segment: Array = CLIP_LEFT if punch_step % 2 == 0 else CLIP_RIGHT
		clip_time = lerpf(segment[1] - 0.08, segment[1], _ramp(punch_time, 0.0, 0.035)) + maxf(0.0, punch_time - 0.035) * 0.4
		blend = 1.0 - _ramp(punch_time, 0.07, PUNCH_LIFE)
	elif wind > 0.0 and wind_step >= 0:
		var segment: Array = CLIP_LEFT if wind_step % 2 == 0 else CLIP_RIGHT
		clip_time = lerpf(segment[0], segment[1] - 0.08, wind)
		blend = wind
	for entry in _clip_bones:
		var track: int = entry[1]
		var q := _clip.rotation_track_interpolate(track, GUARD_TIME)
		if blend > 0.0:
			q = q.slerp(_clip.rotation_track_interpolate(track, clip_time), blend)
		_skeleton.set_bone_pose_rotation(entry[0], q)
	# Legs: swing from the hip, the knee bends while the foot is behind.
	_turn("LeftUpLeg", RIG_SIDE, swing)
	_turn("RightUpLeg", RIG_SIDE, -swing)
	var knee := 0.25 * move_amount
	_turn("LeftLeg", RIG_SIDE, maxf(0.0, swing) * 1.1 + knee)
	_turn("RightLeg", RIG_SIDE, maxf(0.0, -swing) * 1.1 + knee)
	# Body faces the legs; the spine twists toward the aim and leans.
	body.rotation.y = hips.rotation.y
	body.position.y = maxf(rise, -0.25)
	var spine_twist := wrapf(torso.rotation.y - hips.rotation.y, -PI, PI)
	var rest := _skeleton.get_bone_rest(_bone["Spine1"]).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(_bone["Spine1"], rest)
	_turn("Spine1", RIG_UP, spine_twist)
	_turn("Spine1", RIG_SIDE, lean * 0.5 + squat * 0.5)
	_turn("Head", RIG_SIDE, -hurt * 0.5)


## Rotates bone `bone_name` about a skeleton-space axis (approximated in the
## bone's rest frame, fine for the small procedural angles).
func _turn(bone_name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var bone: int = _bone[bone_name]
	var local := (_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * axis).normalized()
	_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone) * Quaternion(local, angle))


func _arm_of(step: int, side: int) -> bool:
	match step:
		0, 2:
			return side == 0
		1:
			return side == 1
	return true


func _apply_flash() -> void:
	if body != null:
		# Etappe 4 Teil D: write the instance uniform only when it changes.
		var f := snappedf(hurt, 0.02)
		if f != _flash_shown:
			_flash_shown = f
			_rig_mesh.set_instance_shader_parameter("hit_flash", f)
		return
	for item in _parts:
		item.set_instance_shader_parameter("hit_flash", hurt)


static func _ramp(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)


# ---------------------------------------------------------------- building

func _pivot(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = TOON
		material.set_shader_parameter("albedo", color)
		material.set_shader_parameter("brightness", 1.05)
		material.set_shader_parameter("saturation", 1.15)
		material.set_shader_parameter("shape_light", 0.42)
		material.set_shader_parameter("rim_color", Color("ffd9a0"))
		material.set_shader_parameter("rim_strength", 0.5)
		material.set_shader_parameter("rim_power", 3.0)
		_materials[key] = material
	return _materials[key]


func _add(parent: Node3D, mesh: Mesh, color: Color, xform: Transform3D) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = _material(color)
	item.transform = xform
	parent.add_child(item)
	_parts.append(item)
	return item


func _box(parent: Node3D, color: Color, size: Vector3, at: Vector3, tilt := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, color, Transform3D(Basis.from_euler(tilt), at))


func _sphere(parent: Node3D, color: Color, radius: float, at: Vector3, stretch: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _add(parent, mesh, color, Transform3D(Basis.from_scale(stretch), at))


## Capsule from a to b.
func _limb(parent: Node3D, color: Color, a: Vector3, b: Vector3, radius: float) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(radius * 2.0, a.distance_to(b) + radius * 2.0)
	mesh.radial_segments = 10
	mesh.rings = 3
	var dir := (b - a).normalized()
	var basis := Basis.IDENTITY
	if dir.length_squared() > 0.0:
		var axis := Vector3.UP.cross(dir)
		if axis.length_squared() < 0.000001:
			basis = Basis.IDENTITY if dir.y > 0.0 else Basis(Vector3.RIGHT, PI)
		else:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	return _add(parent, mesh, color, Transform3D(basis, (a + b) * 0.5))
