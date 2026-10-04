class_name SiegeOrder
## Order (M3c "forts and sieges", design/M3C_SIEGES.md §3.4-§3.6): only in a game with sieges.
##   storm   every army of yours at an enemy fort after movement attacks its garrison, which defends with its
##           walls. One per fort per faction per turn; it may come from the march (a move into the fort this
##           turn). Saved as {"type": "siege", "action": "storm", "province": id}.
##   sally   one army of yours inside your own besieged fort comes out and fights everyone outside the walls,
##           in the open. One per army. A sally tied to a relief army (`with_army`, saved as "with") happens
##           only if that relief army stands outside the walls when the battles start. Saved as
##           {"type": "siege", "action": "sally", "army": id} plus "with": relief army id for a tied sally.
## Siege orders are checked after every move order of that faction (SiegeRules.check_siege_order), so their
## place in the list doesn't matter. The issuing faction is the key it is filed under in orders_by_faction.

const TYPE := "siege"
const STORM := "storm"
const SALLY := "sally"

var action: String  # STORM or SALLY
var province: String  # a storm's fort
var army_id: String  # a sally's army
var with_army: String  # a tied sally's relief army ("" for a sally of its own)

func _init(p_action: String = "", p_target: String = "", p_with: String = "") -> void:
	action = p_action
	province = p_target if p_action == STORM else ""
	army_id = p_target if p_action != STORM else ""
	with_army = p_with

## A storm of the fort at `province_id`.
static func storm(province_id: String) -> SiegeOrder:
	return SiegeOrder.new(STORM, province_id)

## A sally by `army`, tied to the relief army `relief` when it is given.
static func sally(army: String, relief: String = "") -> SiegeOrder:
	return SiegeOrder.new(SALLY, army, relief)

func is_storm() -> bool:
	return action == STORM

func is_sally() -> bool:
	return action == SALLY

func to_dict() -> Dictionary:
	if action == STORM:
		return {"type": TYPE, "action": action, "province": province}
	var d := {"type": TYPE, "action": action, "army": army_id}
	if not with_army.is_empty():
		d["with"] = with_army
	return d

func describe() -> String:
	if action == STORM:
		return "storm %s" % province
	return "sally with %s%s" % [army_id, "" if with_army.is_empty() else " beside %s" % with_army]
