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
## CW-1 is the scaffold: the field, save and load, validation, the wake step's place in the turn (wake_step, after recruitment
## and before the Wick step) and the event contracts below. The truth table of §3.3 (a mark when the Candlewake take a province,
## a scar when they lose it, consuming it on a retake), harbours, the gold and the Risen are CW-3 (#254).
##
## Event contracts (CW-3 emits them; public: FogData.AUDIENCE rebuilds them for the other players):
##   mark_stage     numbers {"province", "stage"}: a mark reached a new stage in the wake step. "Thornvale wakes: the Wake-Line."
##   scar_formed    numbers {"province", "stage", "until_turn"}: a marked province changed hands. "A cold wake forms at Rivermarch."
##   scar_consumed  numbers {"province", "stage"}: its faction retook a scarred province. "Rivermarch relights."

const EVENT_TYPES := ["mark_stage", "scar_formed", "scar_consumed"]
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


## The stage (1-based) of `faction_id`'s mark held for `held` turns: the last stage whose threshold it has reached, or 0 before
## the first (a since_turn in the future).
static func stage_of(faction_id: String, held: int) -> int:
	var out := 0
	var stages: Array = MarkData.row(faction_id).get("stages", [])
	for i in stages.size():
		if held >= int(stages[i].held):
			out = i + 1
	return out


## The wake step (§3.3): marks start, grow, scar and heal on the end clock, after recruitment and before the Wick step, so a
## province that reaches the Wake-Line shelters armies in that turn's Wick step. CW-1 gives it its place in the turn; CW-3 gives
## it its rules, so for now it changes nothing.
static func wake_step(state: GameState, _events: Array) -> void:
	if not in_play(state):
		return


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
		for part in ["mark", "scar"]:
			if entry.has(part) and not _part_ok(state, entry[part], part, where, errors):
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
	return _event(state, "mark_stage", faction_id, province_id, {"province": province_id, "stage": stage})


## A scar_formed event: `faction_id`'s mark at `province_id` became a scar at `stage`, lasting until `until_turn`.
static func scar_event(state: GameState, faction_id: String, province_id: String, stage: int, until_turn: int) -> Dictionary:
	return _event(state, "scar_formed", faction_id, province_id, {"province": province_id, "stage": stage, "until_turn": until_turn})


## A scar_consumed event: `faction_id` retook its scarred `province_id`, and the mark came back at `stage`.
static func relit_event(state: GameState, faction_id: String, province_id: String, stage: int) -> Dictionary:
	return _event(state, "scar_consumed", faction_id, province_id, {"province": province_id, "stage": stage})


static func _event(state: GameState, type: String, faction_id: String, province_id: String, numbers: Dictionary) -> Dictionary:
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
	return String(e.get("text", ""))


## The name of stage `stage` of `faction_id`'s mark as players read it ("the Wake-Line"), or "".
static func stage_name(faction_id: String, stage_number: int) -> String:
	return String(MarkData.stage(faction_id, stage_number).get("name", ""))


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
