class_name SacrificeOrder
## Order (M2 "the ruler", design/M2_RULER.md §2.4): the faction's living ruler gives up kept power for a
## new mandate, at the mandate's price plus MandateData.SACRIFICE_PREMIUM. At most one per turn. It
## resolves in the sacrifice phase, first in the turn, before any other order is checked, so the new
## mandate already counts in that turn's moves, battles, recruits and income. The rule is
## RulerRules.sacrifice_check and the effect RulerRules.apply_sacrifice; OrderBook checks the faction's
## other orders as if it had already happened (RulerRules.state_after_orders).
## The issuing faction is the key it is filed under in orders_by_faction (see TurnResolver).
## Saved as {"type": "sacrifice", "mandate": mandate id}.

const TYPE := "sacrifice"

var mandate_id: String  # the MandateData id the ruler sacrifices for

func _init(p_mandate_id: String = "") -> void:
	mandate_id = p_mandate_id

func to_dict() -> Dictionary:
	return {"type": TYPE, "mandate": mandate_id}

func describe() -> String:
	return "sacrifice for %s" % mandate_id
