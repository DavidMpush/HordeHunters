// Glutsumpf ground (stage 09 prep, stage 34): smoky peat in two tones, pale ash
// flecks and thin glowing cracks that pulse slowly. World-space, so chunks tile
// seamlessly. Stage 34: the glow channels (paths), the ash of the clearings and
// the contact shade of stones come from the chunk's ground_field, so the whole
// ground is one surface per chunk (no channel mesh, no ash discs).
// Lit like the Verdant ground (roughness 0.95, no specular).
// use_vertex_tint: seeded maps pass the soft region tint as vertex colour (sRGB).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/ember_noise.gdshaderinc"
#include "res://shaders/ground_field.gdshaderinc"

uniform vec4 dark_color : source_color = vec4(0.27, 0.23, 0.26, 1.0);
uniform vec4 light_color : source_color = vec4(0.42, 0.35, 0.36, 1.0);
uniform vec4 ash_color : source_color = vec4(0.54, 0.5, 0.52, 1.0);
uniform vec4 vein_color : source_color = vec4(1.0, 0.54, 0.17, 1.0);
uniform float vein_amount = 0.55;
// Glow channel along the paths (was ember_channel.gdshader).
uniform vec4 crust_color : source_color = vec4(0.17, 0.13, 0.14, 1.0);
uniform vec4 rim_color : source_color = vec4(0.29, 0.23, 0.23, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.69, 0.24, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.94, 0.63, 1.0);
uniform bool use_vertex_tint = false;
uniform vec4 reference_color : source_color = vec4(0.37, 0.31, 0.33, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	vec4 f = ground_field(w);
	float calm = ground_calm(w);
	float broad = ember_noise(w * 0.085);
	float fine = ember_noise(w * 0.42 + 11.0);
	vec3 base = mix(dark_color.rgb, light_color.rgb, smoothstep(0.2, 0.85, broad * 0.72 + fine * 0.28));
	if (use_vertex_tint) {
		// Region tint relative to the biome ground colour (vertex colour is sRGB).
		vec3 tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
		base *= clamp(tint / max(reference_color.rgb, vec3(0.02)), vec3(0.8), vec3(1.25));
	}
	float warp = ember_noise(w * 0.27 + 2.0) - 0.5;
	// Ash flecks: small pale spots, mostly on the lighter peat.
	float ash = smoothstep(0.82, 0.9, ember_noise(w * 3.1 + 37.0)) * smoothstep(0.45, 0.8, broad);
	base = mix(base, ash_color.rgb, ash * 0.25 * detail * mix(0.4, 1.0, calm));
	// Pale ash drifts: organic fields instead of round ash discs; plus the ash
	// clearing of a classic landmark (field B < 0) and trodden POI clearings.
	float drift = smoothstep(0.7, 0.75, ember_noise(w * 0.05 + 23.0) + warp * 0.25);
	drift = max(drift, smoothstep(0.1, 0.45, -f.b + warp * 0.35));
	float tread = clamp(f.b, 0.0, 1.0) * smoothstep(0.15, 0.55, f.b + warp * 0.6);
	base = mix(base, mix(base, ash_color.rgb, 0.55), max(drift * 0.6, tread * 0.45));
	// Glowing cracks: thin noise contour lines, only in some zones of the map.
	float zone = smoothstep(0.5, 0.68, ember_noise(w * 0.05 + 5.0));
	float crack = ember_line(ember_noise(w * 0.21 + fine * 0.6), 0.014) * zone * mix(0.3, 1.0, calm);
	// Burnt scars: large, soft darker areas around the crack zones.
	base *= 1.0 - 0.22 * smoothstep(0.35, 0.8, zone + (fine - 0.5) * 0.4);
	float pulse = 0.72 + 0.28 * sin(TIME * 1.25 + broad * 9.0);
	vec3 albedo = mix(base, vein_color.rgb * 0.45, crack * 0.75);
	vec3 emission = vein_color.rgb * crack * vein_amount * pulse;
	// Glow channel: dark crust band with a soft ragged rim, broken glowing core.
	float edge = f.r + warp * 0.6;
	float band = 1.0 - smoothstep(0.2, 1.1, edge);
	float rim = smoothstep(-1.2, 0.8, edge);
	float grain = ember_noise(w * 1.9 + 3.0);
	vec3 crust = mix(crust_color.rgb, rim_color.rgb, rim) * (0.82 + 0.3 * grain);
	// Centre distance looked up at a jittered point: breaks the facets of the
	// 1 m field into an organic, wandering core.
	vec2 jitter = vec2(ember_noise(w * 1.3 + 4.0), ember_noise(w * 1.3 + 17.0)) - 0.5;
	float centre = ground_field(w + jitter * 1.1).g;
	float glow = (1.0 - smoothstep(0.05, 1.1, centre)) * 0.9 + 0.1 * (1.0 - smoothstep(1.0, 2.0, centre));
	float wander = ember_noise(w * 0.5 + vec2(TIME * 0.18, TIME * -0.11));
	float core = smoothstep(0.52 + 0.4 * wander, 0.72 + 0.3 * wander, glow) * band;
	float side = ember_line(ember_noise(w * 0.8 + 21.0), 0.02) * smoothstep(0.15, 0.45, glow) * (1.0 - core) * band;
	// Dimmer right under the swarm (ember-red Mawlings must not drown in glow).
	float heat = clamp(core + side * 0.7, 0.0, 1.0) * mix(0.35, 1.0, calm);
	crust = mix(crust, core_color.rgb * 0.45, smoothstep(0.35, 0.8, glow) * 0.35);
	float channel_pulse = 0.82 + 0.18 * sin(TIME * 1.7 + w.x * 0.21 + w.y * 0.17);
	vec3 hot = mix(core_color.rgb, hot_color.rgb, core * core * wander) * channel_pulse;
	albedo = mix(albedo, crust, band);
	albedo = mix(albedo, hot * 0.6, heat);
	emission = mix(emission, hot * 0.9, heat);
	// Soft contact shade under basalt.
	albedo *= 1.0 - 0.4 * ground_contact(f.a);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 0.95;
}
