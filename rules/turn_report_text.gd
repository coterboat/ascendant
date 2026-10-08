class_name TurnReportText
## The turn report's lines, as players read them (#55; the play critic's review in
## playtest/reviews/2026-10-03-1f9dd26-turn-resolver-events.md). Pure: no nodes, no scenes, and it never
## changes an event or a state.
##
## The resolver's own event "text" stays exactly as it was: it is part of every recorded game's digest
## (tests/fixtures/main_records.json), and no new field goes into events or saves. So the report writes its
## lines here, when it is shown, from each event's structured fields, the other events of the turn and the
## state after the turn. A loaded game reads exactly like a game just played.
##
##   rows(events, state, viewer = "", before = null) -> [{"event", "text"}]   the report, in display order
##   line(event, events, state, viewer = "", before = null) -> String         one event's line
##   display_order(events, state) -> Array        the events in report order, moves grouped by destination
##   army_name(state, army_id, owner = "") -> String    an army's name for life ("the Crown's 3rd")
##   describe_army(army, state = null) -> String  an army in one line, for Army.get_description()
##   third_person(reason, faction_name) -> String a rejection reason told about a faction, not to "you"
##
## `state` is the state after the turn (GameSession.state()). `before`, the state at the start of the turn,
## is optional: the game never passes it (a loaded game doesn't have it). Tests pass it to name the units of
## armies the test battle rules (StubBattleResolver) destroyed, which carry no battle report.
##
## The rules of #55:
##   1. Stable army names. An army is named once and keeps the name until it is gone: a ruler's army by its
##      ruler ("King Corvane I"), every other army by its number, "the Crown's 3rd". The number is the one in
##      its id, which the game hands out once, in the order each faction raises its armies (its own count,
##      #94), and never reuses, so a name never changes when other armies die, move or are raised. Numbers
##      sort as numbers. The map, the orders list, the forecasts, the order checks and the battle screens use
##      the same names (army_title, log_armies).
##   2. Battle lines name the units on each side and the outcome: "Aurel Crown's Knights (20 hp) beat
##      Thornmane Clans' Tuskers (14 hp) ... The Tuskers (the Clans' 5th) were destroyed; the Knights (the
##      Crown's 3rd) lost no fighters."
##   3. A border battle is armies that "tried to swap places".
##   4. An exact tie is settled by "a 50/50 roll" (between two sides; "an even roll" among more).
##   5. A capture says what happened to the defenders: "Wildmoor fell to Aurel Crown: its defenders (the
##      Clans' 4th) marched out and died on the Thornvale border". "Unopposed" only when nobody left it.
##   6. A rejected order says the result: where the army stays, and for a recruit short of gold what it
##      cost, what the faction had, and whether this turn's income would have covered it. No lone "you".
##   7. Moves are grouped by destination.
##   8. Forts and sieges (M3c, design/M3C_SIEGES.md §9.4), in a game with sieges:
##      - a recruit's line names its fort and count, "(keep, 3 of 4 this turn)", and a capture's says the fort came
##        with it, "It came with its keep (walls 2 of 6): ..." (both from the events' numbers);
##      - an open or breach battle at a fort says where the armies met: "through the breach", "outside the walls,
##        as the garrison sallied", "... as a relief arrived";
##      - every turn word is the reader's: the report of turn T is read at the start of turn T + 1, the turn the top
##        bar shows, so a siege line says "this turn (T + 1)", "next turn (T + 2)", "in 3 turns (turn T + 3)"
##        (reader_turn, reader_end), where the event's own text says "next turn (T + 1)". The phrase comes from the
##        event's numbers (breach_turn, cut_off_from, battle_turn, recruit_from); the rest of the line is the
##        resolver's own words, so the two never disagree on anything else.

const BORDER := "border_battle"
const BATTLE := "battle"
const ORDINAL_WORDS := ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
## Event types whose lines name armies (the report's tooltip points at the codex entry on army names).
const NAMES_ARMIES := ["army_moved", "order_rejected", "border_battle", "battle", "captured", "recruited"]
## A one-line explanation of army names for tooltips (RulesCodex "army_names" has the full text).
const NAMES_HINT := "Every army keeps one name until it is gone: a ruler's army is named after its ruler, and every other army by its number, like the Crown's 3rd."


# --- the report -----------------------------------------------------------------------------------

## The report's lines in display order: [{"event": the event, "text": its line}]. Without a state the
## lines are the events' own text, in resolver order.
static func rows(events: Array, state: GameState, viewer: String = "", before: GameState = null) -> Array:
	var out := []
	if state == null:
		for e in events:
			if not is_beat(e, events):
				out.append({"event": e, "text": own_text(e, viewer)})
		return out
	var ctx := _context(events, state, before, viewer)
	var texts := {}
	for i in events.size():
		texts[i] = _line_at(i, ctx)
	for i in _order(events, state):
		if not is_beat(events[i], events):
			out.append({"event": events[i], "text": texts[i]})
	return out


## M5-6: true for a board beat whose sentence another line of the same report already says, so the report shows it
## once: enchantment_began and summoned (the ritual_cast line says what began and who answered), and fort_raised when
## the same report holds its ritual_cast (a rival who reads only the public fort_raised still gets its line).
static func is_beat(e: Dictionary, events: Array) -> bool:
	match String(e.get("type", "")):
		"enchantment_began", "summoned":
			return events.any(func(o): return String(o.get("type", "")) == "ritual_cast")
		"fort_raised":
			var pid := String(e.get("numbers", {}).get("province", ""))
			return events.any(func(o): return String(o.get("type", "")) == "ritual_cast" and String(o.get("numbers", {}).get("fort", "")) == pid)
	return false


## One event's line. `events` is the whole turn's report it belongs to (it reads the other events: who
## moved where, who died, the faction's income).
static func line(e: Dictionary, events: Array, state: GameState, viewer: String = "", before: GameState = null) -> String:
	if state == null:
		return own_text(e, viewer)
	var all := events
	var index := -1
	for i in events.size():
		if is_same(events[i], e):
			index = i
	if index < 0:
		all = events.duplicate()
		all.append(e)
		index = all.size() - 1
	return _line_at(index, _context(all, state, before, viewer))


## The events in display order: the resolver's order, except that the moves of the movement phase are
## grouped by destination (rule 7), destinations in name order and each destination's moves in the order
## the resolver made them.
static func display_order(events: Array, state: GameState) -> Array:
	var out := []
	for i in _order(events, state):
		out.append(events[i])
	return out


static func _order(events: Array, state: GameState) -> Array:
	var out := []
	var i := 0
	while i < events.size():
		if not _is_plain_move(events[i]):
			out.append(i)
			i += 1
			continue
		var run := []
		while i < events.size() and _is_plain_move(events[i]):
			run.append(i)
			i += 1
		var keyed := []
		for k in run.size():
			var dest := _province_name(state, String(Array(events[run[k]].get("provinces", [])).back()))
			keyed.append([dest, k, run[k]])
		keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for kv in keyed:
			out.append(kv[2])
	return out


static func _is_plain_move(e: Dictionary) -> bool:
	return String(e.get("type", "")) == "army_moved" and String(e.get("phase", "")) == "movement" \
		and not Array(e.get("provinces", [])).is_empty()


# --- army names (rule 1) --------------------------------------------------------------------------

## An army's name for life: its ruler's name for a ruler's army, otherwise "the Crown's 3rd" from the
## number in its id. `owner` is needed only for an army that is not in `state` and whose id has no faction.
static func army_name(state: GameState, army_id: String, owner: String = "", ruler_name: String = "") -> String:
	if not ruler_name.is_empty():
		return ruler_name
	var a: Army = state.find_army(army_id) if state != null else null
	if a != null and a.ruler != null:
		return a.ruler.type.name
	if army_id.begins_with(IndependentData.ARMY_PREFIX):  # IND-1: "the Highcrag Hillguard", named for its province
		var p: Province = state.find_province(army_id.trim_prefix(IndependentData.ARMY_PREFIX)) if state != null else null
		if p != null:
			return "the %s %s" % [p.name, IndependentData.garrison_kind(p.terrain)]
	var fid := owner
	if fid.is_empty():
		fid = a.owner if a != null else faction_of(army_id)
	var n := army_number(army_id)
	if n <= 0:
		return "an army of %s" % _faction_name(state, fid)
	return "%s %s" % [_possessive(faction_short(state, fid)), ordinal(n)]


## The number in an army id ("kingdom-12" -> 12), or 0 when it has none.
static func army_number(army_id: String) -> int:
	var dash := army_id.rfind("-")
	var digits := army_id.substr(dash + 1) if dash >= 0 else army_id
	return int(digits) if not digits.is_empty() and digits.is_valid_int() else 0


## The faction id at the front of an army id ("kingdom-12" -> "kingdom"), or "".
static func faction_of(army_id: String) -> String:
	if army_id.begins_with(IndependentData.ARMY_PREFIX):
		return IndependentData.FACTION_ID  # IND-1: a garrison's id names its province, not its faction
	var dash := army_id.rfind("-")
	return army_id.substr(0, dash) if dash > 0 else ""


## "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "102nd".
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


## A faction's short name in running text: the last word of its name, with "the" ("the Crown", "the Clans").
static func faction_short(state: GameState, fid: String) -> String:
	var name := _faction_name(state, fid)
	var words := name.split(" ", false)
	return "the %s" % words[words.size() - 1] if words.size() > 1 else name


## Army ids in number order (numbers sort as numbers: 9 before 10).
static func sort_ids(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b):
		var na := army_number(String(a))
		var nb := army_number(String(b))
		return na < nb or (na == nb and String(a) < String(b)))
	return out


## An army as the map, the orders list, the forecasts and the tooltips name it, the way the turn report does:
## its name, who is in it, and where it stands: "the Crown's 3rd (Knights and Spearmen) at Blackwood", or
## "King Corvane I (ruler of the Aurel Crown) at Crownkeep" for a ruler's army. `with_place` false leaves off
## " at <province>". It starts with a lower-case "the"; at the start of a sentence, cap it (RulerRules._cap).
## Without a state, names come from the faction and map data.
static func army_title(state: GameState, army: Army, with_place: bool = true) -> String:
	if army == null:
		return "an army that is not on the map"
	var text := army_name(state, army.id, army.owner)
	if army.ruler != null:
		text += " (ruler of the %s)" % _faction_name(state, army.owner)
	else:
		var entries := _army_entries(army)
		text += " (%s)" % (units_phrase(entries) if not entries.is_empty() else "no one left in it")
	if with_place:
		text += " at %s" % _province_name(state, army.location)
	return text


## An army in one line, with no ids, for Army.get_description(): its army_title.
static func describe_army(army: Army, state: GameState = null) -> String:
	return army_title(state, army)


## The armies of `faction_id`'s side in a battle, from its battle log, as the report names them:
## [{"id", "title": "the Crown's 2nd (Crossbowmen)", "from": the province it came from, in a border battle,
## else ""}], in the log's army order. Who was in each army comes from the log's fighters; where a border
## battle's army came from, from the log's label for it ("... army at Thornvale ..."). [] without a log.
static func log_armies(battle_log, faction_id: String, state: GameState = null) -> Array:
	var out := []
	if not (battle_log is Dictionary):
		return out
	var per := {}
	for f in battle_log.get("fighters", []):
		var id := String(f.get("army", ""))
		if not per.has(id):
			per[id] = []
		_add_entry(per[id], String(f.get("name", "")), String(f.get("role", "unit")))
	var border := String(battle_log.get("kind", "")) == "border"
	for side in battle_log.get("sides", []):
		if String(side.get("faction", "")) != faction_id:
			continue
		for a in side.get("armies", []):
			if not (a is Dictionary) or String(a.get("id", "")).is_empty():
				continue
			var id := String(a.id)
			var entries: Array = per.get(id, [])
			var ruler := ""
			for en in entries:
				if en.role == "ruler":
					ruler = String(en.name)
			var title := army_name(state, id, faction_id, ruler)
			if ruler.is_empty() and not entries.is_empty():
				title += " (%s)" % units_phrase(entries)
			var from := ""
			if border:
				for pid in battle_log.get("provinces", []):
					var place := _province_name(state, String(pid))
					if String(a.get("label", "")).contains(" at %s" % place):
						from = place
			out.append({"id": id, "title": title, "from": from})
	return out


# --- the turn's context ---------------------------------------------------------------------------

## What the lines need to know about the whole turn, gathered once:
##   state, before, events, viewer
##   owners    {army id: faction id}
##   rulers    {army id: ruler name} for every ruler's army the turn mentions
##   units     {army id: [{"name", "count", "role"}]}: who was in it when it moved or fought
##   moved     {army id: its army_moved event}
##   died      {army id: the battle event it was destroyed in}
##   income    {faction id: its income event}
static func _context(events: Array, state: GameState, before: GameState, viewer: String) -> Dictionary:
	var ctx := {"state": state, "before": before, "events": events, "viewer": viewer,
		"owners": {}, "rulers": {}, "units": {}, "moved": {}, "died": {}, "income": {}, "joined": {}}
	for s in [before, state]:
		if s == null:
			continue
		for a in s.armies:
			ctx.owners[a.id] = a.owner
			if a.ruler != null:
				ctx.rulers[a.id] = a.ruler.type.name
	for e in events:
		var type := String(e.get("type", ""))
		var armies: Array = e.get("armies", [])
		var numbers: Dictionary = e.get("numbers", {})
		var factions: Array = e.get("factions", [])
		match type:
			"army_moved":
				if not armies.is_empty():
					ctx.moved[String(armies[0])] = e
					if not factions.is_empty():
						ctx.owners[String(armies[0])] = String(factions[0])
			"battle", "border_battle":
				for id in numbers.get("destroyed", []):
					ctx.died[String(id)] = e
				_read_log(ctx, numbers.get("log", {}))
			"ruler_died":
				var id := String(numbers.get("army", ""))
				if not id.is_empty():
					ctx.rulers[id] = String(numbers.get("name", ctx.rulers.get(id, "")))
			"income":
				if not factions.is_empty():
					ctx.income[String(factions[0])] = e
			"recruited":
				if not armies.is_empty():
					var id := String(armies[0])
					if not ctx.joined.has(id):
						ctx.joined[id] = []
					ctx.joined[id].append(_recruited_unit_name(e, state))
		if type in ["army_moved", "recruited", "captured", "battle", "border_battle"]:
			for id in armies:
				var sid := String(id)
				if not ctx.owners.has(sid) and not faction_of(sid).is_empty():
					ctx.owners[sid] = faction_of(sid)
	# Units: from a battle log (exact, as the army stood when it fought), then the state at the start of the
	# turn, then the state after it without this turn's recruits (an army that didn't fight lost no one).
	if before != null:
		for a in before.armies:
			if not ctx.units.has(a.id):
				ctx.units[a.id] = _army_entries(a)
	for a in state.armies:
		if ctx.units.has(a.id) or not _existed_before(ctx, a.id):
			continue
		ctx.units[a.id] = _without(_army_entries(a), ctx.joined.get(a.id, []))
	return ctx


## Fighters per army from a battle log ({"fighters": [{"army", "role", "name"}]}), in the resolver's order.
static func _read_log(ctx: Dictionary, battle_log) -> void:
	if not (battle_log is Dictionary) or not (battle_log.get("fighters") is Array):
		return
	var per := {}
	for f in battle_log.fighters:
		var id := String(f.get("army", ""))
		if id.is_empty():
			continue
		if not per.has(id):
			per[id] = []
		_add_entry(per[id], String(f.get("name", "")), String(f.get("role", "unit")))
		if String(f.get("role", "")) == "ruler":
			ctx.rulers[id] = String(f.get("name", ""))
	for side in battle_log.get("sides", []):
		for a in side.get("armies", []):
			if a is Dictionary and not String(a.get("id", "")).is_empty():
				ctx.owners[String(a.id)] = String(side.get("faction", ""))
	for id in per:
		if not ctx.units.has(id):  # an army that fought twice moved with what it had in its first battle
			ctx.units[id] = per[id]


## True unless the army was formed by a recruit this turn (it then has no part in the turn's moves).
static func _existed_before(ctx: Dictionary, army_id: String) -> bool:
	if ctx.before != null:
		return ctx.before.find_army(army_id) != null
	for e in ctx.events:
		if String(e.get("type", "")) == "recruited" and bool(e.get("numbers", {}).get("new_army", false)) \
				and Array(e.get("armies", [])).has(army_id):
			return false
		if String(e.get("type", "")) == "ruler_arrived" and Array(e.get("armies", [])).has(army_id):
			return false
	return true


static func _army_entries(a: Army) -> Array:
	var out := []
	for u in a.units:
		_add_entry(out, u.type.name, "unit")
	if a.commander != null:
		_add_entry(out, a.commander.type.name, "commander")
	if a.ruler != null:
		_add_entry(out, a.ruler.type.name, "ruler")
	return out


static func _add_entry(entries: Array, name: String, role: String) -> void:
	for en in entries:
		if en.name == name and en.role == role:
			en.count += 1
			return
	entries.append({"name": name, "count": 1, "role": role})


## `entries` without one fighter of each name in `names` (this turn's recruits that joined the army).
static func _without(entries: Array, names: Array) -> Array:
	var out := entries.duplicate(true)
	for n in names:
		for en in out:
			if en.name == n and en.count > 0:
				en.count -= 1
				break
	return out.filter(func(en): return en.count > 0)


## "Knights", "Spearmen and Knight Captain", "3 Spearmen, 2 Knights and Knight Captain", "King Corvane I".
static func units_phrase(entries: Array) -> String:
	var parts := []
	for role in ["unit", "commander", "ruler"]:
		for en in entries:
			if en.role == role:
				parts.append(String(en.name) if int(en.count) == 1 else "%d %s" % [int(en.count), _plural_name(String(en.name))])
	return RulerRules._and_list(parts)


## A plural verb fits these fighters: more than one, or one unit with a plural name ("Knights", "Spearmen").
static func _plural(entries: Array) -> bool:
	var n := 0
	for en in entries:
		n += int(en.count)
	if n != 1:
		return true
	return _plural_word(String(entries[0].name)) if not entries.is_empty() and entries[0].role == "unit" else false


static func _plural_word(name: String) -> bool:
	return name.ends_with("s") or name.ends_with("men")


static func _plural_name(name: String) -> String:
	return name if _plural_word(name) else name + "s"


# --- one line -------------------------------------------------------------------------------------

static func _line_at(i: int, ctx: Dictionary) -> String:
	var e: Dictionary = ctx.events[i]
	var text := ""
	match String(e.get("type", "")):
		"army_moved":
			text = _moved_line(e, ctx)
		"order_rejected":
			text = _rejected_line(e, i, ctx)
		BORDER, BATTLE:
			text = _battle_line(e, ctx)
		"captured":
			text = _captured_line(e, ctx)
		"recruited":
			text = _recruited_line(e, ctx)
		"siege_started", "walls_damaged", "walls_breached", "siege_lifted", "fort_built":
			text = _siege_line(e, ctx)  # M3c: the reader's turn words
	return text if not text.is_empty() else own_text(e, ctx.viewer)


## The event's own text, as `viewer` reads it (M4-4): a faction's own transformation speaks to it.
static func own_text(e: Dictionary, viewer: String) -> String:
	var factions: Array = e.get("factions", [])
	if ["transformed", "research_done"].has(String(e.get("type", ""))) and not viewer.is_empty() and not factions.is_empty() and String(factions[0]) == viewer:
		var own := String(e.get("numbers", {}).get("own_text", ""))
		if not own.is_empty():
			return own
	return String(e.get("text", ""))


## "the Crown's 3rd (Knights)", or "King Corvane I" for a ruler's army.
static func _ref(id: String, ctx: Dictionary, with_units: bool = true) -> String:
	var name := _name(id, ctx)
	if ctx.rulers.has(id) or not with_units:
		return name
	var entries: Array = ctx.units.get(id, [])
	return name if entries.is_empty() else "%s (%s)" % [name, units_phrase(entries)]


static func _name(id: String, ctx: Dictionary) -> String:
	return army_name(ctx.state, id, String(ctx.owners.get(id, "")), String(ctx.rulers.get(id, "")))


## Names of several armies: "the Clans' 4th", "the Clans' 4th and 6th", "the Crown's 1st and King Corvane I".
static func _names(ids: Array, ctx: Dictionary) -> String:
	var plain := {}  # faction id -> numbers, for armies named by number
	var order := []
	var named := []
	for id in sort_ids(ids):
		var sid := String(id)
		if ctx.rulers.has(sid) or army_number(sid) <= 0:
			named.append(_name(sid, ctx))
			continue
		var fid := String(ctx.owners.get(sid, faction_of(sid)))
		if not plain.has(fid):
			plain[fid] = []
			order.append(fid)
		plain[fid].append(ordinal(army_number(sid)))
	var parts := []
	for fid in order:
		parts.append("%s %s" % [_possessive(faction_short(ctx.state, fid)), RulerRules._and_list(plain[fid])])
	parts.append_array(named)
	return RulerRules._and_list(parts)


# --- moves ----------------------------------------------------------------------------------------

static func _moved_line(e: Dictionary, ctx: Dictionary) -> String:
	var armies: Array = e.get("armies", [])
	var provinces: Array = e.get("provinces", [])
	if armies.is_empty() or provinces.size() < 2:
		return ""
	var id := String(armies[0])
	var s: GameState = ctx.state
	var from := _province_name(s, String(provinces[0]))
	var to := _province_name(s, String(provinces.back()))
	if String(e.get("cause", "")) == "won_border_battle":
		return "%s won the border battle and went on to %s." % [_cap(_name(id, ctx)), to]
	var who := _cap(_ref(id, ctx))
	if String(e.get("cause", "")) == "road_move" and provinces.size() >= 3:
		var via := _province_name(s, String(provinces[1]))
		if String(e.get("numbers", {}).get("rule", "")) == "forest_stride":
			return "%s moved from %s through the forest of %s to %s (Forest Stride)." % [who, from, via, to]
		return "%s moved from %s through %s to %s by the King's Roads." % [who, from, via, to]
	return "%s moved from %s to %s." % [who, from, to]


# --- rejected orders (rule 6) ---------------------------------------------------------------------

static func _rejected_line(e: Dictionary, index: int, ctx: Dictionary) -> String:
	var order: Dictionary = e.get("order", {})
	var factions: Array = e.get("factions", [])
	if factions.is_empty() or not (order is Dictionary):
		return ""
	var fid := String(factions[0])
	var fname := _faction_name(ctx.state, fid)
	var reason := String(e.get("reason", ""))
	match String(order.get("type", "")):
		"move":
			return _rejected_move(e, order, fid, ctx)
		"recruit":
			return _rejected_recruit(e, order, index, fid, ctx)
		"research":
			var node := String(order.get("node", order.get("node_id", "")))
			var what := AscensionRules.node_name(node) if not AscensionRules.node_data(node).is_empty() else "something this game doesn't have"
			return "%s order to research %s was rejected: %s" % [_possessive(fname), what, third_person(reason, fname)]
		"sacrifice":
			var mid := String(order.get("mandate", order.get("mandate_id", "")))
			var what := RulerRules.mandate_name(mid) if not RulerRules.mandate_data(mid).is_empty() else "a mandate this game doesn't have"
			return "%s order to sacrifice power for %s was rejected: %s" % [_possessive(fname), what, third_person(reason, fname)]
	if String(e.get("cause", "")) == "unknown_order":
		return "%s gave an order that was rejected: %s" % [fname, third_person(reason, fname)]
	return ""


static func _rejected_move(e: Dictionary, order: Dictionary, fid: String, ctx: Dictionary) -> String:
	var id := String(order.get("army", ""))
	var s: GameState = ctx.state
	var known: bool = ctx.owners.has(id)
	var fname := _faction_name(s, fid)
	var dest := _province_name(s, String(order.get("to", "")))
	var via := String(order.get("via", ""))
	var what := "%s to %s" % [_ref(id, ctx), dest] if known else "an army that is not on the map to %s" % dest
	if not via.is_empty():
		what += " through %s" % _province_name(s, via)
	var whose := "The order" if known and String(ctx.owners[id]) == fid else "%s order" % _possessive(fname)
	var code := String(e.get("cause", ""))
	var reason := _move_reason(code, String(e.get("reason", "")), id, fname, ctx)
	var text := "%s to move %s was rejected: %s" % [whose, what, reason]
	if not known:
		return text
	var result := _move_result(id, code, ctx)
	return text if result.is_empty() else "%s %s" % [text, result]


## The rejection reason told about the faction, with the army's name where the rules wrote its old label.
static func _move_reason(code: String, reason: String, id: String, fname: String, ctx: Dictionary) -> String:
	match code:
		"already_there":
			var a: Army = ctx.state.find_army(id)
			var here := _province_name(ctx.state, a.location) if a != null else "where it stands"
			return "%s is already in %s, and an army with no move order holds where it is." % [_cap(_name(id, ctx)), here]
		"duplicate_move":
			return "Each army moves once per turn, and %s already had a move order." % _name(id, ctx)
	return third_person(_relabel(reason, id, ctx), fname)


## What became of the army whose move was rejected: it stays where it is, or went on its other order.
static func _move_result(id: String, code: String, ctx: Dictionary) -> String:
	var s: GameState = ctx.state
	var which := "first" if code == "duplicate_move" else "other"
	if ctx.moved.has(id):
		var to := _province_name(s, String(Array(ctx.moved[id].get("provinces", [])).back()))
		return "It moved to %s on its %s order instead." % [to, which] if which == "other" else "It followed its first order, to %s." % to
	var battle: Dictionary = ctx.died.get(id, {})
	if String(battle.get("type", "")) == BORDER:
		return "It followed its %s order and died on the border between %s." % [which, _border_name(battle, s)]
	var subject := _subject(id, ctx)
	var a: Army = s.find_army(id)
	if a != null:
		return "%s %s at %s." % [subject.text, "stay" if subject.plural else "stays", _province_name(s, a.location)]
	if not battle.is_empty():
		var where := _province_name(s, String(Array(battle.get("provinces", [""]))[0]))
		return "%s stayed at %s and %s destroyed in the battle there." % [subject.text, where, "were" if subject.plural else "was"]
	if ctx.before != null and ctx.before.find_army(id) != null:
		return "%s stayed at %s." % [subject.text, _province_name(s, ctx.before.find_army(id).location)]
	return ""


## The army as the subject of a sentence: its units ("The War Bear", "The Tuskers") when it has a name by
## number and its units are known, otherwise its name. {"text", "plural"}.
static func _subject(id: String, ctx: Dictionary) -> Dictionary:
	var entries: Array = ctx.units.get(id, [])
	if ctx.rulers.has(id) or entries.is_empty():
		return {"text": _cap(_name(id, ctx)), "plural": false}
	return {"text": "The %s" % units_phrase(entries), "plural": _plural(entries)}


## `reason` with the army's old place-based label ("the Aurel Crown army at Crownkeep (3 units, led by
## Knight Captain)", TurnResolver.army_label) replaced by its name.
static func _relabel(reason: String, id: String, ctx: Dictionary) -> String:
	var fid := String(ctx.owners.get(id, ""))
	if fid.is_empty():
		return reason
	var places := []
	for p in ctx.state.provinces:
		places.append(_escape(p.name))
	var ords := []
	for w in ORDINAL_WORDS:
		ords.append(w)
	var pattern := "(?:([Tt])he )?(?:(?:%s|number \\d+) )?%s (?:army|ruler [^.]+?) at (?:%s)(?: \\([^)]*\\))?" % [
		"|".join(ords), _escape(_faction_name(ctx.state, fid)), "|".join(places)]
	var re := RegEx.create_from_string(pattern)
	var m := re.search(reason)
	if m == null:
		return reason
	var name := _name(id, ctx)
	if m.get_start() == 0 or m.get_string(1) == "T":
		name = _cap(name)
	return reason.substr(0, m.get_start()) + name + reason.substr(m.get_end())


static func _escape(text: String) -> String:
	var out := ""
	for c in text:
		out += ("\\" + c) if ".^$*+?()[]{}|\\".contains(c) else c
	return out


static func _rejected_recruit(e: Dictionary, order: Dictionary, index: int, fid: String, ctx: Dictionary) -> String:
	var s: GameState = ctx.state
	var fname := _faction_name(s, fid)
	var reason := String(e.get("reason", ""))
	var code := String(e.get("cause", ""))
	var unit := _unit_type_name(s, String(order.get("unit_type", "")))
	var cost := -1
	var had := -1
	if code == "not_enough_gold":
		# The reason was written when the recruit was paid for, with that moment's price and gold (TurnResolver.check_recruit).
		var m := RegEx.create_from_string("^(.+) cost (\\d+) gold, but you only have (\\d+) gold left\\.$").search(reason)
		if m != null:
			unit = m.get_string(1)
			cost = int(m.get_string(2))
			had = int(m.get_string(3))
	var which := _recruit_order_name(index, unit, fid, String(order.get("at", "")), ctx)
	match code:
		"not_enough_gold":
			if cost < 0:
				return ""
			var plural := _plural_word(unit)
			var text := "%s was rejected: %s %s %d gold, and %s had %d gold left." % [which, unit, "cost" if plural else "costs", cost, fname, had]
			var income: Dictionary = ctx.income.get(fid, {})
			if income.is_empty():
				return text + " Recruits are paid before income."
			var earned := int(income.get("numbers", {}).get("income", 0))
			if had + earned >= cost:
				return text + " Recruits are paid before income: this turn's income of %d gold would have covered %s, but it came after." % [earned, "them" if plural else "it"]
			return text + " Recruits are paid before income, and even this turn's income of %d gold would not have covered %s." % [earned, "them" if plural else "it"]
		"capital_not_held":
			var f := s.find_faction(fid)
			var capital := _province_name(s, f.capital) if f != null else "its capital"
			var fell := false
			for other in ctx.events:
				if String(other.get("type", "")) == "captured" and f != null and Array(other.get("provinces", [])).has(f.capital):
					fell = true
			var why := "%s, the capital of %s, fell this turn before recruiting" % [capital, fname] if fell \
				else "%s does not hold its capital, %s" % [fname, capital]
			return "%s was rejected: %s, and a faction can recruit only while it holds its capital. No gold was spent." % [which, why]
	return "%s was rejected: %s" % [which, third_person(reason, fname)]


## "Aurel Crown's third Knights order" (when it gave several), "Aurel Crown's Knights order", "Thornmane
## Clans' Tuskers order with the Ninth Fang". Counts the faction's recruit orders for that unit this turn.
static func _recruit_order_name(index: int, unit: String, fid: String, at: String, ctx: Dictionary) -> String:
	var rank := 0
	var total := 0
	for i in ctx.events.size():
		var other: Dictionary = ctx.events[i]
		if Array(other.get("factions", [])).is_empty() or String(other.factions[0]) != fid:
			continue
		var name := ""
		if String(other.get("type", "")) == "recruited":
			name = _recruited_unit_name(other, ctx.state)
		elif String(other.get("type", "")) == "order_rejected" and other.get("order") is Dictionary \
				and String(other.order.get("type", "")) == "recruit":
			name = _rejected_unit_name(other, ctx.state)
		if name != unit:
			continue
		total += 1
		if i <= index:
			rank = total
	var fname := _faction_name(ctx.state, fid)
	var text := "%s %s order" % [_possessive(fname), unit]
	if total > 1 and rank >= 1:
		text = "%s %s %s order" % [_possessive(fname), _ordinal_word(rank), unit]
	if at == RecruitOrder.AT_RULER:
		var who := RulerRules.current_name(ctx.state, fid)
		text += " with %s" % (who if not who.is_empty() else "its ruler")
	return text


static func _rejected_unit_name(e: Dictionary, s: GameState) -> String:
	var m := RegEx.create_from_string("^(.+) cost \\d+ gold, but you only have \\d+ gold left\\.$").search(String(e.get("reason", "")))
	if m != null:
		return m.get_string(1)
	return _unit_type_name(s, String(e.order.get("unit_type", "")))


static func _ordinal_word(n: int) -> String:
	return ORDINAL_WORDS[n - 1] if n >= 1 and n <= ORDINAL_WORDS.size() else ordinal(n)


## A rejection reason the rules wrote for the player giving the order ("you only have 5 gold left"), told
## about the faction instead, for a report everyone reads: "Aurel Crown only had 5 gold left".
static func third_person(reason: String, faction_name: String) -> String:
	var f := faction_name
	var fs := _possessive(faction_name)
	var swaps := [
		["You don't hold your capital, ", "%s does not hold its capital, " % f],
		[", so you can't recruit. Retake it first.", ", so it can't recruit until it retakes it."],
		["but you only have", "but %s only had" % f],
		["You already gave", "%s had already given" % f],
		["before you end the turn", "before the turn ends"],
		["when you set up a new game", "when a new game is set up"],
		["cancel that order first to choose another mandate", "only the first one counts"],
		["Mandates you already have stay", "Mandates %s already has stay" % f],
		["you have researched", "%s has researched" % f],
		["; you have ", "; %s has " % f],
		["you gain ", "%s gains " % f],
		["you swore", "%s swore" % f],
		["you already own", "%s already owns" % f],
		["you owned", "%s owned" % f],
		["you own", "%s owns" % f],
		["you hold", "%s holds" % f],
		["you can recruit", "it can recruit"],
		["Recruit from your faction's roster.", "A faction recruits from its own roster."],
		["Recruit at your capital instead.", "%s recruits at its capital instead." % f],
		["is not yours", "is not %s" % fs],
		["your own land", "%s own land" % fs],
	]
	var text := reason
	for pair in swaps:
		text = text.replace(pair[0], pair[1])
	text = RegEx.create_from_string("has (\\d+) and gain ").sub(text, "has $1 and gains ", true)
	# Whatever is left: "your" -> the faction's, "you" -> the faction.
	text = RegEx.create_from_string("\\b[Yy]our\\b").sub(text, fs, true)
	text = RegEx.create_from_string("\\b[Yy]ou\\b").sub(text, f, true)
	return text


# --- battles (rules 2-4) --------------------------------------------------------------------------

static func _battle_line(e: Dictionary, ctx: Dictionary) -> String:
	var numbers: Dictionary = e.get("numbers", {})
	var fids: Array = e.get("factions", [])
	var provinces: Array = e.get("provinces", [])
	var winner := String(numbers.get("winner", ""))
	if fids.size() < 2 or provinces.is_empty() or not fids.has(winner):
		return ""
	var s: GameState = ctx.state
	var report: Dictionary = numbers.get("report", {})
	var real := not report.is_empty()
	var defender := String(numbers.get("defender", ""))
	var sides := {}  # faction id -> {"armies", "entries", "size", "report"}
	for fid in fids:
		sides[fid] = _side(String(fid), e, ctx)
	var losers := []
	for fid in fids:
		if fid != winner:
			losers.append(fid)

	var won := _side_phrase(winner, sides[winner], ctx)
	var lost_parts := []
	for fid in losers:
		lost_parts.append(_side_phrase(fid, sides[fid], ctx))
	var beaten := RulerRules._and_list(lost_parts)
	var head: String
	var kind := String(e.get("type", ""))
	if kind == BORDER and provinces.size() >= 2:
		head = "On the border between %s, where they tried to swap places, %s beat %s" % [_border_name(e, s), won, beaten]
	elif defender.is_empty() and not siege_where(e).is_empty():  # M3c: an open or breach battle at a fort
		head = "In %s, %s, %s beat %s" % [_province_name(s, String(provinces[0])), siege_where(e), won, beaten]
	elif defender.is_empty():
		head = "In %s, where %s arrived at the same time, %s beat %s" % [_province_name(s, String(provinces[0])),
			"both" if fids.size() == 2 else "all of them", won, beaten]
	elif winner == defender:
		head = "In %s, %s held %s ground against %s" % [_province_name(s, String(provinces[0])), won,
			"their" if _plural(sides[winner].entries) else "its", beaten]
	else:
		var parts := []
		for fid in losers:
			var phrase := _side_phrase(fid, sides[fid], ctx)
			if fid == defender:
				phrase += ", who %s holding it" % ("were" if _plural(sides[fid].entries) else "was")
			parts.append(phrase)
		head = "In %s, %s attacked %s, and won" % [_province_name(s, String(provinces[0])), won, RulerRules._and_list(parts)]
	if real:
		var n := int(report.get("rounds_fought", 0))
		head += " after %d %s" % [n, "round" if n == 1 else "rounds"]
	var why := String(numbers.get("why", report.get("why", "")))
	var text := "%s: %s." % [head, why] if not why.is_empty() else head + "."

	# What happened to each side.
	var out := []
	for fid in losers:
		out.append(_loser_outcome(String(fid), sides[fid], report, winner, ctx))
	var tail := _winner_outcome(winner, sides[winner], e, real, ctx)
	text += " " + " ".join(out)
	if not tail.is_empty():
		text = text.trim_suffix(".") + "; " + tail
	var extras := _battle_extras(e, winner, sides, real, ctx)
	return text if extras.is_empty() else "%s %s" % [text, extras]


## One side of a battle: its armies (by number), who fought (from the battle report's roster, else the
## armies' units) and its size (hit points in a real battle, strength with the test rules).
static func _side(fid: String, e: Dictionary, ctx: Dictionary) -> Dictionary:
	var numbers: Dictionary = e.get("numbers", {})
	var report: Dictionary = numbers.get("report", {})
	var armies := []
	for id in e.get("armies", []):
		if String(ctx.owners.get(String(id), faction_of(String(id)))) == fid:
			armies.append(String(id))
	var sr := {}
	for side in report.get("sides", []):
		if String(side.get("faction", "")) == fid:
			sr = side
	var entries := []
	if not sr.is_empty():
		var roster: Dictionary = sr.get("roster", {})
		for u in roster.get("units", []):
			entries.append({"name": String(u.get("name", "")), "count": int(u.get("count", 1)), "role": "unit"})
		for c in roster.get("commanders", []):
			_add_entry(entries, String(c.get("name", "")), "commander")
		if roster.get("ruler") is Dictionary and not roster.ruler.is_empty():
			_add_entry(entries, String(roster.ruler.get("name", "")), "ruler")
	else:
		var known := true
		for id in armies:
			if not ctx.units.has(id):
				known = false
		if known:
			for id in armies:
				for en in ctx.units[id]:
					for k in int(en.count):
						_add_entry(entries, String(en.name), String(en.role))
	var size := "%d hp" % int(sr.get("hp_start", 0)) if not sr.is_empty() else str(int(numbers.get("strengths", {}).get(fid, 0)))
	return {"armies": sort_ids(armies), "entries": entries, "size": size, "report": sr}


## "Aurel Crown's Knights (20 hp)"; with unknown units, the armies' names: "the Clans' 5th (15)".
static func _side_phrase(fid: String, side: Dictionary, ctx: Dictionary) -> String:
	if side.entries.is_empty():
		return "%s (%s)" % [_names(side.armies, ctx), side.size]
	if fid == IndependentData.FACTION_ID and not side.armies.is_empty():
		# IND-1 (#142): a garrison goes by its name, "the Ebonpeak Hillguard (2 Hill Slingers and Free Spears, 26 hp)".
		return "%s (%s, %s)" % [_names(side.armies, ctx), units_phrase(side.entries), side.size]
	return "%s %s (%s)" % [_possessive(_faction_name(ctx.state, fid)), units_phrase(side.entries), side.size]


## The side as a sentence's subject: "The Tuskers (the Clans' 5th)". {"text", "plural"}.
## A short side goes by its units, with its armies' names after them; a side of many kinds of fighters, or
## with a ruler, goes by its armies' names alone ("The Clans' 2nd", "The Crown's 1st and King Corvane I").
static func _side_subject(side: Dictionary, ctx: Dictionary) -> Dictionary:
	var has_ruler: bool = side.entries.any(func(en): return en.role == "ruler")
	if side.entries.is_empty() or side.entries.size() > 2 or has_ruler:
		return {"text": _cap(_names(side.armies, ctx)), "plural": side.armies.size() > 1}
	var text := "The %s" % units_phrase(side.entries)
	if not side.armies.is_empty():
		text += " (%s)" % _names(side.armies, ctx)
	return {"text": text, "plural": _plural(side.entries)}


static func _loser_outcome(fid: String, side: Dictionary, report: Dictionary, winner: String, ctx: Dictionary) -> String:
	var subj := _side_subject(side, ctx)
	var were := "were" if subj.plural else "was"
	var they := "they" if subj.plural else "it"
	var their := "their" if subj.plural else "its"
	var sr: Dictionary = side.report
	if report.is_empty() or sr.is_empty():
		return "%s %s destroyed." % [subj.text, were]
	if bool(sr.get("destroyed", false)):
		return "%s %s wiped out." % [subj.text, were]
	if bool(sr.get("routed", false)):
		return "%s broke and fled, and %s destroyed as %s fled (there are no retreats yet)." % [subj.text, were, they]
	if String(report.get("end", "")) == "round_cap" and String(report.get("defender", "")) == winner:
		return "%s could not break the defenders within %d rounds and %s destroyed (there are no retreats yet)." % [
			subj.text, int(report.get("round_cap", AutoBattleResolver.ROUND_CAP)), were]
	return "%s had less of %s strength left when the battle ended and %s destroyed (there are no retreats yet)." % [subj.text, their, were]


## The winner's losses, starting lower-case: "the Knights (the Crown's 3rd) lost no fighters.".
static func _winner_outcome(winner: String, side: Dictionary, e: Dictionary, real: bool, ctx: Dictionary) -> String:
	var subj := _side_subject(side, ctx)
	var who: String = subj.text.substr(0, 1).to_lower() + subj.text.substr(1) if subj.text.begins_with("The ") else subj.text
	if not real:
		return "%s took no losses." % who
	var sr: Dictionary = side.report
	var lost := int(sr.get("fighters_lost", 0))
	var start := int(sr.get("fighters_start", 0))
	if lost == 0:
		return "%s lost no fighters." % who
	var names := []
	var counted := {}
	for n in sr.get("lost", []):
		var key := String(n)
		if not counted.has(key):
			counted[key] = 0
			names.append(key)
		counted[key] += 1
	var parts := []
	for n in names:
		parts.append(n if counted[n] == 1 else "%d %s" % [counted[n], _plural_name(n)])
	var text := "%s lost %d of %d fighters" % [who, lost, start] if lost < start else "%s lost every fighter" % who
	if not parts.is_empty():
		text += " (%s)" % RulerRules._and_list(parts)
	# A winning army whose every fighter fell is gone too.
	var gone := []
	for id in Array(e.get("numbers", {}).get("destroyed", [])):
		if side.armies.has(String(id)) and not ctx.rulers.has(String(id)):
			gone.append(String(id))
	if not gone.is_empty():
		text += ", and %s %s gone" % [_names(gone, ctx), "is" if gone.size() == 1 else "are"]
	return text + "."


## The tie roll, a winner's fallen ruler, Feast of Victory and Red Harvest.
static func _battle_extras(e: Dictionary, winner: String, sides: Dictionary, real: bool, ctx: Dictionary) -> String:
	var numbers: Dictionary = e.get("numbers", {})
	var report: Dictionary = numbers.get("report", {})
	var out := []
	if real and String(numbers.get("tie_break", "")) == "roll":
		var tied := int(numbers.get("log", {}).get("events", [{}]).back().get("tied", 2)) if numbers.get("log") is Dictionary \
			and not Array(numbers.log.get("events", [])).is_empty() else 2
		out.append("The sides had exactly the same share of their strength left, so %s picked the winner." % tie_roll(tied))
	var fallen := []
	for other in ctx.events:
		if String(other.get("type", "")) == "ruler_died" and bool(other.get("numbers", {}).get("won", false)) \
				and Array(e.get("armies", [])).has(String(other.numbers.get("army", ""))) and String(other.numbers.get("winner", "")) == winner:
			fallen.append(String(other.numbers.get("name", "")))
	if not fallen.is_empty():
		out.append("%s won, but %s fell." % [_faction_name(ctx.state, winner), RulerRules._and_list(fallen)])
	var feast: Dictionary = report.get("feast", {})
	if not feast.is_empty():
		var n := int(feast.get("fighters", 0))
		out.append("%s: the %s %s healed to full (+%d hp)." % [RulerRules.mandate_name(RulerRules.FEAST_OF_VICTORY),
			RulerRules._possessive(String(feast.get("name", ""))), "only surviving fighter" if n == 1 else "%d surviving fighters" % n,
			int(feast.get("healed", 0))])
	var harvest: Dictionary = report.get("red_harvest", {})
	if not harvest.is_empty():
		var lost := int(harvest.get("fighters", 0))
		out.append("%s: the %s took %d gold from the %s." % [TurnResolver._red_harvest_name(), _faction_name(ctx.state, winner),
			int(harvest.get("gold", 0)), "enemy fighter lost" if lost == 1 else "%d enemy fighters lost" % lost])
	return " ".join(out)


## "a 50/50 roll" between two tied sides, "an even roll among the 3 tied sides" among more (rule 4).
static func tie_roll(tied: int) -> String:
	return "a 50/50 roll" if tied <= 2 else "an even roll among the %d tied sides" % tied


static func _border_name(e: Dictionary, s: GameState) -> String:
	var provinces: Array = e.get("provinces", [])
	if provinces.size() < 2:
		return "two provinces"
	return "%s and %s" % [_province_name(s, String(provinces[0])), _province_name(s, String(provinces[1]))]


# --- captures (rule 5) ----------------------------------------------------------------------------

static func _captured_line(e: Dictionary, ctx: Dictionary) -> String:
	var provinces: Array = e.get("provinces", [])
	var factions: Array = e.get("factions", [])
	var armies: Array = e.get("armies", [])
	if provinces.is_empty() or factions.is_empty():
		return ""
	var s: GameState = ctx.state
	var pid := String(provinces[0])
	var place := _province_name(s, pid)
	var fid := String(factions[0])
	var fname := _faction_name(s, fid)
	var previous := String(factions[1]) if factions.size() > 1 else ""
	var who := _names(armies, ctx) if not armies.is_empty() else "its army"
	var text := ""
	match String(e.get("cause", "")):
		"battle_victory":
			text = "%s fell to %s: %s won the battle there." % [place, fname, who]
		"undefended_neutral":
			text = "%s fell to %s: %s marched in unopposed (it was neutral)." % [place, fname, who]
		"undefended_enemy":
			text = _fell_text(place, pid, fname, previous, who, ctx)
		_:
			return ""
	var income := int(e.get("numbers", {}).get("income", 0))
	text += " It now pays %s %d gold per turn" % [fname, income]
	text += (" instead of %s." % _faction_name(s, previous)) if not previous.is_empty() else "."
	if bool(e.get("numbers", {}).get("is_capital", false)):
		for f in s.factions:
			if f.capital == pid and f.id != fid:
				text += " This is the capital of %s: it cannot recruit until it retakes it." % f.faction_name
	return text + _fort_came_with(e, fname, ctx)


## An enemy province taken without a battle: what became of the armies that left it this turn.
static func _fell_text(place: String, pid: String, fname: String, previous: String, who: String, ctx: Dictionary) -> String:
	var s: GameState = ctx.state
	var fates := []  # [army id, "border" | "battle" | "moved", the place]
	for id in sort_ids(_left(pid, previous, ctx)):
		var battle: Dictionary = ctx.died.get(id, {})
		var moved: Dictionary = ctx.moved.get(id, {})
		if String(battle.get("type", "")) == BORDER:
			var other := ""
			for p in battle.get("provinces", []):
				if String(p) != pid:
					other = _province_name(s, String(p))
			fates.append([id, "border", other])
		elif not battle.is_empty():
			fates.append([id, "battle", _province_name(s, String(Array(battle.get("provinces", [""]))[0]))])
		elif not moved.is_empty():
			fates.append([id, "moved", _province_name(s, String(Array(moved.get("provinces", [])).back()))])
	if fates.is_empty():
		return "%s fell to %s unopposed: no %s army was there when %s marched in." % [place, fname, _faction_name(s, previous), who]
	var all_died := fates.all(func(f): return f[1] != "moved")
	var same := fates.all(func(f): return f[1] == fates[0][1] and f[2] == fates[0][2])
	var what: String
	if same:
		var ids := fates.map(func(f): return f[0])
		var tail := {"border": "and died on the %s border", "battle": "and were destroyed in %s", "moved": "to %s"}
		what = "its defenders (%s) marched out %s" % [_names(ids, ctx), String(tail[fates[0][1]]) % fates[0][2]]
	else:
		var each := {"border": "%s died on the %s border", "battle": "%s was destroyed in %s", "moved": "%s went to %s"}
		var parts := []
		for f in fates:
			parts.append(String(each[f[1]]) % [_name(f[0], ctx), f[2]])
		what = "its defenders marched out: %s" % RulerRules._and_list(parts)
	return "%s fell to %s%s: %s, and %s marched in." % [place, fname, "" if all_died else " unopposed", what, who]


## The armies of `owner` that started the turn in `pid` and left it: they moved away, or died on a border
## they were crossing out of it.
static func _left(pid: String, owner: String, ctx: Dictionary) -> Array:
	var out := []
	if owner.is_empty():
		return out
	for id in ctx.moved:
		var e: Dictionary = ctx.moved[id]
		var provinces: Array = e.get("provinces", [])
		if String(ctx.owners.get(id, "")) == owner and not provinces.is_empty() and String(provinces[0]) == pid:
			out.append(String(id))
	for id in ctx.died:
		var battle: Dictionary = ctx.died[id]
		if out.has(id) or String(ctx.owners.get(id, "")) != owner or String(battle.get("type", "")) != BORDER:
			continue
		if not Array(battle.get("provinces", [])).has(pid):
			continue
		if _started_in(id, pid, battle, ctx):
			out.append(String(id))
	return out


## Whether an army that died on a border started the turn in `pid`, one end of that border: from the state
## at the start of the turn, else from the battle log's label for it ("... army at Wildmoor ..."), else
## from the winners: in a swap, the losers came from the province the winners went on to.
static func _started_in(id: String, pid: String, battle: Dictionary, ctx: Dictionary) -> bool:
	if ctx.before != null and ctx.before.find_army(id) != null:
		return ctx.before.find_army(id).location == pid
	var place := _province_name(ctx.state, pid)
	var battle_log = battle.get("numbers", {}).get("log", {})
	if battle_log is Dictionary:
		for side in battle_log.get("sides", []):
			for a in side.get("armies", []):
				if a is Dictionary and String(a.get("id", "")) == id:
					return String(a.get("label", "")).contains(" at %s" % place)
	for other in ctx.moved.values():
		if String(other.get("cause", "")) == "won_border_battle" and String(Array(other.get("provinces", [])).back()) == pid:
			return true
	return false


# --- forts and sieges (M3c, rule 8) ---------------------------------------------------------------------

## "this turn (8)", "next turn (9)", "in 3 turns (turn 10)": `turn`, as someone reading at the start of turn `now`
## counts it (the turn they are playing counts as one).
static func reader_turn(turn: int, now: int) -> String:
	var n := turn - now + 1
	if n <= 1:
		return "this turn (%d)" % turn
	if n == 2:
		return "next turn (%d)" % turn
	return "in %d turns (turn %d)" % [n, turn]


## "at the end of this turn (8)", "at the end of next turn (9)", "in 3 turns (end of turn 10)": the end of `turn`, as
## someone reading at the start of turn `now` counts it.
static func reader_end(turn: int, now: int) -> String:
	var n := turn - now + 1
	if n <= 2:
		return "at the end of %s" % reader_turn(turn, now)
	return "in %d turns (end of turn %d)" % [n, turn]


## Where an open or breach battle at a fort was fought, from its siege block (numbers.siege): "through the breach",
## "outside the walls, as the garrison sallied", "outside the walls, as a relief arrived", "outside the walls, as a
## relief arrived and the garrison sallied to join it", "outside the walls". "" for any other battle (a storm, a
## battle away from a fort, or armies arriving together at an empty fort, which "arrived at the same time" says).
static func siege_where(e: Dictionary) -> String:
	var siege = e.get("numbers", {}).get("siege", {})
	if not (siege is Dictionary) or (siege as Dictionary).is_empty():
		return ""
	match String(siege.get("kind", "")):
		"breach":
			return "through the breach"
		"open":
			match String(siege.get("why", "")):
				"sally", "gate":
					return "outside the walls, as the garrison sallied"
				"relief":
					return "outside the walls, as a relief arrived"
				"relief_sally":
					return "outside the walls, as a relief arrived and the garrison sallied to join it"
				"empty":
					return ""
			return "outside the walls"
	return ""


## A siege event's line (rule 8): the event's own words, with its turn phrase in the reader's terms, composed from
## the event's numbers. The report of turn T is read at the start of turn T + 1 (the state after the turn has
## current_turn T).
static func _siege_line(e: Dictionary, ctx: Dictionary) -> String:
	var text := String(e.get("text", ""))
	var numbers: Dictionary = e.get("numbers", {})
	var reported := int((ctx.state as GameState).current_turn)
	var now := reported + 1
	match String(e.get("type", "")):
		"siege_started", "walls_damaged":
			if int(numbers.get("walls", 0)) > 0 and numbers.has("breach_turn"):
				var end := int(numbers.breach_turn)
				text = text.replace("The walls reach 0 %s," % SiegeRules.report_when(end, reported), "The walls reach 0 %s," % reader_end(end, now))
			if int(numbers.get("cut_off_from", 0)) > 0:
				var from := int(numbers.cut_off_from)
				text = text.replace("From next turn (%d) " % from, "From %s " % reader_turn(from, now))
		"walls_breached":
			var battle := int(numbers.get("battle_turn", now))
			text = text.replace("still there next turn (%d)," % battle, "still there %s," % reader_turn(battle, now))
		"siege_lifted":
			text = text.replace("from next turn (%d)." % now, "from %s." % reader_turn(now, now))
		"fort_built":
			var from := int(numbers.get("recruit_from", now))
			text = text.replace("from next turn (%d)," % from, "from %s," % reader_turn(from, now))
	return text


## A capture's fort clause (rule 8), from the event's numbers: " It came with its keep (walls 2 of 6): the Aurel Crown
## can recruit there from next turn (9)." A fort retaken within FortData.RETAKE_TURNS recruits at once. "" when no
## fort came with the province.
static func _fort_came_with(e: Dictionary, fname: String, ctx: Dictionary) -> String:
	var numbers: Dictionary = e.get("numbers", {})
	var level := int(numbers.get("fort_level", 0))
	if level <= 0:
		return ""
	var now := int((ctx.state as GameState).current_turn) + 1
	var from := int(numbers.get("recruit_from", now + 1))
	var when := "from %s" % reader_turn(from, now)
	if from <= now:
		when += ", since they retook it within %d turns of losing it" % FortData.RETAKE_TURNS
	return " It came with its %s (walls %d of %d): the %s can recruit there %s." % [SiegeRules.level_word(level), int(numbers.get("walls", 0)),
		SiegeRules.walls_max(level), fname, when]


## The level word of the fort a recruit was made at ("keep"), from the recruit limit the event carries (each level
## takes a different number), else from the state.
static func _fort_word(numbers: Dictionary, pid: String, s: GameState) -> String:
	for lv in FortData.LEVELS:
		if int(lv.level) > 0 and int(lv.recruits) == int(numbers.get("limit", -1)):
			return SiegeRules.level_word(int(lv.level))
	var p := s.find_province(pid) if s != null else null
	return SiegeRules.level_word(p.fort_level) if p != null else "fort"


# --- recruits -------------------------------------------------------------------------------------

static func _recruited_line(e: Dictionary, ctx: Dictionary) -> String:
	var factions: Array = e.get("factions", [])
	var armies: Array = e.get("armies", [])
	var provinces: Array = e.get("provinces", [])
	var numbers: Dictionary = e.get("numbers", {})
	if factions.is_empty() or armies.is_empty() or provinces.is_empty() or not numbers.has("cost"):
		return ""
	var s: GameState = ctx.state
	var fid := String(factions[0])
	var fname := _faction_name(s, fid)
	var unit := _recruited_unit_name(e, s)
	if unit.is_empty():
		return ""
	var where := _province_name(s, String(provinces[0]))
	var how := "at %s" % where
	if numbers.has("fort") and numbers.has("limit"):  # M3c: "at Stonegate (keep, 3 of 4 this turn)"
		how += " (%s, %d of %d this turn)" % [_fort_word(numbers, String(provinces[0]), s), int(numbers.get("count", 0)), int(numbers.limit)]
	if String(e.get("cause", "")) == "with_ruler":
		var ruler := RulerRules.current_name(s, fid)
		how = "with %s at %s, where it started the turn," % [ruler if not ruler.is_empty() else "its ruler", where]
	var text := "%s recruited %s %s for %d gold (%d gold left)." % [fname, unit, how, int(numbers.cost), int(numbers.get("gold_after", 0))]
	var id := String(armies[0])
	var plural := _plural_word(unit)
	var f := s.find_faction(fid)
	var is_commander := f != null and f.commander_type != null and f.commander_type.name == unit
	if bool(numbers.get("new_army", false)):
		text += " %s formed a new army, %s." % ["They" if plural else "It", _name(id, ctx)]
	elif is_commander:
		text += " The %s now leads %s." % [unit, _name(id, ctx)]
	else:
		text += " %s joined %s." % ["They" if plural else "It", _name(id, ctx)]
	if numbers.has("hp") and numbers.has("max_hp"):
		var ut := _unit_type_by_name(s, fid, unit)
		var wounded := AscensionRules.arrival_text(ut, int(numbers.hp), int(numbers.max_hp), int(numbers.get("blood_levy", 4)))
		if not wounded.is_empty():
			text += " " + wounded
	return text


## The unit a "recruited" event is about, as its text names it ("Aurel Crown recruited Knights at ...").
static func _recruited_unit_name(e: Dictionary, s: GameState) -> String:
	var text := String(e.get("text", ""))
	var factions: Array = e.get("factions", [])
	var lead := "%s recruited " % _faction_name(s, String(factions[0])) if not factions.is_empty() else ""
	if lead.is_empty() or not text.begins_with(lead):
		return ""
	var rest := text.substr(lead.length())
	var cut := rest.length()
	for word in [" at ", " with "]:
		var k := rest.find(word)
		if k > 0 and k < cut:
			cut = k
	return rest.substr(0, cut)


static func _unit_type_by_name(s: GameState, fid: String, unit_name: String) -> UnitType:
	var f := s.find_faction(fid)
	if f == null:
		return null
	for ut in f.unit_types:
		if ut.name == unit_name:
			return ut
	return f.commander_type if f.commander_type != null and f.commander_type.name == unit_name else null


# --- names ----------------------------------------------------------------------------------------

static func _faction_name(s: GameState, fid: String) -> String:
	var f: Faction = s.find_faction(fid) if s != null else null
	if f != null:
		return f.faction_name
	for d in FactionData.FACTIONS:
		if String(d.id) == fid:
			return String(d.name)
	return "an unknown faction"


static func _province_name(s: GameState, pid: String) -> String:
	var p: Province = s.find_province(pid) if s != null else null
	if p != null:
		return p.name
	for d in MapData.PROVINCES:
		if String(d.id) == pid:
			return String(d.name)
	return "a place not on the map"


static func _unit_type_name(s: GameState, type_id: String) -> String:
	if s != null:
		var name := TurnResolver._unit_type_name(s, type_id)
		if name != "an unknown unit type":
			return name
	for f in FactionData.FACTIONS:
		for u in f.unit_types + [f.commander]:
			if String(u.id) == type_id:
				return String(u.name)
	return "an unknown unit type"


static func _possessive(name: String) -> String:
	return RulerRules._possessive(name)


static func _cap(text: String) -> String:
	return RulerRules._cap(text)
