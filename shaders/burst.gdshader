// Anime impact flash: a billboarded star burst that expands and fades.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float progress = 0.0;
uniform float spikes = 8.0;

void vertex() {
	// Face the camera, keep the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float star = 0.35 + 0.65 * pow(abs(cos(a * spikes * 0.5)), 6.0);
	float reach = mix(0.3, 1.0, progress);
	float shape = 1.0 - smoothstep(reach * star - 0.08, reach * star, r);
	float core = 1.0 - smoothstep(0.0, 0.35 * (1.0 - progress), r);
	float fade = 1.0 - progress;
	ALBEDO = color.rgb;
	ALPHA = clamp(shape * fade * 0.9 + core, 0.0, 1.0);
}
