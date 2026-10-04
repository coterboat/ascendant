class_name ResearchOrder
## Order (M4 "paths of ascension", design/M4_ASCENSION.md §2.2): make one node of your faction's path your
## research target. The target persists from turn to turn until the node is done or you change it, so most
## turns need no research order. At most one per faction per turn: queuing another replaces the queued one
## (OrderBook). Checked in the orders phase against the state after sacrifices (AscensionRules.check_research);
## the research phase, after income, then gains research and completes the target once it is paid for.
## Changing the target moves nothing: the pool simply saves toward the new node. The target is private.
## The issuing faction is the key it is filed under in orders_by_faction (see TurnResolver).
## Saved as {"type": "research", "node": node id}.

const TYPE := "research"

var node_id: String  # the PathData node id to research

func _init(p_node_id: String = "") -> void:
	node_id = p_node_id

func to_dict() -> Dictionary:
	return {"type": TYPE, "node": node_id}

func describe() -> String:
	return "research %s" % node_id
