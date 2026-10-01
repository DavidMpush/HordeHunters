extends Control

# Etappe 4 Teil D: small performance overlay of the run (bottom left, above the
# DASH button: never under the top bar or the centre banners), switched by the profile setting show_fps
# ("FPS-ANZEIGE" in the settings):
#   60 FPS  16.7 ms  max 22.1        frames of the last second
#   [frame-time graph, last 2 s, line at 16.7 ms]
#   Skript 6.1 ms  Render 9.9 ms     _process work vs. the rest of the frame
#   DC 252  Obj 437  Gegner 198      draw calls, objects, living enemies
#   HOCH 80 %  MSAA 2x              quality tier, 3D render scale
# Text redraws 4x per second, the graph every frame (one polyline).
# attach(battle) (one line in battle.gd) also creates the quality governor
# (adaptive tiers, the overlay's data source) and the shader warm-up.

const SESSION := preload("res://scripts/core/session.gd")
const QUALITY := preload("res://scripts/world/quality.gd")
const GOVERNOR := preload("res://scripts/world/quality_governor.gd")
const WARMUP := preload("res://scripts/world/shader_warmup.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")

## Left margin and gap above the DASH button's touch area (centre at H - 190,
## touch radius 135: free above H - 325).
const MARGIN_X := 16.0
const ABOVE_BOTTOM := 340.0
const PANEL := Vector2(250.0, 128.0)
const GRAPH := Rect2(8.0, 30.0, 234.0, 34.0)
const GRAPH_FRAMES := 120
const GRAPH_MAX_MS := 50.0
const TEXT_HZ := 4.0
const FONT_SIZE := 16
const GOOD := Color(0.55, 1.0, 0.55)
const OK := Color(1.0, 0.85, 0.35)
const BAD := Color(1.0, 0.4, 0.35)

var battle: Node
var governor: Node
var warmup: Node3D
var lines: PackedStringArray = PackedStringArray()
var fps := 0.0
var avg_ms := 0.0
var worst_ms := 0.0
var _text_clock := 0.0
var _font: Font
var _graph := PackedVector2Array()
var _glyph_frames := 2
## Setting on: the node itself stays visible (its first draws warm the glyphs).
var _on := true


## Creates the overlay (HUD layer), the quality governor and the shader
## warm-up for a battle. Returns the overlay.
static func attach(owner_battle: Node) -> Control:
	var overlay: Control = load("res://scripts/ui/fps_overlay.gd").new()
	overlay.name = "FpsOverlay"
	overlay.battle = owner_battle
	var layer: CanvasLayer = owner_battle.get("hud_layer")
	if layer != null:
		layer.add_child(overlay)
	else:
		owner_battle.add_child(overlay)
	return overlay


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = PANEL
	_place()
	_font = ThemeDB.fallback_font
	_graph.resize(GRAPH_FRAMES)
	governor = GOVERNOR.new()
	governor.name = "QualityGovernor"
	if battle != null:
		governor.paused_check = func() -> bool: return battle.has_method("paused") and battle.paused()
	add_child(governor)
	var host: Node = battle.get_parent() if battle != null else null
	# No warm-up without a renderer (headless tests): nothing would compile.
	if host is Node3D and DisplayServer.get_name() != "headless":
		warmup = WARMUP.new()
		warmup.battle = battle
		warmup.effects = battle.get("effects")
		host.add_child.call_deferred(warmup)
	_on = shown()
	_refresh_text()


## The setting (default on while we test).
static func shown() -> bool:
	return bool(SESSION.setting("show_fps")) if SESSION.setting("show_fps") != null else true


func _process(delta: float) -> void:
	_text_clock -= delta
	if _text_clock <= 0.0:
		_text_clock = 1.0 / TEXT_HZ
		_on = shown()
		_place()
		if _on:
			_refresh_text()
	if _on or _glyph_frames > 0:
		queue_redraw()


func _place() -> void:
	var height := get_viewport_rect().size.y if is_inside_tree() else 1600.0
	position = Vector2(MARGIN_X, height - ABOVE_BOTTOM - PANEL.y)


func _refresh_text() -> void:
	if governor == null:
		return
	# Frames of the last second (real time).
	var total := 0.0
	var worst := 0.0
	var script := 0.0
	var count := 0
	while count < governor.filled and total < 1000.0:
		var ms: float = governor.frame_at(count)
		total += ms
		worst = maxf(worst, ms)
		script += governor.script_at(count)
		count += 1
	avg_ms = total / maxf(1.0, count)
	worst_ms = worst
	fps = 1000.0 * count / maxf(1.0, total)
	var script_avg := script / maxf(1.0, count)
	var enemies := 0
	if battle != null and battle.get("horde") != null:
		enemies = int(battle.horde.count())
	var viewport := get_viewport()
	var tier := QUALITY.current_tier()
	lines = PackedStringArray([
		"%d FPS  %.1f ms  max %.0f" % [roundi(fps), avg_ms, worst_ms],
		"Skript %.1f ms  Rest %.1f ms" % [script_avg, maxf(0.0, avg_ms - script_avg)],
		"DC %d  Obj %d  Gegner %d" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), enemies],
		"%s %d %%  MSAA %s%s" % [QUALITY.tier_name(tier), roundi(viewport.scaling_3d_scale * 100.0) if viewport != null else 100, _msaa_text(viewport), "  auto" if QUALITY.adaptive_enabled() else ""],
	])


static func _msaa_text(viewport: Viewport) -> String:
	if viewport == null:
		return "-"
	match viewport.msaa_3d:
		Viewport.MSAA_2X:
			return "2x"
		Viewport.MSAA_4X:
			return "4x"
		Viewport.MSAA_8X:
			return "8x"
	return "aus"


func _tone(ms: float) -> Color:
	if ms <= 17.5:
		return GOOD
	if ms <= 25.0:
		return OK
	return BAD


func _draw() -> void:
	if _glyph_frames > 0:
		_glyph_frames -= 1
		_warm_glyphs()
	if not _on or governor == null:
		return
	draw_rect(Rect2(Vector2.ZERO, PANEL), Color(0.04, 0.03, 0.08, 0.55))
	if lines.size() > 0:
		draw_string(_font, Vector2(8.0, 22.0), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 2, _tone(avg_ms))
	# Graph: background, 16.7 ms (60 fps) and 33 ms lines, frame times.
	draw_rect(GRAPH, Color(0, 0, 0, 0.35))
	for mark in [16.7, 33.3]:
		var y := GRAPH.end.y - GRAPH.size.y * float(mark) / GRAPH_MAX_MS
		draw_line(Vector2(GRAPH.position.x, y), Vector2(GRAPH.end.x, y), Color(1, 1, 1, 0.35 if mark < 20.0 else 0.18), 1.0)
	var count := mini(GRAPH_FRAMES, int(governor.filled))
	if count >= 2:
		var points := _graph
		points.resize(count)
		for k in count:
			var ms: float = minf(GRAPH_MAX_MS, governor.frame_at(k))
			points[k] = Vector2(GRAPH.end.x - GRAPH.size.x * float(k) / float(GRAPH_FRAMES - 1), GRAPH.end.y - GRAPH.size.y * ms / GRAPH_MAX_MS)
		draw_polyline(points, _tone(worst_ms), 1.5)
	for k in range(1, lines.size()):
		draw_string(_font, Vector2(8.0, GRAPH.end.y + 2.0 + 18.0 * k), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, 0.9))


## Damage numbers rasterise their glyphs at first use (a hitch at the first
## hit): draw the digits once off-screen in every size step they use.
func _warm_glyphs() -> void:
	var px := 30.0
	while px <= 90.0:
		UiStyle.text_px(self, "0123456789", Vector2(-4000.0, -4000.0), px, Color.WHITE, true, 9)
		px += 3.0
