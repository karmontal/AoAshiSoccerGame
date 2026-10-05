class_name Footballer
extends Node3D
## One player. Gameplay state lives on the 2D logic plane (`pos`); the 3D
## model is synced to it every frame. Movement is driven by `desired_velocity`,
## which the match sets each physics frame (touch input or AI).

const GK := 0
const DEF := 1
const MID := 2
const FWD := 3
const ARROW_HEIGHT := 2.15

## Defensive actions.
const ACT_NONE := 0
const ACT_SLIDE := 1
const ACT_TACKLE := 2
const SLIDE_TIME := 0.55
const SLIDE_SPEED := 11.0 * Config.M
const TACKLE_TIME := 0.28
const TACKLE_SPEED := 9.0 * Config.M
const GET_UP_TIME := 0.5

var team := 0
var number := 1
var role := MID
## Formation slot in the team's own frame (attacking +x), both axes in [-1, 1].
var formation := Vector2.ZERO

var pos := Vector2.ZERO
var velocity := Vector2.ZERO
var desired_velocity := Vector2.ZERO
var facing := Vector2.RIGHT
var is_human := false
## Hide the selection ring/arrow (e.g. during close-up camera shots).
var hide_marker := false
var tackle_cooldown := 0.0
var stun := 0.0
var decision_timer := 0.0
## Difficulty multiplier on movement speed.
var speed_mult := 1.0
## Cached "find space" target for attacking off-ball movement.
var space_target := Vector2.ZERO
var space_base := Vector2.ZERO
var space_timer := 0.0
## While > 0 the player commits to a tackle instead of jockeying.
var lunge := 0.0
var action := ACT_NONE
var action_time := 0.0
var action_dir := Vector2.RIGHT
## Set once a slide/tackle has had its outcome, so it is only rolled once.
var action_resolved := false
var fouls := 0
var _get_up := 0.0

var model: PlayerModel
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _yaw := 0.0


func _ready() -> void:
	model = PlayerModel.new()
	add_child(model)
	var shirt: Color = Config.KEEPER_COLORS[team] if role == GK else Config.TEAM_COLORS[team]
	var accent: Color = Config.ACCENT_COLORS[team]
	if role == GK:
		accent = Color(0.95, 0.4, 0.15) if team == 0 else Color(0.2, 0.3, 0.9)
	model.build(shirt, Config.SHORTS_COLORS[team], Config.SOCK_COLORS[team], number, team * 11 + number, accent, role == GK)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.68
	torus.rings = 32
	torus.ring_segments = 4
	_ring = Toon.mesh_instance(torus, Toon.flat(Color(1, 0.88, 0.2)), Vector3(0, 0.04, 0))
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.16
	cone.bottom_radius = 0.0
	cone.height = 0.28
	_arrow = Toon.mesh_instance(cone, Toon.material(Color(1, 0.88, 0.2), true, 0.025), Vector3(0, ARROW_HEIGHT, 0))
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)
	_sync_visual(0.0)


func play_kick() -> void:
	model.play_kick()


func busy() -> bool:
	return action != ACT_NONE or stun > 0.0


func start_slide(dir: Vector2) -> bool:
	if busy() or tackle_cooldown > 0.0:
		return false
	_begin(ACT_SLIDE, SLIDE_TIME, dir)
	tackle_cooldown = 1.2
	return true


func start_tackle(dir: Vector2) -> bool:
	if busy() or tackle_cooldown > 0.0:
		return false
	_begin(ACT_TACKLE, TACKLE_TIME, dir)
	tackle_cooldown = 0.7
	model.play_kick()
	return true


func end_action() -> void:
	action = ACT_NONE
	action_time = 0.0


func _begin(kind: int, time: float, dir: Vector2) -> void:
	action = kind
	action_time = time
	action_dir = dir.normalized() if dir.length() > 0.01 else facing
	action_resolved = false
	facing = action_dir


func step(delta: float) -> void:
	tackle_cooldown = maxf(tackle_cooldown - delta, 0.0)
	decision_timer -= delta
	lunge -= delta
	_get_up = maxf(_get_up - delta, 0.0)
	if action != ACT_NONE:
		action_time -= delta
		if action == ACT_SLIDE:
			velocity = action_dir * lerpf(1.5 * Config.M, SLIDE_SPEED, clampf(action_time / SLIDE_TIME, 0.0, 1.0))
		else:
			velocity = action_dir * TACKLE_SPEED
		pos += velocity * delta
		pos.x = clampf(pos.x, -Config.HALF_L + 4, Config.HALF_L - 4)
		pos.y = clampf(pos.y, -Config.HALF_W + 4, Config.HALF_W - 4)
		if action_time <= 0.0:
			if action == ACT_SLIDE:
				stun = GET_UP_TIME
				_get_up = GET_UP_TIME
			end_action()
		return
	var want := desired_velocity * speed_mult
	if stun > 0.0:
		stun -= delta
		want = Vector2.ZERO
	velocity = velocity.move_toward(want, Config.PLAYER_ACCEL * delta)
	pos += velocity * delta
	pos.x = clampf(pos.x, -Config.HALF_L + 4, Config.HALF_L - 4)
	pos.y = clampf(pos.y, -Config.HALF_W + 4, Config.HALF_W - 4)
	if want.length() > 10.0:
		facing = facing.slerp(want.normalized(), minf(1.0, 14.0 * delta)).normalized()


func _process(delta: float) -> void:
	_sync_visual(delta)


func _sync_visual(delta: float) -> void:
	position = Config.to_3d(pos)
	var target_yaw := atan2(-facing.x, -facing.y)
	_yaw = target_yaw if delta == 0.0 else lerp_angle(_yaw, target_yaw, minf(1.0, 16.0 * delta))
	model.rotation.y = _yaw
	var sliding := action == ACT_SLIDE or _get_up > 0.0
	model.slide_target = 1.0 if action == ACT_SLIDE else (_get_up / GET_UP_TIME if _get_up > 0.0 else 0.0)
	var run := 0.0 if sliding else clampf(velocity.length() / Config.PLAYER_SPEED, 0.0, 1.2)
	model.animate(delta, run, stun > 0.0 and not sliding)
	_ring.visible = is_human and not hide_marker
	_arrow.visible = is_human and not hide_marker
	if is_human:
		_ring.rotate_y(delta * 2.0)
		_arrow.position.y = ARROW_HEIGHT + sin(Time.get_ticks_msec() * 0.008) * 0.08
