// Ground warning of the Brocken swing: a danger-magenta sector (pie slice)
// from `inner` to `outer` metres around local +Z, half opening `half_angle`.
// The fill grows from the body outwards with `progress` (0..1 of the wind-up);
// a bright contour framed by a dark hairline marks the exact hit edge.
// The mesh is a flat plane of 2 * (outer + margin) centred on the attacker.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float outer = 2.65;
uniform float inner = 0.6;
uniform float half_angle = 1.047;
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform vec4 fill_color : source_color = vec4(0.95, 0.21, 0.56, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.49, 0.76, 1.0);
uniform vec4 dark_color : source_color = vec4(0.23, 0.06, 0.14, 1.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX.xz;
}

void fragment() {
	float d = length(v_local);
	float a = abs(atan(v_local.x, v_local.y));
	// Distance (metres) outside the sector: negative inside.
	// half_angle >= PI: a full ring (stomp), no side edges (and no seam behind).
	float side = half_angle >= 3.14 ? -100.0 : (a - half_angle) * max(d, 0.001);
	float radial = max(d - outer, inner - d);
	float sdf = max(side, radial);
	float edge_w = 0.12;
	float hair = 0.05;
	float inside = 1.0 - smoothstep(-0.01, 0.01, sdf);
	float rim = smoothstep(-edge_w - 0.02, -edge_w, sdf) * inside;
	float dark = smoothstep(-0.005, 0.0, sdf) * (1.0 - smoothstep(hair, hair + 0.02, sdf));
	float front = mix(inner, outer, clamp(progress, 0.0, 1.0));
	float filled = inside * (1.0 - smoothstep(front - 0.04, front, d));
	// Stripes moving outwards in the empty part (reads "this is coming").
	float stripes = step(0.5, fract(d * 1.6 - TIME * 1.8)) * inside * (1.0 - filled);
	vec3 color = fill_color.rgb;
	float alpha = inside * 0.22 + stripes * 0.1 + filled * (0.38 + 0.25 * progress);
	color = mix(color, edge_color.rgb, rim);
	alpha = max(alpha, rim * (0.75 + 0.25 * progress));
	// Bright front line of the fill.
	float line = inside * (1.0 - smoothstep(0.0, 0.08, abs(d - front))) * step(0.02, progress);
	color = mix(color, vec3(1.0, 0.85, 0.95), line);
	alpha = max(alpha, line * 0.9);
	color = mix(color, dark_color.rgb, dark);
	alpha = max(alpha, dark * 0.85);
	ALBEDO = color;
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
