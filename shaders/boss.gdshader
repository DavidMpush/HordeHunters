// Moorkönig (scripts/enemies/boss_king.gd): the creature look of the Mawlings
// models plus a danger-magenta wind-up glow (`windup` 0..1, pulsing faster as
// the attack comes closer) and the hit flash of creature_look (`flash`).
shader_type spatial;
render_mode unshaded, cull_disabled;

#define OUTLINE_DEFAULT 0.9
#include "res://shaders/creature_look.gdshaderinc"

uniform vec4 windup_color : source_color = vec4(1.0, 0.25, 0.6, 1.0);
uniform float windup = 0.0;

void fragment() {
	vec3 look = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float facing = 1.0 - clamp(abs(dot(n, VIEW)), 0.0, 1.0);
	float w = clamp(windup, 0.0, 1.0);
	float pulse = 0.65 + 0.35 * sin(TIME * (14.0 + 26.0 * w));
	float glow = w * (0.25 + 0.6 * smoothstep(0.1, 0.6, facing)) * pulse;
	ALBEDO = mix(look, windup_color.rgb, clamp(glow, 0.0, 0.8));
}
