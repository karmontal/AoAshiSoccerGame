extends SceneTree
## Network co-op test, coach side: joins, becomes the coach, sets PRESS and
## sends #8 somewhere with screen taps, then checks #8 runs there.
## Run with: net_host_test.gd ++ coach, net_client_test.gd and this script.
var game: SoccerMatch
var t := 0.0
var phase := "join"
var target := Vector2.ZERO
var start_dist := 0.0


func _initialize() -> void:
	GameSettings.reset_to_defaults()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _fail(msg: String) -> bool:
	push_error(msg)
	return true


func _process(delta: float) -> bool:
	t += delta
	if t < 0.3:
		return false
	match phase:
		"join":
			if game.net.role == "":
				game.net.join("127.0.0.1")
			if game.multiplayer.get_unique_id() != 1 and game.net.players.size() >= 2:
				game.net.set_coach(true)
				phase = "wait_coach"
		"wait_coach":
			if game.net.is_coach():
				print("COACH: lobby slot ok")
				phase = "wait_start"
		"wait_start":
			if game.is_client and game.state != SoccerMatch.State.MENU:
				if not game.coach_view or not game.vision.active:
					return _fail("coach should get the tactical view")
				phase = "settle"
				t = 0.0
		"settle":
			if t > 2.0:
				game.net.coach_mentality.rpc_id(1, 2)
				var eight := game.player_by_number(0, 8)
				target = eight.pos + (Vector2.ZERO - eight.pos).normalized() * 15.0 * Config.M
				start_dist = eight.pos.distance_to(target)
				# Select #8, then tap the target spot, through the screen like a player.
				game.coach_tap(game.camera.unproject_position(Config.to_3d(eight.pos)))
				if game.coach_selected != eight:
					return _fail("tap should select #8")
				game.coach_tap(game.camera.unproject_position(Config.to_3d(target)))
				phase = "watch"
				t = 0.0
		"watch":
			if t > 2.5:
				var eight := game.player_by_number(0, 8)
				var now := eight.pos.distance_to(target)
				print("COACH: #8 distance to order %.1f m -> %.1f m, order shown: %s" % [start_dist / Config.M, now / Config.M, game.orders.has(8)])
				if now > start_dist - 8.0 * Config.M:
					return _fail("#8 should run to the coach's spot")
				phase = "wait_end"
		"wait_end":
			if game.net.role == "":
				print("COACH OK")
				return true
	return t > 60.0
