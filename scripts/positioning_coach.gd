class_name PositioningCoach
extends RefCounted
## "Captain's Eye": rates the human player's positioning off the ball, the
## core idea of the game. Every half second it scores the current position;
## good reads trigger pop-ups, points and extra Field Vision energy.
##
## Attacking (a teammate has the ball): open passing lane to the carrier, free
## space, getting ahead of the ball, not crowding teammates.
## Defending (an opponent has the ball): cutting a passing lane, staying
## goal-side of the carrier, marking a receiver tightly.

const INTERVAL := 0.5
const EVENT_COOLDOWN := 3.0
const SMOOTHING := 0.35
const VISION_PER_POINT := 0.004

## Event id -> [label, points].
const EVENTS := {
	"open_lane": ["OPEN LANE", 10],
	"free_space": ["FREE SPACE", 5],
	"run_behind": ["RUN IN BEHIND", 15],
	"lane_cut": ["LANE CUT", 15],
	"goal_side": ["GOAL-SIDE", 5],
	"tight_mark": ["TIGHT MARK", 5],
	"intercept": ["INTERCEPT!", 25],
	"received": ["GOOD RUN", 10],
	"slide_won": ["CLEAN SLIDE!", 15],
	"tackle_won": ["TACKLE WON", 10],
	"foul": ["FOUL", -10],
}

var game: SoccerMatch
## Smoothed 0..1 rating of the current positioning.
var rating := 0.5
var points := 0
var counts := {}
var _rating_sum := 0.0
var _rating_samples := 0
var _timer := 0.0
var _cooldowns := {}


func _init(match_ref: SoccerMatch) -> void:
	game = match_ref
	reset()


func reset() -> void:
	rating = 0.5
	points = 0
	counts.clear()
	_cooldowns.clear()
	_rating_sum = 0.0
	_rating_samples = 0
	_timer = 0.0
	for id: String in EVENTS:
		counts[id] = 0


## Overall grade for the match so far, from the average rating.
func grade() -> String:
	return grade_for(average())


## Grade for the live rating (the on-screen meter).
func live_grade() -> String:
	return grade_for(rating)


static func grade_for(value: float) -> String:
	if value >= 0.75:
		return "S"
	if value >= 0.6:
		return "A"
	if value >= 0.45:
		return "B"
	if value >= 0.3:
		return "C"
	return "D"


func average() -> float:
	return _rating_sum / _rating_samples if _rating_samples > 0 else rating


func update(delta: float) -> void:
	for id: String in _cooldowns:
		_cooldowns[id] -= delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	var me := game.human
	var holder := game.ball.holder
	if holder == null or holder == me:
		return
	var r := _rate_attack(me, holder) if holder.team == me.team else _rate_defence(me, holder)
	rating = lerpf(rating, r, SMOOTHING)
	_rating_sum += r
	_rating_samples += 1


func _rate_attack(me: Footballer, holder: Footballer) -> float:
	var dir := Config.attack_dir(me.team)
	var opp := 1 - me.team
	var dist := me.pos.distance_to(holder.pos)
	var lane := game.lane_clearance(holder.pos, me.pos, opp)
	var lane_open := lane > 60.0 and dist > 120.0 and dist < 750.0
	var marker := game.nearest_to(opp, me.pos, false)
	var space := marker.pos.distance_to(me.pos) if marker != null else 999.0
	var ahead := (me.pos.x - holder.pos.x) * dir > 60.0
	var mate := _nearest_teammate(me)
	var spaced := mate == null or mate.pos.distance_to(me.pos) > 160.0

	var r := 0.0
	r += 0.4 if lane_open else clampf(lane / 150.0, 0.0, 0.2)
	r += 0.25 * clampf((space - 60.0) / 120.0, 0.0, 1.0)
	r += 0.2 if ahead else 0.0
	r += 0.15 if spaced else 0.0

	if lane_open:
		if ahead and _beyond_last_defender(me):
			_event("run_behind", me)
		else:
			_event("open_lane", me)
	if space > 170.0 and lane > 40.0:
		_event("free_space", me)
	return r


func _rate_defence(me: Footballer, holder: Footballer) -> float:
	var dir := Config.attack_dir(me.team)
	var cutting := false
	for receiver: Footballer in game.teams[holder.team]:
		if receiver == holder or receiver.role == Footballer.GK:
			continue
		var a := holder.pos
		var b := receiver.pos
		var ab := b - a
		var t := clampf((me.pos - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		if t > 0.15 and t < 0.85 and (a + ab * t).distance_to(me.pos) < 40.0:
			cutting = true
			break
	# Goal-side: between the carrier and my own goal, close enough to matter.
	var goal_side := (holder.pos.x - me.pos.x) * dir > 0.0 and me.pos.distance_to(holder.pos) < 320.0
	var marking := false
	for o: Footballer in game.teams[holder.team]:
		if o != holder and o.role != Footballer.GK and o.pos.distance_to(me.pos) < 90.0:
			marking = true
			break

	var r := 0.0
	r += 0.45 if cutting else 0.0
	r += 0.35 if goal_side else 0.0
	r += 0.2 if marking else 0.0
	if cutting:
		_event("lane_cut", me)
	elif goal_side:
		_event("goal_side", me)
	if marking and not cutting:
		_event("tight_mark", me)
	return r


## Called by the match when the human wins the ball from an opponent's pass.
func on_interception() -> void:
	_event("intercept", game.human, true)


func on_tackle_won(sliding: bool) -> void:
	_event("slide_won" if sliding else "tackle_won", game.human, true)


func on_foul() -> void:
	_event("foul", game.human, true)


## Called by the match when the human receives a pass from a teammate.
func on_received_pass() -> void:
	_event("received", game.human)


func _event(id: String, me: Footballer, force := false) -> void:
	if not force and _cooldowns.get(id, 0.0) > 0.0:
		return
	_cooldowns[id] = EVENT_COOLDOWN
	var label: String = EVENTS[id][0]
	var pts: int = EVENTS[id][1]
	points += pts
	counts[id] += 1
	game.vision.energy = clampf(game.vision.energy + pts * VISION_PER_POINT, 0.0, 1.0)
	var text := "%s %+d" % [label, pts]
	var color := Color(0.55, 1.0, 0.6) if pts > 0 else Color(1.0, 0.4, 0.35)
	game.hud.popup(text, Config.to_3d(me.pos, 0.0) + Vector3(0, 2.5, 0), color)


func _nearest_teammate(me: Footballer) -> Footballer:
	var best: Footballer = null
	var best_d := INF
	for p: Footballer in game.teams[me.team]:
		if p == me:
			continue
		var d := p.pos.distance_squared_to(me.pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func _beyond_last_defender(me: Footballer) -> bool:
	var dir := Config.attack_dir(me.team)
	var deepest := -INF
	for o: Footballer in game.teams[1 - me.team]:
		if o.role != Footballer.GK:
			deepest = maxf(deepest, o.pos.x * dir)
	return me.pos.x * dir > deepest - 20.0
