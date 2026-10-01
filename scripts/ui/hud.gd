extends Control

# HUD of stage 1 in the brawl kit (scripts/ui/ui_kit_brawl.gd):
#   top      - hero health bar, run timer, kill counter
#   overhead - small health bar over Brann with two shell pips (reload fill)
#   Brocken  - health bars over damaged Brocken
#   numbers  - damage numbers (after Mawlings hud_damage.gd, push based: one
#              number per enemy and shot, kills gold and bigger)
#   vignette - red edge flash on a hit, pulse at low health
#   result   - GEFALLEN: time, kills, level, the build ("DEIN BUILD") and
#              damage per source, NOCHMAL (stage 2), MENÜ (stage 3)
#   stage 2  - XP bar with level and gold counter under the top row, price
#              pills over cocoons
#   stage 4  - SIEG! result after the last world's boss (run.won), the world
#              reached under the ribbon, black fade of the portal transition
# Reads everything from battle.gd; never changes game state.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const T := preload("res://scripts/core/tuning.gd")
const RUN := preload("res://scripts/core/run.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const CHESTS := preload("res://scripts/progression/chests.gd")
const SESSION := preload("res://scripts/core/session.gd")
const BIOMES := preload("res://scripts/world/biomes.gd")

const POP_LIFE := 0.75
const POP_RISE := 70.0
const MAX_POPUPS := 36
const RESULT_DELAY := 0.9
## Stage 4: a won run shows its result a little later (the last boss sinks).
const RESULT_DELAY_WIN := 1.8
const RESULT_PANEL_Y := 152.0
const NORMAL := Color("fff6e8")
const KILL := Color("ffd23c")
const HEAVY := Color("ff9a3c")
## Stage 3: room at the top right for the pause button (ui/pause_screen.gd).
const PAUSE_SLOT := 96.0
## Result buttons: MENÜ (left) and NOCHMAL (right) in one row.
const RESULT_MENU_W := 250.0
const RESULT_AGAIN_W := 430.0
const RESULT_GAP := 20.0

var battle: Node
var popups: Array[Dictionary] = []
var hurt_flash := 0.0
var _jitter := 0
var _clock := 0.0
var _top: Control
var _overlay: Control
var _top_key := []
var _overlay_shown := false
var _fade_shown := false
var _evolved_hooked := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The top bar only repaints when a shown value changes; the result sits on
	# top of everything (its own layer).
	_top = _layer("Top", _draw_top)
	_overlay = _layer("Result", _draw_result)


func _layer(layer_name: String, painter: Callable) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(func() -> void:
		if battle != null and battle.hero != null:
			painter.call(layer))
	return layer


func add_damage(at: Vector3, amount: float, kind: int, killed: bool) -> void:
	if amount < 0.5 or not SESSION.flag("damage_numbers"):
		return
	if popups.size() >= MAX_POPUPS:
		popups.pop_front()
	_jitter += 1
	var jitter := Vector2(fposmod(float(_jitter) * 0.618034, 1.0) * 90.0 - 45.0, fposmod(float(_jitter) * 0.381966, 1.0) * 36.0 - 18.0)
	var tint := KILL if killed else (HEAVY if kind == T.Kind.BROCKEN else NORMAL)
	var size := 34 if not killed else 44
	if amount >= 30.0:
		size += 10
	popups.append({"at": at + Vector3.UP * 1.3, "text": str(int(round(amount))), "age": 0.0, "color": tint, "size": size, "jitter": jitter})


## strength 0..1 (a Brocken slam is 1, a Wichtel bite about 0.6).
func flash_hurt(strength: float = 1.0) -> void:
	hurt_flash = maxf(hurt_flash, clampf(strength, 0.0, 1.0))


func clear() -> void:
	popups.clear()
	hurt_flash = 0.0


func _process(delta: float) -> void:
	_clock += delta
	_hook_evolved()
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.5)
	for index in range(popups.size() - 1, -1, -1):
		popups[index].age += delta
		if float(popups[index].age) >= POP_LIFE:
			popups.remove_at(index)
	queue_redraw()
	if battle != null and battle.hero != null:
		var key := [int(ceil(battle.hero.health)), int(ceil(battle.hero.max_health)), int(battle.run.elapsed), battle.run.kills, size, battle.run.level, int(battle.run.xp_share() * 200.0), battle.run.gold]
		if key != _top_key:
			_top_key = key
			_top.queue_redraw()
	var fading := _fade() > 0.0
	if result_visible() or _overlay_shown or fading or _fade_shown:
		_overlay_shown = result_visible()
		_fade_shown = fading
		_overlay.queue_redraw()


## NOCHMAL button of the result screen (900 x 1600 base, centred vertically):
## right part of the button row under the panel.
func result_button_rect() -> Rect2:
	var left := size.x * 0.5 - (RESULT_MENU_W + RESULT_GAP + RESULT_AGAIN_W) * 0.5
	return Rect2(Vector2(left + RESULT_MENU_W + RESULT_GAP, _result_buttons_y()), Vector2(RESULT_AGAIN_W, 136.0))


## Stage 3: MENÜ button left of NOCHMAL (back to the title screen).
func result_menu_rect() -> Rect2:
	var left := size.x * 0.5 - (RESULT_MENU_W + RESULT_GAP + RESULT_AGAIN_W) * 0.5
	return Rect2(Vector2(left, _result_buttons_y()), Vector2(RESULT_MENU_W, 136.0))


func _result_buttons_y() -> float:
	var top := (size.y - 1600.0) * 0.5
	return minf(_result_top() + RESULT_PANEL_Y + result_panel_height() + 44.0, top + 1600.0 - 136.0 - 80.0)


# Top of the result block (ribbon), centred vertically on the 1600 base.
func _result_top() -> float:
	var total := RESULT_PANEL_Y + result_panel_height() + 44.0 + 136.0 + 60.0
	return (size.y - 1600.0) * 0.5 + maxf(70.0, (1600.0 - total) * 0.5)


## Height of the result panel: tiles, the build rows, the damage rows.
func result_panel_height() -> float:
	if battle == null or battle.run == null:
		return 600.0
	var build: Array = battle.progress.build_summary() if battle.get("progress") != null else []
	var rows := ceili(float(mini(build.size(), 15)) / 3.0) if not build.is_empty() else 0
	var build_h := float(rows) * 86.0 if rows > 0 else 60.0
	var sources: int = clampi(battle.run.damage_by_source.size(), 1, 4)
	return 30.0 + 132.0 + 52.0 + 34.0 + build_h + 44.0 + 34.0 + float(sources) * 58.0 + 20.0


func result_visible() -> bool:
	return battle != null and battle.run.dead and battle.run.since_death >= _result_delay()


func _result_delay() -> float:
	return RESULT_DELAY_WIN if battle != null and bool(battle.run.get("won")) else RESULT_DELAY


## Stage 4 Teil A: black screen of the portal transition (worlds.gd), 0..1.
func _fade() -> float:
	if battle == null or battle.get("worlds") == null:
		return 0.0
	return float(battle.worlds.fade)


func _draw() -> void:
	if battle == null or battle.hero == null:
		return
	var camera := get_viewport().get_camera_3d()
	_draw_vignette()
	if camera != null:
		_draw_cocoon_tags(camera)
		_draw_brocken_bars(camera)
		_draw_overhead(camera)
		_draw_popups(camera)


# ---------------------------------------------------------------- top bar

func _draw_top(c: CanvasItem) -> void:
	var hero: Node3D = battle.hero
	var share: float = clampf(hero.health / hero.max_health, 0.0, 1.0)
	# Health: heart plate + bar + number.
	var panel := Rect2(20, 26, 318, 76)
	Kit.panel(c, panel, "dark", UiStyle.R_L, UiStyle.STROKE_M, true)
	_heart(c, Vector2(62, 62), 24.0)
	var low := share < 0.3
	var bar := Rect2(96, 45, 226, 38)
	Kit.bar(c, bar, share, "danger" if low else "action")
	Kit.number(c, bar.get_center() + Vector2(0, 1), int(ceil(hero.health)), UiStyle.T_LABEL + 4, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	# Timer.
	var clock := Rect2(size.x * 0.5 - 84.0, 26, 168, 76)
	Kit.pill(c, clock, "dark")
	Kit.number(c, clock.get_center() + Vector2(0, 2), RUN.clock(battle.run.elapsed), UiStyle.T_HEAD, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	# Kills.
	var kills := Rect2(size.x - 20.0 - PAUSE_SLOT - 196.0, 26, 196, 76)
	Kit.pill(c, kills, "dark")
	_skull(c, Vector2(kills.position.x + 44.0, kills.get_center().y), 20.0)
	Kit.number(c, Vector2(kills.end.x - 26.0, kills.get_center().y + 2.0), battle.run.kills, UiStyle.T_HEAD, Color.WHITE, Kit.RIGHT | Kit.MIDDLE)
	_draw_xp_row(c)


# Stage 2: XP bar with the level plate on its left end, gold counter right.
func _draw_xp_row(c: CanvasItem) -> void:
	var run: RefCounted = battle.run
	var gold := Rect2(size.x - 20.0 - 150.0, 118.0, 150.0, 56.0)
	var bar := Rect2(76.0, 128.0, gold.position.x - 16.0 - 76.0, 36.0)
	Kit.bar(c, bar, run.xp_share(), "info")
	var lv := Vector2(58.0, bar.get_center().y)
	Kit.disc(c, lv + Vector2(0, 4), 40.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(c, lv, 40.0, UiStyle.BRAWL_INK)
	var tone: Dictionary = UiStyle.brawl_tone("special")
	Kit.disc(c, lv, 35.0, tone["face"])
	Kit.disc(c, lv + Vector2(0, -6), 27.0, Color(tone["light"], 0.35))
	Kit.text_outlined(c, lv + Vector2(0, -21), "LV", UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.number(c, lv + Vector2(0, 8), run.level, UiStyle.T_HEAD, Color.WHITE, Kit.CENTER | Kit.MIDDLE)
	Kit.pill(c, gold, "dark")
	Icons.draw(c, "coin", Vector2(gold.position.x + 32.0, gold.get_center().y), 44.0)
	Kit.number(c, Vector2(gold.end.x - 22.0, gold.get_center().y + 2.0), run.gold, UiStyle.T_HEAD, Color("ffd65a"), Kit.RIGHT | Kit.MIDDLE)


func _heart(c: CanvasItem, center: Vector2, r: float) -> void:
	var tone: Dictionary = UiStyle.brawl_tone("danger")
	var pts := PackedVector2Array()
	for k in 32:
		var t := TAU * float(k) / 32.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(center + Vector2(x, y) * r / 16.0)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 4))
	c.draw_colored_polygon(shadow, UiStyle.BRAWL_INK_SOFT)
	var ring := pts.duplicate()
	ring.append(pts[0])
	c.draw_polyline(ring, UiStyle.BRAWL_INK, 7.0, true)
	c.draw_colored_polygon(pts, tone["face"])
	Kit.disc(c, center + Vector2(-r * 0.42, -r * 0.38), r * 0.2, Color(1, 1, 1, 0.55))


func _skull(c: CanvasItem, center: Vector2, r: float) -> void:
	Kit.disc(c, center + Vector2(0, 4), r + 3.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(c, center, r + 3.0, UiStyle.BRAWL_INK)
	Kit.disc(c, center, r, Color("f1ecff"))
	c.draw_rect(Rect2(center + Vector2(-r * 0.55, r * 0.5), Vector2(r * 1.1, r * 0.75)), Color("f1ecff"))
	c.draw_rect(Rect2(center + Vector2(-r * 0.62, r * 0.5), Vector2(r * 1.24, r * 0.82)), UiStyle.BRAWL_INK, false, 3.0)
	Kit.disc(c, center + Vector2(-r * 0.38, 0.0), r * 0.27, UiStyle.BRAWL_INK)
	Kit.disc(c, center + Vector2(r * 0.38, 0.0), r * 0.27, UiStyle.BRAWL_INK)


# ---------------------------------------------------------------- world-anchored

func _screen(camera: Camera3D, at: Vector3) -> Vector2:
	if camera.is_position_behind(at):
		return Vector2.INF
	return camera.unproject_position(at)


func _draw_overhead(camera: Camera3D) -> void:
	var hero: Node3D = battle.hero
	if hero.is_dead():
		return
	var at := _screen(camera, hero.global_position + Vector3.UP * 3.6)
	if not at.is_finite():
		return
	var share: float = clampf(hero.health / hero.max_health, 0.0, 1.0)
	var bar := Rect2(at - Vector2(78, 11), Vector2(110, 22))
	Kit.bar(self, bar, share, "danger" if share < 0.3 else "action")
	# Shell pips: loaded = red shell with brass cap; reload fills them back in.
	var gun: Node = battle.shotgun
	var progress: float = gun.reload_progress()
	for k in int(gun.max_shells()):
		var pip := Rect2(at + Vector2(40 + k * 22, -16), Vector2(17, 28))
		Kit.rrect(self, Rect2(pip.position + Vector2(0, 3), pip.size), 6.0, UiStyle.BRAWL_INK_SOFT)
		Kit.rrect(self, pip.grow(3.0), 8.0, UiStyle.BRAWL_INK)
		Kit.rrect(self, pip, 6.0, UiStyle.BRAWL_WELL)
		var loaded: bool = k < int(gun.shells)
		var fill := 1.0 if loaded else 0.0
		if progress >= 0.0:
			fill = clampf((progress - 0.3) / 0.55, 0.0, 1.0)
		if fill > 0.0:
			var h := pip.size.y * fill
			var body := Rect2(Vector2(pip.position.x, pip.end.y - h), Vector2(pip.size.x, h))
			Kit.rrect(self, body, 6.0, Color("e8362c"))
			var cap := Rect2(Vector2(pip.position.x, pip.end.y - minf(h, 9.0)), Vector2(pip.size.x, minf(h, 9.0)))
			Kit.rrect(self, cap, 4.0, Color("ffc84a"))
			Kit.rrect(self, Rect2(body.position + Vector2(4, 3), Vector2(5, maxf(0.0, body.size.y - 14.0))), 2.0, Color(1, 1, 1, 0.45))


# Price pill over closed cocoons (map: gold price, red when too expensive;
# dropped ones: GRATIS) and a fill ring while the hero stands in the ring.
func _draw_cocoon_tags(camera: Camera3D) -> void:
	var chests: Node3D = battle.get("chests")
	if chests == null:
		return
	var view := Rect2(Vector2.ZERO, size).grow(-10.0)
	for entry in chests.cocoons:
		if int(entry.state) != 0:
			continue
		var at := _screen(camera, entry.at + Vector3.UP * (3.2 * float(CHESTS.SIZE[entry.kind]) + 0.6))
		if not at.is_finite() or not view.has_point(at):
			continue
		var price: int = chests.price(entry)
		var label := "GRATIS" if price <= 0 else str(price)
		var afford: bool = price <= int(battle.run.gold)
		var tone: Variant = "dark" if afford else "danger"
		var font := UiStyle.number_font() if price > 0 else UiStyle.display_font()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_BODY).x + (70.0 if price > 0 else 36.0)
		var pill := Rect2(at - Vector2(w * 0.5, 24.0), Vector2(w, 48.0))
		Kit.pill(self, pill, tone, UiStyle.STROKE_S)
		if price > 0:
			Icons.draw(self, "coin", Vector2(pill.position.x + 26.0, pill.get_center().y), 34.0)
			Kit.number(self, Vector2(pill.end.x - 16.0, pill.get_center().y + 1.0), label, UiStyle.T_BODY, Color("ffd65a") if afford else Color.WHITE, Kit.RIGHT | Kit.MIDDLE)
		else:
			Kit.text_outlined(self, pill.get_center(), label, UiStyle.T_LABEL, UiStyle.brawl_tone("loot")["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		var hold := float(entry.hold) / CHESTS.HOLD_SECONDS
		if hold > 0.0 and not bool(entry.denied):
			Kit.bar(self, Rect2(pill.position + Vector2(8.0, pill.size.y + 6.0), Vector2(pill.size.x - 16.0, 14.0)), hold, "loot")


func _draw_brocken_bars(camera: Camera3D) -> void:
	var horde: Node3D = battle.horde
	var max_hp := float(T.enemy(T.Kind.BROCKEN).hp)
	for i in horde.count():
		if horde.kind_of(i) != T.Kind.BROCKEN:
			continue
		# Champions draw their own gold bar (hud_pressure.gd).
		if horde.has_method("is_elite") and horde.is_elite(i):
			continue
		var hp: float = horde.health_of(i)
		if hp >= max_hp:
			continue
		var at := _screen(camera, horde.position_of(i) + Vector3.UP * 2.2)
		if not at.is_finite() or not Rect2(Vector2.ZERO, size).grow(60.0).has_point(at):
			continue
		Kit.bar(self, Rect2(at - Vector2(55, 9), Vector2(110, 18)), hp / max_hp, "danger")


func _draw_popups(camera: Camera3D) -> void:
	for popup in popups:
		var at := _screen(camera, popup.at)
		if not at.is_finite():
			continue
		var t: float = float(popup.age) / POP_LIFE
		var pop := clampf(float(popup.age) / 0.1, 0.0, 1.0)
		var grow := lerpf(1.5, 1.0, pop)
		var alpha := clampf((1.0 - t) / 0.35, 0.0, 1.0)
		var where: Vector2 = at + popup.jitter - Vector2(0.0, POP_RISE * (1.0 - pow(1.0 - t, 2.0)))
		var tint: Color = popup.color
		UiStyle.text_px(self, String(popup.text), where, float(popup.size) * grow, Color(tint, alpha), true, 9)


# ---------------------------------------------------------------- overlays

func _draw_vignette() -> void:
	var hero: Node3D = battle.hero
	var share: float = clampf(hero.health / hero.max_health, 0.0, 1.0)
	var strength := hurt_flash * 0.55
	if share < 0.3 and not hero.is_dead():
		strength = maxf(strength, (0.18 + 0.12 * sin(_clock * 6.0)) * (1.0 - share / 0.3))
	if strength <= 0.01:
		return
	var red := Color(0.85, 0.05, 0.15, strength)
	var clear := Color(0.85, 0.05, 0.15, 0.0)
	var band := minf(size.x, size.y) * 0.22
	var w := size.x
	var h := size.y
	_band([Vector2(0, 0), Vector2(w, 0), Vector2(w - band, band), Vector2(band, band)], red, clear)
	_band([Vector2(0, h), Vector2(w, h), Vector2(w - band, h - band), Vector2(band, h - band)], red, clear)
	_band([Vector2(0, 0), Vector2(0, h), Vector2(band, h - band), Vector2(band, band)], red, clear)
	_band([Vector2(w, 0), Vector2(w, h), Vector2(w - band, h - band), Vector2(w - band, band)], red, clear)


func _band(pts: Array, edge: Color, inner: Color) -> void:
	draw_polygon(PackedVector2Array(pts), PackedColorArray([edge, edge, inner, inner]))


func _draw_result(c: CanvasItem) -> void:
	var black := _fade()
	if black > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.04, black))
	if not result_visible():
		return
	var appear := clampf((battle.run.since_death - _result_delay()) / 0.3, 0.0, 1.0)
	Kit.dim(c, Rect2(Vector2.ZERO, size), 0.78 * appear)
	if appear < 0.05:
		return
	var rise := (1.0 - appear) * 60.0
	var cx := size.x * 0.5
	var run: RefCounted = battle.run
	var ribbon := Rect2(Vector2(cx - 280.0, _result_top() + rise), Vector2(560.0, 112.0))
	var won := bool(run.get("won"))
	Kit.ribbon(c, ribbon, "loot" if won else "danger")
	Kit.text_outlined(c, ribbon.get_center() + Vector2(0, -4), "SIEG!" if won else "GEFALLEN", UiStyle.T_HERO, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	# Stage 4: how far the run came (world n of 3) under the ribbon.
	var reached := _world_line(won)
	if reached != "":
		Kit.text_outlined(c, Vector2(cx, ribbon.end.y + 20.0), reached, UiStyle.T_LABEL + 2, UiStyle.brawl_tone("loot" if won else "info")["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var panel := Rect2(Vector2(cx - 410.0, _result_top() + RESULT_PANEL_Y + rise), Vector2(820.0, result_panel_height()))
	Kit.panel(c, panel)
	var inner := panel.grow(-30.0)
	# Three tiles: time, kills, level.
	var tile_w := (inner.size.x - 2.0 * 16.0) / 3.0
	var tiles := [["ZEIT", RUN.clock(run.elapsed), "info"], ["KILLS", Kit.format_int(run.kills), "danger"], ["LEVEL", str(run.level), "special"]]
	for k in 3:
		var tile := Rect2(Vector2(inner.position.x + float(k) * (tile_w + 16.0), inner.position.y), Vector2(tile_w, 132.0))
		Kit.well(c, tile, UiStyle.R_M)
		Kit.text_outlined(c, Vector2(tile.get_center().x, tile.position.y + 32.0), tiles[k][0], UiStyle.T_LABEL, UiStyle.brawl_tone(tiles[k][2])["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		Kit.number(c, Vector2(tile.get_center().x, tile.position.y + 84.0), tiles[k][1], UiStyle.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, tile.size.x - 20.0)
	# Build.
	var y := inner.position.y + 132.0 + 52.0
	_section(c, Vector2(inner.position.x, y), "DEIN BUILD", "loot", inner.size.x)
	y += 34.0
	var build: Array = battle.progress.build_summary() if battle.get("progress") != null else []
	if build.is_empty():
		Kit.paragraph(c, Vector2(inner.position.x, y + 8.0), "Keine Upgrades gewählt", inner.size.x, UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)
		y += 60.0
	else:
		var cols := 3
		var chip_w := (inner.size.x - float(cols - 1) * 12.0) / float(cols)
		var chip_h := 74.0
		var rows := ceili(float(mini(build.size(), 15)) / float(cols))
		for index in mini(build.size(), 15):
			var col := index % cols
			var row := index / cols
			_build_chip(c, Rect2(Vector2(inner.position.x + float(col) * (chip_w + 12.0), y + float(row) * (chip_h + 12.0)), Vector2(chip_w, chip_h)), build[index])
		y += float(rows) * (chip_h + 12.0)
	# Damage per source.
	y += 44.0
	_section(c, Vector2(inner.position.x, y), "SCHADEN", "ember", inner.size.x)
	y += 34.0
	var sources: Array = run.damage_by_source.keys()
	sources.sort_custom(func(a, b): return float(run.damage_by_source[a]) > float(run.damage_by_source[b]))
	var best := 1.0
	for source in sources:
		best = maxf(best, float(run.damage_by_source[source]))
	if sources.is_empty():
		Kit.paragraph(c, Vector2(inner.position.x, y + 8.0), "Kein Schaden", inner.size.x, UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)
	for index in mini(sources.size(), 4):
		var source: String = sources[index]
		var amount := float(run.damage_by_source[source])
		var row := Rect2(Vector2(inner.position.x, y + float(index) * 58.0), Vector2(inner.size.x, 46.0))
		Kit.text_outlined(c, Vector2(row.position.x + 4.0, row.get_center().y), source, UiStyle.T_BODY, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, 220.0)
		Kit.bar(c, Rect2(Vector2(row.position.x + 236.0, row.position.y + 8.0), Vector2(row.size.x - 236.0 - 150.0, 30.0)), amount / best, "ember")
		Kit.number(c, Vector2(row.end.x - 4.0, row.get_center().y + 1.0), Kit.format_int(int(amount)), UiStyle.T_HEAD, Color.WHITE, Kit.RIGHT | Kit.MIDDLE, 140.0)
	var menu := result_menu_rect()
	menu.position.y += rise
	Kit.button(c, menu, "neutral")
	var menu_mid := Kit.button_label_center(menu)
	_home_glyph(c, Vector2(menu.position.x + 52.0, menu_mid.y + 2.0), 19.0)
	Kit.text_outlined(c, Vector2(menu.position.x + 160.0, menu_mid.y), "MENÜ", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, menu.size.x - 110.0)
	var button := result_button_rect()
	button.position.y += rise
	var pulse := 1.0 + 0.03 * sin(_clock * 5.0)
	var shown := Rect2(button.get_center() - button.size * pulse * 0.5, button.size * pulse)
	Kit.button(c, shown, "action")
	Kit.text_outlined(c, Kit.button_label_center(shown), "NOCHMAL", UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, shown.size.x - 40.0)
	Kit.paragraph(c, Vector2(cx - 340.0, button.end.y + 26.0), "Enter · R: nochmal   ·   M · Esc: Menü", 680.0, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)


# Stage 4 (Teil B signal): "EVOLUTION: <Name>" in the banner style of the
# pressure HUD when an evolution card was taken. Null-safe: connected once
# progression exists and has the signal.
func _hook_evolved() -> void:
	if _evolved_hooked or battle == null:
		return
	var progression: Node = battle.get("progression")
	if progression == null:
		return
	_evolved_hooked = true
	if progression.has_signal("evolved"):
		progression.connect("evolved", _on_evolved)


func _on_evolved(weapon_id: String) -> void:
	var pressure: Node = battle.get("pressure")
	if pressure == null or not pressure.has_method("_banner"):
		return
	var label := weapon_id.to_upper()
	var progress: RefCounted = battle.get("progress")
	if progress != null and progress.has_method("evolution_def"):
		label = String(progress.evolution_def(weapon_id).get("name", label)).to_upper()
	pressure._banner("EVOLUTION: %s" % label, "special")


# "WELT 2/3 · DÜRRSCHLUND" (death) or "ALLE 3 WELTEN BEZWUNGEN" (victory).
func _world_line(won: bool) -> String:
	if battle.get("worlds") == null:
		return ""
	if won:
		return "ALLE 3 WELTEN BEZWUNGEN"
	var index := int(battle.world_index)
	var biome := String(battle.worlds.biome_of(index))
	var title := String(BIOMES.get_data(biome).get("title", biome.to_upper()))
	return "WELT %d/3 · %s" % [index + 1, title]


# House glyph for the MENÜ button (roof, body, door).
func _home_glyph(c: CanvasItem, center: Vector2, r: float) -> void:
	var roof := PackedVector2Array([center + Vector2(-r * 1.25, -r * 0.1), center + Vector2(0, -r * 1.2), center + Vector2(r * 1.25, -r * 0.1)])
	var body := Rect2(center + Vector2(-r * 0.85, -r * 0.25), Vector2(r * 1.7, r * 1.25))
	Kit.rrect(c, body.grow(4.0), 6.0, UiStyle.BRAWL_INK)
	c.draw_polyline(roof, UiStyle.BRAWL_INK, 15.0, true)
	Kit.rrect(c, body, 4.0, Color.WHITE)
	c.draw_polyline(roof, Color.WHITE, 7.0, true)
	Kit.rrect(c, Rect2(center + Vector2(-r * 0.28, r * 0.35), Vector2(r * 0.56, r * 0.65)), 3.0, UiStyle.brawl_tone("neutral")["dark"])


# Section heading with a thin rule to the right.
func _section(c: CanvasItem, at: Vector2, label: String, tone: String, width: float) -> void:
	var w := Kit.text_outlined(c, at, label, UiStyle.T_HEAD, UiStyle.brawl_tone(tone)["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	Kit.rrect(c, Rect2(Vector2(at.x + w + 18.0, at.y - 2.0), Vector2(maxf(0.0, width - w - 18.0), 4.0)), 2.0, Color(UiStyle.brawl_tone(tone)["light"], 0.35))


# One build item: icon plate in the rarity colour, name, rank / stacks.
func _build_chip(c: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var rarity := String(item.get("rarity", "common"))
	var t: Dictionary = UiStyle.rarity_tone(rarity)
	Kit.well(c, rect, UiStyle.R_M)
	Kit.ring(c, rect, UiStyle.R_M, 3.0, Color(t["face"], 0.9))
	var plate := 58.0
	var pc := Vector2(rect.position.x + 10.0 + plate * 0.5, rect.get_center().y)
	Kit.icon_plate(c, pc, plate, rarity)
	Icons.draw(c, String(item.get("icon", "")), Kit.plate_center(pc, plate), plate * 0.74)
	var x0 := pc.x + plate * 0.5 + 10.0
	var width := rect.end.x - 10.0 - x0
	Kit.text_outlined(c, Vector2(x0, rect.position.y + 24.0), String(item.name), UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, width)
	var rank_text := "×%d" % int(item.rank)
	if String(item.type) == "stat":
		rank_text = "RANG %d" % int(item.rank)
	elif String(item.type) == "weapon":
		rank_text = "STUFE %d" % int(item.rank)
	if String(item.type) != "relic" and int(item.rank) >= int(item.max):
		rank_text = "MAX"
	Kit.text_outlined(c, Vector2(x0, rect.position.y + 54.0), rank_text, UiStyle.T_LABEL, t["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE, width)
	# Stage 4: evolved weapons carry an EVO mark.
	if bool(item.get("evolved", false)):
		var mark := Rect2(Vector2(rect.end.x - 66.0, rect.position.y + 40.0), Vector2(58.0, 28.0))
		Kit.chip(c, mark, "special")
		Kit.text_outlined(c, mark.get_center(), "EVO", UiStyle.T_LABEL - 4, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
