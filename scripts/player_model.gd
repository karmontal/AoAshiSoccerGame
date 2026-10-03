class_name PlayerModel
extends Node3D
## Procedural anime-style footballer built from primitive meshes with cel
## shading and ink outlines, animated in code (run cycle, kick, celebration).
## Faces -Z.

const SKIN_TONES := [Color(1.0, 0.86, 0.74), Color(0.97, 0.79, 0.64), Color(0.86, 0.65, 0.5), Color(0.6, 0.43, 0.32)]
const HAIR_COLORS := [
	Color(0.13, 0.11, 0.14), Color(0.38, 0.22, 0.13), Color(0.98, 0.83, 0.38),
	Color(0.93, 0.47, 0.16), Color(0.82, 0.84, 0.93), Color(0.22, 0.28, 0.58),
]
const KICK_TIME := 0.32
const HEAD_RADIUS := 0.2

## Hair styles: each spike is [anchor direction on the head, pointing direction, length].
const HAIR_STYLES := [
	[ # spiky
		[Vector3(0, 1, 0.3), Vector3(0, 1, 0.5), 0.3], [Vector3(0.5, 0.8, 0.3), Vector3(0.8, 0.8, 0.5), 0.26],
		[Vector3(-0.5, 0.8, 0.3), Vector3(-0.8, 0.8, 0.5), 0.26], [Vector3(0, 0.6, 0.9), Vector3(0, 0.5, 1), 0.28],
		[Vector3(0.6, 0.4, 0.7), Vector3(0.7, 0.2, 1), 0.22], [Vector3(-0.6, 0.4, 0.7), Vector3(-0.7, 0.2, 1), 0.22],
		[Vector3(0.3, 0.7, -0.6), Vector3(0.3, -0.3, -1), 0.2], [Vector3(-0.3, 0.7, -0.6), Vector3(-0.3, -0.3, -1), 0.2],
		[Vector3(0, 0.8, -0.5), Vector3(0, 0.1, -1), 0.22],
	],
	[ # swept back
		[Vector3(0, 0.9, -0.3), Vector3(0, 0.6, 1), 0.34], [Vector3(0.4, 0.8, -0.2), Vector3(0.3, 0.4, 1), 0.32],
		[Vector3(-0.4, 0.8, -0.2), Vector3(-0.3, 0.4, 1), 0.32], [Vector3(0, 0.5, 0.9), Vector3(0, -0.2, 1), 0.3],
		[Vector3(0.7, 0.5, 0.4), Vector3(0.5, -0.3, 1), 0.24], [Vector3(-0.7, 0.5, 0.4), Vector3(-0.5, -0.3, 1), 0.24],
	],
	[ # long bangs
		[Vector3(0, 0.8, -0.6), Vector3(0.1, -0.6, -1), 0.26], [Vector3(0.45, 0.7, -0.5), Vector3(0.4, -0.7, -0.8), 0.26],
		[Vector3(-0.45, 0.7, -0.5), Vector3(-0.4, -0.7, -0.8), 0.26], [Vector3(0.8, 0.4, 0), Vector3(0.6, -1, 0.1), 0.26],
		[Vector3(-0.8, 0.4, 0), Vector3(-0.6, -1, 0.1), 0.26], [Vector3(0, 0.6, 0.8), Vector3(0, -0.6, 1), 0.3],
		[Vector3(0, 1, 0.1), Vector3(0.3, 1, -0.2), 0.18],
	],
]

var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _phase := 0.0
var _kick := 0.0
var _celebrate := -1.0


func build(shirt: Color, shorts: Color, socks: Color, number: int, variant: int, accent := Color.WHITE, keeper := false) -> void:
	var skin: Color = SKIN_TONES[variant % SKIN_TONES.size()]
	var hair: Color = HAIR_COLORS[(variant * 7 + 3) % HAIR_COLORS.size()]
	var boot := accent.darkened(0.15)

	_body = Node3D.new()
	add_child(_body)

	# Legs: hip -> thigh -> knee -> shin -> boot.
	_leg_l = _pivot(_body, Vector3(-0.12, 0.95, 0))
	_leg_r = _pivot(_body, Vector3(0.12, 0.95, 0))
	for leg: Node3D in [_leg_l, _leg_r]:
		_part(leg, _capsule(0.105, 0.5), skin, Vector3(0, -0.22, 0))
		var knee := _pivot(leg, Vector3(0, -0.44, 0))
		knee.name = "Knee"
		_part(knee, _capsule(0.092, 0.46), socks, Vector3(0, -0.2, 0))
		_part(knee, _cylinder(0.096, 0.096, 0.05), accent, Vector3(0, -0.02, 0), false)
		_part(knee, _box(Vector3(0.15, 0.11, 0.3)), boot, Vector3(0, -0.46, -0.06))

	_part(_body, _cylinder(0.21, 0.24, 0.3), shorts, Vector3(0, 0.92, 0))
	for sx: float in [-1.0, 1.0]:
		var stripe := _part(_body, _box(Vector3(0.02, 0.26, 0.07)), accent, Vector3(sx * 0.228, 0.92, 0), false)
		stripe.rotation.z = sx * 0.1
	_part(_body, _capsule(0.235, 0.66), shirt, Vector3(0, 1.3, 0))
	var collar := TorusMesh.new()
	collar.inner_radius = 0.08
	collar.outer_radius = 0.12
	collar.rings = 16
	collar.ring_segments = 6
	_part(_body, collar, accent, Vector3(0, 1.585, 0), false)

	# Arms: shoulder -> upper arm -> elbow -> forearm -> hand.
	_arm_l = _pivot(_body, Vector3(-0.31, 1.5, 0))
	_arm_r = _pivot(_body, Vector3(0.31, 1.5, 0))
	for arm: Node3D in [_arm_l, _arm_r]:
		_part(arm, _capsule(0.095, 0.3), shirt, Vector3(0, -0.1, 0))
		_part(arm, _cylinder(0.098, 0.098, 0.04), accent, Vector3(0, -0.2, 0), false)
		_part(arm, _capsule(0.066, 0.3), skin, Vector3(0, -0.2, 0))
		var elbow := _pivot(arm, Vector3(0, -0.3, 0))
		elbow.name = "Elbow"
		_part(elbow, _capsule(0.062, 0.3), skin, Vector3(0, -0.13, 0))
		if keeper:
			_part(elbow, _sphere(0.1), accent, Vector3(0, -0.3, 0))
		else:
			_part(elbow, _sphere(0.072), skin, Vector3(0, -0.29, 0))

	var head := _pivot(_body, Vector3(0, 1.62, 0))
	_part(head, _cylinder(0.075, 0.085, 0.16), skin, Vector3(0, 0.0, 0), false)
	var face_center := Vector3(0, 0.2, 0)
	_part(head, _sphere(HEAD_RADIUS), skin, face_center)
	_build_eyes(head, face_center, hair)
	var mouth := _part(head, _box(Vector3(0.05, 0.012, 0.01)), Color(0.45, 0.2, 0.2), face_center + Vector3(0, -0.1, -0.178), false)
	mouth.rotation.x = 0.4
	_build_hair(head, face_center, hair, variant)

	var text_col := Color.WHITE if shirt.get_luminance() < 0.7 else Config.INK
	var outline_col := Config.INK if shirt.get_luminance() < 0.7 else Color.WHITE
	_add_number(str(number), Vector3(0, 1.36, 0.245), 0.0, 110, text_col, outline_col)
	_add_number(str(number), Vector3(0.1, 1.43, -0.235), PI, 50, text_col, outline_col)

	_knee_l = _leg_l.get_node("Knee")
	_knee_r = _leg_r.get_node("Knee")
	_elbow_l = _arm_l.get_node("Elbow")
	_elbow_r = _arm_r.get_node("Elbow")


func _add_number(text: String, pos: Vector3, yaw: float, size: int, color: Color, outline: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.0034
	label.outline_size = int(size / 5.0)
	label.modulate = color
	label.outline_modulate = outline
	label.position = pos
	label.rotation.y = yaw
	_body.add_child(label)


func _build_eyes(head: Node3D, c: Vector3, hair: Color) -> void:
	var iris := hair.darkened(0.35) if hair.get_luminance() > 0.3 else Color(0.25, 0.18, 0.12)
	for sx: float in [-1.0, 1.0]:
		var white := _part(head, _sphere(0.05), Color.WHITE, c + Vector3(sx * 0.078, 0.0, -0.172), false)
		white.scale = Vector3(0.95, 1.35, 0.45)
		var pupil := _part(head, _sphere(0.04), iris, c + Vector3(sx * 0.075, -0.005, -0.19), false)
		pupil.scale = Vector3(0.8, 1.25, 0.4)
		var shine := _part(head, _sphere(0.014), Color.WHITE, c + Vector3(sx * 0.062, 0.02, -0.205), false)
		shine.material_override = Toon.flat(Color.WHITE)
		var brow := _part(head, _box(Vector3(0.08, 0.018, 0.02)), hair.darkened(0.3), c + Vector3(sx * 0.08, 0.085, -0.178), false)
		brow.rotation.z = sx * -0.18


func _build_hair(head: Node3D, c: Vector3, hair: Color, variant: int) -> void:
	var cap := SphereMesh.new()
	cap.radius = HEAD_RADIUS + 0.018
	cap.height = (HEAD_RADIUS + 0.018) * 2
	cap.is_hemisphere = true
	cap.radial_segments = 16
	cap.rings = 6
	var cap_mi := _part(head, cap, hair, c + Vector3(0, 0.01, 0.015))
	cap_mi.rotation.x = -0.25
	var style: Array = HAIR_STYLES[variant % HAIR_STYLES.size()]
	for spike: Array in style:
		var anchor: Vector3 = (spike[0] as Vector3).normalized()
		var dir: Vector3 = (spike[1] as Vector3).normalized()
		var length: float = spike[2]
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.08
		cone.height = length
		cone.radial_segments = 8
		cone.rings = 1
		var mi := _part(head, cone, hair, c + anchor * (HEAD_RADIUS - 0.02) + dir * length * 0.4)
		mi.basis = Basis(Quaternion(Vector3.UP, dir))


func play_kick() -> void:
	_kick = KICK_TIME


func set_celebrating(on: bool) -> void:
	_celebrate = 0.0 if on else -1.0


func animate(delta: float, speed_ratio: float, stunned: bool) -> void:
	_phase += delta * (5.0 + 9.0 * speed_ratio)
	var s := sin(_phase)
	var amp := 0.85 * speed_ratio
	var leg_l := s * amp
	var leg_r := -s * amp
	# Knees bend most while the leg swings forward (negative = foot goes back).
	var knee_l := -maxf(0.0, cos(_phase)) * 1.3 * speed_ratio - 0.05
	var knee_r := -maxf(0.0, -cos(_phase)) * 1.3 * speed_ratio - 0.05
	var arm_l := Vector2(-s * amp * 0.9, -0.12)
	var arm_r := Vector2(s * amp * 0.9, 0.12)
	var elbow := 0.25 + 0.9 * speed_ratio
	var elbow_l := elbow
	var elbow_r := elbow
	var bob := absf(cos(_phase)) * 0.07 * speed_ratio
	var lean := -0.2 * speed_ratio

	if _kick > 0.0:
		_kick -= delta
		var k := 1.0 - _kick / KICK_TIME
		if k < 0.35:
			leg_r = lerpf(0.0, -0.8, k / 0.35)
			knee_r = lerpf(0.0, -1.4, k / 0.35)
		elif k < 0.65:
			leg_r = lerpf(-0.8, 1.4, (k - 0.35) / 0.3)
			knee_r = lerpf(-1.4, 0.0, (k - 0.35) / 0.3)
		else:
			leg_r = lerpf(1.4, 0.0, (k - 0.65) / 0.35)
			knee_r = lerpf(0.0, -0.1, (k - 0.65) / 0.35)
		leg_l = 0.0
		knee_l = -0.25
		arm_l = Vector2(0.3, -0.8)
		arm_r = Vector2(-0.3, 0.6)
		elbow_l = 0.4
		elbow_r = 0.4
		lean = 0.12

	if _celebrate >= 0.0:
		_celebrate += delta
		bob = absf(sin(_celebrate * 7.0)) * 0.45
		arm_l = Vector2(0.0, -2.7)
		arm_r = Vector2(0.0, 2.7)
		elbow_l = 0.2
		elbow_r = 0.2
		leg_l = -0.3 * bob
		leg_r = -0.3 * bob
		knee_l = -1.6 * bob
		knee_r = -1.6 * bob
		lean = -0.1

	if stunned:
		lean = 0.3 + sin(_phase * 2.0) * 0.1

	_leg_l.rotation.x = leg_l
	_leg_r.rotation.x = leg_r
	_knee_l.rotation.x = knee_l
	_knee_r.rotation.x = knee_r
	_arm_l.rotation = Vector3(arm_l.x, 0, arm_l.y)
	_arm_r.rotation = Vector3(arm_r.x, 0, arm_r.y)
	_elbow_l.rotation.x = elbow_l
	_elbow_r.rotation.x = elbow_r
	_body.position.y = bob
	_body.rotation.x = lean


# --- mesh helpers -----------------------------------------------------------

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, outline := true) -> MeshInstance3D:
	var mi := Toon.mesh_instance(mesh, Toon.material(color, outline), pos)
	parent.add_child(mi)
	return mi


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


static func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2
	m.radial_segments = 16
	m.rings = 8
	return m


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 12
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
