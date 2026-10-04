// Look B, "lit painted" models: the same colours under ordinary lighting, matte (Ludo's GLBs ship
// metallicFactor 1.0; this ignores it).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://world3d/shaders/model_common.gdshaderinc"

void vertex() {
	v_team = instanced_team ? INSTANCE_CUSTOM.rgb : team;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cut_away()) {
		discard;
	}
	ALBEDO = model_albedo(COLOR, UV);
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
