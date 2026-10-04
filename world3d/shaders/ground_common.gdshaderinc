// The ground of the 3D world map, shared by the two looks (ground_cel.gdshader, ground_lit.gdshader).
// A plane with a vertex for every cell of terrain3d.gd's heights, raised here. Its colour is painted
// from the bake: the bare ground of each terrain, the style bible's terrain tiles as grain, woods,
// roads, beaches, and each owner's colour washed in at the province's edges (drawn in code: the
// player's identity is never baked into art).

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear, repeat_disable, source_color;
uniform sampler2D weights_tex : filter_linear, repeat_disable;
uniform sampler2D data_n : filter_nearest, repeat_disable; // r: province index (255 sea)
uniform sampler2D data_l : filter_linear, repeat_disable;  // g: coast distance, b: border distance, a: wall
uniform sampler2D owner_tex : filter_nearest, repeat_disable; // 16x1: rgb owner colour, a owned
uniform sampler2D tile_plains : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_hills : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 origin = vec2(-100.0, -100.0);
uniform vec2 extent = vec2(1200.0, 800.0);
uniform float cell = 2.5;
uniform float tile_scale = 46.0;  // world units per terrain tile
uniform float tile_k = 0.55;      // how strongly the tiles' grain shows
uniform float wash = 0.42;        // owner colour at a province's edge
uniform vec3 mean_plains = vec3(0.62, 0.72, 0.36); // the tiles' mean colours (world_view.gd measures them)
uniform vec3 mean_hills = vec3(0.62, 0.55, 0.33);
uniform int hover_id = -1;
uniform int select_id = -1;

varying vec2 mp;
varying float wy;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hgt(vec2 p) {
	return textureLod(height_tex, (p - origin) / extent, 0.0).r;
}

vec3 ground_normal(vec2 p) {
	float hl = hgt(p - vec2(cell, 0.0));
	float hr = hgt(p + vec2(cell, 0.0));
	float hu = hgt(p - vec2(0.0, cell));
	float hd = hgt(p + vec2(0.0, cell));
	return normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
}

// (varyings can only be set in vertex() itself, so each shader's vertex() raises the ground:
//     mp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; wy = hgt(mp); VERTEX.y += wy; NORMAL = ground_normal(mp);)

// The painted ground in sRGB, and how much of it is road (for roughness), and what the province is.
struct Ground {
	vec3 col;      // sRGB
	float slope;
	float coast;
	float bdist;
	float wall;
	int id;
	vec3 owner;    // sRGB, the owner's colour
	float owned;
	vec3 n;        // world normal
};

Ground paint_ground() {
	Ground g;
	vec2 uv = (mp - origin) / extent;
	vec4 dn = texture(data_n, uv);
	vec4 dl = texture(data_l, uv);
	g.id = int(round(dn.r * 255.0));
	g.coast = (dl.g * 255.0 - 128.0) / 2.0;
	g.bdist = abs((dl.b * 255.0 - 128.0) / 10.0);
	g.wall = dl.a;
	g.n = ground_normal(mp);
	g.slope = 1.0 - g.n.y;
	vec4 gt = texture(ground_tex, uv);
	vec3 col = gt.rgb;
	float woods = gt.a;
	vec3 wts = texture(weights_tex, uv).rgb;
	wts /= max(dot(wts, vec3(1.0)), 0.001);
	// the bible's terrain tiles as grain: a ratio over the painted colour, two scales a little turned
	vec2 t1 = mp / tile_scale;
	vec2 t2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * mp / (tile_scale * 2.3);
	vec3 tp = mix(texture(tile_plains, t1).rgb, texture(tile_plains, t2).rgb, 0.4);
	vec3 th = mix(texture(tile_hills, t1 * 0.8).rgb, texture(tile_hills, t2).rgb, 0.4);
	vec3 tf = texture(tile_forest, mp / (tile_scale * 0.55)).rgb;
	vec3 ratio = tp / mean_plains * (wts.r + wts.g) + th / mean_hills * wts.b;
	ratio = clamp(ratio, vec3(0.55), vec3(1.5));
	float flat_n = smoothstep(0.5, 0.2, g.slope);
	col = mix(col, col * ratio, tile_k * flat_n);
	// woods: the canopy tile under the 3D trees, so a wood reads as dense from far away
	col = mix(col, tf * vec3(0.92, 1.0, 0.92), smoothstep(0.15, 0.55, woods) * 0.85);
	// rock on the steep, the walls' crests a cool grey
	vec3 gn = texture(grain_tex, mp / 21.0).rgb;
	vec3 rock = vec3(0.55, 0.52, 0.49) * (0.82 + 0.3 * gn.r);
	float on_wall = g.wall * (1.0 - smoothstep(6.0, 18.0, g.bdist));
	float rocky = max(smoothstep(0.30, 0.52, g.slope + (gn.g - 0.5) * 0.14), on_wall * smoothstep(0.1, 0.25, g.slope));
	col = mix(col, rock, rocky);
	float peak = smoothstep(62.0, 76.0, wy + (gn.b - 0.5) * 12.0);
	col = mix(col, vec3(0.93, 0.93, 0.95), peak * (1.0 - smoothstep(0.55, 0.75, g.slope)));
	// a beach where low land meets the sea; wet sand going dark under it
	float beach = (1.0 - smoothstep(2.0, 7.0 + gn.r * 4.0, g.coast)) * (1.0 - smoothstep(5.0, 10.0, wy)) * step(0.0, g.coast);
	col = mix(col, vec3(0.90, 0.82, 0.60), beach * (1.0 - rocky));
	float sand = smoothstep(-1.0, 1.0, g.coast);
	col = mix(mix(vec3(0.72, 0.66, 0.48), vec3(0.20, 0.34, 0.38), smoothstep(0.0, 16.0, -g.coast)), col, sand);
	// owners: a wash of the owner's colour inside the province's edge
	vec4 st = texture(owner_tex, vec2((float(g.id) + 0.5) / 16.0, 0.5));
	g.owner = st.rgb;
	g.owned = (g.id < 255) ? st.a : 0.0;
	if (g.owned > 0.5 && rocky < 0.5) {
		float edge = 1.0 - smoothstep(0.0, 9.0, g.bdist);
		float px = max(length(fwidth(mp)), 0.05);
		float iw = clamp(px * 3.2, 0.5, 2.6);
		float inner = 1.0 - smoothstep(iw * 0.4, iw, g.bdist);
		float k = sand * (1.0 - rocky * 2.0);
		col = mix(col, st.rgb, (edge * edge * wash + 0.05) * k);
		col = mix(col, st.rgb * 1.05, inner * 0.6 * k);
	}
	if (g.id == select_id) {
		col = col * 1.12 + vec3(0.03, 0.025, 0.0);
	}
	if (g.id == hover_id) {
		col = col * 1.07 + vec3(0.012);
	}
	g.col = col;
	return g;
}
