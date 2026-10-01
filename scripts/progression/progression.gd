extends Node

# Progression of a run (stage 2, Teil A): wires XP gems + gold (loot.gd),
# cocoons (chests.gd), the build (progress.gd), the 1-of-3 choice
# (ui/choice_screen.gd) and the run's XP/level/gold (core/run.gd).
# A child of Battle; battle.gd calls step() inside tick() and asks paused()
# (the choice pauses the run: no hero, enemies, director, effects, time).
#
#   kills      horde.enemy_killed -> XP gem by kind (+ rare gold)
#   pick-up    loot.step (magnet = MAGNET x hero.stat("magnet_mult")) ->
#              run.add_xp(x xp_mult) / run.add_gold(x gold_mult)
#   level-up   run.pending_levels > 0 -> level choice (stats + shotgun track)
#   cocoons    hold in the ring -> pay (map) -> burst -> chest choice
#   relics     thorns (Dornenweste) on hero.hurt, Jagdtrophäe heal on kills
# Public: choose(slot), reroll(), paused(), drop_xp/drop_gold/drop_chest,
# reset(). Hero stats: hero.build = progress (hero.stat(id)).

const PROGRESS := preload("res://scripts/progression/progress.gd")
const LOOT := preload("res://scripts/progression/loot.gd")
const CHESTS := preload("res://scripts/progression/chests.gd")
const CHOICE := preload("res://scripts/ui/choice_screen.gd")
const T := preload("res://scripts/core/tuning.gd")
const RUN := preload("res://scripts/core/run.gd")

## XP per kill by enemy kind (unknown kinds, e.g. elite/boss of Teil B: XP_OTHER).
const XP_BY_KIND := {T.Kind.WICHTEL: 4.0, T.Kind.RENNER: 4.0, T.Kind.BROCKEN: 20.0}
const XP_OTHER := 15.0
## Gold of normal enemies: chance and amount per kind.
const GOLD_CHANCE := {T.Kind.WICHTEL: 0.06, T.Kind.RENNER: 0.06, T.Kind.BROCKEN: 0.6}
const GOLD_AMOUNT := {T.Kind.WICHTEL: 1, T.Kind.RENNER: 1, T.Kind.BROCKEN: 3}
const TROPHY_KILLS := 25
const THORNS_REACH := 2.6

var battle: Node
var progress: RefCounted
var loot: Node3D
var chests: Node3D
var choice: Control
var mode := ""              # "" / "level" / "chest"
var offers: Array = []
var chest_kind := ""
var _trophy_count := 0
var _thorns: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
## Picks in this run (tests): number of choices taken.
var choices_taken := 0
## Bots and long tests: every choice takes its first card at once (no pause).
var auto_pick := false


func setup(battle_node: Node) -> void:
	battle = battle_node
	_rng.seed = 777
	progress = PROGRESS.new()
	loot = LOOT.new()
	loot.name = "Loot"
	loot.setup(battle.arena)
	add_child(loot)
	chests = CHESTS.new()
	chests.name = "Cocoons"
	chests.setup(battle.arena)
	chests.price_of = func() -> int: return progress.chest_price()
	chests.pay = _pay_chest
	add_child(chests)
	chests.burst.connect(_on_burst)
	choice = CHOICE.new()
	choice.name = "Choice"
	choice.progression = self
	battle.hud_layer.add_child(choice)
	battle.hero.set("build", progress)
	battle.horde.enemy_killed.connect(_on_enemy_killed)
	battle.hero.hurt.connect(_on_hero_hurt)
	_apply_hero_stats(false)


# A map cocoon is bought: gold off, the next one costs more.
func _pay_chest(price: int) -> bool:
	if not battle.run.spend_gold(price):
		return false
	progress.chests_bought += 1
	return true


func paused() -> bool:
	return mode != ""


## New run (battle.restart): build, loot, cocoons and the choice cleared.
func reset() -> void:
	progress.reset(20202 + int(battle.run.runs) * 7919)
	loot.clear()
	chests.reset()
	mode = ""
	offers = []
	choices_taken = 0
	_trophy_count = 0
	_thorns.clear()
	choice.close()
	_apply_hero_stats(false)
	battle.hero.health = battle.hero.max_health


func magnet_radius() -> float:
	return LOOT.MAGNET_RADIUS * progress.stat("magnet_mult")


## Called by battle.tick() while not paused (after the effects, before run.step).
func step(delta: float) -> void:
	var hero: Node3D = battle.hero
	var run: RefCounted = battle.run
	if not _thorns.is_empty():
		_strike_back()
	var got: Dictionary = loot.step(delta, hero.position, magnet_radius() if not run.dead else 0.0)
	if float(got.xp) > 0.0:
		run.add_xp(float(got.xp) * progress.stat("xp_mult"))
	if int(got.gold) > 0:
		run.add_gold(int(round(float(got.gold) * progress.stat("gold_mult"))))
	if int(got.items) > 0 and battle.sfx != null:
		battle.sfx.play("ui", 1.6 + 0.2 * randf())
	chests.step(delta, hero.position, not run.dead)
	if mode == "" and not run.dead and run.pending_levels > 0:
		open_level()


# ---------------------------------------------------------------- drops

func drop_xp(at: Vector3, amount: float) -> void:
	loot.drop_xp(at, amount)


func drop_gold(at: Vector3, amount: int) -> void:
	loot.drop_gold(at, amount)


func drop_chest(at: Vector3, kind: String = "free") -> Dictionary:
	return chests.drop_chest(at, kind)


# ---------------------------------------------------------------- choices

func open_level() -> void:
	mode = "level"
	chest_kind = ""
	offers = progress.roll_level_offers()
	battle.controls.clear_pointers()
	choice.open("level", offers, {"level": battle.run.level - battle.run.pending_levels + 1, "rerolls": progress.rerolls})
	if battle.sfx != null:
		battle.sfx.play("ui", 0.8)
	if auto_pick:
		choose(0)


func open_chest(kind: String, rolled: Array = []) -> void:
	mode = "chest"
	chest_kind = kind
	offers = rolled if not rolled.is_empty() else progress.roll_chest_offers(kind)
	battle.controls.clear_pointers()
	choice.open("chest", offers, {"kind": kind, "rerolls": progress.rerolls})
	if auto_pick:
		choose(0)


## Takes card `slot` of the open choice. Returns the chosen entry ({} if none).
func choose(slot: int) -> Dictionary:
	if mode == "" or slot < 0 or slot >= offers.size():
		return {}
	var entry: Dictionary = offers[slot]
	var source := "level" if mode == "level" else chest_kind
	var gold: int = progress.apply(entry, source, battle.run.elapsed)
	if gold > 0:
		battle.run.add_gold(gold)
	choices_taken += 1
	if mode == "level":
		battle.run.pending_levels = maxi(0, battle.run.pending_levels - 1)
	_apply_hero_stats(true)
	mode = ""
	offers = []
	choice.close()
	if battle.sfx != null:
		battle.sfx.play("ui", 1.2)
	# Several level-ups at once: the next choice follows right away.
	if not battle.run.dead and battle.run.pending_levels > 0:
		open_level()
	return entry


## One reroll per run: new cards for the open choice.
func reroll() -> bool:
	if mode == "" or not progress.use_reroll():
		return false
	offers = progress.roll_level_offers() if mode == "level" else progress.roll_chest_offers(chest_kind)
	choice.redeal(offers, progress.rerolls)
	if battle.sfx != null:
		battle.sfx.play("ui", 1.0)
	return true


func _on_burst(entry: Dictionary) -> void:
	var rolled: Array = progress.roll_chest_offers(String(entry.kind))
	var best := "common"
	for card in rolled:
		if PROGRESS.rarity_index(String(card.rarity)) > PROGRESS.rarity_index(best):
			best = String(card.rarity)
	chests.play_moment(entry, best)
	if battle.shake != null:
		battle.shake.shake(0.25)
	if battle.sfx != null:
		battle.sfx.play("slam", 1.4)
	open_chest(String(entry.kind), rolled)


# Hero numbers that are not read live (max health): keeps the missing health
# when the maximum grows (a Max-LP pick heals by its gain).
func _apply_hero_stats(keep_missing: bool) -> void:
	var hero: Node3D = battle.hero
	var base: Variant = hero.get("base_health")
	var wanted: float = (float(base) if base != null else T.HERO_HP) + progress.stat("max_hp_bonus")
	var gain: float = wanted - float(hero.max_health)
	hero.max_health = wanted
	if keep_missing and gain > 0.0:
		hero.health = minf(wanted, float(hero.health) + gain)
	hero.health = minf(float(hero.health), wanted)


# ---------------------------------------------------------------- events

func _on_enemy_killed(kind: int, at: Vector3) -> void:
	loot.drop_xp(at, float(XP_BY_KIND.get(kind, XP_OTHER)))
	if _rng.randf() < float(GOLD_CHANCE.get(kind, 0.0)):
		loot.drop_gold(at, int(GOLD_AMOUNT.get(kind, 1)))
	var heal: float = progress.stat("trophy_heal")
	if heal > 0.0:
		_trophy_count += 1
		if _trophy_count >= TROPHY_KILLS:
			_trophy_count = 0
			var hero: Node3D = battle.hero
			if not hero.is_dead():
				hero.health = minf(hero.max_health, hero.health + heal)


# Dornenweste: the attacker (nearest enemy to the strike origin) takes damage.
# hurt fires inside horde.step (enemy arrays in use), so the strike back waits
# for the next progression step.
func _on_hero_hurt(_damage: float, from: Vector3) -> void:
	if progress.stat("thorns") > 0.0:
		_thorns.append(from)


func _strike_back() -> void:
	var thorns: float = progress.stat("thorns")
	var horde: Node3D = battle.horde
	for from in _thorns:
		_hit_back(horde, from, thorns)
	_thorns.clear()


func _hit_back(horde: Node3D, from: Vector3, thorns: float) -> void:
	var index: int = horde.nearest_index(from, THORNS_REACH)
	if index < 0:
		return
	var dir: Vector3 = horde.position_of(index) - battle.hero.position
	battle.run.damage_source = "Dornenweste"
	horde.hurt(index, thorns, dir, 0.0)
	battle.run.damage_source = RUN.DEFAULT_SOURCE
