// A banner in the player's colour with the seat's emblem (circle for Player 1, square for
// Player 2: style bible 1.1), rippling in the wind. Drawn in code; never baked into art.
// UV.x 0 at the staff, 1 at the fly. `cel` 1: flat with a hard fold shadow.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec3 colour : source_color = vec3(0.847, 0.263, 0.173);
uniform int emblem = 0; // 0 circle, 1 square, 2 triangle, 3 diamond
uniform float cel = 1.0;
uniform float phase = 0.0;
uniform float wind = 1.0;

varying float fold;

void vertex() {
	float k = UV.x;
	float w = sin(UV.x * 6.0 - TIME * 4.5 + phase) * k * wind;
	VERTEX.z += w * 0.35;
	VERTEX.y -= k * k * 0.15 * wind;
	fold = w;
}

float emblem_mask(vec2 p) {
	vec2 q = p - vec2(0.55, 0.5);
	q.y *= 0.8;
	float r = 0.0;
	if (emblem == 0) {
		r = length(q) - 0.2;
	} else if (emblem == 1) {
		vec2 d = abs(q) - vec2(0.17);
		r = max(d.x, d.y);
	} else if (emblem == 2) {
		r = max(abs(q.x) * 0.866 + q.y * 0.5, -q.y) - 0.12;
	} else {
		r = abs(q.x) + abs(q.y) - 0.22;
	}
	return r;
}

void fragment() {
	float r = emblem_mask(UV);
	float aa = fwidth(r);
	vec3 c = colour;
	vec3 halo = vec3(0.957, 0.941, 0.910);
	vec3 ink = vec3(0.102, 0.086, 0.071);
	c = mix(c, ink, 1.0 - smoothstep(0.0, aa, abs(r + 0.035) - 0.02));
	c = mix(c, halo, 1.0 - smoothstep(-aa, aa, r + 0.055));
	// a hoist stripe so even a dark colour reads against the sky; an ink edge round the cloth
	float edge = max(max(1.0 - smoothstep(0.0, 0.05, UV.y), smoothstep(0.95, 1.0, UV.y)), smoothstep(0.96, 1.0, UV.x));
	c = mix(c, ink, edge * 0.9);
	float f = mix(0.85 + 0.25 * fold, mix(0.8, 1.0, step(0.0, fold + 0.02)), cel);
	ALBEDO = c * f;
	ROUGHNESS = 0.9;
}
