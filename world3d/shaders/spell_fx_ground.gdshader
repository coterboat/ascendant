// The spell effects' ground decals (M5-9): rings, bands, veins and triangles lying on the ground, drawn through the depth test so a
// figure's body hides the part of a ring behind it. The marks themselves are in spell_fx.gdshaderinc.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://world3d/shaders/spell_fx.gdshaderinc"
