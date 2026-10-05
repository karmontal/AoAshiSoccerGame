extends SceneTree
## Network co-op test, client side (see net_host_test.gd).
var game: SoccerMatch
var t := 0.0
var phase := "discover"
var start_pos := Vector2.ZERO
var drive := Vector2.ZERO


func _initialize() -> void:
	GameSettings.reset_to_defaults()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(delta: float) -> bool:
	t += delta
	if t < 0.3:
		return false
	match phase:
		"discover":
			if game.net._listener == null:
				game.net.start_discovery()
			if not game.net.games.is_empty():
				print("CLIENT: found games ", game.net.games.keys())
				game.net.stop_discovery()
				assert(game.net.join("127.0.0.1"))
				phase = "wait_start"
			elif t > 8.0:
				print("CLIENT: discovery found nothing, joining directly")
				assert(game.net.join("127.0.0.1"))
				phase = "wait_start"
		"wait_start":
			if game.is_client and game.state != SoccerMatch.State.MENU:
				var slot := game.net.my_slot
				if slot < 1 or slot >= NetCoop.SLOTS.size() or game.human.number != NetCoop.SLOTS[slot]:
					push_error("client should control the attacker of its slot")
					return true
				print("CLIENT: playing as P%d #%d" % [slot + 1, game.human.number])
				phase = "settle"
				t = 0.0
		"settle":
			if t > 2.5:
				start_pos = game.human.pos
				# Run towards the centre spot so the touchline never stops the player.
				drive = (Vector2.ZERO - start_pos).normalized()
				phase = "drive"
				t = 0.0
		"drive":
			# Two seconds of joystick input; the host simulates the movement.
			game.controls.vector = drive
			if t > 2.0:
				game.controls.vector = Vector2.ZERO
				var moved := (game.human.pos - start_pos).dot(drive)
				print("CLIENT: #%d moved %.1f m towards the centre (state %d)" % [game.human.number, moved / Config.M, game.state])
				if moved < 5.0 * Config.M:
					push_error("host should move the client's player")
					return true
				phase = "wait_end"
		"wait_end":
			if game.state == SoccerMatch.State.MENU and game.menus.page == "lobby":
				print("CLIENT: back in lobby after full time, score ", game.score)
				print("CLIENT: audio ", game.audio.played)
				if not game.audio.played.has("whistle_final") or not game.audio.played.has("whistle_long"):
					push_error("client never heard the host's match sounds")
					return true
				phase = "wait_host_leave"
		"wait_host_leave":
			if game.net.role == "":
				print("CLIENT OK")
				return true
	return t > 60.0
