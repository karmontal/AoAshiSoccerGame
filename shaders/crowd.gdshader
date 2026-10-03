// Stylised crowd: a grid of coloured heads over a dark stand.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec2 cells = vec2(160.0, 22.0);
uniform vec4 stand_color : source_color = vec4(0.16, 0.18, 0.28, 1.0);
uniform float time_offset = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 g = UV * cells;
	vec2 cell = floor(g);
	float h = hash(cell);
	float bounce = step(0.85, h) * abs(sin(TIME * 6.0 + h * 40.0 + time_offset)) * 0.18;
	vec2 f = fract(g) - vec2(0.5, 0.45 - bounce);
	vec3 shirt = 0.55 + 0.45 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
	float head = 1.0 - smoothstep(0.26, 0.31, length(f * vec2(1.0, 0.85)));
	float row_shade = 0.75 + 0.25 * fract(cell.y * 0.5);
	vec3 col = mix(stand_color.rgb * row_shade, shirt, head * step(0.12, h));
	ALBEDO = col;
}
