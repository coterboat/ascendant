## Fog of war on the 3D board, the pure part (no nodes) (M5-3, #114; design/M5_MAGIC_FOG.md §2.3, §2.5, §12.1;
## design/3D_DIRECTION.md §6.3, §6.6, §10.2). What the board needs to know about the viewer's sight, worked out from the
## viewer's view (FogRules.view_state: a GameState with is_view set) and its memory, and nothing else: the board never
## reads the truth, so what it draws can't come from state the viewer is not shown (tests/test_fog_board.gd).
##
##   active(state)                    true for a fog view (FogView.active); false for a plain game and for the observer
##   levels(state, viewer, memory)    {province id: "clear" | "glimpse" | "veiled" | "never"}: the sight level of every
##                                    province ("never": out of sight and never seen)
##   texels(levels, ids)              the 16 x 1 R8 vision texture's bytes (WIDTH texels, one per province index):
##                                    0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight
##   age_of(state, army)              how many turns ago a remembered army was last seen (0 for any other army)
##   ghost_step(age), ghost_alpha(step)   a memory ghost fades a step for every 2 turns of age, down to the last step
##   look(level)                      UX-2 (design/UX_WAR_TABLE.md 2.2): the ground's look at a level, the shader's parameters: how light
##                                    it is, how drained, the veil's tint, and the texture that tells it apart without colour (clear:
##                                    none; glimpse: a thin drifting mist; veiled: a static old-map hatch; never: flat dark parchment)
##   look_arrays()                    the four looks packed for the shaders' uniform arrays, indexed by the vision texel / 85
##   ago_text(state, turn)            "3 turns ago": a sighting's age in FogView's words (UX-2: no sight words are printed under a plate any
##                                    more, since sight speaks through the veil; a ghost's plate and the hovers keep the age)
##   words(level)                     what a level looks like on the ground and means, for the plate's tooltip and the legend
##   legend_lines(state)              the board legend's fog section
## The ground shader reads the texture (world3d/shaders/ground_common.gdshaderinc: the veil, mist, hatching and parchment); the
## armies draw stand-ins from the view's own armies and memory ghosts in their own material (armies.gd).
extends RefCounted

## The vision texture's width: one texel per province index, beside the owner and mark textures.
const WIDTH := 16
## The texel of each level (§12.1): 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight.
const TEXEL := {"never": 0, "veiled": 85, "glimpse": 170, "clear": 255}
## A memory ghost's opacity by step (§12.1: "they fade a step every 2 turns"); the last step stays.
const GHOST_ALPHA := [0.74, 0.62, 0.52, 0.43, 0.35, 0.28]
const GHOST_STEP_TURNS := 2

## UX-2 (§2.2): the four looks of the ground, one per sight level, different in lightness AND in texture, so sight reads without
## colour vision and without a word. The keys of a look (the shader's copy of the arithmetic is paint_ground in
## ground_common.gdshaderinc):
##   level      the sight level
##   texture    the non-colour channel: "none" | "mist" | "hatch" | "parchment"
##   lightness  the ground's luminance against clear ground (clear 1.0): the shader scales each pixel's luminance by it, so the relief
##              of the terrain survives; a flat parchment (detail 0) has no relief, and its tone IS that lightness of REF_LUMA
##   drain      how much of the terrain's colour is drained to grey (0 none, 1 all)
##   tint       the veil's colour, and tint_k how far the colour is pulled to it
##   detail     how much of the terrain's painted detail and relief is kept (1 all, 0 none: flat parchment)
##   mist       the strength of the drifting mist (animated and slow: it stands still at the quality ladder's low rungs)
##   hatch      the strength of the static hatch lines (ink, at a constant screen size)
##   grain      a faint paper grain over the flat parchment
## The steps: clear 1.0, a step down (0.84), two steps (0.68) toward sepia, and the darkest (0.30). A test pins the least step.
const REF_LUMA := 0.55 ## a mean clear ground's luminance (sRGB), for the flat parchment's tone
const LIGHTNESS_STEP := 0.16
const LOOKS := {
	"clear": {"level": "clear", "texture": "none", "lightness": 1.0, "drain": 0.0, "tint": Color(1.0, 1.0, 1.0), "tint_k": 0.0,
		"detail": 1.0, "mist": 0.0, "hatch": 0.0, "grain": 0.0},
	"glimpse": {"level": "glimpse", "texture": "mist", "lightness": 0.84, "drain": 0.12, "tint": Color(0.40, 0.50, 0.66), "tint_k": 0.14,
		"detail": 1.0, "mist": 0.7, "hatch": 0.0, "grain": 0.0},
	"veiled": {"level": "veiled", "texture": "hatch", "lightness": 0.68, "drain": 0.55, "tint": Color(0.52, 0.38, 0.22), "tint_k": 0.42,
		"detail": 0.75, "mist": 0.0, "hatch": 0.85, "grain": 0.0},
	"never": {"level": "never", "texture": "parchment", "lightness": 0.30, "drain": 1.0, "tint": Color(0.19, 0.145, 0.095), "tint_k": 1.0,
		"detail": 0.0, "mist": 0.0, "hatch": 0.0, "grain": 0.07},
}
## The shaders index the looks by the vision texel / 85: 0 never seen, 1 remembered, 2 glimpsed, 3 in clear sight.
const LOOK_ORDER := ["never", "veiled", "glimpse", "clear"]


static func active(state: GameState) -> bool:
	return FogView.active(state)


## {province id: level} for every province of the view `state`; {} when it is not a fog view. `memory` is the viewer's
## memory (GameSession.memory): a province out of sight whose seen_turn is below 0 was never seen.
static func levels(state: GameState, viewer: String, memory: Dictionary) -> Dictionary:
	var out := {}
	if not active(state):
		return out
	var sight := FogRules.sight(state, viewer)
	var seen: Dictionary = memory.get("provinces", {})
	for p in state.provinces:
		var level := String(sight.get(p.id, FogRules.VEILED))
		if level == FogRules.VEILED and int((seen.get(p.id, {}) as Dictionary).get("seen_turn", -1)) < 0:
			level = FogView.NEVER
		out[p.id] = level
	return out


## The vision texture's bytes for `levels` over the terrain's province `ids` (index = the data image's red channel):
## WIDTH bytes. With no levels (fog off) every texel is 255, so a stale texture could never veil anything.
static func texels(level_of: Dictionary, ids: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(WIDTH)
	out.fill(255)
	for i in mini(ids.size(), WIDTH):
		out[i] = int(TEXEL.get(String(level_of.get(ids[i], "clear")), 255))
	return out


## Turns since a remembered army was last seen, counted as the board's plate counts them (FogView's "3 turns ago": the
## turn being played, less the turn of the sighting); 0 for an army that is not a memory.
static func age_of(state: GameState, army: Army) -> int:
	if army == null or String(army.seen.get("level", "")) != FogData.MEMORY:
		return 0
	return maxi(0, state.current_turn + 1 - int(army.seen.get("turn", 0)))


## The fade step of a memory ghost of `age` turns: one more every GHOST_STEP_TURNS, no further than the last step.
static func ghost_step(age: int) -> int:
	return clampi(maxi(age, 0) / GHOST_STEP_TURNS, 0, GHOST_ALPHA.size() - 1)


static func ghost_alpha(step: int) -> float:
	return float(GHOST_ALPHA[clampi(step, 0, GHOST_ALPHA.size() - 1)])


## True for the stand-in armies of a view (a rival's glimpse, memory or exact sighting).
static func is_stand_in(army: Army) -> bool:
	return FogView.is_stand_in(army)


static func is_memory(army: Army) -> bool:
	return army != null and String(army.seen.get("level", "")) == FogData.MEMORY


# --- the looks (UX-2) ------------------------------------------------------------------------------

## The ground's look at `level` ("clear", "glimpse", "veiled" or "never"): a copy of its parameters (see LOOKS). An unknown level, or ""
## (no fog), is the clear look: nothing drawn.
static func look(level: String) -> Dictionary:
	return (LOOKS.get(level, LOOKS["clear"]) as Dictionary).duplicate()


## The luminance a look leaves on a ground of luminance `luma` (0 to 1), as the shader works it out: the ground's own luminance scaled by
## the look's lightness, or, as its detail goes to nothing, the flat tone of its tint. For tests and swatches; the shader does the same sum.
static func lit(level: String, luma: float = REF_LUMA) -> float:
	var lk := look(level)
	var scaled := luma * float(lk["lightness"])
	return lerpf((lk["tint"] as Color).get_luminance(), scaled, float(lk["detail"]))


## The four looks packed for the ground's uniform arrays, in LOOK_ORDER (index = texel / 85):
## {"look_tone": rgb tint + tint_k, "look_lift": lightness, drain, detail, grain, "look_tex": mist, hatch, 0, 0}.
static func look_arrays() -> Dictionary:
	var tone := PackedVector4Array()
	var lift := PackedVector4Array()
	var tex := PackedVector4Array()
	for level in LOOK_ORDER:
		var lk := look(level)
		var c: Color = lk["tint"]
		tone.append(Vector4(c.r, c.g, c.b, float(lk["tint_k"])))
		lift.append(Vector4(float(lk["lightness"]), float(lk["drain"]), float(lk["detail"]), float(lk["grain"])))
		tex.append(Vector4(float(lk["mist"]), float(lk["hatch"]), 0.0, 0.0))
	return {"look_tone": tone, "look_lift": lift, "look_tex": tex}


# --- words -----------------------------------------------------------------------------------------

## "3 turns ago", "1 turn ago" or "at the start": a sighting of turn `turn`, in FogView's words (the turn being played, less the
## sighting's).
static func ago_text(state: GameState, turn: int) -> String:
	if turn <= 0:
		return "at the start"
	var ago := maxi(1, state.current_turn + 1 - turn)
	return "1 turn ago" if ago == 1 else "%d turns ago" % ago


## What a level looks like on the ground and means (the plate's tooltip and the legend), one sentence each. The looks are LOOKS':
## a thin drifting mist, an old map's hatch lines in sepia, flat dark parchment.
static func words(level: String) -> String:
	match level:
		FogRules.CLEAR:
			return "In clear sight: the ground is untouched. You see every army there exactly."
		FogRules.GLIMPSE:
			return "Glimpsed: a step darker, with a thin mist drifting over the land. You see rival armies there roughly, under a plate that reads ≈ and a rounded number."
		FogRules.VEILED:
			return "Out of sight: two steps darker and washed toward sepia, ruled with fine hatch lines like an old map. Terrain, owners and forts stay true; rival armies show only as grey ghosts of what you last saw."
		FogView.NEVER:
			return "Never seen: the darkest, flat parchment with no terrain drawn on it. You know nothing of the armies there."
	return ""


## The board legend's fog section (appended to the legend's tooltip in a fog game): one line per sight level and for
## the stand-ins and ghosts, in the words of the legend the retired Vision map mode had (FogView.legend_rows, kept for the Sight lens).
static func legend_lines(state: GameState) -> String:
	if not active(state):
		return ""
	var lines := ["\n\nFog of war (what you see, level by level):"]
	for level in [FogRules.CLEAR, FogRules.GLIMPSE, FogRules.VEILED, FogView.NEVER]:
		lines.append("- %s" % words(level))
	lines.append("- A rival army you glimpse stands as blocks drawn from the rounded number on its plate (≈20): the real army may be a little bigger or smaller, and there may be more you can't see.")
	lines.append("- A grey translucent ghost, with a plate like \"≈10 · 3 turns ago\": an army you saw there once. It fades a step every %d turns, and it may have moved on. A rival yard under the veil stands empty, or shows only its ghosts." % GHOST_STEP_TURNS)
	lines.append("- A rival column marching out of your sight walks to the border and fades. A ritual cast from a caster you can't see arrives at its target with no direction.")
	lines.append("- The four looks tell the levels apart without words or colour: nothing on the land, a drifting mist, hatch lines, flat parchment. Hover a province's plate for its level and why.")
	return "\n".join(lines)
