class_name Hud
extends Node2D
## Screen-space overlay: scoreboard, Captain's Eye meter and
## pop-ups, anime cut-in banners and the full-time panel.

const GRADE_COLORS := {
	"S": Color(1.0, 0.85, 0.2), "A": Color(0.4, 1.0, 0.5), "B": Color(0.4, 0.85, 1.0),
	"C": Color(1.0, 0.6, 0.25), "D": Color(1.0, 0.35, 0.35),
}
const POPUP_TIME := 1.4

var game: SoccerMatch
var _banner_text := ""
var _banner_color := Color.WHITE
var _banner_time := 0.0
var _banner_duration := 0.0
var _banner_scale := 1.0
var _popups: Array[Dictionary] = []
var _time := 0.0


func show_banner(text: String, color: Color, duration: float, text_scale := 1.0) -> void:
	_banner_text = text
	_banner_color = color
	_banner_duration = duration
	_banner_scale = text_scale
	_banner_time = 0.0


## Floating anime text above a point in the 3D world (e.g. "LANE CUT +15").
func popup(text: String, world: Vector3, color := Color(0.55, 1.0, 0.6)) -> void:
	_popups.append({"text": text, "world": world, "t": 0.0, "color": color})
	if _popups.size() > 6:
		_popups.pop_front()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_banner_time += real
	_time += real
	for p in _popups:
		p["t"] += real
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p["t"] < POPUP_TIME)
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	if game.state == SoccerMatch.State.MENU:
		return
	if game.cinematic_active():
		_draw_focus_lines(vs)
	var fulltime := game.state == SoccerMatch.State.FULLTIME
	if not fulltime:
		_draw_popups(font)
	_draw_scoreboard(vs, font)
	if not fulltime:
		_draw_eye_meter(font)
	if GameSettings.enabled("show_fps"):
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
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	_text(font, Vector2(0, vs.y * 0.24), "FULL TIME", 76, Color.WHITE, vs.x)
	var line := "%s  %d - %d  %s" % [Config.TEAM_NAMES[0], game.score[0], game.score[1], Config.TEAM_NAMES[1]]
	_text(font, Vector2(0, vs.y * 0.37), line, 42, Color(1, 0.9, 0.3), vs.x)

	var coach := game.coach
	var g := coach.grade()
	_text(font, Vector2(0, vs.y * 0.5), "CAPTAIN'S EYE", 26, Color(0.7, 0.9, 1.0), vs.x)
	_text(font, Vector2(0, vs.y * 0.63), "%s   %d pts" % [g, coach.points], 56, GRADE_COLORS[g], vs.x)
	var parts := PackedStringArray()
	for id: String in ["open_lane", "run_behind", "free_space", "lane_cut", "goal_side", "tight_mark", "intercept", "received"]:
		if coach.counts.get(id, 0) > 0:
			parts.append("%s x%d" % [PositioningCoach.EVENTS[id][0].trim_suffix("!"), coach.counts[id]])
	if parts.is_empty():
		parts.append("Move into space and cut lanes to earn points")
	_text(font, Vector2(0, vs.y * 0.73), "  |  ".join(parts), 20, Color(0.85, 0.9, 1.0), vs.x)
	_text(font, Vector2(0, vs.y * 0.86), "Tap to continue", 28, Color(0.8, 0.9, 1.0), vs.x)


func _draw_popups(font: Font) -> void:
	var cam := game.camera
	for p in _popups:
		var world: Vector3 = p["world"]
		if cam.is_position_behind(world):
			continue
		var t: float = p["t"]
		var pos := cam.unproject_position(world) + Vector2(0, -t * 45.0)
		var punch := 1.0 + 0.5 * maxf(0.0, 1.0 - t * 7.0)
		var size := int(26 * punch)
		var alpha := clampf((POPUP_TIME - t) / 0.4, 0.0, 1.0)
		var col: Color = p["color"]
		var text: String = p["text"]
		var w := 400.0
		draw_string_outline(font, pos + Vector2(-w / 2 + 3, 3), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 9, Color(Config.INK, alpha))
		draw_string_outline(font, pos + Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 6, Color(Config.INK, alpha))
		draw_string(font, pos + Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(col, alpha))


## Live positioning grade (top-left).
func _draw_eye_meter(font: Font) -> void:
	var coach := game.coach
	var g := coach.live_grade()
	var col: Color = GRADE_COLORS[g]
	var box := Rect2(12, 40, 170, 64)
	draw_rect(box, Color(0.03, 0.04, 0.10, 0.75))
	draw_rect(box, Color(col, 0.9), false, 2)
	draw_string(font, box.position + Vector2(10, 20), "CAPTAIN'S EYE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.9, 1.0))
	draw_string(font, box.position + Vector2(10, 46), "%d pts" % coach.points, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string_outline(font, box.position + Vector2(118, 52), g, HORIZONTAL_ALIGNMENT_CENTER, 40, 40, 6, Config.INK)
	draw_string(font, box.position + Vector2(118, 52), g, HORIZONTAL_ALIGNMENT_CENTER, 40, 40, col)
	var bar := Rect2(box.position.x + 10, box.end.y - 12, 100, 6)
	draw_rect(bar, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * coach.rating, bar.size.y)), col)
