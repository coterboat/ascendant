class_name FortifyOrder
## Order (M3c "forts and sieges", design/M3C_SIEGES.md §2.4): build the next fort level in a province you
## own: a palisade where there is no fort, a keep where there is a palisade. Only in a game with sieges.
## Checked in the orders phase (SiegeRules.check_fortify) and paid in the recruitment phase, in the order
## given with that faction's recruits, from the same gold (TurnResolver.price_recruits). One fort at a time
## per faction. The issuing faction is the key it is filed under in orders_by_faction (see TurnResolver).
## Saved as {"type": "fortify", "province": province id}.

const TYPE := "fortify"

var province: String  # the province id to fortify

func _init(p_province: String = "") -> void:
	province = p_province

func to_dict() -> Dictionary:
	return {"type": TYPE, "province": province}

func describe() -> String:
	return "fortify %s" % province
