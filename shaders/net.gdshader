// Goal net: transparent grid.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec2 cells = vec2(10.0, 10.0);

void fragment() {
	vec2 g = abs(fract(UV * cells) - 0.5);
	float l = smoothstep(0.38, 0.47, max(g.x, g.y));
	ALBEDO = vec3(1.0);
	ALPHA = 0.08 + 0.6 * l;
}
