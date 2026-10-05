class_name NetCoop
extends Node
## Wi-Fi co-op: one phone hosts (and runs the match), up to three friends join
## and each controls one attacker. Hosts announce themselves on the local
## network with UDP broadcasts; joining is by tapping a found game or typing
## the host's IP. Clients send their input; the host sends back snapshots.

signal lobby_changed
signal games_changed

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_CLIENTS := 3
## Shirt numbers controlled by player 1 (host) .. player 4.
const SLOTS := [9, 10, 7, 11]
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

var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_timer := 0.0
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	players = {1: 0}
	my_slot = 0
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_set_status("Hosting - friends on the same Wi-Fi can join")
	lobby_changed.emit()
	return true


func join(ip: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		_set_status("Could not connect (error %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	role = "client"
	_set_status("Connecting to %s..." % ip)
	return true


func leave() -> void:
	if role != "":
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = ""
	players.clear()
	_announcer = null
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
	game.human.set_slot(0)
	for peer: int in players:
		if peer != 1:
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
	for s in range(1, SLOTS.size()):
		if s not in used:
			players[id] = s
			break
	if not players.has(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	sync_lobby.rpc(players)
	lobby_changed.emit()
	# Joining mid-match: take over a player straight away.
	if game.net_active and game.state != SoccerMatch.State.MENU:
		game.add_remote(id, players[id])
		start_client_match.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	if role != "host":
		return
	players.erase(id)
	game.remove_remote(id)
	sync_lobby.rpc(players)
	lobby_changed.emit()


func _on_connected() -> void:
	_set_status("Connected - waiting for the host to start")


func _on_connection_failed() -> void:
	role = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_status("Connection failed")


func _on_server_disconnected() -> void:
	var was_playing := game.net_active
	leave()
	_set_status("The host left the game")
	if was_playing:
		game.quit_to_menu()
	game.menus.show_page("coop")


# --- Messages ---------------------------------------------------------------

func send_input(inp: PlayerInput) -> void:
	if role == "client":
		net_input.rpc_id(1, inp.vector, inp.presses, inp.releases)


func send_snapshot(data: PackedFloat32Array) -> void:
	if role == "host" and players.size() > 1:
		snapshot.rpc(data)


@rpc("authority", "call_remote", "reliable")
func sync_lobby(new_players: Dictionary) -> void:
	players = new_players
	my_slot = players.get(multiplayer.get_unique_id(), 0)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func start_client_match() -> void:
	game.start_client(my_slot)


@rpc("authority", "call_remote", "reliable")
func back_to_lobby() -> void:
	game.end_client_match()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(stick: Vector2, presses: PackedInt32Array, releases: PackedInt32Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if role == "host" and game.remote.has(peer):
		game.remote[peer]["input"].receive(stick, presses, releases)


@rpc("any_peer", "call_remote", "reliable")
func request_pass(number: int) -> void:
	if role == "host":
		game.remote_pass(multiplayer.get_remote_sender_id(), number)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(data: PackedFloat32Array) -> void:
	game.apply_snapshot(data)


@rpc("authority", "call_remote", "reliable")
func event(kind: String, args: Array) -> void:
	game.apply_event(kind, args)
