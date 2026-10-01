extends Control

# Statistics of the menu (stage 3, Teil A §1): runs in total and per hero the
# best run (time survived, kills, level) from the profile. FERTIG / Esc
# returns to the title.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const PARTS := preload("res://scripts/menu/menu_parts.gd")
const HEROES := preload("res://scripts/menu/hero_catalog.gd")
const SESSION := preload("res://scripts/core/session.gd")
const RUN := preload("res://scripts/core/run.gd")

var menu: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _oy() -> float:
	return (size.y - 1600.0) * 0.5


func done_rect() -> Rect2:
	return PARTS.done_rect(size.x, _oy())


func tap(at: Vector2) -> void:
	if done_rect().grow(8.0).has_point(at):
		menu.show_screen("title")


func key(code: int) -> bool:
	if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		menu.show_screen("title")
		return true
	return false


func _draw() -> void:
	var oy := _oy()
	var cx := size.x * 0.5
	PARTS.shade(self, Rect2(Vector2.ZERO, size), 0.84, 0.74, 0.88)
	PARTS.sheet_title(self, size.x, oy, "STATISTIK", "loot")
	var profile: RefCounted = SESSION.profile()
	# Runs in total.
	var total := Rect2(Vector2(cx - 410.0, oy + 210.0), Vector2(820.0, 140.0))
	Kit.panel(self, total, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	Kit.icon_plate(self, Vector2(total.position.x + 80.0, total.get_center().y), 92.0, "loot")
	Icons.draw(self, "trophy", Kit.plate_center(Vector2(total.position.x + 80.0, total.get_center().y), 92.0), 66.0)
	Kit.text_outlined(self, Vector2(total.position.x + 150.0, total.get_center().y), "RUNS GESAMT", UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE)
	Kit.number(self, Vector2(total.end.x - 40.0, total.get_center().y + 2.0), Kit.format_int(int(profile.runs_total)), UiStyle.T_HERO, UiStyle.brawl_tone("loot")["light"], Kit.RIGHT | Kit.MIDDLE)
	var ids: Array = HEROES.ids()
	for index in mini(ids.size(), 3):
		_draw_hero(Rect2(Vector2(cx - 410.0, oy + 390.0 + float(index) * 320.0), Vector2(820.0, 296.0)), String(ids[index]), profile.record(String(ids[index])))
	PARTS.draw_done(self, done_rect())


func _draw_hero(rect: Rect2, id: String, record: Dictionary) -> void:
	var hero := HEROES.hero(id)
	Kit.panel(self, rect, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	var pc := Vector2(rect.position.x + 96.0, rect.position.y + 92.0)
	HEROES.draw_portrait(self, id, pc, 62.0, "dark")
	var x0 := rect.position.x + 186.0
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 66.0), String(hero.name).to_upper(), UiStyle.T_TITLE, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, 380.0)
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 112.0), String(hero.title), UiStyle.T_BODY, UiStyle.BRAWL_TEXT_DIM, -1, -1, UiStyle.body_bold_font(), Kit.LEFT | Kit.MIDDLE, 380.0)
	var runs := int(record.get("runs", 0))
	var chip := Rect2(Vector2(rect.end.x - 30.0 - 170.0, rect.position.y + 40.0), Vector2(170.0, 56.0))
	Kit.pill(self, chip, "dark", UiStyle.STROKE_S)
	Kit.text_outlined(self, chip.get_center(), "%d %s" % [runs, "RUN" if runs == 1 else "RUNS"], UiStyle.T_LABEL + 4, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, chip.size.x - 20.0)
	var none := runs <= 0
	var cells := [
		["BESTE ZEIT", RUN.clock(float(record.get("best_time", 0.0))) if not none else "-", "info"],
		["KILLS", Kit.format_int(int(record.get("best_kills", 0))) if not none else "-", "danger"],
		["LEVEL", str(int(record.get("best_level", 0))) if not none else "-", "special"],
	]
	var inner_w := rect.size.x - 60.0
	var w := (inner_w - 2.0 * 14.0) / 3.0
	for k in 3:
		var cell := Rect2(Vector2(rect.position.x + 30.0 + float(k) * (w + 14.0), rect.position.y + 168.0), Vector2(w, 100.0))
		Kit.well(self, cell, UiStyle.R_M)
		Kit.text_outlined(self, Vector2(cell.get_center().x, cell.position.y + 26.0), cells[k][0], UiStyle.T_LABEL, UiStyle.brawl_tone(cells[k][2])["light"], -1, -1, null, Kit.CENTER | Kit.MIDDLE, w - 16.0)
		Kit.number(self, Vector2(cell.get_center().x, cell.position.y + 66.0), cells[k][1], UiStyle.T_HEAD, Color.WHITE if not none else UiStyle.BRAWL_TEXT_DIM, Kit.CENTER | Kit.MIDDLE, w - 16.0)
