class_name Hud
extends Node2D
## Screen-space overlay: scoreboard, anime cut-in banners and the full-time panel.

var game: SoccerMatch
var _banner_text := ""
var _banner_color := Color.WHITE
var _banner_time := 0.0
var _banner_duration := 0.0
var _banner_scale := 1.0


func show_banner(text: String, color: Color, duration: float, text_scale := 1.0) -> void:
	_banner_text = text
	_banner_color = color
	_banner_duration = duration
	_banner_scale = text_scale
	_banner_time = 0.0


func _process(delta: float) -> void:
	_banner_time += delta / maxf(Engine.time_scale, 0.01)
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	if game.cinematic_active():
		_draw_focus_lines(vs)
	_draw_scoreboard(vs, font)
	draw_string(font, Vector2(12, 26), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	if game.vision.active:
		_text(font, Vector2(0, vs.y - 28), "VISION  -  tap a teammate to pass", 22, Color(0.6, 0.9, 1.0), vs.x)
	if _banner_time < _banner_duration:
		_draw_banner(vs, font)
	if game.state == SoccerMatch.State.FULLTIME:
		_draw_fulltime(vs, font)


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color, width: float) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, maxi(4, size / 5), Config.INK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _draw_scoreboard(vs: Vector2, font: Font) -> void:
	var board := Rect2(vs.x / 2 - 240, 12, 480, 52)
	draw_rect(board, Color(0.03, 0.04, 0.10, 0.85))
	draw_rect(board, Color.WHITE, false, 2)
	for t in 2:
		var x := board.position.x + 8 if t == 0 else board.end.x - 22
		draw_rect(Rect2(x, board.position.y + 8, 14, 36), Config.TEAM_COLORS[t])
	var y := board.position.y + 36
	draw_string(font, Vector2(board.position.x + 30, y), Config.TEAM_NAMES[0], HORIZONTAL_ALIGNMENT_LEFT, 120, 22)
	draw_string(font, Vector2(board.end.x - 150, y), Config.TEAM_NAMES[1], HORIZONTAL_ALIGNMENT_RIGHT, 120, 22)
	var score := "%d - %d" % [game.score[0], game.score[1]]
	draw_string(font, Vector2(board.position.x + 150, y + 2), score, HORIZONTAL_ALIGNMENT_CENTER, 90, 30, Color(1, 0.9, 0.3))
	var secs := int(ceil(game.time_left))
	draw_string(font, Vector2(board.position.x + 245, y), "%02d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_CENTER, 80, 22)


## Slanted cut-in band with speed lines; the text slams in from the right and exits left.
func _draw_banner(vs: Vector2, font: Font) -> void:
	var t := _banner_time
	var d := _banner_duration
	var band_h := 150.0 * _banner_scale
	var cy := vs.y * 0.42
	var grow := clampf(t / 0.12, 0.0, 1.0) * clampf((d - t) / 0.15, 0.0, 1.0)
	var h := band_h * grow
	var skew := 60.0
	var band := PackedVector2Array([
		Vector2(0, cy - h / 2 + skew), Vector2(vs.x, cy - h / 2 - skew),
		Vector2(vs.x, cy + h / 2 - skew), Vector2(0, cy + h / 2 + skew)])
	draw_colored_polygon(band, Color(0, 0, 0, 0.75))
	draw_polyline(PackedVector2Array([band[0], band[1]]), _banner_color, 6)
	draw_polyline(PackedVector2Array([band[3], band[2]]), _banner_color, 6)

	# Speed lines running along the band (band centre-line: y = cy + skew - slope * x).
	var slope := 2.0 * skew / vs.x
	for i in 18:
		var k := float(i)
		var off := (fmod(k * 0.618, 1.0) - 0.5) * h * 0.85
		var length := 120.0 + fmod(k * 53.0, 140.0)
		var x0 := vs.x + 200.0 - fmod(k * 211.0 + t * 2600.0, vs.x + 400.0)
		var a := Vector2(x0, cy + skew - slope * x0 + off)
		draw_line(a, a + Vector2(length, -slope * length), Color(1, 1, 1, 0.35), 2)

	var enter := clampf(t / 0.18, 0.0, 1.0)
	var leave := clampf((t - (d - 0.18)) / 0.18, 0.0, 1.0)
	var x := lerpf(vs.x, 0.0, 1.0 - pow(1.0 - enter, 3.0)) - leave * vs.x
	var size := int(96 * _banner_scale)
	draw_string_outline(font, Vector2(x + 8, cy + size * 0.35 + 6), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, vs.x, size, 14, Config.INK)
	draw_string_outline(font, Vector2(x, cy + size * 0.35), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, vs.x, size, 10, _banner_color)
	draw_string(font, Vector2(x, cy + size * 0.35), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, vs.x, size, Color.WHITE)


## Manga-style radial focus lines around the screen edge.
func _draw_focus_lines(vs: Vector2) -> void:
	var center := vs / 2
	var outer := vs.length() * 0.6
	var jitter := int(_banner_time * 30.0)
	for i in 64:
		var k := float((i * 37 + jitter * 13) % 101) / 101.0
		var a := TAU * (float(i) + k * 0.6) / 64.0
		var dir := Vector2.from_angle(a)
		var inner := outer * (0.55 + 0.2 * k)
		var w := 2.0 + 5.0 * k
		var side := dir.orthogonal() * w
		draw_colored_polygon(PackedVector2Array([
			center + dir * outer + side, center + dir * outer - side, center + dir * inner]), Color(1, 1, 1, 0.55))


func _draw_fulltime(vs: Vector2, font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	_text(font, Vector2(0, vs.y * 0.36), "FULL TIME", 84, Color.WHITE, vs.x)
	var line := "%s  %d - %d  %s" % [Config.TEAM_NAMES[0], game.score[0], game.score[1], Config.TEAM_NAMES[1]]
	_text(font, Vector2(0, vs.y * 0.52), line, 48, Color(1, 0.9, 0.3), vs.x)
	_text(font, Vector2(0, vs.y * 0.68), "Tap to play again", 30, Color(0.8, 0.9, 1.0), vs.x)
