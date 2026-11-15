## CW-8 (#259, design/CANDLEWAKE.md §3.5): the Wake on the board, the pure part: what each marked province shows, read from
## GameState.marks. Marks are public (as owners and terrain are), so a fog view shows them as the true state does.
##   tint    the ground's pale wax, at three strengths by the mark's stage (Sitting Up, the Wake-Line, Deep Wake)
##   reach   how far that wax has spread from the province's roads and buildings (WorldView.wake_reach_of, the mask), further with
##           each stage; a cold wake's (the scar) tint and reach fade back over the turns it has left
##   melt    how far the buildings have melted (three steps, by stage); a scarred building keeps its melt
##   lit     a flame in every window (stage 1 and up, never on a scar)
##   posts   candle-posts along the roads (stage 2 and up, never on a scar)
## The quality ladder (WakeLook.ladder, design §3.5): low keeps the tint and the window flames, medium adds the posts and the melt,
## high the wax drips and the flames' flicker (never with reduced motion).
extends RefCounted

const TINT := [0.0, 0.3, 0.44, 0.56]
const REACH := [0.0, 0.3, 0.6, 1.0] ## of REACH_MAX world units from the nearest road or building
const REACH_MAX := 60.0
const MELT := [0.0, 0.34, 0.67, 1.0]
## The board's quality rungs (WorldView.quality, 0 best .. 3) from which each layer is drawn: melts and posts down to MEDIUM_RUNG,
## the drips and the flames' flicker down to HIGH_RUNG.
const MEDIUM_RUNG := 2
const HIGH_RUNG := 1


## {province id: {"stage", "scar", "tint", "reach", "melt", "lit", "posts", "faction"}} for every province with a mark or a scar in
## `state`.
static func of(state: GameState) -> Dictionary:
	var out := {}
	if state == null or state.marks.is_empty():
		return out
	var e := MarkRules.end_clock(state)
	for pid in state.marks:
		var entry: Dictionary = state.marks[pid]
		var mark: Dictionary = entry.get("mark", {})
		var scar: Dictionary = entry.get("scar", {})
		if not mark.is_empty():
			var st := clampi(MarkRules.stage_now(state, String(pid)), 0, TINT.size() - 1)
			out[pid] = {"stage": st, "scar": false, "tint": float(TINT[st]), "reach": float(REACH[st]), "melt": float(MELT[st]), "lit": st >= 1,
				"posts": st >= 2, "faction": String(mark.faction)}
		elif not scar.is_empty():
			var st2 := clampi(int(scar.get("stage", 0)), 0, TINT.size() - 1)
			var total := float(int(MarkData.row(String(scar.faction)).get("scar_turns", 1)) * maxi(st2, 1))
			var left := clampf(float(int(scar.get("until_turn", 0)) - e + 1) / total, 0.0, 1.0)
			out[pid] = {"stage": st2, "scar": true, "tint": float(TINT[st2]) * left, "reach": float(REACH[st2]) * left, "melt": float(MELT[st2]),
				"lit": false, "posts": false, "faction": String(scar.faction)}
	return out


## What the board draws of the Wake on quality rung `rung` (the tint and the window flames on every rung): {"melt", "posts", "drips",
## "sway"}. `reduced` (the reduced-motion setting) stills the flames.
static func ladder(rung: int, reduced := false) -> Dictionary:
	return {"melt": rung <= MEDIUM_RUNG, "posts": rung <= MEDIUM_RUNG, "drips": rung <= HIGH_RUNG, "sway": rung <= HIGH_RUNG and not reduced}


## The ground's and the buildings' wake texture (Vision.WIDTH x 1 RGBA8), one texel per province index in `ids` order: r a live
## mark's tint, g a cold wake's, b the melt, a the reach.
static func texels(look: Dictionary, ids: Array, width: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(width * 4)
	for i in mini(ids.size(), width):
		var w: Dictionary = look.get(ids[i], {})
		if w.is_empty():
			continue
		var tint := roundi(clampf(float(w.tint), 0.0, 1.0) * 255.0)
		out[i * 4] = 0 if bool(w.scar) else tint
		out[i * 4 + 1] = tint if bool(w.scar) else 0
		out[i * 4 + 2] = roundi(clampf(float(w.melt), 0.0, 1.0) * 255.0)
		out[i * 4 + 3] = roundi(clampf(float(w.reach), 0.0, 1.0) * 255.0)
	return out
