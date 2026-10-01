// Glutsumpf lava pool (walkable decoration, never a damage floor). Bright core,
// orange body, drifting dark crust plates and a crusted rim; the heat pulses
// slowly with a phase per pool. Radius in local units of the pool disc.
shader_type spatial;
render_mode unshaded;

#include "res://shaders/ember_noise.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 0.89, 0.48, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.6, 0.18, 1.0);
uniform vec4 crust_color : source_color = vec4(0.35, 0.13, 0.08, 1.0);
uniform float radius = 1.1;

varying vec2 local;
varying vec3 world_pos;
varying vec3 origin;

void vertex() {
	local = VERTEX.xz / radius;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	origin = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	float r = length(local);
	float flow = ember_noise(w * 0.8 + vec2(TIME * 0.14, TIME * -0.09));
	float plates = smoothstep(0.6, 0.72, ember_noise(w * 1.5 - vec2(TIME * 0.06, TIME * 0.04)));
	float phase = ember_hash(floor(origin.xz * 2.0)) * 6.2832;
	float pulse = 0.5 + 0.5 * sin(TIME * 1.4 + phase);
	float heat = 1.0 - smoothstep(0.05, 0.95, r + (flow - 0.5) * 0.35);
	vec3 color = mix(mid_color.rgb, core_color.rgb, heat * (0.7 + 0.3 * pulse));
	color = mix(color, crust_color.rgb, plates * (0.75 - 0.45 * heat));
	color = mix(color, crust_color.rgb, smoothstep(0.8, 0.98, r) * 0.85);
	ALBEDO = color * (0.92 + 0.12 * pulse);
}
