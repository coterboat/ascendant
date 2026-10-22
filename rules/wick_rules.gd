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
## The codex entry each event links (CW-2 writes them).
const CODEX := {"flame_changed": "wick", "guttered": "guttering", "harvest": "harvest"}


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


## The Wick step (§2.2): one deterministic pass over the armies in id order, on the end clock E = current_turn + 1, after the
## wake step and before income. CW-1 gives it its place in the turn; CW-2 gives it its rules, so for now it changes nothing.
static func wick_step(state: GameState, _events: Array) -> void:
	if not in_play(state):
		return


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
	return _event(state, "flame_changed", army, {"army": army.id, "from": from, "to": to, "why": why})


## A guttered event: `army`, at flame 0, lost `hp` hit points over `units` regulars.
static func gutter_event(state: GameState, army: Army, units: int, hp: int) -> Dictionary:
	return _event(state, "guttered", army, {"army": army.id, "units": units, "hp": hp})


## A harvest event: `count` fighters of `unit_type` rose at `army`'s province and joined it (`joined`) or formed it.
static func harvest_event(state: GameState, army: Army, unit_type: String, count: int, joined: bool) -> Dictionary:
	var e := _event(state, "harvest", army, {"army": army.id, "unit": unit_type, "count": count, "joined": joined})
	e.phase = "battles"
	return e


static func _event(state: GameState, type: String, army: Army, numbers: Dictionary) -> Dictionary:
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
