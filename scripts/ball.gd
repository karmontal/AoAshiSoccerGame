class_name Ball
extends Node3D
## Arcade ball physics on the 2D logic plane plus a height axis for lofted
## passes; the 3D mesh is synced to it and rolls with the ball's velocity.
## The touchlines and goal lines act as walls, except for the goal mouth.

signal goal_scored(scoring_team: int)

## Somewhat heavier than real gravity so lofted balls stay snappy.
const GRAVITY := 16.0 * Config.M
const GROUND_DAMP := 1.25
const AIR_DAMP := 0.35
const CROSSBAR := Config.GOAL_HEIGHT
## Players can bring the ball down up to chest height.
const CONTROL_HEIGHT := 1.7 * Config.M
## Slightly larger than a real ball (0.11 m) so it reads on a phone screen.
const VISUAL_RADIUS := 0.14
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
var _trail: CPUParticles3D
var _trail_ramp: Gradient


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
				vz = -vz * 0.35 if absf(vz) > 4.0 * Config.M else 0.0
				velocity *= 0.8
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
	mat.next_pass = Toon.outline_material(0.012)
	_mesh = Toon.mesh_instance(sphere, mat)
	add_child(_mesh)

	var blob := CylinderMesh.new()
	blob.top_radius = VISUAL_RADIUS * 1.1
	blob.bottom_radius = VISUAL_RADIUS * 1.1
	blob.height = 0.01
	_shadow = Toon.mesh_instance(blob, Toon.flat(Color(0, 0, 0, 0.35)), Vector3(0, 0.03, 0))
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	# Light trail behind fast shots and passes.
	_trail = CPUParticles3D.new()
	_trail.amount = 48
	_trail.lifetime = 0.35
	_trail.local_coords = false
	_trail.emitting = false
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot := SphereMesh.new()
	dot.radius = VISUAL_RADIUS * 0.9
	dot.height = VISUAL_RADIUS * 1.8
	dot.radial_segments = 8
	dot.rings = 4
	_trail.mesh = dot
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail.material_override = trail_mat
	_trail_ramp = Gradient.new()
	_trail_ramp.set_color(0, Color(1, 1, 1, 0.9))
	_trail_ramp.set_color(1, Color(1, 1, 1, 0.0))
	_trail.color_ramp = _trail_ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.1))
	_trail.scale_amount_curve = shrink
	_trail.gravity = Vector3.ZERO
	_trail.initial_velocity_min = 0.0
	_trail.initial_velocity_max = 0.0
	add_child(_trail)


func _process(delta: float) -> void:
	position = Config.to_3d(pos)
	_mesh.position.y = VISUAL_RADIUS + height * Config.WORLD_SCALE
	var v3 := Vector3(velocity.x, 0, velocity.y) * Config.WORLD_SCALE
	if v3.length() > 0.05:
		# Rolling axis is up x velocity.
		_mesh.rotate(Vector3(v3.z, 0, -v3.x).normalized(), v3.length() * delta / VISUAL_RADIUS)
	_trail.position = _mesh.position
	_trail.emitting = FX.quality > 0.5 and holder == null and not frozen and velocity.length() > 850.0
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
	if _trail_ramp != null and kicker != null:
		var c: Color = Config.TEAM_COLORS[kicker.team].lightened(0.45)
		_trail_ramp.set_color(0, Color(c, 0.9))
		_trail_ramp.set_color(1, Color(c, 0.0))
	_ignore_kicker = 0.22


## Knock the ball away after a failed first touch on a fast ball.
func deflect(by: Footballer) -> void:
	velocity = velocity.rotated(randf_range(2.2, 4.1)) * 0.35
	last_kicker = by
	intended_receiver = null
	_ignore_kicker = 0.25


## Where the ball will be worth running to: its landing spot while airborne,
## a little ahead of it while rolling.
func target_point() -> Vector2:
	if height <= 0.0 and vz <= 0.0:
		return pos + velocity * 0.35
	var t := (vz + sqrt(vz * vz + 2.0 * GRAVITY * height)) / GRAVITY
	return pos + velocity * t * exp(-AIR_DAMP * t * 0.5)


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
