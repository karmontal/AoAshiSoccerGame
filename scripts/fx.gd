class_name FX
extends RefCounted
## One-shot anime effects: kick flashes, grass bursts and goal confetti.
## Every effect frees itself when done.

const BURST_SHADER := preload("res://shaders/burst.gdshader")

## Particle amount multiplier from the graphics setting.
static var quality := 1.0


static func kick(parent: Node3D, at: Vector3, color: Color, size: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = BURST_SHADER
	mat.set_shader_parameter("color", color)
	var mi := Toon.mesh_instance(quad, mat, at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	parent.add_child(mi)
	var tween := mi.create_tween()
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.28)
	tween.tween_callback(mi.queue_free)
	grass(parent, at, int(8 + size * 6))


static func grass(parent: Node3D, at: Vector3, amount: int) -> void:
	var p := _particles(amount, 0.7)
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.12, 0.02)
	p.mesh = box
	p.material_override = Toon.flat(Color(0.3, 0.7, 0.3))
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -12, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.position = Vector3(at.x, 0.05, at.z)
	_launch(parent, p)


static func confetti(parent: Node3D, at: Vector3, team_color: Color) -> void:
	var p := _particles(160, 3.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.08)
	p.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = mat
	var colors := Gradient.new()
	colors.set_color(0, team_color)
	colors.set_color(1, Color(1, 0.9, 0.3))
	colors.add_point(0.5, Color.WHITE)
	p.color_initial_ramp = colors
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -5, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angular_velocity_min = -600.0
	p.angular_velocity_max = 600.0
	p.particle_flag_rotate_y = true
	p.position = at + Vector3(0, 0.5, 0)
	_launch(parent, p)


static func _particles(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, int(amount * quality))
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _launch(parent: Node3D, p: CPUParticles3D) -> void:
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
