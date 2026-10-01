extends Control

# Pause of a run (stage 3, Teil A §2) in the brawl kit, after Mawlings'
# pause panel (hud_overlays.gd _paint_pause):
#   button   round-cornered pause button at the top right (hidden while dead,
#            while a level-up / cocoon choice is open and while paused)
#   overlay  ribbon PAUSE, time / kills / level tiles, the current build as
#            icons (upgrades, weapon track, relics), three volume sliders,
#            WEITER (big), NEUSTART and MENÜ
# Opens on the button, Esc / P and automatically when the app loses focus
# (only while battle.auto, i.e. not in tests/captures that step by hand).
# The run stands still through battle.set_paused() (same gate in tick() as
# the level-up choice). MENÜ emits menu_requested (main.gd changes scenes).
# Added by main.gd as the last child of the HUD layer: drawn on top and the
# first to see input; while open it swallows every tap and key.

signal menu_requested

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const SLIDERS := preload("res://scripts/ui/volume_sliders.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")
const SESSION := preload("res://scripts/core/session.gd")
const RUN := preload("res://scripts/core/run.gd")

const BUTTON := Vector2(84.0, 76.0)
const PANEL_TOP := 210.0
const OPEN_TIME := 0.22
const ICON := 80.0
const ICON_GAP := 12.0
const MAX_ICONS := 14

var battle: Node
var _clock := 0.0
var _opened_at := -10.0
var _drag_key := ""
var _drag_pointer := -99
var _overlay: Control
var _key := []
var _overlay_key := []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	if battle != null and battle.has_signal("pause_changed"):
		battle.pause_changed.connect(_on_pause_changed)


# ---------------------------------------------------------------- state

func is_open() -> bool:
	return battle != null and bool(battle.user_paused)


## The pause button is shown (and Esc/P may pause): run alive, no choice open.
func button_visible() -> bool:
	if battle == null or battle.run == null or battle.run.dead or is_open():
		return false
	return battle.progression == null or not battle.progression.paused()


func can_pause() -> bool:
	return battle != null and battle.run != null and not battle.run.dead and not is_open()


func open() -> void:
	if can_pause():
		battle.set_paused(true)


func resume() -> void:
	if is_open():
		_end_drag()
		battle.set_paused(false)


func _on_pause_changed(on: bool) -> void:
	if on:
		_opened_at = _clock
		if battle.sfx != null:
			battle.sfx.play("ui", 0.9)
	_key = []
	_overlay_key = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		# Only real play pauses itself; tests and captures step by hand.
		if battle != null and bool(battle.auto):
			open()


# ---------------------------------------------------------------- geometry

func _oy() -> float:
	return (size.y - 1600.0) * 0.5


func pause_button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 20.0 - BUTTON.x, 26.0), BUTTON)


func panel_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 400.0, _oy() + PANEL_TOP), Vector2(800.0, 1160.0))


func _p() -> float:
	return _oy() + PANEL_TOP


func slider_rect(index: int) -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 350.0, _p() + 514.0 + float(index) * (SLIDERS.ROW_H + 10.0)), Vector2(700.0, SLIDERS.ROW_H))


func resume_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 350.0, _p() + 858.0), Vector2(700.0, 132.0))


func restart_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 350.0, _p() + 1012.0), Vector2(340.0, 112.0))


func menu_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 + 10.0, _p() + 1012.0), Vector2(340.0, 112.0))


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if battle == null:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			if is_open():
				get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			if is_open():
				resume()
				get_viewport().set_input_as_handled()
			elif can_pause():
				open()
				get_viewport().set_input_as_handled()
		elif is_open():
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				resume()
			get_viewport().set_input_as_handled()
		return
	var pointer := -99
	var at := Vector2.INF
	var pressed := false
	var released := false
	var moved := false
	if event is InputEventScreenTouch:
		pointer = event.index
		at = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.index
		at = event.position
		moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		pointer = -2
		at = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		pointer = -2
		at = event.position
		moved = true
	else:
		return
	if not is_open():
		if pressed and button_visible() and pause_button_rect().grow(14.0).has_point(at):
			open()
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if pressed:
		tap(at, pointer)
	elif moved and pointer == _drag_pointer and _drag_key != "":
		_drag_to(at)
	elif released and pointer == _drag_pointer:
		_end_drag()


## A press at `at` while the pause is open (tests call this directly).
func tap(at: Vector2, pointer: int = -2) -> void:
	if not is_open():
		if button_visible() and pause_button_rect().grow(14.0).has_point(at):
			open()
		return
	for k in AUDIO.ORDER.size():
		if SLIDERS.hit(slider_rect(k)).has_point(at):
			_drag_key = AUDIO.ORDER[k]
			_drag_pointer = pointer
			_drag_to(at)
			return
	if resume_rect().grow(8.0).has_point(at):
		resume()
	elif restart_rect().grow(8.0).has_point(at):
		_end_drag()
		battle.restart()
	elif menu_rect().grow(8.0).has_point(at):
		_end_drag()
		menu_requested.emit()


func _drag_to(at: Vector2) -> void:
	var index := AUDIO.ORDER.find(_drag_key)
	if index < 0:
		return
	var value := SLIDERS.value_at(slider_rect(index), at.x)
	if not is_equal_approx(value, float(SESSION.setting(_drag_key))):
		SESSION.set_setting(_drag_key, value, false)


func _end_drag() -> void:
	if _drag_key != "":
		_drag_key = ""
		_drag_pointer = -99
		SESSION.save_profile()


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	_clock += delta
	var key := [button_visible(), size]
	if key != _key:
		_key = key
		queue_redraw()
	var open_now := is_open()
	var appear := clampf((_clock - _opened_at) / OPEN_TIME, 0.0, 1.0) if open_now else 0.0
	_overlay.visible = open_now
	_overlay.modulate.a = clampf(_ease(appear) * 1.4, 0.0, 1.0)
	if not open_now:
		return
	var volumes := []
	for k in AUDIO.ORDER:
		volumes.append(SESSION.setting(k))
	var okey := [size, snappedf(appear, 0.01), volumes, _drag_key, int(battle.run.elapsed), int(battle.run.kills), int(battle.run.level)]
	if okey != _overlay_key:
		_overlay_key = okey
		_overlay.queue_redraw()


func _draw() -> void:
	if not button_visible():
		return
	var rect := pause_button_rect()
	Kit.button(self, rect, "neutral", false, UiStyle.R_M)
	var mid := Kit.button_label_center(rect)
	for dx in [-11.0, 11.0]:
		var bar := Rect2(mid + Vector2(dx - 6.0, -17.0), Vector2(12.0, 34.0))
		Kit.rrect(self, bar.grow(4.0), 6.0, UiStyle.BRAWL_INK)
		Kit.rrect(self, bar, 3.0, Color.WHITE)


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _draw_overlay() -> void:
	if not is_open():
		return
	var c: CanvasItem = _overlay
	var appear := _ease((_clock - _opened_at) / OPEN_TIME)
	Kit.dim(c, Rect2(Vector2.ZERO, size), 0.74 * appear)
	var cx := size.x * 0.5
	var panel := panel_rect()
	Kit.panel(c, panel, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	var ribbon := Rect2(Vector2(cx - 200.0, panel.position.y - 52.0), Vector2(400.0, 104.0))
	Kit.ribbon(c, ribbon, "info")
	Kit.text_outlined(c, ribbon.get_center() + Vector2(0, -4), "PAUSE", UiStyle.T_HERO, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, ribbon.size.x - 50.0)
	var p := _p()
	# Run so far: time, kills, level.
	var run: RefCounted = battle.run
	var tiles := [["ZEIT", RUN.clock(run.elapsed), "info"], ["KILLS", Kit.format_int(run.kills), "danger"], ["LEVEL", str(run.level), "special"]]
	var tile_w := (700.0 - 2.0 * 16.0) / 3.0
	for k in 3:
		var tile := Rect2(Vector2(cx - 350.0 + float(k) * (tile_w + 16.0), p + 78.0), Vector2(tile_w, 116.0))
		Kit.well(c, tile, UiStyle.R_M)
		Kit.text_outlined(c, Vector2(tile.get_center().x, tile.position.y + 28.0), tiles[k][0], UiStyle.T_LABEL, UiStyle.brawl_tone(tiles[k][2])["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE)
		Kit.number(c, Vector2(tile.get_center().x, tile.position.y + 76.0), tiles[k][1], UiStyle.T_TITLE, Color.WHITE, Kit.CENTER | Kit.MIDDLE, tile.size.x - 20.0)
	_section(c, Vector2(cx - 350.0, p + 236.0), "AKTUELLER BUILD", "loot")
	var well := Rect2(Vector2(cx - 350.0, p + 262.0), Vector2(700.0, 190.0))
	Kit.well(c, well, UiStyle.R_M)
	_draw_build(c, well)
	_section(c, Vector2(cx - 350.0, p + 490.0), "LAUTSTÄRKE", "info")
	for k in AUDIO.ORDER.size():
		var key: String = AUDIO.ORDER[k]
		SLIDERS.draw(c, slider_rect(k), key, float(SESSION.setting(key)), _drag_key == key)
	var go := resume_rect()
	Kit.button(c, go, "action", false, UiStyle.R_L)
	var mid := Kit.button_label_center(go)
	_play_glyph(c, Vector2(go.position.x + 150.0, mid.y), 26.0)
	Kit.text_outlined(c, Vector2(cx + 30.0, mid.y), "WEITER", UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	var again := restart_rect()
	Kit.button(c, again, "neutral", false, UiStyle.R_L)
	Kit.text_outlined(c, Kit.button_label_center(again), "NEUSTART", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, again.size.x - 30.0)
	var home := menu_rect()
	Kit.button(c, home, "neutral", false, UiStyle.R_L)
	Kit.text_outlined(c, Kit.button_label_center(home), "MENÜ", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, home.size.x - 30.0)
	Kit.text_outlined(c, Vector2(cx, panel.end.y + 50.0), "ESC · P: WEITER", UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE)


# Section heading with a thin rule to the right (as on the result screen).
func _section(c: CanvasItem, at: Vector2, label: String, tone: String) -> void:
	var w := Kit.text_outlined(c, at, label, UiStyle.T_LABEL + 4, UiStyle.brawl_tone(tone)["light"], -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	Kit.rrect(c, Rect2(Vector2(at.x + w + 16.0, at.y - 2.0), Vector2(maxf(0.0, 700.0 - w - 16.0), 4.0)), 2.0, Color(UiStyle.brawl_tone(tone)["light"], 0.35))


# Build as icon plates in their best rarity with the rank (relics: stacks).
func _draw_build(c: CanvasItem, well: Rect2) -> void:
	var build: Array = []
	if battle.get("progress") != null and battle.progress.has_method("build_summary"):
		build = battle.progress.build_summary()
	if build.is_empty():
		Kit.paragraph(c, Vector2(well.position.x, well.get_center().y - 14.0), "Noch keine Upgrades", well.size.x, UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)
		return
	var per_row := 7
	var count := mini(build.size(), MAX_ICONS)
	var rows := ceili(float(count) / float(per_row))
	var row_w := float(per_row) * ICON + float(per_row - 1) * ICON_GAP
	var x0 := well.get_center().x - row_w * 0.5 + ICON * 0.5
	var y0 := well.get_center().y - (float(rows) * ICON + float(rows - 1) * ICON_GAP) * 0.5 + ICON * 0.5
	for index in count:
		var item: Dictionary = build[index]
		var center := Vector2(x0 + float(index % per_row) * (ICON + ICON_GAP), y0 + float(index / per_row) * (ICON + ICON_GAP))
		var rarity := String(item.get("rarity", "common"))
		Kit.icon_plate(c, center, ICON, rarity)
		Icons.draw(c, String(item.get("icon", "")), Kit.plate_center(center, ICON), ICON * 0.72)
		var rank := int(item.get("rank", 0))
		if rank > 0:
			var text := ("×%d" % rank) if String(item.get("type", "")) == "relic" else str(rank)
			Kit.badge(c, center + Vector2(ICON * 0.36, ICON * 0.34), text, "dark", UiStyle.T_LABEL)


func _play_glyph(c: CanvasItem, center: Vector2, r: float) -> void:
	var tri := PackedVector2Array([center + Vector2(-r * 0.7, -r), center + Vector2(r * 0.95, 0.0), center + Vector2(-r * 0.7, r)])
	var ring := tri.duplicate()
	ring.append(tri[0])
	c.draw_polyline(ring, UiStyle.BRAWL_INK, 10.0, true)
	c.draw_colored_polygon(tri, Color.WHITE)
