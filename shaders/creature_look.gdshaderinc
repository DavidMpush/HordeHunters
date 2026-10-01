// Shared fragment look of creature.gdshader and creature_anim.gdshader:
// vertex-colour albedo, optional strain tint and prop recolour, soft fake key
// light, a coloured rim, a dark silhouette contour and a hit flash.
// The includer declares OUTLINE_DEFAULT (contour strength when no script sets it).

uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform float shape_light = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.85, 0.7, 1.0);
uniform float rim_strength = 0.0;
uniform float rim_power = 2.5;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;
// Strain recolour: keeps the model's light/dark pattern, replaces its hue (alpha = amount).
uniform vec4 body_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
// Prop recolour (flowers): non-green texels are remapped by brightness onto a
// dark -> light ramp, so warm red/orange petals never compete with the swarm.
uniform vec4 recolor_dark : source_color = vec4(0.45, 0.3, 0.62, 1.0);
uniform vec4 recolor_light : source_color = vec4(1.0, 0.96, 0.84, 1.0);
uniform float recolor_amount = 0.0;
// Dark contour on grazing view angles (stage 05 readability). Same for every
// strain, so all six read against moss and sand by luminance, not only by hue.
uniform vec4 outline_color : source_color = vec4(0.06, 0.04, 0.05, 1.0);
uniform float outline_strength = OUTLINE_DEFAULT;
// Contour starts where 1 - |N.V| exceeds this (smaller = thicker line).
uniform float outline_start = 0.5;

vec3 creature_look(vec3 vertex_color, vec3 raw_normal, vec3 view, bool front_facing) {
	vec3 base = vertex_color * brightness;
	float grey = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(vec3(grey), base, saturation);
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(base, body_tint.rgb * clamp(luma * 2.4, 0.0, 1.4), body_tint.a);
	if (recolor_amount > 0.0) {
		float green = smoothstep(0.02, 0.12, base.g - max(base.r, base.b));
		vec3 ramp = mix(recolor_dark.rgb, recolor_light.rgb, smoothstep(0.08, 0.45, luma));
		base = mix(base, ramp, recolor_amount * (1.0 - green));
	}
	vec3 normal = normalize(raw_normal);
	if (!front_facing) {
		normal = -normal;
	}
	// View-space key light from upper left, facing the camera.
	float key = clamp(dot(normal, normalize(vec3(-0.35, 0.75, 0.55))) * 0.5 + 0.5, 0.0, 1.0);
	base *= mix(1.0 - shape_light, 1.0 + shape_light * 0.45, key);
	float facing = 1.0 - clamp(abs(dot(normal, view)), 0.0, 1.0);
	float rim = pow(facing, rim_power) * rim_strength;
	base = mix(base, rim_color.rgb, clamp(rim, 0.0, 1.0));
	float contour = smoothstep(outline_start, outline_start + 0.12, facing) * outline_strength;
	base = mix(base, outline_color.rgb, clamp(contour, 0.0, 1.0));
	base = mix(base, flash_color.rgb, clamp(flash, 0.0, 1.0));
	return base;
}
