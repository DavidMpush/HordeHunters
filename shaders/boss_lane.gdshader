// Stage 4 Teil A: Sandwurm "Sandsturz" telegraph. A danger-magenta lane from
// the node along local +Z: `width` metres wide, `lane_length` metres long. The fill
// runs from the worm's end to the far end with `progress` (0..1 of the
// wind-up); chevrons point along the charge, a bright contour framed by a dark
// hairline marks the exact hit edge (same language as telegraph_arc).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float width = 3.2;
uniform float lane_length = 14.0;
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform vec4 fill_color : source_color = vec4(0.95, 0.21, 0.56, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.49, 0.76, 1.0);
uniform vec4 dark_color : source_color = vec4(0.23, 0.06, 0.14, 1.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX.xz;
}

float line(float x, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.03, abs(x));
}

void fragment() {
	float z = v_local.y;
	float x = abs(v_local.x);
	float half_w = width * 0.5;
	float inside = step(0.0, z) * step(z, lane_length) * step(x, half_w);
	float p = clamp(progress, 0.0, 1.0);
	float filled = inside * step(z, lane_length * p);
	float chevron = step(0.55, fract((z - x * 0.9) * 0.3 - TIME * 1.6)) * inside;
	float alpha = inside * 0.18 + chevron * 0.16 + filled * (0.3 + 0.3 * p);
	vec3 color = fill_color.rgb;
	float rim = max(line(x - half_w + 0.1, 0.2) * step(0.0, z) * step(z, lane_length),
		line(z - lane_length + 0.1, 0.2) * step(x, half_w));
	color = mix(color, edge_color.rgb, rim);
	alpha = max(alpha, rim * (0.8 + 0.2 * p));
	float front = line(z - lane_length * p, 0.14) * inside * step(0.02, p);
	color = mix(color, vec3(1.0, 0.86, 0.95), front);
	alpha = max(alpha, front * 0.9);
	float dark = max(line(x - half_w - 0.04, 0.06) * step(0.0, z) * step(z, lane_length + 0.07),
		line(z - lane_length - 0.04, 0.06) * step(x, half_w + 0.07));
	color = mix(color, dark_color.rgb, dark);
	alpha = max(alpha, dark * 0.85);
	ALBEDO = color;
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
