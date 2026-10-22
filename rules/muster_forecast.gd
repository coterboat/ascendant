class_name MusterForecast
## ARM-1 (design/ARM1_SPLIT_MERGE.md §7): what a muster would do, before it is ordered. Pure: it reads a start-of-turn state, the
## plan and one candidate MusterOrder, and changes none of them. The army card shows it as you drag; OrderBook's refusal reasons
## come from the same refusal() (MusterRules holds the rules; this is where they are asked).
##
##   of(state, fid, candidate, orders)   the forecast of adding `candidate` to the plan `orders`
##   refusal(board, fid, candidate)      {} when it may be ordered on `board`, otherwise {"code", "reason"}
##   army_summary(board, army)           one army as the forecast lists it
##   recruit_destinations(board, ...)    where each queued recruit would join
##
## of() returns:
##   "ok", "code", "reason"       whether the candidate may be ordered (a refusal has no more than these and "text"/"armies": [])
##   "text"                       the order in a sentence, then what changes ("Split Knights from the Crown's 1st into ...")
##   "armies"                     each army involved, in the order the order names them: {"id", "name", "new" (it does not exist
##                                yet), "gone" (it will not exist), "before", "after"}, where before/after (or {} for an army that
##                                is not there) are army_summary's: {"id", "name", "units" (type ids), "unit_names", "commander"
##                                (type id or ""), "commander_name", "engines", "fighters", "strength", "sight" (provinces),
##                                "sight_why" ("ruler" | "commander" | "scout" | ""), "location", "blessed" (the blessing's
##                                ritual name or ""), "covered" (fighters it covers), "outside" (fighters outside it)}
##   "dropped"                    the orders in the plan the candidate would drop, with their plain reasons: [{"order", "reason", "text"}]
##   "recruits"                   the plan's recruits and where each would join with the candidate: [{"index", "unit", "army", "name",
##                                "new", "was" (the army it would join without the candidate), "outside" (the blessing it is outside
##                                of, or ""), "text" ("joins the Crown's 4th if it is still at Crownkeep")}]
##   "outside"                    fighters that would join an army under a blessing: [{"army", "name", "count", "ritual", "text"}]
##   "battle"                     a note when one part of an army holds a province and another marches ("" otherwise)
##   "lines"                      one line per army: "the Crown's 1st: ... (strength 44, sees 2) becomes ..."

const SIGHT_WORDS := {"ruler": "its ruler", "commander": "its commander", "scout": "a scout"}


## {} when `order` may be ordered on `board` (the state after the plan's sacrifice and the musters before it), otherwise
## {"code", "reason"}. OrderBook.check_order and of() both ask here.
static func refusal(board: GameState, faction_id: String, order: MusterOrder) -> Dictionary:
	return MusterRules.check(board, faction_id, order)


static func of(state: GameState, faction_id: String, candidate: MusterOrder, orders: Array = []) -> Dictionary:
	var before_board := RulerRules.state_after_orders(state, faction_id, orders)
	var why := refusal(before_board, faction_id, candidate)
	if not why.is_empty():
		return {"ok": false, "code": String(why.code), "reason": String(why.reason), "text": String(why.reason), "armies": [], "dropped": [],
			"recruits": [], "outside": [], "battle": "", "lines": []}
	var after_board := before_board.deep_copy([])
	if after_board == null:
		return {"ok": false, "code": "no_board", "reason": "The board could not be copied to forecast on.", "text": "", "armies": [], "dropped": [],
			"recruits": [], "outside": [], "battle": "", "lines": []}
	var applied := MusterRules.apply(after_board, faction_id, candidate)
	var info: Dictionary = applied.info
	# The armies it touches, in the order it names them.
	var ids := [String(info.from)]
	if String(info.to) != String(info.from):
		ids.append(String(info.to))
	var armies := []
	for id in ids:
		var b := before_board.find_army(id)
		var a := after_board.find_army(id)
		armies.append({"id": id, "name": TurnReportText.army_name(after_board, id, faction_id), "new": b == null, "gone": a == null,
			"before": army_summary(before_board, b) if b != null else {}, "after": army_summary(after_board, a) if a != null else {}})
	# What the plan loses to it.
	var without: Array = OrderBook.recheck(state, faction_id, orders).dropped.map(func(d): return d.order)
	var plan := orders.duplicate()
	plan.append(candidate)
	var with := OrderBook.recheck(state, faction_id, plan)
	var dropped := []
	for d in with.dropped:
		if not without.has(d.order):
			dropped.append({"order": d.order, "reason": String(d.reason), "text": String(d.text)})
	var kept: Array = with.kept  # the plan the candidate leaves
	var outside := []
	for row in info.outside:
		var e := MagicRules._enchantment(after_board, String(row.blessing))
		var ritual := MagicRules.spell_name(String(e.ritual)) if not e.is_empty() else "blessing"
		var name := TurnReportText.army_name(after_board, String(row.army), faction_id)
		var who := _counted(after_board, faction_id, Array(row.get("types", [])))
		var plural := int(row.count) > 1 or TurnReportText._plural_word(who.trim_prefix("1 "))
		outside.append({"army": String(row.army), "name": name, "count": int(row.count), "ritual": ritual,
			"text": "%s join%s %s; its %s won't cover %s" % [who, "" if plural else "s", name, ritual, "them" if plural else "it"]})
	var forecast := {"ok": true, "code": "", "reason": "", "armies": armies, "dropped": dropped, "outside": outside, "info": info}
	forecast["recruits"] = recruit_destinations(state, faction_id, kept, before_board, after_board)
	forecast["battle"] = _battle_note(state, faction_id, kept, after_board, ids)
	forecast["lines"] = _lines(armies)
	forecast["text"] = _text(before_board, faction_id, candidate, forecast)
	return forecast


# --- one army ---------------------------------------------------------------------------------------------------

## `army` as the forecast lists it: its units, commander, engines, rough strength (attack + defense of every unit and the
## commander: the army card's number), sight, name and how much of it its blessing covers.
static func army_summary(board: GameState, army: Army) -> Dictionary:
	var units := []
	var names := []
	for u in army.units:
		units.append(u.type.id)
		names.append(u.type.name)
	var sight := _sight(army)
	var cov := MagicRules.blessing_coverage(board, army)
	var ritual := ""
	if not cov.blessing.is_empty():
		ritual = MagicRules.spell_name(String(cov.blessing.ritual))
	return {"id": army.id, "name": TurnReportText.army_name(board, army.id, army.owner), "units": units, "unit_names": names,
		"commander": army.commander.type.id if army.commander != null else "",
		"commander_name": army.commander.type.name if army.commander != null else "",
		"engines": army.engines, "fighters": units.size() + (1 if army.commander != null else 0),
		"strength": StubBattleResolver.army_strength(army), "sight": int(sight.range), "sight_why": String(sight.why),
		"location": army.location, "blessed": ritual, "covered": int(cov.covered), "outside": int(cov.outside)}


## How far `army` sees and why (the fog rules' own answer: 2 with a ruler, a commander or a scout, otherwise 1).
static func _sight(army: Army) -> Dictionary:
	return FogRules.army_sight(army)


# --- recruits -------------------------------------------------------------------------------------------------------

## Where each recruit in `orders` would join, on `after_board` (the board with the candidate), and where it would have joined on
## `before_board`: [{"index" (in `orders`), "unit", "army", "name", "new", "was", "outside", "text"}]. A recruit joins the first
## army of its faction at its place, by id as TEXT ("kingdom-10" before "kingdom-2", as TurnResolver._add_recruit sorts), that is
## not a ruler's (and for a commander has none), counting the armies the plan marches in and not those it marches out; so the
## forecast says "joins the Crown's 4th if it is still at Crownkeep" and means it conditionally (a battle can end it).
static func recruit_destinations(state: GameState, faction_id: String, orders: Array, before_board: GameState, after_board: GameState) -> Array:
	var out := []
	var faction := after_board.find_faction(faction_id)
	if faction == null:
		return out
	for i in orders.size():
		var o = orders[i]
		if not (o is RecruitOrder):
			continue
		var ut := TurnResolver.recruitable_type(faction, o.unit_type_id, after_board)
		if ut == null:
			continue
		var place := _recruit_place(state, after_board, faction, o)
		var now := _destination(orders, after_board, faction, ut, place)
		var was := _destination(orders, before_board, faction, ut, place)
		var row := {"index": i, "unit": ut.name, "army": now.id, "name": now.name, "new": bool(now.new), "was": String(was.id), "outside": "",
			"place": TurnResolver._province_name(after_board, place)}
		var text := ""
		if bool(now.new):
			text = "forms a new army, %s, at %s" % [now.name, row.place]
		else:
			var blessing := MagicRules.blessing_of(after_board, String(now.id))
			if not blessing.is_empty() and String(blessing.faction) == faction_id:
				row["outside"] = MagicRules.spell_name(String(blessing.ritual))
			text = "joins %s if it is still at %s%s" % [now.name, row.place, ", outside its %s" % row.outside if not String(row.outside).is_empty() else ""]
		row["text"] = text
		out.append(row)
	return out


static func _recruit_place(state: GameState, board: GameState, faction: Faction, order: RecruitOrder) -> String:
	if order.at == RecruitOrder.AT_RULER:
		return TurnResolver.muster_province(state, faction.id)
	var where := TurnResolver.recruit_at(board, faction, order)
	return faction.capital if where.is_empty() else where


## The army a recruit of `ut` at `place` would join on `board`, given the plan's moves: {"id", "name", "new"}. A new army is named
## by the id the faction would hand out next.
static func _destination(orders: Array, board: GameState, faction: Faction, ut: UnitType, place: String) -> Dictionary:
	var leaving := {}
	var arriving := []
	for o in orders:
		if o is MoveOrder:
			var a := board.find_army(o.army_id)
			if a == null or a.owner != faction.id:
				continue
			if a.location == place and o.to != place:
				leaving[a.id] = true
			elif a.location != place and o.to == place:
				arriving.append(a)
	var here := arriving.duplicate()
	for a in board.armies:
		if a.owner == faction.id and a.location == place and not leaving.has(a.id):
			here.append(a)
	here.sort_custom(func(x, y): return x.id < y.id)  # as TEXT, as the recruitment phase sorts
	for a in here:
		var fits: bool = a.ruler == null
		if SiegeRules.is_engine(ut):
			fits = SiegeRules.can_carry(a)
		elif ut.is_commander:
			fits = fits and a.commander == null
		if fits:
			return {"id": a.id, "name": TurnReportText.army_name(board, a.id, faction.id), "new": false}
	var next := String(board.peek_army_ids(faction.id, 1)[0])
	return {"id": next, "name": TurnReportText.army_name(board, next, faction.id), "new": true}


# --- the battle note --------------------------------------------------------------------------------------------------

## "The part that stays (the Crown's 1st) defends Crownkeep; the part that marches (the Crown's 4th) goes to Westwatch and fights
## there as an army of its own." when the candidate leaves armies of the faction at one province, some with a move out and some
## without; "" otherwise.
static func _battle_note(state: GameState, faction_id: String, plan: Array, board: GameState, touched: Array) -> String:
	var moves := {}
	for o in plan:
		if o is MoveOrder:
			moves[o.army_id] = o
	var place := ""
	for id in touched:
		var a := board.find_army(String(id))
		if a != null:
			place = a.location
			break
	if place.is_empty():
		return ""
	var stay := []
	var march := []
	for a in board.armies:
		if a.owner != faction_id or a.location != place:
			continue
		if moves.has(a.id):
			march.append(a)
		else:
			stay.append(a)
	if stay.is_empty() or march.is_empty():
		return ""
	var touched_here := false
	for a in stay + march:
		if touched.has(a.id):
			touched_here = true
	if not touched_here:
		return ""
	var holders := _names(board, faction_id, stay)
	var walkers := _names(board, faction_id, march)
	var goes := []
	for a in march:
		var to := TurnResolver._province_name(board, moves[a.id].to)
		if not goes.has(to):
			goes.append(to)
	var rivals := []
	for a in board.armies:
		if a.owner != faction_id and goes.has(TurnResolver._province_name(board, a.location)) and a.owner != IndependentData.FACTION_ID:
			var n := "the " + TurnResolver._faction_name(board, a.owner)
			if not rivals.has(n):
				rivals.append(n)
	var meets := "fights there as %s of its own" % ("an army" if march.size() == 1 else "armies")
	if not rivals.is_empty():
		meets = "meets %s there as %s of its own" % [RulerRules._and_list(rivals), "an army" if march.size() == 1 else "armies"]
	return "The part that stays (%s) defends %s; the part that marches (%s) goes to %s and %s." % [holders,
		TurnResolver._province_name(board, place), walkers, RulerRules._or_list(goes) if goes.size() > 1 else goes[0], meets]


static func _names(board: GameState, faction_id: String, armies: Array) -> String:
	var ids := armies.map(func(a): return a.id)
	return RulerRules._and_list(TurnReportText.sort_ids(ids).map(func(id): return TurnReportText.army_name(board, String(id), faction_id)))


# --- words ------------------------------------------------------------------------------------------------------------

static func _count_words(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## "2 Knights", "1 Knight Captain and 2 Spearmen": the unit type ids counted by type, with digits (a forecast shows numbers).
static func _counted(state: GameState, faction_id: String, type_ids: Array) -> String:
	var order := []
	var counts := {}
	for id in type_ids:
		if not counts.has(id):
			order.append(id)
			counts[id] = 0
		counts[id] += 1
	var parts := []
	for id in order:
		var name := MusterRules._type_name(state, faction_id, String(id))
		parts.append("%d %s" % [counts[id], name if counts[id] == 1 else TurnReportText._plural_name(name)])
	return RulerRules._and_list(parts) if not parts.is_empty() else "1 fighter"


## One army's make-up in words: "Spearmen and Knights, Knight Captain, 1 Siege Ram".
static func summary_words(s: Dictionary) -> String:
	if s.is_empty():
		return "not there"
	var parts := []
	var counts := {}
	var order := []
	for n in s.unit_names:
		if not counts.has(n):
			counts[n] = 0
			order.append(n)
		counts[n] += 1
	var units := []
	for n in order:
		units.append(String(n) if counts[n] == 1 else "%d %s" % [counts[n], TurnReportText._plural_name(String(n))])
	if not units.is_empty():
		parts.append(RulerRules._and_list(units))
	if not String(s.commander_name).is_empty():
		parts.append(String(s.commander_name))
	if int(s.engines) > 0:
		parts.append("%d engine%s" % [int(s.engines), "" if int(s.engines) == 1 else "s"])
	return ", ".join(parts) if not parts.is_empty() else "no one"


static func _lines(armies: Array) -> Array:
	var out := []
	for row in armies:
		var b: Dictionary = row.before
		var a: Dictionary = row.after
		var left := "%s (strength %d, sees %d)" % [summary_words(b), int(b.strength), int(b.sight)] if not b.is_empty() else ""
		var right := "%s (strength %d, sees %d)" % [summary_words(a), int(a.strength), int(a.sight)] if not a.is_empty() else ""
		if b.is_empty():
			out.append("%s, a new army: %s" % [RulerRules._cap(String(row.name)), right])
		elif a.is_empty():
			out.append("%s: %s, merged away and gone" % [RulerRules._cap(String(row.name)), left])
		else:
			out.append("%s: %s becomes %s" % [RulerRules._cap(String(row.name)), left, right])
	return out


static func _text(board: GameState, faction_id: String, candidate: MusterOrder, f: Dictionary) -> String:
	var parts := [MusterRules.order_text(board, faction_id, candidate)]
	parts.append_array(f.lines.map(func(l): return String(l) + "."))
	for row in f.outside:
		parts.append(RulerRules._cap(String(row.text)) + ".")
	var info: Dictionary = f.info
	if info.has("flame"):
		# CW-2 (design/CANDLEWAKE.md §2.1, the director's ARM-1 rule): a merge or transfer takes the lower flame.
		parts.append("%s flame falls from %d to %d: a merge takes the lower flame." % [RulerRules._cap(TurnReportText._possessive(
			TurnReportText.army_name(board, String(info.to), faction_id))), int(info.flame.from), int(info.flame.to)])
	if bool(info.get("commander_left", false)):
		parts.append("Both armies have a commander, so the commander of %s stays behind as an army of its own." % TurnReportText.army_name(board, String(info.from), faction_id))
	for d in f.dropped:
		parts.append(String(d.text))
	for r in f.recruits:
		if String(r.was) != String(r.army):
			parts.append("Your %s recruit %s." % [r.unit, r.text])
	if not String(f.battle).is_empty():
		parts.append(String(f.battle))
	return " ".join(parts)
