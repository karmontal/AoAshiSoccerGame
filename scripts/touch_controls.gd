class_name TouchControls
extends Node2D
## Multi-touch controls: a floating joystick on one half of the screen and
## action buttons on the other (swapped in left-handed mode), plus a pause
## button. Buttons drive the same input actions the keyboard uses, so
## gameplay code only reads `vector` and the action map. Labels follow the
## situation: SHOOT/TACKLE, PASS/SWITCH/CALL, THROUGH/SLIDE.

const BASE_JOY_RADIUS := 90.0
const DEADZONE := 0.15
const BUTTON_DEFS := [
	{"action": "shoot", "label": "SHOOT", "color": Color(0.95, 0.35, 0.3), "radius": 62.0, "offset": Vector2(130, 140)},
	{"action": "pass", "label": "PASS", "color": Color(0.3, 0.75, 0.4), "radius": 52.0, "offset": Vector2(285, 85)},
	{"action": "special", "label": "THROUGH", "color": Color(0.95, 0.65, 0.2), "radius": 46.0, "offset": Vector2(280, 230)},
	{"action": "vision", "label": "VISION", "color": Color(0.3, 0.75, 1.0), "radius": 44.0, "offset": Vector2(125, 300)},
]
const PAUSE_RADIUS := 26.0
const COACH_BUTTONS := ["DROP", "BALANCE", "PRESS"]
const COACH_GREEN := Color(0.45, 1.0, 0.55)

var game: SoccerMatch
var vector := Vector2.ZERO

var _scale := 1.0
var _left_handed := false
var _joy_radius := BASE_JOY_RADIUS
var _joy_index := -1
var _joy_home := Vector2.ZERO
var _joy_center := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _pause_pos := Vector2.ZERO
var _buttons: Array[Dictionary] = []
var _coach_pick := 1


func _ready() -> void:
	for d: Dictionary in BUTTON_DEFS:
		var b := d.duplicate()
		b["index"] = -1
		b["pos"] = Vector2.ZERO
		_buttons.append(b)
	get_viewport().size_changed.connect(_layout)
	_layout()


func apply_settings() -> void:
	_scale = GameSettings.button_scale()
	_left_handed = GameSettings.enabled("left_handed")
	_layout()


func release_all() -> void:
	for b in _buttons:
		if b["index"] != -1:
			b["index"] = -1
			Input.action_release(b["action"])
	_release_joystick()


func _layout() -> void:
	var vs := get_viewport_rect().size
	_joy_radius = BASE_JOY_RADIUS * _scale
	var joy_x := 180.0 * _scale
	_joy_home = Vector2(vs.x - joy_x if _left_handed else joy_x, vs.y - 170 * _scale)
	if _joy_index == -1:
		_joy_center = _joy_home
		_joy_knob = _joy_home
	for b in _buttons:
		var off: Vector2 = b["offset"] * _scale
		b["pos"] = Vector2(off.x if _left_handed else vs.x - off.x, vs.y - off.y)
		b["size"] = b["radius"] * _scale
	_pause_pos = Vector2(vs.x - 44, 38)


func _in_match() -> bool:
	return game.state != SoccerMatch.State.MENU and game.state != SoccerMatch.State.FULLTIME \
		and game.state != SoccerMatch.State.CHALLENGE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_move_knob(event.position)
		get_viewport().set_input_as_handled()


func _on_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		for b in _buttons:
			if b["index"] == event.index:
				b["index"] = -1
				Input.action_release(b["action"])
		if event.index == _joy_index:
			_release_joystick()
		return

	if game.state == SoccerMatch.State.MENU:
		return  # Menu screens are Control nodes and handle their own input.
	if game.state == SoccerMatch.State.FULLTIME or game.state == SoccerMatch.State.CHALLENGE:
		if game.handle_screen_tap(event.position):
			get_viewport().set_input_as_handled()
		return
	if event.position.distance_to(_pause_pos) < PAUSE_RADIUS * 1.6:
		get_viewport().set_input_as_handled()
		game.pause_game()
		return
	if game.coach_view:
		get_viewport().set_input_as_handled()
		for i in COACH_BUTTONS.size():
			if _coach_rect(i).has_point(event.position):
				_coach_pick = i
				game.net.coach_mentality.rpc_id(1, i)
				return
		game.coach_tap(event.position)
		return
	for b in _buttons:
		if b["index"] == -1 and event.position.distance_to(b["pos"]) < b["size"] * 1.25:
			b["index"] = event.index
			Input.action_press(b["action"])
			get_viewport().set_input_as_handled()
			return
	if game.handle_screen_tap(event.position):
		get_viewport().set_input_as_handled()
		return
	var half := get_viewport_rect().size.x * 0.5
	var on_joy_side := event.position.x > half if _left_handed else event.position.x < half
	if _joy_index == -1 and on_joy_side:
		_joy_index = event.index
		_joy_center = event.position
		_move_knob(event.position)
		get_viewport().set_input_as_handled()


func _release_joystick() -> void:
	_joy_index = -1
	vector = Vector2.ZERO
	_joy_center = _joy_home
	_joy_knob = _joy_home


func _move_knob(pos: Vector2) -> void:
	var off := (pos - _joy_center).limit_length(_joy_radius)
	_joy_knob = _joy_center + off
	var v := off / _joy_radius
	vector = Vector2.ZERO if v.length() < DEADZONE else v


func _draw_pause() -> void:
	draw_circle(_pause_pos, PAUSE_RADIUS + 3, Color(Config.INK, 0.7))
	draw_circle(_pause_pos, PAUSE_RADIUS, Color(0.15, 0.2, 0.35, 0.85))
	for dx: float in [-6.0, 6.0]:
		draw_rect(Rect2(_pause_pos + Vector2(dx - 3, -10), Vector2(6, 20)), Color.WHITE)


func _coach_rect(i: int) -> Rect2:
	var vs := get_viewport_rect().size
	var w := 150.0
	return Rect2(vs.x - (3 - i) * (w + 12) - 8, vs.y - 74, w, 60)


func _draw_coach(font: Font) -> void:
	var vs := get_viewport_rect().size
	for i in COACH_BUTTONS.size():
		var r := _coach_rect(i)
		var on := i == _coach_pick
		draw_rect(r, Color(0.03, 0.06, 0.12, 0.85))
		draw_rect(r, COACH_GREEN if on else Color(1, 1, 1, 0.4), false, 3)
		draw_string(font, r.position + Vector2(0, 40), COACH_BUTTONS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, COACH_GREEN if on else Color.WHITE)
	var hint := "COACH  -  tap a player, then where to run"
	if game.coach_selected != null:
		hint = "Now tap where #%d should run" % game.coach_selected.number
		var p := game.camera.unproject_position(Config.to_3d(game.coach_selected.pos))
		draw_arc(p, 22, 0, TAU, 32, Config.INK, 7)
		draw_arc(p, 22, 0, TAU, 32, COACH_GREEN, 4)
	draw_string_outline(font, Vector2(16, vs.y - 30), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Config.INK)
	draw_string(font, Vector2(16, vs.y - 30), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COACH_GREEN)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _in_match():
		return
	var font := ThemeDB.fallback_font
	if game.coach_view:
		_draw_pause()
		_draw_coach(font)
		return
	draw_circle(_joy_center, _joy_radius, Color(1, 1, 1, 0.12))
	draw_arc(_joy_center, _joy_radius, 0, TAU, 48, Color(1, 1, 1, 0.4), 3)
	draw_circle(_joy_knob, 38 * _scale, Color(1, 1, 1, 0.45))
	draw_arc(_joy_knob, 38 * _scale, 0, TAU, 32, Config.INK, 3)

	_draw_pause()

	var has_ball := game.ball.holder == game.human
	var team_ball := game.ball.holder != null and game.ball.holder.team == game.human.team
	for b in _buttons:
		var pos: Vector2 = b["pos"]
		var radius: float = b["size"]
		var col: Color = b["color"]
		var label: String = b["label"]
		var dim := 1.0
		var charge := 0.0
		match b["action"]:
			"shoot":
				if has_ball:
					charge = game.charge_ratio("shoot")
				else:
					label = "TACKLE"
					dim = 0.45 if team_ball else 1.0
			"pass":
				if has_ball:
					charge = game.charge_ratio("pass")
					if charge >= 1.0:
						label = "LOB"
				else:
					label = "CALL" if game.mode == SoccerMatch.Mode.SOLO else "SWITCH"
			"special":
				if not has_ball:
					label = "SLIDE"
					dim = 0.45 if team_ball else 1.0
			"vision":
				if not game.vision.active and not game.vision.can_activate():
					dim = 0.45
		var pressed: bool = b["index"] != -1
		draw_circle(pos, radius + 4, Color(Config.INK, 0.6 * dim))
		draw_circle(pos, radius, Color(col.lightened(0.25) if pressed else col, 0.75 * dim))
		if b["action"] == "vision":
			var e := game.vision.energy
			draw_arc(pos, radius + 9, -PI / 2, -PI / 2 + TAU * e, 48, Color(0.6, 0.95, 1.0), 6)
		elif charge > 0.0:
			var ring := Color(1, 0.9, 0.3).lerp(Color(1, 0.3, 0.2), charge) if b["action"] == "shoot" else Color(1, 1, 1)
			draw_arc(pos, radius + 9, -PI / 2, -PI / 2 + TAU * charge, 48, Config.INK, 10)
			draw_arc(pos, radius + 9, -PI / 2, -PI / 2 + TAU * charge, 48, ring, 6)
		var fs := int((18 if label.length() > 6 else 20) * _scale)
		draw_string_outline(font, pos + Vector2(-radius, 8), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, fs, 5, Config.INK)
		draw_string(font, pos + Vector2(-radius, 8), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, fs, Color(1, 1, 1, dim))
