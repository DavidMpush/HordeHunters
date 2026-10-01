extends RefCounted

# Run state: time, kills, death (stage 1) plus XP, level and gold (stage 2,
# Teil A). Only death ends a run.
#   xp            XP inside the current level (0 .. xp_needed(level))
#   level         starts at 1; the level curve is Mawlings' 60 + 25 L + 6 L²
#                 with L = level-ups so far (the first level-up costs 60 XP)
#   pending_levels  level-ups not chosen yet (progression opens the choice)
#   damage_by_source  "Schrotflinte", "Dornenweste", ... (result screen)

signal leveled_up(level: int)
signal died

const DEFAULT_SOURCE := "Schrotflinte"

var elapsed := 0.0
var kills := 0
var kills_by_kind := PackedInt32Array([0, 0, 0])
var shots := 0
var damage_dealt := 0.0
var damage_taken := 0.0
var dead := false
## Stage 4 Teil A: the boss of the last world fell. A won run counts as ended
## (`dead` is set too, so everything that stops on death stops), but the hero
## lives; the result screen shows SIEG!.
var won := false
## Seconds since death (the result screen appears after a short beat).
var since_death := 0.0
var runs := 1
var xp := 0.0
var xp_total := 0.0
var level := 1
var pending_levels := 0
var gold := 0
var gold_total := 0
var damage_by_source: Dictionary = {}
## Damage reported now is booked on this source (progression switches it for
## relic damage and back).
var damage_source := DEFAULT_SOURCE


func reset() -> void:
	elapsed = 0.0
	kills = 0
	kills_by_kind = PackedInt32Array([0, 0, 0])
	shots = 0
	damage_dealt = 0.0
	damage_taken = 0.0
	dead = false
	won = false
	since_death = 0.0
	xp = 0.0
	xp_total = 0.0
	level = 1
	pending_levels = 0
	gold = 0
	gold_total = 0
	damage_by_source.clear()
	damage_source = DEFAULT_SOURCE


func step(delta: float) -> void:
	if dead:
		since_death += delta
	else:
		elapsed += delta


func add_kill(kind: int) -> void:
	kills += 1
	while kind >= kills_by_kind.size() and kind < 64:
		kills_by_kind.append(0)
	if kind >= 0 and kind < kills_by_kind.size():
		kills_by_kind[kind] += 1


func add_damage(amount: float, source: String = "") -> void:
	damage_dealt += amount
	var key := source if source != "" else damage_source
	damage_by_source[key] = float(damage_by_source.get(key, 0.0)) + amount


## XP for the next level-up at `level_value` (60 + 25 L + 6 L², L = level - 1).
static func xp_needed(level_value: int) -> int:
	var l := maxi(0, level_value - 1)
	return 60 + 25 * l + 6 * l * l


func xp_share() -> float:
	return clampf(xp / float(xp_needed(level)), 0.0, 1.0)


func add_xp(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	xp += amount
	xp_total += amount
	while xp >= float(xp_needed(level)):
		xp -= float(xp_needed(level))
		level += 1
		pending_levels += 1
		leveled_up.emit(level)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_total += amount


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	return true


## The run is won (worlds.gd): ends it like a death, without `died`.
func win() -> void:
	if dead:
		return
	won = true
	dead = true
	since_death = 0.0


func die() -> void:
	if dead:
		return
	dead = true
	since_death = 0.0
	died.emit()


## "2:05"
static func clock(seconds: float) -> String:
	var whole := int(floor(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
