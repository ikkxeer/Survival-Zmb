// Soft "toy" lighting shared by every lit surface: a smooth terminator, a soft rim
// and a small glossy highlight. Shadows are tinted by the ambient sky light.
uniform float rim_strength = 0.28;
uniform float gloss = 0.18;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.02, 0.22, ndl);
	float lit = band * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * smoothstep(0.0, 0.4, ndl) * ATTENUATION;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(0.94, 0.975, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += LIGHT_COLOR * (rim * rim_strength * (ALBEDO * 0.6 + 0.4) + spec * gloss) / PI;
}
