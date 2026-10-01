extends SceneTree

# Gold and cocoons (stage 2, Teil A §3) in the real scene: gold coins drop and
# are picked up, map cocoons stand on the layout's cocoon slots, buying costs
# the rising gold price (too little gold: nothing happens), opening pauses the
# run with a 1-of-3 relic/stat choice above the rarity floor, the drop API
# (battle.drop_chest / drop_gold) for elites and bosses, restart.

const T := preload("res://scripts/core/tuning.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
const LOOT := preload("res://scripts/progression/loot.gd")
const DT := 1.0 / 30.0

var failures: Array[String] = []


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	var battle: Node = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	var hero: Node3D = battle.hero
	var run: RefCounted = battle.run
	var chests: Node3D = battle.chests
	var progress: RefCounted = battle.progress
	var start := hero.position
	_jam(battle)
	battle.tick(DT)
	# Map cocoons on the layout's cocoon slots.
	var slots: Array = battle.arena.poi_slots("cocoon")
	check(chests.closed_count("map") == slots.size() and slots.size() >= 4, "map cocoons on the cocoon slots (%d / %d)" % [chests.closed_count("map"), slots.size()])
	# Gold: drop_gold -> coins -> picked up.
	battle.drop_gold(hero.position + Vector3(1, 0, 0), 12)
	check(battle.loot.count_of(LOOT.Sort.GOLD) == 3, "12 gold drop as 3 coins (%d)" % battle.loot.count_of(LOOT.Sort.GOLD))
	for k in 40:
		battle.tick(DT)
	check(run.gold == 12, "coins picked up: 12 gold (%d)" % run.gold)
	# Normal enemies drop gold rarely, Brocken often.
	var dropped := 0
	for k in 40:
		var b: int = battle.horde.spawn(T.Kind.BROCKEN, hero.position + Vector3(20, 0, 20))
		battle.horde.hurt(b, 10000.0, Vector3.FORWARD)
	dropped = battle.loot.count_of(LOOT.Sort.GOLD)
	check(dropped >= 8 and dropped <= 36, "Brocken drop gold about half the time (%d / 40)" % dropped)
	battle.loot.clear()
	# Too little gold: the cocoon stays shut.
	run.gold = 5
	var entry: Dictionary = chests.nearest(hero.position, 1000.0, "map")
	check(not entry.is_empty(), "a map cocoon exists")
	var price: int = chests.price(entry)
	check(price == 20, "first cocoon costs 20 gold (%d)" % price)
	_stand(battle, entry.at, 30)
	check(int(entry.state) == 0 and bool(entry.denied) and run.gold == 5, "too little gold: stays shut, nothing paid")
	check(not battle.paused(), "no choice without paying")
	# Enough gold: step out and in again -> pays and opens.
	run.gold = 30
	_stand(battle, entry.at + Vector3(6, 0, 0), 10)
	check(not bool(entry.denied), "stepping out resets the denial")
	_stand(battle, entry.at, 40)
	check(run.gold == 10, "paid 20 gold (%d left)" % run.gold)
	check(battle.paused() and battle.progression.mode == "chest", "cocoon choice open, run paused")
	check(progress.chests_bought == 1 and chests.price(chests.nearest(hero.position, 1000.0, "map")) == 32, "next cocoon costs 32")
	var offers: Array = battle.progression.offers
	check(offers.size() == 3, "three cocoon cards (%d)" % offers.size())
	for card in offers:
		check(PROGRESS.rarity_index(String(card.rarity)) >= PROGRESS.rarity_index("uncommon"), "map cocoon: at least uncommon (%s)" % card.rarity)
		check(card.type == "relic" or card.type == "stat", "cocoon cards are relics or stats (%s)" % card.type)
	var relic_slot := -1
	for k in offers.size():
		if offers[k].type == "relic":
			relic_slot = k
	if relic_slot < 0:
		battle.progression.offers[0] = progress.relic_entry("feldflasche")
		relic_slot = 0
	var chosen: Dictionary = battle.progression.choose(relic_slot)
	check(progress.stacks(String(chosen.id)) == 1, "the chosen relic is owned (%s)" % chosen.id)
	check(not battle.paused(), "run resumes after the cocoon")
	# Elite drop: a free cocoon, at least rare; opens without gold.
	run.gold = 0
	var at := start + Vector3(4, 0, 4)
	battle.drop_chest(at, "free")
	var free: Dictionary = chests.nearest(at, 12.0, "free")
	check(not free.is_empty(), "drop_chest places a free cocoon")
	_stand(battle, free.at, 40)
	check(battle.progression.mode == "chest" and battle.progression.chest_kind == "free", "free cocoon opens without gold")
	for card in battle.progression.offers:
		check(PROGRESS.rarity_index(String(card.rarity)) >= PROGRESS.rarity_index("rare"), "elite cocoon: at least rare (%s)" % card.rarity)
	battle.progression.choose(0)
	# Boss floor: always epic or better.
	for k in 40:
		for card in progress.roll_chest_offers("boss"):
			check(PROGRESS.rarity_index(String(card.rarity)) >= PROGRESS.rarity_index("epic"), "boss cocoon: at least epic (%s)" % card.rarity)
	battle.drop_chest(start + Vector3(-5, 0, 3), "boss")
	check(chests.closed_count("boss") == 1, "boss cocoon placed")
	# open_now for captures/bot pays like a hold.
	run.gold = 0
	var shut: Dictionary = chests.nearest(hero.position, 1000.0, "map")
	check(not chests.open_now(shut) and int(shut.state) == 0, "open_now refuses without gold")
	# Restart: map cocoons back, drops gone, gold reset.
	battle.restart()
	battle.tick(DT)
	check(run.gold == 0 and progress.chests_bought == 0, "restart resets gold and the price")
	check(chests.closed_count("map") == slots.size() and chests.closed_count("free") == 0 and chests.closed_count("boss") == 0, "restart: map cocoons back, drops gone")
	_finish("chests")


func _stand(battle: Node, at: Vector3, frames: int) -> void:
	for k in frames:
		if battle.paused():
			return
		battle.hero.position = Vector3(at.x, 0.0, at.z)
		battle.hero.velocity = Vector3.ZERO
		battle.tick(DT)


func _jam(battle: Node) -> void:
	battle.shotgun.shells = 0
	battle.shotgun.reload_left = 1000.0


func _finish(name: String) -> void:
	if failures.is_empty():
		print("PASS %s" % name)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)
