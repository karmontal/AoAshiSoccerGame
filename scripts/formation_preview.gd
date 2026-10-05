class_name FormationPreview
extends Control
## Mini pitch on the tactics screen showing a formation (attacking right).

var formation := "4-3-3"
var mentality := 1
var color := Config.TEAM_COLORS[0]


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.16, 0.45, 0.22))
	var line := Color(1, 1, 1, 0.6)
	draw_rect(r, line, false, 2)
	draw_line(Vector2(size.x / 2, 0), Vector2(size.x / 2, size.y), line, 2)
	draw_arc(size / 2, size.y * 0.13, 0, TAU, 32, line, 2)
	var box := Vector2(size.x * Config.BOX_DEPTH / Config.PITCH_LENGTH, size.y * Config.BOX_WIDTH / Config.PITCH_WIDTH)
	draw_rect(Rect2(Vector2(0, (size.y - box.y) / 2), box), line, false, 2)
	draw_rect(Rect2(Vector2(size.x - box.x, (size.y - box.y) / 2), box), line, false, 2)

	var shift: float = Formations.MENTALITY_SHIFT[mentality]
	var font := ThemeDB.fallback_font
	for slot: Array in Formations.DATA[formation]:
		var f: Vector2 = slot[1]
		var x := f.x if slot[0] == Footballer.GK else f.x + shift
		# Spread the own-half shape over the whole preview so it is readable.
		var p := Vector2((x + 1.0) / 1.15 * size.x * 0.92 + size.x * 0.03, (f.y * 0.9 + 1.0) / 2.0 * size.y)
		var c: Color = Config.KEEPER_COLORS[0] if slot[0] == Footballer.GK else color
		draw_circle(p, 13, Config.INK)
		draw_circle(p, 11, c)
		draw_string(font, p + Vector2(-13, 5), str(slot[2]), HORIZONTAL_ALIGNMENT_CENTER, 26, 13, Color.WHITE)
