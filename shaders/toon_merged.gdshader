// Merged placeholder hero (Etappe 4 Teil D): all parts that move together are
// ONE mesh, their colour is the vertex colour (Godot converts it like the
// albedo uniform of toon_part.gdshader). Same creature look as toon_part; the
// hit flash is a material uniform (one material per hero, no instance uniforms).
shader_type spatial;
render_mode unshaded, cull_back;

#define OUTLINE_DEFAULT 0.55
#include "res://shaders/creature_look.gdshaderinc"

uniform float hit_flash = 0.0;
uniform vec4 hit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec3 look = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
	ALBEDO = mix(look, hit_color.rgb, clamp(hit_flash, 0.0, 1.0));
}
