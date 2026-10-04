class_name RecruitOrder
## Order: recruit one unit of a type from your faction's roster at your capital, paid in gold.
## Takes effect in the recruitment phase, after capture: you must still hold your capital then.
## Several recruit orders are paid in the order they were given.
## Warband Muster (M2, design/M2_RULER.md §1.4): `at` = "ruler" recruits a regular unit with the
## ruler instead, where it stands after movement and battles (TurnResolver.check_recruit has the
## rule). Without `at` it is the M1 capital recruit, and it saves exactly as before.
## Forts and sieges (M3c, design/M3C_SIEGES.md §2.3), only in a game with sieges: `at` may name a fort you own
## (its province id), where the unit is made, within that fort's limit; an `at` naming your own capital is read
## as the capital. In a game without sieges such an `at` is rejected, as before. In a game with sieges the unit
## type may be the faction's siege engine (SiegeRules.engine_type), recruited at a keep or citadel.

## Where the unit is recruited: at the capital (M1) or with the ruler (Warband Muster); M3c: or a fort's id.
const AT_CAPITAL := ""
const AT_RULER := "ruler"

var unit_type_id: String
var at: String  # AT_CAPITAL, AT_RULER, or (M3c, with sieges) a fort's province id

func _init(p_unit_type_id: String = "", p_at: String = AT_CAPITAL) -> void:
	unit_type_id = p_unit_type_id
	at = p_at

func is_with_ruler() -> bool:
	return at == AT_RULER

func to_dict() -> Dictionary:
	var d := {"type": "recruit", "unit_type": unit_type_id}
	if not at.is_empty():
		d["at"] = at  # only Warband Muster and fort recruits carry the key, so M1 records stay byte-identical
	return d

func describe() -> String:
	if at.is_empty():
		return "recruit %s" % unit_type_id
	return "recruit %s at %s" % [unit_type_id, at]
