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
uniform float fade = 1.0;

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

vec3 model_albedo(vec4 vcol, vec2 uv) {
	vec3 c = vcol.rgb;
	if (use_tex) {
		vec3 t = texture(albedo_tex, uv).rgb;
		if (key_hue >= 0.0) {
			vec3 hsv = rgb2hsv(t);
			float dh = abs(hsv.x - key_hue);
			dh = min(dh, 1.0 - dh);
			float key = (1.0 - smoothstep(key_width, key_width * 1.8, dh)) * smoothstep(0.30, 0.45, hsv.y) * smoothstep(0.05, 0.12, hsv.z);
			float l = dot(t, vec3(0.2126, 0.7152, 0.0722));
			float tl = max(dot(v_team, vec3(0.2126, 0.7152, 0.0722)), 0.02);
			t = mix(t, clamp(v_team * (l / tl) * 1.1, 0.0, 1.0), key);
		}
		c *= t;
	}
	c = mix(v_team, c, vcol.a);
	return c * tint;
}
