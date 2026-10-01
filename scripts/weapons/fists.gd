extends "res://scripts/weapons/weapon.gd"

# Brine's fists (stage 3, Teil B §3): melee auto-target and a 3-hit combo.
#   target    nearest enemy whose body is within REACH (2.2 m x range_mult);
#             the boxer turns to it (hero.aim_yaw, model snaps on the strike)
#   combo     left jab -> right cross -> uppercut, then a short recovery.
#             Jab and cross hit hard but only the 2 nearest bodies in a +-50
#             deg arc; the uppercut hits everything in a +-75 deg arc a little
#             further out with strong knockback by mass
#             (light far, medium clearly, heavy a nudge, bosses never), a mini
#             camera kick and a 3-frame hitstop (hitstop_requested).
#   rhythm    every strike has a short wind (WIND s: the fist pulls back), then
#             the hit frame; the combo restarts after IDLE_RESET s without target.
#   feedback  white swipe crescents (weapon_fx.gd), sparks and dust on hits.
# Track (progress.gd FISTS_STEPS, rank 1..5): wider arcs (+-65 / +-100),
# 25 % faster combo, uppercut shockwave, life steal per landed strike, fourth
# strike "Hammerfaust" (all round).

signal struck(step: int, hits: int, kills: int)

const FX := preload("res://scripts/weapons/weapon_fx.gd")

const REACH := 2.2
const WIND := 0.07
## Gap after each strike before the next one winds (s): jab, cross, uppercut
## (only before a Hammerfaust); after the last strike RECOVER.
const GAPS := [0.24, 0.28, 0.3]
const RECOVER := 0.9
const DAMAGE := [10.0, 10.0, 18.0, 18.0]
## Most enemies one strike can hit (0 = all in the arc); rank 1 adds one.
const MAX_TARGETS := [2, 2, 0, 0]
const HALF_DEG := [50.0, 50.0, 75.0, 180.0]
const HALF_DEG_WIDE := [65.0, 65.0, 100.0, 180.0]
const REACH_SCALE := [1.0, 1.0, 1.15, 1.1]
## Knock speed (m/s) by mass [light, medium, heavy] per strike.
const KNOCK := [[0.8, 0.3, 0.0], [0.8, 0.3, 0.0], [7.0, 4.0, 1.0], [6.0, 3.0, 0.6]]
const HITSTOP_FRAMES := 3
const IDLE_RESET := 0.8
const SHOCK_RADIUS := 2.9
const SHOCK_DAMAGE := 10.0
const LIFESTEAL := 1.5
const NAMES := ["Links", "Rechts", "Aufwärtshaken", "Hammerfaust"]

var step_index := 0
## > 0: the next strike is winding (seconds left).
var wind_left := 0.0
var target := -1
var aim := Vector3.FORWARD
var idle := 0.0
var strikes := 0
var combos := 0
var healed := 0.0
## Last strike (tests): {"step", "dir", "half", "reach", "hits": {index: data}}.
var last_strike: Dictionary = {}
var fx: Node3D


func _init() -> void:
	super()
	id = "fists"
	source = "Fäuste"


func _ready() -> void:
	fx = FX.new()
	fx.name = "FistFx"
	add_child(fx)


func reset() -> void:
	super()
	step_index = 0
	wind_left = 0.0
	target = -1
	idle = 0.0
	strikes = 0
	combos = 0
	healed = 0.0
	last_strike = {}
	if fx != null:
		fx.clear()


func reach() -> float:
	return REACH * range_mult()


## Strikes per combo: 3, 4 with Hammerfaust (rank 5).
func combo_length() -> int:
	return 4 if rank() >= 5 else 3


func speed_mult() -> float:
	return _stat("fire_rate_mult") * (1.25 if rank() >= 2 else 1.0)


func half_angle(step: int) -> float:
	var table: Array = HALF_DEG_WIDE if rank() >= 1 else HALF_DEG
	return deg_to_rad(float(table[step]))


func strike_reach(step: int) -> float:
	return reach() * float(REACH_SCALE[step])


## Seconds from one strike to the next one (wind included).
func gap_after(step: int) -> float:
	var g := RECOVER if step >= combo_length() - 1 else float(GAPS[step])
	return g / maxf(0.1, speed_mult())


func step(delta: float) -> void:
	if fx != null:
		fx.step(delta)
	if not can_act():
		return
	target = _find_target(reach())
	if target >= 0:
		var to: Vector3 = horde.position_of(target) - hero_at()
		to.y = 0.0
		if to.length_squared() > 0.0001:
			aim = to.normalized()
		hero.aim_yaw = atan2(aim.x, aim.z)
		idle = 0.0
	else:
		idle += delta
		if idle > 0.5:
			hero.aim_yaw = NAN
		if idle > IDLE_RESET and wind_left <= 0.0:
			step_index = 0
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if wind_left > 0.0:
		wind_left -= delta
		if wind_left <= 0.0:
			wind_left = 0.0
			strike(step_index)
		return
	if target >= 0 and cooldown_left <= 0.0:
		wind_left = WIND / maxf(0.1, speed_mult())
		var model: Node3D = hero.get("model")
		if model != null and model.has_method("wind_punch"):
			model.wind_punch(step_index)


## Hits with strike `step` along the current aim. Returns the kills.
func strike(step: int) -> int:
	var at := hero_at()
	if target >= 0 and target < horde.count() or target == BOSS_SLOT:
		var to: Vector3 = horde.position_of(target) - at
		to.y = 0.0
		if to.length_squared() > 0.0001:
			aim = to.normalized()
	var dir := aim
	var half := half_angle(step)
	var reach_now := strike_reach(step)
	var model: Node3D = hero.get("model")
	if model != null and model.has_method("punch"):
		if model.has_method("snap_aim") and model.is_inside_tree():
			model.snap_aim(atan2(dir.x, dir.z))
		model.punch(step)
	var hits := {}
	var knock: Array = KNOCK[step]
	var base := float(DAMAGE[step])
	var struck_now := enemies_in_arc(at, dir, reach_now, half)
	# Jab and cross land on the nearest bodies only (a fist hits one or two).
	var limit := int(MAX_TARGETS[step]) + (1 if rank() >= 1 and int(MAX_TARGETS[step]) > 0 else 0)
	if limit > 0 and struck_now.size() > limit:
		struck_now.sort_custom(func(a: int, b: int) -> bool:
			return horde.position_of(a).distance_squared_to(at) < horde.position_of(b).distance_squared_to(at))
		struck_now = struck_now.slice(0, limit)
	for index in struck_now:
		var p: Vector3 = horde.position_of(index)
		var push := Vector3(p.x - at.x, 0.0, p.z - at.z)
		push = push.normalized() if push.length_squared() > 0.0001 else dir
		# Knock mostly along the punch, a little outwards (fans the crowd open).
		var along := (dir * 0.6 + push * 0.4).normalized()
		hits[index] = {"damage": roll_damage(base), "dir": along, "knock": knock_by_mass(index, knock)}
		if _fx():
			effects.hit_sparks(Vector3(p.x, 0.9, p.z), along, 3 if step < 2 else 6)
			# White impact puff where the fist lands.
			effects.dust(Vector3(p.x, 0.55, p.z) - along * 0.3, 1, 0.8 if step < 2 else 1.2, Color(1.0, 1.0, 0.96, 0.9))
			if step >= 2:
				effects.dust(Vector3(p.x, 0.0, p.z), 2, 0.55)
	last_strike = {"step": step, "dir": dir, "half": half, "reach": reach_now, "hits": hits.duplicate(true)}
	var landed := hits.size()
	var killed := apply(hits)
	strikes += 1
	attacks += 1
	# Feedback: swipe crescent, sound, camera.
	if fx != null:
		match step:
			0, 1:
				fx.swipe(at, dir, reach_now + 0.45, half, 0.22, 1.0 if step == 0 else -1.0, Color(0.72, 0.86, 1.0), reach_now * 0.3, 1.0, 0.3)
			2:
				fx.swipe(at, dir, reach_now + 0.7, half, 0.3, 1.0, Color(1.0, 0.82, 0.38), reach_now * 0.2, 1.05, 0.3)
			_:
				fx.swipe(at, dir, reach_now + 0.5, PI, 0.32, -1.0, Color(1.0, 0.74, 0.36), reach_now * 0.25, 0.7, 0.25)
	if step >= 2:
		_kick(dir, 0.2 if step == 2 else 0.16)
		_shake(0.12 if landed > 0 else 0.04)
		_sound("dash", 0.75)
		if landed > 0:
			_sound("slam", 1.5)
			hitstop_requested.emit(HITSTOP_FRAMES)
		if _fx():
			effects.dust(at + dir * 0.6, 4 if step == 2 else 6, 0.7)
		if step == 2 and rank() >= 3:
			killed += _shockwave(at)
		if step == 3 and _fx():
			effects.ring(at, Color(1.0, 0.9, 0.6, 0.8), 0.6, reach_now, 0.3)
	else:
		_sound("dash", 1.7 + 0.15 * float(step))
	if landed > 0:
		_sound("hit", 1.15 - 0.1 * float(step))
		if rank() >= 4 and not hero.is_dead():
			var before: float = hero.health
			hero.health = minf(hero.max_health, hero.health + LIFESTEAL)
			healed += hero.health - before
	# Next strike of the combo.
	step_index = step + 1
	cooldown_left = gap_after(step)
	if step_index >= combo_length():
		step_index = 0
		combos += 1
	struck.emit(step, landed, killed)
	return killed


# Rank 3: the uppercut sends out a shockwave ring.
func _shockwave(at: Vector3) -> int:
	var radius := SHOCK_RADIUS * range_mult()
	var hits := {}
	for index in enemies_in_circle(at, radius):
		var p: Vector3 = horde.position_of(index)
		var out := Vector3(p.x - at.x, 0.0, p.z - at.z)
		out = out.normalized() if out.length_squared() > 0.0001 else aim
		hits[index] = {"damage": roll_damage(SHOCK_DAMAGE), "dir": out, "knock": knock_by_mass(index, [6.0, 3.0, 0.0])}
	if _fx():
		effects.ring(at, Color(1.0, 0.95, 0.75, 0.85), 0.5, radius, 0.32)
		effects.dust(at, 6, 0.8)
	return apply(hits)


# Nearest enemy whose body edge is within `max_range` (the boss included).
func _find_target(max_range: float) -> int:
	var at := hero_at()
	var best := -1
	var best_d := INF
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var d := Vector2(p.x - at.x, p.z - at.z).length() - float(horde.radius_of_kind(horde.kind_of(i)))
		if d <= max_range and d < best_d:
			best_d = d
			best = i
	var boss_index: int = horde.nearest_index(at, max_range)
	if boss_index == BOSS_SLOT:
		var b: Vector3 = horde.position_of(BOSS_SLOT)
		var d := Vector2(b.x - at.x, b.z - at.z).length() - float(horde._boss_radius())
		if d < best_d:
			best = BOSS_SLOT
	return best
