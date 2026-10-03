class_name TouchControls
extends Node2D
## Multi-touch controls: a floating joystick on the left half of the screen and
## action buttons on the right. Buttons drive the same input actions the
## keyboard uses, so gameplay code only reads `vector` and the action map.

const JOY_RADIUS := 90.0
const DEADZONE := 0.15

var game: SoccerMatch
var vector := Vector2.ZERO

var _joy_index := -1
var _joy_home := Vector2.ZERO
var _joy_center := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _buttons: Array[Dictionary] = []


func _ready() -> void:
	_buttons = [
		{"action": "shoot", "label": "SHOOT", "color": Color(0.95, 0.35, 0.3), "radius": 66.0},
		{"action": "pass", "label": "PASS", "color": Color(0.3, 0.75, 0.4), "radius": 54.0},
		{"action": "vision", "label": "VISION", "color": Color(0.3, 0.75, 1.0), "radius": 48.0},
	]
	for b in _buttons:
		b["index"] = -1
		b["pos"] = Vector2.ZERO
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := get_viewport_rect().size
	_joy_home = Vector2(180, vs.y - 170)
	if _joy_index == -1:
		_joy_center = _joy_home
		_joy_knob = _joy_home
	_buttons[0]["pos"] = Vector2(vs.x - 130, vs.y - 140)
	_buttons[1]["pos"] = Vector2(vs.x - 290, vs.y - 90)
	_buttons[2]["pos"] = Vector2(vs.x - 150, vs.y - 310)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_move_knob(event.position)
		get_viewport().set_input_as_handled()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		for b in _buttons:
			if b["index"] == -1 and event.position.distance_to(b["pos"]) < b["radius"] * 1.25:
				b["index"] = event.index
				Input.action_press(b["action"])
				get_viewport().set_input_as_handled()
				return
		if game.handle_screen_tap(event.position):
			get_viewport().set_input_as_handled()
			return
		if _joy_index == -1 and event.position.x < get_viewport_rect().size.x * 0.5:
			_joy_index = event.index
			_joy_center = event.position
			_move_knob(event.position)
			get_viewport().set_input_as_handled()
	else:
		for b in _buttons:
			if b["index"] == event.index:
				b["index"] = -1
				Input.action_release(b["action"])
		if event.index == _joy_index:
			_joy_index = -1
			vector = Vector2.ZERO
			_joy_center = _joy_home
			_joy_knob = _joy_home


func _move_knob(pos: Vector2) -> void:
	var off := (pos - _joy_center).limit_length(JOY_RADIUS)
	_joy_knob = _joy_center + off
	var v := off / JOY_RADIUS
	vector = Vector2.ZERO if v.length() < DEADZONE else v


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_circle(_joy_center, JOY_RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(_joy_center, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 3)
	draw_circle(_joy_knob, 38, Color(1, 1, 1, 0.45))
	draw_arc(_joy_knob, 38, 0, TAU, 32, Config.INK, 3)

	var has_ball := game.ball.holder == game.human
	for b in _buttons:
		var pos: Vector2 = b["pos"]
		var radius: float = b["radius"]
		var col: Color = b["color"]
		var label: String = b["label"]
		if b["action"] == "pass" and not has_ball:
			label = "SWITCH"
		var dim := 1.0
		if b["action"] == "shoot" and not has_ball:
			dim = 0.45
		if b["action"] == "vision" and not game.vision.active and not game.vision.can_activate():
			dim = 0.45
		var pressed: bool = b["index"] != -1
		draw_circle(pos, radius + 4, Color(Config.INK, 0.6 * dim))
		draw_circle(pos, radius, Color(col.lightened(0.25) if pressed else col, 0.75 * dim))
		if b["action"] == "vision":
			var e := game.vision.energy
			draw_arc(pos, radius + 9, -PI / 2, -PI / 2 + TAU * e, 48, Color(0.6, 0.95, 1.0), 6)
		draw_string_outline(font, pos + Vector2(-radius, 8), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 20, 5, Config.INK)
		draw_string(font, pos + Vector2(-radius, 8), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 20, Color(1, 1, 1, dim))
