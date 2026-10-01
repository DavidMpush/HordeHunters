extends RefCounted

# Natural map edge (stage 18) and the walls of a seeded map (stage 18b/18c).
#
# Stage 34 ("walls from one cast"): every wall - the inner walls of the layout
# (rock ridges, thickets, ruins, tree groups) and the map edge - is one
# continuous extruded shape per chunk, built by scripts/wall_mesh.gd from the
# smoothed wall field (the layout's signed wall distance, cubic B-spline over
# the 2 m NAV cells, blended with the edge field behind the wavy front line):
# a side skirt from the collision edge up to a top cap at ~1.6-2.2 m, a dark
# floor copy and a soft contact shadow on the ground. shaders/wall.gdshader
# paints rock, hedge and masonry (biome colours from biomes.gd "walls") in
# world coordinates, so walls run on over chunk borders without seams. A few
# big accents stand on top (trees on hedges, rock spires on ridges, pillar
# stubs on ruins; charred stumps / basalt columns in the Glutsumpf, cacti and
# sandstone spires in the desert), inside the footprint and without collision.
# The edge keeps its segments of one character (~36 m: thicket, cliff, water),
# the edge lakes of stage 29 (the wall starts behind them), the ground band
# fading into the fog colour and two fog layers; a single skirt mesh in the fog
# colour covers everything past the border chunks.
#
# Performance: per chunk one wall mesh (one draw), one shadow strip, one
# MultiMesh per accent kind, the water surface of stage 29 and the flat edge
# meshes; no node per prop. Meshes are cached per chunk key.

const GRID := 2.8                   # edge deco grid (10 cells per 28 m chunk)
const PER_CHUNK := 10
const SEGMENT := 36.0               # edge length with one character
# Stage 18c follow-up: the visible front stays within 0.3 m of the collision edge.
const WAVE_MAX := 0.3               # front line waves 0..WAVE_MAX m outwards (< BORDER_INSET)
const BAND_Y := 0.009
const FOG_LOW_Y := 1.2
const FOG_HIGH_Y := 5.0
const SKIRT_REACH := 600.0
const TOUCH_MARGIN := 4.0           # chunks this close to the edge get border parts
enum Side { NORTH, EAST, SOUTH, WEST }   # -z, +x, +z, -x
enum Kind { THICKET, CLIFF, WATER }
const KIND_NAMES := [["thicket", "cliff", "water"], ["char", "basalt", "lava"]]
const DEFAULT_LOOK := {"floor": Color("4a6a34"), "fog": Color(0.16, 0.23, 0.18), "water": Color("2f9ea6"), "shore": Color("5d7a3a")}

const QUALITY = preload("res://scripts/world/quality.gd")
const TUNING = preload("res://scripts/world/world_tuning.gd")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const WALL_SHADER = preload("res://shaders/wall.gdshader")
const WALL_MESH = preload("res://scripts/world/wall_mesh.gd")
# Stage 29 water surface: one field texel per NAV cell (2 m, aligned to the
# layout grid) and two texels of margin around the 28 m chunk (bicubic); the surface
# floats just above the wall floor. Edge water: shoreline on the wavy front
# line, only a thin shallow lip (beyond the edge nothing is walkable), a band of
# EDGE_WATER_DEPTH m with round ends.
const FIELD_STEP := 2.0
const FIELD_MARGIN := 2
const FIELD_TEXELS := 18
const WATER_FAR := 64.0
const WATER_Y := 0.018
const EDGE_WATER_DEPTH := 14.0
const EDGE_WATER_ROUND := 9.0
const EDGE_WATER_LIP := 0.35
const WATER_LOOK := {
	"rim": Color("a39a62"), "shallow_light": Color("9edcc2"), "shallow": Color("4cbfb6"),
	"deep": Color("1f8993"), "abyss": Color("17687a"), "foam": Color("f0fff6"),
	"glint": Color("d8fff4"), "pad": Color("5f9e3a"), "pads": 1.0,
}
# Stage 34: wall colours (wall.gdshader uniforms) when a biome has no "walls" block.
const WALL_LOOK := {
	"rock_top": Color("a8a494"), "rock_side": Color("7e7a6e"), "rock_dark": Color("4a4740"),
	"moss": Color("7f9c3c"), "moss_amount": 0.55, "band_amount": 0.2,
	"hedge_top": Color("3f7a2a"), "hedge_light": Color("79b23c"), "hedge_side": Color("2d5e22"),
	"hedge_dark": Color("173816"), "stone": Color("cbbf9f"), "stone_top": Color("b9ad8c"),
	"mortar": Color("6b6252"), "rim_color": Color("fff4c8"), "rim_strength": 0.5,
	"glow_color": Color("ff7a24"), "glow": 0.0,
}

var arena: Node3D
var look: Dictionary = DEFAULT_LOOK
var band_material: StandardMaterial3D
var fog_low_material: StandardMaterial3D
var fog_high_material: StandardMaterial3D
var skirt_material: StandardMaterial3D
# Stage 29: water / lava surface (shaders/water.gdshader); every chunk with water
# uses a copy carrying its own field texture.
var surface_material: ShaderMaterial
# Stage 34: one wall material for every chunk (world-space patterns, see-through
# window fed by arena.gd like the prop materials) and the contact shadow strip.
var wall_material: ShaderMaterial
var shadow_material: StandardMaterial3D
var skirt: MeshInstance3D
# Instance colour of the prop being placed: darkens towards the fog with depth.
var _tint := Color.WHITE
# Stage 19: the Dürrschlund builds sandstone, scrub, cacti and bones.
var _desert := false
# Etappe 22: quality "wall_detail" (1 = every accent; lower drops some).
var _detail := clampf(float(QUALITY.value("wall_detail", 1.0)), 0.3, 1.0)
# Edge deco (reeds in the edge lakes) per chunk key; cleared with every new
# layout or biome.
var _cache: Dictionary = {}
const CACHE_LIMIT := 48
var _builder: RefCounted = WALL_MESH.new()


func _init(owner: Node3D) -> void:
	arena = owner
	band_material = StandardMaterial3D.new()
	band_material.vertex_color_use_as_albedo = true
	band_material.vertex_color_is_srgb = true
	band_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	band_material.roughness = 1.0
	# Stage 29: the edge ground band lies under the water surface, and the water
	# under every other ground decal (puddles -1, shadows 1, telegraphs 0).
	band_material.render_priority = -3
	surface_material = ShaderMaterial.new()
	surface_material.shader = WATER_SHADER
	surface_material.render_priority = -2
	wall_material = ShaderMaterial.new()
	wall_material.shader = WALL_SHADER
	arena.fade_materials.append(wall_material)
	shadow_material = StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.vertex_color_use_as_albedo = true
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Over the ground and the water (a lake never touches a wall), under telegraphs.
	shadow_material.render_priority = -1
	fog_low_material = _fog_material(1)
	fog_high_material = _fog_material(2)
	skirt_material = StandardMaterial3D.new()
	skirt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skirt = MeshInstance3D.new()
	skirt.name = "Edge fog skirt"
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.material_override = skirt_material
	arena.add_child(skirt)
	_builder.heights = Vector3(TUNING.WALL_HEIGHT_ROCK, TUNING.WALL_HEIGHT_HEDGE, TUNING.WALL_HEIGHT_MASONRY)
	_builder.domes = Vector3(TUNING.WALL_DOME_ROCK, TUNING.WALL_DOME_HEDGE, 0.0)
	_builder.camera_low = TUNING.WALL_CAMERA_LOW
	_builder.inset = TUNING.WALL_INSET
	_builder.shadow_width = TUNING.WALL_SHADOW_WIDTH
	_builder.shadow_alpha = TUNING.WALL_SHADOW_ALPHA
	rebuild_skirt()


static func _fog_material(priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	return material


## Restyles the shared edge materials for a biome (biomes.gd "border", "water", "walls").
func apply_biome(data: Dictionary) -> void:
	look = DEFAULT_LOOK.duplicate()
	look.merge(data.get("border", {}), true)
	_cache.clear()
	_wall_cache.clear()
	skirt_material.albedo_color = look.fog
	# Stage 29: lake / lava surface colours (biomes.gd "water").
	var water_look: Dictionary = WATER_LOOK.duplicate()
	water_look.merge(data.get("water", {}), true)
	var params := {
		"rim_color": "rim", "shallow_light": "shallow_light", "shallow_color": "shallow",
		"deep_color": "deep", "abyss_color": "abyss", "foam_color": "foam", "glint_color": "glint",
		"pad_color": "pad", "pads": "pads", "crust_color": "crust", "crack_color": "crack",
		"lava_core": "lava_core", "lava_mid": "lava_mid", "lava_crust": "lava_crust", "plate_amount": "plates",
	}
	for param in params:
		if water_look.has(params[param]):
			surface_material.set_shader_parameter(param, water_look[params[param]])
	surface_material.set_shader_parameter("lava", bool(water_look.get("lava", false)))
	surface_material.set_shader_parameter("rim_width", float(water_look.get("rim_width", 0.9)))
	# Stage 34: wall colours (biomes.gd "walls").
	var wall_look: Dictionary = WALL_LOOK.duplicate()
	wall_look.merge(data.get("walls", {}), true)
	for param in wall_look:
		if param == "shadow":
			continue
		wall_material.set_shader_parameter(param, wall_look[param])
	var floor_color: Color = look.floor
	wall_material.set_shader_parameter("floor_color", floor_color.lerp(look.fog, 0.5))
	wall_material.set_shader_parameter("fog_color", look.fog)
	var shade: Color = wall_look.get("shadow", Color(0.04, 0.06, 0.03))
	_builder.shadow_color = shade


## The fog-coloured ground past the border chunks (one mesh for the whole map).
func rebuild_skirt() -> void:
	_cache.clear()
	_wall_cache.clear()
	var inner: Rect2 = arena.bounds().grow(arena.BORDER_CHUNKS * arena.CELL - 0.3)
	var outer := inner.grow(SKIRT_REACH)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strips := [
		Rect2(outer.position.x, outer.position.y, outer.size.x, inner.position.y - outer.position.y),
		Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y),
		Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y),
		Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y),
	]
	for strip in strips:
		var a := Vector3(strip.position.x, -0.03, strip.position.y)
		var b := Vector3(strip.end.x, -0.03, strip.position.y)
		var c := Vector3(strip.end.x, -0.03, strip.end.y)
		var d := Vector3(strip.position.x, -0.03, strip.end.y)
		for point in [a, b, c, a, c, d]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)
	skirt.mesh = surface.commit()


# ------------------------------------------------------------------ geometry

# Side of the map a point beyond (or near) the edge belongs to, and the
# coordinate along that side: Vector2(side, along).
func _side_along(x: float, z: float) -> Vector2:
	var rect: Rect2 = arena.playable_rect()
	var values := [rect.position.y - z, x - rect.end.x, z - rect.end.y, rect.position.x - x]
	var side := 0
	for index in range(1, 4):
		if values[index] > values[side]:
			side = index
	var along := x if side == Side.NORTH or side == Side.SOUTH else z
	return Vector2(side, along)


## How far the visual front of the wall lies beyond the playable edge (0..WAVE_MAX).
func wave(side: int, along: float) -> float:
	var phase := float(arena._hash(side, 0, 1950) % 628) * 0.01
	var value := 1.3 + 0.9 * sin(along * 0.105 + phase) + 0.55 * sin(along * 0.27 + phase * 2.3)
	return clampf(value, 0.0, WAVE_MAX)


func _kind(side: int, along: float) -> int:
	var index := floori((along + 1000.0) / SEGMENT)
	var roll: int = arena._hash(side, index, 1960) % 100
	return Kind.THICKET if roll < 42 else (Kind.CLIFF if roll < 76 else Kind.WATER)


# Depth behind the wavy front line (negative = in front of it).
func _depth(x: float, z: float) -> float:
	var info := _side_along(x, z)
	return arena.edge_distance(Vector3(x, 0.0, z)) - wave(int(info.x), info.y)


## True if a chunk reaches within TOUCH_MARGIN of the playable edge.
func touches(key: Vector2i) -> bool:
	var cell: float = arena.CELL
	var rect: Rect2 = arena.playable_rect().grow(-TOUCH_MARGIN)
	var chunk := Rect2(key.x * cell, key.y * cell, cell, cell)
	return not rect.encloses(chunk)


## Closed organic front line of the wall (world x, z), sampled every `step` m.
func front_line(step: float) -> PackedVector2Array:
	var rect: Rect2 = arena.playable_rect()
	var result := PackedVector2Array()
	var count := maxi(4, ceili(rect.size.x / step))
	# Clockwise: north (west -> east), east, south (east -> west), west.
	for index in count:
		var x := rect.position.x + rect.size.x * float(index) / float(count)
		result.append(Vector2(x, rect.position.y - wave(Side.NORTH, x)))
	for index in count:
		var z := rect.position.y + rect.size.y * float(index) / float(count)
		result.append(Vector2(rect.end.x + wave(Side.EAST, z), z))
	for index in count:
		var x := rect.end.x - rect.size.x * float(index) / float(count)
		result.append(Vector2(x, rect.end.y + wave(Side.SOUTH, x)))
	for index in count:
		var z := rect.end.y - rect.size.y * float(index) / float(count)
		result.append(Vector2(rect.position.x - wave(Side.WEST, z), z))
	return result


## Edge segments with their character: [{kind, side, from, to}] (world x, z on
## the playable edge), neighbouring segments of one kind merged.
func segments() -> Array:
	var rect: Rect2 = arena.playable_rect()
	var names: Array = KIND_NAMES[1 if arena._ember_look() else 0]
	var result := []
	for side in 4:
		var horizontal := side == Side.NORTH or side == Side.SOUTH
		var low := rect.position.x if horizontal else rect.position.y
		var high := rect.end.x if horizontal else rect.end.y
		var fixed: float = [rect.position.y, rect.end.x, rect.end.y, rect.position.x][side]
		var start := low
		var kind := _kind(side, low)
		var along := (floorf((low + 1000.0) / SEGMENT) + 1.0) * SEGMENT - 1000.0
		while true:
			var stop := minf(along, high)
			var next_kind := _kind(side, stop + 0.01) if stop < high else -1
			if next_kind != kind:
				var a := Vector2(start, fixed) if horizontal else Vector2(fixed, start)
				var b := Vector2(stop, fixed) if horizontal else Vector2(fixed, stop)
				result.append({"kind": names[kind], "side": side, "from": a, "to": b})
				start = stop
				kind = next_kind
			if stop >= high:
				break
			along += SEGMENT
	return result



# ------------------------------------------------------------------ building

## Adds the edge parts of one chunk (walls, lake reeds, ground band, fog) to `chunk`.
func build(chunk: Node3D, key: Vector2i) -> void:
	var origin := chunk.position
	var ember: bool = arena._ember_look()
	_desert = arena._desert_look()
	var groups: Dictionary
	if _cache.has(key):
		groups = _cache[key]
	else:
		groups = _edge_deco(key, origin, ember)
		if _cache.size() >= CACHE_LIMIT:
			_cache.clear()
		_cache[key] = groups
	for id in groups:
		var group: Array = groups[id]
		_multimesh(chunk, String(id), group[0], group[1], group[2])
	# One depth per grid vertex, shared by the ground band and both fog layers.
	var depths := PackedFloat32Array()
	for gz in PER_CHUNK + 1:
		for gx in PER_CHUNK + 1:
			depths.append(_depth((key.x * PER_CHUNK + gx) * GRID, (key.y * PER_CHUNK + gz) * GRID))
	# Stage 34: the ground band and the low fog only show at the edge lakes; the
	# edge wall's top covers them everywhere else (its contact shadow darkens
	# the ground in front of it).
	_runs.clear()
	if not _desert and _edge_water_near(Rect2(key.x * arena.CELL, key.y * arena.CELL, arena.CELL, arena.CELL)):
		_ground_band(chunk, key, depths)
		_fog(chunk, key, depths, FOG_LOW_Y, fog_low_material, 2.0, 16.0, 0.75, "Edge fog low")
	_fog(chunk, key, depths, FOG_HIGH_Y, fog_high_material, 6.0, 20.0, 1.0, "Edge fog high")
	# Stage 34: the edge wall (with the layout's inner walls of this chunk).
	_add_walls(chunk, _wall_parts(key, origin), false)


# Deco of the edge lakes: a few reeds (Glutsumpf: basalt lumps) standing in the
# deep part of the water, so they never stand on reachable ground.
func _edge_deco(key: Vector2i, origin: Vector3, ember: bool) -> Dictionary:
	var groups := {}
	if _desert:
		return groups
	_runs.clear()
	var area := Rect2(key.x * arena.CELL, key.y * arena.CELL, arena.CELL, arena.CELL)
	if not _edge_water_near(area):
		return groups
	for gz in PER_CHUNK:
		for gx in PER_CHUNK:
			var ix := key.x * PER_CHUNK + gx
			var iz := key.y * PER_CHUNK + gz
			var wx: float = float(ix) * GRID + (0.15 + 0.7 * arena._unit(ix, iz, 1970)) * GRID
			var wz: float = float(iz) * GRID + (0.15 + 0.7 * arena._unit(ix, iz, 1971)) * GRID
			var lake := _edge_water(wx, wz)
			if lake.y > -1.0:
				continue
			var roll: float = arena._unit(ix, iz, 1980)
			var size_roll: float = arena._unit(ix, iz, 1981)
			var yaw: float = arena._unit(ix, iz, 1982) * TAU
			_tint = _shade(_depth(wx, wz))
			var local := Vector3(wx - origin.x, 0.0, wz - origin.z)
			_fit = 2
			_origin = origin
			if ember:
				if roll < 0.08:
					_lump(groups, local, 0.9 + size_roll * 0.6, yaw)
			elif roll > 0.84:
				_add(groups, "reed", arena.reed_mesh, arena.reed_base, arena.reed_material, local, Vector3.ONE * (1.6 + size_roll * 0.6), yaw)
			_fit = 0
	return groups


# Deep props darken towards the fog colour (instance colour, multiplied).
func _shade(depth: float) -> Color:
	var fog: Color = look.fog
	var dark := Color(minf(1.0, fog.r * 1.5), minf(1.0, fog.g * 1.5), minf(1.0, fog.b * 1.5))
	return Color.WHITE.lerp(dark, smoothstep(1.5, 20.0, depth))


func _rock(groups: Dictionary, local: Vector3, size: Vector3, yaw: float) -> void:
	# Big rocks sink a little so their round base does not float.
	_add(groups, "rock", arena.rock_mesh, arena.rock_base, arena.rock_material, local + Vector3(0, -0.12 * size.y, 0), size, yaw)


func _lump(groups: Dictionary, local: Vector3, size: float, yaw: float) -> void:
	# Same mesh and material as the basalt columns: one MultiMesh for both.
	_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local, Vector3(size * 1.3, size, size * 1.2), yaw)


# Basalt column cluster: one tall column and two shorter ones leaning on it.
func _basalt(groups: Dictionary, local: Vector3, width: float, height: float, yaw: float) -> void:
	_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local, Vector3(width, height, width), yaw)
	for index in 2:
		var angle := yaw + 2.1 + float(index) * 2.2
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.55
		_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local + offset, Vector3(width * 0.75, height * (0.55 + 0.15 * index), width * 0.75), angle * 1.7)


func _add(groups: Dictionary, id: String, mesh: Mesh, base: Transform3D, material: Material, local: Vector3, size: Vector3, yaw: float) -> void:
	var shape := Basis(Vector3.UP, yaw) * Basis.from_scale(size) * base.basis
	var placed := _rest(mesh, shape, Vector3(local.x, 0.0, local.z))
	placed.origin.y += local.y
	_append(groups, id, mesh, material, placed)


# Rests a shaped mesh on the ground, centred over its footprint (arena._prop_shape).
static func _rest(mesh: Mesh, shape: Basis, local: Vector3) -> Transform3D:
	var box: AABB = Transform3D(shape, Vector3.ZERO) * mesh.get_aabb()
	return Transform3D(shape, local + Vector3(-box.get_center().x, -box.position.y, -box.get_center().z))


# Stage 18c follow-up ("collision = look"): while a fit mode is set, a prop's
# footprint (its oriented bounding box: edge midpoints within 0.3 m, corners
# within 0.8 m for the rounded models) must lie inside the collision - the wall
# (mode 1, layout wall distance) or beyond the map edge (mode 2). Too big props
# shrink step by step (height too); what ends up smaller than MIN_PROP is left
# out, so no tiny pieces stand at a wall.
const MIN_PROP := 0.75
var _fit := 0
var _origin := Vector3.ZERO


func _outside(x: float, z: float) -> float:
	if _fit == 1:
		return arena.layout.sample(x, z)
	return -arena.edge_distance(Vector3(x, 0.0, z))


func _fits(mesh: Mesh, placed: Transform3D) -> bool:
	var box := mesh.get_aabb()
	var lo := box.position
	var hi := box.end
	for u in [0.0, 0.5, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			if u == 0.5 and v == 0.5:
				continue
			var corner: bool = u != 0.5 and v != 0.5
			var local := Vector3(lerpf(lo.x, hi.x, float(u)), lo.y, lerpf(lo.z, hi.z, float(v)))
			var world := placed * local + _origin
			if _outside(world.x, world.z) > (0.8 if corner else 0.3):
				return false
	return true


func _append(groups: Dictionary, id: String, mesh: Mesh, material: Material, placed: Transform3D) -> void:
	if _fit != 0 and not _fits(mesh, placed):
		var box: AABB = placed * mesh.get_aabb()
		var middle := Vector3(box.get_center().x, 0.0, box.get_center().z)
		var lift := placed.origin.y - _rest(mesh, placed.basis, middle).origin.y
		var half := maxf(box.size.x, box.size.z) * 0.5
		var fitted := false
		for step in 6:
			half *= 0.8
			if half < MIN_PROP:
				break
			var shape := Basis.from_scale(Vector3.ONE * pow(0.8, step + 1)) * placed.basis
			var trial := _rest(mesh, shape, middle)
			trial.origin.y += lift * pow(0.8, step + 1)
			if _fits(mesh, trial):
				placed = trial
				fitted = true
				break
		if not fitted:
			return
	if not groups.has(id):
		groups[id] = [mesh, material, []]
	(groups[id][2] as Array).append([placed, _tint])


static func _multimesh(chunk: Node3D, id: String, mesh: Mesh, material: Material, entries: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = entries.size()
	for index in entries.size():
		multimesh.set_instance_transform(index, entries[index][0])
		multimesh.set_instance_color(index, entries[index][1])
	var part := MultiMeshInstance3D.new()
	part.name = "Edge %s" % id
	part.multimesh = multimesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)



# ------------------------------------------------------------ walls (stage 34)

# Wall characters of the layout (map_explore.gd KIND_*; the 18b graph map uses
# the first four through wall_kind()).
const WALL_GRID := 28.0 / 12.0
const WALL_ZONE := 46.0             # size of one wall character patch (18b graph map)
enum Wall { THICKET, CLIFF, ROOTS, WATER, RUIN, TREE, PILLAR }
# Look slot per wall character: rock (r), hedge (g), masonry (b); black = no
# land wall (water: stage 29 surface; rib cages: the RibBones model).
const WALL_SLOTS := [Color(0, 1, 0), Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 0), Color(0, 0, 1), Color(0, 1, 0), Color(0, 0, 1), Color(0, 0, 0), Color(0, 1, 0)]
# Field value (m) of samples far from every wall.
const WALL_OPEN := 4.0
# Edge lakes: the edge wall starts this far behind the far shore.
const EDGE_WALL_GAP := 2.5
const WALL_CACHE_LIMIT := 64
# Built walls per chunk key: {mesh, shadow, accents, deco}.
var _wall_cache: Dictionary = {}
var _heights: Dictionary = {}
var _block_mesh: BoxMesh
var _masonry_material: ShaderMaterial
# Edge field helpers (filled per build).
var _phases := PackedFloat32Array()
var _edge_slots: Dictionary = {}


## Adds the walls of one map chunk (the edge chunks got theirs in build()) and
## the wall deco (reeds in lakes, desert rib cages).
func build_walls(chunk: Node3D, key: Vector2i) -> void:
	if arena.layout == null:
		return
	var parts := _wall_parts(key, chunk.position)
	if touches(key):
		_add_walls(chunk, {"deco": parts.deco}, true)
	else:
		_add_walls(chunk, parts, true)


## Drops the cached walls (new layout or biome).
func clear_walls() -> void:
	_wall_cache.clear()


func _wall_parts(key: Vector2i, origin: Vector3) -> Dictionary:
	if _wall_cache.has(key):
		return _wall_cache[key]
	var parts := _make_wall_parts(key, origin)
	if _wall_cache.size() >= WALL_CACHE_LIMIT:
		_wall_cache.clear()
	_wall_cache[key] = parts
	return parts


func _add_walls(chunk: Node3D, parts: Dictionary, deco: bool) -> void:
	if parts.get("mesh") != null:
		var wall := MeshInstance3D.new()
		wall.name = "Wall"
		wall.mesh = parts.mesh
		wall.material_override = wall_material
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(wall)
	if parts.get("shadow") != null:
		var shadow := MeshInstance3D.new()
		shadow.name = "Wall shadow"
		shadow.mesh = parts.shadow
		shadow.material_override = shadow_material
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(shadow)
	for id in parts.get("accents", {}):
		var group: Array = parts.accents[id]
		_multimesh(chunk, "Wall " + String(id), group[0], group[1], group[2])
	if deco:
		for id in parts.get("deco", {}):
			var group: Array = parts.deco[id]
			_multimesh(chunk, "Wall " + String(id), group[0], group[1], group[2])


func _make_wall_parts(key: Vector2i, origin: Vector3) -> Dictionary:
	_desert = arena._desert_look()
	var ember: bool = arena._ember_look()
	var layout: RefCounted = arena.layout
	var inside: bool = arena.in_map(key)
	var edge: bool = not inside or touches(key)
	var step: float = TUNING.WALL_SAMPLE_STEP if inside else TUNING.WALL_EDGE_STEP
	var n := roundi(arena.CELL / step)
	var samples := wall_samples(key, n, step, edge)
	var built: Array = _builder.build(samples[0], samples[1], samples[2], n, step, Vector2.ZERO)
	var accents := {}
	if built[0] != null:
		_accents(accents, key, origin, samples, n, step, ember)
	var deco := {}
	if layout != null and inside:
		deco = _place_walls(key, origin, ember, layout)
	return {"mesh": built[0], "shadow": built[1], "accents": accents, "deco": deco}


## Wall field of a chunk on a regular grid: [field (m, + open), kind weights,
## edge depth] for (n + 3)^2 samples, sample (a, b) at the chunk corner +
## (a - 1, b - 1) * step. The layout part is the cubic B-spline of the NAV
## cells, clamped to within TUNING.WALL_SMOOTH_BAND of the bilinear collision
## field (round where it can be, never more than ~0.3 m off the collision);
## the edge part is the depth behind the wavy front line (on a seeded map the
## layout's own edge cells draw the front, the analytic depth only deepens it
## and carries the edge character), edge lakes cut out.
func wall_samples(key: Vector2i, n: int, step: float, edge: bool) -> Array:
	var size := n + 3
	var base := Vector2(key.x * arena.CELL - step, key.y * arena.CELL - step)
	var f := PackedFloat32Array()
	f.resize(size * size)
	f.fill(WALL_OPEN)
	var w := PackedColorArray()
	w.resize(size * size)
	w.fill(Color(0, 0, 0, 0))
	var e := PackedFloat32Array()
	e.resize(size * size)
	_runs.clear()
	_edge_slots.clear()
	_phases.resize(4)
	for side in 4:
		_phases[side] = float(arena._hash(side, 0, 1950) % 628) * 0.01
	if arena.layout != null:
		_layout_samples(f, w, base, size, step, arena.layout)
	if edge:
		_edge_samples(f, w, e, base, size, step)
	return [f, w, e]


# Tap cells and weights along one axis for `size` samples from `start`:
# [first cell (PackedInt32Array, the cell left of the sample), 4 B-spline
# weights per sample for cells first - 1 .. first + 2, 2 linear weights
# (first, first + 1)].
static func _taps(start: float, origin: float, nav: float, size: int, step: float) -> Array:
	var cells := PackedInt32Array()
	var weights := PackedFloat32Array()
	var linear := PackedFloat32Array()
	for a in size:
		var fx := (start + float(a) * step - origin) / nav - 0.5
		var i := floori(fx)
		var u := fx - float(i)
		var u2 := u * u
		var u3 := u2 * u
		cells.append(i)
		weights.append_array([(1.0 - u) * (1.0 - u) * (1.0 - u) / 6.0, (3.0 * u3 - 6.0 * u2 + 4.0) / 6.0, (-3.0 * u3 + 3.0 * u2 + 3.0 * u + 1.0) / 6.0, u3 / 6.0])
		linear.append_array([1.0 - u, u])
	return [cells, weights, linear]


func _layout_samples(f: PackedFloat32Array, w: PackedColorArray, base: Vector2, size: int, step: float, layout: RefCounted) -> void:
	var nav: float = layout.NAV
	var grid: int = layout.grid
	var grid_origin: Vector2 = layout.grid_origin
	var sdf: PackedFloat32Array = layout.sdf
	var kinds := PackedByteArray()
	if layout.get("kind") != null:
		kinds = layout.kind
	var band: float = TUNING.WALL_SMOOTH_BAND
	var tx := _taps(base.x, grid_origin.x, nav, size, step)
	var tz := _taps(base.y, grid_origin.y, nav, size, step)
	var first_x: PackedInt32Array = tx[0]
	var first_z: PackedInt32Array = tz[0]
	var wx: PackedFloat32Array = tx[1]
	var wz: PackedFloat32Array = tz[1]
	var lx: PackedFloat32Array = tx[2]
	var lz: PackedFloat32Array = tz[2]
	var cx0 := first_x[0] - 1
	var cz0 := first_z[0] - 1
	var cw := first_x[size - 1] + 3 - cx0
	var ch := first_z[size - 1] + 3 - cz0
	var values := PackedFloat32Array()
	values.resize(cw * ch)
	var slots := PackedColorArray()
	slots.resize(cw * ch)
	var rect: Rect2 = arena.playable_rect()
	var any_wall := false
	for jz in ch:
		var iz := clampi(cz0 + jz, 0, grid - 1)
		var z := grid_origin.y + (float(iz) + 0.5) * nav
		for jx in cw:
			var ix := clampi(cx0 + jx, 0, grid - 1)
			var x := grid_origin.x + (float(ix) + 0.5) * nav
			var index := iz * grid + ix
			var value := sdf[index]
			var slot := Color(0, 0, 0, 0)
			if value >= 0.0:
				value = maxf(value, 1.0)  # lakes lower the open side; land walls only
			elif minf(minf(x - rect.position.x, rect.end.x - x), minf(z - rect.position.y, rect.end.y - z)) < 1.0:
				# The map edge row: its character comes from the edge segments.
				var info := _side_along(x, z)
				slot = _edge_slot(int(info.x), info.y)
				any_wall = true
			else:
				var type: int = kinds[index] if not kinds.is_empty() else wall_kind(x, z)
				if type == Wall.WATER and kinds.is_empty():
					type = Wall.ROOTS
				slot = WALL_SLOTS[type] if type < WALL_SLOTS.size() else WALL_SLOTS[1]
				if slot.r + slot.g + slot.b < 0.5:
					value = 1.0  # deep water / rib cage: not a wall surface
				else:
					any_wall = true
			values[jz * cw + jx] = value
			slots[jz * cw + jx] = slot
	if not any_wall:
		return
	# Which 4 x 4 tap windows hold a wall cell (window starting at cell jx, jz):
	# samples whose window is all open keep WALL_OPEN (their field is >= 1).
	var near_x := PackedByteArray()
	near_x.resize(cw * ch)
	for jz in ch:
		for jx in cw - 3:
			var o := jz * cw + jx
			if values[o] < 1.0 or values[o + 1] < 1.0 or values[o + 2] < 1.0 or values[o + 3] < 1.0:
				near_x[o] = 1
	var near := PackedByteArray()
	near.resize(cw * ch)
	for jz in ch - 3:
		for jx in cw:
			var o := jz * cw + jx
			if near_x[o] == 1 or near_x[o + cw] == 1 or near_x[o + cw * 2] == 1 or near_x[o + cw * 3] == 1:
				near[o] = 1
	var rows := PackedFloat32Array()
	rows.resize(ch * size)
	var rows_linear := PackedFloat32Array()
	rows_linear.resize(ch * size)
	for jz in ch:
		var row := jz * cw
		for a in size:
			var c := row + first_x[a] - 1 - cx0
			var o := a * 4
			rows[jz * size + a] = wx[o] * values[c] + wx[o + 1] * values[c + 1] + wx[o + 2] * values[c + 2] + wx[o + 3] * values[c + 3]
			rows_linear[jz * size + a] = lx[a * 2] * values[c + 1] + lx[a * 2 + 1] * values[c + 2]
	for b in size:
		var r := first_z[b] - 1 - cz0
		var o := b * 4
		var z0 := wz[o]
		var z1 := wz[o + 1]
		var z2 := wz[o + 2]
		var z3 := wz[o + 3]
		var s0 := lz[b * 2]
		var s1 := lz[b * 2 + 1]
		for a in size:
			if near[r * cw + first_x[a] - 1 - cx0] == 0:
				continue
			var i := b * size + a
			var value := s0 * rows_linear[(r + 1) * size + a] + s1 * rows_linear[(r + 2) * size + a]
			# Only near the contour the rounder B-spline shapes the edge; deeper
			# in the exact field serves (depth shading, heights).
			if value < 1.4 and value > -1.4:
				var smooth := z0 * rows[r * size + a] + z1 * rows[(r + 1) * size + a] + z2 * rows[(r + 2) * size + a] + z3 * rows[(r + 3) * size + a]
				value = clampf(smooth, value - band, value + band)
			f[i] = value
			if value > 1.6:
				continue  # far from every contour: the weights are never read
			var c := (r + 1) * cw + first_x[a] - cx0
			var t0 := lx[a * 2]
			var t1 := lx[a * 2 + 1]
			w[i] = (slots[c] * t0 + slots[c + 1] * t1) * s0 + (slots[c + cw] * t0 + slots[c + cw + 1] * t1) * s1


func _edge_samples(f: PackedFloat32Array, w: PackedColorArray, e: PackedFloat32Array, base: Vector2, size: int, step: float) -> void:
	var rect: Rect2 = arena.playable_rect()
	var span := step * float(size - 1)
	var lakes: bool = not _desert and _edge_water_near(Rect2(base, Vector2(span, span)))
	for b in size:
		var z := base.y + float(b) * step
		for a in size:
			var x := base.x + float(a) * step
			var north := rect.position.y - z
			var east := x - rect.end.x
			var south := z - rect.end.y
			var west := rect.position.x - x
			if north < -4.0 and east < -4.0 and south < -4.0 and west < -4.0:
				continue  # well inside the map: no edge wall, no fog depth
			var side := Side.NORTH
			var most := north
			if east > most:
				side = Side.EAST
				most = east
			if south > most:
				side = Side.SOUTH
				most = south
			if west > most:
				side = Side.WEST
				most = west
			var along := x if side == Side.NORTH or side == Side.SOUTH else z
			var phase := _phases[side]
			var wave_value := clampf(1.3 + 0.9 * sin(along * 0.105 + phase) + 0.55 * sin(along * 0.27 + phase * 2.3), 0.0, WAVE_MAX)
			var outside := maxf(west, east)
			var outside_z := maxf(north, south)
			var distance := Vector2(outside, outside_z).length() if outside > 0.0 and outside_z > 0.0 else maxf(outside, outside_z)
			var depth := distance - wave_value
			var i := b * size + a
			e[i] = maxf(depth, 0.0)
			if -depth < f[i]:
				f[i] = -depth
				if w[i].r + w[i].g + w[i].b < 0.01 or depth > 0.5:
					w[i] = _edge_slot(side, along)
			if lakes and f[i] < 1.5:
				var lake := _lake_distance(side, along, depth)
				if lake < WATER_FAR:
					f[i] = maxf(f[i], EDGE_WALL_GAP - lake)


# Shoreline distance of the edge lakes at a point given by side, along and
# depth behind the front line (the value of _edge_water().x, without
# recomputing side and depth).
func _lake_distance(side: int, along: float, depth: float) -> float:
	if depth < -10.0 or depth > EDGE_WATER_DEPTH + 12.0:
		return WATER_FAR
	var index := floori((along + 1000.0) / SEGMENT)
	var best := WATER_FAR
	for k in 3:
		var probe := index if k == 0 else (index - 1 if k == 1 else index + 1)
		var run := _water_run(side, probe)
		if not run.is_finite():
			continue
		var phase := float(posmod(roundi(run.x), 628)) * 0.01
		var reach := EDGE_WATER_DEPTH + 3.0 * sin(along * 0.09 + phase) + 1.5 * sin(along * 0.23 + phase * 1.7)
		var round_radius := minf(EDGE_WATER_ROUND, reach * 0.5)
		var half := Vector2((run.y - run.x) * 0.5, reach * 0.5)
		var q := Vector2(absf(along - (run.x + run.y) * 0.5), absf(depth - half.y)) - half + Vector2(round_radius, round_radius)
		best = minf(best, Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_radius)
		if k == 0:
			break
	return best


# Look slot of the edge around `along` (a soft 9 m blend between segments).
func _edge_slot(side: int, along: float) -> Color:
	var result := Color(0, 0, 0, 0)
	for offset in [-4.5, 0.0, 4.5]:
		var index := floori((along + offset + 1000.0) / SEGMENT)
		var id := side * 100000 + index
		if not _edge_slots.has(id):
			var kind := _kind_of(side, index)
			var slot := Color(0, 1, 0)
			if _desert or kind == Kind.CLIFF or (kind == Kind.WATER and arena._ember_look()):
				slot = Color(1, 0, 0)
			_edge_slots[id] = slot
		result += _edge_slots[id] / 3.0
	return result


# Big accents on the wall tops: every ~3 m sample deep enough inside the wall
# rolls by kind for a tree / rock spire / pillar stub (Glutsumpf: charred
# stump / basalt columns; desert: cactus / sandstone spire), at most one per
# WALL_ACCENT_SPACING m. They stand inside the footprint and have no collision.
func _accents(groups: Dictionary, key: Vector2i, origin: Vector3, samples: Array, n: int, step: float, ember: bool) -> void:
	var f: PackedFloat32Array = samples[0]
	var w: PackedColorArray = samples[1]
	var e: PackedFloat32Array = samples[2]
	var size := n + 3
	var stride := maxi(1, roundi(2.0 / step))
	var spacing: float = TUNING.WALL_ACCENT_SPACING
	var placed: Array[Vector2] = []
	var rock_w := _mesh_width(arena.rock_mesh, arena.rock_base)
	var rock_h := _mesh_height(arena.rock_mesh, arena.rock_base)
	var leaf_w := _mesh_width(arena.leaf_mesh, arena.leaf_base)
	var south_edge: float = arena.playable_rect().end.y - 3.0
	_fit = 0
	for b in range(1 + stride / 2, n + 2, stride):
		for a in range(1 + stride / 2, n + 2, stride):
			var i := b * size + a
			var depth := -f[i]
			if depth < 0.6 or e[i] > 14.0:
				continue
			var col := w[i]
			var total := col.r + col.g + col.b
			if total < 0.01:
				continue
			var slot := 0
			if col.g > col.r and col.g >= col.b:
				slot = 1
			elif col.b > col.r and col.b > col.g:
				slot = 2
			# Room per look: spires and trees need a wider wall than a pillar stub.
			if depth < [1.5, 1.4, 0.6][slot] or (e[i] > 0.0 and depth < 2.5):
				continue
			var local2 := Vector2(float(a - 1) * step, float(b - 1) * step)
			# The south edge stands between the camera and the focus: no accents.
			if e[i] > 0.0 and key.y * arena.CELL + local2.y > south_edge:
				continue
			var gx := floori((key.x * arena.CELL + local2.x) / 2.0)
			var gz := floori((key.y * arena.CELL + local2.y) / 2.0)
			var roll: float = arena._unit(gx, gz, 3400)
			var chance: float = [0.06, 0.07, 0.16][slot] * _detail
			if _desert and slot == 1:
				chance = 0.3 * _detail
			if roll > chance:
				continue
			var crowded := false
			for other in placed:
				if other.distance_to(local2) < spacing:
					crowded = true
					break
			if crowded:
				continue
			placed.append(local2)
			var yaw: float = arena._unit(gx, gz, 3401) * TAU
			var size_roll: float = arena._unit(gx, gz, 3402)
			var top: float = _builder._height(col, depth, Vector2(0.0, 1.0))
			var local := Vector3(local2.x, top, local2.y)
			_tint = _shade(e[i])
			match slot:
				0:
					if ember:
						_basalt(groups, local - Vector3(0.0, 0.5, 0.0), 1.2 + size_roll * 0.5, 2.4 + size_roll * 1.6, yaw)
					else:
						var material: Material = arena.sandstone_material if _desert else arena.rock_material
						var width := clampf(depth * 1.3, 1.4, 2.0 + size_roll * 0.9)
						_add(groups, "spire", arena.rock_mesh, arena.rock_base, material, local - Vector3(0.0, 0.6, 0.0), Vector3(width / rock_w, (2.4 + roll * 10.0 + size_roll * 1.2) / rock_h, width * 0.85 / rock_w), yaw)
				1:
					if ember:
						# Charred thicket: a low basalt cluster (one basalt MultiMesh per chunk).
						_basalt(groups, local - Vector3(0.0, 0.4, 0.0), 0.9 + size_roll * 0.4, 1.6 + size_roll * 1.0, yaw)
					elif _desert:
						var part: Array = arena.desert_part("cactus")
						var scale := (1.7 + size_roll * 0.6) / _mesh_width(part[0], part[1])
						_add(groups, "cactus", part[0], part[1], arena.cactus_material, local - Vector3(0.0, 0.3, 0.0), Vector3(scale, scale * (1.1 + roll * 2.0), scale), yaw)
					else:
						_add(groups, "crown", arena.leaf_mesh, arena.leaf_base, arena.leaf_material, local - Vector3(0.0, 0.35, 0.0), Vector3.ONE * (2.8 + size_roll * 0.8) / leaf_w, yaw)
				_:
					var height := 0.8 + size_roll * 1.4
					if ember:
						# Glutsumpf ruins: a broken basalt column (shares the basalt MultiMesh).
						_add(groups, "basalt", arena.rock_mesh, arena.rock_base, arena.basalt_material, local - Vector3(0.0, 0.3, 0.0), Vector3(0.9 / rock_w, (height + 0.4) / rock_h, 0.9 / rock_w), yaw)
						continue
					if _block_mesh == null:
						_block_mesh = BoxMesh.new()
					var material: Material = arena.sandstone_material if _desert else _masonry(ember)
					_tint = _tint * Color("d8cdb0").lerp(Color("bfb296"), roll)
					var shape := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.9, height, 0.9))
					_append(groups, "pillar", _block_mesh, material, Transform3D(shape, local + Vector3(0.0, height * 0.5 - 0.15, 0.0)))


# Wall deco of a layout chunk: reeds and stones in deep lake water (stage 29)
# and the desert rib cages.
func _place_walls(key: Vector2i, origin: Vector3, ember: bool, layout: RefCounted) -> Dictionary:
	var groups := {}
	if layout.get("kind") == null:
		return groups
	var nav: float = layout.NAV
	var grid: int = layout.grid
	var grid_origin: Vector2 = layout.grid_origin
	var lo := Vector2i(floori((key.x * arena.CELL - grid_origin.x) / nav), floori((key.y * arena.CELL - grid_origin.y) / nav))
	var cells := int(round(arena.CELL / nav))
	var kinds: PackedByteArray = layout.kind
	var closed: PackedByteArray = layout.blocked
	for dz in cells:
		for dx in cells:
			var ix := lo.x + dx
			var iz := lo.y + dz
			if ix < 1 or iz < 1 or ix >= grid - 1 or iz >= grid - 1:
				continue
			var index := iz * grid + ix
			if closed[index] == 0 or kinds[index] != Wall.WATER:
				continue
			var cx: float = grid_origin.x + (float(ix) + 0.5) * nav
			var cz: float = grid_origin.y + (float(iz) + 0.5) * nav
			var local := Vector3(cx - origin.x, 0.0, cz - origin.z)
			_tint = Color.WHITE
			var roll: float = arena._unit(ix, iz, 3300)
			var yaw: float = arena._unit(ix, iz, 3301) * TAU
			_water_cell(groups, layout, index, local, roll, yaw, ember, closed[index - grid] == 0, origin)
	if _desert:
		_rib_cages(groups, key, origin, layout)
	return groups


func _mesh_width(mesh: Mesh, base: Transform3D) -> float:
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	return maxf(0.01, maxf(box.size.x, box.size.z))


# Character of the wall around a point: organic seeded patches (Voronoi cells
# of a jittered WALL_ZONE grid).
func wall_kind(x: float, z: float) -> int:
	var cx := floori((x + 1000.0) / WALL_ZONE)
	var cz := floori((z + 1000.0) / WALL_ZONE)
	var best := INF
	var roll := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var gx := cx + dx
			var gz := cz + dz
			var px: float = (float(gx) + 0.1 + 0.8 * arena._unit(gx, gz, 2961)) * WALL_ZONE - 1000.0
			var pz: float = (float(gz) + 0.1 + 0.8 * arena._unit(gx, gz, 2962)) * WALL_ZONE - 1000.0
			var d := (x - px) * (x - px) + (z - pz) * (z - pz)
			if d < best:
				best = d
				roll = arena._hash(gx, gz, 2960) % 100
	return Wall.THICKET if roll < 46 else (Wall.CLIFF if roll < 72 else (Wall.ROOTS if roll < 88 else Wall.WATER))


func _mesh_height(mesh: Mesh, base: Transform3D) -> float:
	var id := mesh.get_instance_id()
	if not _heights.has(id):
		_heights[id] = maxf(0.01, (Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()).size.y)
	return _heights[id]
# One RibBones model per intact rib cage whose centre lies in this chunk,
# stretched over the stamped block (fit-checked against the wall distance).
func _rib_cages(groups: Dictionary, key: Vector2i, origin: Vector3, layout: RefCounted) -> void:
	var cages: Variant = layout.get("ribs")
	if not cages is Array:
		return
	var part: Array = arena.desert_part("ribs")
	var mesh: Mesh = part[0]
	var base: Transform3D = part[1]
	var box: AABB = Transform3D(base.basis, Vector3.ZERO) * mesh.get_aabb()
	for cage in cages:
		var center: Vector3 = cage.center
		if floori(center.x / 28.0) != key.x or floori(center.z / 28.0) != key.y:
			continue
		var scale := float(cage.length) / maxf(0.01, box.size.z)
		_tint = Color.WHITE
		_fit = 1
		_origin = origin
		_add(groups, "ribs", mesh, base, arena.bone_material, center - origin, Vector3(scale, scale * 1.15, scale), float(cage.yaw))
		_fit = 0


# ------------------------------------------------------------ water (stage 29)

# A deep-water cell: the surface itself is build_water(); here only decoration
# that stands inside the collision (fit mode 1) - reeds lining the drop-off,
# rarely a stone far out; Glutsumpf: a rare basalt lump in the lava. Reeds on
# the far (north) side of a lake stay out: they would hide the focus.
func _water_cell(groups: Dictionary, layout: RefCounted, index: int, local: Vector3, roll: float, yaw: float, ember: bool, camera_side: bool, origin: Vector3) -> void:
	var deeps: Variant = layout.get("water_deep")
	if not deeps is PackedFloat32Array or (deeps as PackedFloat32Array).size() <= index:
		return
	var inside := -float(deeps[index])
	_fit = 1
	_origin = origin
	if ember:
		if inside > 3.0 and roll > 0.93:
			_lump(groups, local, 0.9 + roll * 0.5, yaw)
	elif inside > 0.4 and inside < 1.9 and roll < 0.42 and not camera_side:
		_add(groups, "reed", arena.reed_mesh, arena.reed_base, arena.reed_material, local, Vector3.ONE * (1.3 + roll * 1.2), yaw)
	elif inside > 4.0 and roll > 0.965:
		_rock(groups, local, Vector3(1.9, 1.1, 1.7) * (0.9 + (roll - 0.965) * 8.0), yaw)
	_fit = 0


## Adds the water (lava) surface of one chunk: the layout's lakes and, near the
## map edge, the edge water - one mesh of 2 m quads where there is water, one
## material copy carrying the chunk's field texture. Nothing without water.
func build_water(chunk: Node3D, key: Vector2i) -> void:
	var values := _water_values(key)
	if values.is_empty():
		return
	var rim: float = float(surface_material.get_shader_parameter("rim_width"))
	var vertices := PackedVector3Array()
	var cells := FIELD_TEXELS - 2 * FIELD_MARGIN
	for qz in cells:
		for qx in cells:
			# The quad reads texels qx .. qx + 2 * FIELD_MARGIN + 1 (bicubic).
			var wet := false
			for j in range(qz + 1, qz + 2 * FIELD_MARGIN):
				for i in range(qx + 1, qx + 2 * FIELD_MARGIN):
					if values[j * FIELD_TEXELS + i].x < rim + 0.6:
						wet = true
						break
				if wet:
					break
			if not wet:
				continue
			var x0 := float(qx) * FIELD_STEP
			var z0 := float(qz) * FIELD_STEP
			var a := Vector3(x0, WATER_Y, z0)
			var b := Vector3(x0 + FIELD_STEP, WATER_Y, z0)
			var c := Vector3(x0 + FIELD_STEP, WATER_Y, z0 + FIELD_STEP)
			var d := Vector3(x0, WATER_Y, z0 + FIELD_STEP)
			vertices.append_array([a, b, c, a, c, d])
	if vertices.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: ShaderMaterial = surface_material.duplicate()
	material.set_shader_parameter("field", ImageTexture.create_from_image(_field_image(values)))
	material.set_shader_parameter("field_origin", Vector2(chunk.position.x, chunk.position.z) - Vector2.ONE * FIELD_STEP * FIELD_MARGIN)
	material.set_shader_parameter("field_size", FIELD_STEP * FIELD_TEXELS)
	var part := MeshInstance3D.new()
	part.name = "Water"
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


## The water field of a chunk as an RGH image (null without water): texel
## (i, j) sits at the world chunk corner + ((i, j) - FIELD_MARGIN + 0.5) *
## FIELD_STEP, which are the layout's cell centres; R = shoreline distance,
## G = deep-edge distance (m, - inside).
func water_field(key: Vector2i) -> Image:
	var values := _water_values(key)
	return null if values.is_empty() else _field_image(values)


func _field_image(values: PackedVector2Array) -> Image:
	var image := Image.create(FIELD_TEXELS, FIELD_TEXELS, false, Image.FORMAT_RGH)
	for j in FIELD_TEXELS:
		for i in FIELD_TEXELS:
			var value := values[j * FIELD_TEXELS + i]
			image.set_pixel(i, j, Color(value.x, value.y, 0.0))
	return image


# Field values of a chunk (see water_field), empty when no water is near.
func _water_values(key: Vector2i) -> PackedVector2Array:
	var layout: RefCounted = arena.layout
	var shores := PackedFloat32Array()
	var deeps := PackedFloat32Array()
	var grid := 0
	var cell_lo := Vector2i.ZERO
	var area := Rect2(key.x * arena.CELL, key.y * arena.CELL, arena.CELL, arena.CELL)
	if layout != null and layout.get("basins") is Array:
		for basin in layout.basins:
			var center: Vector3 = basin.center
			if area.grow(float(basin.radius) + 8.0).has_point(Vector2(center.x, center.z)):
				grid = int(layout.grid)
				break
	if grid > 0:
		shores = layout.water
		deeps = layout.water_deep
		var grid_origin: Vector2 = layout.grid_origin
		cell_lo = Vector2i(roundi((area.position.x - grid_origin.x) / FIELD_STEP) - FIELD_MARGIN, roundi((area.position.y - grid_origin.y) / FIELD_STEP) - FIELD_MARGIN)
	var edge: bool = not arena._desert_look() and (not arena.in_map(key) or touches(key)) and _edge_water_near(area)
	var values := PackedVector2Array()
	if grid == 0 and not edge:
		return values
	values.resize(FIELD_TEXELS * FIELD_TEXELS)
	var any := false
	var base := area.position + Vector2.ONE * FIELD_STEP * (0.5 - FIELD_MARGIN)
	_runs.clear()
	for j in FIELD_TEXELS:
		for i in FIELD_TEXELS:
			var value := Vector2(WATER_FAR, WATER_FAR)
			if grid > 0:
				var cx := cell_lo.x + i
				var cz := cell_lo.y + j
				if cx >= 0 and cz >= 0 and cx < grid and cz < grid:
					value = Vector2(shores[cz * grid + cx], deeps[cz * grid + cx])
			if edge:
				var lake := _edge_water(base.x + float(i) * FIELD_STEP, base.y + float(j) * FIELD_STEP)
				value = Vector2(minf(value.x, lake.x), minf(value.y, lake.y))
			if value.x < 1.5:
				any = true
			values[j * FIELD_TEXELS + i] = value
	if not any:
		values.clear()
	return values


# True if an edge-water run lies within one segment of the chunk area.
func _edge_water_near(area: Rect2) -> bool:
	for u in [0.0, 0.5, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			var info := _side_along(area.position.x + area.size.x * u, area.position.y + area.size.y * v)
			var index := floori((info.y + 1000.0) / SEGMENT)
			for probe in [index - 1, index, index + 1]:
				if _kind_of(int(info.x), probe) == Kind.WATER:
					return true
	return false


# Edge-water runs of one chunk build: (side, segment) -> Vector2(from, to) or
# Vector2.INF when that segment is no water.
var _runs: Dictionary = {}


func _water_run(side: int, index: int) -> Vector2:
	var id := side * 100000 + index
	if _runs.has(id):
		return _runs[id]
	var run := Vector2.INF
	if _kind_of(side, index) == Kind.WATER:
		var first := index
		while first > index - 8 and _kind_of(side, first - 1) == Kind.WATER:
			first -= 1
		var last := index
		while last < index + 8 and _kind_of(side, last + 1) == Kind.WATER:
			last += 1
		run = Vector2(float(first) * SEGMENT - 1000.0, float(last + 1) * SEGMENT - 1000.0)
	_runs[id] = run
	return run


# Edge water at a point beyond the front line: a band along every water
# segment run of a side, shoreline on the wavy front line, the far bank waving
# around EDGE_WATER_DEPTH m and wide round ends (a lake lying against the edge,
# not a strip). Returns Vector2(shore, deep) distances (WATER_FAR = none).
func _edge_water(x: float, z: float) -> Vector2:
	var rect: Rect2 = arena.playable_rect()
	# Well inside the map (the common case in a border chunk): no edge water.
	if x > rect.position.x + 10.0 and x < rect.end.x - 10.0 and z > rect.position.y + 10.0 and z < rect.end.y - 10.0:
		return Vector2(WATER_FAR, WATER_FAR)
	var info := _side_along(x, z)
	var side := int(info.x)
	var along := info.y
	var depth: float = arena.edge_distance(Vector3(x, 0.0, z)) - wave(side, along)
	if depth < -10.0 or depth > EDGE_WATER_DEPTH + 12.0:
		return Vector2(WATER_FAR, WATER_FAR)
	var index := floori((along + 1000.0) / SEGMENT)
	var best := WATER_FAR
	for probe in [index, index - 1, index + 1]:
		var run := _water_run(side, probe)
		if not run.is_finite():
			continue
		var from := run.x
		var to := run.y
		var phase := float(posmod(roundi(from), 628)) * 0.01
		var reach := EDGE_WATER_DEPTH + 3.0 * sin(along * 0.09 + phase) + 1.5 * sin(along * 0.23 + phase * 1.7)
		# Rounded box in (along, depth); the shore runs exactly on the front line.
		var round_radius := minf(EDGE_WATER_ROUND, reach * 0.5)
		var half := Vector2((to - from) * 0.5, reach * 0.5)
		var q := Vector2(absf(along - (from + to) * 0.5), absf(depth - half.y)) - half + Vector2(round_radius, round_radius)
		var value := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_radius
		best = minf(best, value)
		if probe == index:
			break
	return Vector2(best, best + EDGE_WATER_LIP)


func _kind_of(side: int, index: int) -> int:
	var roll: int = arena._hash(side, index, 1960) % 100
	return Kind.THICKET if roll < 42 else (Kind.CLIFF if roll < 76 else Kind.WATER)

# Stone material of the masonry blocks (instance colours carry the stone).
func _masonry(ember: bool) -> Material:
	if ember:
		return arena.basalt_material
	if _masonry_material == null:
		_masonry_material = (arena.rock_material as ShaderMaterial).duplicate()
		_masonry_material.set_shader_parameter("body_tint", Color(0.72, 0.68, 0.6, 0.35))
		arena.fade_materials.append(_masonry_material)
	return _masonry_material
# Ground darkening behind the front line: forest floor fading into the fog
# colour; transparent towards the open ground so it blends with any tint.
func _ground_band(chunk: Node3D, key: Vector2i, depths: PackedFloat32Array) -> void:
	var floor_color: Color = look.floor
	var fog_color: Color = look.fog
	var mesh := _grid_mesh(chunk, key, depths, BAND_Y, func(depth: float) -> Color:
		var color := floor_color.lerp(fog_color, smoothstep(3.0, 24.0, depth))
		color.a = smoothstep(-2.5, 0.0, depth)
		return color)
	if mesh == null:
		return
	var part := MeshInstance3D.new()
	part.name = "Edge ground"
	part.mesh = mesh
	part.material_override = band_material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


func _fog(chunk: Node3D, key: Vector2i, depths: PackedFloat32Array, height: float, material: Material, start: float, full: float, strength: float, label: String) -> void:
	var fog_color: Color = look.fog
	var mesh := _grid_mesh(chunk, key, depths, height, func(depth: float) -> Color:
		return Color(fog_color, strength * smoothstep(start, full, depth)))
	if mesh == null:
		return
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(part)


# Flat grid over the chunk with a colour per vertex from the depth behind the
# front line; quads that stay fully transparent are left out.
func _grid_mesh(chunk: Node3D, key: Vector2i, depths: PackedFloat32Array, height: float, paint: Callable) -> ArrayMesh:
	var count := PER_CHUNK + 1
	var colors: Array[Color] = []
	var points: Array[Vector3] = []
	for gz in count:
		for gx in count:
			var world := Vector3((key.x * PER_CHUNK + gx) * GRID, 0.0, (key.y * PER_CHUNK + gz) * GRID)
			colors.append(paint.call(depths[gz * count + gx]))
			points.append(Vector3(world.x - chunk.position.x, height, world.z - chunk.position.z))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for gz in PER_CHUNK:
		for gx in PER_CHUNK:
			var a := gz * count + gx
			var corners := [a, a + 1, a + count + 1, a + count]
			var visible := false
			for corner in corners:
				if colors[corner].a > 0.004:
					visible = true
			if not visible:
				continue
			for index in [0, 1, 2, 0, 2, 3]:
				var corner: int = corners[index]
				surface.set_color(colors[corner])
				surface.set_normal(Vector3.UP)
				surface.add_vertex(points[corner])
			quads += 1
	if quads == 0:
		return null
	return surface.commit()
