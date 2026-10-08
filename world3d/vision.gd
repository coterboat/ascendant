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
##   tag_for(state, level, seen_turn) the short lines under a province's name plate on the board ("glimpsed", "out of sight" /
##                                    "seen 3 turns ago", "never seen"); "" in clear sight
##   words(level)                     what a level looks like on the ground and means, for tooltips and the legend
##   legend_lines(state)              the board legend's fog section
## The ground shader reads the texture (world3d/shaders/ground_common.gdshaderinc: the veil, hatching and clouds); the
## armies draw stand-ins from the view's own armies and memory ghosts in their own material (armies.gd).
extends RefCounted

## The vision texture's width: one texel per province index, beside the owner and mark textures.
const WIDTH := 16
## The texel of each level (§12.1): 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight.
const TEXEL := {"never": 0, "veiled": 85, "glimpse": 170, "clear": 255}
## A memory ghost's opacity by step (§12.1: "they fade a step every 2 turns"); the last step stays.
const GHOST_ALPHA := [0.74, 0.62, 0.52, 0.43, 0.35, 0.28]
const GHOST_STEP_TURNS := 2


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


# --- words -----------------------------------------------------------------------------------------

## The short lines under a province's name plate on the board, or "" in clear sight (no line, no clutter): "glimpsed",
## "out of sight" over "seen 3 turns ago" (two lines, so neighbouring plates never run into each other), "never seen". It is
## words, so a level never rests on colour alone.
static func tag_for(state: GameState, level: String, seen_turn: int) -> String:
	match level:
		FogRules.GLIMPSE:
			return "glimpsed"
		FogRules.VEILED:
			return "out of sight\nseen %s" % ago_text(state, seen_turn)
		FogView.NEVER:
			return "never seen"
	return ""


## "3 turns ago", "1 turn ago" or "at the start": a sighting of turn `turn`, in FogView's words (the turn being played, less the
## sighting's).
static func ago_text(state: GameState, turn: int) -> String:
	if turn <= 0:
		return "at the start"
	var ago := maxi(1, state.current_turn + 1 - turn)
	return "1 turn ago" if ago == 1 else "%d turns ago" % ago


## What a level looks like on the ground and means (the board's tooltips and legend), one sentence each.
static func words(level: String) -> String:
	match level:
		FogRules.CLEAR:
			return "In clear sight: the ground is untouched. You see every army there exactly."
		FogRules.GLIMPSE:
			return "Glimpsed: a faint cool veil. You see rival armies there roughly, under a plate that reads ≈ and a rounded number."
		FogRules.VEILED:
			return "Out of sight: a dark veil with fine diagonal hatching and the colours drained. Terrain, owners and forts stay true; rival armies show only as grey ghosts of what you last saw."
		FogView.NEVER:
			return "Never seen: the darkest veil, hatched, with slow clouds drifting over it. You know nothing of the armies there."
	return ""


## The board legend's fog section (appended to the legend's tooltip in a fog game): one line per sight level and for
## the stand-ins and ghosts, in the words of the Vision map mode (FogView.legend_rows).
static func legend_lines(state: GameState) -> String:
	if not active(state):
		return ""
	var lines := ["\n\nFog of war (what you see, level by level):"]
	for level in [FogRules.CLEAR, FogRules.GLIMPSE, FogRules.VEILED, FogView.NEVER]:
		lines.append("- %s" % words(level))
	lines.append("- A rival army you glimpse stands as blocks drawn from the rounded number on its plate (≈20): the real army may be a little bigger or smaller, and there may be more you can't see.")
	lines.append("- A grey translucent ghost, with a plate like \"≈10 · 3 turns ago\": an army you saw there once. It fades a step every %d turns, and it may have moved on. A rival yard under the veil stands empty, or shows only its ghosts." % GHOST_STEP_TURNS)
	lines.append("- A rival column marching out of your sight walks to the border and fades. A ritual cast from a caster you can't see arrives at its target with no direction.")
	lines.append("- Under the plate of each province: \"glimpsed\", or \"out of sight, seen 3 turns ago\", or \"never seen\".")
	return "\n".join(lines)
