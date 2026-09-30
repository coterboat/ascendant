class_name Army
## Army belonging to a faction, located in a province, containing units and a commander.

var id: String  # unique within a GameState, e.g. "kingdom-1"; orders refer to armies by id
var owner: String
var location: String  # province id
var units: Array[Unit] = []
var commander: Unit = null

func get_description() -> String:
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
	
	return {
		"id": id,
		"owner": owner,
		"location": location,
		"units": unit_dicts,
		"commander": cmd_dict,
	}

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
	
	return a
