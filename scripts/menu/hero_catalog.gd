extends RefCounted

# Hero data for the menu (stage 3, Teil A): reads scripts/hero/heroes.gd
# (Teil B's catalogue, HEROES / ORDER) defensively and fills gaps from
# FALLBACK, so the menu works even while the catalogue is missing or partial.
# Portraits are cropped concept-art copies under assets/heroes/ (Brann from the
# V2 roster, Brine from the boxer app icon). Also draws round portraits and the
# "BALD" silhouettes of heroes that are not playable yet.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")

const CATALOG_PATH := "res://scripts/hero/heroes.gd"
const PORTRAIT_DIR := "res://assets/heroes/"
const DEFAULT := "brann"
const FALLBACK := {
	"brann": {"name": "Brann", "title": "Der Schrotflinten-Koch", "weapon": "shotgun", "weapon_name": "Schrotflinte",
		"hp": 100.0, "armor": 0.0, "text": "Zwei Schuss, dann Nachladen. Ein Fächer aus Schrot wirft leichte Gegner um.",
		"color": Color("ef6a22")},
	"boxer": {"name": "Brine", "title": "Der Straßenboxer", "weapon": "fists", "weapon_name": "Fäuste",
		"hp": 130.0, "armor": 0.1, "text": "Links, rechts, Aufwärtshaken. Muss nah ran, hält dafür mehr aus.",
		"color": Color("d8382e")},
}
const FALLBACK_ORDER := ["brann", "boxer"]
## Heroes shown as silhouettes with "BALD" (V2 roster names).
const COMING := ["Vexa", "Rook", "Sable", "Kael"]
const WEAPON_NAMES := {"shotgun": "Schrotflinte", "fists": "Fäuste"}

static var _textures: Dictionary = {}


static func _catalog() -> Dictionary:
	if not ResourceLoader.exists(CATALOG_PATH):
		return {}
	var script: Variant = load(CATALOG_PATH)
	if not (script is Script):
		return {}
	var constants: Dictionary = (script as Script).get_script_constant_map()
	return constants


## Playable hero ids in menu order.
static func ids() -> Array:
	var constants := _catalog()
	var heroes: Variant = constants.get("HEROES", {})
	var order: Variant = constants.get("ORDER", [])
	var out: Array = []
	if order is Array:
		for id in order:
			if id is String and (heroes is Dictionary and heroes.has(id)):
				out.append(id)
	if heroes is Dictionary:
		for id in heroes:
			if id is String and not out.has(id):
				out.append(id)
	for id in FALLBACK_ORDER:
		if not out.has(id):
			out.append(id)
	return out


static func has(id: String) -> bool:
	return ids().has(id)


## Normalised entry: id, name, title, weapon, weapon_name, hp, armor, text, color.
static func hero(id: String) -> Dictionary:
	if not has(id):
		id = DEFAULT
	var out: Dictionary = FALLBACK.get(id, {"name": id.capitalize(), "title": "", "weapon": "", "hp": 100.0, "armor": 0.0, "text": "", "color": Color("5a64a0")}).duplicate()
	var heroes: Variant = _catalog().get("HEROES", {})
	if heroes is Dictionary and heroes.get(id) is Dictionary:
		var entry: Dictionary = heroes[id]
		for key in ["name", "title", "weapon", "weapon_name", "text"]:
			if entry.get(key) is String and String(entry[key]) != "":
				out[key] = entry[key]
		for key in ["hp", "armor"]:
			if entry.get(key) is float or entry.get(key) is int:
				out[key] = float(entry[key])
		var portrait: Variant = entry.get("portrait")
		if portrait is Dictionary and portrait.get("main") is Color:
			out["color"] = portrait["main"]
	if not out.has("weapon_name") or String(out.get("weapon_name", "")) == "":
		out["weapon_name"] = String(WEAPON_NAMES.get(String(out.get("weapon", "")), String(out.get("weapon", "")).capitalize()))
	out["id"] = id
	return out


## Portrait texture of `id` (null if there is no image).
static func portrait(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := PORTRAIT_DIR + "portrait_%s.png" % id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_textures[id] = tex
	return tex


# ---------------------------------------------------------------- drawing

static func _circle(center: Vector2, radius: float, steps: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in steps:
		var a := TAU * float(k) / float(steps)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


## Round portrait with ink rim and a coloured ring (tone: kit tone or Color).
## zoom > 1 crops tighter into the image.
static func draw_portrait(c: CanvasItem, id: String, center: Vector2, radius: float, ring_tone: Variant = "dark", zoom: float = 1.0) -> void:
	var info := hero(id)
	var t: Dictionary = UiStyle.brawl_tone(ring_tone)
	Kit.disc(c, center + Vector2(0, 6), radius + 8.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(c, center, radius + 8.0, UiStyle.BRAWL_INK)
	Kit.disc(c, center, radius + 4.0, t["face"])
	Kit.disc(c, center, radius, Color(info.color).darkened(0.3))
	var tex := portrait(id)
	if tex != null:
		var pts := _circle(center, radius - 1.0)
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append((p - center) / (2.0 * radius * zoom) + Vector2(0.5, 0.5))
		c.draw_colored_polygon(pts, Color.WHITE, uvs, tex)
	else:
		Kit.text_outlined(c, center, String(info.name).left(1), UiStyle.size_step(radius * 0.9), Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.circle_ring(c, center, radius, 3.0, Color(UiStyle.BRAWL_INK, 0.9))


## Dark silhouette (head and shoulders) for a hero that is not playable yet.
static func draw_silhouette(c: CanvasItem, center: Vector2, radius: float) -> void:
	Kit.disc(c, center + Vector2(0, 6), radius + 8.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(c, center, radius + 8.0, UiStyle.BRAWL_INK)
	Kit.disc(c, center, radius + 4.0, UiStyle.brawl_tone("neutral")["dark"])
	Kit.disc(c, center, radius, UiStyle.BRAWL_WELL)
	var shade := Color("2a2752")
	# Shoulders: upper half of an ellipse, cut at the circle.
	var pts := PackedVector2Array()
	var shoulder := center + Vector2(0, radius * 0.92)
	for k in 25:
		var a := PI + PI * float(k) / 24.0
		var p := shoulder + Vector2(cos(a) * radius * 0.78, sin(a) * radius * 0.62)
		pts.append(center + (p - center).limit_length(radius - 2.0))
	for k in range(1, 12):
		var a := lerpf(asin(clampf((pts[pts.size() - 1] - center).y / radius, -1.0, 1.0)), PI - asin(clampf((pts[0] - center).y / radius, -1.0, 1.0)), float(k) / 12.0)
		pts.append(center + Vector2(cos(a), sin(a)) * (radius - 2.0))
	c.draw_colored_polygon(pts, shade)
	Kit.disc(c, center + Vector2(0, -radius * 0.18), radius * 0.34, shade)
	Kit.text_outlined(c, center + Vector2(0, -radius * 0.16), "?", UiStyle.size_step(radius * 0.5), Color(1, 1, 1, 0.55), -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	Kit.circle_ring(c, center, radius, 3.0, Color(UiStyle.BRAWL_INK, 0.9))
