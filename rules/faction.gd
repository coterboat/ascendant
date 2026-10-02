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


func has_ruler() -> bool:
	return not ruler_type.is_empty()

func get_description() -> String:
	return faction_name

# Faction stat descriptions per acceptance criterion
static func describe(stat: String) -> String:
	match stat:
		"gold": return "Current treasury. Used to recruit units and commanders."
		_: return ""

func to_dict() -> Dictionary:
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
	return d

static func from_dict(data: Dictionary) -> Faction:
	var f := Faction.new()
	f.id = data.get("id", "")
	f.faction_name = data.get("name", "")
	f.gold = Serial.to_int(data.get("gold", 0))
	f.capital = data.get("capital", "")
	
	if data.has("unit_types"):
		for u in data.unit_types:
			f.unit_types.append(UnitType.from_dict(u))
	
	if data.has("commander_type") and not data.commander_type.is_empty():
		f.commander_type = UnitType.from_dict(data.commander_type)

	# Ruler fields are only present for a faction with a ruler (see to_dict). GameState.from_dict
	# checks them and rebuilds ruler_unit_type.
	f.ruler_type = str(data.get("ruler_type", ""))
	if f.has_ruler():
		f.kept_power = Serial.to_int(data.get("kept_power", 0))
		f.mandates = Serial.to_string_array(data.get("mandates", []))
		f.ruler_generation = Serial.to_int(data.get("ruler_generation", 1), 1)
		f.ruler_status = str(data.get("ruler_status", "alive"))
		f.successor_turn = Serial.to_int(data.get("successor_turn", 0))
		f.successor_power = Serial.to_int(data.get("successor_power", 0))
		var sacs = data.get("sacrifices", [])
		if sacs is Array:
			for sac in sacs:
				if sac is Dictionary:
					f.sacrifices.append({"turn": Serial.to_int(sac.get("turn", 0)), "mandate": str(sac.get("mandate", "")),
						"cost": Serial.to_int(sac.get("cost", 0))})
	else:
		# A faction without a ruler has no mandates; keep any in the data so validation can name them.
		f.mandates = Serial.to_string_array(data.get("mandates", []))
	return f
