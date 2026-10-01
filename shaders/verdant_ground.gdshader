// Verdant Maw ground (stage 34): calm meadow in world space, one surface per
// chunk. Large soft grass tones, organic clover and dirt fields (noise
// thresholds, never circles), fine painterly grass grain, sandy paths with soft
// worn verges and lighter trodden ground in POI clearings (ground_field).
// Calmer right around the swarm so the centre of the picture stays readable.
// Lit like the old StandardMaterial ground (roughness 0.95, no specular).
// use_vertex_tint: seeded maps pass the soft region tint as vertex colour (sRGB).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/ember_noise.gdshaderinc"
#include "res://shaders/ground_field.gdshaderinc"

uniform vec4 grass_dark : source_color = vec4(0.42, 0.56, 0.25, 1.0);
uniform vec4 grass_mid : source_color = vec4(0.5, 0.63, 0.3, 1.0);
uniform vec4 grass_light : source_color = vec4(0.59, 0.71, 0.34, 1.0);
uniform vec4 clover : source_color = vec4(0.37, 0.57, 0.3, 1.0);
uniform vec4 clover_light : source_color = vec4(0.47, 0.67, 0.35, 1.0);
uniform vec4 dirt : source_color = vec4(0.62, 0.54, 0.36, 1.0);
uniform vec4 trodden : source_color = vec4(0.66, 0.69, 0.4, 1.0);
uniform vec4 path_color : source_color = vec4(0.83, 0.7, 0.47, 1.0);
uniform vec4 verge_color : source_color = vec4(0.68, 0.67, 0.38, 1.0);
uniform float clover_amount = 1.0;
uniform float dirt_amount = 1.0;
uniform bool use_vertex_tint = false;
uniform vec4 reference_color : source_color = vec4(0.5, 0.63, 0.3, 1.0);

varying vec3 world_pos;

// Two turned frames so the value-noise grid never lines up with the view.
const mat2 TURN_A = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
const mat2 TURN_B = mat2(vec2(0.28, 0.96), vec2(-0.96, 0.28));

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	vec2 wa = TURN_A * w;
	vec2 wb = TURN_B * w;
	vec4 f = ground_field(w);
	float calm = ground_calm(w);
	float quiet = mix(0.4, 1.0, calm);
	// Broad grass tones (tens of metres).
	float broad = ember_noise(wa * 0.021) * 0.6 + ember_noise(wb * 0.057 + 7.3) * 0.4;
	vec3 col = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.3, 0.5, broad));
	col = mix(col, grass_light.rgb, smoothstep(0.56, 0.78, broad));
	if (use_vertex_tint) {
		// Region tint relative to the biome ground colour (vertex colour is sRGB).
		vec3 tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
		col *= clamp(tint / max(reference_color.rgb, vec3(0.02)), vec3(0.85), vec3(1.18));
	}
	// Edge warp shared by the fields: lobed, irregular outlines.
	float warp = ember_noise(wb * 0.23 + 2.0) - 0.5;
	float grain = ember_noise(wa * 0.8 + 5.5) - 0.5;
	// Clover fields: deeper, bluer green with soft light leaf clusters.
	float clover_value = ember_noise(wa * 0.066 + 19.0) + warp * 0.24 + grain * 0.06;
	float clover_mask = smoothstep(0.72, 0.755, clover_value) * clover_amount;
	clover_mask = max(clover_mask, smoothstep(0.1, 0.45, -f.b + warp * 0.35));
	// Dirt fields: rare, small bare earth, ragged rim with grass tufts.
	float dirt_value = ember_noise(wb * 0.11 + 43.0) + warp * 0.2 + grain * 0.12;
	float dirt_mask = smoothstep(0.85, 0.89, dirt_value) * dirt_amount;
	// Bare earth never touches paths or clearings (it must not read as a path).
	dirt_mask *= smoothstep(1.2, 2.4, f.r) * (1.0 - clamp(f.b, 0.0, 1.0));
	clover_mask *= 1.0 - dirt_mask;
	float field_quiet = mix(0.65, 1.0, calm);
	float leaves = ember_noise(wa * 1.1 + 5.0) * 0.6 + ember_noise(wb * 2.3 + 1.0) * 0.4;
	vec3 clover_col = mix(clover.rgb, clover_light.rgb, smoothstep(0.45, 0.75, leaves) * mix(0.2, 0.45, detail));
	col = mix(col, clover_col, clover_mask * field_quiet);
	vec3 dirt_col = dirt.rgb * (0.9 + 0.18 * ember_noise(wa * 0.9 + 17.0));
	// Sparse grass growing back inside the earth.
	dirt_col = mix(dirt_col, col, smoothstep(0.55, 0.85, ember_noise(wb * 1.4 + 23.0)) * 0.45);
	col = mix(col, dirt_col, dirt_mask * field_quiet);
	// Trodden ground in POI clearings: lighter, drier grass with a ragged rim.
	float tread = clamp(f.b, 0.0, 1.0) * smoothstep(0.15, 0.55, f.b + warp * 0.6);
	col = mix(col, trodden.rgb, tread * 0.45);
	// Painterly grass: soft clumps (~1 m) and short blade strokes along z (the
	// camera looks north, so they read as upright blades). Low contrast.
	float clump = ember_noise(wa * 1.25 + 3.0) * 0.55 + ember_noise(wb * 2.6 + 8.0) * 0.45;
	float blade = ember_noise(vec2(w.x * 5.5, w.y * 1.9) + clump * 1.2);
	float micro = (clump - 0.5) * 0.14 + (blade - 0.5) * 0.08;
	col *= 1.0 + micro * mix(0.4, 1.0, detail) * quiet * (1.0 - dirt_mask * 0.5);
	// Paths: packed sand with soft wobbling edges and a worn verge.
	float edge = f.r + warp * 0.7 + grain * 0.25;
	float sand = 1.0 - smoothstep(-0.25, 0.25, edge);
	float verge = 1.0 - smoothstep(0.1, 1.5, edge);
	col = mix(col, mix(col, verge_color.rgb, 0.5), verge * (1.0 - sand));
	vec3 sand_col = path_color.rgb * (0.94 + 0.12 * ember_noise(wa * 1.2 + 31.0));
	// A few grass tufts creeping in from the edge.
	float tuft = smoothstep(0.62, 0.8, ember_noise(wb * 1.9 + 3.3)) * smoothstep(-1.4, -0.2, edge);
	sand_col = mix(sand_col, verge_color.rgb, tuft * 0.5);
	col = mix(col, sand_col, sand);
	// Soft contact shade under stones.
	col *= 1.0 - 0.34 * ground_contact(f.a);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
