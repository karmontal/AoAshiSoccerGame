class_name Ball
extends Node3D
## Arcade ball physics on the 2D logic plane plus a height axis for lofted
## passes; the 3D mesh is synced to it and rolls with the ball's velocity.
## The touchlines and goal lines act as walls, except for the goal mouth.

signal goal_scored(scoring_team: int)

const GRAVITY := 980.0
const GROUND_DAMP := 1.25
const AIR_DAMP := 0.35
const CROSSBAR := 70.0
const CONTROL_HEIGHT := 32.0
const VISUAL_RADIUS := 0.3
const BALL_SHADER := preload("res://shaders/ball.gdshader")

var pos := Vector2.ZERO
var velocity := Vector2.ZERO
var height := 0.0
var vz := 0.0
var holder: Footballer = null
var intended_receiver: Footballer = null
var last_kicker: Footballer = null
var frozen := false
var _ignore_kicker := 0.0
var _mesh: MeshInstance3D
var _shadow: MeshInstance3D


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_ignore_kicker = maxf(_ignore_kicker - delta, 0.0)
	if holder != null:
		pos = holder.pos + holder.facing * (Config.PLAYER_RADIUS + Config.BALL_RADIUS + 2.0)
		velocity = holder.velocity
		height = 0.0
		vz = 0.0
	else:
		if height > 0.0 or vz > 0.0:
			vz -= GRAVITY * delta
			height += vz * delta
			if height <= 0.0:
				height = 0.0
				vz = -vz * 0.4 if absf(vz) > 150.0 else 0.0
			velocity *= exp(-AIR_DAMP * delta)
		else:
			velocity *= exp(-GROUND_DAMP * delta)
		if velocity.length() < 4.0:
			velocity = Vector2.ZERO
		pos += velocity * delta
	_check_bounds()


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = VISUAL_RADIUS
	sphere.height = VISUAL_RADIUS * 2
	sphere.radial_segments = 24
	sphere.rings = 12
	var mat := ShaderMaterial.new()
	mat.shader = BALL_SHADER
	mat.next_pass = Toon.outline_material(0.025)
	_mesh = Toon.mesh_instance(sphere, mat)
	add_child(_mesh)

	var blob := CylinderMesh.new()
	blob.top_radius = VISUAL_RADIUS * 1.1
	blob.bottom_radius = VISUAL_RADIUS * 1.1
	blob.height = 0.01
	_shadow = Toon.mesh_instance(blob, Toon.flat(Color(0, 0, 0, 0.35)), Vector3(0, 0.03, 0))
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


func _process(delta: float) -> void:
	position = Config.to_3d(pos)
	_mesh.position.y = VISUAL_RADIUS + height * Config.WORLD_SCALE
	var v3 := Vector3(velocity.x, 0, velocity.y) * Config.WORLD_SCALE
	if v3.length() > 0.05:
		# Rolling axis is up x velocity.
		_mesh.rotate(Vector3(v3.z, 0, -v3.x).normalized(), v3.length() * delta / VISUAL_RADIUS)
	var s := 1.0 - minf(height * Config.WORLD_SCALE / 6.0, 0.6)
	_shadow.scale = Vector3(s, 1, s)


func _check_bounds() -> void:
	if absf(pos.x) > Config.HALF_L:
		var side := signf(pos.x)
		var in_mouth := absf(pos.y) < Config.GOAL_WIDTH / 2 - Config.BALL_RADIUS and height < CROSSBAR
		if in_mouth:
			if absf(pos.x) > Config.HALF_L + Config.BALL_RADIUS:
				frozen = true
				holder = null
				velocity = Vector2.ZERO
				goal_scored.emit(0 if side > 0 else 1)
			return
		pos.x = side * Config.HALF_L
		velocity.x = -velocity.x * 0.5
	if absf(pos.y) > Config.HALF_W:
		pos.y = signf(pos.y) * Config.HALF_W
		velocity.y = -velocity.y * 0.5


func kick(vel: Vector2, lift: float, kicker: Footballer, receiver: Footballer = null) -> void:
	holder = null
	velocity = vel
	vz = lift
	if lift > 0.0:
		height = maxf(height, 1.0)
	last_kicker = kicker
	intended_receiver = receiver
	_ignore_kicker = 0.22


## Knock the ball away after a failed first touch on a fast ball.
func deflect(by: Footballer) -> void:
	velocity = velocity.rotated(randf_range(2.2, 4.1)) * 0.35
	last_kicker = by
	intended_receiver = null
	_ignore_kicker = 0.25


func can_be_taken_by(p: Footballer) -> bool:
	return not frozen and height < CONTROL_HEIGHT and not (p == last_kicker and _ignore_kicker > 0.0)


func place(at: Vector2) -> void:
	holder = null
	intended_receiver = null
	last_kicker = null
	pos = at
	velocity = Vector2.ZERO
	height = 0.0
	vz = 0.0
	frozen = false
