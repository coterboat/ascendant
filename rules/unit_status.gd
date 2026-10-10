class_name UnitStatus
## ARM-1 (design/ARM1_SPLIT_MERGE.md §2.1): the registry of per-unit statuses. Pure rules code.
##
## A status is a record on one unit (`Unit.statuses`): {"kind", "source", ...}. Dominions remembers its
## afflictions and enchantments on each unit, and so does this game: the plumbing (save, validate, clear, show, fog)
## lives here once, and a new kind (a lasting wound, veterancy, a per-unit curse) only adds its row to KINDS and its
## own effect code.
##
## Each kind registers, in KINDS and the functions below:
##   fields    its fields and their types (exactly these keys, nothing else), "kind" and "source" first
##   validate  `problem_in_state` against the game it lives in (a plain reason, or "")
##   clears    when it clears: "source_ends" (the enchantment that made it ends), "recast" (that enchantment is cast
##             again, which keeps its id and covers everyone), "leaves_army" (its unit leaves the army it stands in),
##             "turn" (a turn count, for kinds that carry one)
##   tooltip   how it reads on a unit (`tooltip`), with the codex entry that explains it (`codex_id`)
##   fog       how it shows in a rival's view: FOG_HIDDEN (never; its effect reaches a rival only through what it
##             changes, which is pooled and rounded as any sighting) or FOG_CLEAR (a rival in clear sight sees it)
##
## ARM-1 ships one kind, OUTSIDE_BLESSING: {"kind": "outside_blessing", "source": <the blessing's enchantment id>}.
## A unit that joins a blessed army after the blessing was cast (a muster, a recruit, a commander moved in) carries
## it, and the blessing skips it: healing, the half-blessed morale, fog pooling and the computer's valuation all
## decide per fighter (MagicRules.covers). It is saved only when a unit has statuses, as Unit.until is, so every
## existing record and save is byte-identical.

const OUTSIDE_BLESSING := "outside_blessing"

const FOG_HIDDEN := "hidden"
const FOG_CLEAR := "clear"
const FOG_RULES := [FOG_HIDDEN, FOG_CLEAR]

## The triggers a kind may clear on.
const TRIGGERS := ["source_ends", "recast", "leaves_army", "turn"]

## The registry. "name" is the player-facing name; "fields" the keys and their types, in saved order.
const KINDS := {
	OUTSIDE_BLESSING: {
		"name": "Outside the blessing",
		"fields": {"kind": TYPE_STRING, "source": TYPE_STRING},
		"clears": ["source_ends", "recast", "leaves_army"],
		"fog": FOG_HIDDEN,
		"codex_id": "blessing",
	},
}

## Every hook a kind declares in KINDS (the registry's own test checks each kind has each one).
const HOOKS := ["name", "fields", "clears", "fog", "codex_id"]


# --- the registry -----------------------------------------------------------------------------------

static func known(kind: String) -> bool:
	return KINDS.has(kind)


static func kinds() -> Array:
	var out: Array = KINDS.keys()
	out.sort()
	return out


static func kind_name(kind: String) -> String:
	return String(KINDS.get(kind, {}).get("name", kind))


## The codex entry that explains `kind`.
static func codex_id(kind: String) -> String:
	return String(KINDS.get(kind, {}).get("codex_id", ""))


## Whether `kind` clears on `trigger` (one of TRIGGERS).
static func clears_on(kind: String, trigger: String) -> bool:
	return Array(KINDS.get(kind, {}).get("clears", [])).has(trigger)


## How `kind` shows in a rival's view: FOG_HIDDEN or FOG_CLEAR.
static func fog_rule(kind: String) -> String:
	return String(KINDS.get(kind, {}).get("fog", FOG_HIDDEN))


## Whether a rival whose sight of the unit is `level` ("clear", "glimpse" or "memory") sees a status of `kind`.
static func shown_to_rival(kind: String, level: String) -> bool:
	return fog_rule(kind) == FOG_CLEAR and level == FogRules.CLEAR


## One short line for a status on a unit, for tooltips: what it is and why it is there. `state` names the source.
static func tooltip(status: Dictionary, state: GameState = null) -> String:
	var kind := String(status.get("kind", ""))
	match kind:
		OUTSIDE_BLESSING:
			var e := MagicRules._enchantment(state, String(status.get("source", ""))) if state != null else {}
			var name := MagicRules.spell_name(String(e.ritual)) if not e.is_empty() else "the blessing"
			return "Outside the blessing: it joined this army after %s was cast, so %s doesn't heal it or count it for morale." % [name, name]
	return ""


# --- the shape of a status ---------------------------------------------------------------------------

## Plain reasons `status` is not a well-formed status record: a group of named values holding exactly its kind's
## fields, each of its type. [] when it is well formed.
static func shape_problems(status: Variant) -> Array:
	if not (status is Dictionary):
		return ["is not a group of named values"]
	var kind = status.get("kind")
	if not (kind is String):
		return ["has no 'kind' text"]
	if not known(String(kind)):
		return ["has the kind '%s', which this game does not know" % kind]
	var fields: Dictionary = KINDS[kind].fields
	var out := []
	for key in fields:
		if not status.has(key):
			out.append("has no '%s'" % key)
		elif typeof(status[key]) != int(fields[key]) and not (int(fields[key]) == TYPE_STRING and status[key] is StringName):
			out.append("has '%s' as %s, not %s" % [key, Serial._type_words(typeof(status[key])), Serial._type_words(int(fields[key]))])
	for key in status:
		if not fields.has(str(key)):
			out.append("holds '%s', which a %s status never holds" % [key, kind])
	return out


## `status` in its saved form: its kind's fields in order, text as text.
static func normalize(status: Dictionary) -> Dictionary:
	var out := {}
	var fields: Dictionary = KINDS.get(String(status.get("kind", "")), {}).get("fields", {})
	for key in fields:
		if status.has(key):
			out[key] = String(status[key]) if int(fields[key]) == TYPE_STRING else status[key]
	return out


## A list of statuses as it is saved (copies, in order).
static func to_list(statuses: Array) -> Array:
	var out := []
	for s in statuses:
		out.append(normalize(s))
	return out


## Reads a saved `statuses` value for `who` ("unit 2 of army 'kingdom-1'"): the list of well-formed, distinct
## statuses, or null after a plain reason in `errors` when it is not a list, holds something malformed, an unknown
## kind, or the same status twice. A load that gets null stops (Unit.from_dict).
static func parse_list(value: Variant, errors, who: String) -> Variant:
	if not Serial.check(value, TYPE_ARRAY, errors, "the 'statuses' field of %s" % who):
		return null
	var out := []
	var seen := {}
	for i in value.size():
		var problems := shape_problems(value[i])
		if not problems.is_empty():
			Serial.report(errors, "Status %d of %s %s." % [i + 1, who, problems[0]])
			return null
		var status := normalize(value[i])
		var key := "%s|%s" % [status.kind, status.get("source", "")]
		if seen.has(key):
			Serial.report(errors, "%s has the status '%s' from '%s' twice." % [Serial.cap(who), status.kind, status.get("source", "")])
			return null
		seen[key] = true
		out.append(status)
	return out


# --- validation against a game --------------------------------------------------------------------

## "" when `status` on `unit` (a fighter of `army`) is valid in `state`, otherwise the plain reason it is not.
## OUTSIDE_BLESSING: its source must be a live blessing of the unit's own faction that lists the army the unit
## stands in, and the unit must be a unit or a commander (a ruler travels alone and never joins an army).
static func problem_in_state(state: GameState, army: Army, unit: Unit, status: Dictionary) -> String:
	var kind := String(status.get("kind", ""))
	var source := String(status.get("source", ""))
	match kind:
		OUTSIDE_BLESSING:
			if unit == army.ruler:
				return "%s carries a status outside a blessing, but a ruler travels alone and is never in an army to join" % _fighter(army, unit)
			var e := MagicRules._enchantment(state, source) if state.magic else {}
			if e.is_empty():
				return "%s is outside the blessing '%s', which is not an enchantment in play" % [_fighter(army, unit), source]
			if String(e.kind) != "blessing":
				return "%s is outside '%s', which is a %s, not a blessing" % [_fighter(army, unit), source, String(e.kind)]
			if String(e.faction) != unit.owner:
				return "%s is outside the blessing '%s', which belongs to '%s', not to its own faction '%s'" % [_fighter(army, unit), source, String(e.faction), unit.owner]
			if not Array(e.armies).has(army.id):
				return "%s is outside the blessing '%s', but that blessing does not list army '%s'" % [_fighter(army, unit), source, army.id]
			return ""
	return "%s has a status of the unknown kind '%s'" % [_fighter(army, unit), kind]


## Checks every status in `state` (GameState.validate calls it). Appends plain reasons to `errors` (or push_error
## when it isn't an Array). A game with no statuses costs one pass over its units.
static func validate(state: GameState, errors = null) -> bool:
	var ok := true
	for a in state.armies:
		var fighters: Array = a.units.duplicate()
		for u in [a.commander, a.ruler]:
			if u != null:
				fighters.append(u)
		for u in fighters:
			for status in u.statuses:
				var why := problem_in_state(state, a, u, status)
				if not why.is_empty():
					Serial.report(errors, why + ".")
					ok = false
	return ok


static func _fighter(army: Army, unit: Unit) -> String:
	var role := "its commander" if unit == army.commander else ("its ruler" if unit == army.ruler else "a unit")
	return "%s (%s) of army '%s'" % [unit.type.name, role, army.id]


# --- clearing -------------------------------------------------------------------------------------

## Removes every status whose source is `source` and whose kind clears on `trigger`, from the units of `state`'s
## armies (only those in `army_ids` when it isn't empty). Returns how many it removed. MagicRules.clear_outside is
## this for a blessing's id.
static func clear_source(state: GameState, source: String, trigger: String = "source_ends", army_ids: Array = []) -> int:
	var n := 0
	for a in state.armies:
		if not army_ids.is_empty() and not army_ids.has(a.id):
			continue
		for u in army_fighters(a):
			n += _clear_unit(u, source, trigger)
	return n


## Removes the statuses of `unit` that clear when it leaves its army. Returns how many.
static func clear_on_leave(unit: Unit) -> int:
	var kept := []
	var n := 0
	for s in unit.statuses:
		if clears_on(String(s.kind), "leaves_army"):
			n += 1
		else:
			kept.append(s)
	unit.statuses = kept
	return n


static func _clear_unit(unit: Unit, source: String, trigger: String) -> int:
	if unit.statuses.is_empty():
		return 0
	var kept := []
	var n := 0
	for s in unit.statuses:
		if String(s.get("source", "")) == source and clears_on(String(s.kind), trigger):
			n += 1
		else:
			kept.append(s)
	unit.statuses = kept
	return n


## An army's fighters: its units, its commander, its ruler.
static func army_fighters(a: Army) -> Array:
	var out: Array = a.units.duplicate()
	if a.commander != null:
		out.append(a.commander)
	if a.ruler != null:
		out.append(a.ruler)
	return out
