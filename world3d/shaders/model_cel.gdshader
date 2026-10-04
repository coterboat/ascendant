// Look A, "Bright Cel" models: flat colour, one hard shadow tone and one highlight tone. The ink
// outline is a second pass (outline.gdshader, an inverted hull).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://world3d/shaders/model_common.gdshaderinc"

uniform float shade = 0.56;
uniform vec3 shade_tint = vec3(0.86, 0.90, 1.08);
// M3a.2, figures only: a higher floor for the shadow tone (a face under a hat brim stays readable) and a
// soft rim at grazing angles that lifts a figure off the ground at small sizes. 0 for buildings and props.
uniform float fig_lift = 0.0;

void vertex() {
	v_team = instanced_team ? INSTANCE_CUSTOM.rgb : team;
	v_hurt = instanced_team ? clamp(1.0 - INSTANCE_CUSTOM.a, 0.0, 1.0) : 0.0;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cut_away() && (IN_SHADOW_PASS || ghost_drop(FRAGCOORD.xy))) {
		discard;
	}
	ALBEDO = model_albedo(COLOR, UV);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (fig_lift > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
		EMISSION = ALBEDO * (0.10 + rim * 0.32) * fig_lift;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.3, 0.6, ATTENUATION);
	float lit = smoothstep(0.0, 0.08, ndl) * sh;
	float hi = smoothstep(0.80, 0.84, ndl) * sh;
	vec3 tone = mix(shade_tint, vec3(1.0), lit);
	float sh_floor = mix(shade, 0.7, fig_lift);
	DIFFUSE_LIGHT += LIGHT_COLOR * (sh_floor + (1.0 - sh_floor) * lit + hi * 0.14) * tone;
}
