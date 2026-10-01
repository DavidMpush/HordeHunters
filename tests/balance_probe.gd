extends SceneTree

# Balance probe (not in the suite): a bot plays the real scene headless.
#   -- idle   stands still (must die quickly)
#   -- kite   flees from the nearest enemy, dashes when one is close; with no
#             enemy near it walks to the nearest XP gem (stage 2) and takes
#             the first card of every level-up / cocoon choice
#   -- smart  realistic kiting (stage 2 Teil B): flees from the weighted threat,
#             steers round walls and the map edge, leaves shown danger zones
#             (boss attacks, champion stomp, Brocken arcs), dashes out of
#             wind-ups, runs for the gap of an encircle ring, picks gems when
#             nothing is close
#   add "noup" to skip every level-up / cocoon choice (no upgrades),
#   "seed=N" for another director/pressure seed, "limit=S" for the time limit
#   (default 360 s; smart 600 s), "hero=boxer" for Brine (stage 3).
# Prints survival time, kills, hits, pressure events.
# Godot --headless --audio-driver Dummy --script res://tests/balance_probe.gd -- smart noup

const T := preload("res://scripts/core/tuning.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")

var battle: Node
var hero: Node3D
var horde: Node3D
var pressure: Node
var wander := 0.0
var _last_dir := Vector3.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	battle = main.get_node("Battle")
	battle.auto = false
	var mode := "idle"
	var upgrades := true
	var seed_value := 0
	var limit := -1.0
	var hero_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "noup":
			upgrades = false
		elif arg.begins_with("seed="):
			seed_value = int(arg.substr(5))
		elif arg.begins_with("hero="):
			hero_id = arg.substr(5)
		elif arg.begins_with("limit="):
			limit = float(arg.substr(6))
		elif arg != "verbose":
			mode = arg
	if limit < 0.0:
		limit = 600.0 if mode == "smart" else 360.0
	# Stage 3: "hero=boxer" / "hero=brann" (a fresh run of that hero).
	if hero_id != "":
		battle.set_hero(hero_id)
	if seed_value != 0:
		battle.director.reset(seed_value)
		battle.pressure._rng.seed = seed_value
	hero = battle.hero
	horde = battle.horde
	pressure = battle.pressure
	# Hits by damage (8 Wichtel, 6 Renner, 22 Brocken, 26 champion, 22-28 boss).
	var by_damage := {}
	hero.hurt.connect(func(damage: float, _from: Vector3) -> void:
		var key := "%d@%d" % [int(damage), int(battle.run.elapsed)]
		by_damage[int(damage)] = int(by_damage.get(int(damage), 0)) + 1
		if OS.get_cmdline_user_args().has("verbose"):
			var close := 0
			for k in horde.count():
				if horde.position_of(k).distance_to(hero.position) < 2.5:
					close += 1
			var opens := []
			for k in 8:
				var dd := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * 0.5
				var moved: Vector3 = battle.arena.resolve_motion(hero.position, dd, T.HERO_RADIUS)
				opens.append(snappedf((moved - hero.position).length(), 0.01))
			print("  open ", opens, " is_open ", battle.arena.is_open(hero.position, T.HERO_RADIUS), " move ", battle.controls.movement_vector)
			print("  hit %s pos (%.1f, %.1f) vel %.1f close %d dash %s" % [key, hero.position.x, hero.position.z, Vector3(hero.velocity.x, 0, hero.velocity.z).length(), close, str(hero.dash_ready())]))
	var t := 0.0
	var dt := 1.0 / 30.0
	var angle := 0.0
	var max_alive := 0
	var levels: Array[int] = [0]
	var hits_by_minute := {}
	var last_hits := 0
	while t < limit and not battle.run.dead:
		var move := Vector2.ZERO
		if mode == "kite":
			# Run away from the nearest enemy, sideways a bit; dash when crowded.
			var i: int = battle.horde.nearest_index(hero.position, 6.0)
			if i >= 0:
				var away: Vector3 = (hero.position - battle.horde.position_of(i)).normalized()
				var side := Vector3(-away.z, 0, away.x)
				var dir := (away + side * 0.6).normalized()
				move = Vector2(dir.x, dir.z)
				if hero.position.distance_to(battle.horde.position_of(i)) < 2.0 and hero.dash_ready():
					hero.dash(dir)
			else:
				var gem: Vector3 = battle.loot.nearest_lying(hero.position, 14.0)
				if gem.is_finite():
					var to := Vector3(gem.x - hero.position.x, 0, gem.z - hero.position.z).normalized()
					move = Vector2(to.x, to.z)
				else:
					angle += dt * 0.4
					move = Vector2(cos(angle), sin(angle)) * 0.5
		elif mode == "smart":
			move = _kite_smart(dt)
		if battle.paused():
			if upgrades:
				battle.progression.choose(0)
			else:
				_skip_choice()
			if battle.run.level > levels.size():
				levels.append(int(t))
		battle.controls.movement_pointer = 7
		battle.controls.movement_vector = move
		battle.tick(dt)
		# Main syncs the arena (flow field focus, chunks) in its own _process,
		# which never runs in this frame-less loop: do it here.
		battle.arena.sync(hero.position)
		max_alive = maxi(max_alive, battle.horde.count())
		if hero.hits_taken > last_hits:
			var minute := int(battle.run.elapsed / 60.0)
			hits_by_minute[minute] = int(hits_by_minute.get(minute, 0)) + hero.hits_taken - last_hits
			last_hits = hero.hits_taken
		t += dt
		if int(t * 30.0) % 900 == 0:
			var nearest := INF
			var within := 0
			for k in battle.horde.count():
				var dd: float = battle.horde.position_of(k).distance_to(hero.position)
				nearest = minf(nearest, dd)
				if dd < 12.0:
					within += 1
			print("t=%d alive=%d near12=%d nearest=%.1f kills=%d hp=%.0f shots=%d level=%d gold=%d pos=(%.0f,%.0f)%s" % [int(t), battle.horde.count(), within, nearest, battle.run.kills, hero.health, battle.run.shots, battle.run.level, battle.run.gold_total,
				hero.position.x, hero.position.z, " boss=%.0f" % pressure.boss.health if pressure.boss_alive() else ""])
	var waves := []
	for w in pressure.events_of("spawn"):
		waves.append("%s@%d" % [String(w.kind).left(4), int(w.t)])
	var boss := "-"
	if not pressure.events_of("boss_defeated").is_empty():
		boss = "killed@%d" % int(pressure.events_of("boss_defeated")[0].t)
	elif pressure.boss_alive():
		boss = "alive (%.0f hp)" % pressure.boss.health
	print("PRESSURE waves %s elites %d killed %d boss %s" % [waves, pressure.events_of("elite").size(), pressure.events_of("elite_killed").size(), boss])
	print("hits per minute %s, by damage %s" % [str(hits_by_minute), str(by_damage)])
	print("LEVELS reached at s: %s" % str(levels))
	print("HERO %s weapons %s" % [hero.hero_id, str(battle.progress.weapons)])
	print("BOT %s%s survived %.1f s kills %d max_alive %d hits %d dmg %.0f" % [mode, "" if upgrades else " noup", battle.run.elapsed, battle.run.kills, max_alive, hero.hits_taken, hero.damage_taken])
	quit()


## Closes the open choice without taking a card (no upgrades).
func _skip_choice() -> void:
	var progression: Node = battle.progression
	progression.mode = ""
	progression.offers = []
	battle.run.pending_levels = 0
	progression.choice.close()


# Realistic kiting (what a decent player would do).
func _kite_smart(dt: float) -> Vector2:
	var at := Vector3(hero.position.x, 0.0, hero.position.z)
	var flee := Vector3.ZERO
	var dash_now := false
	var dash_dir := Vector3.ZERO
	var near := 0
	# Enemies: inverse-square push, wind-ups count triple.
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var off := at - p
		var d := off.length()
		if d > 9.0 or d < 0.001:
			continue
		var w := 1.0
		var kind: int = horde.kind_of(i)
		if kind == T.Kind.BROCKEN:
			w = 2.5 if horde.is_elite(i) else 1.8
		if horde.state_of(i) == horde.State.WINDUP:
			w *= 3.0
			var reach: float = (PT.ELITE_REACH if horde.is_elite(i) else horde.reach_of_kind(kind)) + T.HERO_RADIUS
			if d < reach + 0.3 and float(horde._timer[i]) < 0.22:
				dash_now = true
				dash_dir += off / d
		if d < 3.0:
			near += 1
		flee += off / (d * d) * w
	# Shown boss zones: get out radially.
	for zone in pressure.danger_zones():
		var c: Vector3 = zone.center
		var off := at - c
		var d := off.length()
		var r: float = float(zone.radius) + 0.8
		var inside := d < r
		if inside and float(zone.half) < PI and d > 0.01:
			inside = Vector3(zone.dir).dot(off / d) >= cos(float(zone.half)) - 0.15
		if inside:
			var out := off.normalized() if d > 0.01 else Vector3.RIGHT
			flee += out * 6.0
			if float(zone.left) < 0.35 and d < r - 0.6:
				dash_now = true
				dash_dir += out
	# Boss body: keep some distance anyway.
	if pressure.boss_alive():
		var off := at - Vector3(pressure.boss.position.x, 0.0, pressure.boss.position.z)
		var d := maxf(0.5, off.length())
		if d < 7.0:
			flee += off / (d * d) * 4.0
	# Encircle: head for the gap while inside the ring.
	if horde.ring_active and at.distance_to(horde.ring_center) < horde.ring_radius + 1.0:
		var gap := Vector3(cos(horde.ring_gap), 0.0, sin(horde.ring_gap))
		var exit: Vector3 = horde.ring_center + gap * (horde.ring_radius + 2.0)
		flee = flee.normalized() * 0.3 + (exit - at).normalized() * 2.0
	var dir := Vector3.ZERO
	if flee.length() > 0.05:
		dir = flee.normalized()
		# Sideways component: circle the crowd instead of running straight.
		dir = (dir + Vector3(-dir.z, 0, dir.x) * 0.35).normalized()
	else:
		var gem: Vector3 = battle.loot.nearest_lying(hero.position, 12.0) if battle.get("loot") != null else Vector3.INF
		if gem.is_finite():
			dir = Vector3(gem.x - at.x, 0, gem.z - at.z).normalized()
		else:
			wander += dt * 0.3
			dir = Vector3(cos(wander), 0.0, sin(wander)) * 0.6
	# Stay off the map edge.
	var arena: Node3D = battle.arena
	if arena.has_method("playable_rect"):
		var rect: Rect2 = arena.playable_rect()
		if rect.size.x > 0.0 and not rect.grow(-14.0).has_point(Vector2(at.x, at.z)):
			var center: Vector3 = arena.map_center()
			dir = (dir + (center - at).normalized() * 1.5).normalized()
	if dir.length() > 0.1 and flee.length() > 0.05:
		dir = _best_direction(at, dir)
	elif dir.length() > 0.1:
		dir = _open_direction(at, dir)
	if dash_now and hero.dash_ready():
		var dd := dash_dir.normalized() if dash_dir.length() > 0.01 else dir
		hero.dash(_open_direction(at, dd, 3.0))
	elif near >= 4 and hero.dash_ready() and dir.length() > 0.1:
		hero.dash(dir)
	return Vector2(dir.x, dir.z)


## Of 16 directions the one that best follows `wish`, is open for 2.5 m and
## has the fewest enemies ahead (a player sees walls and crowds).
func _best_direction(at: Vector3, wish: Vector3) -> Vector3:
	var arena: Node3D = battle.arena
	var best := wish
	var best_score := -INF
	for k in 16:
		var a := TAU * float(k) / 16.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var moved: Vector3 = arena.resolve_motion(at, d * 2.5, T.HERO_RADIUS) if arena.has_method("resolve_motion") else at + d * 2.5
		var open := (moved - at).length() / 2.5
		# A long probe can slide along a wall; the short one must go straight.
		if arena.has_method("resolve_motion"):
			var short: Vector3 = arena.resolve_motion(at, d * 0.6, T.HERO_RADIUS)
			open = minf(open, (short - at).dot(d) / 0.6)
		# Danger in this direction: enemies inside a cone, nearer ones count more.
		var crowd := 0.0
		for i in horde.count():
			var off: Vector3 = horde.position_of(i) - at
			off.y = 0.0
			var dist := off.length()
			if dist > 10.0 or dist < 0.01:
				continue
			var facing := d.dot(off / dist)
			if facing > 0.5:
				crowd += (facing - 0.5) * 2.0 / maxf(1.0, dist * 0.5)
		# Further along: is there room to keep running (walls, edge)?
		var far: Vector3 = arena.resolve_motion(at, d * 6.0, T.HERO_RADIUS) if arena.has_method("resolve_motion") else at + d * 6.0
		var room := (far - at).length() / 6.0
		var score := d.dot(wish) * 1.2 + open * 2.0 + room * 1.0 - crowd * 1.2 + d.dot(_last_dir) * 1.6
		if open < 0.6:
			score -= 100.0
		if score > best_score:
			best_score = score
			best = d
	_last_dir = best
	return best


## Turns `dir` until a short probe along it is not blocked by walls.
func _open_direction(at: Vector3, dir: Vector3, probe := 1.6) -> Vector3:
	var arena: Node3D = battle.arena
	if not arena.has_method("resolve_motion"):
		return dir
	var length := dir.length()
	var unit := dir / length
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var d := unit.rotated(Vector3.UP, turn)
		var moved: Vector3 = arena.resolve_motion(at, d * probe, T.HERO_RADIUS)
		if (moved - at).length() > probe * 0.7:
			return d * length
	return dir
