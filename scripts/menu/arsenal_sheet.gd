extends Control

# Arsenal of the menu (Megabonk-like weapon pool): one row per weapon of
# PROGRESS.arsenal_catalog() with icon, name, intro text and an on/off switch.
# Switched-off weapons are never offered as NEUE WAFFE (profile
# disabled_weapons, handed to the run by Session.start_run). The chosen hero's
# start weapon is always carried (badge STARTWAFFE, no switch); signature
# weapons of other heroes are locked (badge NUR <HELD>, no switch). Every
# toggle is saved at once. FERTIG / Esc returns to the title.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const PARTS := preload("res://scripts/menu/menu_parts.gd")
const HEROES := preload("res://scripts/menu/hero_catalog.gd")
const SESSION := preload("res://scripts/core/session.gd")
const PROGRESS := preload("res://scripts/progression/progress.gd")

const ROW_TOP := 270.0
const ROW_H := 196.0
const ROW_GAP := 16.0
const BADGE := Vector2(196.0, 56.0)
const HINT := "Ausgeschaltete Waffen kommen in keinem Lauf als neue Waffe."

var menu: Control
var _catalog: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _oy() -> float:
	return (size.y - 1600.0) * 0.5


## Weapons in display order ({id, name, icon, text, signature}).
func entries() -> Array:
	if _catalog.is_empty():
		_catalog = PROGRESS.arsenal_catalog()
	return _catalog


func index_of(id: String) -> int:
	var list := entries()
	for k in list.size():
		if String(list[k].id) == id:
			return k
	return -1


func _hero() -> String:
	if menu != null and menu.has_method("hero_id"):
		return String(menu.hero_id())
	var id := String(SESSION.profile().hero_id)
	return id if HEROES.has(id) else HEROES.DEFAULT


## "start" (hero's own weapon, always on), "locked" (signature of another
## hero), "on" or "off".
func state(index: int) -> String:
	var list := entries()
	if index < 0 or index >= list.size():
		return ""
	var entry: Dictionary = list[index]
	var hero := _hero()
	if String(HEROES.hero(hero).weapon) == String(entry.id):
		return "start"
	var sig := String(entry.get("signature", ""))
	if sig != "" and sig != hero:
		return "locked"
	return "on" if SESSION.profile().is_weapon_enabled(String(entry.id)) else "off"


func row_rect(index: int) -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 410.0, _oy() + ROW_TOP + float(index) * (ROW_H + ROW_GAP)), Vector2(820.0, ROW_H))


func switch_rect(index: int) -> Rect2:
	var row := row_rect(index)
	return Rect2(Vector2(row.end.x - 28.0 - PARTS.SWITCH.x, row.get_center().y - PARTS.SWITCH.y * 0.5), PARTS.SWITCH)


func badge_rect(index: int) -> Rect2:
	var row := row_rect(index)
	return Rect2(Vector2(row.end.x - 24.0 - BADGE.x, row.get_center().y - BADGE.y * 0.5), BADGE)


func done_rect() -> Rect2:
	return PARTS.done_rect(size.x, _oy())


## Switches weapon `index` in or out (only "on" / "off" rows). True if done.
func toggle(index: int) -> bool:
	var s := state(index)
	if s != "on" and s != "off":
		return false
	SESSION.profile().set_weapon_enabled(String(entries()[index].id), s == "off")
	SESSION.save_profile()
	return true


func tap(at: Vector2) -> void:
	for k in entries().size():
		if row_rect(k).has_point(at):
			if toggle(k):
				if menu != null:
					menu.click()
			elif menu != null and menu.has_method("deny"):
				menu.deny()
			queue_redraw()
			return
	if done_rect().grow(8.0).has_point(at) and menu != null:
		menu.show_screen("title")


func key(code: int) -> bool:
	if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if menu != null:
			menu.show_screen("title")
		return true
	return false


func _draw() -> void:
	var oy := _oy()
	var cx := size.x * 0.5
	PARTS.shade(self, Rect2(Vector2.ZERO, size), 0.84, 0.74, 0.88)
	PARTS.sheet_title(self, size.x, oy, "ARSENAL", "ember")
	Kit.paragraph(self, Vector2(cx - 410.0, oy + 200.0), HINT, 820.0, UiStyle.T_LABEL + 2, UiStyle.BRAWL_TEXT_DIM, false, Kit.CENTER, 2)
	for k in entries().size():
		_draw_row(k)
	PARTS.draw_done(self, done_rect())


func _draw_row(index: int) -> void:
	var entry: Dictionary = entries()[index]
	var row := row_rect(index)
	var s := state(index)
	var active := s == "on" or s == "start"
	Kit.panel(self, row, "dark", UiStyle.R_L, UiStyle.STROKE_M)
	var pc := Vector2(row.position.x + 92.0, row.get_center().y)
	var plate_tone: String = "ember" if s == "start" else ("loot" if s == "on" else "dark")
	Kit.icon_plate(self, pc, 124.0, plate_tone)
	Icons.draw(self, String(entry.icon), Kit.plate_center(pc, 124.0), 92.0)
	var x0 := row.position.x + 176.0
	var text_w := row.end.x - 24.0 - BADGE.x - 20.0 - x0
	var name_color := Color.WHITE if active else UiStyle.BRAWL_TEXT_DIM
	Kit.text_outlined(self, Vector2(x0, row.position.y + 54.0), String(entry.name).to_upper(), UiStyle.T_HEAD, name_color, -1, -1, null, Kit.LEFT | Kit.MIDDLE, text_w)
	Kit.paragraph(self, Vector2(x0, row.position.y + 98.0), String(entry.text), text_w, UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, false, Kit.LEFT, 2)
	if not active:
		# Switched off or locked: the row sinks back (the control stays bright).
		Kit.rrect(self, row.grow(-3.0), UiStyle.R_L - 3.0, Color(0.04, 0.03, 0.1, 0.4))
	match s:
		"start":
			_badge(badge_rect(index), "STARTWAFFE", "ember")
		"locked":
			_badge(badge_rect(index), locked_label(index), "neutral")
		_:
			PARTS.toggle(self, switch_rect(index), s == "on")


## "NUR BRINE" for a signature weapon of another hero.
func locked_label(index: int) -> String:
	var sig := String(entries()[index].get("signature", ""))
	var hero_name := String(HEROES.hero(sig).name) if HEROES.has(sig) else sig.capitalize()
	return "NUR " + hero_name.to_upper()


func _badge(rect: Rect2, label: String, tone: String) -> void:
	Kit.pill(self, rect, tone, UiStyle.STROKE_S)
	Kit.text_outlined(self, rect.get_center(), label, UiStyle.T_LABEL + 2, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, rect.size.x - 24.0)
