extends RefCounted

# Stage 18b: the seeded map as a designed level. Clearings are the nodes of a
# graph, paths its edges; everything else is impassable wall (thicket, rock,
# roots, water - Glutsumpf: charred wood, basalt, lava). Pure data: built once
# per seed / biome / map size, deterministic, no nodes.
#
#   nodes  [{center, radius, types, slots, amp, phase, main}]   clearings
#   edges  [{a, b, kind, points, half, length, mst}]            paths
#   sdf    signed wall distance on a NAV grid (+ = open, metres to the
#          nearest wall; - = inside a wall), including the map edge
#
# Generation (seeded RNG, retried with the same stream if a rule fails):
#   1. clearings: forced start/arrival points, a big hub in the middle, the
#      boss arena far from the start, the Migrationsschlund on the opposite
#      side near the edge, then best-candidate darts with a wall gap;
#   2. POI types (nest, cocoon, totem, grove, landmark) spread over the rest;
#   3. paths: Delaunay candidates -> minimum spanning tree (wide main roads)
#      plus narrow extra paths until every clearing has two ways out, the graph
#      has no bridge (no dead end to be chased into) and enough loops;
#   4. geometry: gently bent centrelines, main 16-20 m wide, narrow ones 9-12 m
#      with a 8-9 m choke; checked against each other and third clearings;
#   5. furnishing: POI slots, a landmark per landmark clearing, cover stones;
#   6. the SDF grid (clearings as wavy discs, paths as capsule chains).

const NAV := 2.0
const SDF_MARGIN := 7.0
const EDGE_WALL := 14.0
const GAP := 30.0
const HUB_RADIUS := Vector2(30.0, 33.0)
const BOSS_RADIUS := Vector2(26.0, 29.0)
const START_RADIUS := Vector2(20.0, 23.0)
const MAW_RADIUS := Vector2(18.0, 21.0)
const CLEARING_RADIUS := Vector2(15.0, 24.0)
const MAIN_HALF := Vector2(7.0, 9.0)
const NARROW_HALF := Vector2(4.8, 6.0)
const PINCH_HALF := 4.4
const PATH_WALL := 8.0
const SAMPLE_STEP := 3.0
const MOUTH_ANGLE := deg_to_rad(34.0)
# Share of the map regions that become clearings (solo 4 x 4 -> 10 + hub).
const CLEARINGS_PER_REGION := 0.62
# POI types spread over the free clearings, in this order; the first seven are
# required (doubled up on bigger clearings if the map has too few).
const TYPE_ORDER := ["nest", "cocoon", "totem", "grove", "nest", "cocoon", "landmark", "nest", "landmark", "grove", "cocoon", "landmark", "nest", "totem", "grove", "landmark"]
const REQUIRED_TYPES := 7
# Landmark kinds of arena.gd (Landmark enum): ROOT_ARCH, FALLEN_LOG, POND, MEADOW.
const LANDMARK_KINDS := 4
const STONE_RADIUS := 1.85

var rng := RandomNumberGenerator.new()
var playable := Rect2()
var bounds := Rect2()
var center := Vector3.ZERO
var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var hub := 0
var boss := -1
var maw := -1
# Signed wall distance grid (cell centres at bounds.position + (i + 0.5) * NAV).
var grid := 0
var grid_origin := Vector2.ZERO
var sdf := PackedFloat32Array()
var landmarks: Array[Dictionary] = []
var stones: Array[Vector4] = []
var eruption_points: Array[Vector4] = []
var attempts := 0
var build_msec := 0.0


func _init(seed_value: int, playable_rect: Rect2, bounds_rect: Rect2, regions: int, starts: Array[Vector3], arrivals: Array[Vector3]) -> void:
	var started := Time.get_ticks_usec()
	playable = playable_rect
	bounds = bounds_rect
	center = Vector3(playable.get_center().x, 0.0, playable.get_center().y)
	rng.seed = hash("mawlings-map:%d:%d" % [seed_value, regions])
	for attempt in 6:
		attempts = attempt + 1
		if _generate(regions, starts, arrivals, attempt >= 4):
			break
	_furnish()
	_bake_sdf()
	_eruptions()
	build_msec = float(Time.get_ticks_usec() - started) / 1000.0


# ------------------------------------------------------------------ generation

func _generate(regions: int, starts: Array[Vector3], arrivals: Array[Vector3], relaxed: bool) -> bool:
	nodes.clear()
	edges.clear()
	boss = -1
	maw = -1
	_place_nodes(regions, starts, arrivals)
	_assign_types()
	if not _build_graph(relaxed):
		return false
	_shape_paths()
	return relaxed or (_connected(-1) and _bridges().is_empty() and _hub_ok())


func _node(point: Vector3, radius: float, types: Array) -> int:
	var node := {
		"center": Vector3(point.x, 0.0, point.z), "radius": radius, "types": types.duplicate(),
		"amp": Vector3(rng.randf_range(0.03, 0.07), rng.randf_range(0.02, 0.05), rng.randf_range(0.02, 0.045)),
		"phase": Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU),
		"slots": {}, "edges": [],
	}
	nodes.append(node)
	return nodes.size() - 1


func _inner(radius: float) -> Rect2:
	return playable.grow(-(EDGE_WALL + radius))


func _clamp(point: Vector3, radius: float) -> Vector3:
	var inner := _inner(radius)
	if inner.size.x <= 0.0:
		return center
	return Vector3(clampf(point.x, inner.position.x, inner.end.x), 0.0, clampf(point.z, inner.position.y, inner.end.y))


# Smallest wall gap between a candidate clearing and the placed ones.
func _gap(point: Vector3, radius: float) -> float:
	var best := INF
	for node in nodes:
		var other: Vector3 = node.center
		best = minf(best, Vector2(point.x - other.x, point.z - other.z).length() - radius - float(node.radius))
	return best


func _random_point(radius: float) -> Vector3:
	var inner := _inner(radius)
	return Vector3(rng.randf_range(inner.position.x, inner.end.x), 0.0, rng.randf_range(inner.position.y, inner.end.y))


func _place_nodes(regions: int, starts: Array[Vector3], arrivals: Array[Vector3]) -> void:
	var size := playable.size.x
	var solo := starts.size() <= 1
	# Start clearings (solo: the hub in the middle) and migration arrivals.
	for point in starts:
		var at_center := Vector2(point.x - center.x, point.z - center.z).length() < 1.0
		var radius := rng.randf_range(HUB_RADIUS.x, HUB_RADIUS.y) if at_center else rng.randf_range(START_RADIUS.x, START_RADIUS.y)
		var index := _node(_clamp(point, radius) if not at_center else point, radius, ["start"])
		if at_center:
			hub = index
	if not solo:
		hub = _node(center, rng.randf_range(HUB_RADIUS.x, HUB_RADIUS.y) - 2.0, ["landmark"])
	for point in arrivals:
		var inside := false
		for node in nodes:
			var other: Vector3 = node.center
			if Vector2(point.x - other.x, point.z - other.z).length() < float(node.radius) - 6.0:
				inside = true
		if not inside:
			var radius := rng.randf_range(START_RADIUS.x, START_RADIUS.y)
			_node(_clamp(point, radius), radius, ["arrival"])
	# Boss arena: big, far from every start.
	var boss_radius := rng.randf_range(BOSS_RADIUS.x, BOSS_RADIUS.y)
	var best_point := Vector3.INF
	var best_score := -INF
	for sample in 48:
		var point := _random_point(boss_radius)
		var gap := _gap(point, boss_radius)
		if gap < GAP:
			continue
		var far := INF
		for node in nodes:
			if node.types.has("start") or node.types.has("arrival"):
				far = minf(far, point.distance_to(node.center))
		var score := minf(gap, 60.0) + minf(far, size * 0.42) * 0.8 + rng.randf() * 6.0
		if far >= size * 0.28 and score > best_score:
			best_score = score
			best_point = point
	if best_point.is_finite():
		boss = _node(best_point, boss_radius, ["boss"])
	# Migrationsschlund: near the edge, as far from the boss arena as possible.
	var maw_radius := rng.randf_range(MAW_RADIUS.x, MAW_RADIUS.y)
	best_point = Vector3.INF
	best_score = -INF
	for sample in 48:
		var point := _random_point(maw_radius)
		var gap := _gap(point, maw_radius)
		if gap < GAP:
			continue
		var edge := -_edge_distance(point)
		var away: float = point.distance_to(nodes[boss].center) if boss >= 0 else point.distance_to(center)
		var score := away - maxf(0.0, edge - maw_radius - EDGE_WALL - 12.0) * 1.5 + rng.randf() * 6.0
		if score > best_score:
			best_score = score
			best_point = point
	if best_point.is_finite():
		maw = _node(best_point, maw_radius, ["maw"])
	# The rest: best-candidate darts (spread evenly, a real wall between rims).
	var wanted := maxi(8, roundi(float(regions * regions) * CLEARINGS_PER_REGION)) + 1
	var misses := 0
	while nodes.size() < wanted and misses < 40:
		var radius := rng.randf_range(CLEARING_RADIUS.x, CLEARING_RADIUS.y)
		var pick := Vector3.INF
		var pick_gap := -INF
		for sample in 16:
			var point := _random_point(radius)
			var gap := _gap(point, radius)
			if gap > pick_gap:
				pick_gap = gap
				pick = point
		if pick_gap < GAP:
			# Crowded: try again once with the smallest clearing size.
			radius = CLEARING_RADIUS.x
			pick_gap = _gap(pick, radius)
			if pick_gap < GAP:
				misses += 1
				continue
		_node(pick, radius, [])


func _free_nodes() -> Array[int]:
	var result: Array[int] = []
	for index in nodes.size():
		if (nodes[index].types as Array).is_empty():
			result.append(index)
	return result


# Spreads the POI types: the first of a type goes to the free clearing nearest to
# the start (early reach), every further one as far as possible from its kind.
func _assign_types() -> void:
	var start: Vector3 = nodes[hub].center
	var holders := {}
	var placed := 0
	for type in TYPE_ORDER:
		var free := _free_nodes()
		if free.is_empty():
			break
		var best := -1
		var best_score := -INF
		for index in free:
			var point: Vector3 = nodes[index].center
			var score := 0.0
			if not holders.has(type):
				score = -point.distance_to(start) + rng.randf() * 20.0
			else:
				var near := INF
				for other in holders[type]:
					near = minf(near, point.distance_to(nodes[other].center))
				score = near + rng.randf() * 10.0
			if score > best_score:
				best_score = score
				best = index
		(nodes[best].types as Array).append(type)
		if not holders.has(type):
			holders[type] = []
		holders[type].append(best)
		placed += 1
	# Too few clearings: the missing required types share a clearing (secondary
	# slot at half the radius), landmark clearings first, never start/boss/maw.
	for order in range(placed, REQUIRED_TYPES):
		var type: String = TYPE_ORDER[order]
		var host := -1
		var host_score := INF
		for index in nodes.size():
			var types: Array = nodes[index].types
			if types.has("start") or types.has("arrival") or types.has("boss") or types.has("maw") or types.has(type):
				continue
			var score := float(types.size()) - (0.5 if types.has("landmark") else 0.0) - float(nodes[index].radius) * 0.01
			if score < host_score:
				host_score = score
				host = index
		if host >= 0:
			(nodes[host].types as Array).append(type)
	for index in _free_nodes():
		(nodes[index].types as Array).append("landmark")


# --- graph ---------------------------------------------------------------------

func _key(a: int, b: int) -> int:
	return mini(a, b) * 1024 + maxi(a, b)


func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


# A straight path between two clearings keeps its distance to every third one.
func _straight_ok(a: int, b: int) -> bool:
	var pa := _flat(nodes[a].center)
	var pb := _flat(nodes[b].center)
	for index in nodes.size():
		if index == a or index == b:
			continue
		if _segment_distance(_flat(nodes[index].center), pa, pb) < float(nodes[index].radius) * 1.17 + 14.0:
			return false
	return true


func _rim_length(a: int, b: int) -> float:
	return (nodes[a].center as Vector3).distance_to(nodes[b].center) - float(nodes[a].radius) - float(nodes[b].radius)


func _angle(from: int, to: int) -> float:
	var d: Vector3 = nodes[to].center - nodes[from].center
	return atan2(d.z, d.x)


# Path mouths at one clearing stay MOUTH_ANGLE apart (no two paths merge).
func _mouth_free(node: int, other: int) -> bool:
	var angle := _angle(node, other)
	for edge_index in nodes[node].edges:
		var edge: Dictionary = edges[edge_index]
		var far: int = edge.b if edge.a == node else edge.a
		if absf(angle_difference(angle, _angle(node, far))) < MOUTH_ANGLE:
			return false
	return true


func _has_edge(a: int, b: int) -> bool:
	for edge_index in nodes[a].edges:
		var edge: Dictionary = edges[edge_index]
		if (edge.a == a and edge.b == b) or (edge.a == b and edge.b == a):
			return true
	return false


func _add_edge(a: int, b: int, mst: bool) -> int:
	var edge := {"a": a, "b": b, "mst": mst, "kind": "main" if mst else "narrow", "points": PackedVector3Array(), "half": PackedFloat32Array(), "length": 0.0, "bend": rng.randf_range(-0.14, 0.14), "alive": true}
	edges.append(edge)
	var index := edges.size() - 1
	(nodes[a].edges as Array).append(index)
	(nodes[b].edges as Array).append(index)
	return index


func _remove_edge(index: int) -> void:
	var edge: Dictionary = edges[index]
	edge.alive = false
	(nodes[edge.a].edges as Array).erase(index)
	(nodes[edge.b].edges as Array).erase(index)


func _degree(node: int) -> int:
	return (nodes[node].edges as Array).size()


# Nodes reachable from node 0 without edge `skip` (-1 = none).
func _reach(skip: int) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(nodes.size())
	var stack: Array[int] = [0]
	seen[0] = 1
	while not stack.is_empty():
		var node: int = stack.pop_back()
		for edge_index in nodes[node].edges:
			if edge_index == skip:
				continue
			var edge: Dictionary = edges[edge_index]
			var far: int = edge.b if edge.a == node else edge.a
			if seen[far] == 0:
				seen[far] = 1
				stack.append(far)
	return seen


func _connected(skip: int) -> bool:
	return _reach(skip).count(1) == nodes.size()


## Edges whose removal splits the graph (a dead end one could be chased into).
func _bridges() -> Array[int]:
	var result: Array[int] = []
	for index in edges.size():
		if edges[index].alive and not _connected(index):
			result.append(index)
	return result


func _hub_ok() -> bool:
	return _degree(hub) >= 3


func _build_graph(relaxed: bool) -> bool:
	if nodes.size() < 3:
		return false
	var points := PackedVector2Array()
	for node in nodes:
		points.append(_flat(node.center))
	var triangles := Geometry2D.triangulate_delaunay(points)
	var seen := {}
	var candidates: Array = []
	for corner in range(0, triangles.size(), 3):
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: int = triangles[corner + pair[0]]
			var b: int = triangles[corner + pair[1]]
			var id := _key(a, b)
			if seen.has(id):
				continue
			seen[id] = true
			candidates.append([_rim_length(a, b), mini(a, b), maxi(a, b), _straight_ok(a, b)])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var longest := playable.size.x * 0.42
	# Kruskal over the good candidates, then (if needed) the rest.
	var parent := PackedInt32Array()
	for index in nodes.size():
		parent.append(index)
	for pass_index in 2:
		for candidate in candidates:
			if pass_index == 0 and (not candidate[3] or candidate[0] > longest):
				continue
			var ra := _root(parent, candidate[1])
			var rb := _root(parent, candidate[2])
			if ra == rb:
				continue
			parent[ra] = rb
			_add_edge(candidate[1], candidate[2], true)
	if not _connected(-1):
		return false
	var usable := func(candidate: Array, check_mouth: bool) -> bool:
		if _has_edge(candidate[1], candidate[2]):
			return false
		if not relaxed and (not candidate[3] or candidate[0] > longest):
			return false
		if check_mouth and not (_mouth_free(candidate[1], candidate[2]) and _mouth_free(candidate[2], candidate[1])):
			return false
		return true
	# 1. No clearing with a single way out.
	for index in nodes.size():
		if _degree(index) >= 2:
			continue
		for check in [true, false]:
			var added := false
			for candidate in candidates:
				if (candidate[1] == index or candidate[2] == index) and usable.call(candidate, check):
					_add_edge(candidate[1], candidate[2], false)
					added = true
					break
			if added:
				break
	# 2. At least three paths into the hub (two loops through the middle).
	for check in [true, false]:
		for candidate in candidates:
			if _degree(hub) >= 3:
				break
			if (candidate[1] == hub or candidate[2] == hub) and usable.call(candidate, check):
				_add_edge(candidate[1], candidate[2], false)
	# 3. No bridges: a short extra path around every one.
	for round_index in 12:
		var bridges := _bridges()
		if bridges.is_empty():
			break
		var side := _reach(bridges[0])
		var added := false
		for check in [true, false]:
			for candidate in candidates:
				if side[candidate[1]] != side[candidate[2]] and usable.call(candidate, check):
					_add_edge(candidate[1], candidate[2], false)
					added = true
					break
			if added:
				break
		if not added:
			break
	# 4. More loops (variety: skip some candidates by chance).
	var target := maxi(3, roundi(float(nodes.size()) * 0.45))
	for candidate in candidates:
		if _loops() >= target:
			break
		if usable.call(candidate, true) and rng.randf() < 0.75:
			_add_edge(candidate[1], candidate[2], false)
	return true


func _root(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index:
		index = parent[index]
	return index


## Independent loops of the path graph (edges - nodes + 1).
func _loops() -> int:
	var alive := 0
	for edge in edges:
		if edge.alive:
			alive += 1
	return alive - nodes.size() + 1


# --- path geometry -----------------------------------------------------------------

func _shape_paths() -> void:
	# The hub keeps wide roads (at most one narrow shortcut).
	var narrow_at_hub := 0
	for edge_index in nodes[hub].edges:
		if edges[edge_index].kind == "narrow":
			narrow_at_hub += 1
			if narrow_at_hub > 1:
				edges[edge_index].kind = "main"
	# Important clearings (nests, then the boss arena, which wins shared paths)
	# get a short narrow and a long open route.
	var order: Array[int] = []
	for index in nodes.size():
		if (nodes[index].types as Array).has("nest"):
			order.append(index)
	if boss >= 0:
		order.append(boss)
	for index in order:
		if _degree(index) < 2:
			continue
		var shortest := -1
		var longest := -1
		for edge_index in nodes[index].edges:
			if shortest < 0 or _edge_length(edge_index) < _edge_length(shortest):
				shortest = edge_index
			if longest < 0 or _edge_length(edge_index) > _edge_length(longest):
				longest = edge_index
		edges[shortest].kind = "narrow"
		edges[longest].kind = "main"

	for index in edges.size():
		if edges[index].alive:
			_build_path(index)
	# Checks: unrelated paths keep a real wall between them, paths pass third
	# clearings at a distance; first straighten, then drop an extra path.
	for round_index in 3:
		var changed := false
		for index in edges.size():
			if not edges[index].alive:
				continue
			var problem := _path_conflict(index)
			if problem < 0:
				continue
			changed = true
			if absf(float(edges[index].bend)) > 0.001:
				edges[index].bend = 0.0
				_build_path(index)
			elif problem < edges.size() and absf(float(edges[problem].bend)) > 0.001:
				edges[problem].bend = 0.0
				_build_path(problem)
			elif not edges[index].mst:
				_remove_edge(index)
			elif problem < edges.size() and not edges[problem].mst:
				_remove_edge(problem)
		if not changed:
			break
	var alive: Array[Dictionary] = []
	for edge in edges:
		if edge.alive:
			alive.append(edge)
	# Re-index the node edge lists to the compacted list.
	for node in nodes:
		node.edges = []
	edges = alive
	for index in edges.size():
		(nodes[edges[index].a].edges as Array).append(index)
		(nodes[edges[index].b].edges as Array).append(index)


func _edge_length(index: int) -> float:
	return _rim_length(edges[index].a, edges[index].b)


func _build_path(index: int) -> void:
	var edge: Dictionary = edges[index]
	var a: Vector3 = nodes[edge.a].center
	var b: Vector3 = nodes[edge.b].center
	var along := b - a
	var length := along.length()
	var side := Vector3(along.z, 0.0, -along.x) / maxf(length, 0.001)
	var control := (a + b) * 0.5 + side * float(edge.bend) * length
	var steps := maxi(4, ceili(length / SAMPLE_STEP))
	var points := PackedVector3Array()
	var half := PackedFloat32Array()
	var narrow: bool = edge.kind == "narrow"
	var small := minf(float(nodes[edge.a].radius), float(nodes[edge.b].radius))
	var base: float
	if narrow:
		base = rng.randf_range(NARROW_HALF.x, NARROW_HALF.y)
	else:
		base = minf(rng.randf_range(MAIN_HALF.x, MAIN_HALF.y), small * 0.55 + 1.0)
	var pinch_at := rng.randf_range(0.38, 0.62)
	var wobble := rng.randf() * TAU
	for step in steps + 1:
		var t := float(step) / float(steps)
		var u := 1.0 - t
		points.append(a * (u * u) + control * (2.0 * u * t) + b * (t * t))
		var width := base
		if narrow:
			width = lerpf(base, PINCH_HALF, clampf(1.0 - absf(t - pinch_at) / 0.16, 0.0, 1.0))
		else:
			width = base * (1.0 + 0.08 * sin(t * TAU * 1.5 + wobble))
		half.append(width)
	edge.points = points
	edge.half = half
	var box := Rect2(points[0].x, points[0].z, 0.0, 0.0)
	var widest := 0.0
	for step in points.size():
		box = box.expand(Vector2(points[step].x, points[step].z))
		widest = maxf(widest, half[step])
	edge.box = box.grow(widest)
	edge.widest = widest
	var total := 0.0
	for step in steps:
		total += points[step].distance_to(points[step + 1])
	edge.length = total


func _max_half(edge: Dictionary) -> float:
	return float(edge.widest)


# Returns -1 if the path is fine, else the index of a conflicting path (or
# edges.size() for a conflict with a third clearing).
func _path_conflict(index: int) -> int:
	var edge: Dictionary = edges[index]
	var half := _max_half(edge)
	var points: PackedVector3Array = edge.points
	for node_index in nodes.size():
		if node_index == edge.a or node_index == edge.b:
			continue
		var node: Dictionary = nodes[node_index]
		var limit := float(node.radius) * 1.17 + half + PATH_WALL
		if not (edge.box as Rect2).grow(limit).has_point(_flat(node.center)):
			continue
		for point in points:
			if Vector2(point.x - node.center.x, point.z - node.center.z).length() < limit:
				return edges.size()
	for other_index in edges.size():
		if other_index == index or not edges[other_index].alive:
			continue
		var other: Dictionary = edges[other_index]
		var shared := -1
		if other.a == edge.a or other.b == edge.a:
			shared = edge.a
		elif other.a == edge.b or other.b == edge.b:
			shared = edge.b
		var need := half + _max_half(other) + (4.0 if shared >= 0 else PATH_WALL)
		if not (edge.box as Rect2).grow(need).intersects(other.box):
			continue
		var skip := 0.0
		var hub_point := Vector3.ZERO
		if shared >= 0:
			hub_point = nodes[shared].center
			skip = float(nodes[shared].radius) * 1.2 + 14.0
		var other_points: PackedVector3Array = other.points
		for point_index in range(0, points.size(), 2):
			var point := points[point_index]
			if shared >= 0 and point.distance_to(hub_point) < skip:
				continue
			for other_step in other_points.size() - 1:
				var q0 := other_points[other_step]
				if shared >= 0 and q0.distance_to(hub_point) < skip:
					continue
				if _segment_distance(_flat(point), _flat(q0), _flat(other_points[other_step + 1])) < need:
					return other_index
	return -1


# --- furnishing ----------------------------------------------------------------------

# Direction angles of the path mouths at a clearing.
func _mouths(index: int) -> Array[float]:
	var result: Array[float] = []
	var node: Dictionary = nodes[index]
	for edge_index in node.edges:
		var edge: Dictionary = edges[edge_index]
		var points: PackedVector3Array = edge.points
		var probe: Vector3 = points[mini(3, points.size() - 1)] if edge.a == index else points[maxi(0, points.size() - 4)]
		var d: Vector3 = probe - node.center
		result.append(atan2(d.z, d.x))
	return result


# The angle farthest from every path mouth (rotated by `turn` for more spots).
func _quiet_angle(mouths: Array[float], turn: int) -> float:
	var best := 0.0
	var best_gap := -INF
	for step in 24:
		var angle := TAU * float(step) / 24.0 + float(turn) * 0.9
		var gap := PI
		for mouth in mouths:
			gap = minf(gap, absf(angle_difference(angle, mouth)))
		if gap > best_gap + 0.01:
			best_gap = gap
			best = angle
	return best


func _furnish() -> void:
	landmarks.clear()
	stones.clear()
	for index in nodes.size():
		var node: Dictionary = nodes[index]
		var c: Vector3 = node.center
		var r: float = node.radius
		var mouths := _mouths(index)
		var slots := {}
		var types: Array = node.types
		for type_index in types.size():
			var type: String = types[type_index]
			var base := c
			if type_index > 0:
				var angle := _quiet_angle(mouths, type_index)
				base = c + Vector3(cos(angle), 0.0, sin(angle)) * r * 0.5
			elif type != "start" and type != "arrival":
				base = c + Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
			var spots: Array[Vector3] = []
			match type:
				"grove":
					var turn := rng.randf() * TAU
					var reach := r * (0.42 if type_index == 0 else 0.22)
					if type_index == 0:
						spots.append(base)
					for spot_index in 4:
						var angle := turn + TAU * float(spot_index) / 4.0
						spots.append(base + Vector3(cos(angle), 0.0, sin(angle)) * reach)
				"cocoon":
					var angle := rng.randf() * TAU
					var reach := r * (0.24 if type_index == 0 else 0.14)
					spots.append(base + Vector3(cos(angle), 0.0, sin(angle)) * reach)
					spots.append(base - Vector3(cos(angle), 0.0, sin(angle)) * reach)
				"landmark":
					spots.append(base)
					landmarks.append({"type": rng.randi() % LANDMARK_KINDS, "center": base, "yaw": rng.randf() * TAU, "node": index})
				_:
					spots.append(base)
			slots[type] = spots
		node.slots = slots
		# Cover stones: none on start/arrival clearings, pillars in the boss arena.
		var count := 0
		if types.has("boss"):
			count = 3
		elif not (types.has("start") or types.has("arrival")):
			count = rng.randi_range(0, 2)
		var placed := 0
		for attempt in 24:
			if placed >= count:
				break
			var angle := rng.randf() * TAU
			var distance := r * rng.randf_range(0.5, 0.72) if not types.has("boss") else r * 0.55
			var stone := c + Vector3(cos(angle), 0.0, sin(angle)) * distance
			var radius := STONE_RADIUS * rng.randf_range(0.9, 1.15)
			if _stone_fits(stone, radius, slots, mouths, c):
				stones.append(Vector4(stone.x, 0.0, stone.z, radius))
				placed += 1


func _stone_fits(stone: Vector3, radius: float, slots: Dictionary, mouths: Array[float], c: Vector3) -> bool:
	var angle := atan2(stone.z - c.z, stone.x - c.x)
	for mouth in mouths:
		if absf(angle_difference(angle, mouth)) < 0.45:
			return false
	for type in slots:
		for spot in slots[type]:
			if Vector2(spot.x - stone.x, spot.z - stone.z).length() < radius + 7.5:
				return false
	for mark in landmarks:
		var mark_center: Vector3 = mark.center
		if Vector2(mark_center.x - stone.x, mark_center.z - stone.z).length() < radius + 9.0:
			return false
	for other in stones:
		if Vector2(other.x - stone.x, other.z - stone.z).length() < radius + other.w + 4.0:
			return false
	# Wall distance of the clearing shape alone (the SDF is baked afterwards).
	return _clearing_value(nodes[_nearest_node(stone)], stone.x, stone.z) >= radius + 4.0


func _nearest_node(point: Vector3) -> int:
	var best := 0
	var best_d := INF
	for index in nodes.size():
		var d := point.distance_to(nodes[index].center) - float(nodes[index].radius)
		if d < best_d:
			best_d = d
			best = index
	return best


# Eruption sources (Glutsumpf): points on the paths every ~10 m and a few on
# every clearing away from its POI slots; kind 1 (channel point).
func _eruptions() -> void:
	eruption_points.clear()
	for edge in edges:
		var points: PackedVector3Array = edge.points
		var node_a: Dictionary = nodes[edge.a]
		var node_b: Dictionary = nodes[edge.b]
		for index in range(2, points.size() - 2, 3):
			var point := points[index]
			if point.distance_to(node_a.center) < float(node_a.radius) or point.distance_to(node_b.center) < float(node_b.radius):
				continue
			eruption_points.append(Vector4(point.x, 0.0, point.z, 1.0))
	for node in nodes:
		var c: Vector3 = node.center
		for index in 3:
			var angle := float(index) * TAU / 3.0 + float(node.phase.x)
			var point := c + Vector3(cos(angle), 0.0, sin(angle)) * float(node.radius) * 0.62
			if sample(point.x, point.z) > 2.0:
				eruption_points.append(Vector4(point.x, 0.0, point.z, 1.0))


# --- SDF ---------------------------------------------------------------------------

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


func _bake_sdf() -> void:
	grid = ceili(bounds.size.x / NAV)
	grid_origin = bounds.position
	sdf = PackedFloat32Array()
	sdf.resize(grid * grid)
	sdf.fill(-SDF_MARGIN)
	var values := sdf
	sdf = PackedFloat32Array()
	for node in nodes:
		var c: Vector3 = node.center
		var reach := float(node.radius) * 1.2 + SDF_MARGIN
		var lo := Vector2i(maxi(0, floori((c.x - reach - grid_origin.x) / NAV)), maxi(0, floori((c.z - reach - grid_origin.y) / NAV)))
		var hi := Vector2i(mini(grid - 1, floori((c.x + reach - grid_origin.x) / NAV)), mini(grid - 1, floori((c.z + reach - grid_origin.y) / NAV)))
		for iz in range(lo.y, hi.y + 1):
			var z := grid_origin.y + (float(iz) + 0.5) * NAV
			for ix in range(lo.x, hi.x + 1):
				var x := grid_origin.x + (float(ix) + 0.5) * NAV
				var value := _clearing_value(node, x, z)
				var cell := iz * grid + ix
				if value > values[cell]:
					values[cell] = value
	for edge in edges:
		var points: PackedVector3Array = edge.points
		var halves: PackedFloat32Array = edge.half
		# Chords over two samples (6 m): the bend is gentle, the error tiny.
		for index in range(0, points.size() - 1, 2):
			var next := mini(index + 2, points.size() - 1)
			var a := points[index]
			var b := points[next]
			var ha := minf(halves[index], halves[(index + next) / 2])
			var hb := minf(halves[next], halves[(index + next) / 2])
			var reach := maxf(ha, hb) + SDF_MARGIN
			var lo := Vector2i(maxi(0, floori((minf(a.x, b.x) - reach - grid_origin.x) / NAV)), maxi(0, floori((minf(a.z, b.z) - reach - grid_origin.y) / NAV)))
			var hi := Vector2i(mini(grid - 1, floori((maxf(a.x, b.x) + reach - grid_origin.x) / NAV)), mini(grid - 1, floori((maxf(a.z, b.z) + reach - grid_origin.y) / NAV)))
			var abx := b.x - a.x
			var abz := b.z - a.z
			var ab2 := maxf(abx * abx + abz * abz, 0.000001)
			for iz in range(lo.y, hi.y + 1):
				var z := grid_origin.y + (float(iz) + 0.5) * NAV
				for ix in range(lo.x, hi.x + 1):
					var x := grid_origin.x + (float(ix) + 0.5) * NAV
					var t := clampf(((x - a.x) * abx + (z - a.z) * abz) / ab2, 0.0, 1.0)
					var px := a.x + abx * t - x
					var pz := a.z + abz * t - z
					var value := ha + (hb - ha) * t - sqrt(px * px + pz * pz)
					var cell := iz * grid + ix
					if value > values[cell]:
						values[cell] = value
	# The map edge is a wall too.
	for iz in grid:
		var z := grid_origin.y + (float(iz) + 0.5) * NAV
		var dz := minf(z - playable.position.y, playable.end.y - z)
		for ix in grid:
			var x := grid_origin.x + (float(ix) + 0.5) * NAV
			var inside := minf(minf(x - playable.position.x, playable.end.x - x), dz)
			var cell := iz * grid + ix
			if inside < values[cell]:
				values[cell] = inside
	sdf = values


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


## Index of the clearing containing a point (inside its wavy rim), or -1.
func clearing_at(point: Vector3) -> int:
	for index in nodes.size():
		if _clearing_value(nodes[index], point.x, point.z) >= 0.0:
			return index
	return -1


## Path index and position (0..1) nearest to a point, [-1, 0] if none.
func path_at(point: Vector3) -> Array:
	var best := -1
	var best_t := 0.0
	var best_d := INF
	var flat := _flat(point)
	for index in edges.size():
		var points: PackedVector3Array = edges[index].points
		for step in points.size() - 1:
			var d := _segment_distance(flat, _flat(points[step]), _flat(points[step + 1]))
			if d < best_d:
				best_d = d
				best = index
				best_t = (float(step) + 0.5) / float(points.size() - 1)
	return [best, best_t]


## POI positions of one type over the whole map.
func slots(type: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node in nodes:
		if node.slots.has(type):
			for spot in node.slots[type]:
				result.append(spot)
	return result


## Checks used by tests: number of loops, bridges, the smallest wall between
## unrelated paths, degree range.
func stats() -> Dictionary:
	var degrees: Array[int] = []
	for index in nodes.size():
		degrees.append(_degree(index))
	var narrow := 0
	for edge in edges:
		if edge.kind == "narrow":
			narrow += 1
	return {"clearings": nodes.size(), "paths": edges.size(), "narrow": narrow, "loops": _loops(), "bridges": _bridges().size(), "hub_degree": _degree(hub), "min_degree": degrees.min(), "attempts": attempts, "msec": build_msec}
