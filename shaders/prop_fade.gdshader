// Stage 18c: map props (walls, trees, ruins, landmarks) with the creature look
// (creature_look.gdshaderinc) plus a see-through window: every fragment that
// lies between the camera and the swarm - on screen within the swarm's ring of
// `fade_radius` metres and nearer to the camera than the swarm - and stands
// higher than `fade_floor` is dithered away (screen-door, so it stays opaque
// and cheap). The swarm and a ring of ~6 m around it are always visible.
// arena.gd feeds `fade_center` (swarm) every frame; fade_radius 0 = off.
shader_type spatial;
render_mode unshaded, cull_disabled;

#define OUTLINE_DEFAULT 0.0
#include "res://shaders/creature_look.gdshaderinc"

uniform vec3 fade_center = vec3(0.0);
uniform float fade_radius = 0.0;
uniform float fade_floor = 0.45;
uniform float fade_keep = 0.22;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int index = q.x + q.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	if (fade_radius > 0.0 && world_position.y > fade_floor) {
		// Swarm centre and a point on its ring, both in screen space.
		vec4 centre_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(fade_center + vec3(0.0, 0.5, 0.0), 1.0);
		vec4 ring_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(fade_center + vec3(fade_radius, 0.5, 0.0), 1.0);
		vec2 centre_ndc = centre_clip.xy / centre_clip.w;
		vec2 ring_ndc = ring_clip.xy / ring_clip.w;
		vec2 frag_ndc = (FRAGCOORD.xy / VIEWPORT_SIZE) * 2.0 - 1.0;
		frag_ndc.y = -frag_ndc.y;
		float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		vec2 offset = (frag_ndc - centre_ndc) * vec2(aspect, 1.0);
		float ring = length((ring_ndc - centre_ndc) * vec2(aspect, 1.0));
		// In front of the swarm (closer to the camera) only.
		float swarm_depth = (VIEW_MATRIX * vec4(fade_center, 1.0)).z;
		float frag_depth = (VIEW_MATRIX * vec4(world_position, 1.0)).z;
		if (frag_depth > swarm_depth + 0.5) {
			float inside = 1.0 - smoothstep(ring * 0.75, ring * 1.1, length(offset));
			float height = smoothstep(fade_floor, fade_floor + 0.6, world_position.y);
			float keep = mix(1.0, fade_keep, inside * height);
			if (bayer4(FRAGCOORD.xy) > keep) {
				discard;
			}
		}
	}
	ALBEDO = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
}
