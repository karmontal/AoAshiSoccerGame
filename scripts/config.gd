class_name Config
extends RefCounted
## Shared tuning values. World units are pixels at zoom 1; the pitch is centred on (0, 0).

const PITCH_LENGTH := 2000.0
const PITCH_WIDTH := 1240.0
const HALF_L := PITCH_LENGTH / 2.0
const HALF_W := PITCH_WIDTH / 2.0
const GOAL_WIDTH := 230.0
const GOAL_DEPTH := 55.0
const BOX_DEPTH := 330.0
const BOX_WIDTH := 700.0
const SMALL_BOX_DEPTH := 110.0
const SMALL_BOX_WIDTH := 380.0
const CENTER_CIRCLE := 170.0

const PLAYER_RADIUS := 18.0
const BALL_RADIUS := 9.0
const PLAYER_SPEED := 240.0
const PLAYER_ACCEL := 1500.0
const DRIBBLE_SPEED_MULT := 0.88

const MATCH_SECONDS := 180.0

const TEAM_COLORS := [Color(0.14, 0.39, 0.92), Color(0.90, 0.28, 0.30)]
const KEEPER_COLORS := [Color(0.98, 0.78, 0.15), Color(0.30, 0.85, 0.45)]
const TEAM_NAMES := ["AOBA", "KAZE"]

const INK := Color(0.05, 0.05, 0.10)


## +1 when the team attacks the right-hand goal, -1 for the left-hand goal.
static func attack_dir(team: int) -> float:
	return 1.0 if team == 0 else -1.0
