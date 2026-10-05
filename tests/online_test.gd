extends SceneTree
## Online rooms test: a lobby server (server/lobby.gd) plus two phones.
##   godot --headless --path . -s server/lobby.gd -- port=7790 first-room-port=7891 idle=3 exit-when-done &
##   godot --headless --path . -s tests/online_test.gd ++ create lag=100 &
##   godot --headless --path . -s tests/online_test.gd ++ join lag=100
## "create" makes a room, waits for a friend, starts a short match and checks
## that its own player moves at once despite the lag (client-side prediction)
## and ends up where the server has it. "join" enters the room by its code.
const SERVER := "127.0.0.1:7790"
const CODE_FILE := "user://online_test_code.txt"

var game: SoccerMatch
var creator := "create" in OS.get_cmdline_user_args()
var who := "A" if creator else "B"
var t := 0.0
var frames := 0
var phase := "start"
var started_at := Time.get_unix_time_from_system()
var start_pos := Vector2.ZERO
var drive := Vector2.ZERO


func _initialize() -> void:
	GameSettings.reset_to_defaults()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _fail(msg: String) -> bool:
	push_error("%s: %s" % [who, msg])
	return true


func _process(delta: float) -> bool:
	t += delta
	frames += 1
	if t < 0.3:
		return false
	match phase:
		"start":
			game.menus.show_page("online")
			if creator:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
				game.net.create_room(SERVER)
				phase = "wait_room"
			else:
				game.net.join_room(SERVER, "QQQQ")
				phase = "bad_code"
			t = 0.0
		"bad_code":
			if game.net.status.begins_with("No room"):
				print("B: wrong code refused: ", game.net.status)
				phase = "wait_code"
			elif t > 10.0:
				return _fail("a wrong code should be refused, status: " + game.net.status)
		"wait_code":
			if FileAccess.file_exists(CODE_FILE) and FileAccess.get_modified_time(CODE_FILE) >= int(started_at) - 1:
				var code := FileAccess.get_file_as_string(CODE_FILE).strip_edges()
				if code.length() == 4:
					print("B: joining room ", code)
					game.net.join_room(SERVER, code)
					phase = "wait_room"
					t = 0.0
		"wait_room":
			var net := game.net
			if net.online and net.role == "client" and net.players.has(game.multiplayer.get_unique_id()):
				# The owner may already have started the match (page "").
				if game.menus.page != "lobby" and not game.is_client:
					return _fail("should be in the room lobby, page " + game.menus.page)
				print("%s: in room %s as P%d, owner: %s" % [who, net.room_code, net.my_slot + 1, net.can_start()])
				if net.can_start() != creator:
					return _fail("only the room creator should be able to start")
				if creator:
					var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
					f.store_string(net.room_code)
					f.close()
				phase = "wait_friend" if creator else "wait_start"
				t = 0.0
			elif t > 20.0:
				return _fail("never got into a room, status: " + net.status)
		"wait_friend":
			if game.net.players.size() == 2:
				print("A: friend joined ", game.net.players)
				game.net.request_start(25.0)
				phase = "wait_start"
				t = 0.0
		"wait_start":
			if game.is_client and game.state != SoccerMatch.State.MENU:
				var want: int = NetCoop.SLOTS[game.net.my_slot]
				if game.human.number != want:
					return _fail("should control #%d" % want)
				print("%s: playing as #%d" % [who, game.human.number])
				phase = "settle"
				t = 0.0
		"settle":
			if creator and t > 3.0 and game.state == SoccerMatch.State.PLAYING and game.human.stun <= 0.0 \
					and game.human.action == Footballer.ACT_NONE:
				start_pos = game.human.pos
				# Back into our own half and towards the middle: open space after kick-off.
				drive = Vector2(-Config.attack_dir(0), -signf(start_pos.y) * 0.4).normalized()
				game.controls.vector = drive
				phase = "instant"
				frames = 0
			elif not creator:
				phase = "wait_end"
		"instant":
			# Six frames is 0.1 s: far less than the 0.2 s round trip, so any
			# movement here is the phone's own prediction.
			if frames >= 6:
				var moved := (game.human.pos - start_pos).dot(drive)
				print("A: moved %.2f m in %d frames (round trip %d ms)" % [moved / Config.M, frames, int(game.net.lag * 2000)])
				if moved < 0.3 * Config.M:
					return _fail("own player should move before the server answers")
				phase = "drive"
				t = 0.0
		"drive":
			game.controls.vector = drive
			if t > 2.0:
				game.controls.vector = Vector2.ZERO
				phase = "agree"
				t = 0.0
		"agree":
			if t > 1.0:
				var moved := (game.human.pos - start_pos).dot(drive)
				var gap := game.human.pos.distance_to(game.human.net_pos)
				print("A: moved %.1f m; phone vs server %.2f m; biggest correction %.2f m" % [moved / Config.M, gap / Config.M, game.max_correction / Config.M])
				if moved < 5.0 * Config.M:
					return _fail("the server should move our player too")
				if gap > 1.5 * Config.M:
					return _fail("prediction and server disagree")
				phase = "wait_end"
		"wait_end":
			if game.state == SoccerMatch.State.MENU and game.menus.page == "lobby":
				print("%s: back in the room after full time, score %s" % [who, game.score])
				game.menus.go_back()
				if game.net.role != "" or game.menus.page != "online":
					return _fail("leaving should go back to the online page")
				print("ONLINE %s OK" % who)
				return true
	return t > 90.0
