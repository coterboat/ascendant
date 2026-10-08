class_name AIPaths
extends RefCounted
## The computer's research plan in a game with paths (M4, design/M4_ASCENSION.md §8.1; ticket M4-5, #70).
## Pure code: no nodes, no scenes, no state of its own. AIPlayer reads it every turn.
##
##   var side := AIPaths.choose_branch(game_seed, seat, "warrior_king", "kingdom")   # "celestial_host" | "living_iron"
##   var node := AIPaths.next_node(state, "kingdom", AIPaths.sequence("kingdom", "warrior_king", side))
##
## The plan, per build preset (AI_PATHS, the spec's `ai_path`): the listed ordinary nodes, then the chosen
## side's Oath, then its transformation, then the remaining ordinary nodes in data order. The computer gives
## a ResearchOrder only when its own target is empty or differs from the plan's next node, so most turns
## carry none (an Oath's transformation becomes the target by itself).
##
## The fork (choose_branch) is a weighted pick, the FIRST draw of its own stream,
## SeededRNG(AISeat.seat_seed(game_seed, seat) + BRANCH_SALT). It never touches the seat's RNG, so every
## draw the seat makes, and with it every M1/M2 computer game, is unchanged. It is a pure function of the
## seed, the seat and the preset, so it needs no saved AI state: a save, a replay or a test gets the same side.
##
## Privacy (§3.3): only the faction's OWN research target is ever read here. A rival's completed nodes and
## sworn side are public; its target is not, and nothing in ai/ reads it.
##
## Proposed by the director in the spec (§8.1). The spec puts `ai_path` in data/build_presets.gd; that file
## is outside the AI ticket's lane, so the same table lives here, keyed by preset id.

## Salt of the fork's random stream (§8.1): its own stream, never the seat RNG.
const BRANCH_SALT := 7

## Per build preset (data/build_presets.gd ids): the ordinary nodes taken before the fork, in order, and
## the weights of the two sides of the fork, [[branch id, weight], ...] in PathData.BRANCHES order.
const AI_PATHS := {
	"warrior_king": {"faction": "kingdom", "before": ["crown_drillyard", "crown_charters"],
		"weights": [["celestial_host", 1], ["living_iron", 1]]},
	"iron_crown": {"faction": "kingdom", "before": ["crown_charters", "crown_drillyard", "crown_stables"],
		"weights": [["celestial_host", 1], ["living_iron", 1]]},
	"regents_court": {"faction": "kingdom", "before": ["crown_drillyard", "crown_arbalests"],
		"weights": [["celestial_host", 1], ["living_iron", 1]]},
	"beast_god_unbound": {"faction": "beasts", "before": ["beasts_boar_hide", "beasts_raiding"],
		"weights": [["thorn_wild", 1], ["blood_pact", 1]]},
	"clan_moot": {"faction": "beasts", "before": ["beasts_raiding", "beasts_boar_hide", "beasts_forest_stride"],
		"weights": [["thorn_wild", 1], ["blood_pact", 1]]},
	"blood_of_the_fang": {"faction": "beasts", "before": ["beasts_boar_hide", "beasts_bone_fangs"],
		"weights": [["thorn_wild", 1], ["blood_pact", 1]]},
}


## M5-10 (#121, design/M5_MAGIC_FOG.md §10.2): the spec puts `ai_arcana` in data/build_presets.gd, which is outside the AI
## ticket's lane, so the same table lives here, keyed by preset id, as AI_PATHS does. "first": how many of the preset's
## ordinary nodes (AI_PATHS "before") it researches before its aligned school's tier I spell. The spec says after its first.
const AI_ARCANA := {
	"warrior_king": {"first": 1},
	"iron_crown": {"first": 1},
	"regents_court": {"first": 1},
	"beast_god_unbound": {"first": 1},
	"clan_moot": {"first": 1},
	"blood_of_the_fang": {"first": 1},
}


## The arcana plan of `preset_id`: {"first"}. A custom build gets the spec's default, after its first ordinary node.
static func arcana_plan_for(preset_id: String) -> Dictionary:
	return AI_ARCANA.get(preset_id, {"first": 1}).duplicate()


## The research plan of `preset_id` for `faction_id`: {"faction", "before", "weights"}. A custom build (no
## preset, or a preset of another faction) gets a stand-in: the faction's two tier I nodes in data order, and
## even weights over its two sides. {} for a faction without a path.
static func plan_for(preset_id: String, faction_id: String) -> Dictionary:
	var plan: Dictionary = AI_PATHS.get(preset_id, {})
	if not plan.is_empty() and String(plan.faction) == faction_id:
		return plan.duplicate(true)
	if AscensionRules.path_data(faction_id).is_empty():
		return {}
	var before := []
	for nid in AscensionRules.node_ids(faction_id):
		if AscensionRules.node_kind(nid) == PathData.TIER1:
			before.append(nid)
	var weights := []
	for b in PathData.BRANCHES:
		if String(PathData.BRANCHES[b].faction) == faction_id:
			weights.append([b, 1])
	return {"faction": faction_id, "before": before, "weights": weights}


## The side of the fork the computer in 0-based `seat` swears to (§8.1): a weighted pick over the plan's
## weights, made with the first draw of SeededRNG(AISeat.seat_seed(game_seed, seat) + BRANCH_SALT). "" for a
## faction without a path.
static func choose_branch(game_seed: int, seat: int, preset_id: String, faction_id: String) -> String:
	var weights: Array = plan_for(preset_id, faction_id).get("weights", [])
	var total := 0
	for w in weights:
		total += maxi(0, int(w[1]))
	if total <= 0:
		return ""
	var roll := SeededRNG.new(AISeat.seat_seed(game_seed, seat) + BRANCH_SALT).randi_range(0, total - 1)
	for w in weights:
		roll -= maxi(0, int(w[1]))
		if roll < 0:
			return String(w[0])
	return String(weights.back()[0])


## The chance of each side under the plan's weights, as a whole percentage: {branch id: pct}.
static func branch_odds(preset_id: String, faction_id: String) -> Dictionary:
	var weights: Array = plan_for(preset_id, faction_id).get("weights", [])
	var total := 0
	for w in weights:
		total += maxi(0, int(w[1]))
	var out := {}
	for w in weights:
		out[String(w[0])] = roundi(100.0 * maxi(0, int(w[1])) / maxf(1.0, float(total)))
	return out


## The whole research order for `preset_id` on side `branch_id` (§8.1): the listed ordinary nodes, the
## side's Oath and transformation, then the remaining ordinary nodes in data order. M5-10 (`magic`, a game with magic): the
## arcana join it (design/M5_MAGIC_FOG.md §10.2). The aligned school's tier I comes after the first ordinary node(s)
## (AI_ARCANA); after the transformation come the aligned tier II, tier III and mastery, then the remaining ordinary
## nodes, then the other school's tier I, tier II and mastery. Without `magic` the order is exactly the M4 one.
static func sequence(faction_id: String, preset_id: String, branch_id: String, magic: bool = false) -> Array:
	var plan := plan_for(preset_id, faction_id)
	if plan.is_empty():
		return []
	var out: Array = plan.before.duplicate()
	var side := AscensionRules.branch_data(branch_id)
	var arcana := AIMagic.arcana_order(faction_id, branch_id) if magic else {}
	var aligned: Array = arcana.get("aligned", [])
	if not aligned.is_empty():
		out.insert(mini(int(arcana_plan_for(preset_id).first), out.size()), aligned[0])
	if not side.is_empty() and String(side.faction) == faction_id:
		out.append(String(side.oath))
		out.append(String(side.transformation))
	if not aligned.is_empty():
		out.append_array(aligned.slice(1))
	for nid in AscensionRules.node_ids(faction_id):
		if AscensionRules.is_ordinary(nid) and not out.has(nid):
			out.append(nid)
	out.append_array(arcana.get("other", []))
	return out


## The first node of `seq` that the faction may research now (AscensionRules.check_research: available, or
## already its target), or "" when none is (the plan is done). Reads only the faction's own state.
static func next_node(state: GameState, faction_id: String, seq: Array) -> String:
	for nid in seq:
		if AscensionRules.check_research(state, faction_id, String(nid)).is_empty():
			return String(nid)
	return ""


## The node to order this turn, or "" for no ResearchOrder: the plan's next node, when the faction's own
## target is empty or another node. The side is the one the faction already swore, if any, else `branch_id`.
static func order_for(state: GameState, faction_id: String, preset_id: String, branch_id: String) -> String:
	if not AscensionRules.has_paths(state):
		return ""
	var sworn := AscensionRules.branch(state, faction_id)
	var want := next_node(state, faction_id, sequence(faction_id, preset_id, sworn if not sworn.is_empty() else branch_id, MagicRules.has_magic(state)))
	if want.is_empty() or want == AscensionRules.research_target(state, faction_id):
		return ""
	return want


## The nodes the faction completed at the end of `turn` (public: both turn reports named them), in order.
static func done_on(state: GameState, faction_id: String, turn: int) -> Array:
	var out := []
	for nid in AscensionRules.researched(state, faction_id):
		if AscensionRules.researched_turn(state, faction_id, nid) == turn:
			out.append(nid)
	return out
