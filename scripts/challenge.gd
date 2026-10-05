class_name Challenge
extends RefCounted
## One Field Vision puzzle: a frozen match situation plus the scoring rules.
## Generated from a seed with its own RNG, so a daily seed gives every player
## the same puzzle. Scoring only uses the stored positions, never the scene.

enum Kind { PASS, SPACE, CUT }

const PROMPTS := {
	Kind.PASS: "CHOOSE THE BEST PASS",
	Kind.SPACE: "FIND THE SPACE",
	Kind.CUT: "CUT THE PASSING LANE",
}
const HINTS := {
	Kind.PASS: "Tap the teammate you would pass to",
	Kind.SPACE: "Tap where your striker should run",
	Kind.CUT: "Tap where your defender should stand",
}
const SHORT_NAMES := {Kind.PASS: "PASS", Kind.SPACE: "SPACE", Kind.CUT: "CUT"}
## How far the player may move in SPACE / CUT puzzles.
const MOVE_RADIUS := 12.0 * Config.M
const GRID_STEP := 2.0 * Config.M
const M := Config.M

var kind := Kind.PASS
var formations := ["4-3-3", "4-3-3"]
## positions[team][shirt number] = logic-plane position.
var positions := [{}, {}]
var carrier_team := 0
var carrier_number := 6
## The player the puzzle is about (the passer in PASS puzzles).
var me_number := 9
var me_team := 0


static func make(puzzle_kind: Kind, seed_value: int) -> Challenge:
	var c := Challenge.new()
	c.kind = puzzle_kind
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	c._generate(rng)
	return c


static func daily_seed(date: String, index: int) -> int:
	return hash("ao-soccer-daily-%s-%d" % [date, index])


func carrier_pos() -> Vector2:
	return positions[carrier_team][carrier_number]


func me_pos() -> Vector2:
	return positions[me_team][me_number]


# --- Generation -------------------------------------------------------------

func _generate(rng: RandomNumberGenerator) -> void:
	for t in 2:
		formations[t] = Formations.NAMES[rng.randi_range(0, Formations.NAMES.size() - 1)]
	var attack := 1 if kind == Kind.CUT else 0
	var defend := 1 - attack
	# Ball zone in the attacking team's frame: from their own half to the edge of the box.
	var bx := rng.randf_range(-0.1, 0.7)
	var by := rng.randf_range(-0.6, 0.6)

	for t in 2:
		var attacking := t == attack
		var dir := Config.attack_dir(t)
		var ball_x_own := bx if attacking else -bx
		for slot: Array in Formations.DATA[formations[t]]:
			var role: int = slot[0]
			var f: Vector2 = slot[1]
			var x := f.x
			var y := f.y
			if role != Footballer.GK:
				x = f.x + 0.5 * (ball_x_own + 0.2) + (0.25 if attacking else -0.08)
				match role:
					Footballer.DEF:
						x = clampf(x, -0.85, 0.3)
					Footballer.MID:
						x = clampf(x, -0.7, 0.65)
					_:
						x = clampf(x, -0.45, 0.85)
				y = f.y + by * 0.35
			var p := Vector2(x * Config.HALF_L * dir, clampf(y, -0.9, 0.9) * Config.HALF_W)
			if role != Footballer.GK:
				p += Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0)) * M
			positions[t][slot[2]] = _clamp_to_pitch(p)

	var ball_world := Vector2(bx * Config.HALF_L * Config.attack_dir(attack), by * Config.HALF_W)
	carrier_team = attack
	carrier_number = _nearest(attack, ball_world, [1])
	positions[attack][carrier_number] = _clamp_to_pitch(ball_world)
	# One defender closes the carrier down from the goal side.
	var own_goal := Vector2(-Config.attack_dir(defend) * Config.HALF_L, 0)
	var presser := _nearest(defend, ball_world, [1])
	var to_goal := (own_goal - ball_world).normalized()
	positions[defend][presser] = _clamp_to_pitch(ball_world + to_goal * rng.randf_range(2.5, 4.0) * M)

	match kind:
		Kind.PASS:
			me_team = attack
			me_number = carrier_number
		Kind.SPACE:
			me_team = attack
			me_number = 9 if carrier_number != 9 else 10
		Kind.CUT:
			me_team = defend
			me_number = _nearest(defend, ball_world, [1, presser])
			# Start close enough to make a difference, but not on top of play.
			var me := positions[defend][me_number] as Vector2
			if me.distance_to(ball_world) > 18.0 * M:
				positions[defend][me_number] = _clamp_to_pitch(ball_world + (me - ball_world).normalized() * 14.0 * M)


func _nearest(team: int, point: Vector2, exclude: Array) -> int:
	var best := -1
	var best_d := INF
	for n: int in positions[team]:
		if n in exclude:
			continue
		var d := (positions[team][n] as Vector2).distance_to(point)
		if d < best_d:
			best_d = d
			best = n
	return best


static func _clamp_to_pitch(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -Config.HALF_L + M, Config.HALF_L - M), clampf(p.y, -Config.HALF_W + M, Config.HALF_W - M))


# --- Scoring ----------------------------------------------------------------

## Candidate answers with their raw values: teammates for PASS, a grid of
## reachable points for SPACE / CUT. Each entry: [answer, value] where answer
## is a shirt number (PASS) or a Vector2.
func candidates() -> Array:
	var out: Array = []
	if kind == Kind.PASS:
		for n: int in positions[me_team]:
			if n != me_number:
				out.append([n, pass_value(n)])
		return out
	var c := me_pos()
	var steps := int(MOVE_RADIUS / GRID_STEP)
	for ix in range(-steps, steps + 1):
		for iy in range(-steps, steps + 1):
			var p := c + Vector2(ix, iy) * GRID_STEP
			if p.distance_to(c) <= MOVE_RADIUS and p == _clamp_to_pitch(p):
				out.append([p, point_value(p)])
	return out


func value_of(answer: Variant) -> float:
	return pass_value(answer) if kind == Kind.PASS else point_value(answer)


## 0-100: where the answer falls between the worst and best candidate.
func score(answer: Variant, cands: Array) -> int:
	var lo := INF
	var hi := -INF
	for entry: Array in cands:
		lo = minf(lo, entry[1])
		hi = maxf(hi, entry[1])
	if hi - lo < 0.0001:
		return 100
	return int(round(clampf((value_of(answer) - lo) / (hi - lo), 0.0, 1.0) * 100.0))


## Keep a tapped point within the reachable circle.
func clamp_answer(p: Vector2) -> Vector2:
	var c := me_pos()
	if p.distance_to(c) > MOVE_RADIUS:
		p = c + (p - c).normalized() * MOVE_RADIUS
	return _clamp_to_pitch(p)


func pass_value(to_number: int) -> float:
	var from := carrier_pos()
	var to: Vector2 = positions[carrier_team][to_number]
	var dir := Config.attack_dir(carrier_team)
	var opponents: Array = positions[1 - carrier_team].values()
	var s := clampf(lane_clearance(from, to, opponents) / (3.2 * M), 0.0, 1.5)
	s += (to.x - from.x) * dir / (16.0 * M)
	s -= absf(from.distance_to(to) - 12.8 * M) / (28.0 * M)
	s += clampf(_min_distance(to, opponents) / (6.0 * M), 0.0, 1.0)
	return s


func point_value(p: Vector2) -> float:
	return _space_value(p) if kind == Kind.SPACE else _cut_value(p)


## Attacking off the ball: room from opponents, an open lane from the carrier,
## progress towards goal, not crowding teammates, and not offside.
func _space_value(p: Vector2) -> float:
	var from := carrier_pos()
	var dir := Config.attack_dir(me_team)
	var opponents: Array = positions[1 - me_team].values()
	var mates: Array = []
	for n: int in positions[me_team]:
		if n != me_number and n != carrier_number:
			mates.append(positions[me_team][n])
	var v := 0.35 * minf(_min_distance(p, opponents), 12.0 * M) / (12.0 * M)
	v += 0.35 * minf(lane_clearance(from, p, opponents), 6.0 * M) / (6.0 * M)
	v += 0.2 * clampf((p.x - from.x) * dir, 0.0, 25.0 * M) / (25.0 * M)
	v += 0.1 * minf(_min_distance(p, mates), 8.0 * M) / (8.0 * M)
	if p.x * dir > _last_defender_x(1 - me_team) * dir and p.x * dir > from.x * dir:
		v -= 0.3  # Offside.
	return v


## Defending: how much standing here reduces the most dangerous pass, plus a
## small bonus for staying between the ball and our goal.
func _cut_value(p: Vector2) -> float:
	var from := carrier_pos()
	var attack_dir := Config.attack_dir(carrier_team)
	var defenders: Array = []
	for n: int in positions[me_team]:
		defenders.append(p if n == me_number else positions[me_team][n])
	var danger := 0.0
	for n: int in positions[carrier_team]:
		if n == carrier_number or n == 1:
			continue
		var r: Vector2 = positions[carrier_team][n]
		var threat := 0.6 * minf(lane_clearance(from, r, defenders), 6.0 * M) / (6.0 * M)
		threat += 0.4 * clampf((r.x - from.x) * attack_dir, 0.0, 25.0 * M) / (25.0 * M)
		danger = maxf(danger, threat)
	var v := -danger
	var own_goal := Vector2(-Config.attack_dir(me_team) * Config.HALF_L, 0)
	if (p - from).dot(own_goal - from) > 0.0 and p.distance_to(from) < 15.0 * M:
		v += 0.15
	return v


func _last_defender_x(team: int) -> float:
	var dir := Config.attack_dir(team)
	var deepest := INF
	for n: int in positions[team]:
		if n == 1:
			continue
		deepest = minf(deepest, (positions[team][n] as Vector2).x * dir)
	return deepest * dir


static func lane_clearance(a: Vector2, b: Vector2, blockers: Array) -> float:
	var clearance := INF
	for o: Vector2 in blockers:
		clearance = minf(clearance, Geometry2D.get_closest_point_to_segment(o, a, b).distance_to(o))
	return clearance


static func _min_distance(p: Vector2, points: Array) -> float:
	var d := INF
	for o: Vector2 in points:
		d = minf(d, o.distance_to(p))
	return d
