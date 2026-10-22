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
## "start_flame" when it has one (Kindling: 2), never above the cap.
static func start_flame(state: GameState, faction_id: String) -> int:
	var out := int(FactionData.row(faction_id).get("wick", {}).get("start", 1))
	if state != null:
		for mid in RulerRules.mandates(state, faction_id):
			out = maxi(out, int(RulerRules.mandate_data(mid).get("start_flame", 0)))
	return mini(out, cap(state, faction_id))


## The start flame in words, naming the mandate that raised it (§2.5; the director, 10-22: a hotter start says where it comes
## from): "flame 2 (Kindling)", or "flame 1".
static func start_words(state: GameState, faction_id: String) -> String:
	var flame := start_flame(state, faction_id)
	if state != null:
		for mid in RulerRules.mandates(state, faction_id):
			if int(RulerRules.mandate_data(mid).get("start_flame", 0)) == flame:
				return "flame %d (%s)" % [flame, RulerRules.mandate_name(mid)]
	return "flame %d" % flame


## The flame `army` fights a battle at (§2.2): its flame (the one the battle phase began with: nothing changes a flame
## during the battle phase), with any battle bonus (Bonfire Night, CW-5), never above its cap. -1 for an army with none.
static func battle_flame(state: GameState, army: Army) -> int:
	if army == null or army.flame < 0:
		return -1
	return mini(army.flame, cap(state, army.owner))


## The highest flame `faction_id`'s armies reach (§2.1: 3; the Red Wake's 4 is CW-4).
static func cap(_state: GameState, faction_id: String) -> int:
	return int(FactionData.row(faction_id).get("wick", {}).get("cap", 3))


## Whether `army` carries a flame: every army of a Wick faction but a ruler's.
static func carries_flame(army: Army) -> bool:
	return army != null and army.ruler == null and has_wick(army.owner)


## Lights a new army: its faction's start flame when it carries one, none (-1) otherwise.
static func light(state: GameState, army: Army) -> void:
	army.flame = start_flame(state, army.owner) if carries_flame(army) else -1


## The Wick step (§2.2, CW-2): one deterministic pass over every army that carries a flame, in id order, after the wake step and
## before income. `start` is the state at the start of the turn (an army not in it was raised this turn, and its flame then is
## where the turn's net line starts). For each army:
##   1. it won a battle this turn: +1, once;
##   2. else it fought none: outside a harbour -1, in one no change; an army raised this turn skips this;
##   3. Vigil: in the province of a living ruler with Vigil, it rises to at least that ruler's floor (never above VIGIL_MAX);
##   4. clamp to 0 and the cap;
##   5. at flame 0 it gutters: every regular (not mages or summoned creatures) loses GUTTER_HP, never below 1.
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
		var flame: int = a.flame
		var why := ""
		if facts.won.has(a.id):
			flame += 1
			why = "won"
		elif not facts.fought.has(a.id) and not raised and not harbour(state, a.owner, a.location):
			flame -= 1
			why = "idle"
		var floor := int(floors.get("%s|%s" % [a.owner, a.location], 0))
		if floor > flame:
			flame = mini(floor, VIGIL_MAX)
			why = "vigil"
		a.flame = clampi(flame, 0, cap(state, a.owner))
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
	for e in events:
		if not BATTLE_TYPES.has(String(e.get("type", ""))):
			continue
		var destroyed: Array = e.get("numbers", {}).get("destroyed", [])
		for aid in e.get("armies", []):
			fought[String(aid)] = true
			if not destroyed.has(aid):
				won[String(aid)] = true
	return {"fought": fought, "won": won}


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
	var count := RulerRules.ability_value(f.ruler_type, RulerRules.ability_rank(f.kept_power)) if beat_player else int(ability.get("free_hold", 1))
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
	var line := "Flame %d: its regulars fight at %s attack." % [army.flame, "%+d" % (army.flame - 1) if army.flame != 1 else "+0"]
	if army.flame == 0:
		line += " It is guttering: its regulars lose %d hp a turn, never below 1, until it wins." % GUTTER_HP
	if army.flame < cap_:
		line += " A win this turn raises it to %d." % (army.flame + 1)
	if army.flame > 0:
		line += " If it doesn't win this turn and isn't in a harbour, it drops to %d." % (army.flame - 1)
	return line


## The orders forecast's line for `army` ending the turn at `destination` (§2.5): "the Candlewake's 2nd: flame 2 → 3 if it
## wins; → 1 if it fights no battle (Thornvale is no harbour)." "" for an army with no flame.
static func forecast_line(state: GameState, army: Army, destination: String = "") -> String:
	if army == null or army.flame < 0:
		return ""
	var where := destination if not destination.is_empty() else army.location
	var name := TurnReportText.army_name(state, army.id, army.owner)
	var won := mini(army.flame + 1, cap(state, army.owner))
	var sheltered := harbour(state, army.owner, where)
	var idle := army.flame if sheltered else maxi(0, army.flame - 1)
	return "%s: flame %d → %d if it wins; → %d if it fights no battle (%s %s a harbour)." % [RulerRules._cap(name), army.flame, won, idle,
		TurnResolver._province_name(state, where), "is" if sheltered else "is not"]


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
