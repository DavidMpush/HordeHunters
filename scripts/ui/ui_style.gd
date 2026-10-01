extends RefCounted

# Shared look for every UI component (stage 04). Colours come from the concept
# sheets in Swarm/Design (active HUD, mutation choice). Components use these
# tokens instead of literals so the whole UI stays one family.

# Surfaces
const PANEL := Color("0c1d17e8")        # deep green-black card body
const PANEL_SOFT := Color("12281fcc")   # secondary panels, chips
const PANEL_EDGE := Color("2f4b3a")     # quiet inner stroke
const SHADOW := Color("03090680")
const DIM := Color("050b08b8")           # world dimmer behind overlays

# Text
const TEXT := Color("f4ecd8")
const TEXT_DIM := Color("a9b8a2")
const BONE := Color("efe2c0")            # claws, teeth, ornaments
const OUTLINE := Color("07110d")         # text outline

# Accents (the frame colour carries meaning; text repeats it)
const EMBER := Color("ff7a2e")           # player, attack, Rally
const EMBER_GLOW := Color("ffb347")
const CYAN := Color("3fe6d8")            # growth, brood, DNA
const VIOLET := Color("b07ae8")          # mutation, special, evolution
const TOXIC := Color("9be15d")           # protection, spores
const DANGER := Color("ff4a3a")          # threat, pressure, loss
const GOLD := Color("f5c86a")            # rewards, boss, crowns
const AMBER := Color("efb642")           # biomass, Alpha-Kern core

const CATEGORY := {"attack": EMBER, "growth": CYAN, "special": VIOLET, "protect": TOXIC, "reflex": VIOLET}

# Colour-blind palette (stage 05), after Okabe & Ito: stays apart under
# deuteranopia and protanopia because it pairs blue with orange/yellow and adds
# white/black instead of relying on red against green. Meaning must never rest
# on colour alone: telegraphs also carry patterns (scripts/telegraph_style.gd).
const CB_ORANGE := Color("e69f00")
const CB_SKY := Color("56b4e9")
const CB_GREEN := Color("009e73")        # bluish green, not grass green
const CB_YELLOW := Color("f0e442")
const CB_BLUE := Color("0072b2")
const CB_VERMILLION := Color("d55e00")
const CB_PURPLE := Color("cc79a7")
const CB_WHITE := Color("f7f7f2")
const CB_BLACK := Color("111014")
# Colour-blind equivalents of the accent tokens above (same keys as `accent()`).
const CB_ACCENT := {
	"ember": CB_ORANGE, "cyan": CB_SKY, "violet": CB_PURPLE, "toxic": CB_YELLOW,
	"danger": CB_VERMILLION, "gold": CB_YELLOW, "amber": CB_ORANGE,
}
const ACCENT := {
	"ember": EMBER, "cyan": CYAN, "violet": VIOLET, "toxic": TOXIC,
	"danger": DANGER, "gold": GOLD, "amber": AMBER,
}

# UI skin switch. "brawl" (default since stage 15) = bold Supercell-style
# kit drawn in code (scripts/ui/ui_kit_brawl.gd): saturated faces, thick
# near-black outlines, 3D buttons, deep blue-violet panels. "calm" = quiet
# petrol cards, panels and bars from Swarm/Design/UI_Assets_V2 (copied to
# res://assets/ui/v2/); "organic" = the glowing organic frames of stage 04.
# Both older skins stay fully working options.
#
# is_calm() is true for every quiet skin (calm AND brawl): components use it
# to leave out claws, teeth, vines and big glows. is_brawl() picks the kit.
#
# The UPPER_CASE tokens above are the organic palette and stay constant (other
# scripts use them in `const` expressions). Skin-aware colours come from:
#   UiStyle.color("text")   token by name for the current skin (see TOKENS)
#   UiStyle.tone(c)         an organic token (or a colour close to one) mapped
#                           onto the current skin; unchanged in organic and in
#                           colour-blind mode. text()/text_px() and UiFrames
#                           apply it, so labels and frames follow the skin.
const SKINS := ["organic", "calm", "brawl"]
static var skin := "brawl"
const CALM_BG := Color("09191c")
const CALM_TEXT := Color("eaf0d9")
const CALM_TEXT_DIM := Color("a2c4b8")
const CALM_TEAL := Color("4cdacb")      # DNA, growth
const CALM_AMBER := Color("d9aa5b")     # biomass, rewards
const CALM_GOLD := Color("e6c27a")      # crowns, boss, trophies (light amber)
const CALM_ORANGE := Color("e9905d")    # attack
const CALM_ORANGE_LIGHT := Color("f2b36e")  # Rally, highlights
const CALM_DANGER := Color("e57b53")    # threat fill of the kit
const CALM_LEAF := Color("b4d778")      # protection
const CALM_VIOLET := Color("b993e8")    # special
const CALM_EDGE := Color("37645e")      # quiet panel stroke
const CALM_CREAM := Color("f4e7bd")     # focus frame, ornaments

const TOKENS := {
	"organic": {
		"text": TEXT, "text_dim": TEXT_DIM, "bone": BONE, "outline": OUTLINE,
		"panel": PANEL, "panel_soft": PANEL_SOFT, "panel_edge": PANEL_EDGE,
		"shadow": SHADOW, "dim": DIM,
		"ember": EMBER, "ember_glow": EMBER_GLOW, "cyan": CYAN, "violet": VIOLET,
		"toxic": TOXIC, "danger": DANGER, "gold": GOLD, "amber": AMBER,
	},
	"calm": {
		"text": CALM_TEXT, "text_dim": CALM_TEXT_DIM, "bone": CALM_CREAM, "outline": Color("041012"),
		"panel": Color("09191cf0"), "panel_soft": Color("0f2428dc"), "panel_edge": CALM_EDGE,
		"shadow": Color("02080a80"), "dim": Color("071310b8"),
		"ember": CALM_ORANGE, "ember_glow": CALM_ORANGE_LIGHT, "cyan": CALM_TEAL, "violet": CALM_VIOLET,
		"toxic": CALM_LEAF, "danger": CALM_DANGER, "gold": CALM_GOLD, "amber": CALM_AMBER,
	},
	# Accent tokens here are the *text-on-dark* shades (a bit lighter than the
	# kit faces in BRAWL_TONES) so coloured labels stay readable on panels.
	"brawl": {
		"text": Color("ffffff"), "text_dim": Color("b8b4e6"), "bone": Color("fff1cf"), "outline": Color("0e0b1f"),
		"panel": Color("211d46f2"), "panel_soft": Color("2c2860e0"), "panel_edge": Color("4b4692"),
		"shadow": Color("0706148c"), "dim": Color("0b0920bf"),
		"ember": Color("ff8a3a"), "ember_glow": Color("ffb24a"), "cyan": Color("45d4ff"), "violet": Color("b98cff"),
		"toxic": Color("7ee04a"), "danger": Color("ff4fa3"), "gold": Color("ffd23f"), "amber": Color("ffb526"),
	},
}

# ------------------------------------------------------------------ brawl kit
# Tokens of the "brawl" skin (stage 15). All sizes in base-viewport pixels
# (900 x 1600; the phone shows this at ~1.2x, the 450 x 800 editor window at 0.5x).
#
# Tones: every kit component takes a tone name (or any Color, from which the
# same three shades are derived). face = main fill, light = top of the
# gradient + gloss, dark = 3D lip / bottom of the gradient / bar track.
# Meaning of the tones (fixed; do not use a tone for something else):
#   ember   own swarm, attack, Rally, player numbers (glow orange-red)
#   action  confirm, play, buy, "yes" (green)
#   info    DNA, growth, information, links (turquoise-blue)
#   loot    biomass, rewards, currency, trophies (gold)
#   danger  threat, pressure, damage, boss (magenta-pink; NOT CONFIRMED by the
#           user yet, change BRAWL_DANGER_* only)
#   special evolution, mutation rarity, Alpha-Kern (violet)
#   neutral secondary buttons, inactive tabs (slate blue)
#   dark    panels, cards, wells (deep blue-violet)
const BRAWL_DANGER_FACE := Color("f2358f")
const BRAWL_DANGER_LIGHT := Color("ff7cc2")
const BRAWL_DANGER_DARK := Color("a3145c")
const BRAWL_TONES := {
	"ember": {"light": Color("ffa340"), "face": Color("ff6a1f"), "dark": Color("bd3a0c")},
	"action": {"light": Color("a6f25c"), "face": Color("4fc92c"), "dark": Color("2a8619")},
	"info": {"light": Color("7fe6ff"), "face": Color("22a9ef"), "dark": Color("0e62ad")},
	"loot": {"light": Color("ffe679"), "face": Color("ffbe1f"), "dark": Color("c07800")},
	"danger": {"light": BRAWL_DANGER_LIGHT, "face": BRAWL_DANGER_FACE, "dark": BRAWL_DANGER_DARK},
	"special": {"light": Color("c9a2ff"), "face": Color("925aff"), "dark": Color("5a2db3")},
	"neutral": {"light": Color("8791c9"), "face": Color("5a64a0"), "dark": Color("333b6e")},
	"dark": {"light": Color("35306c"), "face": Color("242050"), "dark": Color("151232")},
}
## Colour-blind replacements (Okabe & Ito faces; light/dark derived).
const BRAWL_CB_FACE := {"ember": CB_ORANGE, "action": CB_GREEN, "info": CB_SKY, "loot": CB_YELLOW,
	"danger": CB_VERMILLION, "special": CB_PURPLE}
## Stage 28: card colour follows the RARITY (one table for every screen:
## mutation cards, loot card, cocoons, relic strip, codex). Same dict format
## as BRAWL_TONES; common/uncommon are own shades (grey, emerald: not the
## action green), rare/epic/legendary reuse info/special/loot. Valid in every
## skin; brawl_tone() resolves these ids too, so kit calls take a rarity id.
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_TONES := {
	"common": {"light": Color("d9dde8"), "face": Color("9ba2b6"), "dark": Color("5b6176")},
	"uncommon": {"light": Color("8ff5a0"), "face": Color("2cc45e"), "dark": Color("137a3a")},
	"rare": {"light": Color("7fe6ff"), "face": Color("22a9ef"), "dark": Color("0e62ad")},
	"epic": {"light": Color("c9a2ff"), "face": Color("925aff"), "dark": Color("5a2db3")},
	"legendary": {"light": Color("ffe679"), "face": Color("ffbe1f"), "dark": Color("c07800")},
}
const RARITY_NAMES := {"common": "GEWÖHNLICH", "uncommon": "UNGEWÖHNLICH", "rare": "SELTEN", "epic": "EPISCH",
	"legendary": "LEGENDÄR"}
## Colour-blind faces per rarity (grey stays grey; the chip text names the tier).
const RARITY_CB_FACE := {"uncommon": CB_GREEN, "rare": CB_SKY, "epic": CB_PURPLE, "legendary": CB_YELLOW}
const BRAWL_INK := Color("0e0b1f")        # outlines of shapes and text (near black, blue cast)
const BRAWL_INK_SOFT := Color("0e0b1f99")  # hard drop shadows
const BRAWL_TEXT := Color("ffffff")
const BRAWL_TEXT_DIM := Color("b8b4e6")
const BRAWL_PANEL_TOP := Color("2f2a63")   # panel gradient
const BRAWL_PANEL_BOTTOM := Color("1b1840")
const BRAWL_PANEL_RIM := Color("5a54a8")   # 2 px inner highlight under the top edge
const BRAWL_WELL := Color("120f2b")        # sunken areas: bar tracks, inputs, slots

# Radius steps
const R_S := 10.0
const R_M := 16.0
const R_L := 24.0
const R_XL := 34.0
# Outline widths (shapes); text outlines are OUTLINE_TEXT_* (Godot outline size = 2x visible)
const STROKE_S := 3.0
const STROKE_M := 4.0
const STROKE_L := 5.0
# 3D lip of buttons, hard drop shadow below components
const LIP := 8.0
const LIP_S := 5.0
const SHADOW_Y := 6.0
# Spacing steps
const SPACE_XS := 4.0
const SPACE_S := 8.0
const SPACE_M := 12.0
const SPACE_L := 16.0
const SPACE_XL := 24.0
const SPACE_XXL := 32.0
# Minimum touch target (~9 mm on the S25)
const TOUCH_MIN := 96.0

# Type scale of the brawl skin (base px at 900 x 1600; x1.2 = 1080 px wide
# phone). All values are SIZE_STEPS so fitted/animated text shares caches.
#   HERO  72  result title, level-up, "SIEG"      (Baloo 800)
#   TITLE 54  screen titles, big numbers          (Baloo 800)
#   HEAD  38  card titles, button labels, HUD values (Baloo 800)
#   BODY  26  descriptions, list text             (Figtree 500/700)
#   LABEL 22  captions, chips, small numbers      (Baloo 800 or Figtree 700)
# Nothing readable below 22 (text_px may scale 22 down to ~18 for badges).
const T_HERO := 72
const T_TITLE := 54
const T_HEAD := 38
const T_BODY := 26
const T_LABEL := 22
## Text outline size per step (Godot outline size; visible stroke = half).
const OUTLINE_TEXT := {72: 14, 54: 12, 38: 10, 26: 7, 22: 6}
## Hard text shadow offset per step.
const SHADOW_TEXT := {72: 6, 54: 5, 38: 4, 26: 3, 22: 3}


static func is_brawl() -> bool:
	return skin == "brawl"


## Three shades {light, face, dark} of a brawl tone name, or derived from any
## Color (keeps callers free to pass accent colours). Honours colour-blind mode.
static func brawl_tone(tone_value: Variant) -> Dictionary:
	if tone_value is Color:
		return _derive_tone(tone_value)
	var key := String(tone_value)
	if RARITY_TONES.has(key):
		return rarity_tone(key)
	if colorblind and BRAWL_CB_FACE.has(key):
		return _derive_tone(BRAWL_CB_FACE[key])
	return BRAWL_TONES.get(key, BRAWL_TONES["neutral"])


## Stage 28: tone dict {light, face, dark} of a rarity id; unknown -> common.
## Honours colour-blind mode.
static func rarity_tone(id: Variant) -> Dictionary:
	var key := String(id) if RARITY_TONES.has(String(id)) else "common"
	if colorblind and RARITY_CB_FACE.has(key):
		return _derive_tone(RARITY_CB_FACE[key])
	return RARITY_TONES[key]


## Face colour of a rarity (cocoon beams, glows, strips).
static func rarity_color(id: Variant) -> Color:
	return rarity_tone(id)["face"]


## Display name of a rarity ("UNGEWÖHNLICH"); unknown -> GEWÖHNLICH.
static func rarity_name(id: Variant) -> String:
	return String(RARITY_NAMES.get(String(id), RARITY_NAMES["common"]))


static func _derive_tone(face: Color) -> Dictionary:
	var light := Color.from_hsv(face.h, face.s * 0.75, minf(1.0, face.v * 1.12 + 0.12), face.a)
	var dark := Color.from_hsv(face.h, minf(1.0, face.s * 1.08 + 0.05), face.v * 0.62, face.a)
	return {"light": light, "face": face, "dark": dark}

static var _tone_cache: Dictionary = {}


## True for every quiet skin (calm and brawl): no claws, teeth, vines, big glows.
static func is_calm() -> bool:
	return skin != "organic"


## Colour token of the current skin (the colour-blind swap stays with
## accent(), so this is a drop-in for the UPPER_CASE constants) ("text", "text_dim", "bone", "outline",
## "panel", "panel_soft", "panel_edge", "shadow", "dim", "ember", "ember_glow",
## "cyan", "violet", "toxic", "danger", "gold", "amber").
static func color(token: String) -> Color:
	return TOKENS[skin].get(token, TOKENS["organic"].get(token, TEXT))


## Maps an organic palette colour onto the current skin (alpha kept). Colours
## far from every token (white, custom greys, painted tints) stay unchanged.
## Identity in the organic skin and in colour-blind mode.
static func tone(value: Color) -> Color:
	if skin == "organic" or colorblind:
		return value
	var key := Color(value.r, value.g, value.b, 1.0)
	if not _tone_cache.has(key):
		_tone_cache[key] = _nearest(key, skin)
	var mapped: Color = _tone_cache[key]
	return Color(mapped, value.a)


static func _nearest(value: Color, target: String) -> Color:
	var organic: Dictionary = TOKENS["organic"]
	var table: Dictionary = TOKENS[target]
	# Idempotent: a colour already nearer to the target palette than to the
	# organic one (e.g. a calm token lightened by a component) stays as it is.
	if _distance(value, table) < _distance(value, organic):
		return value
	var best := 0.012
	var mapped := value
	for token in organic:
		var ref: Color = organic[token]
		var d := Vector3(value.r - ref.r, value.g - ref.g, value.b - ref.b).length_squared()
		if d < best:
			best = d
			mapped = table[token]
	if mapped == value:
		# Mixed shades (e.g. EMBER.lerp(WHITE, 0.3)): shift by the offset of the
		# nearest accent so tints keep their family in the new palette.
		best = 0.09
		for token in ["ember", "ember_glow", "cyan", "violet", "toxic", "danger", "gold", "amber", "text", "text_dim", "bone"]:
			var ref: Color = organic[token]
			var d := Vector3(value.r - ref.r, value.g - ref.g, value.b - ref.b).length_squared()
			if d < best:
				best = d
				var to: Color = table[token]
				mapped = Color(clampf(value.r + to.r - ref.r, 0.0, 1.0), clampf(value.g + to.g - ref.g, 0.0, 1.0), clampf(value.b + to.b - ref.b, 0.0, 1.0))
	if mapped == value and target != "organic" and value.v < 0.45 and value.h > 0.18 and value.h < 0.5:
		# Dark moss greens of the organic look (card bodies, wells, tracks)
		# become the kit's petrol (calm) or deep blue-violet (brawl) with the
		# same saturation and brightness.
		if target == "calm":
			mapped = Color.from_hsv(0.525, minf(value.s, 0.72), value.v)
		else:
			mapped = Color.from_hsv(0.68, minf(value.s * 1.1, 0.62), value.v * 1.15)
	return mapped


static func _distance(value: Color, table: Dictionary) -> float:
	var best := 9.0
	for token in table:
		var ref: Color = table[token]
		best = minf(best, Vector3(value.r - ref.r, value.g - ref.g, value.b - ref.b).length_squared())
	return best


## Switches the skin at runtime and repaints every Control (cached UiLayers
## are invalidated so they bake again with the new frames).
static func set_skin(value: String) -> void:
	if not SKINS.has(value) or value == skin:
		return
	skin = value
	_tone_cache.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	for node in tree.root.find_children("*", "Control", true, false):
		if node.has_method("invalidate"):
			node.invalidate()
		(node as Control).queue_redraw()


# Colour-blind mode switch. Persisting it in the settings is the menu's job;
# readers call `accent()` or check the flag when they build their visuals.
static var colorblind := false


# Accent colour by token name, honouring the colour-blind switch.
static func accent(token: String) -> Color:
	if colorblind:
		return CB_ACCENT.get(token, TEXT)
	return TOKENS[skin].get(token, TEXT)

# Type scale in base-viewport pixels (900 x 1600). Nothing readable below 20.
const SIZE_HERO := 72
const SIZE_TITLE := 48
const SIZE_HEAD := 34
const SIZE_BODY := 26
const SIZE_LABEL := 22

# Fonts (stage 15, all skins): Baloo 2 ExtraBold for titles and numbers,
# Figtree for text. Both are Latin subsets of the variable OFL fonts built by
# tools/subset_fonts.py; the weight is set by FontVariation resources:
#   display.tres          Baloo 2, wght 800
#   display_numbers.tres  Baloo 2, wght 800, tnum (tabular digits: timers, counters)
#   body.tres             Figtree, wght 500 (also the project theme default font,
#                         project.godot gui/theme/custom_font, so plain Controls
#                         and ThemeDB.fallback_font use it)
#   body_bold.tres        Figtree, wght 700
const DISPLAY_FONT_PATH := "res://assets/ui/fonts/display.tres"
const NUMBER_FONT_PATH := "res://assets/ui/fonts/display_numbers.tres"
const BODY_FONT_PATH := "res://assets/ui/fonts/body.tres"
const BODY_BOLD_FONT_PATH := "res://assets/ui/fonts/body_bold.tres"

static var _fonts: Dictionary = {}
static var _textures: Dictionary = {}
static var _boxes: Dictionary = {}


## Baloo 2 ExtraBold: titles, button labels, HUD values.
static func display_font() -> Font:
	if not _fonts.has("display"):
		_fonts["display"] = _load_font(DISPLAY_FONT_PATH, 0.9, -1)
	return _fonts["display"]


## Baloo 2 ExtraBold with tabular digits: numbers that change (timer, counts).
static func number_font() -> Font:
	if not _fonts.has("number"):
		_fonts["number"] = _load_font(NUMBER_FONT_PATH, 0.9, -1)
	return _fonts["number"]


## Figtree Medium (500): running text, descriptions.
static func body_font() -> Font:
	if not _fonts.has("body"):
		_fonts["body"] = _load_font(BODY_FONT_PATH, 0.35, 0)
	return _fonts["body"]


## Figtree Bold (700): emphasis inside text, small captions.
static func body_bold_font() -> Font:
	if not _fonts.has("body_bold"):
		_fonts["body_bold"] = _load_font(BODY_BOLD_FONT_PATH, 0.6, 0)
	return _fonts["body_bold"]


# Missing font files fall back to Godot's built-in font, emboldened, so a
# broken checkout still lays out.
static func _load_font(path: String, embolden: float, spacing: int) -> Font:
	if ResourceLoader.exists(path):
		var font: Font = load(path)
		if font != null:
			return font
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	variation.spacing_glyph = spacing
	return variation


# Cached texture (SVG/PNG) or null when the file does not exist yet.
static func tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


# Nine-slice box from a texture; margins in texture pixels (left, top, right, bottom).
static func nine(path: String, margins: Vector4, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var key := "%s|%s|%s" % [path, margins, tint]
	if not _boxes.has(key):
		var box := StyleBoxTexture.new()
		box.texture = tex(path)
		box.texture_margin_left = margins.x
		box.texture_margin_top = margins.y
		box.texture_margin_right = margins.z
		box.texture_margin_bottom = margins.w
		box.modulate_color = tint
		_boxes[key] = box
	return _boxes[key]


# Outlined text; align center when centered. Returns the drawn width.
static func text(canvas: CanvasItem, value: String, at: Vector2, size: int, tint: Color = TEXT, centered: bool = false, outline: int = 6, font: Font = null) -> float:
	var face: Font = font if font != null else display_font()
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := at - Vector2(width * 0.5, 0.0) if centered else at
	if outline > 0:
		_text_shadow(canvas, face, origin, value, size, outline)
		canvas.draw_string_outline(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color())
	canvas.draw_string(face, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tone(tint))
	return width


# Brawl skin: hard drop shadow under outlined text (ink, offset down).
static func _text_shadow(canvas: CanvasItem, face: Font, origin: Vector2, value: String, size: int, outline: int) -> void:
	if skin != "brawl":
		return
	var drop := Vector2(0.0, maxf(2.0, roundf(size * 0.08)))
	canvas.draw_string_outline(face, origin + drop, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, BRAWL_INK)


# Text outline of the current skin.
static func outline_color() -> Color:
	return color("outline")


# Stage 07: every rasterised font size costs a glyph cache (~0.8 MB RAM and
# ~0.3 MB VRAM per size with outline). Animated or fitted sizes (pop, zoom,
# shrink-to-fit) therefore never rasterise their own size: they pick the next
# larger size of this palette and scale it down with draw_set_transform.
const SIZE_STEPS := [22, 26, 30, 34, 38, 44, 48, 54, 64, 72, 84, 96, 110]


# Palette size a fractional size is drawn from (the next larger one).
static func size_step(px: float) -> int:
	for step in SIZE_STEPS:
		if step >= px - 0.01:
			return step
	return int(ceil(px))


# Width of `value` at a fractional size (same measure text_px() draws with).
static func width_px(value: String, px: float, font: Font = null) -> float:
	var face: Font = font if font != null else display_font()
	var step := size_step(px)
	return face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, step).x * px / step


# Outlined text at a fractional size: drawn at a palette size and scaled, so a
# pulsing or fitted label adds no new glyph cache. Palette sizes draw exactly
# like text(). Returns the drawn width.
static func text_px(canvas: CanvasItem, value: String, at: Vector2, px: float, tint: Color = TEXT, centered: bool = false, outline: int = 6, font: Font = null) -> float:
	var step := size_step(px)
	if absf(px - step) < 0.01:
		return text(canvas, value, at, step, tint, centered, outline, font)
	var face: Font = font if font != null else display_font()
	var k := px / step
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, step).x * k
	var origin := at - Vector2(width * 0.5, 0.0) if centered else at
	canvas.draw_set_transform(origin, 0.0, Vector2(k, k))
	if outline > 0:
		_text_shadow(canvas, face, Vector2.ZERO, value, step, outline)
		canvas.draw_string_outline(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, outline, outline_color())
	canvas.draw_string(face, Vector2.ZERO, value, HORIZONTAL_ALIGNMENT_LEFT, -1, step, tone(tint))
	canvas.draw_set_transform(Vector2.ZERO)
	return width
