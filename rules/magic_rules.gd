class_name MagicRules
## The magic rules (M5 "magic and fog of war", design/M5_MAGIC_FOG.md §3-§8). Pure functions over GameState: no
## nodes, no scenes, no randomness (spells and rituals never draw).
##
## Magic is OPT-IN at game setup, as paths are: GameState.magic is off by default, and without it no magic key is
## saved, so M1, M2 and M4 games save exactly as before.
##
## M5-0 (#111) is the scaffold the fog and magic lanes build on:
##   the state's magic fields      GameState.magic, GameState.enchantments, Faction.spellbook,
##                                 Faction.enchant_counter, Faction.bastions, UnitType.summoned, Unit.until
##   enchantment_copy, enchantment_from_dict   an enchantment's saved form (§6.4)
##   validate(state, errors)       those fields checked against GameState.magic, in plain language
##   vision_grants(state, fid)     the provinces a faction's magic lets it see (a stub until Far Sight, M5-6)
## M5-5 adds the schools, spells, casters, mastery, cast checks and prices; M5-6 the rituals and enchantments.

## The kinds of ritual that leave an enchantment in GameState.enchantments (§3.4, §6.2-§6.4). Summons leave
## creatures (Unit.until) and raisings leave a fort (Faction.bastions) instead.
const ENCHANTMENT_KINDS := ["blessing", "ward", "curse", "global", "sight"]
## An enchantment's fields, in the order they are saved (§6.4). Nothing else is saved, so nothing else can leak
## into a view.
const ENCHANTMENT_KEYS := ["id", "ritual", "faction", "kind", "province", "armies", "cast_turn", "until_turn", "bonus", "ending"]


## The province ids `faction_id` sees in clear sight through magic (Far Sight, §6.2), sorted. FogRules.sight
## (M5-1) calls it. A stub until M5-6 brings Far Sight: no faction sees anything through magic yet.
static func vision_grants(_state: GameState, _faction_id: String) -> Array:
	return []


# --- the saved form -------------------------------------------------------------------------------

## Enchantment `e` in its saved form: exactly ENCHANTMENT_KEYS in that order, texts as text, turns and the bonus as
## ints (JSON reads them back as floats), `armies` as a list of ids and `ending` as true or false.
static func enchantment_copy(e: Dictionary) -> Dictionary:
	return {
		"id": _text(e, "id"),
		"ritual": _text(e, "ritual"),
		"faction": _text(e, "faction"),
		"kind": _text(e, "kind"),
		"province": _text(e, "province"),
		"armies": Serial.to_string_array(e.get("armies", [])),
		"cast_turn": Serial.to_int(e.get("cast_turn", 0)),
		"until_turn": Serial.to_int(e.get("until_turn", 0)),
		"bonus": Serial.to_int(e.get("bonus", 0)),
		"ending": e.get("ending") == true,
	}


## Reads one saved enchantment (GameState.from_dict). Returns null when a field has the wrong type, with a
## plain-language reason in `errors` (Serial load checks); validate checks what the values mean.
static func enchantment_from_dict(data: Dictionary, errors = null, who: String = "") -> Variant:
	if who.is_empty():
		who = Serial.label("enchantment", data)
	for key in ["id", "ritual", "faction", "kind", "province"]:
		if Serial.expect(data, key, TYPE_STRING, errors, who, "") == null:
			return null
	if Serial.expect(data, "armies", TYPE_ARRAY, errors, who, []) == null:
		return null
	if Serial.expect(data, "ending", TYPE_BOOL, errors, who, false) == null:
		return null
	return enchantment_copy(data)


# --- checks ---------------------------------------------------------------------------------------

## Checks the magic fields (GameState.validate calls it). Without magic the game carries none of them: no
## enchantment, spellbook, enchantment count, Bastion fort, summoned creature or fading unit. With magic, the game
## has paths, and every spellbook, Bastion entry, enchantment and summoned unit is well formed (§5.1, §6.4).
## Appends plain-language messages to `errors` (or push_error when it isn't an Array).
static func validate(state: GameState, errors = null) -> bool:
	if not state.magic:
		return _validate_without_magic(state, errors)
	var ok := true
	if not state.paths:
		_report(errors, "This game has magic, but magic needs paths (and paths need rulers), and it is played without them.")
		ok = false
	var provinces := {}
	for p in state.provinces:
		provinces[p.id] = true
	for f in state.factions:
		if not _validate_faction(f, provinces, errors):
			ok = false
	if not _validate_enchantments(state, provinces, errors):
		ok = false
	for a in state.armies:
		for i in a.units.size():
			var u: Unit = a.units[i]
			if u.until == 0:
				continue
			var who := "%s (unit %d of army '%s')" % [u.type.name, i + 1, a.id]
			if not u.type.summoned:
				_report(errors, "%s fades at the end of turn %d, but only summoned creatures fade." % [Serial.cap(who), u.until])
				ok = false
			elif u.until <= state.current_turn:
				_report(errors, "%s should have faded at the end of turn %d, and turn %d is over." % [Serial.cap(who), u.until, state.current_turn])
				ok = false
	return ok


static func _validate_without_magic(state: GameState, errors) -> bool:
	var ok := true
	if not state.enchantments.is_empty():
		_report(errors, "This game has %d enchantments, but it is played without magic." % state.enchantments.size())
		ok = false
	for f in state.factions:
		var name := _faction_name(f)
		if not f.spellbook.is_empty():
			_report(errors, "%s has a battle spellbook, but this game is played without magic." % name)
			ok = false
		if f.enchant_counter != 0:
			_report(errors, "%s has begun %d enchantments, but this game is played without magic." % [name, f.enchant_counter])
			ok = false
		if not f.bastions.is_empty():
			_report(errors, "%s has raised Bastion forts, but this game is played without magic." % name)
			ok = false
		for ut in _types(f):
			if ut.summoned:
				_report(errors, "%s has the summoned creature %s, but this game is played without magic, and only a ritual summons creatures." % [name, ut.name])
				ok = false
	for a in state.armies:
		for i in a.units.size():
			var u: Unit = a.units[i]
			if u.type.summoned or u.until != 0:
				_report(errors, "Army '%s' holds %s (unit %d), a summoned creature, but this game is played without magic." % [a.id, u.type.name, i + 1])
				ok = false
		for u in [a.commander, a.ruler]:
			if u != null and (u.type.summoned or u.until != 0):
				_report(errors, "Army '%s' is led by %s, a summoned creature, but this game is played without magic." % [a.id, u.type.name])
				ok = false
	return ok


static func _validate_faction(f: Faction, provinces: Dictionary, errors) -> bool:
	var ok := true
	var name := _faction_name(f)
	var book := f.spellbook
	if not book.is_empty():
		for key in book:
			if not ["order", "off"].has(str(key)):
				_report(errors, "%s's battle spellbook holds '%s'; a spellbook is its order and the spells switched off." % [name, key])
				ok = false
		var order = book.get("order", [])
		var off = book.get("off", [])
		if not (order is Array and off is Array):
			_report(errors, "%s's battle spellbook should list its order and the spells switched off." % name)
			return false
		var listed := {}
		for sid in order:
			if not (sid is String) or String(sid).is_empty():
				_report(errors, "%s's battle spellbook has a spell with no id." % name)
				ok = false
			elif listed.has(sid):
				_report(errors, "%s's battle spellbook lists '%s' twice." % [name, sid])
				ok = false
			listed[sid] = true
		var switched := {}
		for sid in off:
			if not listed.has(sid):
				_report(errors, "%s's battle spellbook switches off '%s', which is not in its order." % [name, str(sid)])
				ok = false
			elif switched.has(sid):
				_report(errors, "%s's battle spellbook switches off '%s' twice." % [name, sid])
				ok = false
			switched[sid] = true
	if f.enchant_counter < 0:
		_report(errors, "%s has begun %d enchantments, but the count is never below 0." % [name, f.enchant_counter])
		ok = false
	var raised := {}
	for pid in f.bastions:
		if not provinces.has(pid):
			_report(errors, "%s raised a Bastion fort at '%s', which is not a province on this map." % [name, pid])
			ok = false
		elif raised.has(pid):
			_report(errors, "%s lists its Bastion fort at '%s' twice." % [name, pid])
			ok = false
		raised[pid] = true
	return ok


static func _validate_enchantments(state: GameState, provinces: Dictionary, errors) -> bool:
	var ok := true
	var ids := {}
	var last := ""
	for e in state.enchantments:
		var eid := _text(e, "id")
		var what := "Enchantment '%s'" % eid
		if eid.is_empty():
			_report(errors, "An enchantment has no id.")
			ok = false
		elif ids.has(eid):
			_report(errors, "Two enchantments share the id '%s'." % eid)
			ok = false
		elif not last.is_empty() and eid < last:
			_report(errors, "The enchantments are kept in id order, but '%s' comes after '%s'." % [eid, last])
			ok = false
		ids[eid] = true
		last = eid
		var fid := _text(e, "faction")
		var f := state.find_faction(fid)
		if f == null:
			_report(errors, "%s belongs to '%s', which is not a faction in this game." % [what, fid])
			ok = false
		elif eid.begins_with(fid + "-e") and eid.substr(fid.length() + 2).is_valid_int():
			var n := eid.substr(fid.length() + 2).to_int()
			if n < 1 or n > f.enchant_counter:
				_report(errors, "%s is numbered %d, but %s has begun %d enchantments." % [what, n, _faction_name(f), f.enchant_counter])
				ok = false
		if _text(e, "ritual").is_empty():
			_report(errors, "%s names no ritual." % what)
			ok = false
		var kind := _text(e, "kind")
		if not ENCHANTMENT_KINDS.has(kind):
			_report(errors, "%s is of kind '%s', but an enchantment is a blessing, a ward, a curse, a global or a sight." % [what, kind])
			ok = false
		var pid := _text(e, "province")
		if kind == "global" and not pid.is_empty():
			_report(errors, "%s is global, so it lies on no province, but it names '%s'." % [what, pid])
			ok = false
		elif kind != "global" and not provinces.has(pid):
			_report(errors, "%s lies on '%s', which is not a province on this map." % [what, pid])
			ok = false
		var blessed = e.get("armies", [])
		if not (blessed is Array):
			_report(errors, "%s should list the armies it blesses." % what)
			ok = false
			blessed = []
		if kind != "blessing" and not blessed.is_empty():
			_report(errors, "%s lists armies, but only a blessing is on armies." % what)
			ok = false
		var seen := {}
		for aid in blessed:
			var a := state.find_army(str(aid))
			if a == null or a.owner != fid:
				_report(errors, "%s blesses army '%s', which is not an army of '%s' in this game." % [what, aid, fid])
				ok = false
			elif seen.has(aid):
				_report(errors, "%s blesses army '%s' twice." % [what, aid])
				ok = false
			seen[aid] = true
		var cast := Serial.to_int(e.get("cast_turn", 0))
		var until := Serial.to_int(e.get("until_turn", 0))
		if cast < 1:
			_report(errors, "%s was cast on turn %d, but turns count from 1." % [what, cast])
			ok = false
		if until < cast:
			_report(errors, "%s lasts through turn %d, before turn %d, when it was cast." % [what, until, cast])
			ok = false
		elif until <= state.current_turn:
			_report(errors, "%s lasted through turn %d, and turn %d is over, so it should have ended." % [what, until, state.current_turn])
			ok = false
		var bonus := Serial.to_int(e.get("bonus", 0))
		if bonus < 0:
			_report(errors, "%s has a mastery bonus of %d, but a bonus is never below 0." % [what, bonus])
			ok = false
		if e.get("ending") == true and kind != "curse":
			_report(errors, "%s is ending early, but only a curse is ended early (by a ward)." % what)
			ok = false
	return ok


# --- helpers --------------------------------------------------------------------------------------

## Every unit type a faction knows: its roster, its commander and its ruler.
static func _types(f: Faction) -> Array:
	var out: Array = f.unit_types.duplicate()
	for ut in [f.commander_type, f.ruler_unit_type]:
		if ut != null:
			out.append(ut)
	return out


static func _faction_name(f: Faction) -> String:
	return f.faction_name if not f.faction_name.is_empty() else f.id


static func _text(e: Dictionary, key: String) -> String:
	var v = e.get(key)
	return "" if v == null else str(v)


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
