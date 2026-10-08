// The spell effects' sprites and beams (M5-9): flares, shields, briars, motes, eyes, moons and the beams, drawn over the figures
// (no depth test: a bolt reads the whole way from its caster in the second rank to its target). The marks themselves are in
// spell_fx.gdshaderinc.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

#include "res://world3d/shaders/spell_fx.gdshaderinc"
