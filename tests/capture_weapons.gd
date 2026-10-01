extends SceneTree

# Review frames of the extra weapons (stage 3, Teil B §4) from the game camera
# (main.tscn, Brann with a silent shotgun so only the extra weapon acts):
#   preview_weapon_axe.png          - axes on their loop through a pack
#   preview_weapon_sword.png        - the sword whirl mid spin
#   preview_weapon_grenade_fly.png  - grenade in the air, landing ring
#   preview_weapon_grenade_boom.png - the explosion
#   preview_weapon_choice.png       - level-up with a NEUE WAFFE card
# Run with a window (never --headless): tools/capture.ps1 -Only weapons

const T := preload("res://scripts/core/tuning.gd")
const DT := 1.0 / 60.0

var main: Node
var battle: Node


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
	await _axe()
	await _sword()
	await _grenade()
	await _choice()
	print("Saved weapon review frames")
	quit()


func _axe() -> void:
	_give("axe", 3)
	_pack(Vector3(0.3, 0, -1), 5.0, 10)
	var axe: Node = battle.weapon_of("axe")
	var throws: int = axe.throws
	for k in 180:
		await _tick()
		if axe.throws > throws:
			break
	for k in 16:
		await _tick()
	await _save("preview_weapon_axe")
	_drop("axe")


func _sword() -> void:
	_give("sword", 3)
	_pack(Vector3(-0.5, 0, -1), 2.2, 9)
	var sword: Node = battle.weapon_of("sword")
	var spins: int = sword.spins
	for k in 240:
		await _tick()
		if sword.spins > spins:
			break
	for k in 6:
		await _tick()
	await _save("preview_weapon_sword")
	_drop("sword")


func _grenade() -> void:
	_give("grenade", 1)
	_pack(Vector3(0.6, 0, -1), 6.0, 12)
	var grenade: Node = battle.weapon_of("grenade")
	var throws: int = grenade.throws
	for k in 240:
		await _tick()
		if grenade.throws > throws:
			break
	for k in 20:
		await _tick()
	await _save("preview_weapon_grenade_fly")
	var booms: int = grenade.explosions
	for k in 60:
		await _tick()
		if grenade.explosions > booms:
			break
	for k in 3:
		await _tick()
	await _save("preview_weapon_grenade_boom")
	_drop("grenade")


func _choice() -> void:
	battle.horde.clear()
	var progress: RefCounted = battle.progress
	battle.run.add_xp(float(battle.run.xp_needed(battle.run.level)))
	battle.tick(DT)
	var progression: Node = battle.progression
	progression.offers = [progress.weapon_entry("axe", "rare"), progress.own_weapon_entry("epic"), progress.weapon_entry("grenade", "common")]
	progression.choice.offers = progression.offers
	for k in 40:
		await process_frame
	await _save("preview_weapon_choice")
	progression.choose(0)


func _give(id: String, rank: int) -> void:
	var progress: RefCounted = battle.progress
	for k in rank:
		progress.apply(progress.weapon_entry(id, "common"))
	battle.sync_weapons()


func _drop(id: String) -> void:
	battle.progress.weapons.erase(id)
	battle.sync_weapons()
	battle.horde.clear()


func _pack(direction: Vector3, distance: float, count: int) -> void:
	var at: Vector3 = battle.hero.position
	var dir := direction.normalized()
	for k in count:
		var spot := at + dir * (distance + 0.6 * float(k % 3)) + Vector3(-dir.z, 0, dir.x) * (float(k / 3) - 1.5) * 0.9
		var i: int = battle.horde.spawn(T.Kind.WICHTEL if k % 4 != 3 else T.Kind.RENNER, battle.arena.safe_spawn(spot, 0.45))
		if i >= 0:
			battle.horde._appear[i] = 1.0
			battle.horde._hp[i] = 60.0


func _tick() -> void:
	battle.hero.invulnerable = 0.11
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
