extends "res://tests/test_case.gd"
## M5-6 (#117) acceptance, Tithe of Blood's payments in the rituals phase (design/M5_MAGIC_FOG.md §7.1): one soldier at
## a time, never below 1, only the caster's army, never a ruler, half when turned aside, illegal when short; the
## forecast names the soldiers who bleed, and the turn report says who gave what. Numbers come from the data.

const CROWN := "kingdom"
const CLANS := "beasts"


## A magic game with the Clans as the Ninth Fang holding Tithe of Blood, 200 gold each, Bloodrot and Call the Pack known.
func _game() -> GameState:
	var s := GameState.with_magic(7, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	assert_true(s != null, "the game starts")
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	s = AscensionRules.with_nodes(s, CROWN, ["shield_of_law", "sanctum_ward"])
	for f in s.factions:
		f.gold = 200
	return s


func _army(s: GameState, fid: String, at: String, types: Array) -> Army:
	var f := s.find_faction(fid)
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	for t in types:
		a.units.append(Unit.new(TurnResolver.recruitable_type(f, String(t), s), fid))
	s.armies.append(a)
	return a


func _resolve(s: GameState, orders: Dictionary) -> Dictionary:
	var r := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state != null, "the turn resolves: %s" % [r.get("errors", [])])
	var errors := []
	assert_true(r.new_state.validate(errors), "valid after the turn: %s" % [errors])
	return r


func _of(r: Dictionary, type: String) -> Array:
	return r.events.filter(func(e): return String(e.type) == type)


func _hps(a: Army) -> Array:
	return a.units.map(func(u): return u.current_hp)


## The price written out (§7.1): `amount` hit points from the regular units, one soldier at a time: the one with the most
## left gives until it is at 1, then the next; ties go in army order.
func _bleed(hps: Array, amount: int) -> Array:
	var out := hps.duplicate()
	var left := amount
	while left > 0:
		var pick := -1
		for k in out.size():
			if int(out[k]) > 1 and (pick < 0 or int(out[k]) > int(out[pick])):
				pick = k
		if pick < 0:
			break
		var give := mini(left, int(out[pick]) - 1)
		out[pick] = int(out[pick]) - give
		left -= give
	return out


func _cost(ritual: String, size: int = 0) -> int:
	return int(MagicRules.price(GameState.with_magic(1), CLANS, ritual, size).gold)


func test_the_pack_paid_in_blood_takes_one_soldier_at_a_time_never_below_1() -> void:
	var s := _game()
	var garrison := _army(s, CLANS, "thornvale", ["shamans", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers"])
	var gold := s.find_faction(CLANS).gold
	var price := _cost("call_the_pack", 3)
	var hp_price := price * MagicData.BLOOD_PER_GOLD
	var before := _hps(garrison)
	var order := CastOrder.new("call_the_pack", garrison.id, "thornvale", CastOrder.BLOOD, 3)
	var f := MagicRules.forecast_ritual(s, CLANS, order, [order])
	assert_true(bool(f.ok), String(f.get("reason", "")))
	var r := _resolve(s, {CLANS: [order]})
	var after := _hps(r.new_state.find_army(garrison.id))
	assert_eq(after, _bleed(before, hp_price), "the soldier with the most left gives down to 1, then the next")
	# §7.1's example: 15 hp from Tuskers at 14: the first gives 13 (to 1), the next 2 (to 12). Shamans have fewer.
	var tusker := int(RulerRules.unit_stats(s, CLANS, "tuskers").hp)
	if tusker == 14 and hp_price == 15:
		assert_eq(after.slice(1, 3), [1, 12], "§7.1's example")
	for hp in after:
		assert_true(int(hp) >= 1, "never below 1")
	var wounded := 0
	for k in after.size():
		if int(after[k]) < int(before[k]):
			wounded += 1
	assert_eq(wounded, f.effect.gives.size(), "as few soldiers as the price needs")
	assert_eq(f.effect.gives, _of(r, "blood_paid")[0].numbers.gives, "the forecast names who bleeds")
	assert_true(String(f.text).contains("Paid in blood"), f.text)
	assert_true(String(f.text).contains("%d hit points" % hp_price) or String(f.text).contains("%d hp" % hp_price), f.text)
	assert_true(String(f.text).contains("Berserk"), "the side effect on the wounded Tuskers: %s" % f.text)
	var paid: Dictionary = _of(r, "blood_paid")[0]
	assert_eq(int(paid.numbers.hp), hp_price)
	assert_eq(String(paid.factions[0]), CLANS)
	assert_eq(r.new_state.find_faction(CLANS).gold, TurnResolver.resolve(s, {}, TurnResolver.seed_for_turn(s)).new_state.find_faction(CLANS).gold,
		"no gold spent")
	assert_true(gold > 0)
	var cast: Dictionary = _of(r, "ritual_cast")[0]
	assert_eq([int(cast.numbers.gold), int(cast.numbers.hp), String(cast.numbers.pay)], [0, hp_price, CastOrder.BLOOD])


func test_only_the_casters_army_bleeds() -> void:
	var s := _game()
	var caster := _army(s, CLANS, "thornvale", ["shamans", "tuskers", "tuskers"])
	var bystanders := _army(s, CLANS, "thornvale", ["tuskers", "tuskers"])
	var field_before := s.find_army("beasts-1").units.map(func(u): return u.current_hp)
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", caster.id, "crownkeep", CastOrder.BLOOD)]})
	assert_eq(_hps(r.new_state.find_army(bystanders.id)), _hps(bystanders), "another army in the same province gives nothing")
	assert_eq(r.new_state.find_army("beasts-1").units.map(func(u): return u.current_hp), field_before)
	assert_eq(_hps(r.new_state.find_army(caster.id)), _bleed(_hps(caster), _cost("bloodrot") * MagicData.BLOOD_PER_GOLD))


func test_a_ruler_never_pays_in_blood() -> void:
	var s := _game()
	var fang := RulerRules.ruler_army(s, CLANS)
	fang.location = "thornvale"
	var check := OrderBook.check_order(s, CLANS, CastOrder.new("bloodrot", fang.id, "crownkeep", CastOrder.BLOOD), [])
	assert_eq(String(check.get("code", "")), "ruler_pays_gold")
	# Even when it shares a province with soldiers: they are another army.
	_army(s, CLANS, "thornvale", ["tuskers", "tuskers"])
	assert_eq(String(OrderBook.check_order(s, CLANS, CastOrder.new("bloodrot", fang.id, "crownkeep", CastOrder.BLOOD), []).get("code", "")),
		"ruler_pays_gold")
	# In gold, the Fang may cast it.
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", fang.id, "crownkeep")]})
	assert_eq(int(_of(r, "ritual_cast")[0].numbers.gold), _cost("bloodrot"))
	assert_eq(_of(r, "blood_paid"), [])


func test_turned_aside_it_takes_half_the_blood() -> void:
	var s := _game()
	var caster := _army(s, CLANS, "thornvale", ["shamans", "tuskers", "tuskers"])
	var adepts := _army(s, CROWN, "crownkeep", ["adepts"])
	var half := floori(float(_cost("bloodrot") * MagicData.BLOOD_PER_GOLD) / MagicData.TURNED_ASIDE)
	var r := _resolve(s, {CROWN: [CastOrder.new("sanctum_ward", adepts.id, "crownkeep")],
		CLANS: [CastOrder.new("bloodrot", caster.id, "crownkeep", CastOrder.BLOOD)]})
	var aside: Dictionary = _of(r, "ritual_turned_aside")[0]
	assert_eq([int(aside.numbers.hp), int(aside.numbers.gold)], [half, 0])
	assert_eq(_hps(r.new_state.find_army(caster.id)), _bleed(_hps(caster), half))
	assert_eq(int(_of(r, "blood_paid")[0].numbers.hp), half)
	assert_true(String(aside.text).contains("%d hit points" % half), aside.text)


func test_short_of_blood_the_cast_is_illegal() -> void:
	var s := _game()
	var thin := _army(s, CLANS, "thornvale", ["shamans", "fangthrowers"])
	for u in thin.units:
		u.current_hp = 3
	var available := 0
	for u in thin.units:
		available += u.current_hp - 1
	assert_true(available < _cost("bloodrot") * MagicData.BLOOD_PER_GOLD)
	var check := OrderBook.check_order(s, CLANS, CastOrder.new("bloodrot", thin.id, "crownkeep", CastOrder.BLOOD), [])
	assert_eq(String(check.get("code", "")), "short_of_blood")
	assert_true(String(check.reason).contains("can give only %d" % available), check.reason)
	var f := MagicRules.forecast_ritual(s, CLANS, CastOrder.new("bloodrot", thin.id, "crownkeep", CastOrder.BLOOD), [])
	assert_false(bool(f.ok))
	# In the resolver it is rejected in the orders phase, nothing paid, and the army is not pinned.
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", thin.id, "crownkeep", CastOrder.BLOOD)]})
	assert_eq(_of(r, "ritual_cast"), [])
	assert_eq(_hps(r.new_state.find_army(thin.id)), [3, 3])
	assert_eq(_of(r, "order_rejected").map(func(e): return String(e.cause)), ["short_of_blood"])


func test_a_shaman_that_would_bleed_below_three_is_named_in_the_forecast() -> void:
	var s := _game()
	var lone := _army(s, CLANS, "thornvale", ["shamans", "shamans"])
	var order := CastOrder.new("far_sight", lone.id, "crownkeep", CastOrder.BLOOD)
	var f := MagicRules.forecast_ritual(s, CLANS, order, [order])
	assert_true(bool(f.ok), String(f.get("reason", "")))
	var min_hp := int(MagicData.SPELLS.bloodbolt.min_caster_hp)
	if f.effect.gives.any(func(g): return int(g.to) < min_hp):
		assert_true(String(f.text).contains("can't cast Bloodbolt below %d" % min_hp), f.text)
