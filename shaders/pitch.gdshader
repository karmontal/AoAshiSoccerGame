// Procedural pitch: mowing stripes and crisp anti-aliased line markings.
shader_type spatial;

#include "res://shaders/toon_light.gdshaderinc"

uniform vec2 half_size = vec2(40.0, 24.8);
uniform float box_depth = 13.2;
uniform float box_half_width = 14.0;
uniform float small_box_depth = 4.4;
uniform float small_box_half_width = 7.6;
uniform float center_radius = 6.8;
uniform float spot_distance = 8.8;
uniform float arc_radius = 6.0;
uniform float line_half_width = 0.08;
uniform float stripe_count = 12.0;
uniform vec4 grass_a : source_color = vec4(0.2, 0.52, 0.24, 1.0);
uniform vec4 grass_b : source_color = vec4(0.17, 0.46, 0.21, 1.0);
uniform vec4 outside : source_color = vec4(0.13, 0.36, 0.17, 1.0);
uniform vec4 line_color : source_color = vec4(0.96, 0.97, 1.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float line_mask(float dist) {
	float aa = fwidth(dist);
	return 1.0 - smoothstep(line_half_width - aa, line_half_width + aa, abs(dist));
}

float dot_mask(vec2 p, vec2 c, float r) {
	float d = length(p - c);
	float aa = fwidth(d);
	return 1.0 - smoothstep(r - aa, r + aa, d);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 q = vec2(abs(p.x), p.y);
	bool inside = abs(p.x) <= half_size.x && abs(p.y) <= half_size.y;
	float stripe = floor((p.x + half_size.x) / (2.0 * half_size.x / stripe_count));
	vec3 col = mod(stripe, 2.0) < 0.5 ? grass_a.rgb : grass_b.rgb;
	if (!inside) {
		col = outside.rgb;
	}
	// Soft large-scale variation so the grass doesn't look flat.
	col *= 0.97 + 0.03 * sin(p.x * 0.35 + sin(p.y * 0.27) * 2.0);

	float m = line_mask(sd_box(p, half_size));
	m = max(m, line_mask(p.x) * step(abs(p.y), half_size.y));
	m = max(m, line_mask(length(p) - center_radius));
	m = max(m, dot_mask(p, vec2(0.0), 0.25));
	m = max(m, line_mask(sd_box(q - vec2(half_size.x - box_depth * 0.5, 0.0), vec2(box_depth * 0.5, box_half_width))));
	m = max(m, line_mask(sd_box(q - vec2(half_size.x - small_box_depth * 0.5, 0.0), vec2(small_box_depth * 0.5, small_box_half_width))));
	vec2 spot = vec2(half_size.x - spot_distance, 0.0);
	m = max(m, dot_mask(q, spot, 0.22));
	if (q.x < half_size.x - box_depth) {
		m = max(m, line_mask(length(q - spot) - arc_radius));
	}
	ALBEDO = mix(col, line_color.rgb, m);
}
