class_name FieldVision
extends Node2D
## "Field vision": the signature ability. Slows time, pulls the camera up to a
## bird's-eye view and paints every passing lane so the player can read the game.
## With the ball: lanes to teammates (green = open, yellow = risky, red = blocked)
## and a tap on a teammate plays the pass. Without it: the carrier's options,
## so you can see which lane to cut off.

const SLOW_SCALE := 0.18
const DRAIN_PER_SEC := 0.30
const RECHARGE_PER_SEC := 0.07
const MIN_ENERGY := 0.25

const OPEN := Color(0.35, 1.0, 0.55)
const RISKY := Color(1.0, 0.85, 0.25)
const BLOCKED := Color(1.0, 0.3, 0.3)
const TINT := Color(0.02, 0.06, 0.18, 0.5)
const GRID := Color(0.4, 0.8, 1.0, 0.14)

var game: SoccerMatch
var energy := 1.0
var active := false
var _t := 0.0


func can_activate() -> bool:
	return energy >= MIN_ENERGY and game.state == SoccerMatch.State.PLAYING


func toggle() -> void:
	if active:
		deactivate()
	else:
		activate()


func activate() -> void:
	if active or not can_activate():
		return
	active = true
	Engine.time_scale = SLOW_SCALE
	game.hud.show_banner("VISION", Color(0.3, 0.8, 1.0), 0.8, 0.6)


func deactivate() -> void:
	if not active:
		return
	active = false
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	if active:
		energy -= DRAIN_PER_SEC * real
		if energy <= 0.0:
			energy = 0.0
			deactivate()
	else:
		energy = minf(1.0, energy + RECHARGE_PER_SEC * real)
	queue_redraw()


static func lane_color(clearance: float) -> Color:
	if clearance > 60.0:
		return OPEN
	if clearance > 30.0:
		return RISKY
	return BLOCKED


func _draw() -> void:
	if not active:
		return
	var hl := Config.HALF_L
	var hw := Config.HALF_W
	draw_rect(Rect2(-hl - 500, -hw - 500, Config.PITCH_LENGTH + 1000, Config.PITCH_WIDTH + 1000), TINT)
	for i in range(-5, 6):
		draw_line(Vector2(i * hl / 5.0, -hw), Vector2(i * hl / 5.0, hw), GRID, 2.0 * maxf(1.0, 0.7 / maxf(game.camera.zoom.x, 0.1)))
	for i in range(-3, 4):
		draw_line(Vector2(-hl, i * hw / 3.0), Vector2(hl, i * hw / 3.0), GRID, 2.0 * maxf(1.0, 0.7 / maxf(game.camera.zoom.x, 0.1)))

	var carrier: Footballer = game.ball.holder
	if carrier == null:
		carrier = game.human
	var mates: Array = game.teams[carrier.team]
	var opponents: Array = game.teams[1 - carrier.team]
	# Strokes are in world units; scale them so they stay readable when zoomed out.
	var k := 0.7 / maxf(game.camera.zoom.x, 0.1)
	var pulse := sin(_t * 7.0) * 3.0 * k

	for o: Footballer in opponents:
		draw_arc(o.position, Config.PLAYER_RADIUS + 10 * k, 0, TAU, 24, Color(1, 0.3, 0.3, 0.7), 3 * k)

	var best: Footballer = game.best_pass_target(carrier, carrier.facing)
	for mate: Footballer in mates:
		if mate == carrier:
			continue
		var clearance := game.lane_clearance(carrier.position, mate.position, 1 - carrier.team)
		var col := lane_color(clearance)
		if carrier.team != 0:
			col = col.lerp(Color(1, 0.4, 0.2), 0.5)
		var width := (7.0 if mate == best else 3.0) * k
		draw_dashed_line(carrier.position, mate.position, Config.INK, width + 4.0 * k, 18.0 * k)
		draw_dashed_line(carrier.position, mate.position, col, width, 18.0 * k)
		draw_arc(mate.position, Config.PLAYER_RADIUS + 14 * k + pulse, 0, TAU, 32, col, 4 * k)

	if best != null:
		var font := ThemeDB.fallback_font
		var label := "BEST" if carrier.team == 0 else "DANGER"
		var size := int(24 * k)
		var pos := best.position + Vector2(-100 * k, -Config.PLAYER_RADIUS - 26 * k)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200 * k, size, int(6 * k), Config.INK)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200 * k, size, Color(1, 0.9, 0.3))
