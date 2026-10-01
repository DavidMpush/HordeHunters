extends Control

# HUD of stage 1 in the brawl kit (scripts/ui/ui_kit_brawl.gd):
#   top      - hero health bar, run timer, kill counter
#   overhead - small health bar over Brann with two shell pips (reload fill)
#   Brocken  - health bars over damaged Brocken
#   numbers  - damage numbers (after Mawlings hud_damage.gd, push based: one
#              number per enemy and shot, kills gold and bigger)
#   vignette - red edge flash on a hit, pulse at low health
#   result   - GEFALLEN: time, kills, NOCHMAL
# Reads everything from battle.gd; never changes game state.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const T := preload("res://scripts/core/tuning.gd")
const RUN := preload("res://scripts/core/run.gd")

const POP_LIFE := 0.75
const POP_RISE := 70.0
const MAX_POPUPS := 36
const RESULT_DELAY := 0.9
const NORMAL := Color("fff6e8")
const KILL := Color("ffd23c")
const HEAVY := Color("ff9a3c")

var battle: Node
var popups: Array[Dictionary] = []
var hurt_flash := 0.0
var _jitter := 0
var _clock := 0.0
var _top: Control
var _overlay: Control
var _top_key := []
var _overlay_shown := false


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
	if amount < 0.5:
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
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.5)
	for index in range(popups.size() - 1, -1, -1):
		popups[index].age += delta
		if float(popups[index].age) >= POP_LIFE:
			popups.remove_at(index)
	queue_redraw()
	if battle != null and battle.hero != null:
		var key := [int(ceil(battle.hero.health)), int(battle.run.elapsed), battle.run.kills, size]
		if key != _top_key:
			_top_key = key
			_top.queue_redraw()
	if result_visible() or _overlay_shown:
		_overlay_shown = result_visible()
		_overlay.queue_redraw()


## NOCHMAL button of the result screen (900 x 1600 base, centred vertically).
func result_button_rect() -> Rect2:
	var top := (size.y - 1600.0) * 0.5
	return Rect2(Vector2(size.x * 0.5 - 290.0, top + 1110.0), Vector2(580.0, 136.0))


func result_visible() -> bool:
	return battle != null and battle.run.dead and battle.run.since_death >= RESULT_DELAY


func _draw() -> void:
	if battle == null or battle.hero == null:
		return
	var camera := get_viewport().get_camera_3d()
	_draw_vignette()
	if camera != null:
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
	var kills := Rect2(size.x - 20.0 - 196.0, 26, 196, 76)
	Kit.pill(c, kills, "dark")
	_skull(c, Vector2(kills.position.x + 44.0, kills.get_center().y), 20.0)
	Kit.number(c, Vector2(kills.end.x - 26.0, kills.get_center().y + 2.0), battle.run.kills, UiStyle.T_HEAD, Color.WHITE, Kit.RIGHT | Kit.MIDDLE)


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
	for k in T.GUN_SHELLS:
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


func _draw_brocken_bars(camera: Camera3D) -> void:
	var horde: Node3D = battle.horde
	var max_hp := float(T.enemy(T.Kind.BROCKEN).hp)
	for i in horde.count():
		if horde.kind_of(i) != T.Kind.BROCKEN:
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
	if not result_visible():
		return
	var appear := clampf((battle.run.since_death - RESULT_DELAY) / 0.3, 0.0, 1.0)
	Kit.dim(c, Rect2(Vector2.ZERO, size), 0.72 * appear)
	if appear < 0.05:
		return
	var top := (size.y - 1600.0) * 0.5
	var rise := (1.0 - appear) * 60.0
	var cx := size.x * 0.5
	var ribbon := Rect2(Vector2(cx - 280.0, top + 360.0 + rise), Vector2(560.0, 112.0))
	Kit.ribbon(c, ribbon, "danger")
	Kit.text_outlined(c, ribbon.get_center() + Vector2(0, -4), "GEFALLEN", UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var panel := Rect2(Vector2(cx - 330.0, top + 530.0 + rise), Vector2(660.0, 450.0))
	Kit.panel(c, panel)
	var run: RefCounted = battle.run
	_stat_row(c, Rect2(panel.position + Vector2(36, 40), Vector2(panel.size.x - 72, 110)), "ZEIT", RUN.clock(run.elapsed), "info")
	_stat_row(c, Rect2(panel.position + Vector2(36, 170), Vector2(panel.size.x - 72, 110)), "KILLS", Kit.format_int(run.kills), "loot")
	var detail := "Wichtel %d  ·  Renner %d  ·  Brocken %d" % [run.kills_by_kind[0], run.kills_by_kind[1], run.kills_by_kind[2]]
	Kit.paragraph(c, Vector2(panel.position.x + 36, panel.position.y + 330), detail, panel.size.x - 72, UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, true, Kit.CENTER, 1)
	var shots := "Schüsse %d  ·  Schaden %d" % [run.shots, int(run.damage_dealt)]
	Kit.paragraph(c, Vector2(panel.position.x + 36, panel.position.y + 390), shots, panel.size.x - 72, UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)
	var button := result_button_rect()
	button.position.y += rise
	var pulse := 1.0 + 0.03 * sin(_clock * 5.0)
	var shown := Rect2(button.get_center() - button.size * pulse * 0.5, button.size * pulse)
	Kit.button(c, shown, "action")
	Kit.text_outlined(c, Kit.button_label_center(shown), "NOCHMAL", UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.paragraph(c, Vector2(cx - 300.0, button.end.y + 34.0), "Tippen · Enter · R", 600.0, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)


func _stat_row(c: CanvasItem, rect: Rect2, label: String, value: String, tone: String) -> void:
	Kit.well(c, rect, UiStyle.R_M)
	Kit.text_outlined(c, Vector2(rect.position.x + 28, rect.get_center().y), label, UiStyle.T_HEAD, UiStyle.brawl_tone(tone)["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	Kit.number(c, Vector2(rect.end.x - 28, rect.get_center().y + 2), value, UiStyle.T_TITLE, Color.WHITE, Kit.RIGHT | Kit.MIDDLE)
