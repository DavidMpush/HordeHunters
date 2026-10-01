extends SceneTree

# Evolutions (stage 4, Teil B): a weapon on level 6 plus its partner relic ->
# the next elite ("free") or boss cocoon deals the EVOLUTION card (always),
# never a map cocoon or a level-up, never without the relic or below level 6.
# Taking it evolves the weapon (progress.is_evolved, weapon.evolved()),
# progression emits evolved(id), the build summary shows the evolved name and
# icon, and every evolved weapon is clearly stronger and behaves differently.

const T := preload("res://scripts/core/tuning.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []
var battle: Node
var hero: Node3D
var horde: Node3D
var signalled: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_catalogue()
	_condition()
	_partner_priority()
	var lab: Node = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab)
	for k in 3:
		await process_frame
	battle = lab.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	hero = battle.hero
	horde = battle.horde
	battle.progression.evolved.connect(func(id: String) -> void: signalled.append(id))
	_in_cocoon()
	_shotgun()
	_axe()
	_sword()
	_grenade()
	_pistols()
	_lightning()
	battle.set_hero("boxer")
	_fists()
	_finish("evolutions")


# ---------------------------------------------------------------- catalogue

func _catalogue() -> void:
	for id in PROGRESS.WEAPON_ORDER:
		var e: Dictionary = PROGRESS.evolution_def(id)
		check(not e.is_empty(), "%s has an evolution" % id)
		if e.is_empty():
			continue
		var relic: Dictionary = PROGRESS.relic_def(String(e.relic))
		check(not relic.is_empty(), "%s: partner relic %s exists" % [id, e.relic])
		var needs := String(relic.get("needs", ""))
		check(needs == "" or needs == id, "%s: partner relic needs no other weapon (%s)" % [id, needs])
		check(PROGRESS.partner_weapon(String(e.relic)) == id, "%s: one evolution per relic" % id)
		check(String(e.name) != String(PROGRESS.weapon_def(id).name) and String(e.icon).ends_with("_evo"), "%s: own name and icon" % id)


# ---------------------------------------------------------------- condition

func _has_evolution(offers: Array) -> int:
	var found := 0
	for entry in offers:
		if String(entry.type) == "evolution":
			found += 1
	return found


func _condition() -> void:
	var p: RefCounted = PROGRESS.new()
	for k in 4:
		p.apply(p.weapon_entry("shotgun", "common"))
	p.apply(p.relic_entry("pulverhorn"))
	check(p.weapon_rank("shotgun") == 5 and p.evolution_ready().is_empty(), "level 5 + relic: not ready")
	var seen := 0
	for k in 30:
		seen += _has_evolution(p.roll_chest_offers("free")) + _has_evolution(p.roll_chest_offers("boss"))
	check(seen == 0, "no evolution card below level 6 (%d)" % seen)
	var q: RefCounted = PROGRESS.new()
	for k in 5:
		q.apply(q.weapon_entry("shotgun", "common"))
	check(q.weapon_rank("shotgun") == 6 and q.evolution_ready().is_empty(), "level 6 without relic: not ready")
	seen = 0
	for k in 30:
		seen += _has_evolution(q.roll_chest_offers("free")) + _has_evolution(q.roll_chest_offers("boss"))
	check(seen == 0, "no evolution card without the relic (%d)" % seen)
	# Level 6 + relic: guaranteed in elite and boss cocoons, never elsewhere.
	p.apply(p.weapon_entry("shotgun", "common"))
	check(p.evolution_ready() == ["shotgun"], "level 6 + Pulverhorn: ready (%s)" % str(p.evolution_ready()))
	for kind in ["free", "boss"]:
		for k in 20:
			var offers: Array = p.roll_chest_offers(kind)
			check(offers.size() == 3 and _has_evolution(offers) == 1, "%s cocoon: exactly one evolution among 3 cards" % kind)
			check(String(offers[0].id) == "shotgun" and String(offers[0].name) == "Drachenatem" and String(offers[0].rarity) == "legendary", "%s cocoon: Drachenatem card first" % kind)
	seen = 0
	for k in 30:
		seen += _has_evolution(p.roll_chest_offers("map"))
		seen += _has_evolution(p.roll_level_offers())
	check(seen == 0, "never in a map cocoon or a level-up (%d)" % seen)
	# Taking it.
	var before: float = p.stat("pellets_bonus")
	p.apply(p.evolution_entry("shotgun"), "free", 120.0)
	check(p.is_evolved("shotgun") and p.evolution_ready().is_empty(), "evolved, no longer ready")
	check(is_equal_approx(p.stat("pellets_bonus"), before + 2.0), "Drachenatem: +2 pellets")
	seen = 0
	for k in 20:
		seen += _has_evolution(p.roll_chest_offers("boss"))
	check(seen == 0, "an evolved weapon is not offered again")
	check(p.weapon_name("shotgun") == "Drachenatem" and p.weapon_icon("shotgun") == "shotgun_evo", "evolved name and icon")
	var summary: Array = p.build_summary()
	var gun := {}
	for item in summary:
		check(String(item.type) != "evolution", "the evolution pick adds no own item")
		if String(item.id) == "shotgun":
			gun = item
	check(not gun.is_empty() and String(gun.name) == "Drachenatem" and String(gun.icon) == "shotgun_evo" and bool(gun.evolved) and String(gun.rarity) == "legendary" and int(gun.rank) == 6, "summary shows Drachenatem (%s)" % str(gun))
	# A card for a weapon that is not ready does nothing.
	p.apply(p.evolution_entry("axe"))
	check(not p.is_evolved("axe"), "evolution of a weapon not ready is refused")
	p.reset(3)
	check(not p.is_evolved("shotgun") and p.evolved.is_empty(), "a new run starts unevolved")
	# Partner relics: weapon relics only with their weapon, card names the evolution.
	var r: RefCounted = PROGRESS.new()
	check(not r.relic_candidates().has("eisenbandagen") and not r.relic_candidates().has("brandsatz"), "Brann: no fist / grenade relics without them")
	r.apply(r.weapon_entry("grenade", "common"))
	check(r.relic_candidates().has("brandsatz"), "grenade owned: Brandsatz can come")
	check(String(r.relic_entry("brandsatz").text).contains("Evolution: Napalm"), "relic card names the evolution it opens")
	r.apply(r.relic_entry("brandsatz"))
	check(is_equal_approx(r.stat("grenade_radius_mult"), 1.15), "Brandsatz: grenade blast +15 %")


func _partner_priority() -> void:
	var p: RefCounted = PROGRESS.new()
	for k in 4:
		p.apply(p.weapon_entry("axe", "common"))
	var partner := 0
	for k in 40:
		if p.roll_chest_offers("free").any(func(e: Dictionary) -> bool: return String(e.id) == "jagdtrophaee"):
			partner += 1
	check(partner >= 18, "axe on level 4: Jagdtrophäe comes often (%d / 40)" % partner)


# ---------------------------------------------------------------- in the fight

func _in_cocoon() -> void:
	var progress: RefCounted = battle.progress
	for k in 5:
		progress.apply(progress.weapon_entry("shotgun", "common"))
	progress.apply(progress.relic_entry("pulverhorn"))
	battle.progression.open_chest("map")
	check(_has_evolution(battle.progression.offers) == 0, "map cocoon in the fight: no evolution")
	battle.progression.choose(1)
	battle.progression.open_chest("free")
	check(battle.paused() and _has_evolution(battle.progression.offers) == 1, "elite cocoon in the fight: evolution card")
	var slot := -1
	for k in battle.progression.offers.size():
		if String(battle.progression.offers[k].type) == "evolution":
			slot = k
	battle.progression.choose(slot)
	check(signalled == ["shotgun"], "progression emits evolved(shotgun) (%s)" % str(signalled))
	check(battle.shotgun.evolved() and not battle.paused(), "the shotgun is Drachenatem now")
	battle.restart()
	check(not battle.shotgun.evolved(), "restart: back to the plain shotgun")


func _setup(id: String, evolve: bool) -> Node:
	battle.restart()
	battle.director_enabled = false
	var progress: RefCounted = battle.progress
	var owned: int = progress.weapon_rank(id)
	for k in 6 - owned:
		progress.apply(progress.weapon_entry(id, "common"))
	battle.sync_weapons()
	var weapon: Node = battle.weapon_of(id)
	if evolve:
		progress.apply(progress.relic_entry(PROGRESS.partner_relic(id)))
		progress.apply(progress.evolution_entry(id))
	if battle.shotgun != weapon:
		battle.shotgun.shells = 0
		battle.shotgun.reload_left = 1000.0
	hero.position = Vector3.ZERO
	hero.health = hero.max_health
	return weapon


func _spawn(kind: int, at: Vector3, hp := 100000.0) -> int:
	var i: int = horde.spawn(kind, at)
	horde._hp[i] = hp
	horde._appear[i] = 1.0
	return i


func _run_weapon(weapon: Node, seconds: float, pin := true) -> void:
	var spots: Array[Vector3] = []
	for i in horde.count():
		spots.append(horde.position_of(i))
	var t := 0.0
	while t < seconds:
		hero.invulnerable = 1.0
		if battle.shotgun != weapon:
			battle.shotgun.reload_left = 1000.0
		weapon.step(DT)
		if pin:
			for i in mini(spots.size(), horde.count()):
				horde._pos[i] = spots[i]
				horde._knock[i] = Vector3.ZERO
		t += DT


func _damage_in(pack: Array) -> float:
	var total := 0.0
	for i in pack:
		total += 100000.0 - horde.health_of(i)
	return total


func _hit_count(pack: Array) -> int:
	var n := 0
	for i in pack:
		if horde.health_of(i) < 100000.0:
			n += 1
	return n


# Same pack, plain weapon vs evolved: [damage, enemies hit] of each.
func _compare(id: String, layout: Array, seconds: float) -> Array:
	var out: Array = []
	for evolve in [false, true]:
		var weapon := _setup(id, evolve)
		var pack: Array[int] = []
		for spot in layout:
			pack.append(_spawn(T.Kind.WICHTEL, spot))
		horde.step(DT)
		_run_weapon(weapon, seconds)
		out.append([_damage_in(pack), _hit_count(pack), weapon])
	return out


func _fan_pack() -> Array:
	var layout: Array = []
	for k in 10:
		layout.append(Vector3(-1.6 + 0.35 * k, 0, -3.0 - 0.5 * float(k % 3)))
	return layout


func _shotgun() -> void:
	var gun := _setup("shotgun", false)
	var pack: Array[int] = []
	for spot in _fan_pack():
		pack.append(_spawn(T.Kind.WICHTEL, spot))
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	var plain := _damage_in(pack)
	var plain_hit := _hit_count(pack)
	gun = _setup("shotgun", true)
	pack.clear()
	for spot in _fan_pack():
		pack.append(_spawn(T.Kind.WICHTEL, spot))
	horde.step(DT)
	gun.fire(Vector3(0, 0, -1))
	check(gun.evolved() and gun.pellet_count() == T.GUN_PELLETS + 3, "Drachenatem: 7 + 1 + 2 pellets (%d)" % gun.pellet_count())
	check(_hit_count(pack) > plain_hit and _damage_in(pack) > plain * 1.5, "Drachenatem burns the whole fan (%d vs %d hit, %.0f vs %.0f)" % [_hit_count(pack), plain_hit, _damage_in(pack), plain])
	check(gun._burns == 1 and gun._flames.active() > 0, "flame tongues shown")


func _axe() -> void:
	var r := _compare("axe", [Vector3(0, 0, -4.0), Vector3(0.4, 0, -5.0), Vector3(-0.4, 0, -3.0)], 1.2)
	var evo: Node = r[1][2]
	check(float(r[1][0]) > float(r[0][0]) * 1.4, "Blutmond-Axt: clearly more damage (%.0f vs %.0f)" % [r[1][0], r[0][0]])
	check(evo.axe_count() == 4 and evo.hit_radius() > evo.HIT_RADIUS * 1.4, "4 axes, bigger")
	hero.health = hero.max_health - 30.0
	var before: float = hero.health
	_spawn(T.Kind.WICHTEL, Vector3(0, 0, -3.5))
	horde.step(DT)
	evo.cooldown_left = 0.0
	_run_weapon(evo, 1.2)
	check(hero.health > before and evo.healed > 0.0, "Blutmond hits heal (%.1f)" % evo.healed)


func _sword() -> void:
	var sword := _setup("sword", true)
	sword.cooldown_left = 100.0
	var a := _spawn(T.Kind.WICHTEL, Vector3(2.0, 0, 0))
	var b := _spawn(T.Kind.WICHTEL, Vector3(-1.5, 0, 1.5))
	horde.step(DT)
	_run_weapon(sword, 1.0)
	check(sword.spins == 0 and sword.orbit_hits >= 2, "Klingenorkan: the orbit hits without a whirl (%d)" % sword.orbit_hits)
	check(_hit_count([a, b]) == 2, "both sides swept")
	var hits_before: int = sword.orbit_hits
	_run_weapon(sword, 0.2)
	check(sword.orbit_hits - hits_before <= 2, "rehit limit (%d in 0.2 s)" % (sword.orbit_hits - hits_before))
	var storm_radius: float = sword.radius()
	var plain := _setup("sword", false)
	plain.cooldown_left = 100.0
	_spawn(T.Kind.WICHTEL, Vector3(2.0, 0, 0))
	horde.step(DT)
	_run_weapon(plain, 1.0)
	check(plain.orbit_hits == 0 and plain.radius() < storm_radius, "plain sword: no orbit, smaller whirl")


func _grenade() -> void:
	var grenade := _setup("grenade", true)
	var pack: Array[int] = []
	for k in 4:
		pack.append(_spawn(T.Kind.WICHTEL, Vector3(-0.5 + 0.35 * k, 0, -5.0)))
	horde.step(DT)
	grenade.explode(Vector3(0, 0, -5.0))
	var after_blast := _damage_in(pack)
	check(grenade.burns.size() == 1, "Napalm: a burning pool stays")
	grenade.cooldown_left = 100.0
	_run_weapon(grenade, 2.0)
	check(grenade.burn_ticks >= 4 and _damage_in(pack) > after_blast * 1.3, "the pool keeps burning (%d ticks, %.0f -> %.0f)" % [grenade.burn_ticks, after_blast, _damage_in(pack)])
	_run_weapon(grenade, 1.5)
	check(grenade.burns.is_empty(), "the pool burns out")
	var napalm_radius: float = grenade.radius()
	var plain := _setup("grenade", false)
	check(napalm_radius > plain.radius() * 1.15, "Napalm: bigger blast")
	plain.explode(Vector3(0, 0, -5.0))
	check(plain.burns.is_empty(), "plain grenade: no pool")


func _pistols() -> void:
	var r := _compare("pistols", [Vector3(0, 0, -5.0), Vector3(0.1, 0, -6.0), Vector3(1.5, 0, -6.5)], 1.5)
	var evo: Node = r[1][2]
	check(evo.bullets() == 3 and evo.pierce() >= 4, "Kugelhagel: 3 bullets, pierce 4")
	check(float(r[1][0]) > float(r[0][0]) * 2.0, "Kugelhagel: far more damage (%.0f vs %.0f)" % [r[1][0], r[0][0]])


func _lightning() -> void:
	var layout: Array = []
	for k in 9:
		layout.append(Vector3(0.0, 0, -3.0 - 2.4 * k))
	var r := _compare("lightning", layout, 0.1)
	var evo: Node = r[1][2]
	check(int(r[1][1]) > int(r[0][1]) and evo.strikes == 1, "Gewittersturm: longer chain and a strike (%d vs %d)" % [r[1][1], r[0][1]])
	check(float(r[1][0]) > float(r[0][0]) * 1.3, "Gewittersturm: more damage")


func _fists() -> void:
	var fists := _setup("fists", false)
	check(fists == battle.shotgun and not fists.evolved(), "Brine: own fists")
	var progress: RefCounted = battle.progress
	check(progress.relic_candidates().has("eisenbandagen"), "Brine: Eisenbandagen can come")
	var near := _spawn(T.Kind.WICHTEL, Vector3(0, 0, -1.4))
	var behind := _spawn(T.Kind.WICHTEL, Vector3(0.3, 0, -3.3))
	horde.step(DT)
	fists.aim = Vector3(0, 0, -1)
	fists.target = -1
	fists.strike(0)
	check(horde.health_of(behind) == 100000.0, "plain jab: the one behind is safe")
	var plain_jab: float = 100000.0 - horde.health_of(near)
	fists = _setup("fists", true)
	check(fists.evolved(), "Titanenfäuste")
	near = _spawn(T.Kind.WICHTEL, Vector3(0, 0, -1.4))
	behind = _spawn(T.Kind.WICHTEL, Vector3(0.3, 0, -3.3))
	horde.step(DT)
	fists.aim = Vector3(0, 0, -1)
	fists.target = -1
	fists.strike(0)
	check(fists.titan_waves == 1 and horde.health_of(behind) < 100000.0, "every strike sends a shockwave")
	check(100000.0 - horde.health_of(near) > plain_jab * 1.5, "Titanenfäuste hit much harder")
	var summary: Array = progress.build_summary()
	var found := false
	for item in summary:
		if String(item.id) == "fists" and String(item.name) == "Titanenfäuste" and bool(item.evolved):
			found = true
	check(found, "summary lists Titanenfäuste")


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
