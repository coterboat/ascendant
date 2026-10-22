// CW-8 (#259, design/CANDLEWAKE.md §10): an army's flame on its figures' wicks, one MultiMesh an army (Armies). "Flame height is
// the flame": each instance's transform carries the height and width (CandleFigures.flame_look), and its custom data the colour (a
// lilac flame, cherry-red at the Red Wake's 4, smoke at 0, with the smoke's alpha). `flicker` sways the flame on the quality
// ladder's top rungs (never with reduced motion), from TIME and the instance id: cosmetic, never the game's dice.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float flicker = 0.0;

varying vec4 v_col;

void vertex() {
	v_col = INSTANCE_CUSTOM;
	float t = TIME * 8.0 + float(INSTANCE_ID) * 2.31;
	float k = clamp(VERTEX.y, 0.0, 1.0);
	VERTEX.x += sin(t) * 0.16 * k * flicker;
	VERTEX.z += cos(t * 1.37) * 0.16 * k * flicker;
	VERTEX.y *= 1.0 + sin(t * 1.9) * 0.1 * flicker;
}

void fragment() {
	ALBEDO = v_col.rgb * COLOR.rgb;
	ALPHA = v_col.a;
}
