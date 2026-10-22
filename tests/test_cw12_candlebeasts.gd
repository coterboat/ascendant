extends "res://tests/test_case.gd"
## CW-12 (#263, design/CANDLEWAKE.md §4.5): the candlebeasts, beasts the Wake has poured over. Wax Hounds, the Tallow Stag and the
## Guttering Bear are the roster's last three rows, each poured only in a province of the Candlewake's own that stands in Deep Wake
## (the capital from the start), with no new trait code. The gate's reason says how long until Deep Wake, the recruit list greys
## them with it, the tooltip carries the family line, and the codex has their page. Numbers come from the data and the rules.

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
const BEASTS := ["wax_hounds", "tallow_stag", "guttering_bear"]
const MAP_SCENE := "res://ui/map_screen.tscn"


func _game(flags: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.create(23, [CROWN, WAKE], flags, {}, errors)
	assert_eq(errors, [], "the game starts")
	for f in s.factions:
		f.gold = 300
	return s


func _type(s: GameState, id: String) -> UnitType:
	return TurnResolver.recruitable_type(s.find_faction(WAKE), id, s)


## A province next to the Candlewake's capital that nobody holds, now theirs with their mark held `held` turns as the land looks
## now (MarkRules.stage_now), or with no mark when `held` is -1.
func _held(s: GameState, held: int, pid: String = "") -> Province:
	if pid.is_empty():
		for n in s.find_province(s.find_faction(WAKE).capital).neighbors:
			if s.find_province(n).owner.is_empty() and s.garrison_at(n) == null and pid.is_empty():
				pid = n
	var p := s.find_province(pid)
	p.owner = WAKE
	if held < 0:
		s.marks.erase(pid)
	else:
		s.marks[pid] = {"mark": {"faction": WAKE, "since_turn": s.current_turn - held}}
	return p


func _deep_held() -> int:
	return int(MarkData.stage(WAKE, MarkData.stage_count(WAKE)).held)


func _head() -> String:
	var words: Dictionary = MarkData.row(WAKE).poured
	return "%s are poured only %s." % [words.many, words.where]


# --- the rows -----------------------------------------------------------------------------------------------------

func test_the_beasts_are_the_rosters_last_three_poured_in_deep_wake() -> void:
	var ids: Array = FactionData.row(WAKE).unit_types.map(func(u): return String(u.id))
	assert_eq(ids.slice(ids.size() - BEASTS.size()), BEASTS, "after the host, which rules read by its place")
	var s := _game()
	assert_eq(BEASTS.map(func(id): return _type(s, id).trait_id), [AutoBattleResolver.SKIRMISH, AutoBattleResolver.CHARGE,
		AutoBattleResolver.BERSERK], "no new trait code")
	for id in BEASTS:
		var ut := _type(s, id)
		assert_true(MarkRules.is_poured(ut))
		assert_eq(MarkData.stage_index(WAKE, ut.mark_stage), MarkData.stage_count(WAKE), "%s: Deep Wake, the last stage" % id)
		assert_eq(UnitType.from_dict(ut.to_dict()).mark_stage, ut.mark_stage, "%s saves and loads its stage" % id)
	for f in s.factions:
		for ut in f.unit_types:
			if not BEASTS.has(ut.id):
				assert_false(ut.to_dict().has("mark_stage"), "%s saves as before" % ut.id)
	assert_eq(String(MarkData.row(WAKE).risen.unit), "wickwardens", "the Risen raise Wickwardens, never candlebeasts")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(_type(back, "tallow_stag").mark_stage, "deep_wake", "a saved game keeps the gate")


# --- the gate -----------------------------------------------------------------------------------------------------

func test_the_capital_pours_them_from_the_start() -> void:
	var s := _game()
	var cap := s.find_faction(WAKE).capital
	assert_eq(MarkRules.stage_now(s, cap), MarkData.stage_count(WAKE), "the capital stands in Deep Wake from the start")
	for id in BEASTS:
		assert_eq(TurnResolver.check_recruit(s, WAKE, RecruitOrder.new(id), 300), {}, "%s at the capital" % id)
	var r := TurnResolver.resolve(s, {WAKE: [RecruitOrder.new("guttering_bear")]}, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state.armies.any(func(a): return a.owner == WAKE and a.location == cap and a.units.any(func(u): return u.type.id == "guttering_bear")),
		"the Guttering Bear is poured at the capital")


func test_elsewhere_the_reason_says_how_long_until_deep_wake() -> void:
	var s := _game()
	var ut := _type(s, "wax_hounds")
	var p := _held(s, -1)
	assert_eq(MarkRules.pour_reason(s, WAKE, ut, p.id), "%s %s %s." % [_head(), p.name, MarkData.row(WAKE).poured.unmarked])
	for held in [0, 1, 3, 4, 5]:
		_held(s, held, p.id)
		var stage := MarkRules.stage_now(s, p.id)
		assert_eq(MarkRules.pour_reason(s, WAKE, ut, p.id), "%s %s %s: Deep Wake in %s." % [_head(), p.name, MarkData.stage(WAKE, maxi(1, stage)).at,
			"1 turn" if _deep_held() - held == 1 else "%d turns" % (_deep_held() - held)], "held %d" % held)
		assert_eq(String(TurnResolver.check_recruit(s, WAKE, RecruitOrder.new("wax_hounds"), 300).get("code", "")), "",
			"the capital still pours, whatever the field's Wake")
	_held(s, _deep_held(), p.id)
	assert_eq(MarkRules.pour_reason(s, WAKE, ut, p.id), "", "Deep Wake pours")
	assert_eq(MarkRules.pour_reason(s, WAKE, _type(s, "wickwardens"), p.id), "", "the host has no gate")
	# A rival's province, or a cold wake of yours retaken this turn (it relights only in the wake step, after recruitment).
	p.owner = CROWN
	assert_true(MarkRules.pour_reason(s, WAKE, ut, p.id).ends_with("%s %s." % [p.name, MarkData.row(WAKE).poured.unmarked]))
	p.owner = WAKE
	s.marks[p.id] = {"scar": {"faction": WAKE, "stage": MarkData.stage_count(WAKE), "until_turn": s.current_turn + 4}}
	assert_true(MarkRules.pour_reason(s, WAKE, ut, p.id).ends_with("is a cold wake of yours: it relights at the end of this turn."))


func test_sitting_up_early_moves_the_wake_line_not_deep_wake() -> void:
	var s := AscensionRules.with_nodes(_game({"paths": true}), WAKE, ["wake_sitting_up_early"])
	var ut := _type(s, "tallow_stag")
	var line := MarkRules.threshold(s, WAKE, 2)
	assert_eq(line, int(MarkData.stage(WAKE, 2).held) - 1, "the Wake-Line a turn sooner")
	var p := _held(s, line)
	assert_eq(MarkRules.pour_reason(s, WAKE, ut, p.id), "%s %s %s: Deep Wake in %d turns." % [_head(), p.name, MarkData.stage(WAKE, 2).at,
		_deep_held() - line], "on the Wake-Line already, and Deep Wake where it was")


func test_a_fort_pours_only_in_deep_wake_and_the_forecast_greys_it() -> void:
	var s := _game({"sieges": true})
	var p := _held(s, 3)
	p.has_fort = true
	p.fort_level = 2
	p.walls = SiegeRules.walls_max(2)
	var order := RecruitOrder.new("tallow_stag", p.id)
	var check := TurnResolver.check_recruit(s, WAKE, order, 300)
	assert_eq(String(check.get("code", "")), "needs_mark_stage")
	assert_eq(String(check.get("reason", "")), MarkRules.pour_reason(s, WAKE, _type(s, "tallow_stag"), p.id))
	assert_eq(TurnResolver.check_recruit(s, WAKE, RecruitOrder.new("wickwardens", p.id), 300), {}, "the host recruits there")
	var fc := Forecast.recruit_at(s, WAKE, "tallow_stag", p.id, [])
	assert_false(bool(fc.ok), "the fort's recruit list greys it")
	assert_eq(String(fc.reason), String(check.reason), "with the rules' reason")
	_held(s, _deep_held(), p.id)
	assert_eq(TurnResolver.check_recruit(s, WAKE, order, 300), {}, "in Deep Wake the fort pours it")
	var r := TurnResolver.resolve(s, {WAKE: [order]}, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state.armies.any(func(a): return a.location == p.id and a.units.any(func(u): return u.type.id == "tallow_stag")),
		"and the order resolves into a Tallow Stag there")
	# Refused when the order is given, so it never reaches the recruitment phase.
	_held(s, 1, p.id)
	assert_false(OrderBook.check_order(s, WAKE, order, []).is_empty(), "the order book refuses it on the Wake-Line's near side")


# --- the words ----------------------------------------------------------------------------------------------------

func test_the_tooltip_carries_the_family_line_before_the_trait() -> void:
	var s := _game()
	var ut := _type(s, "guttering_bear")
	var words: Dictionary = MarkData.row(WAKE).poured
	var line := "A %s: poured in %s." % [words.one, MarkRules.stage_name(WAKE, MarkData.stage_count(WAKE))]
	assert_eq(MarkRules.family_line(ut), line)
	var desc := Breakdown.unit_type_description(ut)
	assert_true(desc.contains("%s Trait %s" % [line, ut.trait_id]), desc)
	for f in s.factions:
		for t in f.unit_types:
			if not BEASTS.has(t.id):
				assert_false(Breakdown.unit_type_description(t).contains("poured"), "%s has no family line" % t.id)


func test_the_codex_page_lists_the_forms_from_the_data() -> void:
	var entry: Dictionary = RulesCodex.ENTRIES.get(String(MarkData.row(WAKE).poured.codex), {})
	assert_false(entry.is_empty(), "the page is there")
	assert_eq(String(entry.get("faction", "")), WAKE)
	for id in BEASTS:
		var row: Dictionary = FactionData.row(WAKE).unit_types.filter(func(u): return String(u.id) == id)[0]
		assert_true(String(entry.text).contains("%s (%d hit points, attack %d, defense %d, morale %d, %d gold, %s)" % [row.name, row.hp,
			row.attack, row.defense, row.morale, row.cost, row.trait]), "%s's numbers" % id)
	assert_true(String(entry.text).contains(MarkRules.stage_name(WAKE, MarkData.stage_count(WAKE))))
	assert_false(RulesCodex.shown_for("candlebeasts", [CROWN, CLANS]), "a Crown–Clans codex doesn't list it")


func test_the_recruit_list_greys_a_beast_the_capital_cant_pour() -> void:
	var s := _game()
	var cap := s.find_faction(WAKE).capital
	s.marks[cap] = {"mark": {"faction": WAKE, "since_turn": s.current_turn - 1}}  # a fresh Wake: Sitting Up
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_state(s, WAKE)
	map.select_province(cap)
	var open := map.details.find_children("RecruitButton", "", true, false)
	assert_false(open.is_empty(), "the capital has its Recruit button")
	(open[0] as Button).button_pressed = true
	for id in BEASTS:
		var b := map.details.find_children("Recruit_%s" % id, "Button", true, false)
		assert_false(b.is_empty(), "%s is listed" % id)
		if not b.is_empty():
			assert_true((b[0] as Button).disabled, "%s is greyed" % id)
			var why := TooltipText.plain("Can't recruit %s here" % _type(s, id).name, MarkRules.pour_reason(s, WAKE, _type(s, id), cap))
			assert_true((b[0] as Button).tooltip_text.begins_with(why), "with the reason on hover")
		assert_false(map.details.find_children("RecruitReason_%s" % id, "", true, false).is_empty(), "and under it")
	var plain := map.details.find_children("Recruit_wickwardens", "Button", true, false)
	assert_false(plain.is_empty() or (plain[0] as Button).disabled, "the host isn't")
	map.free()


# --- in battle, and the computer ------------------------------------------------------------------------------------

func test_candlebeasts_burn_and_gutter_as_regulars() -> void:
	var s := _game()
	var field := _held(s, -1).id
	var a := Army.new()
	a.id = s.new_army_id(WAKE)
	a.owner = WAKE
	a.location = field
	for id in BEASTS:
		a.units.append(Unit.new(_type(s, id), WAKE))
	WickRules.light(s, a)
	a.flame = WickRules.base_cap(WAKE)
	s.armies.append(a)
	var foe := Army.new()
	foe.id = s.new_army_id(CROWN)
	foe.owner = CROWN
	foe.location = field
	foe.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen", s), CROWN))
	var r := AutoBattleResolver.resolve(a, foe, s.find_province(field), SeededRNG.new(3), s, true)
	var wake := -1
	for sd in r.log.sides:
		if String(sd.faction) == WAKE:
			wake = int(sd.index)
	var seen := 0
	for e in r.log.events:
		if String(e.t) == "attack" and int(r.log.fighters[int(e.by)].side) == wake:
			seen += 1
			assert_eq(int(e.attack.parts.get(AutoBattleResolver.FLAME, 0)), WickRules.base_cap(WAKE) - 1, "a beast fights at flame - 1")
	assert_true(seen > 0, "the beasts attacked")
	# Guttering: at flame 0 every beast loses its hit points in the Wick step, as the host does.
	a.flame = 0
	s.armies.erase(foe)
	var t := TurnResolver.resolve(s, {}, TurnResolver.seed_for_turn(s))
	assert_true(t.events.any(func(e): return String(e.type) == "guttered" and String(e.numbers.army) == a.id), "they gutter")


func test_the_computer_never_orders_a_beast_it_cant_pour() -> void:
	for flags in [{}, {"sieges": true, "independents": true}]:
		var start := _game(flags)
		start.marks[start.find_faction(WAKE).capital] = {"mark": {"faction": WAKE, "since_turn": start.current_turn - 1}}
		var session := GameSession.new(start, [WAKE, CROWN], 9, AutoBattleResolver.new(), {WAKE: "normal", CROWN: "normal"})
		var computer := AISeat.new(session, 9)
		var rejected := []
		while not session.is_over() and session.turns_played() < 4:
			var before := session.turns_played()
			computer.play(session)
			if session.turns_played() == before:
				break
			for e in session.turn_report().get("events", []):
				if String(e.type) == "order_rejected" and String(e.get("numbers", {}).get("code", "")) == "needs_mark_stage":
					rejected.append(e.text)
		assert_eq(rejected, [], "%s: no candlebeast ordered where it can't be poured" % [flags.keys()])
		assert_eq(computer.rejections(), [], "%s: every order the computer gave was accepted" % [flags.keys()])
