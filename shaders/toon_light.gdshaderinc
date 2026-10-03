// Shared cel-shading light function: two hard tone bands, hard-edged shadows
// and a thin rim highlight on the lit side.
uniform vec4 shade_color : source_color = vec4(0.5, 0.54, 0.8, 1.0);
uniform float shade_threshold = 0.05;
uniform float rim_strength = 0.35;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shade_threshold - 0.02, shade_threshold + 0.02, ndl);
	lit *= smoothstep(0.4, 0.6, ATTENUATION);
	vec3 tone = mix(shade_color.rgb, vec3(1.0), lit);
	float rim = smoothstep(0.62, 0.68, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * lit * rim_strength;
	DIFFUSE_LIGHT += (tone + vec3(rim)) * LIGHT_COLOR / PI;
}
