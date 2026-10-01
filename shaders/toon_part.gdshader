// Flat-colour part of the placeholder hero (Brann): the creature look of the
// enemies (soft fake key light, warm rim, dark contour) with one albedo per
// material and a per-instance hit flash, so all parts of one colour share a
// material and every MeshInstance flashes on its own.
shader_type spatial;
render_mode unshaded, cull_back;

#define OUTLINE_DEFAULT 0.55
#include "res://shaders/creature_look.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
instance uniform float hit_flash = 0.0;
instance uniform vec4 hit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec3 look = creature_look(albedo.rgb, NORMAL, VIEW, FRONT_FACING);
	ALBEDO = mix(look, hit_color.rgb, clamp(hit_flash, 0.0, 1.0));
}
