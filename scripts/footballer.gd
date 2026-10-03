class_name Footballer
extends Node2D
## One player. Movement is driven by `desired_velocity`, which the match sets
## each physics frame (from the touch input for the human, or from the AI).

const GK := 0
const DEF := 1
const MID := 2
const FWD := 3

var team := 0
var number := 1
var role := MID
## Formation slot in the team's own frame (attacking +x), both axes in [-1, 1].
var formation := Vector2.ZERO

var velocity := Vector2.ZERO
var desired_velocity := Vector2.ZERO
var facing := Vector2.RIGHT
var is_human := false
var tackle_cooldown := 0.0
var stun := 0.0
var decision_timer := 0.0


func step(delta: float) -> void:
	tackle_cooldown = maxf(tackle_cooldown - delta, 0.0)
	decision_timer -= delta
	var want := desired_velocity
	if stun > 0.0:
		stun -= delta
		want = Vector2.ZERO
	velocity = velocity.move_toward(want, Config.PLAYER_ACCEL * delta)
	position += velocity * delta
	position.x = clampf(position.x, -Config.HALF_L + 4, Config.HALF_L - 4)
	position.y = clampf(position.y, -Config.HALF_W + 4, Config.HALF_W - 4)
	if want.length() > 10.0:
		facing = facing.slerp(want.normalized(), minf(1.0, 14.0 * delta)).normalized()
	queue_redraw()


func _draw() -> void:
	var r := Config.PLAYER_RADIUS
	var col: Color = Config.KEEPER_COLORS[team] if role == GK else Config.TEAM_COLORS[team]

	draw_set_transform(Vector2(4, 9), 0, Vector2(1, 0.5))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	if is_human:
		draw_arc(Vector2.ZERO, r + 9, 0, TAU, 32, Config.INK, 7)
		draw_arc(Vector2.ZERO, r + 9, 0, TAU, 32, Color(1, 0.88, 0.2), 4)
		var top := Vector2(0, -r - 22)
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(-9, -12), top + Vector2(9, -12)]), Color(1, 0.88, 0.2))

	# Cel-shaded body: ink outline, flat base, hard-edged highlight.
	draw_circle(Vector2.ZERO, r + 3, Config.INK)
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.42, col.lightened(0.3))

	var side := facing.orthogonal()
	var tip := facing * (r + 9)
	draw_colored_polygon(PackedVector2Array([tip, facing * r * 0.55 + side * r * 0.55, facing * r * 0.55 - side * r * 0.55]), Config.INK)

	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-r, 6), str(number), HORIZONTAL_ALIGNMENT_CENTER, r * 2, 17, 4, Config.INK)
	draw_string(font, Vector2(-r, 6), str(number), HORIZONTAL_ALIGNMENT_CENTER, r * 2, 17, Color.WHITE)
