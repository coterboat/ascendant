class_name FortView
## The words and numbers the fort and siege screens show (M3c S-3, #101; design/M3C_SIEGES.md §9). Static and
## node-free: every number comes from SiegeRules, Breakdown or Forecast (the functions the turn resolves with),
## and every breakdown built here adds up to a SiegeRules number, so a screen can never disagree with the rules.
## The fort panel (FortPanel), the plate's chip (FortChip), the move preview (OrdersController), the turn report
## (TurnReportPanel), the battle screens and the victory screen all read it.
##
##   status(state, pid) / turn_of_siege_breakdown, troops_breakdown, breach_breakdown, staying_breakdown
##   needs_you(state, viewer, report_turn)   the turn report's "needs you" lines (§9.4)
##   report_extra(event, row_text)           a fort clause the report's rewritten line dropped (§9.4)
##   siege_chip(siege)                       the battle viewer's and Watch's chip from a battle's `siege` block (§9.7)
##   siege_odds(kind, ...) / odds_text(odds) THE S-2 SEAM: storm, sally and relief odds (§9.2), {} until S-2

## Turn words follow §9.2: the relative turn and the absolute one, and a breach turn carries its condition.
const IF_THEY_STAY := "if the besiegers stay as they are"
const IF_YOU_STAY := "if you stay as you are"


# --- the S-2 seam --------------------------------------------------------------------------------------

## THE S-2 SEAM (one function): the odds of a storm, a sally or a relief at `province_id` for `faction_id`,
## with its queued `orders`, as Forecast.storm_odds, Forecast.sally_odds and Forecast.relief_odds will give them
## (design/M3C_SIEGES.md §9.2): {"ok", "label", "wins", "samples", ...} like Forecast.battle_odds, or {} while
## there are none. Until S-2 (#100) lands this returns {} and every siege control shows its forecast without
## odds. S-2 replaces the body, e.g.
##     match kind:
##         "storm": return Forecast.storm_odds(state, faction_id, province_id, orders)
##         "sally": return Forecast.sally_odds(state, faction_id, province_id, orders)
##         "relief": return Forecast.relief_odds(state, faction_id, province_id, orders)
## and every caller (the fort panel's Storm toggle and Sally ticks, the move preview's Besiege / Storm now and
## relief, the order lines, the "needs you" lines) starts showing them through odds_text.
static func siege_odds(_kind: String, _state: GameState, _faction_id: String, _province_id: String, _orders: Array) -> Dictionary:
	return {}


## "likely win (21 of 24 test battles)" for siege_odds' result; "" when there are no odds.
static func odds_text(odds: Dictionary) -> String:
	if odds.is_empty() or not odds.has("label"):
		return ""
	return "%s (%d of %d test battles)" % [String(odds.label), int(odds.get("wins", 0)), int(odds.get("samples", 0))]


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
## [{"text", "province", "codex"}], in province id order.
##   "Your fort at Stonegate is besieged: its walls reach 0 in 2 turns (end of turn 9), if the besiegers stay
##    as they are. Sally, send relief, or hold."
##   "Your armies besiege Crownkeep: storm, wait for the walls to reach 0 in 3 turns (end of turn 11), or leave."
##   "Stonegate's walls are down. Next turn (9) you fight there in the open, unless you leave."
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
			out.append({"text": "%s's walls are down. Next turn (%d) you fight there in the open, unless you leave%s." % [p.name, turn,
				": odds %s" % odds if not odds.is_empty() else ""], "province": p.id, "codex": "breach"})
			continue
		var dmg := SiegeRules.siege_damage_at(state, p.id)
		var end := SiegeRules.breach_turn(p.walls, int(dmg.total), turn)
		var when := _when(end, report_turn)
		if mine:
			out.append({"text": "Your fort at %s is besieged: its walls reach 0 %s, %s. Sally, send relief, or hold." % [p.name, when, IF_THEY_STAY],
				"province": p.id, "codex": "siege"})
		else:
			out.append({"text": "Your armies besiege %s: storm, wait for the walls to reach 0 %s, or leave." % [p.name, when],
				"province": p.id, "codex": "storm"})
	return out


## "in 2 turns (end of turn 9)", or "at the end of next turn (8)", for something at the end of `end_turn`, told
## after the report of `resolved` (the report's own turn words, SiegeRules.report_when).
static func _when(end_turn: int, resolved: int) -> String:
	var n := end_turn - resolved
	if n <= 1:
		return "at the end of next turn (%d)" % end_turn
	return "in %d turns (end of turn %d)" % [n, end_turn]


## What the report's line of `e` (TurnReportText's rewrite, `row_text`) left out of the event's own words, to put
## back (§9.4): a recruit's fort and count, "(keep, 3 of 4 this turn)", and a capture's fort clause, "It came
## with its keep (walls 2 of 6): ...". "" when nothing is missing.
static func report_extra(e: Dictionary, row_text: String) -> String:
	var own := String(e.get("text", ""))
	match String(e.get("type", "")):
		"recruited":
			var m := RegEx.create_from_string("\\(([a-z]+), (\\d+) of (\\d+) this turn\\)").search(own)
			if m != null and not row_text.contains(m.get_string()):
				return m.get_string()
		"captured":
			var at := own.find("It came with its ")
			if at >= 0:
				var clause := own.substr(at)
				if not row_text.contains(clause):
					return clause
	return ""


## `row_text` with report_extra put back: the fort clause of a recruit after "at <place>", a capture's at the end.
static func with_extra(e: Dictionary, row_text: String) -> String:
	var extra := report_extra(e, row_text)
	if extra.is_empty():
		return row_text
	if String(e.get("type", "")) == "recruited":
		var provinces: Array = e.get("provinces", [])
		var own := String(e.get("text", ""))
		var place_at := own.find(" at ")
		var place := own.substr(place_at + 4, own.find(" (", place_at) - place_at - 4) if place_at >= 0 else ""
		if not place.is_empty() and row_text.contains(" at %s " % place):
			return row_text.replace(" at %s " % place, " at %s %s " % [place, extra])
		return "%s %s" % [row_text, extra] if not provinces.is_empty() else row_text
	return "%s %s" % [row_text.strip_edges(), extra]


# --- battles at walls (§9.7) ----------------------------------------------------------------------------

## The chip a battle at a fort shows by its sides, from the battle's `siege` block (§4.4): {"text", "tip",
## "codex"}, or {} for a battle without one. In a storm, "Walls: +4 defense (5 of 9)"; in an open battle,
## "Outside the walls: nobody holds the ground; the garrison's fighters have +2 cover" (no cover clause when
## nobody came from inside, a relief alone); through the breach, "Through the breach: no walls, and nobody gets
## the hills". The codex entries are S-2's battle entries once they exist, the S-1a ones until then.
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
			var cover := int(siege.get("cover_defense", 0))
			var text := "Outside the walls: nobody holds the ground"
			var tip := "This battle was fought outside the walls, in the open: nobody defended, so nobody got walls or terrain."
			if cover > 0:
				text += "; the garrison's fighters have +%d cover" % cover
				tip += " The fighters who came from inside the walls kept +%d cover from their fort." % cover
			return {"text": text, "tip": TooltipText.plain("Outside the walls", tip), "codex": _entry("battle_open", "inside_outside")}
	return {}


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
