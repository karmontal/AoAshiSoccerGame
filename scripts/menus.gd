class_name Menus
extends Control
## Front-end screens built from Control nodes: title, mode select, settings
## and the in-match pause menu. Runs while the tree is paused.

const VERSION := "v0.6"
const VISION_BLUE := Color(0.35, 0.8, 1.0)
const COOP_GREEN := Color(0.45, 1.0, 0.55)
const ACCENT := Color(1.0, 0.75, 0.2)

var game: SoccerMatch
var page := ""

var _pages := {}
var _settings_return := "title"
var _tactics_return := "modes"
var _pending_mode := SoccerMatch.Mode.TEAM
var _preview: FormationPreview
var _opponent_label: Label
var _kickoff_button: Button
var _daily_info: Label
var _daily_play: Button
var _result_title: Label
var _result_total: Label
var _result_detail: Label
var _result_note: Label
var _share_button: Button
var _coop_status: Label
var _join_list: VBoxContainer
var _ip_edit: LineEdit
var _lobby_info: Label
var _lobby_players: Label
var _lobby_start: Button
var _lobby_tactics: Button
var _setting_labels := {}
var _logo: Control
var _time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_pages["title"] = _build_title()
	_pages["modes"] = _build_modes()
	_pages["settings"] = _build_settings()
	_pages["pause"] = _build_pause()
	_pages["tactics"] = _build_tactics()
	_pages["daily"] = _build_daily()
	_pages["daily_result"] = _build_daily_result()
	_pages["coop"] = _build_coop()
	_pages["join"] = _build_join()
	_pages["lobby"] = _build_lobby()
	game.net.lobby_changed.connect(_refresh_lobby)
	game.net.games_changed.connect(_refresh_join)
	for p: Control in _pages.values():
		add_child(p)
	show_page("title")


func show_page(name: String) -> void:
	page = name
	for key: String in _pages:
		_pages[key].visible = key == name
	mouse_filter = Control.MOUSE_FILTER_IGNORE if name == "" else Control.MOUSE_FILTER_STOP
	if name == "title":
		_play_logo_intro()
	elif name == "settings" or name == "tactics":
		_refresh_settings()
	elif name == "daily":
		_refresh_daily()
	elif name == "daily_result":
		_refresh_result()
	elif name == "lobby" or name == "coop":
		_refresh_lobby()
	if name == "join":
		game.net.start_discovery()
		_refresh_join()
	else:
		game.net.stop_discovery()


func open_settings(from_page: String) -> void:
	_settings_return = from_page
	show_page("settings")


func _process(delta: float) -> void:
	_time += delta
	if page == "title" and _logo != null:
		_logo.rotation = sin(_time * 1.3) * 0.012


# --- Back button / Escape ---------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	match page:
		"settings":
			show_page(_settings_return)
		"modes":
			show_page("title")
		"tactics":
			show_page(_tactics_return)
		"daily":
			show_page("title")
		"daily_result":
			show_page("daily")
		"coop":
			show_page("modes")
		"join":
			show_page("coop")
		"lobby":
			game.net.leave()
			show_page("coop")
		"pause":
			game.resume_game()
		"title":
			get_tree().quit()
		_:
			if game.state == SoccerMatch.State.CHALLENGE:
				game.quit_challenge()
			else:
				game.pause_game()


# --- Pages ------------------------------------------------------------------

func _build_title() -> Control:
	var root := _page()
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.06, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var box := _column(root, 18)
	_logo = _make_logo()
	box.add_child(_logo)
	box.add_child(_label("Read the pitch. Win the space.", 26, Color(0.8, 0.9, 1.0)))
	box.add_child(_spacer(6))
	box.add_child(_button("PLAY", func() -> void: show_page("modes"), 38, Vector2(380, 76), ACCENT))
	box.add_child(_button("DAILY VISION", func() -> void: show_page("daily"), 30, Vector2(380, 66), VISION_BLUE))
	box.add_child(_button("SETTINGS", func() -> void: open_settings("title"), 30, Vector2(380, 70)))

	var version := _label(VERSION, 16, Color(1, 1, 1, 0.5))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -120
	version.offset_top = -44
	version.offset_right = -18
	version.offset_bottom = -12
	root.add_child(version)
	return root


func _build_modes() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 22)
	box.add_child(_header("CHOOSE MODE"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	row.add_child(_mode_card("TEAM", "Control whoever is nearest\nthe ball. Classic arcade.",
		Config.TEAM_COLORS[0], func() -> void: _choose_mode(SoccerMatch.Mode.TEAM)))
	row.add_child(_mode_card("SOLO", "You are #9 all match.\nFind space, CALL for the ball.",
		ACCENT, func() -> void: _choose_mode(SoccerMatch.Mode.SOLO)))
	row.add_child(_mode_card("CO-OP", "Up to 4 friends on the\nsame Wi-Fi, one player each.",
		COOP_GREEN, func() -> void: show_page("coop")))
	box.add_child(_button("BACK", func() -> void: show_page("title"), 26, Vector2(240, 60)))
	return root


func _build_settings() -> Control:
	var root := _page()
	_dim(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = 16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	box.add_child(_header("SETTINGS"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	center.add_child(rows)
	for d: Dictionary in GameSettings.DEFS:
		rows.add_child(_setting_row(d["key"], d["label"]))

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	box.add_child(bottom)
	bottom.add_child(_button("DEFAULTS", func() -> void:
		GameSettings.reset_to_defaults()
		_on_setting_changed(), 22, Vector2(200, 56)))
	bottom.add_child(_button("BACK", func() -> void: show_page(_settings_return), 26, Vector2(240, 56), ACCENT))
	return root


func _build_pause() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 18)
	box.add_child(_header("PAUSED"))
	box.add_child(_button("RESUME", func() -> void: game.resume_game(), 34, Vector2(380, 76), ACCENT))
	box.add_child(_button("TACTICS", func() -> void: open_tactics("pause"), 28, Vector2(380, 66)))
	box.add_child(_button("SETTINGS", func() -> void: open_settings("pause"), 28, Vector2(380, 66)))
	box.add_child(_button("QUIT TO MENU", func() -> void: game.quit_to_menu(), 28, Vector2(380, 66)))
	return root


## Mode card picked: choose tactics before kick-off.
func _choose_mode(mode: SoccerMatch.Mode) -> void:
	_pending_mode = mode
	game.prepare_opponent()
	open_tactics("modes")


func open_tactics(from_page: String) -> void:
	_tactics_return = from_page
	_kickoff_button.visible = from_page == "modes"
	show_page("tactics")


func _start(mode: SoccerMatch.Mode) -> void:
	show_page("")
	game.start_match(mode)


# --- Wi-Fi co-op -------------------------------------------------------------

func _build_coop() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 16)
	box.add_child(_header("CO-OP"))
	box.add_child(_label("Play together on the same Wi-Fi: each friend controls one attacker\n(P1 #9, P2 #10, P3 #7, P4 #11) against the computer.", 22, Color(0.8, 0.9, 1.0)))
	_coop_status = _label("", 20, Color(1, 0.75, 0.6))
	box.add_child(_coop_status)
	box.add_child(_button("HOST A GAME", func() -> void:
		if game.net.host():
			show_page("lobby"), 32, Vector2(400, 74), COOP_GREEN))
	box.add_child(_button("JOIN A GAME", func() -> void: show_page("join"), 30, Vector2(400, 68)))
	box.add_child(_button("BACK", func() -> void: show_page("modes"), 24, Vector2(240, 56)))
	return root


func _build_join() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 14)
	box.add_child(_header("JOIN"))
	box.add_child(_label("Games on your Wi-Fi:", 22, Color(0.8, 0.9, 1.0)))
	_join_list = VBoxContainer.new()
	_join_list.add_theme_constant_override("separation", 8)
	box.add_child(_join_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Host IP, e.g. 192.168.1.20"
	_ip_edit.custom_minimum_size = Vector2(360, 56)
	_ip_edit.add_theme_font_size_override("font_size", 24)
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	row.add_child(_ip_edit)
	row.add_child(_button("JOIN", func() -> void: _join(_ip_edit.text), 26, Vector2(160, 56), COOP_GREEN))
	box.add_child(_button("BACK", func() -> void: show_page("coop"), 24, Vector2(240, 56)))
	return root


func _refresh_join() -> void:
	if _join_list == null:
		return
	for child in _join_list.get_children():
		child.queue_free()
	var games: Dictionary = game.net.games
	if games.is_empty():
		_join_list.add_child(_label("Searching...", 22, Color(1, 1, 1, 0.6)))
	for ip: String in games:
		var info: Dictionary = games[ip]
		var text := "%s   (%d/4)   %s" % [info["name"], info["players"], ip]
		_join_list.add_child(_button(text, func() -> void: _join(ip), 22, Vector2(520, 56), COOP_GREEN))


func _join(ip: String) -> void:
	if ip.strip_edges() != "" and game.net.join(ip):
		show_page("lobby")


func _build_lobby() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 14)
	box.add_child(_header("CO-OP LOBBY"))
	_lobby_info = _label("", 22, Color(0.8, 0.9, 1.0))
	box.add_child(_lobby_info)
	_lobby_players = _label("", 26, Color.WHITE)
	box.add_child(_lobby_players)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	row.add_child(_button("LEAVE", func() -> void: go_back(), 24, Vector2(200, 60)))
	_lobby_tactics = _button("TACTICS", func() -> void: open_tactics("lobby"), 24, Vector2(200, 60))
	row.add_child(_lobby_tactics)
	_lobby_start = _button("START MATCH", func() -> void:
		show_page("")
		game.net.start_match(), 30, Vector2(300, 66), COOP_GREEN)
	row.add_child(_lobby_start)
	return root


func _refresh_lobby() -> void:
	if _lobby_info == null:
		return
	var net := game.net
	_coop_status.text = net.status
	var hosting := net.role == "host"
	var ips := NetCoop.local_ips()
	if hosting:
		_lobby_info.text = "You are hosting.  Your IP: %s\n%s" % [", ".join(ips) if not ips.is_empty() else "?", net.status]
	else:
		_lobby_info.text = net.status
	var lines := PackedStringArray()
	for peer: int in net.players:
		var s: int = net.players[peer]
		var me := " (you)" if peer == multiplayer.get_unique_id() else ""
		lines.append("P%d  -  #%d%s" % [s + 1, NetCoop.SLOTS[s], me])
	lines.sort()
	_lobby_players.text = "\n".join(lines) if not lines.is_empty() else "..."
	_lobby_start.visible = hosting
	_lobby_tactics.visible = hosting


# --- Daily Vision -----------------------------------------------------------

func _build_daily() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 16)
	box.add_child(_header("DAILY VISION #%d" % DailyStats.day_number()))
	box.add_child(_label("3 tactical puzzles - the same for everyone today.\nRead the pitch: pass, find space, cut the lane.", 22, Color(0.8, 0.9, 1.0)))
	_daily_info = _label("", 26, ACCENT)
	box.add_child(_daily_info)
	_daily_play = _button("PLAY TODAY", func() -> void:
		show_page("")
		game.challenge.start_daily(), 34, Vector2(380, 76), VISION_BLUE)
	box.add_child(_daily_play)
	box.add_child(_button("PRACTICE", func() -> void:
		show_page("")
		game.challenge.start_practice(), 28, Vector2(380, 64)))
	box.add_child(_button("BACK", func() -> void: show_page("title"), 24, Vector2(240, 56)))
	return root


func _refresh_daily() -> void:
	var info := DailyStats.info()
	var played := DailyStats.played_today()
	var today := "TODAY: %d / 300" % _sum(info["last_scores"]) if played else "TODAY: NOT PLAYED"
	_daily_info.text = "%s     STREAK: %d     BEST: %d" % [today, DailyStats.current_streak(), info["best"]]
	_daily_play.disabled = played
	_daily_play.text = "PLAYED - SEE YOU TOMORROW" if played else "PLAY TODAY"


func _build_daily_result() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 14)
	_result_title = _header("")
	box.add_child(_result_title)
	_result_total = _label("", 72, ACCENT)
	box.add_child(_result_total)
	_result_detail = _label("", 26, Color(0.85, 0.92, 1.0))
	box.add_child(_result_detail)
	_result_note = _label("", 20, Color(0.6, 1.0, 0.7))
	box.add_child(_result_note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	_share_button = _button("SHARE", func() -> void:
		var ch := game.challenge
		DisplayServer.clipboard_set(DailyStats.share_text(ch.results, ch.kinds()))
		_result_note.text = "Copied! Paste it to your friends.", 28, Vector2(240, 62), VISION_BLUE)
	row.add_child(_share_button)
	row.add_child(_button("DONE", func() -> void: show_page("daily"), 28, Vector2(240, 62), ACCENT))
	return root


func _refresh_result() -> void:
	var ch := game.challenge
	var parts := PackedStringArray()
	for i in ch.results.size():
		parts.append("%s %d" % [Challenge.SHORT_NAMES[ch.puzzles[i].kind], ch.results[i]])
	_result_title.text = ("DAILY VISION #%d" % DailyStats.day_number()) if ch.daily else "PRACTICE"
	_result_total.text = "%d / %d" % [_sum(ch.results), ch.results.size() * 100]
	_result_detail.text = "   ·   ".join(parts)
	_result_note.text = ("STREAK: %d" % DailyStats.current_streak()) if ch.daily else ""
	_share_button.visible = ch.daily


static func _sum(values: Array) -> int:
	var total := 0
	for v: int in values:
		total += v
	return total


func _build_tactics() -> Control:
	var root := _page()
	_dim(root)
	var box := _column(root, 16)
	box.add_child(_header("TACTICS"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	_preview = FormationPreview.new()
	_preview.custom_minimum_size = Vector2(380, 250)
	row.add_child(_preview)
	var options := VBoxContainer.new()
	options.alignment = BoxContainer.ALIGNMENT_CENTER
	options.add_theme_constant_override("separation", 12)
	row.add_child(options)
	for d: Dictionary in GameSettings.TACTICS_DEFS:
		options.add_child(_setting_row(d["key"], d["label"]))
	_opponent_label = _label("", 22, Color(1.0, 0.75, 0.7))
	options.add_child(_opponent_label)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	box.add_child(bottom)
	bottom.add_child(_button("BACK", func() -> void: go_back(), 24, Vector2(200, 60)))
	_kickoff_button = _button("KICK OFF", func() -> void: _start(_pending_mode), 32, Vector2(300, 66), ACCENT)
	bottom.add_child(_kickoff_button)
	return root


# --- Settings rows ----------------------------------------------------------

func _setting_row(key: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := _label(text, 24, Color(0.85, 0.92, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)
	row.add_child(_button("<", func() -> void: _change(key, -1), 26, Vector2(64, 54)))
	var value := _button("", func() -> void: _change(key, 1), 24, Vector2(200, 54))
	row.add_child(value)
	row.add_child(_button(">", func() -> void: _change(key, 1), 26, Vector2(64, 54)))
	_setting_labels[key] = value
	return row


func _change(key: String, step: int) -> void:
	GameSettings.cycle(key, step)
	_on_setting_changed()


func _on_setting_changed() -> void:
	_refresh_settings()
	game.apply_settings()
	if game.state != SoccerMatch.State.MENU:
		game.apply_tactics()


func _refresh_settings() -> void:
	for key: String in _setting_labels:
		_setting_labels[key].text = GameSettings.option_text(key)
	if _preview != null:
		_preview.formation = GameSettings.formation()
		_preview.mentality = GameSettings.mentality()
		_preview.queue_redraw()
		_opponent_label.text = "VS %s:  %s  /  %s" % [Config.TEAM_NAMES[1], game.team_formation[1],
			Formations.MENTALITIES[game.team_mentality[1]]]


# --- Widgets ----------------------------------------------------------------

func _page() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


func _dim(root: Control) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.06, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)


func _column(root: Control, separation: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	center.add_child(box)
	return box


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Config.INK)
	return l


func _header(text: String) -> Label:
	return _label(text, 52, Color.WHITE)


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _button(text: String, on_press: Callable, size: int, min_size: Vector2, accent := Config.TEAM_COLORS[0]) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = theme.get_stylebox(state, "Button").duplicate()
		style.border_color = accent if state != "pressed" else Color.WHITE
		if state == "pressed":
			style.bg_color = accent.darkened(0.35)
		b.add_theme_stylebox_override(state, style)
	b.pressed.connect(on_press)
	return b


func _mode_card(title: String, text: String, accent: Color, on_press: Callable) -> Button:
	var b := _button("\n\n" + text, on_press, 21, Vector2(330, 220), accent)
	var title_label := _label(title, 48, accent)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_label.position.y = 22
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title_label)
	return b


## Slanted anime band with the game title.
func _make_logo() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(760, 170)
	holder.pivot_offset = Vector2(380, 85)
	var band := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.border_color = Config.TEAM_COLORS[0]
	style.border_width_top = 6
	style.border_width_bottom = 6
	style.skew = Vector2(0.35, 0)
	band.add_theme_stylebox_override("panel", style)
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.offset_top = 20
	band.offset_bottom = -20
	holder.add_child(band)
	var title := _label("AO SOCCER", 104, Color.WHITE)
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_outline_color", Config.TEAM_COLORS[0])
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(title)
	return holder


func _play_logo_intro() -> void:
	if _logo == null:
		return
	_logo.scale = Vector2(2.2, 2.2)
	_logo.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_logo, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_logo, "modulate:a", 1.0, 0.2)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.04, 0.06, 0.15, 0.92)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(3)
	normal.skew = Vector2(0.2, 0)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(4, 4)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.08, 0.12, 0.26, 0.95)
	var pressed := normal.duplicate()
	pressed.shadow_offset = Vector2(1, 1)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.7))
	t.set_color("font_outline_color", "Button", Config.INK)
	t.set_constant("outline_size", "Button", 6)
	return t
