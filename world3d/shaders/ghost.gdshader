// A queued recruit's ghost in the muster yard (design/3D_DIRECTION.md 6.3): the figure, translucent,
// washed toward its player's colour with a bright rim, so it reads as "not here yet". Drawn only in
// the ordering player's view.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform vec3 team : source_color = vec3(0.847, 0.263, 0.173);
uniform float alpha = 0.58;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 base = mix(COLOR.rgb, team, 0.6);
	ALBEDO = mix(base * 1.2, vec3(1.0), rim * 0.75);
	ALPHA = clamp(alpha + rim * 0.4 + 0.1 * sin(TIME * 3.0), 0.0, 1.0);
}
