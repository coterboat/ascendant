class_name SpellbookOrder
## Order (M5 magic, design/M5_MAGIC_FOG.md §5.1): the faction's battle doctrine, its spellbook. `order` lists
## every battle spell of its schools in the order its casters try them; `off` the ones switched off. At most one
## per turn; it applies in the orders phase, so this turn's battles already use it, and it stays in
## Faction.spellbook until changed. Checked by MagicRules.check_spellbook. Preparation, not micromanagement: no
## choices are made inside a battle. The issuing faction is the key it is filed under in orders_by_faction.
## Saved as {"type": "spellbook", "order": [spell ids], "off": [spell ids]}.

const TYPE := "spellbook"

var order: Array  # spell ids, every battle spell of the faction's schools once
var off: Array  # spell ids switched off (each one in `order`)


func _init(p_order: Array = [], p_off: Array = []) -> void:
	order = Serial.to_string_array(p_order)
	off = Serial.to_string_array(p_off)


func to_dict() -> Dictionary:
	return {"type": TYPE, "order": order.duplicate(), "off": off.duplicate()}


func describe() -> String:
	return "spellbook %s (off: %s)" % [", ".join(order), ", ".join(off)]
