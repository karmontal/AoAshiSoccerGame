// Classic football pattern: black pentagons at the 12 icosahedron vertices.
shader_type spatial;

#include "res://shaders/toon_light.gdshaderinc"

const float PHI = 1.618034;
const vec3 DIRS[6] = vec3[6](
	vec3(0.0, 1.0, PHI), vec3(0.0, 1.0, -PHI), vec3(1.0, PHI, 0.0),
	vec3(-1.0, PHI, 0.0), vec3(PHI, 0.0, 1.0), vec3(-PHI, 0.0, 1.0));

varying vec3 obj_normal;

void vertex() {
	obj_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(obj_normal);
	float m = 0.0;
	for (int i = 0; i < 6; i++) {
		m = max(m, abs(dot(n, normalize(DIRS[i]))));
	}
	ALBEDO = mix(vec3(0.97), vec3(0.08, 0.08, 0.12), step(0.935, m));
}
