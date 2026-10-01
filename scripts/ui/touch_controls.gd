extends Control

# Input of stage 1 (after Mawlings touch_controls.gd): floating joystick on the
# right (a touch in the right movement zone puts the stick origin under the
# thumb), dash button on the left (brawl style), keyboard WASD/arrows + Space.
# On the result screen a tap on NOCHMAL (rect from hud.gd) or R/Enter/Space
# restarts; MENÜ (tap, M, Esc) asks for the menu (main.gd switches scenes). Draws the joystick and the dash button itself.

signal dash_requested
signal restart_requested
## Stage 3: MENÜ on the result screen (tap, M or Esc).
signal menu_requested

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Kit := preload("res://scripts/ui/ui_kit_brawl.gd")

const MOVE_RADIUS := 70.0        # displacement for full speed
const MOVE_FRAME_R := 118.0      # drawn joystick frame
const MOVE_ZONE_TOP := 0.28      # zone starts below the top HUD (share of height)
const MOVE_ZONE_LEFT := 0.42     # and right of this share of the width
const DASH_R := 92.0
const DASH_TOUCH_R := 135.0

var movement_vector := Vector2.ZERO
var movement_pointer := -1
var dash_pointer := -1
var dash_presses := 0
var _origin := Vector2.INF
var _knob := Vector2.ZERO
var _dash_flash := 0.0
var _denied := 0.0
var _key := []

## Fed by battle.gd every frame.
var dash_charge := 0.0           # 0 = ready, 1 = just used
var dead := false
var result_button := Rect2()     # NOCHMAL hit area while the result shows
var result_menu_button := Rect2()  # MENÜ hit area next to it
var show_result := false
## A choice screen is open (level-up, cocoon): no stick, no dash.
var blocked := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_pointers()


func clear_pointers() -> void:
	movement_vector = Vector2.ZERO
	movement_pointer = -1
	dash_pointer = -1
	_origin = Vector2.INF


## Stick or keyboard direction (x right, y down), length <= 1.
func move_vector() -> Vector2:
	if movement_pointer != -1:
		return movement_vector
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	return input.normalized() if input != Vector2.ZERO else Vector2.ZERO


func request_dash() -> void:
	if dead:
		return
	dash_presses += 1
	if dash_charge > 0.0:
		_denied = 0.25
	else:
		_dash_flash = 0.3
	dash_requested.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if dead and show_result and event.keycode in [KEY_R, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
			restart_requested.emit()
		elif dead and show_result and event.keycode in [KEY_M, KEY_ESCAPE]:
			menu_requested.emit()
		elif not dead and not blocked and event.keycode in [KEY_SPACE, KEY_SHIFT]:
			request_dash()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag and event.index == movement_pointer:
		_update_movement(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			_press(-2, event.position)
		else:
			_release(-2)
	elif event is InputEventMouseMotion and movement_pointer == -2 and event.device != InputEvent.DEVICE_ID_EMULATION:
		_update_movement(event.position)


func _press(pointer: int, location: Vector2) -> void:
	if dead:
		if show_result and result_button.grow(12.0).has_point(location):
			restart_requested.emit()
		elif show_result and result_menu_button.size.x > 0.0 and result_menu_button.grow(12.0).has_point(location):
			menu_requested.emit()
		return
	if blocked:
		return
	if dash_pointer == -1 and location.distance_to(dash_center()) < DASH_TOUCH_R:
		dash_pointer = pointer
		request_dash()
		return
	if movement_pointer == -1 and _in_movement_zone(location):
		movement_pointer = pointer
		var r := MOVE_FRAME_R
		_origin = Vector2(clampf(location.x, r, size.x - r), clampf(location.y, r, size.y - r))
		_update_movement(location)


func _release(pointer: int) -> void:
	if pointer == movement_pointer:
		movement_pointer = -1
		movement_vector = Vector2.ZERO
		_origin = Vector2.INF
	if pointer == dash_pointer:
		dash_pointer = -1


func _update_movement(location: Vector2) -> void:
	movement_vector = ((location - _origin) / MOVE_RADIUS).limit_length(1.0)


func _in_movement_zone(location: Vector2) -> bool:
	if location.distance_to(movement_rest_center()) < MOVE_FRAME_R:
		return true
	return location.x >= size.x * MOVE_ZONE_LEFT and location.y >= size.y * MOVE_ZONE_TOP


func movement_rest_center() -> Vector2:
	return Vector2(size.x - 150.0, size.y - 190.0)


func dash_center() -> Vector2:
	return Vector2(150.0, size.y - 190.0)


func _process(delta: float) -> void:
	_dash_flash = maxf(0.0, _dash_flash - delta)
	_denied = maxf(0.0, _denied - delta)
	var knob := movement_vector * MOVE_RADIUS
	_knob = _knob.lerp(knob, 1.0 - exp(-30.0 * delta))
	# Repaint only when something visible changed (the kit shapes are costly).
	var key := [dead, blocked, movement_pointer != -1, _origin.round(), _knob.round(), snappedf(dash_charge, 0.01), dash_pointer != -1, snappedf(_dash_flash, 0.02), snappedf(_denied, 0.02), size]
	if key != _key:
		_key = key
		queue_redraw()


func _draw() -> void:
	# Hidden while dead or while a choice screen is open (its buttons sit there).
	if dead or blocked:
		return
	_draw_joystick()
	_draw_dash()


func _draw_joystick() -> void:
	var active := movement_pointer != -1 and _origin != Vector2.INF
	var center := _origin if active else movement_rest_center()
	var alpha := 0.9 if active else 0.38
	Kit.disc(self, center + Vector2(0, 5), MOVE_FRAME_R, Color(UiStyle.BRAWL_INK, 0.25 * alpha))
	Kit.disc(self, center, MOVE_FRAME_R, Color(UiStyle.BRAWL_WELL, 0.45 * alpha))
	Kit.circle_ring(self, center, MOVE_FRAME_R, 5.0, Color(UiStyle.BRAWL_INK, 0.8 * alpha))
	Kit.circle_ring(self, center, MOVE_FRAME_R - 5.0, 3.0, Color(1, 1, 1, 0.22 * alpha))
	var knob_at := center + (_knob if active else Vector2.ZERO)
	Kit.round_button(self, knob_at, 50.0, "ember" if active else "neutral", false)


func _draw_dash() -> void:
	var center := dash_center()
	var ready := dash_charge <= 0.0
	var shake := Vector2(sin(_denied * 80.0) * 6.0 * (_denied / 0.25), 0.0)
	var pressed := dash_pointer != -1 or _dash_flash > 0.15
	var tone: Variant = "info" if ready else "neutral"
	Kit.round_button(self, center + shake, DASH_R, tone, pressed)
	var label := Kit.round_label_center(center + shake, DASH_R, pressed)
	# Chevrons ">>" as the dash icon.
	var icon_tone: Variant = Color.WHITE if ready else Color(0.75, 0.75, 0.85)
	Kit.chevron(self, label + Vector2(-16, -10), Vector2.RIGHT, 40.0, icon_tone)
	Kit.chevron(self, label + Vector2(14, -10), Vector2.RIGHT, 40.0, icon_tone)
	Kit.text_outlined(self, label + Vector2(0, 40), "DASH", UiStyle.T_LABEL, Color.WHITE, -1, -1, null, Kit.CENTER | Kit.MIDDLE)
	if not ready:
		# Cooldown: dark pie that shrinks clockwise, seconds in the middle.
		var pts := PackedVector2Array([center + shake])
		var steps := 40
		for k in steps + 1:
			var a := -PI * 0.5 + TAU * dash_charge * float(k) / float(steps)
			pts.append(center + shake + Vector2(cos(a), sin(a)) * (DASH_R - 6.0))
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(UiStyle.BRAWL_INK, 0.55))
	if _dash_flash > 0.0:
		Kit.circle_ring(self, center, DASH_R + 16.0 * (1.0 - _dash_flash / 0.3), 6.0, Color(0.5, 0.9, 1.0, _dash_flash / 0.3))
