extends SceneTree
## Online lobby: hands out four-letter room codes and starts one headless
## match process per room.
##
##   godot --headless --path . -s server/lobby.gd -- [port=7777] [rooms=20]
##         [first-room-port=7801] [idle=90] [exit-when-done]
##
## Phones talk to it over TCP, one JSON line each way:
##   {"op": "create"}               -> {"ok": true, "code": "KQTZ", "port": 7803}
##   {"op": "join", "code": "KQTZ"} -> {"ok": true, ...} or {"ok": false, "error": "..."}
## A new room's process reports {"op": "ready"} on the same port once it
## listens, and only then does the phone get its answer. Rooms close
## themselves when they've been empty for `idle` seconds.

const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const REQUEST_TIMEOUT := 10.0

var port := 7777
var max_rooms := 20
var first_room_port := 7801
var idle := 90.0
## Tests: quit once at least one room has come and gone.
var exit_when_done := false

var _server := TCPServer.new()
## code -> {"port", "pid", "ready", "waiting": Array of connections}
var _rooms := {}
## Open phone / room connections: {"conn", "buffer", "age"}.
var _conns: Array = []
var _rooms_made := 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		match kv[0]:
			"port": port = kv[1].to_int()
			"rooms": max_rooms = kv[1].to_int()
			"first-room-port": first_room_port = kv[1].to_int()
			"idle": idle = kv[1].to_float()
			"exit-when-done": exit_when_done = true
	var err := _server.listen(port)
	if err != OK:
		printerr("LOBBY: cannot listen on TCP %d (error %d)" % [port, err])
		quit(1)
		return
	print("LOBBY: listening on TCP %d, rooms on UDP %d-%d" % [port, first_room_port, first_room_port + max_rooms - 1])


func _process(delta: float) -> bool:
	while _server.is_connection_available():
		_conns.append({"conn": _server.take_connection(), "buffer": "", "age": 0.0})
	for c: Dictionary in _conns.duplicate():
		_poll_conn(c, delta)
	_reap_rooms()
	return exit_when_done and _rooms_made > 0 and _rooms.is_empty()


func _poll_conn(c: Dictionary, delta: float) -> void:
	var conn: StreamPeerTCP = c["conn"]
	conn.poll()
	c["age"] += delta
	if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED or c["age"] > REQUEST_TIMEOUT:
		_close(c)
		return
	var n := conn.get_available_bytes()
	if n > 0:
		c["buffer"] += conn.get_utf8_string(n)
	var cut: int = c["buffer"].find("\n")
	if cut < 0:
		if c["buffer"].length() > 1024:
			_close(c)
		return
	var line: String = c["buffer"].left(cut)
	c["buffer"] = ""
	var msg: Variant = JSON.parse_string(line)
	if not msg is Dictionary:
		_reply(c, {"ok": false, "error": "Bad request"})
		return
	match str(msg.get("op", "")):
		"create":
			_create(c)
		"join":
			_join(c, str(msg.get("code", "")).to_upper())
		"ready":
			_room_ready(c, str(msg.get("code", "")))
		_:
			_reply(c, {"ok": false, "error": "Unknown request"})


func _create(c: Dictionary) -> void:
	var room_port := _free_port()
	if room_port < 0:
		_reply(c, {"ok": false, "error": "The server is full, try again soon"})
		return
	var code := _new_code()
	var args := PackedStringArray(["--headless"])
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--room", code, "--port", str(room_port), "--lobby", str(port), "--idle", str(idle)])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		_reply(c, {"ok": false, "error": "Could not start a room"})
		return
	_rooms[code] = {"port": room_port, "pid": pid, "ready": false, "waiting": [c]}
	_rooms_made += 1
	c["age"] = 0.0
	print("LOBBY: room %s on UDP %d (pid %d)" % [code, room_port, pid])


func _join(c: Dictionary, code: String) -> void:
	if not _rooms.has(code):
		_reply(c, {"ok": false, "error": "No room %s - check the code" % code})
		return
	var room: Dictionary = _rooms[code]
	if room["ready"]:
		_reply(c, {"ok": true, "code": code, "port": room["port"]})
	else:
		room["waiting"].append(c)


func _room_ready(c: Dictionary, code: String) -> void:
	_close(c)
	if not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	room["ready"] = true
	var waiting: Array = room["waiting"].duplicate()
	room["waiting"].clear()
	for w: Dictionary in waiting:
		_reply(w, {"ok": true, "code": code, "port": room["port"]})


func _reap_rooms() -> void:
	for code: String in _rooms.keys():
		var room: Dictionary = _rooms[code]
		if not OS.is_process_running(room["pid"]):
			print("LOBBY: room %s closed" % code)
			_rooms.erase(code)
			for w: Dictionary in room["waiting"]:
				_reply(w, {"ok": false, "error": "The room could not start"})


func _free_port() -> int:
	if _rooms.size() >= max_rooms:
		return -1
	var used := []
	for room: Dictionary in _rooms.values():
		used.append(room["port"])
	for p in range(first_room_port, first_room_port + max_rooms):
		if p not in used:
			return p
	return -1


func _new_code() -> String:
	while true:
		var code := ""
		for i in 4:
			code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
		if not _rooms.has(code):
			return code
	return ""


func _reply(c: Dictionary, data: Dictionary) -> void:
	var conn: StreamPeerTCP = c["conn"]
	conn.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())
	_close(c)


## Connections waiting for a room stay in `_conns` (and keep being polled for
## their timeout) until the room is ready.
func _close(c: Dictionary) -> void:
	_conns.erase(c)
	for room: Dictionary in _rooms.values():
		room["waiting"].erase(c)
	c["conn"].disconnect_from_host()
