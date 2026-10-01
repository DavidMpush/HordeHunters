extends Control

# Settings of the menu (stage 3, Teil A §1): volumes (Gesamt, Musik, Effekte
# on the Master / Music / SFX buses), vibration on/off, damage numbers on/off.
# Every change is applied at once and saved in the profile (sliders on
# release). FERTIG / Esc returns to the title.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const PARTS := preload("res://scripts/menu/menu_parts.gd")
const SLIDERS := preload("res://scripts/ui/volume_sliders.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")
const SESSION := preload("res://scripts/core/session.gd")

const TOGGLES := [
	["vibration", "VIBRATION", "Kurzes Rütteln, wenn dich ein Gegner trifft"],
	["damage_numbers", "SCHADENSZAHLEN", "Zahlen über getroffenen Gegnern"],
]

var menu: Control
var drag_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _oy() -> float:
	return (size.y - 1600.0) * 0.5


func panel_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 400.0, _oy() + 210.0), Vector2(800.0, 850.0))


func slider_rect(index: int) -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 350.0, _oy() + 310.0 + float(index) * (SLIDERS.ROW_H + 12.0)), Vector2(700.0, SLIDERS.ROW_H))


func toggle_row(index: int) -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 350.0, _oy() + 720.0 + float(index) * 136.0), Vector2(700.0, 120.0))


func switch_rect(index: int) -> Rect2:
	var row := toggle_row(index)
	return Rect2(Vector2(row.end.x - 24.0 - PARTS.SWITCH.x, row.get_center().y - PARTS.SWITCH.y * 0.5), PARTS.SWITCH)


func done_rect() -> Rect2:
	return PARTS.done_rect(size.x, _oy())


func tap(at: Vector2) -> void:
	for k in AUDIO.ORDER.size():
		if SLIDERS.hit(slider_rect(k)).has_point(at):
			drag_key = AUDIO.ORDER[k]
			drag(at)
			return
	for k in TOGGLES.size():
		if toggle_row(k).has_point(at):
			var key: String = TOGGLES[k][0]
			SESSION.set_setting(key, not SESSION.flag(key))
			if key == "vibration":
				SESSION.vibrate(60)
			menu.click()
			queue_redraw()
			return
	if done_rect().grow(8.0).has_point(at):
		menu.show_screen("title")


func drag(at: Vector2) -> void:
	var index := AUDIO.ORDER.find(drag_key)
	if index < 0:
		return
	var value := SLIDERS.value_at(slider_rect(index), at.x)
	if not is_equal_approx(value, float(SESSION.setting(drag_key))):
		SESSION.set_setting(drag_key, value, false)
		queue_redraw()


func release() -> void:
	if drag_key != "":
		drag_key = ""
		SESSION.save_profile()
		menu.click()
		queue_redraw()


func key(code: int) -> bool:
	if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		menu.show_screen("title")
		return true
	return false


func _draw() -> void:
	var oy := _oy()
	PARTS.shade(self, Rect2(Vector2.ZERO, size), 0.84, 0.74, 0.88)
	PARTS.sheet_title(self, size.x, oy, "EINSTELLUNGEN", "info")
	var panel := panel_rect()
	Kit.panel(self, panel, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	var x0 := size.x * 0.5 - 350.0
	PARTS.section(self, Vector2(x0, oy + 272.0), "LAUTSTÄRKE", "info", 700.0)
	for k in AUDIO.ORDER.size():
		var key: String = AUDIO.ORDER[k]
		SLIDERS.draw(self, slider_rect(k), key, float(SESSION.setting(key)), drag_key == key)
	PARTS.section(self, Vector2(x0, oy + 680.0), "SPIEL", "loot", 700.0)
	for k in TOGGLES.size():
		var row := toggle_row(k)
		var on := SESSION.flag(TOGGLES[k][0])
		Kit.well(self, row, UiStyle.R_M)
		var sw := switch_rect(k)
		var text_w := sw.position.x - 20.0 - (row.position.x + 24.0)
		Kit.text_outlined(self, Vector2(row.position.x + 24.0, row.position.y + 38.0), TOGGLES[k][1], UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, text_w)
		Kit.paragraph(self, Vector2(row.position.x + 24.0, row.position.y + 88.0), TOGGLES[k][2], text_w, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, false, Kit.LEFT, 1)
		PARTS.toggle(self, sw, on)
	var note := "Vibration wirkt nur auf dem Handy." if not OS.has_feature("mobile") else ""
	if note != "":
		Kit.paragraph(self, Vector2(x0, oy + 1010.0), note, 700.0, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 1)
	PARTS.draw_done(self, done_rect())
