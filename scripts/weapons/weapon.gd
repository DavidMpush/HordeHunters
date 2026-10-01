extends Node

# Common base of all weapons (stage 3, Teil B §1).
#   id / source     catalogue id (progress.gd WEAPONS) and the name damage is
#                   booked on for the result page (run.damage_by_source)
#   cooldown        seconds between attacks (cooldown_time(): base / fire rate)
#   rank()          level 1..6 from the build (hero.build.weapon_rank, 0 = not owned),
#                   rank_override >= 0 wins (tests); power() = rarity units
#   targeting       nearest_target(range) via horde.nearest_index (boss incl.)
#   damage          base x hero.stat("damage_mult"), crit doubles
#   hits            apply(hits) books the damage on `source`, then
#                   horde.apply_hits(); knock_for(index, scale) by mass
# Subclasses override step(delta) (attack logic) and reset(); battle.gd steps
# every weapon in order after the hero. Feedback hooks (camera, sound,
# hitstop) are optional and null-safe.

signal hitstop_requested(frames: int)

const T := preload("res://scripts/core/tuning.gd")
const BOSS_SLOT := T.ENEMY_CAP + 1
const TOON := preload("res://shaders/toon_part.gdshader")

## Catalogue id (progress.gd WEAPONS) and damage source on the result page.
var id := ""
var source := ""
var hero: Node3D
var horde: Node3D
var effects: Node3D
## Optional: run (damage per source), camera shake, sound.
var run: RefCounted
var shake: Node
var sfx: Node
## >= 0: fixed rank (tests); < 0: read from the build.
var rank_override := -1
## Seconds until the next attack.
var cooldown_left := 0.0
var attacks := 0
var kills := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 1234


# ---------------------------------------------------------------- build

func _stat(stat_id: String) -> float:
	if hero != null and hero.has_method("stat"):
		return hero.stat(stat_id)
	return 1.0 if stat_id.ends_with("_mult") else 0.0


## Level 1..6 (1 = just taken), 0 without a build entry.
func rank() -> int:
	if rank_override >= 0:
		return rank_override
	var build: Variant = hero.get("build") if hero != null else null
	if build != null and build.has_method("weapon_rank"):
		return int(build.weapon_rank(id))
	return 0


## Sum of the rarity factors picked for this weapon (like stats; rank if unknown).
func power() -> float:
	if rank_override >= 0:
		return float(rank_override)
	var build: Variant = hero.get("build") if hero != null else null
	if build != null and build.has_method("weapon_power"):
		return float(build.weapon_power(id))
	return float(rank())


## Damage factor of the weapon from its power (1 unit = x1, 5 = x2;
## same formula as progress.gd power_factor).
func power_factor() -> float:
	return 0.75 + 0.25 * maxf(1.0, power())


func damage_mult() -> float:
	return _stat("damage_mult")


## Damage with the build multiplier and a crit roll (doubles).
func roll_damage(base: float) -> float:
	var damage := base * damage_mult()
	var crit := _stat("crit")
	if crit > 0.0 and _rng.randf() < crit:
		damage *= 2.0
	return damage


func cooldown_time(base: float) -> float:
	return base / maxf(0.1, _stat("fire_rate_mult"))


func range_mult() -> float:
	return _stat("range_mult")


# ---------------------------------------------------------------- state

func reset() -> void:
	cooldown_left = 0.0
	attacks = 0
	kills = 0


## HUD hooks (the shotgun shows its shells; other weapons have none).
func max_shells() -> int:
	return 0


func reload_progress() -> float:
	return -1.0


func step(_delta: float) -> void:
	pass


func can_act() -> bool:
	if hero == null or horde == null:
		return false
	return not (hero.has_method("is_dead") and hero.is_dead())


func hero_at() -> Vector3:
	return Vector3(hero.position.x, 0.0, hero.position.z)


# ---------------------------------------------------------------- targets

func nearest_target(max_range: float) -> int:
	return horde.nearest_index(hero_at(), max_range)


## Living enemies (and the boss) whose body reaches into the circle.
func enemies_in_circle(center: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	var c := Vector3(center.x, 0.0, center.z)
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var r: float = radius + float(horde.radius_of_kind(horde.kind_of(i)))
		if Vector2(p.x - c.x, p.z - c.z).length_squared() <= r * r:
			out.append(i)
	if boss_in_circle(c, radius):
		out.append(BOSS_SLOT)
	return out


## Enemies inside a sector (centre, unit direction, reach, half angle in rad).
## The body radius counts for the reach and widens the angle a little.
func enemies_in_arc(center: Vector3, direction: Vector3, reach: float, half_angle: float) -> Array[int]:
	var out: Array[int] = []
	var c := Vector3(center.x, 0.0, center.z)
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var off := Vector3(p.x - c.x, 0.0, p.z - c.z)
		var d := off.length()
		var body: float = horde.radius_of_kind(horde.kind_of(i))
		if d > reach + body:
			continue
		if d > 0.05:
			var slack := asin(clampf(body / d, 0.0, 1.0))
			if dir.angle_to(off / d) > half_angle + slack:
				continue
		out.append(i)
	if horde.get("boss") != null and is_instance_valid(horde.boss) and horde._boss_targetable():
		var b: Vector3 = horde.position_of(BOSS_SLOT)
		var off := Vector3(b.x - c.x, 0.0, b.z - c.z)
		var d := off.length()
		var body: float = horde._boss_radius()
		if d <= reach + body and (d < 0.05 or dir.angle_to(off / d) <= half_angle + asin(clampf(body / maxf(d, 0.001), 0.0, 1.0))):
			out.append(BOSS_SLOT)
	return out


func boss_in_circle(center: Vector3, radius: float) -> bool:
	if horde.get("boss") == null or not is_instance_valid(horde.boss) or not horde._boss_targetable():
		return false
	var b: Vector3 = horde.position_of(BOSS_SLOT)
	var r: float = radius + horde._boss_radius()
	return Vector2(b.x - center.x, b.z - center.z).length_squared() <= r * r


## Knock speed by the mass of enemy `index`; `scale` per mass class:
## [light, medium, heavy]. Bosses never move.
func knock_by_mass(index: int, speeds: Array) -> float:
	if index == BOSS_SLOT:
		return 0.0
	var masses: Variant = horde.get("_mass")
	var kind: int = horde.kind_of(index)
	var mass := T.Mass.LIGHT
	if masses is PackedInt32Array and kind >= 0 and kind < (masses as PackedInt32Array).size():
		mass = (masses as PackedInt32Array)[kind]
	if horde.has_method("is_elite") and horde.is_elite(index):
		mass = T.Mass.HEAVY
	return float(speeds[clampi(mass, 0, speeds.size() - 1)])


## Mass class of enemy `index` (bosses count as heavy).
func mass_of(index: int) -> int:
	if index == BOSS_SLOT:
		return T.Mass.HEAVY
	var masses: Variant = horde.get("_mass")
	var kind: int = horde.kind_of(index)
	if masses is PackedInt32Array and kind >= 0 and kind < (masses as PackedInt32Array).size():
		return (masses as PackedInt32Array)[kind]
	return T.Mass.LIGHT


# ---------------------------------------------------------------- hits

## Applies {index: {"damage", "dir", "knock"?}} booked on this weapon's source.
## Returns the kills.
func apply(hits: Dictionary) -> int:
	if hits.is_empty():
		return 0
	var before := ""
	if run != null:
		before = String(run.damage_source)
		run.damage_source = source
	var killed: int = horde.apply_hits(hits)
	if run != null:
		run.damage_source = before
	kills += killed
	return killed


# ---------------------------------------------------------------- feedback

func _shake(amount: float) -> void:
	if shake != null and is_instance_valid(shake):
		shake.shake(amount)


func _kick(direction: Vector3, amount: float) -> void:
	if shake != null and is_instance_valid(shake):
		shake.kick(direction, amount)


func _sound(sound_id: String, pitch: float = 1.0) -> void:
	if sfx != null and is_instance_valid(sfx):
		sfx.play(sound_id, pitch)


func _fx() -> bool:
	return effects != null and is_instance_valid(effects)


# ---------------------------------------------------------------- meshes

## Toon material like the hero parts (shaders/toon_part.gdshader).
static func toon(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TOON
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("brightness", 1.08)
	material.set_shader_parameter("saturation", 1.15)
	material.set_shader_parameter("shape_light", 0.42)
	material.set_shader_parameter("rim_color", Color("ffe9c0"))
	material.set_shader_parameter("rim_strength", 0.6)
	material.set_shader_parameter("rim_power", 3.0)
	return material


static func part(parent: Node3D, mesh: Mesh, color: Color, xform: Transform3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = toon(color)
	node.transform = xform
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func ball(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


## Unshaded flat ring on the ground (markers), radius 1 (scale it).
static func ground_ring(parent: Node3D, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.86
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.render_priority = 2
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
