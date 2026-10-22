extends "res://tests/test_case.gd"
## CW-5's hand-off to the board (#256): SpellPlan reads the Candlewake's spells (MagicRules.spell_data), so their casts draw their
## own beats in their own colours: the Wick lilac, Wax honey (SCHOOL_COLOURS), Kindle's flame (cast:flame), Draw the Warmth's bolt
## and Wax Skin's shield in battle. The Crown's and the Clans' effects keep their looks.

const SpellPlan := preload("res://world3d/spell_plan.gd")


func _cols(plan) -> Array:
	return Array(plan.elements).map(func(e): return Color(e.col.r, e.col.g, e.col.b))


func test_every_candlewake_ritual_has_its_board_beat_and_colours() -> void:
	for id in MagicData.PREVIEW_SPELLS:
		var sp: Dictionary = MagicData.PREVIEW_SPELLS[id]
		assert_eq(SpellPlan.school_of(id), String(sp.school), "%s reads its school" % id)
		assert_true(SpellPlan.SCHOOL_COLOURS.has(String(sp.school)), "%s's school has its colours" % id)
		if bool(sp.battle):
			continue
		assert_eq(SpellPlan.rkind_of(id), String(sp.kind), "%s reads its kind" % id)
		var key: Variant = SpellPlan.board_key({"kind": "ritual_cast", "rkind": SpellPlan.rkind_of(id)})
		assert_true(SpellPlan.BOARD_KEYS.has(key), "%s casts with %s" % [id, key])
		for rung in [0, 2, 4]:
			var plan: Variant = SpellPlan.board(key, rung, {"school": SpellPlan.school_of(id), "at": Vector3(10, 0, 10), "r": 30.0,
				"from": Vector3.ZERO})
			assert_false(Array(plan.elements).is_empty(), "%s draws something on rung %d" % [id, rung])
	# Kindle's beat is the Wick's lilac flame, not a ward's band.
	var kindle: Variant = SpellPlan.board("cast:flame", 0, {"school": "wick", "at": Vector3(10, 0, 10), "r": 30.0})
	assert_true(_cols(kindle).has(SpellPlan.WICK), "Kindle draws in the Wick's lilac")
	assert_false(Array(kindle.elements).any(func(e): return String(e.k) == "band"), "never a ward's band")


func test_draw_the_warmth_and_wax_skin_play_in_their_own_colours() -> void:
	assert_eq(SpellPlan.effect_of("bolt", "draw_the_warmth"), "draw_the_warmth")
	assert_eq(SpellPlan.effect_of("shield", "wax_skin"), "wax_skin")
	var caster := {"foot": Vector3.ZERO, "head": Vector3.UP * 4.0}
	var target := {"foot": Vector3(8, 0, 0), "head": Vector3(8, 4, 0)}
	for rung in [0, 2, 4]:
		var bolt: Variant = SpellPlan.battle("draw_the_warmth", rung, {"caster": caster, "target": target, "damage": 3, "self": 0})
		assert_false(Array(bolt.elements).is_empty(), "Draw the Warmth on rung %d" % rung)
		assert_false(_cols(bolt).has(SpellPlan.GILT), "no Sun gold on rung %d" % rung)
		var shield: Variant = SpellPlan.battle("wax_skin", rung, {"caster": caster, "targets": [target], "life": 2.0, "name": "Wax Skin",
			"part": {"stat": "defense", "value": 4}})
		assert_false(Array(shield.elements).is_empty(), "Wax Skin on rung %d" % rung)
		assert_false(_cols(shield).has(SpellPlan.LAW), "no Law blue on rung %d" % rung)
	assert_true(_cols(SpellPlan.battle("wax_skin", 0, {"caster": caster, "targets": [target], "life": 2.0})).has(SpellPlan.WAX))


func test_the_crowns_and_the_clans_effects_keep_their_looks() -> void:
	assert_eq(SpellPlan.effect_of("bolt", "sunlance"), "sunlance")
	assert_eq(SpellPlan.effect_of("shield", "shield_of_law"), "shield_of_law")
	assert_eq(SpellPlan.school_of("bloodrot"), "blood")
	assert_eq(SpellPlan.rkind_of("call_the_pack"), "summon")
	var caster := {"foot": Vector3.ZERO, "head": Vector3.UP * 4.0}
	var target := {"foot": Vector3(8, 0, 0), "head": Vector3(8, 4, 0)}
	assert_true(_cols(SpellPlan.battle("shield_of_law", 0, {"caster": caster, "targets": [target], "life": 2.0})).has(SpellPlan.LAW),
		"Shield of Law stays Law blue")
	var pack: Variant = SpellPlan.board("summoned", 0, {"school": "wild", "at": Vector3(10, 0, 10), "r": 30.0})
	assert_true(_cols(pack).has(SpellPlan.WILD), "the pack's ring stays Wild green")
	var dawn: Variant = SpellPlan.board("cast:blessing", 0, {"school": "sun", "at": Vector3(10, 0, 10), "r": 30.0})
	assert_true(_cols(dawn).has(SpellPlan.GILT), "Dawn Blessing stays gilt")
