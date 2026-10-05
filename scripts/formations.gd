class_name Formations
extends RefCounted
## Team shapes. Each slot: role, position in the team's own frame (attacking
## +x, axes normalised to the half-pitch) and shirt number. Every formation
## uses shirt numbers 1-11, with #9 up front and #6 in midfield, so players
## keep their identity when the shape changes mid-match.

const G := Footballer.GK
const D := Footballer.DEF
const MI := Footballer.MID
const F := Footballer.FWD

const NAMES := ["4-3-3", "4-4-2", "4-2-3-1", "3-5-2", "5-3-2"]

const DATA := {
	"4-3-3": [
		[G, Vector2(-0.95, 0.0), 1],
		[D, Vector2(-0.64, 0.66), 2], [D, Vector2(-0.70, 0.22), 5], [D, Vector2(-0.70, -0.22), 4], [D, Vector2(-0.64, -0.66), 3],
		[MI, Vector2(-0.40, 0.36), 8], [MI, Vector2(-0.46, 0.0), 6], [MI, Vector2(-0.40, -0.36), 10],
		[F, Vector2(-0.14, 0.62), 7], [F, Vector2(-0.06, 0.0), 9], [F, Vector2(-0.14, -0.62), 11],
	],
	"4-4-2": [
		[G, Vector2(-0.95, 0.0), 1],
		[D, Vector2(-0.64, 0.66), 2], [D, Vector2(-0.70, 0.22), 5], [D, Vector2(-0.70, -0.22), 4], [D, Vector2(-0.64, -0.66), 3],
		[MI, Vector2(-0.36, 0.64), 7], [MI, Vector2(-0.42, 0.2), 6], [MI, Vector2(-0.42, -0.2), 8], [MI, Vector2(-0.36, -0.64), 11],
		[F, Vector2(-0.07, 0.16), 9], [F, Vector2(-0.12, -0.2), 10],
	],
	"4-2-3-1": [
		[G, Vector2(-0.95, 0.0), 1],
		[D, Vector2(-0.64, 0.66), 2], [D, Vector2(-0.70, 0.22), 5], [D, Vector2(-0.70, -0.22), 4], [D, Vector2(-0.64, -0.66), 3],
		[MI, Vector2(-0.50, 0.18), 6], [MI, Vector2(-0.50, -0.18), 8],
		[F, Vector2(-0.28, 0.6), 7], [MI, Vector2(-0.26, 0.0), 10], [F, Vector2(-0.28, -0.6), 11],
		[F, Vector2(-0.06, 0.0), 9],
	],
	"3-5-2": [
		[G, Vector2(-0.95, 0.0), 1],
		[D, Vector2(-0.70, 0.38), 5], [D, Vector2(-0.73, 0.0), 4], [D, Vector2(-0.70, -0.38), 3],
		[MI, Vector2(-0.40, 0.74), 2], [MI, Vector2(-0.38, 0.3), 8], [MI, Vector2(-0.48, 0.0), 6],
		[MI, Vector2(-0.38, -0.3), 10], [MI, Vector2(-0.40, -0.74), 11],
		[F, Vector2(-0.07, 0.16), 9], [F, Vector2(-0.10, -0.2), 7],
	],
	"5-3-2": [
		[G, Vector2(-0.95, 0.0), 1],
		[D, Vector2(-0.58, 0.76), 2], [D, Vector2(-0.70, 0.36), 5], [D, Vector2(-0.73, 0.0), 4],
		[D, Vector2(-0.70, -0.36), 3], [D, Vector2(-0.58, -0.76), 11],
		[MI, Vector2(-0.40, 0.36), 8], [MI, Vector2(-0.45, 0.0), 6], [MI, Vector2(-0.40, -0.36), 10],
		[F, Vector2(-0.07, 0.16), 9], [F, Vector2(-0.10, -0.2), 7],
	],
}

const MENTALITIES := ["DEFENSIVE", "BALANCED", "ATTACKING"]
## How far the whole block steps up (fraction of the half-pitch).
const MENTALITY_SHIFT := [-0.08, 0.0, 0.08]


static func slot_for(formation: String, number: int) -> Array:
	for slot: Array in DATA[formation]:
		if slot[2] == number:
			return slot
	return DATA[formation][0]
