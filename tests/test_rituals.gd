extends "res://tests/test_case.gd"
## M5-6 (#117) acceptance, rituals on the map (design/M5_MAGIC_FOG.md §6, §9, §18): the two new phases, every ritual's
## effect and its "through turn" arithmetic, budgets taken and given one hit point at a time in the stated order,
## wards turning rituals aside at half price and ending a curse after one more bite, Far Sight's sight and reading
## (a caster blocks the reading, not the sight), one pack and one Greenwrath at a time, Bastion's cap counting forts
## ever raised, summons holding on arrival and fading on time, blessings following armies and recruits, cursed fighters
## healing from nothing, every forecast equal to its result, rituals under fog and on Free Holds garrisons, and a
## replay through every ritual. Expected numbers come from MagicData, RulerRules and the map, never typed in.

const CROWN := "kingdom"
const CLANS := "beasts"
const Policies := preload("res://tools/autoplay/policies.gd")
const Simulator := preload("res://tools/autoplay/simulator.gd")

## The arcana and path nodes each greater working needs (its school's ritual, its Oath, and the Oath's two ordinary
## nodes): a test faction with one of these lists knows every ritual of that line.
const CROWN_FORGE := ["crown_drillyard", "crown_charters", "crown_oath_forge", "shield_of_law", "sanctum_ward", "bastion",
	"sunlance", "dawn_blessing"]
const CLANS_GROVE := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "briar_snare", "call_the_pack",
	"wake_the_greenwrath", "bloodbolt", "bloodrot"]
const CLANS_BLOOD := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "bloodbolt", "bloodrot", "blood_moon",
	"briar_snare", "call_the_pack"]


# --- helpers ----------------------------------------------------------------------------------------

## A magic game: the Crown as Regent's Court (the Ever-Regent), the Clans as Blood of the Fang (the Ninth Fang) unless
## `builds` says otherwise, with `nodes` researched ({faction id: [node ids]}) and 200 gold each.
func _game(nodes: Dictionary = {}, builds: Dictionary = {}) -> GameState:
	var b := {CROWN: "regents_court", CLANS: "blood_of_the_fang"}
	b.merge(builds, true)
	var s := GameState.with_magic(7, b)
	assert_true(s != null, "the magic game starts")
	for fid in nodes:
		s = AscensionRules.with_nodes(s, fid, nodes[fid])
	for f in s.factions:
		f.gold = 200
	return s


## A new army of `fid` at `at` holding units of these type ids, at full hp.
func _army(s: GameState, fid: String, at: String, types: Array) -> Army:
	var f := s.find_faction(fid)
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	for t in types:
		var ut := TurnResolver.recruitable_type(f, String(t), s)
		assert_true(ut != null, "%s can field %s" % [fid, t])
		a.units.append(Unit.new(ut, fid))
	s.armies.append(a)
	return a


func _field(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid and a.ruler == null:
			return a
	return null


func _ruler(s: GameState, fid: String) -> Army:
	return RulerRules.ruler_army(s, fid)


func _own(s: GameState, fid: String, pids: Array) -> void:
	for pid in pids:
		s.find_province(String(pid)).owner = fid


func _resolve(s: GameState, orders: Dictionary = {}) -> Dictionary:
	var r := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state != null, "the turn resolves: %s" % [r.get("errors", [])])
	if r.new_state != null:
		var errors := []
		assert_true(r.new_state.validate(errors), "the state after the turn is valid: %s" % [errors])
	return r


func _of(r: Dictionary, type: String) -> Array:
	return r.events.filter(func(e): return String(e.type) == type)


func _one(r: Dictionary, type: String) -> Dictionary:
	var found := _of(r, type)
	assert_eq(found.size(), 1, "one %s event: %s" % [type, found.map(func(e): return e.text)])
	return found[0] if not found.is_empty() else {"numbers": {}, "text": "", "factions": [], "provinces": [], "phase": ""}


func _rejections(r: Dictionary) -> Array:
	return _of(r, "order_rejected").map(func(e): return "%s: %s" % [e.cause, e.text])


## Every fighter of an army in fighter order: its units, then the commander, then the ruler.
func _fighters(a: Army) -> Array:
	var out: Array = a.units.duplicate()
	if a.commander != null:
		out.append(a.commander)
	if a.ruler != null:
		out.append(a.ruler)
	return out


func _hps(fighters: Array) -> Array:
	return fighters.map(func(u): return u.current_hp)


## The rule written out (§6.2): `budget` hit points taken one at a time from the fighter with the most left (ties: the
## first in order), never below 1.
func _bite(hps: Array, budget: int) -> Array:
	var out := hps.duplicate()
	for _i in budget:
		var pick := -1
		for k in out.size():
			if int(out[k]) > 1 and (pick < 0 or int(out[k]) > int(out[pick])):
				pick = k
		if pick < 0:
			break
		out[pick] = int(out[pick]) - 1
	return out


## The rule written out (§6.2): `budget` hit points given one at a time to the wounded fighter with the fewest left
## (ties: the first in order), never above its maximum.
func _heal(hps: Array, maxes: Array, budget: int) -> Array:
	var out := hps.duplicate()
	for _i in budget:
		var pick := -1
		for k in out.size():
			if int(out[k]) < int(maxes[k]) and (pick < 0 or int(out[k]) < int(out[pick])):
				pick = k
		if pick < 0:
			break
		out[pick] = int(out[pick]) + 1
	return out


func _budget(ritual: String, bonus: int) -> int:
	return int(MagicRules.spell_numbers(ritual, bonus).value)


func _duration(ritual: String, bonus: int) -> int:
	return int(MagicRules.spell_numbers(ritual, bonus).duration)


func _cost(ritual: String) -> int:
	return int(MagicData.SPELLS[ritual].cost)


func _half(gold: int) -> int:
	return floori(float(gold) / MagicData.TURNED_ASIDE)


func _enchantments(s: GameState, ritual: String) -> Array:
	return s.enchantments.filter(func(e): return String(e.ritual) == ritual)


# --- the phases (§9) --------------------------------------------------------------------------------

func test_the_magic_phases_run_only_in_a_magic_game() -> void:
	assert_eq(TurnResolver.MAGIC_PHASES, ["sacrifice", "orders", "rituals", "movement", "battles", "capture", "recruitment",
		"income", "research", "rulers", "enchantments"])
	assert_eq(TurnResolver.phases(GameState.with_magic(4)), TurnResolver.MAGIC_PHASES)
	assert_eq(TurnResolver.phases(GameState.with_paths(4)), TurnResolver.PATH_PHASES, "no magic, no new phase")
	assert_eq(TurnResolver.phases(GameState.new(4)), TurnResolver.PHASES)
	var both := GameState.with_magic(4)
	assert_true(both.setup_sieges([]))
	var with_sieges := TurnResolver.phases(both)
	assert_eq(with_sieges.find("sieges"), with_sieges.find("battles") + 1, "sieges right after battles")
	assert_eq(with_sieges.find("rituals"), with_sieges.find("orders") + 1)
	assert_eq(with_sieges.back(), "enchantments", "the enchantments phase ends the turn")
	assert_eq(GameSession.report_phases(GameState.with_magic(4)), GameSession.MAGIC_REPORT_PHASES)
	# Every event of a magic turn with rituals names one of its game's phases.
	var s := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var shamans := _army(s, CLANS, "thornvale", ["shamans", "tuskers"])
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", shamans.id, "crownkeep")]})
	for e in r.events:
		assert_true(TurnResolver.phases(s).has(String(e.phase)), "%s is in a phase of its game (%s)" % [e.type, e.phase])
	assert_eq(_one(r, "ritual_cast").phase, "rituals")
	assert_eq(_one(r, "curse_bit").phase, "enchantments")


func test_the_rituals_phase_goes_by_kind_then_faction_then_the_order_given() -> void:
	var s := _game({CROWN: CROWN_FORGE, CLANS: CLANS_GROVE})
	_own(s, CROWN, ["highcrag"])
	var adepts := _army(s, CROWN, "crownkeep", ["adepts"])
	var shamans := _army(s, CLANS, "thornvale", ["shamans", "tuskers"])
	var pack := _army(s, CLANS, "fangridge", ["shamans"])
	var orders := {
		CLANS: [CastOrder.new("call_the_pack", pack.id, "fangridge", CastOrder.GOLD, 3), CastOrder.new("bloodrot", shamans.id, "highcrag")],
		CROWN: [CastOrder.new("bastion", _ruler(s, CROWN).id, "highcrag"), CastOrder.new("sanctum_ward", adepts.id, "crownkeep")],
	}
	var r := _resolve(s, orders)
	var cast: Array = _of(r, "ritual_cast").map(func(e): return String(e.numbers.ritual))
	# wards, curses, blessings, summons, raisings, global, sight.
	assert_eq(cast, ["sanctum_ward", "bloodrot", "call_the_pack", "bastion"], "the fixed order of kinds")
	assert_eq(MagicRules.KIND_ORDER, ["ward", "curse", "blessing", "summon", "raising", "global", "sight"])
	var first_ritual := -1
	var first_move := -1
	for i in r.events.size():
		if String(r.events[i].phase) == "rituals" and first_ritual < 0:
			first_ritual = i
		if String(r.events[i].phase) == "movement" and first_move < 0:
			first_move = i
	assert_true(first_ritual >= 0 and (first_move < 0 or first_ritual < first_move), "rituals before movement")


# --- every ritual: its effect and its "through turn" arithmetic (§6.2) ---------------------------------

func test_bloodrot_curses_bites_one_hit_point_at_a_time_and_ends_through_turn_t_plus_2() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var shamans := _army(s, CLANS, "thornvale", ["shamans", "tuskers"])
	_ruler(s, CROWN).location = "rivermarch"  # the Regent away, so nothing heals at Crownkeep
	var crown := _field(s, CROWN)
	var victims := _fighters(crown)
	var t := s.current_turn + 1
	var bonus := int(MagicRules.mastery_bonus(s, CLANS, "blood", MagicRules.MAGE).value)
	var budget := _budget("bloodrot", bonus)
	var until := t + _duration("bloodrot", bonus)
	assert_eq(until, t + 2, "through turn T + 2")
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", shamans.id, "crownkeep")]})
	assert_eq(_rejections(r), [], "the cast is legal")
	var cast := _one(r, "ritual_cast")
	assert_eq(int(cast.numbers.gold), _cost("bloodrot"), "paid its price in gold")
	assert_eq(r.new_state.find_faction(CLANS).gold, TurnResolver.resolve(s, {}, TurnResolver.seed_for_turn(s)).new_state.find_faction(CLANS).gold - _cost("bloodrot"))
	var curse: Array = _enchantments(r.new_state, "bloodrot")
	assert_eq(curse.size(), 1)
	assert_eq([curse[0].kind, curse[0].province, curse[0].faction, int(curse[0].cast_turn), int(curse[0].until_turn), int(curse[0].bonus)],
		["curse", "crownkeep", CLANS, t, until, bonus])
	assert_eq(String(curse[0].id), "%s-e1" % CLANS, "ids count per faction")
	# It first bites after this turn's battles: one hit point at a time from the fighter with the most left.
	var expected := _bite(_hps(victims), budget)
	assert_eq(_hps(_fighters(r.new_state.find_army(crown.id))), expected, "the first bite")
	var bit := _one(r, "curse_bit")
	assert_eq(int(bit.numbers.total), budget)
	assert_eq(String(bit.factions[0]), CROWN, "the bitten faction reads it whole")
	var fell := _one(r, "ritual_fell")
	assert_eq(String(fell.factions[0]), CROWN, "the Crown is told its capital is cursed")
	assert_false(String(fell.text).contains("Thornvale"), "never the caster's province: %s" % fell.text)
	assert_true(String(fell.text).contains("Sanctum Ward"), "how to stop it: %s" % fell.text)
	# Through turn T + 2: it bites at the end of turns T, T + 1 and T + 2, then ends.
	var state: GameState = r.new_state
	for turn in [t + 1, t + 2]:
		var before := _hps(_fighters(state.find_army(crown.id)))
		var next := _resolve(state, {})
		assert_eq(_hps(_fighters(next.new_state.find_army(crown.id))), _bite(before, budget), "the bite of turn %d" % turn)
		state = next.new_state
		if turn < until:
			assert_eq(_enchantments(state, "bloodrot").size(), 1, "still there after turn %d" % turn)
	assert_eq(_enchantments(state, "bloodrot"), [], "ended in turn %d's enchantments phase" % until)
	var after := _resolve(state, {})
	assert_eq(_of(after, "curse_bit"), [], "no bite after it ended")
	# Never below 1: a fighter at 1 gives nothing more.
	var worn := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var ws := _army(worn, CLANS, "thornvale", ["shamans"])
	_ruler(worn, CROWN).location = "rivermarch"
	for u in _fighters(_field(worn, CROWN)):
		u.current_hp = 1
	var wr := _resolve(worn, {CLANS: [CastOrder.new("bloodrot", ws.id, "crownkeep")]})
	assert_eq(_hps(_fighters(wr.new_state.find_army(_field(worn, CROWN).id))), _hps(_fighters(_field(worn, CROWN))), "never below 1")


func test_a_curse_bites_in_the_stated_order() -> void:
	# Two armies of the Crown in the cursed province: armies by id, units in order, then the commander, then the ruler.
	var s := _game()
	var a := _field(s, CROWN)
	var hps := [10, 12, 12]
	a.units.resize(3)
	for k in 3:
		a.units[k].current_hp = hps[k]
	a.commander = null
	s.enchantments = [{"id": "beasts-e1", "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false}]
	s.find_faction(CLANS).enchant_counter = 1
	_ruler(s, CROWN).location = "rivermarch"
	var step := MagicRules.enchantment_step(s, 1)
	assert_eq(_hps(a.units), [7, 7, 8], "12 from 10, 12, 12: the two 12s down to 10 first, then round from the front")
	assert_eq(_hps(a.units), _bite(hps, _budget("bloodrot", 0)))
	assert_eq(step.bit.size(), 1)


func test_dawn_blessing_heals_its_armies_follows_them_and_their_recruits() -> void:
	var s := _game({CROWN: ["sunlance", "dawn_blessing"]})
	_ruler(s, CROWN).location = "rivermarch"  # no Mending Light at Crownkeep, so only the blessing heals
	var field := _field(s, CROWN)
	field.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts", s), CROWN))
	var wounds := [3, 5, 10]
	for k in 3:
		field.units[k].current_hp = wounds[k]
	var other := _army(s, CROWN, "crownkeep", ["spearmen"])
	other.units[0].current_hp = 2
	var t := s.current_turn + 1
	var bonus := int(MagicRules.mastery_bonus(s, CROWN, "sun", MagicRules.MAGE).value)
	var budget := _budget("dawn_blessing", bonus)
	var before := {field.id: _hps(_fighters(field)), other.id: _hps(_fighters(other))}
	var maxes := {}
	for army in [field, other]:
		maxes[army.id] = _fighters(army).map(func(u): return RulerRules.unit_max_hp(s, u))
	var r := _resolve(s, {CROWN: [CastOrder.new("dawn_blessing", field.id, "crownkeep"), RecruitOrder.new("spearmen")]})
	assert_eq(_rejections(r), [])
	var blessing: Array = _enchantments(r.new_state, "dawn_blessing")
	assert_eq(blessing.size(), 1)
	var blessed: Array = blessing[0].armies
	var ids := [field.id, other.id]
	ids.sort()
	assert_eq(blessed, ids, "every army of the Crown there as it resolves")
	assert_eq(int(blessing[0].until_turn), t + _duration("dawn_blessing", bonus))
	assert_eq(int(blessing[0].until_turn), t + 2)
	# The recruit joined the first army at the capital, a blessed one: it is blessed with it.
	var recruit_army := String(_one(r, "recruited").armies[0])
	assert_true(blessed.has(recruit_army), "recruits who join a blessed army are blessed")
	# Each blessed army heals its budget, one hit point at a time to its wounded fighter with the fewest left.
	for army in [field, other]:
		var now := _fighters(r.new_state.find_army(army.id))
		var healed := _heal(before[army.id], maxes[army.id], budget)
		if army == field:
			healed.insert(healed.size() - 1, now[now.size() - 2].current_hp)  # the recruit sits before the commander, at full hp
		assert_eq(_hps(now), healed, "%s healed %d" % [army.id, budget])
	assert_eq(_of(r, "blessing_healed").size(), 2, "one line per blessed army")
	# It follows its armies: the field army marches to Highcrag and heals there.
	var state: GameState = r.new_state
	for u in state.find_army(field.id).units:
		u.current_hp = 1
	var r2 := _resolve(state, {CROWN: [MoveOrder.new(field.id, "highcrag")]})
	assert_eq(r2.new_state.find_army(field.id).location, "highcrag")
	var heal := _of(r2, "blessing_healed").filter(func(e): return String(e.armies[0]) == field.id)
	assert_eq(heal.size(), 1, "healed where it went")
	assert_eq(String(heal[0].provinces[0]), "highcrag")
	# An army that arrives in the province later is not blessed; a new army formed by recruits is not either.
	assert_eq(_enchantments(r2.new_state, "dawn_blessing")[0].armies, ids)


func test_an_army_blessed_again_elsewhere_carries_one_blessing() -> void:
	# One blessing per army (§6.4): the same armies blessed again in another province restart their blessing, so a
	# blessed army never heals twice a turn.
	var s := _game({CROWN: ["sunlance", "dawn_blessing"]})
	_own(s, CROWN, ["highcrag"])
	_ruler(s, CROWN).location = "rivermarch"
	var lone := _army(s, CROWN, "crownkeep", ["adepts", "spearmen"])
	_field(s, CROWN).location = "westwatch"
	_own(s, CROWN, ["westwatch"])
	var r1 := _resolve(s, {CROWN: [CastOrder.new("dawn_blessing", lone.id, "crownkeep"), MoveOrder.new(_field(s, CROWN).id, "crownkeep")]})
	var r2 := _resolve(r1.new_state, {CROWN: [MoveOrder.new(lone.id, "highcrag")]})
	var state: GameState = r2.new_state
	for u in state.find_army(lone.id).units:
		u.current_hp = 1
	var r3 := _resolve(state, {CROWN: [CastOrder.new("dawn_blessing", lone.id, "highcrag")]})
	var holding: Array = r3.new_state.enchantments.filter(func(e): return String(e.kind) == "blessing" and e.armies.has(lone.id))
	assert_eq(holding.size(), 1, "one blessing for the army: %s" % [r3.new_state.enchantments])
	assert_eq(_of(r3, "blessing_healed").filter(func(e): return String(e.armies[0]) == lone.id).size(), 1, "it heals once a turn")


func test_a_destroyed_army_loses_its_blessing_and_an_empty_blessing_ends() -> void:
	var s := _game({CROWN: ["sunlance", "dawn_blessing"]})
	var lone := _army(s, CROWN, "highcrag", ["adepts"])
	_own(s, CROWN, ["highcrag"])
	var r := _resolve(s, {CROWN: [CastOrder.new("dawn_blessing", lone.id, "highcrag")]})
	assert_eq(_enchantments(r.new_state, "dawn_blessing")[0].armies, [lone.id])
	# The blessed army marches into the Clans' great host at Thornvale and is destroyed.
	var state: GameState = r.new_state
	var host := _army(state, CLANS, "thornvale", ["war_bear", "war_bear", "war_bear", "war_bear"])
	state.find_province("thornvale").owner = CLANS
	var r2 := _resolve(state, {CROWN: [MoveOrder.new(lone.id, "thornvale")]})
	assert_eq(r2.new_state.find_army(lone.id), null, "destroyed")
	assert_eq(_enchantments(r2.new_state, "dawn_blessing"), [], "a blessing with no army left ends")
	var ended := _one(r2, "enchantment_ended")
	assert_eq(String(ended.numbers.cause), "no_armies")
	assert_true(host != null)


func test_sanctum_ward_lasts_through_t_plus_1_and_more_with_law_mastery() -> void:
	var s := _game({CROWN: ["shield_of_law", "sanctum_ward"]})
	var adepts := _army(s, CROWN, "crownkeep", ["adepts"])
	var t := s.current_turn + 1
	var r := _resolve(s, {CROWN: [CastOrder.new("sanctum_ward", adepts.id, "crownkeep")]})
	var ward: Array = _enchantments(r.new_state, "sanctum_ward")
	assert_eq([ward[0].kind, ward[0].province, int(ward[0].until_turn)], ["ward", "crownkeep", t + 1], "a mage's ward: through turn T + 1")
	# The Ever-Regent's Law mastery is his ability rank - 1: each point adds a turn.
	var r2 := _resolve(s, {CROWN: [CastOrder.new("sanctum_ward", _ruler(s, CROWN).id, "crownkeep")]})
	var bonus := int(MagicRules.mastery_bonus(s, CROWN, "law", MagicRules.RULER).value)
	assert_true(bonus > 0, "the Regent has Law mastery")
	assert_eq(int(_enchantments(r2.new_state, "sanctum_ward")[0].until_turn), t + 1 + bonus)
	assert_eq(int(_one(r2, "ritual_cast").numbers.gold), _cost("sanctum_ward"))


func test_a_same_turn_ward_turns_a_curse_and_a_far_sight_aside_at_half_price() -> void:
	var s := _game({CROWN: ["shield_of_law", "sanctum_ward"], CLANS: ["bloodbolt", "bloodrot"]})
	s.setup_fog([])
	var rot := _army(s, CLANS, "thornvale", ["shamans", "tuskers"])
	var eye := _army(s, CLANS, "wildmoor", ["shamans"])
	var crown_gold := s.find_faction(CROWN).gold
	var clans_gold := s.find_faction(CLANS).gold
	var plain: GameState = TurnResolver.resolve(s, {}, TurnResolver.seed_for_turn(s)).new_state
	var r := _resolve(s, {
		CLANS: [CastOrder.new("bloodrot", rot.id, "crownkeep"), CastOrder.new("far_sight", eye.id, "crownkeep")],
		CROWN: [CastOrder.new("sanctum_ward", _ruler(s, CROWN).id, "crownkeep")],
	})
	var aside := _of(r, "ritual_turned_aside")
	assert_eq(aside.map(func(e): return String(e.numbers.ritual)), ["bloodrot", "far_sight"], "both turned aside")
	for e in aside:
		assert_eq(int(e.numbers.gold), _half(_cost(String(e.numbers.ritual))), "half its price, rounded down: %s" % e.text)
		assert_eq(String(e.numbers.warder), CROWN)
		assert_eq(String(e.factions[0]), CLANS, "the caster reads it")
	assert_eq(r.new_state.find_faction(CLANS).gold, plain.find_faction(CLANS).gold - _half(_cost("bloodrot")) - _half(_cost("far_sight")))
	assert_eq(r.new_state.find_faction(CROWN).gold, plain.find_faction(CROWN).gold - _cost("sanctum_ward"))
	assert_eq(_enchantments(r.new_state, "bloodrot"), [], "no curse")
	assert_eq(_enchantments(r.new_state, "far_sight"), [], "no sight")
	assert_eq(MagicRules.vision_grants(r.new_state, CLANS), [])
	assert_eq(_of(r, "ritual_fell"), [], "nothing fell")
	assert_true(String(aside[0].text).contains("half its price (%d gold)" % _half(_cost("bloodrot"))), aside[0].text)
	assert_true(crown_gold > 0 and clans_gold > 0)
	# A ward on a province its faction no longer holds protects nothing.
	var lost := _game({CLANS: ["bloodbolt", "bloodrot"]})
	_own(lost, CLANS, ["highcrag"])
	lost.find_faction(CROWN).enchant_counter = 1
	lost.enchantments = [{"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "highcrag",
		"armies": [], "cast_turn": 1, "until_turn": 2, "bonus": 0, "ending": false}]
	assert_eq(MagicRules.ward_on(lost, "highcrag", CLANS), {}, "the Crown's ward there no longer protects anything")


func test_a_ward_ends_an_existing_curse_after_one_more_bite() -> void:
	var s := _game({CROWN: ["shield_of_law", "sanctum_ward"], CLANS: ["bloodbolt", "bloodrot"]})
	var rot := _army(s, CLANS, "thornvale", ["shamans"])
	_ruler(s, CROWN).location = "rivermarch"
	var adepts := _army(s, CROWN, "crownkeep", ["adepts"])
	var t := s.current_turn + 1
	var r1 := _resolve(s, {CLANS: [CastOrder.new("bloodrot", rot.id, "crownkeep")]})
	assert_eq(int(_enchantments(r1.new_state, "bloodrot")[0].until_turn), t + 2)
	var r2 := _resolve(r1.new_state, {CROWN: [CastOrder.new("sanctum_ward", adepts.id, "crownkeep")]})
	var ward_cast := _one(r2, "ritual_cast")
	assert_eq(ward_cast.numbers.ends, [String(_enchantments(r1.new_state, "bloodrot")[0].id)], "the ward marks the curse")
	assert_true(String(ward_cast.text).contains("bites once more"), ward_cast.text)
	assert_eq(_of(r2, "curse_bit").size(), 1, "it bites once more")
	assert_eq(_enchantments(r2.new_state, "bloodrot"), [], "then ends, a turn early")
	var ended := _one(r2, "enchantment_ended")
	assert_eq([ended.numbers.ritual, ended.numbers.cause], ["bloodrot", "ward"])
	assert_eq(String(ended.factions[0]), CLANS)


func test_far_sight_sees_for_two_turns_and_a_caster_blocks_the_reading_not_the_sight() -> void:
	var s := _game({}, {CROWN: "warrior_king"})
	s.setup_fog([])
	var eye := _army(s, CLANS, "wildmoor", ["shamans"])
	var t := s.current_turn + 1
	assert_eq(int(MagicRules.distances(s, "wildmoor").crownkeep), 3, "Crownkeep is in range")
	assert_eq(FogRules.sight(s, CLANS).crownkeep, FogRules.VEILED, "out of sight before")
	var r := _resolve(s, {CLANS: [CastOrder.new("far_sight", eye.id, "crownkeep")]})
	var sight: Array = _enchantments(r.new_state, "far_sight")
	assert_eq([sight[0].kind, sight[0].province, int(sight[0].until_turn)], ["sight", "crownkeep", t + 2])
	assert_eq(MagicRules.vision_grants(r.new_state, CLANS), ["crownkeep"])
	assert_eq(MagicRules.vision_grants(r.new_state, CROWN), [], "only the caster sees")
	# King Corvane casts nothing and no Adepts stand there: the reading is given.
	var reading := _one(r, "far_sight_reading")
	assert_false(bool(reading.numbers.blocked))
	var read: Dictionary = reading.numbers.reading
	var crown: Faction = r.new_state.find_faction(CROWN)
	assert_eq(int(read.gold), s.find_faction(CROWN).gold, "the gold as the ritual resolves")
	assert_eq(read.mandates, crown.mandates)
	assert_eq(int(read.kept_power), crown.kept_power)
	assert_eq(int(read.research_points), s.find_faction(CROWN).research_points)
	for key in ["nodes", "spells", "spellbook"]:
		assert_true(read.has(key), "the reading names %s" % key)
	assert_false(read.has("research_target"), "never the research target")
	assert_eq(int(_one(r, "ritual_cast").numbers.gold), _cost("far_sight"))
	# You see it in clear sight at the start of your next 2 turns.
	var state: GameState = r.new_state
	for turn in [t + 1, t + 2]:
		assert_eq(FogRules.sight(state, CLANS).crownkeep, FogRules.CLEAR, "in clear sight at the start of turn %d" % turn)
		state = _resolve(state, {}).new_state
	assert_eq(FogRules.sight(state, CLANS).crownkeep, FogRules.VEILED, "and not after")
	# The Ever-Regent stands at Crownkeep: a caster blocks the reading, not the sight, and the price is paid in full.
	var regent := _game()
	var eye2 := _army(regent, CLANS, "wildmoor", ["shamans"])
	var r2 := _resolve(regent, {CLANS: [CastOrder.new("far_sight", eye2.id, "crownkeep")]})
	var blocked := _one(r2, "far_sight_reading")
	assert_true(bool(blocked.numbers.blocked))
	assert_eq(blocked.numbers.get("reading", {}), {}, "no reading")
	assert_true(String(blocked.text).contains("blocked"), blocked.text)
	assert_eq(MagicRules.vision_grants(r2.new_state, CLANS), ["crownkeep"], "the sight still stands")
	assert_eq(_of(r2, "ritual_turned_aside"), [], "not turned aside")
	assert_eq(int(_one(r2, "ritual_cast").numbers.gold), _cost("far_sight"), "full price")


func test_one_pack_at_a_time_its_size_and_its_price() -> void:
	var s := _game({CLANS: ["briar_snare", "call_the_pack"]})
	var shamans := _army(s, CLANS, "thornvale", ["shamans"])
	var t := s.current_turn + 1
	var r := _resolve(s, {CLANS: [CastOrder.new("call_the_pack", shamans.id, "thornvale", CastOrder.GOLD, 3)]})
	var summoned := _one(r, "summoned")
	var pack: Army = r.new_state.find_army(String(summoned.numbers.army))
	assert_true(pack != null, "a new army of its own")
	assert_ne(pack.id, shamans.id)
	assert_eq(pack.location, "thornvale")
	assert_eq(pack.units.map(func(u): return u.type.id), ["thornwolves", "thornwolves", "thornwolves"])
	assert_eq(pack.units.map(func(u): return u.until), [t + 4, t + 4, t + 4], "fading at the end of turn T + 4")
	assert_eq(int(_one(r, "ritual_cast").numbers.gold), 3 * _cost("call_the_pack"))
	var again := OrderBook.check_order(r.new_state, CLANS, CastOrder.new("call_the_pack", shamans.id, "thornvale", CastOrder.GOLD, 3), [])
	assert_eq(String(again.get("code", "")), "pack_out", "one pack at a time: %s" % again)
	# With Wild Mastery the pack can be one wolf bigger, at 5 gold a wolf.
	var big := _game({CLANS: ["briar_snare", "call_the_pack", "wild_mastery"]})
	var bs := _army(big, CLANS, "thornvale", ["shamans"])
	assert_eq(MagicRules.pack_sizes(big, CLANS, bs), [3, 4])
	var rb := _resolve(big, {CLANS: [CastOrder.new("call_the_pack", bs.id, "thornvale", CastOrder.GOLD, 4)]})
	assert_eq(int(_one(rb, "summoned").numbers.count), 4)
	assert_eq(int(_one(rb, "ritual_cast").numbers.gold), 4 * _cost("call_the_pack"))


func test_summons_hold_on_their_arrival_turn_fade_on_time_and_empty_armies_are_removed() -> void:
	var s := _game({CLANS: ["briar_snare", "call_the_pack"]})
	var shamans := _army(s, CLANS, "thornvale", ["shamans"])
	var t := s.current_turn + 1
	var r := _resolve(s, {CLANS: [CastOrder.new("call_the_pack", shamans.id, "thornvale", CastOrder.GOLD, 3)]})
	var pack_id := String(_one(r, "summoned").numbers.army)
	assert_eq(r.new_state.find_army(pack_id).location, "thornvale", "it holds the turn it arrives")
	var state: GameState = r.new_state
	var turn := t + 1
	while turn < t + 4:
		state = _resolve(state, {}).new_state
		assert_true(state.find_army(pack_id) != null, "still out after turn %d" % turn)
		turn += 1
	# A Tusker joined the pack's army (as a recruit at the capital would): it stays when the wolves fade.
	var mixed: GameState = state.deep_copy()
	mixed.find_army(pack_id).units.append(Unit.new(TurnResolver.recruitable_type(mixed.find_faction(CLANS), "tuskers", mixed), CLANS))
	var last := _resolve(state, {})
	assert_eq(last.new_state.find_army(pack_id), null, "faded at the end of turn T + 4; the empty army is removed")
	var faded := _one(last, "summon_faded")
	assert_eq([int(faded.numbers.count), bool(faded.numbers.removed)], [3, true])
	assert_eq(faded.phase, "enchantments")
	var kept := _resolve(mixed, {})
	assert_eq(kept.new_state.find_army(pack_id).units.map(func(u): return u.type.id), ["tuskers"], "only the wolves leave")
	assert_false(bool(_one(kept, "summon_faded").numbers.removed))
	# Once the pack has faded, a new one can be called.
	assert_eq(OrderBook.check_order(last.new_state, CLANS, CastOrder.new("call_the_pack", shamans.id, "thornvale", CastOrder.GOLD, 3), []), {})


func test_siege_engines_riding_with_a_faded_pack_are_lost_and_said_so() -> void:
	var s := _game({CLANS: ["briar_snare", "call_the_pack"]})
	assert_true(s.setup_sieges([]))
	var den := _army(s, CLANS, "fangridge", ["shamans"])
	var r := _resolve(s, {CLANS: [CastOrder.new("call_the_pack", den.id, "fangridge", CastOrder.GOLD, 3)]})
	var pack_id := String(_one(r, "summoned").numbers.army)
	var state: GameState = r.new_state
	state.find_army(pack_id).engines = 1  # as a recruited engine joins the first army there that can carry it
	var t := s.current_turn + 1
	while state.current_turn < t + 4:  # the wolves fade at the end of turn T + 4
		var next := _resolve(state, {})
		if next.new_state.find_army(pack_id) == null:
			var faded := _one(next, "summon_faded")
			assert_eq(int(faded.numbers.engines_lost), 1)
			assert_true(String(faded.text).contains("lost with it"), faded.text)
		state = next.new_state
	assert_eq(state.find_army(pack_id), null, "the pack is gone")


func test_one_greenwrath_at_a_time_in_a_forest_until_it_falls() -> void:
	var s := _game({CLANS: CLANS_GROVE}, {CLANS: {"ruler": "thornmane_avatar", "mandates": []}})
	var shamans := _army(s, CLANS, "thornvale", ["shamans"])
	assert_eq(s.find_province("thornvale").terrain, "forest")
	var plains := _army(s, CLANS, "bloodfen", ["shamans"])
	assert_eq(String(OrderBook.check_order(s, CLANS, CastOrder.new("wake_the_greenwrath", plains.id, "bloodfen"), []).get("code", "")), "not_forest")
	var r := _resolve(s, {CLANS: [CastOrder.new("wake_the_greenwrath", shamans.id, "thornvale")]})
	var wrath: Army = r.new_state.find_army(String(_one(r, "summoned").numbers.army))
	assert_eq(wrath.units.map(func(u): return [u.type.id, u.until]), [["greenwrath", 0]], "it stays until it falls")
	assert_eq(int(_one(r, "ritual_cast").numbers.gold), _cost("wake_the_greenwrath"))
	var again := OrderBook.check_order(r.new_state, CLANS, CastOrder.new("wake_the_greenwrath", shamans.id, "thornvale"), [])
	assert_eq(String(again.get("code", "")), "summon_awake", "one at a time")
	var state: GameState = r.new_state
	for _i in 4:
		state = _resolve(state, {}).new_state
	assert_true(state.find_army(wrath.id) != null, "still awake turns later")


func test_bastion_raises_a_fort_and_its_cap_counts_forts_ever_raised() -> void:
	var s := _game({CROWN: CROWN_FORGE})
	_own(s, CROWN, ["highcrag", "westwatch", "rivermarch"])
	var regent := _ruler(s, CROWN)
	assert_false(s.find_province("highcrag").has_fort)
	var r := _resolve(s, {CROWN: [CastOrder.new("bastion", regent.id, "highcrag")]})
	assert_true(r.new_state.find_province("highcrag").has_fort, "raised for good")
	assert_eq(r.new_state.find_faction(CROWN).bastions, ["highcrag"])
	var raised := _one(r, "fort_raised")
	assert_eq(raised.provinces, ["highcrag"])
	assert_eq(int(_one(r, "ritual_cast").numbers.gold), _cost("bastion"))
	var r2 := _resolve(r.new_state, {CROWN: [CastOrder.new("bastion", regent.id, "westwatch")]})
	assert_eq(r2.new_state.find_faction(CROWN).bastions, ["highcrag", "westwatch"])
	# Highcrag is lost: the cap still counts it, whether or not it is later lost.
	var state: GameState = r2.new_state
	state.find_province("highcrag").owner = CLANS
	var third := OrderBook.check_order(state, CROWN, CastOrder.new("bastion", regent.id, "rivermarch"), [])
	assert_eq(String(third.get("code", "")), "bastion_cap")
	assert_true(String(third.reason).contains("%d Bastion forts" % MagicData.BASTION_CAP), third.reason)
	# With forts and sieges, Bastion builds the lowest level at once, at full walls.
	var sieges := _game({CROWN: CROWN_FORGE})
	assert_true(sieges.setup_sieges([]))
	_own(sieges, CROWN, ["highcrag"])
	var rs := _resolve(sieges, {CROWN: [CastOrder.new("bastion", _ruler(sieges, CROWN).id, "highcrag")]})
	var p: Province = rs.new_state.find_province("highcrag")
	assert_eq([p.has_fort, p.fort_level, p.walls, p.fort_by], [true, 1, SiegeRules.walls_max(1), CROWN])


func test_blood_moon_is_one_global_enchantment_heralded_to_everyone() -> void:
	var s := _game({CLANS: CLANS_BLOOD})
	s.setup_fog([])
	var shamans := _army(s, CLANS, "fangridge", ["shamans"])
	var t := s.current_turn + 1
	var r := _resolve(s, {CLANS: [CastOrder.new("blood_moon", shamans.id, "")]})
	var moon: Array = _enchantments(r.new_state, "blood_moon")
	assert_eq([moon[0].kind, moon[0].province, int(moon[0].until_turn)], ["global", "", t + 2])
	var cast := _one(r, "ritual_cast")
	assert_true(bool(cast.numbers.global))
	assert_eq(int(cast.numbers.gold), _cost("blood_moon"))
	# Under fog the Crown is told: the moon turns red for everyone, by name.
	var crown_view := FogRules.filter_events(r.events, CROWN, s, r.new_state)
	var heard := crown_view.filter(func(e): return String(e.type) == "ritual_cast")
	assert_eq(heard.size(), 1, "the global ritual is heralded")
	assert_true(String(heard[0].text).contains("Blood Moon"), "named, not an id: %s" % heard[0].text)
	assert_false(String(heard[0].text).contains("Fangridge"), heard[0].text)
	assert_eq(heard[0].provinces, [], "the herald never says where it was cast from")
	# The same ritual again restarts it: one moon, a new end, paid again.
	var r2 := _resolve(r.new_state, {CLANS: [CastOrder.new("blood_moon", shamans.id, "")]})
	var again: Array = _enchantments(r2.new_state, "blood_moon")
	assert_eq(again.size(), 1, "never stacks")
	assert_eq(String(again[0].id), String(moon[0].id), "the same enchantment")
	assert_eq(int(again[0].until_turn), t + 3)
	assert_true(bool(_one(r2, "ritual_cast").numbers.restarted))


func test_the_same_curse_on_the_same_province_restarts_it_and_is_paid_again() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var rot := _army(s, CLANS, "thornvale", ["shamans"])
	var t := s.current_turn + 1
	var r1 := _resolve(s, {CLANS: [CastOrder.new("bloodrot", rot.id, "crownkeep")]})
	var r2 := _resolve(r1.new_state, {CLANS: [CastOrder.new("bloodrot", rot.id, "crownkeep")]})
	var curses: Array = _enchantments(r2.new_state, "bloodrot")
	assert_eq(curses.size(), 1, "one Bloodrot per province")
	assert_eq(int(curses[0].until_turn), t + 1 + 2)
	assert_eq(int(_one(r2, "ritual_cast").numbers.gold), _cost("bloodrot"), "paid again")
	assert_eq(_of(r2, "curse_bit").size(), 1, "it bites once a turn, not twice")


# --- the heal skips (§6.3) ----------------------------------------------------------------------------

func _cursed(s: GameState, pid: String) -> GameState:
	var c := s.deep_copy()
	c.find_faction(CLANS).enchant_counter = 1
	c.enchantments = [{"id": "beasts-e1", "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": pid, "armies": [],
		"cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false}]
	return c


func test_cursed_fighters_heal_from_nothing_in_the_rulers_and_research_phases() -> void:
	var s := _game()
	for u in _fighters(_field(s, CROWN)):
		u.current_hp = 2
	_ruler(s, CROWN).ruler.current_hp = 3
	assert_false(RulerRules.apply_mending_light(s.deep_copy(), CROWN).healed.is_empty(), "Mending Light heals at Crownkeep")
	assert_true(int(RulerRules.heal_ruler(s.deep_copy(), CROWN).healed) > 0, "the Regent heals")
	var cursed := _cursed(s, "crownkeep")
	assert_eq(RulerRules.apply_mending_light(cursed, CROWN).healed, [], "Mending Light heals nobody cursed")
	assert_eq(int(RulerRules.heal_ruler(cursed, CROWN).healed), 0, "a cursed ruler doesn't heal")
	# Through the resolver: the rulers phase writes no healing at a cursed Crownkeep.
	var r := _resolve(cursed, {})
	assert_eq(_of(r, "mending"), [])
	assert_eq(_of(r, "ruler_healed"), [])
	# Hallowed Land (Celestial Host) and the Forges (Living Iron) in the research phase.
	for line in [["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"],
			["crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"]]:
		var p := _game({CROWN: line})
		for u in _fighters(_field(p, CROWN)):
			u.current_hp = 2
		assert_false(AscensionRules.heal_targets(p, CROWN).get("healed", []).is_empty(), "%s heals at home" % line.back())
		assert_eq(AscensionRules.heal_targets(_cursed(p, "crownkeep"), CROWN).get("healed", []), [], "%s: not the cursed" % line.back())
	# Dawn Blessing: a blessed army standing in a rival's curse heals nothing.
	var b := _cursed(_game({CROWN: ["sunlance", "dawn_blessing"]}), "crownkeep")
	_ruler(b, CROWN).location = "rivermarch"
	var field := _field(b, CROWN)
	for u in _fighters(field):
		u.current_hp = 2
	b.find_faction(CROWN).enchant_counter = 1
	b.enchantments.append({"id": "kingdom-e1", "ritual": "dawn_blessing", "faction": CROWN, "kind": "blessing", "province": "crownkeep",
		"armies": [field.id], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false})
	b.enchantments.sort_custom(func(x, y): return String(x.id) < String(y.id))
	var step := MagicRules.enchantment_step(b, 1)
	assert_eq(step.healed, [], "cursed: the blessing heals nothing")


# --- forecasts (§6.2, §11.2) ------------------------------------------------------------------------

## For each ritual: a game where it is legal, the faction, and its order.
func _forecast_cases() -> Array:
	var out := []
	var a := _game({CROWN: CROWN_FORGE})
	_own(a, CROWN, ["highcrag"])
	var adepts := _army(a, CROWN, "crownkeep", ["adepts"])
	out.append([a, CROWN, CastOrder.new("dawn_blessing", adepts.id, "crownkeep")])
	out.append([a, CROWN, CastOrder.new("sanctum_ward", adepts.id, "crownkeep")])
	out.append([a, CROWN, CastOrder.new("bastion", _ruler(a, CROWN).id, "highcrag")])
	out.append([a, CROWN, CastOrder.new("far_sight", adepts.id, "thornvale")])
	var g := _game({CLANS: CLANS_GROVE})
	var gs := _army(g, CLANS, "thornvale", ["shamans", "tuskers"])
	out.append([g, CLANS, CastOrder.new("call_the_pack", gs.id, "thornvale", CastOrder.GOLD, 3)])
	out.append([g, CLANS, CastOrder.new("wake_the_greenwrath", gs.id, "thornvale")])
	out.append([g, CLANS, CastOrder.new("bloodrot", gs.id, "crownkeep")])
	var m := _game({CLANS: CLANS_BLOOD})
	out.append([m, CLANS, CastOrder.new("blood_moon", _army(m, CLANS, "fangridge", ["shamans"]).id, "")])
	out.append([m, CLANS, CastOrder.new("far_sight", _ruler(m, CLANS).id, "ironspike")])
	return out


func test_every_ritual_forecast_equals_its_result_when_nothing_is_turned_aside() -> void:
	var seen := {}
	for c in _forecast_cases():
		var s: GameState = c[0]
		var fid: String = c[1]
		var order: CastOrder = c[2]
		seen[order.ritual] = true
		var f := MagicRules.forecast_ritual(s, fid, order, [order])
		assert_true(bool(f.ok), "%s: legal (%s)" % [order.ritual, f.get("reason", "")])
		assert_false(String(f.text).is_empty(), "%s: a forecast sentence" % order.ritual)
		assert_false(String(f.text).contains("_"), "%s: no raw id: %s" % [order.ritual, f.text])
		var r := _resolve(s, {fid: [order]})
		var cast := _one(r, "ritual_cast")
		var fx: Dictionary = f.effect
		assert_eq(fx.outcome, "cast", order.ritual)
		for key in ["ritual", "kind", "army", "caster", "target", "pay", "price", "gold", "hp", "until_turn", "bonus", "enchantment",
				"restarted", "global", "blessed", "ends", "summon", "fort", "read", "blocked"]:
			assert_eq(fx.get(key), cast.numbers.get(key), "%s: the forecast's %s is the result's" % [order.ritual, key])
		# The sentence names the numbers the turn report will.
		if int(fx.gold) > 0:
			assert_true(String(f.text).contains("%d gold" % int(fx.gold)), "%s: %s" % [order.ritual, f.text])
		if int(fx.until_turn) > 0:
			assert_true(String(f.text).contains("turn %d" % int(fx.until_turn)), "%s: %s" % [order.ritual, f.text])
			assert_true(String(cast.text).contains("turn %d" % int(fx.until_turn)) or _of(r, "enchantment_began").any(
				func(e): return String(e.text).contains("turn %d" % int(fx.until_turn))), "%s: the report says it too" % order.ritual)
	for rid in MagicData.SPELLS:
		if MagicRules.is_ritual(rid):
			assert_true(seen.has(rid), "%s has a forecast case" % rid)
	# An illegal cast has no forecast but its reason.
	var s0 := _game()
	var bad := MagicRules.forecast_ritual(s0, CLANS, CastOrder.new("bloodrot", _field(s0, CLANS).id, "crownkeep"), [])
	assert_false(bool(bad.ok))
	assert_true(String(bad.reason).contains("You don't know Bloodrot yet"), bad.reason)


func test_a_forecast_names_the_summoned_army_in_the_order_given() -> void:
	# Two summons of one faction resolve in the order given (§6.3): each forecast names the army the turn will make.
	var s := _game({CLANS: CLANS_GROVE})
	var wild := _army(s, CLANS, "thornvale", ["shamans"])
	var other := _army(s, CLANS, "thornvale", ["shamans"])
	var wrath := CastOrder.new("wake_the_greenwrath", wild.id, "thornvale")
	var pack := CastOrder.new("call_the_pack", other.id, "thornvale", CastOrder.GOLD, 3)
	var orders := [wrath, pack]
	var fw := MagicRules.forecast_ritual(s, CLANS, wrath, orders)
	var fp := MagicRules.forecast_ritual(s, CLANS, pack, orders)
	var r := _resolve(s, {CLANS: orders})
	var made := {}
	for e in _of(r, "summoned"):
		made[String(e.numbers.ritual)] = String(e.numbers.army)
	assert_eq(String(fw.effect.summon.army), made.wake_the_greenwrath)
	assert_eq(String(fp.effect.summon.army), made.call_the_pack)


func test_a_forecast_warns_of_a_ward_it_can_see() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var rot := _army(s, CLANS, "thornvale", ["shamans"])
	s.find_faction(CROWN).enchant_counter = 1
	s.enchantments = [{"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 2, "bonus": 0, "ending": false}]
	s.current_turn = 1
	var order := CastOrder.new("bloodrot", rot.id, "crownkeep")
	var f := MagicRules.forecast_ritual(s, CLANS, order, [order])
	assert_true(bool(f.ok), "still legal: legality never reads a rival's ward (§2.10)")
	assert_eq(f.effect.outcome, "turned_aside")
	assert_true(String(f.text).contains("turned aside"), f.text)
	assert_true(String(f.text).contains("%d gold" % _half(_cost("bloodrot"))), f.text)
	var r := _resolve(s, {CLANS: [order]})
	assert_eq(int(_one(r, "ritual_turned_aside").numbers.gold), int(f.effect.gold), "and it was")


# --- fog (§2.8) --------------------------------------------------------------------------------------

func test_under_fog_a_ritual_is_shown_only_as_the_fog_allows() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"]})
	s.setup_fog([])
	_ruler(s, CROWN).location = "rivermarch"
	var rot := _army(s, CLANS, "thornvale", ["shamans", "tuskers"])
	var den := _army(s, CLANS, "fangridge", ["shamans"])
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", rot.id, "crownkeep"),
		CastOrder.new("call_the_pack", den.id, "fangridge", CastOrder.GOLD, 3)]})
	var crown := FogRules.report_for(r.events, CROWN, s, r.new_state)
	var clans := FogRules.report_for(r.events, CLANS, s, r.new_state)
	var crown_types: Array = crown.map(func(e): return String(e.type))
	# The Crown: its land was targeted, so it reads ritual_fell whole (never the caster's province); it was bitten, so
	# it reads the bite whole. It never reads the Clans' cast, their pack or their price.
	assert_true(crown_types.has("ritual_fell"))
	assert_true(crown_types.has("curse_bit"))
	for t in ["ritual_cast", "summoned", "enchantment_began"]:
		assert_false(crown_types.has(t), "the Crown doesn't see the Clans' %s" % t)
	for e in crown:
		assert_false(String(e.text).contains("Thornvale") and String(e.type) == "ritual_fell", "never the caster's province")
		assert_false(String(e.text).contains("Fangridge") and ["summoned", "ritual_cast"].has(String(e.type)), e.text)
	# The Clans: their own casts whole; the bite on the Crown rebuilt with no count of what stands there.
	var bit: Array = clans.filter(func(e): return String(e.type) == "curse_bit")
	assert_eq(bit.size(), 1, "the caster hears its curse bit")
	assert_true(bool(bit[0].get("rebuilt", false)), "rebuilt for the caster")
	for key in bit[0].numbers:
		assert_true(FogData.SAFE_NUMBERS.curse_bit.has(key), "only safe numbers: %s" % key)
	assert_false(bit[0].numbers.has("taken") or bit[0].numbers.has("total"), "no count of the garrison")
	assert_true(String(bit[0].text).contains("Bloodrot"), bit[0].text)
	assert_eq(clans.filter(func(e): return String(e.type) == "ritual_cast").size(), 2)
	# The Crown learns the Clans know Bloodrot (it fell on its land).
	var intel := FogRules.learn({}, CROWN, crown.filter(func(e): return not FogData.SYNTHETIC_TYPES.has(String(e.type))), r.new_state)
	assert_true(intel[CLANS].nodes.map(func(n): return String(n.node)).has("bloodrot"), "learned from the curse: %s" % intel)
	# The view shows the curse to the Crown on its own land (in clear sight), under a view id.
	var view := FogRules.view_state(r.new_state, CROWN)
	var seen: Array = view.enchantments.filter(func(e): return String(e.ritual) == "bloodrot")
	assert_eq(seen.size(), 1)
	assert_true(String(seen[0].id).begins_with(FogData.VIEW_PREFIX), "a view id")


func test_a_far_sight_reading_is_learned_by_its_caster_under_fog() -> void:
	var s := _game({}, {CROWN: "warrior_king"})
	s.setup_fog([])
	var eye := _army(s, CLANS, "wildmoor", ["shamans"])
	var r := _resolve(s, {CLANS: [CastOrder.new("far_sight", eye.id, "crownkeep")]})
	var shown := FogRules.report_for(r.events, CLANS, s, r.new_state).filter(func(e): return not FogData.SYNTHETIC_TYPES.has(String(e.type)))
	assert_eq(shown.filter(func(e): return String(e.type) == "far_sight_reading").size(), 1)
	var intel := FogRules.learn({}, CLANS, shown, r.new_state)
	assert_eq(intel[CROWN].mandates, _sorted(r.new_state.find_faction(CROWN).mandates), "the reading's mandates are learned")
	assert_eq(int(intel[CROWN].kept_power), r.new_state.find_faction(CROWN).kept_power)
	var crown := FogRules.report_for(r.events, CROWN, s, r.new_state)
	var fell: Array = crown.filter(func(e): return String(e.type) == "ritual_fell")
	assert_eq(fell.size(), 1, "the Crown is told its capital was read")
	assert_false(String(fell[0].text).contains("Wildmoor"), fell[0].text)


func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


# --- independents (IND-1) ------------------------------------------------------------------------------

func test_a_curse_or_a_summon_on_a_free_holds_garrison_resolves_sensibly() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"]})
	assert_true(s.setup_independents([]))
	s.setup_fog([])
	var shamans := _field(s, CLANS)
	shamans.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CLANS), "shamans", s), CLANS))
	var garrison := s.garrison_at("bloodfen")
	var before := _hps(_fighters(garrison))
	var r := _resolve(s, {CLANS: [CastOrder.new("bloodrot", shamans.id, "bloodfen")]})
	assert_eq(_rejections(r), [])
	assert_eq(_hps(_fighters(r.new_state.garrison_at("bloodfen"))), _bite(before, _budget("bloodrot", 0)), "the garrison is bitten")
	assert_eq(_of(r, "ritual_fell"), [], "the Free Holds are never a player: nobody to tell")
	var bit := _one(r, "curse_bit")
	assert_eq(String(bit.factions[0]), CLANS, "a garrison's wounds are public: the caster reads the bite whole")
	assert_true(String(bit.text).contains("Free Holds") or String(bit.text).contains(IndependentData.garrison_kind("plains")), bit.text)
	var shown := FogRules.report_for(r.events, CLANS, s, r.new_state).filter(func(e): return String(e.type) == "curse_bit")
	assert_false(bool(shown[0].get("rebuilt", false)), "whole, under fog")
	var violations := Simulator.check_invariants(s, r.new_state, r.events)
	assert_eq(violations, [], "no invariant broken")
	# The Clans take Bloodfen: their curse goes on there, and hurts only other factions' fighters.
	var taken: GameState = r.new_state.deep_copy()
	taken.armies = taken.armies.filter(func(a): return a.owner != IndependentData.FACTION_ID or a.location != "bloodfen")
	taken.find_province("bloodfen").owner = CLANS
	var mine := _army(taken, CLANS, "bloodfen", ["tuskers"])
	mine.units[0].current_hp = 9
	var r2 := _resolve(taken, {})
	assert_eq(r2.new_state.find_army(mine.id).units[0].current_hp, 9, "the caster's own are never bitten")
	assert_eq(_of(r2, "curse_bit"), [])
	assert_eq(_enchantments(r2.new_state, "bloodrot").size(), 1, "the curse goes on")
	# A summon: Call the Pack forms at the caster's own province, and a caster never shares a province with a garrison
	# (a neutral fort's Free Holds meet you in the open, M3c with IND-1), so a summon can't land on a hold: aimed at one it
	# is refused with its reason. Called beside one, the pack can attack it next turn like any army, and the battle,
	# the capture and the fading resolve as for any army.
	var g := _game({CLANS: ["briar_snare", "call_the_pack"]})
	assert_true(g.setup_independents([]))
	var den := _field(g, CLANS)
	den.units.append(Unit.new(TurnResolver.recruitable_type(g.find_faction(CLANS), "shamans", g), CLANS))
	var aimed := OrderBook.check_order(g, CLANS, CastOrder.new("call_the_pack", den.id, "bloodfen", CastOrder.GOLD, 3), [])
	assert_eq(String(aimed.get("code", "")), "bad_target", "a summon is cast on the caster's own province")
	assert_true(String(aimed.reason).contains("caster's own province"), aimed.reason)
	var t := g.current_turn + 1
	var r3 := _resolve(g, {CLANS: [CastOrder.new("call_the_pack", den.id, "fangridge", CastOrder.GOLD, 3)]})
	var pack_id := String(_one(r3, "summoned").numbers.army)
	var r4 := _resolve(r3.new_state, {CLANS: [MoveOrder.new(pack_id, "bloodfen")]})
	assert_eq(_of(r4, "battle").size(), 1, "the pack fights the hold")
	assert_eq(Simulator.check_invariants(r3.new_state, r4.new_state, r4.events), [], "no invariant broken")
	var state: GameState = r4.new_state
	while state.current_turn < t + 4:
		var next := _resolve(state, {})
		assert_eq(Simulator.check_invariants(state, next.new_state, next.events), [], "no invariant broken on turn %d" % (state.current_turn + 1))
		state = next.new_state
	assert_eq(state.find_army(pack_id), null, "gone by the end of turn T + 4, beaten or faded")


# --- the replay (§18) -----------------------------------------------------------------------------------

## A scripted game from `start` through `script` ({turn: {faction id: [orders]}}): every ritual of the game's builds is
## cast. Returns the session.
func _play(start: GameState, script: Dictionary) -> GameSession:
	var session := GameSession.new(start, [CROWN, CLANS], 23, AutoBattleResolver.new())
	assert_eq(session.setup_errors(), [])
	var turn := 1
	while turn <= script.size() + 3 and not session.is_over():
		for fid in [CROWN, CLANS]:
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			assert_eq(session.current_player(), fid)
			for o in script.get(turn, {}).get(fid, []):
				assert_eq(session.queue_order(o), "", "turn %d, %s: %s" % [turn, fid, o.describe()])
			session.end_turn()
		turn += 1
	return session


func test_a_replay_through_every_ritual_is_identical() -> void:
	var cast := {}
	for clans_line in [CLANS_GROVE, CLANS_BLOOD]:
		var s := _game({CROWN: CROWN_FORGE, CLANS: clans_line}, {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
		s.setup_fog([])
		_own(s, CROWN, ["highcrag", "westwatch"])
		_own(s, CLANS, ["thornvale", "wildmoor"])
		var ward := _army(s, CROWN, "crownkeep", ["adepts"])
		var bless := _army(s, CROWN, "highcrag", ["adepts", "spearmen"])
		var rot := _army(s, CLANS, "thornvale", ["shamans", "tuskers", "tuskers"])
		var wild := _army(s, CLANS, "thornvale", ["shamans"])
		var eye := _army(s, CLANS, "wildmoor", ["shamans"])
		var regent := _ruler(s, CROWN).id
		var script := {
			1: {CROWN: [CastOrder.new("sanctum_ward", ward.id, "crownkeep"), CastOrder.new("dawn_blessing", bless.id, "highcrag")],
				CLANS: [CastOrder.new("bloodrot", rot.id, "crownkeep", CastOrder.BLOOD), CastOrder.new("far_sight", eye.id, "crownkeep")]},
			2: {CROWN: [CastOrder.new("bastion", regent, "westwatch"), CastOrder.new("far_sight", ward.id, "thornvale")],
				CLANS: [CastOrder.new("bloodrot", rot.id, "highcrag"), CastOrder.new("call_the_pack", wild.id, "thornvale", CastOrder.GOLD, 3)]},
			3: {CLANS: [CastOrder.new("wake_the_greenwrath", wild.id, "thornvale") if clans_line == CLANS_GROVE
				else CastOrder.new("blood_moon", eye.id, "")]},
		}
		var session := _play(s, script)
		var rec := session.record()
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "the record replays")
		assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()), "to the same state")
		var restored := GameSession.from_record(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
		assert_eq(restored.errors, [], "the save loads")
		assert_eq(JSON.stringify(restored.session.state().to_dict()), JSON.stringify(session.state().to_dict()))
		# Which rituals were cast (or turned aside) over the game: resolved again from the record, turn by turn.
		var state := GameState.from_dict(JSON.parse_string(JSON.stringify(rec.start_state)))
		for entry in rec.history:
			var r := TurnResolver.resolve(state, OrderBook.orders_from_dict(entry.orders), Serial.to_int(entry.seed))
			assert_eq(Simulator.check_invariants(state, r.new_state, r.events), [], "no invariant broken on turn %d" % (state.current_turn + 1))
			for e in r.events:
				if ["ritual_cast", "ritual_turned_aside"].has(String(e.type)):
					cast[String(e.numbers.ritual)] = true
				assert_false(String(e.type) == "order_rejected" and String(e.phase) == "rituals", "no ritual failed: %s" % e.text)
			state = r.new_state
	for rid in MagicData.SPELLS:
		if MagicRules.is_ritual(rid):
			assert_true(cast.has(rid), "%s was cast in the replay" % rid)
