// Stage 34: per-chunk ground field shared by the ground shaders (Verdant,
// Glutsumpf, Dürrschlund). arena.gd bakes one small RGBA half-float texture per
// chunk (1 m texels, 2 texel margin, linear filtering):
//   R = signed distance to the sand edge of the nearest path (m, - on the sand)
//   G = distance to the nearest path centre line (m; Glutsumpf glow core)
//   B = clearing weight: 0..1 trodden ground around POI clearings (seeded maps),
//       -1..0 clover / ash field of a classic landmark (meadow, fallen log)
//   A = distance to the nearest stone footprint edge (m, - under the stone)
// Without a field (has_field false) the ground is plain grass / sand / peat.
uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(0.0);
uniform float field_size = 32.0;
uniform bool has_field = false;
// Swarm centre (xz) and radius of the calmer ground around it (0 = off).
uniform vec3 calm_center = vec3(0.0);
uniform float calm_radius = 0.0;
// Quality decor density: scales fine detail (grass grain, flecks, ripples).
uniform float detail : hint_range(0.0, 1.0) = 1.0;

vec4 ground_field(vec2 w) {
	if (!has_field) {
		return vec4(8.0, 16.0, 0.0, 8.0);
	}
	return texture(field, (w - field_origin) / field_size);
}

// 0 right at the swarm, 1 outside the calm radius.
float ground_calm(vec2 w) {
	if (calm_radius <= 0.0) {
		return 1.0;
	}
	return smoothstep(calm_radius * 0.3, calm_radius, distance(w, calm_center.xz));
}

// Soft contact shade around stones (their footprint on the ground).
float ground_contact(float stone_edge) {
	return 1.0 - smoothstep(-0.3, 1.4, stone_edge);
}
