class_name OrdersController
extends RefCounted
## The orders UI's side of issue #6: the orders of the faction at the controls.
## Holds no rules math. Whether an order is allowed comes from OrderBook.submit (the resolver's own
## checks, with their plain-language reasons) and every forecast number comes from Forecast.
## Only reads the GameState, never changes it.
##
## Two modes:
##   standalone      (map preview, tests) the orders live in this controller's own OrderBook.
##   session-backed  (the game screen, #7) pass a GameSession: the orders live in the session's books,
##                   the single source of truth, so they survive map rebuilds and resolve with the
##                   turn. orders() is empty unless `faction_id` is the session's current player, so
##                   one player's orders can never show up on another player's map.
##
## Sacrifice (M2-6, design/M2_RULER.md §2.4): the sacrifice phase resolves first, so every forecast here
## reads view_state(), the start-of-turn state with the queued Sacrifice order applied (the same copy
## OrderBook checks against). Cancelling an order checks the others again; last_removed() names the ones
## that no longer pass, with the reason.
##
## Forts and sieges (M3c S-3, #101; design/M3C_SIEGES.md §9), only in a game with sieges: Fortify orders
## (queue_fortify, fortify_preview), the storm of a fort (set_storm) and per-army sallies (set_sally), each
## checked by OrderBook with the rules' reasons before it is offered (storm_check, sally_check); recruits at any
## fort you own (queue_recruit(type, at), recruit_places() for the "Recruit at" picker); and a move into a fort
## previewed and listed as what it will be: a siege ("Besiege", with "Storm now"), a relief (whose garrison comes
## out to join it: queue_move ties a sally to it for every garrison army but the ruler's), or an empty fort taken.
## Recruits and Fortify orders share one gold pool (paid_orders). Every number comes from SiegeRules, Forecast
## and Breakdown; odds come through FortView.siege_odds, S-2's seam.

## Shown instead of battle odds when no enemy army is in the destination (M1 has no fog of war).
const NO_ENEMY_TEXT := "No enemy army there now; enemies may still move in."

var state: GameState
var faction_id := ""
## M5-2, fog of war (design/M5_MAGIC_FOG.md §2.10): in a fog game `state` is this faction's view, and the forecasts say
## so (Forecast.view_odds): the short line with two odds and its guesses (ⓘ), or "no odds" out of sight. The map sets
## the viewer's memory and intel (GameSession.memory, intel) here, for "last seen" and a known kept power.
var fog_memory := {}
var fog_intel := {}
var book := OrderBook.new()
var session: GameSession = null
var _odds_cache := {}  # "army ids>province" -> move_odds() result; the state never changes under us
var _view: GameState = null  # view_state() for the sacrifice in _view_key
var _view_key := ""
var _removed: Array = []  # texts of the orders the last queue or cancel removed (M2-6)
## M3c: the garrison armies the last queue_move sent out to join its relief (tied sallies), by id.
var last_relief: Array = []


func _init(p_state: GameState = null, p_faction_id: String = "", p_session: GameSession = null) -> void:
	state = p_state
	faction_id = p_faction_id
	session = p_session


## Queues a move. A province two steps away that King's Roads reach is ordered as a road move through
## the first legal province by id (move_order_for). Returns "" when accepted, otherwise the rules' reason
## it was refused.
## M3c: a move into your own besieged fort is a relief, and the garrison comes out to join it (§3.6, §9.2):
## a sally tied to the relief is queued for every garrison army but the ruler's (last_relief names them; untick
## them in the fort panel), and a sally ticked before the relief is tied to it.
func queue_move(army_id: String, to_province: String) -> String:
	last_relief = []
	var garrison := relief_garrison(army_id, to_province)
	var why := _queue(move_order_for(army_id, to_province))
	if not why.is_empty() or garrison.is_empty():
		return why
	var removed := _removed.duplicate()
	for a in garrison:
		var i := sally_index(a.id)
		if i >= 0 and String(orders()[i].with_army).is_empty():
			cancel(i)  # a sally ticked before the relief now goes out with it, and stays in if the relief never comes
			removed.append_array(_removed)
		elif a.ruler != null or i >= 0:
			continue
		if _queue(SiegeOrder.sally(a.id, army_id)).is_empty():
			last_relief.append(a.id)
		removed.append_array(_removed)
	_removed = removed
	return ""


## Queues one recruit at the capital, or (M3c, a game with sieges) at the fort `at` names. Returns "" when
## accepted, otherwise the rules' reason.
func queue_recruit(unit_type_id: String, at: String = RecruitOrder.AT_CAPITAL) -> String:
	return _queue(RecruitOrder.new(unit_type_id, at))


## Queues one recruit with the ruler (Warband Muster: the unit appears where the Ninth Fang ends the
## turn). Returns "" when accepted, otherwise the rules' reason.
func queue_recruit_with_ruler(unit_type_id: String) -> String:
	return _queue(RecruitOrder.new(unit_type_id, RecruitOrder.AT_RULER))


## Queues a Sacrifice order (§2.4): the ruler gives up power for `mandate_id`. Returns "" when accepted,
## otherwise the rules' reason. Orders it makes fail are removed: see last_removed().
func queue_sacrifice(mandate_id: String) -> String:
	return _queue(SacrificeOrder.new(mandate_id))


## Queues a cast order (M5-6, design/M5_MAGIC_FOG.md §6.1): `army_id`'s caster casts `ritual` on `target`, paid in
## `pay` (gold, or blood under Tithe of Blood), with Call the Pack's `size`. Returns "" when accepted, otherwise the
## rules' reason. A move given to that army is removed (the army holds): see last_removed().
func queue_cast(ritual: String, army_id: String, target: String, pay: String = CastOrder.GOLD, size: int = 0) -> String:
	return _queue(CastOrder.new(ritual, army_id, target, pay, size))


## What the cast dialog offers `army_id` (M5-6): one row per ritual of the faction's schools it knows, and Far Sight in a fog
## game (§6.2: without fog it has nothing to show, so it is never offered), in the Magic tab's order:
## {"ritual", "name", "price" (words), "ok", "reason" (why not), "line" (where it can go), "targets" (legal province
## ids; [""] for a ritual with no target), "sizes" (Call the Pack's [least, most] wolves, else []), "blood" (whether it
## may be paid in blood: Tithe of Blood and a mage casting it)}.
func cast_options(army_id: String) -> Array:
	var out := []
	var view := view_state()
	var army: Army = view.find_army(army_id) if view != null else null
	if army == null or not MagicRules.has_magic(view) or army.owner != faction_id:
		return out
	var rituals := []
	for school in MagicRules.schools(faction_id):
		for nid in MagicRules.school_data(school).nodes:
			if MagicRules.is_ritual(String(nid)) and MagicRules.knows(view, faction_id, String(nid)):
				rituals.append(String(nid))  # the ones still to research are in the Magic tab
	if view.fog:
		rituals.append("far_sight")
	for rid in rituals:
		var sp := MagicRules.spell_data(rid)
		var targets := MagicRules.ritual_targets(view, faction_id, rid, army_id)
		var sizes: Array = MagicRules.pack_sizes(view, faction_id, army) if String(sp.get("summon", "")) == "thornwolves" else []
		var probe := String(targets[0]) if not targets.is_empty() else ("" if String(sp.target) == "none" else army.location)
		var caster := MagicRules.caster_for(view, faction_id, army, rid)
		var blood: bool = RulerRules.has_mandate(view, faction_id, MagicRules.TITHE_OF_BLOOD) and String(caster.get("kind", "")) == MagicRules.MAGE
		var check := OrderBook.check_order(state, faction_id, CastOrder.new(rid, army_id, probe, CastOrder.GOLD,
			int(sizes[0]) if not sizes.is_empty() else 0), orders())
		if not check.is_empty() and blood:
			var in_blood := OrderBook.check_order(state, faction_id, CastOrder.new(rid, army_id, probe, CastOrder.BLOOD,
				int(sizes[0]) if not sizes.is_empty() else 0), orders())
			if in_blood.is_empty():
				check = in_blood
		var names := targets.map(func(pid): return _province_name(String(pid)))
		var line := "Covers every battle." if String(sp.target) == "none" else "Can be cast on %s." % RulerRules._and_list(names)
		if names.size() > 4:
			line = "Can be cast on %d provinces in reach." % names.size()
		var price := "%d gold a wolf" % int(sp.cost) if not sizes.is_empty() else "%d gold" % int(sp.cost)
		out.append({"ritual": rid, "name": MagicRules.spell_name(rid), "price": price, "ok": check.is_empty(),
			"reason": String(check.get("reason", "")), "line": line, "targets": targets, "sizes": sizes, "blood": blood})
	return out


## The cast dialog's forecast (MagicRules.forecast_ritual) for one choice, with this faction's queued orders.
func cast_preview(ritual: String, army_id: String, target: String, pay: String = CastOrder.GOLD, size: int = 0) -> Dictionary:
	var order := CastOrder.new(ritual, army_id, target, pay, size)
	var list := orders()
	list.append(order)
	return MagicRules.forecast_ritual(state, faction_id, order, list)


## The queued Sacrifice order, or null.
func queued_sacrifice() -> SacrificeOrder:
	return RulerRules.queued_sacrifice(orders())


## The state this faction's orders and forecasts read: the start-of-turn state, or a copy with the
## queued Sacrifice order applied (RulerRules.state_after_orders), because the sacrifice phase resolves
## first. Never changes `state`.
func view_state() -> GameState:
	var sac := queued_sacrifice()
	if sac == null or state == null:
		return state
	if _view == null or _view_key != sac.mandate_id:
		_view = RulerRules.state_after_orders(state, faction_id, orders())
		_view_key = sac.mandate_id
	return _view


## Every mandate on this faction's list for the sacrifice dialog (Forecast.sacrifice_options).
func sacrifice_options() -> Array:
	return Forecast.sacrifice_options(state, faction_id, orders())


## The sacrifice dialog's before → after preview for `mandate_id` (Forecast.sacrifice), with this
## faction's other queued orders.
func sacrifice_preview(mandate_id: String) -> Dictionary:
	return Forecast.sacrifice(state, faction_id, mandate_id, orders())


## Plain lines for the orders the last queue or cancel removed because they no longer pass ("Road move to
## Westwatch removed: you no longer have King's Roads."); [] when none were.
func last_removed() -> Array:
	return _removed.duplicate()


## The order a click on `to` gives `army_id`: a one-step move to a neighbour, or, for a province further
## away, a road move through the first legal province by id when King's Roads allow one (§2.3).
## Anything else stays a one-step move, which the rules then refuse with their reason.
func move_order_for(army_id: String, to: String) -> MoveOrder:
	var army: Army = state.find_army(army_id) if state else null
	var here: Province = state.find_province(army.location) if army else null
	if here != null and not here.neighbors.has(to):
		var vias := RulerRules.road_vias(view_state(), faction_id, army_id, to)
		if not vias.is_empty():
			return MoveOrder.new(army_id, to, vias[0])
	return MoveOrder.new(army_id, to)


## The provinces two steps away that `army_id` can reach by the King's Roads this turn, {province id:
## [legal vias, sorted]}: the map draws them as road destinations. Empty when the army is not yours,
## already has a move, or your faction has no King's Roads.
func road_destinations(army_id: String) -> Dictionary:
	var army: Army = state.find_army(army_id) if state else null
	if army == null or army.owner != faction_id:
		return {}
	for o in orders():
		if o is MoveOrder and o.army_id == army_id:
			return {}
	return RulerRules.road_destinations(view_state(), faction_id, army_id)


## Every legal way through for the queued road move at `index` ([] for any other order).
func road_vias_at(index: int) -> Array:
	var list := orders()
	if index < 0 or index >= list.size() or not (list[index] is MoveOrder) or not list[index].is_road_move():
		return []
	return RulerRules.road_vias(view_state(), faction_id, list[index].army_id, list[index].to)


## Sends the queued road move at `index` through the next legal province instead (the player's other
## choice, §2.3). The order is given again, so it moves to the end of the list. "" or the reason.
func change_via(index: int) -> String:
	var vias := road_vias_at(index)
	if vias.size() < 2:
		return "This road move has only one way through."
	var o: MoveOrder = orders()[index]
	var next: String = vias[(vias.find(o.via) + 1) % vias.size()]
	var why := cancel(index)
	if not why.is_empty():
		return why
	return _queue(MoveOrder.new(o.army_id, o.to, next))


## Withdraws the order at `index` (as listed by orders()). Returns "" or why it could not. The other
## orders are checked again: cancelling a sacrifice removes the orders that relied on it (last_removed()).
func cancel(index: int) -> String:
	_removed = []
	if session != null:
		var why := _not_my_turn()
		if not why.is_empty():
			return why
		why = session.cancel_order(index)
		_removed = session.removed_orders()
		return why
	_removed = book.cancel(state, faction_id, index).map(func(d): return String(d.text))
	return ""


func orders() -> Array:
	if session != null:
		return session.current_orders() if session.current_player() == faction_id else []
	return book.orders_for(faction_id)


func recruit_orders() -> Array:
	var out := []
	for o in orders():
		if o is RecruitOrder:
			out.append(o)
	return out


## The orders paid from gold in the recruitment phase, in the order given: recruits and (M3c) Fortify orders.
func paid_orders() -> Array:
	return orders().filter(func(o): return o is RecruitOrder or o is FortifyOrder)


## Forecast for a move that is not queued yet (catches a second move for the same army). A province
## two steps away is forecast as the road move a click would order.
func move_forecast(army_id: String, to: String) -> Dictionary:
	return Forecast.move(view_state(), faction_id, move_order_for(army_id, to), orders())


## Battle odds for moving `army_id` to `to`, counting every army you have already ordered there.
## Returns {"enemy_present", "odds" (Forecast.battle_odds result, {} when no enemy is there),
## "line" (verdict and main reasons, for the forecast line), "text" (the full odds text, for tooltips)}.
func move_odds(army_id: String, to: String) -> Dictionary:
	var ids := [army_id]
	for o in orders():
		if o is MoveOrder and o.to == to and not ids.has(o.army_id):
			ids.append(o.army_id)
	ids.sort()
	var view := view_state()
	var key := "%s>%s|%s" % [",".join(ids), to, _view_key if view != state else ""]
	if _odds_cache.has(key):
		return _odds_cache[key]
	# Forecast.battle_odds checks for enemy armies there itself (M1 has no fog: all are visible). A queued
	# sacrifice counts: its mandate fights in this turn's battles.
	if Forecast.is_fog_view(view):
		_odds_cache[key] = _fog_odds(view, ids, to)  # M5-2: odds against what you can see
		return _odds_cache[key]
	var odds := Forecast.battle_odds(view, faction_id, ids, to)
	var out := {"enemy_present": false, "odds": {}, "line": NO_ENEMY_TEXT, "text": NO_ENEMY_TEXT}
	if odds.get("ok", false):
		var line := "Battle odds: %s (you won %d of %d test battles)." % [odds.label, odds.wins, odds.samples]
		if not odds.reasons.is_empty():
			line += " Main reasons: %s." % "; ".join(odds.reasons)
		out = {"enemy_present": true, "odds": odds, "line": line, "text": odds.text}
	_odds_cache[key] = out
	return out


## M5-2: move_odds in a fog game (§2.10): the forecast's short line ("Odds against what you can see: 58% (close), 41% if
## they are at the top of the range ⓘ", or "You can't see ... No odds."), with its guesses in "text" for the tooltip.
func _fog_odds(view: GameState, ids: Array, to: String) -> Dictionary:
	var vo := Forecast.view_odds(view, faction_id, ids, to, fog_memory, fog_intel)
	if bool(vo.get("no_odds", false)):
		return {"enemy_present": false, "odds": vo, "line": String(vo.short), "text": "%s %s" % [String(vo.short), RulesCodex.text("view_odds")], "fog": true}
	if not bool(vo.get("ok", false)):
		return {"enemy_present": false, "odds": {}, "line": NO_ENEMY_TEXT, "text": NO_ENEMY_TEXT, "fog": true}
	var line := String(vo.short)
	if not vo.reasons.is_empty():
		line += " Main reasons: %s." % "; ".join(vo.reasons)
	var text := "%s %s %s: %s %s" % [String(vo.short), String(vo.text), Forecast.INFO, " ".join(vo.assumptions), RulesCodex.text("view_odds")]
	return {"enemy_present": true, "odds": vo, "line": line, "text": text, "fog": true}


## What clicking `to` with `army_id` selected would do, before the click (the map's hover preview):
## {"ok", "text"}. When the move is allowed, the text has the arrival forecast and the battle odds.
func move_preview(army_id: String, to: String) -> Dictionary:
	var f := move_forecast(army_id, to)
	if not f.ok:
		return {"ok": false, "text": "This move can't be ordered: %s" % f.reason}
	var siege := siege_move_text(army_id, to, orders(), false)  # M3c: a move into a fort says what it will be
	if not siege.is_empty():
		return {"ok": true, "text": siege}
	return {"ok": true, "text": "Click to order this move. %s %s" % [f.text, move_odds(army_id, to).line]}


## Gold after the queued recruits and the income forecast. Your queued moves count for Royal Court,
## which pays where the King ends the turn.
func gold_after_recruits() -> Dictionary:
	return Forecast.gold_after_recruits(view_state(), faction_id, paid_orders(), orders())


## The price of one unit, the same the recruitment phase charges (Muster Grounds included).
func recruit_cost(unit_type_id: String) -> int:
	return Forecast.recruit_cost(view_state(), faction_id, unit_type_id)


## "16 gold (20 - Muster Grounds 4)", or "20 gold" when no mandate changes the price.
func price_text(unit_type_id: String) -> String:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id, state) if f else null
	return RulerRules.price_text(view_state(), faction_id, ut) if ut else ""


## The roster this faction can recruit from at its capital.
func recruitable_types() -> Array:
	var f := state.find_faction(faction_id)
	return f.unit_types.duplicate() if f else []


## The Warband Muster part of the recruit panel (§1.4): {"ok", "army_id", "province", "ruler", "limit",
## "used", "left", "text"} for this faction. "ok" is false when its ruler can't recruit in the field
## (another ruler, no rulers, or not on the map).
func ruler_recruit_info() -> Dictionary:
	var view := view_state()
	var limit := RulerRules.field_recruit_limit(view, faction_id)
	var army := RulerRules.ruler_army(view, faction_id)
	if limit <= 0 or army == null:
		return {"ok": false}
	var used := 0
	for o in orders():
		if o is RecruitOrder and o.is_with_ruler():
			used += 1
	var name := RulerRules.current_name(view, faction_id)
	var f := view.find_faction(faction_id)
	var where := view.find_province(army.location)
	var text := "%s can recruit %d regular %s per turn (Warband Muster at ability rank %d), at the usual prices. They gather at %s, where %s starts this turn, and join your armies there at the end of the turn, even if %s marches on; if you no longer own %s then, or %s has fallen, they are cancelled and cost nothing. Commanders come only from your capital." % [
		RulerRules._cap(name), limit, "unit" if limit == 1 else "units", RulerRules.ability_rank(f.kept_power),
		where.name if where else "off the map", name, name, where.name if where else "it", name]
	return {"ok": true, "army_id": army.id, "province": army.location, "ruler": name, "limit": limit, "used": used,
		"left": maxi(0, limit - used), "text": text}


## The road rule of a legal road move of `army_id` to `to` through `via`, by name ("King's Roads" or "Forest
## Stride", M4-2), for the map's road destination marks.
func road_rule_name(army_id: String, to: String, via: String) -> String:
	return TurnResolver.road_rule_name(TurnResolver.road_rule(view_state(), faction_id, MoveOrder.new(army_id, to, via)))


## Every transformation's province rule forecast on the board (M4-2, §9.4), in faction id order:
## Forecast.province_rules for each faction with a rule now (your own counts a transformation your research
## completes this turn; a rival's never reads its private target), plus "faction".
func province_rule_forecasts() -> Array:
	var out := []
	if state == null or not AscensionRules.has_paths(state):
		return out
	var fids := []
	for f in state.factions:
		fids.append(f.id)
	fids.sort()
	for fid in fids:
		var pr := Forecast.province_rules(state, fid, orders() if fid == faction_id else [], faction_id)
		if pr.ok:
			pr["faction"] = fid
			out.append(pr)
	return out


## Every Sworn Vassals forecast on the board (§2.3), one per faction with the mandate, in faction id
## order: Forecast.vassal with this faction's queued moves (other armies hold), plus "faction".
func vassal_forecasts() -> Array:
	var out := []
	if state == null:
		return out
	var view := view_state()  # Sworn Vassals bought by a queued sacrifice joins this turn
	var fids := []
	for f in view.factions:
		if RulerRules.has_mandate(view, f.id, RulerRules.SWORN_VASSALS):
			fids.append(f.id)
	fids.sort()
	for fid in fids:
		var v := Forecast.vassal(view, fid, orders(), faction_id)
		v["faction"] = fid
		out.append(v)
	return out


## One plain-language line per queued order (names, never ids), with its forecast.
func order_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for i in orders().size():
		out.append(order_text(i))
	return out


func order_text(index: int) -> String:
	var list := orders()
	if index < 0 or index >= list.size():
		return ""
	var o = list[index]
	if o is MoveOrder:
		var f := _move_forecast_at(index)
		if f.ok:  # M3c: a move into a fort is listed as the siege, relief or capture it will be
			var others := list.duplicate()
			others.remove_at(index)
			var siege := siege_move_text(o.army_id, o.to, others, true, o)
			if not siege.is_empty():
				return siege
		return "%s %s" % [f.text, move_odds(o.army_id, o.to).line] if f.ok else f.reason
	if o is SacrificeOrder:
		return sacrifice_text(o)
	if o is FortifyOrder:  # M3c
		return fortify_text(index)
	if o is SiegeOrder:  # M3c
		return siege_order_text(o)
	if o is ResearchOrder:  # M4-4: the research target, with its forecast (only its own player sees it)
		var fc := Forecast.research(state, faction_id, list)
		return "Research: %s" % String(fc.text) if fc.ok else "Not researched: %s" % String(fc.reason)
	if o is SpellbookOrder:  # M5-5: the battle spellbook, kept until changed
		return "Battle spellbook: %s. Your casters try the spells in this order each round, from this turn's battles on; it is kept until you change it." % MagicRules.spellbook_text(o.order, o.off)
	if o is CastOrder:  # M5-5; M5-6: with what it will do (its forecast; the tooltip has the rest)
		var army := state.find_army(o.army_id)
		var paid := "paid in blood" if o.pay == CastOrder.BLOOD else "%d gold" % int(MagicRules.price(view_state(), faction_id, o.ritual, o.size).gold)
		var at := "at" if String(MagicRules.spell_data(o.ritual).get("kind", "")) == "summon" else "on"
		var text := "Cast %s%s from your army at %s (%s). That army holds this turn." % [MagicRules.spell_name(o.ritual),
			" %s %s" % [at, _province_name(o.target)] if not o.target.is_empty() else "", _province_name(army.location) if army else "nowhere", paid]
		var fc := MagicRules.forecast_ritual(state, faction_id, o, list)
		return "%s %s" % [text, String(fc.get("effect_text", ""))] if fc.ok else text
	var r := _recruit_result_at(index)
	if not r.ok:
		return "Not recruited: %s" % r.reason
	if state.sieges and r.has("fort") and r.at != RecruitOrder.AT_RULER:  # M3c: at a fort, with its count
		var head := "Recruit %s at %s (%d of %d this turn) for %d gold, leaving %d gold." % [_unit_phrase(String(r.unit_type)),
			_province_name(String(r.province)), int(r.count), int(r.limit), int(r.cost), int(r.gold_after)]
		if bool(r.get("engine", false)):
			head += " It rides with an army of yours there and never fights."
		return head + _arrival_note(r)
	if r.at == RecruitOrder.AT_RULER:
		var name := RulerRules.current_name(state, faction_id)
		return "Recruit one %s with %s for %d gold, leaving %d gold. It gathers at %s, where %s starts this turn, and joins your armies there at the end of the turn, if you still own %s then and %s stands; if not, it is cancelled and costs nothing." % [
			_unit_name(r.unit_type), name, r.cost, r.gold_after, _province_name(r.province), name, _province_name(r.province), name] + _arrival_note(r)
	var text := "Recruit one %s at %s for %d gold, leaving %d gold." % [_unit_name(r.unit_type), _capital_name(), r.cost, r.gold_after]
	return text + _arrival_note(r)


## M4-2, Blood Levy (§9.4): " It arrives wounded, 11 of 14 hit points (Blood Levy ...)." for a recruit that
## arrives below its maximum (price_recruits' "hp"), "" otherwise, so other lines read as before.
func _arrival_note(r: Dictionary) -> String:
	if int(r.get("hp", 0)) >= int(r.get("max_hp", 0)):
		return ""
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, String(r.unit_type), state) if f else null
	return " " + AscensionRules.arrival_text(ut, int(r.hp), int(r.max_hp), AscensionRules.blood_levy_divisor(view_state(), faction_id)).replace("They arrive", "It arrives")


## Breakdown (rules/breakdown.gd shape) behind an order line's numbers, for its tooltip.
func order_breakdown(index: int) -> Dictionary:
	var o = orders()[index]
	if o is SacrificeOrder:
		var b := Breakdown.sacrifice_kept_power(state, faction_id, o.mandate_id)
		b.description = "%s %s %s" % [String(RulerRules.mandate_data(o.mandate_id).get("effect", "")),
			Forecast.mandate_now(view_state(), faction_id, o.mandate_id, orders()), RulesCodex.text("sacrifice")]
		return b
	if o is MoveOrder:
		var f := _move_forecast_at(index)
		if not f.ok:
			return _bd("Move order", f.reason, [], "Arrives at the start of turn", 0)
		var odds := move_odds(o.army_id, o.to)
		var odds_desc: String = "%s %s" % [odds.text, RulesCodex.text("battle_odds")] if odds.enemy_present and not odds.get("fog", false) else odds.text
		var step := _line("Moving one province", 1, "armies move one neighboring province per turn")
		var rule := RulesCodex.text("move")
		if o.is_road_move() and TurnResolver.road_rule(view_state(), faction_id, o) == "forest_stride":
			step = _line("Moving two provinces by Forest Stride", 1, "a road move takes one turn, through a forest you own into another forest")
			rule = RulesCodex.text("forest_stride")
		elif o.is_road_move():
			step = _line("Moving two provinces by the King's Roads", 1, "a road move takes one turn, through land you own")
			rule = RulesCodex.text("road_move")
		if o.is_road_move():
			if road_vias_at(index).size() > 1:
				rule += " Another way through is open: use the button next to this order to change it."
		return _bd("Move forecast", "%s %s %s" % [f.text, odds_desc, rule],
			[_line("Turn now", state.current_turn + 1, "turns count from 1"), step],
			"Arrives at the start of turn", f.arrival_turn)
	if o is ResearchOrder:  # M4-4
		return Breakdown.research_progress(state, faction_id, orders())
	if o is FortifyOrder:  # M3c
		return fortify_breakdown(index)
	if o is SiegeOrder:  # M3c
		return siege_order_breakdown(o)
	if o is SpellbookOrder:  # M5-5: one line per spell switched on, in order
		var lines := []
		for sid in o.order:
			if not o.off.has(sid):
				lines.append(_line(MagicRules.spell_name(String(sid)), 1, "known" if MagicRules.knows(view_state(), faction_id, String(sid)) else "not researched yet"))
		return _bd("Battle spellbook", "%s %s" % [MagicRules.spellbook_text(o.order, o.off), RulesCodex.text("spellbook")], lines, "Spells switched on", lines.size())
	if o is CastOrder:  # M5-5: the ritual's price; M5-6: under the forecast
		var b := Breakdown.ritual_price(view_state(), faction_id, o.ritual, o.size)
		var fc := MagicRules.forecast_ritual(state, faction_id, o, orders())
		b.description = "%s %s" % [String(fc.get("text", "")), String(b.get("description", ""))]
		return b
	var r := _recruit_result_at(index)
	if not r.ok:
		return _bd("Recruit order", r.reason, [], "Gold spent", 0)
	var rules := RulesCodex.text("field_recruit" if r.at == RecruitOrder.AT_RULER else "recruit")
	return _bd("Recruit %s" % _unit_name(r.unit_type), "Recruits are paid in the order given. %s" % rules,
		[_line("Gold before this recruit", r.gold_after + r.cost, ""), _line("Cost", -r.cost, _price_note(r.unit_type))],
		"Gold left after this recruit", r.gold_after)


## Which kind of number an order line is, for its codex link (TooltipText.CODEX): a move into an
## enemy army links to the battle odds, a road move to road moves, any other move to moving, a recruit
## with the ruler to recruiting in the field, any other recruit to recruiting.
func order_codex_kind(index: int) -> String:
	var list := orders()
	if index < 0 or index >= list.size():
		return ""
	var o = list[index]
	if o is SacrificeOrder:
		return "sacrifice"
	if o is ResearchOrder:  # M4-4
		return "research_order"
	if o is SpellbookOrder:  # M5-5
		return "spellbook_order"
	if o is CastOrder:  # M5-5
		return "cast_order"
	if o is FortifyOrder:  # M3c
		return "fortify_order"
	if o is SiegeOrder:  # M3c
		return "storm_order" if o.is_storm() else "sally_order"
	if o is MoveOrder:
		var kind := siege_kind(o.army_id, o.to)  # M3c: a siege, a relief, the breach or an empty fort
		if kind in ["besiege", "relief", "breach", "empty"]:
			return {"besiege": "siege_move", "relief": "relief", "breach": "breach", "empty": "empty_fort"}[kind]
		var odds := move_odds(o.army_id, o.to)
		if odds.get("fog", false) and (odds.enemy_present or bool(odds.odds.get("no_odds", false))):
			return "view_odds"  # M5-2: odds against what you can see
		if odds.enemy_present:
			return "move_odds"
		return "road_move" if o.is_road_move() else "move_order"
	if o is RecruitOrder and o.is_with_ruler():
		return "field_recruit"
	return "recruit"


func gold_breakdown() -> Dictionary:
	var g := gold_after_recruits()
	return _bd("Gold after recruits", g.text, [_line("Gold now", g.gold_now, ""), _line("Queued recruits", -g.spent, "")],
		"Gold after recruits", g.gold_after)


## Tooltip numbers for a recruit button: what one more of this unit would leave you with. `at` is
## RecruitOrder.AT_RULER for the "Recruit with the Ninth Fang" buttons (Warband Muster).
func recruit_breakdown(unit_type_id: String, at: String = RecruitOrder.AT_CAPITAL) -> Dictionary:
	var g := gold_after_recruits()
	var cost := recruit_cost(unit_type_id)
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id, state) if f else null
	var rules := RulesCodex.text("recruit")
	var title := "Recruit %s" % _unit_name(unit_type_id)
	if at == RecruitOrder.AT_RULER:
		var info := ruler_recruit_info()
		rules = String(info.get("text", RulesCodex.text("field_recruit")))
		title = "Recruit %s with %s" % [_unit_name(unit_type_id), RulerRules.current_name(state, faction_id)]
	var desc := "%s %s" % [Breakdown.unit_type_description(ut, price_text(unit_type_id)) if ut else "", rules]
	if MagicRules.is_mage(ut) and not MagicRules.knows_a_spell(view_state(), faction_id):  # M5-5: the mage gate
		desc = "%s %s" % [MagicRules.mage_gate_reason(view_state(), faction_id, ut), desc]
	var fc := Forecast.recruit(state, faction_id, unit_type_id, orders())  # M4-2: Blood Levy's wounded arrivals
	if fc.ok and int(fc.hp) < int(fc.max_hp):
		desc = "%s %s" % [fc.text, desc]
	if state.sieges and at != RecruitOrder.AT_RULER:  # M3c: the fort, its count, and the army it joins
		var at_fort := Forecast.recruit_at(state, faction_id, unit_type_id, at, orders())
		desc = "%s %s %s" % [String(at_fort.text), desc, RulesCodex.text("recruit_at_forts")]
	return _bd(title, desc.strip_edges(), [_line("Gold left after queued recruits", g.gold_after, ""),
		_line("Cost of one %s" % _unit_name(unit_type_id), -cost, _price_note(unit_type_id))],
		"Gold left if you recruit it", g.gold_after - cost)


# --- forts and sieges (M3c S-3, #101; design/M3C_SIEGES.md §9) -----------------------------------------

## What a move of `army_id` into `to` meets at a fort (§3.9, §9.2): "besiege" (an enemy fort with standing walls
## and a garrison inside), "breach" (its walls are down), "empty" (an enemy or neutral fort nobody holds),
## "relief" (your own besieged fort), "own" (your own fort, with no siege), or "" (no sieges, or no fort there).
func siege_kind(army_id: String, to: String) -> String:
	var view := view_state()
	if view == null or not view.sieges:
		return ""
	var dest := view.find_province(to)
	var army := view.find_army(army_id)
	if dest == null or army == null or dest.fort_level <= 0 or army.location == to:
		return ""
	if dest.owner == faction_id:
		return "relief" if SiegeRules.siege_stands(view, to) else "own"
	if SiegeRules.garrison(view, to).is_empty():
		return "empty"
	return "breach" if dest.walls <= 0 else "besiege"


## The garrison armies that come out to join a relief of `to` by `army_id` (§3.6): your armies inside with no
## move queued, the ruler's included (the caller leaves it in). [] when the move is no relief, or the walls are
## down (the battle there then comes on its own).
func relief_garrison(army_id: String, to: String) -> Array:
	if siege_kind(army_id, to) != "relief" or view_state().find_province(to).walls <= 0:
		return []
	var moving := {}
	for o in orders():
		if o is MoveOrder:
			moving[o.army_id] = true
	return SiegeRules.garrison(view_state(), to).filter(func(a): return not moving.has(a.id) and a.id != army_id)


## The move preview (queued false) or the order line (queued true) of a move into a fort: Besiege with Storm now,
## a relief with the garrison coming out, the breach, an empty fort taken, or your own fort. "" for any other
## move. `others` are the faction's other orders (the move itself left out); `queued_move` is the queued order
## itself for an order line (a click's move for a preview).
func siege_move_text(army_id: String, to: String, others: Array, queued: bool, queued_move: MoveOrder = null) -> String:
	var kind := siege_kind(army_id, to)
	if kind.is_empty():
		return ""
	var view := view_state()
	var move: MoveOrder = queued_move if queued_move != null else move_order_for(army_id, to)
	var f := Forecast.move(view, faction_id, move, others)
	if not f.ok:
		return ""
	var arrive := _arrival_sentence(f)
	var p := view.find_province(to)
	var with_move: Array = others + [move]
	match kind:
		"besiege":
			var fc := FortView.siege_forecast(view, faction_id, to, with_move)  # with S-2's odds lines: they are on screen
			var storm_odds := FortView.odds_text(FortView.siege_odds("storm", view, faction_id, to, with_move))
			var odds := ""  # the forecast's own lines carry the storm, the breach and a relief's odds
			if queued and storm_index(to) >= 0:
				var ruler := storm_armies(to).any(func(a): return a.ruler != null)
				return "Storm %s from the march: %s Every army of yours there attacks its garrison behind its walls (%d of %d: +%d defense)%s.%s" % [
					p.name, _decap(arrive), p.walls, SiegeRules.walls_max(p.fort_level), SiegeRules.walls_defense(p.walls),
					", your ruler's included" if ruler else "", " Odds: %s." % storm_odds if not storm_odds.is_empty() else ""]
			var joins := SiegeRules.besiegers(view, to).any(func(a): return a.owner == faction_id)
			var verb := "Join the siege of %s" % p.name if joins else "Besiege %s" % p.name
			if queued:
				return "%s: %s %s To storm instead, tick Storm now under this order.%s" % [verb, _decap(arrive), String(fc.text), odds]
			return "Click to %s. %s %s Storm now instead: after the click, tick Storm now under this move in your orders.%s" % [
				verb.left(1).to_lower() + verb.substr(1), arrive, String(fc.text), odds]
		"breach":
			var fc2 := Forecast.siege(view, faction_id, to, with_move)
			var breach_odds := FortView.odds_text(FortView.siege_odds("breach", view, faction_id, to, with_move))
			return "%s %s %s%s" % ["Attack through the breach at %s:" % p.name if queued else "Click to attack through the breach at %s." % p.name,
				_decap(arrive) if queued else arrive, String(fc2.text), " Odds: %s." % breach_odds if not breach_odds.is_empty() else ""]
		"empty":
			var fc3 := Forecast.siege(view, faction_id, to, with_move)
			return "%s %s %s" % ["Take the fort at %s:" % p.name if queued else "Click to take the fort at %s." % p.name,
				_decap(arrive) if queued else arrive, String(fc3.text)]
		"relief":
			return _relief_text(army_id, to, arrive, with_move, queued)
	return "%s %s %s is your own fort: the army goes inside its walls. If an enemy army arrives there this turn too, you meet outside the walls, where nobody gets walls or ground." % [
		"Move to %s:" % p.name if queued else "Click to order this move.", _decap(arrive) if queued else arrive, p.name]


func _relief_text(army_id: String, to: String, arrive: String, with_move: Array, queued: bool) -> String:
	var view := view_state()
	var p := view.find_province(to)
	var lead := ("Relief for %s:" if queued else "Click to send relief to %s.") % p.name
	if queued:
		arrive = _decap(arrive)
	if p.walls <= 0:
		return "%s %s The walls are down, so the battle there comes this turn on its own, in the open: your army fights beside the garrison, whose fighters keep +%d cover; yours get none." % [
			lead, arrive, FortData.COVER_DEFENSE]
	var text := "%s %s It meets the siege lines outside the walls, in the open, where nobody gets walls or ground and the relief gets no cover." % [lead, arrive]
	var out := []
	var stay := []
	if queued:
		for a in SiegeRules.garrison(view, to):
			(out if sally_index(a.id) >= 0 else stay).append(a)
	else:
		for a in relief_garrison(army_id, to):
			(stay if a.ruler != null else out).append(a)
	var names := func(list: Array) -> String: return RulerRules._and_list(list.map(func(a): return TurnReportText.army_name(view, a.id, a.owner)))
	if not out.is_empty():
		text += " The garrison comes out to join you: %s" % names.call(out)
		text += " (%s %s inside)" % [names.call(stay), "stays" if stay.size() == 1 else "stay"] if not stay.is_empty() else ""
		var them := "them" if out.size() > 1 else "it"
		text += ". " + ("Untick %s in %s's fort panel to keep %s in." % [them, p.name, them] if not queued else "If the relief doesn't arrive, %s inside." % ("they stay" if out.size() > 1 else "it stays"))
	elif not stay.is_empty():
		text += " The garrison stays inside: %s. Tick a sally in %s's fort panel to bring an army out with you." % [names.call(stay), p.name]
	# A preview's odds count the sallies the click will tie to the relief.
	var odds_orders: Array = with_move if queued else with_move + out.map(func(a): return SiegeOrder.sally(a.id, army_id))
	var odds := FortView.odds_text(FortView.siege_odds("relief", view, faction_id, to, odds_orders))
	if not odds.is_empty():
		text += " Odds: %s." % odds
	return text


## "The Crown's 3rd" -> "the Crown's 3rd", for a sentence that goes on after a colon.
static func _decap(text: String) -> String:
	return "t" + text.substr(1) if text.begins_with("The ") else text


## "the Crown's 3rd (Knights) moves from Westwatch to Stonegate and is there at the start of turn 3." from a
## move forecast, without what it says about the enemy there (the siege text says that instead).
static func _arrival_sentence(f: Dictionary) -> String:
	var marker := "at the start of turn %d." % int(f.get("arrival_turn", 0))
	var text := String(f.get("text", ""))
	var at := text.find(marker)
	return text.substr(0, at + marker.length()) if at >= 0 else text


## The fort a queued move at `index` besieges, so its order row offers Storm now; "" for any other order.
func storm_target(index: int) -> String:
	var list := orders()
	if index < 0 or index >= list.size() or not (list[index] is MoveOrder):
		return ""
	return list[index].to if siege_kind(list[index].army_id, list[index].to) == "besiege" else ""


## The index of the queued storm of `province_id`, or -1.
func storm_index(province_id: String) -> int:
	var list := orders()
	for i in list.size():
		if list[i] is SiegeOrder and list[i].is_storm() and list[i].province == province_id:
			return i
	return -1


## The index of `army_id`'s queued sally, or -1.
func sally_index(army_id: String) -> int:
	var list := orders()
	for i in list.size():
		if list[i] is SiegeOrder and list[i].is_sally() and list[i].army_id == army_id:
			return i
	return -1


## The queued relief move into `province_id` (an army of yours from outside), as its army id, or "".
func relief_into(province_id: String) -> String:
	for o in orders():
		if o is MoveOrder and o.to == province_id and siege_kind(o.army_id, province_id) == "relief":
			return o.army_id
	return ""


## Whether a storm of `province_id` would be accepted now: {} or the rules' {"code", "reason"} (OrderBook's).
func storm_check(province_id: String) -> Dictionary:
	if storm_index(province_id) >= 0:
		return {}
	return OrderBook.check_order(state, faction_id, SiegeOrder.storm(province_id), orders())


## Whether `army_id` could sally now (tied to a queued relief into its fort): {} or the rules' reason.
func sally_check(army_id: String) -> Dictionary:
	if sally_index(army_id) >= 0:
		return {}
	var a := state.find_army(army_id)
	var relief := relief_into(a.location) if a != null else ""
	return OrderBook.check_order(state, faction_id, SiegeOrder.sally(army_id, relief), orders())


## The Storm toggle: queues the storm of `province_id` (on) or cancels it. "" or the rules' reason.
func set_storm(province_id: String, on: bool) -> String:
	var i := storm_index(province_id)
	if on and i < 0:
		return _queue(SiegeOrder.storm(province_id))
	if not on and i >= 0:
		return cancel(i)
	return ""


## A Sally tick: queues `army_id`'s sally (tied to a queued relief into its fort, if any) or cancels it.
func set_sally(army_id: String, on: bool) -> String:
	var i := sally_index(army_id)
	if on and i < 0:
		var a := state.find_army(army_id)
		return _queue(SiegeOrder.sally(army_id, relief_into(a.location) if a != null else ""))
	if not on and i >= 0:
		return cancel(i)
	return ""


## Your armies that would storm `province_id` this turn: those there now and those marching in, in id order.
func storm_armies(province_id: String) -> Array:
	var out := []
	var coming := {}
	for o in orders():
		if o is MoveOrder and o.to == province_id:
			coming[o.army_id] = true
	for a in TurnResolver._sorted_armies(state):
		if a.owner == faction_id and (a.location == province_id or coming.has(a.id)):
			out.append(a)
	return out


## Queues a Fortify order for `province_id`. "" or the rules' reason.
func queue_fortify(province_id: String) -> String:
	return _queue(FortifyOrder.new(province_id))


## The index of the queued Fortify order for `province_id`, or -1.
func fortify_index(province_id: String) -> int:
	var list := orders()
	for i in list.size():
		if list[i] is FortifyOrder and list[i].province == province_id:
			return i
	return -1


## The Fortify preview (Forecast.fortify) for `province_id`, after your queued recruits and Fortify orders (those
## before it, when it is queued itself).
func fortify_preview(province_id: String) -> Dictionary:
	var list := orders()
	var i := fortify_index(province_id)
	return Forecast.fortify(state, faction_id, province_id, list.slice(0, i) if i >= 0 else list)


## The order line of the Fortify order at `index`.
func fortify_text(index: int) -> String:
	var o: FortifyOrder = orders()[index]
	var r := _recruit_result_at(index)
	if not r.ok:
		return "Not fortified: %s" % String(r.reason)
	var fc := fortify_preview(o.province)
	if not fc.ok:
		return "Not fortified: %s" % String(fc.reason)
	return "Fortify %s: %s for %d gold (%d gold left). It stands at the end of turn %d if no enemy army stands there, and takes %d recruits a turn from turn %d." % [
		_province_name(o.province), SiegeRules.fort_phrase(int(fc.level)), int(fc.cost), int(r.gold_after), int(fc.stands), int(fc.recruits), int(fc.recruit_from)]


func fortify_breakdown(index: int) -> Dictionary:
	var o: FortifyOrder = orders()[index]
	var r := _recruit_result_at(index)
	if not r.ok:
		return _bd("Fortify order", String(r.reason), [], "Gold spent", 0)
	var desc := "%s %s" % [String(fortify_preview(o.province).text), RulesCodex.text("fortify")]
	var b := _bd("Fortify %s" % _province_name(o.province), desc, [_line("Gold before this order", int(r.gold_after) + int(r.cost), ""),
		_line(SiegeRules.level_name(int(r.to)), -int(r.cost), "paid with your recruits, in the order given")], "Gold left after it", int(r.gold_after))
	b["codex"] = "fortify"
	return b


## The order line of a storm or a sally.
func siege_order_text(o: SiegeOrder) -> String:
	if o.is_storm():
		var p := state.find_province(o.province)
		if p == null:
			return "Storm a place that is not on the map."
		var who := storm_armies(o.province).map(func(a): return TurnReportText.army_name(state, a.id, a.owner))
		var odds := FortView.odds_text(FortView.siege_odds("storm", state, faction_id, o.province, orders()))
		return "Storm the walls of %s with %s: the garrison defends behind %d of %d walls (+%d defense) and its %s. To keep an army out, move it away.%s" % [
			p.name, RulerRules._and_list(who) if not who.is_empty() else "every army of yours there", p.walls, SiegeRules.walls_max(p.fort_level),
			SiegeRules.walls_defense(p.walls), p.terrain, " Odds: %s." % odds if not odds.is_empty() else ""]
	var a := state.find_army(o.army_id)
	if a == null:
		return "Sally out with an army that is not on the map."
	var where := _province_name(a.location)
	var text := "Sally out of %s with %s: it fights the siege lines in the open, keeping +%d cover from the walls. If it loses, it is destroyed." % [
		where, TurnReportText.army_name(state, a.id, a.owner), FortData.COVER_DEFENSE]
	if not o.with_army.is_empty():
		var relief := state.find_army(o.with_army)
		text += " It goes out together with the relief from %s, and stays inside if that relief doesn't arrive." % (_province_name(relief.location) if relief else "an army that is not on the map")
	var odds2 := FortView.odds_text(FortView.siege_odds("sally", state, faction_id, a.location, orders()))
	return text + (" Odds: %s." % odds2 if not odds2.is_empty() else "")


func siege_order_breakdown(o: SiegeOrder) -> Dictionary:
	if o.is_storm():
		var b := Breakdown.walls_defense(state, o.province)
		b.description = "%s %s" % [siege_order_text(o), RulesCodex.text("storm")]
		b["codex"] = "storm"
		return b
	var a := state.find_army(o.army_id)
	var t := FortView.troops_breakdown(state, [a] if a != null else [], "Sallying out", "sally")
	t.description = "%s %s" % [siege_order_text(o), RulesCodex.text("sally")]
	return t


## The forts you can recruit at, for the "Recruit at" picker (§9.1): [{"province", "name", "level", "count"
## (recruits queued there), "limit", "ok", "code", "reason"}], the capital first, then by name. A fort refused by
## the rules (cut off, full, just captured) carries SiegeRules.check_recruit_at's reason.
func recruit_places() -> Array:
	var out := []
	var view := view_state()
	var f := view.find_faction(faction_id) if view != null else null
	if f == null or not view.sieges or f.unit_types.is_empty():
		return out
	var counts := {}
	for o in orders():
		if o is RecruitOrder and not o.is_with_ruler():
			var place := SiegeRules.recruit_place(view, f, TurnResolver.recruit_at(view, f, o))
			counts[place] = int(counts.get(place, 0)) + 1
	var forts := view.provinces.filter(func(p): return p.owner == faction_id and p.fort_level > 0)
	forts.sort_custom(func(a, b): return a.id == f.capital or (b.id != f.capital and a.name < b.name))
	for p in forts:
		var n := int(counts.get(p.id, 0))
		var check := SiegeRules.check_recruit_at(view, faction_id, p.id, f.unit_types[0], n)
		out.append({"province": p.id, "name": p.name, "level": p.fort_level, "count": n, "limit": SiegeRules.recruit_limit(p.fort_level),
			"ok": check.is_empty(), "code": String(check.get("code", "")), "reason": String(check.get("reason", ""))})
	return out


## What can be recruited at the fort `province_id`: the roster, and the siege engine at a keep or a citadel.
func recruitable_types_at(province_id: String) -> Array:
	var out := recruitable_types()
	var view := view_state()
	var p := view.find_province(province_id) if view != null else null
	var engine := SiegeRules.engine_type(faction_id)
	if p != null and view.sieges and engine != null and SiegeRules.may_recruit(p.fort_level, engine):
		out.append(engine)
	return out


## "one Spearmen", "a Siege Ram", "Wallbreakers" for a recruit order line.
func _unit_phrase(unit_type_id: String) -> String:
	var name := _unit_name(unit_type_id)
	if not FortData.engine_by_id(unit_type_id).is_empty():
		return name if name.ends_with("s") else "a %s" % name
	return "one %s" % name


# --- helpers --------------------------------------------------------------------------------------

## Queues `order` through the session's books (session-backed) or this controller's own book.
func _queue(order) -> String:
	_removed = []
	if session != null:
		var why := _not_my_turn()
		if not why.is_empty():
			return why
		why = session.queue_order(order)
		_removed = session.removed_orders()
		return why
	var reason := book.submit(state, faction_id, order)
	_removed = book.last_dropped().map(func(d): return String(d.text))
	return reason


## The orders list's line for a queued Sacrifice order.
func sacrifice_text(order: SacrificeOrder) -> String:
	var mid := order.mandate_id
	var kept := RulerRules.kept_power(state, faction_id)
	return "Sacrifice for %s: %s gives up %d power (%d, +%d for a mid-game sacrifice), keeping %d. It resolves first, so it already counts for your other orders this turn." % [
		RulerRules.mandate_name(mid), RulerRules._cap(RulerRules.current_name(state, faction_id)), RulerRules.sacrifice_cost(mid),
		RulerRules.mandate_cost(mid), MandateData.SACRIFICE_PREMIUM, kept - RulerRules.sacrifice_cost(mid)]


## The price breakdown as a line note when a mandate changes the price ("16 gold (20 - Muster Grounds
## 4)"), "" otherwise, so an M1 tooltip reads exactly as before.
func _price_note(unit_type_id: String) -> String:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id, state) if f else null
	return price_text(unit_type_id) if ut and not RulerRules.price_mods(view_state(), faction_id, ut).is_empty() else ""


func _province_name(province_id: String) -> String:
	var p: Province = state.find_province(province_id) if state else null
	return p.name if p else "a place not on the map"

func _not_my_turn() -> String:
	if session.current_player() == faction_id:
		return ""
	var f: Faction = state.find_faction(faction_id) if state else null
	return "It is not %s's turn, so these orders can't be changed now." % (f.faction_name if f else "this player")


func _move_forecast_at(index: int) -> Dictionary:
	var list := orders()
	var others := list.duplicate()
	others.remove_at(index)
	return Forecast.move(view_state(), faction_id, list[index], others)


func _recruit_result_at(index: int) -> Dictionary:
	var list := orders()
	var k := 0
	for i in index:
		if list[i] is RecruitOrder or list[i] is FortifyOrder:  # M3c: Fortify orders are paid in the same list
			k += 1
	return gold_after_recruits().results[k]


func _unit_name(unit_type_id: String) -> String:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id, state) if f else null
	return ut.name if ut else "unknown unit"


func _capital_name() -> String:
	var f := state.find_faction(faction_id)
	var p: Province = state.find_province(f.capital) if f else null
	return p.name if p else "your capital"


static func _bd(title: String, description: String, lines: Array, total_label: String, total: int) -> Dictionary:
	return {"title": title, "description": description, "lines": lines, "total_label": total_label, "total": total}


static func _line(label: String, value: int, note: String) -> Dictionary:
	return {"label": label, "value": value, "note": note}
