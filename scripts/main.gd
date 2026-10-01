extends Node3D

# Root of the game scene. Owns the world (Arena), the game camera and the sun;
# the hero and the combat systems (stage 01 Teil B) are added as children of
# Main. Kept small on purpose:
#   hero   - Node3D the camera follows and the map streams around. Until Teil B
#            gives it a script, WASD moves the placeholder capsule here.
#   arena  - scripts/world/arena.gd (map, collision, spawns, flow field).
# Main runs after its children every frame (process_priority), so the map and
# the camera always see the hero's newest position.

const BIOMES = preload("res://scripts/world/biomes.gd")
const QUALITY = preload("res://scripts/world/quality.gd")
const SESSION := preload("res://scripts/core/session.gd")
const PAUSE := preload("res://scripts/ui/pause_screen.gd")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
# Camera follow sharpness (1/s, exponential smoothing like Mawlings).
const CAMERA_FOLLOW := 5.0
const DEFAULT_SEED := 4242
const PLACEHOLDER_SPEED := 6.0
const PLACEHOLDER_RADIUS := 0.6

@onready var arena: Node3D = $Arena
@onready var hero: Node3D = $Hero
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun

var world_seed := DEFAULT_SEED
var biome_id: String = BIOMES.DEFAULT
## Purely visual camera offset added on top of the follow position (shake,
## recoil kick); Teil B writes it, it is not smoothed.
var camera_jitter := Vector3.ZERO
var _camera_base := Vector3.ZERO


func _ready() -> void:
	process_priority = 100
	QUALITY.apply_viewport(get_viewport(), QUALITY.settings())
	# Stage 3: run configuration from the menu (Session.config), settings.
	SESSION.apply_settings()
	world_seed = SESSION.world_seed(world_seed)
	biome_id = SESSION.biome(biome_id)
	arena.chunk_budget = 1
	start_world(world_seed, biome_id)
	_wire_session()


# Stage 3 Teil A: pause screen on top of the HUD, MENÜ (pause / result) back
# to the title, finished runs into the profile, vibration on hits.
func _wire_session() -> void:
	var battle := get_node_or_null("Battle")
	if battle == null or battle.get("hud_layer") == null:
		return
	var pause: Control = PAUSE.new()
	pause.name = "Pause"
	pause.battle = battle
	battle.hud_layer.add_child(pause)
	pause.menu_requested.connect(go_to_menu)
	battle.controls.menu_requested.connect(go_to_menu)
	battle.run_ended.connect(func() -> void: SESSION.record_run(battle.run))
	# Stage 4: a won run (boss of world 3) is booked like a finished one.
	if battle.has_signal("run_won"):
		battle.run_won.connect(func() -> void: SESSION.record_run(battle.run))
	battle.hero.hurt.connect(func(damage: float, _from: Vector3) -> void: SESSION.vibrate(clampi(int(25.0 + damage * 2.0), 25, 90)))


## Back to the title screen (scenes/menu.tscn).
func go_to_menu() -> void:
	SESSION.to_menu(get_tree())


## (Re)builds the map for `seed_value` in biome `id`, puts the hero on the start
## point and snaps the camera. Safe to call again for a restart; stage 4: the
## portal (scripts/core/worlds.gd) calls it for the next world of the run.
func start_world(seed_value: int, id: String = BIOMES.DEFAULT) -> void:
	world_seed = seed_value
	biome_id = id if BIOMES.has(id) else BIOMES.DEFAULT
	arena.set_biome(biome_id)
	arena.set_seed(world_seed)
	_apply_light()
	var start: Vector3 = arena.spawn_points(1)[0]
	hero.position = start
	arena.sync(start)
	arena.finish_rebuild()
	arena.finish_flow(start)
	snap_camera()


func _process(delta: float) -> void:
	if hero.get_script() == null:
		_move_placeholder(delta)
	arena.sync(hero.position)
	var target := Vector3(hero.position.x, 0.0, hero.position.z)
	_camera_base = _camera_base.lerp(target + CAMERA_OFFSET, 1.0 - exp(-CAMERA_FOLLOW * delta))
	camera.position = _camera_base + camera_jitter
	camera.look_at(_camera_base - CAMERA_OFFSET + camera_jitter * 0.5, Vector3.UP)


## Puts the camera straight onto the hero (start, restart, captures).
func snap_camera() -> void:
	var target := Vector3(hero.position.x, 0.0, hero.position.z)
	_camera_base = target + CAMERA_OFFSET
	camera.position = _camera_base
	camera.look_at(target, Vector3.UP)


func _apply_light() -> void:
	var light: Dictionary = BIOMES.get_data(biome_id).get("light", {})
	sun.light_color = light.get("color", Color(1, 1, 1))
	sun.light_energy = float(light.get("energy", 1.15))


# WASD / arrow keys for the placeholder capsule (replaced by the hero script).
func _move_placeholder(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if input == Vector2.ZERO:
		return
	input = input.normalized()
	var motion := Vector3(input.x, 0.0, input.y) * PLACEHOLDER_SPEED * delta
	hero.position = arena.resolve_motion(hero.position, motion, PLACEHOLDER_RADIUS)
