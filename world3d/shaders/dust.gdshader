// M3c S-4 (#102): a one-shot dust burst on the 3D board (design/M3C_SIEGES.md §10.2): a siege's strike at the walls,
// a wall section collapsing at the breach, masons at work, scaffolding falling. Camera-facing quads in one MultiMesh,
// all on the burst's point; each puff's way out comes from a hash of its instance id (cosmetic and deterministic,
// never the game's dice), and `age` (0..1, set by world_view.gd step_fx) carries the whole burst.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float age = 0.0;
uniform float spread = 6.0; // how far the puffs fly out
uniform float lift = 5.0;   // how high they rise
uniform float size = 3.0;   // a puff's size at its biggest
uniform vec3 tint : source_color = vec3(0.80, 0.74, 0.64);

varying float v_a;

void vertex() {
	float h = fract(sin(float(INSTANCE_ID) * 12.9898 + 1.7) * 43758.5453);
	float h2 = fract(sin(float(INSTANCE_ID) * 78.233 + 3.1) * 43758.5453);
	float a = h * 6.2832;
	float k = 1.0 - pow(1.0 - clamp(age, 0.0, 1.0), 2.0);
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 at = base + vec3(cos(a) * spread * k * (0.45 + h2 * 0.55), lift * k * (0.35 + h2 * 0.65) + 0.8, sin(a) * spread * k * (0.45 + h2 * 0.55));
	float s = size * (0.45 + k * 0.85) * (0.7 + h2 * 0.6);
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(at, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	VERTEX *= s;
	v_a = (1.0 - smoothstep(0.5, 1.0, age)) * smoothstep(0.0, 0.06, age);
}

void fragment() {
	float r = length(UV - vec2(0.5));
	ALBEDO = tint;
	ALPHA = v_a * (1.0 - smoothstep(0.2, 0.5, r)) * 0.85;
}
