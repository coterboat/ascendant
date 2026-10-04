// Look A, "Bright Cel": the ground in flat colour with one hard shadow tone and one highlight tone
// (a stepped light ramp), and ink keylines drawn in code on every province border and the coast.
// A wall (a border between provinces that are not neighbours) gets a heavier line.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://world3d/shaders/ground_common.gdshaderinc"

uniform vec3 ink : source_color = vec3(0.102, 0.086, 0.071);
uniform float shade = 0.58;      // the shadow tone, as a share of the lit colour
uniform float terrace = 1.0;     // 1: the light falls in hard bands
uniform vec3 shade_tint = vec3(0.86, 0.90, 1.08); // the shadow tone leans cool, as cel art does

void vertex() {
	mp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	wy = hgt(mp);
	VERTEX.y += wy;
	NORMAL = ground_normal(mp);
}

void fragment() {
	Ground g = paint_ground();
	vec3 col = g.col;
	// ink: a keyline on each province border (a halo of the owner's colour beside it), the coast
	float px = max(length(fwidth(mp)), 0.05);
	float bw = clamp(px * 1.1, 0.35, 1.6);
	float line = 1.0 - smoothstep(bw * 0.6, bw * 0.6 + px, g.bdist);
	float land = step(0.0, g.coast) * (1.0 - smoothstep(0.3, 0.5, g.slope));
	col = mix(col, ink, line * land * 0.9);
	float cline = 1.0 - smoothstep(bw * 0.9, bw * 0.9 + px, abs(g.coast));
	col = mix(col, ink, cline * 0.9);
	ALBEDO = to_linear(clamp(col, 0.0, 1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(g.n, 0.0)).xyz);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.3, 0.6, ATTENUATION);
	// bands: the shadow tone on slopes turned from the sun, a highlight on those that face it
	float lit = mix(1.0, smoothstep(0.50, 0.56, ndl), terrace) * sh;
	float hi = smoothstep(0.92, 0.95, ndl) * sh;
	float soft = clamp(ndl, 0.0, 1.0) * sh;
	float l = mix(soft, shade + (1.0 - shade) * lit + hi * 0.10, terrace);
	vec3 tint = mix(shade_tint, vec3(1.0), clamp(lit, 0.0, 1.0));
	DIFFUSE_LIGHT += LIGHT_COLOR * l * tint;
}
