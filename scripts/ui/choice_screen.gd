extends Control

# 1-of-3 choice (stage 2, Teil A §2-3) in the brawl kit, after Mawlings
# mutation_screen.gd (stack layout): ribbon ("LEVEL-UP!" / "KOKON!"), three
# wide cards coloured by rarity (rim, header, chip), a NEU WÜRFELN button
# (one reroll per run) and a hint. The run is paused while it is open
# (battle.paused()); progression owns the logic, this only draws and reports
# taps (card, reroll) back to progression.choose()/reroll().
# Input: tap/click a card, keys 1-3; reroll button or key N.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Icons := preload("res://scripts/ui/icons.gd")

const SIDE := 36.0
const CARD_H := 250.0
const GAP := 30.0
const HEADER := 62.0
const RIBBON := Vector2(560.0, 112.0)
const CARD_IN := 0.24
const STAGGER := 0.07
const DIM_IN := 0.15
const CLOSE_OUT := 0.22
## Taps right after opening are ignored (a finger still on the stick).
const GUARD := 0.3
const TYPE_TAB := {"stat": "WERT", "shotgun": "WAFFE", "weapon": "WAFFE", "new_weapon": "NEUE WAFFE", "relic": "RELIKT", "gold": "GOLD"}
const CHEST_TITLE := {"map": "KOKON!", "free": "ELITE-KOKON!", "boss": "BOSS-KOKON!"}

var progression: Node
var mode := ""              # "level" or "chest"
var kind := ""              # cocoon kind in chest mode
var offers: Array = []
var level := 1
var rerolls := 0
var _open := false
var _clock := 0.0
var _opened_at := -10.0
var _closed_at := -10.0
var _dealt_at := -10.0
var _key := []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


func open(new_mode: String, new_offers: Array, info: Dictionary = {}) -> void:
	mode = new_mode
	offers = new_offers
	kind = String(info.get("kind", ""))
	level = int(info.get("level", 1))
	rerolls = int(info.get("rerolls", 0))
	if not _open:
		_opened_at = _clock
	_dealt_at = _clock
	_open = true
	queue_redraw()


## New cards after a reroll (same screen, cards deal in again).
func redeal(new_offers: Array, rerolls_left: int) -> void:
	offers = new_offers
	rerolls = rerolls_left
	_dealt_at = _clock
	queue_redraw()


func close() -> void:
	if _open:
		_closed_at = _clock
	_open = false
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	var animating := (_open and _clock - _dealt_at < 1.0) or (not _open and _clock - _closed_at < CLOSE_OUT + 0.05)
	var key := [_open, offers.size(), rerolls, size, int(_clock * 30.0) if animating or _has_legendary() else 0]
	if key != _key:
		_key = key
		queue_redraw()


func _has_legendary() -> bool:
	for entry in offers:
		if String(entry.get("rarity", "")) == "legendary":
			return _open
	return false


# ---------------------------------------------------------------- geometry

func _top() -> float:
	return (size.y - 1600.0) * 0.5


func card_rect(slot: int) -> Rect2:
	var count := maxi(1, offers.size())
	var total := float(count) * CARD_H + float(count - 1) * GAP
	var y0 := _top() + 470.0 + (3.0 * CARD_H + 2.0 * GAP - total) * 0.5
	return Rect2(Vector2(SIDE, y0 + float(slot) * (CARD_H + GAP)), Vector2(size.x - 2.0 * SIDE, CARD_H))


func reroll_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 230.0, _top() + 1350.0), Vector2(460.0, 112.0))


func _ribbon_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - RIBBON.x * 0.5, _top() + 250.0), RIBBON)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not _open or progression == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var number := -1
		match event.keycode:
			KEY_1, KEY_KP_1:
				number = 0
			KEY_2, KEY_KP_2:
				number = 1
			KEY_3, KEY_KP_3:
				number = 2
			KEY_N:
				progression.reroll()
				get_viewport().set_input_as_handled()
				return
		if number >= 0 and number < offers.size():
			progression.choose(number)
			get_viewport().set_input_as_handled()
		return
	var at := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		at = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		at = event.position
	if at == Vector2.INF or _clock - _opened_at < GUARD:
		return
	tap(at)
	get_viewport().set_input_as_handled()


## A tap at `at` (screen px): card -> choose, reroll button -> reroll.
func tap(at: Vector2) -> void:
	for slot in offers.size():
		if card_rect(slot).has_point(at):
			progression.choose(slot)
			return
	if rerolls > 0 and reroll_rect().grow(8.0).has_point(at):
		progression.reroll()


# ---------------------------------------------------------------- drawing

static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


static func _back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


func _draw() -> void:
	var dim := 0.0
	if _open:
		dim = _ease((_clock - _opened_at) / DIM_IN)
	else:
		dim = 1.0 - _ease((_clock - _closed_at) / CLOSE_OUT)
	if dim <= 0.0:
		return
	Kit.dim(self, Rect2(Vector2.ZERO, size), 0.66 * dim)
	if not _open:
		return
	_draw_title()
	for slot in offers.size():
		var t := (_clock - _dealt_at - STAGGER * float(slot)) / CARD_IN
		if t <= 0.0:
			continue
		var k := _back(t)
		var rect := card_rect(slot)
		var shift := (1.0 - k) * 220.0
		# Kit text helpers reset the canvas transform: cards draw in screen space.
		_draw_card(Rect2(rect.position + Vector2(shift, 0.0), rect.size), offers[slot])
	_draw_footer()


func _draw_title() -> void:
	var r := _ribbon_rect()
	var pop := _back((_clock - _opened_at) / 0.25)
	var grown := Rect2(r.get_center() - r.size * pop * 0.5, r.size * pop)
	var chest := mode == "chest"
	var tone := "loot" if chest else "special"
	Kit.glow(self, grown.grow(-8.0), 30.0, tone, 0.45)
	Kit.ribbon(self, grown, tone)
	var title := String(CHEST_TITLE.get(kind, "KOKON!")) if chest else "LEVEL-UP!"
	Kit.text_outlined(self, grown.get_center() + Vector2(0, -4), title, UiStyle.T_HERO if pop > 0.98 else UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, grown.size.x - 50.0)
	var sub := "WÄHLE 1 AUS %d" % offers.size()
	if not chest:
		sub = "LEVEL %d  ·  %s" % [level, sub]
	Kit.text_outlined(self, Vector2(size.x * 0.5, r.end.y + 44.0), sub, UiStyle.T_BODY + 4, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


func _draw_footer() -> void:
	var r := reroll_rect()
	var ready := rerolls > 0
	Kit.button(self, r, "info" if ready else "disabled")
	var mid := Kit.button_label_center(r)
	_reroll_glyph(Vector2(r.position.x + 58.0, mid.y), ready)
	Kit.text_outlined(self, Vector2(r.position.x + 260.0, mid.y), "NEU WÜRFELN", UiStyle.T_HEAD, Color.WHITE if ready else Color(1, 1, 1, 0.6), -1, -1, null, Kit.CENTER | Kit.MIDDLE, 300.0)
	Kit.badge(self, Vector2(r.end.x - 10.0, r.position.y + 6.0), str(rerolls), "danger" if ready else "neutral", UiStyle.T_LABEL)
	Kit.text_outlined(self, Vector2(size.x * 0.5, r.end.y + 52.0), "KARTE ANTIPPEN ZUM WÄHLEN", UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


func _reroll_glyph(center: Vector2, ready: bool) -> void:
	var tint := Color.WHITE if ready else Color(1, 1, 1, 0.6)
	var pts := PackedVector2Array()
	for k in 19:
		var a := lerpf(-PI * 0.15, PI * 1.45, float(k) / 18.0)
		pts.append(center + Vector2(cos(a), sin(a)) * 24.0)
	draw_polyline(pts, UiStyle.BRAWL_INK, 15.0, true)
	draw_polyline(pts, tint, 7.0, true)
	var tip := pts[pts.size() - 1]
	var head := PackedVector2Array([tip + Vector2(-14, -4), tip + Vector2(10, -12), tip + Vector2(4, 12)])
	draw_colored_polygon(head, tint)


# One wide card: rarity rim, kit card with a header (name + rarity chip),
# a type tab on the top edge, icon plate left, value/text right, rank pips.
func _draw_card(rect: Rect2, entry: Dictionary) -> void:
	var rarity := String(entry.get("rarity", "common"))
	var t: Dictionary = UiStyle.rarity_tone(rarity)
	if rarity != "common":
		if rarity == "legendary" or rarity == "epic":
			Kit.glow(self, rect.grow(6.0), 26.0, rarity, 0.4 + 0.15 * sin(_clock * 3.0))
		Kit.rrect(self, rect.grow(12.0), UiStyle.R_L + 12.0, Color(t["light"], 0.3))
		Kit.ring(self, rect.grow(9.0), UiStyle.R_L + 9.0, 6.0, t["face"])
	Kit.card(self, rect, rarity, "normal", HEADER)
	var inset := UiStyle.STROKE_L + 7.0
	var head := Rect2(rect.position + Vector2(inset, inset), Vector2(rect.size.x - 2.0 * inset, HEADER))
	var body := Rect2(rect.position + Vector2(inset, inset + HEADER), Vector2(rect.size.x - 2.0 * inset, rect.size.y - 2.0 * inset - HEADER))
	# Rarity chip right in the header, name left.
	var chip_label := UiStyle.rarity_name(rarity)
	var font := UiStyle.display_font()
	var chip_w := font.get_string_size(chip_label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 30.0
	var chip := Rect2(Vector2(head.end.x - 12.0 - chip_w, head.get_center().y - 21.0), Vector2(chip_w, 42.0))
	Kit.chip(self, chip, rarity)
	Kit.text_outlined(self, chip.get_center() + Vector2(0, -1), chip_label, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var title_x := head.position.x + 18.0
	Kit.text_outlined(self, Vector2(title_x, head.get_center().y), String(entry.name).to_upper(), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, chip.position.x - 16.0 - title_x)
	# Icon plate.
	var plate := 124.0
	var pc := Vector2(body.position.x + 22.0 + plate * 0.5, body.get_center().y + 2.0)
	Kit.icon_plate(self, pc, plate, rarity)
	Icons.draw(self, String(entry.get("icon", "")), Kit.plate_center(pc, plate), plate * 0.78)
	var type := String(entry.get("type", ""))
	if (type == "relic" and int(entry.get("from", 0)) == 0) or type == "new_weapon":
		Kit.badge(self, pc + Vector2(plate * 0.38, -plate * 0.42), "NEU", "loot", UiStyle.T_LABEL)
	var x0 := pc.x + plate * 0.5 + 26.0
	var width := body.end.x - 22.0 - x0
	match type:
		"stat":
			_value_line(Vector2(x0, body.position.y + 46.0), String(entry.before), String(entry.after), t, width)
			Kit.paragraph(self, Vector2(x0, body.position.y + 104.0), String(entry.label), width, UiStyle.T_BODY, Color.WHITE, true, Kit.LEFT, 1)
		"shotgun", "weapon", "new_weapon":
			var line := "RANG %d → %d" % [int(entry.from), int(entry.to)]
			if type == "new_weapon":
				line = "NEUE WAFFE"
			Kit.text_outlined(self, Vector2(x0, body.position.y + 40.0), line, UiStyle.T_HEAD, t["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE, width)
			Kit.paragraph(self, Vector2(x0, body.position.y + 78.0), String(entry.text), width, UiStyle.T_BODY, Color.WHITE, true, Kit.LEFT, 2)
		"relic":
			Kit.paragraph(self, Vector2(x0, body.position.y + 34.0), String(entry.text), width, UiStyle.T_BODY, Color.WHITE, true, Kit.LEFT, 2)
			if int(entry.from) > 0:
				Kit.text_outlined(self, Vector2(x0, body.end.y - 30.0), "STAPEL %d → %d" % [int(entry.from), int(entry.to)], UiStyle.T_LABEL, t["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE)
		_:
			Kit.paragraph(self, Vector2(x0, body.position.y + 40.0), String(entry.text), width, UiStyle.T_BODY, Color.WHITE, true, Kit.LEFT, 2)
	if type in ["stat", "shotgun", "weapon", "new_weapon"]:
		_pips(Vector2(body.end.x - 22.0, body.end.y - 28.0), int(entry.from), int(entry.to), t)
	# Type tab on the top edge.
	var tab_label := String(TYPE_TAB.get(type, ""))
	if tab_label != "":
		var tw := font.get_string_size(tab_label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 32.0
		var tab := Rect2(Vector2(rect.position.x + 26.0, rect.position.y - 20.0), Vector2(tw, 36.0))
		Kit.pill(self, tab, "dark", UiStyle.STROKE_S)
		Kit.text_outlined(self, tab.get_center() + Vector2(0, -1), tab_label, UiStyle.T_LABEL, t["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)


# "+8 % → +16 %": before dimmed, arrow in the rarity tone, after big.
func _value_line(at: Vector2, before: String, after: String, t: Dictionary, width: float) -> void:
	var nf := UiStyle.number_font()
	var w_before := nf.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_HEAD).x
	var w_arrow := nf.get_string_size("→", HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_HEAD).x
	var w_after := nf.get_string_size(after, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_TITLE).x
	var gap := 14.0
	var total := w_before + w_arrow + w_after + gap * 2.0
	var k := minf(1.0, width / total)
	var x := at.x
	x += Kit.number(self, Vector2(x, at.y), before, UiStyle.T_HEAD, UiStyle.BRAWL_TEXT_DIM, Kit.LEFT | Kit.MIDDLE, w_before * k) + gap * k
	x += Kit.text_outlined(self, Vector2(x, at.y), "→", UiStyle.T_HEAD, t["light"], -1, -1, nf, Kit.LEFT | Kit.MIDDLE, w_arrow * k) + gap * k
	Kit.number(self, Vector2(x, at.y), after, UiStyle.T_TITLE, Color.WHITE, Kit.LEFT | Kit.MIDDLE, w_after * k)


# Five rank pips right-aligned at `right`: owned filled, new ones in the
# rarity colour, the rest empty wells.
func _pips(right: Vector2, from: int, to: int, t: Dictionary) -> void:
	var r := 11.0
	var step := 30.0
	for k in 5:
		var center := right + Vector2(-(4 - k) * step - r, 0.0)
		Kit.disc(self, center, r + 3.0, UiStyle.BRAWL_INK)
		var fill: Color = UiStyle.BRAWL_WELL
		if k < from:
			fill = Color.WHITE
		elif k < to:
			fill = t["light"]
		Kit.disc(self, center, r, fill)
		if k >= from and k < to:
			Kit.circle_ring(self, center, r + 6.0, 3.0, Color(t["light"], 0.6 + 0.4 * sin(_clock * 6.0)))
