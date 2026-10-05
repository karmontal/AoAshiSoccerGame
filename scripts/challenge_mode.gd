class_name ChallengeMode
extends Node2D
## Runs a set of Field Vision puzzles over the frozen 3D scene: asks, takes a
## tap, then reveals the truth (heat map / passing lanes, best answer, score).
## Lives in the UI layer and draws in screen space.

const TIME_LIMIT := 20.0
const DAILY_KINDS := [Challenge.Kind.PASS, Challenge.Kind.SPACE, Challenge.Kind.CUT]

var game: SoccerMatch
var daily := true
var puzzles: Array[Challenge] = []
var results: Array[int] = []
var index := 0
var active := false

var _phase := "ask"
var _timer := TIME_LIMIT
var _answer: Variant = null
var _score := 0
var _cands: Array = []
var _lo := 0.0
var _hi := 1.0
var _best: Variant = null
var _t := 0.0


func start_daily() -> void:
	var date := DailyStats.today()
	var list: Array[Challenge] = []
	for i in DAILY_KINDS.size():
		list.append(Challenge.make(DAILY_KINDS[i], Challenge.daily_seed(date, i)))
	_start(list, true)


func start_practice() -> void:
	var list: Array[Challenge] = []
	for kind: Challenge.Kind in DAILY_KINDS:
		list.append(Challenge.make(kind, randi()))
	_start(list, false)


func kinds() -> Array:
	return puzzles.map(func(c: Challenge) -> Challenge.Kind: return c.kind)


func current() -> Challenge:
	return puzzles[index]


func _start(list: Array[Challenge], is_daily: bool) -> void:
	puzzles = list
	daily = is_daily
	results.clear()
	index = 0
	active = true
	_load()


func _load() -> void:
	var c := current()
	game.load_challenge(c)
	_cands = c.candidates()
	_lo = INF
	_hi = -INF
	for entry: Array in _cands:
		if entry[1] > _hi:
			_hi = entry[1]
			_best = entry[0]
		_lo = minf(_lo, entry[1])
	_phase = "ask"
	_timer = TIME_LIMIT
	_answer = null


## Taps from TouchControls while a puzzle is on screen.
func handle_tap(screen_pos: Vector2) -> bool:
	if not active:
		return false
	if _phase == "reveal":
		_next()
		return true
	var c := current()
	if c.kind == Challenge.Kind.PASS:
		var best_d := 70.0
		for n: int in c.positions[c.me_team]:
			if n == c.me_number:
				continue
			var d := _screen(c.positions[c.me_team][n]).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				_answer = n
		if _answer == null:
			return true
	else:
		var p := game.screen_to_pitch(screen_pos)
		if p == Vector2.INF:
			return true
		_answer = c.clamp_answer(p)
	answer(_answer)
	return true


func answer(value: Variant) -> void:
	_answer = value
	_score = current().score(value, _cands) if value != null else 0
	results.append(_score)
	_phase = "reveal"
	game.vibrate(30)
	if _score >= 80:
		game.audio.play("success", -4.0)
	elif _score < 40:
		game.audio.play("ooh", -10.0)


func _next() -> void:
	index += 1
	if index < puzzles.size():
		_load()
		return
	active = false
	if daily:
		DailyStats.record(results)
	game.finish_challenge()


func _process(delta: float) -> void:
	_t += delta
	if active and _phase == "ask":
		_timer -= delta
		if _timer <= 0.0:
			answer(null)
	queue_redraw()


func _screen(p: Vector2) -> Vector2:
	return game.camera.unproject_position(Config.to_3d(p))


func _draw() -> void:
	if not active:
		return
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var c := current()

	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.05, 0.14, 0.25))
	if c.kind != Challenge.Kind.PASS:
		var centre := _screen(c.me_pos())
		var edge := _screen(c.me_pos() + Vector2(Challenge.MOVE_RADIUS, 0))
		draw_arc(centre, centre.distance_to(edge), 0, TAU, 64, Color(0.6, 0.9, 1.0, 0.7), 3)

	# Mark every player so they read clearly from above.
	for t in 2:
		var col := Color(0.4, 0.75, 1.0, 0.9) if t == c.me_team else Color(1.0, 0.4, 0.35, 0.8)
		for n: int in c.positions[t]:
			var p := _screen(c.positions[t][n])
			var tappable := c.kind == Challenge.Kind.PASS and t == c.me_team and n != c.me_number and _phase == "ask"
			draw_arc(p, 15.0 if tappable else 11.0, 0, TAU, 20, Config.INK, 5)
			draw_arc(p, 15.0 if tappable else 11.0, 0, TAU, 20, col, 3 if tappable else 2)

	if _phase == "reveal":
		_draw_reveal(c)

	# Highlight the carrier and the player the puzzle is about.
	_ring(_screen(c.carrier_pos()), Color(1, 0.85, 0.2), "BALL")
	if c.kind != Challenge.Kind.PASS:
		_ring(_screen(c.me_pos()), Color(0.5, 0.9, 1.0), "YOU")

	# Header band.
	var title := "DAILY VISION #%d" % DailyStats.day_number() if daily else "PRACTICE"
	draw_rect(Rect2(0, 0, vs.x, 92), Color(0.02, 0.03, 0.08, 0.85))
	_text(font, Vector2(0, 32), "%s   ·   %d / %d" % [title, index + 1, puzzles.size()], 20, Color(0.7, 0.85, 1.0), vs.x)
	_text(font, Vector2(0, 74), Challenge.PROMPTS[c.kind], 36, Color.WHITE, vs.x)

	if _phase == "ask":
		_text(font, Vector2(0, vs.y - 24), Challenge.HINTS[c.kind], 22, Color(0.85, 0.92, 1.0), vs.x)
		var frac := clampf(_timer / TIME_LIMIT, 0.0, 1.0)
		draw_rect(Rect2(0, 92, vs.x * frac, 6), Color(1, 0.85, 0.2).lerp(Color(1, 0.3, 0.3), 1.0 - frac))
	else:
		var verdict := "PERFECT READ!" if _score >= 90 else ("GOOD READ" if _score >= 60 else ("RISKY" if _score >= 30 else "MISREAD"))
		if _answer == null:
			verdict = "TIME UP"
		var col := Color(0.4, 1.0, 0.5) if _score >= 60 else (Color(1, 0.85, 0.2) if _score >= 30 else Color(1, 0.35, 0.3))
		draw_rect(Rect2(0, vs.y - 120, vs.x, 120), Color(0.02, 0.03, 0.08, 0.85))
		_text(font, Vector2(0, vs.y - 64), "%s   %d" % [verdict, _score], 44, col, vs.x)
		var more := "Tap to continue" if index + 1 < puzzles.size() else "Tap to see your result"
		_text(font, Vector2(0, vs.y - 22), more, 20, Color(0.8, 0.9, 1.0), vs.x)


func _draw_reveal(c: Challenge) -> void:
	if c.kind == Challenge.Kind.PASS:
		var from := _screen(c.carrier_pos())
		for entry: Array in _cands:
			var k: float = (entry[1] - _lo) / maxf(_hi - _lo, 0.0001)
			var col := Color(1, 0.3, 0.3).lerp(Color(0.35, 1.0, 0.5), k)
			var to := _screen(c.positions[c.me_team][entry[0]])
			var w := 6.0 if entry[0] == _best else 3.0
			draw_dashed_line(from, to, Config.INK, w + 3.0, 12.0)
			draw_dashed_line(from, to, col, w, 12.0)
		if _answer != null:
			_ring(_screen(c.positions[c.me_team][_answer]), Color.WHITE, "YOUR PICK", 26)
		_ring(_screen(c.positions[c.me_team][_best]), Color(0.35, 1.0, 0.5), "BEST", 32)
		return
	# Heat map of every reachable point.
	var dot := maxf(4.0, _screen(c.me_pos()).distance_to(_screen(c.me_pos() + Vector2(Challenge.GRID_STEP, 0))) * 0.42)
	for entry: Array in _cands:
		var k: float = (entry[1] - _lo) / maxf(_hi - _lo, 0.0001)
		draw_circle(_screen(entry[0]), dot, Color(Color(1, 0.3, 0.3).lerp(Color(0.35, 1.0, 0.5), k), 0.55))
	if _answer != null:
		_ring(_screen(_answer), Color.WHITE, "YOUR PICK", 18)
	_ring(_screen(_best), Color(0.35, 1.0, 0.5), "BEST", 22)


func _ring(p: Vector2, col: Color, label: String, radius := 22.0) -> void:
	var r := radius + sin(_t * 6.0) * 2.0
	draw_arc(p, r, 0, TAU, 32, Config.INK, 7)
	draw_arc(p, r, 0, TAU, 32, col, 4)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, p + Vector2(-60, -r - 8), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, 5, Config.INK)
	draw_string(font, p + Vector2(-60, -r - 8), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, col)


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color, width: float) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, maxi(4, size / 5), Config.INK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)
