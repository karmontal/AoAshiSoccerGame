// Inverted-hull outline, used as next_pass of toon materials.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.1, 1.0);
uniform float width = 0.022;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
