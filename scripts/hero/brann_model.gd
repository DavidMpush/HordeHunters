extends Node3D

# Placeholder Brann (V2 roster): big bald bearded man, dark shirt, orange
# apron, grey bracers, double-barrelled shotgun as its own part. Built from
# primitives and animated procedurally:
#   legs   - follow the move direction, swing and bob while running
#   torso  - turns to the aim (auto-aim target), leans on recoil and dash
#   gun    - recoil kick, reload (swings across the chest, barrels break open,
#            shells fly out, two new ones go in, snap shut)
#   flash  - the whole model flashes on a hit (material uniform)
# The model faces local +Z. The hero (hero.gd) drives it with the setters below.
# Etappe 4 Teil D (performance): the ~60 primitive parts are merged into ONE
# vertex-coloured mesh per animation pivot (hips, legs, torso, head, gun,
# barrels, left arm, shells in hand) with one shared material: about 9 draw
# calls instead of 60, and the hit flash is one material write per change.

const TOON := preload("res://shaders/toon_merged.gdshader")

const SCALE := 1.35
const SKIN := Color("8a5636")
const SKIN_DARK := Color("6b3f26")
const BEARD := Color("1d1512")
const SHIRT := Color("4a4558")
const PANTS := Color("2f2a2c")
const APRON := Color("ef6a22")
const APRON_DARK := Color("b8461a")
const STEEL := Color("9aa3ad")
const STEEL_DARK := Color("4a4f57")
const WOOD := Color("8c4f26")
const LEATHER := Color("5a3420")
const SHELL_RED := Color("d8322a")
const BRASS := Color("e8b64a")

const HIP_HEIGHT := 0.82
const RUN_RATE := 11.0           # rad/s of the gait at full speed
const LEG_SWING := 0.75
const BOB := 0.07
const AIM_TURN := 22.0           # 1/s torso turn response
const LEG_TURN := 14.0

var hips: Node3D
var torso: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var gun: Node3D
var barrels: Node3D
var muzzle: Node3D
var breech: Node3D
var hand_shells: Node3D
## Merged meshes (one per pivot that carries parts).
var _parts: Array[GeometryInstance3D] = []
## pivot -> [[mesh, transform, colour], ...] while building.
var _pending := {}
var _material: ShaderMaterial
var _flash_shown := -1.0

# Animation state
var move_amount := 0.0           # 0..1 share of full run speed
var move_yaw := 0.0
var aim_yaw := 0.0
var gait := 0.0
var recoil := 0.0                # 1 at the shot, decays
var reload := -1.0               # 0..1 progress, < 0 = not reloading
var dash := 0.0                  # 1 while dashing, decays
var hurt := 0.0                  # hit flash 0..1
var dead := 0.0                  # 0..1 fall over
var _torso_yaw := 0.0
var _leg_yaw := 0.0


func _ready() -> void:
	if hips == null:
		build()


func build() -> void:
	if hips != null:
		return
	scale = Vector3.ONE * SCALE
	hips = _pivot(self, "Hips", Vector3(0, HIP_HEIGHT, 0))
	# Legs: pivot at the hip, pants and a boot with steel toe cap.
	for side in [-1.0, 1.0]:
		var leg := _pivot(hips, "Leg", Vector3(side * 0.2, 0, 0))
		_box(leg, PANTS, Vector3(0.26, 0.62, 0.28), Vector3(0, -0.3, 0))
		_box(leg, LEATHER, Vector3(0.28, 0.2, 0.4), Vector3(0, -0.72, 0.05))
		_box(leg, STEEL, Vector3(0.29, 0.12, 0.14), Vector3(0, -0.76, 0.22))
		if side < 0.0:
			leg_l = leg
		else:
			leg_r = leg
	torso = _pivot(self, "Torso", Vector3(0, HIP_HEIGHT, 0))
	# Belly and chest: one wide ellipsoid, shoulders on top.
	_sphere(torso, SHIRT, 0.5, Vector3(0, 0.42, 0), Vector3(1.0, 0.8, 0.72))
	for side in [-1.0, 1.0]:
		_sphere(torso, SHIRT, 0.21, Vector3(side * 0.42, 0.66, -0.02), Vector3.ONE)
	# Apron: bib over the chest and a skirt down over the thighs, straps.
	_box(torso, APRON, Vector3(0.58, 0.5, 0.06), Vector3(0, 0.46, 0.36), Vector3(-0.18, 0, 0))
	_box(torso, APRON, Vector3(0.74, 0.6, 0.06), Vector3(0, 0.0, 0.33), Vector3(0.12, 0, 0))
	_box(torso, APRON_DARK, Vector3(0.78, 0.07, 0.07), Vector3(0, 0.22, 0.38))
	# Apron string round the waist with a bow at the back.
	_box(torso, APRON, Vector3(0.92, 0.08, 0.7), Vector3(0, 0.12, -0.02))
	_sphere(torso, APRON, 0.1, Vector3(-0.08, 0.13, -0.36), Vector3(1.3, 0.8, 0.6))
	_sphere(torso, APRON, 0.1, Vector3(0.08, 0.13, -0.36), Vector3(1.3, 0.8, 0.6))
	for side in [-1.0, 1.0]:
		_box(torso, APRON_DARK, Vector3(0.07, 0.42, 0.06), Vector3(side * 0.25, 0.72, 0.2), Vector3(-0.6, 0, 0))
		_box(torso, STEEL, Vector3(0.11, 0.09, 0.07), Vector3(side * 0.25, 0.66, 0.31))
		# Straps crossing on the back and over the shoulders (readable from behind).
		_box(torso, APRON_DARK, Vector3(0.08, 0.72, 0.06), Vector3(side * 0.08, 0.42, -0.35), Vector3(0.12, 0, side * 0.55))
		_box(torso, APRON_DARK, Vector3(0.09, 0.07, 0.5), Vector3(side * 0.27, 0.86, -0.05), Vector3(0.15, 0, 0))
	# Head: bald dome, black beard, brows, ears.
	var head := _pivot(torso, "Head", Vector3(0, 0.98, 0.02))
	_sphere(head, SKIN, 0.27, Vector3.ZERO, Vector3(1.0, 1.05, 1.0))
	_sphere(head, BEARD, 0.22, Vector3(0, -0.12, 0.13), Vector3(1.05, 0.85, 0.75))
	_box(head, BEARD, Vector3(0.3, 0.05, 0.06), Vector3(0, 0.06, 0.24))
	_sphere(head, SKIN_DARK, 0.06, Vector3(0, -0.01, 0.27), Vector3.ONE)
	for side in [-1.0, 1.0]:
		_sphere(head, SKIN, 0.07, Vector3(side * 0.26, -0.02, 0), Vector3(0.6, 1.0, 1.0))
	# Gun: pivot in front of the belly, pointing +Z.
	gun = _pivot(torso, "Gun", Vector3(0.08, 0.5, 0.52))
	_box(gun, WOOD, Vector3(0.13, 0.15, 0.5), Vector3(0, -0.03, -0.3), Vector3(0.18, 0, 0))
	_box(gun, STEEL_DARK, Vector3(0.16, 0.15, 0.2), Vector3(0, 0, 0.02))
	breech = _pivot(gun, "Breech", Vector3(0, 0.03, 0.12))
	barrels = _pivot(gun, "Barrels", Vector3(0, -0.02, 0.1))
	for side in [-1.0, 1.0]:
		_cylinder(barrels, STEEL, 0.05, 0.82, Vector3(side * 0.05, 0.04, 0.43))
	_box(barrels, WOOD, Vector3(0.14, 0.07, 0.36), Vector3(0, -0.03, 0.22))
	_box(barrels, STEEL_DARK, Vector3(0.2, 0.12, 0.05), Vector3(0, 0.04, 0.82))
	muzzle = _pivot(barrels, "Muzzle", Vector3(0, 0.04, 0.86))
	# Arms: right hand on the grip, left hand under the forend.
	var right_shoulder := Vector3(0.44, 0.62, 0.02)
	var left_shoulder := Vector3(-0.44, 0.62, 0.02)
	_limb(torso, SHIRT, right_shoulder, Vector3(0.42, 0.36, 0.3), 0.14)
	_limb(torso, SKIN, Vector3(0.42, 0.36, 0.3), Vector3(0.14, 0.46, 0.46), 0.12)
	_limb(torso, STEEL, Vector3(0.36, 0.39, 0.34), Vector3(0.24, 0.43, 0.41), 0.135)
	_sphere(torso, SKIN, 0.11, Vector3(0.12, 0.46, 0.46), Vector3.ONE)
	arm_l = _pivot(torso, "ArmL", left_shoulder)
	_limb(arm_l, SHIRT, Vector3.ZERO, Vector3(-0.02, -0.22, 0.34), 0.14)
	_limb(arm_l, SKIN, Vector3(-0.02, -0.22, 0.34), Vector3(0.34, -0.12, 0.72), 0.12)
	_limb(arm_l, STEEL, Vector3(0.06, -0.2, 0.43), Vector3(0.2, -0.16, 0.58), 0.135)
	_sphere(arm_l, SKIN, 0.11, Vector3(0.36, -0.11, 0.74), Vector3.ONE)
	hand_shells = _pivot(arm_l, "Shells", Vector3(0.36, -0.03, 0.74))
	for side in [-1.0, 1.0]:
		_cylinder(hand_shells, SHELL_RED, 0.045, 0.16, Vector3(side * 0.05, 0.0, 0.0))
		_cylinder(hand_shells, BRASS, 0.05, 0.04, Vector3(side * 0.05, 0.0, -0.09))
	hand_shells.visible = false
	_merge_parts()


## Turns the torso onto the aim at once (the shot must leave along the aim).
func snap_aim(yaw: float) -> void:
	aim_yaw = yaw
	_torso_yaw = yaw
	torso.rotation.y = yaw


## Muzzle tip in world space (tracers and flash start here).
func muzzle_position() -> Vector3:
	return muzzle.global_position


## Opened breech in world space (empty shells fly out here).
func breech_position() -> Vector3:
	return breech.global_position


func set_hurt(amount: float) -> void:
	hurt = maxf(hurt, amount)


func animate(delta: float) -> void:
	# Gait and leg yaw follow the movement; torso follows the aim.
	gait = fposmod(gait + delta * RUN_RATE * (0.35 + 0.65 * move_amount) * signf(move_amount), TAU * 4.0)
	if move_amount > 0.05:
		_leg_yaw = lerp_angle(_leg_yaw, move_yaw, 1.0 - exp(-LEG_TURN * delta))
	_torso_yaw = lerp_angle(_torso_yaw, aim_yaw, 1.0 - exp(-AIM_TURN * delta))
	# Legs look the same way as the torso within 100 deg, else they run backwards.
	var leg_view := _leg_yaw
	var twist := wrapf(_torso_yaw - _leg_yaw, -PI, PI)
	var backwards := absf(twist) > PI * 0.6
	if backwards:
		leg_view = _leg_yaw + PI
	hips.rotation.y = lerp_angle(_torso_yaw, leg_view, 0.7)
	torso.rotation.y = _torso_yaw
	var swing := sin(gait) * LEG_SWING * move_amount * (-1.0 if backwards else 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	var bob := absf(sin(gait)) * BOB * move_amount
	hips.position.y = HIP_HEIGHT + bob
	torso.position.y = HIP_HEIGHT + bob
	# Lean: forward when running/dashing, back on recoil.
	recoil = maxf(0.0, recoil - delta * 6.5)
	dash = maxf(0.0, dash - delta * 5.0)
	hurt = maxf(0.0, hurt - delta * 5.0)
	var kick := recoil * recoil
	var lean := 0.1 * move_amount + 0.45 * dash - 0.22 * kick
	torso.rotation.x = lean
	torso.rotation.z = sin(gait) * 0.04 * move_amount
	# Gun: recoil pushes it back and up; the reload swings it across the chest.
	var open := 0.0
	var across := 0.0
	var hand_lift := 0.0
	hand_shells.visible = false
	if reload >= 0.0:
		var p := reload
		across = _ramp(p, 0.0, 0.18) * (1.0 - _ramp(p, 0.84, 1.0))
		open = _ramp(p, 0.04, 0.2) * (1.0 - _ramp(p, 0.84, 0.92))
		# Snap shut with a little overshoot.
		if p > 0.84:
			open -= sin(_ramp(p, 0.84, 1.0) * PI) * 0.12
		hand_lift = sin(_ramp(p, 0.3, 0.8) * PI)
		hand_shells.visible = p > 0.32 and p < 0.72
	gun.position = Vector3(0.08 - across * 0.18, 0.5 + across * 0.12 + kick * 0.08, 0.52 - kick * 0.22 - across * 0.12)
	gun.rotation = Vector3(-kick * 0.55 - across * 0.35, -across * 0.95, across * 0.35)
	barrels.rotation.x = open * 0.85
	arm_l.rotation = Vector3(-hand_lift * 0.9, -hand_lift * 0.3 + across * 0.4, 0.0)
	# Death: tip over backwards.
	rotation.x = -dead * PI * 0.48
	position.y = dead * 0.25
	_apply_flash()


func _apply_flash() -> void:
	var f := snappedf(hurt, 0.02)
	if f == _flash_shown:
		return
	_flash_shown = f
	_shared_material().set_shader_parameter("hit_flash", f)


static func _ramp(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)


# ---------------------------------------------------------------- building

func _pivot(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = TOON
		_material.set_shader_parameter("brightness", 1.05)
		_material.set_shader_parameter("saturation", 1.15)
		_material.set_shader_parameter("shape_light", 0.42)
		_material.set_shader_parameter("rim_color", Color("ffd9a0"))
		_material.set_shader_parameter("rim_strength", 0.5)
		_material.set_shader_parameter("rim_power", 3.0)
	return _material


## Records a part; _merge_parts() turns each pivot's parts into one mesh.
func _add(parent: Node3D, mesh: Mesh, color: Color, xform: Transform3D) -> void:
	if not _pending.has(parent):
		_pending[parent] = []
	_pending[parent].append([mesh, xform, color])


func _merge_parts() -> void:
	for pivot: Node3D in _pending:
		var part := MeshInstance3D.new()
		part.name = "Merged"
		part.mesh = merge_colored(_pending[pivot])
		part.material_override = _shared_material()
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(part)
		_parts.append(part)
	_pending.clear()


## One ArrayMesh from [[mesh, transform, colour], ...]: positions and normals
## baked into the pivot's space, the colour as (sRGB) vertex colour.
static func merge_colored(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var mesh: Mesh = part[0]
		var xform: Transform3D = part[1]
		var color: Color = part[2]
		var normal_basis := xform.basis.inverse().transposed()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for i in pv.size():
				verts.append(xform * pv[i])
				normals.append((normal_basis * pn[i]).normalized())
				colors.append(color)
			var pi: Variant = arrays[Mesh.ARRAY_INDEX]
			if pi is PackedInt32Array and not (pi as PackedInt32Array).is_empty():
				for index in pi:
					indices.append(base + index)
			else:
				for i in pv.size():
					indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return merged


func _box(parent: Node3D, color: Color, size: Vector3, at: Vector3, tilt := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(parent, mesh, color, Transform3D(Basis.from_euler(tilt), at))


func _sphere(parent: Node3D, color: Color, radius: float, at: Vector3, stretch: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	_add(parent, mesh, color, Transform3D(Basis.from_scale(stretch), at))


## Cylinder along local Z.
func _cylinder(parent: Node3D, color: Color, radius: float, length: float, at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	_add(parent, mesh, color, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at))


## Capsule from a to b.
func _limb(parent: Node3D, color: Color, a: Vector3, b: Vector3, radius: float) -> void:
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
	_add(parent, mesh, color, Transform3D(basis, (a + b) * 0.5))
