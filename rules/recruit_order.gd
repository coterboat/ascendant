class_name RecruitOrder
## Order: recruit one unit of a type from your faction's roster at your capital, paid in gold.
## Takes effect in the recruitment phase, after capture: you must still hold your capital then.
## Several recruit orders are paid in the order they were given.
## Warband Muster (M2, design/M2_RULER.md §1.4): `at` = "ruler" recruits a regular unit with the
## ruler instead, where it stands after movement and battles (TurnResolver.check_recruit has the
## rule). Without `at` it is the M1 capital recruit, and it saves exactly as before.

## Where the unit is recruited: at the capital (M1) or with the ruler (Warband Muster).
const AT_CAPITAL := ""
const AT_RULER := "ruler"

var unit_type_id: String
var at: String  # AT_CAPITAL or AT_RULER

func _init(p_unit_type_id: String = "", p_at: String = AT_CAPITAL) -> void:
	unit_type_id = p_unit_type_id
	at = p_at

func is_with_ruler() -> bool:
	return at == AT_RULER

func to_dict() -> Dictionary:
	var d := {"type": "recruit", "unit_type": unit_type_id}
	if not at.is_empty():
		d["at"] = at  # only Warband Muster recruits carry the key, so M1 records stay byte-identical
	return d

func describe() -> String:
	if at.is_empty():
		return "recruit %s" % unit_type_id
	return "recruit %s at %s" % [unit_type_id, at]
