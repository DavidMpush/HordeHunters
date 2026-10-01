extends Node3D

# Cocoons in the world (stage 2, Teil A §3), after Mawlings chests.gd:
#   map   silk cocoons on arena.poi_slots("cocoon"); opening costs gold
#         (progress.chest_price(), rises with every bought cocoon).
#   free  small cocoon dropped by an elite (Teil B: battle.drop_chest(at)),
#         free, at least rare.
#   boss  big golden cocoon (boss victory), free, at least epic.
# Opening: stand in the ring for HOLD_SECONDS. Too little gold: the ring turns
# grey and the price pill red; step out and back in to try again. The cocoon
# swells, bursts (shards + a light beam in the rarity colour of the best
# card) and emits `burst(entry)`; progression then opens the 1-of-3 choice.
# Cocoons stay until opened. Logic and animation only run in step(), so the
# choice pause freezes them.
#
# entry: {at, kind, hold, state (0 closed, 1 swelling, 2 opened), anim, denied,
#         phase, node, body, ring, paid}

signal burst(entry: Dictionary)

const UiStyle := preload("res://scripts/ui/ui_style.gd")

const HOLD_SECONDS := 0.5
const HOLD_RADIUS := {"map": 1.9, "free": 1.7, "boss": 2.6}
const SIZE := {"map": 0.85, "free": 0.7, "boss": 1.3}
const PULSE_SECONDS := 0.35
const BEAM_SECONDS := 1.4
## Map cocoons when the arena has no slots (flat lab / seed 0).
const FALLBACK_MAP := 6
const SILK := Color("f4ead2")
const SILK_DARK := Color("cdb994")

var cocoons: Array[Dictionary] = []
var arena: Node3D
## Callables set by progression: price() -> int, pay(price) -> bool.
var price_of := Callable()
var pay := Callable()
var opened := 0
var opened_by_kind := {"map": 0, "free": 0, "boss": 0}
var _layout: Variant = null
var _placed := false
var _time := 0.0
var _beams: Array[Dictionary] = []
static var _meshes := {}
static var _materials := {}


func setup(arena_node: Node3D) -> void:
	arena = arena_node


## New run: map cocoons back on their slots, dropped ones gone.
func reset() -> void:
	for entry in cocoons:
		if entry.node != null and is_instance_valid(entry.node):
			entry.node.queue_free()
	cocoons.clear()
	for beam in _beams:
		if is_instance_valid(beam.node):
			beam.node.queue_free()
	_beams.clear()
	opened = 0
	opened_by_kind = {"map": 0, "free": 0, "boss": 0}
	_placed = false
	_layout = null


# ---------------------------------------------------------------- placement

func _place_map() -> void:
	_placed = true
	_layout = arena.get("layout") if arena != null else null
	for index in range(cocoons.size() - 1, -1, -1):
		var entry: Dictionary = cocoons[index]
		if entry.kind == "map" and int(entry.state) == 0:
			if entry.node != null:
				entry.node.queue_free()
			cocoons.remove_at(index)
	var slots: Array = []
	if arena != null and arena.has_method("poi_slots"):
		slots = arena.poi_slots("cocoon")
	if slots.is_empty():
		slots = _fallback_spots(FALLBACK_MAP)
	for at in slots:
		_add("map", at)


func _fallback_spots(count: int) -> Array:
	var out: Array = []
	var centre: Vector3 = arena.map_center() if arena != null and arena.has_method("map_center") else Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for index in count:
		var angle := float(index) * 2.39996323 + rng.randf() * 0.6
		var distance := 14.0 + 7.0 * float(index) + rng.randf_range(-2.0, 2.0)
		out.append(_open_spot(centre + Vector3(cos(angle), 0.0, sin(angle)) * distance, 1.4))
	return out


func _open_spot(point: Vector3, radius: float) -> Vector3:
	var spot := Vector3(point.x, 0.0, point.z)
	if arena != null and arena.has_method("safe_spawn"):
		spot = arena.safe_spawn(spot, radius)
		spot.y = 0.0
	return spot


func _add(kind: String, at: Vector3) -> Dictionary:
	var entry := {"at": Vector3(at.x, 0.0, at.z), "kind": kind, "hold": 0.0, "state": 0, "anim": 0.0,
		"denied": false, "phase": float(cocoons.size()) * 1.7, "node": null, "body": null, "ring": null, "paid": 0}
	cocoons.append(entry)
	if is_inside_tree():
		_build_node(entry)
	return entry


## Free cocoon at `at` (elite: "free", boss: "boss"; "map" costs gold).
func drop_chest(at: Vector3, kind: String = "free") -> Dictionary:
	if not HOLD_RADIUS.has(kind):
		kind = "free"
	return _add(kind, _open_spot(at, 1.2))


func closed_count(kind: String = "") -> int:
	var total := 0
	for entry in cocoons:
		if int(entry.state) == 0 and (kind == "" or entry.kind == kind):
			total += 1
	return total


## Nearest closed cocoon within `reach` ({} when none).
func nearest(point: Vector3, reach: float = 1000.0, kind: String = "") -> Dictionary:
	var best := {}
	var best_d := reach
	for entry in cocoons:
		if int(entry.state) != 0 or (kind != "" and entry.kind != kind):
			continue
		var d := Vector2(entry.at.x - point.x, entry.at.z - point.z).length()
		if d < best_d:
			best_d = d
			best = entry
	return best


func price(entry: Dictionary) -> int:
	if String(entry.kind) != "map":
		return 0
	return int(price_of.call()) if price_of.is_valid() else 0


# ---------------------------------------------------------------- update

func step(delta: float, centre: Vector3, can_open: bool = true) -> void:
	_time += delta
	if arena != null and (not _placed or arena.get("layout") != _layout):
		# Wait for the generated layout (its cocoon slots); an open map without
		# one gets fallback spots after a moment.
		var ready_now: bool = not arena.has_method("has_layout") or arena.has_layout()
		if ready_now or (not _placed and _time > 1.0):
			_place_map()
	for index in range(cocoons.size() - 1, -1, -1):
		var entry: Dictionary = cocoons[index]
		match int(entry.state):
			0:
				_step_closed(entry, delta, centre, can_open)
			1:
				entry.anim += delta
				if float(entry.anim) >= PULSE_SECONDS:
					_burst(entry)
				else:
					_animate_pulse(entry)
			2:
				entry.anim += delta
				if float(entry.anim) >= 0.6:
					if entry.node != null:
						entry.node.queue_free()
					cocoons.remove_at(index)
				else:
					_animate_shards(entry)
	_step_beams(delta)


func _step_closed(entry: Dictionary, delta: float, centre: Vector3, can_open: bool) -> void:
	var flat := Vector2(entry.at.x - centre.x, entry.at.z - centre.z).length()
	var inside := flat <= float(HOLD_RADIUS[entry.kind])
	if inside and can_open and not bool(entry.denied):
		entry.hold = minf(HOLD_SECONDS, float(entry.hold) + delta)
		if float(entry.hold) >= HOLD_SECONDS:
			var cost := price(entry)
			if cost > 0 and not (pay.is_valid() and bool(pay.call(cost))):
				entry.denied = true
			else:
				entry.paid = cost
				entry.state = 1
				entry.anim = 0.0
				return
	elif not inside:
		entry.hold = maxf(0.0, float(entry.hold) - delta * 2.0)
		entry.denied = false
	if flat < 40.0:
		_animate_idle(entry)


## Opens a closed cocoon at once (tests, captures). Pays like a hold would.
func open_now(entry: Dictionary) -> bool:
	if int(entry.state) != 0:
		return false
	var cost := price(entry)
	if cost > 0 and not (pay.is_valid() and bool(pay.call(cost))):
		entry.denied = true
		return false
	entry.paid = cost
	_burst(entry)
	return true


func _burst(entry: Dictionary) -> void:
	entry.state = 2
	entry.anim = 0.0
	opened += 1
	opened_by_kind[entry.kind] = int(opened_by_kind.get(entry.kind, 0)) + 1
	burst.emit(entry)


## Opening moment: shards and a beam in `rarity` colour (progression calls it
## once the offers are rolled).
func play_moment(entry: Dictionary, rarity: String) -> void:
	if entry.node == null:
		return
	_spawn_shards(entry, rarity)
	if entry.body != null:
		(entry.body as Node3D).visible = false
	if entry.ring != null:
		(entry.ring as Node3D).visible = false
	_beam(entry.at, rarity, float(SIZE[entry.kind]))


# ---------------------------------------------------------------- visuals

static func _glow_color(kind: String) -> Color:
	return UiStyle.brawl_tone("loot")["light"] if kind == "boss" else (UiStyle.brawl_tone("special")["light"] if kind == "free" else UiStyle.brawl_tone("loot")["face"])


static func _shell(kind: String) -> Color:
	return UiStyle.brawl_tone("loot")["face"] if kind == "boss" else SILK


static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		"egg":
			var egg := SphereMesh.new()
			egg.radius = 0.74
			egg.height = 2.0
			egg.radial_segments = 20
			egg.rings = 12
			mesh = egg
		"band":
			var band := TorusMesh.new()
			band.inner_radius = 0.62
			band.outer_radius = 0.8
			band.rings = 24
			band.ring_segments = 6
			mesh = band
		"seam":
			var seam := CapsuleMesh.new()
			seam.radius = 0.13
			seam.height = 1.35
			seam.radial_segments = 8
			seam.rings = 2
			mesh = seam
		"mound":
			var mound := SphereMesh.new()
			mound.radius = 0.95
			mound.height = 0.7
			mound.radial_segments = 16
			mound.rings = 6
			mound.is_hemisphere = true
			mesh = mound
		"ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.9
			ring.outer_radius = 1.0
			ring.rings = 48
			ring.ring_segments = 4
			mesh = ring
		"spike":
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = 0.13
			spike.height = 0.55
			spike.radial_segments = 6
			spike.rings = 1
			mesh = spike
		"beam":
			var beam := CylinderMesh.new()
			beam.top_radius = 0.25
			beam.bottom_radius = 0.75
			beam.height = 1.0
			beam.radial_segments = 20
			beam.rings = 1
			beam.cap_top = false
			beam.cap_bottom = false
			mesh = beam
		"halo":
			var halo := CylinderMesh.new()
			halo.top_radius = 1.0
			halo.bottom_radius = 1.0
			halo.height = 0.02
			halo.radial_segments = 32
			halo.rings = 1
			mesh = halo
		"shard":
			var shard := SphereMesh.new()
			shard.radius = 0.16
			shard.height = 0.26
			shard.radial_segments = 6
			shard.rings = 3
			mesh = shard
	_meshes[key] = mesh
	return mesh


static func _material(key: String, color: Color, glow: float = 0.0, unshaded := false, transparent := false) -> StandardMaterial3D:
	var id := "%s:%s:%.2f:%s:%s" % [key, color.to_html(true), glow, unshaded, transparent]
	if _materials.has(id):
		return _materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not unshaded:
		material.rim_enabled = true
		material.rim = 0.55
		material.rim_tint = 0.3
	_materials[id] = material
	return material


static func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = Transform3D(basis, at)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _ready() -> void:
	for entry in cocoons:
		if entry.node == null:
			_build_node(entry)


# Silk cocoon on a small mound (Mawlings look): egg wrapped in three bands, a
# glowing seam towards the camera, a hold ring on the ground; the boss cocoon
# is golden with a crown of bone spikes, the elite one glows violet.
func _build_node(entry: Dictionary) -> void:
	var kind: String = entry.kind
	var scale_value: float = SIZE[kind]
	var root := Node3D.new()
	root.name = "Cocoon %s" % kind
	root.position = entry.at
	add_child(root)
	var shell := _shell(kind)
	var glow := _glow_color(kind)
	var dark: Color = shell.darkened(0.25)
	var ring := _piece(root, _mesh("ring"), _material("ring", Color(glow, 0.6), 0.0, true, true), Vector3(0, 0.05, 0), Basis.from_scale(Vector3(HOLD_RADIUS[kind], 0.3, HOLD_RADIUS[kind])))
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * scale_value
	root.add_child(body)
	_piece(root, _mesh("halo"), _material("halo", Color(glow, 0.22), 0.0, true, true), Vector3(0, 0.035, 0), Basis.from_scale(Vector3(1.7, 1.0, 1.7) * scale_value))
	_piece(body, _mesh("mound"), _material("mound", SILK_DARK.darkened(0.25) if kind != "boss" else dark.darkened(0.1)), Vector3.ZERO, Basis.from_scale(Vector3(1.2, 0.45, 1.2)))
	var tuft := _material("tuft", SILK if kind != "boss" else shell.lightened(0.15))
	for i in 6:
		var angle := TAU * float(i) / 6.0 + 0.3
		_piece(body, _mesh("shard"), tuft, Vector3(cos(angle) * 0.95, 0.12, sin(angle) * 0.95), Basis.from_scale(Vector3(1.8, 0.9, 1.8)))
	_piece(body, _mesh("egg"), _material("shell", shell, 0.12), Vector3(0, 1.1, 0), Basis.from_scale(Vector3(0.95, 1.08, 0.9)))
	var band := _material("band", SILK_DARK if kind != "boss" else dark)
	_piece(body, _mesh("band"), band, Vector3(0, 0.62, 0), Basis(Vector3.RIGHT, 0.22) * Basis.from_scale(Vector3(0.98, 1.0, 0.92)))
	_piece(body, _mesh("band"), band, Vector3(0, 1.05, 0), Basis(Vector3.FORWARD, -0.32) * Basis.from_scale(Vector3(1.06, 1.0, 1.0)))
	_piece(body, _mesh("band"), band, Vector3(0, 1.5, 0), Basis(Vector3.RIGHT, -0.25) * Basis.from_scale(Vector3(0.84, 1.0, 0.8)))
	_piece(body, _mesh("seam"), _material("seam", glow, 2.6, true), Vector3(0, 1.08, 0.64), Basis(Vector3.RIGHT, -0.2) * Basis.from_scale(Vector3(0.8, 0.8, 0.8)))
	_piece(body, _mesh("seam"), _material("seam_soft", Color(glow, 0.45), 0.0, true, true), Vector3(0, 1.08, 0.7), Basis(Vector3.RIGHT, -0.2) * Basis.from_scale(Vector3(1.9, 0.9, 1.0)))
	if kind == "boss":
		var bone := _material("bone", Color("f3e7c8"))
		for i in 5:
			var angle := TAU * float(i) / 5.0
			var tilt := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.45)
			_piece(body, _mesh("spike"), bone, Vector3(sin(angle) * 0.42, 1.95, cos(angle) * 0.42), tilt)
	entry.node = root
	entry.body = body
	entry.ring = ring


func _animate_idle(entry: Dictionary) -> void:
	var body: Node3D = entry.body
	if body == null:
		return
	var base: float = SIZE[entry.kind]
	var hold := float(entry.hold) / HOLD_SECONDS
	var breathe := 1.0 + 0.035 * sin(_time * 2.2 + float(entry.phase))
	var swell := 1.0 + 0.12 * hold
	body.scale = Vector3(breathe * swell, (2.0 - breathe) * swell, breathe * swell) * base
	body.rotation.z = sin(_time * 40.0) * 0.05 * hold
	var ring: MeshInstance3D = entry.ring
	if ring != null:
		var radius: float = HOLD_RADIUS[entry.kind]
		var grow := 1.0 + 0.06 * sin(_time * 3.0 + float(entry.phase)) - 0.12 * hold
		ring.scale = Vector3(radius * grow, 0.3, radius * grow)
		var level := roundf(hold * 4.0) / 4.0
		if bool(entry.denied):
			ring.material_override = _material("ring", Color(UiStyle.brawl_tone("neutral")["light"], 0.85), 0.0, true, true)
		else:
			ring.material_override = _material("ring", Color(Color.WHITE if hold > 0.0 else _glow_color(entry.kind), 0.6 + 0.35 * level), 0.0, true, true)


func _animate_pulse(entry: Dictionary) -> void:
	var body: Node3D = entry.body
	if body == null:
		return
	var t := float(entry.anim) / PULSE_SECONDS
	var beat := 1.0 + 0.22 * t + 0.1 * sin(t * TAU * 3.0)
	body.scale = Vector3.ONE * float(SIZE[entry.kind]) * beat
	body.rotation.z = sin(float(entry.anim) * 60.0) * 0.08 * t


func _spawn_shards(entry: Dictionary, rarity: String) -> void:
	var shards: Array = []
	var material := _material("shard", _shell(entry.kind), 0.1)
	var tint := _material("shardglow", UiStyle.rarity_tone(rarity)["light"], 1.8, true)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + 0.3
		var part := _piece(entry.node, _mesh("shard"), material if i % 2 == 0 else tint, Vector3(0, float(SIZE[entry.kind]), 0))
		shards.append([part, Vector3(cos(angle) * 4.5, 5.0 + float(i % 3), sin(angle) * 4.5)])
	entry["shards"] = shards


func _animate_shards(entry: Dictionary) -> void:
	var t := float(entry.anim)
	for pair in entry.get("shards", []):
		var part: MeshInstance3D = pair[0]
		var velocity: Vector3 = pair[1]
		part.position = Vector3(velocity.x * t, float(SIZE[entry.kind]) + velocity.y * t - 12.0 * t * t, velocity.z * t)
		part.scale = Vector3.ONE * maxf(0.05, 1.0 - t * 1.6)


func _beam(at: Vector3, rarity: String, size_value: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(UiStyle.rarity_tone(rarity)["face"], 0.9)
	var holder := Node3D.new()
	holder.name = "Beam"
	holder.position = Vector3(at.x, 0.0, at.z)
	add_child(holder)
	var tier := clampf(float(UiStyle.RARITIES.find(rarity)) / 4.0, 0.0, 1.0)
	var height := 9.0 + 15.0 * tier
	var beam := _piece(holder, _mesh("beam"), material, Vector3.ZERO)
	var core_material := material.duplicate() as StandardMaterial3D
	core_material.albedo_color = Color(Color.WHITE, 0.35)
	var core := _piece(holder, _mesh("beam"), core_material, Vector3.ZERO)
	_beams.append({"node": holder, "beam": beam, "core": core, "material": material, "core_material": core_material,
		"age": 0.0, "height": height, "width": size_value * (1.0 + 0.75 * tier)})
	_step_beams(0.0)


func _step_beams(delta: float) -> void:
	for index in range(_beams.size() - 1, -1, -1):
		var entry: Dictionary = _beams[index]
		entry.age += delta
		var t := float(entry.age) / BEAM_SECONDS
		if t >= 1.0:
			entry.node.queue_free()
			_beams.remove_at(index)
			continue
		var rise := clampf(t / 0.18, 0.0, 1.0)
		var height: float = float(entry.height) * (1.0 - pow(1.0 - rise, 3.0))
		var width: float = float(entry.width) * (1.0 + 0.4 * (1.0 - rise)) * (1.0 - 0.5 * t)
		var fade := 1.0 - smoothstep(0.35, 1.0, t)
		(entry.beam as MeshInstance3D).transform = Transform3D(Basis.from_scale(Vector3(width, maxf(0.01, height), width)), Vector3(0, height * 0.5, 0))
		(entry.core as MeshInstance3D).transform = Transform3D(Basis.from_scale(Vector3(width * 0.25, maxf(0.01, height * 0.98), width * 0.25)), Vector3(0, height * 0.49, 0))
		var tint: Color = (entry.material as StandardMaterial3D).albedo_color
		tint.a = 0.62 * fade
		(entry.material as StandardMaterial3D).albedo_color = tint
		(entry.core_material as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.3 * fade)


func active_beams() -> int:
	return _beams.size()
