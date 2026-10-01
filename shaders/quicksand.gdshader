// Quicksand patch (stage 19, Dürrschlund): a darker, damp sand disc with a
// slowly turning spiral that trickles towards the centre and a soft rim. Flat,
// walkable decoration of a hazard that only slows (never lethal). Unit disc in
// UV space: the mesh is a quad of 2 x 2 m scaled to the patch diameter.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, depth_draw_opaque;

uniform vec4 sand_color : source_color = vec4(0.72, 0.6, 0.39, 1.0);
uniform vec4 swirl_color : source_color = vec4(0.56, 0.45, 0.27, 1.0);
uniform vec4 rim_color : source_color = vec4(0.9, 0.82, 0.64, 1.0);
uniform float speed = 0.35;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	// Spiral arms drawn inwards over time (trickling sand).
	float spiral = sin(a * 3.0 + r * 11.0 + TIME * speed * 6.0);
	float arms = smoothstep(0.35, 0.95, spiral) * smoothstep(1.0, 0.25, r);
	vec3 color = mix(sand_color.rgb, swirl_color.rgb, arms * 0.75);
	// Darker, sinking centre.
	color = mix(color, swirl_color.rgb * 0.8, smoothstep(0.45, 0.0, r) * 0.55);
	// Light crumbling rim so the edge reads at phone size.
	float rim = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(0.93, 1.0, r));
	color = mix(color, rim_color.rgb, rim * 0.7);
	ALBEDO = color;
	ROUGHNESS = 0.9;
	ALPHA = 1.0 - smoothstep(0.96, 1.0, r);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
