extends RefCounted

# Stage 18c: the exploration map (replaces the clearing/corridor graph of
# map_layout.gd as the standard for seeded maps; same data interface, so
# arena.gd, flow_field.gd, the wall builder and the minimap keep working).
#
# Every region rolls a landscape - open meadow, light forest (tree groups with
# gaps), dense thicket, ruin field (broken walls, pillars), rock ridge, swamp
# ponds, rock labyrinth - blended organically (warped Voronoi between region
# seeds). Terrain is a blocked mask on the NAV grid (~25-35 % blocked); choke
# points arise between thicket, rock and water, open ground stays connected
# (small pockets filled, larger ones joined by a carved gap). POIs are scattered
# seeded (Poisson disc, a small clearing carved around each), loose trampled
# trails wind between some of them (A* over open ground, visual only), amber
# nodes (loot) are strewn everywhere, a few tall landmarks lure from afar.
#
#   nodes      POI sites [{center, radius (cleared), types, slots, amp, phase, edges}]
#   edges      trails [{a, b, kind "trail", points, half, length}]
#   sdf        signed wall distance (m, + open) on the NAV grid, map edge included
#   kind       wall character per cell (Wall enum of arena_border.gd + RUIN)
#   loot_points  Vector4(x, 0, z, tier 0..2) amber nodes
#   beacons    tall landmarks [{kind, center, radius}]
#   basins     stage 29 lakes / moors / oasis [{center, radius, lobes, big, region}]
#   water, water_deep  per NAV cell: signed distance (m, - inside) to the
#              shoreline and to the deep edge; only deep water blocks, the
#              shallow band between them is walkable and slows (arena.gd)
#
# Stage 29: a swamp region holds 1-2 big basins (buchtig-rund, smooth union of
# a few discs) and 0-3 small shallow ponds instead of noise bands; the desert
# oasis is one big pond. The deep part enters the wall distance field directly
# (sdf = min(land walls, water_deep)), so the collision edge is exactly the
# edge the water shader draws from the same values.

const NAV := 2.0
const TUNING = preload("res://scripts/world/world_tuning.gd")
const STYLE := "explore"
# Sand of the loose trails: narrow, never a rail.
const SAND_SHARE := 0.5
const SAND_MIN := 1.1
enum Land { MEADOW, FOREST, THICKET, RUINS, RIDGE, SWAMP, LABYRINTH }
const LAND_NAMES := ["meadow", "forest", "thicket", "ruins", "ridge", "swamp", "labyrinth"]
# Region weights (meadow and forest most common, labyrinth rare).
const LAND_WEIGHTS := [18, 20, 12, 14, 12, 12, 10]
# Blocked share each landscape aims for (before the map-wide 25-35 % scaling).
const LAND_TARGET := [0.07, 0.26, 0.58, 0.3, 0.24, 0.36, 0.4]
# Wall characters (arena_border.gd Wall enum; RUIN is new).
const KIND_THICKET := 0
const KIND_CLIFF := 1
const KIND_ROOTS := 2
const KIND_WATER := 3
const KIND_RUIN := 4
const KIND_TREE := 5
const KIND_PILLAR := 6
# Stage 19 (Dürrschlund): rib cages (one RibBones model per cage) and cactus groves.
const KIND_RIB := 7
const KIND_CACTUS := 8
# Desert landscapes on the same Land slots: open dunes (sandstone outcrops),
# cactus grove, sandstone cliff field, bone field (rib cages), sandstone ridge,
# oasis (turquoise ponds), canyon labyrinth.
const DESERT_LAND_NAMES := ["dunes", "cactus", "cliffs", "bones", "ridge", "oasis", "canyon"]
const DESERT_LAND_WEIGHTS := [22, 16, 10, 16, 12, 12, 10]
const DESERT_LAND_TARGET := [0.07, 0.24, 0.44, 0.3, 0.26, 0.2, 0.4]
# Rib cages: one per RIB_PLOT plot (most plots), length RIB_LENGTH, width from
# the model (0.366 of its length).
const RIB_PLOT := 24.0
const RIB_LENGTH := Vector2(10.0, 13.2)
const RIB_RATIO := 0.366
# Quicksand patches (radius range) per solo map (scaled by area).
const QUICKSAND_COUNT := Vector2i(7, 10)
const QUICKSAND_RADIUS := Vector2(4.2, 6.5)
# Rock arch landmark: length (m) and its two feet (model: outer thirds).
const ARCH_LENGTH := 13.0
# Before the wide corridors (they open ~4-8 %), so the result lands in 25-35 %.
const BLOCKED_SHARE := Vector2(0.3, 0.36)
const EDGE_KEEP := 10.0
# POI types: [count (solo 4 x 4, scaled by area), clear radius, min spacing].
const POI := {
	"cocoon": [12, 4.0, 20.0], "cocoon_gold": [3, 5.0, 40.0], "shrine": [5, 6.0, 45.0],
	"nest": [8, 7.0, 30.0], "totem": [5, 5.0, 40.0], "grove": [7, 8.0, 30.0],
	"elite": [3, 9.0, 60.0],
}
const LOOT_COUNT := Vector2i(60, 90)
# Stage 29 basins: radius ranges (m; diameter 14-30 big, 4-8 small ponds), the
# smooth-union blend of their lobes, open land between two basins and around
# every shore (no other wall there, the shallow band always joins the land).
const BASIN_BIG := Vector2(8.5, 15.0)
const BASIN_SMALL := Vector2(2.0, 4.0)
const OASIS_RADIUS := Vector2(10.0, 13.5)
const BASIN_BLEND := 3.0
const BASIN_GAP := 8.0
const BASIN_RING := 5.0
const BASIN_START_GAP := 20.0
const SWAMP_ISLANDS := 0.16
# Water field value far from any basin, and the cells that count as blocked for
# the mask (closer than WATER_OPEN to the deep edge: too tight to pass).
const WATER_FAR := 64.0
const WATER_OPEN := 0.9
# Deep value of a cell a later pass had to open (a ford): walkable, shallow look.
const WATER_FORD := 1.6

var rng := RandomNumberGenerator.new()
# Read by arena.gd (sand band of the trails; null on the 18b layout).
var sand_share := SAND_SHARE
var sand_min := SAND_MIN
var style := STYLE
var playable := Rect2()
var bounds := Rect2()
var center := Vector3.ZERO
var regions := 4
var grid := 0
var grid_origin := Vector2.ZERO
var sdf := PackedFloat32Array()
var blocked := PackedByteArray()
var kind := PackedByteArray()
var land := PackedByteArray()
var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var hub := 0
var boss := -1
var maw := -1
var landmarks: Array[Dictionary] = []
var stones: Array[Vector4] = []
var eruption_points: Array[Vector4] = []
var loot_points: Array[Vector4] = []
var beacons: Array[Dictionary] = []
## Stage 19: biome of this map ("duerrschlund" builds the desert variant).
var biome_id := ""
var desert := false
## Desert rib cages [{center, yaw, length, width, cells}] (intact ones only).
var ribs: Array[Dictionary] = []
## Desert quicksand patches Vector4(x, 0, z, radius) on open ground.
var quicksand: Array[Vector4] = []
## Stage 29 basins [{center: Vector3, radius (nominal), lobes: PackedVector3Array
## (x, z, r), big: bool, region: Vector2i}] and their water fields (see header).
var basins: Array[Dictionary] = []
var water := PackedFloat32Array()
var water_deep := PackedFloat32Array()
var _keep_clear: Array[Vector3] = []
var _water_rng := RandomNumberGenerator.new()
var _fords := 0
var _flooded := 0
var _land_weights: Array = LAND_WEIGHTS
var _land_target: Array = LAND_TARGET
var _ribs_dropped := 0
var region_lands: Dictionary = {}
var attempts := 1
var build_msec := 0.0
var _region_seeds: Dictionary = {}
var _noise_a := FastNoiseLite.new()
var _noise_b := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _cells := FastNoiseLite.new()
var _filled := 0
var _ruin_cos := 1.0
var _ruin_sin := 0.0
var _joined := 0


func _init(seed_value: int, playable_rect: Rect2, bounds_rect: Rect2, map_regions: int, starts: Array[Vector3], arrivals: Array[Vector3], biome := "") -> void:
	var started := Time.get_ticks_usec()
	biome_id = biome
	desert = biome == "duerrschlund"
	if desert:
		_land_weights = DESERT_LAND_WEIGHTS
		_land_target = DESERT_LAND_TARGET
	playable = playable_rect
	bounds = bounds_rect
	regions = map_regions
	center = Vector3(playable.get_center().x, 0.0, playable.get_center().y)
	rng.seed = hash("mawlings-explore:%d:%d" % [seed_value, regions])
	# Stage 29: the basins draw from their own stream (the rest of a map keeps
	# the random sequence it had before the lakes).
	_water_rng.seed = hash("mawlings-water:%d:%d" % [seed_value, regions])
	for noise in [_noise_a, _noise_b, _warp, _cells]:
		noise.seed = rng.randi()
	_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_a.frequency = 1.0 / 30.0
	_noise_a.fractal_octaves = 2
	_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_b.frequency = 1.0 / 13.0
	_noise_b.fractal_octaves = 1
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 1.0 / 60.0
	_warp.fractal_octaves = 1
	_cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cells.frequency = 1.0 / 17.0
	_cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_cells.cellular_jitter = 0.9
	_cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	grid = ceili(bounds.size.x / NAV)
	grid_origin = bounds.position
	var ruin_angle := rng.randf_range(-0.6, 0.6)
	_ruin_cos = cos(ruin_angle)
	_ruin_sin = sin(ruin_angle)
	var start := _pick_start(starts)
	_keep_clear = [start]
	if starts.size() > 1:
		_keep_clear.append_array(starts)
	_keep_clear.append_array(arrivals)
	_roll_regions(start)
	_mark("init")
	_build_mask()
	_drop_specks()
	_mask_share = _blocked_share()
	_mark("mask")
	_place_pois(start, starts, arrivals)
	_mark("pois")
	_carve_pois()
	_join_open()
	_settle_ribs()
	_mark("join")
	_bake_sdf()
	# Two rounds: a corridor may reveal (or pass) another cut-off wide area.
	for round_index in 2:
		if _join_wide() == 0:
			break
		_settle_ribs()
		_bake_sdf()
	_mark("sdf")
	_trails()
	_mark("trails")
	_place_loot()
	_eruptions()
	if desert:
		_place_quicksand()
	_mark("loot")
	build_msec = float(Time.get_ticks_usec() - started) / 1000.0


## Build time per phase (ms), for perf notes.
var timings := {}
var _mark_at := 0


func _mark(label: String) -> void:
	var now := Time.get_ticks_usec()
	if _mark_at > 0:
		timings[label] = float(now - _mark_at) / 1000.0
	_mark_at = now


# ------------------------------------------------------------------ helpers

func _cell_center(ix: int, iz: int) -> Vector2:
	return Vector2(grid_origin.x + (float(ix) + 0.5) * NAV, grid_origin.y + (float(iz) + 0.5) * NAV)


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((point.x - grid_origin.x) / NAV), 0, grid - 1), clampi(floori((point.z - grid_origin.y) / NAV), 0, grid - 1))


func _region_size() -> float:
	return bounds.size.x / float(regions)


func _region_of(x: float, z: float) -> Vector2i:
	var size := _region_size()
	return Vector2i(clampi(floori((x - bounds.position.x) / size), 0, regions - 1), clampi(floori((z - bounds.position.y) / size), 0, regions - 1))


func _inner(margin: float) -> Rect2:
	return playable.grow(-margin)


func _random_point(margin: float) -> Vector3:
	var inner := _inner(margin)
	return Vector3(rng.randf_range(inner.position.x, inner.end.x), 0.0, rng.randf_range(inner.position.y, inner.end.y))


# Solo: a random open spot away from the edge; multiplayer keeps the given ring.
func _pick_start(starts: Array[Vector3]) -> Vector3:
	if starts.size() > 1:
		return starts[0]
	var inner := _inner(playable.size.x * 0.22)
	return Vector3(rng.randf_range(inner.position.x, inner.end.x), 0.0, rng.randf_range(inner.position.y, inner.end.y))


# ------------------------------------------------------------------ landscape

func _roll_regions(start: Vector3) -> void:
	var total := 0
	for weight in _land_weights:
		total += weight
	var size := _region_size()
	var start_region := _region_of(start.x, start.z)
	for rz in regions:
		for rx in regions:
			var key := Vector2i(rx, rz)
			var roll := rng.randi() % total
			var pick := 0
			for index in _land_weights.size():
				roll -= _land_weights[index]
				if roll < 0:
					pick = index
					break
			# The start region is walkable at first glance.
			if key == start_region:
				pick = Land.MEADOW if rng.randf() < 0.6 else Land.FOREST
			region_lands[key] = pick
			_region_seeds[key] = Vector2(bounds.position.x + (float(rx) + rng.randf_range(0.25, 0.75)) * size, bounds.position.y + (float(rz) + rng.randf_range(0.25, 0.75)) * size)
	# No two neighbouring regions of the same rare, heavy kind.
	for rz in regions:
		for rx in regions:
			var here: int = region_lands[Vector2i(rx, rz)]
			if here in [Land.THICKET, Land.LABYRINTH, Land.SWAMP]:
				for other in [Vector2i(rx - 1, rz), Vector2i(rx, rz - 1)]:
					if region_lands.has(other) and region_lands[other] == here:
						region_lands[Vector2i(rx, rz)] = Land.FOREST if rng.randf() < 0.5 else Land.MEADOW
	# Stage 19: every desert has its signature landscapes (bone field, oasis,
	# cactus grove) at least once, taken from the open dunes.
	if desert:
		for wanted in [Land.RUINS, Land.SWAMP, Land.FOREST]:
			if region_lands.values().has(wanted):
				continue
			var spare: Array[Vector2i] = []
			for key in region_lands:
				if key != start_region and region_lands[key] == Land.MEADOW:
					spare.append(key)
			if spare.is_empty():
				for key in region_lands:
					if key != start_region and region_lands[key] != Land.RUINS and region_lands[key] != Land.SWAMP:
						spare.append(key)
			if not spare.is_empty():
				region_lands[spare[rng.randi() % spare.size()]] = wanted


# One noise over the whole grid as bytes (native FastNoiseLite.get_image; one
# pixel = one NAV cell, value 0..255 = noise -1..1). `scale` stretches space.
func _noise_grid(noise: FastNoiseLite, scale := 1.0) -> PackedByteArray:
	var base := noise.frequency
	noise.frequency = base * NAV * scale
	noise.offset = Vector3(grid_origin.x / NAV + 0.5, grid_origin.y / NAV + 0.5, 0.0)
	var image := noise.get_image(grid, grid, false, false, false)
	noise.frequency = base
	noise.offset = Vector3.ZERO
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	return image.get_data()


const BYTE := 1.0 / 127.5


static func _unit_byte(value: int) -> float:
	return float(value) / 127.5 - 1.0


# Landscape of every cell: nearest region seed after a domain warp (organic
# borders), computed on a half-resolution grid and spread to the full one.
func _land_grid(warp_x: PackedByteArray, warp_z: PackedByteArray) -> void:
	var seeds := PackedVector2Array()
	var lands := PackedInt32Array()
	for rz in regions:
		for rx in regions:
			seeds.append(_region_seeds[Vector2i(rx, rz)])
			lands.append(region_lands[Vector2i(rx, rz)])
	var size := _region_size()
	var half := (grid + 1) / 2
	var w := grid
	for hz in half:
		var iz := mini(hz * 2, w - 1)
		var cz := grid_origin.y + (float(iz) + 0.5) * NAV
		for hx in half:
			var ix := mini(hx * 2, w - 1)
			var index := iz * w + ix
			var wx := grid_origin.x + (float(ix) + 0.5) * NAV + (float(warp_x[index]) * BYTE - 1.0) * 34.0
			var wz := cz + (float(warp_z[index]) * BYTE - 1.0) * 34.0
			var rx := clampi(floori((wx - bounds.position.x) / size), 0, regions - 1)
			var rz := clampi(floori((wz - bounds.position.y) / size), 0, regions - 1)
			var best := INF
			var pick := 0
			for oz in range(maxi(0, rz - 1), mini(regions, rz + 2)):
				for ox in range(maxi(0, rx - 1), mini(regions, rx + 2)):
					var s := seeds[oz * regions + ox]
					var d := (wx - s.x) * (wx - s.x) + (wz - s.y) * (wz - s.y)
					if d < best:
						best = d
						pick = lands[oz * regions + ox]
			var x := hx * 2
			var z := hz * 2
			land[z * w + x] = pick
			if x + 1 < w:
				land[z * w + x + 1] = pick
			if z + 1 < w:
				land[(z + 1) * w + x] = pick
				if x + 1 < w:
					land[(z + 1) * w + x + 1] = pick

static func _hash2(x: int, z: int, salt: int) -> int:
	var n := x * 374761393 + z * 668265263 + salt * 144269
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n ^ (n >> 16))


# Ruin field: building remains on a skewed 20 m grid - rooms with 2.4 m walls,
# a doorway in most sides, broken wall stretches (corners always stand) and
# loose pillars between the houses. Returns Vector2(density, kind): density
# > 0 = blocked (absolute), kind KIND_RUIN or KIND_PILLAR.
func _ruin(x: float, z: float, broken: float) -> Vector2:
	var u := x * _ruin_cos + z * _ruin_sin
	var v := -x * _ruin_sin + z * _ruin_cos
	var iu := floori(u / 20.0)
	var iv := floori(v / 20.0)
	var lu := u - float(iu) * 20.0
	var lv := v - float(iv) * 20.0
	# Loose pillar where four house plots meet.
	var pu := minf(lu, 20.0 - lu)
	var pv := minf(lv, 20.0 - lv)
	var corner_u := iu + (1 if lu > 10.0 else 0)
	var corner_v := iv + (1 if lv > 10.0 else 0)
	if pu < 1.8 and pv < 1.8 and _hash2(corner_u, corner_v, 51) % 10 < 6:
		return Vector2(1.0, KIND_PILLAR)
	var h := _hash2(iu, iv, 50)
	if h % 10 < 2:
		return Vector2(-1.0, KIND_RUIN)
	var hw := 4.0 + float(h % 7) * 0.45
	var hh := 4.0 + float((h >> 4) % 7) * 0.45
	var cu := 10.0 + float((h >> 8) % 5 - 2) * 0.6
	var cv := 10.0 + float((h >> 12) % 5 - 2) * 0.6
	var du := absf(lu - cu) - hw
	var dv := absf(lv - cv) - hh
	var outline := maxf(du, dv)
	if absf(outline) > 1.2:
		return Vector2(-1.0, KIND_RUIN)
	# Corners always stand (the L shape reads as a building).
	var near_corner := du > -2.8 and dv > -2.8
	if not near_corner:
		# A doorway in most sides (3 m, position per side).
		var on_u := du > dv
		var along := (lv - cv) if on_u else (lu - cu)
		var side := (1 if (lu > cu if on_u else lv > cv) else 0) + (2 if on_u else 0)
		if (h >> (16 + side)) % 4 != 0:
			var door := float((h >> (20 + side * 2)) % 5 - 2) * 1.2
			if absf(along - door) < 1.5:
				return Vector2(-1.0, KIND_RUIN)
		if broken > 0.25:
			return Vector2(-1.0, KIND_RUIN)
	return Vector2(1.2 - absf(outline), KIND_RUIN)


func _build_mask() -> void:
	var count := grid * grid
	var density := PackedFloat32Array()
	density.resize(count)
	blocked.resize(count)
	kind.resize(count)
	land.resize(count)
	var na := _noise_grid(_noise_a)
	var nb := _noise_grid(_noise_b)
	var nc := _noise_grid(_cells)
	var warp_x := _noise_grid(_warp)
	_warp.seed += 17
	var warp_z := _noise_grid(_warp)
	_warp.seed -= 17
	_land_grid(warp_x, warp_z)
	_place_basins(nb)
	for iz in grid:
		for ix in grid:
			var index := iz * grid + ix
			var a := float(na[index]) * BYTE - 1.0
			var b := float(nb[index]) * BYTE - 1.0
			var type: int = land[index]
			var value := 0.0
			var wall := KIND_CLIFF
			if desert:
				var dv := _desert_value(type, a, b, float(nc[index]) * BYTE)
				density[index] = dv.x
				kind[index] = int(dv.y)
				continue
			match type:
				Land.MEADOW:
					value = b * 0.8 + a * 0.5 - 0.72
				Land.FOREST:
					value = 0.18 - float(nc[index]) * BYTE * 0.5 + a * 0.12
					wall = KIND_TREE
				Land.THICKET:
					value = a * 0.9 + b * 0.35 + 0.12
					wall = KIND_THICKET if b > -0.2 else KIND_ROOTS
				Land.RUINS:
					var ruin := _ruin(grid_origin.x + (float(ix) + 0.5) * NAV, grid_origin.y + (float(iz) + 0.5) * NAV, b)
					value = ruin.x
					wall = int(ruin.y)
				Land.RIDGE:
					value = (0.11 - absf(a)) * 4.0 - maxf(0.0, b - 0.55) * 3.0 + (b * 0.5 - 0.62)
				Land.SWAMP:
					# Stage 29: open moor between the basins; the rest of its blocked
					# share are a few root and thicket islands.
					value = a * 0.9 + b * 0.35
					wall = KIND_ROOTS if b > 0.1 else KIND_THICKET
				_:
					value = (0.1 - minf(absf(a * 1.3), absf(b))) * 5.0
			density[index] = value
			kind[index] = wall
	# Stage 29: no other wall on and around the water (the shallow band always
	# joins open land; the deep part is stamped below).
	for basin in basins:
		var reach := float(basin.radius) + BASIN_RING + 4.0
		var lo := _cell_of(basin.center - Vector3(reach, 0.0, reach))
		var hi := _cell_of(basin.center + Vector3(reach, 0.0, reach))
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				var index := iz * grid + ix
				if water[index] < BASIN_RING:
					density[index] = -10.0
	# Every landscape gets its own threshold (its character: few rocks on a
	# meadow, a dense thicket), scaled together so the map stays 25-35 %
	# blocked; ruins keep their own absolute shape.
	var samples: Array = []
	var deep_samples := PackedInt32Array()
	for type in _land_target.size():
		samples.append([])
		deep_samples.append(0)
	var mix := 0.0
	var total := 0
	var inner := playable.grow(-EDGE_KEEP)
	for iz in range(0, grid, 2):
		for ix in range(0, grid, 2):
			var p := _cell_center(ix, iz)
			if inner.has_point(p):
				var index := iz * grid + ix
				(samples[land[index]] as Array).append(density[index])
				if water_deep[index] < WATER_OPEN:
					deep_samples[land[index]] += 1
				mix += _land_target[land[index]]
				total += 1
	var natural := mix / float(maxi(1, total))
	var factor := lerpf(BLOCKED_SHARE.x, BLOCKED_SHARE.y, 0.5) / maxf(0.01, natural)
	var thresholds := PackedFloat32Array()
	for type in LAND_TARGET.size():
		var values: Array = samples[type]
		values.sort()
		if values.is_empty() or type == Land.RUINS:
			thresholds.append(0.0)
			continue
		# Deep water already counts towards the landscape's blocked share; the
		# swamp stays mostly open moor (a few islands, at most SWAMP_ISLANDS).
		var share: float = clampf(_land_target[type] * factor - float(deep_samples[type]) / float(values.size()), 0.0, 0.9)
		if type == Land.SWAMP:
			share = minf(share, SWAMP_ISLANDS)
		thresholds.append(values[clampi(roundi((1.0 - share) * float(values.size())), 0, values.size() - 1)] if share > 0.0 else 10.0)
	for iz in grid:
		var z := grid_origin.y + (float(iz) + 0.5) * NAV
		var dz := minf(z - playable.position.y, playable.end.y - z)
		for ix in grid:
			var x := grid_origin.x + (float(ix) + 0.5) * NAV
			var index := iz * grid + ix
			var edge := minf(minf(x - playable.position.x, playable.end.x - x), dz)
			if edge < 1.0:
				blocked[index] = 1
			elif edge < EDGE_KEEP:
				blocked[index] = 0
			elif water_deep[index] < WATER_OPEN:
				blocked[index] = 1
				kind[index] = KIND_WATER
			else:
				blocked[index] = 1 if density[index] > thresholds[land[index]] else 0
	if desert:
		_rib_cages()


# Stage 18c follow-up: blocking pieces are big and clear - a blocked patch of
# fewer than MIN_BLOCK cells (~3.5 m across) becomes open ground instead.
const MIN_BLOCK := 4
var _specks := 0

func _drop_specks() -> void:
	var count := grid * grid
	var w := grid
	var seen := PackedByteArray()
	seen.resize(count)
	for seed_cell in count:
		if blocked[seed_cell] == 0 or seen[seed_cell] == 1:
			continue
		var members := PackedInt32Array([seed_cell])
		seen[seed_cell] = 1
		var head := 0
		var touches_edge := false
		while head < members.size():
			var here := members[head]
			head += 1
			var x := here % w
			if x == 0 or x == w - 1 or here < w or here >= count - w:
				touches_edge = true
			for next in [here + 1 if x + 1 < w else -1, here - 1 if x > 0 else -1, here + w if here + w < count else -1, here - w if here >= w else -1]:
				if next >= 0 and blocked[next] == 1 and seen[next] == 0:
					seen[next] = 1
					members.append(next)
		if members.size() < MIN_BLOCK and not touches_edge:
			for cell in members:
				blocked[cell] = 0
			_specks += 1


# ------------------------------------------------------------------ water (stage 29)

# Every swamp region: 1-2 big basins and 0-3 small ponds (the desert oasis: one
# big pond), placed inside its own land, apart from each other and from the
# start and arrival clearings. `wobble` (noise bytes per cell) roughens the shore.
func _place_basins(wobble: PackedByteArray) -> void:
	basins.clear()
	var count := grid * grid
	water.resize(count)
	water.fill(WATER_FAR)
	water_deep.resize(count)
	water_deep.fill(WATER_FAR)
	for rz in regions:
		for rx in regions:
			var key := Vector2i(rx, rz)
			if region_lands[key] != Land.SWAMP:
				continue
			if desert:
				_try_basin(key, OASIS_RADIUS, true)
				continue
			for index in (1 if _water_rng.randf() < 0.3 else 2):
				_try_basin(key, BASIN_BIG, true)
			for index in _water_rng.randi_range(0, 3):
				_try_basin(key, BASIN_SMALL, false)
	for basin in basins:
		_stamp_basin(basin, wobble)
	# Every cell the water fields touch (the later passes only look there).
	_wet_cells = PackedInt32Array()
	for index in count:
		if water[index] < WATER_FAR:
			_wet_cells.append(index)


var _wet_cells := PackedInt32Array()

func _basin_cells() -> PackedInt32Array:
	return _wet_cells


# Tries to fit one basin of a radius in `sizes` into region `key` (smaller on
# later tries). Returns true if one was added.
func _try_basin(key: Vector2i, sizes: Vector2, big: bool) -> bool:
	var size := _region_size()
	var corner := bounds.position + Vector2(key) * size
	for attempt in 48:
		var radius := _water_rng.randf_range(sizes.x, lerpf(sizes.y, sizes.x, float(attempt) / 60.0))
		var point := Vector3(corner.x + _water_rng.randf_range(0.1, 0.9) * size, 0.0, corner.y + _water_rng.randf_range(0.1, 0.9) * size)
		if not _inner(EDGE_KEEP + radius + 3.0).has_point(Vector2(point.x, point.z)):
			continue
		# Mostly inside its own land (the warped region border may cut a bay).
		var inside := 0
		for step in 8:
			var angle := TAU * float(step) / 8.0
			var probe := _cell_of(point + Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.85)
			if land[probe.y * grid + probe.x] == Land.SWAMP:
				inside += 1
		var middle := _cell_of(point)
		if land[middle.y * grid + middle.x] != Land.SWAMP or inside < (6 if attempt < 30 else 4):
			continue
		var clash := false
		for spot in _keep_clear:
			if Vector2(spot.x - point.x, spot.z - point.z).length() < radius + BASIN_START_GAP:
				clash = true
				break
		for other in basins:
			if clash:
				break
			if point.distance_to(other.center) < radius + float(other.radius) + BASIN_GAP:
				clash = true
		if clash:
			continue
		basins.append({"center": point, "radius": radius, "lobes": _lobes(point, radius, big), "big": big, "region": key})
		return true
	return false


# Lobes of a basin: a main disc and 3-5 (small ponds 1-2) overlapping side
# discs, blended smoothly - a round lake with bays, never a chain of puddles.
func _lobes(point: Vector3, radius: float, big: bool) -> PackedVector3Array:
	var lobes := PackedVector3Array([Vector3(point.x, point.z, radius * _water_rng.randf_range(0.58, 0.7))])
	var count := _water_rng.randi_range(3, 5) if big else _water_rng.randi_range(1, 2)
	var turn := _water_rng.randf() * TAU
	for index in count:
		var angle := turn + TAU * float(index) / float(count) + _water_rng.randf_range(-0.45, 0.45)
		var reach := radius * _water_rng.randf_range(0.3, 0.5)
		var lobe := maxf(radius * 0.3, (radius - reach) * _water_rng.randf_range(0.82, 1.0))
		lobes.append(Vector3(point.x + cos(angle) * reach, point.z + sin(angle) * reach, lobe))
	return lobes


# Polynomial smooth minimum (blend radius k).
static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


# Signed shore distance of one basin at a point (before the wobble).
static func _basin_value(lobes: PackedVector3Array, x: float, z: float) -> float:
	var value := Vector2(x - lobes[0].x, z - lobes[0].y).length() - lobes[0].z
	for index in range(1, lobes.size()):
		var lobe := lobes[index]
		value = _smin(value, Vector2(x - lobe.x, z - lobe.y).length() - lobe.z, BASIN_BLEND)
	return value


# Writes a basin into the water fields: shore distance with a gentle noise
# wobble, deep distance SHALLOW_WIDTH further in (small ponds stay shallow).
func _stamp_basin(basin: Dictionary, wobble: PackedByteArray) -> void:
	var reach := float(basin.radius) + BASIN_BLEND + BASIN_RING + 4.0
	var center: Vector3 = basin.center
	var lo := _cell_of(center - Vector3(reach, 0.0, reach))
	var hi := _cell_of(center + Vector3(reach, 0.0, reach))
	var lobes: PackedVector3Array = basin.lobes
	var big: bool = basin.big
	var shallow := TUNING.SHALLOW_WIDTH if big else float(basin.radius) + 3.0
	var rough := 0.9 if big else 0.35
	for iz in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			var index := iz * grid + ix
			var p := _cell_center(ix, iz)
			var value := _basin_value(lobes, p.x, p.y) + (float(wobble[index]) * BYTE - 1.0) * rough
			if value < water[index]:
				water[index] = value
			water_deep[index] = minf(water_deep[index], value + shallow)


# After every pass that opened or closed cells: the water fields follow the
# final mask. A deep cell a pass opened becomes a shallow ford; a shallow cell a
# pass closed becomes deep water. Blocked water = deep closer than WATER_OPEN.
func _settle_water() -> void:
	for index in _wet_cells:
		if water_deep[index] < WATER_OPEN:
			if blocked[index] == 0:
				water_deep[index] = WATER_FORD
				_fords += 1
		elif blocked[index] == 1 and water[index] < 0.0:
			water_deep[index] = -1.0
			kind[index] = KIND_WATER
			_flooded += 1


# True for a cell of deep (blocked) water - the carving passes go around it.
func _deep(index: int) -> bool:
	return water_deep.size() > index and water_deep[index] < WATER_OPEN


## Signed distance to the shoreline at a world point (m, - in the water;
## bilinear like sample(); WATER_FAR without water nearby).
func water_at(x: float, z: float) -> float:
	return _bilinear(water, x, z)


## Signed distance to the deep edge (m, - in deep water = the collision edge).
func deep_at(x: float, z: float) -> float:
	return _bilinear(water_deep, x, z)


func _bilinear(values: PackedFloat32Array, x: float, z: float) -> float:
	if values.is_empty():
		return WATER_FAR
	var fx := (x - grid_origin.x) / NAV - 0.5
	var fz := (z - grid_origin.y) / NAV - 0.5
	var ix := clampi(floori(fx), 0, grid - 2)
	var iz := clampi(floori(fz), 0, grid - 2)
	var i := iz * grid + ix
	# Far from every basin: skip the blend.
	if values[i] >= WATER_FAR:
		return WATER_FAR
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var top := values[i] + (values[i + 1] - values[i]) * tx
	var bottom := values[i + grid] + (values[i + grid + 1] - values[i + grid]) * tx
	return top + (bottom - top) * tz


# ------------------------------------------------------------------ desert (stage 19)

# Density and wall kind of a desert cell (same noise inputs as the green map).
func _desert_value(type: int, a: float, b: float, cell: float) -> Vector2:
	match type:
		Land.MEADOW:
			return Vector2(b * 0.8 + a * 0.5 - 0.72, KIND_CLIFF)
		Land.FOREST:
			return Vector2(0.18 - cell * 0.5 + a * 0.12, KIND_CACTUS)
		Land.THICKET:
			return Vector2(a * 0.9 + b * 0.35 + 0.12, KIND_CLIFF)
		Land.RUINS:
			# Bone field: open sand, the rib cages are stamped in afterwards.
			return Vector2(-1.0, KIND_CLIFF)
		Land.RIDGE:
			return Vector2((0.11 - absf(a)) * 4.0 - maxf(0.0, b - 0.55) * 3.0 + (b * 0.5 - 0.62), KIND_CLIFF)
		Land.SWAMP:
			# Stage 29: the oasis pond is a basin; around it a few sandstone
			# outcrops and cacti.
			return Vector2(a * 0.9 + b * 0.35, KIND_CACTUS if b > 0.2 else KIND_CLIFF)
	return Vector2((0.1 - minf(absf(a * 1.3), absf(b))) * 5.0, KIND_CLIFF)


# Bone field: one big rib cage per RIB_PLOT plot (skewed grid like the ruins),
# stamped into the mask as a solid block exactly under the RibBones model.
func _rib_cages() -> void:
	ribs.clear()
	var inner := playable.grow(-(EDGE_KEEP + 4.0))
	var corners := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in corners:
		var u: float = corner.x * _ruin_cos + corner.y * _ruin_sin
		var v: float = -corner.x * _ruin_sin + corner.y * _ruin_cos
		lo = Vector2(minf(lo.x, u), minf(lo.y, v))
		hi = Vector2(maxf(hi.x, u), maxf(hi.y, v))
	var base_angle := atan2(_ruin_sin, _ruin_cos)
	for iv in range(floori(lo.y / RIB_PLOT), ceili(hi.y / RIB_PLOT)):
		for iu in range(floori(lo.x / RIB_PLOT), ceili(hi.x / RIB_PLOT)):
			var h := _hash2(iu, iv, 61)
			if h % 10 < 3:
				continue
			var u := (float(iu) + 0.5) * RIB_PLOT + float((h >> 4) % 7 - 3) * 0.9
			var v := (float(iv) + 0.5) * RIB_PLOT + float((h >> 7) % 7 - 3) * 0.9
			var center := Vector2(u * _ruin_cos - v * _ruin_sin, u * _ruin_sin + v * _ruin_cos)
			if not inner.has_point(center):
				continue
			var cell := _cell_of(Vector3(center.x, 0.0, center.y))
			if land[cell.y * grid + cell.x] != Land.RUINS:
				continue
			var length := lerpf(RIB_LENGTH.x, RIB_LENGTH.y, float((h >> 10) % 5) / 4.0)
			var angle := base_angle + float((h >> 13) % 9 - 4) * 0.14 + (PI * 0.5 if (h >> 17) % 3 == 0 else 0.0)
			var axis := Vector2(cos(angle), sin(angle))
			var half_length := length * 0.5 + 0.3
			var half_width := length * RIB_RATIO * 0.5 + 0.4
			var reach := half_length + 2.0
			var c0 := _cell_of(Vector3(center.x - reach, 0.0, center.y - reach))
			var c1 := _cell_of(Vector3(center.x + reach, 0.0, center.y + reach))
			var cells := PackedInt32Array()
			for iz in range(c0.y, c1.y + 1):
				for ix in range(c0.x, c1.x + 1):
					var d := _cell_center(ix, iz) - center
					if absf(d.dot(axis)) < half_length and absf(d.x * -axis.y + d.y * axis.x) < half_width:
						cells.append(iz * grid + ix)
			for index in cells:
				blocked[index] = 1
				kind[index] = KIND_RIB
			# Model yaw: its long axis (+z) along the cage axis.
			ribs.append({"center": Vector3(center.x, 0.0, center.y), "yaw": atan2(axis.x, axis.y), "length": length, "width": length * RIB_RATIO, "cells": cells})


# A rib cage is one model: when a POI clearing, a joined pocket or a wide
# corridor opened any of its cells, the whole cage goes (never half a skeleton).
func _settle_ribs() -> void:
	if not desert:
		return
	for index in range(ribs.size() - 1, -1, -1):
		var cells: PackedInt32Array = ribs[index].cells
		var intact := true
		for cell in cells:
			if blocked[cell] == 0:
				intact = false
				break
		if intact:
			continue
		for cell in cells:
			blocked[cell] = 0
			kind[cell] = KIND_CLIFF
		ribs.remove_at(index)
		_ribs_dropped += 1


# Rock arch landmark: walkable underneath, only its two feet block (two
# circles per foot along its depth, inside the model's foot footprint).
func _add_arch(point: Vector3, node: int) -> void:
	# Span across the screen (feet west and east): the camera in the south sees
	# the opening, the way under it runs north-south.
	var yaw := (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.3, 0.3)
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var depth := Vector3(sin(yaw), 0.0, cos(yaw))
	var feet: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var foot: Vector3 = point + across * (side * ARCH_LENGTH * 0.335)
		feet.append(foot)
		for step in [-1.0, 1.0]:
			var spot: Vector3 = foot + depth * (step * 1.45)
			stones.append(Vector4(spot.x, 0.0, spot.z, 2.1))
	beacons.append({"kind": "rock_arch", "center": point, "radius": ARCH_LENGTH * 0.5, "node": node, "yaw": yaw, "feet": feet})


# Quicksand: round patches on open sand (dunes and bone fields first), away
# from every place, the start and each other. Walkable, only slows.
func _place_quicksand() -> void:
	quicksand.clear()
	var target := rng.randi_range(QUICKSAND_COUNT.x, QUICKSAND_COUNT.y) * regions * regions / 16
	var start_point: Vector3 = nodes[hub].center
	var tries := 0
	while quicksand.size() < target and tries < target * 80:
		tries += 1
		var radius := rng.randf_range(QUICKSAND_RADIUS.x, QUICKSAND_RADIUS.y)
		var point := _random_point(radius + 14.0)
		if sample(point.x, point.z) < radius + 1.2 or water_at(point.x, point.z) < radius + 2.0:
			continue
		var cell := _cell_of(point)
		var type: int = land[cell.y * grid + cell.x]
		if not type in [Land.MEADOW, Land.RUINS, Land.FOREST] and rng.randf() < 0.7:
			continue
		if point.distance_to(start_point) < radius + 26.0:
			continue
		var clash := false
		for other in nodes:
			if point.distance_to(other.center) < float(other.radius) + radius + 3.0:
				clash = true
				break
		if not clash:
			for other in quicksand:
				if Vector2(other.x - point.x, other.z - point.z).length() < other.w + radius + 10.0:
					clash = true
					break
		if not clash:
			for stone in stones:
				if Vector2(stone.x - point.x, stone.z - point.z).length() < stone.w + radius + 2.0:
					clash = true
					break
		if not clash:
			for amber in loot_points:
				if Vector2(amber.x - point.x, amber.z - point.z).length() < radius + 1.5:
					clash = true
					break
		if clash:
			continue
		quicksand.append(Vector4(point.x, 0.0, point.z, radius))


# ------------------------------------------------------------------ POIs

func _poi_count(base: int) -> int:
	return maxi(1, roundi(float(base) * float(regions * regions) / 16.0))


func _free(point: Vector3, radius: float, spacing: float) -> bool:
	if not _inner(radius + 12.0).has_point(Vector2(point.x, point.z)):
		return false
	# Stage 29: places never stand in the water (the whole clearing stays dry).
	if water_at(point.x, point.z) < radius * 1.15 + 2.5:
		return false
	for node in nodes:
		var other: Vector3 = node.center
		if Vector2(point.x - other.x, point.z - other.z).length() < radius + float(node.radius) + spacing * 0.5:
			return false
	return true


# Open share around a point (0..1) - POIs prefer places that are already open.
func _openness(point: Vector3, radius: float) -> float:
	var open := 0
	var total := 0
	for step in 8:
		var angle := TAU * float(step) / 8.0
		for reach in [radius * 0.5, radius]:
			var cell := _cell_of(point + Vector3(cos(angle), 0.0, sin(angle)) * reach)
			total += 1
			if blocked[cell.y * grid + cell.x] == 0:
				open += 1
	return float(open) / float(total)


func _add_node(point: Vector3, radius: float, type: String) -> int:
	var node := {
		"center": Vector3(point.x, 0.0, point.z), "radius": radius, "types": [type],
		"amp": Vector3(rng.randf_range(0.04, 0.09), rng.randf_range(0.03, 0.06), rng.randf_range(0.02, 0.05)),
		"phase": Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU),
		"slots": {type: [Vector3(point.x, 0.0, point.z)]}, "edges": [],
	}
	nodes.append(node)
	return nodes.size() - 1


# Best of `tries` random candidates: free, as open as possible, scored by `score`.
func _scatter(radius: float, spacing: float, tries: int, score: Callable) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	for attempt in tries:
		var point := _random_point(radius + 14.0)
		if not _free(point, radius, spacing):
			continue
		var value: float = score.call(point) + _openness(point, radius) * 2.0 + rng.randf() * 0.5
		if value > best_score:
			best_score = value
			best = point
	return best


func _danger(point: Vector3) -> float:
	var cell := _cell_of(point)
	var type: int = land[cell.y * grid + cell.x]
	return 1.0 if type in [Land.THICKET, Land.LABYRINTH, Land.SWAMP, Land.RUINS] else 0.0


func _place_pois(start: Vector3, starts: Array[Vector3], arrivals: Array[Vector3]) -> void:
	nodes.clear()
	var solo := starts.size() <= 1
	if solo:
		hub = _add_node(start, 14.0, "start")
	else:
		for point in starts:
			var index := _add_node(point, 14.0, "start")
			if index == 0:
				hub = index
	for point in arrivals:
		_add_node(point, 12.0, "arrival")
	var start_point: Vector3 = nodes[hub].center
	var span := playable.size.x
	# Boss arena: a wide open area somewhere far enough from the start.
	# At least ~110 m from the start (the apex comes from there; stage 18b had >= 90 m).
	var boss_point := _scatter(24.0, 30.0, 80, func(p: Vector3) -> float:
		var far := p.distance_to(start_point)
		return (minf(far, span * 0.5) / span * 4.0) - (20.0 if far < span * 0.33 else 0.0))
	if boss_point.is_finite():
		boss = _add_node(boss_point, 24.0, "boss")
	# Migrationsschlund: far from the boss arena.
	var maw_point := _scatter(10.0, 30.0, 60, func(p: Vector3) -> float:
		return (p.distance_to(nodes[boss].center) if boss >= 0 else p.distance_to(start_point)) / span * 4.0)
	if maw_point.is_finite():
		maw = _add_node(maw_point, 10.0, "maw")
	# Tall landmarks: 4 (solo), spread far apart, never on a POI.
	# Stage 18c follow-up: only forms whose base matches the collision circle.
	var lure_kinds := ["giant_skull", "rock_arch"] if desert else ["giant_tree", "bone_pillar", "stone_needle"]
	lure_kinds.shuffle()
	for index in _poi_count(4):
		var point := _scatter(10.0, 50.0, 60, func(p: Vector3) -> float:
			var near := INF
			for mark in beacons:
				near = minf(near, p.distance_to(mark.center))
			return minf(near, span) / span * 3.0)
		if point.is_finite():
			var node := _add_node(point, 10.0, "landmark")
			var lure: String = lure_kinds[index % lure_kinds.size()]
			if lure == "rock_arch":
				_add_arch(point, node)
			elif lure == "giant_skull":
				beacons.append({"kind": lure, "center": point, "radius": 3.5, "node": node, "yaw": rng.randf() * TAU})
				stones.append(Vector4(point.x, 0.0, point.z, 3.5))
			else:
				beacons.append({"kind": lure, "center": point, "radius": 2.6, "node": node})
				stones.append(Vector4(point.x, 0.0, point.z, 2.6))
	for type in ["elite", "shrine", "cocoon_gold", "nest", "totem", "grove", "cocoon"]:
		var spec: Array = POI[type]
		for index in _poi_count(int(spec[0])):
			var golden: bool = type == "cocoon_gold" or type == "elite"
			var point := _scatter(float(spec[1]), float(spec[2]), 30, func(p: Vector3) -> float:
				var away := minf(p.distance_to(start_point), span * 0.6) / span
				return (_danger(p) * 2.0 + away * 2.0) if golden else (-0.5 if p.distance_to(start_point) < 20.0 else 0.0))
			if point.is_finite():
				_add_node(point, float(spec[1]), type)


# Clears an organic disc around every POI.
func _carve_pois() -> void:
	for node in nodes:
		var c: Vector3 = node.center
		var reach := float(node.radius) * 1.2 + 2.0
		var lo := _cell_of(c - Vector3(reach, 0.0, reach))
		var hi := _cell_of(c + Vector3(reach, 0.0, reach))
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				var p := _cell_center(ix, iz)
				if _clearing_value(node, p.x, p.y) >= -0.5 and playable.grow(-1.0).has_point(p):
					blocked[iz * grid + ix] = 0


# Every open pocket joins the main ground: small ones are filled, bigger ones
# get a carved gap to the nearest main cell (so nothing is ever cut off).
func _join_open() -> void:
	var count := grid * grid
	var component := PackedInt32Array()
	component.resize(count)
	component.fill(-1)
	var start_cell := _cell_of(nodes[hub].center)
	var first := start_cell.y * grid + start_cell.x
	var open := blocked
	var cells_of: Array = []
	var w := grid
	var order := PackedInt32Array([first])
	for index in count:
		if open[index] == 0:
			order.append(index)
	for seed_cell in order:
		if open[seed_cell] != 0 or component[seed_cell] >= 0:
			continue
		var id := cells_of.size()
		var members := PackedInt32Array([seed_cell])
		component[seed_cell] = id
		var head := 0
		while head < members.size():
			var here := members[head]
			head += 1
			var x := here % w
			if x + 1 < w and open[here + 1] == 0 and component[here + 1] < 0:
				component[here + 1] = id
				members.append(here + 1)
			if x > 0 and open[here - 1] == 0 and component[here - 1] < 0:
				component[here - 1] = id
				members.append(here - 1)
			if here + w < count and open[here + w] == 0 and component[here + w] < 0:
				component[here + w] = id
				members.append(here + w)
			if here >= w and open[here - w] == 0 and component[here - w] < 0:
				component[here - w] = id
				members.append(here - w)
		cells_of.append(members)
	# A pocket holding a place is always joined, never filled (its clearing stays).
	var holds := {}
	for node in nodes:
		var cell := _cell_of(node.center)
		holds[component[cell.y * w + cell.x]] = true
	for id in range(1, cells_of.size()):
		var members: PackedInt32Array = cells_of[id]
		if members.size() < 40 and not holds.has(id):
			for cell in members:
				blocked[cell] = 1
			_filled += 1
			continue
		_bridge(members, component)
		_joined += 1

# Multi-source BFS through the wall from a pocket to the main ground; the path
# found is carved 3 cells wide. Stage 29: around deep water first (`dry`), only
# through it when there is no other way.
func _bridge(members: PackedInt32Array, component: PackedInt32Array, dry := true) -> void:
	var count := grid * grid
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-2)
	var queue := PackedInt32Array()
	for cell in members:
		parent[cell] = -1
		queue.append(cell)
	var head := 0
	var goal := -1
	while head < queue.size() and goal < 0:
		var here := queue[head]
		head += 1
		var x := here % grid
		var z := here / grid
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + offset.x
			var nz: int = z + offset.y
			if nx < 2 or nz < 2 or nx >= grid - 2 or nz >= grid - 2:
				continue
			var next := nz * grid + nx
			if parent[next] != -2 or (dry and _deep(next)):
				continue
			parent[next] = here
			if blocked[next] == 0 and component[next] == 0:
				goal = next
				break
			queue.append(next)
	if goal < 0 and dry and not basins.is_empty():
		_bridge(members, component, false)
		return
	var cell := goal
	while cell >= 0 and parent[cell] != -1:
		var x := cell % grid
		var z := cell / grid
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nx := clampi(x + dx, 1, grid - 2)
				var nz := clampi(z + dz, 1, grid - 2)
				if playable.grow(-1.0).has_point(_cell_center(nx, nz)) and not (dry and _deep(nz * grid + nx)):
					blocked[nz * grid + nx] = 0
					component[nz * grid + nx] = 0
		cell = parent[cell]
	for member in members:
		component[member] = 0


# ------------------------------------------------------------------ distance field

# Signed distance in one two-pass chamfer: every cell on the boundary between
# open and blocked ground starts at half a cell, the sign comes from the mask.
func _bake_sdf() -> void:
	var count := grid * grid
	var w := grid
	var mask := blocked
	# Stage 29: deep water is not part of the chamfer mask - its exact distance
	# (water_deep) is blended in below, so its edge is round, not cell-shaped.
	if not basins.is_empty():
		_settle_water()
		mask = blocked.duplicate()
		for index in _basin_cells():
			if water_deep[index] < WATER_OPEN:
				mask[index] = 0
	var dist := PackedFloat32Array()
	dist.resize(count)
	var far := float(grid * 2)
	for z in w:
		for x in w:
			var i := z * w + x
			var own := mask[i]
			var edge := (x > 0 and mask[i - 1] != own) or (x < w - 1 and mask[i + 1] != own) or (z > 0 and mask[i - w] != own) or (z < w - 1 and mask[i + w] != own)
			dist[i] = 0.5 if edge else far
	var diag := 1.4142
	for z in w:
		for x in w:
			var i := z * w + x
			var d := dist[i]
			if d <= 0.5:
				continue
			if x > 0:
				d = minf(d, dist[i - 1] + 1.0)
			if z > 0:
				d = minf(d, dist[i - w] + 1.0)
				if x > 0:
					d = minf(d, dist[i - w - 1] + diag)
				if x < w - 1:
					d = minf(d, dist[i - w + 1] + diag)
			dist[i] = d
	for z in range(w - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := z * w + x
			var d := dist[i]
			if d <= 0.5:
				continue
			if x < w - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if z < w - 1:
				d = minf(d, dist[i + w] + 1.0)
				if x < w - 1:
					d = minf(d, dist[i + w + 1] + diag)
				if x > 0:
					d = minf(d, dist[i + w - 1] + diag)
			dist[i] = d
	for iz in w:
		var z := grid_origin.y + (float(iz) + 0.5) * NAV
		var dz := minf(z - playable.position.y, playable.end.y - z)
		for ix in w:
			var i := iz * w + ix
			var value := dist[i] * NAV if mask[i] == 0 else -dist[i] * NAV
			var x := grid_origin.x + (float(ix) + 0.5) * NAV
			var inside := minf(minf(x - playable.position.x, playable.end.x - x), dz)
			dist[i] = minf(value, inside)
	for index in _basin_cells():
		dist[index] = minf(dist[index], water_deep[index])
	sdf = dist

# Big bodies (Bog King, apex: radius up to 3.2 m) need wide ground: every
# larger area with WIDE m of wall distance gets a carved corridor (~8 m) to
# the main wide ground around the start. Returns the number of corridors.
const WIDE := 3.6
var _wide_joined := 0
var _mask_share := 0.0

func _blocked_share() -> float:
	var inside := 0
	var closed := 0
	var inner := playable.grow(-EDGE_KEEP)
	for iz in grid:
		for ix in grid:
			if inner.has_point(_cell_center(ix, iz)):
				inside += 1
				closed += blocked[iz * grid + ix]
	return float(closed) / float(maxi(1, inside))

func _join_wide() -> int:
	var count := grid * grid
	var w := grid
	var wide := PackedByteArray()
	wide.resize(count)
	for index in count:
		wide[index] = 1 if sdf[index] >= WIDE else 0
	# Landmark stones block big bodies as well (as in the big-body flow field).
	for stone in stones:
		var reach := stone.w + WIDE
		var lo := _cell_of(Vector3(stone.x - reach, 0.0, stone.z - reach))
		var hi := _cell_of(Vector3(stone.x + reach, 0.0, stone.z + reach))
		for iz in range(lo.y, hi.y + 1):
			for ix in range(lo.x, hi.x + 1):
				var c := _cell_center(ix, iz)
				if Vector2(c.x - stone.x, c.y - stone.z).length() < reach:
					wide[iz * w + ix] = 0
	var component := PackedInt32Array()
	component.resize(count)
	component.fill(-1)
	var groups: Array = []
	for seed_cell in count:
		if wide[seed_cell] == 0 or component[seed_cell] >= 0:
			continue
		var id := groups.size()
		var members := PackedInt32Array([seed_cell])
		component[seed_cell] = id
		var head := 0
		while head < members.size():
			var here := members[head]
			head += 1
			var x := here % w
			if x + 1 < w and wide[here + 1] == 1 and component[here + 1] < 0:
				component[here + 1] = id
				members.append(here + 1)
			if x > 0 and wide[here - 1] == 1 and component[here - 1] < 0:
				component[here - 1] = id
				members.append(here - 1)
			if here + w < count and wide[here + w] == 1 and component[here + w] < 0:
				component[here + w] = id
				members.append(here + w)
			if here >= w and wide[here - w] == 1 and component[here - w] < 0:
				component[here - w] = id
				members.append(here - w)
		groups.append(members)
	if groups.size() < 2:
		return 0
	# Main wide ground: the group at the start, else the largest.
	var start_cell := _cell_of(nodes[hub].center)
	var main := component[start_cell.y * w + start_cell.x]
	if main < 0:
		var biggest := 0
		for id in groups.size():
			if (groups[id] as PackedInt32Array).size() > biggest:
				biggest = (groups[id] as PackedInt32Array).size()
				main = id
	# One BFS from the main wide ground over every cell: each cell learns the
	# way back to it; every other group follows that way from its nearest cell.
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-2)
	var dist := PackedInt32Array()
	dist.resize(count)
	var queue := PackedInt32Array()
	var deeps := water_deep
	var wet := not basins.is_empty()
	for cell in groups[main]:
		parent[cell] = -1
		queue.append(cell)
	var head := 0
	while head < queue.size():
		var here := queue[head]
		head += 1
		var x := here % w
		var d := dist[here] + 1
		# Stage 29: never carve a corridor through or along deep water (there it
		# would stay too narrow for big bodies anyway).
		if wet and deeps[here] < WIDE + 1.0 and parent[here] != -1:
			continue
		if x + 1 < w and parent[here + 1] == -2:
			parent[here + 1] = here
			dist[here + 1] = d
			queue.append(here + 1)
		if x > 0 and parent[here - 1] == -2:
			parent[here - 1] = here
			dist[here - 1] = d
			queue.append(here - 1)
		if here + w < count and parent[here + w] == -2:
			parent[here + w] = here
			dist[here + w] = d
			queue.append(here + w)
		if here >= w and parent[here - w] == -2:
			parent[here - w] = here
			dist[here - w] = d
			queue.append(here - w)
	# Groups holding a place (big bodies may start there) or of real size.
	var holds := {}
	for node in nodes:
		var cell_of := _cell_of(node.center)
		holds[component[cell_of.y * w + cell_of.x]] = true
	var joined := 0
	for id in groups.size():
		var members: PackedInt32Array = groups[id]
		if id == main or (members.size() < 70 and not holds.has(id)):
			continue
		var cell := -1
		for member in members:
			if parent[member] != -2 and (cell < 0 or dist[member] < dist[cell]):
				cell = member
		# Stage 29: a group only reachable along the water stays as it is.
		if cell < 0:
			continue
		while cell >= 0 and parent[cell] >= 0 and component[cell] != main:
			var cx := cell % w
			var cz := cell / w
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if dx * dx + dz * dz > 5:
						continue
					var nx := clampi(cx + dx, 1, w - 2)
					var nz := clampi(cz + dz, 1, w - 2)
					if not _deep(nz * w + nx):
						blocked[nz * w + nx] = 0
			cell = parent[cell]
		joined += 1
	_wide_joined = joined
	return joined


# ------------------------------------------------------------------ trails

# Loose trampled trails: from the start to its three nearest POIs and between a
# few neighbouring POIs, found by A* over open ground (they wind with the land).
func _trails() -> void:
	edges.clear()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid, grid)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for index in grid * grid:
		# Stage 29: trails keep out of the shallow water too.
		if sdf[index] < 1.5 or water[index] < 0.5:
			astar.set_point_solid(Vector2i(index % grid, index / grid), true)
	# Trails lead somewhere: from the start and between important places
	# (boss arena, elite camps, shrines, landmarks, the Schlund) 45-120 m apart,
	# each place joined at most twice; they wind with the land (A*).
	var pairs: Array = []
	var major: Array[int] = []
	for index in nodes.size():
		if String(nodes[index].types[0]) in ["start", "boss", "elite", "shrine", "landmark", "maw", "cocoon_gold"]:
			major.append(index)
	var links := {}
	var candidates: Array = []
	for i in major.size():
		for j in range(i + 1, major.size()):
			var a: int = major[i]
			var b: int = major[j]
			var d: float = (nodes[a].center as Vector3).distance_to(nodes[b].center)
			if d > 45.0 and d < 120.0:
				candidates.append([d + rng.randf() * 30.0, a, b])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var wanted := _poi_count(9)
	for entry in candidates:
		if pairs.size() >= wanted:
			break
		var a: int = entry[1]
		var b: int = entry[2]
		if int(links.get(a, 0)) >= 2 or int(links.get(b, 0)) >= 2:
			continue
		pairs.append([a, b])
		links[a] = int(links.get(a, 0)) + 1
		links[b] = int(links.get(b, 0)) + 1
	for pair in pairs:
		var a_cell := _cell_of(nodes[pair[0]].center)
		var b_cell := _cell_of(nodes[pair[1]].center)
		if astar.is_point_solid(a_cell) or astar.is_point_solid(b_cell):
			continue
		var path := astar.get_id_path(a_cell, b_cell)
		if path.size() < 6:
			continue
		var raw := PackedVector3Array()
		for step in range(0, path.size(), 3):
			var c := _cell_center(path[step].x, path[step].y)
			raw.append(Vector3(c.x, 0.0, c.y))
		var last := _cell_center(path[path.size() - 1].x, path[path.size() - 1].y)
		raw.append(Vector3(last.x, 0.0, last.y))
		var points := _smooth(_smooth(raw))
		var half := PackedFloat32Array()
		var wobble := rng.randf() * TAU
		for index in points.size():
			half.append(2.2 + 0.5 * sin(float(index) * 0.7 + wobble))
		var total := 0.0
		for index in points.size() - 1:
			total += points[index].distance_to(points[index + 1])
		edges.append({"a": pair[0], "b": pair[1], "kind": "trail", "points": points, "half": half, "length": total, "mst": false})
		(nodes[pair[0]].edges as Array).append(edges.size() - 1)
		(nodes[pair[1]].edges as Array).append(edges.size() - 1)


func _paired(pairs: Array, a: int, b: int) -> bool:
	for pair in pairs:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


# Chaikin corner cutting (keeps the end points).
static func _smooth(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 3:
		return points
	var result := PackedVector3Array([points[0]])
	for index in points.size() - 1:
		result.append(points[index].lerp(points[index + 1], 0.25))
		result.append(points[index].lerp(points[index + 1], 0.75))
	result.append(points[points.size() - 1])
	return result


# ------------------------------------------------------------------ loot and eruptions

# Amber nodes: denser in forest, ruins, thicket edges and near the map edge,
# rarer on open meadow; tier 0..2 grows with the distance from the start and
# in dangerous land.
func _place_loot() -> void:
	loot_points.clear()
	var target := rng.randi_range(LOOT_COUNT.x, LOOT_COUNT.y) * regions * regions / 16
	var start_point: Vector3 = nodes[hub].center
	var span := playable.size.x
	var tries := 0
	while loot_points.size() < target and tries < target * 40:
		tries += 1
		var point := _random_point(6.0)
		var value := sample(point.x, point.z)
		if value < 1.2 or water_at(point.x, point.z) < 1.0:
			continue
		var cell := _cell_of(point)
		var type: int = land[cell.y * grid + cell.x]
		var weight: float = [0.35, 1.0, 1.0, 1.0, 0.7, 0.8, 0.9][type]
		# Close to a wall (in the nooks) and near the map edge: more.
		if value < 5.0:
			weight += 0.4
		if -_edge_distance(point) < 40.0:
			weight += 0.3
		if rng.randf() > weight * 0.6:
			continue
		var clash := false
		for node in nodes:
			if point.distance_to(node.center) < float(node.radius) + 2.0:
				clash = true
				break
		if clash:
			continue
		for other in loot_points:
			if Vector2(other.x - point.x, other.z - point.z).length() < 7.0:
				clash = true
				break
		if clash:
			continue
		var depth := clampf(point.distance_to(start_point) / (span * 0.6), 0.0, 1.0) + _danger(point) * 0.5
		var tier := 0 if depth < 0.45 else (1 if depth < 1.05 else 2)
		loot_points.append(Vector4(point.x, 0.0, point.z, float(tier)))


func _eruptions() -> void:
	eruption_points.clear()
	for attempt in 600:
		var point := _random_point(4.0)
		if sample(point.x, point.z) > 2.5:
			eruption_points.append(Vector4(point.x, 0.0, point.z, 1.0))


# ------------------------------------------------------------------ queries (map_layout.gd interface)

func _clearing_rim(node: Dictionary, angle: float) -> float:
	var amp: Vector3 = node.amp
	var phase: Vector3 = node.phase
	return float(node.radius) * (1.0 + amp.x * sin(3.0 * angle + phase.x) + amp.y * sin(5.0 * angle + phase.y) + amp.z * sin(2.0 * angle + phase.z))


func _clearing_value(node: Dictionary, x: float, z: float) -> float:
	var c: Vector3 = node.center
	var dx := x - c.x
	var dz := z - c.z
	return _clearing_rim(node, atan2(dz, dx)) - sqrt(dx * dx + dz * dz)


func _edge_distance(point: Vector3) -> float:
	var dx := maxf(playable.position.x - point.x, point.x - playable.end.x)
	var dz := maxf(playable.position.y - point.z, point.z - playable.end.y)
	if dx > 0.0 and dz > 0.0:
		return Vector2(dx, dz).length()
	return maxf(dx, dz)


## Signed wall distance at a world point (bilinear; + open, - inside a wall).
func sample(x: float, z: float) -> float:
	var fx := (x - grid_origin.x) / NAV - 0.5
	var fz := (z - grid_origin.y) / NAV - 0.5
	var ix := clampi(floori(fx), 0, grid - 2)
	var iz := clampi(floori(fz), 0, grid - 2)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var i := iz * grid + ix
	var top := sdf[i] + (sdf[i + 1] - sdf[i]) * tx
	var bottom := sdf[i + grid] + (sdf[i + grid + 1] - sdf[i + grid]) * tx
	return top + (bottom - top) * tz


## Direction of rising wall distance (towards open ground), not normalised.
func gradient(x: float, z: float) -> Vector2:
	var fx := (x - grid_origin.x) / NAV - 0.5
	var fz := (z - grid_origin.y) / NAV - 0.5
	var ix := clampi(floori(fx), 0, grid - 2)
	var iz := clampi(floori(fz), 0, grid - 2)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var i := iz * grid + ix
	var gx := (sdf[i + 1] - sdf[i]) * (1.0 - tz) + (sdf[i + grid + 1] - sdf[i + grid]) * tz
	var gz := (sdf[i + grid] - sdf[i]) * (1.0 - tx) + (sdf[i + grid + 1] - sdf[i + 1]) * tx
	return Vector2(gx, gz)


## Wall character at a point (arena_border.gd Wall enum, 4 = ruin, 5 = tree group).
func kind_at(x: float, z: float) -> int:
	var cell := _cell_of(Vector3(x, 0.0, z))
	return kind[cell.y * grid + cell.x]


## Landscape name at a point ("meadow", "forest", ...; desert "dunes", "bones", ...).
func land_at(x: float, z: float) -> String:
	var cell := _cell_of(Vector3(x, 0.0, z))
	return (DESERT_LAND_NAMES if desert else LAND_NAMES)[land[cell.y * grid + cell.x]]


## Quicksand patch index at a point (-1 = none).
func quicksand_at(point: Vector3, margin := 0.0) -> int:
	for index in quicksand.size():
		var patch := quicksand[index]
		if Vector2(point.x - patch.x, point.z - patch.z).length() < patch.w + margin:
			return index
	return -1


func clearing_at(point: Vector3) -> int:
	for index in nodes.size():
		if _clearing_value(nodes[index], point.x, point.z) >= 0.0:
			return index
	return -1


func slots(type: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node in nodes:
		if node.slots.has(type):
			for spot in node.slots[type]:
				result.append(spot)
	return result


func stats() -> Dictionary:
	var inside := 0
	var closed := 0
	for iz in grid:
		for ix in grid:
			if playable.grow(-EDGE_KEEP).has_point(_cell_center(ix, iz)):
				inside += 1
				if blocked[iz * grid + ix] == 1:
					closed += 1
	var counts := {}
	for node in nodes:
		var type: String = node.types[0]
		counts[type] = int(counts.get(type, 0)) + 1
	var lands := {}
	for key in region_lands:
		var name: String = (DESERT_LAND_NAMES if desert else LAND_NAMES)[region_lands[key]]
		lands[name] = int(lands.get(name, 0)) + 1
	return {"timings": timings, "blocked": float(closed) / float(maxi(1, inside)), "pois": counts, "trails": edges.size(), "loot": loot_points.size(), "beacons": beacons.size(), "filled": _filled, "joined": _joined, "wide_joined": _wide_joined, "mask_share": _mask_share, "lands": lands, "ribs": ribs.size(), "ribs_dropped": _ribs_dropped, "quicksand": quicksand.size(), "basins": basins.size(), "fords": _fords, "flooded": _flooded, "msec": build_msec, "clearings": nodes.size(), "paths": edges.size(), "bridges": 0, "min_degree": 0, "loops": 0, "hub_degree": (nodes[hub].edges as Array).size(), "attempts": attempts, "narrow": 0}
