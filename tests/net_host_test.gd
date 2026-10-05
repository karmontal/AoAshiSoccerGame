extends SceneTree
## Network co-op test, host side. Run together with net_client_test.gd:
##   godot --headless --path . -s tests/net_host_test.gd &
##   godot --headless --path . -s tests/net_client_test.gd
var game: SoccerMatch
var t := 0.0
var phase := "wait_peer"
var start_pos := Vector2.ZERO


func _initialize() -> void:
	GameSettings.reset_to_defaults()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(delta: float) -> bool:
	t += delta
	if t < 0.3:
		return false
	match phase:
		"wait_peer":
			if game.net.role == "":
				assert(game.net.host())
			if game.net.players.size() == 2:
				print("HOST: client joined, players ", game.net.players)
				game.net.start_match()
				assert(game.net_active and game.mode == SoccerMatch.Mode.COOP)
				assert(game.remote.size() == 1)
				var p: Footballer = game.remote.values()[0]["player"]
				assert(p.number == 10 and p.is_human)
				phase = "playing"
				t = 0.0
		"playing":
			if t > 9.0:
				var p: Footballer = game.remote.values()[0]["player"]
				print("HOST: remote #10 at ", p.pos.round(), " fouls ", game.stats["fouls"], " score ", game.score)
				game.time_left = 0.05
				phase = "fulltime"
				t = 0.0
		"fulltime":
			if game.state == SoccerMatch.State.FULLTIME and t > 1.0:
				game.handle_screen_tap(Vector2.ZERO)
				assert(game.menus.page == "lobby")
				phase = "linger"
				t = 0.0
		"linger":
			if t > 2.0:
				game.net.leave()
				print("HOST OK")
				return true
	return t > 60.0
