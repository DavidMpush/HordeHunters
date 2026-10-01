extends Control

# Hero choice of the menu (stage 3, Teil A §1): the chosen hero large on top
# (portrait, name, title, starting weapon, health, armor, short text), below a
# grid of tiles: playable heroes (Brann, Brine) and silhouettes of upcoming
# heroes with "BALD". Tapping a playable tile chooses it at once (saved in the
# profile); FERTIG / Esc returns to the title.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const HEROES := preload("res://scripts/menu/hero_catalog.gd")
const PARTS := preload("res://scripts/menu/menu_parts.gd")

const COLS := 3
const TILE := Vector2(252.0, 290.0)
const GAP := Vector2(32.0, 26.0)
const GRID_TOP := 676.0
const WEAPON_ICONS := {"shotgun": "shotgun", "fists": "burst"}

var menu: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _oy() -> float:
	return (size.y - 1600.0) * 0.5


## Tile ids in grid order: playable heroes, then "coming:<name>" slots.
func tiles() -> Array:
	var out: Array = HEROES.ids()
	for name in HEROES.COMING:
		if out.size() >= 6:
			break
		out.append("coming:" + name)
	return out


func tile_rect(index: int) -> Rect2:
	var col := index % COLS
	var row := index / COLS
	var x0 := size.x * 0.5 - (float(COLS) * TILE.x + float(COLS - 1) * GAP.x) * 0.5
	return Rect2(Vector2(x0 + float(col) * (TILE.x + GAP.x), _oy() + GRID_TOP + float(row) * (TILE.y + GAP.y)), TILE)


func done_rect() -> Rect2:
	return PARTS.done_rect(size.x, _oy())


func tap(at: Vector2) -> void:
	var list := tiles()
	for index in list.size():
		if tile_rect(index).has_point(at):
			var id: String = list[index]
			if not id.begins_with("coming:"):
				menu.choose_hero(id)
			else:
				menu.deny()
			return
	if done_rect().grow(8.0).has_point(at):
		menu.show_screen("title")


func key(code: int) -> bool:
	if code in [KEY_LEFT, KEY_RIGHT]:
		var ids: Array = HEROES.ids()
		var index := ids.find(menu.hero_id())
		index = posmod(index + (1 if code == KEY_RIGHT else -1), ids.size())
		menu.choose_hero(ids[index])
		return true
	if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		menu.show_screen("title")
		return true
	return false


func _draw() -> void:
	var oy := _oy()
	PARTS.shade(self, Rect2(Vector2.ZERO, size), 0.82, 0.7, 0.88)
	PARTS.sheet_title(self, size.x, oy, "HELDEN", "info")
	var current: String = menu.hero_id()
	_draw_detail(Rect2(Vector2(size.x * 0.5 - 410.0, oy + 196.0), Vector2(820.0, 440.0)), HEROES.hero(current))
	var list := tiles()
	for index in list.size():
		var id: String = list[index]
		if id.begins_with("coming:"):
			_draw_coming(tile_rect(index), id.substr(7))
		else:
			_draw_tile(tile_rect(index), HEROES.hero(id), id == current)
	PARTS.draw_done(self, done_rect())


func _draw_detail(rect: Rect2, hero: Dictionary) -> void:
	Kit.panel(self, rect, "dark", UiStyle.R_XL, UiStyle.STROKE_L)
	var pc := Vector2(rect.position.x + 186.0, rect.get_center().y)
	Kit.glow(self, pc, 150.0, "info", 0.3)
	HEROES.draw_portrait(self, String(hero.id), pc, 140.0, "info")
	var x0 := rect.position.x + 360.0
	var width := rect.end.x - 30.0 - x0
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 66.0), String(hero.name).to_upper(), UiStyle.T_HERO, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, width)
	Kit.text_outlined(self, Vector2(x0, rect.position.y + 122.0), String(hero.title), UiStyle.T_BODY, UiStyle.brawl_tone("loot")["light"], -1, -1, UiStyle.body_bold_font(), Kit.LEFT | Kit.MIDDLE, width)
	# Starting weapon chip.
	var chip := Rect2(Vector2(x0, rect.position.y + 156.0), Vector2(minf(width, 300.0), 60.0))
	Kit.pill(self, chip, "ember", UiStyle.STROKE_S)
	Icons.draw(self, String(WEAPON_ICONS.get(String(hero.weapon), "burst")), Vector2(chip.position.x + 34.0, chip.get_center().y), 48.0)
	Kit.text_outlined(self, Vector2(chip.position.x + 66.0, chip.get_center().y), String(hero.weapon_name).to_upper(), UiStyle.T_LABEL + 4, Color.WHITE, -1, -1, null, Kit.LEFT | Kit.MIDDLE, chip.size.x - 80.0)
	# Health and armor.
	var stats := [["heart", "LEBEN", str(int(hero.hp))], ["shield", "RÜSTUNG", "%d %%" % roundi(float(hero.armor) * 100.0)]]
	for k in stats.size():
		var cell := Rect2(Vector2(x0 + float(k) * (width * 0.5 + 6.0), rect.position.y + 232.0), Vector2(width * 0.5 - 6.0, 76.0))
		Kit.well(self, cell, UiStyle.R_M)
		Icons.draw(self, stats[k][0], Vector2(cell.position.x + 36.0, cell.get_center().y), 46.0)
		Kit.text_outlined(self, Vector2(cell.position.x + 68.0, cell.position.y + 24.0), stats[k][1], UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.LEFT | Kit.MIDDLE, cell.size.x - 76.0)
		Kit.number(self, Vector2(cell.position.x + 68.0, cell.position.y + 54.0), stats[k][2], UiStyle.T_BODY + 4, Color.WHITE, Kit.LEFT | Kit.MIDDLE, cell.size.x - 76.0)
	Kit.paragraph(self, Vector2(x0, rect.position.y + 344.0), String(hero.text), width, UiStyle.T_BODY, Color.WHITE, false, Kit.LEFT, 3)


func _draw_tile(rect: Rect2, hero: Dictionary, selected: bool) -> void:
	Kit.card(self, rect, "info" if selected else "neutral", "selected" if selected else "normal")
	var pc := Vector2(rect.get_center().x, rect.position.y + 112.0)
	HEROES.draw_portrait(self, String(hero.id), pc, 80.0, "info" if selected else "dark")
	Kit.text_outlined(self, Vector2(rect.get_center().x, rect.position.y + 222.0), String(hero.name).to_upper(), UiStyle.T_HEAD, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE, rect.size.x - 30.0)
	Kit.text_outlined(self, Vector2(rect.get_center().x, rect.position.y + 258.0), String(hero.weapon_name), UiStyle.T_LABEL, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE, rect.size.x - 30.0)
	if selected:
		var mark := Vector2(rect.end.x - 20.0, rect.position.y + 18.0)
		Kit.disc(self, mark + Vector2(0, 3), 24.0, UiStyle.BRAWL_INK_SOFT)
		Kit.disc(self, mark, 24.0, UiStyle.BRAWL_INK)
		Kit.disc(self, mark, 20.0, UiStyle.brawl_tone("action")["face"])
		var tick := PackedVector2Array([mark + Vector2(-10, 0), mark + Vector2(-3, 8), mark + Vector2(11, -8)])
		draw_polyline(tick, Color.WHITE, 6.0, true)


func _draw_coming(rect: Rect2, name: String) -> void:
	Kit.card(self, rect, "dark", "disabled")
	var pc := Vector2(rect.get_center().x, rect.position.y + 112.0)
	HEROES.draw_silhouette(self, pc, 80.0)
	Kit.text_outlined(self, Vector2(rect.get_center().x, rect.position.y + 222.0), "???", UiStyle.T_HEAD, UiStyle.BRAWL_TEXT_DIM, -1, -1, null, Kit.CENTER | Kit.MIDDLE, rect.size.x - 30.0)
	var chip := Rect2(Vector2(rect.get_center().x - 50.0, rect.position.y + 240.0), Vector2(100.0, 36.0))
	Kit.chip(self, chip, "special")
	Kit.text_outlined(self, chip.get_center() + Vector2(0, -1), "BALD", UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
