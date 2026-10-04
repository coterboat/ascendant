// Look A, "Bright Cel" models: flat colour, one hard shadow tone and one highlight tone. The ink
// outline is a second pass (outline.gdshader, an inverted hull).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://world3d/shaders/model_common.gdshaderinc"

uniform float shade = 0.56;
uniform vec3 shade_tint = vec3(0.86, 0.90, 1.08);

void vertex() {
	v_team = instanced_team ? INSTANCE_CUSTOM.rgb : team;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cut_away()) {
		discard;
	}
	ALBEDO = model_albedo(COLOR, UV);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.3, 0.6, ATTENUATION);
	float lit = smoothstep(0.0, 0.08, ndl) * sh;
	float hi = smoothstep(0.80, 0.84, ndl) * sh;
	vec3 tone = mix(shade_tint, vec3(1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * (shade + (1.0 - shade) * lit + hi * 0.14) * tone;
}
