extends SceneTree
## Headless smoke test: from the menu, plays a full TEAM match and then a full
## SOLO match with random "human" input, checking the whole match flow.
## Run: godot --headless --path . --fixed-fps 60 -s tests/sim_test.gd

var game: SoccerMatch
var frames := 0
var possession_changes := 0
var vision_uses := 0
var calls := 0
var last_holder: Footballer = null
var pressed: Array[String] = []
var modes_left: Array = [SoccerMatch.Mode.TEAM, SoccerMatch.Mode.SOLO]
var menus_checked := false


func _initialize() -> void:
	GameSettings.reset_to_defaults()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


## Title -> settings (every option applied) -> back -> modes -> back -> title.
func _check_menus_and_settings() -> void:
	var menus := game.menus
	assert(menus.page == "title")
	menus.open_settings("title")
	assert(menus.page == "settings")
	for d: Dictionary in GameSettings.DEFS:
		for i in d["options"].size():
			menus._change(d["key"], 1)
	GameSettings.reset_to_defaults()
	game.apply_settings()
	menus.go_back()
	assert(menus.page == "title")
	menus.show_page("modes")
	menus.go_back()
	assert(menus.page == "title")
	print("MENUS OK")


func _process(_delta: float) -> bool:
	frames += 1
	for a in pressed:
		Input.action_release(a)
	pressed.clear()

	if not menus_checked:
		menus_checked = true
		_check_menus_and_settings()
	if game.state == SoccerMatch.State.MENU:
		if modes_left.is_empty():
			print("ALL MODES OK")
			return true
		var choice: SoccerMatch.Mode = modes_left.pop_front()
		game.menus._start(choice)
		assert(game.state == SoccerMatch.State.KICKOFF and game.mode == choice)
		assert(game.menus.page == "")
		frames = 0
		possession_changes = 0
		vision_uses = 0
		calls = 0
		return false

	if game.state == SoccerMatch.State.PLAYING:
		game.controls.vector = Vector2.from_angle(frames * 0.013).normalized() * 0.9
		if frames % 47 == 0:
			_press("pass")
			if game.mode == SoccerMatch.Mode.SOLO and game.ball.holder != game.human:
				calls += 1
		if frames % 131 == 0:
			_press("shoot")
		if frames % 400 == 0 and game.vision.can_activate():
			_press("vision")
			vision_uses += 1
		if frames == 900:
			game.pause_game()
			assert(paused and game.menus.page == "pause")
			game.resume_game()
			assert(not paused and game.menus.page == "")
		if game.vision.active and frames % 10 == 0:
			var mate: Footballer = game.teams[0][randi() % 5]
			game.handle_screen_tap(game.camera.unproject_position(Config.to_3d(mate.pos) + Vector3(0, 1, 0)))

	if game.ball.holder != last_holder:
		possession_changes += 1
		last_holder = game.ball.holder
	assert(game.human != null and game.human.is_human)
	assert(game.human.team == 0)
	if game.mode == SoccerMatch.Mode.SOLO:
		assert(game.human == game.teams[0][4], "SOLO mode must keep control of #9")
	assert(not is_nan(game.ball.pos.x))

	if game.state == SoccerMatch.State.FULLTIME:
		print("%s FULLTIME after %d frames | score %d-%d | possession changes %d | vision uses %d | calls %d | eye %s %d pts %s"
			% [SoccerMatch.Mode.keys()[game.mode], frames, game.score[0], game.score[1], possession_changes,
				vision_uses, calls, game.coach.grade(), game.coach.points, game.coach.counts])
		game.handle_screen_tap(Vector2.ZERO)
		assert(game.state == SoccerMatch.State.MENU and game.menus.page == "modes")
	elif frames > 60 * 60 * 10:
		push_error("match never finished")
		return true
	return false


func _press(a: String) -> void:
	Input.action_press(a)
	pressed.append(a)
