extends Control

# HUD of stage 2, Teil B (Druck) in the brawl kit; reads scripts/enemies/
# pressure.gd and never changes game state:
#   banner - "WELLE!", "EINKESSELUNG!", "CHAMPION!", "MOORKÖNIG", "ENDWELLE!",
#            "SIEG!" pop in under the top bar and fade
#   arrow  - at the screen edge towards an incoming wave (danger), the gap of
#            an encircle ring (info) or a champion off-screen (loot)
#   boss   - Moorkönig bar under the top bar (after Mawlings hud_top boss bar)
#   elite  - gold health bars over champion Brocken

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const PT := preload("res://scripts/enemies/pressure_tuning.gd")

const BANNER_LIFE := 2.4
const EDGE := 74.0

var pressure: Node
var _clock := 0.0
var _boss_seen := -1.0


var _banner_layer: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The banner fades as a whole: own child item with its own modulate.
	_banner_layer = Control.new()
	_banner_layer.name = "Banner"
	_banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner_layer)
	_banner_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner_layer.draw.connect(_draw_banner)


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()
	if pressure != null:
		var age: float = pressure.banner_age
		_banner_layer.modulate.a = clampf((BANNER_LIFE - age) / 0.4, 0.0, 1.0) * clampf(age / 0.12, 0.0, 1.0)
		# Stage 4: the result screen (GEFALLEN / SIEG!) has its own ribbon.
		var battle: Node = pressure.battle
		if battle != null and battle.run != null and battle.run.dead:
			_banner_layer.modulate.a *= clampf(1.0 - float(battle.run.since_death) / 0.8, 0.0, 1.0)
		if age < BANNER_LIFE + 0.1:
			_banner_layer.queue_redraw()


func _draw() -> void:
	if pressure == null or pressure.hero == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_draw_elite_bars(camera)
		_draw_arrow(camera)
	_draw_boss_bar()


# ---------------------------------------------------------------- banner

func _draw_banner() -> void:
	if pressure == null:
		return
	var age: float = pressure.banner_age
	if age >= BANNER_LIFE or String(pressure.banner) == "":
		return
	var pop := clampf(age / 0.18, 0.0, 1.0)
	var grow := 1.0 + 0.35 * (1.0 - pop) * (1.0 - pop) + 0.04 * sin(_clock * 9.0) * (1.0 - age / BANNER_LIFE)
	var top := 300.0 if not pressure.boss_alive() and pressure.boss_state != pressure.Boss.ANNOUNCED else 370.0
	var w := 560.0 * grow
	var h := 104.0 * grow
	var rect := Rect2(Vector2(size.x * 0.5 - w * 0.5, top - h * 0.5), Vector2(w, h))
	Kit.ribbon(_banner_layer, rect, pressure.banner_tone)
	Kit.text_outlined(_banner_layer, rect.get_center() + Vector2(0, -4), String(pressure.banner), int(UiStyle.T_TITLE * grow), Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, w - 60.0)


# ---------------------------------------------------------------- edge arrow

func _draw_arrow(camera: Camera3D) -> void:
	var dir: Vector3 = pressure.arrow_dir
	if dir == Vector3.ZERO:
		return
	var hero_at: Vector3 = pressure.hero.global_position
	var from := camera.unproject_position(hero_at)
	var toward := camera.unproject_position(hero_at + dir * 6.0)
	var screen_dir := (toward - from).normalized()
	if screen_dir == Vector2.ZERO:
		return
	# Ray from the hero's screen point to the inset screen border.
	var top_room := 300.0 if pressure.boss_alive() else 210.0
	var inset := Rect2(Vector2(EDGE, top_room), size - Vector2(EDGE * 2.0, top_room + EDGE + 170.0))
	var t := INF
	if screen_dir.x > 0.001:
		t = minf(t, (inset.end.x - from.x) / screen_dir.x)
	elif screen_dir.x < -0.001:
		t = minf(t, (inset.position.x - from.x) / screen_dir.x)
	if screen_dir.y > 0.001:
		t = minf(t, (inset.end.y - from.y) / screen_dir.y)
	elif screen_dir.y < -0.001:
		t = minf(t, (inset.position.y - from.y) / screen_dir.y)
	if not is_finite(t) or t <= 0.0:
		return
	var at := from + screen_dir * t
	var tone: String = pressure.arrow_tone
	var beat := 0.5 + 0.5 * sin(_clock * 10.0)
	var bob := screen_dir * 12.0 * beat
	Kit.glow(self, at, 90.0, tone, 0.3 + 0.3 * beat)
	_big_arrow(at + bob, screen_dir, 1.0 + 0.06 * beat, tone)
	var label: String = pressure.arrow_label
	if label != "":
		var label_at := at - screen_dir * 135.0
		var font_size := UiStyle.T_LABEL + 2
		var width := UiStyle.number_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 34.0
		var chip := Rect2(label_at - Vector2(width * 0.5, 22.0), Vector2(width, 44.0))
		Kit.chip(self, chip, tone)
		Kit.text_outlined(self, chip.get_center(), label, font_size, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


## Bold brawl arrow (head + shaft) with ink outline and drop shadow; the tip
## sits at `tip` pointing along `dir`.
func _big_arrow(tip: Vector2, dir: Vector2, scale_by: float, tone: String) -> void:
	var colors: Dictionary = UiStyle.brawl_tone(tone)
	var side := Vector2(-dir.y, dir.x)
	var s := 46.0 * scale_by
	var shape := [Vector2(0, 0), Vector2(-1.15, 1.0), Vector2(-1.15, 0.42), Vector2(-2.1, 0.42),
		Vector2(-2.1, -0.42), Vector2(-1.15, -0.42), Vector2(-1.15, -1.0)]
	var pts := PackedVector2Array()
	for p: Vector2 in shape:
		pts.append(tip + dir * p.x * s + side * p.y * s)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 6))
	draw_colored_polygon(shadow, UiStyle.BRAWL_INK_SOFT)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, UiStyle.BRAWL_INK, 9.0, true)
	draw_colored_polygon(pts, colors["face"])
	# Light upper half for the brawl gloss.
	var gloss := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], tip + dir * -2.1 * s, tip + dir * -0.2 * s])
	draw_colored_polygon(gloss, Color(colors["light"], 0.55))


# ---------------------------------------------------------------- boss bar

func _draw_boss_bar() -> void:
	var announced: bool = pressure.boss_state == pressure.Boss.ANNOUNCED
	if not pressure.boss_alive() and not announced:
		_boss_seen = -1.0
		return
	if _boss_seen < 0.0:
		_boss_seen = _clock
	var t := _clock - _boss_seen
	# Slides in from the right with a small overshoot (Mawlings boss bar).
	var k := clampf(t / 0.45, 0.0, 1.0)
	var back := 1.0 + 2.4 * pow(k - 1.0, 3.0) + 1.4 * pow(k - 1.0, 2.0)
	var rect := Rect2(Vector2(20.0, 196.0), Vector2(size.x - 40.0, 88.0))
	rect.position.x += (1.0 - back) * (size.x + 24.0)
	var danger: Dictionary = UiStyle.brawl_tone("danger")
	var beat := 0.5 + 0.5 * sin(_clock * 7.0)
	var boss: Node3D = pressure.boss
	var recovering: bool = boss != null and is_instance_valid(boss) and boss.state == boss.State.RECOVER
	if recovering:
		Kit.ring(self, rect.grow(6), UiStyle.R_L + 6.0, 6.0, Color(UiStyle.brawl_tone("loot")["face"], 0.35 + 0.5 * beat))
	elif t < 1.6:
		Kit.ring(self, rect.grow(5), UiStyle.R_L + 5.0, 5.0, Color(danger["face"], (1.0 - t / 1.6) * (0.3 + 0.55 * beat)))
	Kit.panel(self, rect, "dark", UiStyle.R_L)
	var plate := rect.size.y + 10.0
	var plate_c := Vector2(rect.position.x + plate * 0.5 - 6.0, rect.get_center().y)
	Kit.icon_plate(self, plate_c, plate, "danger", "square")
	_crown(Kit.plate_center(plate_c, plate), plate * 0.3)
	var x0 := plate_c.x + plate * 0.5 + 12.0
	var x1 := rect.end.x - 18.0
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 38.0), pressure.boss_title(), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT, x1 - x0 - 150.0)
	var fraction := 1.0
	var tag := ""
	if announced:
		fraction = clampf(1.0 - (PT.BOSS_AT - float(pressure.elapsed)) / PT.BOSS_WARNING, 0.0, 1.0)
		tag = "ERWACHT"
	elif boss != null and is_instance_valid(boss):
		fraction = clampf(boss.health / boss.max_health, 0.0, 1.0)
		if recovering:
			tag = "JETZT ANGREIFEN"
	if tag != "":
		var tw := UiStyle.number_font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 34.0
		var tag_rect := Rect2(Vector2(x1 - tw, rect.position.y + 10.0), Vector2(tw, 34.0))
		Kit.chip(self, tag_rect, "loot" if recovering else "danger")
		Kit.text_outlined(self, tag_rect.get_center(), tag, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	elif boss != null and is_instance_valid(boss):
		var numbers := "%s / %s" % [Kit.format_int(int(ceil(boss.health))), Kit.format_int(int(boss.max_health))]
		Kit.number(self, Vector2(x1, rect.position.y + 36.0), numbers, UiStyle.T_LABEL, (danger["light"] as Color).lerp(Color.WHITE, 0.6), Kit.RIGHT)
	Kit.bar(self, Rect2(x0, rect.position.y + 50.0, x1 - x0, 28.0), fraction, "loot" if recovering else "danger")


func _crown(center: Vector2, r: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(-r, r * 0.6), center + Vector2(-r, -r * 0.5), center + Vector2(-r * 0.5, 0.0),
		center + Vector2(0.0, -r * 0.8), center + Vector2(r * 0.5, 0.0), center + Vector2(r, -r * 0.5),
		center + Vector2(r, r * 0.6)])
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 4))
	draw_colored_polygon(shadow, UiStyle.BRAWL_INK_SOFT)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, UiStyle.BRAWL_INK, 6.0, true)
	draw_colored_polygon(pts, Color("ffcf3f"))


# ---------------------------------------------------------------- champions

func _draw_elite_bars(camera: Camera3D) -> void:
	var horde: Node3D = pressure.horde
	var n: int = horde.count()
	# Teil E: the champion indices horde.gd collected this step.
	var list: PackedInt32Array = horde.get("elite_list") if horde.get("elite_list") != null else PackedInt32Array()
	for i in list:
		if i >= n or not horde.is_elite(i):
			continue
		var p: Vector3 = horde.position_of(i)
		if camera.is_position_behind(p):
			continue
		var at := camera.unproject_position(p + Vector3.UP * 3.0)
		if not Rect2(Vector2.ZERO, size).grow(60.0).has_point(at):
			continue
		var share: float = clampf(horde.health_of(i) / horde.max_health_of(i), 0.0, 1.0)
		# Same spot as the Brocken bar of hud.gd (drawn over it).
		var bar := Rect2(at - Vector2(55, 9), Vector2(110, 18))
		Kit.bar(self, bar.grow(2.0), share, "loot")
		_crown(at + Vector2(-70.0, 0.0), 13.0)
