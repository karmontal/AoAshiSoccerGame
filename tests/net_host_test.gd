extends SceneTree
## Network co-op test, host side. Run together with net_client_test.gd:
##   godot --headless --path . -s tests/net_host_test.gd &
##   godot --headless --path . -s tests/net_client_test.gd
## With "++ coach" it also waits for tests/net_coach_test.gd and checks orders.
var game: SoccerMatch
var with_coach := "coach" in OS.get_cmdline_user_args()
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
			if game.net.players.size() == (3 if with_coach else 2) \
					and (not with_coach or NetCoop.COACH_SLOT in game.net.players.values()):
				print("HOST: client joined, players ", game.net.players)
				game.net.start_match()
				assert(game.net_active and game.mode == SoccerMatch.Mode.COOP)
				var peer: int = game.remote.keys()[0] if game.remote.size() == 1 else -1
				var p: Footballer = game.remote[peer]["player"] if peer != -1 else null
				if p == null or p.number != NetCoop.SLOTS[game.net.players[peer]] or not p.is_human:
					push_error("host should hand exactly one attacker to the player client")
					return true
				phase = "playing"
				t = 0.0
		"playing":
			if t > 9.0:
				if with_coach:
					var eight := game.player_by_number(0, 8)
					print("HOST: mentality ", game.team_mentality[0], ", #8 order time left ", snappedf(eight.order_time, 0.1))
					if game.team_mentality[0] != 2:
						push_error("coach mentality not applied")
						return true
				var p: Footballer = game.remote.values()[0]["player"]
				print("HOST: remote #", p.number, " at ", p.pos.round(), " fouls ", game.stats["fouls"], " score ", game.score)
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
