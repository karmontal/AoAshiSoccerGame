class_name Pitch
extends Node2D
## Draws the pitch: striped grass, markings and both goals.

const LINE_COLOR := Color(1, 1, 1, 0.85)
const GRASS_A := Color(0.20, 0.56, 0.26)
const GRASS_B := Color(0.18, 0.50, 0.23)
const SURROUND := Color(0.12, 0.36, 0.17)
const LINE_W := 4.0


func _draw() -> void:
	var hl := Config.HALF_L
	var hw := Config.HALF_W
	draw_rect(Rect2(-hl - 400, -hw - 400, Config.PITCH_LENGTH + 800, Config.PITCH_WIDTH + 800), SURROUND)

	var stripes := 12
	var sw := Config.PITCH_LENGTH / stripes
	for i in stripes:
		draw_rect(Rect2(-hl + i * sw, -hw, sw, Config.PITCH_WIDTH), GRASS_A if i % 2 == 0 else GRASS_B)

	draw_rect(Rect2(-hl, -hw, Config.PITCH_LENGTH, Config.PITCH_WIDTH), LINE_COLOR, false, LINE_W)
	draw_line(Vector2(0, -hw), Vector2(0, hw), LINE_COLOR, LINE_W)
	draw_arc(Vector2.ZERO, Config.CENTER_CIRCLE, 0, TAU, 64, LINE_COLOR, LINE_W)
	draw_circle(Vector2.ZERO, 6, LINE_COLOR)

	for side: float in [-1.0, 1.0]:
		draw_rect(_box_rect(side, Config.BOX_DEPTH, Config.BOX_WIDTH), LINE_COLOR, false, LINE_W)
		draw_rect(_box_rect(side, Config.SMALL_BOX_DEPTH, Config.SMALL_BOX_WIDTH), LINE_COLOR, false, LINE_W)
		draw_circle(Vector2(side * (hl - 220), 0), 5, LINE_COLOR)
		var arc_center := Vector2(side * (hl - 220), 0)
		var start := PI - 0.74 if side > 0 else -0.74
		draw_arc(arc_center, 150, start, start + 1.48, 24, LINE_COLOR, LINE_W)
		_draw_goal(side)


func _box_rect(side: float, depth: float, width: float) -> Rect2:
	var x := Config.HALF_L - depth if side > 0 else -Config.HALF_L
	return Rect2(x, -width / 2, depth, width)


func _draw_goal(side: float) -> void:
	var gx := side * Config.HALF_L
	var x0 := gx if side > 0 else gx - Config.GOAL_DEPTH
	var goal := Rect2(x0, -Config.GOAL_WIDTH / 2, Config.GOAL_DEPTH, Config.GOAL_WIDTH)
	draw_rect(goal, Color(1, 1, 1, 0.15))
	var net := Color(1, 1, 1, 0.35)
	var y := goal.position.y
	while y < goal.end.y:
		draw_line(Vector2(goal.position.x, y), Vector2(goal.end.x, y), net, 1.5)
		y += 14
	var x := goal.position.x
	while x < goal.end.x:
		draw_line(Vector2(x, goal.position.y), Vector2(x, goal.end.y), net, 1.5)
		x += 14
	draw_rect(goal, Config.INK, false, 9)
	draw_rect(goal, Color.WHITE, false, 5)
