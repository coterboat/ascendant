extends "res://tests/test_case.gd"
## The computer buys the Clans' path units when they are the better buy (#94). Briarwardens (Rooted) and
## Bloodsworn (Lifedrinker) are valued with the battle rules' own constants: Rooted battle by battle (a forest
## battle or an open one, weighted by the forest share of the front), Lifedrinker with the rules' rounding, from
## the first round for a recruit that arrives wounded, and in full (healing lands before morale is checked).
## "Better buy" is derived here from the unit data through AIPlayer._side_summary and _trait_power at equal gold
## (gain per gold of price), never from typed-in stats.

const SIDES := {"thorn_wild": ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "beasts_thorn_wild"],
	"blood_pact": ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"]}
const CROWN := {"celestial_host": ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"],
	"living_iron": ["crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"]}


## A state with paths where the Clans swore `side` and the Crown `crown_side` (both transformed), the Clans'
## `garrison` (unit ids, a Warchief first) in Fangridge and the Crown's `foes` in Crownkeep, far from it.
## `frenzy`: the Clans' ruler has sacrificed for Blood Frenzy (+attack below full hp: every Blood Levy recruit).
func _state(side: String, crown_side: String, garrison: Array, foes: Array, frenzy: bool = false) -> GameState:
	var s := GameState.with_paths(99, {}, [])
	s = AscensionRules.with_nodes(s, "kingdom", CROWN[crown_side], 0)
	s = AscensionRules.with_nodes(s, "beasts", SIDES[side], 0)
	if frenzy:
		assert_true(RulerRules.sacrifice_check(s, "beasts", RulerRules.BLOOD_FRENZY).is_empty(), "Blood Frenzy can be bought")
		s = RulerRules.with_sacrifice(s, "beasts", RulerRules.BLOOD_FRENZY)
	var rulers := s.armies.filter(func(a): return a.ruler != null)
	s.armies.clear()
	s.armies.append_array(rulers)
	for spec in [["beasts-9", "beasts", "fangridge", garrison], ["kingdom-9", "kingdom", "crownkeep", foes]]:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			var u := Unit.new(ut, f.id)
			if ut.is_commander:
				a.commander = u
			else:
				u.current_hp = AscensionRules.arrival_hp(s, f.id, ut, RulerRules.unit_max_hp(s, u))
				a.units.append(u)
		s.armies.append(a)
	return s


## The brain's view of `s` for the Clans, with the front's forest share set to `share`.
func _brain(s: GameState, share: float) -> AIPlayer:
	var ai := AIPlayer.new()
	ai._begin(s, "beasts", SeededRNG.new(1), "normal")
	ai._ctx["forest_share"] = share
	return ai


## Our side's worth against `foes`, from _side_summary and _trait_power alone: a forest battle and an open one,
## weighted by the forest share when Rooted is on the field (else the one summary).
func _worth(ctx: Dictionary, units: Array, foes: Array) -> float:
	var share := float(ctx.get("forest_share", 0.0))
	var rooted := (units + foes).any(func(u): return u.type.trait_id == AutoBattleResolver.ROOTED)
	if not rooted or share <= 0.0 or share >= 1.0:
		return AIPlayer._value_of(AIPlayer._side_summary(units, ctx), AIPlayer._side_summary(foes, ctx))
	var forest := ctx.duplicate()
	forest["forest_share"] = 1.0
	var open := ctx.duplicate()
	open["forest_share"] = 0.0
	return share * AIPlayer._value_of(AIPlayer._side_summary(units, forest), AIPlayer._side_summary(foes, forest)) \
		+ (1.0 - share) * AIPlayer._value_of(AIPlayer._side_summary(units, open), AIPlayer._side_summary(foes, open))


## A recruit of `ut` as it arrives (Blood Levy's share missing), from the rules.
func _arrival(s: GameState, ut: UnitType) -> Unit:
	var u := Unit.new(ut, "beasts")
	u.current_hp = AscensionRules.arrival_hp(s, "beasts", ut, RulerRules.unit_max_hp(s, u))
	return u


## The Clans' better buy for the garrison in Fangridge: the regular unit whose recruit adds the most worth per
## gold of its price (equal gold), derived from the data.
func _better_buy(s: GameState, ai: AIPlayer) -> String:
	var clans := s.find_faction("beasts")
	var base := ai._units(ai._mine_at("fangridge"))
	var foes := ai._units(ai._foes)
	var v0 := _worth(ai._ctx, base, foes)
	var best := ""
	var best_gain := 0.0
	for ut in clans.unit_types:  # roster order breaks a tie, within the planner's margin of 0.000001
		var price := RulerRules.recruit_price(s, "beasts", ut)
		var gain := (_worth(ai._ctx, base + [_arrival(s, ut)], foes) - v0) / float(price)
		if gain > best_gain + 0.000001:
			best = ut.id
			best_gain = gain
	return best


func _many(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


# --- the traits, valued with the rules' constants ----------------------------------------------------

func test_rooted_is_worth_a_forest_battle_or_an_open_one_by_the_forest_share() -> void:
	var s := _state("thorn_wild", "celestial_host", ["warchief"] + _many("briarwardens", 4) + _many("tuskers", 2), _many("knights", 5) + ["knight_captain"])
	for share in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var ai := _brain(s, share)
		var ours := ai._units(ai._mine_at("fangridge"))
		var foes := ai._units(ai._foes)
		var forest := ai._ctx.duplicate()
		forest["forest_share"] = 1.0
		var open := ai._ctx.duplicate()
		open["forest_share"] = 0.0
		var want: float = share * AIPlayer._value_of(AIPlayer._side_summary(ours, forest), AIPlayer._side_summary(foes, forest)) \
			+ (1.0 - share) * AIPlayer._value_of(AIPlayer._side_summary(ours, open), AIPlayer._side_summary(foes, open))
		assert_true(absf(ai._recruit_value(ours, foes) - want) < 0.000001, "share %.2f: %f vs %f" % [share, ai._recruit_value(ours, foes), want])
	# The forest battle is the one where ROOTED_DEFENSE counts.
	var f := _brain(s, 1.0)
	var o := _brain(s, 0.0)
	var wardens := f._units(f._mine_at("fangridge")).filter(func(u): return u.type.trait_id == AutoBattleResolver.ROOTED)
	assert_eq(AIPlayer._side_summary(wardens, f._ctx).def_hp - AIPlayer._side_summary(wardens, o._ctx).def_hp,
		float(wardens.reduce(func(acc, u): return acc + u.current_hp, 0)) * AutoBattleResolver.ROOTED_DEFENSE)


## #131: _recruit_value sums the foe side once per recruit plan (_foe_summary) instead of for every unit it tries.
## The cached worth is the uncached one, a different foe list is summed afresh, and nothing outlives a plan.
func test_the_foe_summary_is_cached_within_one_plan() -> void:
	var s := _state("thorn_wild", "celestial_host", ["warchief"] + _many("briarwardens", 4) + _many("tuskers", 2), _many("knights", 5) + ["knight_captain"])
	var ai := _brain(s, 0.5)
	var ours := ai._units(ai._mine_at("fangridge"))
	var foes := ai._units(ai._foes)
	var want := _worth(ai._ctx, ours, foes)
	assert_true(absf(ai._recruit_value(ours, foes) - want) < 0.000001, "first call")
	assert_true(is_same(ai._foe_cache.get("foes"), foes), "the foe list is cached")
	assert_true(ai._foe_cache.has("forest") and ai._foe_cache.has("open"), "a forest and an open summary (Rooted, share 0.5)")
	var forest: Dictionary = ai._foe_cache.forest
	assert_true(absf(ai._recruit_value(ours + [ours[1]], foes) - _worth(ai._ctx, ours + [ours[1]], foes)) < 0.000001, "a trial recruit")
	assert_true(is_same(ai._foe_cache.forest, forest), "the trial reuses the foe summary")
	var fewer: Array = foes.slice(1)
	assert_true(absf(ai._recruit_value(ours, fewer) - _worth(ai._ctx, ours, fewer)) < 0.000001, "another foe list is summed afresh")
	assert_true(is_same(ai._foe_cache.get("foes"), fewer))
	ai._begin(s, "beasts", SeededRNG.new(1), "normal")
	assert_eq(ai._foe_cache, {}, "a new plan starts empty")
	ai.plan_orders(s, "beasts", SeededRNG.new(1), "normal")
	assert_eq(ai._foe_cache, {}, "a plan leaves nothing behind")


func test_lifedrinker_heals_with_the_rules_rounding_and_counts_in_full() -> void:
	var s := _state("blood_pact", "celestial_host", ["warchief", "bloodsworn"], _many("knights", 4))
	var ai := _brain(s, 0.0)
	var sworn: UnitType = TurnResolver.recruitable_type(s.find_faction("beasts"), "bloodsworn")
	var knights := ai._units(ai._foes)
	var foe := AIPlayer._side_summary(knights, ai._ctx)
	var foe_def := roundi(AIPlayer._summary_defense(foe))
	var stats: Dictionary = ai._ctx.stats["beasts|bloodsworn"]
	var max_hp := int(stats.hp)
	var hit := AIPlayer._hit_rate(float(stats.attack), float(foe_def))
	var per_hit := AutoBattleResolver.damage(int(stats.attack), foe_def)
	var heal := hit * ceilf(float(per_hit) / AutoBattleResolver.LIFEDRINK_DIVISOR)
	# A twin with the same numbers and no trait.
	var twin := UnitType.new()
	for k in ["id", "name", "hp", "attack", "defense", "morale", "cost", "is_commander"]:
		twin.set(k, sworn.get(k))
	twin.id = "twin"
	for wounded in [true, false]:
		var u := Unit.new(sworn, "beasts")
		u.current_hp = max_hp - 1 if wounded else max_hp
		var t := Unit.new(twin, "beasts")
		t.current_hp = u.current_hp
		var ctx: Dictionary = ai._ctx.duplicate(true)
		ctx.stats["beasts|twin"] = stats
		var with_it := AIPlayer._trait_power(AIPlayer._side_summary([u], ctx), foe)
		var without := AIPlayer._trait_power(AIPlayer._side_summary([t], ctx), foe)
		var dmg := hit * per_hit
		var ready := 1.0 if wounded else AIPlayer.LIFEDRINK_SHARE
		assert_true(absf((with_it - without) - heal * ready * AIPlayer.ROUNDS_GUESS * dmg) < 0.0001,
			"%s: the healing over ROUNDS_GUESS rounds counts in full (%f vs %f)" % ["wounded" if wounded else "whole", with_it - without, heal * ready * AIPlayer.ROUNDS_GUESS * dmg])


func test_wounded_units_fight_with_berserk_and_blood_frenzy_from_the_first_blow() -> void:
	# Every Blood Levy recruit arrives wounded, so Berserk and Blood Frenzy are on for it from the first blow:
	# the rough guess and the trait-aware value both count them in full for a unit below its maximum hp.
	var s := _state("blood_pact", "celestial_host", ["warchief", "tuskers"], _many("knights", 4), true)
	var ai := _brain(s, 0.0)
	var frenzy := int(RulerRules.battle_effects(s, "beasts").wounded_attack)
	assert_true(frenzy > 0, "Blood Frenzy gives wounded fighters attack")
	var tusker: Unit = ai._mine_at("fangridge")[0].units[0]
	var max_hp := RulerRules.unit_max_hp(s, tusker)
	assert_true(tusker.current_hp < max_hp, "a Blood Levy recruit arrives wounded")
	assert_eq(ai._wounded_attack(tusker), AutoBattleResolver.BERSERK_ATTACK + frenzy)
	var whole := Unit.new(tusker.type, "beasts")
	whole.current_hp = max_hp
	assert_eq(ai._wounded_attack(whole), 0, "a whole unit gets neither yet")
	var chief := Unit.new(s.find_faction("beasts").commander_type, "beasts")
	chief.current_hp -= 1
	assert_eq(ai._wounded_attack(chief), frenzy, "Blood Frenzy works on every fighter, Berserk only on its own")
	var foe := AIPlayer._side_summary(ai._units(ai._foes), ai._ctx)
	assert_true(AIPlayer._trait_power(AIPlayer._side_summary([tusker], ai._ctx), foe) > AIPlayer._trait_power(AIPlayer._side_summary([whole], ai._ctx), foe) * float(tusker.current_hp) / max_hp,
		"the wounded one hits harder than its hp alone says")
	# Without paths nothing changes: every unit counts Berserk BERSERK_SHARE of the time, as before.
	assert_false(AIPlayer._side_summary([tusker]).wounded_aware)


# --- better buys ------------------------------------------------------------------------------------

func test_the_clans_buy_their_path_units_when_they_are_the_better_buy() -> void:
	var comps := {"knights": _many("knights", 6) + ["knight_captain"], "foot": _many("spearmen", 6) + _many("crossbowmen", 5) + ["knight_captain"],
		"mixed": _many("spearmen", 3) + _many("crossbowmen", 3) + _many("knights", 3) + ["knight_captain"]}
	var path_best := {"thorn_wild": 0, "blood_pact": 0}
	var other_best := {"thorn_wild": 0, "blood_pact": 0}
	var checked := 0
	for side in SIDES:
		var new_unit := String(AscensionRules.node_effects(String(PathData.BRANCHES[side].transformation)).new_unit)
		for crown_side in CROWN:
			var crown_new := String(AscensionRules.node_effects(String(PathData.BRANCHES[crown_side].transformation)).new_unit)
			var foes_by: Dictionary = comps.duplicate()
			foes_by["new"] = _many("spearmen", 3) + _many(crown_new, 3) + ["knight_captain"]
			for cname in foes_by:
				for share in [0.0, 0.5, 1.0]:
					for garrison in [["warchief"], ["warchief", "tuskers", "tuskers", "fangthrowers", "fangthrowers", "war_bear", "war_bear"]]:
						for frenzy in ([false, true] if side == "blood_pact" else [false]):  # the Thorn Wild forswears it
							_check_buy(side, crown_side, cname, share, garrison, foes_by[cname], frenzy, new_unit, path_best, other_best)
							checked += 1
	assert_true(checked > 0)
	for side in SIDES:
		assert_true(path_best[side] > 0, "%s: its new unit is the better buy somewhere (%d positions)" % [side, path_best[side]])
		assert_true(other_best[side] > 0, "%s: and not everywhere (%d positions)" % [side, other_best[side]])


## One position of test_the_clans_buy_their_path_units_when_they_are_the_better_buy.
func _check_buy(side: String, crown_side: String, cname: String, share: float, garrison: Array, foes: Array, frenzy: bool,
		new_unit: String, path_best: Dictionary, other_best: Dictionary) -> void:
	var s := _state(side, crown_side, garrison, foes, frenzy)
	s.find_faction("beasts").gold = 0
	var ai := _brain(s, share)
	var want := _better_buy(s, ai)
	# Enough gold for one of anything: the plan's first regular pick is the better buy.
	var gold := 0
	for ut in s.find_faction("beasts").unit_types:
		gold = maxi(gold, RulerRules.recruit_price(s, "beasts", ut))
	ai._me.gold = gold
	var plan: Array = ai._plan_recruits(ai._mine_at("fangridge")).filter(func(ut): return not ut.is_commander)
	assert_false(plan.is_empty(), "%s vs %s %s: it recruits" % [side, crown_side, cname])
	if plan.is_empty():
		return
	assert_eq(plan[0].id, want, "%s vs %s %s, forest %.1f, garrison of %d, frenzy %s: the better buy first" % [
		side, crown_side, cname, share, garrison.size(), frenzy])
	if want == new_unit:
		path_best[side] += 1
	else:
		other_best[side] += 1
