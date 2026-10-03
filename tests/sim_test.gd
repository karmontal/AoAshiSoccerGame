extends SceneTree
## Headless smoke test: plays a full match with random "human" input.
## Run: godot --headless --path . --fixed-fps 60 -s tests/sim_test.gd

var game: SoccerMatch
var frames := 0
var goals_seen := 0
var possession_changes := 0
var vision_uses := 0
var last_holder: Footballer = null
var pressed: Array[String] = []


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	for a in pressed:
		Input.action_release(a)
	pressed.clear()

	if game.state == SoccerMatch.State.PLAYING:
		game.controls.vector = Vector2.from_angle(frames * 0.013).normalized() * 0.9
		if frames % 47 == 0:
			_press("pass")
		if frames % 131 == 0:
			_press("shoot")
		if frames % 400 == 0 and game.vision.can_activate():
			_press("vision")
			vision_uses += 1
		if game.vision.active and frames % 10 == 0:
			var mate: Footballer = game.teams[0][randi() % 5]
			game.handle_screen_tap(game.camera.unproject_position(Config.to_3d(mate.pos) + Vector3(0, 1, 0)))

	if game.ball.holder != last_holder:
		possession_changes += 1
		last_holder = game.ball.holder
	assert(game.human != null and game.human.is_human)
	assert(game.human.team == 0)
	assert(not is_nan(game.ball.pos.x))

	if game.state == SoccerMatch.State.FULLTIME:
		print("FULLTIME after %d frames | score %d-%d | possession changes %d | vision uses %d"
			% [frames, game.score[0], game.score[1], possession_changes, vision_uses])
		game.handle_screen_tap(Vector2.ZERO)
		assert(game.state == SoccerMatch.State.KICKOFF and game.score == [0, 0])
		print("restart OK")
		return true
	if frames > 60 * 60 * 10:
		push_error("match never finished")
		return true
	return false


func _press(a: String) -> void:
	Input.action_press(a)
	pressed.append(a)
