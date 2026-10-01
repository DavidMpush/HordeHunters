extends Control

# Title menu (stage 3, Teil A §1), root of scenes/menu.tscn (run/main_scene):
#   backdrop  key art (assets/branding/key_art_1200.png), cover-cropped on
#             the heroes, slowly panning, dimmed towards top and bottom
#   title     logo (assets/branding/logo_900.png), hero card (portrait, name,
#             title, weapon, short text; tap -> hero choice), SPIELEN,
#             STATISTIK and EINSTELLUNGEN
#   sheets    hero_select.gd, settings_sheet.gd, stats_sheet.gd (children,
#             one visible at a time)
# SPIELEN hands {hero_id, seed} to main.tscn through Session (scripts/core/
# session.gd). Keys: Enter = SPIELEN, H = heroes, Esc = back to the title.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const SESSION := preload("res://scripts/core/session.gd")
const SFX := preload("res://scripts/core/sfx.gd")
const HEROES := preload("res://scripts/menu/hero_catalog.gd")
const PARTS := preload("res://scripts/menu/menu_parts.gd")
const HERO_SELECT := preload("res://scripts/menu/hero_select.gd")
const SETTINGS := preload("res://scripts/menu/settings_sheet.gd")
const STATS := preload("res://scripts/menu/stats_sheet.gd")

const KEY_ART := "res://assets/branding/key_art_1200.png"
const LOGO := "res://assets/branding/logo_900.png"
## Horizontal centre of the cover crop in the key art (share of its width):
## Rocco and his companions, the logo of the art stays outside.
const ART_FOCUS := 0.68
const ART_PAN := 0.02
const WEAPON_ICONS := {"shotgun": "shotgun", "fists": "burst"}

var screen := "title"
## Run start requested (SPIELEN): the scene changes after the loading frame.
var starting := false
## Seed handed to the run (0 = random per start).
var fixed_seed := 0
var sheets: Dictionary = {}
var _clock := 0.0
var _art: Texture2D
var _logo: Texture2D
var _backdrop: Control
var _pressed := ""
var _pointer := -99
var _sfx: Node
var _deny := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SESSION.apply_settings()
	_art = load(KEY_ART) if ResourceLoader.exists(KEY_ART) else null
	_logo = load(LOGO) if ResourceLoader.exists(LOGO) else null
	_backdrop = Control.new()
	_backdrop.name = "Backdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.show_behind_parent = true
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.draw.connect(_draw_backdrop)
	for entry in [["heroes", HERO_SELECT], ["settings", SETTINGS], ["stats", STATS]]:
		var sheet: Control = entry[1].new()
		sheet.name = String(entry[0]).capitalize()
		sheet.menu = self
		sheet.visible = false
		add_child(sheet)
		sheets[entry[0]] = sheet
	_sfx = SFX.new()
	_sfx.name = "Sfx"
	add_child(_sfx)


## Current hero of the profile (falls back to Brann for unknown ids).
func hero_id() -> String:
	var id := String(SESSION.profile().hero_id)
	return id if HEROES.has(id) else HEROES.DEFAULT


func choose_hero(id: String) -> void:
	if not HEROES.has(id):
		return
	SESSION.profile().hero_id = id
	SESSION.save_profile()
	click()
	_refresh()


## "title", "heroes", "settings" or "stats".
func show_screen(id: String) -> void:
	if id != "title" and not sheets.has(id):
		return
	screen = id
	for key in sheets:
		sheets[key].visible = key == id
	click()
	_refresh()


func _refresh() -> void:
	queue_redraw()
	for key in sheets:
		sheets[key].queue_redraw()


func click() -> void:
	if _sfx != null:
		_sfx.play("ui")


## A locked tile: short shake of the hero card area.
func deny() -> void:
	_deny = 0.25
	if _sfx != null:
		_sfx.play("ui", 0.6)


## SPIELEN: shows the loading state for a frame, then starts main.tscn with
## the chosen hero.
func play() -> void:
	if starting:
		return
	starting = true
	click()
	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var run_seed := fixed_seed if fixed_seed != 0 else randi_range(1, 999999)
	SESSION.start_run(get_tree(), hero_id(), run_seed)


# ---------------------------------------------------------------- geometry

func _oy() -> float:
	return (size.y - 1600.0) * 0.5


func hero_card_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 410.0, _oy() + 880.0), Vector2(820.0, 270.0))


func play_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 320.0, _oy() + 1196.0), Vector2(640.0, 156.0))


func stats_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 410.0, _oy() + 1394.0), Vector2(400.0, 100.0))


func settings_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 + 10.0, _oy() + 1394.0), Vector2(400.0, 100.0))


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if starting:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		_key(event.keycode)
		get_viewport().set_input_as_handled()
		return
	var pointer := -99
	var at := Vector2.INF
	var kind := ""
	if event is InputEventScreenTouch:
		pointer = event.index
		at = event.position
		kind = "press" if event.pressed else "release"
	elif event is InputEventScreenDrag:
		pointer = event.index
		at = event.position
		kind = "drag"
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		pointer = -2
		at = event.position
		kind = "press" if event.pressed else "release"
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		pointer = -2
		at = event.position
		kind = "drag"
	else:
		return
	match kind:
		"press":
			if _pointer == -99:
				_pointer = pointer
				tap(at)
		"drag":
			if pointer == _pointer:
				drag(at)
		"release":
			if pointer == _pointer:
				_pointer = -99
				release()
	get_viewport().set_input_as_handled()


func _key(code: int) -> void:
	if screen != "title":
		if code == KEY_ESCAPE or code == KEY_BACKSPACE:
			show_screen("title")
		elif sheets[screen].key(code):
			pass
		return
	match code:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			play()
		KEY_H:
			show_screen("heroes")
		KEY_S:
			show_screen("settings")


## A press at `at` (screen px) on the current screen (tests call this).
func tap(at: Vector2) -> void:
	if starting:
		return
	if screen != "title":
		sheets[screen].tap(at)
		return
	if play_rect().grow(8.0).has_point(at):
		_pressed = "play"
		play()
	elif hero_card_rect().has_point(at):
		show_screen("heroes")
	elif stats_rect().grow(6.0).has_point(at):
		show_screen("stats")
	elif settings_rect().grow(6.0).has_point(at):
		show_screen("settings")


func drag(at: Vector2) -> void:
	if screen != "title" and sheets[screen].has_method("drag"):
		sheets[screen].drag(at)


func release() -> void:
	if screen != "title" and sheets[screen].has_method("release"):
		sheets[screen].release()


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	_clock += delta
	_deny = maxf(0.0, _deny - delta)
	_backdrop.queue_redraw()
	if screen == "title":
		queue_redraw()


func _draw_backdrop() -> void:
	var c: CanvasItem = _backdrop
	var full := Rect2(Vector2.ZERO, size)
	c.draw_rect(full, Color("141133"))
	if _art != null:
		var art := Vector2(_art.get_size())
		# Cover crop: full art height, width by the screen aspect.
		var src_h := art.y
		var src_w := minf(art.x, src_h * size.x / maxf(1.0, size.y))
		var focus := ART_FOCUS + ART_PAN * sin(_clock * 0.11)
		var x0 := clampf(art.x * focus - src_w * 0.5, 0.0, art.x - src_w)
		c.draw_texture_rect_region(_art, full, Rect2(Vector2(x0, 0.0), Vector2(src_w, src_h)))
	if screen == "title":
		PARTS.shade(c, full, 0.62, 0.18, 0.86, 0.5)
	else:
		PARTS.shade(c, full, 0.5, 0.4, 0.6, 0.5)


func _draw() -> void:
	if screen != "title":
		return
	var oy := _oy()
	var cx := size.x * 0.5
	if _logo != null:
		var w := 800.0
		var h := w * float(_logo.get_height()) / float(_logo.get_width())
		var bob := 6.0 * sin(_clock * 1.5)
		var at := Vector2(cx - w * 0.5, oy + 46.0 + bob)
		c_logo_glow(Vector2(cx, at.y + h * 0.55), w)
		draw_texture_rect(_logo, Rect2(at, Vector2(w, h)), false)
	else:
		Kit.text_outlined(self, Vector2(cx, oy + 240.0), "HORDE HUNTERS", UiStyle.T_HERO, Color("fff2d0"), -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	_draw_hero_card(hero_card_rect())
	# SPIELEN: big action button, slow breathing.
	var go := play_rect()
	var pulse := 1.0 + 0.025 * sin(_clock * 4.0)
	var shown := Rect2(go.get_center() - go.size * pulse * 0.5, go.size * pulse)
	Kit.glow(self, shown.grow(-6.0), 34.0, "action", 0.35 + 0.1 * sin(_clock * 4.0))
	Kit.button(self, shown, "action", starting, UiStyle.R_XL)
	var mid := Kit.button_label_center(shown, starting)
	PARTS.play(self, Vector2(shown.position.x + 104.0, mid.y), 30.0)
	Kit.text_outlined(self, Vector2(shown.get_center().x + 40.0, mid.y), "LÄDT ..." if starting else "SPIELEN", UiStyle.T_HERO, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, shown.size.x - 200.0)
	# Statistics and settings.
	var st := stats_rect()
	Kit.button(self, st, "neutral", false, UiStyle.R_L)
	var st_mid := Kit.button_label_center(st)
	Icons.draw(self, "trophy", Vector2(st.position.x + 58.0, st_mid.y), 60.0)
	Kit.text_outlined(self, Vector2(st.position.x + 100.0, st_mid.y), "STATISTIK", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, st.size.x - 120.0)
	var se := settings_rect()
	Kit.button(self, se, "neutral", false, UiStyle.R_L)
	var se_mid := Kit.button_label_center(se)
	PARTS.gear(self, Vector2(se.position.x + 56.0, se_mid.y), 26.0)
	Kit.text_outlined(self, Vector2(se.position.x + 100.0, se_mid.y), "EINSTELLUNGEN", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, se.size.x - 120.0)


# Soft warm glow behind the logo so it stands off the art.
func c_logo_glow(center: Vector2, width: float) -> void:
	Kit.fade_disc(self, center, width * 0.55, Color(0.05, 0.03, 0.15, 0.55), 0.0, 1.0)


func _draw_hero_card(rect: Rect2) -> void:
	var shake := Vector2(sin(_deny * 80.0) * 8.0 * (_deny / 0.25), 0.0)
	rect.position += shake
	var hero := HEROES.hero(hero_id())
	Kit.panel(self, rect, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	var pc := Vector2(rect.position.x + 140.0, rect.get_center().y)
	Kit.glow(self, pc, 120.0, "info", 0.25 + 0.08 * sin(_clock * 2.0))
	HEROES.draw_portrait(self, String(hero.id), pc, 104.0, "info")
	var x0 := rect.position.x + 280.0
	var width := rect.end.x - 30.0 - x0
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 62.0), String(hero.name).to_upper(), UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, width)
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 108.0), String(hero.title), UiStyle.T_BODY, UiStyle.brawl_tone("loot")["light"], -1, -1, UiStyle.body_bold_font(), Kit.LEFT | Kit.MIDDLE, width)
	var chip := Rect2(Vector2(x0, rect.position.y + 136.0), Vector2(minf(width, 280.0), 54.0))
	Kit.pill(self, chip, "ember", UiStyle.STROKE_S)
	Icons.draw(self, String(WEAPON_ICONS.get(String(hero.weapon), "burst")), Vector2(chip.position.x + 32.0, chip.get_center().y), 44.0)
	Kit.text_outlined(self, Vector2(chip.position.x + 62.0, chip.get_center().y), String(hero.weapon_name).to_upper(), UiStyle.T_LABEL + 4, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, chip.size.x - 76.0)
	Kit.paragraph(self, Vector2(x0, rect.position.y + 212.0), String(hero.text), width, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, false, Kit.LEFT, 2)
	# "WECHSELN" tab on the top edge: the whole card opens the hero choice.
	var tab_label := "HELD WECHSELN"
	var tw := UiStyle.display_font().get_string_size(tab_label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.T_LABEL).x + 70.0
	var tab := Rect2(Vector2(rect.end.x - 26.0 - tw, rect.position.y - 24.0), Vector2(tw, 46.0))
	Kit.pill(self, tab, "info", UiStyle.STROKE_S)
	Kit.text_outlined(self, Vector2(tab.position.x + 22.0, tab.get_center().y), tab_label, UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	Kit.chevron(self, Vector2(tab.end.x - 26.0, tab.get_center().y), Vector2.RIGHT, 22.0, Color.WHITE)
