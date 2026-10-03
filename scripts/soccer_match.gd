class_name SoccerMatch
extends Node3D
## Builds the match scene in code and runs everything: kickoff/goal flow,
## the human-controlled player, team AI, passing, shooting and possession.

enum State { MENU, KICKOFF, PLAYING, GOAL, FULLTIME }
## TEAM: control switches to whoever is nearest the ball.
## SOLO: you are always #9 and play off the ball, Ao Ashi style; teammates
## carry the ball and you call for it.
enum Mode { TEAM, SOLO }

## 4-3-3 in the team's own frame (attacking +x), axes normalised to the half-pitch.
const FORMATION := [
	{"role": Footballer.GK, "pos": Vector2(-0.95, 0.0), "num": 1},
	{"role": Footballer.DEF, "pos": Vector2(-0.64, 0.66), "num": 2},
	{"role": Footballer.DEF, "pos": Vector2(-0.70, 0.22), "num": 5},
	{"role": Footballer.DEF, "pos": Vector2(-0.70, -0.22), "num": 4},
	{"role": Footballer.DEF, "pos": Vector2(-0.64, -0.66), "num": 3},
	{"role": Footballer.MID, "pos": Vector2(-0.40, 0.36), "num": 8},
	{"role": Footballer.MID, "pos": Vector2(-0.46, 0.0), "num": 6},
	{"role": Footballer.MID, "pos": Vector2(-0.40, -0.36), "num": 10},
	{"role": Footballer.FWD, "pos": Vector2(-0.14, 0.62), "num": 7},
	{"role": Footballer.FWD, "pos": Vector2(-0.06, 0.0), "num": 9},
	{"role": Footballer.FWD, "pos": Vector2(-0.14, -0.62), "num": 11},
]
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
}

const PASS_MIN := 60.0
const PASS_MAX := 55.0 * Config.M
const SHOT_SPEED := 44.0 * Config.M
## Time after receiving the ball before an opponent may tackle.
const RECEIVE_GRACE := 0.35

var teams: Array = [[], []]
var ball: Ball
var vision: FieldVision
var hud: Hud
var controls: TouchControls
var menus: Menus
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
var stats := {"shots": [0, 0], "saves": [0, 0]}

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


func _ready() -> void:
	_register_inputs()
	stadium = Stadium.new()
	add_child(stadium)
	for t in 2:
		for slot: Dictionary in FORMATION:
			var p := Footballer.new()
			p.team = t
			p.role = slot["role"]
			p.number = slot["num"]
			p.formation = slot["pos"]
			add_child(p)
			teams[t].append(p)

	ball = Ball.new()
	ball.goal_scored.connect(_on_goal)
	add_child(ball)

	camera = Camera3D.new()
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()

	var ui := CanvasLayer.new()
	add_child(ui)
	vision = FieldVision.new()
	vision.game = self
	ui.add_child(vision)
	hud = Hud.new()
	hud.game = self
	ui.add_child(hud)
	controls = TouchControls.new()
	controls.game = self
	ui.add_child(controls)
	menus = Menus.new()
	menus.game = self
	ui.add_child(menus)

	coach = PositioningCoach.new(self)
	human = player_by_number(0, STRIKER)
	_set_human(human)
	apply_settings()
	_enter_menu()


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
	if state == State.MENU or state == State.FULLTIME or get_tree().paused:
		return
	controls.release_all()
	get_tree().paused = true
	menus.show_page("pause")


func resume_game() -> void:
	get_tree().paused = false
	menus.show_page("")


func quit_to_menu() -> void:
	get_tree().paused = false
	_enter_menu()
	menus.show_page("title")


func vibrate(ms: int) -> void:
	if GameSettings.enabled("vibration") and not autopilot:
		Input.vibrate_handheld(ms)


## Starts a new match in the given mode (from the menu).
func start_match(new_mode: Mode) -> void:
	mode = new_mode
	score = [0, 0]
	time_left = GameSettings.match_seconds()
	apply_settings()
	vision.energy = 1.0
	stats = {"shots": [0, 0], "saves": [0, 0]}
	coach.reset()
	_start_kickoff(0)


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
	_set_human(player_by_number(0, STRIKER if mode == Mode.SOLO or team_with_ball == 0 else PLAYMAKER))
	hud.show_banner("KICK OFF", Color(1, 0.9, 0.3), 1.2, 0.8)


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
	FX.confetti(self, Config.to_3d(_celebrant.pos), Config.TEAM_COLORS[scoring_team])
	_shake = 18.0
	hud.show_banner("GOAL!!", Config.TEAM_COLORS[scoring_team], 2.6, 1.2)


func _end_match() -> void:
	state = State.FULLTIME
	time_left = 0.0
	ball.frozen = true
	vision.deactivate()


## Called by TouchControls for touches that didn't land on a button.
## Returns true if the tap was consumed.
func handle_screen_tap(screen_pos: Vector2) -> bool:
	if state == State.MENU:
		return false
	if state == State.FULLTIME:
		_enter_menu()
		menus.show_page("modes")
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
	pass_to(human, target)
	vision.deactivate()
	return true


# --- Per-frame update -------------------------------------------------------

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_clock += real
	if state == State.FULLTIME:
		if Input.is_action_just_pressed("pass") or Input.is_action_just_pressed("shoot"):
			_enter_menu()
			menus.show_page("modes")
	elif state == State.PLAYING and not autopilot:
		_handle_actions()
	human.hide_marker = cinematic_active() or state == State.GOAL or state == State.MENU
	_update_camera(real)


func _physics_process(delta: float) -> void:
	match state:
		State.MENU:
			for t in 2:
				for p: Footballer in teams[t]:
					p.desired_velocity = Vector2.ZERO
					p.step(delta)
			return
		State.KICKOFF:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.PLAYING
			return
		State.GOAL, State.FULLTIME:
			for t in 2:
				for p: Footballer in teams[t]:
					p.desired_velocity = Vector2.ZERO
					p.step(delta)
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
	if not autopilot:
		_update_human_movement()
	_update_ai(delta)
	for t in 2:
		for p: Footballer in teams[t]:
			p.step(delta)
	_separate_players()
	_handle_ball_contacts()
	_check_possession_change()
	coach.update(delta)


func _input_vector() -> Vector2:
	var v := controls.vector
	if v.length() < 0.05:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return v.limit_length(1.0)


func _update_human_movement() -> void:
	var v := _input_vector()
	if v.length() > 0.1:
		var mult := Config.DRIBBLE_SPEED_MULT if ball.holder == human else 1.0
		human.desired_velocity = v * Config.PLAYER_SPEED * mult
	elif ball.intended_receiver == human or (ball.holder == null and human.pos.distance_to(ball.pos) < 140.0):
		# Help the player: step towards a pass or a nearby loose ball.
		human.desired_velocity = _steer(human, ball.target_point(), 1.0)
	else:
		human.desired_velocity = Vector2.ZERO


func _handle_actions() -> void:
	if Input.is_action_just_pressed("vision"):
		vision.toggle()
	var v := _input_vector()
	if ball.holder == human:
		if Input.is_action_just_pressed("pass"):
			var aim := v if v.length() > 0.2 else human.facing
			var target := best_pass_target(human, aim)
			if target != null:
				pass_to(human, target)
				vision.deactivate()
		elif Input.is_action_just_pressed("shoot"):
			vision.deactivate()
			shoot(human, v.y)
	elif Input.is_action_just_pressed("pass"):
		if mode == Mode.SOLO:
			_call_for_ball()
		else:
			_switch_to_nearest()


## SOLO mode: ask the teammate on the ball to pass to you.
func _call_for_ball() -> void:
	var h := ball.holder
	if h == null or h.team != human.team or h == human:
		return
	_call_timer = 1.5
	h.decision_timer = minf(h.decision_timer, 0.15)
	hud.popup("CALL!", Config.to_3d(human.pos) + Vector3(0, 2.5, 0), Color(1, 0.9, 0.3))


func _set_human(p: Footballer) -> void:
	if human != null:
		human.is_human = false
	human = p
	human.is_human = true


func _switch_to_nearest() -> void:
	var nearest := nearest_to(0, ball.pos, true)
	if nearest != null and nearest != human:
		_set_human(nearest)
		_switch_cooldown = 0.8


func _auto_switch() -> void:
	if mode == Mode.SOLO or _switch_cooldown > 0.0 or (ball.holder != null and ball.holder.team == 0):
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
	if state == State.MENU:
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
		if _call_timer > 0.0 and p.team == human.team and mode == Mode.SOLO:
			var d := p.pos.distance_to(human.pos)
			if d > PASS_MIN and d < PASS_MAX and (lane_clearance(p.pos, human.pos, 1 - p.team) > 25.0 or randf() < 0.4):
				_call_timer = 0.0
				pass_to(p, human)
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
		if best != null and gain > 8.0 * Config.M and randf() < 0.35:
			pass_to(p, best)
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
		if mode == Mode.SOLO and mate == human and not autopilot:
			s += 0.6
		if align < -0.2:
			s -= 3.0
		if s > best_score:
			best_score = s
			best = mate
	return best


func pass_to(from: Footballer, to: Footballer) -> void:
	var lead := to.pos + to.velocity * 0.4
	var offset := lead - from.pos
	var d := offset.length()
	if d < 1.0:
		return
	var lift := 0.0
	var spd := clampf(d * Ball.GROUND_DAMP + 20.0 * Config.M, 22.0 * Config.M, 60.0 * Config.M)
	if lane_clearance(from.pos, lead, 1 - from.team) < 30.0 and d > 9.0 * Config.M:
		# Lane is blocked: chip it over. Airtime T = 2 * lift / g.
		lift = clampf(d * 0.3, 7.0 * Config.M, 11.0 * Config.M)
		var airtime := 2.0 * lift / Ball.GRAVITY
		spd = d / airtime * (1.0 + Ball.AIR_DAMP * airtime * 0.5) * 0.9
	from.facing = offset / d
	from.play_kick()
	ball.kick(offset / d * spd, lift, from, to)
	if from == human:
		vibrate(20)
	FX.kick(self, Config.to_3d(from.pos + from.facing * 16.0, 5.0), Color(1, 0.97, 0.8), 0.6)
	if from.team == 0 and mode == Mode.TEAM:
		_set_human(to)


func shoot(p: Footballer, aim: float) -> void:
	var dir := Config.attack_dir(p.team)
	var target := Vector2(dir * (Config.HALF_L + 30.0), clampf(aim, -1.0, 1.0) * (Config.GOAL_WIDTH * 0.5 - 18.0))
	var err := p.pos.distance_to(target) / 1000.0 * 70.0
	if p.team == 1:
		err *= GameSettings.ai_shot_error()
	target.y += randf_range(-err, err)
	var v := (target - p.pos).normalized() * SHOT_SPEED
	p.facing = v.normalized()
	p.play_kick()
	if p == human:
		vibrate(45)
	ball.kick(v, randf_range(40.0, 200.0) * minf(p.pos.distance_to(target) / 600.0, 1.0), p)
	FX.kick(self, Config.to_3d(p.pos + p.facing * 16.0, 5.0), Config.TEAM_COLORS[p.team].lightened(0.5), 1.5)
	_shake = 6.0
	stats["shots"][p.team] += 1
	hud.show_banner("SHOOT!", Config.TEAM_COLORS[p.team], 0.55, 0.55)
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
	if ball.holder == null:
		var best: Footballer = null
		var best_d := INF
		for t in 2:
			for p: Footballer in teams[t]:
				if p.stun > 0.0 or not ball.can_be_taken_by(p):
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
			ball.holder = best
			ball.intended_receiver = null
		return

	var h := ball.holder
	for p: Footballer in teams[1 - h.team]:
		if p.tackle_cooldown > 0.0 or p.stun > 0.0 or _possession_time < RECEIVE_GRACE:
			continue
		if p.pos.distance_to(ball.pos) < Config.PLAYER_RADIUS + Config.BALL_RADIUS + 6.0:
			p.tackle_cooldown = 0.9
			var chance := 0.1 if h.role == Footballer.GK else (GameSettings.ai_tackle() if p.team == 1 else 0.4)
			if randf() < chance:
				ball.holder = p
				h.stun = 0.45
				if h == human:
					vibrate(60)
				FX.grass(self, Config.to_3d(ball.pos), 10)
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
		elif mode == Mode.SOLO and ball.last_kicker != human:
			coach.on_received_pass()
	if h.team == 0 and mode == Mode.TEAM:
		_set_human(h)


func player_by_number(team: int, number: int) -> Footballer:
	for p: Footballer in teams[team]:
		if p.number == number:
			return p
	return teams[team][0]


static func formation_to_world(team: int, f: Vector2) -> Vector2:
	return Vector2(f.x * Config.HALF_L * Config.attack_dir(team), f.y * Config.HALF_W)
