extends "res://tests/test_case.gd"
## CW-2 (#253, design/CANDLEWAKE.md §2.5): every part of Wick explains itself in the same PR. The army card's line
## (WickRules.flame_text), the orders forecast's line on every move (and Forecast.wick for every army), the recruit forecast's
## cooling, the muster forecast's lower flame, the battle's "why" ("Wick: +1 attack (flame 2)"), and the codex entries the
## events and factors link. A Crown army's forecasts say nothing about flame.

const CROWN := "kingdom"
const WAKE := "candlewake"


func _game() -> GameState:
	var errors := []
	var s := GameState.create(29, [CROWN, WAKE], {}, {}, errors)
	assert_eq(errors, [])
	return s


func _field(s: GameState) -> String:
	for pid in s.find_province(s.find_faction(WAKE).capital).neighbors:
		if not s.find_province(pid).has_fort:
			return pid
	return ""


func test_the_army_card_says_what_its_flame_does() -> void:
	var s := _game()
	var a := s.find_army("candlewake-1")
	for flame in range(0, WickRules.cap(s, WAKE) + 1):
		a.flame = flame
		var text := WickRules.flame_text(s, a)
		assert_true(text.begins_with("Flame %d: its regulars fight at %s attack." % [flame, "%+d" % (flame - 1) if flame != 1 else "+0"]), text)
		assert_eq(text.contains("guttering"), flame == 0, "flame %d: guttering said only at 0" % flame)
		assert_eq(text.contains("drops to %d" % (flame - 1)), flame > 0, "flame %d: what idling costs" % flame)
		assert_eq(text.contains("raises it to %d" % (flame + 1)), flame < WickRules.cap(s, WAKE), "flame %d: what a win gives" % flame)
	assert_eq(WickRules.flame_text(s, s.find_army("kingdom-1")), "", "a Crown army has no flame to explain")


func test_a_move_forecasts_the_flame_it_ends_the_turn_with() -> void:
	var s := _game()
	var a := s.find_army("candlewake-1")
	a.flame = 2
	var field := _field(s)
	var out := Forecast.move(s, WAKE, MoveOrder.new(a.id, field))
	assert_true(out.ok, out.text)
	assert_true(String(out.text).contains("flame 2 → 3 if it wins; → 1 if it fights no battle"), out.text)
	assert_true(String(out.text).contains("is not a harbour"), out.text)
	# Staying home: the capital's fort is a harbour.
	var lines := Forecast.wick(s, WAKE)
	assert_eq(lines.size(), s.armies.filter(func(x): return x.owner == WAKE and x.flame >= 0).size(), "a line for every army with a flame")
	assert_true(String(lines[0].text).contains("→ 2 if it fights no battle") and String(lines[0].text).contains("is a harbour"), lines[0].text)
	var crown := Forecast.move(s, CROWN, MoveOrder.new("kingdom-1", s.find_province("crownkeep").neighbors[0]))
	assert_false(String(crown.text).contains("flame"), "a Crown move says nothing of flame")
	assert_eq(Forecast.wick(s, CROWN), [])


func test_the_recruit_forecast_says_joining_cools_and_a_new_army_starts_at_the_start_flame() -> void:
	var s := _game()
	var a := s.find_army("candlewake-1")
	a.flame = 3
	var start := WickRules.start_flame(s, WAKE)
	var joins := Forecast.recruit_at(s, WAKE, "wickwardens")
	assert_true(String(joins.text).contains("Joining the Candlewake's 1st cools it from flame 3 to %d." % start), joins.text)
	a.location = _field(s)  # nobody at the capital: the recruits form a new army
	var fresh := Forecast.recruit_at(s, WAKE, "wickwardens")
	assert_true(String(fresh.text).contains("A new army starts at flame %d." % start), fresh.text)
	var cmd := Forecast.recruit_at(_game(), WAKE, "lamplighter")
	assert_false(String(cmd.text).contains("flame"), "a commander cools nothing: %s" % cmd.text)


func test_the_muster_forecast_says_a_merge_takes_the_lower_flame() -> void:
	var s := _game()
	var hot := s.find_army("candlewake-1")
	hot.flame = 3
	var cool := Army.new()
	cool.id = s.new_army_id(WAKE)
	cool.owner = WAKE
	cool.location = hot.location
	cool.units.append(Unit.new(s.find_faction(WAKE).unit_types[0], WAKE))
	cool.flame = 1
	s.armies.append(cool)
	var f := MusterForecast.of(s, WAKE, MusterOrder.merge(cool.id, hot.id))
	assert_true(f.ok, String(f.get("reason", "")))
	assert_true(String(f.text).contains("flame falls from 3 to 1: a merge takes the lower flame."), f.text)


func test_the_battle_why_names_wick() -> void:
	var s := _game()
	var wake := Army.new()
	wake.id = s.new_army_id(WAKE)
	wake.owner = WAKE
	wake.location = "thornvale"
	for i in 6:
		wake.units.append(Unit.new(s.find_faction(WAKE).unit_types[0], WAKE))
	wake.flame = 3
	var foe := Army.new()
	foe.id = s.new_army_id(CROWN)
	foe.owner = CROWN
	foe.location = "thornvale"
	for i in 3:
		foe.units.append(Unit.new(s.find_faction(CROWN).unit_types[0], CROWN))
	var r := AutoBattleResolver.resolve(wake, foe, s.find_province("thornvale"), SeededRNG.new(4), s)
	var found := false
	for fct in r.report.all_factors:
		if String(fct.id) == AutoBattleResolver.FLAME:
			found = true
			assert_eq(String(fct.brief), "Wick: +2 attack (flame 3)")
			assert_eq(String(fct.get("codex", "")), "wick")
	assert_true(found, "the why counts the flame")


func test_the_why_panel_names_a_siphon_heal() -> void:
	var s := _game()
	var heals := {}
	for game_seed in 24:
		var wake := Army.new()
		wake.id = s.new_army_id(WAKE)
		wake.owner = WAKE
		wake.location = "thornvale"
		for i in 3:
			wake.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(WAKE), "gleaners"), WAKE))
		wake.flame = 1
		var foe := Army.new()
		foe.id = s.new_army_id(CROWN)
		foe.owner = CROWN
		foe.location = "thornvale"
		for type_id in ["spearmen", "spearmen", "crossbowmen"]:
			foe.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), type_id), CROWN))
		var r := AutoBattleResolver.resolve(wake, foe, s.find_province("thornvale"), SeededRNG.new(300 + game_seed), s, true)
		var p := BattlePlayer.new(r.log, r.report)
		var why := BattleWhy.new(p)
		for k in p.beats().size() + 1:
			for f in why.at(k, p.timeline().state_at(0)).feed:
				if String(f.kind) == "heal":
					heals["%d|%d" % [game_seed, int(f.event)]] = f
	assert_false(heals.is_empty(), "the Gleaners healed")
	for f in heals.values():
		assert_true(String(f.text).ends_with("(Siphon).") and not String(f.text).contains("Lifedrinker"), f.text)
		assert_eq(String(f.codex), AutoBattleResolver.codex_id_for_trait(AutoBattleResolver.SIPHON))


func test_every_new_codex_link_exists() -> void:
	for key in ["wick", "harbour", "guttering", "ruler_half_death", "ruler_mother_tallow", "ability_harvest", "ability_vigil",
			"mandate_kindling", "mandate_tallow_levy", "unit_guttering_ram"]:
		assert_true(RulesCodex.ENTRIES.has(key), "codex %s" % key)
	for t in AutoBattleResolver.WICK_TRAITS:
		assert_true(RulesCodex.ENTRIES.has(AutoBattleResolver.codex_id_for_trait(t)), "the %s codex entry" % t)
	for type in WickRules.CODEX:
		assert_true(RulesCodex.ENTRIES.has(String(WickRules.CODEX[type])), "%s's link" % type)
	assert_true(RulesCodex.text("wick").contains("flame"), "Wick's entry explains the flame")
