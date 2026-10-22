// CW-8 (#259, design/CANDLEWAKE.md §3.5): the soft lilac glow round each of the Wake's flames (WakeLights), so a window or a
// candle-post reads as a light and not a shape: a disc turned to the camera, fading from its middle, drawn in the instance's colour
// (custom data). It grows far out with the flames (wick_flame.gdshader's min_px), so the two keep together.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float min_px = 0.0;

varying vec4 v_col;

void vertex() {
	v_col = INSTANCE_CUSTOM;
	float s = length(MODEL_MATRIX[0].xyz);
	if (min_px > 0.0) {
		float dist = max(-(MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).z, 0.01);
		s *= clamp(min_px / max(abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / dist, 0.001), 1.0, 3.0);
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a * (1.0 - smoothstep(0.0, 1.0, r)) * (1.0 - smoothstep(0.85, 1.0, r));
}
