// The sea round the continent: one plane at height 0 out to the horizon. Its colour comes from how
// deep the ground lies under it (terrain3d.gd's heights), with surf rings at the shore. `toon` 1 is
// Look A (flat bands of colour and a white foam line), 0 is Look B (glossy, rippled).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D data_l : filter_linear, repeat_disable;
uniform sampler2D wave_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wave_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec2 origin = vec2(-100.0, -100.0);
uniform vec2 extent = vec2(1200.0, 800.0);
uniform float toon = 1.0;
uniform vec3 shallow : source_color = vec3(0.30, 0.66, 0.70);
uniform vec3 mid : source_color = vec3(0.18, 0.48, 0.58);
uniform vec3 deep : source_color = vec3(0.14, 0.31, 0.43);

varying vec2 mp;

void vertex() {
	mp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = (mp - origin) / extent;
	bool inside = uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
	float ground = inside ? texture(height_tex, uv).r : -26.0;
	float depth = max(0.0, -ground);
	float coast = inside ? (texture(data_l, uv).g * 255.0 - 128.0) / 2.0 : -80.0;
	// toon: hard bands; lit: smooth
	float d1 = mix(smoothstep(0.0, 8.0, depth), step(3.5, depth), toon);
	float d2 = mix(smoothstep(6.0, 22.0, depth), step(13.0, depth), toon);
	vec3 col = mix(mix(shallow, mid, d1), deep, d2);
	float ring = sin(-coast * 0.55 - TIME * 1.6);
	float surf = smoothstep(0.80, 0.95, ring) * smoothstep(20.0, 3.0, -coast) * (inside ? 1.0 : 0.0);
	float lap = 1.0 - smoothstep(0.0, 0.9 + 0.4 * sin(TIME * 1.7 + mp.x * 0.07), depth);
	float foam = clamp(surf * mix(0.45, 0.85, toon) + lap, 0.0, 1.0);
	foam = mix(foam, step(0.5, foam), toon);
	col = mix(col, vec3(0.96, 0.97, 0.95), foam);
	// toon: mostly flat colour (emission), so the bands keep their hue under any light
	ALBEDO = col * mix(1.0, 0.3, toon);
	EMISSION = col * 0.95 * toon;
	ALPHA = clamp(mix(0.6, 0.97, smoothstep(0.0, 6.0, depth)) + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.12, 0.7, toon);
	SPECULAR = mix(0.5, 0.15, toon);
	vec3 na = texture(wave_a, mp / 90.0 + TIME * vec2(0.012, 0.007)).rgb;
	vec3 nb = texture(wave_b, mp / 60.0 - TIME * vec2(0.008, 0.012)).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = mix(0.5, 0.15, toon);
}
