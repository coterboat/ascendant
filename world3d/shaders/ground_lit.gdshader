// Look B, "lit painted" (CONCURRENT-like): the same painted ground under ordinary lighting, a
// little grain in the light so it isn't plastic, the owner wash softer and no keylines.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://world3d/shaders/ground_common.gdshaderinc"

void vertex() {
	mp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	wy = hgt(mp);
	VERTEX.y += wy;
	NORMAL = ground_normal(mp);
}

void fragment() {
	Ground g = paint_ground();
	vec3 gn = texture(grain_tex, mp / 30.0).rgb;
	vec3 n = normalize(g.n + vec3(gn.r - 0.5, 0.0, gn.g - 0.5) * 0.22);
	vec3 col = g.col;
	// hollows a shade darker, the fine colour of grass: no two paces the same
	float fine = texture(grain_tex, mp / 7.0).r;
	col *= 0.92 + 0.16 * fine;
	// a soft dark seam on borders, so provinces still read without ink
	float seam = (1.0 - smoothstep(0.0, 1.6, g.bdist)) * step(0.0, g.coast);
	col = mix(col, col * 0.55, seam * 0.6);
	ALBEDO = to_linear(clamp(col, 0.0, 1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
