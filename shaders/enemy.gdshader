// Mass enemies (MultiMesh, scripts/enemies/horde.gd): the creature look of the
// Mawlings models (vertex colour, strain tint, rim, dark contour) plus three
// per-instance channels in INSTANCE_CUSTOM:
//   x = hit flash (0..1, white-hot)
//   y = wind-up glow (0..1, pulsing danger magenta: "it is about to hit")
//   z = corpse (0..1, darkens a flung body)
shader_type spatial;
render_mode unshaded, cull_disabled;

#define OUTLINE_DEFAULT 0.9
#include "res://shaders/creature_look.gdshaderinc"

uniform vec4 windup_color : source_color = vec4(1.0, 0.25, 0.6, 1.0);
uniform vec4 hit_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);

varying vec3 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	vec3 look = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float facing = 1.0 - clamp(abs(dot(n, VIEW)), 0.0, 1.0);
	float windup = clamp(v_custom.y, 0.0, 1.0);
	// Wind-up: the body warms towards magenta, the rim glows and pulses faster
	// as the strike comes closer.
	float pulse = 0.65 + 0.35 * sin(TIME * (18.0 + 30.0 * windup));
	float glow = windup * (0.35 + 0.55 * smoothstep(0.1, 0.6, facing)) * pulse;
	look = mix(look, windup_color.rgb, clamp(glow, 0.0, 0.85));
	look = mix(look, look * 0.35, clamp(v_custom.z, 0.0, 1.0));
	look = mix(look, hit_color.rgb, clamp(v_custom.x, 0.0, 1.0) * 0.85);
	ALBEDO = look;
}
