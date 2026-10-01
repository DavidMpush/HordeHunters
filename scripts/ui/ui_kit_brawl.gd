extends RefCounted

# Brawl UI kit (stage 15, wave 1): the building blocks of the Supercell-style
# skin. Bold saturated faces, thick near-black outlines, 3D buttons with a
# darker lip and a gloss streak, deep blue-violet panels, big outlined text
# with a hard drop shadow. Drawn with the canvas API (no textures), so every
# size stays sharp and a UiLayer can cache it.
#
#   const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
#   Kit.panel(self, rect)                                   # in _draw() / a UiLayer painter
#   Kit.button(self, rect, "action", pressed)
#   Kit.text_outlined(self, Kit.button_label_center(rect, pressed), "SPIELEN", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
#
# Conventions
# - Coordinates and sizes are base-viewport pixels (900 x 1600). `rect` is the
#   whole visible footprint incl. outline and 3D lip; only the hard drop
#   shadow (UiStyle.SHADOW_Y) reaches below it.
# - `tone` is a UiStyle.BRAWL_TONES name ("ember", "action", "info", "loot",
#   "danger", "special", "neutral", "dark", "disabled") or any Color (shades are
#   derived). Colour-blind mode is honoured by UiStyle.brawl_tone().
# - Edges: solid fills are StyleBoxFlat (anti-aliased); gradients are vertex
#   coloured overlays that fade out before they reach an uncovered edge, and the
#   ink outline ring is drawn last, so every visible edge is anti-aliased.
# - Every function leaves the canvas transform at identity.

const UiStyle := preload("res://scripts/ui/ui_style.gd")

# Text alignment flags for text_outlined()/number().
const LEFT := 0
const CENTER := 1
const RIGHT := 2
const BASELINE := 0      # `pos.y` is the baseline (default, like draw_string)
const MIDDLE := 4        # `pos.y` is the visual middle of the capitals

## Visual cap height per em (Baloo 2 = 0.613, Figtree = 0.70).
const CAP_DISPLAY := 0.62
const CAP_BODY := 0.70

const DISABLED := {"light": Color("7d7a99"), "face": Color("5b5875"), "dark": Color("3a3850")}

static var _sb: StyleBoxFlat


# ------------------------------------------------------------------ panels

## Dark (or tinted) panel: hard shadow, ink outline, top-to-bottom gradient,
## 2 px highlight under the top edge. radius: UiStyle.R_* step.
static func panel(canvas: CanvasItem, rect: Rect2, tone: Variant = "dark", radius: float = UiStyle.R_L, stroke: float = UiStyle.STROKE_M, shadow: bool = true) -> void:
	var top: Color
	var bottom: Color
	var rim: Color
	if tone is String and tone == "dark":
		top = UiStyle.BRAWL_PANEL_TOP
		bottom = UiStyle.BRAWL_PANEL_BOTTOM
		rim = UiStyle.BRAWL_PANEL_RIM
	else:
		var t := UiStyle.brawl_tone(tone)
		top = t["light"]
		bottom = t["face"]
		rim = t["light"].lightened(0.35)
	if shadow:
		rrect(canvas, Rect2(rect.position + Vector2(0.0, UiStyle.SHADOW_Y), rect.size), radius, UiStyle.BRAWL_INK_SOFT)
	var inner := rect.grow(-stroke)
	var r_in := maxf(radius - stroke, 0.0)
	rrect(canvas, inner.grow(0.5), r_in + 0.5, bottom)
	fade_rrect(canvas, inner, r_in, top, 0.0, 1.0)
	top_rim(canvas, inner, r_in, rim, 2.0)
	ring(canvas, rect, radius, stroke, UiStyle.BRAWL_INK)


## Inner area of a panel/card (inside outline plus one spacing step).
static func panel_inner(rect: Rect2, stroke: float = UiStyle.STROKE_M) -> Rect2:
	return rect.grow(-stroke - UiStyle.SPACE_M)


## Sunken well inside a panel (slots, inputs, list rows): darker, inner shade
## at the top, thin ink outline.
static func well(canvas: CanvasItem, rect: Rect2, radius: float = UiStyle.R_S) -> void:
	rrect(canvas, rect, radius, UiStyle.BRAWL_WELL)
	fade_rrect(canvas, rect, radius, Color(0, 0, 0, 0.45), 0.0, 0.35)
	# light catches the lower lip of the recess
	var sb := _box()
	sb.draw_center = false
	sb.border_color = Color(UiStyle.BRAWL_PANEL_RIM, 0.55)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 2
	var r := int(roundf(clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)))
	sb.set_corner_radius_all(r)
	sb.corner_detail = _detail(r)
	canvas.draw_style_box(sb, rect.grow(1.0))
	ring(canvas, rect, radius, 2.0, Color(UiStyle.BRAWL_INK, 0.9))


## Card (mutation choice, shop item): coloured frame band around a dark body.
## header > 0 fills a coloured title strip of that height at the top.
## state: "normal", "pressed", "selected", "disabled".
static func card(canvas: CanvasItem, rect: Rect2, tone: Variant = "info", state: String = "normal", header: float = 0.0, radius: float = UiStyle.R_L) -> void:
	var t := DISABLED if state == "disabled" else UiStyle.brawl_tone(tone)
	var box := rect
	if state == "pressed":
		box = Rect2(rect.position + Vector2(0.0, 4.0), rect.size - Vector2(0.0, 4.0))
	else:
		rrect(canvas, Rect2(box.position + Vector2(0.0, UiStyle.SHADOW_Y + 2.0), box.size), radius, UiStyle.BRAWL_INK_SOFT)
	if state == "selected":
		rrect(canvas, box.grow(9.0), radius + 9.0, Color(t["light"], 0.35))
		ring(canvas, box.grow(7.0), radius + 7.0, 5.0, t["light"])
	var stroke := UiStyle.STROKE_L
	var band := 7.0
	var inner := box.grow(-stroke)
	var r_in := maxf(radius - stroke, 0.0)
	rrect(canvas, inner.grow(0.5), r_in + 0.5, t["face"])
	fade_rrect(canvas, inner, r_in, t["light"], 0.0, 0.5)
	var body := Rect2(inner.position + Vector2(band, band + header), inner.size - Vector2(band * 2.0, band * 2.0 + header))
	var r_body := maxf(r_in - band, 4.0)
	if body.size.y > 4.0:
		rrect(canvas, body, r_body, UiStyle.BRAWL_PANEL_BOTTOM)
		fade_rrect(canvas, body, r_body, UiStyle.BRAWL_PANEL_TOP, 0.0, 1.0)
		ring(canvas, body.grow(1.5), r_body + 1.5, 3.0, Color(t["dark"], 0.95))
	top_rim(canvas, inner, r_in, Color(t["light"].lightened(0.4), 0.9), 2.0)
	if state == "pressed":
		rrect(canvas, inner, r_in, Color(0, 0, 0, 0.12))
	ring(canvas, box, radius, stroke, UiStyle.BRAWL_INK)


## Body area of a card (below the header, inside the frame band).
static func card_inner(rect: Rect2, header: float = 0.0) -> Rect2:
	var inset := UiStyle.STROKE_L + 7.0
	return Rect2(rect.position + Vector2(inset, inset + header), rect.size - Vector2(inset * 2.0, inset * 2.0 + header)).grow(-UiStyle.SPACE_S)


# ------------------------------------------------------------------ buttons

## Depth of the 3D lip for a button of this height.
static func lip_for(height: float) -> float:
	return clampf(roundf(height * 0.11), UiStyle.LIP_S, UiStyle.LIP)


## 3D button: ink outline around face + darker lip, gloss streak on top, hard
## shadow. pressed = face sinks onto the lip (no shadow). tone "action" is the
## primary confirm button, "neutral" the secondary one, "disabled" inactive.
static func button(canvas: CanvasItem, rect: Rect2, tone: Variant = "action", pressed: bool = false, radius: float = UiStyle.R_M) -> void:
	var t := DISABLED if (tone is String and tone == "disabled") else UiStyle.brawl_tone(tone)
	var lip := lip_for(rect.size.y)
	var stroke := UiStyle.STROKE_M if rect.size.y >= 64.0 else UiStyle.STROKE_S
	var sink := lip - 2.0 if pressed else 0.0
	var box := Rect2(rect.position + Vector2(0.0, sink), rect.size - Vector2(0.0, sink))
	radius = minf(radius, box.size.y * 0.5)
	if not pressed:
		rrect(canvas, Rect2(box.position + Vector2(0.0, UiStyle.SHADOW_Y * 0.7), box.size), radius, UiStyle.BRAWL_INK_SOFT)
	var inner := box.grow(-stroke)
	var r_in := maxf(radius - stroke, 0.0)
	rrect(canvas, inner.grow(0.5), r_in + 0.5, t["dark"])
	var face := Rect2(inner.position, inner.size - Vector2(0.0, lip - sink))
	var face_color: Color = t["face"].darkened(0.1) if pressed else t["face"]
	rrect(canvas, face, r_in, face_color)
	if t == DISABLED:
		# inactive: flat face, no gloss or glint (must not look pressable)
		fade_rrect(canvas, face, r_in, Color(t["light"], 0.6), 0.0, 0.5)
	elif pressed:
		# pushed in: lighter band only low, a soft inner shade at the top
		fade_rrect(canvas, face, r_in, Color(t["light"], 0.55), 0.0, 0.5)
		fade_rrect(canvas, face, r_in, Color(0, 0, 0, 0.22), 0.0, 0.3)
	else:
		fade_rrect(canvas, face, r_in, t["light"], 0.0, 0.58)
		fade_rrect(canvas, face, r_in, Color(1, 1, 1, 0.26), 0.0, 0.42)
		top_rim(canvas, face, r_in, Color(1, 1, 1, 0.5), 2.0)
		_glint(canvas, face, r_in)
	ring(canvas, box, radius, stroke, UiStyle.BRAWL_INK)


# Small specular glint in the upper-left corner of a face (cartoon gloss).
static func _glint(canvas: CanvasItem, face: Rect2, r_in: float) -> void:
	var gh := clampf(roundf(face.size.y * 0.12), 4.0, 9.0)
	var gw := clampf(face.size.x * 0.12, gh * 2.2, 46.0)
	var at := face.position + Vector2(maxf(r_in * 0.7, 8.0), maxf(4.0, face.size.y * 0.12))
	rrect(canvas, Rect2(at, Vector2(gw, gh)), gh * 0.5, Color(1, 1, 1, 0.75))
	disc(canvas, at + Vector2(gw + gh * 0.9, gh * 0.5), gh * 0.42, Color(1, 1, 1, 0.75))


## Where a label goes (use with MIDDLE alignment): centre of the face, moves
## with the pressed state.
static func button_label_center(rect: Rect2, pressed: bool = false) -> Vector2:
	var lip := lip_for(rect.size.y)
	var sink := lip - 2.0 if pressed else 0.0
	return Vector2(rect.get_center().x, rect.position.y + sink + (rect.size.y - lip) * 0.5 + 1.0)


## Round 3D button (Rally, pause, close). Same layers as button().
static func round_button(canvas: CanvasItem, center: Vector2, radius: float, tone: Variant = "ember", pressed: bool = false) -> void:
	var t := DISABLED if (tone is String and tone == "disabled") else UiStyle.brawl_tone(tone)
	var lip := clampf(roundf(radius * 0.12), UiStyle.LIP_S, UiStyle.LIP)
	var stroke := UiStyle.STROKE_L if radius >= 60.0 else UiStyle.STROKE_M
	var sink := lip - 2.0 if pressed else 0.0
	# Etappe 22b: discs and fades in one triangle list, the glint, then the outline.
	var batch := TriBatch.new()
	if not pressed:
		batch.disc(center + Vector2(0.0, UiStyle.SHADOW_Y), radius, UiStyle.BRAWL_INK_SOFT)
	var c := center + Vector2(0.0, sink * 0.5)
	var r := radius - sink * 0.5
	batch.disc(c, r, UiStyle.BRAWL_INK)
	batch.disc(c, r - stroke + 0.5, t["dark"])
	var face_c := c - Vector2(0.0, (lip - sink) * 0.5)
	var face_r := r - stroke - (lip - sink) * 0.5
	batch.disc(face_c, face_r, t["face"].darkened(0.1) if pressed else t["face"])
	if pressed:
		_fade_disc_into(batch, face_c, face_r, Color(t["light"], 0.5), 0.0, 0.6)
		_fade_disc_into(batch, face_c, face_r, Color(0, 0, 0, 0.22), 0.0, 0.35)
		batch.ring(c, r, stroke, UiStyle.BRAWL_INK)
		batch.flush(canvas)
		return
	_fade_disc_into(batch, face_c, face_r, t["light"], 0.0, 0.66)
	_fade_disc_into(batch, face_c - Vector2(0, face_r * 0.18), face_r * 0.78, Color(1, 1, 1, 0.24), 0.0, 0.6)
	batch.flush(canvas)
	_round_glint(canvas, face_c, face_r)
	batch.ring(c, r, stroke, UiStyle.BRAWL_INK)
	batch.flush(canvas)


# Curved glint on the upper-left of a round face: a short capsule tangent to
# the rim plus a dot.
static func _round_glint(canvas: CanvasItem, c: Vector2, r: float) -> void:
	var gh := clampf(r * 0.13, 4.0, 12.0)
	var a := deg_to_rad(-128.0)
	var p := c + Vector2(cos(a), sin(a)) * (r * 0.7)
	canvas.draw_set_transform(p, a + PI * 0.5, Vector2.ONE)
	rrect(canvas, Rect2(Vector2(-r * 0.22, -gh * 0.5), Vector2(r * 0.44, gh)), gh * 0.5, Color(1, 1, 1, 0.75))
	canvas.draw_set_transform(Vector2.ZERO)
	var d := c + Vector2(cos(a + 0.62), sin(a + 0.62)) * (r * 0.7)
	disc(canvas, d, gh * 0.42, Color(1, 1, 1, 0.75))


## Centre for an icon/label on a round button.
static func round_label_center(center: Vector2, radius: float, pressed: bool = false) -> Vector2:
	var lip := clampf(roundf(radius * 0.12), UiStyle.LIP_S, UiStyle.LIP)
	var sink := lip - 2.0 if pressed else 0.0
	return center + Vector2(0.0, sink * 0.5 - (lip - sink) * 0.5)


# ------------------------------------------------------------------ small parts

## Capsule chip (resource counters, tags). tone "dark" = quiet chip.
static func pill(canvas: CanvasItem, rect: Rect2, tone: Variant = "dark", stroke: float = UiStyle.STROKE_M) -> void:
	panel(canvas, rect, tone, rect.size.y * 0.5, stroke, true)


## See-through capsule for short in-run messages (flood moment, context line):
## tinted body at `alpha`, ink outline, no hard shadow, so the arena stays
## readable behind it. tone "dark" = panel colour.
static func veil_pill(canvas: CanvasItem, rect: Rect2, tone: Variant = "dark", alpha: float = 0.6) -> void:
	var face: Color
	if tone is String and tone == "dark":
		face = UiStyle.BRAWL_PANEL_BOTTOM
	else:
		face = UiStyle.brawl_tone(tone)["dark"]
	var r := rect.size.y * 0.5
	rrect(canvas, rect.grow(-1.0), r - 1.0, Color(face, alpha))
	fade_rrect(canvas, rect.grow(-3.0), r - 3.0, Color(Color.WHITE, 0.08 * alpha), 0.0, 0.5)
	ring(canvas, rect, r, UiStyle.STROKE_S, Color(UiStyle.BRAWL_INK, minf(1.0, alpha + 0.25)))


## Small rounded tag (filters, "NEU" labels on cards, rank chips).
static func chip(canvas: CanvasItem, rect: Rect2, tone: Variant = "neutral") -> void:
	panel(canvas, rect, tone, UiStyle.R_S, UiStyle.STROKE_S, false)


## Round counter badge or capsule ("3", "NEU", "!"). Grows with the text.
static func badge(canvas: CanvasItem, center: Vector2, value: String, tone: Variant = "danger", size: int = UiStyle.T_BODY) -> void:
	var font := UiStyle.number_font()
	var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := roundf(size * 1.5)
	var box_w := maxf(h, w + size * 0.9)
	var rect := Rect2(center - Vector2(box_w, h) * 0.5, Vector2(box_w, h))
	var t := UiStyle.brawl_tone(tone)
	rrect(canvas, Rect2(rect.position + Vector2(0, 3), rect.size), h * 0.5, UiStyle.BRAWL_INK_SOFT)
	rrect(canvas, rect.grow(-2.0), h * 0.5 - 2.0, t["face"])
	fade_rrect(canvas, rect.grow(-2.0), h * 0.5 - 2.0, t["light"], 0.0, 0.6)
	ring(canvas, rect.grow(-3.0), h * 0.5 - 3.0, 2.0, Color(1, 1, 1, 0.85))
	ring(canvas, rect, h * 0.5, 3.0, UiStyle.BRAWL_INK)
	text_outlined(canvas, center, value, size, Color.WHITE, int(size * 0.28), 2, font, CENTER | MIDDLE)


## Round or rounded-square plate as the common icon background.
## shape: "round" or "square". The icon goes on plate_center().
static func icon_plate(canvas: CanvasItem, center: Vector2, size: float, tone: Variant = "dark", shape: String = "round") -> void:
	if size < 12.0:
		return
	var t: Dictionary
	if tone is String and tone == "dark":
		t = {"light": UiStyle.BRAWL_PANEL_RIM, "face": UiStyle.BRAWL_PANEL_TOP, "dark": UiStyle.BRAWL_PANEL_BOTTOM.darkened(0.3)}
	else:
		t = UiStyle.brawl_tone(tone)
	var r := size * 0.5
	var stroke := UiStyle.STROKE_M if size >= 56.0 else UiStyle.STROKE_S
	var lip := clampf(roundf(size * 0.07), 3.0, 6.0)
	if shape == "square":
		var rect := Rect2(center - Vector2(r, r), Vector2(size, size))
		var radius := size * 0.26
		rrect(canvas, Rect2(rect.position + Vector2(0, 4), rect.size), radius, UiStyle.BRAWL_INK_SOFT)
		var inner := rect.grow(-stroke)
		var r_in := radius - stroke
		rrect(canvas, inner.grow(0.5), r_in + 0.5, t["dark"])
		var face := Rect2(inner.position, inner.size - Vector2(0, lip))
		rrect(canvas, face, r_in, t["face"])
		fade_rrect(canvas, face, r_in, t["light"], 0.0, 0.7)
		top_rim(canvas, face, r_in, Color(t["light"].lightened(0.3), 0.8), 2.0)
		ring(canvas, rect, radius, stroke, UiStyle.BRAWL_INK)
		return
	# Etappe 22b: the whole round plate is one triangle list (was ~12 draw calls).
	var batch := TriBatch.new()
	icon_plate_into(batch, center, size, tone)
	batch.flush(canvas)


## Round icon_plate added to a triangle batch (several plates, one draw call).
## shadow = false leaves out the soft drop shadow (a plate laid over an
## identical one that already casts it).
static func icon_plate_into(batch: TriBatch, center: Vector2, size: float, tone: Variant = "dark", shadow: bool = true) -> void:
	if size < 12.0:
		return
	var t: Dictionary
	if tone is String and tone == "dark":
		t = {"light": UiStyle.BRAWL_PANEL_RIM, "face": UiStyle.BRAWL_PANEL_TOP, "dark": UiStyle.BRAWL_PANEL_BOTTOM.darkened(0.3)}
	else:
		t = UiStyle.brawl_tone(tone)
	var r := size * 0.5
	var stroke := UiStyle.STROKE_M if size >= 56.0 else UiStyle.STROKE_S
	var lip := clampf(roundf(size * 0.07), 3.0, 6.0)
	if shadow:
		batch.disc(center + Vector2(0, 4), r, UiStyle.BRAWL_INK_SOFT)
	batch.disc(center, r, UiStyle.BRAWL_INK)
	batch.disc(center, r - stroke + 0.5, t["dark"])
	var fc := center - Vector2(0, lip * 0.5)
	var fr := r - stroke - lip * 0.5
	batch.disc(fc, fr, t["face"])
	_fade_disc_into(batch, fc, fr, t["light"], 0.0, 0.75)
	batch.ring(center, r, stroke, UiStyle.BRAWL_INK)


## Where the icon sits on an icon_plate (the face is lifted by the lip).
static func plate_center(center: Vector2, size: float) -> Vector2:
	return center - Vector2(0, clampf(roundf(size * 0.07), 3.0, 6.0) * 0.5)


## Progress bar: thick ink frame, sunken track, glossy fill. segments > 0
## draws ink notches between the parts (life pips, danger meter).
static func bar(canvas: CanvasItem, rect: Rect2, fraction: float, tone: Variant = "info", segments: int = 0) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	var t := UiStyle.brawl_tone(tone)
	var stroke := UiStyle.STROKE_M if rect.size.y >= 26.0 else UiStyle.STROKE_S
	var radius := rect.size.y * 0.5
	rrect(canvas, Rect2(rect.position + Vector2(0, 3), rect.size), radius, UiStyle.BRAWL_INK_SOFT)
	var inner := rect.grow(-stroke)
	var r_in := inner.size.y * 0.5
	rrect(canvas, inner.grow(0.5), r_in + 0.5, UiStyle.BRAWL_WELL)
	fade_rrect(canvas, inner, r_in, Color(0, 0, 0, 0.5), 0.0, 0.45)
	var fill_w := inner.size.x * fraction
	if fill_w > 0.5:
		var fill := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		var fr := minf(r_in, fill_w * 0.5)
		rrect(canvas, fill, fr, t["face"])
		fade_rrect(canvas, fill, fr, t["light"], 0.0, 0.55)
		# darker lower edge for volume
		rrect(canvas, Rect2(fill.position + Vector2(0, fill.size.y * 0.72), Vector2(fill.size.x, fill.size.y * 0.28)).grow_individual(-fr * 0.35, 0, -fr * 0.35, 0), fr * 0.5, Color(t["dark"], 0.55))
		var gh := maxf(2.0, fill.size.y * 0.22)
		var gloss := Rect2(fill.position + Vector2(fr * 0.6, fill.size.y * 0.16), Vector2(fill.size.x - fr * 1.2, gh))
		if gloss.size.x > gh:
			rrect(canvas, gloss, gh * 0.5, Color(1, 1, 1, 0.4))
	if segments > 1:
		var step := inner.size.x / float(segments)
		# Etappe 22b: all dividers in one multiline (1 draw call, was one per line).
		var lines := PackedVector2Array()
		for i in range(1, segments):
			var x := roundf(inner.position.x + step * i)
			lines.append_array([Vector2(x, inner.position.y), Vector2(x, inner.end.y)])
		canvas.draw_multiline(lines, UiStyle.BRAWL_INK, 3.0, true)
	ring(canvas, rect, radius, stroke, UiStyle.BRAWL_INK)


## Title ribbon (screen and overlay titles): band with folded tails.
static func ribbon(canvas: CanvasItem, rect: Rect2, tone: Variant = "ember") -> void:
	var t := UiStyle.brawl_tone(tone)
	var h := rect.size.y
	var tail := h * 0.62
	var drop := h * 0.22
	for side: float in [-1.0, 1.0]:
		var x0 := rect.position.x if side < 0.0 else rect.end.x
		var outer := x0 + side * tail
		var top := rect.position.y + drop
		var bottom := rect.end.y + drop
		var pts := PackedVector2Array([Vector2(x0, top), Vector2(outer, top), Vector2(outer - side * tail * 0.38, (top + bottom) * 0.5), Vector2(outer, bottom), Vector2(x0, bottom)])
		canvas.draw_colored_polygon(pts, t["dark"])
		var closed := pts.duplicate()
		closed.append(pts[0])
		canvas.draw_polyline(closed, UiStyle.BRAWL_INK, UiStyle.STROKE_M, true)
		# fold shadow where the band meets the tail
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x0, rect.end.y - 1.0), Vector2(x0 - side * h * 0.3, rect.end.y - 1.0), Vector2(x0, bottom)]), UiStyle.BRAWL_INK)
	panel(canvas, rect, tone, UiStyle.R_S, UiStyle.STROKE_M, true)


## Dims the world behind overlays.
static func dim(canvas: CanvasItem, rect: Rect2, alpha: float = 0.72) -> void:
	canvas.draw_rect(rect, Color(UiStyle.BRAWL_PANEL_BOTTOM.darkened(0.55), alpha))


## Soft halo (Polier-Runde, Kit wish of packages C/D/E): radial falloff from
## `alpha` at the core to transparent at the rim. `at` is a centre (Vector2,
## `radius` = halo radius) or a Rect2 (a rounded halo `radius` px around it).
## tone: BRAWL_TONES name (uses its light shade) or a Color. Additive-looking
## but plain alpha blend, so it works on any layer.
static func glow(canvas: CanvasItem, at: Variant, radius: float, tone: Variant = "loot", alpha: float = 0.5) -> void:
	if radius <= 0.0 or alpha <= 0.0:
		return
	var color: Color = tone if tone is Color else UiStyle.brawl_tone(tone)["light"]
	var core := Color(color, color.a * alpha)
	var clear := Color(color, 0.0)
	if at is Rect2:
		var rect: Rect2 = at
		var r0 := minf(rect.size.x, rect.size.y) * 0.5
		var inner := _glow_ring(rect, r0)
		var outer := _glow_ring(rect.grow(radius), r0 + radius)
		var n := inner.size()
		# Etappe 22b: the same quads as ONE triangle list (one draw call instead of n).
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for i in n:
			points.append_array([inner[i], outer[i]])
			colors.append_array([core, clear])
		for i in n:
			var j := (i + 1) % n
			indices.append_array([i * 2, i * 2 + 1, j * 2 + 1, i * 2, j * 2 + 1, j * 2])
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
		return
	var c: Vector2 = at
	var steps := clampi(int(radius * 0.5), 16, 48)
	var half := Color(color, core.a * 0.45)
	# Fan plus one ring: the inner ring at 45 % alpha gives a soft, eased falloff.
	# Etappe 22b: one triangle list (was 2 x steps draw calls, up to 96).
	var fan_points := PackedVector2Array([c])
	var fan_colors := PackedColorArray([core])
	for i in steps:
		var a := TAU * float(i) / float(steps)
		var dir := Vector2(cos(a), sin(a))
		fan_points.append_array([c + dir * radius * 0.45, c + dir * radius])
		fan_colors.append_array([half, clear])
	var fan := PackedInt32Array()
	for i in steps:
		var j := (i + 1) % steps
		var p0 := 1 + i * 2
		var p1 := 1 + j * 2
		fan.append_array([0, p0, p1, p0, p0 + 1, p1 + 1, p0, p1 + 1, p1])
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), fan, fan_points, fan_colors)


# Rounded outline with a fixed point count (8 per corner), so an inner and an
# outer ring of glow() line up point by point.
static func _glow_ring(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var centres := [Vector2(rect.position.x + r, rect.position.y + r), Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r), Vector2(rect.position.x + r, rect.end.y - r)]
	for corner in 4:
		for i in 8:
			var a := PI + PI * 0.5 * (float(corner) + float(i) / 7.0)
			pts.append(centres[corner] + Vector2(cos(a), sin(a)) * r)
	return pts


## Warning glyph: white rounded triangle with an ink contour and a "!" in the
## tone's dark shade (default danger). `radius` = centre to top corner.
static func warn_glyph(canvas: CanvasItem, center: Vector2, radius: float, tone: Variant = "danger") -> void:
	var pts := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 1.1, radius * 0.82), center + Vector2(-radius * 1.1, radius * 0.82)])
	var closed := pts.duplicate()
	closed.append(pts[0])
	var ink_w := maxf(4.0, radius * 0.42)
	var dark: Color = tone if tone is Color else UiStyle.brawl_tone(tone)["dark"]
	for p in pts:
		disc(canvas, p + Vector2(0, maxf(2.0, radius * 0.1)), ink_w * 0.5, UiStyle.BRAWL_INK_SOFT)
	canvas.draw_polyline(closed, UiStyle.BRAWL_INK, ink_w, true)
	for p in pts:
		disc(canvas, p, ink_w * 0.5, UiStyle.BRAWL_INK)
	canvas.draw_colored_polygon(pts, Color.WHITE)
	canvas.draw_polyline(closed, Color.WHITE, maxf(2.0, ink_w * 0.36), true)
	canvas.draw_line(center + Vector2(0, -radius * 0.42), center + Vector2(0, radius * 0.28), dark, maxf(3.0, radius * 0.23), true)
	disc(canvas, center + Vector2(0, radius * 0.56), maxf(2.0, radius * 0.145), dark)


## Chevron (">" arrow) pointing along `direction`: a thick rounded stroke with
## ink contour and drop shadow, face in the tone's face colour with a light
## core line. `size` = length from the wing ends to the tip.
static func chevron(canvas: CanvasItem, center: Vector2, direction: Vector2, size: float, tone: Variant = "loot") -> void:
	if direction.length_squared() < 0.0001 or size <= 0.0:
		return
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	var t: Dictionary = UiStyle.brawl_tone(tone) if not (tone is Color) else {"face": tone, "light": (tone as Color).lightened(0.35), "dark": (tone as Color).darkened(0.35)}
	var tip := center + d * size * 0.3
	var wing := center - d * size * 0.45
	var pts := PackedVector2Array([wing + side * size * 0.55, tip, wing - side * size * 0.55])
	var face_w := maxf(4.0, size * 0.3)
	var ink_w := face_w + maxf(4.0, size * 0.16)
	var drop := Vector2(0, maxf(2.0, size * 0.1))
	# Etappe 22b: all four strokes in one triangle list (1 draw call, was 16).
	var batch := TriBatch.new()
	_stroke_into(batch, _moved(pts, drop), ink_w, UiStyle.BRAWL_INK_SOFT)
	_stroke_into(batch, pts, ink_w, UiStyle.BRAWL_INK)
	_stroke_into(batch, pts, face_w, t["face"])
	_stroke_into(batch, _moved(pts, Vector2(0, -face_w * 0.18)), face_w * 0.3, t["light"])
	batch.flush(canvas)


# Polyline with round caps and joints (discs at every point).
static func _stroke_into(batch: TriBatch, pts: PackedVector2Array, width: float, color: Color) -> void:
	batch.strip(pts, width, color)
	for p in pts:
		batch.disc(p, width * 0.5, color)


static func _moved(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


# ------------------------------------------------------------------ text

## Big friendly text: fill, ink outline, hard ink drop shadow.
## size: a UiStyle.T_* step (other SIZE_STEPS values are fine too).
## outline/shadow -1 = the step's default (UiStyle.OUTLINE_TEXT / SHADOW_TEXT);
## 0 disables. font null = display font (Baloo 2 ExtraBold).
## align: LEFT/CENTER/RIGHT, optionally | MIDDLE (pos.y = middle of capitals).
## max_width > 0 shrinks the text uniformly (no new glyph cache) to fit.
## Returns the drawn width.
static func text_outlined(canvas: CanvasItem, pos: Vector2, value: String, size: int, color: Color = Color.WHITE, outline: int = -1, shadow: int = -1, font: Font = null, align: int = LEFT, max_width: float = 0.0) -> float:
	if value == "":
		return 0.0
	var face: Font = font if font != null else UiStyle.display_font()
	if outline < 0:
		outline = int(UiStyle.OUTLINE_TEXT.get(size, roundf(size * 0.26)))
	if shadow < 0:
		shadow = int(UiStyle.SHADOW_TEXT.get(size, maxf(2.0, roundf(size * 0.08))))
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var k := 1.0
	if max_width > 0.0 and width > max_width:
		k = max_width / width
	var origin := pos
	match align & 3:
		CENTER:
			origin.x -= width * k * 0.5
		RIGHT:
			origin.x -= width * k
	if align & MIDDLE:
		origin.y += cap_height(face, size) * k * 0.5
	canvas.draw_set_transform(origin, 0.0, Vector2(k, k))
	# Etappe 22b: both outline passes first, then both fills, so glyphs of the
	# same atlas follow each other and batch (2 draw calls instead of 4). Same
	# picture: the shadow fill and the outline are the same opaque ink, and
	# ink over ink composes the same in either order.
	var drop := Vector2(0.0, shadow / k)
	if outline > 0:
		if shadow > 0:
			canvas.draw_string_outline(face, drop, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, UiStyle.BRAWL_INK)
		canvas.draw_string_outline(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, UiStyle.BRAWL_INK)
	if shadow > 0:
		canvas.draw_string(face, drop, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiStyle.BRAWL_INK)
	canvas.draw_string(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	canvas.draw_set_transform(Vector2.ZERO)
	return width * k


## Numbers with tabular digits (timers and counters don't jitter). int values
## get German thousands dots ("12.345").
## Etappe 22b: several outlined texts at once - all outlines, then all fills,
## so the glyphs batch into about two draw calls in total. Only for texts that
## do not overlap each other. job = [pos, value, size, color, font, align, max_width].
static func texts_outlined(canvas: CanvasItem, jobs: Array) -> void:
	var prepared: Array = []
	for job: Array in jobs:
		var value: String = job[1]
		if value == "":
			continue
		var size: int = job[2]
		var face: Font = job[4] if job[4] != null else UiStyle.display_font()
		var outline := int(UiStyle.OUTLINE_TEXT.get(size, roundf(size * 0.26)))
		var shadow := int(UiStyle.SHADOW_TEXT.get(size, maxf(2.0, roundf(size * 0.08))))
		var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var k := 1.0
		var max_width: float = job[6]
		if max_width > 0.0 and width > max_width:
			k = max_width / width
		var origin: Vector2 = job[0]
		var align: int = job[5]
		match align & 3:
			CENTER:
				origin.x -= width * k * 0.5
			RIGHT:
				origin.x -= width * k
		if align & MIDDLE:
			origin.y += cap_height(face, size) * k * 0.5
		prepared.append([face, origin, k, value, size, outline, shadow, job[3]])
	for fill in [false, true]:
		for item: Array in prepared:
			var face: Font = item[0]
			var k: float = item[2]
			var value: String = item[3]
			var size: int = item[4]
			var outline: int = item[5]
			var shadow: int = item[6]
			var drop := Vector2(0.0, shadow / k)
			canvas.draw_set_transform(item[1], 0.0, Vector2(k, k))
			if not fill:
				if outline > 0:
					if shadow > 0:
						canvas.draw_string_outline(face, drop, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, UiStyle.BRAWL_INK)
					canvas.draw_string_outline(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, UiStyle.BRAWL_INK)
				continue
			if shadow > 0:
				canvas.draw_string(face, drop, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiStyle.BRAWL_INK)
			canvas.draw_string(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, item[7])
	canvas.draw_set_transform(Vector2.ZERO)


static func number(canvas: CanvasItem, pos: Vector2, value: Variant, size: int, color: Color = Color.WHITE, align: int = LEFT, max_width: float = 0.0) -> float:
	var s := format_int(value) if value is int else str(value)
	return text_outlined(canvas, pos, s, size, color, -1, -1, UiStyle.number_font(), align, max_width)


## Body text (Figtree): thin outline, no shadow by default; wraps at width
## and returns the y below the last line. bold picks Figtree 700.
static func paragraph(canvas: CanvasItem, pos: Vector2, value: String, width: float, size: int = UiStyle.T_BODY, color: Color = Color.WHITE, bold: bool = false, align: int = LEFT, max_lines: int = 4, outline: int = 0) -> float:
	var face := UiStyle.body_bold_font() if bold else UiStyle.body_font()
	var line_h := roundf(size * 1.28)
	var lines := wrap_lines(value, face, size, width)
	var y := pos.y
	for i in mini(lines.size(), max_lines):
		var line: String = lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			line = line.trim_suffix(".") + "…"
		var x := pos.x
		var w := face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if align & 3 == CENTER:
			x = pos.x + (width - w) * 0.5
		elif align & 3 == RIGHT:
			x = pos.x + width - w
		if outline > 0:
			canvas.draw_string_outline(face, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, UiStyle.BRAWL_INK)
		canvas.draw_string(face, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		y += line_h
	return y


## Greedy word wrap.
static func wrap_lines(value: String, face: Font, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for block in value.split("\n"):
		var line := ""
		for word in block.split(" ", false):
			var probe := word if line == "" else line + " " + word
			if line != "" and face.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				out.append(line)
				line = word
			else:
				line = probe
		out.append(line)
	return out


## Visual cap height of a face at a size (for vertical centring).
static func cap_height(face: Font, size: int) -> float:
	var is_body := face == UiStyle.body_font() or face == UiStyle.body_bold_font()
	return size * (CAP_BODY if is_body else CAP_DISPLAY)


## 12345 -> "12.345" (German grouping).
static func format_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


# ------------------------------------------------------------------ primitives

static func _box() -> StyleBoxFlat:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.anti_aliasing = true
		_sb.anti_aliasing_size = 1.0
	return _sb


## Etappe 4 Teil E: one finished StyleBoxFlat per (colour, radius, border)
## instead of re-setting the shared box per call (every setter emits
## "changed"); border 0 = solid fill, else an outline ring of that width.
static var _boxes := {}


static func _cached_box(color: Color, r: int, border: int) -> StyleBoxFlat:
	var key := Vector4i(r, border, color.to_rgba32(), 0)
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		if _boxes.size() >= 1024:
			_boxes.clear()
		sb = StyleBoxFlat.new()
		sb.anti_aliasing = true
		sb.anti_aliasing_size = 1.0
		sb.draw_center = border == 0
		if border == 0:
			sb.bg_color = color
		else:
			sb.border_color = color
			sb.set_border_width_all(border)
		sb.set_corner_radius_all(r)
		sb.corner_detail = _detail(r)
		_boxes[key] = sb
	return sb


static func _detail(radius: float) -> int:
	return clampi(int(radius * 0.5), 4, 16)


## Solid anti-aliased rounded rectangle.
static func rrect(canvas: CanvasItem, rect: Rect2, radius: float, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or color.a <= 0.0:
		return
	var r := int(roundf(clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)))
	canvas.draw_style_box(_cached_box(color, r, 0), rect)


## Anti-aliased rounded outline ring of `width` inside `rect`.
static func ring(canvas: CanvasItem, rect: Rect2, radius: float, width: float, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var r := int(roundf(clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)))
	var w := int(roundf(width))
	if w <= 0:
		return
	canvas.draw_style_box(_cached_box(color, r, w), rect)


## Highlight along the top edge only (curves into the corners).
static func top_rim(canvas: CanvasItem, rect: Rect2, radius: float, color: Color, width: float = 2.0) -> void:
	var sb := _box()
	sb.draw_center = false
	sb.border_color = color
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.border_width_top = int(roundf(width))
	var r := int(roundf(clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)))
	sb.set_corner_radius_all(r)
	sb.corner_detail = _detail(r)
	canvas.draw_style_box(sb, rect)


## Vertical fade overlay in the rounded shape: `color` at full alpha from the
## top down to `from` (0..1 of the height), then fading to transparent at `to`.
## Edges near full alpha must lie under an outline ring (not anti-aliased).
static var _fade_cache := {}


static func fade_rrect(canvas: CanvasItem, rect: Rect2, radius: float, color: Color, from: float, to: float) -> void:
	var h := rect.size.y * to
	if h <= 1.0 or rect.size.x <= 1.0:
		return
	var r := clampf(radius, 0.0, minf(rect.size.x * 0.5, rect.size.y * 0.5))
	# Etappe 4 Teil E: the shape only depends on size, radius, colour and the
	# fade band; built once at the origin and moved natively (world-anchored
	# bars repaint every frame).
	var key := [rect.size, r, color, from, to]
	var cached: Variant = _fade_cache.get(key)
	if cached == null:
		var local := Rect2(Vector2.ZERO, rect.size)
		# The real contour, clipped at the fade end (convex, so one clip pass).
		var pts := _clip_below(round_rect_points(local, Vector4(r, r, r, r)), h)
		var cols := PackedColorArray()
		var clear := Color(color, 0.0)
		var start := rect.size.y * from
		for p in pts:
			var k := 0.0 if p.y <= start else clampf((p.y - start) / maxf(h - start, 0.001), 0.0, 1.0)
			cols.append(color.lerp(clear, k))
		if _fade_cache.size() >= 512:
			_fade_cache.clear()
		cached = [pts, cols]
		_fade_cache[key] = cached
	var shape: PackedVector2Array = cached[0]
	if shape.size() < 3:
		return
	canvas.draw_polygon(Transform2D(0.0, rect.position) * shape, cached[1])


# Keeps the part of a convex polygon with y <= cut; drops duplicate points
# (they break the triangulation).
static func _clip_below(pts: PackedVector2Array, cut: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var a_in := a.y <= cut
		var b_in := b.y <= cut
		if a_in:
			_push(out, a)
		if a_in != b_in:
			var t := (cut - a.y) / (b.y - a.y)
			_push(out, a.lerp(b, t))
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) < 0.01:
		out.remove_at(out.size() - 1)
	return out


static func _push(out: PackedVector2Array, p: Vector2) -> void:
	if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.01:
		out.append(p)


## Solid anti-aliased disc.
## Etappe 22b: every round shape is built as one triangle list with a thin
## feathered rim (the anti-aliasing), so a disc costs one draw call instead of
## two and a whole plate (shadow, rim, faces, fade, outline) only one.
static func disc(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius > 0.0:
		var batch := TriBatch.new()
		batch.disc(center, radius, color)
		batch.flush(canvas)


## Anti-aliased circle outline of `width` inside `radius`.
static func circle_ring(canvas: CanvasItem, center: Vector2, radius: float, width: float, color: Color) -> void:
	var batch := TriBatch.new()
	batch.ring(center, radius, width, color)
	batch.flush(canvas)


## Triangle batch for round shapes: collect, then draw in ONE command. The rim
## feather is FEATHER base pixels wide (about one screen pixel on phones).
class TriBatch:
	const FEATHER := 1.2
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	static func segments(radius: float) -> int:
		return clampi(int(radius * 0.9), 20, 96)

	func disc(c: Vector2, r: float, color: Color) -> void:
		if r <= 0.0 or color.a <= 0.0:
			return
		var n := segments(r)
		var inner := maxf(0.0, r - FEATHER * 0.5)
		var outer := r + FEATHER * 0.5
		var clear := Color(color, 0.0)
		var base := points.size()
		points.append(c)
		colors.append(color)
		for i in n:
			var dir := Vector2.from_angle(TAU * float(i) / float(n))
			points.append_array([c + dir * inner, c + dir * outer])
			colors.append_array([color, clear])
		for i in n:
			var j := (i + 1) % n
			var a := base + 1 + i * 2
			var b := base + 1 + j * 2
			indices.append_array([base, a, b, a, a + 1, b + 1, a, b + 1, b])

	# Band from radius - width to radius, feathered on both edges.
	func ring(c: Vector2, radius: float, width: float, color: Color) -> void:
		if width <= 0.0 or color.a <= 0.0:
			return
		var n := segments(radius)
		var r_in := maxf(0.0, radius - width)
		var clear := Color(color, 0.0)
		var f := FEATHER * 0.5
		var radii := [maxf(0.0, r_in - f), r_in + f, radius - f, radius + f]
		var cols := [clear, color, color, clear]
		if width <= FEATHER:
			radii = [maxf(0.0, r_in - f), (r_in + radius) * 0.5, (r_in + radius) * 0.5, radius + f]
		var base := points.size()
		for i in n:
			var dir := Vector2.from_angle(TAU * float(i) / float(n))
			for k in 4:
				points.append(c + dir * float(radii[k]))
				colors.append(cols[k])
		for i in n:
			var j := (i + 1) % n
			for k in 3:
				var a := base + i * 4 + k
				var b := base + j * 4 + k
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])

	# Thick polyline like draw_polyline(..., antialiased): per point the averaged
	# normal of its segments (Godot's joint), feathered on both edges.
	func strip(pts: PackedVector2Array, width: float, color: Color) -> void:
		var n := pts.size()
		if n < 2 or width <= 0.0 or color.a <= 0.0:
			return
		var hw := width * 0.5
		var f := FEATHER * 0.5
		var clear := Color(color, 0.0)
		var base := points.size()
		var prev := Vector2.ZERO
		for i in n:
			var t: Vector2 = prev if i == n - 1 else (pts[i + 1] - pts[i]).normalized().orthogonal()
			if i == 0:
				prev = t
			var nrm := (t + prev).normalized()
			prev = t
			var p := pts[i]
			points.append_array([p + nrm * (hw + f), p + nrm * maxf(0.0, hw - f), p - nrm * maxf(0.0, hw - f), p - nrm * (hw + f)])
			colors.append_array([clear, color, color, clear])
		for i in n - 1:
			for k in 3:
				var a := base + i * 4 + k
				var b := a + 4
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])

	# Filled polygon with per-vertex colours, triangulated like draw_polygon().
	func polygon(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		var tris := Geometry2D.triangulate_polygon(pts)
		if tris.is_empty():
			return
		var base := points.size()
		points.append_array(pts)
		colors.append_array(cols)
		for index in tris:
			indices.append(base + index)

	func flush(canvas: CanvasItem) -> void:
		if not indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
		points = PackedVector2Array()
		colors = PackedColorArray()
		indices = PackedInt32Array()


## Vertical fade overlay in a disc (same rules as fade_rrect).
static func fade_disc(canvas: CanvasItem, center: Vector2, radius: float, color: Color, from: float, to: float) -> void:
	var batch := TriBatch.new()
	_fade_disc_into(batch, center, radius, color, from, to)
	batch.flush(canvas)


static func _fade_disc_into(batch: TriBatch, center: Vector2, radius: float, color: Color, from: float, to: float) -> void:
	# Tiny discs (shrinking popups) would collapse the polygon.
	if radius < 2.0:
		return
	var n := clampi(int(radius * 0.6), 16, 64)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var top := center.y - radius
	var span := radius * 2.0
	for i in n:
		var a := TAU * i / n
		var p := center + Vector2(cos(a), sin(a)) * radius
		pts.append(p)
		var y := (p.y - top) / span
		var k := 0.0 if y <= from else clampf((y - from) / maxf(to - from, 0.001), 0.0, 1.0)
		cols.append(color.lerp(Color(color, 0.0), k))
	batch.polygon(pts, cols)


## Outline of a rounded rect with per-corner radii (tl, tr, br, bl), clockwise.
static func round_rect_points(rect: Rect2, radii: Vector4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.position.x + radii.x, rect.position.y + radii.x), radii.x, PI],
		[Vector2(rect.end.x - radii.y, rect.position.y + radii.y), radii.y, PI * 1.5],
		[Vector2(rect.end.x - radii.z, rect.end.y - radii.z), radii.z, 0.0],
		[Vector2(rect.position.x + radii.w, rect.end.y - radii.w), radii.w, PI * 0.5],
	]
	for corner in corners:
		var c: Vector2 = corner[0]
		var r: float = corner[1]
		var a0: float = corner[2]
		if r <= 0.5:
			pts.append(c)
			continue
		var steps := clampi(int(r * 0.45), 3, 14)
		for i in steps + 1:
			var a := a0 + PI * 0.5 * i / steps
			pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
