// A remembered army on a fogged board (M5-3, design/M5_MAGIC_FOG.md 12.1): a rival army the viewer saw there once and
// cannot see now. Grey-blue and translucent, in its own material, so it never passes for a queued recruit's ghost
// (ghost.gdshader: washed toward the player's colour, pulsing) or for an army that stands there. It carries no team colour
// (it is a memory, not a force) and does not pulse. `alpha` is the ghost's opacity for its age: the board sets a lower one
// for every 2 turns it has been since the army was seen (Vision.ghost_alpha).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform float alpha = 0.5;
uniform vec3 tint : source_color = vec3(0.50, 0.56, 0.68);

void fragment() {
	// a mid grey-blue with a soft top light, so each figure has a form (not a puff of smoke) and the ghost reads on a dark
	// veiled field and on a pale yard floor alike; a thin bright rim draws its edge
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = clamp(dot(n, normalize(vec3(-0.45, 0.85, 0.35))), 0.0, 1.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 base = tint * (0.55 + 0.65 * lit);
	ALBEDO = mix(base, vec3(0.88, 0.92, 1.0), rim * 0.35);
	ALPHA = clamp(alpha + rim * 0.15, 0.0, 1.0);
}
