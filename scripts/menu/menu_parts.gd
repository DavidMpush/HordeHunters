extends RefCounted

# Shared drawing pieces of the menu screens (brawl kit): sheet ribbon, section
# heading, FERTIG button, toggle switch, small glyphs (gear, play, back).
# Geometry is on the 900 x 1600 base; callers pass the vertical offset.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")

const SWITCH := Vector2(128.0, 64.0)


## Ribbon title at the top of a sheet.
static func sheet_title(c: CanvasItem, width: float, oy: float, label: String, tone: String = "info") -> void:
	var ribbon := Rect2(Vector2(width * 0.5 - 300.0, oy + 54.0), Vector2(600.0, 108.0))
	Kit.glow(c, ribbon.grow(-8.0), 26.0, tone, 0.35)
	Kit.ribbon(c, ribbon, tone)
	Kit.text_outlined(c, ribbon.get_center() + Vector2(0, -4), label, UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, ribbon.size.x - 70.0)


## Section heading with a thin rule to the right.
static func section(c: CanvasItem, at: Vector2, label: String, tone: String, width: float) -> void:
	var w := Kit.text_outlined(c, at, label, UiStyle.T_LABEL + 4, UiStyle.brawl_tone(tone)["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	Kit.rrect(c, Rect2(Vector2(at.x + w + 16.0, at.y - 2.0), Vector2(maxf(0.0, width - w - 16.0), 4.0)), 2.0, Color(UiStyle.brawl_tone(tone)["light"], 0.35))


## Bottom button of every sheet (back to the title).
static func done_rect(width: float, oy: float) -> Rect2:
	return Rect2(Vector2(width * 0.5 - 260.0, oy + 1400.0), Vector2(520.0, 130.0))


static func draw_done(c: CanvasItem, rect: Rect2, label: String = "FERTIG", pressed: bool = false) -> void:
	Kit.button(c, rect, "action", pressed, UiStyle.R_L)
	Kit.text_outlined(c, Kit.button_label_center(rect, pressed), label, UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, rect.size.x - 40.0)


## On/off switch (capsule with a knob); `at` is its rect.
static func toggle(c: CanvasItem, rect: Rect2, on: bool) -> void:
	var tone: String = "action" if on else "neutral"
	var t: Dictionary = UiStyle.brawl_tone(tone)
	var r := rect.size.y * 0.5
	Kit.rrect(c, Rect2(rect.position + Vector2(0, 4), rect.size), r, UiStyle.BRAWL_INK_SOFT)
	Kit.rrect(c, rect, r, UiStyle.BRAWL_INK)
	var inner := rect.grow(-4.0)
	Kit.rrect(c, inner, r - 4.0, t["dark"] if on else UiStyle.BRAWL_WELL)
	Kit.fade_rrect(c, inner, r - 4.0, Color(t["face"], 0.9 if on else 0.35), 0.0, 1.0)
	var knob_x := rect.end.x - r if on else rect.position.x + r
	var knob := Vector2(knob_x, rect.get_center().y)
	Kit.disc(c, knob + Vector2(0, 3), r - 7.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(c, knob, r - 7.0, UiStyle.BRAWL_INK)
	Kit.disc(c, knob, r - 11.0, Color.WHITE)
	var label := "AN" if on else "AUS"
	var label_x := rect.position.x + (rect.size.x - r * 2.0) * 0.5 + 6.0 if on else rect.end.x - (rect.size.x - r * 2.0) * 0.5 - 6.0
	Kit.text_outlined(c, Vector2(label_x, rect.get_center().y), label, UiStyle.T_LABEL, Color.WHITE if on else UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


## Cog wheel glyph (settings).
static func gear(c: CanvasItem, center: Vector2, r: float, tint: Color = Color.WHITE) -> void:
	var pts := PackedVector2Array()
	var teeth := 8
	for k in teeth * 4:
		var a := TAU * float(k) / float(teeth * 4) - PI / float(teeth * 4)
		var outer := k % 4 == 1 or k % 4 == 2
		pts.append(center + Vector2(cos(a), sin(a)) * (r if outer else r * 0.76))
	var ring := pts.duplicate()
	ring.append(pts[0])
	c.draw_polyline(ring, UiStyle.BRAWL_INK, 9.0, true)
	c.draw_colored_polygon(pts, tint)
	Kit.disc(c, center, r * 0.32 + 3.0, UiStyle.BRAWL_INK)
	Kit.disc(c, center, r * 0.32, UiStyle.brawl_tone("neutral")["dark"])


## Right-pointing play triangle.
static func play(c: CanvasItem, center: Vector2, r: float, tint: Color = Color.WHITE) -> void:
	var tri := PackedVector2Array([center + Vector2(-r * 0.7, -r), center + Vector2(r * 0.95, 0.0), center + Vector2(-r * 0.7, r)])
	var ring := tri.duplicate()
	ring.append(tri[0])
	c.draw_polyline(ring, UiStyle.BRAWL_INK, 10.0, true)
	c.draw_colored_polygon(tri, tint)


## Background dim with vertical fade (top and bottom darker than the middle).
static func shade(c: CanvasItem, rect: Rect2, top: float, middle: float, bottom: float, split: float = 0.5) -> void:
	var ink := Color("0b0920")
	var y_mid := rect.position.y + rect.size.y * split
	var a := Color(ink, top)
	var m := Color(ink, middle)
	var b := Color(ink, bottom)
	c.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, y_mid), Vector2(rect.position.x, y_mid)]), PackedColorArray([a, a, m, m]))
	c.draw_polygon(PackedVector2Array([Vector2(rect.position.x, y_mid), Vector2(rect.end.x, y_mid), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([m, m, b, b]))
