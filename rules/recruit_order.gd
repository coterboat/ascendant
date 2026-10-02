class_name RecruitOrder
## Order: recruit one unit of a type from your faction's roster at your capital, paid in gold.
## Takes effect in the recruitment phase, after capture: you must still hold your capital then.
## Several recruit orders are paid in the order they were given.

var unit_type_id: String

func _init(p_unit_type_id: String = "") -> void:
	unit_type_id = p_unit_type_id

func to_dict() -> Dictionary:
	return {"type": "recruit", "unit_type": unit_type_id}

func describe() -> String:
	return "recruit %s" % unit_type_id
