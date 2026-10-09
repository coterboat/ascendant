// The spell and ritual effects (M5-9, design/M5_MAGIC_FOG.md §12.2, §15.3): every placeholder mark in code, in one shader.
// world3d/spell_fx.gd writes one instance per mark into a MultiMesh and puts the mark's look in the instance's custom data:
//   x: the kind (SpellPlan.KINDS), y: its intro progress 0..1 (a beam's head), z: a seed 0..1 (a sprite turns by it), w: a variant
//      (1 animates a standing decal or a pulsing rim; a beam's w picks its style)
// and its colour (alpha is its opacity, already faded by the caller). Ground decals (kinds 0-9) are flat quads on the ground,
// sprites (10-29) face the camera, beams (30+) are crossed ribbons. Nothing here is random: a mark's variety is its seed.
// Included by spell_fx_ground.gdshader (depth-tested, so a figure hides a ring at its feet) and spell_fx_top.gdshader (over the figures).

varying vec4 v_col;
varying vec4 v_cd;

// The land's heights (the ground shaders' own texture, bound by spell_fx.gd bind_ground): a ground decal's grid of vertices is laid on
// the terrain, so a ring on a slope follows it instead of sinking into it. Unbound (a test, a floor with no land) the decal stays flat.
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 origin = vec2(-100.0, -100.0);
uniform vec2 extent = vec2(1200.0, 800.0);
uniform float ground_bound = 0.0;
uniform vec3 ink : source_color = vec3(0.102, 0.086, 0.071);

void vertex() {
	v_cd = INSTANCE_CUSTOM;
	v_col = COLOR;
	if (v_cd.x < 9.5 && ground_bound > 0.5) {
		// a flat decal: its model z is the world's up (scale 1), so the vertex's lift above its centre's ground is added to z
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 c = MODEL_MATRIX[3].xyz;
		float h_here = textureLod(height_tex, (wp.xz - origin) / extent, 0.0).r;
		float h_mid = textureLod(height_tex, (c.xz - origin) / extent, 0.0).r;
		VERTEX.z += (h_here + (c.y - h_mid)) - wp.y;
	}
	if (v_cd.x > 9.5 && v_cd.x < 29.5) {
		// a camera-facing sprite: the instance's place and size, the camera's turn
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		VERTEX = vec3(VERTEX.x * sx, VERTEX.y * sy, VERTEX.z);
	}
}

float ring_shape(float r, float c, float hw) {
	return 1.0 - smoothstep(hw * 0.35, hw, abs(r - c));
}

// an upward triangle's signed distance (negative inside), in the quad's -1..1 space
float tri_d(vec2 p) {
	vec2 n1 = normalize(vec2(-1.4, 0.8));
	vec2 n2 = normalize(vec2(1.4, 0.8));
	float d1 = dot(p - vec2(0.0, 0.8), n1);
	float d2 = dot(p - vec2(0.0, 0.8), n2);
	float d3 = -(p.y + 0.6);
	return max(d1, max(d2, d3));
}

// a heater shield's signed distance (negative inside): flat top, sides tapering to a point
float shield_d(vec2 p) {
	float d = max(abs(p.x) - 0.72, p.y - 0.85);
	float taper = abs(p.x) * 1.1 + max(0.0, -p.y - 0.1) * 0.62 - 0.78;
	return max(max(d, taper), -p.y - 0.98);
}

vec2 turn(vec2 p, float a) {
	float cs = cos(a);
	float sn = sin(a);
	return vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	int kind = int(v_cd.x + 0.5);
	float u = clamp(v_cd.y, 0.0, 1.0);
	float seed = v_cd.z;
	float w = v_cd.w;
	bool anim = w > 0.5;
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec2 q = turn(p, seed * 6.2832);
	vec3 col = v_col.rgb;
	float a = 0.0;
	float a_out = -1.0; // the mark with an ink outline round it (a ground decal's keyline); -1: no outline

	if (kind == 0) {
		// ring: a plain ring on the ground with a faint fill
		a = ring_shape(r, 0.84, 0.17) + 0.12 * (1.0 - smoothstep(0.0, 0.84, r));
		a_out = ring_shape(r, 0.84, 0.25);
	} else if (kind == 1) {
		// thorn ring: a ring with thorns growing out of it (Briar Snare)
		float turnby = anim ? TIME * 0.35 : 0.0;
		float teeth = pow(0.5 + 0.5 * cos((ang + seed * 6.0 + turnby) * 14.0), 3.0);
		float rr = 0.74 + 0.2 * teeth;
		float thorn = (1.0 - smoothstep(rr - 0.05, rr, r)) * smoothstep(0.68, 0.74, r);
		a = max(ring_shape(r, 0.72, 0.12), thorn * 0.95);
		a_out = max(ring_shape(r, 0.72, 0.2), thorn * 0.95);
	} else if (kind == 2) {
		// sun ring: a gilt ring with a sun's short rays (a blessing)
		float pulse = anim ? 0.02 * sin(TIME * 2.5) : 0.0;
		float base = ring_shape(r, 0.74 + pulse, 0.11);
		float rays = step(0.55, 0.5 + 0.5 * cos(ang * 16.0 + (anim ? TIME * 0.5 : 0.0)));
		float ticks = rays * smoothstep(0.80, 0.84, r) * (1.0 - smoothstep(0.93, 0.97, r));
		a = base + ticks * 0.9 + 0.12 * (1.0 - smoothstep(0.0, 0.74, r));
		a_out = max(ring_shape(r, 0.74 + pulse, 0.17), ticks * 0.9);
	} else if (kind == 3) {
		// band: a dashed band with a hard line either side (a ward)
		float rot = anim ? TIME * 0.25 : 0.0;
		float dash = step(0.35, 0.5 + 0.5 * cos((ang + rot) * 20.0));
		float band = smoothstep(0.62, 0.70, r) * (1.0 - smoothstep(0.88, 0.95, r));
		a = band * (0.30 + 0.70 * dash) + ring_shape(r, 0.66, 0.05) * 0.95 + ring_shape(r, 0.92, 0.05) * 0.95 + 0.08 * (1.0 - smoothstep(0.0, 0.9, r));
		a_out = max(ring_shape(r, 0.66, 0.11), ring_shape(r, 0.92, 0.11));
	} else if (kind == 4) {
		// tri: a triangle on the ground under a covered fighter (Shield of Law, from rung 4)
		float d = tri_d(p);
		a = (1.0 - smoothstep(0.0, 0.10, abs(d + 0.09))) + 0.30 * (1.0 - smoothstep(-0.02, 0.02, d));
		a_out = 1.0 - smoothstep(0.0, 0.2, d + 0.02);
	} else if (kind == 5) {
		// veins: crimson veins running out of the middle of a province (a curse)
		float pulse = anim ? 0.7 + 0.3 * sin(TIME * 3.0 - r * 6.0) : 1.0;
		float v = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float k = abs(sin(ang * (3.0 + fi) + 3.0 * sin(r * (4.0 + fi * 2.0) + seed * 6.0 + fi * 1.7)));
			v = max(v, (1.0 - smoothstep(0.0, 0.17 + 0.12 * r, k)) * (1.0 - fi * 0.15));
		}
		a = (v * 0.95 * (1.0 - smoothstep(0.55, 1.0, r)) + 0.26 * (1.0 - smoothstep(0.0, 0.85, r))) * pulse;
		a_out = clamp(a + v * (1.0 - smoothstep(0.55, 1.0, r)) * 0.4, 0.0, 1.0);
	} else if (kind == 6) {
		// glare ring: a bright band at the ring's edge over a faint wash of light inside it (Sunburst's sweep)
		float band = smoothstep(0.74, 0.93, r) * (1.0 - smoothstep(0.93, 1.0, r));
		a = max(band, 0.22 * (1.0 - smoothstep(0.0, 0.93, r)) * step(r, 0.97));
		col = mix(col, vec3(1.0), 0.5 * band);
	} else if (kind == 7) {
		// dust ring: a ragged ring of dust (a fort raised)
		float rr = 0.78 + 0.08 * sin(ang * 9.0 + seed * 6.0) + 0.05 * sin(ang * 17.0);
		a = ring_shape(r, rr, 0.16) * 0.9 + 0.12 * (1.0 - smoothstep(0.0, 0.8, r));
	} else if (kind == 8) {
		// summon ring: a thorn ring round dark earth (the creatures step out of it)
		float teeth = pow(0.5 + 0.5 * cos((ang + seed * 6.0) * 16.0), 3.0);
		float rr = 0.78 + 0.18 * teeth;
		float thorn = (1.0 - smoothstep(rr - 0.05, rr, r)) * smoothstep(0.72, 0.78, r);
		float disc = 1.0 - smoothstep(0.66, 0.74, r);
		a = max(max(ring_shape(r, 0.76, 0.12), thorn), disc * 0.55);
		a_out = max(max(ring_shape(r, 0.76, 0.2), thorn), disc * 0.55);
		col = mix(col, col * 0.30, disc);
	} else if (kind == 9) {
		// fizzle ring: a ring in broken pieces (a ritual turned aside)
		float gaps = step(0.4, 0.5 + 0.5 * cos(ang * 9.0));
		a = ring_shape(r, 0.80, 0.07) * gaps;
	} else if (kind == 10) {
		// glow: a soft round glow
		a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	} else if (kind == 11) {
		// flare: a four-point flare in a white-hot glow (art: sun_flare)
		float core = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		float cross_ = pow(clamp(1.0 - 7.0 * abs(q.x * q.y), 0.0, 1.0), 2.0) * (1.0 - r * 0.8);
		a = max(core * 0.85, cross_);
		col = mix(col, vec3(1.0), clamp(core * 1.2, 0.0, 1.0));
	} else if (kind == 12) {
		// burst: a six-point starburst, white-hot at its middle (a bolt's impact sheet)
		float edge = 0.30 + 0.70 * pow(0.5 + 0.5 * cos((ang + seed * 6.2832) * 6.0), 3.0);
		a = 1.0 - smoothstep(edge - 0.10, edge, r);
		col = mix(col, vec3(1.0), (1.0 - r) * 0.85);
	} else if (kind == 13) {
		// blood spray: streaks of blood out of a core (Bloodbolt's impact sheet)
		float streak = pow(0.5 + 0.5 * cos((ang + seed * 6.2832) * 9.0), 14.0);
		float rad = 0.25 + 0.70 * streak;
		a = (1.0 - smoothstep(rad - 0.10, rad, r)) * 0.95;
		col = mix(col, col * 0.55, smoothstep(0.1, 0.9, r));
	} else if (kind == 14) {
		// briar burst: a thorny star
		float edge = 0.2 + 0.8 * pow(0.5 + 0.5 * cos((ang + seed * 6.2832) * 8.0), 6.0);
		a = 1.0 - smoothstep(edge - 0.08, edge, r);
	} else if (kind == 15) {
		// shield: a heater shield with a gold rim and Law's square, translucent (Shield of Law)
		float d = shield_d(p);
		float inside = 1.0 - smoothstep(-0.02, 0.02, d);
		float rim = 1.0 - smoothstep(0.0, 0.10, abs(d + 0.06));  // MVP-3 (#177): a thicker rim and a firmer pane, so the shield reads without its label
		float pul = anim ? 0.75 + 0.25 * sin(TIME * 4.0 + seed * 6.2832) : 0.85;
		float emblem = step(abs(p.x), 0.20) * step(abs(p.y - 0.05), 0.20);
		vec3 rimc = vec3(1.0, 0.86, 0.45);
		col = mix(col * (0.80 + 0.40 * (p.y * 0.5 + 0.5)), rimc, clamp(rim * pul + emblem * 0.7, 0.0, 1.0));
		a = inside * (0.52 + 0.40 * rim * pul + emblem * 0.30);
	} else if (kind == 16) {
		// briar: a ball of thorns, dark with a lighter heart
		float s = pow(0.5 + 0.5 * cos((ang + seed * 6.2832) * 7.0), 5.0);
		float edge = 0.30 + 0.70 * s;
		a = 1.0 - smoothstep(edge - 0.07, edge, r);
		col = mix(col * 1.2, vec3(0.04, 0.14, 0.05), smoothstep(edge - 0.30, edge, r));
	} else if (kind == 17) {
		// vine: a thorny vine climbing from the foot of the quad, growing in
		float grow = clamp(u, 0.0, 1.0);
		float sway = anim ? sin(TIME * 2.0 + seed * 6.2832) * 0.08 : 0.0;
		float yy = p.y * 0.5 + 0.5;
		float x0 = 0.28 * sin(yy * 7.0 + seed * 6.2832) * (0.4 + 0.6 * yy) + sway * yy;
		float width = 0.085 * (1.0 - 0.55 * yy);
		float line = (1.0 - smoothstep(width * 0.6, width, abs(p.x - x0))) * (1.0 - smoothstep(grow - 0.04, grow, yy));
		float cell = fract(yy * 6.0);
		float side = mod(floor(yy * 6.0), 2.0) * 2.0 - 1.0;
		float th = (1.0 - smoothstep(0.03, 0.07, length(vec2(p.x - x0 - side * 0.10, (cell - 0.5) * 0.17)))) * (1.0 - smoothstep(grow - 0.04, grow, yy));
		a = max(line, th);
		col = mix(col, col * 0.6, th);
	} else if (kind == 18) {
		// mote: a soft dot with a small sparkle
		float soft = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		float sp = pow(clamp(1.0 - 9.0 * abs(q.x * q.y), 0.0, 1.0), 2.0) * (1.0 - r);
		a = max(soft, sp * 0.85);
	} else if (kind == 19) {
		// leaf: a pointed oval with a lighter vein
		float half_h = 0.38 * (1.0 - q.x * q.x);
		a = (1.0 - smoothstep(half_h - 0.06, half_h, abs(q.y))) * step(abs(q.x), 0.98);
		col = mix(col, col * 1.3 + vec3(0.1), 1.0 - smoothstep(0.0, 0.06, abs(q.y)));
	} else if (kind == 20) {
		// mist: a soft, lumpy cloud
		float n = 0.55 + 0.25 * sin(p.x * 4.0 + seed * 9.0 + u * 2.0) + 0.20 * sin(p.y * 5.0 + seed * 5.0);
		a = (1.0 - smoothstep(0.2, 1.0, r)) * n;
	} else if (kind == 21) {
		// puff: a puff of smoke, shaded darker underneath
		a = (1.0 - smoothstep(0.55, 0.95 + 0.05 * sin(ang * 5.0 + seed * 6.0), r)) * 0.9;
		col = mix(col * 1.1, col * 0.7, clamp(-p.y * 0.5 + 0.5, 0.0, 1.0));
	} else if (kind == 22) {
		// eye: an almond with an iris and a pupil, opening as it appears (Far Sight)
		float open = clamp(u, 0.05, 1.0);
		float lid = open * 0.55 * (1.0 - p.x * p.x);
		float inside = (1.0 - smoothstep(lid - 0.02, lid, abs(p.y))) * step(abs(p.x), 0.99);
		float edge = (1.0 - smoothstep(0.0, 0.07, abs(abs(p.y) - lid))) * step(abs(p.x), 0.99);
		float er = length(vec2(p.x, p.y * 1.3));
		float iris = (1.0 - smoothstep(0.30, 0.34, er)) * inside;
		float pupil = (1.0 - smoothstep(0.12, 0.15, er)) * inside;
		float glint = (1.0 - smoothstep(0.0, 0.07, length(p - vec2(0.10, 0.10)))) * inside;
		col = mix(col, vec3(0.78, 0.55, 0.16), iris);
		col = mix(col, vec3(0.10, 0.07, 0.02), pupil);
		col = mix(col, vec3(1.0), glint);
		a = inside * 0.55 + edge * 0.95 + iris * 0.4;
	} else if (kind == 23) {
		// moon: a disc with a dark crescent and a halo (the Blood Moon)
		float disc = 1.0 - smoothstep(0.60, 0.64, r);
		float r2 = length(p - vec2(0.20, 0.10));
		float shade = smoothstep(0.52, 0.62, r2);
		col = mix(col, col * 0.40, shade * disc);
		a = max(disc, 0.30 * (1.0 - smoothstep(0.62, 1.0, r)));
	} else if (kind == 24) {
		// plus: a plus sign (a heal), with a dark edge
		float arm = max(step(abs(p.x), 0.20) * step(abs(p.y), 0.66), step(abs(p.y), 0.20) * step(abs(p.x), 0.66));
		float arm2 = max(step(abs(p.x), 0.30) * step(abs(p.y), 0.76), step(abs(p.y), 0.30) * step(abs(p.x), 0.76));
		a = arm2;
		col = mix(vec3(0.05, 0.10, 0.05), col, arm);
	} else if (kind >= 30) {
		// beams and columns: a ribbon, UV.x across it, UV.y along it; y is how far the head has got
		float c = abs(UV.x - 0.5) * 2.0;
		float along = UV.y;
		float vis = step(along, u + 0.0001) * smoothstep(0.0, 0.03, along);
		float spark = exp(-pow((along - u) * 22.0, 2.0)) * (1.0 - c);
		if (kind == 31) {
			// a pillar of light: wide at the foot, fading toward the top
			a = (1.0 - smoothstep(0.15, 1.0, c)) * (1.0 - smoothstep(0.55, 1.0, along));
			col = mix(col, vec3(1.0), (1.0 - c) * (1.0 - c) * 0.6);
		} else if (w < 0.5) {
			// the full beam: a glow, a white-hot core
			float core = 1.0 - smoothstep(0.0, 0.2, c);
			a = max(pow(1.0 - c, 1.4) * 0.8, core);
			col = mix(col, vec3(1.0), core * 0.9);
		} else if (w < 1.5) {
			// the plain beam: a flat band with a lighter middle
			a = 1.0 - smoothstep(0.55, 0.70, c);
			col = mix(col, vec3(1.0), (1.0 - smoothstep(0.0, 0.3, c)) * 0.5);
		} else if (w < 2.5) {
			// a straight line
			a = 1.0 - smoothstep(0.35, 0.50, c);
		} else {
			// the trail: wide, soft, faint
			a = pow(1.0 - c, 1.5);
		}
		a = a * vis + spark * 0.8;
	}
	if (a_out >= 0.0) {
		// the stroke in its colour, the ink round it (the game's keyline), so a ring reads on any ground
		float o = clamp(max(a, a_out), 0.0, 1.0);
		col = mix(ink, col, clamp(a / max(o, 0.001), 0.0, 1.0));
		a = o;
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * v_col.a;
}
