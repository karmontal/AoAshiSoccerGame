class_name Footballer
extends Node3D
## One player. Gameplay state lives on the 2D logic plane (`pos`); the 3D
## model is synced to it every frame. Movement is driven by `desired_velocity`,
## which the match sets each physics frame (touch input or AI).

const GK := 0
const DEF := 1
const MID := 2
const FWD := 3

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

var model: PlayerModel
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _yaw := 0.0


func _ready() -> void:
	model = PlayerModel.new()
	add_child(model)
	var shirt: Color = Config.KEEPER_COLORS[team] if role == GK else Config.TEAM_COLORS[team]
	model.build(shirt, Config.SHORTS_COLORS[team], Config.SOCK_COLORS[team], number, team * 5 + number)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 0.95
	torus.rings = 32
	torus.ring_segments = 4
	_ring = Toon.mesh_instance(torus, Toon.flat(Color(1, 0.88, 0.2)), Vector3(0, 0.04, 0))
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 0.0
	cone.height = 0.35
	_arrow = Toon.mesh_instance(cone, Toon.material(Color(1, 0.88, 0.2), true, 0.03), Vector3(0, 2.5, 0))
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)
	_sync_visual(0.0)


func play_kick() -> void:
	model.play_kick()


func step(delta: float) -> void:
	tackle_cooldown = maxf(tackle_cooldown - delta, 0.0)
	decision_timer -= delta
	var want := desired_velocity
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
	model.animate(delta, clampf(velocity.length() / Config.PLAYER_SPEED, 0.0, 1.2), stun > 0.0)
	_ring.visible = is_human and not hide_marker
	_arrow.visible = is_human and not hide_marker
	if is_human:
		_ring.rotate_y(delta * 2.0)
		_arrow.position.y = 2.5 + sin(Time.get_ticks_msec() * 0.008) * 0.08
