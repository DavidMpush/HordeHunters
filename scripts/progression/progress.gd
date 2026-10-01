extends RefCounted

# Build of one run (stage 2, Teil A §2-3), after Mawlings stats.gd + arsenal.gd:
#   stats    11 values, at most SLOTS (6) different per run, 5 ranks each.
#            A pick raises the rank by 1 and the value by the rarity factor of
#            the card (common 1.0 .. legendary 3.0); effect = step x value.
#   shotgun  own upgrade track, 5 ranks in a fixed order (SHOTGUN_STEPS);
#            rarity = rank jump (epic +2, legendary +3), like Mawlings weapons.
#   relics   hero relics from cocoons only (RELICS), at most RELIC_SLOTS
#            different, a few stacks each.
# Level-ups offer stats + the shotgun track; cocoons offer relics + stats with
# a rarity floor per cocoon kind. One reroll per run (level-up and cocoon).
#
# Everything the hero and the shotgun read goes through stat(id) (hero.stat()):
#   damage_mult, fire_rate_mult, reload_mult, range_mult, fan_mult,
#   pellets_bonus, pierce, knockback_mult, mag_bonus, crit, speed_mult,
#   max_hp_bonus, regen, armor, magnet_mult, xp_mult, gold_mult, luck,
#   dash_cooldown_mult, thorns, trophy_heal
#
# Offer entries (Dictionary), also stored in `picks`:
#   {"type": "stat"|"shotgun"|"relic"|"gold", "id", "name", "text", "rarity",
#    "icon", "from", "to", "before", "after", "label", "amount"}

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_FACTOR := {"common": 1.0, "uncommon": 1.25, "rare": 1.5, "epic": 2.0, "legendary": 3.0}
const RARITY_CHANCE := {"common": 0.55, "uncommon": 0.25, "rare": 0.13, "epic": 0.06, "legendary": 0.01}
## Luck: +10 % (relative) on every tier from uncommon up, per point.
const LUCK_STEP := 0.10
const MAX_RANK := 5
const SLOTS := 6
const RELIC_SLOTS := 6
const RELIC_MAX_STACK := 3
const RELIC_STACK_LIMIT := {"ahnenamulett": 1, "bleihagel": 2, "patronengurt": 2}
const REROLLS_PER_RUN := 1
const CHOICES := 3
## Share of level-up offers that carry the shotgun track while it can grow.
const SHOTGUN_SHARE := 0.5
## Cocoons: share of relic cards (rest stats).
const RELIC_SHARE := 0.6
## Lowest rarity per cocoon kind (map = paid with gold, free = elite drop).
const CHEST_FLOOR := {"map": "uncommon", "free": "rare", "boss": "epic"}
## Map cocoon price in gold: CHEST_BASE x CHEST_GROWTH^bought, luck -3 % per point.
const CHEST_BASE := 20.0
const CHEST_GROWTH := 1.6
const CHEST_LUCK_DISCOUNT := 0.03
## Nothing left to improve: a gold card instead.
const GOLD_CARD := 25
const ARMOR_CAP := 0.6

const STATS := [
	{"id": "damage", "name": "Schaden", "step": 0.08, "unit": "pct", "label": "Schaden", "icon": "burst"},
	{"id": "firerate", "name": "Feuerrate", "step": 0.07, "unit": "pct", "label": "Feuerrate und Nachladetempo", "icon": "clock"},
	{"id": "range", "name": "Reichweite", "step": 0.06, "unit": "pct", "label": "Reichweite der Waffe", "icon": "aim"},
	{"id": "speed", "name": "Tempo", "step": 0.05, "unit": "pct", "label": "Lauftempo", "icon": "boot"},
	{"id": "maxhp", "name": "Max-LP", "step": 15.0, "unit": "flat", "label": "Max-LP", "icon": "heart"},
	{"id": "regen", "name": "Regeneration", "step": 0.4, "unit": "lps", "label": "LP je Sekunde", "icon": "regen"},
	{"id": "armor", "name": "Rüstung", "step": 0.06, "unit": "neg", "label": "erlittener Schaden", "icon": "shield"},
	{"id": "magnet", "name": "Sammelradius", "step": 0.2, "unit": "pct", "label": "Sammelradius für XP und Gold", "icon": "magnet"},
	{"id": "crit", "name": "Krit-Chance", "step": 0.05, "unit": "chance", "label": "Chance auf doppelten Schaden", "icon": "crit"},
	{"id": "xp", "name": "XP-Bonus", "step": 0.08, "unit": "pct", "label": "XP je Gem", "icon": "gem"},
	{"id": "luck", "name": "Glück", "step": 1.0, "unit": "luck", "label": "seltenere Karten, billigere Kokons", "icon": "clover"},
]

const SHOTGUN_NAME := "Schrotflinte"
const SHOTGUN_STEPS := [
	{"name": "+1 Kugel", "text": "+1 Kugel je Schuss"},
	{"name": "Durchschlag", "text": "Kugeln treffen 1 weiteren Gegner"},
	{"name": "Wucht", "text": "+50 % Rückstoß"},
	{"name": "Großes Magazin", "text": "+1 Schuss im Magazin"},
	{"name": "Würgebohrung", "text": "Fächer 30 % enger, +25 % Reichweite"},
]
const RANK_GAIN := {"common": 1, "uncommon": 1, "rare": 1, "epic": 2, "legendary": 3}

const RELICS := [
	{"id": "pulverhorn", "name": "Pulverhorn", "text": "Nachladen 15 % schneller", "rarity": "common", "icon": "horn"},
	{"id": "feldflasche", "name": "Feldflasche", "text": "+0,5 LP je Sekunde", "rarity": "common", "icon": "flask"},
	{"id": "lockstein", "name": "Lockstein", "text": "+40 % Sammelradius", "rarity": "common", "icon": "magnet"},
	{"id": "dornenweste", "name": "Dornenweste", "text": "Wer dich trifft, erleidet 20 Schaden", "rarity": "uncommon", "icon": "thorns"},
	{"id": "gluecksmuenze", "name": "Glücksmünze", "text": "+50 % Gold und +1 Glück", "rarity": "uncommon", "icon": "coin"},
	{"id": "siebenmeilenstiefel", "name": "Siebenmeilenstiefel", "text": "Dash lädt 20 % schneller", "rarity": "rare", "icon": "boot"},
	{"id": "jagdtrophaee", "name": "Jagdtrophäe", "text": "Jeder 25. Kill heilt 8 LP", "rarity": "rare", "icon": "trophy"},
	{"id": "bleihagel", "name": "Bleihagel", "text": "+2 Kugeln je Schuss", "rarity": "epic", "icon": "shells"},
	{"id": "patronengurt", "name": "Patronengurt", "text": "+1 Schuss im Magazin", "rarity": "epic", "icon": "belt"},
	{"id": "ahnenamulett", "name": "Ahnenamulett", "text": "+25 % Schaden und +25 Max-LP", "rarity": "legendary", "icon": "amulet"},
]

var ranks: Dictionary = {}
var units: Dictionary = {}
var shotgun_rank := 0
var relics: Dictionary = {}
var picks: Array[Dictionary] = []
var rerolls := REROLLS_PER_RUN
var chests_bought := 0
var rng := RandomNumberGenerator.new()
## stat() cache, dropped on every change.
var _cache: Dictionary = {}


func _init() -> void:
	rng.seed = 20202


func reset(seed_value: int = 20202) -> void:
	ranks.clear()
	units.clear()
	relics.clear()
	picks.clear()
	shotgun_rank = 0
	rerolls = REROLLS_PER_RUN
	chests_bought = 0
	rng.seed = seed_value
	_cache.clear()


# ---------------------------------------------------------------- catalogue

static func stat_def(id: String) -> Dictionary:
	for entry in STATS:
		if entry.id == id:
			return entry
	return {}


static func relic_def(id: String) -> Dictionary:
	for entry in RELICS:
		if entry.id == id:
			return entry
	return {}


static func stat_ids() -> Array:
	var out: Array = []
	for entry in STATS:
		out.append(entry.id)
	return out


static func relic_limit(id: String) -> int:
	return int(RELIC_STACK_LIMIT.get(id, RELIC_MAX_STACK))


## Neutral value of a hero stat without any build (tests, the lab).
static func default_stat(id: String) -> float:
	return 1.0 if id.ends_with("_mult") else 0.0


# ---------------------------------------------------------------- state

func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func units_of(id: String) -> float:
	return float(units.get(id, float(rank(id))))


func stacks(id: String) -> int:
	return int(relics.get(id, 0))


func amount(id: String) -> float:
	var d := stat_def(id)
	return 0.0 if d.is_empty() else float(d.step) * units_of(id)


func owned_stats() -> int:
	var used := 0
	for id in ranks:
		if int(ranks[id]) > 0:
			used += 1
	return used


func owned_relics() -> int:
	var used := 0
	for id in relics:
		if int(relics[id]) > 0:
			used += 1
	return used


func luck() -> float:
	return stat("luck")


## Combined effect for the hero / shotgun (see the header).
func stat(id: String) -> float:
	if _cache.has(id):
		return _cache[id]
	var value := default_stat(id)
	match id:
		"damage_mult":
			value = (1.0 + amount("damage")) * (1.25 if stacks("ahnenamulett") > 0 else 1.0)
		"fire_rate_mult":
			value = 1.0 + amount("firerate")
		"reload_mult":
			value = (1.0 + amount("firerate")) * (1.0 + 0.15 * stacks("pulverhorn"))
		"range_mult":
			value = 1.0 + amount("range") + (0.25 if shotgun_rank >= 5 else 0.0)
		"fan_mult":
			value = 0.7 if shotgun_rank >= 5 else 1.0
		"pellets_bonus":
			value = (1.0 if shotgun_rank >= 1 else 0.0) + 2.0 * stacks("bleihagel")
		"pierce":
			value = 1.0 if shotgun_rank >= 2 else 0.0
		"knockback_mult":
			value = 1.5 if shotgun_rank >= 3 else 1.0
		"mag_bonus":
			value = (1.0 if shotgun_rank >= 4 else 0.0) + float(stacks("patronengurt"))
		"crit":
			value = minf(0.75, amount("crit"))
		"speed_mult":
			value = 1.0 + amount("speed")
		"max_hp_bonus":
			value = amount("maxhp") + (25.0 if stacks("ahnenamulett") > 0 else 0.0)
		"regen":
			value = amount("regen") + 0.5 * stacks("feldflasche")
		"armor":
			value = minf(ARMOR_CAP, amount("armor"))
		"magnet_mult":
			value = 1.0 + amount("magnet") + 0.4 * stacks("lockstein")
		"xp_mult":
			value = 1.0 + amount("xp")
		"gold_mult":
			value = 1.0 + 0.5 * stacks("gluecksmuenze")
		"luck":
			value = amount("luck") + float(stacks("gluecksmuenze"))
		"dash_cooldown_mult":
			value = 1.0 / (1.0 + 0.2 * stacks("siebenmeilenstiefel"))
		"thorns":
			value = 20.0 * stacks("dornenweste")
		"trophy_heal":
			value = 8.0 * stacks("jagdtrophaee")
	_cache[id] = value
	return value


# ---------------------------------------------------------------- rarity

static func rarity_chances(luck_value: float, minimum: String = "common") -> Dictionary:
	var boost := 1.0 + LUCK_STEP * maxf(0.0, luck_value)
	var out := {}
	var upper := 0.0
	for rarity in RARITIES.slice(1):
		out[rarity] = float(RARITY_CHANCE[rarity]) * boost
		upper += out[rarity]
	out["common"] = maxf(0.0, 1.0 - upper)
	var floor_index := RARITIES.find(minimum)
	var total := 0.0
	for index in RARITIES.size():
		if index < floor_index:
			out[RARITIES[index]] = 0.0
		total += out[RARITIES[index]]
	for rarity in RARITIES:
		out[rarity] = out[rarity] / total if total > 0.0 else (1.0 if rarity == minimum else 0.0)
	return out


func roll_rarity(minimum: String = "common") -> String:
	var chances := rarity_chances(luck(), minimum)
	var roll := rng.randf()
	var sum := 0.0
	for rarity in RARITIES:
		sum += float(chances[rarity])
		if roll < sum:
			return rarity
	return minimum


static func rarity_index(rarity: String) -> int:
	return maxi(0, RARITIES.find(rarity))


# ---------------------------------------------------------------- offers

## Stats that can still grow; with all SLOTS taken only owned ones.
func stat_candidates() -> Array:
	var full := owned_stats() >= SLOTS
	var out: Array = []
	for entry in STATS:
		var r := rank(entry.id)
		if r >= MAX_RANK or (full and r <= 0):
			continue
		out.append(entry.id)
	return out


## Relics that can still be taken (`minimum`..: rarity window not applied here).
func relic_candidates() -> Array:
	var full := owned_relics() >= RELIC_SLOTS
	var out: Array = []
	for entry in RELICS:
		var s := stacks(entry.id)
		if s >= relic_limit(entry.id) or (full and s <= 0):
			continue
		out.append(entry.id)
	return out


## Level-up: three different cards (stats + shotgun track).
func roll_level_offers(count: int = CHOICES) -> Array:
	var offers: Array = []
	var pool := stat_candidates()
	if shotgun_rank < MAX_RANK and rng.randf() < SHOTGUN_SHARE:
		offers.append(_shotgun_entry(roll_rarity()))
	while offers.size() < count and not pool.is_empty():
		var id: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		offers.append(stat_entry(id, roll_rarity()))
	if offers.size() < count and shotgun_rank < MAX_RANK and not _has_type(offers, "shotgun"):
		offers.append(_shotgun_entry(roll_rarity()))
	if offers.is_empty():
		offers.append(gold_entry())
	_shuffle(offers)
	return offers


## Cocoon: relics and stats, at least CHEST_FLOOR[kind].
func roll_chest_offers(kind: String, count: int = CHOICES) -> Array:
	var minimum := String(CHEST_FLOOR.get(kind, "common"))
	var offers: Array = []
	var stat_pool := stat_candidates()
	var relic_pool := relic_candidates()
	var tries := 0
	while offers.size() < count and tries < 12:
		tries += 1
		var rarity := roll_rarity(minimum)
		var entry := {}
		if not relic_pool.is_empty() and (rng.randf() < RELIC_SHARE or stat_pool.is_empty()):
			var id := _pick_relic(relic_pool, rarity, minimum)
			if id != "":
				relic_pool.erase(id)
				entry = relic_entry(id)
		if entry.is_empty() and not stat_pool.is_empty():
			var sid: String = stat_pool.pop_at(rng.randi_range(0, stat_pool.size() - 1))
			entry = stat_entry(sid, rarity)
		if entry.is_empty():
			break
		offers.append(entry)
	if offers.is_empty():
		offers.append(gold_entry())
	return offers


# Relic of exactly `rarity`, else the nearest tier at or above `minimum`
# (lower ones first, then higher). "" when none fits.
func _pick_relic(pool: Array, rarity: String, minimum: String) -> String:
	var order: Array = []
	var start := rarity_index(rarity)
	for index in range(start, rarity_index(minimum) - 1, -1):
		order.append(RARITIES[index])
	for index in range(start + 1, RARITIES.size()):
		order.append(RARITIES[index])
	for tier in order:
		var fits: Array = pool.filter(func(id): return String(relic_def(id).rarity) == tier)
		if not fits.is_empty():
			return String(fits[rng.randi_range(0, fits.size() - 1)])
	return ""


func stat_entry(id: String, rarity: String) -> Dictionary:
	var d := stat_def(id)
	var now := units_of(id)
	var next := now + float(RARITY_FACTOR.get(rarity, 1.0))
	return {"type": "stat", "id": id, "name": d.name, "rarity": rarity, "icon": d.icon,
		"from": rank(id), "to": mini(MAX_RANK, rank(id) + 1),
		"before": format_value(id, now), "after": format_value(id, next), "label": d.label,
		"text": "%s → %s %s" % [format_value(id, now), format_value(id, next), d.label]}


func _shotgun_entry(rarity: String) -> Dictionary:
	var to := mini(MAX_RANK, shotgun_rank + int(RANK_GAIN.get(rarity, 1)))
	var names := PackedStringArray()
	var texts := PackedStringArray()
	for index in range(shotgun_rank, to):
		names.append(SHOTGUN_STEPS[index].name)
		texts.append(SHOTGUN_STEPS[index].text)
	return {"type": "shotgun", "id": "shotgun", "name": SHOTGUN_NAME, "rarity": rarity, "icon": "shotgun",
		"from": shotgun_rank, "to": to, "label": " · ".join(names), "text": " · ".join(texts)}


func relic_entry(id: String) -> Dictionary:
	var d := relic_def(id)
	return {"type": "relic", "id": id, "name": d.name, "rarity": d.rarity, "icon": d.icon,
		"from": stacks(id), "to": stacks(id) + 1, "label": d.text, "text": d.text}


func gold_entry() -> Dictionary:
	return {"type": "gold", "id": "gold", "name": "Goldbeutel", "rarity": "common", "icon": "coin",
		"amount": GOLD_CARD, "from": 0, "to": 0, "label": "+%d Gold" % GOLD_CARD, "text": "+%d Gold" % GOLD_CARD}


static func _has_type(offers: Array, type: String) -> bool:
	for entry in offers:
		if String(entry.type) == type:
			return true
	return false


func _shuffle(list: Array) -> void:
	for index in range(list.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var keep: Variant = list[index]
		list[index] = list[other]
		list[other] = keep


# ---------------------------------------------------------------- picks

## Applies a chosen card. `source` "level" or a cocoon kind. Returns the gold of
## a gold card (0 otherwise).
func apply(entry: Dictionary, source: String = "level", time: float = 0.0) -> int:
	var gold := 0
	match String(entry.get("type", "")):
		"stat":
			var id := String(entry.id)
			var before := units_of(id)
			ranks[id] = mini(MAX_RANK, rank(id) + 1)
			units[id] = before + float(RARITY_FACTOR.get(String(entry.rarity), 1.0))
		"shotgun":
			shotgun_rank = mini(MAX_RANK, shotgun_rank + int(RANK_GAIN.get(String(entry.rarity), 1)))
		"relic":
			var rid := String(entry.id)
			relics[rid] = mini(relic_limit(rid), stacks(rid) + 1)
		"gold":
			gold = int(entry.get("amount", GOLD_CARD))
	_cache.clear()
	var logged := entry.duplicate()
	logged["source"] = source
	logged["time"] = time
	picks.append(logged)
	return gold


func can_reroll() -> bool:
	return rerolls > 0


func use_reroll() -> bool:
	if rerolls <= 0:
		return false
	rerolls -= 1
	return true


## Current map cocoon price in gold.
func chest_price() -> int:
	var factor := maxf(0.4, 1.0 - CHEST_LUCK_DISCOUNT * luck())
	return int(round(CHEST_BASE * pow(CHEST_GROWTH, chests_bought) * factor))


## Build overview for the result: [{"type", "id", "name", "icon", "rank", "max", "rarity"}]
## (stats in pick order, the shotgun track, relics), best rarity picked per item.
func build_summary() -> Array:
	var out: Array = []
	var seen := {}
	for pick in picks:
		var type := String(pick.type)
		if type == "gold":
			continue
		var key := type + ":" + String(pick.id)
		if seen.has(key):
			var item: Dictionary = out[seen[key]]
			if rarity_index(String(pick.rarity)) > rarity_index(String(item.rarity)):
				item.rarity = pick.rarity
			continue
		seen[key] = out.size()
		out.append({"type": type, "id": pick.id, "name": pick.name, "icon": pick.icon, "rarity": pick.rarity})
	for item in out:
		match String(item.type):
			"stat":
				item["rank"] = rank(String(item.id))
				item["max"] = MAX_RANK
			"shotgun":
				item["rank"] = shotgun_rank
				item["max"] = MAX_RANK
			"relic":
				item["rank"] = stacks(String(item.id))
				item["max"] = relic_limit(String(item.id))
	return out


# ---------------------------------------------------------------- text

static func format_value(id: String, value: float) -> String:
	var d := stat_def(id)
	var amount_value := float(d.get("step", 0.0)) * value
	match String(d.get("unit", "")):
		"pct", "chance":
			return "0 %" if value <= 0.0 else "+%s %%" % _num(amount_value * 100.0)
		"neg":
			return "0 %" if value <= 0.0 else "−%s %%" % _num(minf(ARMOR_CAP, amount_value) * 100.0)
		"flat":
			return "+0" if value <= 0.0 else "+%s" % _num(amount_value)
		"lps":
			return "0/s" if value <= 0.0 else "+%s/s" % _num(amount_value)
		"luck":
			return "+%s" % _num(amount_value)
	return str(value)


static func _num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 1).replace(".", ",")
