class_name Stadium
extends Node3D
## Builds the 3D environment: sky and sun, procedural pitch, goals, ad boards and stands.

const PITCH_SHADER := preload("res://shaders/pitch.gdshader")
const CROWD_SHADER := preload("res://shaders/crowd.gdshader")
const NET_SHADER := preload("res://shaders/net.gdshader")

const S := Config.WORLD_SCALE

var sun: DirectionalLight3D


func _ready() -> void:
	_build_environment()
	_build_pitch()
	for side: float in [-1.0, 1.0]:
		_build_goal(side)
	_build_boards()
	_build_stands()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.48, 0.95)
	sky_mat.sky_horizon_color = Color(0.72, 0.86, 1.0)
	sky_mat.ground_horizon_color = Color(0.72, 0.86, 1.0)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 1.0)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _build_pitch() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 180)
	var mat := ShaderMaterial.new()
	mat.shader = PITCH_SHADER
	mat.set_shader_parameter("half_size", Vector2(Config.HALF_L, Config.HALF_W) * S)
	mat.set_shader_parameter("box_depth", Config.BOX_DEPTH * S)
	mat.set_shader_parameter("box_half_width", Config.BOX_WIDTH * 0.5 * S)
	mat.set_shader_parameter("small_box_depth", Config.SMALL_BOX_DEPTH * S)
	mat.set_shader_parameter("small_box_half_width", Config.SMALL_BOX_WIDTH * 0.5 * S)
	mat.set_shader_parameter("center_radius", Config.CENTER_CIRCLE * S)
	mat.set_shader_parameter("spot_distance", 220.0 * S)
	mat.set_shader_parameter("arc_radius", 150.0 * S)
	var ground := Toon.mesh_instance(plane, mat)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


func _build_goal(side: float) -> void:
	var x := side * Config.HALF_L * S
	var half_w := Config.GOAL_WIDTH * 0.5 * S
	var h := Ball.CROSSBAR * S
	var depth := Config.GOAL_DEPTH * S
	var white := Toon.material(Color(0.97, 0.97, 1.0), true, 0.03)
	var bar := 0.1

	for z: float in [-half_w, half_w]:
		add_child(Toon.mesh_instance(_cylinder(bar, h), white, Vector3(x, h / 2, z)))
		var back := Toon.mesh_instance(_cylinder(bar * 0.5, h), white, Vector3(x + side * depth, h / 2, z))
		add_child(back)
		var top_side := Toon.mesh_instance(_cylinder(bar * 0.5, depth), white, Vector3(x + side * depth / 2, h, z))
		top_side.rotation.z = PI / 2
		add_child(top_side)
	var crossbar := Toon.mesh_instance(_cylinder(bar, half_w * 2), white, Vector3(x, h, 0))
	crossbar.rotation.x = PI / 2
	add_child(crossbar)

	var net := ShaderMaterial.new()
	net.shader = NET_SHADER
	_add_net(net, Vector3(x + side * depth, h / 2, 0), Vector2(half_w * 2, h), Vector3(0, PI / 2, 0), Vector2(16, 6))
	_add_net(net, Vector3(x + side * depth / 2, h, 0), Vector2(depth, half_w * 2), Vector3(-PI / 2, 0, 0), Vector2(4, 16))
	for z: float in [-half_w, half_w]:
		_add_net(net, Vector3(x + side * depth / 2, h / 2, z), Vector2(depth, h), Vector3.ZERO, Vector2(4, 6))


func _add_net(mat: Material, pos: Vector3, size: Vector2, rot: Vector3, cells: Vector2) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var mi := Toon.mesh_instance(quad, mat.duplicate(), pos)
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(mi.material_override as ShaderMaterial).set_shader_parameter("cells", cells)
	add_child(mi)


func _build_boards() -> void:
	var hl := Config.HALF_L * S
	var hw := Config.HALF_W * S
	var colors := [Color(0.14, 0.39, 0.92), Color(0.97, 0.97, 1.0), Color(0.95, 0.75, 0.15)]
	var texts := ["AO SOCCER", "AOBA FC", "KAZE UTD", "YOUTH CUP"]
	var length := 12.0
	var i := 0
	# Far touchline and both goal lines (the near side is left open for the camera).
	var x := -hl
	while x < hl - 0.1:
		_add_board(Vector3(x + length / 2, 0.5, -hw - 3.5), 0.0, length, colors[i % 3], texts[i % 4])
		x += length
		i += 1
	for side: float in [-1.0, 1.0]:
		var z := -hw
		while z < hw - 0.1:
			if absf(z + length / 2) > Config.GOAL_WIDTH * S:
				_add_board(Vector3(side * (hl + 4.0), 0.5, z + length / 2), -side * PI / 2, length, colors[i % 3], texts[i % 4])
			z += length
			i += 1


func _add_board(pos: Vector3, yaw: float, length: float, color: Color, text: String) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(length - 0.2, 1.0, 0.25)
	var board := Toon.mesh_instance(box, Toon.material(color, true, 0.03), pos)
	board.rotation.y = yaw
	add_child(board)
	var label := Label3D.new()
	label.text = text
	label.font_size = 160
	label.pixel_size = 0.004
	label.outline_size = 24
	label.modulate = Color.WHITE if color.get_luminance() < 0.6 else Config.TEAM_COLORS[0]
	label.outline_modulate = Config.INK
	label.position = Vector3(0, 0, 0.14)
	board.add_child(label)


func _build_stands() -> void:
	var hl := Config.HALF_L * S
	var hw := Config.HALF_W * S
	var slope := deg_to_rad(32.0)
	var depth := 26.0
	var defs := [
		{"center": Vector3(0, 0, -hw - 7.0), "yaw": 0.0, "length": hl * 2 + 30.0},
		{"center": Vector3(0, 0, hw + 9.0), "yaw": PI, "length": hl * 2 + 30.0},
		{"center": Vector3(-hl - 8.0, 0, 0), "yaw": PI / 2, "length": hw * 2 + 14.0},
		{"center": Vector3(hl + 8.0, 0, 0), "yaw": -PI / 2, "length": hw * 2 + 14.0},
	]
	var k := 0
	for d: Dictionary in defs:
		var pivot := Node3D.new()
		pivot.position = d["center"]
		pivot.rotation.y = d["yaw"]
		add_child(pivot)
		var quad := QuadMesh.new()
		var length: float = d["length"]
		quad.size = Vector2(length, depth)
		var mat := ShaderMaterial.new()
		mat.shader = CROWD_SHADER
		mat.set_shader_parameter("cells", Vector2(length * 2.2, depth * 1.6))
		mat.set_shader_parameter("time_offset", float(k) * 3.0)
		var stand := Toon.mesh_instance(quad, mat)
		# Quad faces +z; tilt it back so it rises away from the pitch.
		stand.rotation.x = -(PI / 2 - slope)
		stand.position = Vector3(0, sin(slope) * depth / 2 + 1.0, -cos(slope) * depth / 2)
		stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(stand)
		k += 1


## 0 = low (no shadows), 1 = medium, 2 = high.
func set_quality(level: int) -> void:
	sun.shadow_enabled = level > 0
	sun.directional_shadow_max_distance = 60.0 if level == 1 else 90.0


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 12
	c.rings = 1
	return c
