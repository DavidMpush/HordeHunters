extends RefCounted

# Small vector icons for upgrade cards, the build list and the HUD (brawl
# look: flat fill, thick ink outline). Icons.draw(canvas, id, center, size)
# draws into a square of `size` px around `center`. Ids: burst, clock, aim,
# boot, heart, regen, shield, magnet, crit, gem, clover, shotgun, shells, horn,
# flask, thorns, coin, trophy, belt, amulet, fists, axe, sword, grenade,
# pistols, lightning, bandage, firepot and the evolved weapons (stage 4):
# shotgun_evo, fists_evo, axe_evo, sword_evo, grenade_evo, pistols_evo,
# lightning_evo - the base weapon recoloured over a burst aura
# (unknown ids draw a star).

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")

const INK := UiStyle.BRAWL_INK
const WHITE := Color("fff8ec")
const RED := Color("ff4a5a")
const GOLD := Color("ffc52e")
const BRASS := Color("ffd76a")
const STEEL := Color("c9d2ea")
const WOOD := Color("b5652e")
const GREEN := Color("6fe36a")
const SKY := Color("6fd6ff")
const VIOLET := Color("c08bff")


static func draw(c: CanvasItem, id: String, center: Vector2, size: float) -> void:
	var s := size / 100.0
	match id:
		"burst":
			_star(c, center, 46.0 * s, 24.0 * s, 8, Color("ff8a3c"))
			_star(c, center, 22.0 * s, 12.0 * s, 8, Color("ffe08a"), false)
		"clock":
			_disc(c, center, 40.0 * s, WHITE)
			_line(c, center, center + Vector2(0, -26) * s, 8.0 * s, INK)
			_line(c, center, center + Vector2(18, 8) * s, 8.0 * s, INK)
			Kit.disc(c, center, 6.0 * s, RED)
		"aim":
			Kit.circle_ring(c, center, 36.0 * s, 16.0 * s, INK)
			Kit.circle_ring(c, center, 36.0 * s, 8.0 * s, RED)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_line(c, center + d * 22.0 * s, center + d * 48.0 * s, 9.0 * s, INK)
				_line(c, center + d * 24.0 * s, center + d * 45.0 * s, 4.0 * s, WHITE)
			_disc(c, center, 9.0 * s, RED)
		"boot":
			var pts := _pts(center, s, [[-22, -40], [8, -40], [8, 4], [40, 14], [42, 38], [-26, 38], [-26, 10]])
			_poly(c, pts, WOOD, 7.0 * s)
			_poly(c, _pts(center, s, [[-26, 26], [42, 26], [42, 38], [-26, 38]]), Color("5b3420"), 5.0 * s)
			_line(c, center + Vector2(-46, -6) * s, center + Vector2(-32, -6) * s, 6.0 * s, WHITE)
			_line(c, center + Vector2(-50, 10) * s, center + Vector2(-34, 10) * s, 6.0 * s, WHITE)
		"heart":
			_heart(c, center, 40.0 * s, RED)
		"regen":
			_heart(c, center + Vector2(-6, 4) * s, 34.0 * s, RED)
			_plus(c, center + Vector2(26, -24) * s, 18.0 * s, GREEN)
		"shield":
			var pts := _pts(center, s, [[0, -44], [38, -30], [34, 10], [0, 44], [-34, 10], [-38, -30]])
			_poly(c, pts, SKY, 7.0 * s)
			_poly(c, _pts(center, s, [[0, -30], [24, -21], [21, 6], [0, 30]]), Color(1, 1, 1, 0.45), 0.0)
		"magnet":
			_magnet(c, center, s)
		"crit":
			_star(c, center, 44.0 * s, 16.0 * s, 4, Color("ffe14a"))
			_disc(c, center, 9.0 * s, RED)
		"gem":
			_poly(c, _pts(center, s, [[0, -44], [30, -8], [0, 44], [-30, -8]]), Color("3cc8ff"), 7.0 * s)
			_poly(c, _pts(center, s, [[0, -44], [30, -8], [0, -2]]), Color("a8ecff"), 0.0)
		"clover":
			for d in [Vector2(0, -18), Vector2(18, 0), Vector2(0, 18), Vector2(-18, 0)]:
				_disc(c, center + d * s + Vector2(0, -6) * s, 18.0 * s, GREEN)
			_line(c, center + Vector2(4, 14) * s, center + Vector2(14, 44) * s, 8.0 * s, Color("2f9a3a"))
		"shotgun":
			_shotgun(c, center, s)
		"fists":
			_fist(c, center + Vector2(-12, 6) * s, s * 0.85, true)
			_fist(c, center + Vector2(16, -8) * s, s, false)
		"axe":
			_axe(c, center, s)
		"sword":
			_sword(c, center, s)
		"grenade":
			_grenade(c, center, s)
		"pistols":
			_pistol(c, center + Vector2(-10, 4) * s, s, false, STEEL)
			_pistol(c, center + Vector2(10, -6) * s, s, true, STEEL)
		"lightning":
			_bolt(c, center, s, Color("8fe8ff"))
		"bandage":
			_poly(c, _pts(center, s, [[-40, -14], [34, -34], [42, -6], [-32, 14]]), Color("f2e6cc"), 6.0 * s)
			_poly(c, _pts(center, s, [[-36, 8], [38, -12], [44, 14], [-30, 34]]), Color("e2d2ae"), 6.0 * s)
			for k in 3:
				Kit.disc(c, center + Vector2(-14 + 22 * k, -12 - 6 * k) * s, 6.0 * s, Color("8a93a6"))
		"firepot":
			_star(c, center + Vector2(0, -20) * s, 26.0 * s, 12.0 * s, 7, Color("ff8a2c"))
			_disc(c, center + Vector2(0, 14) * s, 28.0 * s, Color("7a4a2a"))
			_poly(c, _pts(center, s, [[-20, -12], [20, -12], [20, -4], [-20, -4]]), Color("4a2c18"), 4.0 * s)
			Kit.disc(c, center + Vector2(-10, 8) * s, 6.0 * s, Color(1, 1, 1, 0.35))
		"shotgun_evo":
			_aura(c, center, s, Color("ff6a1f"))
			_shotgun(c, center, s)
			_star(c, center + Vector2(-50, -10) * s, 20.0 * s, 9.0 * s, 6, Color("ffd24a"))
		"fists_evo":
			_aura(c, center, s, Color("ffbe1f"))
			_fist(c, center + Vector2(-12, 6) * s, s * 0.85, true, Color("ffd86a"))
			_fist(c, center + Vector2(16, -8) * s, s, false, Color("ffe8a0"))
		"axe_evo":
			_disc(c, center + Vector2(-8, 6) * s, 34.0 * s, Color("c4162e"))
			Kit.disc(c, center + Vector2(4, -2) * s, 26.0 * s, Color("ff6a72"))
			_axe(c, center, s, Color("ff3346"))
		"sword_evo":
			Kit.circle_ring(c, center, 44.0 * s, 8.0 * s, Color("9fe8ff"))
			_sword(c, center + Vector2(-10, 0) * s, s * 0.9, Color("9fe8ff"))
			_sword(c, center + Vector2(12, 0) * s, s * 0.9, Color("dff7ff"))
		"grenade_evo":
			_aura(c, center + Vector2(0, 10) * s, s, Color("ff4a14"))
			_grenade(c, center, s)
		"pistols_evo":
			_aura(c, center, s, Color("ff3a2a"))
			_pistol(c, center + Vector2(-10, 4) * s, s, false, Color("ffb08a"))
			_pistol(c, center + Vector2(10, -6) * s, s, true, Color("ffb08a"))
		"lightning_evo":
			_aura(c, center, s, Color("a66bff"))
			_bolt(c, center, s, Color("e2c8ff"))
		"shells":
			for k in 3:
				_shell(c, center + Vector2(-24 + 24 * k, 4) * s, s)
		"horn":
			var pts := PackedVector2Array()
			for k in 9:
				var t := float(k) / 8.0
				var a := lerpf(PI * 1.05, PI * 1.95, t)
				pts.append(center + Vector2(cos(a) * 38.0, sin(a) * 30.0 + 18.0) * s)
			for k in range(8, -1, -1):
				var t := float(k) / 8.0
				var a := lerpf(PI * 1.05, PI * 1.95, t)
				var w := lerpf(16.0, 4.0, t)
				pts.append(center + Vector2(cos(a) * (38.0 - w), sin(a) * (30.0 - w) + 18.0) * s)
			_poly(c, pts, Color("e9d3a5"), 7.0 * s)
			_disc(c, center + Vector2(-38, 22) * s, 11.0 * s, BRASS)
		"flask":
			_disc(c, center + Vector2(0, 12) * s, 32.0 * s, Color("8fd06a"))
			_poly(c, _pts(center, s, [[-10, -40], [10, -40], [10, -16], [-10, -16]]), WOOD, 6.0 * s)
			Kit.disc(c, center + Vector2(-10, 4) * s, 8.0 * s, Color(1, 1, 1, 0.5))
		"thorns":
			_star(c, center, 46.0 * s, 28.0 * s, 10, Color("7cc04e"))
			_disc(c, center, 20.0 * s, Color("4d8a2e"))
		"coin":
			_disc(c, center, 38.0 * s, GOLD)
			Kit.circle_ring(c, center, 26.0 * s, 5.0 * s, Color("c07800"))
			Kit.disc(c, center + Vector2(-12, -12) * s, 7.0 * s, Color(1, 1, 1, 0.6))
		"trophy":
			_poly(c, _pts(center, s, [[-30, -40], [30, -40], [24, -6], [8, 6], [8, 24], [22, 30], [22, 40], [-22, 40], [-22, 30], [-8, 24], [-8, 6], [-24, -6]]), GOLD, 7.0 * s)
			Kit.circle_ring(c, center + Vector2(-32, -24) * s, 12.0 * s, 6.0 * s, INK)
			Kit.circle_ring(c, center + Vector2(32, -24) * s, 12.0 * s, 6.0 * s, INK)
		"belt":
			_poly(c, _pts(center, s, [[-46, -12], [46, -12], [46, 18], [-46, 18]]), Color("7a4a2a"), 6.0 * s)
			for k in 4:
				_shell(c, center + Vector2(-30 + 20 * k, -6) * s, s * 0.8)
		"amulet":
			Kit.circle_ring(c, center + Vector2(0, -12) * s, 30.0 * s, 6.0 * s, BRASS)
			_disc(c, center + Vector2(0, 20) * s, 22.0 * s, VIOLET)
			Kit.disc(c, center + Vector2(-7, 13) * s, 6.0 * s, Color(1, 1, 1, 0.6))
		_:
			_star(c, center, 42.0 * s, 20.0 * s, 5, GOLD)


# ---------------------------------------------------------------- helpers

static func _pts(center: Vector2, s: float, list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(center + Vector2(float(p[0]), float(p[1])) * s)
	return out


## Filled polygon with an ink outline (outline 0 = fill only).
static func _poly(c: CanvasItem, pts: PackedVector2Array, fill: Color, outline: float) -> void:
	if outline > 0.0:
		var ring := pts.duplicate()
		ring.append(pts[0])
		c.draw_polyline(ring, INK, outline * 2.0, true)
	c.draw_colored_polygon(pts, fill)


static func _disc(c: CanvasItem, center: Vector2, r: float, fill: Color) -> void:
	Kit.disc(c, center, r + maxf(3.0, r * 0.18), INK)
	Kit.disc(c, center, r, fill)


static func _line(c: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	c.draw_line(a, b, color, width, true)


static func _star(c: CanvasItem, center: Vector2, outer: float, inner: float, points: int, fill: Color, outlined := true) -> void:
	var pts := PackedVector2Array()
	for k in points * 2:
		var a := -PI * 0.5 + PI * float(k) / float(points)
		pts.append(center + Vector2(cos(a), sin(a)) * (outer if k % 2 == 0 else inner))
	_poly(c, pts, fill, maxf(3.0, outer * 0.12) if outlined else 0.0)


static func _heart(c: CanvasItem, center: Vector2, r: float, fill: Color) -> void:
	var pts := PackedVector2Array()
	for k in 32:
		var t := TAU * float(k) / 32.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(center + Vector2(x, y) * r / 16.0)
	_poly(c, pts, fill, maxf(3.0, r * 0.14))
	Kit.disc(c, center + Vector2(-r * 0.42, -r * 0.38), r * 0.2, Color(1, 1, 1, 0.55))


static func _plus(c: CanvasItem, center: Vector2, r: float, fill: Color) -> void:
	var w := r * 0.38
	var pts := PackedVector2Array([center + Vector2(-w, -r), center + Vector2(w, -r), center + Vector2(w, -w), center + Vector2(r, -w),
		center + Vector2(r, w), center + Vector2(w, w), center + Vector2(w, r), center + Vector2(-w, r), center + Vector2(-w, w),
		center + Vector2(-r, w), center + Vector2(-r, -w), center + Vector2(-w, -w)])
	_poly(c, pts, fill, maxf(3.0, r * 0.16))


static func _magnet(c: CanvasItem, center: Vector2, s: float) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 13:
		var a := PI * float(k) / 12.0
		outer.append(center + Vector2(cos(a) * 36.0, sin(a) * 36.0 + 2.0) * s)
		inner.append(center + Vector2(cos(a) * 14.0, sin(a) * 14.0 + 2.0) * s)
	var shape := PackedVector2Array([center + Vector2(36, -38) * s])
	shape.append_array(outer)
	shape.append(center + Vector2(-36, -38) * s)
	shape.append(center + Vector2(-14, -38) * s)
	var back := inner.duplicate()
	back.reverse()
	shape.append_array(back)
	shape.append(center + Vector2(14, -38) * s)
	_poly(c, shape, RED, 6.0 * s)
	c.draw_colored_polygon(_pts(center, s, [[14, -38], [36, -38], [36, -20], [14, -20]]), STEEL)
	c.draw_colored_polygon(_pts(center, s, [[-36, -38], [-14, -38], [-14, -20], [-36, -20]]), STEEL)


static func _shotgun(c: CanvasItem, center: Vector2, s: float) -> void:
	var barrels := _pts(center, s, [[-48, -16], [36, -16], [36, -2], [-48, -2]])
	_poly(c, barrels, STEEL, 6.0 * s)
	c.draw_line(center + Vector2(-46, -9) * s, center + Vector2(34, -9) * s, INK, 3.0 * s, true)
	var stock := _pts(center, s, [[0, -4], [50, -6], [52, 24], [30, 22], [14, 6], [0, 6]])
	_poly(c, stock, WOOD, 6.0 * s)
	_poly(c, _pts(center, s, [[-6, 2], [6, 2], [8, 18], [-2, 18]]), Color("6b3a1c"), 4.0 * s)


# Bandaged fist seen from the front: a rounded block, four knuckles, thumb.
static func _fist(c: CanvasItem, center: Vector2, s: float, back: bool, override := Color(0, 0, 0, 0)) -> void:
	var tint := Color("e6d6b4") if back else Color("f6ecd6")
	if override.a > 0.0:
		tint = override
	_poly(c, _pts(center, s, [[-30, -22], [30, -22], [34, 20], [24, 34], [-24, 34], [-34, 20]]), tint, 6.0 * s)
	for k in 4:
		var x := -21.0 + 14.0 * k
		Kit.disc(c, center + Vector2(x, -22) * s, 9.0 * s, INK)
		Kit.disc(c, center + Vector2(x, -22) * s, 6.5 * s, tint)
	_poly(c, _pts(center, s, [[-30, 2], [4, 2], [4, 14], [-30, 14]]), Color("d9884f"), 4.0 * s)
	c.draw_line(center + Vector2(-26, 22) * s, center + Vector2(26, 26) * s, Color("c9b48c"), 4.0 * s, true)


static func _axe(c: CanvasItem, center: Vector2, s: float, steel := STEEL) -> void:
	_poly(c, _pts(center, s, [[-34, 40], [-26, 46], [22, -14], [14, -20]]), WOOD, 6.0 * s)
	var blade := _pts(center, s, [[4, -30], [26, -48], [46, -24], [40, 6], [20, -4]])
	_poly(c, blade, steel, 7.0 * s)
	c.draw_line(center + Vector2(28, -44) * s, center + Vector2(42, -22) * s, WHITE, 5.0 * s, true)


static func _sword(c: CanvasItem, center: Vector2, s: float, steel := STEEL) -> void:
	# Swirl behind the blade.
	Kit.circle_ring(c, center, 40.0 * s, 6.0 * s, Color(SKY, 0.8))
	_poly(c, _pts(center, s, [[-6, 22], [6, 22], [6, -38], [0, -50], [-6, -38]]), steel, 6.0 * s)
	c.draw_line(center + Vector2(0, -40) * s, center + Vector2(0, 16) * s, WHITE, 3.0 * s, true)
	_poly(c, _pts(center, s, [[-22, 20], [22, 20], [22, 28], [-22, 28]]), GOLD, 5.0 * s)
	_poly(c, _pts(center, s, [[-5, 28], [5, 28], [5, 46], [-5, 46]]), Color("5a3420"), 4.0 * s)


static func _grenade(c: CanvasItem, center: Vector2, s: float) -> void:
	_disc(c, center + Vector2(0, 8) * s, 32.0 * s, Color("4f7a34"))
	c.draw_line(center + Vector2(-28, 8) * s, center + Vector2(28, 8) * s, Color("2f4a20"), 4.0 * s, true)
	c.draw_line(center + Vector2(0, -22) * s, center + Vector2(0, 38) * s, Color("2f4a20"), 4.0 * s, true)
	_poly(c, _pts(center, s, [[-10, -34], [10, -34], [10, -22], [-10, -22]]), STEEL, 5.0 * s)
	Kit.circle_ring(c, center + Vector2(18, -34) * s, 9.0 * s, 4.0 * s, INK)
	_star(c, center + Vector2(-4, -46) * s, 14.0 * s, 6.0 * s, 6, Color("ffd24a"))
	Kit.disc(c, center + Vector2(-12, -2) * s, 7.0 * s, Color(1, 1, 1, 0.45))


# Pistol in side view, muzzle left (flip: muzzle right): slide, grip, trigger guard.
static func _pistol(c: CanvasItem, center: Vector2, s: float, flip: bool, steel: Color) -> void:
	var f := -1.0 if flip else 1.0
	var slide := PackedVector2Array()
	for p in [[-40, -22], [20, -22], [20, -6], [-40, -6]]:
		slide.append(center + Vector2(float(p[0]) * f, float(p[1])) * s)
	_poly(c, slide, steel, 6.0 * s)
	var grip := PackedVector2Array()
	for p in [[2, -8], [20, -8], [26, 30], [8, 30]]:
		grip.append(center + Vector2(float(p[0]) * f, float(p[1])) * s)
	_poly(c, grip, WOOD, 6.0 * s)
	Kit.circle_ring(c, center + Vector2(-4.0 * f, 2.0) * s, 8.0 * s, 4.0 * s, INK)
	c.draw_line(center + Vector2(-36.0 * f, -15.0) * s, center + Vector2(14.0 * f, -15.0) * s, WHITE, 3.0 * s, true)


# Zigzag lightning bolt.
static func _bolt(c: CanvasItem, center: Vector2, s: float, fill: Color) -> void:
	_poly(c, _pts(center, s, [[8, -48], [-26, 4], [-4, 4], [-14, 48], [28, -10], [4, -10], [18, -48]]), fill, 6.0 * s)
	c.draw_line(center + Vector2(10, -40) * s, center + Vector2(-12, -2) * s, WHITE, 3.0 * s, true)


# Spiky glow behind an evolved weapon.
static func _aura(c: CanvasItem, center: Vector2, s: float, fill: Color) -> void:
	_star(c, center, 50.0 * s, 32.0 * s, 12, Color(fill, 0.95), false)
	_star(c, center, 38.0 * s, 26.0 * s, 12, Color(fill.lightened(0.4), 0.8), false)


static func _shell(c: CanvasItem, center: Vector2, s: float) -> void:
	_poly(c, _pts(center, s, [[-9, -30], [9, -30], [9, 18], [-9, 18]]), RED, 5.0 * s)
	c.draw_colored_polygon(_pts(center, s, [[-9, 18], [9, 18], [9, 30], [-9, 30]]), BRASS)
	var ring := _pts(center, s, [[-9, 18], [9, 18], [9, 30], [-9, 30], [-9, 18]])
	c.draw_polyline(ring, INK, 5.0 * s, true)
