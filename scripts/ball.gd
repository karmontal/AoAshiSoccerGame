class_name Ball
extends Node2D
## Arcade ball physics with a fake height axis for lofted passes.
## The touchlines and goal lines act as walls, except for the goal mouth.

signal goal_scored(scoring_team: int)

const GRAVITY := 980.0
const GROUND_DAMP := 1.25
const AIR_DAMP := 0.35
const CROSSBAR := 70.0
const CONTROL_HEIGHT := 32.0

var velocity := Vector2.ZERO
var height := 0.0
var vz := 0.0
var holder: Footballer = null
var intended_receiver: Footballer = null
var last_kicker: Footballer = null
var frozen := false
var _ignore_kicker := 0.0
var _spin := 0.0


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_ignore_kicker = maxf(_ignore_kicker - delta, 0.0)
	if holder != null:
		position = holder.position + holder.facing * (Config.PLAYER_RADIUS + Config.BALL_RADIUS + 2.0)
		velocity = holder.velocity
		height = 0.0
		vz = 0.0
	else:
		if height > 0.0 or vz > 0.0:
			vz -= GRAVITY * delta
			height += vz * delta
			if height <= 0.0:
				height = 0.0
				vz = -vz * 0.4 if absf(vz) > 150.0 else 0.0
			velocity *= exp(-AIR_DAMP * delta)
		else:
			velocity *= exp(-GROUND_DAMP * delta)
		if velocity.length() < 4.0:
			velocity = Vector2.ZERO
		position += velocity * delta
	_spin += velocity.length() * delta * 0.05
	_check_bounds()
	queue_redraw()


func _check_bounds() -> void:
	if absf(position.x) > Config.HALF_L:
		var side := signf(position.x)
		var in_mouth := absf(position.y) < Config.GOAL_WIDTH / 2 - Config.BALL_RADIUS and height < CROSSBAR
		if in_mouth:
			if absf(position.x) > Config.HALF_L + Config.BALL_RADIUS:
				frozen = true
				holder = null
				velocity = Vector2.ZERO
				goal_scored.emit(0 if side > 0 else 1)
			return
		position.x = side * Config.HALF_L
		velocity.x = -velocity.x * 0.5
	if absf(position.y) > Config.HALF_W:
		position.y = signf(position.y) * Config.HALF_W
		velocity.y = -velocity.y * 0.5


func kick(vel: Vector2, lift: float, kicker: Footballer, receiver: Footballer = null) -> void:
	holder = null
	velocity = vel
	vz = lift
	if lift > 0.0:
		height = maxf(height, 1.0)
	last_kicker = kicker
	intended_receiver = receiver
	_ignore_kicker = 0.22


## Knock the ball away after a failed first touch on a fast ball.
func deflect(by: Footballer) -> void:
	velocity = velocity.rotated(randf_range(2.2, 4.1)) * 0.35
	last_kicker = by
	intended_receiver = null
	_ignore_kicker = 0.25


func can_be_taken_by(p: Footballer) -> bool:
	return not frozen and height < CONTROL_HEIGHT and not (p == last_kicker and _ignore_kicker > 0.0)


func place(pos: Vector2) -> void:
	holder = null
	intended_receiver = null
	last_kicker = null
	position = pos
	velocity = Vector2.ZERO
	height = 0.0
	vz = 0.0
	frozen = false


func _draw() -> void:
	var r := Config.BALL_RADIUS
	var s := 1.0 + height / 220.0
	draw_set_transform(Vector2(2, 5), 0, Vector2(1, 0.5))
	draw_circle(Vector2.ZERO, r * (1.0 - minf(height / 300.0, 0.5)), Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	var c := Vector2(0, -height * 0.6)
	var speed := velocity.length()
	if holder == null and speed > 650.0:
		# Anime speed lines trailing the ball.
		var back := -velocity / speed
		var side := back.orthogonal()
		for i in 4:
			var off := side * (float(i) - 1.5) * 5.0
			var length := 30.0 + 18.0 * float((i * 7) % 3)
			draw_line(c + off + back * (r + 4), c + off + back * (r + 4 + length), Color(1, 1, 1, 0.55), 2.0)
	draw_circle(c, r * s + 2, Config.INK)
	draw_circle(c, r * s, Color.WHITE)
	draw_circle(c + Vector2(cos(_spin), sin(_spin)) * r * 0.45 * s, r * 0.35 * s, Config.INK)
