// Melee swipe (stage 3): a bright crescent that sweeps round the attacker on a
// flat plane (local +Z = strike direction). The head runs from -half_angle to
// +half_angle (mirrored with `side` = -1) as `sweep` goes 0 -> 1 and drags a
// fading tail; `fade` dims the whole arc at the end of its life. The band is
// widest in the middle of the sector (a crescent, not a ring piece) and has a
// thin dark rim so it reads on light ground too.
// The mesh is a plane of 2 * (outer + margin), centred on the attacker.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform float outer = 2.2;
uniform float inner = 1.0;
uniform float half_angle = 0.87;
uniform float sweep = 1.0;
uniform float trail = 1.6;
uniform float side = 1.0;
uniform float fade = 1.0;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.1, 0.12, 0.25, 1.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX.xz;
}

void fragment() {
	float d = length(v_local);
	float a = atan(v_local.x, v_local.y) * side;
	float span = max(half_angle, 0.01);
	// Head position along the sector (rad), the tail lags behind it.
	float head = mix(-span, span, clamp(sweep, 0.0, 1.0));
	float behind = head - a;
	float in_tail = step(0.0, behind) * (1.0 - smoothstep(trail * 0.55, trail, behind));
	float inside_sector = step(-span - 0.02, a) * step(a, span + 0.02);
	// Crescent: thick in the middle of the sector, thin at both ends.
	float along = clamp((a + span) / (2.0 * span), 0.0, 1.0);
	float thick = span >= 3.1 ? 0.8 : sin(along * 3.14159);
	float mid = mix(inner, outer, 0.6);
	float half_w = (outer - inner) * 0.5 * (0.3 + 0.7 * thick);
	float dist = abs(d - mid);
	float band = 1.0 - smoothstep(half_w * 0.85, half_w, dist);
	float rim = (1.0 - smoothstep(half_w + 0.03, half_w + 0.08, dist)) * (1.0 - band);
	float core = 1.0 - smoothstep(half_w * 0.2, half_w * 0.55, abs(d - mid - half_w * 0.2));
	float head_glow = 1.0 - smoothstep(0.0, 0.6, behind);
	float mask = in_tail * inside_sector * fade;
	vec3 colour = mix(edge_color.rgb, core_color.rgb, clamp(core + head_glow * 0.7, 0.0, 1.0));
	colour = mix(colour, rim_color.rgb, rim);
	ALBEDO = colour;
	ALPHA = clamp((band * (0.8 + 0.2 * core) + rim * 0.55) * mask, 0.0, 1.0);
}
