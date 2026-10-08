class_name PathView
## The words and numbers of the research panel, the lock-in preview, the HUD chip, the enemy's path and the
## victory screen's paths (M4-4, #69; design/M4_ASCENSION.md §5, §9.1, §9.2). A UI model only: pure static
## functions over a GameState that read AscensionRules, Forecast and Breakdown and do no rules math of their
## own, so every number on screen is the number the research phase, the income phase and recruitment use.
## It builds no nodes, so the screens stay thin and everything here is tested headless.
##
## Privacy (§3.3, §15 call 10): a faction's research target is its own. Every function that could name it
## takes `own` (the viewer is that faction) and, for anyone else, reads only what is public: the nodes
## researched (with their turns), the sworn side, what it closed, and research per turn.
##
##   view_state(state, fid, orders)        the state this turn's orders are checked against (a queued
##                                         sacrifice applied, a queued research order as the target)
##   card(state, fid, nid, orders, own)    one node card: state, plain reason, cost, ETA, effect, breakdown
##   columns(state, fid, orders, own)      the path tree in four columns (tier I, tier II, Oaths, transformations)
##   sidebar(state, fid, orders, own)      research per turn, the pool, the target and each side's path ETA
##   chip(state, fid, orders)              the top bar chip's text, tooltip breakdown and attention flag
##   preview(state, fid, nid, orders)      the lock-in preview of the side `nid` is on (§5)
##   victory_lines(state)                  each faction's path, in the order taken, for the victory screen
##   needs_you(state, fid)                 "Choose what to research: 14 research is waiting." or ""

const COLUMNS := [
	{"kind": PathData.TIER1, "title": "Tier I", "codex": "path_node"},
	{"kind": PathData.TIER2, "title": "Tier II", "codex": "path_node"},
	{"kind": PathData.OATH, "title": "Oaths: the fork", "codex": "oath"},
	{"kind": PathData.TRANSFORMATION, "title": "Transformations", "codex": "transformation"},
]
## The unit stats the preview's roster table shows, in order, with their headings and codex entries.
const STATS := ["hp", "attack", "defense", "morale", "cost"]
const STAT_HEADS := {"hp": "Hit points", "attack": "Attack", "defense": "Defense", "morale": "Morale", "cost": "Cost"}
const STAT_CODEX := {"hp": "stat_hit_points", "attack": "stat_attack", "defense": "stat_defense", "morale": "stat_morale",
	"cost": "stat_cost"}
## The fork colours of the placeholder frames (§12.3; PathData.BRANCHES "colour").
const FORK_COLOURS := {"gilt": Color("#E6B84E"), "iron": Color("#8A96A3"), "moss": Color("#6FA04B"), "crimson": Color("#C0303A")}
## What the glyph on a fork's frame is, in words (tooltips).
const FORK_GLYPHS := {"gilt": "a gilt sun ring", "iron": "riveted iron", "moss": "a vine", "crimson": "a blood edge"}


# --- the state the orders are checked against -----------------------------------------------------------

## The state `fid`'s orders this turn are checked against: the start-of-turn state with a queued Sacrifice
## applied (RulerRules.state_after_orders) and a queued, legal ResearchOrder as the target. `state` itself
## when neither is queued. Only for the faction's own screens (it reads the private target).
static func view_state(state: GameState, fid: String, orders: Array = []) -> GameState:
	var view := RulerRules.state_after_orders(state, fid, orders)
	var queued := AscensionRules.queued_research(orders)
	if queued == null or AscensionRules.research_target(view, fid) == queued.node_id:
		return view
	if not AscensionRules.check_research(view, fid, queued.node_id).is_empty():
		return view
	if view == state:
		view = state.deep_copy([])
	AscensionRules.set_target(view, fid, queued.node_id)
	return view


## The node the faction's queued ResearchOrder names, or "".
static func queued_node(orders: Array) -> String:
	var q := AscensionRules.queued_research(orders)
	return q.node_id if q != null else ""


# --- node cards -----------------------------------------------------------------------------------------

## One node card. `own` is the faction's own panel; otherwise only public facts are read (researched or not,
## closed), never "researching", "available" or an ETA, which could give the target away.
## Returns {"node", "name", "kind", "kind_name", "cost", "branch", "state" (an AscensionRules state, or
## "unresearched" for the enemy), "state_line", "reason", "effect" (one line), "detail" (the full effect with
## the faction's numbers now), "eta", "done_turn", "number_text" (cost and ETA), "breakdown" (behind
## number_text), "codex", "can_research", "is_oath", "queued", "colour"}.
static func card(state: GameState, fid: String, nid: String, orders: Array = [], own: bool = true) -> Dictionary:
	var view := view_state(state, fid, orders) if own else state
	var n := AscensionRules.node_data(nid)
	var name := AscensionRules.node_name(nid)
	var cost := AscensionRules.node_cost(nid)
	var side := String(n.get("branch", ""))
	var out := {"node": nid, "name": name, "kind": AscensionRules.node_kind(nid), "kind_name": AscensionRules.kind_name(nid),
		"cost": cost, "branch": side, "state": "", "state_line": "", "reason": "", "effect": String(n.get("text", "")),
		"detail": "", "eta": 0, "done_turn": 0, "number_text": "", "breakdown": {}, "codex": String(n.get("codex", "path_node")),
		"can_research": false, "is_oath": AscensionRules.is_oath(nid), "queued": own and queued_node(orders) == nid,
		"colour": String(AscensionRules.branch_data(side).get("colour", ""))}
	var st := AscensionRules.node_state(view, fid, nid)
	var done_turn := AscensionRules.researched_turn(view, fid, nid)
	if not own:
		out.effect = their(String(out.effect))
		out.detail = out.effect
		out.breakdown = cost_breakdown(nid)
		out.number_text = "%d research" % cost
		match String(st.state):
			AscensionRules.RESEARCHED:
				out.state = AscensionRules.RESEARCHED
				out.state_line = "Researched on turn %d" % done_turn
				out.breakdown = cost_breakdown(nid, "They finished it at the end of turn %d." % done_turn)
			AscensionRules.CLOSED:
				out.state = AscensionRules.CLOSED
				out.reason = their_closed_reason(view, fid)
				out.state_line = "Closed: they swore the other Oath"
				out.breakdown = cost_breakdown(nid, String(out.reason))
			_:
				out.state = "unresearched"
				out.state_line = "Not researched"
				out.reason = "What they research next is their secret, as yours is to them."
		return out
	out.state = String(st.state)
	out.reason = String(st.reason)
	var fc := Forecast.research(state, fid, orders, nid)
	match out.state:
		AscensionRules.RESEARCHED:
			out.state_line = "Researched on turn %d" % done_turn
			out.detail = "%s: %s." % [name, _cap(AscensionRules._effects_now(view, fid, nid, false))]
			out.breakdown = cost_breakdown(nid, "%s Its effect works now." % String(out.reason))
			out.number_text = "%d research, paid" % cost
		AscensionRules.CLOSED:
			out.state_line = "Closed for the rest of the game"
			out.detail = out.effect
			out.breakdown = cost_breakdown(nid, out.reason)
			out.number_text = "%d research" % cost
		AscensionRules.NEEDS:
			out.state_line = _needs_line(view, fid, nid)
			out.detail = "%s If researched: %s." % [out.effect, AscensionRules.effect_preview(view, fid, nid)]
			out.breakdown = cost_breakdown(nid, out.reason)
			out.number_text = "%d research" % cost
		_:
			out.can_research = true
			out.eta = int(fc.eta)
			out.done_turn = int(fc.done_turn)
			out.detail = "%s If researched: %s." % [out.effect, AscensionRules.effect_preview(view, fid, nid)]
			out.breakdown = Breakdown.research_progress(state, fid, orders, nid)
			out.number_text = "%d research · %s" % [cost, eta_words(int(fc.eta), int(fc.done_turn), view.current_turn)]
			if out.state == AscensionRules.RESEARCHING:
				out.state_line = "Researching%s" % (" (chosen this turn)" if out.queued else "")
				out.can_research = false
			else:
				out.state_line = "Available: %s if researched next" % eta_short(int(fc.eta))
	return out


## The cards in four columns: [{"kind", "title", "codex", "cards": [card]}], each column in data order.
static func columns(state: GameState, fid: String, orders: Array = [], own: bool = true) -> Array:
	var out := []
	for c in COLUMNS:
		var col: Dictionary = c.duplicate()
		col["cards"] = []
		for nid in AscensionRules.node_ids(fid):
			if AscensionRules.node_kind(nid) == String(c.kind):
				col.cards.append(card(state, fid, nid, orders, own))
		out.append(col)
	return out


## "done at the end of this turn", "done at the end of turn 7 (3 turns)", "never at this pace".
static func eta_words(eta: int, done_turn: int, current_turn: int) -> String:
	if eta < 0:
		return "never at this pace"
	if eta == 1:
		return "done at the end of this turn"
	return "done at the end of turn %d (%d turns)" % [done_turn, eta]


static func eta_short(eta: int) -> String:
	if eta < 0:
		return "never at this pace"
	return "1 turn" if eta == 1 else "%d turns" % eta


## "Needs Drillyard" or "Needs any 2 ordinary nodes (1 so far)".
static func _needs_line(state: GameState, fid: String, nid: String) -> String:
	var n := AscensionRules.node_data(nid)
	for r in n.get("requires", []):
		if not AscensionRules.has_node(state, fid, String(r)):
			return "Needs %s" % AscensionRules.node_name(String(r))
	var any := int(n.get("requires_any", 0))
	return "Needs any %d ordinary nodes (%d so far)" % [any, ordinary_done(state, fid)]


static func ordinary_done(state: GameState, fid: String) -> int:
	var done := 0
	for nid in AscensionRules.researched(state, fid):
		if AscensionRules.is_ordinary(nid):
			done += 1
	return done


## A node's cost as a breakdown (one line), with `note` as its description: the panel's numbers on cards
## that are not open to research (researched, closed, needs) still explain themselves.
static func cost_breakdown(nid: String, note: String = "") -> Dictionary:
	var desc := note if not note.is_empty() else RulesCodex.text("path_node")
	return {"title": "Cost of %s" % AscensionRules.node_name(nid), "description": desc,
		"lines": [{"label": "A %s node" % AscensionRules.kind_name(nid), "value": AscensionRules.node_cost(nid),
			"note": "research points, from your land"}],
		"total_label": "Research it costs", "total": AscensionRules.node_cost(nid), "codex": "path_node"}


## Why the enemy's other side is closed, in public words: "The Aurel Crown swore the Oath of the Dawn on
## turn 5, so the Oath of the Forge and Living Iron are closed to them for the rest of the game."
static func their_closed_reason(state: GameState, fid: String) -> String:
	var sworn := AscensionRules.branch(state, fid)
	if sworn.is_empty():
		return ""
	var oath := String(AscensionRules.branch_data(sworn).get("oath", ""))
	var other := AscensionRules.other_branch(fid, sworn)
	return "%s swore %s on turn %d, so %s and %s are closed to them for the rest of the game." % [
		_cap(_the(state, fid)), AscensionRules.node_ref(oath), AscensionRules.researched_turn(state, fid, oath),
		AscensionRules.node_ref(String(AscensionRules.branch_data(other).get("oath", ""))), AscensionRules.branch_ref(other)]


## A node's one-line effect as the other player reads it ("your" becomes "their").
static func their(text: String) -> String:
	var out := text
	for pair in [["Your ", "Their "], [" your ", " their "], ["you own", "they own"], [" you ", " they "]]:
		out = out.replace(pair[0], pair[1])
	return out


# --- the sidebar ------------------------------------------------------------------------------------------

## The panel's right side. Own: research per turn, the pool, the target and its forecast, and each open
## side's path ETA. Enemy: research per turn, the sworn side and its people, and that the target is secret.
## Returns {"rate": breakdown, "rate_text", "pool", "pool_text", "progress": breakdown, "target", "target_name",
## "cost", "forecast" (Forecast.research), "target_text", "routes": [{"branch", "text", "breakdown", "eta"}],
## "people", "sworn_text", "complete"}.
static func sidebar(state: GameState, fid: String, orders: Array = [], own: bool = true) -> Dictionary:
	var rate := Breakdown.research_rate(state, fid)
	var out := {"rate": rate, "rate_text": "Research per turn: %d" % int(rate.total), "pool": 0, "pool_text": "",
		"progress": {}, "target": "", "target_name": "", "cost": 0, "forecast": {}, "target_text": "", "routes": [],
		"people": AscensionRules.people_name(state, fid), "sworn_text": sworn_text(state, fid, own),
		"complete": AscensionRules.all_complete(state, fid)}  # M5-5: the arcana too, in a magic game
	if not own:
		return out
	var view := view_state(state, fid, orders)
	var fc := Forecast.research(state, fid, orders)
	var pool := AscensionRules.research_points(view, fid)
	out.pool = pool
	out.pool_text = "Research saved: %d" % pool
	out.progress = Breakdown.research_progress(state, fid, orders)
	out.forecast = fc
	out.target = String(fc.get("target", ""))
	out.target_name = String(fc.get("name", ""))
	out.cost = int(fc.get("cost", 0))
	out.target_text = String(fc.get("text", ""))
	for side in PathData.BRANCHES:
		if String(PathData.BRANCHES[side].faction) != fid:
			continue
		var r := route(view, fid, side)
		if not r.is_empty():
			out.routes.append(r)
	return out


## One side's path ETA (§9.1): "Celestial Host: 50 to go (Oath 20 + 30), about 5 turns at 9 a turn", with a
## breakdown of what is still to research, minus what is saved. {} when the side is closed or transformed.
static func route(state: GameState, fid: String, side: String) -> Dictionary:
	var road := AscensionRules.road_need(state, fid, side)  # M5-8: one function, shared with the Magic tab's delay
	if road.is_empty():
		return {}
	var lines: Array = road.lines
	var parts: Array = road.parts
	var need := int(road.need)
	var pool := AscensionRules.research_points(state, fid)
	var saved := mini(pool, need)
	lines.append({"label": "Research saved now", "value": -saved, "note": "spare points are never lost"})
	var to_go := need - saved
	var rate := int(AscensionRules.research_rate(state, fid).rate)
	var turns := AscensionRules.eta(need, pool, rate)
	var when := "never at this pace" if turns < 0 else "about %s at %d a turn" % [eta_short(turns), rate]
	var name := AscensionRules.branch_name(side)
	var text := "%s: %d to go (%s), %s" % [name, to_go, " + ".join(parts), when]
	var desc := "Everything still to research to become %s, as the board stands now: %s. Capturing or losing a province changes the pace by %d a turn, so this is a guide." % [
		AscensionRules.branch_ref(side), when, int(PathData.RESEARCH.province)]
	return {"branch": side, "text": text, "eta": turns, "to_go": to_go,
		"breakdown": {"title": "The road to %s" % AscensionRules.branch_ref(side), "description": desc, "lines": lines,
			"total_label": "Research still to go", "total": to_go, "codex": "transformation"}}


## "Sworn to the Celestial Host (the Oath of the Dawn, turn 5); became it on turn 8." or "No Oath sworn yet."
static func sworn_text(state: GameState, fid: String, own: bool) -> String:
	var side := AscensionRules.branch(state, fid)
	if side.is_empty():
		return "No Oath sworn yet: both sides of the fork are open." if own else "No Oath sworn yet."
	var oath := String(AscensionRules.branch_data(side).get("oath", ""))
	var trans := String(AscensionRules.branch_data(side).get("transformation", ""))
	var text := "Sworn to %s (%s, turn %d)" % [AscensionRules.branch_ref(side), AscensionRules.node_ref(oath),
		AscensionRules.researched_turn(state, fid, oath)]
	if AscensionRules.has_node(state, fid, trans):
		text += "; became %s on turn %d" % [AscensionRules.branch_ref(side), AscensionRules.researched_turn(state, fid, trans)]
	return text + "."


# --- the HUD chip -------------------------------------------------------------------------------------------

## The top bar chip (§9.1): {"text" (two short lines), "breakdown", "attention" (nothing chosen while research
## waits), "codex"}. "Research: Arbalests" / "12/15 · this turn"; "Research: choose a node" / "14 waiting".
static func chip(state: GameState, fid: String, orders: Array = []) -> Dictionary:
	var fc := Forecast.research(state, fid, orders)
	var progress := Breakdown.research_progress(state, fid, orders)
	var target := String(fc.get("target", ""))
	var pool := AscensionRules.research_points(state, fid)
	if AscensionRules.all_complete(state, fid):  # M5-5: in a magic game, the arcana too; research is then sold
		var done := "nothing left" if MagicRules.has_magic(state) else "path complete"
		return {"text": "Research\n%s" % done, "breakdown": progress, "attention": false, "codex": "research_sold" if MagicRules.has_magic(state) else "research"}
	if target.is_empty() or not fc.get("ok", false):
		return {"text": "Research: choose\n%d waiting" % pool, "breakdown": progress, "attention": true, "codex": "research_order"}
	var when := "never" if int(fc.eta) < 0 else ("this turn" if int(fc.eta) == 1 else "turn %d" % int(fc.done_turn))
	return {"text": "Research: %s\n%d/%d · %s" % [String(fc.name), mini(pool, int(fc.cost)), int(fc.cost), when],
		"breakdown": progress, "attention": false, "codex": "research"}


## The turn report's "needs you" line (§9.5): "Choose what to research: 14 research is waiting." when the
## faction has no target and something is left to research; "" otherwise. Own faction only.
static func needs_you(state: GameState, fid: String) -> String:
	if not AscensionRules.has_paths(state) or state.find_faction(fid) == null:
		return ""
	if not AscensionRules.research_target(state, fid).is_empty() or AscensionRules.all_complete(state, fid):
		return ""
	return "Choose what to research: %d research is waiting, and you gain %d a turn. Open the research panel from the top bar." % [
		AscensionRules.research_points(state, fid), int(AscensionRules.research_rate(state, fid).rate)]


# --- the lock-in preview (§5) --------------------------------------------------------------------------------

## The lock-in preview of the side of the fork `nid` (an Oath or a transformation) is on, built on
## AscensionRules.with_nodes: a copy of the state with the side's Oath and transformation applied (those not
## yet researched), then the transformation's first research-phase province rules (the Wild's first growth,
## the first heal), exactly as the research phase of the turn it completes would leave the board if nothing
## else changes. The screen does no math of its own. Returns {"ok", "node", "oath", "transformation",
## "branch", "other", "mode" ("oath" before the Oath, "transformation" after it), "header", "when",
## "when_breakdown", "gain": [line], "lose": [line], "units": [row], "map_units": [line], "economy": line,
## "look": {"changed", "new_unit", "colour", "glyph"}, "can_confirm", "confirm_text", "reason", "before", "after"}.
## A line is {"text", "breakdown" (or {}), "tooltip", "codex"}. A row is {"type", "name", "was_name", "new",
## "trait", "cells": {stat: {"before", "after", "changed", "better", "before_bd", "after_bd"}}}.
static func preview(state: GameState, fid: String, nid: String, orders: Array = []) -> Dictionary:
	var side := String(AscensionRules.node_data(nid).get("branch", ""))
	var out := {"ok": false, "node": nid, "branch": side}
	if side.is_empty() or not AscensionRules.has_paths(state) or String(AscensionRules.branch_data(side).get("faction", "")) != fid:
		out["reason"] = "Only the Oaths and transformations of your own path have a lock-in preview."
		return out
	var before := view_state(state, fid, orders)
	var oath := String(AscensionRules.branch_data(side).oath)
	var trans := String(AscensionRules.branch_data(side).transformation)
	var other := AscensionRules.other_branch(fid, side)
	var other_oath := String(AscensionRules.branch_data(other).oath)
	var other_trans := String(AscensionRules.branch_data(other).transformation)
	var sworn := AscensionRules.has_node(before, fid, oath)
	var ids := []
	for id in [oath, trans]:
		if not AscensionRules.has_node(before, fid, id):
			ids.append(id)
	var after := after_state(before, fid, ids)
	var first_spread := AscensionRules.wild_spread_picks(AscensionRules.with_nodes(before, fid, ids), fid) if not ids.is_empty() else []
	out.ok = true
	out.oath = oath
	out.transformation = trans
	out.other = other
	out.mode = "transformation" if sworn else "oath"
	out.before = before
	out.after = after
	var fx := AscensionRules.node_effects(trans)

	# 1. The header and 2. when.
	var oath_fc := Forecast.research(state, fid, orders, oath)
	var trans_fc := Forecast.research(state, fid, orders, trans)
	if sworn:
		out.header = "Become %s? You swore %s on turn %d, so this is the road you are on: nothing more is closed." % [
			AscensionRules.branch_ref(side), AscensionRules.node_ref(oath), AscensionRules.researched_turn(before, fid, oath)]
		out.when = _when_trans(before, trans, trans_fc)
		out.when_breakdown = Breakdown.research_progress(state, fid, orders, trans) if trans_fc.get("ok", false) else cost_breakdown(trans, String(trans_fc.get("reason", "")))
	else:
		out.header = "Swear %s? It leads to %s and closes %s for the rest of the game." % [AscensionRules.node_ref(oath),
			AscensionRules.branch_ref(side), AscensionRules.branch_ref(other)]
		out.when = _when_oath(before, fid, oath, side, oath_fc)
		out.when_breakdown = Breakdown.research_progress(state, fid, orders, oath) if oath_fc.get("ok", false) else cost_breakdown(oath, String(oath_fc.get("reason", "")))

	# 3. You gain.
	var gain := []
	if not sworn:
		gain.append(_economy_line(before, after, fid, oath, true))
	for type_id in fx.get("rename", {}):
		gain.append(_changed_unit_line(before, after, fid, String(type_id), String(fx.rename[type_id]), trans))
	var new_id := String(fx.get("new_unit", ""))
	if not new_id.is_empty():
		gain.append(_new_unit_line(after, fid, new_id, trans))
	gain.append(_province_rule_line(after, fid, trans, first_spread))
	var opens := String(fx.get("opens_mandate", ""))
	if not opens.is_empty():
		var sb := Breakdown.sacrifice_cost(opens)
		gain.append({"text": "%s can be bought by sacrifice (%d power): %s" % [RulerRules.mandate_name(opens), int(sb.total),
			String(RulerRules.mandate_data(opens).get("effect", ""))], "breakdown": sb, "tooltip": "",
			"codex": String(RulerRules.mandate_data(opens).get("codex", "mandates"))})
	out.gain = gain

	# 4. You lose access to.
	var lose := []
	if sworn:
		lose.append({"text": "Nothing more: %s closed when you swore %s on turn %d." % [AscensionRules.branch_ref(other),
			AscensionRules.node_ref(oath), AscensionRules.researched_turn(before, fid, oath)], "breakdown": {},
			"tooltip": TooltipText.plain("The fork", RulesCodex.text("fork")), "codex": "fork", "rule": true})
	else:
		lose.append(_economy_line(before, AscensionRules.with_nodes(before, fid, [other_oath]), fid, other_oath, false))
		var ofx := AscensionRules.node_effects(other_trans)
		var bits := []
		for type_id in ofx.get("rename", {}):
			bits.append("your %s never become %s" % [AscensionRules.base_unit_name(fid, String(type_id)), String(ofx.rename[type_id])])
		var other_new := String(ofx.get("new_unit", ""))
		if not other_new.is_empty():
			var d: Dictionary = PathData.NEW_UNITS[other_new]
			bits.append("no %s (%d hp, attack %d, defense %d, %d gold, %s)" % [String(d.name), int(d.hp), int(d.attack),
				int(d.defense), int(d.cost), String(d.trait)])
		var orule: Dictionary = ofx.get("province_rule", {})
		if not orule.is_empty():
			bits.append("no %s" % String(PathData.PROVINCE_RULES.get(String(orule.id), {}).get("name", "")).trim_prefix("the "))
		lose.append({"text": "%s: %s." % [AscensionRules.node_name(other_trans), ", ".join(bits)], "breakdown": cost_breakdown(other_trans,
			String(AscensionRules.node_data(other_trans).get("text", ""))), "tooltip": "",
			"codex": String(AscensionRules.node_data(other_trans).get("codex", "transformation"))})
		var other_opens := String(ofx.get("opens_mandate", ""))
		if not other_opens.is_empty():
			lose.append({"text": "%s never opens for sacrifice." % RulerRules.mandate_name(other_opens), "breakdown": {},
				"tooltip": TooltipText.plain(RulerRules.mandate_name(other_opens), String(RulerRules.mandate_data(other_opens).get("effect", ""))),
				"codex": String(RulerRules.mandate_data(other_opens).get("codex", "mandates"))})
	var forswears := String(fx.get("forswears", ""))
	if not forswears.is_empty():
		var kept := " You have it, so you keep it." if RulerRules.has_mandate(before, fid, forswears) else " Mandates you already have stay."
		lose.append({"text": "%s can no longer be bought by sacrifice.%s" % [RulerRules.mandate_name(forswears), kept], "breakdown": {},
			"tooltip": TooltipText.plain("Forsworn: %s" % RulerRules.mandate_name(forswears), "%s %s" % [
				String(RulerRules.mandate_data(forswears).get("effect", "")), RulesCodex.text("forsworn")]), "codex": "forsworn"})
	out.lose = lose

	# 5. Your units, before and after.
	var rows := []
	var fa := after.find_faction(fid)
	for ut in fa.unit_types:
		if ut.is_ruler:
			continue
		var is_new: bool = ut.id == new_id
		var row := {"type": ut.id, "name": ut.name, "was_name": AscensionRules.base_unit_name(fid, ut.id) if fx.get("rename", {}).has(ut.id) else "",
			"new": is_new, "commander": ut.is_commander, "trait": ut.trait_id, "cells": {}}
		for stat in STATS:
			var a := Breakdown.unit_stat(after, fid, ut.id, stat)
			var b := Breakdown.unit_stat(before, fid, ut.id, stat) if not is_new else {}
			var changed := not is_new and int(a.total) != int(b.total)
			var up := not is_new and int(a.total) > int(b.total)
			row.cells[stat] = {"after": int(a.total), "before": int(b.get("total", 0)), "changed": changed, "up": up,
				"better": up != (stat == "cost"), "after_bd": a, "before_bd": b}
		rows.append(row)
	out.units = rows
	var map_units := []
	for type_id in fx.get("rename", {}):
		var count := 0
		for army in before.armies:
			if army.owner != fid:
				continue
			for u in army.units:
				if u.type.id == String(type_id):
					count += 1
		if count == 0:
			continue
		var hb := RulerRules.unit_stats(before, fid, String(type_id))
		var ha := RulerRules.unit_stats(after, fid, String(type_id))
		var bits := []
		for stat in ["hp", "attack", "defense", "morale"]:
			var d := int(ha[stat]) - int(hb[stat])
			if d != 0:
				bits.append("%+d %s" % [d, "hp" if stat == "hp" else stat])
		map_units.append({"text": "Your %s on the map (%s) become %s at once: %s each, now and for every recruit." % [
			AscensionRules.base_unit_name(fid, String(type_id)), TooltipText.count(count, "unit"), String(fx.rename[type_id]), ", ".join(bits) if not bits.is_empty() else "the same numbers"],
			"breakdown": Breakdown.unit_stat(after, fid, String(type_id), "hp"), "tooltip": "", "codex": "transformation"})
	out.map_units = map_units

	# The economy: income per turn before and after, as the board stands now.
	var ib := Breakdown.income(before, fid)
	var ia := Breakdown.income(after, fid)
	var econ_text := "Income per turn: %d now, %d once you are %s (as the board stands now%s)." % [int(ib.total), int(ia.total),
		AscensionRules.branch_ref(side), ", after the Wild's first growth" if not first_spread.is_empty() else ""]
	out.economy = {"text": econ_text, "breakdown": ia, "before_breakdown": ib, "tooltip": "", "codex": "income",
		"before": int(ib.total), "after": int(ia.total)}

	# 6. How they will look: placeholders until the portraits land (§12.3).
	var colour := String(AscensionRules.branch_data(side).get("colour", ""))
	var changed_id := ""
	for type_id in fx.get("rename", {}):
		changed_id = String(type_id)
	out.look = {"changed": changed_id, "changed_name": String(fx.get("rename", {}).get(changed_id, "")),
		"changed_was": AscensionRules.base_unit_name(fid, changed_id), "new_unit": new_id,
		"new_name": String(PathData.NEW_UNITS.get(new_id, {}).get("name", "")), "colour": colour,
		"glyph": String(FORK_GLYPHS.get(colour, ""))}

	# 7. The confirm step.
	var target := trans if sworn else oath
	var check := AscensionRules.check_research(before, fid, target)
	out.target = target
	out.can_confirm = check.is_empty() and AscensionRules.research_target(before, fid) != target
	out.confirm_text = "Research %s" % AscensionRules.node_name(trans) if sworn else "Swear the Oath"
	out.reason = String(check.get("reason", ""))
	if check.is_empty() and not out.can_confirm:
		out.reason = "You are already researching %s." % AscensionRules.node_name(target)
	return out


## `before` with `ids` (the side's Oath and transformation not yet researched) applied by with_nodes, then
## the transformation's first research-phase province rules (§3.4: they run in the turn it completes).
static func after_state(before: GameState, fid: String, ids: Array) -> GameState:
	var after := AscensionRules.with_nodes(before, fid, ids)
	if not ids.is_empty():
		AscensionRules.province_rules_step(after, fid)
	return after


static func _when_oath(state: GameState, fid: String, oath: String, side: String, fc: Dictionary) -> String:
	var trans := String(AscensionRules.branch_data(side).transformation)
	var lock := "Nothing is closed until the Oath is done; until then you can change your research freely."
	if not fc.get("ok", false):
		return "Not yet: %s %s" % [String(fc.get("reason", "")), lock]
	var rate := int(fc.rate)
	var text := "Oath: %d research, %s at %d a turn." % [int(fc.cost), eta_words(int(fc.eta), int(fc.done_turn), state.current_turn), rate]
	var then: Dictionary = fc.get("then", {})
	if not then.is_empty() and int(then.get("done_turn", -1)) > 0:
		text += " %s then needs %d more: about turn %d." % [_cap(AscensionRules.branch_ref(side)), AscensionRules.node_cost(trans),
			int(then.done_turn)]
	return "%s %s" % [text, lock]


static func _when_trans(state: GameState, trans: String, fc: Dictionary) -> String:
	if AscensionRules.has_node(state, String(AscensionRules.node_data(trans).faction), trans):
		return "Done: you became %s on turn %d." % [AscensionRules.branch_ref(String(AscensionRules.node_data(trans).branch)),
			AscensionRules.researched_turn(state, String(AscensionRules.node_data(trans).faction), trans)]
	if not fc.get("ok", false):
		return "Not yet: %s" % String(fc.get("reason", ""))
	return "%s: %d research, %s at %d a turn." % [AscensionRules.node_name(trans), int(fc.cost),
		eta_words(int(fc.eta), int(fc.done_turn), state.current_turn), int(fc.rate)]


## An Oath's economy rule with the faction's numbers now. `gain` false: the side it closes.
static func _economy_line(before: GameState, after: GameState, fid: String, oath: String, gain: bool) -> Dictionary:
	var rule := AscensionRules.economy_rule_name(oath)
	var effect := AscensionRules.effect_preview(before, fid, oath)
	var codex_key := String(PathData.ECONOMY_RULES.get(oath, {}).get("codex", "oath"))
	var bd := Breakdown.income(after, fid)
	var fx := AscensionRules.node_effects(oath)
	if fx.has("blood_levy"):
		# Blood Levy changes prices, not income: its breakdown is a regular unit's price.
		var f := after.find_faction(fid)
		for ut in f.unit_types:
			if not ut.is_commander and not ut.is_ruler:
				bd = Breakdown.unit_stat(after, fid, ut.id, "cost")
				break
	var text := "%s: %s." % [_cap(AscensionRules.node_ref(oath)), effect] if gain \
		else "%s and %s: %s." % [_cap(AscensionRules.node_ref(oath)), rule, effect]
	return {"text": text.replace("..", "."), "breakdown": bd, "tooltip": "", "codex": codex_key}


static func _changed_unit_line(before: GameState, after: GameState, fid: String, type_id: String, new_name: String, trans: String) -> Dictionary:
	var hb := RulerRules.unit_stats(before, fid, type_id)
	var ha := RulerRules.unit_stats(after, fid, type_id)
	var bits := []
	var bd := {}
	for stat in STATS:
		if int(ha[stat]) != int(hb[stat]):
			bits.append("%s %d (was %d)" % [String(STAT_HEADS[stat]).to_lower(), int(ha[stat]), int(hb[stat])])
			if bd.is_empty():
				bd = Breakdown.unit_stat(after, fid, type_id, stat)
	var f := after.find_faction(fid)
	var ut := TurnResolver.recruitable_type(f, type_id)
	return {"text": "Your %s become %s: %s. %s stays." % [AscensionRules.base_unit_name(fid, type_id), new_name,
		", ".join(bits), ut.trait_id if ut else ""], "breakdown": bd, "tooltip": "",
		"codex": String(AscensionRules.node_data(trans).get("codex", "transformation"))}


static func _new_unit_line(after: GameState, fid: String, new_id: String, trans: String) -> Dictionary:
	var us := RulerRules.unit_stats(after, fid, new_id)
	var f := after.find_faction(fid)
	var ut := TurnResolver.recruitable_type(f, new_id)
	var cap := after.find_province(f.capital)
	var trait_text := ut.trait_description if ut else ""
	var trait_key := AutoBattleResolver.codex_id_for_trait(ut.trait_id) if ut else ""
	var codex_key := trait_key if RulesCodex.ENTRIES.has(trait_key) else String(AscensionRules.node_data(trans).get("codex", "transformation"))
	return {"text": "New unit: %s (%d hp, attack %d, defense %d, morale %d, %d gold), recruited at %s. %s: %s" % [String(us.name),
		int(us.hp), int(us.attack), int(us.defense), int(us.morale), int(us.cost), cap.name if cap else "your capital",
		ut.trait_id if ut else "", trait_text], "breakdown": Breakdown.unit_stat(after, fid, new_id, "cost"), "tooltip": "", "codex": codex_key}


static func _province_rule_line(after: GameState, fid: String, trans: String, first_spread: Array) -> Dictionary:
	var rule := AscensionRules.province_rule(after, fid)
	var text := AscensionRules.province_rule_sentence(after, fid, true)
	if not first_spread.is_empty():
		text += " The first to grow: %s." % String(first_spread[0].name)
	var codex_key := String(rule.get("codex", "transformation"))
	return {"text": text, "breakdown": {}, "rule": true, "tooltip": TooltipText.plain(String(rule.get("name", "")).capitalize(), RulesCodex.text(codex_key)),
		"codex": codex_key if RulesCodex.ENTRIES.has(codex_key) else String(AscensionRules.node_data(trans).get("codex", "transformation"))}


# --- the victory screen ------------------------------------------------------------------------------------

## Each faction's path for the victory screen (§9.1): [{"faction", "name", "text", "tooltip"}], "Aurel Crown:
## Drillyard (turn 2), Market Charters (turn 3), the Oath of the Dawn (turn 5), Celestial Host (turn 8).
## Became the Celestial Host." [] without paths.
static func victory_lines(state: GameState) -> Array:
	var out := []
	if not AscensionRules.has_paths(state):
		return out
	for f in state.factions:
		var taken := []
		for nid in AscensionRules.researched(state, f.id):
			taken.append("%s (turn %d)" % [AscensionRules.node_name(nid), AscensionRules.researched_turn(state, f.id, nid)])
		var people := AscensionRules.people_name(state, f.id)
		var side := AscensionRules.branch(state, f.id)
		var outcome := "Became %s." % AscensionRules.branch_ref(side) if not people.is_empty() \
			else ("Sworn to %s, not yet transformed." % AscensionRules.branch_ref(side) if not side.is_empty() else "Swore no Oath.")
		var text := "%s: %s. %s" % [f.faction_name, ", ".join(taken) if not taken.is_empty() else "nothing researched", outcome]
		out.append({"faction": f.id, "name": f.faction_name, "text": text,
			"tooltip": TooltipText.plain("The path of the %s" % f.faction_name, "%s %s" % [AscensionRules.path_name(f.id).capitalize(),
				RulesCodex.text("path")])})
	return out


# --- helpers ----------------------------------------------------------------------------------------------

static func _the(state: GameState, fid: String) -> String:
	var f := state.find_faction(fid)
	return "the " + (f.faction_name if f else "enemy")


static func _cap(text: String) -> String:
	return RulerRules._cap(text)
