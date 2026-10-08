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
uniform sampler2D mark_tex : filter_nearest, repeat_disable; // 16x1: r road target, g move target, b focus flash
uniform sampler2D vision_tex : filter_nearest, repeat_disable; // M5-3 16x1 R8: 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight
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
// M3a.2: a capture's sweep. Each: xy the arriving column (world), z the front's radius, w the province's
// index (-1: none). Outside the front the province still shows sweep_old (its old owner: rgb, a owned).
uniform vec4 sweep_a[4];
uniform vec4 sweep_old[4];
// M5-3 fog of war (design/M5_MAGIC_FOG.md 12.1). fog_on is 0 in a game without fog, and then the ground is untouched:
// one uniform branch, no fetch. fog_drift moves the clouds over a never-seen province (the quality ladder stops it
// from rung 3: the clouds stand still).
uniform float fog_on = 0.0;
uniform float fog_drift = 1.0;
uniform vec3 fog_veil : source_color = vec3(0.106, 0.133, 0.200); // the cool veil, the 2D map's too (#1B2233)

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
	// a province the rules turned to forest since the land was baked (the Wild Spreads): the canopy over it
	vec4 mk0 = texture(mark_tex, vec2((float(g.id) + 0.5) / 16.0, 0.5));
	if (g.id < 255 && mk0.a > 0.5) {
		col = mix(col, tf * vec3(0.92, 1.0, 0.92), 0.78 * (1.0 - smoothstep(0.3, 0.5, g.slope)));
	}
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
	// fog of war: the terrain out of sight is desaturated 70% under a cool veil at 40%, a glimpsed province has a faint
	// veil (13%, 12% drained: the spec's 10% did not read against a clear province at the whole-map zoom), a never-seen
	// one adds slow clouds. The owner's wash goes on after it and stays true (owners are public); the edges are hard, on
	// the province border, because the lookup is the province's own texel.
	float fog_out = 0.0;
	if (fog_on > 0.5 && g.id < 255) {
		float v = texture(vision_tex, vec2((float(g.id) + 0.5) / 16.0, 0.5)).r;
		fog_out = 1.0 - step(0.5, v);
		float never = 1.0 - step(0.17, v);
		float glimpsed = step(0.5, v) * (1.0 - step(0.84, v));
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(luma), (0.70 * fog_out + 0.12 * glimpsed) * sand);
		col = mix(col, fog_veil, (0.40 * fog_out + 0.13 * glimpsed) * sand);
		float cl = texture(grain_tex, mp / 64.0 + vec2(TIME * 0.011, TIME * 0.005) * fog_drift).g;
		col = mix(col, vec3(0.80, 0.84, 0.92), smoothstep(0.5, 0.85, cl) * 0.22 * never * sand);
	}
	// owners: a wash of the owner's colour inside the province's edge
	vec4 st = texture(owner_tex, vec2((float(g.id) + 0.5) / 16.0, 0.5));
	float sweep_edge = 0.0;
	for (int i = 0; i < 4; i++) {
		if (sweep_a[i].w >= 0.0 && int(sweep_a[i].w + 0.5) == g.id) {
			float sd = distance(mp, sweep_a[i].xy) - sweep_a[i].z;
			if (sd > 0.0) {
				st = sweep_old[i];
			}
			sweep_edge = max(sweep_edge, 1.0 - smoothstep(0.0, 5.0, abs(sd + 2.0)));
		}
	}
	g.owner = st.rgb;
	g.owned = (g.id < 255) ? st.a : 0.0;
	if (g.owned > 0.5 && rocky < 0.5) {
		float px = max(length(fwidth(mp)), 0.05);
		float ed = min(g.bdist, max(g.coast, 0.0));
		float k = sand * (1.0 - rocky * 2.0);
		// the bible's owner tint (2.2: a 30% multiply toward the owner's colour) over the whole province,
		// a stronger wash toward its edges, and the owner's inner band at about 4 px at any zoom, with an
		// ink keyline on its inside (STYLE_BIBLE.md 8.1), so ownership reads from the whole-map zoom
		col *= mix(vec3(1.0), clamp(st.rgb * 1.25, 0.0, 1.0), 0.3 * k);
		float edge = 1.0 - smoothstep(0.0, 16.0, ed);
		col = mix(col, st.rgb, edge * edge * wash * k);
		float band = 1.0 - smoothstep(px * 4.2, px * 5.0, ed);
		float keyl = (1.0 - smoothstep(px * 5.0, px * 6.0, ed)) * smoothstep(px * 4.2, px * 5.0, ed);
		col = mix(col, st.rgb * 1.05, band * 0.85 * k);
		col = mix(col, vec3(0.102, 0.086, 0.071), keyl * 0.55 * k);
	}
	// fog of war, out of sight: fine 45 degree hatching at a constant screen size, kept off the owner's inner band
	if (fog_out > 0.5) {
		float pxh = max(length(fwidth(mp)), 0.05);
		float hh = fract((mp.x + mp.y) / (pxh * 12.0));
		float hline = smoothstep(0.0, 0.07, hh) * (1.0 - smoothstep(0.15, 0.23, hh));
		float hed = min(g.bdist, max(g.coast, 0.0));
		col = mix(col, vec3(0.102, 0.086, 0.071), hline * 0.42 * smoothstep(pxh * 5.5, pxh * 8.0, hed) * sand);
	}
	// a capture's sweep front: a gilt edge running out from the arriving column
	col = mix(col, vec3(1.0, 0.86, 0.45), sweep_edge * 0.75 * sand);
	// the board's highlights, drawn on the ground in code (STYLE_BIBLE.md 8.1: selection a white band,
	// hover a cream one, at a constant screen width inside the province's edge, its coast included)
	if (g.id < 255) {
		float pxw = max(length(fwidth(mp)), 0.05);
		float edge_d = min(g.bdist, max(g.coast, 0.0));
		vec4 mk = texture(mark_tex, vec2((float(g.id) + 0.5) / 16.0, 0.5));
		if (g.id == select_id) {
			float band = (1.0 - smoothstep(pxw * 4.0, pxw * 5.0, edge_d)) * smoothstep(pxw * 1.1, pxw * 1.7, edge_d);
			col = col * 1.10 + vec3(0.03, 0.025, 0.0);
			col = mix(col, vec3(1.0), band * 0.95);
		} else if (g.id == hover_id) {
			float band = (1.0 - smoothstep(pxw * 2.8, pxw * 3.6, edge_d)) * smoothstep(pxw * 1.1, pxw * 1.7, edge_d);
			col = col * 1.06 + vec3(0.012);
			col = mix(col, vec3(0.945, 0.925, 0.878), band * 0.8);
		}
		if (mk.r > 0.5) {
			// a King's Roads destination: a dashed gilt band over ink, inside the edge
			float band = (1.0 - smoothstep(pxw * 9.0, pxw * 10.5, edge_d)) * smoothstep(pxw * 5.5, pxw * 6.5, edge_d);
			float dash = step(0.45, fract((mp.x + mp.y) / (pxw * 20.0)));
			col = mix(col, vec3(0.102, 0.086, 0.071), band * 0.85);
			col = mix(col, vec3(0.902, 0.722, 0.306), band * dash);
		}
		if (mk.g > 0.5) {
			// a province the selected army can move to: a gilt glow inside its edge, about 16 px wide
			float glow = 1.0 - smoothstep(pxw * 2.0, pxw * 13.0, edge_d);
			col = mix(col, vec3(0.98, 0.80, 0.36), glow * glow * 0.6);
		}
		col = mix(col, vec3(1.0), mk.b * 0.4);
	}
	g.col = col;
	return g;
}
