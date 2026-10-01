extends Node

# Stage 2, Teil B (Druck): everything that makes running away risky, on top of
# the director's steady packs (numbers in pressure_tuning.gd):
#   - announced waves every 45-60 s: "WELLE!" banner, edge arrow, danger rings
#     on the ground along the incoming direction, then a big mixed front
#   - from 2:00 every second wave is an EINKESSELUNG: a ring of Wichtel with a
#     bright gap closes slowly around the hero
#   - from 1:30 every ~75 s a champion Brocken (gold, 2x health, stomp ring);
#     its death drops a free cocoon and gold (battle.drop_chest / drop_gold)
#   - at 4:00 the Moorkönig (boss_king.gd); its death drops a boss cocoon and
#     starts a short breather (no spawns)
#   - from 6:00 the Endwelle: exponentially growing packs (director.endwave)
# Stage 4 Teil A (worlds): all times above are world time (run time minus
# world_start); start_world() begins the timeline of the next world, whose boss
# comes from pressure_tuning.gd BOSSES. After a boss that is not the last one
# the Endwelle starts PORTAL_GRACE s later unless the hero took the portal;
# while the portal is open and off-screen the edge arrow points at it.
# battle.gd creates this node, calls setup() once, step() every frame and
# reset() on NOCHMAL. The HUD part (banner, arrows, boss bar, champion bars)
# is scripts/ui/hud_pressure.gd, added to the battle's HUD layer.

signal announced(kind: String, direction: Vector3)
signal wave_spawned(kind: String, count: int)
signal boss_spawned
signal boss_defeated(at: Vector3)
signal elite_spawned(at: Vector3)

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BOSS := preload("res://scripts/enemies/boss_king.gd")
const ZONE_SHADER := preload("res://shaders/telegraph_zone.gdshader")
const HUD := preload("res://scripts/ui/hud_pressure.gd")
const DANGER := Color(1.0, 0.49, 0.76, 1.0)

enum Boss { WAITING, ANNOUNCED, FIGHTING, DEFEATED }

var battle: Node
var horde: Node3D
var director: RefCounted
var arena: Node3D
var hero: Node3D
var effects: Node3D
var hud: Control

var elapsed := 0.0
# Waves: wave_state 0 calm, 1 announced (warning runs until wave_next).
var wave_state := 0
var wave_next := PT.WAVE_FIRST
var wave_index := 0
var wave_kind := ""
var wave_angle := 0.0          # incoming direction (rad, xz: cos, sin)
var late_waves := 0            # waves announced from 2:00 on
# Encircle ring.
var ring_gap := 0.0            # gap direction (rad, xz: cos, sin)
var ring_time := 0.0
var ring_start := 0.0          # ring_radius when it spawned
# Elite and boss.
var elite_next := PT.ELITE_FROM
var boss_state := Boss.WAITING
var boss: Node3D
var breather := 0.0
var endwave_on := false
# Log and HUD state (tests read these too).
var events: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var banner := ""
var banner_tone := "danger"
var banner_age := 99.0
## Edge arrow: world direction from the hero (zero = none), label, tone.
var arrow_dir := Vector3.ZERO
var arrow_label := ""
var arrow_tone := "danger"
var arrow_left := 0.0

## Stage 4 Teil A: world of the run (0..2), its start in run time, Endwelle start
## (world time), the last world (no portal, the boss ends the run).
var world_index := 0
var world_start := 0.0
var end_at := PT.END_AT
var final_world := false
## Open portal (Vector3.INF = none); the edge arrow points at it off-screen.
var portal_at := Vector3.INF

var _ring_zone: MeshInstance3D
var _lane_zone: MeshInstance3D
var _mark_clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(owner_battle: Node) -> void:
	battle = owner_battle
	horde = battle.horde
	director = battle.director
	arena = battle.arena
	hero = battle.hero
	effects = battle.effects
	_rng.seed = 777
	horde.elite_killed.connect(_on_elite_killed)
	_ring_zone = MeshInstance3D.new()
	_ring_zone.name = "Encircle ring"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (PT.RING_RADIUS + 4.0) * 2.0
	_ring_zone.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = ZONE_SHADER
	material.set_shader_parameter("mode", 1)
	material.set_shader_parameter("ring_width", 1.5)
	material.set_shader_parameter("gap_half", PT.RING_GAP * 0.5)
	material.render_priority = 2
	_ring_zone.material_override = material
	_ring_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_zone.visible = false
	add_child(_ring_zone)
	_ring_zone.top_level = true
	# Incoming lane of a wave (chevrons running at the hero).
	_lane_zone = MeshInstance3D.new()
	_lane_zone.name = "Wave lane"
	var lane_plane := PlaneMesh.new()
	lane_plane.size = Vector2.ONE * 46.0
	_lane_zone.mesh = lane_plane
	var lane_material := ShaderMaterial.new()
	lane_material.shader = ZONE_SHADER
	lane_material.set_shader_parameter("mode", 2)
	lane_material.set_shader_parameter("radius", 3.0)
	lane_material.set_shader_parameter("lane_end", 22.0)
	lane_material.set_shader_parameter("ring_width", 4.5)
	lane_material.render_priority = 2
	_lane_zone.material_override = lane_material
	_lane_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lane_zone.visible = false
	add_child(_lane_zone)
	_lane_zone.top_level = true
	var layer: Node = battle.get("hud_layer")
	if layer != null:
		hud = HUD.new()
		hud.name = "HudPressure"
		hud.pressure = self
		layer.add_child(hud)
		# Below the touch controls and the result screen of the main HUD.
		layer.move_child(hud, mini(1, layer.get_child_count() - 1))


## Stage 4 Teil A: begins the timeline of world `index` at run time `start`.
func start_world(index: int, start: float) -> void:
	reset()
	world_index = clampi(index, 0, PT.WORLD_COUNT - 1)
	world_start = start
	final_world = world_index >= PT.WORLD_COUNT - 1


func boss_title() -> String:
	if boss != null and is_instance_valid(boss):
		return String(boss.title)
	return String(PT.BOSSES[world_index].title)


func reset() -> void:
	world_index = 0
	world_start = 0.0
	end_at = PT.END_AT
	final_world = false
	portal_at = Vector3.INF
	elapsed = 0.0
	wave_state = 0
	wave_next = PT.WAVE_FIRST
	wave_index = 0
	wave_kind = ""
	late_waves = 0
	ring_time = 0.0
	elite_next = PT.ELITE_FROM
	boss_state = Boss.WAITING
	_free_boss()
	breather = 0.0
	endwave_on = false
	events.clear()
	drops.clear()
	banner = ""
	banner_age = 99.0
	arrow_dir = Vector3.ZERO
	arrow_left = 0.0
	if horde != null:
		horde.release_ring()
	if _ring_zone != null:
		_ring_zone.visible = false
		_lane_zone.visible = false


## schedule = false: only running things (boss, ring) move on; nothing new is
## planned (tests, labs, the dead hero).
func step(delta: float, run_elapsed: float, schedule := true) -> void:
	elapsed = run_elapsed - world_start
	banner_age += delta
	arrow_left = maxf(0.0, arrow_left - delta)
	if breather > 0.0:
		breather = maxf(0.0, breather - delta)
	if schedule:
		_schedule(delta)
	_step_ring(delta)
	if _lane_zone.visible and (wave_state != 1 or wave_kind != "wave"):
		# The wave is here (or cancelled): the lane fades out.
		var material := _lane_zone.material_override as ShaderMaterial
		var opacity := float(material.get_shader_parameter("opacity")) - delta * 3.0
		material.set_shader_parameter("opacity", maxf(0.0, opacity))
		_lane_zone.visible = opacity > 0.0
	if boss != null and is_instance_valid(boss) and not boss.is_dead():
		boss.step(delta)
	if director != null:
		director.paused = breather > 0.0
		director.density_scale = PT.BOSS_DENSITY if boss_alive() else 1.0
	_update_arrow()


func boss_alive() -> bool:
	return boss != null and is_instance_valid(boss) and boss.is_alive()


func _schedule(delta: float) -> void:
	# Boss: announced, then rises near the hero.
	if boss_state == Boss.WAITING and elapsed >= PT.BOSS_AT - PT.BOSS_WARNING:
		boss_state = Boss.ANNOUNCED
		_banner(boss_title(), "danger")
		_log("announce", {"kind": "boss"})
		announced.emit("boss", Vector3.ZERO)
		_sfx("warn")
	if boss_state == Boss.ANNOUNCED and elapsed >= PT.BOSS_AT:
		spawn_boss()
	# Endwelle.
	if not endwave_on and elapsed >= end_at:
		endwave_on = true
		_banner("ENDWELLE!", "danger")
		_log("announce", {"kind": "endwave"})
		announced.emit("endwave", Vector3.ZERO)
		_sfx("warn")
	if endwave_on and director != null:
		director.endwave = maxf(0.001, elapsed - end_at)
	_schedule_waves(delta)
	# Champion Brocken (not while the boss is announced or fighting).
	if elapsed >= elite_next:
		if boss_state == Boss.ANNOUNCED or boss_alive():
			elite_next = elapsed + 5.0
		elif spawn_elite() >= 0:
			elite_next = elapsed + PT.ELITE_INTERVAL
		else:
			elite_next = elapsed + 2.0


func _schedule_waves(delta: float) -> void:
	var blocked := boss_state == Boss.ANNOUNCED or boss_alive() or breather > 0.0
	if boss_state == Boss.WAITING and PT.BOSS_AT - elapsed < PT.WAVE_BOSS_GAP and PT.BOSS_AT > elapsed:
		blocked = true
	if blocked:
		if wave_state == 1:
			wave_state = 0
			_ring_zone.visible = horde.ring_active
		# A blocked wave comes a little after the block ends, not at once.
		wave_next = maxf(wave_next, elapsed + PT.WAVE_WARNING + 2.0)
		return
	if wave_state == 0 and elapsed >= wave_next - PT.WAVE_WARNING:
		announce_wave()
	if wave_state == 1:
		_wave_marks()
		if elapsed >= wave_next:
			spawn_wave()


## Starts the warning of the next wave (kind and direction are fixed now).
func announce_wave() -> void:
	wave_state = 1
	wave_next = maxf(wave_next, elapsed + PT.WAVE_WARNING)
	var encircle := false
	if elapsed >= PT.ENCIRCLE_FROM and not horde.ring_active:
		encircle = late_waves % 2 == 0
		late_waves += 1
	wave_kind = "encircle" if encircle else "wave"
	var at := _hero_at()
	if encircle:
		ring_gap = _open_angle(at, PT.RING_RADIUS + 2.5, 1.2)
		arrow_dir = _dir(ring_gap)
		arrow_label = "LÜCKE"
		arrow_tone = "info"
		_banner("EINKESSELUNG!", "danger")
		_show_ring(at, PT.RING_RADIUS, true)
	else:
		wave_angle = _wave_angle(at)
		arrow_dir = _dir(wave_angle)
		arrow_label = "WELLE"
		arrow_tone = "danger"
		_banner("WELLE!", "danger")
	_mark_clock = 0.0
	_log("announce", {"kind": wave_kind, "angle": ring_gap if encircle else wave_angle})
	announced.emit(wave_kind, arrow_dir)
	_sfx("warn")


func _wave_angle(at: Vector3) -> float:
	# Another side than the last wave, preferring one the director can fill.
	var start := _rng.randi_range(0, 7)
	var last := wave_angle
	for k in 8:
		var a := TAU * float((start + k) % 8) / 8.0
		if wave_index > 0 and absf(angle_difference(a, last)) < 0.8:
			continue
		if director.find_spawn_point(at, a, 0.2).is_finite():
			return a
	return TAU * float(start) / 8.0


## A direction (rad) whose ground at `distance` is open (encircle gap).
func _open_angle(at: Vector3, distance: float, clearance: float) -> float:
	var start := _rng.randi_range(0, 11)
	for k in 12:
		var a := TAU * float((start + k) % 12) / 12.0
		var p := at + _dir(a) * distance
		if arena == null or not arena.has_method("is_open") or arena.is_open(p, clearance):
			return a
	return TAU * float(start) / 12.0


## Danger rings along the incoming direction (wave) or the ring line (encircle).
func _wave_marks() -> void:
	if effects == null or not is_instance_valid(effects):
		return
	var at := _hero_at()
	if wave_kind == "encircle":
		_show_ring(at, PT.RING_RADIUS, true)
		return
	_show_lane(at)


## Magenta lane from the hero towards the incoming side (follows the hero).
func _show_lane(at: Vector3) -> void:
	var dir := _dir(wave_angle)
	_lane_zone.visible = true
	_lane_zone.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(at.x, 0.065, at.z))
	var material := _lane_zone.material_override as ShaderMaterial
	material.set_shader_parameter("opacity", 1.0)


func spawn_wave() -> int:
	wave_state = 0
	var at := _hero_at()
	var count := mini(PT.WAVE_SIZE_MAX, PT.WAVE_SIZE + PT.WAVE_SIZE_STEP * wave_index)
	count = int(round(float(count) * float(PT.WORLD_DENSITY[world_index])))
	if endwave_on:
		count = int(round(float(count) * 1.5))
	var made := 0
	if wave_kind == "encircle":
		made = spawn_ring(at)
	else:
		made = _spawn_front(at, count)
	wave_index += 1
	var gap: Array = PT.WAVE_INTERVAL
	wave_next = elapsed + (PT.END_WAVE_INTERVAL if endwave_on else _rng.randf_range(float(gap[0]), float(gap[1])))
	arrow_left = 1.5
	_log("spawn", {"kind": wave_kind, "count": made})
	wave_spawned.emit(wave_kind, made)
	if battle != null and battle.get("shake") != null:
		battle.shake.shake(0.25)
	_sfx("slam")
	return made


## A broad front of mixed enemies just outside the view on the wave's side.
func _spawn_front(at: Vector3, count: int) -> int:
	var center: Vector3 = director.find_spawn_point(at, wave_angle, 0.15)
	if not center.is_finite():
		return 0
	var base := at.distance_to(center)
	var made := 0
	var brocken := 1 if elapsed >= PT.WAVE_BROCKEN_FROM else 0
	var tries := 0
	while made < count and tries < count * 3:
		tries += 1
		var a := wave_angle + _rng.randf_range(-PT.WAVE_FRONT_SPREAD, PT.WAVE_FRONT_SPREAD)
		var spot := at + _dir(a) * (base + _rng.randf_range(0.0, 4.0))
		var kind := T.Kind.WICHTEL
		if brocken > 0:
			kind = T.Kind.BROCKEN
		elif elapsed >= T.RENNER_FROM and _rng.randf() < PT.WAVE_RENNER_SHARE:
			kind = T.Kind.RENNER
		if director.place(kind, spot, at) >= 0:
			made += 1
			if kind == T.Kind.BROCKEN:
				brocken -= 1
	return made


## Ring of Wichtel around `center` with a gap of RING_GAP metres at ring_gap.
func spawn_ring(center: Vector3) -> int:
	horde.release_ring()
	horde.ring_center = Vector3(center.x, 0.0, center.z)
	horde.ring_radius = PT.RING_RADIUS
	horde.ring_gap = ring_gap
	horde.ring_gap_width = PT.RING_GAP
	horde.ring_active = true
	ring_time = 0.0
	ring_start = PT.RING_RADIUS
	var span := TAU - PT.RING_GAP / PT.RING_RADIUS
	var slots := int(floor(span * PT.RING_RADIUS / PT.RING_SPACING))
	slots = mini(slots, T.ENEMY_CAP - horde.count())
	var made := 0
	if slots >= 2:
		for k in slots:
			# From one gap edge to the other (the gap itself stays empty).
			if horde.spawn_ring_member(T.Kind.WICHTEL, (float(k) + 0.5) / float(slots), director.hp_mult()) >= 0:
				made += 1
	if made == 0:
		horde.ring_active = false
	_show_ring(center, PT.RING_RADIUS, false)
	return made


func _step_ring(delta: float) -> void:
	if not horde.ring_active:
		if wave_state != 1 or wave_kind != "encircle":
			_fade_ring(delta)
		return
	ring_time += delta
	horde.ring_radius = maxf(PT.RING_END_RADIUS, horde.ring_radius - PT.RING_SPEED * delta)
	var hero_out: bool = _hero_at().distance_to(horde.ring_center) > horde.ring_radius + PT.RING_ESCAPE
	if horde.ring_radius <= PT.RING_END_RADIUS + 0.001 or ring_time >= PT.RING_MAX_SECONDS or hero_out or horde.count_ring() == 0:
		horde.release_ring()
		_log("ring_end", {"escaped": hero_out, "radius": horde.ring_radius})
		return
	_show_ring(horde.ring_center, horde.ring_radius, false)


func _show_ring(center: Vector3, radius: float, warning: bool) -> void:
	_ring_zone.visible = true
	_ring_zone.global_transform = Transform3D(Basis.IDENTITY, Vector3(center.x, 0.06, center.z))
	var material := _ring_zone.material_override as ShaderMaterial
	material.set_shader_parameter("radius", radius)
	# Shader angle: atan(x, z) of the gap direction (cos, sin) in xz.
	material.set_shader_parameter("gap_angle", atan2(cos(ring_gap), sin(ring_gap)))
	var pulse := 0.55 + 0.45 * absf(sin(elapsed * 6.0)) if warning else 1.0
	material.set_shader_parameter("opacity", pulse)


func _fade_ring(delta: float) -> void:
	if not _ring_zone.visible:
		return
	var material := _ring_zone.material_override as ShaderMaterial
	var opacity := float(material.get_shader_parameter("opacity")) - delta * 2.5
	material.set_shader_parameter("opacity", maxf(0.0, opacity))
	if opacity <= 0.0:
		_ring_zone.visible = false


func ring_visible() -> bool:
	return _ring_zone != null and _ring_zone.visible


func lane_visible() -> bool:
	return _lane_zone != null and _lane_zone.visible


## A champion Brocken off-screen on one of the pack sides. Returns its index.
func spawn_elite() -> int:
	var at := _hero_at()
	for k in 4:
		var spot: Vector3 = director.find_spawn_point(at, director.pick_angle())
		if not spot.is_finite():
			continue
		var index: int = director.place(T.Kind.BROCKEN, spot, at, true)
		if index >= 0:
			_banner("CHAMPION!", "loot")
			_log("elite", {"at": horde.position_of(index)})
			elite_spawned.emit(horde.position_of(index))
			return index
	return -1


func spawn_boss() -> Node3D:
	_free_boss()
	boss_state = Boss.FIGHTING
	var at := _hero_at()
	var spot := Vector3.INF
	var start := _rng.randi_range(0, 7)
	for k in 8:
		var a := TAU * float((start + k) % 8) / 8.0
		var p := at + _dir(a) * PT.BOSS_SPAWN_DISTANCE
		if arena == null or not arena.has_method("is_open") or arena.is_open(p, PT.BOSS_RADIUS + 0.5):
			spot = p
			break
	if not spot.is_finite():
		spot = at + Vector3(0, 0, -PT.BOSS_SPAWN_DISTANCE)
		if arena != null and arena.has_method("safe_spawn"):
			spot = arena.safe_spawn(spot, PT.BOSS_RADIUS)
	boss = BOSS.new()
	var config: Dictionary = PT.BOSSES[world_index]
	boss.name = String(config.id).capitalize()
	if world_index > 0:
		boss.configure(config)
	boss.setup(arena, hero, effects)
	boss.position = Vector3(spot.x, 0.0, spot.z)
	var host: Node = battle.get_parent() if battle != null and battle.get_parent() != null else self
	host.add_child(boss)
	horde.boss = boss
	boss.attack_started.connect(_on_boss_attack_started)
	boss.attack_landed.connect(_on_boss_attack_landed)
	boss.defeated.connect(_on_boss_defeated)
	if effects != null and is_instance_valid(effects):
		effects.ring(boss.position, config.ring, 0.8, 4.5, 0.9)
		effects.ring(boss.position, Color(0.66, 0.45, 0.95, 0.75), 0.4, 3.2, 1.2)
	if battle != null and battle.get("shake") != null:
		battle.shake.shake(0.4)
	_log("boss", {"at": boss.position})
	boss_spawned.emit()
	return boss


func _free_boss() -> void:
	if horde != null:
		horde.boss = null
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	boss = null


func _on_boss_attack_started(_pattern: int, _center: Vector3) -> void:
	_sfx("warn")


func _on_boss_attack_landed(_pattern: int, _center: Vector3, _hit: bool) -> void:
	_sfx("slam")
	if battle != null and battle.get("shake") != null:
		battle.shake.shake(0.45)


func _on_boss_defeated(at: Vector3) -> void:
	boss_state = Boss.DEFEATED
	breather = PT.BREATHER
	horde.boss = null
	_banner("SIEG!", "loot")
	_log("boss_defeated", {"at": at, "world": world_index})
	if not final_world:
		# The portal opens here (worlds.gd); dawdling brings the Endwelle.
		end_at = minf(end_at, elapsed + PT.PORTAL_GRACE)
		_drop(at, "boss", PT.BOSS_GOLD)
		if battle != null and battle.has_method("drop_xp"):
			battle.drop_xp(at, 150)
	if battle != null and battle.get("run") != null and battle.run.has_method("add_kill"):
		battle.run.add_kill(-1)
	boss_defeated.emit(at)


func _on_elite_killed(at: Vector3) -> void:
	_log("elite_killed", {"at": at})
	_drop(at, "elite", PT.ELITE_GOLD)


## Asks the battle for a cocoon and gold (Teil A provides them); always logged.
func _drop(at: Vector3, kind: String, gold: int) -> void:
	var chest := battle != null and battle.has_method("drop_chest")
	var coins := battle != null and battle.has_method("drop_gold")
	if chest:
		# battle.gd names the elite cocoon "free" (any unknown kind falls back to it).
		battle.drop_chest(at, "free" if kind == "elite" else kind)
	if coins:
		battle.drop_gold(at, gold)
	drops.append({"kind": kind, "at": at, "gold": gold, "chest_called": chest, "gold_called": coins})


# ---------------------------------------------------------------- helpers

## Edge arrow follows the current reason: wave warning, ring gap, champion.
func _update_arrow() -> void:
	if wave_state == 1 or arrow_left > 0.0:
		return
	# Inside a closing ring: point at the gap.
	if horde.ring_active and _hero_at().distance_to(horde.ring_center) < horde.ring_radius + 0.5:
		arrow_dir = _dir(ring_gap)
		arrow_label = "LÜCKE"
		arrow_tone = "info"
		return
	arrow_dir = Vector3.ZERO
	# The open portal off-screen: point at it (the way on).
	if portal_at.is_finite():
		var to_portal := portal_at - _hero_at()
		to_portal.y = 0.0
		var on_screen: bool = director != null and director.camera != null and director.in_view(portal_at, _hero_at())
		if to_portal.length() > 3.0 and not on_screen:
			arrow_dir = to_portal.normalized()
			arrow_label = "PORTAL"
			arrow_tone = "info"
			return
	# A living champion off-screen: point at him (he carries a cocoon).
	for i in horde.count():
		if horde.is_elite(i):
			var offset: Vector3 = horde.position_of(i) - _hero_at()
			if offset.length() > 9.0:
				arrow_dir = Vector3(offset.x, 0.0, offset.z).normalized()
				arrow_label = "CHAMPION"
				arrow_tone = "loot"
			return


func _banner(text: String, tone: String) -> void:
	banner = text
	banner_tone = tone
	banner_age = 0.0


func _log(what: String, data: Dictionary) -> void:
	data["t"] = elapsed
	data["what"] = what
	events.append(data)


func _sfx(id: String) -> void:
	if battle != null and battle.get("sfx") != null and battle.sfx.has_method("play"):
		battle.sfx.play(id)


func _hero_at() -> Vector3:
	if hero == null or not is_instance_valid(hero):
		return Vector3.ZERO
	return Vector3(hero.position.x, 0.0, hero.position.z)


static func _dir(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


## Shown danger shapes (boss telegraph) for bots: [{center, radius, dir, half, left}].
func danger_zones() -> Array:
	var zones := []
	if boss_alive():
		var zone: Dictionary = boss.danger_zone()
		if not zone.is_empty():
			zones.append(zone)
	return zones


func events_of(what: String) -> Array:
	var found := []
	for event in events:
		if event.what == what:
			found.append(event)
	return found
