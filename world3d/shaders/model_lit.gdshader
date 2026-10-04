// Look B, "lit painted" models: the same colours under ordinary lighting, matte (Ludo's GLBs ship
// metallicFactor 1.0; this ignores it).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://world3d/shaders/model_common.gdshaderinc"

void vertex() {
	v_team = instanced_team ? INSTANCE_CUSTOM.rgb : team;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

uniform float fig_lift = 0.0;

void fragment() {
	if (cut_away() && (IN_SHADOW_PASS || ghost_drop(FRAGCOORD.xy))) {
		discard;
	}
	ALBEDO = model_albedo(COLOR, UV);
	if (fig_lift > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
		EMISSION = ALBEDO * (0.06 + rim * 0.25) * fig_lift;
	}
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
