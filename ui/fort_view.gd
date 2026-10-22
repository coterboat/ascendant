class_name FortView
## The words and numbers the fort and siege screens show (M3c S-3, #101; design/M3C_SIEGES.md §9). Static and
## node-free: every number comes from SiegeRules, Breakdown or Forecast (the functions the turn resolves with),
## and every breakdown built here adds up to a SiegeRules number, so a screen can never disagree with the rules.
## The fort panel (FortPanel), the plate's chip (FortChip), the move preview (OrdersController), the turn report
## (TurnReportPanel), the battle screens and the victory screen all read it.
##
##   status(state, pid) / turn_of_siege_breakdown, troops_breakdown, breach_breakdown, staying_breakdown
##   needs_you(state, viewer, report_turn)   the turn report's "needs you" lines (§9.4)
##   siege_chip(siege)                       the battle viewer's and Watch's chip from a battle's `siege` block (§9.7)
##   siege_odds(kind, ...) / odds_text(odds) the storm, sally, relief and breach odds (S-2's Forecast, §9.2)

## Turn words follow §9.2: the relative turn and the absolute one, and a breach turn carries its condition. The
## relative words are the reader's (TurnReportText.reader_turn / reader_end): the turn being played is "this turn".
const IF_THEY_STAY := "if the besiegers stay as they are"
const IF_YOU_STAY := "if you stay as you are"


# --- the S-2 seam --------------------------------------------------------------------------------------

## THE S-2 SEAM (one function): the odds of a storm, a sally, a relief or the battle through the breach at
## `province_id` for `faction_id`, with its queued `orders`, from Forecast.storm_odds, sally_odds, relief_odds and
## breach_odds (S-2, design/M3C_SIEGES.md §9.2), which fight the real resolver through SiegeRules.next_battle:
## {"ok", "label", "wins", "samples", ...} like Forecast.battle_odds, or {} when there is nothing to fight. The
## sally is every queued sally of an army at the fort; the relief is the queued move into it, with the sallies
## tied to it. Each call fights dozens of test battles, so the answers are kept per state, side, place and orders.
## Every caller (the fort panel's Storm toggle and Sally ticks, the move preview's Besiege / Storm now and relief,
## the order lines, the breach "needs you" line) prints them through odds_text.
static var _odds_cache := {}


static func siege_odds(kind: String, state: GameState, faction_id: String, province_id: String, orders: Array) -> Dictionary:
	if state == null or not state.sieges or state.find_province(province_id) == null:
		return {}
	var key := "%s|%d|%d|%s|%s|%s" % [kind, state.get_instance_id(), state.current_turn, faction_id, province_id,
		JSON.stringify(orders.map(func(o): return o.to_dict()))]
	if _odds_cache.has(key):
		return _odds_cache[key]
	var out := {}
	match kind:
		"storm":
			out = Forecast.storm_odds(state, faction_id, province_id, orders)
		"breach":
			out = Forecast.breach_odds(state, faction_id, province_id, orders)
		"sally":
			var ids := _sallies_at(state, province_id, orders)
			if not ids.is_empty():
				out = Forecast.sally_odds(state, faction_id, ids, orders)
		"relief":
			for o in orders:
				var a: Army = state.find_army(o.army_id) if o is MoveOrder else null
				if a != null and o.to == province_id and a.owner == faction_id and a.location != province_id:
					out = Forecast.relief_odds(state, faction_id, o, _sallies_at(state, province_id, orders, o.army_id), orders)
					break
	if _odds_cache.size() > 256:
		_odds_cache.clear()
	_odds_cache[key] = out
	return out


## Forecast.siege with its odds lines (S-2, §9.2), for a place where the odds are on screen (the fort panel, the
## besiege preview and its order line): the besiegers' storming now, against the garrison's cover (a sally or the
## breach) and storming with their relief arriving; the garrison's odds of holding a storm, of a sally with every
## army but the ruler's, and of a relief with that sally. Kept like siege_odds.
static func siege_forecast(state: GameState, faction_id: String, province_id: String, orders: Array) -> Dictionary:
	if state == null:
		return {}
	var key := "siege|%d|%d|%s|%s|%s" % [state.get_instance_id(), state.current_turn, faction_id, province_id,
		JSON.stringify(orders.map(func(o): return o.to_dict()))]
	if not _odds_cache.has(key):
		if _odds_cache.size() > 256:
			_odds_cache.clear()
		_odds_cache[key] = Forecast.siege(state, faction_id, province_id, orders, true)
	return _odds_cache[key]


## The armies at `province_id` with a sally in `orders` (only those tied to `relief_id` when it is given).
static func _sallies_at(state: GameState, province_id: String, orders: Array, relief_id: String = "") -> Array:
	var out := []
	for o in orders:
		if o is SiegeOrder and o.is_sally() and (relief_id.is_empty() or o.with_army == relief_id):
			var a := state.find_army(o.army_id)
			if a != null and a.location == province_id:
				out.append(a.id)
	return out


## "likely win (21 of 24 test battles)" for siege_odds' result; "" when there are no odds.
static func odds_text(odds: Dictionary) -> String:
	if odds.is_empty() or not odds.has("label"):
		return ""
	return "%s (%d of %d test battles)" % [String(odds.label), int(odds.get("wins", 0)), int(odds.get("samples", 0))]


## siege_odds' result as a breakdown whose total is the test battles won (the number odds_text shows), with the
## odds' own text and reasons in its description and the battle odds entry as its codex.
static func odds_breakdown(odds: Dictionary, title: String) -> Dictionary:
	var wins := int(odds.get("wins", 0))
	var samples := int(odds.get("samples", 0))
	var desc := String(odds.get("text", ""))
	if odds.get("reasons") is Array and not (odds.reasons as Array).is_empty():
		desc += " Main reasons: %s." % "; ".join(odds.reasons)
	return _coded(_make(title, "%s %s" % [desc, RulesCodex.text("battle_odds")], [_line("Test battles fought", samples, "the real battle rules, on fixed seeds"),
		_line("Test battles lost", wins - samples, "")], "Test battles won", wins), "battle_odds")


# --- the fort's state --------------------------------------------------------------------------------

## The fort's state in a few words, for chips and panels: "besieged", "breached", "building", "quiet" or "".
static func state_of(state: GameState, province_id: String) -> String:
	var p := state.find_province(province_id)
	if p == null or not state.sieges:
		return ""
	if p.fort_level > 0 and SiegeRules.siege_stands(state, province_id):
		return "breached" if p.walls <= 0 else "besieged"
	if p.fort_level > 0 and p.walls <= 0:
		return "breached"
	if not p.works.is_empty():
		return "building"
	return "quiet" if p.fort_level > 0 else ""


## The besieging faction's name ("" when there is none).
static func besieger_name(state: GameState, province_id: String) -> String:
	var fid := SiegeRules.besieging_faction(state, province_id)
	var f := state.find_faction(fid) if not fid.is_empty() else null
	return f.faction_name if f else ""


## Which turn of its siege this is, as a breakdown that adds up to SiegeRules.turn_of_siege.
static func turn_of_siege_breakdown(state: GameState, province_id: String) -> Dictionary:
	var p := state.find_province(province_id)
	var turn := state.current_turn + 1
	var n := SiegeRules.turn_of_siege(state, province_id)
	var lines := [_line("This turn", turn, "the turn being ordered"), _line("The siege began on turn", -p.siege_since, ""),
		_line("Its first turn counts as one", 1, "")]
	var desc := "The %s laid siege to %s on turn %d. %s" % [besieger_name(state, province_id), p.name, p.siege_since, RulesCodex.text("siege")]
	return _coded(_make("Turn of the siege of %s" % p.name, desc, lines, "Turn of the siege", n), "siege")


## Troops in `armies` (one line per army), adding up to SiegeRules.troops: the units that fight. `title` names
## the side; commanders, rulers and engines are listed in the notes but never counted.
static func troops_breakdown(state: GameState, armies: Array, title: String, codex: String = "inside_outside") -> Dictionary:
	var lines := []
	for a in armies:
		var bits := []
		if a.commander != null:
			bits.append("led by %s" % a.commander.type.name)
		if a.ruler != null:
			bits.append("a ruler, not a troop")
		if a.engines > 0:
			bits.append("%s, not troops" % SiegeRules.engines_text(a.owner, a.engines))
		lines.append(_line(RulerRules._cap(TurnReportText.army_name(state, a.id, a.owner)), a.units.size(), ", ".join(bits)))
	if lines.is_empty():
		lines.append(_line("No army", 0, ""))
	var desc := "Troops are the units that fight: commanders, rulers and siege engines are not troops. %s" % RulesCodex.text(codex)
	return _coded(_make(title, desc, lines, "Troops", SiegeRules.troops(armies)), codex)


## When the walls reach 0, as a breakdown adding up to SiegeRules.breach_turn: the turn being ordered plus the
## turns of siege after it. `damage` is the siege damage a turn; `who_stays` is IF_THEY_STAY or IF_YOU_STAY.
static func breach_breakdown(state: GameState, province_id: String, damage: int, who_stays: String = IF_THEY_STAY) -> Dictionary:
	var p := state.find_province(province_id)
	var turn := state.current_turn + 1
	var n := SiegeRules.turns_to_breach(p.walls, damage)
	var end := SiegeRules.breach_turn(p.walls, damage, turn)
	var lines := [_line("This turn", turn, "its sieges phase drops the walls first"),
		_line("More turns of siege", n - 1, "walls %d at %d a turn, rounded up: %s, this one included" % [p.walls, damage, _count(n, "turn")])]
	var desc := "The walls of %s (%d of %d) drop by %d a turn and reach 0 at the end of turn %d, %s. %s" % [p.name, p.walls,
		SiegeRules.walls_max(p.fort_level), damage, end, who_stays, RulesCodex.text("breach")]
	return _coded(_make("When the walls of %s reach 0" % p.name, desc, lines, "Walls reach 0 at the end of turn", end), "breach")


## How many of `inside` stay inside when `sallying` (army ids) come out: the sally's risk, as a breakdown.
static func staying_breakdown(state: GameState, province_id: String, inside: Array, sallying: Array) -> Dictionary:
	var p := state.find_province(province_id)
	var out := sallying.filter(func(id): return inside.any(func(a): return a.id == id))
	var lines := [_line("Armies inside the walls", inside.size(), ""), _line("Ordered to sally", -out.size(), "they fight in the open")]
	var desc := "%s %s" % [risk_text(state, province_id, inside, sallying), RulesCodex.text("sally")]
	return _coded(_make("Who stays inside %s" % p.name, desc, lines, "Armies staying inside", inside.size() - out.size()), "sally")


## The Sally ticks' risk line (§9.1): "If they lose, the armies that came out are destroyed. 1 army stays inside."
static func risk_text(state: GameState, province_id: String, inside: Array, sallying: Array) -> String:
	var p := state.find_province(province_id)
	var out := sallying.filter(func(id): return inside.any(func(a): return a.id == id)).size()
	var stay := inside.size() - out
	if out == 0:
		return "Nobody sallies: the garrison holds inside the walls."
	if stay == 0:
		return "If they lose, the armies that came out are destroyed, and with nobody left inside the besiegers take %s." % p.name
	return "If they lose, the armies that came out are destroyed. %s inside." % ("1 army stays" if stay == 1 else "%d armies stay" % stay)


# --- the turn report ---------------------------------------------------------------------------------

## The "needs you" lines for `viewer` at the start of its turn, after the report of `report_turn` (§9.4):
## [{"text", "province", "codex"}], in province id order. Turn words are the reader's (TurnReportText.reader_end),
## the turn the top bar shows counting as "this turn":
##   "Your fort at Stonegate is besieged: its walls reach 0 at the end of next turn (9), if the besiegers stay as
##    they are. Sally, send relief, or hold."
##   "Your armies besiege Crownkeep: storm, wait for the walls to reach 0 in 3 turns (end of turn 11), or leave."
##   "Stonegate's walls are down. This turn (9) you fight there in the open, unless you leave."
static func needs_you(state: GameState, viewer: String, report_turn: int) -> Array:
	var out := []
	if state == null or not state.sieges or viewer.is_empty():
		return out
	var turn := report_turn + 1
	var provinces: Array = state.provinces.duplicate()
	provinces.sort_custom(func(a, b): return a.id < b.id)
	for p: Province in provinces:
		if p.fort_level <= 0 or p.owner.is_empty() or not SiegeRules.siege_stands(state, p.id):
			continue
		var mine := p.owner == viewer
		var outside := SiegeRules.besiegers(state, p.id).filter(func(a): return a.owner == viewer)
		if not mine and outside.is_empty():
			continue
		if p.walls <= 0:
			var odds := odds_text(siege_odds("breach", state, viewer, p.id, []))
			out.append({"text": "%s's walls are down. %s you fight there in the open, unless you leave%s." % [RulerRules._cap(p.name),  # #284: the Long Vigil
				RulerRules._cap(TurnReportText.reader_turn(turn, turn)), ": odds %s" % odds if not odds.is_empty() else ""], "province": p.id, "codex": "breach"})
			continue
		var dmg := SiegeRules.siege_damage_at(state, p.id)
		var end := SiegeRules.breach_turn(p.walls, int(dmg.total), turn)
		var when := TurnReportText.reader_end(end, turn)
		if mine:
			out.append({"text": "Your fort at %s is besieged: its walls reach 0 %s, %s. Sally, send relief, or hold." % [p.name, when, IF_THEY_STAY],
				"province": p.id, "codex": "siege"})
		else:
			out.append({"text": "Your armies besiege %s: storm, wait for the walls to reach 0 %s, or leave." % [p.name, when],
				"province": p.id, "codex": "storm"})
	return out


# --- battles at walls (§9.7) ----------------------------------------------------------------------------

## The chip a battle at a fort shows by its sides, from the battle's `siege` block (§4.4): {"text", "tip",
## "codex"}, or {} for a battle without one. In a storm, "Walls: +4 defense (5 of 9)"; in an open battle,
## "Outside the walls: nobody holds the ground; the garrison's fighters have +2 cover" (no cover clause when
## nobody came from inside, a relief alone); through the breach, "Through the breach: no walls, and nobody gets
## the hills"; at a neutral fort (MVP-3: the block's "holder"), "Holds the ground: no walls, no cover". The codex entries are S-2's battle entries once they exist, the S-1a ones until then.
static func siege_chip(siege: Dictionary) -> Dictionary:
	if siege.is_empty():
		return {}
	var walls := int(siege.get("walls", 0))
	var top := int(siege.get("walls_max", 0))
	match String(siege.get("kind", "")):
		"storm":
			var d := int(siege.get("walls_defense", SiegeRules.walls_defense(walls)))
			return {"text": "Walls: +%d defense (%d of %d)" % [d, walls, top],
				"tip": TooltipText.plain("Walls: +%d defense" % d, "The garrison was stormed behind %d of %d walls, so every fighter of it had +%d defense: %d for every %d wall strength standing, rounded up. Only a stormed garrison gets the walls." % [
					walls, top, d, FortData.WALLS_DEFENSE_PER_STEP, FortData.WALL_STEP]),
				"codex": _entry("battle_walls", "walls")}
		"breach":
			return {"text": "Through the breach: no walls, and nobody gets the hills",
				"tip": TooltipText.plain("Through the breach", "The walls were down, so this battle came on its own and was fought in the open: nobody defended and nobody got the terrain, but the garrison's fighters kept +%d cover among the ruins." % FortData.COVER_DEFENSE),
				"codex": _entry("battle_breach", "breach")}
		"open":
			if int(siege.get("holder", -1)) >= 0:  # MVP-3 (#177): a neutral fort's garrison holds the ground in the open
				return {"text": "Holds the ground: no walls, no cover", "short": "No walls, no cover",
					"tip": TooltipText.plain("The garrison holds the ground", "This neutral fort's garrison met the attackers in the open, so it defended: the province's terrain gives it its bonus. Nobody owns the fort, so no walls and no cover came into the battle, for either side. Only a storm is fought behind walls."),
					"codex": _entry("battle_open", "inside_outside")}
			var cover := int(siege.get("cover_defense", 0))
			var text := "Outside the walls: nobody holds the ground"
			var tip := "This battle was fought outside the walls, in the open: nobody defended, so nobody got walls or terrain."
			if cover > 0:
				text += "; the garrison's fighters have +%d cover" % cover
				tip += " The fighters who came from inside the walls kept +%d cover from their fort." % cover
			return {"text": text, "tip": TooltipText.plain("Outside the walls", tip), "codex": _entry("battle_open", "inside_outside")}
	return {}


## A side's role in a battle at a fort, from the battle's `siege` block and the side's index (sides in faction id
## order, as the block's "garrison" counts them), in the words of the report's first line (S-2,
## AutoBattleResolver._siege_role): "defending the walls", "storming", "garrison, in the breach", "attacking
## through the breach", "sallying garrison", "relief", "relief and sallying garrison", "outside the walls"; at a
## neutral fort (the block has a "holder") "holding the ground" and "attacking". "" without a block.
static func siege_role(siege: Dictionary, side_index: int) -> String:
	if siege.is_empty():
		return ""
	if String(siege.get("kind", "")) == "open" and int(siege.get("holder", -1)) >= 0:
		return "holding the ground" if side_index == int(siege.holder) else "attacking"  # MVP-3 (#177): a neutral fort's garrison
	var garrison := side_index == int(siege.get("garrison", -1))
	match String(siege.get("kind", "")):
		"storm":
			return "defending the walls" if garrison else "storming"
		"breach":
			return "garrison, in the breach" if garrison else "attacking through the breach"
	if not garrison:
		return "outside the walls"
	match String(siege.get("why", "")):
		"relief_sally":
			return "relief and sallying garrison"
		"relief", "empty":
			return "relief"
	return "sallying garrison" if not Array(siege.get("from_inside", [])).is_empty() else "relief"


## What a siege role means, for the role line's second half and its tooltip: {"text", "title", "codex"}.
static func role_meaning(siege: Dictionary, side_index: int) -> Dictionary:
	var role := siege_role(siege, side_index)
	var walls := int(siege.get("walls", 0))
	var top := int(siege.get("walls_max", 0))
	match role:
		"defending the walls":
			return {"text": "it held the walls (%d of %d), +%d defense to every fighter." % [walls, top, int(siege.get("walls_defense", 0))],
				"title": "Defending the walls", "codex": _entry("battle_walls", "walls")}
		"storming":
			return {"text": "it went over the walls (%d of %d) instead of waiting for them to fall." % [walls, top],
				"title": "Storming the walls", "codex": _entry("battle_walls", "storm")}
		"garrison, in the breach":
			return {"text": "the walls were down; its fighters kept +%d cover among the ruins." % int(siege.get("cover_defense", FortData.COVER_DEFENSE)),
				"title": "Through the breach", "codex": _entry("battle_breach", "breach")}
		"attacking through the breach":
			return {"text": "the walls were down, so the battle came on its own, in the open.", "title": "Through the breach",
				"codex": _entry("battle_breach", "breach")}
		"sallying garrison", "relief and sallying garrison":
			return {"text": "it came out of the walls to fight in the open; its fighters from inside kept +%d cover." % int(siege.get("cover_defense", FortData.COVER_DEFENSE)),
				"title": "Sallying out", "codex": _entry("battle_open", "sally")}
		"relief":
			return {"text": "it arrived outside its own fort and fought in the open, with no cover.", "title": "Relief",
				"codex": _entry("battle_open", "relief")}
		"holding the ground":
			return {"text": "it met the attackers in the open before the fort and held the ground: the terrain's bonus was its, with no walls and no cover.",
				"title": "Holding the ground", "codex": _entry("battle_open", "inside_outside")}
		"attacking":
			return {"text": "it marched on a neutral fort and met its garrison in the open, where the garrison held the ground.",
				"title": "Attacking", "codex": _entry("battle_open", "inside_outside")}
	return {"text": "it stood outside the walls, where nobody holds the ground.", "title": "Outside the walls",
		"codex": _entry("battle_open", "inside_outside")}


static func _entry(preferred: String, fallback: String) -> String:
	return preferred if RulesCodex.ENTRIES.has(preferred) else fallback


# --- helpers -----------------------------------------------------------------------------------------

static func _make(title: String, description: String, lines: Array, total_label: String, total: int) -> Dictionary:
	return {"title": title, "description": description, "lines": lines, "total_label": total_label, "total": total}


static func _line(label: String, value: int, note: String) -> Dictionary:
	return {"label": label, "value": value, "note": note}


static func _coded(b: Dictionary, codex: String) -> Dictionary:
	b["codex"] = codex
	return b


static func _count(n: int, singular: String, plural: String = "") -> String:
	return "%d %s" % [n, singular if n == 1 else (plural if not plural.is_empty() else singular + "s")]
