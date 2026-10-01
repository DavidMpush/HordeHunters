// Textured hero model (Hunyuan mesh, e.g. Brine): the base-colour map through
// the same creature look as the placeholder parts (fake key light, warm rim,
// dark contour) plus the per-instance hit flash of toon_part.gdshader.
shader_type spatial;
render_mode unshaded, cull_back;

#define OUTLINE_DEFAULT 0.45
#include "res://shaders/creature_look.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
instance uniform float hit_flash = 0.0;
instance uniform vec4 hit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec3 look = creature_look(texture(albedo_texture, UV).rgb, NORMAL, VIEW, FRONT_FACING);
	ALBEDO = mix(look, hit_color.rgb, clamp(hit_flash, 0.0, 1.0));
}
