class_name WickRules
extends RefCounted
## Wick, the Candlewake's faction rule (CW-1 scaffold, #252; design/CANDLEWAKE.md §2). Every army of a faction whose
## FactionData row has "wick" burns at a flame from 0 to its cap, kept on the army (Army.flame) and saved in no other game. A
## ruler's army holds only its ruler, whom flame never touches, so it carries none.
##
## CW-1 is the scaffold: the field and where flames start (light: the start army, recruits forming a new army, a summoned
## army; a split's new army keeps its source's flame), save and load, validation, fog (the exact flame only in clear sight,
## FogRules.stand_ins), the Wick step's place in the turn (wick_step, after the wake step and before income) and the event
## contracts below. What the step does, battles at flame - 1 attack, guttering, Harvest, recruits cooling what they join and a
## merge taking the lower flame are CW-2 (#253), with their explanations.
##
## Event contracts (CW-2 emits them; FogData.AUDIENCE keeps each to its owner, because a rival never learns which unseen
## army found harbour where, §2.4):
##   flame_changed  numbers {"army", "from", "to", "why"}: one net line an army a turn, in the Wick step.
##                  "The Candlewake's 2nd burns hotter: flame 3."
##   guttered       numbers {"army", "units", "hp"}: an army at flame 0 lost hit points, in the Wick step.
##                  "The Candlewake's 3rd is guttering: its regulars lost 2 hp."
##   harvest        numbers {"army", "unit", "count", "joined"}: Half-Death's Harvest raised fighters after a won battle (§4.2).
##                  "Half-Death's Harvest raised 2 Wickwardens at Thornvale: they joined the Candlewake's 2nd."

const EVENT_TYPES := ["flame_changed", "guttered", "harvest"]
## The phase the Wick step runs in (TurnResolver.phases): after "wake", before "income".
const PHASE := "wick"
## What an army at flame 0 loses in each Wick step, per regular unit, never below 1 hp (§2.2: guttering).
const GUTTER_HP := 2
## Vigil never lifts a flame above this (§4.2), whatever the cap.
const VIGIL_MAX := 3
## The battle event types whose armies "fought" this turn (TurnResolver).
const BATTLE_TYPES := ["battle", "border_battle"]
## The stage of their own Wake a province must stand at, or deeper, for a win there to be on Pyre Roads (§6.3).
const PYRE_STAGE := "wake_line"
## The codex entry each event links.
const CODEX := {"flame_changed": "wick", "guttered": "guttering", "harvest": "ability_harvest"}


## Whether `faction_id` keeps a flame on its armies (its FactionData row has "wick").
static func has_wick(faction_id: String) -> bool:
	return not Dictionary(FactionData.row(faction_id).get("wick", {})).is_empty()


## Whether a faction seated in `state` keeps a flame: only then does the Wick step run.
static func in_play(state: GameState) -> bool:
	if state == null:
		return false
	for f in state.factions:
		if has_wick(f.id):
			return true
	return false


## The flame a new army of `faction_id`, and its recruits, start at (§2.1, §4.3): the row's start (1), or a mandate's
## "start_flame" when it has one (Kindling: 2), never above the row's cap (§6.3: Kindle never lifts a flame above 3).
static func start_flame(state: GameState, faction_id: String) -> int:
	var out := int(FactionData.row(faction_id).get("wick", {}).get("start", 1))
	if state != null:
		for mid in RulerRules.mandates(state, faction_id):
			out = maxi(out, int(RulerRules.mandate_data(mid).get("start_flame", 0)))
	return mini(out, base_cap(faction_id))


## The start flame in words, naming the mandate that raised it (§2.5; the director, 10-22: a hotter start says where it comes
## from): "flame 2 (Kindling)", or "flame 1".
static func start_words(state: GameState, faction_id: String) -> String:
	var flame := start_flame(state, faction_id)
	if state != null:
		for mid in RulerRules.mandates(state, faction_id):
			if int(RulerRules.mandate_data(mid).get("start_flame", 0)) == flame:
				return "flame %d (%s)" % [flame, RulerRules.mandate_name(mid)]
	return "flame %d" % flame


# --- the path's numbers (CW-4, §6) ----------------------------------------------------------------------

## A Hundred-Wick's Flare for `faction_id` (§4.1, §6.1): FLARE_DAMAGE, and Brighter Flare's 1 more.
static func flare_damage(state: GameState, faction_id: String) -> int:
	return AutoBattleResolver.FLARE_DAMAGE + AscensionRules.effect_int(state, faction_id, "flare_damage")


## What a Siphon unit of type `type_id` heals (§4.1, §6.3): SIPHON_HEAL, or its path's (Red Gleaners: 2).
static func siphon_heal(state: GameState, faction_id: String, type_id: String) -> int:
	return int(AscensionRules.effect_dict(state, faction_id, "siphon_heal").get(type_id, AutoBattleResolver.SIPHON_HEAL))


## The row's cap (§2.1: 3): the flame Kindling, Vigil and every army that doesn't win come back under.
static func base_cap(faction_id: String) -> int:
	return int(FactionData.row(faction_id).get("wick", {}).get("cap", 3))


## What an army idle outside a harbour loses (§2.2: 1; §6.3, the Red Wake: 2).
static func idle_loss(state: GameState, faction_id: String) -> int:
	return maxi(1, AscensionRules.effect_max(state, faction_id, "idle_loss"))


## Whether `faction_id` has Pyre Roads (§6.3, the Oath of the Snuffed), and the flame a win on one gives (2), else 1.
static func pyre_gain(state: GameState, faction_id: String) -> int:
	return maxi(1, AscensionRules.effect_max(state, faction_id, "pyre_roads"))


## Pyre Roads (§6.3): whether a win at `province_id` gives `faction_id` Pyre Roads' flame, read in `state` as the battle phase
## begins (the turn's start): its own province, its own mark at the Wake-Line or deeper as the land looks then. A cold wake
## retaken that turn never qualifies: someone else held it when the battles began. False without the Oath of the Snuffed.
static func pyre_road(state: GameState, faction_id: String, province_id: String) -> bool:
	if state == null or pyre_gain(state, faction_id) <= 1:
		return false
	var p := state.find_province(province_id)
	var mark: Dictionary = Dictionary(state.marks.get(province_id, {})).get("mark", {})
	return p != null and p.owner == faction_id and not mark.is_empty() and String(mark.faction) == faction_id \
		and MarkRules.stage_now(state, province_id) >= MarkData.stage_index(faction_id, PYRE_STAGE)


## The flame `flame` becomes in a Wick step (§2.2, §6.3), with the reason it moved: {"flame", "why"}. The one transition the
## step, the forecasts and the army card read:
##   1. won a battle this turn: +1, or Pyre Roads' gain when it won on one (`pyre`); once a turn;
##   2. else, an army raised this turn or in a harbour keeps it; any other loses the idle loss (1; the Red Wake: 2);
##   3. above the row's cap (only the Red Wake's flame 4 can be), an army that didn't win drops to it, even in a harbour;
##   4. Vigil lifts it to at least `vigil`, never above VIGIL_MAX;
##   5. clamp to 0 and the cap.
## why: "won", "pyre", "idle", "burned_down", "vigil" or "" when nothing moved it.
static func flame_step(state: GameState, faction_id: String, flame: int, won: bool, pyre: bool, in_harbour: bool, raised: bool,
		vigil: int = 0) -> Dictionary:
	var out := flame
	var why := ""
	if won:
		out += pyre_gain(state, faction_id) if pyre else 1
		why = "pyre" if pyre else "won"
	elif not raised and not in_harbour:
		out -= idle_loss(state, faction_id)
		why = "idle"
	if not won and out > base_cap(faction_id):
		out = base_cap(faction_id)
		why = "burned_down"
	if vigil > 0 and out < mini(vigil, VIGIL_MAX):
		out = mini(vigil, VIGIL_MAX)
		why = "vigil"
	return {"flame": clampi(out, 0, cap(state, faction_id)), "why": why}


static func next_flame(state: GameState, faction_id: String, flame: int, won: bool, pyre: bool, in_harbour: bool, raised: bool,
		vigil: int = 0) -> int:
	return int(flame_step(state, faction_id, flame, won, pyre, in_harbour, raised, vigil).flame)


## How many Half-Death's Harvest raises (§4.2, §6.3): its ability's value at the ruler's rank against a player's army
## (`beat_player`), the reduced Harvest against only a Free Hold, and the Swelling's 1 more either way.
static func harvest_count(state: GameState, faction_id: String, beat_player: bool) -> int:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return 0
	var ability := RulerRules.ability_data(f.ruler_type)
	var base := RulerRules.ability_value(f.ruler_type, RulerRules.ability_rank(f.kept_power)) if beat_player else int(ability.get("free_hold", 1))
	return base + AscensionRules.effect_int(state, faction_id, "harvest_bonus")


## The flame `army` fights a battle at (§2.2): its flame (the one the battle phase began with: nothing changes a flame
## during the battle phase), with any battle bonus (Bonfire Night, CW-5), never above its cap. -1 for an army with none.
static func battle_flame(state: GameState, army: Army) -> int:
	if army == null or army.flame < 0:
		return -1
	return mini(army.flame, cap(state, army.owner))


## The highest flame `faction_id`'s armies reach (§2.1: 3; §6.3, the Red Wake: 4).
static func cap(state: GameState, faction_id: String) -> int:
	return maxi(base_cap(faction_id), AscensionRules.effect_max(state, faction_id, "flame_cap"))


## Whether `army` carries a flame: every army of a Wick faction but a ruler's.
static func carries_flame(army: Army) -> bool:
	return army != null and army.ruler == null and has_wick(army.owner)


## Lights a new army: its faction's start flame when it carries one, none (-1) otherwise.
static func light(state: GameState, army: Army) -> void:
	army.flame = start_flame(state, army.owner) if carries_flame(army) else -1


## The Wick step (§2.2, CW-2): one deterministic pass over every army that carries a flame, in id order, after the wake step and
## before income. `start` is the state at the start of the turn (an army not in it was raised this turn, and its flame then is
## where the turn's net line starts). For each army, flame_step's order (win, Pyre Roads, idle loss, the Red Wake's burn-down,
## Vigil in the province of a living ruler with it, clamp); then, at flame 0, it gutters: every regular (not mages or summoned
## creatures) loses GUTTER_HP, never below 1. Pyre Roads reads `start`, the land as the battles began.
## Then one flame_changed line an army whose flame differs from the turn's start, and a guttered line an army that lost hp.
static func wick_step(state: GameState, events: Array, start: GameState = null) -> void:
	if not in_play(state):
		return
	var facts := battle_facts(events)
	var floors := vigil_floors(state)
	for a in TurnResolver._sorted_armies(state):
		if not carries_flame(a):
			continue
		var before: Army = start.find_army(a.id) if start != null else null
		var raised := start != null and before == null
		var won: bool = facts.won.has(a.id)
		var pyre := won and start != null and Array(facts.won_at.get(a.id, [])).any(func(pid): return pyre_road(start, a.owner, String(pid)))
		var sheltered: bool = facts.fought.has(a.id) or harbour(state, a.owner, a.location)
		var floor := int(floors.get("%s|%s" % [a.owner, a.location], 0))
		var step := flame_step(state, a.owner, a.flame, won, pyre, sheltered, raised, floor)
		var why := String(step.why)
		a.flame = int(step.flame)
		if a.flame == 0:
			var units := 0
			var lost := 0
			for u in a.units:
				if u.type.summoned or u.type.trait_id == AutoBattleResolver.MAGE:
					continue
				var take := mini(GUTTER_HP, u.current_hp - 1)
				if take > 0:
					u.current_hp -= take
					units += 1
					lost += take
			if lost > 0:
				events.append(gutter_event(state, a, units, lost))
		var from: int = before.flame if before != null else a.flame
		if from >= 0 and from != a.flame:
			events.append(flame_event(state, a, from, a.flame, why if not why.is_empty() else "joined"))


## The turn's per-army facts (§2.1), read from its battle events: {"fought": {army id: true}, "won": {army id: true}}. Losing
## armies are destroyed, so an army that fought and was not destroyed in that battle won it.
static func battle_facts(events: Array) -> Dictionary:
	var fought := {}
	var won := {}
	var won_at := {}  # CW-4: {army id: [province ids]}, the province battles it won (Pyre Roads)
	for e in events:
		if not BATTLE_TYPES.has(String(e.get("type", ""))):
			continue
		var destroyed: Array = e.get("numbers", {}).get("destroyed", [])
		for aid in e.get("armies", []):
			fought[String(aid)] = true
			if not destroyed.has(aid):
				won[String(aid)] = true
				if String(e.type) == "battle" and not Array(e.get("provinces", [])).is_empty():
					var at: Array = won_at.get(String(aid), [])
					at.append(String(e.provinces[0]))
					won_at[String(aid)] = at
	return {"fought": fought, "won": won, "won_at": won_at}


## Whether `province_id` is a harbour for `faction_id`'s armies (§2.2): a fort it owns, or a mark of its own at a stage that
## shelters, or a cold wake of its own (MarkRules.harbour, CW-3). A siege camp is not one: it stands in someone else's land.
static func harbour(state: GameState, faction_id: String, province_id: String) -> bool:
	var p := state.find_province(province_id)
	if p == null:
		return false
	if p.owner == faction_id and (p.has_fort or p.fort_level > 0):
		return true
	return MarkRules.harbour(state, faction_id, province_id)


## Vigil's floors (§4.2): {"<faction id>|<province id>": the floor} for every living ruler with Vigil, where its army stands.
static func vigil_floors(state: GameState) -> Dictionary:
	var out := {}
	for f in state.factions:
		if not has_wick(f.id) or not f.has_ruler() or f.ruler_status != RulerRules.ALIVE:
			continue
		if String(RulerRules.ruler_data(f.ruler_type).get("ability", "")) != "vigil":
			continue
		var army := RulerRules.ruler_army(state, f.id)
		if army != null:
			out["%s|%s" % [f.id, army.location]] = RulerRules.ability_value(f.ruler_type, RulerRules.ability_rank(f.kept_power))
	return out


## Harvest (§4.2, CW-2), after a battle (TurnResolver._fight): once a turn, when a battle in a province (not on a border) is won
## by a faction whose living ruler has Harvest and fought in it, the ruler's ability raises its "unit" (Wickwardens): its value
## at the ruler's ability rank against a player's army, "free_hold" against only a Free Hold. They join the lowest-id regular
## army of the winner that fought there and stands, at its flame (they rose in the fire), or form a new army there at the start
## flame. Never the enemy's dead. `sides` {faction id: armies}, `destroyed` the armies the battle destroyed.
static func harvest(state: GameState, kind: String, province_ids: Array, sides: Dictionary, winner: String, destroyed: Array,
		events: Array) -> void:
	if kind == "border" or province_ids.is_empty() or not sides.has(winner) or not has_wick(winner):
		return
	var f := state.find_faction(winner)
	if f == null or not f.has_ruler() or String(RulerRules.ruler_data(f.ruler_type).get("ability", "")) != "harvest":
		return
	var ruler_fought := false
	var joins: Array = []
	for a in sides[winner]:
		if destroyed.has(a.id):
			continue
		if a.ruler != null:
			ruler_fought = true
		elif state.find_army(a.id) != null:
			joins.append(a)
	if not ruler_fought:
		return
	for e in events:
		if String(e.get("type", "")) == "harvest" and Array(e.get("factions", [])).has(winner):
			return  # once a turn (a fort's chain of battles counts once)
	var beat_player := false
	for fid in sides:
		if fid != winner and fid != IndependentData.FACTION_ID:
			beat_player = true
	var ability := RulerRules.ability_data(f.ruler_type)
	var count := harvest_count(state, winner, beat_player)  # CW-4: the Swelling raises one more
	var ut := TurnResolver.recruitable_type(f, String(ability.get("unit", "")))
	if ut == null or count <= 0:
		return
	var raised := raise(state, winner, ut, count, String(province_ids[0]), joins)
	var e := harvest_event(state, raised.army, ut.id, count, bool(raised.joined))
	e.phase = String(events.back().get("phase", "battles")) if not events.is_empty() else "battles"
	events.append(e)


## Raises `count` of `ut` for `faction_id` at `province_id` (Harvest; the Risen, MarkRules, CW-3): they join the lowest-numbered
## army of `joins` at its flame (they don't cool it), or form a new army there lit at the start flame, which the Wick step counts
## as raised this turn. {"army": the army they are in, "joined": whether it stood there already}.
static func raise(state: GameState, faction_id: String, ut: UnitType, count: int, province_id: String, joins: Array) -> Dictionary:
	var sorted := joins.duplicate()
	sorted.sort_custom(func(x, y): return TurnReportText.army_number(x.id) < TurnReportText.army_number(y.id))
	var army: Army = sorted[0] if not sorted.is_empty() else null
	var joined := army != null
	if army == null:
		army = Army.new()
		army.id = state.new_army_id(faction_id)
		army.owner = faction_id
		army.location = province_id
		light(state, army)
		state.armies.append(army)
	for i in count:
		var u := Unit.new(ut, faction_id)
		u.current_hp = RulerRules.unit_max_hp(state, u)
		army.units.append(u)
	return {"army": army, "joined": joined}


# --- the words (§2.5) ------------------------------------------------------------------------------------

## The army card's and the banner's line (§2.5): "Flame 2: its regulars fight at +1 attack. If it doesn't win this turn and
## isn't in a harbour, it drops to 1." "" for an army with no flame. In a player's view, a rival's army out of clear sight
## shows "flame unknown" (FogRules shows exact flame only in clear sight).
static func flame_text(state: GameState, army: Army) -> String:
	if army == null or not has_wick(army.owner) or army.ruler != null:
		return ""
	if army.flame < 0:
		return "Flame unknown: only an army in clear sight shows its flame."
	var cap_ := cap(state, army.owner)
	var shown := "%d/%d" % [army.flame, cap_] if cap_ > base_cap(army.owner) else str(army.flame)  # CW-4: the Red Wake's 4/4
	var line := "Flame %s: its regulars fight at %s attack." % [shown, "%+d" % (army.flame - 1) if army.flame != 1 else "+0"]
	if army.flame == 0:
		line += " It is guttering: its regulars lose %d hp a turn, never below 1, until it wins." % GUTTER_HP
	if army.flame < cap_:
		var won := next_flame(state, army.owner, army.flame, true, false, false, false)
		var on_pyre := next_flame(state, army.owner, army.flame, true, true, false, false)
		line += " A win this turn raises it to %d%s." % [won, " (%d on Pyre Roads)" % on_pyre if on_pyre > won else ""]
	if army.flame > base_cap(army.owner):
		line += " It drops to %d if it doesn't win, even in a harbour; idle outside a harbour, to %d." % [
			next_flame(state, army.owner, army.flame, false, false, true, false), next_flame(state, army.owner, army.flame, false, false, false, false)]
	elif army.flame > 0:
		line += " If it doesn't win this turn and isn't in a harbour, it drops to %d." % next_flame(state, army.owner, army.flame, false, false,
			false, false)
	return line


## The orders forecast's line for `army` ending the turn at `destination` (§2.5): "the Candlewake's 2nd: flame 2 → 3 if it
## wins; → 1 if it fights no battle (Thornvale is no harbour)." "" for an army with no flame.
static func forecast_line(state: GameState, army: Army, destination: String = "") -> String:
	if army == null or army.flame < 0:
		return ""
	var where := destination if not destination.is_empty() else army.location
	var name := TurnReportText.army_name(state, army.id, army.owner)
	var pyre := pyre_road(state, army.owner, where)  # CW-4: the orders' state is the land as the battles begin
	var won := next_flame(state, army.owner, army.flame, true, pyre, false, false)
	var plain := next_flame(state, army.owner, army.flame, true, false, false, false)
	var sheltered := harbour(state, army.owner, where)
	var idle := next_flame(state, army.owner, army.flame, false, false, sheltered, false)
	return "%s: flame %d → %d if it wins%s; → %d if it fights no battle (%s %s a harbour)." % [RulerRules._cap(name), army.flame, won,
		" (Pyre Roads)" if won > plain else "", idle, TurnResolver._province_name(state, where), "is" if sheltered else "is not"]


## The recruit forecast's words (§2.5): " Joining the Candlewake's 2nd cools it from flame 3 to 1." or " A new army starts at
## flame 1." "" for a faction that keeps no flame, or a commander (it cools nothing).
static func recruit_words(state: GameState, faction_id: String, joins: Army, ut: UnitType) -> String:
	if not has_wick(faction_id) or ut == null or ut.is_commander or SiegeRules.is_engine(ut):
		return ""
	var start := start_flame(state, faction_id)
	if joins == null:
		return " A new army starts at flame %d." % start
	if joins.flame > start:
		return " Joining %s cools it from flame %d to %d." % [TurnReportText.army_name(state, joins.id, faction_id), joins.flame, start]
	return ""


## Checks every flame (GameState.validate): only a Wick faction's armies carry one, every one of theirs but a ruler's does,
## and none is above its cap. In a player's view a rival's stand-in shows its flame only in clear sight (FogRules), so a
## rival's army without one is allowed there. Plain reasons in `errors` (push_error when it isn't an Array).
static func validate(state: GameState, errors = null) -> bool:
	var ok := true
	for a in state.armies:
		if not carries_flame(a):
			if a.flame >= 0:
				_report(errors, "Army '%s' burns at a flame, but %s." % [a.id,
					"a ruler's army carries none" if a.ruler != null else "its faction keeps no flame"])
				ok = false
		elif a.flame < 0:
			if not state.view_relaxes(a.owner):
				_report(errors, "Army '%s' of %s has no flame, but every army of theirs except a ruler's burns at one." % [a.id,
					TurnResolver._faction_name(state, a.owner)])
				ok = false
		elif a.flame > cap(state, a.owner):
			_report(errors, "Army '%s' burns at flame %d, above its cap of %d." % [a.id, a.flame, cap(state, a.owner)])
			ok = false
	return ok


# --- the event contracts ------------------------------------------------------------------------------

## A flame_changed event: `army`'s flame went from `from` to `to` this turn, for `why` (CW-2: "won", "idle", "vigil", ...).
static func flame_event(state: GameState, army: Army, from: int, to: int, why: String) -> Dictionary:
	return _wick_event(state, "flame_changed", army, {"army": army.id, "from": from, "to": to, "why": why})


## A guttered event: `army`, at flame 0, lost `hp` hit points over `units` regulars.
static func gutter_event(state: GameState, army: Army, units: int, hp: int) -> Dictionary:
	return _wick_event(state, "guttered", army, {"army": army.id, "units": units, "hp": hp})


## A harvest event: `count` fighters of `unit_type` rose at `army`'s province and joined it (`joined`) or formed it.
static func harvest_event(state: GameState, army: Army, unit_type: String, count: int, joined: bool) -> Dictionary:
	var e := _wick_event(state, "harvest", army, {"army": army.id, "unit": unit_type, "count": count, "joined": joined})
	e.phase = "battles"
	return e


static func _wick_event(state: GameState, type: String, army: Army, numbers: Dictionary) -> Dictionary:
	var e := {"type": type, "phase": PHASE, "provinces": [army.location], "factions": [army.owner], "armies": [army.id],
		"numbers": numbers, "codex": String(CODEX[type])}
	e["text"] = event_sentence(state, e)
	return e


## The plain sentence of an event of EVENT_TYPES, as the record and the owner's report say it; `state` is read for names.
static func event_sentence(state: GameState, e: Dictionary) -> String:
	var n: Dictionary = e.get("numbers", {})
	var fid := String(Array(e.get("factions", [])).front()) if not Array(e.get("factions", [])).is_empty() else ""
	var army := TurnReportText.army_name(state, String(n.get("army", "")), fid)
	match String(e.get("type", "")):
		"flame_changed":
			return "%s burns %s: flame %d." % [RulerRules._cap(army), "hotter" if int(n.get("to", 0)) > int(n.get("from", 0)) else "lower",
				int(n.get("to", 0))]
		"guttered":
			return "%s is guttering: its regulars lost %d hp." % [RulerRules._cap(army), int(n.get("hp", 0))]
		"harvest":
			var where := TurnResolver._province_name(state, String(Array(e.get("provinces", [""])).front()))
			var risen := []
			for i in int(n.get("count", 0)):
				risen.append(String(n.get("unit", "")))
			var ruler := RulerRules.current_name(state, fid) if RulerRules.ruler_alive(state, fid) else ""
			return "%s raised %s at %s: they %s %s." % ["%s's Harvest" % RulerRules._cap(ruler) if not ruler.is_empty() else "The Harvest",
				MusterRules.units_words(state, fid, risen), where, "joined" if bool(n.get("joined", false)) else "formed", army]
	return String(e.get("text", ""))


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
