extends Node

# Stage 4 Teil A: the journey through three worlds of a run (biomes.gd ORDER:
# Verdant Maw -> Dürrschlund -> Glutsumpf) and the victory.
#   - the boss of a world falls (pressure.boss_defeated): a portal opens at the
#     death spot (nearest open ground), banner PORTAL OFFEN, edge arrow while it
#     is off-screen (pressure.portal_at); battle.portal_opened(at)
#   - the hero stands in it PORTAL_HOLD s: fade out, the next world is built
#     (new seed, next biome, hero on a safe start point), enemies, gems, gold
#     and cocoons on the ground are gone, build / health / level / gold stay,
#     the run clock goes on; the world's own timeline starts (pressure,
#     director), enemies get the world's health / damage / density / tint;
#     fade in; battle.world_changed(index, biome)
#   - nobody enters: the Endwelle comes PORTAL_GRACE s after the boss (pressure)
#   - the boss of the last world falls: no portal, all enemies vanish, the run
#     is won (run.win(): the result screen shows SIEG!); battle.run_won
# battle.gd creates this node after pressure.gd, calls step() in tick() (true =
# a transition holds the world) and rewind() at the start of restart().

const PT := preload("res://scripts/enemies/pressure_tuning.gd")
const BIOMES := preload("res://scripts/world/biomes.gd")
const PORTAL := preload("res://scripts/world/portal.gd")

enum Phase { NONE, OUT, IN }
const PORTAL_OFFSET := 6.0

var battle: Node
## Biome ids of the run's worlds (world 0 = the map main.gd started with).
var sequence: Array[String] = []
var first_seed := 4242
var portal: Node3D
var phase := Phase.NONE
## Black screen 0..1 (hud.gd draws it).
var fade := 0.0
## PORTAL OFFEN follows the SIEG! banner of the boss after this many seconds.
var banner_delay := -1.0
## Log for tests: {what, world, t}.
var events: Array[Dictionary] = []


func setup(owner_battle: Node) -> void:
	battle = owner_battle
	battle.pressure.boss_defeated.connect(_on_boss_defeated)


func index() -> int:
	return int(battle.world_index)


func busy() -> bool:
	return phase != Phase.NONE


func _ensure_sequence() -> void:
	if not sequence.is_empty():
		return
	var host := battle.get_parent()
	var start := String(host.get("biome_id")) if host != null and host.get("biome_id") != null else BIOMES.DEFAULT
	if host != null and host.get("world_seed") != null:
		first_seed = int(host.world_seed)
	sequence.append(start if BIOMES.has(start) else BIOMES.DEFAULT)
	for id in BIOMES.ORDER:
		if sequence.size() >= PT.WORLD_COUNT:
			break
		if not sequence.has(String(id)):
			sequence.append(String(id))


func biome_of(world: int) -> String:
	_ensure_sequence()
	return sequence[clampi(world, 0, sequence.size() - 1)]


## Called by battle.tick() after the pause gate. True while a transition holds
## the world (nothing else steps then).
func step(delta: float) -> bool:
	_ensure_sequence()
	match phase:
		Phase.OUT:
			fade = minf(1.0, fade + delta / PT.FADE_OUT)
			if fade >= 1.0:
				travel()
				phase = Phase.IN
			return true
		Phase.IN:
			fade = maxf(0.0, fade - delta / PT.FADE_IN)
			if fade <= 0.0:
				phase = Phase.NONE
			return phase != Phase.NONE
	if banner_delay >= 0.0:
		banner_delay -= delta
		if banner_delay < 0.0 and portal != null:
			battle.pressure._banner("PORTAL OFFEN", "info")
	if portal != null and is_instance_valid(portal) and not battle.run.dead:
		if portal.step(delta, battle.hero.position):
			enter_portal()
	return false


## Starts the fade into the next world (the portal was entered).
func enter_portal() -> void:
	if phase != Phase.NONE:
		return
	phase = Phase.OUT
	fade = 0.0
	_log("enter")
	if battle.get("controls") != null:
		battle.controls.clear_pointers()


func _on_boss_defeated(at: Vector3) -> void:
	if battle.run.dead:
		return
	if battle.pressure.final_world:
		win(at)
	else:
		open_portal(at)


## Portal at the boss's death spot `at`: PORTAL_OFFSET behind it (seen from the
## hero), so the boss cocoon and its gems stay outside the portal ring; then
## the nearest open ground. Returns it.
func open_portal(at: Vector3) -> Node3D:
	_free_portal()
	_ensure_sequence()
	var away := Vector3(at.x - battle.hero.position.x, 0.0, at.z - battle.hero.position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var spot := Vector3(at.x, 0.0, at.z) + away * PORTAL_OFFSET
	var arena: Node3D = battle.arena
	if arena != null and arena.has_method("safe_spawn"):
		var fallback: Vector3 = arena.safe_spawn(spot, PT.PORTAL_RADIUS + 0.4)
		if fallback.is_finite():
			spot = Vector3(fallback.x, 0.0, fallback.z)
		# First open spot around the death spot that keeps clear of cocoons.
		for turn in [0.0, 0.8, -0.8, 1.6, -1.6, PI]:
			var candidate: Vector3 = arena.safe_spawn(Vector3(at.x, 0.0, at.z) + away.rotated(Vector3.UP, turn) * PORTAL_OFFSET, PT.PORTAL_RADIUS + 0.4)
			if candidate.is_finite() and _clear_of_cocoons(candidate):
				spot = Vector3(candidate.x, 0.0, candidate.z)
				break
	portal = PORTAL.new()
	portal.name = "Portal"
	portal.setup(biome_of(index() + 1))
	portal.position = spot
	var host: Node = battle.get_parent() if battle.get_parent() != null else battle
	host.add_child(portal)
	battle.pressure.portal_at = spot
	banner_delay = 1.4
	var effects: Node3D = battle.effects
	if effects != null and is_instance_valid(effects):
		effects.ring(spot, Color(1.0, 0.95, 0.7, 0.9), 0.7, PT.PORTAL_RADIUS + 3.0, 0.9)
		effects.ring(spot, Color(0.5, 0.9, 1.0, 0.8), 0.5, PT.PORTAL_RADIUS + 1.2, 1.2)
	_log("portal")
	battle.portal_opened.emit(spot)
	return portal


## Builds the next world now (the screen is black).
func travel() -> void:
	_ensure_sequence()
	var next := mini(index() + 1, PT.WORLD_COUNT - 1)
	var biome := biome_of(next)
	var seed_value := first_seed + 7919 * next + 104729 * int(battle.run.runs)
	_free_portal()
	var host := battle.get_parent()
	if host != null and host.has_method("start_world"):
		host.start_world(seed_value, biome)
	var hero: Node3D = battle.hero
	if hero.get("velocity") is Vector3:
		hero.velocity = Vector3.ZERO
	if hero.get("invulnerable") != null:
		hero.invulnerable = maxf(float(hero.invulnerable), 1.0)
	battle.horde.clear()
	battle.effects.clear()
	battle.hud.clear()
	if battle.get("loot") != null:
		battle.loot.clear()
	if battle.get("chests") != null:
		battle.chests.reset()
	battle.world_index = next
	battle.director.reset(seed_value)
	battle.pressure.start_world(next, float(battle.run.elapsed))
	apply_scaling(next)
	battle.pressure._banner("WELT %d · %s" % [next + 1, String(BIOMES.get_data(biome).get("title", biome.to_upper()))], "info")
	_log("world")
	battle.world_changed.emit(next, biome)


## Health / damage / density / tint of world `world` on director and horde.
func apply_scaling(world: int) -> void:
	battle.director.set_world(world, float(battle.run.elapsed) if world > 0 else 0.0)
	battle.horde.damage_mult = float(PT.WORLD_DAMAGE[world])
	if battle.horde.has_method("set_world_tint"):
		battle.horde.set_world_tint(PT.WORLD_TINT[world])


## The last boss fell: all enemies vanish, the run is won.
func win(at: Vector3) -> void:
	_free_portal()
	var effects: Node3D = battle.effects
	var horde: Node3D = battle.horde
	if effects != null and is_instance_valid(effects):
		for i in mini(horde.count(), 40):
			effects.ring(horde.position_of(i), Color(1.0, 0.85, 0.4, 0.7), 0.4, 1.4, 0.4)
		effects.ring(at, Color(1.0, 0.85, 0.4, 0.95), 1.2, 9.0, 1.0)
	horde.clear()
	horde.release_ring()
	battle.pressure._banner("SIEG!", "loot")
	battle.run.win()
	battle.set("_ended", true)
	_log("won")
	battle.run_won.emit()


## New run (battle.restart): back to world 1 before the hero is placed.
func rewind() -> void:
	_ensure_sequence()
	_free_portal()
	phase = Phase.NONE
	fade = 0.0
	banner_delay = -1.0
	events.clear()
	if index() != 0:
		var host := battle.get_parent()
		if host != null and host.has_method("start_world"):
			host.start_world(first_seed, sequence[0])
	battle.world_index = 0
	apply_scaling(0)


func _clear_of_cocoons(spot: Vector3) -> bool:
	var chests: Node = battle.get("chests")
	if chests == null:
		return true
	for entry in chests.cocoons:
		if Vector2(entry.at.x - spot.x, entry.at.z - spot.z).length() < PT.PORTAL_RADIUS + 3.4:
			return false
	return true


func _free_portal() -> void:
	if portal != null and is_instance_valid(portal):
		portal.queue_free()
	portal = null
	if battle != null and battle.pressure != null:
		battle.pressure.portal_at = Vector3.INF


func _log(what: String) -> void:
	events.append({"what": what, "world": index(), "t": float(battle.run.elapsed)})
