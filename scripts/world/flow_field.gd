extends RefCounted

# Stage 18b: one shared navigation field for every enemy. A grid of CELL m over
# the map (passable = open ground of the map layout), walking distances from
# the focus by Dijkstra with costs 2 (straight) / 3 (diagonal, never around a
# wall corner) on a four-bucket queue. The field is rebuilt continuously in
# small steps (cells per frame), so a frame never pays for a whole map;
# queries always read the last finished field.
#
#   direction(point)  walking direction towards the focus (blend of the four
#                     nearest cells, smooth across cell borders)
#   distance(point)   walking distance in metres (INF behind walls)
#   ring              cells at walking distance RING_NEAR..RING_FAR (spawn
#                     candidates for the flood: path mouths just out of view)

const UNREACHED := 1 << 29
const STRAIGHT := 2
const DIAGONAL := 3
const RING_NEAR := 24.0
const RING_FAR := 44.0
const OPEN_THRESHOLD := 1.0
# Neighbour directions in the order of _offsets (4 straight, 4 diagonal).
const DIRECTIONS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071), Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071)]

var cell := 4.0
## Wall distance a cell centre needs to be passable (big bodies need more).
var open_threshold := OPEN_THRESHOLD
var size := 0
var origin := Vector2.ZERO
var passable := PackedByteArray()
var open_cells := 0
# Finished field.
var dist := PackedInt32Array()
var ring := PackedInt32Array()
var source := Vector3.INF
var ready := false
var generation := 0
# Field in progress.
var _work := PackedInt32Array()
var _ring_work := PackedInt32Array()
var _work_source := Vector3.INF
var _q0 := PackedInt32Array()
var _q1 := PackedInt32Array()
var _q2 := PackedInt32Array()
var _q3 := PackedInt32Array()
var _heads := PackedInt32Array([0, 0, 0, 0])
var _level := 0
var _running := false
var _ring_lo := 0
var _ring_hi := 0
## Cells expanded by the last step() and in total for the last finished field.
var last_step_cells := 0
var field_cells := 0
var _count := 0
var _offsets := PackedInt32Array()


func _init(layout: RefCounted, cell_size: float, threshold := OPEN_THRESHOLD) -> void:
	cell = cell_size
	open_threshold = threshold
	var bounds: Rect2 = layout.bounds
	size = ceili(bounds.size.x / cell) + 2
	origin = bounds.position - Vector2(cell, cell)
	passable.resize(size * size)
	var quarter := cell * 0.25
	var same_grid: bool = is_equal_approx(cell, float(layout.NAV)) and int(layout.grid) == size - 2
	var values: PackedFloat32Array = layout.sdf
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			var best := 0.0
			if same_grid:
				# Cell centres are the wall grid's sample points.
				best = values[(z - 1) * (size - 2) + x - 1]
			else:
				var cx := origin.x + (float(x) + 0.5) * cell
				var cz := origin.y + (float(z) + 0.5) * cell
				best = layout.sample(cx, cz)
				if best < open_threshold:
					for offset in [Vector2(-quarter, -quarter), Vector2(quarter, -quarter), Vector2(-quarter, quarter), Vector2(quarter, quarter)]:
						best = maxf(best, layout.sample(cx + offset.x, cz + offset.y))
			if best >= open_threshold:
				passable[z * size + x] = 1
				open_cells += 1
	# Stage 18c: the layout's collision circles (landmarks, cover stones) are no
	# ground to route through either.
	var circles: Variant = layout.get("stones")
	if circles != null:
		for stone in circles:
			var reach: float = stone.w + open_threshold
			var lo := Vector2i(floori((stone.x - reach - origin.x) / cell), floori((stone.z - reach - origin.y) / cell))
			var hi := Vector2i(floori((stone.x + reach - origin.x) / cell), floori((stone.z + reach - origin.y) / cell))
			for z in range(maxi(1, lo.y), mini(size - 1, hi.y + 1)):
				for x in range(maxi(1, lo.x), mini(size - 1, hi.x + 1)):
					var cx := origin.x + (float(x) + 0.5) * cell
					var cz := origin.y + (float(z) + 0.5) * cell
					if Vector2(cx - stone.x, cz - stone.z).length() < reach and passable[z * size + x] == 1:
						passable[z * size + x] = 0
						open_cells -= 1
	_offsets = PackedInt32Array([1, -1, size, -size, size + 1, size - 1, -size + 1, -size - 1])
	dist.resize(size * size)
	dist.fill(UNREACHED)
	_work.resize(size * size)
	_ring_lo = roundi(RING_NEAR / cell * float(STRAIGHT))
	_ring_hi = roundi(RING_FAR / cell * float(STRAIGHT))


func index_of(point: Vector3) -> int:
	var x := floori((point.x - origin.x) / cell)
	var z := floori((point.z - origin.y) / cell)
	if x < 1 or z < 1 or x >= size - 1 or z >= size - 1:
		return -1
	return z * size + x


func cell_center(index: int) -> Vector3:
	return Vector3(origin.x + (float(index % size) + 0.5) * cell, 0.0, origin.y + (float(index / size) + 0.5) * cell)


func is_running() -> bool:
	return _running


## Starts a new field from `point` (the old one stays readable until done).
func begin(point: Vector3) -> void:
	var start := index_of(point)
	if start < 0:
		return
	if passable[start] == 0:
		# Standing against a wall: the nearest passable cell nearby is the source.
		var best := -1
		var best_d := INF
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var candidate := start + dz * size + dx
				if candidate > 0 and candidate < passable.size() and passable[candidate] == 1:
					var d := cell_center(candidate).distance_squared_to(point)
					if d < best_d:
						best_d = d
						best = candidate
		if best < 0:
			return
		start = best
	_work.fill(UNREACHED)
	_ring_work = PackedInt32Array()
	_q0 = PackedInt32Array()
	_q1 = PackedInt32Array()
	_q2 = PackedInt32Array()
	_q3 = PackedInt32Array()
	_heads = PackedInt32Array([0, 0, 0, 0])
	_work[start] = 0
	_q0.append(start)
	_level = 0
	_count = 0
	_work_source = point
	_running = true


## Expands up to `budget` cells; true once the field is finished (and swapped in).
func step(budget: int) -> bool:
	if not _running:
		return false
	# Locals (members are ~2x slower; arrays are moved out to avoid copies).
	var work := _work
	_work = PackedInt32Array()
	var open := passable
	var q0 := _q0
	var q1 := _q1
	var q2 := _q2
	var q3 := _q3
	_q0 = PackedInt32Array()
	_q1 = PackedInt32Array()
	_q2 = PackedInt32Array()
	_q3 = PackedInt32Array()
	var ring_work := _ring_work
	_ring_work = PackedInt32Array()
	var heads := _heads
	var level := _level
	var w := size
	var lo := _ring_lo
	var hi := _ring_hi
	var done := 0
	var finished := false
	var empty_levels := 0
	while done < budget:
		var bucket := level & 3
		var queue: PackedInt32Array = q0 if bucket == 0 else (q1 if bucket == 1 else (q2 if bucket == 2 else q3))
		var head := heads[bucket]
		if head >= queue.size():
			queue = PackedInt32Array()
			if bucket == 0:
				q0.clear()
			elif bucket == 1:
				q1.clear()
			elif bucket == 2:
				q2.clear()
			else:
				q3.clear()
			heads[bucket] = 0
			empty_levels += 1
			if empty_levels >= 4:
				finished = true
				break
			level += 1
			continue
		empty_levels = 0
		var here := queue[head]
		heads[bucket] = head + 1
		if work[here] != level:
			continue
		done += 1
		if level >= lo and level <= hi:
			ring_work.append(here)
		var straight := level + STRAIGHT
		var diagonal := level + DIAGONAL
		var e := here + 1
		var west := here - 1
		var s := here + w
		var n := here - w
		var open_e := open[e] == 1
		var open_w := open[west] == 1
		var open_s := open[s] == 1
		var open_n := open[n] == 1
		# Straight neighbours (cost 2 -> bucket level + 2).
		if open_e and straight < work[e]:
			work[e] = straight
			if (straight & 3) == 0: q0.append(e)
			elif (straight & 3) == 1: q1.append(e)
			elif (straight & 3) == 2: q2.append(e)
			else: q3.append(e)
		if open_w and straight < work[west]:
			work[west] = straight
			if (straight & 3) == 0: q0.append(west)
			elif (straight & 3) == 1: q1.append(west)
			elif (straight & 3) == 2: q2.append(west)
			else: q3.append(west)
		if open_s and straight < work[s]:
			work[s] = straight
			if (straight & 3) == 0: q0.append(s)
			elif (straight & 3) == 1: q1.append(s)
			elif (straight & 3) == 2: q2.append(s)
			else: q3.append(s)
		if open_n and straight < work[n]:
			work[n] = straight
			if (straight & 3) == 0: q0.append(n)
			elif (straight & 3) == 1: q1.append(n)
			elif (straight & 3) == 2: q2.append(n)
			else: q3.append(n)
		# Diagonals only between two open straight neighbours (no wall corners).
		var d := 0
		if open_e and open_s:
			d = s + 1
			if open[d] == 1 and diagonal < work[d]:
				work[d] = diagonal
				if (diagonal & 3) == 0: q0.append(d)
				elif (diagonal & 3) == 1: q1.append(d)
				elif (diagonal & 3) == 2: q2.append(d)
				else: q3.append(d)
		if open_w and open_s:
			d = s - 1
			if open[d] == 1 and diagonal < work[d]:
				work[d] = diagonal
				if (diagonal & 3) == 0: q0.append(d)
				elif (diagonal & 3) == 1: q1.append(d)
				elif (diagonal & 3) == 2: q2.append(d)
				else: q3.append(d)
		if open_e and open_n:
			d = n + 1
			if open[d] == 1 and diagonal < work[d]:
				work[d] = diagonal
				if (diagonal & 3) == 0: q0.append(d)
				elif (diagonal & 3) == 1: q1.append(d)
				elif (diagonal & 3) == 2: q2.append(d)
				else: q3.append(d)
		if open_w and open_n:
			d = n - 1
			if open[d] == 1 and diagonal < work[d]:
				work[d] = diagonal
				if (diagonal & 3) == 0: q0.append(d)
				elif (diagonal & 3) == 1: q1.append(d)
				elif (diagonal & 3) == 2: q2.append(d)
				else: q3.append(d)
	_count += done
	last_step_cells = done
	_level = level
	_heads = heads
	if finished:
		# Swap: the finished field becomes readable, the old buffer is reused.
		_work = dist
		dist = work
		ring = ring_work
		source = _work_source
		ready = true
		generation += 1
		field_cells = _count
		_running = false
		return true
	_work = work
	_q0 = q0
	_q1 = q1
	_q2 = q2
	_q3 = q3
	_ring_work = ring_work
	return false


## Walking distance to the source in metres (INF when unreachable / no field).
func distance(point: Vector3) -> float:
	if not ready:
		return INF
	var index := index_of(point)
	if index < 0:
		return INF
	var best := dist[index]
	if best >= UNREACHED:
		# A point at a wall may sit in a closed cell: the best open neighbour.
		for k in 8:
			var other := dist[index + _offsets[k]]
			if other < UNREACHED:
				best = mini(best, other + (STRAIGHT if k < 4 else DIAGONAL))
	if best >= UNREACHED:
		return INF
	return float(best) / float(STRAIGHT) * cell


# Downhill direction of one cell (x, z), ZERO if unreachable.
func _cell_direction(index: int) -> Vector2:
	var here := dist[index]
	if here >= UNREACHED:
		return Vector2.ZERO
	if here == 0:
		var to := Vector2(source.x, source.z) - Vector2(cell_center(index).x, cell_center(index).z)
		return to.normalized() if to.length_squared() > 0.01 else Vector2.ZERO
	var sum := Vector2.ZERO
	for k in 8:
		var other := dist[index + _offsets[k]]
		if other < here:
			sum += DIRECTIONS[k] * (float(here - other) / (2.0 if k < 4 else 3.0))
	return sum.normalized() if sum.length_squared() > 0.000001 else Vector2.ZERO


## Walking direction towards the source (bilinear over the four nearest cells).
func direction(point: Vector3) -> Vector3:
	if not ready:
		return Vector3.ZERO
	var fx := (point.x - origin.x) / cell - 0.5
	var fz := (point.z - origin.y) / cell - 0.5
	var ix := floori(fx)
	var iz := floori(fz)
	if ix < 1 or iz < 1 or ix >= size - 2 or iz >= size - 2:
		return Vector3.ZERO
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var base := iz * size + ix
	var sum := _cell_direction(base) * (1.0 - tx) * (1.0 - tz)
	sum += _cell_direction(base + 1) * tx * (1.0 - tz)
	sum += _cell_direction(base + size) * (1.0 - tx) * tz
	sum += _cell_direction(base + size + 1) * tx * tz
	if sum.length_squared() < 0.000001:
		var own := index_of(point)
		sum = _cell_direction(own) if own >= 0 else Vector2.ZERO
	if sum.length_squared() < 0.000001:
		return Vector3.ZERO
	sum = sum.normalized()
	return Vector3(sum.x, 0.0, sum.y)
