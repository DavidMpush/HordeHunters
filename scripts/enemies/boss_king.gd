extends Node3D

# Moorkönig, the first boss (stage 2, Teil B §4; state machine after Mawlings
# bog_king.gd / apex_toad.gd, target = the hero). Numbers: pressure_tuning.gd.
#
#   ARRIVING  rises out of the ground (not targetable)
#   CHASE     walks to the hero; the next attack of the cycle starts when the
#             hero is in its range; a hero far away or out of range for too long
#             gets a LEAP instead (running away is not safe)
#   WINDUP    the attack is telegraphed in magenta on the ground before any
#             damage: STOMP ring around the boss, LEAP landing zone (locked on
#             the hero's position plus a little lead), SWEEP arc in front
#   AIR       leap flight (not targetable); lands in the shown zone
#   RECOVER   vulnerable pause after every attack
#   DYING     sinks, then `defeated` and gone
# Cycle: STOMP -> LEAP -> SWEEP. Immune to knockback: the shotgun reaches it
# through horde.gd (BOSS_SLOT), which never pushes it. The hero cannot walk
# through the body. Damage only when the hero's centre is inside the shown
# shape at the moment of the strike.

signal attack_started(pattern: int, center: Vector3)
signal attack_landed(pattern: int, center: Vector3, hit: bool)
signal defeated(at: Vector3)

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BOSS_SHADER := preload("res://shaders/boss.gdshader")
const ARC_SHADER := preload("res://shaders/telegraph_arc.gdshader")
const ZONE_SHADER := preload("res://shaders/telegraph_zone.gdshader")
## The Mawlings Bog King model when it has been copied in, else a giant
## crowned Moorbrut (the Wichtel model) as placeholder.
const MODEL_PATHS := ["res://assets/enemies/BogKing_game.glb", "res://assets/enemies/Moorbrut_game.glb"]
const DUST := Color(0.56, 0.42, 0.28, 0.6)
const DYING_SECONDS := 1.4

enum State { ARRIVING, CHASE, WINDUP, AIR, RECOVER, DYING, DEAD }
enum Pattern { STOMP, LEAP, SWEEP }
const CYCLE := [Pattern.STOMP, Pattern.LEAP, Pattern.SWEEP]
const PATTERN_NAMES := {Pattern.STOMP: "Stampfer", Pattern.LEAP: "Sprung", Pattern.SWEEP: "Rundumschlag"}

var arena: Node3D
var hero: Node3D
var effects: Node3D

var state := State.ARRIVING
var timer := PT.BOSS_ARRIVE
var health := PT.BOSS_HP
var max_health := PT.BOSS_HP
var body_radius := PT.BOSS_RADIUS
var pattern := Pattern.STOMP
var cycle_index := 0
var chase_time := 0.0
var facing := Vector3.FORWARD
var zone_center := Vector3.ZERO
var zone_dir := Vector3.FORWARD
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
var clock := 0.0
## Test log: every attack {pattern, shown (clock), struck (clock), hit}.
var attacks: Array[Dictionary] = []
var hits_landed := 0

var _body: Node3D
var _model: Node3D
var _skin: ShaderMaterial
var _shadow: MeshInstance3D
var _stomp_zone: MeshInstance3D
var _sweep_zone: MeshInstance3D
var _leap_zone: MeshInstance3D
var _flash := 0.0
var _air := 0.0
var _gait := 0.0
var _slam := 0.0
var _lift := 0.0
var _lean := 0.0
var _windup_glow := 0.0
var _top := 2.0
var _front := 2.0


func _ready() -> void:
	_build()


func setup(arena_node: Node3D, hero_node: Node3D, effects_node: Node3D) -> void:
	arena = arena_node
	hero = hero_node
	effects = effects_node


func is_targetable() -> bool:
	return state == State.CHASE or state == State.WINDUP or state == State.RECOVER


func is_alive() -> bool:
	return state != State.DYING and state != State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## Seconds the current telegraph still runs (-1 = none shown).
func telegraph_left() -> float:
	if state == State.WINDUP:
		return timer + (PT.LEAP_AIR if pattern == Pattern.LEAP else 0.0)
	if state == State.AIR:
		return timer
	return -1.0


## Shown danger shape for bots and tests: {pattern, center, radius, dir, half, left} or {}.
func danger_zone() -> Dictionary:
	var left := telegraph_left()
	if left < 0.0:
		return {}
	match pattern:
		Pattern.STOMP:
			return {"pattern": pattern, "center": zone_center, "radius": PT.STOMP_RADIUS, "dir": zone_dir, "half": PI, "left": left}
		Pattern.LEAP:
			return {"pattern": pattern, "center": zone_center, "radius": PT.LEAP_RADIUS, "dir": zone_dir, "half": PI, "left": left}
	return {"pattern": pattern, "center": zone_center, "radius": PT.SWEEP_REACH, "dir": zone_dir, "half": deg_to_rad(PT.SWEEP_HALF_DEG), "left": left}


## Shotgun damage (via horde.gd). Never any knockback. True on the kill.
func take_damage(amount: float) -> bool:
	if not is_targetable():
		return false
	health = maxf(0.0, health - amount)
	_flash = 1.0
	if health <= 0.0:
		state = State.DYING
		timer = DYING_SECONDS
		_hide_zones()
		if effects != null and is_instance_valid(effects):
			effects.ring(position, Color(1.0, 0.85, 0.4, 0.9), 1.0, 6.0, 0.7)
			effects.dust(position, 10, 1.2)
		return true
	return false


func step(delta: float) -> void:
	clock += delta
	_flash = maxf(0.0, _flash - delta * 6.0)
	_slam = maxf(0.0, _slam - delta)
	var hero_at := _hero_at()
	var to_hero := hero_at - Vector3(position.x, 0.0, position.z)
	var d := to_hero.length()
	var moved := 0.0
	match state:
		State.ARRIVING:
			timer -= delta
			if d > 0.01:
				facing = to_hero / d
			if timer <= 0.0:
				state = State.CHASE
				chase_time = 0.0
		State.CHASE:
			chase_time += delta
			pattern = CYCLE[cycle_index]
			var forced := pattern != Pattern.LEAP and (d > PT.LEAP_FAR or chase_time > PT.CHASE_PATIENCE)
			if pattern == Pattern.LEAP or forced:
				_start(Pattern.LEAP, hero_at, not forced)
			elif pattern == Pattern.STOMP and d <= PT.STOMP_TRIGGER:
				_start(Pattern.STOMP, hero_at, true)
			elif pattern == Pattern.SWEEP and d <= PT.SWEEP_TRIGGER:
				_start(Pattern.SWEEP, hero_at, true)
			else:
				moved = _walk(delta, hero_at)
		State.WINDUP:
			timer -= delta
			if pattern == Pattern.LEAP:
				if timer <= 0.0:
					state = State.AIR
					timer = PT.LEAP_AIR
			elif timer <= 0.0:
				_strike()
			_progress_zones()
		State.AIR:
			timer -= delta
			var t := clampf(1.0 - timer / PT.LEAP_AIR, 0.0, 1.0)
			var eased := t * t * (3.0 - 2.0 * t)
			var flat := leap_from.lerp(leap_to, eased)
			_air = 4.0 * t * (1.0 - t) * PT.LEAP_HEIGHT
			position = Vector3(flat.x, 0.0, flat.z)
			if timer <= 0.0:
				_air = 0.0
				position = Vector3(leap_to.x, 0.0, leap_to.z)
				_strike()
			_progress_zones()
		State.RECOVER:
			timer -= delta
			if timer <= 0.0:
				state = State.CHASE
				chase_time = 0.0
		State.DYING:
			timer -= delta
			if timer <= 0.0:
				state = State.DEAD
				visible = false
				defeated.emit(Vector3(position.x, 0.0, position.z))
	if state != State.AIR and state != State.DEAD and state != State.DYING:
		_push_hero()
	_pose(delta, moved)


## The next attack: telegraph first, damage only at the end of the wind-up.
func _start(next: int, hero_at: Vector3, advance: bool) -> void:
	pattern = next
	state = State.WINDUP
	var here := Vector3(position.x, 0.0, position.z)
	var to_hero := hero_at - here
	if to_hero.length_squared() > 0.0001:
		facing = to_hero.normalized()
	zone_dir = facing
	match next:
		Pattern.STOMP:
			timer = PT.STOMP_WINDUP
			zone_center = here
		Pattern.SWEEP:
			timer = PT.SWEEP_WINDUP
			zone_center = here
		Pattern.LEAP:
			timer = PT.LEAP_CROUCH
			var lead := Vector3.ZERO
			if hero != null and hero.get("velocity") is Vector3:
				var v: Vector3 = hero.velocity
				lead = Vector3(v.x, 0.0, v.z) * PT.LEAP_LEAD
				lead = lead.limit_length(PT.LEAP_LEAD_MAX)
			var target := hero_at + lead
			var jump := target - here
			if jump.length() > PT.LEAP_MAX:
				target = here + jump.normalized() * PT.LEAP_MAX
			if arena != null and is_instance_valid(arena) and arena.has_method("safe_spawn"):
				var open: Vector3 = arena.safe_spawn(target, body_radius)
				if open.is_finite():
					target = open
			leap_from = here
			leap_to = Vector3(target.x, 0.0, target.z)
			zone_center = leap_to
			if (leap_to - here).length_squared() > 0.01:
				facing = (leap_to - here).normalized()
	if advance:
		cycle_index = (cycle_index + 1) % CYCLE.size()
	attacks.append({"pattern": next, "shown": clock, "struck": -1.0, "hit": false})
	_show_zone(next)
	attack_started.emit(next, zone_center)


func _strike() -> void:
	var hero_at := _hero_at()
	var offset := hero_at - zone_center
	var d := offset.length()
	var inside := false
	var damage := 0.0
	match pattern:
		Pattern.STOMP:
			inside = d <= PT.STOMP_RADIUS
			damage = PT.STOMP_DAMAGE
		Pattern.LEAP:
			inside = d <= PT.LEAP_RADIUS
			damage = PT.LEAP_DAMAGE
		Pattern.SWEEP:
			inside = d <= PT.SWEEP_REACH and (d < 0.001 or zone_dir.dot(offset / d) >= cos(deg_to_rad(PT.SWEEP_HALF_DEG)))
			damage = PT.SWEEP_DAMAGE
	var landed := false
	if inside and hero != null and is_instance_valid(hero) and hero.has_method("take_hit"):
		landed = bool(hero.take_hit(damage, zone_center))
	if landed:
		hits_landed += 1
	if not attacks.is_empty():
		attacks[attacks.size() - 1].struck = clock
		attacks[attacks.size() - 1].hit = landed
	state = State.RECOVER
	timer = PT.RECOVER_LEAP if pattern == Pattern.LEAP else PT.RECOVER
	_slam = 0.4
	_hide_zones()
	if effects != null and is_instance_valid(effects):
		var reach := PT.STOMP_RADIUS if pattern == Pattern.STOMP else (PT.LEAP_RADIUS if pattern == Pattern.LEAP else PT.SWEEP_REACH)
		var at := zone_center if pattern != Pattern.SWEEP else zone_center + zone_dir * PT.SWEEP_REACH * 0.55
		effects.ring(at, Color(1.0, 0.49, 0.76, 0.95), 0.8, reach * 1.1, 0.45)
		effects.ring(at, DUST, 0.6, reach * 0.8, 0.7)
		effects.dust(at, 8, 1.1)
	attack_landed.emit(pattern, zone_center, landed)


func _walk(delta: float, hero_at: Vector3) -> float:
	var here := Vector3(position.x, 0.0, position.z)
	var direction := (hero_at - here).normalized()
	if arena != null and is_instance_valid(arena) and arena.has_method("steer_direction"):
		var steer: Vector3 = arena.steer_direction(here, hero_at, 1.2)
		if steer.length_squared() > 0.01:
			direction = steer
	# Stop at the hero's body (no pushing him around while walking).
	var room := here.distance_to(hero_at) - body_radius - T.HERO_RADIUS
	var step_length := clampf(room, 0.0, PT.BOSS_SPEED * delta)
	var motion := direction * step_length
	var next := here + motion
	if arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
		next = arena.resolve_motion(here, motion, 1.2)
	position = Vector3(next.x, 0.0, next.z)
	if direction.length_squared() > 0.01:
		facing = facing.slerp(direction, minf(1.0, delta * 4.0)).normalized()
	return step_length / maxf(delta, 0.0001)


## The hero's body never overlaps the boss's (he is pushed out, the boss stays).
func _push_hero() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var here := Vector3(position.x, 0.0, position.z)
	var offset := Vector3(hero.position.x - here.x, 0.0, hero.position.z - here.z)
	var least := body_radius + T.HERO_RADIUS
	if offset.length_squared() >= least * least:
		return
	var out := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.RIGHT
	var target := here + out * least
	if arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
		target = arena.resolve_motion(Vector3(hero.position.x, 0.0, hero.position.z), target - Vector3(hero.position.x, 0.0, hero.position.z), T.HERO_RADIUS)
	hero.position = Vector3(target.x, hero.position.y, target.z)


func _hero_at() -> Vector3:
	if hero == null or not is_instance_valid(hero):
		return Vector3(position.x, 0.0, position.z) + Vector3.FORWARD * 100.0
	return Vector3(hero.position.x, 0.0, hero.position.z)


# ---------------------------------------------------------------- visuals

func _build() -> void:
	_body = Node3D.new()
	_body.name = "Moorkoenig body"
	add_child(_body)
	_skin = ShaderMaterial.new()
	_skin.shader = BOSS_SHADER
	_skin.set_shader_parameter("brightness", 1.25)
	_skin.set_shader_parameter("saturation", 1.15)
	_skin.set_shader_parameter("shape_light", 0.4)
	_skin.set_shader_parameter("rim_color", Color("d8b8ff"))
	_skin.set_shader_parameter("rim_strength", 0.8)
	_skin.set_shader_parameter("rim_power", 2.2)
	var placeholder := true
	for path in MODEL_PATHS:
		if ResourceLoader.exists(path):
			_model = (load(path) as PackedScene).instantiate()
			placeholder = path.ends_with("Moorbrut_game.glb")
			break
	if _model == null:
		var capsule := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 1.2
		mesh.height = 3.0
		capsule.mesh = mesh
		_model = capsule
	_body.add_child(_model)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = _skin
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _model is MeshInstance3D:
		(_model as MeshInstance3D).material_override = _skin
	if placeholder:
		# Swamp king look on the Moorbrut: darker moss tint, gold crown.
		_skin.set_shader_parameter("body_tint", Color(0.45, 0.66, 0.32, 0.6))
		_skin.set_shader_parameter("brightness", 1.45)
	_fit_model()
	if placeholder:
		_add_crown()
	_shadow = _make_shadow()
	_stomp_zone = _make_arc(PT.STOMP_RADIUS, PI, "Moorkoenig stomp")
	_sweep_zone = _make_arc(PT.SWEEP_REACH, deg_to_rad(PT.SWEEP_HALF_DEG), "Moorkoenig sweep")
	_leap_zone = _make_zone(PT.LEAP_RADIUS, "Moorkoenig landing")
	_hide_zones()


## Longest ground extent = BOSS_LENGTH, feet on the ground, centred.
func _fit_model() -> void:
	var box := AABB()
	var first := true
	for mesh in _model.find_children("*", "MeshInstance3D", true, false) + ([_model] if _model is MeshInstance3D else []):
		var part := mesh as MeshInstance3D
		if part.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var node: Node = part
		while node != null and node != _body:
			if node is Node3D:
				xform = (node as Node3D).transform * xform
			node = node.get_parent()
		var aabb: AABB = xform * part.mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	var extent := maxf(box.size.x, box.size.z)
	var s := PT.BOSS_LENGTH / maxf(0.01, extent)
	_model.scale *= s
	_model.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	_top = box.size.y * s
	_front = box.size.z * s * 0.5


func _add_crown() -> void:
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color("ffcf3f")
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color("7a4a10")
	var crown := Node3D.new()
	crown.name = "Crown"
	_body.add_child(crown)
	crown.position = Vector3(0.0, _top - 0.1, _front * 0.45)
	var rim := MeshInstance3D.new()
	var band := CylinderMesh.new()
	band.top_radius = 0.62
	band.bottom_radius = 0.66
	band.height = 0.26
	rim.mesh = band
	rim.material_override = dark
	crown.add_child(rim)
	var rim_face := MeshInstance3D.new()
	var face := CylinderMesh.new()
	face.top_radius = 0.6
	face.bottom_radius = 0.64
	face.height = 0.22
	rim_face.mesh = face
	rim_face.material_override = gold
	rim_face.position = Vector3(0, 0.03, 0)
	rim_face.scale = Vector3(1.04, 1.0, 1.04)
	crown.add_child(rim_face)
	for k in 5:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.17
		cone.height = 0.5
		spike.mesh = cone
		spike.material_override = gold
		var a := TAU * float(k) / 5.0
		spike.position = Vector3(cos(a) * 0.55, 0.36, sin(a) * 0.55)
		crown.add_child(spike)


func _make_arc(reach: float, half: float, node_name: String) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (reach + 0.4) * 2.0
	var part := MeshInstance3D.new()
	part.name = node_name
	part.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = ARC_SHADER
	material.set_shader_parameter("outer", reach)
	material.set_shader_parameter("inner", body_radius * 0.7)
	material.set_shader_parameter("half_angle", half)
	material.render_priority = 2
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	part.top_level = true
	return part


func _make_zone(radius: float, node_name: String) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (radius + 0.4) * 2.0
	var part := MeshInstance3D.new()
	part.name = node_name
	part.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = ZONE_SHADER
	material.set_shader_parameter("mode", 0)
	material.set_shader_parameter("radius", radius)
	material.render_priority = 2
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	part.top_level = true
	return part


func _show_zone(next: int) -> void:
	_hide_zones()
	var zone: MeshInstance3D = _stomp_zone
	if next == Pattern.SWEEP:
		zone = _sweep_zone
	elif next == Pattern.LEAP:
		zone = _leap_zone
	zone.visible = true
	zone.global_transform = Transform3D(Basis(Vector3.UP, atan2(zone_dir.x, zone_dir.z)), Vector3(zone_center.x, 0.07, zone_center.z))
	_progress_zones()


func _hide_zones() -> void:
	for zone in [_stomp_zone, _sweep_zone, _leap_zone]:
		if zone != null:
			zone.visible = false


## Shown telegraphs right now (tests, captures).
func zones_visible() -> int:
	var shown := 0
	for zone in [_stomp_zone, _sweep_zone, _leap_zone]:
		if zone != null and zone.visible:
			shown += 1
	return shown


func _progress_zones() -> void:
	var total := PT.STOMP_WINDUP
	match pattern:
		Pattern.SWEEP:
			total = PT.SWEEP_WINDUP
		Pattern.LEAP:
			total = PT.LEAP_CROUCH + PT.LEAP_AIR
	var left := maxf(0.0, telegraph_left())
	var progress := clampf(1.0 - left / total, 0.0, 1.0)
	for zone in [_stomp_zone, _sweep_zone, _leap_zone]:
		if zone != null and zone.visible:
			var material := zone.material_override as ShaderMaterial
			material.set_shader_parameter("progress", progress)
			material.set_shader_parameter("opacity", 1.0)
	_windup_glow = progress


func _pose(delta: float, speed: float) -> void:
	var lift := 0.0
	var lean := 0.0
	var tremble := 0.0
	var squash := 0.0
	var glow := 0.0
	var sink := 0.0
	match state:
		State.ARRIVING:
			var emerge := clampf(1.0 - timer / PT.BOSS_ARRIVE, 0.0, 1.0)
			sink = 3.5 * pow(1.0 - emerge, 2.0)
			tremble = 0.08 * (1.0 - emerge)
		State.CHASE:
			var stride := minf(1.0, speed / PT.BOSS_SPEED)
			var before := sin(_gait)
			_gait += speed * delta * 1.7
			var wave := sin(_gait)
			if stride > 0.2 and before != 0.0 and signf(wave) != signf(before) and effects != null and is_instance_valid(effects):
				effects.ring(position, DUST, 0.4, 1.8, 0.35)
			lift = absf(wave) * 0.25 * stride
			lean = 0.08 * stride
		State.WINDUP:
			var p := _windup_glow
			glow = p
			if pattern == Pattern.LEAP:
				# Crouch low before the jump.
				squash = 0.22 * minf(1.0, p * 2.5)
				lean = 0.2 * minf(1.0, p * 2.5)
			elif pattern == Pattern.STOMP:
				var rise := 1.0 - pow(1.0 - p, 3.0)
				lift = 0.9 * rise
				lean = -0.35 * rise
			else:
				# Sweep: wind the upper body back to one side.
				lean = -0.15 * p
			tremble = 0.08 * smoothstep(0.6, 1.0, p)
		State.AIR:
			glow = _windup_glow
			lean = -0.2
		State.RECOVER:
			var breath := sin(clock * 2.1)
			lift = -0.1
			lean = 0.18 + 0.03 * breath
		State.DYING:
			var t := 1.0 - timer / DYING_SECONDS
			sink = 2.5 * t * t
			lean = 0.5 * t
			tremble = 0.1 * (1.0 - t)
	if _slam > 0.0:
		var s := _slam / 0.4
		lean += 0.3 * s
		lift -= 0.12 * s
		squash += 0.18 * s
	var weight := minf(1.0, delta * 12.0)
	_lift = lerpf(_lift, lift, weight)
	_lean = lerpf(_lean, lean, weight)
	var jitter := Vector3(sin(clock * 47.0), 0.0, sin(clock * 39.0 + 1.3)) * tremble
	var yaw := atan2(facing.x, facing.z)
	var spin := 0.0
	if state == State.WINDUP and pattern == Pattern.SWEEP:
		spin = -0.7 * _windup_glow
	elif state == State.RECOVER and pattern == Pattern.SWEEP:
		spin = 0.6 * clampf(timer / PT.RECOVER, 0.0, 1.0)
	rotation = Vector3(0.0, yaw + spin, 0.0)
	_body.position = Vector3(0.0, _lift + _air - sink, 0.0) + jitter
	_body.rotation = Vector3(_lean, 0.0, 0.0)
	_body.scale = Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)
	_skin.set_shader_parameter("flash", 0.35 * _flash)
	_skin.set_shader_parameter("windup", glow)
	_skin.set_shader_parameter("rim_color", Color("ffe07a") if state == State.RECOVER else Color("d8b8ff"))
	var shadow_size := 1.0 - 0.5 * clampf(_air / PT.LEAP_HEIGHT, 0.0, 1.0)
	_shadow.scale = Vector3(shadow_size, 1.0, shadow_size)


func _make_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.04, 0.02, 0.55))
	gradient.set_color(1, Color(0.02, 0.04, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.02, 0.04, 0.02, 0.38))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.render_priority = 1
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * PT.BOSS_LENGTH * 1.1
	var part := MeshInstance3D.new()
	part.name = "Moorkoenig shadow"
	part.mesh = plane
	part.material_override = material
	part.position = Vector3(0, 0.04, 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
