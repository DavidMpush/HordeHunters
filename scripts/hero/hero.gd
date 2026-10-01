extends Node3D

# The hero: movement (stick/WASD), dash, health with short invulnerability
# after a hit, death. Carries the placeholder model; the weapons
# (scripts/weapons/*) are wired up by battle.gd. Everything runs in step(),
# called by battle.gd (tests call it directly).
# Stage 3: which hero (Brann, Rocco the boxer) comes from the catalogue
# scripts/hero/heroes.gd: apply_hero(id) sets name, base health, base armor,
# speed and builds the model; _ready() takes the menu's choice
# (heroes.current_id(), default Brann) unless hero_id was set before.

signal hurt(damage: float, from: Vector3)
signal died
signal dashed(direction: Vector3)

const T := preload("res://scripts/core/tuning.gd")
const MODEL := preload("res://scripts/hero/brann_model.gd")
const BUILD := preload("res://scripts/progression/progress.gd")
const HEROES := preload("res://scripts/hero/heroes.gd")
## Base armor plus the build's armor never goes above this.
const ARMOR_CAP := 0.7

var arena: Node3D
var model: Node3D
var effects: Node3D
## Stage 2: the run's build (scripts/progression/progress.gd); null = base values.
var build: RefCounted
## Stage 3: catalogue id ("brann", "boxer"), base health and armor share.
var hero_id := ""
var base_health := T.HERO_HP
var base_armor := 0.0

var max_health := T.HERO_HP
var health := T.HERO_HP
var radius := T.HERO_RADIUS
var speed := T.HERO_SPEED
var velocity := Vector3.ZERO
var facing := Vector3.FORWARD
var invulnerable := 0.0
var dash_left := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector3.FORWARD
var dash_count := 0
var dead := false
var damage_taken := 0.0
var hits_taken := 0
var _dust_clock := 0.0
## Optional aim from the weapon (world yaw); NAN = look where we walk.
var aim_yaw := NAN


func _ready() -> void:
	if model == null:
		apply_hero(hero_id if HEROES.has(hero_id) else HEROES.current_id())


## Becomes hero `id` of the catalogue: numbers and a fresh model. Health is
## filled up; the run's build is kept (progression re-applies Max-LP).
func apply_hero(id: String) -> void:
	hero_id = id if HEROES.has(id) else HEROES.DEFAULT
	var data: Dictionary = HEROES.get_hero(hero_id)
	base_health = float(data.get("hp", T.HERO_HP))
	base_armor = float(data.get("armor", 0.0))
	speed = float(data.get("speed", T.HERO_SPEED))
	max_health = base_health
	health = max_health
	if model != null and is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	var script: Variant = load(String(data.get("model_script", ""))) if ResourceLoader.exists(String(data.get("model_script", ""))) else null
	model = (script as GDScript).new() if script is GDScript else MODEL.new()
	model.name = String(data.get("name", "Brann"))
	add_child(model)


func reset(at: Vector3) -> void:
	position = Vector3(at.x, 0.0, at.z)
	health = max_health
	velocity = Vector3.ZERO
	invulnerable = 0.0
	dash_left = 0.0
	dash_cooldown = 0.0
	dead = false
	damage_taken = 0.0
	hits_taken = 0
	dash_count = 0
	aim_yaw = NAN
	if model != null:
		model.dead = 0.0
		model.reload = -1.0
		model.recoil = 0.0
		model.hurt = 0.0


## Build value for `id` (damage_mult, range_mult, pellets_bonus, ...; see
## progress.gd). Without a build: 1 for "*_mult", else 0.
func stat(id: String) -> float:
	if build != null:
		return build.stat(id)
	return BUILD.default_stat(id)


## Share of an enemy hit that is absorbed (hero base + build, capped).
func armor() -> float:
	return minf(ARMOR_CAP, base_armor + stat("armor"))


func move_speed() -> float:
	return speed * stat("speed_mult")


func dash_cooldown_time() -> float:
	return T.DASH_COOLDOWN * stat("dash_cooldown_mult")


func is_dead() -> bool:
	return dead


func is_dashing() -> bool:
	return dash_left > 0.0


func can_be_hit() -> bool:
	return not dead and dash_left <= 0.0 and invulnerable <= 0.0


func dash_ready() -> bool:
	return not dead and dash_cooldown <= 0.0 and dash_left <= 0.0


## Share of the dash cooldown still to wait (1 = just used, 0 = ready).
func dash_charge() -> float:
	return clampf(dash_cooldown / dash_cooldown_time(), 0.0, 1.0)


## Starts a dash along `direction` (zero = facing). False while cooling down.
func dash(direction: Vector3 = Vector3.ZERO) -> bool:
	if not dash_ready():
		return false
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.01:
		dir = facing
	dash_direction = dir.normalized()
	dash_left = T.DASH_SECONDS
	dash_cooldown = dash_cooldown_time()
	dash_count += 1
	if model != null:
		model.dash = 1.0
	if effects != null and is_instance_valid(effects):
		effects.dust(position, 4, 0.6)
	dashed.emit(dash_direction)
	return true


## Enemy strike. Returns true when it landed (not dashing/invulnerable/dead).
func take_hit(damage: float, from: Vector3) -> bool:
	if not can_be_hit():
		return false
	damage *= 1.0 - armor()
	health = maxf(0.0, health - damage)
	damage_taken += damage
	hits_taken += 1
	invulnerable = T.HERO_HURT_INVULN
	# A little shove away from the attacker.
	var away := Vector3(position.x - from.x, 0.0, position.z - from.z)
	if away.length_squared() > 0.0001:
		velocity += away.normalized() * 3.0
	if model != null:
		model.set_hurt(1.0)
	hurt.emit(damage, from)
	if health <= 0.0:
		dead = true
		died.emit()
	return true


## move: stick/keyboard vector (x right, y down on screen = +Z), length <= 1.
func step(delta: float, move: Vector2) -> void:
	invulnerable = maxf(0.0, invulnerable - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	if dead:
		velocity = Vector3.ZERO
		if model != null:
			model.dead = minf(1.0, model.dead + delta * 2.5)
			model.move_amount = 0.0
			model.animate(delta)
		return
	var regen := stat("regen")
	if regen > 0.0:
		health = minf(max_health, health + regen * delta)
	var top_speed := move_speed()
	var wish := Vector3(move.x, 0.0, move.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var motion := Vector3.ZERO
	if dash_left > 0.0:
		var step_time := minf(delta, dash_left)
		dash_left -= delta
		motion = dash_direction * (T.DASH_DISTANCE / T.DASH_SECONDS) * step_time
		velocity = dash_direction * top_speed
		if effects != null and is_instance_valid(effects):
			_dust_clock -= delta
			if _dust_clock <= 0.0:
				_dust_clock = 0.03
				effects.dust(position, 1, 0.45, Color(1.0, 0.92, 0.75, 0.5))
	else:
		var target := wish * top_speed
		var change := target - velocity
		var max_change := T.HERO_ACCEL * delta
		if change.length() > max_change:
			change = change.normalized() * max_change
		velocity += change
		motion = velocity * delta
	if wish.length_squared() > 0.01:
		facing = wish.normalized()
	var next := position + motion
	if arena != null and is_instance_valid(arena) and arena.has_method("resolve_motion"):
		next = arena.resolve_motion(position, motion, radius)
	next.y = 0.0
	position = next
	_animate(delta, wish)


func _animate(delta: float, wish: Vector3) -> void:
	if model == null:
		return
	var moving := Vector3(velocity.x, 0.0, velocity.z)
	model.move_amount = clampf(moving.length() / move_speed(), 0.0, 1.0)
	if moving.length_squared() > 0.04:
		model.move_yaw = atan2(moving.x, moving.z)
	model.aim_yaw = aim_yaw if not is_nan(aim_yaw) else atan2(facing.x, facing.z)
	# Invulnerability blink after a hit (not while dashing).
	model.visible = not (invulnerable > 0.0 and dash_left <= 0.0 and fmod(invulnerable, 0.12) < 0.04)
	model.animate(delta)
	if wish == Vector3.ZERO:
		return
	if effects != null and is_instance_valid(effects) and model.move_amount > 0.8:
		_dust_clock -= delta
		if _dust_clock <= 0.0:
			_dust_clock = 0.28
			effects.dust(position - facing * 0.3, 1, 0.35, Color(0.86, 0.8, 0.66, 0.35))
