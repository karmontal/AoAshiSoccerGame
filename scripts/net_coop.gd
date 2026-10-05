class_name NetCoop
extends Node
## Co-op networking. Two ways to play:
## - Wi-Fi: one phone hosts (and runs the match), up to three friends join and
##   each controls one attacker. Hosts announce themselves on the local network
##   with UDP broadcasts; joining is by tapping a found game or typing an IP.
## - Online: a dedicated server runs the match with no player of its own
##   (`--room CODE --port N`, started by server/lobby.gd), and friends join with
##   a four-letter room code. The first player in is the room's owner.
## Clients send their input; the host sends back snapshots.

signal lobby_changed
signal games_changed

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_CLIENTS := 3
## Online rooms: four players and a coach.
const ROOM_CLIENTS := 5
const LOBBY_PORT := 7777
const ONLINE_CFG := "user://online.cfg"
## Shirt numbers controlled by player 1 (host) .. player 4.
const SLOTS := [9, 10, 7, 11]
## Lobby slot of the coach (no player; tactical view and orders).
const COACH_SLOT := 4
const ANNOUNCE_EVERY := 1.0
const GAME_TIMEOUT := 3.5

var game: SoccerMatch
## "", "host" or "client".
var role := ""
## peer id -> slot (the host is peer 1, slot 0).
var players := {}
var my_slot := 0
## Found games: ip -> {"name", "players", "seen"}.
var games := {}
var status := ""
## Online: this is a dedicated room server (no local player).
var dedicated := false
## Online room code (server and clients) and the peer who may start matches.
var room_code := ""
var room_owner := 1
var online := false
## Test hook: simulated one-way delay (seconds) on input, snapshots and events.
var lag := 0.0
var _delayed: Array = []
## Online client: pending room request to the lobby server.
var _lobby_conn: StreamPeerTCP
var _lobby_request := {}
var _lobby_host := ""
var _lobby_timer := 0.0
var _lobby_buffer := ""
## Dedicated server: seconds with nobody connected, and the limit before quitting.
var _idle := 0.0
var _idle_limit := 90.0
var _ready_conn: StreamPeerTCP
var _ever_joined := false

var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_timer := 0.0
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("lag="):
			lag = arg.trim_prefix("lag=").to_float() / 1000.0
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Hosting / joining --------------------------------------------------------

func host() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_set_status("Could not host (error %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	role = "host"
	dedicated = false
	online = false
	room_code = ""
	room_owner = 1
	players = {1: 0}
	my_slot = 0
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_set_status("Hosting - friends on the same Wi-Fi can join")
	lobby_changed.emit()
	return true


func join(ip: String, port := PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port)
	if err != OK:
		_set_status("Could not connect (error %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	role = "client"
	_set_status("Connecting to %s..." % ip)
	return true


# --- Online rooms -------------------------------------------------------------

## Dedicated room server: run the match for whoever joins on `port`.
func start_dedicated(port: int, code: String, lobby_port: int, idle_limit: float) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, ROOM_CLIENTS)
	if err != OK:
		printerr("ROOM %s: cannot listen on %d (error %d)" % [code, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	role = "host"
	dedicated = true
	online = true
	room_code = code
	room_owner = 0
	players = {}
	_idle_limit = idle_limit
	game.dedicated = true
	print("ROOM %s: listening on UDP %d" % [code, port])
	if lobby_port > 0:
		# Tell the lobby we're up so it can send the player who asked for the room.
		_ready_conn = StreamPeerTCP.new()
		if _ready_conn.connect_to_host("127.0.0.1", lobby_port) != OK:
			_ready_conn = null
	return true


static func load_server_address() -> String:
	var cfg := ConfigFile.new()
	return cfg.get_value("online", "server", "") if cfg.load(ONLINE_CFG) == OK else ""


static func save_server_address(address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "server", address.strip_edges())
	cfg.save(ONLINE_CFG)


## Online client: ask the lobby server for a new room, then join it.
func create_room(server: String) -> void:
	_ask_lobby(server, {"op": "create"})


func join_room(server: String, code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Room codes have 4 letters")
		return
	_ask_lobby(server, {"op": "join", "code": code})


func _ask_lobby(server: String, request: Dictionary) -> void:
	leave()
	server = server.strip_edges()
	if server == "":
		_set_status("Type the server address first")
		return
	var host := server
	var port := LOBBY_PORT
	if ":" in server:
		host = server.get_slice(":", 0)
		port = server.get_slice(":", 1).to_int()
	if not host.is_valid_ip_address():
		host = IP.resolve_hostname(host, IP.TYPE_IPV4)
		if host == "":
			_set_status("Can't find the server %s" % server)
			return
	_lobby_conn = StreamPeerTCP.new()
	if _lobby_conn.connect_to_host(host, port) != OK:
		_lobby_conn = null
		_set_status("Can't reach the server")
		return
	_lobby_host = host
	_lobby_request = request
	_lobby_buffer = ""
	_lobby_timer = 8.0
	_set_status("Creating a room..." if request["op"] == "create" else "Looking for room %s..." % request["code"])


func cancel_online() -> void:
	if _lobby_conn != null:
		_lobby_conn.disconnect_from_host()
	_lobby_conn = null


func _poll_lobby(delta: float) -> void:
	_lobby_timer -= delta
	_lobby_conn.poll()
	var st := _lobby_conn.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		if not _lobby_request.is_empty():
			_send_line(_lobby_conn, _lobby_request)
			_lobby_request = {}
		var reply: Variant = _read_line(_lobby_conn)
		if reply is Dictionary:
			cancel_online()
			if reply.get("ok", false):
				join(_lobby_host, int(reply["port"]))
				online = true
				room_code = reply["code"]
				_set_status("Joining room %s..." % room_code)
			else:
				_set_status(reply.get("error", "The server said no"))
			return
	if st == StreamPeerTCP.STATUS_ERROR or (st == StreamPeerTCP.STATUS_NONE and _lobby_request.is_empty()) or _lobby_timer <= 0.0:
		cancel_online()
		_set_status("No answer from the server")


func _send_line(conn: StreamPeerTCP, data: Dictionary) -> void:
	conn.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())


func _read_line(conn: StreamPeerTCP) -> Variant:
	var n := conn.get_available_bytes()
	if n > 0:
		_lobby_buffer += conn.get_utf8_string(n)
	var cut := _lobby_buffer.find("\n")
	if cut < 0:
		return null
	var line := _lobby_buffer.left(cut)
	_lobby_buffer = _lobby_buffer.substr(cut + 1)
	return JSON.parse_string(line)


## May this device start the match and pick tactics?
func can_start() -> bool:
	return (role == "host" and not dedicated) or (online and role == "client" and room_owner == multiplayer.get_unique_id())


## Online room owner: ask the room server to start, with this phone's tactics and settings.
func request_start(seconds := 0.0) -> void:
	if role != "client":
		return
	var opts := {
		"formation": GameSettings.formation(),
		"mentality": GameSettings.mentality(),
		"opp_formation": game.team_formation[1],
		"opp_mentality": game.team_mentality[1],
		"difficulty": GameSettings.get_value("difficulty"),
		"seconds": seconds if seconds > 0.0 else GameSettings.match_seconds(),
	}
	start_request.rpc_id(1, opts)


## Delay a network action by the simulated lag (tests only).
func _later(action: Callable) -> void:
	if lag <= 0.0:
		action.call()
	else:
		_delayed.append([_clock + lag, action])


func leave() -> void:
	if role != "":
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = ""
	players.clear()
	_announcer = null
	_delayed.clear()
	online = false
	room_code = ""
	if game != null:
		game.end_network()
	lobby_changed.emit()


func start_discovery() -> void:
	stop_discovery()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null
		_set_status("Can't search for games here - type the host's IP instead")
	games.clear()
	games_changed.emit()


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
	_listener = null


## Host: start the co-op match for everyone in the lobby.
func start_match() -> void:
	if role != "host":
		return
	game.start_match(SoccerMatch.Mode.COOP)
	game.set_slot_tags(true)
	if not dedicated:
		game.human.set_slot(0)
	for peer: int in players:
		if peer != 1 and players[peer] != COACH_SLOT:
			game.add_remote(peer, players[peer])
	start_client_match.rpc()


static func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for ip: String in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out


func _process(delta: float) -> void:
	_clock += delta
	while not _delayed.is_empty() and _delayed[0][0] <= _clock:
		_delayed.pop_front()[1].call()
	if _lobby_conn != null:
		_poll_lobby(delta)
	if _ready_conn != null:
		_ready_conn.poll()
		if _ready_conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_send_line(_ready_conn, {"op": "ready", "code": room_code})
			_ready_conn = null
	if dedicated:
		_idle = 0.0 if not players.is_empty() else _idle + delta
		_ever_joined = _ever_joined or not players.is_empty()
		# A new room waits a while for its first player; afterwards `_idle_limit`.
		if _idle > (_idle_limit if _ever_joined else maxf(_idle_limit, 120.0)):
			print("ROOM %s: empty, closing" % room_code)
			get_tree().quit()
	if role == "host" and _announcer != null:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_EVERY
			var msg := JSON.stringify({"game": "aosoccer", "name": OS.get_model_name(), "players": players.size()})
			for target: String in ["255.255.255.255", "127.0.0.1"]:
				_announcer.set_dest_address(target, DISCOVERY_PORT)
				_announcer.put_packet(msg.to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var info: Variant = JSON.parse_string(data)
			if info is Dictionary and info.get("game", "") == "aosoccer":
				changed = changed or not games.has(ip)
				games[ip] = {"name": info.get("name", "Host"), "players": int(info.get("players", 1)), "seen": _clock}
		for ip: String in games.keys():
			if _clock - games[ip]["seen"] > GAME_TIMEOUT:
				games.erase(ip)
				changed = true
		if changed:
			games_changed.emit()


func _set_status(text: String) -> void:
	status = text
	lobby_changed.emit()


# --- Connection events ------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if role != "host":
		return
	var used: Array = players.values()
	for s in range(0 if dedicated else 1, SLOTS.size()):
		if s not in used:
			players[id] = s
			break
	if not players.has(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if dedicated and not players.has(room_owner):
		room_owner = id
		print("ROOM %s: peer %d joined as P%d (owner)" % [room_code, id, players[id] + 1])
	_sync()
	lobby_changed.emit()
	# Joining mid-match: take over a player straight away.
	if game.net_active and game.state != SoccerMatch.State.MENU:
		game.add_remote(id, players[id])
		start_client_match.rpc_id(id)


## Client: ask to be the coach (or go back to playing).
func set_coach(on: bool) -> void:
	if role == "client":
		request_role.rpc_id(1, on)


func is_coach() -> bool:
	return my_slot == COACH_SLOT


func _on_peer_disconnected(id: int) -> void:
	if role != "host":
		return
	players.erase(id)
	game.remove_remote(id)
	if dedicated and id == room_owner:
		room_owner = players.keys().min() if not players.is_empty() else 0
	_sync()


func _on_connected() -> void:
	_set_status("Connected - waiting for the host to start")


func _sync() -> void:
	if not multiplayer.get_peers().is_empty():
		sync_lobby.rpc(players, room_owner, room_code)
	lobby_changed.emit()


func _on_connection_failed() -> void:
	role = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_status("Connection failed")


func _on_server_disconnected() -> void:
	var was_playing := game.net_active
	var was_online := online
	leave()
	_set_status("Lost the connection to the server" if was_online else "The host left the game")
	if was_playing:
		game.quit_to_menu()
	game.menus.show_page("online" if was_online else "coop")


# --- Messages ---------------------------------------------------------------

func send_input(inp: PlayerInput, seq: int) -> void:
	if role == "client":
		var stick := inp.vector
		var presses := inp.presses.duplicate()
		var releases := inp.releases.duplicate()
		_later(func() -> void:
			if role == "client":
				net_input.rpc_id(1, stick, presses, releases, seq))


func send_snapshot(data: PackedFloat32Array) -> void:
	if role == "host" and not multiplayer.get_peers().is_empty():
		snapshot.rpc(data)


@rpc("authority", "call_remote", "reliable")
func sync_lobby(new_players: Dictionary, new_owner := 1, code := "") -> void:
	players = new_players
	room_owner = new_owner
	room_code = code
	my_slot = players.get(multiplayer.get_unique_id(), 0)
	if online and status.begins_with("Joining"):
		_set_status("Room %s" % room_code)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func start_client_match() -> void:
	game.start_client(my_slot)


@rpc("authority", "call_remote", "reliable")
func back_to_lobby() -> void:
	game.end_client_match()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(stick: Vector2, presses: PackedInt32Array, releases: PackedInt32Array, seq := 0) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if role == "host" and game.remote.has(peer):
		game.remote[peer]["input"].receive(stick, presses, releases, seq)


## Online: the room owner starts the match with their tactics and settings.
@rpc("any_peer", "call_remote", "reliable")
func start_request(opts: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not dedicated or peer != room_owner or game.state != SoccerMatch.State.MENU:
		return
	GameSettings.set_value("formation", maxi(Formations.NAMES.find(str(opts.get("formation", ""))), 0), false)
	GameSettings.set_value("mentality", int(opts.get("mentality", 1)), false)
	GameSettings.set_value("difficulty", int(opts.get("difficulty", 1)), false)
	var opp := str(opts.get("opp_formation", ""))
	game.team_formation[1] = opp if opp in Formations.NAMES else Formations.NAMES.pick_random()
	game.team_mentality[1] = clampi(int(opts.get("opp_mentality", 1)), 0, 2)
	start_match()
	game.time_left = clampf(float(opts.get("seconds", 180.0)), 10.0, 600.0)
	print("ROOM %s: match started by peer %d with %d player(s)" % [room_code, peer, players.size()])


@rpc("any_peer", "call_remote", "reliable")
func request_pass(number: int) -> void:
	if role == "host":
		game.remote_pass(multiplayer.get_remote_sender_id(), number)


@rpc("any_peer", "call_remote", "reliable")
func request_role(coach: bool) -> void:
	if role != "host" or game.net_active and game.state != SoccerMatch.State.MENU:
		return
	var peer := multiplayer.get_remote_sender_id()
	var used: Array = players.values()
	if coach and COACH_SLOT not in used:
		players[peer] = COACH_SLOT
	elif not coach and players.get(peer, -1) == COACH_SLOT:
		for s in range(0 if dedicated else 1, SLOTS.size()):
			if s not in used:
				players[peer] = s
				break
	_sync()


@rpc("any_peer", "call_remote", "reliable")
func coach_order(number: int, point: Vector2) -> void:
	if role == "host" and players.get(multiplayer.get_remote_sender_id(), -1) == COACH_SLOT:
		game.give_order(number, point)


@rpc("any_peer", "call_remote", "reliable")
func coach_mentality(level: int) -> void:
	if role == "host" and players.get(multiplayer.get_remote_sender_id(), -1) == COACH_SLOT:
		game.set_coach_mentality(level)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(data: PackedFloat32Array) -> void:
	_later(func() -> void: game.apply_snapshot(data))


@rpc("authority", "call_remote", "reliable")
func event(kind: String, args: Array) -> void:
	_later(func() -> void: game.apply_event(kind, args))
