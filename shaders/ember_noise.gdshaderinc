// Small value noise for the Glutsumpf shaders (ember ground, glow channels,
// lava, eruptions). World coordinates are wrapped so the endless map keeps full
// precision on mobile GPUs far from the origin.
float ember_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float ember_noise(vec2 p) {
	p = mod(p, 512.0);
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = ember_hash(i);
	float b = ember_hash(mod(i + vec2(1.0, 0.0), 512.0));
	float c = ember_hash(mod(i + vec2(0.0, 1.0), 512.0));
	float d = ember_hash(mod(i + vec2(1.0, 1.0), 512.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Anti-aliased thin line where `value` crosses 0.5 (half width in noise units).
float ember_line(float value, float width) {
	float distance_to_line = abs(value - 0.5);
	float w = max(fwidth(value), 1e-4);
	return 1.0 - smoothstep(width - w, width + w, distance_to_line);
}
