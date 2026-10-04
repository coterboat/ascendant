class_name Faction
## Pure faction data.

var id: String
var faction_name: String
var gold: int = 0
var capital: String = ""

var unit_types: Array[UnitType] = []
var commander_type: UnitType = null

# --- the ruler (M2, #29; design/M2_RULER.md §9). Rules: RulerRules. ---
# Rulers are opt-in at game setup (GameState.with_rulers): an empty ruler_type means this faction has
# no ruler, and then none of these fields are serialized, so an M1 game saves exactly as before.
var ruler_type: String = ""  # RulerData id, e.g. "aurel_king"
var kept_power: int = 0  # 0..10: the pool minus mandates, sacrifices and succession losses
var mandates: Array = []  # MandateData ids, in the order taken (the pre-game build, then sacrifices)
var ruler_generation: int = 0  # 1 for the first ruler, +1 for each successor
var ruler_status: String = ""  # "alive" or "dead" ("" without a ruler)
var successor_turn: int = 0  # the turn whose end the next ruler arrives at; 0 when none is due
var successor_power: int = 0  # the kept power that successor will have
var sacrifices: Array = []  # mid-game sacrifices: [{"turn", "mandate", "cost"}], in order
## The living ruler's stats as a UnitType, built from ruler_type, kept_power and ruler_generation by
## RulerRules.refresh_ruler_type. Derived, so never serialized: it is rebuilt on load.
var ruler_unit_type: UnitType = null

# --- research and the path (M4, #66; design/M4_ASCENSION.md §2.2, §3.3). Rules: AscensionRules. ---
# Paths are opt-in at game setup (GameState.with_paths): in a game without paths these stay at their
# defaults and are never serialized (GameState.to_dict passes with_path), so M1 and M2 games save as before.
var research_points: int = 0  # the research pool: whole points, never lost (§2.2)
var research_target: String = ""  # the node being researched (PathData id), or ""; private to this faction
var researched: Array = []  # [{"node": PathData id, "turn": the turn it was done at the end of}], in order
var path_branch: String = ""  # the side of the fork its Oath swore to ("celestial_host", ...), or ""

# --- magic (M5, design/M5_MAGIC_FOG.md §5.1, §6.4, §14). Rules: MagicRules. ---
# Magic is opt-in at game setup (GameState.magic): in a game without it these stay at their defaults and are never
# serialized (GameState.to_dict passes with_magic), so M1, M2 and M4 games save as before.
var spellbook: Dictionary = {}  # the battle spellbook (SpellbookOrder): {} for the default, or {"order": [spell ids], "off": [spell ids]}
var enchant_counter: int = 0  # how many enchantments it has begun; its ids count per faction ("beasts-e3")
var bastions: Array = []  # province ids Bastion has raised a fort in, ever (for the cap)


func has_ruler() -> bool:
	return not ruler_type.is_empty()

func get_description() -> String:
	return faction_name

# Faction stat descriptions per acceptance criterion
static func describe(stat: String) -> String:
	match stat:
		"gold": return "Current treasury. Used to recruit units and commanders."
		_: return ""

## `with_path` (GameState.to_dict passes GameState.paths) adds the research and path fields; without it
## they are left out, so a game without paths saves exactly as before. `with_magic` (GameState.magic) adds the
## magic fields the same way.
func to_dict(with_path: bool = false, with_magic: bool = false) -> Dictionary:
	var ut_dicts := []
	for ut in unit_types:
		ut_dicts.append(ut.to_dict())
	
	var d := {
		"id": id,
		"name": faction_name,
		"gold": gold,
		"capital": capital,
		"unit_types": ut_dicts,
		"commander_type": commander_type.to_dict() if commander_type else {},
	}
	if has_ruler():
		var sacrifice_dicts := []
		for sac in sacrifices:
			sacrifice_dicts.append({"turn": int(sac.get("turn", 0)), "mandate": str(sac.get("mandate", "")),
				"cost": int(sac.get("cost", 0))})
		d["ruler_type"] = ruler_type
		d["kept_power"] = kept_power
		d["mandates"] = mandates.duplicate()
		d["ruler_generation"] = ruler_generation
		d["ruler_status"] = ruler_status
		d["successor_turn"] = successor_turn
		d["successor_power"] = successor_power
		d["sacrifices"] = sacrifice_dicts
	if with_path:
		var done := []
		for r in researched:
			done.append({"node": str(r.get("node", "")), "turn": int(r.get("turn", 0))})
		d["research_points"] = research_points
		d["research_target"] = research_target
		d["researched"] = done
		d["path_branch"] = path_branch
	if with_magic:
		d["spellbook"] = spellbook_copy(spellbook)
		d["enchant_counter"] = enchant_counter
		d["bastions"] = bastions.duplicate()
	return d


## A copy of spellbook `book` in its saved form: {} stays {}; otherwise {"order": [...], "off": [...]} with the
## ids as text. A value of the wrong kind is kept as it is, so MagicRules.validate can name it.
static func spellbook_copy(book: Dictionary) -> Dictionary:
	if book.is_empty():
		return {}
	var out := {}
	for key in ["order", "off"]:
		var ids = book.get(key, [])
		out[key] = Serial.to_string_array(ids) if ids is Array else ids
	for key in book:
		if not ["order", "off"].has(str(key)):
			out[str(key)] = book[key]
	return out

## Returns null when a field has the wrong type, with a plain-language reason in `errors` (Serial load
## checks). `who` names the faction in it; GameState.from_dict passes "faction 'kingdom'".
static func from_dict(data: Dictionary, errors = null, who: String = "") -> Faction:
	if who.is_empty():
		who = Serial.label("faction", data)
	var text := {}
	for key in ["id", "name", "capital", "ruler_type"]:
		text[key] = Serial.expect(data, key, TYPE_STRING, errors, who, "")
		if text[key] == null:
			return null
	var f := Faction.new()
	f.id = text.id
	f.faction_name = text.name
	f.gold = Serial.to_int(data.get("gold", 0))
	f.capital = text.capital

	var type_list = Serial.expect_dicts(data, "unit_types", errors, who, "unit type")
	if type_list == null:
		return null
	for i in type_list.size():
		var ut := UnitType.from_dict(type_list[i], errors, "unit type %d of %s" % [i + 1, who])
		if ut == null:
			return null
		f.unit_types.append(ut)

	var cmd_data = Serial.expect(data, "commander_type", TYPE_DICTIONARY, errors, who, {})  # {} when it has none
	if cmd_data == null:
		return null
	if not cmd_data.is_empty():
		f.commander_type = UnitType.from_dict(cmd_data, errors, "the commander type of %s" % who)
		if f.commander_type == null:
			return null

	# A faction without a ruler has no mandates; any in the data are kept so validation can name them.
	var mandate_list = Serial.expect(data, "mandates", TYPE_ARRAY, errors, who, [])
	if mandate_list == null:
		return null
	f.mandates = Serial.to_string_array(mandate_list)

	# Research and the path (M4): only present in a game with paths (see to_dict). AscensionRules.validate
	# checks them against GameState.paths.
	for key in ["research_target", "path_branch"]:
		var value = Serial.expect(data, key, TYPE_STRING, errors, who, "")
		if value == null:
			return null
		f.set(key, String(value))
	var done_list = Serial.expect_dicts(data, "researched", errors, who, "researched node")
	if done_list == null:
		return null
	for i in done_list.size():
		var node = Serial.expect(done_list[i], "node", TYPE_STRING, errors, "researched node %d of %s" % [i + 1, who], "")
		if node == null:
			return null
		f.researched.append({"node": String(node), "turn": Serial.to_int(done_list[i].get("turn", 0))})
	f.research_points = Serial.to_int(data.get("research_points", 0))

	# Magic (M5): only present in a game with magic (see to_dict). MagicRules.validate checks them against
	# GameState.magic.
	var book = Serial.expect(data, "spellbook", TYPE_DICTIONARY, errors, who, {})
	if book == null:
		return null
	for key in ["order", "off"]:
		if Serial.expect(book, key, TYPE_ARRAY, errors, "the spellbook of %s" % who, []) == null:
			return null
	f.spellbook = spellbook_copy(book)
	var raised = Serial.expect(data, "bastions", TYPE_ARRAY, errors, who, [])
	if raised == null:
		return null
	f.bastions = Serial.to_string_array(raised)
	f.enchant_counter = Serial.to_int(data.get("enchant_counter", 0))

	# The other ruler fields are only present for a faction with a ruler (see to_dict). GameState.from_dict
	# checks them and rebuilds ruler_unit_type.
	f.ruler_type = text.ruler_type
	if not f.has_ruler():
		return f
	var status = Serial.expect(data, "ruler_status", TYPE_STRING, errors, who, "alive")
	if status == null:
		return null
	var sac_list = Serial.expect_dicts(data, "sacrifices", errors, who, "sacrifice")
	if sac_list == null:
		return null
	f.ruler_status = status
	f.kept_power = Serial.to_int(data.get("kept_power", 0))
	f.ruler_generation = Serial.to_int(data.get("ruler_generation", 1), 1)
	f.successor_turn = Serial.to_int(data.get("successor_turn", 0))
	f.successor_power = Serial.to_int(data.get("successor_power", 0))
	for sac in sac_list:
		f.sacrifices.append({"turn": Serial.to_int(sac.get("turn", 0)), "mandate": str(sac.get("mandate", "")),
			"cost": Serial.to_int(sac.get("cost", 0))})
	return f
