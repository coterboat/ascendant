class_name Army
## Army belonging to a faction, located in a province, containing units and a commander.
## M2: a ruler travels alone, as its own army (design/M2_RULER.md §1.5): an army with a `ruler` holds
## no units and no commander (GameState.validate checks it). Rules and labels: RulerRules.

var id: String  # unique within a GameState, e.g. "kingdom-1"; orders refer to armies by id
var owner: String
var location: String  # province id
var units: Array[Unit] = []
var commander: Unit = null
var ruler: Unit = null  # the faction's living ruler (its type is the faction's ruler_unit_type), or null
## M3c: siege engines this army carries, 0..FortData.ARMY_ENGINES_MAX (design/M3C_SIEGES.md §5). Engines are
## a count, never units: they don't fight, the battle code never sees them, and they are lost with the army.
## Only an army with a fighter (a unit or a commander, not a ruler's army) carries any, and only in a game
## with sieges. Saved only when above 0, so every other army saves exactly as before.
var engines: int = 0
## M5 fog of war (design/M5_MAGIC_FOG.md §2.7): the view note on a stand-in in a player's view (GameState.is_view),
## {"level": "clear" | "glimpse" | "memory", "turn", "counts": {type id: round count}, "total": round count,
## "blessed": n}, where a round count is {"shown", "low", "high", "text"} (FogRules.round_count). A true state
## never has one (GameState.validate); saved only when set.
var seen: Dictionary = {}
## CW-1 (#252, design/CANDLEWAKE.md §2.1): the army's flame, from 0 to its faction's cap, on every army of a faction that keeps a
## flame except a ruler's (WickRules); -1 for none. Saved only when it has one, so every other army saves exactly as before.
var flame: int = -1

## The view note's keys, in the order they are saved.
const SEEN_KEYS := ["level", "turn", "counts", "total", "blessed"]
const ROUND_COUNT_KEYS := ["shown", "low", "high", "text"]

## The army in one line for players, with its name for life and no ids (TurnReportText.describe_army): "the
## Crown's 1st at Crownkeep: Spearmen, Crossbowmen, Knights and Knight Captain", or "King Corvane I, the Aurel
## Crown ruler, at Crownkeep". Without `state`, faction and province names come from their data.
func get_description(state: GameState = null) -> String:
	return TurnReportText.describe_army(self, state)

func to_dict() -> Dictionary:
	var unit_dicts := []
	for u in units:
		unit_dicts.append(u.to_dict())
	
	var cmd_dict := {}
	if commander:
		cmd_dict = commander.to_dict()
	
	var d := {
		"id": id,
		"owner": owner,
		"location": location,
		"units": unit_dicts,
		"commander": cmd_dict,
	}
	if ruler:
		d["ruler"] = ruler.to_dict()  # only ruler armies carry the key, so M1 armies save as before
	if engines > 0:
		d["engines"] = engines  # M3c: only armies carrying siege engines have the key
	if not seen.is_empty():
		d["seen"] = seen_copy(seen)  # M5: only stand-ins in a view carry a note
	if flame >= 0:
		d["flame"] = flame  # CW-1: only the armies of a faction that keeps a flame carry the key
	return d

## Returns null when the army is in an unknown province, holds an unknown unit type, or a field has the
## wrong type, with a plain-language reason in `errors` (Serial load checks). `who` names the army in
## it; GameState.from_dict passes "army 'kingdom-1'".
static func from_dict(data: Dictionary, all_unit_types: Dictionary, province_ids: Dictionary, errors = null, who: String = "") -> Army:
	if who.is_empty():
		who = Serial.label("army", data)
	var a := Army.new()
	for key in ["id", "owner", "location"]:
		var text = Serial.expect(data, key, TYPE_STRING, errors, who, "")
		if text == null:
			return null
		a.set(key, String(text))
	if not province_ids.has(a.location):
		Serial.report(errors, "%s is at '%s', which is not a province on this map." % [Serial.cap(who), a.location])
		return null

	var unit_list = Serial.expect_dicts(data, "units", errors, who, "unit")
	if unit_list == null:
		return null
	for i in unit_list.size():
		var unit := Unit.from_dict(unit_list[i], all_unit_types, errors, "unit %d of %s" % [i + 1, who])
		if unit == null:
			return null
		a.units.append(unit)

	var cmd_data = Serial.expect(data, "commander", TYPE_DICTIONARY, errors, who, {})  # {} when it has none
	if cmd_data == null:
		return null
	if not cmd_data.is_empty():
		a.commander = Unit.from_dict(cmd_data, all_unit_types, errors, "the commander of %s" % who)
		if a.commander == null:
			return null

	# Only a ruler's army has the key. The ruler's type is its faction's ruler_unit_type, which
	# GameState.from_dict puts in all_unit_types under the ruler's id before loading armies.
	var ruler_data = Serial.expect(data, "ruler", TYPE_DICTIONARY, errors, who, {})
	if ruler_data == null:
		return null
	if not ruler_data.is_empty():
		a.ruler = Unit.from_dict(ruler_data, all_unit_types, errors, "the ruler of %s" % who)
		if a.ruler == null:
			return null

	a.engines = Serial.to_int(data.get("engines", 0))  # M3c; GameState.validate checks the count
	a.flame = Serial.to_int(data.get("flame", -1), -1)  # CW-1; WickRules.validate checks it
	var note = Serial.expect(data, "seen", TYPE_DICTIONARY, errors, who, {})  # M5: views only; GameState.validate checks it
	if note == null:
		return null
	a.seen = seen_copy(note)
	return a


## Checks this army's view note (seen) has the fixed shape of §2.7: exactly SEEN_KEYS, a known level, whole
## numbers from 0 and round counts of exactly ROUND_COUNT_KEYS, so a view carries nothing else. Appends plain
## reasons to `errors` (or push_error when it isn't an Array). Only for a view: GameState.validate rejects a
## note in a true state before asking.
func validate_seen(errors = null) -> bool:
	var problems := []
	for key in SEEN_KEYS:
		if not seen.has(key):
			problems.append("has no '%s'" % key)
	for key in seen:
		if not SEEN_KEYS.has(str(key)):
			problems.append("holds '%s', which a view note never holds" % key)
	var level = seen.get("level", "")
	if seen.has("level") and not (level is String and ["clear", "glimpse", "memory"].has(level)):
		problems.append("has the level '%s', but a note is clear, glimpse or memory" % str(level))
	for key in ["turn", "blessed"]:
		if seen.has(key) and not (seen[key] is int and int(seen[key]) >= 0):
			problems.append("has '%s' %s, but it is a whole number from 0" % [key, str(seen[key])])
	if seen.has("total"):
		problems.append_array(_round_count_problems(seen.total, "its total"))
	if seen.has("counts"):
		if seen.counts is Dictionary:
			for type_id in seen.counts:
				problems.append_array(_round_count_problems(seen.counts[type_id], "its count of '%s'" % type_id))
		else:
			problems.append("has counts that are not a group of round counts by unit type")
	for p in problems:
		Serial.report(errors, "The view note of army '%s' %s." % [id, p])
	return problems.is_empty()


static func _round_count_problems(value, what: String) -> Array:
	if not (value is Dictionary):
		return ["has %s as %s, not a round count" % [what, str(value)]]
	var out := []
	for key in ROUND_COUNT_KEYS:
		if not value.has(key):
			out.append("has no '%s' in %s" % [key, what])
		elif key == "text":
			if not (value[key] is String):
				out.append("has a '%s' in %s that is not text" % [key, what])
		elif not (value[key] is int and int(value[key]) >= 0):
			out.append("has '%s' %s in %s, but it is a whole number from 0" % [key, str(value[key]), what])
	for key in value:
		if not ROUND_COUNT_KEYS.has(str(key)):
			out.append("holds '%s' in %s, which a round count never holds" % [key, what])
	return out


## A copy of view note `note` in its saved form: its keys in SEEN_KEYS order (any others after them), its
## numbers as ints (JSON reads them back as floats) and its texts as text. A value of the wrong kind is kept as
## it is, so GameState.validate can name it.
static func seen_copy(note: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = SEEN_KEYS.filter(func(k): return note.has(k))
	for k in note:
		if not SEEN_KEYS.has(str(k)):
			keys.append(k)
	for k in keys:
		var value = note[k]
		match str(k):
			"level":
				out["level"] = String(value) if value is String or value is StringName else value
			"turn", "blessed":
				out[str(k)] = Serial.to_int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else value
			"total":
				out["total"] = _round_count_copy(value)
			"counts":
				if value is Dictionary:
					var counts := {}
					for type_id in value:
						counts[str(type_id)] = _round_count_copy(value[type_id])
					out["counts"] = counts
				else:
					out["counts"] = value
			_:
				out[str(k)] = value.duplicate(true) if value is Dictionary or value is Array else value
	return out


## A round count ({"shown", "low", "high", "text"}) with its numbers as ints, or `value` itself when it isn't one.
static func _round_count_copy(value):
	if not (value is Dictionary):
		return value
	var out := {}
	for k in ROUND_COUNT_KEYS:
		if value.has(k):
			var v = value[k]
			if k == "text":
				out[k] = String(v) if v is String or v is StringName else v
			else:
				out[k] = Serial.to_int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else v
	for k in value:
		if not ROUND_COUNT_KEYS.has(str(k)):
			out[str(k)] = value[k]
	return out
