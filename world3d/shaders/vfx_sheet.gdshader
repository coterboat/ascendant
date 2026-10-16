// VFX-WIRE (#242; design/STYLE_BIBLE.md §4.2): one effect sheet's frames on the 3D stage and the board (world3d/spell_fx.gd draws a
// MultiMesh of these per sheet). Normal alpha, never additive (Alex 10-13): the sheet's own alpha over the cel board.
// INSTANCE_CUSTOM.x is the frame. `ground` 1: a flat decal, its instance transform laying it on the ground, turned to its unit's facing
// (Alex 10-15); 0: a camera-facing sprite at the instance's place and size.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(4.0, 4.0);
uniform float ground = 0.0;

varying float v_frame;
varying float v_alpha;

void vertex() {
	v_frame = INSTANCE_CUSTOM.x;
	v_alpha = COLOR.a;
	if (ground < 0.5) {
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		VERTEX = vec3(VERTEX.x * sx, VERTEX.y * sy, VERTEX.z);
	}
}

void fragment() {
	float f = floor(v_frame + 0.5);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	vec4 c = texture(sheet, (cell + UV) / grid);
	ALBEDO = c.rgb;
	ALPHA = c.a * v_alpha;
}
