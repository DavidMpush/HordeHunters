extends RefCounted

# Volume slider row of the brawl kit, shared by the pause panel and the menu's
# settings sheet (after Mawlings _paint_pause_volumes): a well with the name
# left, the percent right ("AUS" at 0) and a bar with a white knob below.
# Geometry helpers turn a tap/drag x into a snapped 0..1 value.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")
const AUDIO := preload("res://scripts/core/audio_settings.gd")

const TONES := {"volume_master": "info", "volume_music": "loot", "volume_sfx": "ember"}
const ROW_H := 96.0


## Bar inside a slider row.
static func track(row: Rect2) -> Rect2:
	return Rect2(Vector2(row.position.x + 24.0, row.position.y + 60.0), Vector2(row.size.x - 48.0, 22.0))


## Touch area of a row (generous: the whole well plus a margin).
static func hit(row: Rect2) -> Rect2:
	return row.grow(6.0)


## Slider value for a pointer at x (snapped to 5 %).
static func value_at(row: Rect2, x: float) -> float:
	var bar := track(row)
	return AUDIO.snap((x - bar.position.x) / maxf(1.0, bar.size.x))


static func draw(c: CanvasItem, row: Rect2, key: String, value: float, active: bool = false) -> void:
	var muted := value <= 0.001
	var tone: String = "neutral" if muted else String(TONES.get(key, "info"))
	Kit.well(c, row, UiStyle.R_M)
	if active:
		Kit.ring(c, row.grow(3.0), UiStyle.R_M + 3.0, 3.0, UiStyle.brawl_tone("info")["light"])
	var label := String(AUDIO.NAMES.get(key, key))
	var ink := Color.WHITE if not muted else UiStyle.BRAWL_TEXT_DIM
	Kit.text_outlined(c, Vector2(row.position.x + 22.0, row.position.y + 30.0), label, UiStyle.T_LABEL, ink, -1, -1, null, Kit.LEFT | Kit.MIDDLE, row.size.x * 0.55)
	Kit.number(c, Vector2(row.end.x - 22.0, row.position.y + 30.0), "AUS" if muted else "%d %%" % roundi(value * 100.0), UiStyle.T_LABEL, ink, Kit.RIGHT | Kit.MIDDLE, row.size.x * 0.4)
	var bar := track(row)
	Kit.bar(c, bar, value, tone)
	var knob := Vector2(bar.position.x + bar.size.x * value, bar.get_center().y)
	Kit.disc(c, knob + Vector2(0, 3), 19.0, UiStyle.BRAWL_INK_SOFT)
	Kit.disc(c, knob, 19.0, UiStyle.BRAWL_INK)
	Kit.disc(c, knob, 14.0, Color.WHITE)
