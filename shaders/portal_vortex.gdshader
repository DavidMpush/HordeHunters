// Stage 4 Teil A: portal to the next world (scripts/world/portal.gd), after the
// Mawlings migration vortex: spiral arms turning inward towards a bright core
// in the destination biome's colours, a dark throat ring and a hold arc on the
// rim that fills while the hero stands inside. Bright centre, never magenta:
// it must never read like a danger telegraph.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 deep_color : source_color = vec4(0.16, 0.05, 0.14, 1.0);
uniform vec4 hold_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float hold = 0.0;
uniform float open = 1.0;
uniform float time = -1.0;
uniform float radius = 2.2;

varying vec2 local_m;

void vertex() {
	local_m = VERTEX.xz / radius;
}

float aa(float e, float v) {
	float w = max(fwidth(v), 1e-4);
	return smoothstep(e - w, e + w, v);
}

void fragment() {
	float t = time >= 0.0 ? time : TIME;
	vec2 p = local_m;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(p.y, p.x);
	float swirl = fract(ang / 6.2832 * 3.0 + log(max(r, 0.02)) * 1.6 + t * 0.55);
	float arm = smoothstep(0.0, 0.18, swirl) * (1.0 - smoothstep(0.42, 0.62, swirl));
	float depth = smoothstep(0.0, 0.85, r);
	vec3 color = mix(core_color.rgb, mid_color.rgb, smoothstep(0.05, 0.45, r));
	color = mix(color, deep_color.rgb, smoothstep(0.35, 0.92, r) * (1.0 - arm * 0.65));
	color = mix(color, mix(mid_color.rgb, core_color.rgb, 0.5), arm * (1.0 - depth) * 0.6);
	float glow = (1.0 - smoothstep(0.0, 0.3, r)) * (0.75 + 0.25 * sin(t * 4.0));
	color = mix(color, vec3(1.0), glow * 0.45);
	float alpha = mix(0.98, 0.9, depth);
	// Hold arc: fills clockwise from the top while the hero stands inside.
	float a = fract(0.25 - ang / 6.2832);
	float band = aa(0.84, r) * (1.0 - aa(0.97, r));
	float filled = 1.0 - aa(hold, a);
	color = mix(color, hold_color.rgb, band * filled * step(0.001, hold));
	ALBEDO = color;
	ALPHA = clamp(alpha * open, 0.0, 1.0);
}
