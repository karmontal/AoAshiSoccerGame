class_name SoccerMatch
extends Node3D
## Builds the match scene in code and runs everything: kickoff/goal flow,
## the human-controlled player, team AI, passing, shooting and possession.

enum State { MENU, KICKOFF, PLAYING, GOAL, FULLTIME, SET_PIECE, CHALLENGE }
## TEAM: control switches to whoever is nearest the ball.
## SOLO: you are always #9 and play off the ball, Ao Ashi style; teammates
## carry the ball and you call for it.
## COOP: SOLO over Wi-Fi; up to four friends each control one attacker.
enum Mode { TEAM, SOLO, COOP }

## The striker: kick-off taker and the SOLO-mode player.
const STRIKER := 9
const PLAYMAKER := 6
const KEY_BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"pass": [KEY_SPACE, KEY_J],
	"shoot": [KEY_K, KEY_ENTER],
	"vision": [KEY_L, KEY_SHIFT],
	"special": [KEY_U, KEY_I],
}

## Pass kinds: AUTO lofts it when the lane is blocked (AI default).
enum PassKind { AUTO, GROUND, LOB }
enum ShotKind { AUTO, FINESSE, POWER, CHIP }
const SHOT_NAMES := {ShotKind.FINESSE: "FINESSE!", ShotKind.POWER: "POWER SHOT!", ShotKind.CHIP: "CHIP!"}
## Hold times for the touch buttons (seconds).
const TAP_TIME := 0.18
const LOB_HOLD := 0.3
const FULL_CHARGE := 0.9
const FREE_KICK_DISTANCE := 9.15 * Config.M

const PASS_MIN := 60.0
const PASS_MAX := 55.0 * Config.M
## Time after receiving the ball before an opponent may tackle.
const RECEIVE_GRACE := 0.35

var teams: Array = [[], []]
var ball: Ball
var vision: FieldVision
var hud: Hud
var controls: TouchControls
var menus: Menus
var challenge: ChallengeMode
var net: NetCoop
var audio: GameAudio
## Local player's input; remote co-op players: peer id -> {"player", "input"}.
var local_input := PlayerInput.new()
var remote := {}
## True for both host and clients during a network game.
var net_active := false
## Clients only mirror the host's simulation.
var is_client := false
## Online room server: runs the match for remote players only, no local player.
var dedicated := false
## This device is the co-op coach: tactical view and orders, no player.
var coach_view := false
var coach_selected: Footballer = null
## Coach orders on screen: shirt number -> {"point", "time"}.
var orders := {}
var stadium: Stadium
var camera: Camera3D
var human: Footballer
var score := [0, 0]
var time_left := Config.MATCH_SECONDS
var state := State.MENU
var mode := Mode.TEAM
var coach: PositioningCoach
## When true the human's player is also AI-driven (attract mode / balance testing).
var autopilot := false
var stats := {"shots": [0, 0], "saves": [0, 0], "fouls": [0, 0]}
var team_formation := ["4-3-3", "4-3-3"]
var team_mentality := [1, 1]

var _state_timer := 0.0
var _last_holder: Footballer = null
var _last_scorer := 0
var _switch_cooldown := 0.0
var _shake := 0.0
var _clock := 0.0
var _cine_timer := 0.0
var _cine_shooter: Footballer = null
var _cine_dir := Vector2.RIGHT
var _celebrant: Footballer = null
var _cam_pos := Vector3(0, 14, 22)
var _cam_look := Vector3.ZERO
var _call_timer := 0.0
var _possession_time := 0.0
var _caller: Footballer = null
var _snapshot_timer := 0.0
## A shot is in flight: a goal-line bounce now is a near miss.
var _shot_live := false
## Client-side prediction of the local player: input number, and the
## predicted position after each input not yet confirmed by the host.
var _input_seq := 0
var _pred_history: Array = []
var _predicting := false
## Biggest correction the host applied to the prediction (tests / tuning).
var max_correction := 0.0


func _ready() -> void:
	_register_inputs()
	stadium = Stadium.new()
	add_child(stadium)
	for t in 2:
		for slot: Array in Formations.DATA[team_formation[t]]:
			var p := Footballer.new()
			p.team = t
			p.role = slot[0]
			p.formation = slot[1]
			p.number = slot[2]
			add_child(p)
			teams[t].append(p)

	ball = Ball.new()
	ball.goal_scored.connect(_on_goal)
	ball.hit_goal_line.connect(_on_goal_line)
	add_child(ball)
	audio = GameAudio.new()
	audio.game = self
	add_child(audio)

	camera = Camera3D.new()
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()

	var ui := CanvasLayer.new()
	add_child(ui)
	vision = FieldVision.new()
	vision.game = self
	ui.add_child(vision)
	challenge = ChallengeMode.new()
	challenge.game = self
	ui.add_child(challenge)
	hud = Hud.new()
	hud.game = self
	ui.add_child(hud)
	controls = TouchControls.new()
	controls.game = self
	ui.add_child(controls)
	net = NetCoop.new()
	net.name = "Net"
	net.game = self
	add_child(net)
	menus = Menus.new()
	menus.game = self
	ui.add_child(menus)

	coach = PositioningCoach.new(self)
	human = player_by_number(0, STRIKER)
	_set_human(human)
	apply_settings()
	_enter_menu()
	_start_room_from_args()


## `-- --room CODE --port N [--lobby P] [--idle S]`: run as an online room server.
func _start_room_from_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--room")
	if i < 0 or i + 1 >= args.size():
		return
	var opts := {"--port": "7801", "--lobby": "0", "--idle": "90"}
	for key: String in opts:
		var k := args.find(key)
		if k >= 0 and k + 1 < args.size():
			opts[key] = args[k + 1]
	GameSettings.reset_to_defaults()
	if not net.start_dedicated(int(opts["--port"]), args[i + 1], int(opts["--lobby"]), float(opts["--idle"])):
		get_tree().quit(1)


func _register_inputs() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# --- Match flow -------------------------------------------------------------

func _enter_menu() -> void:
	state = State.MENU
	vision.deactivate()
	_reset_positions()
	ball.place(Vector2.ZERO)
	_last_holder = null


## Applies the saved settings to the running game (called on every change).
func apply_settings() -> void:
	Engine.max_fps = 30 if GameSettings.get_value("fps_limit") == 0 else 60
	var quality := GameSettings.graphics()
	stadium.set_quality(quality)
	FX.quality = [0.4, 0.7, 1.0][quality]
	get_viewport().scaling_3d_scale = [0.7, 0.85, 1.0][quality]
	for p: Footballer in teams[1]:
		p.speed_mult = GameSettings.ai_speed()
	controls.apply_settings()


func pause_game() -> void:
	if state == State.MENU or state == State.FULLTIME or state == State.CHALLENGE or get_tree().paused:
		return
	controls.release_all()
	# A network match keeps running for everyone else.
	if not net_active:
		get_tree().paused = true
	menus.show_page("pause")


func resume_game() -> void:
	get_tree().paused = false
	menus.show_page("")


func quit_to_menu() -> void:
	get_tree().paused = false
	if net_active:
		net.leave()
	_enter_menu()
	menus.show_page("title")


func vibrate(ms: int) -> void:
	if GameSettings.enabled("vibration") and not autopilot:
		Input.vibrate_handheld(ms)


# --- Daily Vision puzzles ---------------------------------------------------

## Freezes the scene into a puzzle's situation.
func load_challenge(c: Challenge) -> void:
	state = State.CHALLENGE
	vision.deactivate()
	_reset_positions()
	for t in 2:
		apply_formation(t, c.formations[t])
		for p: Footballer in teams[t]:
			p.pos = c.positions[t][p.number]
			p.facing = Vector2(Config.attack_dir(t), 0)
	var carrier := player_by_number(c.carrier_team, c.carrier_number)
	ball.place(carrier.pos)
	ball.holder = carrier
	_last_holder = carrier
	_set_human(player_by_number(c.me_team, c.me_number))


func finish_challenge() -> void:
	_enter_menu()
	menus.show_page("daily_result")


func quit_challenge() -> void:
	challenge.active = false
	_enter_menu()
	menus.show_page("daily")


## Screen position to a point on the pitch (logic plane), or Vector2.INF.
func screen_to_pitch(screen_pos: Vector2) -> Vector2:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector2.INF
	var hit := from + dir * (-from.y / dir.y)
	return Vector2(hit.x, hit.z) / Config.WORLD_SCALE


## Starts a new match in the given mode (from the menu).
func start_match(new_mode: Mode) -> void:
	mode = new_mode
	net_active = new_mode == Mode.COOP
	score = [0, 0]
	time_left = GameSettings.match_seconds()
	apply_settings()
	vision.energy = 1.0
	stats = {"shots": [0, 0], "saves": [0, 0], "fouls": [0, 0]}
	coach.reset()
	audio.stop_voice()
	apply_tactics()
	apply_formation(1, team_formation[1])
	for t in 2:
		for p: Footballer in teams[t]:
			p.fouls = 0
	_start_kickoff(0)


## Picks the opponent's shape for the next match (shown on the tactics screen).
func prepare_opponent() -> void:
	team_formation[1] = Formations.NAMES.pick_random()
	team_mentality[1] = randi_range(0, 2)


## Applies the player's saved formation and mentality (also mid-match).
func apply_tactics() -> void:
	apply_formation(0, GameSettings.formation())
	team_mentality[0] = GameSettings.mentality()


func apply_formation(team: int, formation_name: String) -> void:
	team_formation[team] = formation_name
	for p: Footballer in teams[team]:
		var slot := Formations.slot_for(formation_name, p.number)
		p.role = slot[0]
		p.formation = slot[1]


func _reset_positions() -> void:
	end_cinematic()
	Engine.time_scale = 1.0
	_call_timer = 0.0
	if _celebrant != null:
		_celebrant.model.set_celebrating(false)
		_celebrant = null
	for t in 2:
		for p: Footballer in teams[t]:
			p.pos = formation_to_world(t, p.formation)
			p.velocity = Vector2.ZERO
			p.desired_velocity = Vector2.ZERO
			p.facing = Vector2(Config.attack_dir(t), 0)
			p.stun = 0.0
			p.end_action()


func _start_kickoff(team_with_ball: int) -> void:
	state = State.KICKOFF
	_state_timer = 1.4
	_reset_positions()
	var taker: Footballer = player_by_number(team_with_ball, STRIKER)
	taker.pos = Vector2(-Config.attack_dir(team_with_ball) * 30.0, 0)
	ball.place(Vector2.ZERO)
	ball.holder = taker
	_last_holder = taker
	taker.decision_timer = 0.6
	_set_human(player_by_number(0, STRIKER if mode != Mode.TEAM or team_with_ball == 0 else PLAYMAKER))
	banner("KICK OFF", Color(1, 0.9, 0.3), 1.2, 0.8)
	_shot_live = false
	sfx("whistle_long", -2.0)
	if score[0] + score[1] == 0:
		say("kickoff")


func _on_goal(scoring_team: int) -> void:
	if state != State.PLAYING:
		return
	score[scoring_team] += 1
	_last_scorer = scoring_team
	state = State.GOAL
	_state_timer = 3.0
	vision.deactivate()
	end_cinematic()
	var scorer := ball.last_kicker
	if scorer == null or scorer.team != scoring_team:
		scorer = nearest_to(scoring_team, ball.pos, false)
	_celebrant = scorer
	_celebrant.model.set_celebrating(true)
	vibrate(180)
	fx("confetti", [Config.to_3d(_celebrant.pos), Config.TEAM_COLORS[scoring_team]])
	fx("shake", [18.0])
	banner("GOAL!!", Config.TEAM_COLORS[scoring_team], 2.6, 1.2)
	_shot_live = false
	sfx("net")
	sfx("cheer", 0.0 if scoring_team == 0 else -7.0)
	crowd(1.0)
	say("goal")


func _end_match() -> void:
	state = State.FULLTIME
	_state_timer = 6.0
	time_left = 0.0
	ball.frozen = true
	vision.deactivate()
	sfx("whistle_final", -2.0)
	sfx("cheer", -6.0)
	crowd(0.7)
	say("fulltime")


## Called by TouchControls for touches that didn't land on a button.
## Returns true if the tap was consumed.
func handle_screen_tap(screen_pos: Vector2) -> bool:
	if state == State.MENU:
		return false
	if state == State.CHALLENGE:
		return challenge.handle_tap(screen_pos)
	if state == State.FULLTIME:
		_leave_fulltime()
		return true
	if not vision.active or ball.holder != human:
		return false
	var target: Footballer = null
	var best_d := 70.0
	for mate: Footballer in teams[0]:
		var world := Config.to_3d(mate.pos) + Vector3(0, 1.0, 0)
		if mate == human or camera.is_position_behind(world):
			continue
		var d := camera.unproject_position(world).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			target = mate
	if target == null:
		return false
	if is_client:
		net.request_pass.rpc_id(1, target.number)
	else:
		pass_to(human, target)
	audio.say("vision", 0.6)
	vision.deactivate()
	return true


func _leave_fulltime() -> void:
	_enter_menu()
	if net_active:
		if not is_client:
			net.back_to_lobby.rpc()
		menus.show_page("lobby")
	else:
		menus.show_page("modes")


## Host: a client tapped a teammate in Field Vision.
func remote_pass(peer_id: int, number: int) -> void:
	var p: Footballer = remote[peer_id]["player"] if remote.has(peer_id) else null
	if p != null and ball.holder == p and state == State.PLAYING:
		pass_to(p, player_by_number(p.team, number))


# --- Per-frame update -------------------------------------------------------

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_clock += real
	if state == State.FULLTIME:
		if Input.is_action_just_pressed("pass") or Input.is_action_just_pressed("shoot"):
			_leave_fulltime()
	elif state == State.PLAYING and not autopilot and not coach_view and not dedicated:
		local_input.sample_local(_input_vector())
		if is_client:
			_track_client_charges()
			if local_input.just_pressed["vision"]:
				vision.toggle()
		else:
			_handle_actions_for(human, local_input, true)
		for peer: int in remote:
			var r: Dictionary = remote[peer]
			_handle_actions_for(r["player"], r["input"], false)
			r["input"].clear_edges()
	if is_client and not coach_view:
		coach.update(real)
	human.hide_marker = cinematic_active() or state == State.GOAL or state == State.MENU
	for n: int in orders.keys():
		orders[n]["time"] -= real
		if orders[n]["time"] <= 0.0:
			orders.erase(n)
	_update_camera(real)


func _physics_process(delta: float) -> void:
	if is_client:
		_predict_local(delta)
		_smooth_remote_state(delta)
		return
	match state:
		State.MENU, State.CHALLENGE:
			for t in 2:
				for p: Footballer in teams[t]:
					p.desired_velocity = Vector2.ZERO
					p.step(delta)
			return
		State.KICKOFF, State.SET_PIECE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.PLAYING
			return
		State.GOAL, State.FULLTIME:
			for t in 2:
				for p: Footballer in teams[t]:
					p.desired_velocity = Vector2.ZERO
					p.step(delta)
			if state == State.FULLTIME and dedicated:
				# Nobody taps "continue" on a server: back to the room lobby after a while.
				_state_timer -= delta
				if _state_timer <= 0.0:
					_leave_fulltime()
			if state == State.GOAL:
				_state_timer -= delta
				if _state_timer <= 0.0:
					if time_left <= 0.0:
						_end_match()
					else:
						_start_kickoff(1 - _last_scorer)
			return

	time_left -= delta
	if time_left <= 0.0:
		_end_match()
		return
	_switch_cooldown -= delta
	_call_timer -= delta
	_possession_time += delta
	if not autopilot and not dedicated:
		_move_controlled(human, _input_vector())
	for peer: int in remote:
		var inp: PlayerInput = remote[peer]["input"]
		inp.next_move()
		_move_controlled(remote[peer]["player"], inp.vector)
	_update_ai(delta)
	for t in 2:
		for p: Footballer in teams[t]:
			p.step(delta)
	_separate_players()
	_handle_ball_contacts()
	_check_possession_change()
	coach.update(delta)
	if net_active:
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = 1.0 / 30.0
			net.send_snapshot(build_snapshot())


func _input_vector() -> Vector2:
	var v := controls.vector
	if v.length() < 0.05:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return v.limit_length(1.0)


func _move_controlled(p: Footballer, v: Vector2) -> void:
	if v.length() > 0.1:
		var mult := Config.DRIBBLE_SPEED_MULT if ball.holder == p else 1.0
		p.desired_velocity = v * Config.PLAYER_SPEED * mult
	elif ball.intended_receiver == p or (ball.holder == null and p.pos.distance_to(ball.pos) < 140.0):
		# Help the player: step towards a pass or a nearby loose ball.
		p.desired_velocity = _steer(p, ball.target_point(), 1.0)
	else:
		p.desired_velocity = Vector2.ZERO


## With the ball: PASS (tap = ground, hold = lofted), SHOOT (tap = finesse,
## hold = power, joystick pulled back = chip), SPECIAL = through ball.
## Without it: PASS = switch / call, SHOOT = standing tackle, SPECIAL = slide.
func _handle_actions_for(p: Footballer, inp: PlayerInput, local: bool) -> void:
	if local and inp.just_pressed["vision"]:
		vision.toggle()
	var v := inp.vector
	var aim := v if v.length() > 0.2 else p.facing
	var has_ball := ball.holder == p
	var dir := Vector2(Config.attack_dir(p.team), 0)

	if inp.just_pressed["pass"]:
		if has_ball:
			inp.press_start["pass"] = _clock
		elif mode != Mode.TEAM:
			_call_for_ball(p)
		elif local:
			_switch_to_nearest()
	if inp.just_released["pass"] and inp.press_start["pass"] >= 0.0:
		var held: float = _clock - inp.press_start["pass"]
		inp.press_start["pass"] = -1.0
		var target := best_pass_target(p, aim) if has_ball else null
		if target != null:
			pass_to(p, target, PassKind.LOB if held >= LOB_HOLD else PassKind.GROUND)
			if local:
				vision.deactivate()

	if inp.just_pressed["shoot"]:
		if has_ball:
			inp.press_start["shoot"] = _clock
		elif not _ball_with_teammate(p):
			try_tackle(p)
	if inp.just_released["shoot"] and inp.press_start["shoot"] >= 0.0:
		var held: float = _clock - inp.press_start["shoot"]
		inp.press_start["shoot"] = -1.0
		if has_ball:
			if local:
				vision.deactivate()
			var kind := ShotKind.FINESSE if held < TAP_TIME else ShotKind.POWER
			if v.dot(dir) < -0.5:
				kind = ShotKind.CHIP
			shoot(p, v.y, kind, clampf(held / FULL_CHARGE, 0.0, 1.0))

	if inp.just_pressed["special"]:
		if has_ball:
			var target := best_pass_target(p, (aim + dir).normalized())
			if target != null:
				through_pass(p, target)
				if local:
					vision.deactivate()
		elif not _ball_with_teammate(p):
			try_slide(p, aim)

	if not has_ball:
		inp.reset_charges()


## 0..1 while a PASS/SHOOT button is held with the ball (for the charge ring).
func charge_ratio(action: String) -> float:
	var started: float = local_input.press_start.get(action, -1.0)
	if started < 0.0:
		return 0.0
	var full := LOB_HOLD if action == "pass" else FULL_CHARGE
	return clampf((_clock - started) / full, 0.0, 1.0)


func _ball_with_teammate(p: Footballer) -> bool:
	return ball.holder != null and ball.holder.team == p.team


func try_tackle(p: Footballer) -> void:
	var to_ball := ball.pos - p.pos
	var dir := to_ball if to_ball.length() < 4.0 * Config.M else p.facing
	if p.start_tackle(dir):
		sfx("tackle", -8.0, 0.1)


func try_slide(p: Footballer, dir: Vector2) -> void:
	if p.start_slide(dir):
		fx("grass", [Config.to_3d(p.pos), 8])
		sfx("slide", -7.0, 0.1)
		if p == human:
			vibrate(25)


## SOLO / COOP: ask the teammate on the ball to pass to you.
func _call_for_ball(p: Footballer) -> void:
	var h := ball.holder
	if h == null or h.team != p.team or h == p:
		return
	_call_timer = 1.5
	_caller = p
	h.decision_timer = minf(h.decision_timer, 0.15)
	if p == human:
		hud.popup("CALL!", Config.to_3d(p.pos) + Vector3(0, 2.5, 0), Color(1, 0.9, 0.3))


func _set_human(p: Footballer) -> void:
	if human != null:
		human.is_human = _remote_owns(human)
	human = p
	# A room server has no local player: its "human" is AI unless a friend has it.
	human.is_human = not dedicated or _remote_owns(p)


func _remote_owns(p: Footballer) -> bool:
	for peer: int in remote:
		if remote[peer]["player"] == p:
			return true
	return false


func _switch_to_nearest() -> void:
	var nearest := nearest_to(0, ball.pos, true)
	if nearest != null and nearest != human:
		_set_human(nearest)
		_switch_cooldown = 0.8


func _auto_switch() -> void:
	if mode != Mode.TEAM or _switch_cooldown > 0.0 or (ball.holder != null and ball.holder.team == 0):
		return
	if ball.intended_receiver != null and ball.intended_receiver.team == 0:
		return
	var nearest := nearest_to(0, ball.pos, true)
	if nearest == null or nearest == human:
		return
	if human.pos.distance_to(ball.pos) > nearest.pos.distance_to(ball.pos) + 160.0:
		_set_human(nearest)
		_switch_cooldown = 0.8


## Camera director: broadcast view following the ball, a low cinematic angle
## behind the shooter, an orbit around the scorer, and a bird's-eye view for vision.
func _update_camera(real: float) -> void:
	var ball3 := Config.to_3d(ball.pos, ball.height)
	var target_pos: Vector3
	var target_look: Vector3
	var fov := 42.0
	var follow := 4.0
	if state == State.CHALLENGE and challenge.active:
		var c := challenge.current()
		var centre := c.carrier_pos() + Vector2(Config.attack_dir(c.carrier_team) * 4.0 * Config.M, 0)
		var height := 54.0
		if c.kind != Challenge.Kind.PASS:
			centre = (c.carrier_pos() + c.me_pos()) * 0.5
			height = 40.0
		target_look = Config.to_3d(centre)
		target_pos = target_look + Vector3(0, height, height * 0.45)
		fov = 46.0
		follow = 3.0
	elif state == State.MENU:
		var a := _clock * 0.12
		target_pos = Vector3(sin(a) * 46.0, 15.0, cos(a) * 40.0)
		target_look = Vector3(0, 1.0, 0)
		fov = 50.0
		follow = 2.0
	elif vision.active:
		target_pos = Vector3(0, 68, 34)
		target_look = Vector3(0, 0, 2.0)
		fov = 48.0
	elif _cine_timer > 0.0 and _cine_shooter != null:
		var d3 := Vector3(_cine_dir.x, 0, _cine_dir.y)
		var shooter := Config.to_3d(_cine_shooter.pos)
		_cine_timer -= real
		if _cine_timer <= 0.0:
			end_cinematic()
		target_pos = shooter - d3 * 3.4 + Vector3(0, 1.3, 0) + d3.cross(Vector3.UP) * 1.6
		target_look = shooter + d3 * 6.0 + Vector3(0, 1.0, 0)
		fov = 58.0
		follow = 14.0
	elif state == State.GOAL and _celebrant != null:
		var c := Config.to_3d(_celebrant.pos)
		var a := _clock * 0.7
		target_pos = c + Vector3(cos(a) * 7.5, 3.2, sin(a) * 7.5)
		target_look = c + Vector3(0, 1.2, 0)
		fov = 50.0
	else:
		var lead := Vector3(ball.velocity.x, 0, ball.velocity.y) * Config.WORLD_SCALE * 0.3
		target_look = Vector3(ball3.x, 0, ball3.z * 0.8) + lead
		var lim := Config.HALF_L * Config.WORLD_SCALE - 7.0
		target_look.x = clampf(target_look.x, -lim, lim)
		var k := GameSettings.camera_distance()
		target_pos = Vector3(target_look.x, 13.0 * k, target_look.z * 0.45 + 21.0 * k)
	var t := 1.0 - exp(-follow * real)
	_cam_pos = _cam_pos.lerp(target_pos, t)
	_cam_look = _cam_look.lerp(target_look, t)
	camera.position = _cam_pos
	if not _cam_pos.is_equal_approx(_cam_look):
		camera.look_at(_cam_look)
	camera.fov = lerpf(camera.fov, fov, t)
	_shake = maxf(_shake - 40.0 * real, 0.0)
	camera.h_offset = randf_range(-1, 1) * _shake * 0.02
	camera.v_offset = randf_range(-1, 1) * _shake * 0.02


func cinematic_active() -> bool:
	return _cine_timer > 0.0


func _start_cinematic(shooter: Footballer, dir: Vector2) -> void:
	_cine_shooter = shooter
	_cine_dir = dir
	_cine_timer = 0.7
	if not net_active:
		Engine.time_scale = 0.3


func end_cinematic() -> void:
	if _cine_timer > 0.0 or _cine_shooter != null:
		_cine_timer = 0.0
		_cine_shooter = null
		if not vision.active:
			Engine.time_scale = 1.0


# --- Team AI ----------------------------------------------------------------

func _update_ai(delta: float) -> void:
	_auto_switch()
	var owner_team := ball.holder.team if ball.holder != null else -1
	var predicted := ball.target_point()
	for t in 2:
		var chaser: Footballer = null
		if owner_team != t:
			if ball.intended_receiver != null and ball.intended_receiver.team == t:
				chaser = ball.intended_receiver
			else:
				chaser = nearest_to(t, predicted, true)
		# Against a pass in flight, only go for the interception if we can get
		# there first; otherwise close down the receiver from the goal side.
		var press_target := Vector2.INF
		var receiver := ball.intended_receiver
		if chaser != null and receiver != null and receiver.team != t and ball.holder == null:
			var ours := chaser.pos.distance_to(predicted) / (Config.PLAYER_SPEED * chaser.speed_mult)
			var theirs := receiver.pos.distance_to(predicted) / Config.PLAYER_SPEED
			if ours > theirs * 0.8:
				var own_goal := Vector2(-Config.attack_dir(t) * Config.HALF_L, 0)
				press_target = predicted + (own_goal - predicted).normalized() * 2.5 * Config.M
		for p: Footballer in teams[t]:
			if p.is_human and not autopilot:
				continue
			if p == ball.holder:
				_ai_carry(p)
			elif p.role == Footballer.GK:
				_ai_goalkeeper(p)
			elif p == chaser:
				var target := predicted if ball.holder == null else ball.pos
				if press_target != Vector2.INF:
					target = press_target
				elif ball.holder != null:
					target = _jockey_target(p)
				p.desired_velocity = _steer(p, target, 1.0)
			elif p.order_time > 0.0:
				p.desired_velocity = _steer(p, p.order_point, 1.0)
			else:
				var spot := _support_position(p, owner_team == t)
				if owner_team == t:
					spot = _find_space(p, spot)
				p.desired_velocity = _steer(p, spot, 0.85)


## Pressing the carrier: stay goal-side at arm's length, and now and then
## commit to a tackle.
func _jockey_target(p: Footballer) -> Vector2:
	var carrier := ball.holder
	if p.lunge <= 0.0 and p.tackle_cooldown <= 0.0 and p.pos.distance_to(carrier.pos) < 3.5 * Config.M:
		if randf() < get_physics_process_delta_time() * 1.1:
			if randf() < 0.3 and p.pos.distance_to(carrier.pos) > 1.5 * Config.M:
				try_slide(p, ball.target_point() - p.pos)
				return ball.pos
			p.lunge = 0.5
	if p.lunge > 0.0:
		return ball.pos
	var own_goal := Vector2(-Config.attack_dir(p.team) * Config.HALF_L, 0)
	return carrier.pos + (own_goal - carrier.pos).normalized() * 2.4 * Config.M


func _steer(p: Footballer, target: Vector2, speed_factor: float) -> Vector2:
	var to := target - p.pos
	var d := to.length()
	if d < 6.0:
		return Vector2.ZERO
	var spd := Config.PLAYER_SPEED * speed_factor * clampf(d / 60.0, 0.25, 1.0)
	return to / d * spd


## Off-ball positioning: hold the formation shape but slide with the ball,
## push up in possession and drop off without it.
func _support_position(p: Footballer, attacking: bool) -> Vector2:
	var dir := Config.attack_dir(p.team)
	var ball_x := ball.pos.x * dir / Config.HALF_L
	var x := p.formation.x + 0.5 * (ball_x + 0.2)
	if attacking:
		x += 0.3 if p.role == Footballer.FWD else 0.22
	else:
		x -= 0.08
	x += Formations.MENTALITY_SHIFT[team_mentality[p.team]]
	match p.role:
		Footballer.DEF:
			x = clampf(x, -0.85, 0.3)
		Footballer.MID:
			x = clampf(x, -0.7, 0.65)
		_:
			x = clampf(x, -0.45, 0.85)
	var y := p.formation.y + (ball.pos.y / Config.HALF_W) * 0.35
	return Vector2(x * Config.HALF_L * dir, clampf(y, -0.9, 0.9) * Config.HALF_W)


## Attacking off-ball movement: around the formation spot, pick the nearby
## point with the most room from opponents and an open lane to the ball.
## Re-evaluated a few times per second per player.
func _find_space(p: Footballer, base: Vector2) -> Vector2:
	p.space_timer -= get_physics_process_delta_time()
	if p.space_timer > 0.0 and p.space_base.distance_to(base) < 3.0 * Config.M:
		return p.space_target
	p.space_timer = randf_range(0.3, 0.5)
	p.space_base = base
	var opp := 1 - p.team
	var dir := Config.attack_dir(p.team)
	var step := 6.0 * Config.M
	var best := base
	var best_score := -INF
	for ix in range(-1, 2):
		for iy in range(-1, 2):
			var c := base + Vector2(ix * step, iy * step)
			c.x = clampf(c.x, -Config.HALF_L + Config.M, Config.HALF_L - Config.M)
			c.y = clampf(c.y, -Config.HALF_W + Config.M, Config.HALF_W - Config.M)
			var room := INF
			for o: Footballer in teams[opp]:
				room = minf(room, o.pos.distance_to(c))
			var s := minf(room, 12.0 * Config.M)
			if ball.holder != null:
				s += minf(lane_clearance(ball.holder.pos, c, opp), 4.0 * Config.M) * 0.8
			s += (c.x - base.x) * dir * 0.15
			s -= c.distance_to(base) * 0.1
			if s > best_score:
				best_score = s
				best = c
	p.space_target = best
	return best


func _ai_goalkeeper(p: Footballer) -> void:
	var dir := Config.attack_dir(p.team)
	var goal := Vector2(-dir * Config.HALF_L, 0)
	var limit := Config.GOAL_WIDTH * 0.45
	if ball.holder == null and ball.pos.distance_to(goal) < 260.0:
		p.desired_velocity = _steer(p, ball.pos + ball.velocity * 0.2, 1.1)
		return
	var target := goal + Vector2(dir * 40.0, clampf(ball.pos.y * 0.25, -limit, limit))
	if ball.holder == null and ball.velocity.x * -dir > 400.0:
		var tt := (target.x - ball.pos.x) / ball.velocity.x
		if tt > 0.0 and tt < 1.5:
			target.y = clampf(ball.pos.y + ball.velocity.y * tt, -Config.GOAL_WIDTH * 0.6, Config.GOAL_WIDTH * 0.6)
	p.desired_velocity = _steer(p, target, 1.15)


func _ai_carry(p: Footballer) -> void:
	var dir := Config.attack_dir(p.team)
	var goal := Vector2(dir * Config.HALF_L, 0)
	var dist_goal := p.pos.distance_to(goal)
	var opp := nearest_to(1 - p.team, p.pos, false)
	var pressure := opp.pos.distance_to(p.pos) if opp != null else 9999.0

	if p.decision_timer <= 0.0:
		p.decision_timer = randf_range(0.25, 0.45) * (GameSettings.ai_reaction() if p.team == 1 else 1.0)
		if _call_timer > 0.0 and _caller != null and p.team == _caller.team and p != _caller and mode != Mode.TEAM:
			var d := p.pos.distance_to(_caller.pos)
			if d > PASS_MIN and d < PASS_MAX and (lane_clearance(p.pos, _caller.pos, 1 - p.team) > 25.0 or randf() < 0.4):
				_call_timer = 0.0
				pass_to(p, _caller)
				return
		if p.role == Footballer.GK:
			var outlet := best_pass_target(p, Vector2(dir, 0))
			if outlet != null:
				pass_to(p, outlet)
				return
		var shot_range := 30.0 * Config.M
		if dist_goal < shot_range and absf(p.pos.y) < 20.0 * Config.M:
			var keen := 1.0 if dist_goal < 18.0 * Config.M else 0.35
			if (pressure > 2.5 * Config.M or randf() < 0.5) and randf() < keen:
				shoot(p, randf_range(-0.85, 0.85))
				return
		var best := best_pass_target(p, Vector2(dir, 0))
		var gain := (best.pos.x - p.pos.x) * dir if best != null else -INF
		var runner := _find_runner(p)
		if runner != null and randf() < 0.3:
			through_pass(p, runner)
			return
		if best != null and gain > 8.0 * Config.M and randf() < 0.35:
			var long := p.pos.distance_to(best.pos) > 28.0 * Config.M
			pass_to(p, best, PassKind.LOB if long and randf() < 0.6 else PassKind.AUTO)
			return
		if pressure < 1.8 * Config.M and best != null and randf() < 0.6:
			pass_to(p, best)
			return

	# Dribble at goal, veering away from the nearest opponent; with room ahead, go faster.
	var want := (goal - p.pos).normalized()
	if opp != null and pressure < 6.0 * Config.M:
		want = (want + (p.pos - opp.pos).normalized() * 0.8).normalized()
	var mult := 1.0 if pressure > 6.0 * Config.M else Config.DRIBBLE_SPEED_MULT
	p.desired_velocity = want * Config.PLAYER_SPEED * mult


# --- Passing, shooting, possession -----------------------------------------

func nearest_to(team: int, point: Vector2, exclude_keeper: bool) -> Footballer:
	var best: Footballer = null
	var best_d := INF
	for p: Footballer in teams[team]:
		if exclude_keeper and p.role == Footballer.GK:
			continue
		var d := p.pos.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = p
	return best


## Smallest distance from any opponent to the segment a-b.
func lane_clearance(a: Vector2, b: Vector2, opponent_team: int) -> float:
	var clearance := INF
	for o: Footballer in teams[opponent_team]:
		var closest := Geometry2D.get_closest_point_to_segment(o.pos, a, b)
		clearance = minf(clearance, closest.distance_to(o.pos))
	return clearance


func pass_score(from: Footballer, mate: Footballer) -> float:
	var dir := Config.attack_dir(from.team)
	var s := clampf(lane_clearance(from.pos, mate.pos, 1 - from.team) / 80.0, 0.0, 1.5)
	s += (mate.pos.x - from.pos.x) * dir / 400.0
	s -= absf(from.pos.distance_to(mate.pos) - 320.0) / 700.0
	var marker := nearest_to(1 - from.team, mate.pos, false)
	if marker != null:
		s += clampf(marker.pos.distance_to(mate.pos) / 150.0, 0.0, 1.0)
	return s


## Best teammate to pass to, biased towards the direction the player is aiming.
func best_pass_target(from: Footballer, aim: Vector2) -> Footballer:
	var best: Footballer = null
	var best_score := -INF
	var aim_n := aim.normalized() if aim.length() > 0.01 else from.facing
	for mate: Footballer in teams[from.team]:
		if mate == from:
			continue
		var to := mate.pos - from.pos
		var d := to.length()
		if d < PASS_MIN or d > PASS_MAX:
			continue
		var align := aim_n.dot(to / d)
		var s := pass_score(from, mate) + align * 2.0
		if mode != Mode.TEAM and mate.is_human and not autopilot:
			s += 0.6
		if align < -0.2:
			s -= 3.0
		if s > best_score:
			best_score = s
			best = mate
	return best


func pass_to(from: Footballer, to: Footballer, kind := PassKind.AUTO) -> void:
	var lead := to.pos + to.velocity * 0.4
	var offset := lead - from.pos
	var d := offset.length()
	if d < 1.0:
		return
	var lift := 0.0
	var spd := clampf(d * Ball.GROUND_DAMP + 20.0 * Config.M, 22.0 * Config.M, 60.0 * Config.M)
	var blocked := lane_clearance(from.pos, lead, 1 - from.team) < 30.0 and d > 9.0 * Config.M
	if kind == PassKind.LOB or (kind == PassKind.AUTO and blocked):
		# Lane is blocked: chip it over. Airtime T = 2 * lift / g.
		lift = clampf(d * 0.3, 7.0 * Config.M, 11.0 * Config.M)
		var airtime := 2.0 * lift / Ball.GRAVITY
		spd = d / airtime * (1.0 + Ball.AIR_DAMP * airtime * 0.5) * 0.9
	from.facing = offset / d
	from.play_kick()
	ball.kick(offset / d * spd, lift, from, to)
	if from == human:
		vibrate(20)
	fx("kick", [Config.to_3d(from.pos + from.facing * 16.0, 5.0), Color(1, 0.97, 0.8), 0.6])
	if from.team == 0 and mode == Mode.TEAM:
		_set_human(to)


## Pass into the space ahead of a teammate so they run onto it.
func through_pass(from: Footballer, to: Footballer) -> void:
	var dir := Config.attack_dir(from.team)
	var run := Vector2(dir, 0)
	if to.velocity.length() > Config.M:
		run = (run * 0.6 + to.velocity.normalized() * 0.4).normalized()
	var point := to.pos + run * 7.0 * Config.M
	point.x = clampf(point.x, -Config.HALF_L + 2.0 * Config.M, Config.HALF_L - 2.0 * Config.M)
	point.y = clampf(point.y, -Config.HALF_W + 2.0 * Config.M, Config.HALF_W - 2.0 * Config.M)
	var offset := point - from.pos
	var d := offset.length()
	if d < 1.0:
		return
	# Rolling distance with exponential drag: d = v0 / k * (1 - e^(-k t)); arrive with the runner.
	var k := Ball.GROUND_DAMP
	var t := maxf(to.pos.distance_to(point) / Config.PLAYER_SPEED, 0.6)
	var spd := clampf(d * k / (1.0 - exp(-k * t)), 16.0 * Config.M, 55.0 * Config.M)
	from.facing = offset / d
	from.play_kick()
	ball.kick(offset / d * spd, 0.0, from, to)
	if from == human:
		vibrate(20)
		hud.popup("THROUGH BALL", Config.to_3d(from.pos) + Vector3(0, 2.5, 0), Color(0.6, 0.9, 1.0))
	say("through", 0.5 if from.team == 0 else 0.2)
	fx("kick", [Config.to_3d(from.pos + from.facing * 16.0, 5.0), Color(0.75, 0.95, 1.0), 0.7])
	if from.team == 0 and mode == Mode.TEAM:
		_set_human(to)


## A forward teammate making a run with space in behind, for a through ball.
func _find_runner(from: Footballer) -> Footballer:
	var dir := Config.attack_dir(from.team)
	var deepest := -INF
	for o: Footballer in teams[1 - from.team]:
		if o.role != Footballer.GK:
			deepest = maxf(deepest, o.pos.x * dir)
	for mate: Footballer in teams[from.team]:
		if mate == from or mate.role == Footballer.GK or mate.role == Footballer.DEF:
			continue
		var ahead := (mate.pos.x - from.pos.x) * dir
		var near_line := mate.pos.x * dir > deepest - 4.0 * Config.M
		if ahead > 6.0 * Config.M and near_line and mate.velocity.x * dir > 0.0 \
				and from.pos.distance_to(mate.pos) < 40.0 * Config.M:
			return mate
	return null


## FINESSE: placed and curled into the corner. POWER: faster the longer the
## button is held, but less accurate and may fly over. CHIP: lofted over an
## advancing keeper. AUTO lets the AI pick.
func shoot(p: Footballer, aim: float, kind := ShotKind.AUTO, power := 0.6) -> void:
	var dir := Config.attack_dir(p.team)
	var goal_x := dir * Config.HALF_L
	var target := Vector2(goal_x + dir * 30.0, clampf(aim, -1.0, 1.0) * (Config.GOAL_WIDTH * 0.5 - 0.5 * Config.M))
	var dist := p.pos.distance_to(target)
	if kind == ShotKind.AUTO:
		var keeper := player_by_number(1 - p.team, 1)
		var keeper_out := absf(keeper.pos.x - goal_x) > 4.0 * Config.M
		if keeper_out and dist < 28.0 * Config.M and randf() < 0.5:
			kind = ShotKind.CHIP
		else:
			kind = ShotKind.FINESSE if randf() < 0.5 else ShotKind.POWER
			power = randf_range(0.4, 1.0)

	var err_mult := 0.55
	if kind == ShotKind.POWER:
		err_mult = 0.6 + 0.8 * power
	elif kind == ShotKind.CHIP:
		err_mult = 0.7
	if p.team == 1:
		err_mult *= GameSettings.ai_shot_error()
	target.y += randf_range(-1.0, 1.0) * dist * 0.07 * err_mult
	var to := target - p.pos
	var d := to.length()

	var speed := 27.0 * Config.M
	var lift := randf_range(0.5, 2.5) * Config.M
	var curl := 0.0
	match kind:
		ShotKind.FINESSE:
			# Constant curl w over flight time T: start w*T/2 off-line so the arc ends on target,
			# bending outwards first and back in towards the corner.
			var w := 0.9
			var time := d / speed
			var out := Vector2(0, signf(target.y) if target.y != 0.0 else 1.0)
			if to.rotated(-w * time * 0.5).dot(out) < to.dot(out):
				w = -w
			curl = w
			to = to.rotated(-w * time * 0.5)
		ShotKind.POWER:
			speed = lerpf(30.0, 48.0, power) * Config.M
			lift = randf_range(0.5, 2.0 + 7.5 * power) * Config.M
		ShotKind.CHIP:
			speed = 15.0 * Config.M
			var time := d / speed
			lift = minf((1.6 * Config.M + 0.5 * Ball.GRAVITY * time * time) / time, 14.0 * Config.M)
	var v := to.normalized() * speed
	p.facing = v.normalized()
	p.play_kick()
	if p == human:
		vibrate(30 + int(30 * power))
	ball.kick(v, lift, p, null, curl)
	fx("kick", [Config.to_3d(p.pos + p.facing * 16.0, 5.0), Config.TEAM_COLORS[p.team].lightened(0.5), 1.0 + power])
	fx("shake", [4.0 + 6.0 * power])
	stats["shots"][p.team] += 1
	banner(SHOT_NAMES[kind], Config.TEAM_COLORS[p.team], 0.6, 0.55)
	_shot_live = true
	crowd(0.55)
	say("shot", 0.3)
	if not autopilot or p.team == 0:
		_start_cinematic(p, v.normalized())


func _separate_players() -> void:
	var all: Array = teams[0] + teams[1]
	var min_d := Config.PLAYER_RADIUS * 2.0
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Footballer = all[i]
			var b: Footballer = all[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist < min_d and dist > 0.01:
				var push := d / dist * (min_d - dist) * 0.5
				a.pos -= push
				b.pos += push


func _handle_ball_contacts() -> void:
	if ball.frozen:
		return
	for t in 2:
		for p: Footballer in teams[t]:
			if p.action != Footballer.ACT_NONE and not p.action_resolved:
				_resolve_action(p)
				if state != State.PLAYING:
					return
	if ball.holder == null:
		var best: Footballer = null
		var best_d := INF
		for t in 2:
			for p: Footballer in teams[t]:
				if p.busy() or not ball.can_be_taken_by(p):
					continue
				var reach := Config.PLAYER_RADIUS + Config.BALL_RADIUS + (16.0 if p.role == Footballer.GK else 4.0)
				var d := p.pos.distance_to(ball.pos)
				if d < reach and d < best_d:
					best = p
					best_d = d
		if best == null:
			return
		var fast := ball.velocity.length() > 45.0 * Config.M
		if fast and best != ball.intended_receiver and best.role != Footballer.GK and randf() < 0.5:
			ball.deflect(best)
		else:
			if best.role == Footballer.GK and ball.last_kicker != null and ball.last_kicker.team != best.team and ball.velocity.length() > 900.0:
				stats["saves"][best.team] += 1
				sfx("kick", -3.0, 0.1)
				if _shot_live:
					sfx("ooh", -4.0)
					crowd(0.8)
					say("save")
			_shot_live = false
			ball.holder = best
			ball.intended_receiver = null
		return

	var h := ball.holder
	for p: Footballer in teams[1 - h.team]:
		if p.tackle_cooldown > 0.0 or p.busy() or _possession_time < RECEIVE_GRACE:
			continue
		if p.is_human and not autopilot:
			continue  # The human tackles with the buttons.
		if p.pos.distance_to(ball.pos) < Config.PLAYER_RADIUS + Config.BALL_RADIUS + 6.0:
			p.tackle_cooldown = 0.9
			var chance := 0.1 if h.role == Footballer.GK else (GameSettings.ai_tackle() if p.team == 1 else 0.4)
			if randf() < chance:
				ball.holder = p
				h.stun = 0.45
				if h == human:
					vibrate(60)
				fx("grass", [Config.to_3d(ball.pos), 10])
				sfx("tackle", -4.0, 0.1)
				break


func _check_possession_change() -> void:
	if ball.holder == _last_holder:
		return
	var previous := _last_holder
	_last_holder = ball.holder
	_possession_time = 0.0
	if ball.holder == null:
		return
	var h := ball.holder
	h.decision_timer = 0.8 if h.role == Footballer.GK else randf_range(0.25, 0.45)
	_call_timer = 0.0
	if h == human and previous == null and ball.last_kicker != null and state == State.PLAYING:
		if ball.last_kicker.team != human.team:
			coach.on_interception()
		elif mode != Mode.TEAM and ball.last_kicker != human:
			coach.on_received_pass()
	if h.team == 0 and mode == Mode.TEAM:
		_set_human(h)


## Outcome of a slide or standing tackle: win the ball, miss, or foul.
func _resolve_action(p: Footballer) -> void:
	var sliding := p.action == Footballer.ACT_SLIDE
	var reach := (1.15 if sliding else 0.95) * Config.M
	var h := ball.holder
	if h != null and h.team != p.team:
		var d_ball := p.pos.distance_to(ball.pos)
		var d_man := p.pos.distance_to(h.pos)
		var from_behind := p.action_dir.dot(h.facing) > 0.55
		if d_ball < reach:
			p.action_resolved = true
			var foul_chance := 0.45 if from_behind else (0.08 if sliding else 0.04)
			if randf() < foul_chance:
				_foul(p, h)
				return
			var win := 0.9
			if not sliding:
				var side := (p.pos - h.pos).normalized().dot(h.facing)
				win = 0.7 if side > 0.3 else (0.5 if side > -0.3 else 0.3)
			if randf() < win:
				h.stun = 0.5
				if sliding:
					# The slide pokes the ball away; it is loose until someone collects it.
					ball.kick(p.action_dir * 7.0 * Config.M + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * Config.M, 0.0, p)
				else:
					ball.holder = p
					p.end_action()
				fx("grass", [Config.to_3d(ball.pos), 14])
				sfx("tackle", 0.0, 0.1)
				say("slide" if sliding else "tackle", 0.6 if p.team == 0 else 0.25)
				if h == human:
					vibrate(60)
				if p == human:
					coach.on_tackle_won(sliding)
			elif not sliding:
				p.end_action()
		elif sliding and d_man < 0.8 * Config.M:
			p.action_resolved = true
			_foul(p, h)
	elif h == null and sliding and ball.height < 0.6 * Config.M and p.pos.distance_to(ball.pos) < reach:
		p.action_resolved = true
		ball.kick(p.action_dir * 8.0 * Config.M, 0.0, p)
		fx("grass", [Config.to_3d(ball.pos), 10])


func _foul(fouler: Footballer, victim: Footballer) -> void:
	fouler.fouls += 1
	stats["fouls"][fouler.team] += 1
	victim.stun = 0.9
	if fouler == human:
		coach.on_foul()
	if victim == human or fouler == human:
		vibrate(80)
	if fouler.fouls == 2:
		hud.popup("YELLOW CARD #%d" % fouler.number, Config.to_3d(fouler.pos) + Vector3(0, 2.5, 0), Color(1, 0.9, 0.2))
	var penalty := _in_box(victim.pos, fouler.team)
	sfx("tackle", 0.0, 0.1)
	sfx("whistle_foul", -2.0)
	if penalty:
		crowd(0.9)
		say("penalty")
	else:
		say("foul" if randf() < 0.5 else "freekick")
	_start_set_piece(victim.team, victim.pos, penalty)


## True if the point is inside the penalty area defended by `team`.
func _in_box(point: Vector2, team: int) -> bool:
	var goal_x := -Config.attack_dir(team) * Config.HALF_L
	return absf(point.x - goal_x) < Config.BOX_DEPTH and absf(point.y) < Config.BOX_WIDTH * 0.5


## Free kick (opponents pushed back 9.15 m) or penalty (everyone out of the box).
func _start_set_piece(team: int, at: Vector2, penalty: bool) -> void:
	state = State.SET_PIECE
	_state_timer = 1.8
	vision.deactivate()
	end_cinematic()
	var dir := Config.attack_dir(team)
	var goal_x := dir * Config.HALF_L
	if penalty:
		at = Vector2(goal_x - dir * Config.PENALTY_SPOT, 0)
	at.x = clampf(at.x, -Config.HALF_L + Config.M, Config.HALF_L - Config.M)
	at.y = clampf(at.y, -Config.HALF_W + Config.M, Config.HALF_W - Config.M)
	for t in 2:
		for q: Footballer in teams[t]:
			q.end_action()
			q.velocity = Vector2.ZERO
			q.desired_velocity = Vector2.ZERO
	var taker := player_by_number(team, STRIKER) if penalty else nearest_to(team, at, true)
	for t in 2:
		for q: Footballer in teams[t]:
			if q == taker:
				continue
			if penalty:
				if q.role == Footballer.GK and q.team != team:
					q.pos = Vector2(goal_x - dir * 0.3 * Config.M, 0)
				elif _in_box(q.pos, 1 - team) or q.pos.distance_to(at) < FREE_KICK_DISTANCE:
					q.pos.x = goal_x - dir * (Config.BOX_DEPTH + randf_range(1.0, 4.0) * Config.M)
			elif q.team != team and q.pos.distance_to(at) < FREE_KICK_DISTANCE:
				q.pos = at + (q.pos - at).normalized() * FREE_KICK_DISTANCE
	ball.place(at)
	taker.pos = at - Vector2(dir, 0) * (Config.PLAYER_RADIUS + Config.BALL_RADIUS)
	taker.facing = Vector2(dir, 0)
	ball.holder = taker
	_last_holder = taker
	_possession_time = 0.0
	taker.decision_timer = 0.6
	if team == human.team and mode == Mode.TEAM:
		_set_human(taker)
	banner("PENALTY!" if penalty else "FOUL!", Color(1, 0.85, 0.2), 1.4, 0.8)


# --- Network co-op ----------------------------------------------------------

const SNAP_HEADER := 16
const ORDER_TIME := 5.0
const MENTALITY_CALLS := ["COACH: DROP BACK!", "COACH: BALANCE!", "COACH: PRESS HIGH!"]


## Host: the coach sent a player to a spot. AI players obey; friends see the arrow.
func give_order(number: int, point: Vector2) -> void:
	var p := player_by_number(0, number)
	point.x = clampf(point.x, -Config.HALF_L + Config.M, Config.HALF_L - Config.M)
	point.y = clampf(point.y, -Config.HALF_W + Config.M, Config.HALF_W - Config.M)
	p.order_point = point
	p.order_time = ORDER_TIME
	fx("order", [number, point])


func set_coach_mentality(level: int) -> void:
	team_mentality[0] = clampi(level, 0, 2)
	banner(MENTALITY_CALLS[team_mentality[0]], Color(0.45, 1.0, 0.55), 1.2, 0.6)


## Coach device: tap a teammate to select, then tap the pitch to send them there.
func coach_tap(screen_pos: Vector2) -> void:
	var best_d := 60.0
	var picked: Footballer = null
	for p: Footballer in teams[0]:
		var d := camera.unproject_position(Config.to_3d(p.pos)).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			picked = p
	if picked != null:
		coach_selected = picked
		return
	if coach_selected != null:
		var point := screen_to_pitch(screen_pos)
		if point != Vector2.INF:
			net.coach_order.rpc_id(1, coach_selected.number, point)
		coach_selected = null
const SNAP_PER_PLAYER := 10


## Shows a banner here and, on a network host, on every client.
func banner(text: String, color: Color, duration: float, text_scale: float) -> void:
	fx("banner", [text, color, duration, text_scale])


## Sound effect for everyone in the match.
func sfx(name: String, volume_db := 0.0, pitch_jitter := 0.0) -> void:
	fx("sfx", [name, volume_db, pitch_jitter])


## Commentator line; the dice are rolled here so every device hears the same.
func say(group: String, chance := 1.0) -> void:
	if randf() < chance:
		fx("say", [group])


func crowd(amount: float) -> void:
	fx("crowd", [amount])


## Ball hit the goal line outside the goal mouth.
func _on_goal_line() -> void:
	if _shot_live and state == State.PLAYING:
		_shot_live = false
		sfx("ooh", -3.0)
		crowd(0.7)
		say("miss")


## Visual effect / camera event, mirrored to clients when hosting.
func fx(kind: String, args: Array) -> void:
	apply_event(kind, args)
	if net_active and not is_client:
		net.event.rpc(kind, args)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"banner":
			hud.show_banner(args[0], args[1], args[2], args[3])
		"kick":
			FX.kick(self, args[0], args[1], args[2])
			# args[2]: 0.6 pass .. 2.0 full-power shot.
			if args[2] >= 1.0:
				audio.play("kick_power", -6.0 + 4.0 * (args[2] - 1.0), 0.06)
			else:
				audio.play("kick", -4.0, 0.1)
		"sfx":
			audio.play(args[0], args[1], args[2])
		"say":
			audio.say(args[0])
		"crowd":
			audio.cheer(args[0])
		"grass":
			FX.grass(self, args[0], args[1])
		"confetti":
			FX.confetti(self, args[0], args[1])
		"shake":
			_shake = args[0]
		"order":
			orders[args[0]] = {"point": args[1], "time": ORDER_TIME}


## Host: hand one attacker to a connected friend (slot 1-3).
func add_remote(peer_id: int, slot: int) -> void:
	var p := player_by_number(0, NetCoop.SLOTS[slot])
	remote[peer_id] = {"player": p, "input": PlayerInput.new()}
	p.is_human = true
	p.set_slot(slot)


func remove_remote(peer_id: int) -> void:
	if remote.has(peer_id):
		var p: Footballer = remote[peer_id]["player"]
		remote.erase(peer_id)
		p.is_human = p == human and not dedicated
		p.set_slot(0)


## Client: mirror the host's match, controlling the player in `slot`.
func start_client(slot: int) -> void:
	is_client = true
	net_active = true
	mode = Mode.COOP
	ball.remote = true
	apply_settings()
	vision.energy = 1.0
	coach.reset()
	audio.stop_voice()
	_pred_history.clear()
	_predicting = false
	coach_view = slot == NetCoop.COACH_SLOT
	if coach_view:
		_set_human(player_by_number(0, STRIKER))
		vision.coach_view = true
		vision.active = true
	else:
		_set_human(player_by_number(0, NetCoop.SLOTS[slot]))
		human.set_slot(slot)
	set_slot_tags(true)
	state = State.KICKOFF
	menus.show_page("")


## Client: the host ended the match; wait in the lobby.
func end_client_match() -> void:
	_enter_menu()
	menus.show_page("lobby")


func set_slot_tags(on: bool) -> void:
	for t in 2:
		for p: Footballer in teams[t]:
			p.slot_tags_visible = on


func end_network() -> void:
	for peer: int in remote.keys():
		remove_remote(peer)
	is_client = false
	net_active = false
	coach_view = false
	coach_selected = null
	orders.clear()
	vision.coach_view = false
	vision.deactivate()
	ball.remote = false
	set_slot_tags(false)
	_pred_history.clear()
	_predicting = false
	for t in 2:
		for p: Footballer in teams[t]:
			p.set_slot(0)
			p.is_human = p == human
			p.visual_offset = Vector2.ZERO


## Host -> clients, ~30 times a second.
func build_snapshot() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(SNAP_HEADER + 22 * SNAP_PER_PLAYER)
	var all: Array = teams[0] + teams[1]
	var acks := {}
	for peer: int in remote:
		acks[remote[peer]["player"]] = remote[peer]["input"].acked
	data[0] = state
	data[1] = time_left
	data[2] = score[0]
	data[3] = score[1]
	data[4] = ball.pos.x
	data[5] = ball.pos.y
	data[6] = ball.height
	data[7] = all.find(ball.holder) if ball.holder != null else -1
	data[8] = all.find(_celebrant) if _celebrant != null else -1
	data[9] = Formations.NAMES.find(team_formation[0])
	data[10] = Formations.NAMES.find(team_formation[1])
	data[11] = mode
	# Ball flight and target, so a client can predict its player's help steering.
	data[12] = ball.velocity.x
	data[13] = ball.velocity.y
	data[14] = ball.vz
	data[15] = all.find(ball.intended_receiver) if ball.intended_receiver != null else -1
	for i in all.size():
		var p: Footballer = all[i]
		var o := SNAP_HEADER + i * SNAP_PER_PLAYER
		data[o] = p.pos.x
		data[o + 1] = p.pos.y
		data[o + 2] = p.velocity.x
		data[o + 3] = p.velocity.y
		data[o + 4] = p.facing.angle()
		data[o + 5] = p.action
		data[o + 6] = 1.0 if p.stun > 0.0 else 0.0
		data[o + 7] = p.kick_count
		data[o + 8] = p.slot if p.is_human else -1
		data[o + 9] = acks.get(p, 0)
	return data


func apply_snapshot(data: PackedFloat32Array) -> void:
	if not is_client or data.size() < SNAP_HEADER + 22 * SNAP_PER_PLAYER:
		return
	var all: Array = teams[0] + teams[1]
	var new_state := int(data[0]) as State
	time_left = data[1]
	score = [int(data[2]), int(data[3])]
	ball.net_pos = Vector2(data[4], data[5])
	ball.height = data[6]
	ball.holder = all[int(data[7])] if data[7] >= 0.0 else null
	ball.velocity = Vector2(data[12], data[13])
	ball.vz = data[14]
	ball.intended_receiver = all[int(data[15])] if data[15] >= 0.0 else null
	for t in 2:
		var f: String = Formations.NAMES[int(data[9 + t])]
		if team_formation[t] != f:
			apply_formation(t, f)
	for i in all.size():
		var p: Footballer = all[i]
		var o := SNAP_HEADER + i * SNAP_PER_PLAYER
		p.net_pos = Vector2(data[o], data[o + 1])
		p.action = int(data[o + 5])
		if p == human and _predicting:
			_reconcile(p.net_pos, int(data[o + 9]))
		else:
			p.velocity = Vector2(data[o + 2], data[o + 3])
			p.facing = Vector2.from_angle(data[o + 4])
		p.stun = 0.1 if data[o + 6] > 0.5 else 0.0
		if int(data[o + 7]) != p.kick_count:
			p.kick_count = int(data[o + 7])
			p.model.play_kick()
		var slot := int(data[o + 8])
		p.is_human = slot >= 0
		p.set_slot(maxi(slot, 0))
	var celebrant: Footballer = all[int(data[8])] if data[8] >= 0.0 else null
	if celebrant != _celebrant:
		if _celebrant != null:
			_celebrant.model.set_celebrating(false)
		_celebrant = celebrant
		if _celebrant != null:
			_celebrant.model.set_celebrating(true)
	if new_state != state:
		if new_state == State.FULLTIME:
			vision.deactivate()
		state = new_state
	_check_possession_change()


## Client: glide towards the latest snapshot between packets.
func _smooth_remote_state(delta: float) -> void:
	var k := minf(1.0, 18.0 * delta)
	for t in 2:
		for p: Footballer in teams[t]:
			if p != human or not _predicting:
				p.pos = p.pos.lerp(p.net_pos, k)
	if ball.holder == null:
		ball.pos = ball.pos.lerp(ball.net_pos, k)
	else:
		# Keep the ball at the dribbler's feet (instant for your own predicted player).
		ball.pos = ball.holder.pos + ball.holder.facing * (Config.PLAYER_RADIUS + Config.BALL_RADIUS + 2.0)


## Client: move your own player straight away instead of waiting a round trip
## for the host. Each input is numbered; snapshots say which one the host has
## applied, and `_reconcile` fixes any difference.
func _predict_local(delta: float) -> void:
	var can_predict := state == State.PLAYING and not coach_view and human.action == Footballer.ACT_NONE \
			and human.stun <= 0.0
	if state == State.PLAYING and not coach_view:
		_input_seq += 1
		net.send_input(local_input, _input_seq)
	if not can_predict:
		_predicting = false
		_pred_history.clear()
		return
	if not _predicting:
		human.pos = human.net_pos
		_predicting = true
	_move_controlled(human, local_input.vector)
	human.step(delta)
	# Bump off other players like the host does (they don't move for us here).
	var min_d := Config.PLAYER_RADIUS * 2.0
	for t in 2:
		for q: Footballer in teams[t]:
			var d := human.pos - q.pos
			var dist := d.length()
			if q != human and dist < min_d and dist > 0.01:
				human.pos += d / dist * (min_d - dist) * 0.5
	_pred_history.append([_input_seq, human.pos])
	if _pred_history.size() > 120:
		_pred_history.pop_front()


func _reconcile(server_pos: Vector2, acked: int) -> void:
	while not _pred_history.is_empty() and _pred_history[0][0] < acked:
		_pred_history.pop_front()
	if _pred_history.is_empty() or _pred_history[0][0] != acked:
		return
	var error: Vector2 = server_pos - _pred_history[0][1]
	_pred_history.pop_front()
	if error.length() < 1.0:
		return
	max_correction = maxf(max_correction, error.length())
	if error.length() > 5.0 * Config.M:
		# Way off (e.g. knocked over): jump there.
		human.pos += error
		human.visual_offset = Vector2.ZERO
		_pred_history.clear()
		return
	# Shift the whole predicted path, and let the model glide over.
	human.pos += error
	human.visual_offset -= error
	for entry: Array in _pred_history:
		entry[1] += error


## Client: the charge ring is drawn locally from the player's own button holds.
func _track_client_charges() -> void:
	for a: String in ["pass", "shoot"]:
		if local_input.just_pressed[a] and ball.holder == human:
			local_input.press_start[a] = _clock
		if local_input.just_released[a] or ball.holder != human:
			local_input.press_start[a] = -1.0


func player_by_number(team: int, number: int) -> Footballer:
	for p: Footballer in teams[team]:
		if p.number == number:
			return p
	return teams[team][0]


static func formation_to_world(team: int, f: Vector2) -> Vector2:
	return Vector2(f.x * Config.HALF_L * Config.attack_dir(team), f.y * Config.HALF_W)
