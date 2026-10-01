// Dürrschlund ground (stage 19, stage 34): pale ochre dunes with cool blue-grey
// troughs, thin bent wind ripples and a few bone-white flecks. World-space, so
// chunks tile seamlessly; lit like the Verdant ground (roughness 0.95, no
// specular). Never orange: the ember-red swarm must stay the strongest colour
// on the sand. Stage 34: packed-sand paths with soft edges, smoothed sand in
// POI clearings and the contact shade of stones come from the ground_field
// (one surface per chunk, no path meshes).
// use_vertex_tint: seeded maps pass the soft region tint as vertex colour (sRGB).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/ember_noise.gdshaderinc"
#include "res://shaders/ground_field.gdshaderinc"

uniform vec4 dune_light : source_color = vec4(0.9, 0.83, 0.67, 1.0);
uniform vec4 dune_shadow : source_color = vec4(0.7, 0.65, 0.56, 1.0);
uniform vec4 shadow_cool : source_color = vec4(0.56, 0.58, 0.65, 1.0);
uniform vec4 ripple : source_color = vec4(0.8, 0.71, 0.54, 1.0);
uniform float ripple_amount = 0.4;
uniform vec4 bone_fleck : source_color = vec4(0.96, 0.93, 0.85, 1.0);
uniform vec4 path_color : source_color = vec4(0.74, 0.67, 0.54, 1.0);
uniform vec4 verge_color : source_color = vec4(0.62, 0.56, 0.43, 1.0);
uniform bool use_vertex_tint = false;
uniform vec4 reference_color : source_color = vec4(0.86, 0.78, 0.62, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	vec4 f = ground_field(w);
	float calm = ground_calm(w);
	// Broad dunes: light crests, cool troughs (subtle, the swarm stays on top).
	float dune = ember_noise(w * 0.035) * 0.65 + ember_noise(w * 0.09 + 3.1) * 0.35;
	vec3 base = mix(dune_shadow.rgb, dune_light.rgb, smoothstep(0.22, 0.78, dune));
	base = mix(base, shadow_cool.rgb, (1.0 - smoothstep(0.12, 0.42, dune)) * 0.3);
	if (use_vertex_tint) {
		vec3 tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
		base *= clamp(tint / max(reference_color.rgb, vec3(0.02)), vec3(0.85), vec3(1.15));
	}
	float warp = ember_noise(w * 0.27 + 2.0) - 0.5;
	// Paths: packed sand without ripples, a darker trodden rim along the edge.
	float edge = f.r + warp * 0.7;
	float sand = 1.0 - smoothstep(-0.3, 0.3, edge);
	float rim = smoothstep(-1.1, -0.25, edge) * (1.0 - smoothstep(0.15, 0.9, edge));
	// Smoothed sand in POI clearings: fewer ripples, a touch lighter.
	float tread = clamp(f.b, 0.0, 1.0) * smoothstep(0.15, 0.55, f.b + warp * 0.6);
	// Wind ripples: thin bent stripes, fading on the dune troughs, near the swarm
	// and on the packed paths.
	float bend = ember_noise(w * 0.05) * 6.0;
	float stripe = sin(w.x * 2.2 + w.y * 0.75 + bend);
	float ripple_fade = smoothstep(0.2, 0.55, dune) * mix(0.45, 1.0, calm) * (1.0 - tread * 0.7) * mix(0.5, 1.0, detail) * (1.0 - sand);
	float ripple_mask = smoothstep(0.86, 0.99, stripe) * ripple_fade;
	base = mix(base, ripple.rgb, ripple_mask * ripple_amount * 0.55);
	// Soft shadow line on the lee side of every ripple (reads as relief).
	float lee = smoothstep(0.55, 0.8, stripe) * (1.0 - smoothstep(0.86, 0.95, stripe));
	base = mix(base, shadow_cool.rgb, lee * ripple_amount * 0.12 * ripple_fade);
	// Bone-white flecks: rare small spots.
	float fleck = smoothstep(0.9, 0.95, ember_noise(w * 2.7 + 41.0)) * smoothstep(0.55, 0.75, ember_noise(w * 0.12 + 9.0));
	base = mix(base, bone_fleck.rgb, fleck * 0.35 * detail * calm * (1.0 - sand));
	base = mix(base, dune_light.rgb, tread * 0.3);
	vec3 packed = mix(path_color.rgb, dune_light.rgb, 0.35) * (0.96 + 0.08 * ember_noise(w * 1.3 + 31.0));
	base = mix(base, packed, sand);
	base = mix(base, verge_color.rgb, rim * 0.45);
	// Soft contact shade under sandstone and bones.
	base *= 1.0 - 0.3 * ground_contact(f.a);
	ALBEDO = base;
	ROUGHNESS = 0.95;
}
