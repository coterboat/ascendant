class_name MarkRules
extends RefCounted
## Marks on the land (CW-1 scaffold, #252; design/CANDLEWAKE.md §3.1): the generic engine piece, built once for every faction
## later; only the Candlewake have a MarkData row in this milestone.
##
## GameState.marks is a top-level dictionary of only non-empty entries, {province id: {"mark": {"faction", "since_turn"},
## "scar": {"faction", "stage", "until_turn"}}}, either or both. It is saved only in a game where a seated faction has a MarkData
## row (in_play), so every other game saves exactly as before. A mark's stage is computed, never stored: held = E - since_turn on
## the end clock E = current_turn + 1 (§2.2), turned into a stage by the row's thresholds (stage_of). A scar keeps the stage its
## mark had. Marks and scars are public, like terrain and owners (§3.1): every view carries them whole (FogRules).
##
## CW-1 was the scaffold: the field, save and load, validation, the wake step's place in the turn (wake_step, after recruitment
## and before the Wick step) and the event contracts below. CW-3 (#254) gives the step its rules: the truth table of §3.3 (a mark
## when a marking faction takes a province, a cold wake when it loses one, relit on a retake), the capitals' marks, harbours,
## the gold, the Risen and their words.
##
## Event contracts (the first three are public: FogData.AUDIENCE rebuilds them for the other players; the Risen are their owner's):
##   mark_stage     numbers {"province", "stage"}: a mark reached a new stage in the wake step. "Thornvale wakes: the Wake-Line."
##   scar_formed    numbers {"province", "stage", "until_turn"}: a marked province changed hands. "A cold wake forms at Rivermarch."
##   scar_consumed  numbers {"province", "stage"}: its faction retook a scarred province. "Rivermarch relights."
##   risen          numbers {"province", "army", "unit", "count", "joined"}: the dead rose from Deep Wake (§3.6). "At Thornvale
##                  the dead rose: one Wickwarden. They joined the Candlewake's 2nd."

const EVENT_TYPES := ["mark_stage", "scar_formed", "scar_consumed", "risen"]
## The phase the wake step runs in (TurnResolver.phases): after "recruitment", before "wick".
const PHASE := "wake"
## The codex entry each event links (CW-3 writes it).
const CODEX := "the_wake"
const MARK_KEYS := ["faction", "since_turn"]
const SCAR_KEYS := ["faction", "stage", "until_turn"]


## Whether `faction_id` marks the land it holds (it has a MarkData row).
static func has_marks(faction_id: String) -> bool:
	return not MarkData.row(faction_id).is_empty()


## Whether a faction seated in `state` marks its land: only then does the state carry `marks` and the wake step run.
static func in_play(state: GameState) -> bool:
	if state == null:
		return false
	for f in state.factions:
		if has_marks(f.id):
			return true
	return false


## The end clock E (§2.2): the turn number the next turn will show, which the wake and Wick steps both read.
static func end_clock(state: GameState) -> int:
	return state.current_turn + 1


## The stage (1-based) of `faction_id`'s mark held for `held` turns in `state`: the last stage whose threshold (threshold: the
## path can bring the Wake-Line sooner) it has reached, or 0 before the first (a since_turn in the future).
static func stage_of(state: GameState, faction_id: String, held: int) -> int:
	var out := 0
	for i in MarkData.stage_count(faction_id):
		if held >= threshold(state, faction_id, i + 1):
			out = i + 1
	return out


## The turns held a mark of `faction_id` needs to reach stage `stage_number` in `state` (CW-4, §6): the row's "held"; a stage
## marked "sooner" (the Wake-Line) comes sooner by the faction's "wake_sooner" path effects (Sitting Up Early, Meadow Wake),
## never before 1 turn held. Deep Wake stays put.
static func threshold(state: GameState, faction_id: String, stage_number: int) -> int:
	var st := MarkData.stage(faction_id, stage_number)
	var held := int(st.get("held", 0))
	if bool(st.get("sooner", false)):
		held = maxi(1, held - AscensionRules.effect_int(state, faction_id, "wake_sooner"))
	return held


## What stage `stage_number` changes its province's income by for its own faction (§3.2, §6.2): the row's "gold", or Meadow
## Wake's "wake_gold" in its place where the row's isn't 0 (the Oath of the Kept: +1 where it cost 1).
static func stage_gold(state: GameState, faction_id: String, stage_number: int) -> int:
	var gold := int(MarkData.stage(faction_id, stage_number).get("gold", 0))
	var meadow := AscensionRules.effect_int(state, faction_id, "wake_gold")
	return meadow if gold != 0 and meadow != 0 else gold


## The name of the rule that turned the Wake's gold (Meadow Wake), or "".
static func _gold_rule(state: GameState, faction_id: String) -> String:
	for nid in AscensionRules.researched(state, faction_id):
		if AscensionRules.node_effects(nid).has("wake_gold"):
			return AscensionRules.economy_rule_name(nid)
	return ""


## Where and how often the dead rise for `faction_id` in `state` (§3.6, §6.2): the row's "risen" ({"unit", "every", "count"}) with
## "stage", the first stage they rise from: the row's first "risen" stage, or the Long Sleep's (from the Wake-Line, every 3).
## {} for a faction whose dead never rise.
static func risen_rule(state: GameState, faction_id: String) -> Dictionary:
	var row: Dictionary = MarkData.row(faction_id).get("risen", {})
	if row.is_empty():
		return {}
	var out := row.duplicate()
	out["stage"] = 0
	for i in MarkData.stage_count(faction_id):
		if bool(MarkData.stage(faction_id, i + 1).get("risen", false)):
			out["stage"] = i + 1
			break
	var sleep := AscensionRules.effect_dict(state, faction_id, "risen")
	if not sleep.is_empty():
		out["stage"] = MarkData.stage_index(faction_id, String(sleep.get("from", "")))
		out["every"] = int(sleep.get("every", out.every))
	return out if int(out.stage) > 0 and int(out.get("every", 0)) > 0 else {}


## A new game's marks (GameState._seat, CW-3): only each marking faction's capital, held since its row's "capital" end clock, so
## it stands at the last stage from the start (§3.1: Deep Wake). The legacy constructors never seat, so a Crown–Clans game has none.
static func seed_capitals(state: GameState) -> void:
	state.marks = {}
	for f in state.factions:
		if has_marks(f.id) and state.find_province(f.capital) != null:
			state.marks[f.capital] = {"mark": {"faction": f.id, "since_turn": int(MarkData.row(f.id).capital)}}


## The stage of the mark at `province_id` on end clock `e` (0 with no mark there).
static func stage_at(state: GameState, province_id: String, e: int) -> int:
	var mark: Dictionary = Dictionary(state.marks.get(province_id, {})).get("mark", {})
	return 0 if mark.is_empty() else stage_of(state, String(mark.faction), e - int(mark.since_turn))


## The stage of the mark at `province_id` as the land looks now: the last wake step's (E - 1), what the board and the card show.
## This turn's wake step may move it on (stage_at with end_clock: what the harbour, the gold and the forecasts read).
static func stage_now(state: GameState, province_id: String) -> int:
	return stage_at(state, province_id, end_clock(state) - 1)


## The wake step (§3.3, CW-3): marks start, grow, scar and heal on the end clock E, after recruitment and before the Wick step,
## so a province that reaches the Wake-Line shelters armies in that turn's Wick step and costs its gold in that turn's income.
## `start` is the state at the start of the turn: a province whose owner differs between it and `state` changed hands this turn
## (capture resolves once a turn, and every owner change of the turn, the capture phase's and Sworn Vassals', is done by now).
## Each pass walks a sorted snapshot of province ids, so the order never depends on the dictionary's:
##   1. every cold wake that has run its course (E >= until_turn) fades, before anyone can retake it;
##   2. every province that changed hands: the old owner's mark becomes a cold wake at the stage it had at the last wake step
##      (held E - 1 - since_turn), lasting scar_turns a stage; a new owner that marks its land relights its own cold wake there
##      (the mark resumes at since_turn = E - that stage's threshold, so the stage returns at once) or starts a mark at E;
##   3. every other mark that reached a new stage at E says so (mark_stage);
##   4. the Risen (§3.6, _rise).
static func wake_step(state: GameState, events: Array, start: GameState = null) -> void:
	if not in_play(state):
		return
	var e := end_clock(state)
	for pid in _sorted_ids(state.marks):
		var entry: Dictionary = state.marks[pid]
		if entry.has("scar") and e >= int(entry.scar.until_turn):
			entry.erase("scar")
			_store(state, pid, entry)
	var fresh := {}  # province ids whose mark started or relit in this step: they say nothing more this turn
	if start != null:
		for p in TurnResolver._sorted_provinces(state):
			var before := start.find_province(p.id)
			if before == null or before.owner == p.owner:
				continue
			var entry: Dictionary = state.marks.get(p.id, {})
			var mark: Dictionary = entry.get("mark", {})
			if not mark.is_empty() and String(mark.faction) == before.owner:
				var stage := maxi(1, stage_of(state, before.owner, e - 1 - int(mark.since_turn)))
				var until := e + int(MarkData.row(before.owner).get("scar_turns", 0)) * stage
				entry.erase("mark")
				entry["scar"] = {"faction": before.owner, "stage": stage, "until_turn": until}
				events.append(scar_event(state, before.owner, p.id, stage, until))
			if has_marks(p.owner):
				var scar: Dictionary = entry.get("scar", {})
				if not scar.is_empty() and String(scar.faction) == p.owner:
					entry.erase("scar")
					entry["mark"] = {"faction": p.owner, "since_turn": e - threshold(state, p.owner, int(scar.stage))}
					events.append(relit_event(state, p.owner, p.id, int(scar.stage)))
				else:
					entry["mark"] = {"faction": p.owner, "since_turn": e}
				fresh[p.id] = true
			_store(state, p.id, entry)
	for pid in _sorted_ids(state.marks):
		var mark: Dictionary = Dictionary(state.marks[pid]).get("mark", {})
		if mark.is_empty() or fresh.has(pid):
			continue
		var fid := String(mark.faction)
		var now := stage_of(state, fid, e - int(mark.since_turn))
		if now > stage_of(state, fid, e - 1 - int(mark.since_turn)):
			events.append(stage_event(state, fid, pid, now))
	for pid in _sorted_ids(state.marks):
		_rise(state, pid, e, events)


static func _sorted_ids(marks: Dictionary) -> Array:
	var out := marks.keys()
	out.sort()
	return out


static func _store(state: GameState, province_id: String, entry: Dictionary) -> void:
	if entry.is_empty():
		state.marks.erase(province_id)
	else:
		state.marks[province_id] = entry


## The Risen (§3.6): where the mark of `province_id`'s owner stands at a stage where the dead rise, the row's "risen" unit rises
## every "every" turns past that stage's threshold (Deep Wake at 6, every 4: held 10, 14, 18; the capital, held since -6, at
## the ends of turns 3, 7, 11). They join the lowest-numbered regular army of the owner there, at its flame (they rose in the
## wax: no cooling), or form a new army there lit at the start flame (2 with Kindling), which the Wick step counts as raised
## this turn. A trickle, never their recruitment.
static func _rise(state: GameState, province_id: String, e: int, events: Array) -> void:
	var mark: Dictionary = Dictionary(state.marks[province_id]).get("mark", {})
	var p := state.find_province(province_id)
	if mark.is_empty() or p == null or p.owner != String(mark.faction):
		return
	var fid := String(mark.faction)
	var risen := risen_rule(state, fid)
	if risen.is_empty():
		return
	var every := int(risen.every)
	var past := e - int(mark.since_turn) - threshold(state, fid, int(risen.stage))
	if past < every or past % every != 0:
		return
	var ut := TurnResolver.recruitable_type(state.find_faction(fid), String(risen.get("unit", "")))
	var count := int(risen.get("count", 1))
	if ut == null or count <= 0:
		return
	var joins := state.armies.filter(func(a): return a.owner == fid and a.location == province_id and WickRules.carries_flame(a))
	var raised := WickRules.raise(state, fid, ut, count, province_id, joins)
	events.append(risen_event(state, fid, province_id, raised.army, ut.id, count, bool(raised.joined)))


# --- gold and the words (§3.2, §3.4) ---------------------------------------------------------------------

## The key of the Wake's income part (RulerRules.province_income_parts, Breakdown).
const INCOME_KEY := "wake"


## The Wake's income part for province `p` (RulerRules.province_income_parts, before the floor and a siege's cut-off): its owner's
## own mark at this turn's stage (end_clock: the stage this turn's income is paid at) changes what it pays by that stage's
## "gold". [] for unmarked land, another faction's mark, or a stage that costs nothing.
static func income_parts(state: GameState, p: Province) -> Array:
	if not in_play(state) or p == null:
		return []
	var mark: Dictionary = Dictionary(state.marks.get(p.id, {})).get("mark", {})
	if mark.is_empty() or String(mark.faction) != p.owner:
		return []
	var stage := stage_at(state, p.id, end_clock(state))
	var gold := stage_gold(state, p.owner, stage)
	if gold == 0:
		return []
	var rule := _gold_rule(state, p.owner) if gold > 0 else ""  # CW-4: Meadow Wake pays
	return [{"key": INCOME_KEY, "name": rule if not rule.is_empty() else RulerRules._cap(stage_name(p.owner, stage)), "value": gold,
		"note": ("%s: the Wake pays" % rule) if not rule.is_empty() else "the Wake: the living sit up all night"}]


## The one-sentence rule behind the Wake's income part (Breakdown._modifier_rule), from MarkData's rows.
static func income_rule() -> String:
	for fid in MarkData.ROWS:
		var paying := []
		var gold := 0
		for st in MarkData.ROWS[fid].stages:
			if int(st.gold) != 0:
				paying.append("at %s" % String(st.name))
				gold = int(st.gold)
		if not paying.is_empty():
			return "The Wake: a %s province %s pays its owner %d gold less; the living sit up all night." % [
				FactionData.row(fid).name, " or ".join(paying), -gold]
	return ""


## The province card's lines (§3.4) for `province_id`, as the land looks now (stage_now): the mark's stage, how long it has been
## held, what the stage does and when the next one comes; where the dead rise, when the next one will; a cold wake's stage, when
## it fades and that it relights. [] where nothing marks the land. Every number comes from MarkData's row:
##   "The Wake-Line (held 4 turns): Candlewake armies keep their flame here. The living sit up all night: -1 gold. Deep Wake in 2 turns."
##   "Deep Wake: the dead rise here. Next Wickwarden in 3 turns."
##   "A cold wake. The Candlewake held it to the Wake-Line; it fades in 3 turns. Their armies still find harbour here, and if
##    they retake it, it relights at once."
## A "turn" here counts this one: a stage due "in 2 turns" comes at the end of the next turn.
static func province_text(state: GameState, province_id: String) -> Array:
	var out := []
	var entry: Dictionary = state.marks.get(province_id, {})
	var e := end_clock(state)
	var mark: Dictionary = entry.get("mark", {})
	if not mark.is_empty():
		var fid := String(mark.faction)
		var held := e - 1 - int(mark.since_turn)
		var stage := maxi(1, stage_of(state, fid, held))
		var row := MarkData.stage(fid, stage)
		var who := String(FactionData.row(fid).name)
		var gold := stage_gold(state, fid, stage)
		var line := "%s (held %s):" % [RulerRules._cap(String(row.name)), _turns(held)]
		if bool(row.get("harbour", false)):
			line += " %s armies keep their flame here." % who
		if gold < 0:
			line += " The living sit up all night: %d gold." % gold
		elif gold > 0:
			line += " %s: +%d gold." % [_gold_rule(state, fid), gold]  # CW-4: Meadow Wake
		if not bool(row.get("harbour", false)) and gold == 0:
			line += " A lilac flame in every window."
		if stage < MarkData.stage_count(fid):
			line += " %s in %s." % [RulerRules._cap(stage_name(fid, stage + 1)), _turns(threshold(state, fid, stage + 1) - held)]
		out.append(line)
		var risen := risen_rule(state, fid)
		var ut := TurnResolver.recruitable_type(state.find_faction(fid), String(risen.get("unit", "")))
		if not risen.is_empty() and stage >= int(risen.stage) and ut != null:
			var every := int(risen.every)
			var past := held + 1 - threshold(state, fid, int(risen.stage))  # past the threshold at this turn's end
			var due := maxi(every, ceili(float(past) / every) * every)
			out.append("%s: the dead rise here. Next %s in %s." % [RulerRules._cap(String(row.name)), _one_name(String(ut.name)),
				_turns(due - past + 1)])
	var scar: Dictionary = entry.get("scar", {})
	if not scar.is_empty():
		var fid := String(scar.faction)
		out.append("A cold wake. The %s held it to %s; it fades in %s. Their armies still find harbour here, and if they retake it, it relights at once." % [
			FactionData.row(fid).name, stage_name(fid, int(scar.stage)), _turns(int(scar.until_turn) - e)])
	return out


static func _turns(n: int) -> String:
	return "1 turn" if n == 1 else "%d turns" % n


## Whether a mark or a scar of `faction_id` makes `province_id` a harbour for its armies (§2.2, §3.3): its own mark there, in a
## province it owns, at a stage that shelters (the Wake-Line and Deep Wake), or a cold wake of its own while it lasts. Read on the
## end clock, so in a turn's orders it already says what this turn's Wick step will find (the forecasts read it).
static func harbour(state: GameState, faction_id: String, province_id: String) -> bool:
	var entry: Dictionary = state.marks.get(province_id, {})
	if entry.is_empty():
		return false
	var mark: Dictionary = entry.get("mark", {})
	var p := state.find_province(province_id)
	if not mark.is_empty() and String(mark.faction) == faction_id and p != null and p.owner == faction_id:
		var stage := stage_of(state, faction_id, end_clock(state) - int(mark.since_turn))
		if bool(MarkData.stage(faction_id, stage).get("harbour", false)):
			return true
	var scar: Dictionary = entry.get("scar", {})
	return not scar.is_empty() and String(scar.faction) == faction_id and end_clock(state) < int(scar.until_turn)


## A copy of `marks` in its saved form: entries with no mark and no scar are left out, and the numbers are whole numbers.
static func marks_copy(marks: Dictionary) -> Dictionary:
	var out := {}
	var pids := marks.keys()
	pids.sort()
	for pid in pids:
		var entry = marks[pid]
		if not (entry is Dictionary):
			out[String(pid)] = entry  # kept as it is, so validate can name it
			continue
		var c := {}
		for part in ["mark", "scar"]:
			if entry.get(part) is Dictionary and not Dictionary(entry[part]).is_empty():
				c[part] = _part_copy(entry[part])
		for key in entry:
			if not ["mark", "scar"].has(String(key)):
				c[String(key)] = entry[key]
		if not c.is_empty():
			out[String(pid)] = c
	return out


static func _part_copy(part: Dictionary) -> Dictionary:
	var out := {}
	for key in part:
		var v = part[key]
		out[String(key)] = String(v) if String(key) == "faction" else (Serial.to_int(v) if v is int or v is float else v)
	return out


## Checks `state.marks` (GameState.validate): only in a game where a seated faction marks its land; each entry names a
## province on the map and holds a mark, a scar or both, each with exactly its keys; the faction is seated and marks its land;
## since_turn and until_turn are whole numbers; a scar's stage is one of its faction's stages. Plain reasons in `errors`.
static func validate(state: GameState, errors = null) -> bool:
	if state.marks.is_empty():
		return true
	if not in_play(state):
		_report(errors, "This game has marks on the land, but none of its factions marks the land it holds.")
		return false
	var ok := true
	for pid in state.marks:
		var where := "The marks at '%s'" % pid
		if state.find_province(String(pid)) == null:
			_report(errors, "%s are on a province that is not on this map." % where)
			ok = false
			continue
		var entry = state.marks[pid]
		if not (entry is Dictionary) or entry.is_empty():
			_report(errors, "%s should be a mark, a scar or both." % where)
			ok = false
			continue
		for key in entry:
			if not ["mark", "scar"].has(String(key)):
				_report(errors, "%s hold '%s', but a province holds only a mark and a scar." % [where, key])
				ok = false
		var good := {}
		for part in ["mark", "scar"]:
			if entry.has(part):
				if _part_ok(state, entry[part], part, where, errors):
					good[part] = entry[part]
				else:
					ok = false
		if not _wake_ok(state, String(pid), good, where, errors):
			ok = false
	return ok


## What the wake step keeps true (CW-3, §3.3): a mark stands on land its faction holds and began no later than this turn's end
## clock; a cold wake still has a turn to run (until_turn >= E: one that runs out at E fades in this turn's wake step); and a
## province never holds a mark and a cold wake of one faction, since retaking a cold wake relights it.
static func _wake_ok(state: GameState, province_id: String, parts: Dictionary, where: String, errors) -> bool:
	var ok := true
	var e := end_clock(state)
	if parts.has("mark"):
		var m: Dictionary = parts.mark
		var who := TurnResolver._faction_name(state, String(m.faction))
		if state.find_province(province_id).owner != String(m.faction):
			_report(errors, "%s are a mark of %s, but %s doesn't hold that land." % [where, who, who])
			ok = false
		if int(m.since_turn) > e:
			_report(errors, "%s are a mark from turn %d, still to come (this turn ends at %d)." % [where, int(m.since_turn), e])
			ok = false
	if parts.has("scar") and int(parts.scar.until_turn) < e:
		_report(errors, "%s are a cold wake that has already faded (it lasted until turn %d; this turn ends at %d)." % [where,
			int(parts.scar.until_turn), e])
		ok = false
	if parts.has("mark") and parts.has("scar") and String(parts.mark.faction) == String(parts.scar.faction):
		_report(errors, "%s are both a mark and a cold wake of %s, but retaking a cold wake relights it." % [where,
			TurnResolver._faction_name(state, String(parts.mark.faction))])
		ok = false
	return ok


static func _part_ok(state: GameState, part, kind: String, where: String, errors) -> bool:
	if not (part is Dictionary):
		_report(errors, "%s have a %s that is not a group of named values." % [where, kind])
		return false
	var keys: Array = MARK_KEYS if kind == "mark" else SCAR_KEYS
	var ok := true
	for key in keys:
		if not part.has(key):
			_report(errors, "%s have a %s with no '%s'." % [where, kind, key])
			ok = false
	for key in part:
		if not keys.has(String(key)):
			_report(errors, "%s have a %s that holds '%s', which a %s never holds." % [where, kind, key, kind])
			ok = false
	if not ok:
		return false
	var fid = part.faction
	if not (fid is String) or state.find_faction(fid) == null or not has_marks(fid):
		_report(errors, "%s have a %s of '%s', which is not a faction of this game that marks its land." % [where, kind, str(fid)])
		return false
	for key in keys:
		if key != "faction" and not (part[key] is int):
			_report(errors, "%s have a %s whose '%s' is not a whole number." % [where, kind, key])
			ok = false
	if ok and kind == "scar" and (int(part.stage) < 1 or int(part.stage) > MarkData.stage_count(fid)):
		_report(errors, "%s have a scar at stage %d, but the marks of %s have stages 1 to %d." % [where, int(part.stage),
			TurnResolver._faction_name(state, fid), MarkData.stage_count(fid)])
		ok = false
	return ok


# --- the event contracts ------------------------------------------------------------------------------

## A mark_stage event: `faction_id`'s mark at `province_id` reached stage `stage`.
static func stage_event(state: GameState, faction_id: String, province_id: String, stage: int) -> Dictionary:
	return _mark_event(state, "mark_stage", faction_id, province_id, {"province": province_id, "stage": stage})


## A scar_formed event: `faction_id`'s mark at `province_id` became a scar at `stage`, lasting until `until_turn`.
static func scar_event(state: GameState, faction_id: String, province_id: String, stage: int, until_turn: int) -> Dictionary:
	return _mark_event(state, "scar_formed", faction_id, province_id, {"province": province_id, "stage": stage, "until_turn": until_turn})


## A scar_consumed event: `faction_id` retook its scarred `province_id`, and the mark came back at `stage`.
static func relit_event(state: GameState, faction_id: String, province_id: String, stage: int) -> Dictionary:
	return _mark_event(state, "scar_consumed", faction_id, province_id, {"province": province_id, "stage": stage})


## A risen event: the dead rose at `province_id` as `count` of `unit_id` and joined `army` (`joined`) or formed it (§3.6).
static func risen_event(state: GameState, faction_id: String, province_id: String, army: Army, unit_id: String, count: int,
		joined: bool) -> Dictionary:
	var e := _mark_event(state, "risen", faction_id, province_id, {"province": province_id, "army": army.id, "unit": unit_id,
		"count": count, "joined": joined})
	e["armies"] = [army.id]
	return e


static func _mark_event(state: GameState, type: String, faction_id: String, province_id: String, numbers: Dictionary) -> Dictionary:
	var e := {"type": type, "phase": PHASE, "provinces": [province_id], "factions": [faction_id], "armies": [],
		"numbers": numbers, "codex": CODEX}
	e["text"] = event_sentence(state, e)
	return e


## The plain sentence of an event of EVENT_TYPES. Every word is public (the rebuilt text in FogData.TEXT says the same).
static func event_sentence(state: GameState, e: Dictionary) -> String:
	var n: Dictionary = e.get("numbers", {})
	var fid := String(Array(e.get("factions", [])).front()) if not Array(e.get("factions", [])).is_empty() else ""
	var where := TurnResolver._province_name(state, String(n.get("province", "")))
	match String(e.get("type", "")):
		"mark_stage":
			return "%s wakes: %s." % [RulerRules._cap(where), stage_name(fid, int(n.get("stage", 0)))]
		"scar_formed":
			return "A cold wake forms at %s." % where
		"scar_consumed":
			return "%s relights." % RulerRules._cap(where)
		"risen":
			var ut := TurnResolver.recruitable_type(state.find_faction(fid), String(n.get("unit", "")))
			var name := String(ut.name) if ut != null else String(n.get("unit", ""))
			var count := int(n.get("count", 0))
			var army := TurnReportText.army_name(state, String(n.get("army", "")), fid)
			var tail := ("They joined %s." % army) if bool(n.get("joined", false)) else ("They form a new army: %s, at %s." % [army,
				WickRules.start_words(state, fid)])
			return "At %s the dead rose: %s %s. %s" % [where, MusterRules.count_word(count),
				_one_name(name) if count == 1 else TurnReportText._plural_name(name), tail]
	return String(e.get("text", ""))


## One of a unit named for its company ("Wickwardens"): "Wickwarden".
static func _one_name(name: String) -> String:
	return name.left(-1) if name.ends_with("s") and not name.ends_with("ss") else name


## The name of stage `stage` of `faction_id`'s mark as players read it ("the Wake-Line"), or "".
static func stage_name(faction_id: String, stage_number: int) -> String:
	return String(MarkData.stage(faction_id, stage_number).get("name", ""))


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
