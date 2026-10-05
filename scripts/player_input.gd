class_name PlayerInput
extends RefCounted
## One controller's input for a frame: joystick vector plus press/release
## edges of the action buttons. The local player samples it from the touch
## controls and keyboard; remote co-op players receive it over the network as
## cumulative press/release counters, so a lost packet never loses a tap.

const ACTIONS := ["pass", "shoot", "special", "vision"]

var vector := Vector2.ZERO
var just_pressed := {}
var just_released := {}
## Hold start (match clock) of PASS / SHOOT while charging; -1 when idle.
var press_start := {"pass": -1.0, "shoot": -1.0}
## Cumulative counters, sent by clients.
var presses := PackedInt32Array([0, 0, 0, 0])
var releases := PackedInt32Array([0, 0, 0, 0])

var _seen_presses := PackedInt32Array([0, 0, 0, 0])
var _seen_releases := PackedInt32Array([0, 0, 0, 0])


func _init() -> void:
	clear_edges()


func clear_edges() -> void:
	for a: String in ACTIONS:
		just_pressed[a] = false
		just_released[a] = false


## Local player: read this frame's edges from the input map.
func sample_local(stick: Vector2) -> void:
	vector = stick
	for i in ACTIONS.size():
		var a: String = ACTIONS[i]
		just_pressed[a] = Input.is_action_just_pressed(a)
		just_released[a] = Input.is_action_just_released(a)
		if just_pressed[a]:
			presses[i] += 1
		if just_released[a]:
			releases[i] += 1


## Host side: a client's latest state. Edges accumulate until consumed.
func receive(stick: Vector2, new_presses: PackedInt32Array, new_releases: PackedInt32Array) -> void:
	vector = stick.limit_length(1.0)
	for i in ACTIONS.size():
		var a: String = ACTIONS[i]
		if new_presses[i] > _seen_presses[i]:
			just_pressed[a] = true
			_seen_presses[i] = new_presses[i]
		if new_releases[i] > _seen_releases[i]:
			just_released[a] = true
			_seen_releases[i] = new_releases[i]


func reset_charges() -> void:
	press_start["pass"] = -1.0
	press_start["shoot"] = -1.0
