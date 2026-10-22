class_name CastOrder
## Order (M5 magic, design/M5_MAGIC_FOG.md §6.1): an army casts a ritual. A caster in the army (one of your mages,
## or your ruler if the ritual is in its school) casts it from the province where the army starts the turn, so
## the army holds this turn: queuing a cast drops any move for that army, and a move can't be given to an army
## that casts (the pinned set, MagicRules.pinned_armies). One cast order per army and each ritual once per faction
## per turn. Gold-paid rituals share the turn's gold with recruits (the running budget); under Tithe of Blood a
## Shaman's army may pay in hit points instead (`pay` "blood"). Checked by MagicRules.check_cast; resolved in the
## rituals phase (M5-6). The issuing faction is the key it is filed under in orders_by_faction.
## Saved as {"type": "cast", "ritual", "army", "target", "pay"}, plus "size" for Call the Pack only.
## CW-5 (#256, design/CANDLEWAKE.md §7): a ritual that lands on one army (MagicRules.lands_on_army: Kindle, Candlemass) may name
## it in `target_army`, an army of yours standing in the target province; checked when the order is given and again when it
## resolves (an army no longer fit fails the cast: it never lands on another). Without it the ritual lands on the lowest-numbered
## army of yours there that it fits (a ruler's own army last), chosen when it resolves. Saved as "target_army" only when set, so every other cast saves as before.

const TYPE := "cast"
const GOLD := "gold"
const BLOOD := "blood"

var ritual: String  # a MagicData.SPELLS ritual id (never a battle spell)
var army_id: String  # the army holding the caster
var target: String  # a province id ("" for a ritual with no target, the Blood Moon)
var pay: String  # GOLD or BLOOD
var size: int  # Call the Pack's wolves; 0 for every other ritual
var target_army: String  # CW-5: the army a one-army ritual lands on, or "" for the lowest-numbered it fits


func _init(p_ritual: String = "", p_army_id: String = "", p_target: String = "", p_pay: String = GOLD, p_size: int = 0,
		p_target_army: String = "") -> void:
	ritual = p_ritual
	army_id = p_army_id
	target = p_target
	pay = p_pay
	size = p_size
	target_army = p_target_army


func to_dict() -> Dictionary:
	var d := {"type": TYPE, "ritual": ritual, "army": army_id, "target": target, "pay": pay}
	if size != 0:
		d["size"] = size
	if not target_army.is_empty():
		d["target_army"] = target_army  # CW-5: only a one-army ritual that names its army carries the key
	return d


func describe() -> String:
	return "cast %s from %s on %s" % [ritual, army_id, target]
