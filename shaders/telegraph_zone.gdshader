// Stage 2 ground warnings (Teil B, Druck), flat plane centred on the node:
//   mode 0 - landing zone (boss leap): hatched danger-magenta disc of `radius`
//            metres, a fill closing in from the edge with `progress` (0..1),
//            crosshair on the landing point, bright contour + dark hairline.
//   mode 1 - encircle ring: a dashed magenta band of `ring_width` around
//            `radius` with a GAP around local angle `gap_angle` (rad, 0 = +Z,
//            atan(x, z)); the gap is a friendly bright cyan lane with chevrons
//            running outwards ("this way out"). `gap_half` = half the gap in
//            metres (kept while the ring closes).
//   mode 2 - incoming wave lane: a magenta lane from `radius` to `lane_end`
//            metres along local +Z, `ring_width` wide, chevrons pointing back
//            at the node (the hero) and running towards him.
// Danger is always magenta (telegraph_arc.gdshader), the way out never is.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform int mode = 0;
uniform float radius = 3.4;
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform float ring_width = 1.4;
uniform float gap_angle = 0.0;
uniform float gap_half = 2.0;
uniform float lane_end = 20.0;
uniform vec4 fill_color : source_color = vec4(0.95, 0.21, 0.56, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.49, 0.76, 1.0);
uniform vec4 dark_color : source_color = vec4(0.23, 0.06, 0.14, 1.0);
uniform vec4 safe_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform vec4 safe_light : source_color = vec4(0.92, 1.0, 1.0, 1.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX.xz;
}

// 1 inside a line of width w centred on x = 0 (metres), soft 2 cm edge.
float line(float x, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.03, abs(x));
}

void fragment() {
	float d = length(v_local);
	float a = atan(v_local.x, v_local.y);
	vec3 color = fill_color.rgb;
	float alpha = 0.0;
	float p = clamp(progress, 0.0, 1.0);
	if (mode == 0) {
		float inside = 1.0 - smoothstep(radius - 0.02, radius + 0.02, d);
		// Fill closes in from the edge: when it reaches the centre, it lands.
		float front = radius * (1.0 - p);
		float filled = inside * smoothstep(front - 0.05, front, d);
		float hatch = step(0.55, fract((v_local.x + v_local.y) * 0.9 - TIME * 1.4)) * inside;
		alpha = inside * 0.16 + hatch * 0.1 + filled * (0.28 + 0.3 * p);
		float rim = line(d - radius + 0.1, 0.2) * inside;
		color = mix(color, edge_color.rgb, rim);
		alpha = max(alpha, rim * (0.8 + 0.2 * p));
		float front_line = line(d - front, 0.12) * inside * step(0.02, p);
		color = mix(color, vec3(1.0, 0.86, 0.95), front_line);
		alpha = max(alpha, front_line * 0.9);
		// Crosshair and centre ring on the landing point.
		float cross_arm = max(line(v_local.x, 0.14), line(v_local.y, 0.14)) * step(d, radius * 0.5) * step(radius * 0.16, d);
		float centre = line(d - radius * 0.14, 0.12);
		float mark = max(cross_arm, centre);
		color = mix(color, vec3(1.0, 0.9, 0.97), mark);
		alpha = max(alpha, mark * 0.9);
		float dark = line(d - radius - 0.04, 0.06);
		color = mix(color, dark_color.rgb, dark);
		alpha = max(alpha, dark * 0.85);
	} else if (mode == 2) {
		// Incoming lane: from `radius` to `lane_end` metres along local +Z,
		// `ring_width` wide; chevrons point at the node (the hero) and run in.
		float z = v_local.y;
		float x = abs(v_local.x);
		float half_w = ring_width * 0.5;
		float inside = step(radius, z) * (1.0 - smoothstep(lane_end - 1.5, lane_end, z)) * (1.0 - smoothstep(half_w - 0.02, half_w + 0.02, x));
		float chevron = step(0.55, fract((z - x * 0.9) * 0.28 + TIME * 1.4)) * inside;
		float edge = line(x - half_w + 0.08, 0.16) * inside;
		float fade_in = smoothstep(radius, radius + 2.0, z);
		alpha = (inside * 0.16 + chevron * 0.5 + edge * 0.6) * fade_in;
		color = mix(fill_color.rgb, edge_color.rgb, max(chevron, edge));
	} else {
		float rd = d - radius;
		// Angle distance to the gap direction, as metres along the ring.
		float da = abs(mod(a - gap_angle + PI, TAU) - PI);
		float along = da * max(d, 0.5);
		float in_gap = 1.0 - smoothstep(gap_half - 0.05, gap_half + 0.05, along);
		float band = line(rd, ring_width) * (1.0 - in_gap);
		// Dashes along the ring.
		float dash = step(0.4, fract(a * radius / 1.3 - TIME * 0.3));
		alpha = band * (0.22 + 0.16 * dash);
		float edges = max(line(rd - ring_width * 0.5, 0.14), line(rd + ring_width * 0.5, 0.14)) * (1.0 - in_gap);
		color = mix(color, edge_color.rgb, edges);
		alpha = max(alpha, edges * 0.85);
		float dark = max(line(rd - ring_width * 0.5 - 0.1, 0.06), line(rd + ring_width * 0.5 + 0.1, 0.06)) * (1.0 - in_gap);
		color = mix(color, dark_color.rgb, dark);
		alpha = max(alpha, dark * 0.8);
		// The way out: a bright lane from inside the ring to beyond it.
		float lane = in_gap * step(radius - 2.0, d) * (1.0 - smoothstep(radius + 3.0, radius + 3.6, d));
		// Chevron tips point outwards and run outwards: "this way out".
		float chevron = step(0.5, fract((d + along * 0.8) * 0.9 - TIME * 1.6)) * lane;
		float rails = line(along - gap_half, 0.16) * step(radius - 2.0, d) * (1.0 - smoothstep(radius + 3.0, radius + 3.6, d));
		float safe = max(lane * 0.35, max(chevron * 0.92, rails * 0.95));
		vec3 safe_tint = mix(safe_color.rgb, safe_light.rgb, rails);
		color = mix(color, safe_tint, step(0.001, safe) * step(alpha, safe + 0.001));
		alpha = max(alpha, safe);
	}
	ALBEDO = color;
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
