extends SceneTree

# Review frames of stage 4 Teil B from the game camera (main.tscn, Brann with a
# silent shotgun unless the shotgun itself is shown):
#   preview_evolution_card.png      - elite cocoon with the EVOLUTION card
#   preview_weapon_pistols.png      - Doppelpistolen in a fight
#   preview_weapon_lightning.png    - Blitzkette jumping through a pack
#   preview_evolved_shotgun.png     - Drachenatem (flame cone, bursts)
#   preview_evolved_sword.png       - Klingenorkan (orbiting blades)
#   preview_evolved_grenade.png     - Napalm (burning pools)
#   preview_evolved_lightning.png   - Gewittersturm (strike from the sky)
# Run with a window (never --headless): tools/capture.ps1 -Only evolution

const T := preload("res://scripts/core/tuning.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")
const DT := 1.0 / 60.0

var main: Node
var battle: Node
var _silent := true


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(720, 1280)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for k in 3:
		await process_frame
	battle = main.get_node("Battle")
	battle.auto = false
	battle.director_enabled = false
	battle.sfx.enabled = false
	for k in 10:
		await _tick()
	await _card()
	await _shotgun()
	await _pistols()
	await _lightning(false, "preview_weapon_lightning")
	await _lightning(true, "preview_evolved_lightning")
	await _sword()
	await _grenade()
	print("Saved evolution review frames")
	quit()


func _card() -> void:
	var progress: RefCounted = battle.progress
	_give("axe", 6)
	progress.apply(progress.relic_entry("jagdtrophaee"))
	var progression: Node = battle.progression
	progression.open_chest("free")
	for k in 50:
		await process_frame
	await _save("preview_evolution_card")
	progression.choose(0)
	_drop("axe")


func _pistols() -> void:
	_give("pistols", 4)
	_pack(Vector3(0.4, 0, -1), 5.5, 9)
	_pack(Vector3(-1, 0, 0.5), 4.5, 6)
	var guns: Node = battle.weapon_of("pistols")
	for k in 15:
		await _tick()
	var shots: int = guns.shots
	for k in 60:
		await _tick()
		if guns.shots > shots:
			break
	await _tick()
	await _save("preview_weapon_pistols")
	_drop("pistols")


func _lightning(evolve: bool, name: String) -> void:
	_give("lightning", 6 if evolve else 4)
	if evolve:
		_evolve("lightning")
	_pack(Vector3(0.3, 0, -1), 4.0, 12)
	_pack(Vector3(-1, 0, -0.3), 5.0, 6)
	var bolt: Node = battle.weapon_of("lightning")
	var casts: int = bolt.casts
	for k in 240:
		await _tick()
		if bolt.casts > casts:
			break
	await _tick()
	await _save(name)
	_drop("lightning")


func _sword() -> void:
	_give("sword", 6)
	_evolve("sword")
	_pack(Vector3(1, 0, -0.4), 3.2, 9)
	_pack(Vector3(-1, 0, 0.6), 3.6, 6)
	var sword: Node = battle.weapon_of("sword")
	sword.cooldown_left = 0.5
	for k in 20:
		await _tick()
	await _save("preview_evolved_sword")
	_drop("sword")


func _grenade() -> void:
	_give("grenade", 6)
	_evolve("grenade")
	_pack(Vector3(0.5, 0, -1), 6.0, 12)
	_pack(Vector3(-0.8, 0, 0.6), 5.0, 9)
	var grenade: Node = battle.weapon_of("grenade")
	var booms: int = grenade.explosions
	for k in 300:
		await _tick()
		if grenade.explosions > booms + 1:
			break
	for k in 40:
		await _tick()
	await _save("preview_evolved_grenade")
	_drop("grenade")


func _shotgun() -> void:
	_silent = false
	_give("shotgun", 6)
	_evolve("shotgun")
	battle.shotgun.reload_left = 0.0
	battle.shotgun.shells = battle.shotgun.max_shells()
	_pack(Vector3(0.2, 0, -1), 4.5, 12)
	var gun: Node = battle.shotgun
	var shots: int = gun.shots
	for k in 120:
		await _tick()
		if gun.shots > shots:
			break
	for k in 2:
		await _tick()
	await _save("preview_evolved_shotgun")
	_silent = true
	battle.horde.clear()


func _give(id: String, rank: int) -> void:
	var progress: RefCounted = battle.progress
	var have: int = progress.weapon_rank(id)
	for k in maxi(0, rank - have):
		progress.apply(progress.weapon_entry(id, "common"))
	battle.sync_weapons()


func _evolve(id: String) -> void:
	var progress: RefCounted = battle.progress
	progress.apply(progress.relic_entry(PROGRESS.partner_relic(id)))
	progress.apply(progress.evolution_entry(id))


func _drop(id: String) -> void:
	battle.progress.weapons.erase(id)
	battle.sync_weapons()
	battle.horde.clear()


func _pack(direction: Vector3, distance: float, count: int) -> void:
	var at: Vector3 = battle.hero.position
	var dir := direction.normalized()
	for k in count:
		var spot := at + dir * (distance + 0.7 * float(k % 3)) + Vector3(-dir.z, 0, dir.x) * (float(k / 3) - 1.5) * 0.95
		var i: int = battle.horde.spawn(T.Kind.WICHTEL if k % 4 != 3 else T.Kind.RENNER, battle.arena.safe_spawn(spot, 0.45))
		if i >= 0:
			battle.horde._appear[i] = 1.0
			battle.horde._hp[i] = 400.0


func _tick() -> void:
	battle.hero.invulnerable = 0.11
	if _silent:
		battle.shotgun.shells = 0
		battle.shotgun.reload_left = 1000.0
	battle.tick(DT)
	if battle.paused():
		battle.progression.choose(0)
	await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/%s.png" % name)
	print("saved ", name)
