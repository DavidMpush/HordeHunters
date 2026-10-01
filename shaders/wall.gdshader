// Stage 34: continuous walls (scripts/wall_mesh.gd builds them from the wall
// field, arena_border.gd feeds them). One material for every chunk; all
// patterns live in world coordinates, so walls run on seamlessly over chunk
// borders. Three looks blended by the vertex kind weights (COLOR.rgb):
//   rock     plates on top with moss, strata and cracks on the sides
//   hedge    domed leaf clumps on top, a leafy lobed overhang on the sides
//   masonry  squared stones with mortar, slabs and a moss crown on top
// Biomes recolour them (biomes.gd "walls"): Glutsumpf = basalt with glowing
// cracks and charred thicket, Dürrschlund = banded sandstone and dry scrub.
// UV.x = depth inside the wall (rim light on the top edge), UV.y = part (side
// 0..1 foot..top, cap 2, floor -1), UV2.x = depth beyond the map edge (fog).
// See-through window as in prop_fade.gdshader: everything above fade_floor
// between the camera and the swarm is dithered away.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 rock_top : source_color = vec4(0.66, 0.65, 0.6, 1.0);
uniform vec4 rock_side : source_color = vec4(0.5, 0.48, 0.45, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.3, 0.29, 0.28, 1.0);
uniform vec4 moss : source_color = vec4(0.49, 0.6, 0.24, 1.0);
uniform float moss_amount = 0.5;
uniform float band_amount = 0.25;
uniform vec4 hedge_top : source_color = vec4(0.25, 0.48, 0.18, 1.0);
uniform vec4 hedge_light : source_color = vec4(0.45, 0.68, 0.24, 1.0);
uniform vec4 hedge_side : source_color = vec4(0.18, 0.36, 0.14, 1.0);
uniform vec4 hedge_dark : source_color = vec4(0.1, 0.2, 0.08, 1.0);
uniform vec4 stone : source_color = vec4(0.78, 0.73, 0.62, 1.0);
uniform vec4 stone_top : source_color = vec4(0.7, 0.66, 0.55, 1.0);
uniform vec4 mortar : source_color = vec4(0.4, 0.37, 0.32, 1.0);
uniform vec4 floor_color : source_color = vec4(0.16, 0.22, 0.12, 1.0);
uniform vec4 fog_color : source_color = vec4(0.16, 0.23, 0.18, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.8, 1.0);
uniform float rim_width = 0.45;
uniform float rim_strength = 0.5;
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float glow = 0.0;
uniform float time_scale = 1.0;
uniform vec3 light_dir = vec3(-0.45, 1.0, 0.45);
uniform vec3 fade_center = vec3(0.0);
uniform float fade_radius = 0.0;
uniform float fade_floor = 0.45;
uniform float fade_keep = 0.22;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n + 17.17));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// x = distance to the nearest seed, y = gap to the second (0 on cell borders),
// z = random id of the nearest cell.
vec3 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash21(i + g + 3.7);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), id);
}

// Like voronoi(), but xy = offset from the nearest seed to p (cell units),
// z = gap to the second seed, w = random id of the nearest cell.
vec4 voronoi_offset(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 best = vec2(0.0);
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = -r;
				id = hash21(i + g + 3.7);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec4(best, sqrt(d2) - sqrt(d1), id);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int index = q.x + q.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

// Thin glowing crack lines (Glutsumpf), pulsing slowly.
float cracks(vec2 p) {
	vec3 v = voronoi(p * 0.55 + vec2(vnoise(p * 0.8) * 0.6));
	float line = 1.0 - smoothstep(0.0, 0.06, v.y);
	return line * smoothstep(0.35, 0.6, vnoise(p * 0.21 + 3.1));
}

vec3 rock_cap(vec2 p) {
	vec3 v = voronoi(p / 2.1 + vec2(vnoise(p * 0.5) * 0.35));
	// Every plate is tilted a little: faceted light, not a paved floor.
	vec2 tilt = vec2(hash21(vec2(v.z, 1.7)), hash21(vec2(v.z, 8.3))) - 0.5;
	vec3 facet = normalize(vec3(tilt.x * 0.9, 1.0, tilt.y * 0.9));
	float lit = dot(facet, normalize(light_dir));
	vec3 c = rock_top.rgb * (0.62 + 0.5 * lit) * (0.94 + 0.12 * vnoise(p * 2.9));
	c = mix(c, rock_dark.rgb, (1.0 - smoothstep(0.0, 0.05, v.y)) * 0.65);
	float m = smoothstep(0.52, 0.66, vnoise(p * 0.33) * 0.7 + vnoise(p * 1.4) * 0.3 + (moss_amount - 0.5) * 0.4);
	c = mix(c, moss.rgb * (0.85 + 0.3 * vnoise(p * 3.1)), m * step(0.01, moss_amount));
	return c;
}

// q = (along, height), h = height share of the side (0 foot .. 1 top).
vec3 rock_wall(vec2 q, float h) {
	float warp = vnoise(q * vec2(0.35, 0.9)) * 0.5;
	float band = fract((q.y + warp) * 1.6);
	vec3 c = rock_side.rgb * (0.9 + 0.2 * vnoise(vec2(q.x * 0.5, floor((q.y + warp) * 1.6))));
	c = mix(c, rock_top.rgb * 0.95, smoothstep(0.75, 0.95, band) * band_amount * 2.0);
	c = mix(c, rock_dark.rgb, (1.0 - smoothstep(0.0, 0.08, band)) * 0.55);
	vec3 v = voronoi(q * vec2(0.8, 0.45));
	c = mix(c, rock_dark.rgb, (1.0 - smoothstep(0.0, 0.06, v.y)) * 0.6);
	return c;
}

// Round clumps of foliage (a hemisphere per Voronoi cell, lit from light_dir)
// with smaller leaf tufts on them.
float clump(vec2 p, float scale, out float gap) {
	vec4 v = voronoi_offset(p / scale + vec2(vnoise(p * 0.7) * 0.3));
	// Offset in clump radii (cells are ~0.6 wide): a full hemisphere per clump.
	vec2 o = v.xy / (0.55 + 0.15 * v.w);
	float d2 = dot(o, o);
	float h = sqrt(max(0.0, 1.0 - d2));
	vec3 n = normalize(vec3(o.x, h + 0.35, o.y));
	gap = v.z;
	float lit = clamp(dot(n, normalize(light_dir)), 0.0, 1.0);
	// Clump edges sink into shade (ambient occlusion between the clumps).
	return lit * mix(0.45, 1.0, smoothstep(0.0, 0.6, h)) * (0.9 + 0.2 * v.w);
}

vec3 hedge_cap(vec2 p) {
	float gap_big;
	float gap_small;
	float big = clump(p, 1.5, gap_big);
	float small = clump(p + 5.3, 0.55, gap_small);
	float lit = big * 0.65 + small * 0.35;
	vec3 c = mix(hedge_dark.rgb, hedge_top.rgb, smoothstep(0.1, 0.6, lit));
	c = mix(c, hedge_light.rgb, smoothstep(0.66, 0.95, lit));
	return c;
}

vec3 hedge_wall(vec2 q, float h) {
	float gap;
	float lit = clump(q * vec2(1.0, 1.3), 0.7, gap);
	vec3 c = mix(hedge_dark.rgb, hedge_side.rgb, smoothstep(0.05, 0.6, lit));
	c = mix(c, hedge_top.rgb, smoothstep(0.7, 1.0, lit) * 0.5);
	// Leafy overhang: the canopy spills over the top of the side in lobes.
	float lobe = voronoi(vec2(q.x * 1.3, 0.5)).x;
	float spill = 1.0 - smoothstep(0.0, 0.03, (1.0 - h) - (0.12 + 0.22 * (1.0 - lobe)));
	c = mix(c, mix(hedge_top.rgb, hedge_light.rgb, 0.35), spill);
	return c;
}

vec3 masonry_cap(vec2 p) {
	vec2 s = p / vec2(1.3, 1.0);
	float row = floor(s.y);
	s.x += mod(row, 2.0) * 0.5;
	vec2 f = fract(s);
	float seam = min(min(f.x, 1.0 - f.x) * 1.3, min(f.y, 1.0 - f.y));
	vec3 c = stone_top.rgb * (0.88 + 0.22 * hash21(floor(s) + 7.0));
	c = mix(mortar.rgb, c, smoothstep(0.03, 0.07, seam));
	float m = smoothstep(0.45, 0.62, vnoise(p * 0.45) * 0.75 + vnoise(p * 1.7) * 0.25);
	c = mix(c, moss.rgb * (0.85 + 0.3 * vnoise(p * 2.7)), m * moss_amount);
	return c;
}

vec3 masonry_wall(vec2 q, float h) {
	vec2 s = q / vec2(0.95, 0.42);
	float row = floor(s.y);
	s.x += mod(row, 2.0) * 0.5 + hash21(vec2(row, 1.3)) * 0.3;
	vec2 f = fract(s);
	float seam = min(min(f.x, 1.0 - f.x) * 0.95, min(f.y, 1.0 - f.y) * 0.42);
	vec3 c = stone.rgb * (0.84 + 0.28 * hash21(floor(s)));
	// Soft bevel: stones lighter at their top edge.
	c *= 0.94 + 0.12 * smoothstep(0.3, 0.9, f.y);
	c = mix(mortar.rgb, c, smoothstep(0.018, 0.045, seam));
	return c;
}

void fragment() {
	vec3 w = COLOR.rgb;
	float total = w.r + w.g + w.b;
	w = total > 0.001 ? w / total : vec3(1.0, 0.0, 0.0);
	float part = UV.y;
	float depth = UV.x;
	vec3 n = normalize(world_normal);
	vec2 p = world_position.xz;
	vec3 color;
	if (part < -0.5) {
		// Dark floor under the wall (seen through the see-through window).
		color = floor_color.rgb * (0.85 + 0.2 * vnoise(p * 0.7));
	} else {
		if (fade_radius > 0.0 && world_position.y > fade_floor) {
			vec4 centre_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(fade_center + vec3(0.0, 0.5, 0.0), 1.0);
			vec4 ring_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(fade_center + vec3(fade_radius, 0.5, 0.0), 1.0);
			vec2 centre_ndc = centre_clip.xy / centre_clip.w;
			vec2 ring_ndc = ring_clip.xy / ring_clip.w;
			vec2 frag_ndc = (FRAGCOORD.xy / VIEWPORT_SIZE) * 2.0 - 1.0;
			frag_ndc.y = -frag_ndc.y;
			float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
			vec2 offset = (frag_ndc - centre_ndc) * vec2(aspect, 1.0);
			float ring = length((ring_ndc - centre_ndc) * vec2(aspect, 1.0));
			float swarm_depth = (VIEW_MATRIX * vec4(fade_center, 1.0)).z;
			float frag_depth = (VIEW_MATRIX * vec4(world_position, 1.0)).z;
			if (frag_depth > swarm_depth + 0.5) {
				float inside = 1.0 - smoothstep(ring * 0.75, ring * 1.1, length(offset));
				float height = smoothstep(fade_floor, fade_floor + 0.6, world_position.y);
				if (bayer4(FRAGCOORD.xy) > mix(1.0, fade_keep, inside * height)) {
					discard;
				}
			}
		}
		if (part > 1.5) {
			color = vec3(0.0);
			if (w.r > 0.01) { color += w.r * rock_cap(p); }
			if (w.g > 0.01) { color += w.g * hedge_cap(p); }
			if (w.b > 0.01) { color += w.b * masonry_cap(p); }
			// Rim light along the top edge; hedges get a lobed, leafy rim.
			float lobe = voronoi(p / 0.8).x;
			float width = rim_width * (1.0 + w.g * (0.9 * lobe - 0.3));
			float rim = 1.0 - smoothstep(0.0, width, depth);
			color = mix(color, color * 0.55 + rim_color.rgb * 0.6, rim * rim_strength);
			// Wide wall tops settle a little darker inside.
			color *= 1.0 - 0.16 * smoothstep(2.5, 9.0, depth);
		} else {
			float h = clamp(part, 0.0, 1.0);
			// Two planar projections blended by the facing (seamless on curves).
			float bx = abs(n.x);
			float bz = abs(n.z);
			float sum = max(bx + bz, 0.001);
			vec2 qz = vec2(world_position.x, world_position.y);
			vec2 qx = vec2(world_position.z, world_position.y);
			color = vec3(0.0);
			if (w.r > 0.01) { color += w.r * (rock_wall(qz, h) * bz + rock_wall(qx + 31.0, h) * bx) / sum; }
			if (w.g > 0.01) { color += w.g * (hedge_wall(qz, h) * bz + hedge_wall(qx + 17.0, h) * bx) / sum; }
			if (w.b > 0.01) { color += w.b * (masonry_wall(qz, h) * bz + masonry_wall(qx + 5.0, h) * bx) / sum; }
			// Foot in shade, a bright lip at the top.
			color *= mix(0.62, 1.0, smoothstep(0.0, 0.45, h));
			color = mix(color, color * 0.6 + rim_color.rgb * 0.45, smoothstep(0.9, 1.0, h) * rim_strength * 0.7);
		}
		float light = clamp(dot(n, normalize(light_dir)), 0.0, 1.0);
		color *= 0.64 + 0.46 * light;
		if (glow > 0.0) {
			vec2 cp = part > 1.5 ? p : vec2(p.x + p.y, world_position.y * 2.0);
			float pulse = 0.75 + 0.25 * sin(TIME * 1.3 * time_scale + vnoise(p * 0.1) * 6.28);
			color += glow_color.rgb * cracks(cp) * glow * pulse * (1.0 - w.g * 0.6);
		}
	}
	// Beyond the map edge the wall sinks into the fog.
	color = mix(color, fog_color.rgb, smoothstep(1.5, 16.0, UV2.x) * 0.9);
	ALBEDO = color;
}
