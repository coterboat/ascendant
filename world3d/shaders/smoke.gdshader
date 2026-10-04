// A war camp's fire smoke (design/3D_DIRECTION.md 6.3): soft puffs that rise, drift and fade above
// each camp fire, drawn as camera-facing quads in one MultiMesh (a few instances per fire, stacked on
// the fire's point). Each puff's place in its rise loop comes from TIME and a hash of its instance id:
// cosmetic and deterministic, never the game's dice.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float rate = 0.3;    // rise loops per second
uniform float rise = 15.0;   // world units a puff climbs
uniform float grow = 5.0;    // a puff's size at the top
uniform float scale_k = 1.0; // the board's toy scale

varying float v_a;
varying float v_k;

void vertex() {
	float h = fract(sin(float(INSTANCE_ID) * 12.9898 + 4.1) * 43758.5453);
	float k = fract(TIME * rate + h);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 at = base + vec3(sin(k * 3.5 + h * 6.28) * 1.1 + k * 2.4, 1.6 + k * rise, cos(k * 2.7 + h * 6.28) * 0.8) * vec3(1.0, scale_k, 1.0);
	float s = mix(0.9, grow, k) * scale_k;
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(at, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	VERTEX *= s;
	v_a = smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.5, 1.0, k));
	v_k = k;
}

void fragment() {
	float r = length(UV - vec2(0.5));
	float puff = 1.0 - smoothstep(0.08, 0.5, r);
	ALBEDO = mix(vec3(0.95, 0.93, 0.90), vec3(0.70, 0.69, 0.68), v_k * 0.6);
	ALPHA = puff * puff * v_a * 0.55;
}
