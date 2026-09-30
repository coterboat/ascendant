class_name MoveOrder
## Order: move one army to an adjacent province. Takes effect in the movement phase.
## The issuing faction is the key it is filed under in orders_by_faction (see TurnResolver).

var army_id: String
var to: String  # destination province id

func _init(p_army_id: String = "", p_to: String = "") -> void:
	army_id = p_army_id
	to = p_to

func to_dict() -> Dictionary:
	return {"type": "move", "army": army_id, "to": to}

func describe() -> String:
	return "move army %s to %s" % [army_id, to]
