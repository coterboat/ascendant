class_name MoveOrder
## Order: move one army to an adjacent province. Takes effect in the movement phase.
## The issuing faction is the key it is filed under in orders_by_faction (see TurnResolver).
## King's Roads (M2, design/M2_RULER.md §2.3): an order may name a `via` province. That makes it a
## road move, from the army's province through `via` to `to`, two provinces in one turn inside your
## own land (TurnResolver.check_move has the rule). Without `via` it is the M1 one-step move, and it
## saves exactly as before.

var army_id: String
var to: String  # destination province id
var via: String  # road moves only: the province it goes through ("" for a one-step move)

func _init(p_army_id: String = "", p_to: String = "", p_via: String = "") -> void:
	army_id = p_army_id
	to = p_to
	via = p_via

func is_road_move() -> bool:
	return not via.is_empty()

func to_dict() -> Dictionary:
	var d := {"type": "move", "army": army_id, "to": to}
	if not via.is_empty():
		d["via"] = via  # only road moves carry the key, so M1 records stay byte-identical
	return d

func describe() -> String:
	if via.is_empty():
		return "move army %s to %s" % [army_id, to]
	return "move army %s to %s via %s" % [army_id, to, via]
