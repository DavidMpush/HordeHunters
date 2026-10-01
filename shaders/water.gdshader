// Stage 29: lakes, moors, the desert oasis, the edge water and Glutsumpf lava
// lakes - one surface per chunk. A small field texture (one texel per 2 m NAV
// cell, aligned to the world; texel centres = the layout's cell centres)
// carries R = signed distance to the shoreline and G = signed distance to the
// deep edge (m, negative inside). G is the wall distance of the map (sampled
// bilinearly there, B-spline smoothed here: < 0.3 m apart, tests/water.gd), so
// the colour turns from light to dark where creatures stop ("collision = look"). Everything else is painted in world space (waves, glints,
// lily pads, lava flow), so neighbouring chunks meet without a seam.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/ember_noise.gdshaderinc"

uniform sampler2D field : filter_linear, repeat_disable;
// World xz of the field texture's corner and its edge length (m).
uniform vec2 field_origin = vec2(0.0);
uniform float field_size = 32.0;
uniform bool lava = false;
// Width of the mud / sand / ash rim outside the shoreline (m).
uniform float rim_width = 0.9;
uniform vec4 rim_color : source_color = vec4(0.64, 0.6, 0.39, 1.0);
uniform vec4 shallow_light : source_color = vec4(0.62, 0.86, 0.75, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.75, 0.71, 1.0);
uniform vec4 deep_color : source_color = vec4(0.12, 0.54, 0.58, 1.0);
uniform vec4 abyss_color : source_color = vec4(0.09, 0.42, 0.49, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 1.0, 0.96, 1.0);
uniform vec4 glint_color : source_color = vec4(0.85, 1.0, 0.96, 1.0);
uniform vec4 pad_color : source_color = vec4(0.37, 0.62, 0.23, 1.0);
uniform float pads = 1.0;
// Glutsumpf: walkable crust ring, lava centre (colours of lava.gdshader).
uniform vec4 crust_color : source_color = vec4(0.18, 0.14, 0.15, 1.0);
uniform vec4 crack_color : source_color = vec4(1.0, 0.54, 0.17, 1.0);
uniform vec4 lava_core : source_color = vec4(1.0, 0.89, 0.48, 1.0);
uniform vec4 lava_mid : source_color = vec4(1.0, 0.6, 0.18, 1.0);
uniform vec4 lava_crust : source_color = vec4(0.35, 0.13, 0.08, 1.0);
uniform float plate_amount = 0.8;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Flat lily pads on a jittered 2.2 m grid: a disc with a notch (0..1 coverage).
float lily(vec2 w) {
	vec2 cell = floor(w / 2.2);
	float roll = ember_hash(mod(cell, 512.0) + vec2(3.1, 7.7));
	if (roll > 0.3) {
		return 0.0;
	}
	vec2 centre = (cell + 0.25 + 0.5 * vec2(ember_hash(mod(cell, 512.0) + 11.0), ember_hash(mod(cell, 512.0) + 23.0))) * 2.2;
	vec2 d = w - centre;
	float radius = 0.36 + 0.2 * roll / 0.3;
	float r = length(d);
	float angle = atan(d.y, d.x) + roll * 40.0;
	float notch = step(0.0, cos(angle) - 0.93) * step(r, radius);
	float edge = max(fwidth(r), 0.01);
	return (1.0 - smoothstep(radius - edge, radius + edge, r)) * (1.0 - notch);
}

// Cubic B-spline weights.
vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) * (1.0 / 6.0);
}

// Bicubic field lookup from four bilinear taps: round shores instead of the
// cell-shaped corners of a plain bilinear 2 m field (needs two texels of margin).
vec2 field_at(vec2 w) {
	vec2 size = vec2(textureSize(field, 0));
	vec2 uv = (w - field_origin) / field_size * size - 0.5;
	vec2 fxy = fract(uv);
	uv -= fxy;
	vec4 xc = cubic(fxy.x);
	vec4 yc = cubic(fxy.y);
	vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 offset = (c + vec4(xc.yw, yc.yw) / s) / size.xxyy;
	vec2 s0 = texture(field, offset.xz).rg;
	vec2 s1 = texture(field, offset.yz).rg;
	vec2 s2 = texture(field, offset.xw).rg;
	vec2 s3 = texture(field, offset.yw).rg;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

void fragment() {
	vec2 w = world_pos.xz;
	vec2 f = field_at(w);
	float shore = f.r;
	float deep = f.g;
	if (shore > rim_width) {
		discard;
	}
	float aa = max(fwidth(shore), 0.02);
	float wet = 1.0 - smoothstep(-aa, aa, shore);
	// 0 on the shallow side, 1 in deep water: a crisp change right at the collision edge.
	float daa = max(fwidth(deep), 0.02);
	float drop = 1.0 - smoothstep(-daa, daa, deep);
	float into = max(-deep, 0.0);
	float n1 = ember_noise(w * 0.32 + vec2(TIME * 0.05, TIME * 0.035));
	float n2 = ember_noise(w * 0.85 + vec2(-TIME * 0.06, TIME * 0.045));
	vec3 albedo;
	vec3 glow = vec3(0.0);
	if (lava) {
		// Crust ring: dark cooled crust with thin glowing cracks, warmer near the lava.
		float cracks = ember_line(ember_noise(w * 0.55 + 7.0), 0.035) * (0.35 + 0.65 * (1.0 - smoothstep(0.0, 2.0, deep)));
		vec3 crust = crust_color.rgb * (0.85 + 0.3 * n2);
		// Lava: dark drifting plates with glowing veins between them (no large
		// orange areas next to the ember swarm), hotter and wider towards the
		// middle, a bright seam right on the edge.
		vec2 drift = vec2(TIME * 0.05, TIME * -0.035);
		vec2 turned = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * w;
		float warp = ember_noise(w * 0.21 + drift * 0.5);
		float plates = ember_noise(w * 0.3 + drift + warp * 1.7) * 0.65 + ember_noise(turned * 0.62 - drift) * 0.35;
		float heat = smoothstep(0.3, 6.0, into + (warp - 0.5) * 1.5);
		float pulse = 0.5 + 0.5 * sin(TIME * 1.3 + warp * 9.0);
		// Etappe 31: wider, brighter veins and darker plates - it glows, not caramel.
		float vein_width = 0.07 + 0.14 * heat;
		float vein = 1.0 - smoothstep(vein_width, vein_width + 0.1, abs(plates - 0.5) * 3.5);
		vec3 hot = mix(lava_mid.rgb, lava_core.rgb, heat * (0.6 + 0.4 * pulse));
		vec3 cooled = lava_crust.rgb * (0.55 + 0.3 * n2) + lava_mid.rgb * 0.05 * heat;
		// Plates stay dark (a faint ember haze only); the veins carry the glow.
		vec3 molten = mix(cooled + hot * 0.07 * (1.0 - plate_amount + heat * 0.5), hot, vein);
		// Bright seam right inside the edge, dark crust lip right outside it.
		molten = mix(molten, hot, (1.0 - smoothstep(0.0, 0.5, into)) * 0.85);
		float lip = (1.0 - smoothstep(0.0, 0.4, max(deep, 0.0))) * (1.0 - drop);
		crust *= 1.0 - 0.45 * lip;
		albedo = mix(crust, vec3(0.0), drop);
		glow = mix(crack_color.rgb * cracks * 0.9, molten * (1.1 + 0.2 * pulse), drop);
		vec3 ash = rim_color.rgb * (0.9 + 0.2 * n1);
		albedo = mix(ash, albedo, wet);
		glow *= wet;
	} else {
		// Shallow: the sandy bottom shows through at the shore, teal towards the drop.
		vec3 shallow = mix(shallow_color.rgb, shallow_light.rgb, smoothstep(0.5, 2.3, deep));
		// Deep: darker, and darker still towards the middle.
		vec3 deep_water = mix(deep_color.rgb, abyss_color.rgb, smoothstep(0.8, 7.0, into));
		// A dark ledge line right inside the drop-off, a light lip right outside it.
		deep_water *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.7, into));
		shallow = mix(shallow, shallow_light.rgb * 1.08, (1.0 - smoothstep(0.0, 0.3, max(deep, 0.0))) * 0.45);
		// Soft waves: slow brightness swell in world space.
		float swell = (n1 - 0.5) * 0.12 + (n2 - 0.5) * 0.06;
		albedo = mix(shallow, deep_water, drop) * (1.0 + swell);
		// Lily pads in the calm outer shallow band.
		float pad = pads * lily(w) * smoothstep(0.7, 1.1, deep) * (1.0 - smoothstep(-0.6, -0.35, shore));
		albedo = mix(albedo, pad_color.rgb * (0.9 + 0.25 * n2), pad);
		// Foam line along the shore, wobbling gently.
		float line = shore + 0.2 + 0.07 * sin(TIME * 1.2 + n1 * 7.0);
		float foam = (1.0 - smoothstep(0.05, 0.13, abs(line))) * (1.0 - pad);
		albedo = mix(albedo, foam_color.rgb, foam * 0.8);
		// Small sun glints drifting over the water (more over the deep part):
		// short ripple crests where two moving wave patterns meet.
		vec2 turned = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * w;
		float crest = ember_noise(w * vec2(1.1, 2.6) + vec2(TIME * 0.35, 0.0)) * ember_noise(turned * vec2(2.4, 1.2) - vec2(0.0, TIME * 0.28));
		float glint = smoothstep(0.52, 0.66, crest) * smoothstep(0.35, 0.7, n1) * (1.0 - pad) * (1.0 - foam);
		glow = glint_color.rgb * glint * (0.18 + 0.3 * drop);
		// Wet, darker rim outside the shore.
		vec3 rim = rim_color.rgb * mix(0.78, 1.0, smoothstep(0.0, rim_width, shore));
		albedo = mix(rim, albedo, wet);
		glow *= wet;
	}
	ALBEDO = albedo;
	EMISSION = glow;
	ALPHA = 1.0 - smoothstep(rim_width * 0.35, rim_width, shore);
}
