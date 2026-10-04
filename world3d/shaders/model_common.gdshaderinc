// Models (figures, fortresses, trees, houses) for both looks. Colour comes from the vertex colours
// (linear) times an optional texture (the probe's GLBs). Player identity is drawn in code:
//   * a vertex colour with alpha 0 is a "team" part (a figure's base, a banner) painted in the
//     player's colour: the uniform `team`, or each instance's custom data in a MultiMesh;
//   * `key_hue` repaints one hue range of a texture in the player's colour (the Ludo fortress's
//     blue roofs), keeping its light and shade.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_tex = false;
uniform vec3 team : source_color = vec3(0.847, 0.263, 0.173);
uniform bool instanced_team = false;
uniform float key_hue = -1.0;
uniform float key_width = 0.06;
uniform float tint = 1.0;   // a whole-model brightness (a stage's sunlit stone vs the shade)
uniform vec3 stone_tint : source_color = vec3(1.0); // a kit variant's stone (multiplies the texture, not the keyed roofs)
uniform float fade = 1.0;
// M3a.2: pale, near-neutral stone in a building (a texture's walls, or a primitive's vertex colours)
// is pulled down toward a warm grey, so Look A's bright sun doesn't blow it out or tint it pink. Only
// low-saturation texels move; roofs, timber, gold and grass keep their colour. 0 for figures.
uniform float stone_grade = 0.0;
uniform vec3 stone_grey = vec3(1.10, 1.0, 0.82); // the warm grey's balance (luminance 1)
uniform float grade_knee = 0.10; // linear luminance where the pull starts
uniform float grade_keep = 0.34; // how much of the luminance above the knee stays
// M3a.2: the fortress close-up's see-through walls. On the camera's side of the plane (xyz its normal,
// w its offset) and above cut_y, a wall is drawn as a sparse dither (a ghost of itself) and casts no
// shadow, so the gate side's walls never hide or darken the muster yard.
uniform vec4 cut_plane = vec4(0.0);
uniform float cut_y = 0.0;
varying vec3 v_world;

bool cut_away() {
	return dot(cut_plane.xyz, cut_plane.xyz) > 0.25 && dot(cut_plane.xyz, v_world) > cut_plane.w && v_world.y > cut_y;
}

// The ghost wall's dither: one pixel in three on a diagonal screen pattern is kept.
bool ghost_drop(vec2 frag) {
	ivec2 q = ivec2(frag);
	return (q.x + q.y * 2) % 3 != 0;
}

varying vec3 v_team;
varying float v_mask;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// (each shader's vertex() sets v_team: instanced_team ? INSTANCE_CUSTOM.rgb : team)

// Pale near-neutral colour -> a warm grey of compressed luminance (stone_grade), linear in and out.
vec3 grade_stone(vec3 c) {
	if (stone_grade <= 0.0) {
		return c;
	}
	vec3 hsv = rgb2hsv(c);
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float neutral = 1.0 - smoothstep(0.16, 0.34, hsv.y);
	float l2 = lum > grade_knee ? grade_knee + (lum - grade_knee) * grade_keep : lum;
	return mix(c, l2 * stone_grey, neutral * stone_grade);
}

vec3 model_albedo(vec4 vcol, vec2 uv) {
	vec3 c = vcol.rgb;
	if (use_tex) {
		vec3 t = texture(albedo_tex, uv).rgb;
		vec3 raw = t;
		t = grade_stone(t);
		t *= stone_tint;
		if (key_hue >= 0.0) {
			vec3 hsv = rgb2hsv(raw);
			float dh = abs(hsv.x - key_hue);
			dh = min(dh, 1.0 - dh);
			float key = (1.0 - smoothstep(key_width, key_width * 1.8, dh)) * smoothstep(0.30, 0.45, hsv.y) * smoothstep(0.05, 0.12, hsv.z);
			float l = dot(raw, vec3(0.2126, 0.7152, 0.0722));
			float tl = max(dot(v_team, vec3(0.2126, 0.7152, 0.0722)), 0.02);
			t = mix(t, clamp(v_team * (l / tl) * 1.1, 0.0, 1.0), key);
		}
		c *= t;
	}
	else {
		c = vcol.a > 0.5 ? grade_stone(c) : c;
		c *= stone_tint;
	}
	c = mix(v_team, c, vcol.a);
	return c * tint;
}
