class_name Config
extends RefCounted
## Shared tuning values. Gameplay runs on a 2D plane in logic units with the
## pitch centred on (0, 0); WORLD_SCALE converts to metres in the 3D scene,
## where logic y maps to world z.

## Logic units per metre (the inverse of WORLD_SCALE). Dimensions below are
## real 11-a-side values written in metres.
const M := 25.0

const PITCH_LENGTH := 105.0 * M
const PITCH_WIDTH := 68.0 * M
const HALF_L := PITCH_LENGTH / 2.0
const HALF_W := PITCH_WIDTH / 2.0
const GOAL_WIDTH := 7.32 * M
const GOAL_HEIGHT := 2.44 * M
const GOAL_DEPTH := 2.0 * M
const BOX_DEPTH := 16.5 * M
const BOX_WIDTH := 40.32 * M
const SMALL_BOX_DEPTH := 5.5 * M
const SMALL_BOX_WIDTH := 18.32 * M
const CENTER_CIRCLE := 9.15 * M
const PENALTY_SPOT := 11.0 * M
const PENALTY_ARC := 9.15 * M

## Collision radius around a player's feet, and the real ball radius.
const PLAYER_RADIUS := 0.45 * M
const BALL_RADIUS := 0.11 * M
const PLAYER_SPEED := 8.0 * M
const PLAYER_ACCEL := 55.0 * M
const DRIBBLE_SPEED_MULT := 0.88

const MATCH_SECONDS := 180.0

const TEAM_COLORS := [Color(0.14, 0.39, 0.92), Color(0.90, 0.28, 0.30)]
const SHORTS_COLORS := [Color(0.95, 0.96, 1.0), Color(0.12, 0.12, 0.16)]
const SOCK_COLORS := [Color(0.14, 0.39, 0.92), Color(0.95, 0.96, 1.0)]
const ACCENT_COLORS := [Color(0.98, 0.98, 1.0), Color(0.98, 0.82, 0.2)]
const KEEPER_COLORS := [Color(0.98, 0.78, 0.15), Color(0.30, 0.85, 0.45)]
const TEAM_NAMES := ["AOBA", "KAZE"]

const INK := Color(0.05, 0.05, 0.10)


## +1 when the team attacks the right-hand goal, -1 for the left-hand goal.
static func attack_dir(team: int) -> float:
	return 1.0 if team == 0 else -1.0


const WORLD_SCALE := 0.04


static func to_3d(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x * WORLD_SCALE, height * WORLD_SCALE, p.y * WORLD_SCALE)
