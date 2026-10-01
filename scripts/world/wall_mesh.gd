extends RefCounted

# Stage 34: continuous extruded walls from a signed wall field (the water idea
# of stage 29 applied to walls). arena_border.gd samples the smoothed wall
# field of one chunk on a regular grid; this builder runs marching squares over
# it and emits one indexed mesh:
#   - a side skirt from the contour (y = 0, the collision edge) up to the top,
#     leaning inwards by `inset`, normals from the field gradient (smooth);
#   - a top cap over the inside at the wall height (per vertex: kind heights,
#     a soft dome towards the inside, lower on rims with open ground to the north
#     so the camera sees over them); rows of deep cells merge into one quad;
# plus a second mesh: the soft contact shadow strip on the ground outside the
# contour. Vertex data for shaders/wall.gdshader:
#   COLOR.rgb  kind weights (rock, hedge, masonry), unnormalised
#   UV.x       depth inside the wall (m, 0 on the contour)
#   UV.y       part: side 0..1 (foot..top), cap 2
#   UV2.x      depth beyond the map edge front line (m, 0 inside the map)
#
# Sample grid: (n + 3)^2 values, sample (a, b) at `origin` + (a - 1, b - 1) *
# step (one margin sample on every side for the gradient); the cells between
# samples 1 .. n + 1 are meshed. Vertices are shared: one cap vertex per inside
# sample, one set (cap, foot, side top, shadow foot, shadow outer) per contour
# crossing. Winding: clockwise front faces (Godot).

## Samples at least this deep inside (m) have a flat top: cells of four such
## corners merge into one quad per row run.
const DEEP := 3.0

## Heights (m) per kind slot, dome (m extra towards the inside) per slot.
var heights := Vector3(2.0, 1.75, 1.6)
var domes := Vector3(0.25, 0.35, 0.0)
## Share of the height a rim loses when open ground lies to its north.
var camera_low := 0.3
## The top edge sits this far inside the foot (slightly slanted sides).
var inset := 0.22
## Contact shadow: width (m), strength at the foot and colour.
var shadow_width := 1.3
var shadow_alpha := 0.55
var shadow_color := Color(0.05, 0.07, 0.04)
var shadow_y := 0.014
## When set, every foot vertex (local) and its outward normal are appended here.
var contour := PackedVector2Array()
var contour_normals := PackedVector2Array()
var record_contour := false

# Mesh arrays (reset per build).
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _idx := PackedInt32Array()
var _sv := PackedVector3Array()
var _sc := PackedColorArray()
var _sidx := PackedInt32Array()
# Per-sample inputs and caches.
var _f := PackedFloat32Array()
var _w := PackedColorArray()
var _e := PackedFloat32Array()
var _g := PackedVector2Array()
var _g_ok := PackedByteArray()
var _cap_at := PackedInt32Array()     # cap vertex per sample (-1 = none yet)
var _cross_at := PackedInt32Array()   # grid edge id -> first vertex of its crossing
var _shadow_at := PackedInt32Array()  # grid edge id -> its shadow foot vertex
var _size := 0
var _step := 1.0
var _origin := Vector2.ZERO


## Builds [wall mesh or null, shadow mesh or null] from the sampled field.
## `f` wall field (+ open, - inside), `w` kind weights, `e` edge depth.
func build(f: PackedFloat32Array, w: PackedColorArray, e: PackedFloat32Array, n: int, step: float, origin: Vector2) -> Array:
	_f = f
	_w = w
	_e = e
	_size = n + 3
	_step = step
	_origin = origin
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_uv = PackedVector2Array()
	_uv2 = PackedVector2Array()
	_idx = PackedInt32Array()
	_sv = PackedVector3Array()
	_sc = PackedColorArray()
	_sidx = PackedInt32Array()
	var size := _size
	var count := size * size
	_cross_at = PackedInt32Array()
	_cross_at.resize(count * 2)
	_cross_at.fill(-1)
	_shadow_at = PackedInt32Array()
	_shadow_at.resize(count * 2)
	_cap_at = PackedInt32Array()
	_cap_at.resize(count)
	_cap_at.fill(-1)
	_g = PackedVector2Array()
	_g.resize(count)
	_g_ok = PackedByteArray()
	_g_ok.resize(count)
	# Inside span per sample row (cells outside every span are open).
	var lows := PackedInt32Array()
	var highs := PackedInt32Array()
	lows.resize(size)
	highs.resize(size)
	for b in size:
		var low := size
		var high := -1
		var row := b * size
		for a in size:
			if f[row + a] < 0.0:
				if a < low:
					low = a
				high = a
		lows[b] = low
		highs[b] = high
	for b in range(1, n + 1):
		var first := maxi(1, mini(lows[b], lows[b + 1]) - 1)
		var last := mini(n, maxi(highs[b], highs[b + 1]))
		if last < first:
			continue
		var run := -1   # first cell of the current run of deep full cells
		for a in range(first, last + 2):
			var i0 := b * size + a
			var i1 := i0 + 1
			var i2 := i0 + size + 1
			var i3 := i0 + size
			# Deep inside (every corner DEEP m in): one merged quad per row run.
			if a <= last and f[i0] <= -DEEP and f[i1] <= -DEEP and f[i2] <= -DEEP and f[i3] <= -DEEP:
				if run < 0:
					run = i0
				continue
			if run >= 0:
				var r0 := _cap_sample(run)
				var r3 := _cap_sample(run + size)
				var r1 := _cap_sample(i0)
				var r2 := _cap_sample(i3)
				_idx.append_array(PackedInt32Array([r0, r1, r2, r0, r2, r3]))
				run = -1
			if a > last:
				break
			var in0 := f[i0] < 0.0
			var in1 := f[i1] < 0.0
			var in2 := f[i2] < 0.0
			var in3 := f[i3] < 0.0
			if in0 and in1 and in2 and in3:
				var c0 := _cap_sample(i0)
				var c1 := _cap_sample(i1)
				var c2 := _cap_sample(i2)
				var c3 := _cap_sample(i3)
				_idx.append_array(PackedInt32Array([c0, c1, c2, c0, c2, c3]))
			elif in0 or in1 or in2 or in3:
				_mixed_cell(i0, i1, i2, i3, in0, in1, in2, in3)
	var result: Array = [null, null]
	if not _idx.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v
		arrays[Mesh.ARRAY_NORMAL] = _n
		arrays[Mesh.ARRAY_COLOR] = _c
		arrays[Mesh.ARRAY_TEX_UV] = _uv
		arrays[Mesh.ARRAY_TEX_UV2] = _uv2
		arrays[Mesh.ARRAY_INDEX] = _idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result[0] = mesh
	if not _sidx.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _sv
		var normals := PackedVector3Array()
		normals.resize(_sv.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = _sc
		arrays[Mesh.ARRAY_INDEX] = _sidx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result[1] = mesh
	return result


# Outward unit gradient of a sample (central differences, one-sided at the
# rim), computed on demand.
func _gradient(i: int) -> Vector2:
	if _g_ok[i] == 1:
		return _g[i]
	var size := _size
	var a := i % size
	var b := i / size
	var ax0 := maxi(a - 1, 0)
	var ax1 := mini(a + 1, size - 1)
	var bz0 := maxi(b - 1, 0)
	var bz1 := mini(b + 1, size - 1)
	var g := Vector2((_f[b * size + ax1] - _f[b * size + ax0]) / float(ax1 - ax0), (_f[bz1 * size + a] - _f[bz0 * size + a]) / float(bz1 - bz0))
	g = g.normalized() if g.length_squared() > 0.000001 else Vector2(0.0, 1.0)
	_g[i] = g
	_g_ok[i] = 1
	return g


func _height(w: Color, depth: float, g: Vector2) -> float:
	var total := w.r + w.g + w.b
	if total < 0.0001:
		w = Color(1.0, 0.0, 0.0)
		total = 1.0
	var base := (w.r * heights.x + w.g * heights.y + w.b * heights.z) / total
	var dome := (w.r * domes.x + w.g * domes.y + w.b * domes.z) / total
	base += dome * smoothstep(0.0, 2.5, depth)
	if depth >= 3.0 or g.y >= -0.15:
		return base
	var north := clampf(-g.y * 1.3 - 0.2, 0.0, 1.0)
	return base * (1.0 - camera_low * north * (1.0 - smoothstep(0.8, 3.0, depth)))


func _cap_sample(i: int) -> int:
	var index := _cap_at[i]
	if index >= 0:
		return index
	var depth := maxf(-_f[i], 0.0)
	var size := _size
	var p := _origin + Vector2(float(i % size - 1), float(i / size - 1)) * _step
	var g := Vector2(0.0, 1.0)
	if depth < DEEP:
		g = _gradient(i)
		if depth < inset:
			p -= g * (inset - depth)
	var w := _w[i]
	index = _v.size()
	_v.append(Vector3(p.x, _height(w, depth, g), p.y))
	_n.append(Vector3.UP)
	_c.append(w)
	_uv.append(Vector2(depth, 2.0))
	_uv2.append(Vector2(_e[i], 0.0))
	_cap_at[i] = index
	return index


# The contour crossing on the grid edge between samples i and j, shared by both
# cells; returns the edge id. Its vertices: _cross_at[id] (cap), + 1 (foot),
# + 2 (side top); shadow strip _shadow_at[id] (foot) and + 1 (outer).
func _crossing(i: int, j: int) -> int:
	if j < i:
		var swap := i
		i = j
		j = swap
	var id := i * 2 + (0 if j == i + 1 else 1)
	if _cross_at[id] >= 0:
		return id
	var size := _size
	var fi := _f[i]
	var t := fi / (fi - _f[j])
	var pi := _origin + Vector2(float(i % size - 1), float(i / size - 1)) * _step
	var pj := _origin + Vector2(float(j % size - 1), float(j / size - 1)) * _step
	var p := pi.lerp(pj, t)
	var gi := _gradient(i)
	var g := gi.lerp(_gradient(j), t)
	g = g.normalized() if g.length_squared() > 0.000001 else gi
	var w := _w[i].lerp(_w[j], t)
	var e := lerpf(_e[i], _e[j], t)
	var height := _height(w, 0.0, g)
	var top := Vector3(p.x - g.x * inset, height, p.y - g.y * inset)
	# Slightly slanted side: the normal leans up by the inset over the height.
	var side := Vector3(g.x, inset / maxf(height, 0.5), g.y).normalized()
	var index := _v.size()
	_v.append_array(PackedVector3Array([top, Vector3(p.x, 0.0, p.y), top]))
	_n.append_array(PackedVector3Array([Vector3.UP, side, side]))
	_c.append_array(PackedColorArray([w, w, w]))
	_uv.append_array(PackedVector2Array([Vector2(0.0, 2.0), Vector2(0.0, 0.0), Vector2(0.0, 1.0)]))
	var edge := Vector2(e, 0.0)
	_uv2.append_array(PackedVector2Array([edge, edge, edge]))
	_shadow_at[id] = _sv.size()
	_sv.append_array(PackedVector3Array([Vector3(p.x, shadow_y, p.y), Vector3(p.x + g.x * shadow_width, shadow_y, p.y + g.y * shadow_width)]))
	_sc.append_array(PackedColorArray([Color(shadow_color, shadow_alpha), Color(shadow_color, 0.0)]))
	if record_contour:
		contour.append(p)
		contour_normals.append(g)
	_cross_at[id] = index
	return id


# One cell with the contour through it: the inside polygon (clockwise, corners
# and crossings) becomes cap triangles, every chord exit -> entry a skirt quad
# and a shadow quad.
func _mixed_cell(i0: int, i1: int, i2: int, i3: int, in0: bool, in1: bool, in2: bool, in3: bool) -> void:
	var ids := PackedInt32Array([i0, i1, i2, i3])
	var inside := [in0, in1, in2, in3]
	# Saddle with the middle outside: two separate corners.
	if in0 == in2 and in1 == in3 and in0 != in1 and (_f[i0] + _f[i1] + _f[i2] + _f[i3]) >= 0.0:
		for k in 4:
			if not inside[k]:
				continue
			var here: int = ids[k]
			var exit := _crossing(here, ids[(k + 1) % 4])
			var entry := _crossing(ids[(k + 3) % 4], here)
			_idx.append_array(PackedInt32Array([_cap_sample(here), _cross_at[exit], _cross_at[entry]]))
			_skirt(exit, entry)
		return
	var caps := PackedInt32Array()
	var pending := -1       # exit waiting for its entry
	var first_entry := -1
	for k in 4:
		var here: int = ids[k]
		var here_in: bool = inside[k]
		var next_in: bool = inside[(k + 1) % 4]
		if here_in:
			caps.append(_cap_sample(here))
		if here_in != next_in:
			var point := _crossing(here, ids[(k + 1) % 4])
			caps.append(_cross_at[point])
			if here_in:
				pending = point
			elif pending >= 0:
				_skirt(pending, point)
				pending = -1
			else:
				first_entry = point
	# The walk started outside: the last exit pairs with the first entry.
	if pending >= 0 and first_entry >= 0:
		_skirt(pending, first_entry)
	for k in range(1, caps.size() - 1):
		_idx.append_array(PackedInt32Array([caps[0], caps[k], caps[k + 1]]))


# Side quad from the foot chord exit -> entry up to the top (facing outwards)
# and the contact shadow quad in front of it.
func _skirt(exit_id: int, entry_id: int) -> void:
	if exit_id == entry_id:
		return
	var exit := _cross_at[exit_id]
	var entry := _cross_at[entry_id]
	_idx.append_array(PackedInt32Array([exit + 1, entry + 1, entry + 2, exit + 1, entry + 2, exit + 2]))
	var s1 := _shadow_at[exit_id]
	var s2 := _shadow_at[entry_id]
	_sidx.append_array(PackedInt32Array([s1, s1 + 1, s2 + 1, s1, s2 + 1, s2]))
