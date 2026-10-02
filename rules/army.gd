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

func get_description() -> String:
	if ruler:
		return "%s ruler %s at %s" % [owner, ruler.type.name, location]
	var desc := "%s army at %s with %d units" % [owner, location, units.size()]
	if commander:
		desc += " led by %s" % commander.type.name
	return desc

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
	return d

static func from_dict(data: Dictionary, all_unit_types: Dictionary, province_ids: Dictionary, errors = null) -> Army:
	var location = data.get("location", "")
	if not province_ids.has(location):
		var msg = "unknown province '%s'" % location
		if errors is Array:
			errors.append(msg)
		else:
			push_error(msg)
		return null
	var a := Army.new()
	a.id = str(data.get("id", ""))
	a.owner = str(data.get("owner", ""))
	a.location = location
	
	for u_data in data.get("units", []):
		var unit = Unit.from_dict(u_data, all_unit_types, errors)
		if unit == null:
			return null
		a.units.append(unit)
	
	if data.has("commander") and not data.commander.is_empty():
		var cmd = Unit.from_dict(data.commander, all_unit_types, errors)
		if cmd == null:
			return null
		a.commander = cmd

	var ruler_data = data.get("ruler", {})
	if ruler_data is Dictionary and not ruler_data.is_empty():
		# The ruler's type is its faction's ruler_unit_type, which GameState.from_dict puts in
		# all_unit_types under the ruler's id before loading armies.
		var r = Unit.from_dict(ruler_data, all_unit_types, errors)
		if r == null:
			return null
		a.ruler = r

	return a
