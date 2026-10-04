// Ink outline for Look A: the model drawn again, inside out, pushed out along its normals by about
// a constant width in screen pixels (thinner far away so a whole-map army doesn't go to ink).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec3 ink : source_color = vec3(0.102, 0.086, 0.071);
uniform float width_px = 2.0;
uniform float far_px = 1.0;
uniform float far_dist = 900.0;
uniform vec2 screen = vec2(1600.0, 900.0); // world_view.gd keeps it at the viewport's size
// M3a.2: the fortress close-up's cutaway (model_common.gdshaderinc), on the fortress's own outline
uniform vec4 cut_plane = vec4(0.0);
uniform float cut_y = 0.0;
varying vec3 v_world;

void vertex() {
	// how many world units a pixel spans at this vertex's distance, in model space
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = abs(view_pos.z);
	// abs: the projection's y scale is negative on some backends (Metal/Vulkan flip y)
	float px_world = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * screen.y);
	float w = mix(width_px, far_px, smoothstep(80.0, far_dist, dist));
	float model_scale = length(MODEL_MATRIX[0].xyz);
	VERTEX += normalize(NORMAL) * w * px_world / max(model_scale, 1e-4);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(cut_plane.xyz, cut_plane.xyz) > 0.25 && dot(cut_plane.xyz, v_world) > cut_plane.w && v_world.y > cut_y) {
		discard;
	}
	ALBEDO = ink;
}
