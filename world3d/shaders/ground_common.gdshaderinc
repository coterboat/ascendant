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
// The province textures: one column per province index (the data image's red channel), Vision.WIDTH wide, the one width every
// texture and every lookup here uses (prov_u divides by the texture's own width, so no number is written twice; UX-7, 4.0).
uniform sampler2D owner_tex : filter_nearest, repeat_disable; // WIDTH x 1: rgb owner colour, a owned
uniform sampler2D mark_tex : filter_nearest, repeat_disable; // WIDTH x 1: r road target, g move target, b focus flash, a grown forest
uniform sampler2D vision_tex : filter_nearest, repeat_disable; // M5-3 WIDTH x 1 R8: 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight
// UX-7 (design/UX_WAR_TABLE.md 4.0), the map lenses (ui/map_lens.gd): lens_tex is WIDTH x 2 RGBA8, row 0 the lens tint (rgb) and its
// strength (a), row 1 the mark (r: Threat's hatch density, Magic's sigils, Sight's ring), the flag (g: Threat's amber pulse, Sight's
// dashed ring for next turn) and a = 255 where a province has an entry. lens_mode is the lens's number (0 none, 1 Owner, 2 Income,
// 3 Threat, 4 Magic, 5 Making, 6 Sight); lens_mood mutes the land under it (x drain, y lightness, z pull toward lens_tone).
uniform sampler2D lens_tex : filter_nearest, repeat_disable;
uniform int lens_mode = 0;
uniform vec4 lens_mood = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec3 lens_tone = vec3(0.5, 0.5, 0.5);
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
// one uniform branch, no fetch. fog_drift moves the glimpsed land's mist (the quality ladder stops it from rung 3: the mist
// stands still).
// UX-2 (design/UX_WAR_TABLE.md 2.2): the four looks, one per sight level, indexed by the vision texel / 85 (0 never seen, 1 out of
// sight, 2 glimpsed, 3 clear, which is never veiled). Vision.look_arrays() fills them (WorldView):
//   look_tone: rgb the veil's tint, a how far the colour is pulled to it
//   look_lift: x the look's lightness (the ground's luminance scaled by it), y the colour drained, z the terrain detail kept
//              (0: a flat parchment), w the paper grain on a flat parchment
//   look_tex:  x the mist (glimpsed land: a thin drifting mist), y the hatch (out of sight: static old-map lines)
uniform float fog_on = 0.0;
uniform float fog_drift = 1.0;
uniform vec4 look_tone[4];
uniform vec4 look_lift[4];
uniform vec4 look_tex[4];

varying vec2 mp;
varying float wy;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// The u of province `id`'s column in a province texture.
float prov_u(int id) {
	return (float(id) + 0.5) / float(textureSize(owner_tex, 0).x);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
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
	vec4 mk0 = texture(mark_tex, vec2(prov_u(g.id), 0.5));
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
	// fog of war (UX-2): each sight level is its own look, different in lightness and in texture, so it reads without colour or a
	// word. A glimpsed province is a step darker under a thin drifting mist; one out of sight is two steps darker, washed toward
	// sepia (the hatch lines go on after the owner's wash, below); a never-seen one is flat dark parchment with no terrain on it.
	// The relief of the terrain survives a look by scaling the pixel's own luminance (Vision.lit does the same sum); the owner's
	// wash goes on after and stays true (owners are public). The edges are hard, on the province border, because the lookup is
	// the province's own texel.
	float look_hatch = 0.0;
	float veil_l = 1.0;    // UX-7: the look's lightness here (1 in clear sight or without fog), for a lens drawn over the veil
	float veil_drain = 0.0;
	float veil_mist = 0.0;
	if (fog_on > 0.5 && g.id < 255) {
		float v = texture(vision_tex, vec2(prov_u(g.id), 0.5)).r;
		int li = int(floor(v * 3.0 + 0.5));
		if (li < 3) {
			vec4 tone = look_tone[li];
			vec4 lift = look_lift[li];
			vec4 tx = look_tex[li];
			veil_l = lift.x;
			veil_drain = lift.y;
			float luma0 = dot(col, vec3(0.299, 0.587, 0.114));
			vec3 lc = mix(col, vec3(luma0), lift.y);
			lc = mix(lc, tone.rgb, tone.a);
			lc *= luma0 * lift.x / max(dot(lc, vec3(0.299, 0.587, 0.114)), 0.02);
			// flat parchment: the tint itself, with a faint paper grain, as the terrain's detail goes to nothing
			float paper = texture(grain_tex, mp / 9.0).r - 0.5;
			vec3 flat_col = tone.rgb * (1.0 + paper * lift.w * 2.0);
			lc = mix(flat_col, lc, lift.z);
			// the mist: thin streaks stretched along their drift, two layers sliding past each other
			if (tx.x > 0.0) {
				float t = TIME * 0.018 * fog_drift;
				float m1 = texture(grain_tex, mp / vec2(150.0, 52.0) + vec2(t, t * 0.35)).g;
				float m2 = texture(grain_tex, mp / vec2(95.0, 34.0) + vec2(-t * 0.7, t * 0.25) + vec2(0.37, 0.61)).g;
				float mist = smoothstep(0.42, 0.74, m1 * 0.6 + m2 * 0.4);
				veil_mist = mist * tx.x * 0.55;
				lc = mix(lc, vec3(0.83, 0.88, 0.95), veil_mist);
			}
			col = mix(col, clamp(lc, 0.0, 1.0), sand);
			look_hatch = tx.y * sand;
			// a look with less detail also loses the terrain's relief in the light
			g.n = normalize(mix(g.n, vec3(0.0, 1.0, 0.0), (1.0 - lift.z) * sand));
		}
	}
	// UX-7, a lens (design/UX_WAR_TABLE.md 4.0, the compositing order): its wash or glow lies on the land, then the veil, then its hatch or
	// ring. The land under a lens is muted to the lens's mood first. The veil still reads under every lens: the lens colour is veiled as
	// the land is (its lightness scaled by the look's, its colour drained as much), the mist drifts over it, and the out-of-sight hatch,
	// the owner's band, the capture sweep and the interaction marks all go on after. With no lens (lens_mode 0) nothing here runs.
	vec4 lens_a = vec4(0.0);
	vec4 lens_b = vec4(0.0);
	vec3 lens_c = vec3(0.0);
	if (lens_mode > 0 && g.id < 255) {
		lens_a = texture(lens_tex, vec2(prov_u(g.id), 0.25));
		lens_b = texture(lens_tex, vec2(prov_u(g.id), 0.75));
		float pxl = max(length(fwidth(mp)), 0.05);
		float edl = min(g.bdist, max(g.coast, 0.0));
		float l0 = luma(col);
		vec3 mc = mix(col, vec3(l0), lens_mood.x);
		mc = mix(mc, lens_tone * (l0 / max(luma(lens_tone), 0.02)), lens_mood.z);
		col = mix(col, mc * lens_mood.y, sand);
		lens_c = lens_a.rgb * veil_l;
		lens_c = mix(lens_c, vec3(luma(lens_c)), veil_drain * 0.6);
		float lk = lens_a.a * sand;
		float inner = smoothstep(0.0, 28.0, edl);
		if (lens_mode == 1) {
			// Owner: the seat colour washed over the muted land, a thick border in it and an ink keyline inside that
			col = mix(col, lens_c, 0.62 * lk);
			float band = 1.0 - smoothstep(pxl * 7.0, pxl * 8.2, edl);
			col = mix(col, lens_c * 1.08, band * 0.9 * lk);
			float keyl = (1.0 - smoothstep(pxl * 8.2, pxl * 9.4, edl)) * smoothstep(pxl * 7.0, pxl * 8.2, edl);
			col = mix(col, vec3(0.102, 0.086, 0.071), keyl * 0.7 * lk);
		} else if (lens_mode == 2) {
			// Income: a warm glow, brightest inside the province, with a faint sheen of metal
			col = mix(col, lens_c, lk * (0.5 + 0.4 * inner));
			col += lens_c * (texture(grain_tex, mp / 13.0).g - 0.5) * 0.22 * lk;
		} else if (lens_mode == 3) {
			// Threat: a pale red-pencil wash under the hatching (drawn after the veil, below)
			col = mix(col, lens_c, lk * 0.35);
		} else if (lens_mode == 4) {
			// Magic: an ink-violet glow and sigils, a ring and a dot on a jittered grid, more of them for more at work
			col = mix(col, lens_c, lk * (0.35 + 0.45 * inner));
			vec2 cp = mp / 17.0;
			vec2 ci = floor(cp);
			float hs = fract(sin(dot(ci, vec2(12.9898, 78.233))) * 43758.5453);
			vec2 jit = vec2(fract(hs * 7.13), fract(hs * 3.71)) * 0.3 - 0.15;
			float r = length(fract(cp) - 0.5 - jit);
			float sig = clamp((1.0 - smoothstep(0.02, 0.06, abs(r - 0.22))) + (1.0 - smoothstep(0.0, 0.05, r)) * 0.8, 0.0, 1.0);
			float lit = step(hs, lens_b.r * 0.85) * inner * sand;
			col = mix(col, min(lens_c * 1.6 + vec3(0.08), vec3(1.0)), sig * lit * 0.85);
		} else if (lens_mode == 5) {
			// Making: a soft owner glow that deepens with the marks (the markers are on the plates)
			col = mix(col, lens_c, lk * (0.3 + 0.5 * inner));
		} else if (lens_mode == 6) {
			// Sight: the lantern's warm light on land a source sees, brightest at the source
			col = mix(col, lens_c, lk * 0.3);
		}
		// glimpsed land keeps its drifting mist over the lens
		col = mix(col, vec3(0.83, 0.88, 0.95), veil_mist * sand * 0.8);
	}
	// owners: a wash of the owner's colour inside the province's edge
	vec4 st = texture(owner_tex, vec2(prov_u(g.id), 0.5));
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
	// UX-7: the Owner and Making lenses' own colour replaces the owner wash; under any other lens the owner keeps only its band and keyline
	if (g.owned > 0.5 && rocky < 0.5 && lens_mode != 1 && lens_mode != 5) {
		float px = max(length(fwidth(mp)), 0.05);
		float ed = min(g.bdist, max(g.coast, 0.0));
		float k = sand * (1.0 - rocky * 2.0);
		// the bible's owner tint (2.2: a 30% multiply toward the owner's colour) over the whole province,
		// a stronger wash toward its edges, and the owner's inner band at about 4 px at any zoom, with an
		// ink keyline on its inside (STYLE_BIBLE.md 8.1), so ownership reads from the whole-map zoom
		if (lens_mode == 0) {
			col *= mix(vec3(1.0), clamp(st.rgb * 1.25, 0.0, 1.0), 0.3 * k);
			float edge = 1.0 - smoothstep(0.0, 16.0, ed);
			col = mix(col, st.rgb, edge * edge * wash * k);
		}
		float band = 1.0 - smoothstep(px * 4.2, px * 5.0, ed);
		float keyl = (1.0 - smoothstep(px * 5.0, px * 6.0, ed)) * smoothstep(px * 4.2, px * 5.0, ed);
		col = mix(col, st.rgb * 1.05, band * 0.85 * k);
		col = mix(col, vec3(0.102, 0.086, 0.071), keyl * 0.55 * k);
	}
	// fog of war, out of sight (UX-2): static hatch lines at 45 degrees and a constant screen size, like an old map's, kept off the
	// owner's inner band
	if (look_hatch > 0.0) {
		float pxh = max(length(fwidth(mp)), 0.05);
		float hh = fract((mp.x + mp.y) / (pxh * 11.0));
		float hline = smoothstep(0.0, 0.08, hh) * (1.0 - smoothstep(0.20, 0.30, hh));
		float hed = min(g.bdist, max(g.coast, 0.0));
		col = mix(col, vec3(0.102, 0.086, 0.071), hline * look_hatch * smoothstep(pxh * 5.5, pxh * 8.0, hed));
	}
	// UX-7, a lens's hatch or ring, over the veil and under the sweep and the marks (4.0, steps 5 to 7)
	if (lens_mode > 0 && g.id < 255) {
		float pxm = max(length(fwidth(mp)), 0.05);
		float edm = min(g.bdist, max(g.coast, 0.0));
		if (lens_mode == 3 && lens_b.r > 0.0) {
			// Threat: red-pencil hatching at the other 45 degrees from the veil's, denser for more strength, off the very edge
			float gap = mix(18.0, 8.0, lens_b.r);
			float th = fract((mp.x - mp.y) / (pxm * gap));
			float tl = smoothstep(0.0, 0.06, th) * (1.0 - smoothstep(0.14, 0.2, th));
			col = mix(col, vec3(0.69, 0.12, 0.16), tl * (0.4 + 0.45 * lens_b.r) * sand * smoothstep(pxm * 2.0, pxm * 4.0, edm));
		}
		if (lens_mode == 3 && lens_b.g > 0.5) {
			// Threat: your armies can get here too, an amber band inside the edge, pulsing
			float ab = (1.0 - smoothstep(pxm * 6.0, pxm * 7.5, edm)) * smoothstep(pxm * 1.0, pxm * 2.0, edm);
			col = mix(col, vec3(1.0, 0.70, 0.23), ab * (0.55 + 0.45 * sin(TIME * 3.2)) * 0.9 * sand);
		}
		if (lens_mode == 6 && lens_b.r > 0.0) {
			// Sight: a lantern ring inside the edge of land in sight, brighter nearer the source
			float rb = (1.0 - smoothstep(pxm * 5.0, pxm * 6.5, edm)) * smoothstep(pxm * 1.0, pxm * 2.0, edm);
			col = mix(col, min(lens_c * 1.3 + vec3(0.1, 0.07, 0.0), vec3(1.0)), rb * lens_b.r * sand);
		}
		if (lens_mode == 6 && lens_b.g > 0.5) {
			// Sight: next turn's sight from your queued marches, a dashed lantern ring
			float db = (1.0 - smoothstep(pxm * 5.0, pxm * 6.5, edm)) * smoothstep(pxm * 1.0, pxm * 2.0, edm);
			float dash = step(0.5, fract((mp.x + mp.y) / (pxm * 18.0)));
			col = mix(col, vec3(1.0, 0.82, 0.48), db * dash * 0.9 * sand);
		}
	}
	// a capture's sweep front: a gilt edge running out from the arriving column
	col = mix(col, vec3(1.0, 0.86, 0.45), sweep_edge * 0.75 * sand);
	// the board's highlights, drawn on the ground in code (STYLE_BIBLE.md 8.1: selection a white band,
	// hover a cream one, at a constant screen width inside the province's edge, its coast included)
	if (g.id < 255) {
		float pxw = max(length(fwidth(mp)), 0.05);
		float edge_d = min(g.bdist, max(g.coast, 0.0));
		vec4 mk = texture(mark_tex, vec2(prov_u(g.id), 0.5));
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
