class_name Army
## Army belonging to a faction, located in a province, containing units and a commander.

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
		"owner": owner,
		"location": location,
		"units": unit_dicts,
		"commander": cmd_dict,
	}

static func from_dict(data: Dictionary, all_unit_types: Dictionary) -> Army:
	var a := Army.new()
	a.owner = data.get("owner", "")
	a.location = data.get("location", "")
	
	for u_data in data.get("units", []):
		a.units.append(Unit.from_dict(u_data, all_unit_types))
	
	if data.has("commander") and not data.commander.is_empty():
		a.commander = Unit.from_dict(data.commander, all_unit_types)
	
	return a
