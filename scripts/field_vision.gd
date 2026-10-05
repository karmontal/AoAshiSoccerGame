class_name FieldVision
extends Node2D
## "Field vision": the signature ability. Slows time, lifts the camera to a
## bird's-eye view and paints every passing lane so the player can read the game.
## With the ball: lanes to teammates (green = open, yellow = risky, red = blocked)
## and a tap on a teammate plays the pass. Without it: the carrier's options,
## so you can see which lane to cut off.
## Lives in the UI layer and draws in screen space by projecting the 3D scene.

const SLOW_SCALE := 0.18
const DRAIN_PER_SEC := 0.30
const RECHARGE_PER_SEC := 0.07
const MIN_ENERGY := 0.25
const MAX_LANES := 5

const OPEN := Color(0.35, 1.0, 0.55)
const RISKY := Color(1.0, 0.85, 0.25)
const BLOCKED := Color(1.0, 0.3, 0.3)
const TINT := Color(0.02, 0.06, 0.18, 0.35)
const GRID := Color(0.5, 0.85, 1.0, 0.22)

var game: SoccerMatch
var energy := 1.0
var active := false
## Co-op coach: the view is always on, never drains and never slows time.
var coach_view := false
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
	game.end_cinematic()
	# Slowing time would slow the whole network match, so co-op skips it.
	if not game.net_active:
		Engine.time_scale = SLOW_SCALE
	game.hud.show_banner("VISION", Color(0.3, 0.8, 1.0), 0.8, 0.6)


func deactivate() -> void:
	if not active or coach_view:
		return
	active = false
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	if active and not coach_view:
		energy -= DRAIN_PER_SEC * real
		if energy <= 0.0:
			energy = 0.0
			deactivate()
	else:
		energy = minf(1.0, energy + RECHARGE_PER_SEC * real)
	queue_redraw()


## With eleven players, only the most useful passing options are drawn.
func _top_options(carrier: Footballer, best: Footballer) -> Array[Footballer]:
	var scored: Array = []
	for mate: Footballer in game.teams[carrier.team]:
		if mate != carrier and mate.role != Footballer.GK:
			scored.append([game.pass_score(carrier, mate) + (10.0 if mate == best else 0.0), mate])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var result: Array[Footballer] = []
	for entry: Array in scored.slice(0, MAX_LANES):
		result.append(entry[1])
	return result


static func lane_color(clearance: float) -> Color:
	if clearance > 60.0:
		return OPEN
	if clearance > 30.0:
		return RISKY
	return BLOCKED


## Logic-plane point to screen position.
func to_screen(p: Vector2) -> Vector2:
	return game.camera.unproject_position(Config.to_3d(p))


func _draw() -> void:
	if not active:
		return
	draw_rect(get_viewport_rect(), TINT)
	var hl := Config.HALF_L
	var hw := Config.HALF_W
	for i in range(-5, 6):
		draw_line(to_screen(Vector2(i * hl / 5.0, -hw)), to_screen(Vector2(i * hl / 5.0, hw)), GRID, 1.5)
	for i in range(-3, 4):
		draw_line(to_screen(Vector2(-hl, i * hw / 3.0)), to_screen(Vector2(hl, i * hw / 3.0)), GRID, 1.5)

	var carrier: Footballer = game.ball.holder
	if carrier == null:
		carrier = game.human
	var from := to_screen(carrier.pos)
	var pulse := sin(_t * 7.0) * 2.0

	for o: Footballer in game.teams[1 - carrier.team]:
		draw_arc(to_screen(o.pos), 16, 0, TAU, 24, Color(1, 0.3, 0.3, 0.8), 2.5)

	var best: Footballer = game.best_pass_target(carrier, carrier.facing)
	for mate: Footballer in _top_options(carrier, best):
		var col := lane_color(game.lane_clearance(carrier.pos, mate.pos, 1 - carrier.team))
		if carrier.team != 0:
			col = col.lerp(Color(1, 0.4, 0.2), 0.5)
		var width := 6.0 if mate == best else 3.0
		var to := to_screen(mate.pos)
		draw_dashed_line(from, to, Config.INK, width + 3.0, 14.0)
		draw_dashed_line(from, to, col, width, 14.0)
		draw_arc(to, 20 + pulse, 0, TAU, 32, Config.INK, 6)
		draw_arc(to, 20 + pulse, 0, TAU, 32, col, 3)

	if best != null:
		var font := ThemeDB.fallback_font
		var label := "BEST" if carrier.team == 0 else "DANGER"
		var pos := to_screen(best.pos) + Vector2(-60, -30)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, 6, Config.INK)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(1, 0.9, 0.3))
