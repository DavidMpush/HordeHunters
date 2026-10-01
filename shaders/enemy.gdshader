// Mass enemies (MultiMesh, scripts/enemies/horde.gd): the creature look of the
// Mawlings models (vertex colour, strain tint, rim, dark contour) plus three
// per-instance channels in INSTANCE_CUSTOM:
//   x = hit flash (0..1, white-hot)
//   y = wind-up glow (0..1, pulsing danger magenta: "it is about to hit")
//   z = corpse (0..1, darkens a flung body)
//   w = champion (0..1, gold body tint with a shimmer band sweeping upwards)
shader_type spatial;
render_mode unshaded, cull_disabled;

#define OUTLINE_DEFAULT 0.9
#include "res://shaders/creature_look.gdshaderinc"

uniform vec4 windup_color : source_color = vec4(1.0, 0.25, 0.6, 1.0);
uniform vec4 hit_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform vec4 gold_color : source_color = vec4(1.0, 0.7, 0.08, 1.0);
uniform vec4 gold_light : source_color = vec4(1.0, 0.96, 0.7, 1.0);

varying vec4 v_custom;
varying float v_height;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 look = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float facing = 1.0 - clamp(abs(dot(n, VIEW)), 0.0, 1.0);
	float champion = clamp(v_custom.w, 0.0, 1.0);
	if (champion > 0.0) {
		// Gold armour look: keep the light/dark pattern, gold rim, a bright band
		// sweeping up the body every 1.4 s.
		float luma = dot(look, vec3(0.299, 0.587, 0.114));
		vec3 gold = gold_color.rgb * clamp(luma * 1.6 + 0.4, 0.0, 1.3);
		float band = smoothstep(0.25, 0.0, abs(fract(TIME * 0.7) * 3.2 - 0.4 - v_height));
		gold = mix(gold, gold_light.rgb, clamp(band * 0.7 + pow(facing, 3.0) * 0.4, 0.0, 1.0));
		look = mix(look, gold, champion * 0.9);
	}
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
