// CW-8 (#259, design/CANDLEWAKE.md §10): an army's flame on its figures' wicks, one MultiMesh an army (Armies). "Flame height is
// the flame": each instance's transform carries the height and width (CandleFigures.flame_look), and its custom data the colour (a
// lilac flame, cherry-red at the Red Wake's 4, smoke at 0, with the smoke's alpha). `flicker` sways the flame on the quality
// ladder's top rungs (never with reduced motion), from TIME and the instance id: cosmetic, never the game's dice. Far out every flame
// grows about its foot by one factor, until a world unit spans `min_px` on screen (up to 3 times), fatter and a little brighter as it
// grows, so the board's far zoom still shows them and a taller flame still reads taller (0: off). The Wake's window flames and
// candle-posts (WakeLights) burn with it too.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float flicker = 0.0;
uniform float min_px = 0.0;

varying vec4 v_col;
varying float v_far;

void vertex() {
	v_col = INSTANCE_CUSTOM;
	v_far = 0.0;
	float t = TIME * 8.0 + float(INSTANCE_ID) * 2.31;
	float k = clamp(VERTEX.y, 0.0, 1.0);
	VERTEX.x += sin(t) * 0.16 * k * flicker;
	VERTEX.z += cos(t * 1.37) * 0.16 * k * flicker;
	VERTEX.y *= 1.0 + sin(t * 1.9) * 0.1 * flicker;
	if (min_px > 0.0) {
		float dist = max(-(MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).z, 0.01);
		// a world unit on screen, there (abs: the projection's y scale is negative on some backends, as outline.gdshader says)
		float px_unit = abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / dist;
		float grow = clamp(min_px / max(px_unit, 0.001), 1.0, 3.0);
		v_far = (grow - 1.0) * 0.5;
		VERTEX *= vec3(grow * (1.0 + v_far * 0.6), grow, grow * (1.0 + v_far * 0.6));
	}
}

void fragment() {
	ALBEDO = mix(v_col.rgb, min(v_col.rgb * 1.2 + 0.08, vec3(1.0)), v_far) * COLOR.rgb;
	ALPHA = v_col.a;
}
