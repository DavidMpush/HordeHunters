extends Node

# Combat of stage 1 (Teil B): wires hero, shotgun, enemies, director, effects,
# camera feedback, sound, HUD and the run, and steps them in a fixed order
# every frame. A child of Main (scenes/main.tscn) or of the combat lab:
#   - hero:  sibling "Hero" with scripts/hero/hero.gd (created if missing)
#   - arena: sibling "Arena" (world arena or the flat lab stub)
#   - camera: the viewport camera (main.gd / the lab moves it; feedback only
#     touches h_offset / v_offset)
# Order per frame: input -> hero -> shotgun -> enemies -> director -> effects
# -> run. Main (process_priority 100) syncs the arena and follows the hero
# afterwards. Tests set `auto = false` and call tick(delta) themselves.

signal run_restarted
signal run_ended

const T := preload("res://scripts/core/tuning.gd")
const HERO := preload("res://scripts/hero/hero.gd")
const SHOTGUN := preload("res://scripts/weapons/shotgun.gd")
const HORDE := preload("res://scripts/enemies/horde.gd")
const DIRECTOR := preload("res://scripts/enemies/director.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")
const SHAKE := preload("res://scripts/combat/camera_shake.gd")
const SFX := preload("res://scripts/core/sfx.gd")
const RUN := preload("res://scripts/core/run.gd")
const CONTROLS := preload("res://scripts/ui/touch_controls.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const PROGRESSION := preload("res://scripts/progression/progression.gd")
const PRESSURE := preload("res://scripts/enemies/pressure.gd")

## false: nothing steps by itself (tests drive tick()).
var auto := true
## The director spawns (labs and tests may switch it off).
var director_enabled := true
var max_delta := 1.0 / 20.0

var hero: Node3D
var arena: Node3D
var shotgun: Node
var horde: Node3D
var director: RefCounted
var effects: Node3D
var shake: Node
var sfx: Node
var run: RefCounted
var controls: Control
var hud: Control
var hud_layer: CanvasLayer
## Stage 2 Teil A: progression.gd (XP, level-up choice, gold, cocoons) and
## shortcuts to its parts: loot.gd (gems, coins), chests.gd, progress.gd (build).
var progression: Node
var loot: Node3D
var chests: Node3D
var progress: RefCounted
## Stage 2 Teil B: waves, encircle rings, champions, boss, Endwelle (pressure.gd).
var pressure: Node
var _ended := false


func _ready() -> void:
	var host := get_parent()
	arena = host.get_node_or_null("Arena") as Node3D
	hero = host.get_node_or_null("Hero") as Node3D
	if hero == null or hero.get_script() != HERO:
		hero = HERO.new()
		hero.name = "Hero"
		host.add_child.call_deferred(hero)
	var placeholder := hero.get_node_or_null("Placeholder")
	if placeholder != null:
		placeholder.queue_free()
	hero.arena = arena
	run = RUN.new()
	effects = EFFECTS.new()
	effects.name = "Effects"
	host.add_child.call_deferred(effects)
	horde = HORDE.new()
	horde.name = "Horde"
	host.add_child.call_deferred(horde)
	hero.effects = effects
	horde.setup(arena, hero, effects)
	shotgun = SHOTGUN.new()
	shotgun.name = "Shotgun"
	shotgun.hero = hero
	shotgun.horde = horde
	shotgun.effects = effects
	add_child(shotgun)
	director = DIRECTOR.new()
	director.horde = horde
	director.arena = arena
	shake = SHAKE.new()
	shake.name = "CameraShake"
	add_child(shake)
	sfx = SFX.new()
	sfx.name = "Sfx"
	add_child(sfx)
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)
	hud = HUD.new()
	hud.name = "Hud"
	hud.battle = self
	hud_layer.add_child(hud)
	controls = CONTROLS.new()
	controls.name = "Controls"
	hud_layer.add_child(controls)
	progression = PROGRESSION.new()
	progression.name = "Progression"
	add_child(progression)
	progression.setup(self)
	loot = progression.loot
	chests = progression.chests
	progress = progression.progress
	pressure = PRESSURE.new()
	pressure.name = "Pressure"
	add_child(pressure)
	pressure.setup(self)
	_connect()


func _connect() -> void:
	controls.dash_requested.connect(_on_dash_requested)
	controls.restart_requested.connect(restart)
	hero.hurt.connect(_on_hero_hurt)
	hero.died.connect(_on_hero_died)
	hero.dashed.connect(func(_dir: Vector3) -> void: sfx.play("dash"))
	shotgun.fired.connect(_on_fired)
	shotgun.reload_started.connect(func() -> void: sfx.play("open"))
	shotgun.shells_ejected.connect(func() -> void: sfx.play("shell"))
	shotgun.reload_finished.connect(func() -> void: sfx.play("close"))
	horde.enemy_killed.connect(_on_enemy_killed)
	horde.enemy_damaged.connect(_on_enemy_damaged)
	horde.windup_started.connect(_on_windup)
	horde.swing_landed.connect(_on_swing)


func _process(delta: float) -> void:
	if auto:
		tick(minf(delta, max_delta))


func tick(delta: float) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	if director.camera == null:
		director.camera = get_viewport().get_camera_3d()
	# Level-up / cocoon choice open: the run stands still.
	controls.blocked = paused()
	if paused():
		return
	var move: Vector2 = controls.move_vector() if not run.dead else Vector2.ZERO
	hero.step(delta, move)
	# Main (world scene) syncs the arena itself after its children.
	if arena != null and arena.has_method("sync") and not get_parent().has_method("start_world"):
		arena.sync(hero.position)
	shotgun.step(delta)
	horde.step(delta)
	var running := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	director.heading = running.normalized() if running.length() > 1.5 else Vector3.ZERO
	if director_enabled and not run.dead:
		director.step(delta, run.elapsed, hero.position)
	pressure.step(delta, run.elapsed, director_enabled and not run.dead)
	effects.step(delta)
	progression.step(delta)
	run.step(delta)
	controls.dash_charge = hero.dash_charge()
	controls.dead = run.dead
	controls.show_result = hud.result_visible()
	controls.result_button = hud.result_button_rect()


## New run on the same map: hero back to the start, enemies and effects gone.
func restart() -> void:
	var start := Vector3.ZERO
	if arena != null and arena.has_method("spawn_points"):
		var points: Array = arena.spawn_points(1)
		if not points.is_empty():
			start = points[0]
	elif arena != null and arena.has_method("map_center"):
		start = arena.map_center()
	hero.reset(start)
	shotgun.reset()
	horde.clear()
	effects.clear()
	hud.clear()
	shake.reset()
	director.reset(4242 + run.runs * 7919)
	pressure.reset()
	run.reset()
	run.runs += 1
	progression.reset()
	_ended = false
	controls.clear_pointers()
	controls.dead = false
	controls.show_result = false
	var host := get_parent()
	if arena != null and arena.has_method("sync"):
		arena.sync(start)
	if host.has_method("snap_camera"):
		host.snap_camera()
	sfx.play("ui")
	run_restarted.emit()


# ---------------------------------------------------------------- drops (stage 2 Teil A)
# Public drop API for enemies, elites and bosses (Teil B calls these).
# kind of drop_chest: "free" (elite), "boss" (at least epic), "map" (costs gold).

func drop_xp(at: Vector3, amount: float) -> void:
	progression.drop_xp(at, amount)


func drop_gold(at: Vector3, amount: int) -> void:
	progression.drop_gold(at, amount)


func drop_chest(at: Vector3, kind: String = "free") -> void:
	progression.drop_chest(at, kind)


## True while the level-up / cocoon choice is open (nothing steps).
func paused() -> bool:
	return progression != null and progression.paused()


# ---------------------------------------------------------------- events

func _on_dash_requested() -> void:
	if run.dead:
		return
	hero.dash(Vector3(controls.move_vector().x, 0.0, controls.move_vector().y))


func _on_fired(direction: Vector3, pellets_hit: int, kills: int) -> void:
	run.shots += 1
	shake.kick(direction, 0.24 + 0.04 * float(mini(kills, 3)))
	if kills >= 3:
		shake.shake(0.25)
	sfx.play("shot")
	if pellets_hit > 0:
		sfx.play("hit", 0.9 + 0.1 * randf())


func _on_enemy_damaged(at: Vector3, amount: float, kind: int, killed: bool) -> void:
	run.add_damage(amount)
	hud.add_damage(at, amount, kind, killed)


func _on_enemy_killed(kind: int, at: Vector3) -> void:
	run.add_kill(kind)
	sfx.play("kill", 1.1 if kind == T.Kind.RENNER else (0.75 if kind == T.Kind.BROCKEN else 1.0))
	if kind == T.Kind.BROCKEN:
		shake.shake(0.35)
		effects.ring(at, Color(1.0, 0.85, 0.4, 0.8), 0.6, 3.0, 0.4)


func _on_windup(kind: int, _at: Vector3) -> void:
	if kind == T.Kind.BROCKEN:
		sfx.play("warn")


func _on_swing(kind: int, at: Vector3, _hit: bool) -> void:
	if kind == T.Kind.BROCKEN:
		sfx.play("slam")
		shake.shake(0.3)
		effects.dust(at, 5, 0.8)
		effects.ring(at, Color(1.0, 0.45, 0.7, 0.7), 0.5, 2.4, 0.35)


func _on_hero_hurt(damage: float, _from: Vector3) -> void:
	run.damage_taken += damage
	hud.flash_hurt(0.4 + damage / 36.0)
	shake.shake(0.35 + damage * 0.01)
	sfx.play("hurt")


func _on_hero_died() -> void:
	run.die()
	shake.shake(0.6)
	sfx.play("death")
	if not _ended:
		_ended = true
		run_ended.emit()
