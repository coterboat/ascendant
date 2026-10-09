extends "res://tests/test_case.gd"
## M3c S-1a (#98) acceptance, tests/test_forts.gd: fort levels, Fortify and construction, repair, recruiting at
## forts and siege engines (design/M3C_SIEGES.md §2, §5). Every expected number is derived from FortData.

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


func _check(s: GameState, fid: String, order, existing: Array = []) -> Dictionary:
	return OrderBook.check_order(s, fid, order, existing)


func _plain(reason: String, place: String, what: String) -> void:
	assert_false(reason.is_empty(), "%s: a reason is given" % what)
	assert_false(reason.contains("_"), "%s: plain words, no ids: %s" % [what, reason])
	if not place.is_empty():
		assert_true(reason.contains(place), "%s: the reason names %s: %s" % [what, place, reason])


# --- levels ---------------------------------------------------------------------------------------

func test_every_level_comes_from_fort_data() -> void:
	var s := GameState.with_sieges(3)
	var crown := s.find_faction(CROWN)
	for level in range(1, FortData.MAX_LEVEL + 1):
		var row: Dictionary = FortData.LEVELS[level]
		assert_eq(SiegeRules.walls_max(level), int(row.walls), "walls of level %d" % level)
		assert_eq(SiegeRules.recruit_limit(level), int(row.recruits), "recruits of level %d" % level)
		assert_eq(SiegeRules.repair_amount(level), int(row.repair), "repair of level %d" % level)
		assert_eq(SiegeRules.level_name(level), String(row.name))
		assert_eq(SiegeRules.may_recruit(level, crown.commander_type), bool(row.commanders), "commanders at level %d" % level)
		assert_eq(SiegeRules.may_recruit(level, SiegeRules.engine_type(CROWN)), bool(row.engines), "engines at level %d" % level)
		assert_true(SiegeRules.may_recruit(level, crown.unit_types[0]), "troops at any fort")
		for w in range(0, int(row.walls) + 1):
			assert_eq(SiegeRules.walls_defense(w), FortData.WALLS_DEFENSE_PER_STEP * ceili(float(w) / FortData.WALL_STEP),
				"walls %d give 2 for every 3 standing, rounded up" % w)
		assert_eq(SiegeRules.damage_look(level, int(row.walls)), "intact", "full walls look intact")
		assert_eq(SiegeRules.damage_look(level, 0), "breached")
	# Where forts start (§2.2): capitals are citadels, every other fort on the map a keep, all at full walls.
	for p in s.provinces:
		var on_map := false
		for d in MapData.PROVINCES:
			if d.id == p.id:
				on_map = d.has_fort
		var expected := int(FortData.START.capital) if p.is_capital else (int(FortData.START.fort) if on_map else 0)
		assert_eq(p.fort_level, expected, "%s starts at level %d" % [p.id, expected])
		assert_eq(p.walls, SiegeRules.walls_max(expected), "%s starts at full walls" % p.id)
		assert_eq(p.has_fort, expected > 0, "%s: has_fort agrees with the level" % p.id)
	assert_eq(s.find_province("crownkeep").fort_level, 3)
	assert_eq(s.find_province("stonegate").fort_level, 2)
	# What a Fortify order costs and builds.
	assert_eq(SiegeRules.fortify_level(s, "westwatch"), 1)
	assert_eq(SiegeRules.fortify_cost(s, "westwatch"), int(FortData.LEVELS[1].cost))
	F.set_fort(s, "westwatch", 1)
	assert_eq(SiegeRules.fortify_level(s, "westwatch"), 2)
	assert_eq(SiegeRules.fortify_cost(s, "westwatch"), int(FortData.LEVELS[2].cost))
	# The engines (§5): never in a roster, offered only with sieges on.
	for fid in [CROWN, CLANS]:
		var e := FortData.engine_for(fid)
		var f := s.find_faction(fid)
		for ut in f.unit_types:
			assert_ne(ut.id, String(e.id), "the engine is not in the roster")
		var engine := TurnResolver.recruitable_type(f, String(e.id), s)
		assert_true(engine != null and SiegeRules.is_engine(engine), "%s recruits its engine with sieges on" % fid)
		assert_eq(engine.cost, int(e.cost))
		assert_eq(TurnResolver.recruitable_type(f, String(e.id), GameState.new(3)), null, "no engine without sieges")


# --- Fortify --------------------------------------------------------------------------------------

func test_fortify_legality_table_with_plain_reasons() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "crownkeep", ["spearmen"]],
		["beasts-2", CLANS, "highcrag", ["tuskers"]],
	], {"westwatch": CROWN, "highcrag": CROWN, "stonegate": CROWN, "ebonpeak": CLANS, "rivermarch": ""})
	F.rich(s, CROWN)
	var rows := [
		["westwatch", "", "Westwatch", "owned, no fort, nobody there: a palisade"],
		["rivermarch", "fortify_not_owned", "Rivermarch", "neutral"],
		["ebonpeak", "fortify_not_owned", "Ebonpeak", "the enemy's"],
		["highcrag", "fortify_enemy_present", "Highcrag", "an enemy army stands there"],
		["crownkeep", "fortify_capital", "Crownkeep", "a capital"],
		["stonegate", "fortify_max", "Stonegate", "already a keep"],
	]
	for row in rows:
		var check := _check(s, CROWN, FortifyOrder.new(row[0]))
		assert_eq(String(check.get("code", "")), row[1], "%s: %s" % [row[0], row[3]])
		if not String(row[1]).is_empty():
			_plain(String(check.reason), row[2], row[3])
	# One site at a time: a second order this turn, or a site already under way anywhere.
	var second := _check(s, CROWN, FortifyOrder.new("westwatch"), [FortifyOrder.new("westwatch")])
	assert_eq(String(second.get("code", "")), "fortify_second")
	_plain(String(second.reason), "", "second order")
	var busy := s.deep_copy()
	F.set_fort(busy, "westwatch", 1)
	busy.find_province("westwatch").works = {"faction": CROWN, "to": 2, "left": 3, "turn": 0}
	busy.find_province("rivermarch").owner = CROWN
	var one := _check(busy, CROWN, FortifyOrder.new("rivermarch"))
	assert_eq(String(one.get("code", "")), "fortify_one_at_a_time")
	_plain(String(one.reason), "Westwatch", "one at a time")
	assert_true(String(one.reason).contains("0 of %d turns" % int(FortData.LEVELS[2].turns)), String(one.reason))
	# Gold: paid with the recruits, in the order given, from one pool.
	var poor := s.deep_copy()
	poor.find_faction(CROWN).gold = int(FortData.LEVELS[1].cost) - 1
	var gold := _check(poor, CROWN, FortifyOrder.new("westwatch"))
	assert_eq(String(gold.get("code", "")), "not_enough_gold")
	_plain(String(gold.reason), "Westwatch", "gold")
	poor.find_faction(CROWN).gold = int(FortData.LEVELS[1].cost) + 5
	assert_eq(_check(poor, CROWN, FortifyOrder.new("westwatch")), {}, "enough gold")
	var after := _check(poor, CROWN, FortifyOrder.new("westwatch"), [RecruitOrder.new("spearmen")])
	assert_eq(String(after.get("code", "")), "not_enough_gold", "a recruit given first is paid first")
	# Without sieges there are no forts to build.
	var m1 := GameState.new(3)
	m1.find_province("westwatch").owner = CROWN
	assert_eq(String(_check(m1, CROWN, FortifyOrder.new("westwatch")).get("code", "")), "no_sieges")


func test_fortify_lost_in_capture_is_rejected_at_no_cost() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "crownkeep", ["spearmen"]],
		["beasts-2", CLANS, "stonegate", ["tuskers"]],
	], {"westwatch": CROWN, "stonegate": CLANS})
	var gold := s.find_faction(CROWN).gold
	var r := F.resolve(s, {CROWN: [FortifyOrder.new("westwatch")], CLANS: [MoveOrder.new("beasts-2", "westwatch")]})
	var ns: GameState = r.new_state
	assert_eq(ns.find_province("westwatch").owner, CLANS, "the Clans took Westwatch")
	assert_true(ns.find_province("westwatch").works.is_empty(), "no site was started")
	var rejected := F.events_of(r.events, "order_rejected").filter(func(e): return e.cause == "fortify_lost")
	assert_eq(rejected.size(), 1, "the Fortify order was refused in the recruitment phase")
	assert_eq(rejected[0].phase, "recruitment")
	_plain(String(rejected[0].reason), "Westwatch", "lost in capture")
	var income := int(F.events_of(r.events, "income").filter(func(e): return e.factions[0] == CROWN)[0].numbers.income)
	assert_eq(ns.find_faction(CROWN).gold, gold + income, "no gold was spent")
	assert_eq(F.events_of(r.events, "construction_started").size(), 0)


func test_construction_works_only_with_no_enemy_and_stands_on_the_forecast_turn() -> void:
	var s := F.state([["kingdom-1", CROWN, "crownkeep", ["spearmen"]], ["beasts-2", CLANS, "fangridge", ["tuskers"]]],
		{"westwatch": CROWN})
	F.rich(s, CROWN)
	var level := 1
	var turns := int(FortData.LEVELS[level].turns)
	var fc := Forecast.fortify(s, CROWN, "westwatch")
	assert_true(fc.ok, fc.text)
	assert_eq(fc.cost, int(FortData.LEVELS[level].cost))
	assert_eq(fc.stands, 1 + turns, "ordered on turn 1, it stands at the end of turn 1 + its turns of work")
	assert_eq(fc.recruit_from, 2 + turns)
	assert_true(String(fc.text).contains("one fort at a time"), fc.text)
	var gold := s.find_faction(CROWN).gold
	var r := F.resolve(s, {CROWN: [FortifyOrder.new("westwatch")]})
	s = r.new_state
	var started := F.events_of(r.events, "construction_started")
	assert_eq(started.size(), 1)
	assert_eq(int(started[0].numbers.cost), int(FortData.LEVELS[level].cost))
	assert_eq(int(started[0].numbers.stands), fc.stands, "the event and the forecast agree")
	var income := int(F.events_of(r.events, "income").filter(func(e): return e.factions[0] == CROWN)[0].numbers.income)
	assert_eq(s.find_faction(CROWN).gold, gold - int(FortData.LEVELS[level].cost) + income, "paid from the gold")
	assert_eq(s.find_province("westwatch").works, {"faction": CROWN, "to": level, "left": turns, "turn": 1})
	# A second site can't start while this one is under way.
	assert_eq(String(_check(s, CROWN, FortifyOrder.new("westwatch")).get("code", "")), "fortify_one_at_a_time")
	for t in range(2, fc.stands + 1):
		assert_eq(s.find_province("westwatch").fort_level, 0, "not standing before the end of turn %d" % fc.stands)
		assert_eq(String(_check(s, CROWN, RecruitOrder.new("spearmen", "westwatch")).get("code", "")), "no_fort_there",
			"no recruits before it stands (turn %d)" % t)
		r = F.resolve(s, {})
		s = r.new_state
	var p := s.find_province("westwatch")
	assert_eq(p.fort_level, level, "it stands at the end of turn %d" % fc.stands)
	assert_eq(p.walls, SiegeRules.walls_max(level), "a finished level stands at full walls")
	assert_true(p.has_fort)
	assert_eq(p.fort_by, CROWN)
	assert_true(p.works.is_empty())
	var built := F.events_of(r.events, "fort_built")
	assert_eq(built.size(), 1)
	assert_eq(int(built[0].numbers.recruit_from), fc.recruit_from)
	assert_eq(s.current_turn + 1, fc.recruit_from, "the turn it first takes recruits")
	assert_eq(_check(s, CROWN, RecruitOrder.new("spearmen", "westwatch")), {}, "it takes recruits from turn %d" % fc.recruit_from)


func test_construction_stops_without_loss_and_is_razed_on_capture() -> void:
	# A palisade at Highcrag being raised to a keep, with a garrison inside; the Clans besiege it.
	var s := F.state([
		["kingdom-1", CROWN, "highcrag", ["spearmen"]],
		["beasts-2", CLANS, "thornvale", ["tuskers", "tuskers"]],
	], {"highcrag": CROWN, "thornvale": CLANS})
	F.set_fort(s, "highcrag", 1)
	s.find_province("highcrag").works = {"faction": CROWN, "to": 2, "left": 2, "turn": 0}
	var r := F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "highcrag")]})
	var ns: GameState = r.new_state
	assert_eq(F.events_of(r.events, "battle").size(), 0, "a siege, not a battle")
	var halted := F.events_of(r.events, "construction_halted")
	assert_eq(halted.size(), 1, "an enemy army stands there: no work")
	assert_eq(int(ns.find_province("highcrag").works.left), 2, "nothing done is lost")
	r = F.resolve(ns, {})
	ns = r.new_state
	assert_eq(int(ns.find_province("highcrag").works.left), 2, "still stopped while the siege goes on")
	# The besiegers leave: the work goes on.
	r = F.resolve(ns, {CLANS: [MoveOrder.new("beasts-2", "thornvale")]})
	ns = r.new_state
	assert_eq(int(ns.find_province("highcrag").works.left), 1, "one turn of work once no enemy is there")
	# Captured: the site is razed and the province keeps the level it had.
	var empty := F.state([["beasts-2", CLANS, "thornvale", ["tuskers"]]], {"highcrag": CROWN, "thornvale": CLANS})
	F.set_fort(empty, "highcrag", 1, 2)
	empty.find_province("highcrag").works = {"faction": CROWN, "to": 2, "left": 1, "turn": 0}
	r = F.resolve(empty, {CLANS: [MoveOrder.new("beasts-2", "highcrag")]})
	ns = r.new_state
	var p := ns.find_province("highcrag")
	assert_eq(p.owner, CLANS)
	assert_true(p.works.is_empty(), "the site is razed")
	assert_eq(p.fort_level, 1, "the palisade stands")
	assert_eq(p.walls, 2, "with its walls as they were")
	var razed := F.events_of(r.events, "construction_razed")
	assert_eq(razed.size(), 1)
	assert_eq(razed[0].phase, "capture")
	assert_true(String(razed[0].text).contains("half-built keep") and String(razed[0].text).contains("The palisade stands"), razed[0].text)


func test_repair_by_level() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "crownkeep", ["spearmen"]],
		["kingdom-2", CROWN, "stonegate", ["spearmen"]],
		["beasts-3", CLANS, "fangridge", ["tuskers"]],
	], {"westwatch": CROWN, "stonegate": CROWN})
	F.set_fort(s, "westwatch", 1, 0)
	F.set_fort(s, "stonegate", 2, 0)
	F.set_fort(s, "crownkeep", 3, 0)
	var r := F.resolve(s, {})
	var ns: GameState = r.new_state
	for pid in ["westwatch", "stonegate", "crownkeep"]:
		var level := ns.find_province(pid).fort_level
		assert_eq(ns.find_province(pid).walls, mini(SiegeRules.walls_max(level), int(FortData.LEVELS[level].repair)),
			"%s repairs by its level" % pid)
	assert_eq(F.events_of(r.events, "walls_repaired").size(), 3)
	# A breached fort is whole again after walls / repair turns, at any level.
	for t in range(1, int(FortData.LEVELS[1].walls / FortData.LEVELS[1].repair)):
		ns = F.resolve(ns, {}).new_state
	for pid in ["westwatch", "stonegate", "crownkeep"]:
		assert_eq(ns.find_province(pid).walls, SiegeRules.walls_max(ns.find_province(pid).fort_level), "%s is whole" % pid)
	r = F.resolve(ns, {})
	assert_eq(F.events_of(r.events, "walls_repaired").size(), 0, "full walls don't repair")


# --- recruiting at forts --------------------------------------------------------------------------

func test_recruit_limits_and_level_rules() -> void:
	var s := F.state([["kingdom-1", CROWN, "crownkeep", ["spearmen"]], ["beasts-2", CLANS, "fangridge", ["tuskers"]]],
		{"stonegate": CROWN, "westwatch": CROWN})
	F.set_fort(s, "westwatch", 1)
	F.rich(s, CROWN)
	var keep := SiegeRules.recruit_limit(2)
	var queued := []
	for i in keep:
		assert_eq(_check(s, CROWN, RecruitOrder.new("spearmen", "stonegate"), queued), {}, "recruit %d of %d at the keep" % [i + 1, keep])
		queued.append(RecruitOrder.new("spearmen", "stonegate"))
	var full := _check(s, CROWN, RecruitOrder.new("spearmen", "stonegate"), queued)
	assert_eq(String(full.get("code", "")), "fort_full")
	assert_true(String(full.reason).contains("%d of its %d" % [keep, keep]), full.reason)
	_plain(String(full.reason), "Stonegate", "full")
	# The limit is per fort: the capital and the palisade still take recruits.
	assert_eq(_check(s, CROWN, RecruitOrder.new("spearmen"), queued), {}, "the capital has its own limit")
	assert_eq(_check(s, CROWN, RecruitOrder.new("spearmen", "westwatch"), queued), {}, "so does the palisade")
	# Commanders and engines need a keep or a citadel.
	var cmd := _check(s, CROWN, RecruitOrder.new("knight_captain", "westwatch"))
	assert_eq(String(cmd.get("code", "")), "fort_level_too_low")
	_plain(String(cmd.reason), "Westwatch", "commander at a palisade")
	assert_true(String(cmd.reason).contains("keep or a citadel"), cmd.reason)
	assert_eq(_check(s, CROWN, RecruitOrder.new("knight_captain", "stonegate")), {}, "a keep recruits commanders")
	s.armies.append(F.army(s, ["kingdom-9", CROWN, "westwatch", ["spearmen"]]))
	var ram := _check(s, CROWN, RecruitOrder.new("siege_ram", "westwatch"))
	assert_eq(String(ram.get("code", "")), "fort_level_too_low", "engines need a keep")
	assert_true(String(ram.reason).contains("Siege Rams"), ram.reason)
	# The capital is a citadel with its own limit; an `at` naming it is the capital.
	var capital := SiegeRules.recruit_limit(3)
	var at_home := []
	for i in capital:
		var at := "" if i % 2 == 0 else "crownkeep"
		assert_eq(_check(s, CROWN, RecruitOrder.new("spearmen", at), at_home), {}, "capital recruit %d" % (i + 1))
		at_home.append(RecruitOrder.new("spearmen", at))
	assert_eq(String(_check(s, CROWN, RecruitOrder.new("spearmen"), at_home).get("code", "")), "fort_full", "the capital's limit")
	# Resolved: recruits arrive at their fort and the report names it with its count.
	var r := F.resolve(s, {CROWN: [RecruitOrder.new("spearmen", "stonegate"), RecruitOrder.new("spearmen", "stonegate")]})
	var recruited := F.events_of(r.events, "recruited")
	assert_eq(recruited.size(), 2)
	assert_eq(recruited[0].provinces, ["stonegate"])
	assert_true(String(recruited[1].text).contains("at Stonegate (keep, 2 of %d this turn)" % keep), recruited[1].text)
	var at_gate: Array = r.new_state.armies.filter(func(a): return a.location == "stonegate")
	assert_eq(at_gate.size(), 1, "they formed one army there")
	assert_eq(at_gate[0].units.size(), 2)


func test_the_wait_after_a_capture_and_the_retake_rule() -> void:
	var s := F.state([["kingdom-1", CROWN, "westwatch", ["spearmen"]], ["beasts-2", CLANS, "fangridge", ["tuskers"]]],
		{"westwatch": CROWN})
	F.rich(s, CROWN)
	var r := F.resolve(s, {CROWN: [MoveOrder.new("kingdom-1", "stonegate")]})
	s = r.new_state
	var p := s.find_province("stonegate")
	assert_eq(p.owner, CROWN, "the empty keep falls to the first army that walks in")
	assert_eq(p.owned_since, 1)
	var from := 1 + FortData.CAPTURE_WAIT + 1
	var captured: Dictionary = F.events_of(r.events, "captured")[0]
	assert_true(String(captured.text).contains("from turn %d" % from), captured.text)
	assert_eq(int(captured.numbers.recruit_from), from)
	var wait := _check(s, CROWN, RecruitOrder.new("spearmen", "stonegate"))
	assert_eq(String(wait.get("code", "")), "fort_just_taken", "turn 2: not yet")
	assert_true(String(wait.reason).contains("You took Stonegate on turn 1: it can take recruits from turn %d" % from), wait.reason)
	while s.current_turn + 1 < from:  # the turns of the wait (FortData.CAPTURE_WAIT): still refused
		assert_false(_check(s, CROWN, RecruitOrder.new("spearmen", "stonegate")).is_empty(), "turn %d: still waiting" % (s.current_turn + 1))
		s = F.resolve(s, {}).new_state
	assert_eq(_check(s, CROWN, RecruitOrder.new("spearmen", "stonegate")), {}, "turn %d: it takes recruits" % from)
	# Retaking your own fort within RETAKE_TURNS turns of losing it restores your standing.
	var lost := F.state([
		["kingdom-1", CROWN, "stonegate", ["spearmen"]],
		["beasts-2", CLANS, "blackwood", ["tuskers"]],
	], {"stonegate": CROWN, "westwatch": CROWN, "blackwood": CLANS})
	F.rich(lost, CROWN)
	r = F.resolve(lost, {CROWN: [MoveOrder.new("kingdom-1", "westwatch")], CLANS: [MoveOrder.new("beasts-2", "stonegate")]})
	lost = r.new_state
	assert_eq(lost.find_province("stonegate").owner, CLANS, "turn 1: the Clans take the keep the Crown left")
	assert_eq(lost.find_province("stonegate").lost, {"faction": CROWN, "owned_since": 0, "turn": 1})
	r = F.resolve(lost, {CROWN: [MoveOrder.new("kingdom-1", "stonegate")], CLANS: [MoveOrder.new("beasts-2", "blackwood")]})
	lost = r.new_state
	assert_eq(lost.find_province("stonegate").owner, CROWN, "turn 2: the Crown takes it back")
	assert_eq(lost.find_province("stonegate").owned_since, 0, "its old standing is restored")
	assert_true(String(F.events_of(r.events, "captured")[0].text).contains("from next turn (3)"), F.events_of(r.events, "captured")[0].text)
	assert_eq(_check(lost, CROWN, RecruitOrder.new("spearmen", "stonegate")), {}, "it recruits at once")
	# Too late: a retake after RETAKE_TURNS turns waits like any capture.
	var late := F.state([
		["kingdom-1", CROWN, "westwatch", ["spearmen"]],
		["beasts-2", CLANS, "blackwood", ["tuskers"]],
	], {"stonegate": CLANS, "westwatch": CROWN, "blackwood": CLANS})
	late.current_turn = 5
	late.find_province("stonegate").owned_since = 2
	late.find_province("stonegate").lost = {"faction": CROWN, "owned_since": 0, "turn": 6 - FortData.RETAKE_TURNS - 1}
	r = F.resolve(late, {CROWN: [MoveOrder.new("kingdom-1", "stonegate")]})
	assert_eq(r.new_state.find_province("stonegate").owned_since, 6, "a late retake waits like any capture")


func test_no_recruits_at_a_cut_off_fort_but_recruits_beside_pickets() -> void:
	# Turn 6 is being ordered; the Clans have besieged Stonegate since turn 4.
	var cut := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 2)],
		["beasts-2", CLANS, "stonegate", F.units("tuskers", 2)],
	], {"stonegate": CROWN})
	cut.current_turn = 5
	cut.find_province("stonegate").siege_since = 4
	F.rich(cut, CROWN)
	var refused := _check(cut, CROWN, RecruitOrder.new("spearmen", "stonegate"))
	assert_eq(String(refused.get("code", "")), "fort_cut_off")
	assert_true(String(refused.reason).contains("Stonegate is cut off by the Thornmane Clans' siege"), refused.reason)
	_plain(String(refused.reason), "Stonegate", "cut off")
	# Pickets: fewer than half the garrison's troops cut nothing off.
	var pickets := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 6)],
		["beasts-2", CLANS, "stonegate", F.units("tuskers", 2)],
	], {"stonegate": CROWN})
	pickets.current_turn = 5
	pickets.find_province("stonegate").siege_since = 4
	F.rich(pickets, CROWN)
	assert_true(2 < ceili(6 / 2.0), "two troops are fewer than half of six")
	assert_eq(_check(pickets, CROWN, RecruitOrder.new("spearmen", "stonegate")), {}, "recruits beside pickets")
	var r := F.resolve(pickets, {CROWN: [RecruitOrder.new("spearmen", "stonegate")]})
	assert_eq(F.events_of(r.events, "recruited").size(), 1)
	# The turn the enemy arrives, recruits already ordered there still arrive.
	var fresh := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 2)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 4)],
	], {"stonegate": CROWN, "blackwood": CLANS})
	F.rich(fresh, CROWN)
	r = F.resolve(fresh, {CROWN: [RecruitOrder.new("spearmen", "stonegate")], CLANS: [MoveOrder.new("beasts-2", "stonegate")]})
	assert_eq(F.events_of(r.events, "siege_started").size(), 1)
	assert_eq(F.events_of(r.events, "recruited").size(), 1, "the recruit ordered before the siege arrives")
	# Warband Muster can't gather in a cut-off fort either.
	assert_true(SiegeRules.is_cut_off(cut, "stonegate"))


# --- siege engines --------------------------------------------------------------------------------

func test_an_engine_joins_the_first_army_with_a_fighter_or_is_refused_at_no_cost() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 6) + ["knight_captain"]],
		["kingdom-2", CROWN, "stonegate", ["spearmen"]],
		["beasts-3", CLANS, "fangridge", ["tuskers"]],
	], {"stonegate": CROWN})
	F.rich(s, CROWN)
	var ram := String(FortData.engine_for(CROWN).id)
	var fc := Forecast.recruit_at(s, CROWN, ram, "stonegate")
	assert_true(fc.ok, fc.text)
	assert_eq(fc.joins, "kingdom-1", "the forecast names the army it joins")
	var gold := s.find_faction(CROWN).gold
	var r := F.resolve(s, {CROWN: [RecruitOrder.new(ram, "stonegate")]})
	var ns: GameState = r.new_state
	assert_eq(ns.find_army("kingdom-1").engines, 1, "it joins the first army there with a fighter")
	assert_eq(ns.find_army("kingdom-2").engines, 0)
	assert_eq(ns.find_army("kingdom-1").units.size(), 6, "an engine is never a unit")
	var ev: Dictionary = F.events_of(r.events, "recruited")[0]
	assert_eq(int(ev.numbers.cost), RulerRules.recruit_price(s, CROWN, SiegeRules.engine_type(CROWN)))
	assert_true(String(ev.text).contains("1 Siege Ram"), ev.text)
	var income := int(F.events_of(r.events, "income").filter(func(e): return e.factions[0] == CROWN)[0].numbers.income)
	assert_eq(ns.find_faction(CROWN).gold, gold - int(FortData.engine_for(CROWN).cost) + income)
	# No army there: refused at no cost, with the reason.
	var bare := F.state([["kingdom-1", CROWN, "crownkeep", ["spearmen"]], ["beasts-3", CLANS, "fangridge", ["tuskers"]]],
		{"stonegate": CROWN})
	F.rich(bare, CROWN)
	var refused := _check(bare, CROWN, RecruitOrder.new(ram, "stonegate"))
	assert_eq(String(refused.get("code", "")), "engine_no_army")
	_plain(String(refused.reason), "Stonegate", "no army to carry it")
	gold = bare.find_faction(CROWN).gold
	r = F.resolve(bare, {CROWN: [RecruitOrder.new(ram, "stonegate")]})
	income = int(F.events_of(r.events, "income").filter(func(e): return e.factions[0] == CROWN)[0].numbers.income)
	assert_eq(r.new_state.find_faction(CROWN).gold, gold + income, "no gold spent")
	assert_eq(F.events_of(r.events, "order_rejected").filter(func(e): return e.cause == "engine_no_army").size(), 1)
	# A troop recruited there earlier in the list forms an army to carry it.
	assert_eq(_check(bare, CROWN, RecruitOrder.new(ram, "stonegate"), [RecruitOrder.new("spearmen", "stonegate")]), {},
		"an army formed by a recruit ordered earlier carries it")
	r = F.resolve(bare, {CROWN: [RecruitOrder.new("spearmen", "stonegate"), RecruitOrder.new(ram, "stonegate")]})
	var formed: Array = r.new_state.armies.filter(func(a): return a.location == "stonegate")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].engines, 1)
	# At most ARMY_ENGINES_MAX ride with one army.
	var loaded := F.state([["kingdom-1", CROWN, "stonegate", F.units("spearmen", 20), FortData.ARMY_ENGINES_MAX],
		["beasts-3", CLANS, "fangridge", ["tuskers"]]], {"stonegate": CROWN})
	F.rich(loaded, CROWN)
	assert_eq(String(_check(loaded, CROWN, RecruitOrder.new(ram, "stonegate")).get("code", "")), "engine_no_army", "a full army takes no more")
	# Engines can't be recruited with the ruler, and never without sieges.
	assert_eq(String(_check(GameState.new(3), CROWN, RecruitOrder.new(ram)).get("code", "")), "unknown_unit_type")


func test_an_engine_is_lost_with_its_army() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "westwatch", ["spearmen"], 2],
		["beasts-2", CLANS, "stonegate", F.units("war_bear", 3)],
	], {"westwatch": CROWN, "stonegate": CLANS})
	var r := F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "westwatch")]}, true)
	var ns: GameState = r.new_state
	assert_eq(F.events_of(r.events, "battle").size(), 1, "no fort at Westwatch: a battle")
	assert_eq(ns.find_army("kingdom-1"), null, "the army lost the battle")
	var engines := 0
	for a in ns.armies:
		engines += a.engines
	assert_eq(engines, 0, "its engines went with it")
	# Engines never take part in a battle: the battle's sides list only fighters.
	var report: Dictionary = F.events_of(r.events, "battle")[0].numbers.report
	for side in report.sides:
		if side.faction == CROWN:
			assert_eq(int(side.fighters_start), 1, "one Spearmen fought; the engines did not")
