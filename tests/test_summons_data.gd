extends "res://tests/test_case.gd"
## CW-0 (#251, design/CANDLEWAKE.md §1.2): summons from data. Call the Pack's sized, per-body price was code that asked
## whether a spell summons "thornwolves"; now a summon row in MagicData.SUMMONS says it is a pack ("pack": the word for one
## body and for many), and the rules and screens read that, so a later faction's pack (CW-5) needs a row, not code. Every word
## the Clans see is the same as before (test_rituals, test_magic_rules and test_ritual_screens pin the sentences).

const CROWN := "kingdom"
const CLANS := "beasts"
const FILES := ["res://rules/magic_rules.gd", "res://ui/orders_controller.gd", "res://ui/magic_view.gd"]


func test_the_pack_is_in_the_summon_rows() -> void:
	var pack: Dictionary = MagicData.SUMMONS.thornwolves.get("pack", {})
	assert_eq(pack, {"one": "wolf", "many": "wolves"}, "the Thornwolves are a pack: a wolf, wolves")
	assert_false(MagicData.SUMMONS.greenwrath.has("pack"), "the Greenwrath is one creature")
	assert_true(MagicRules.is_pack("call_the_pack"))
	for sid in MagicData.SPELLS:
		if String(MagicData.SPELLS[sid].get("summon", "")) != "thornwolves":
			assert_false(MagicRules.is_pack(String(sid)), "%s is not a pack" % sid)


func test_no_rule_or_screen_names_the_thornwolves_any_more() -> void:
	for path in FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("== \"thornwolves\""), "%s reads the pack from the data" % path)


func test_the_price_and_the_sizes_come_from_the_rows() -> void:
	var s := GameState.with_magic(11, {CLANS: "clan_moot"})
	var sp := MagicRules.spell_data("call_the_pack")
	var pack: Dictionary = MagicData.SUMMONS[String(sp.summon)].pack
	var army := s.find_army("beasts-1")
	var sizes := MagicRules.pack_sizes(s, CLANS, army)
	assert_eq(int(sizes[0]), int(sp.count), "the least pack is the spell's count")
	assert_eq(int(sizes[1]), int(MagicRules.spell_numbers("call_the_pack", MagicRules.army_bonus(s, CLANS, army, String(sp.school))).count),
		"the most is the count with the army's mastery")
	for n in [int(sp.count), int(sp.count) + 1]:
		var price := MagicRules.price(s, CLANS, "call_the_pack", n)
		assert_eq(int(price.gold), int(sp.cost) * n, "%d bodies at the spell's cost each" % n)
		assert_eq(String(price.parts[0].label), "%d %s" % [n, MagicData.SUMMONS[String(sp.summon)].name])
		assert_eq(String(price.parts[0].note), "%d gold a %s" % [int(sp.cost), pack.one])
	assert_eq(MagicRules.price_words("call_the_pack"), "%d gold a %s" % [int(sp.cost), pack.one])
	var green := MagicRules.spell_data("wake_the_greenwrath")
	assert_eq(MagicRules.price_words("wake_the_greenwrath"), "%d gold" % int(green.cost), "one creature, one price")
	assert_eq(int(MagicRules.price(s, CLANS, "wake_the_greenwrath").gold), int(green.cost))
