extends "res://tests/test_case.gd"
## #184 acceptance, tests/test_ai_temperament.gd: the computer's temperament, its style on screen.
##   * The roll: AIPlayer.choose_temperament is a pure function of the seed and the seat on a stream of its own, near
##     AGGRESSIVE_SHARE; AISeat.temperaments_for rolls one for each computer seat, as the new game screen and Quick start
##     put it in a game's config ("temperaments").
##   * Off unless the game asks: a game started without temperaments (every config from before #184, the CW-0 gate's
##     included) plays "normal" in every seat, and a steady temperament's game is the same game, record and dice, as one
##     started without it. The session keeps and records only a style other than Steady, and a save brings it back.
##   * The aggressive rules: storms, sieges, sallies and attacks at RISK_DISCOUNT worse odds, the stand-off at
##     AGGRESSIVE_STANDOFF of the pile (and its notes), and the main army going around a fort it won't attack. Every threshold
##     comes from AIPlayer and AISieges, every odds from Forecast (the real battle rules), and each position on the edge is
##     found by scanning army sizes.
##   * The screens: the new game screen, the opponent plaque, the codex and the load screen say which style the computer
##     plays and what it means, in words read from TEMPERAMENT_HELP.

const F := preload("res://tests/siege_fixtures.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const SiegeMatrix := preload("res://tools/autoplay/siege_matrix.gd")
const Gate := preload("res://tools/cw0_gate.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 4242
const SAVED_AT := 1790000000


func _brain(temperament: String) -> AIPlayer:
	var ai := AIPlayer.new()
	ai.set_temperament(temperament)
	return ai


func _plan(s: GameState, fid: String, temperament: String, rng_seed: int = 7) -> Array:
	return _brain(temperament).plan_orders(s, fid, SeededRNG.new(rng_seed), "normal")


func _storms(orders: Array, pid: String) -> Array:
	return orders.filter(func(o): return o is SiegeOrder and o.is_storm() and o.province == pid)


func _into(orders: Array, army_id: String, pid: String) -> bool:
	return not orders.filter(func(o): return o is MoveOrder and o.army_id == army_id and o.to == pid).is_empty()


func _assert_legal(s: GameState, fid: String, orders: Array, what: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(s, fid, o), "", "%s: %s is legal" % [what, o.describe()])


func _texts(orders: Array) -> Array:
	return orders.map(func(o): return JSON.stringify(o.to_dict()))


## A tooltip's words on one line (TooltipText wraps them).
func _flat(text: String) -> String:
	return " ".join(text.split("\n", false))


## Seed `game_seed` with every default system, the computer in both seats (watch mode) with the builds the build screen
## gives them, and `temperaments` as the config's (none: a config from before #184).
func _watch_config(game_seed: int, temperaments = null) -> Dictionary:
	var config := {"players": [CROWN, CLANS], "seed": game_seed, "ai": {CROWN: "normal", CLANS: "normal"}}
	config.merge(NewGameScreen.default_systems())
	config["builds"] = {CROWN: BuildScreen.computer_build(CROWN, game_seed, 0), CLANS: BuildScreen.computer_build(CLANS, game_seed, 1)}
	if temperaments != null:
		config["temperaments"] = temperaments
	return config


## The session GameScreen.start_game makes of `config`, and its AISeat.
func _start(config: Dictionary) -> Array:
	var session := GameSession.new(GameScreen.starting_state(config), config.players, config.seed, AutoBattleResolver.new(),
		config.get("ai", {}), config.get("temperaments", {}))
	assert_eq(session.setup_errors(), [], "the game starts")
	return [session, AISeat.new(session, config.seed)]


## `turns` turns of the computer playing every seat: the record's JSON and each turn's dice.
func _play(session: GameSession, computer: AISeat, turns: int) -> Dictionary:
	var dice := [JSON.stringify(computer.rng_state())]
	while not session.is_over() and session.turns_played() < turns:
		computer.play(session)
		dice.append(JSON.stringify(computer.rng_state()))
	return {"record": JSON.stringify(session.record()), "dice": dice, "refused": computer.rejections().size()}


# --- the roll ---------------------------------------------------------------------------------------

func test_the_roll_is_a_pure_function_of_the_seed_and_seat_near_its_share() -> void:
	var aggressive := [0, 0]
	var n := 200
	for game_seed in range(1, n + 1):
		for seat in 2:
			var t := AIPlayer.choose_temperament(game_seed, seat)
			assert_true(AIPlayer.TEMPERAMENTS.has(t), "a known temperament: %s" % t)
			assert_eq(AIPlayer.choose_temperament(game_seed, seat), t, "seed %d seat %d rolls the same again" % [game_seed, seat])
			if t == "aggressive":
				aggressive[seat] += 1
	# Each seat's share within three standard deviations of AGGRESSIVE_SHARE.
	var sd := sqrt(AIPlayer.AGGRESSIVE_SHARE * (1.0 - AIPlayer.AGGRESSIVE_SHARE) / float(n))
	for seat in 2:
		var share := float(aggressive[seat]) / float(n)
		assert_true(absf(share - AIPlayer.AGGRESSIVE_SHARE) <= 3.0 * sd, "seat %d: aggressive share %.3f near %.2f" % [seat + 1, share, AIPlayer.AGGRESSIVE_SHARE])


func test_the_roll_draws_nothing_from_the_seats_dice() -> void:
	for game_seed in [3, 8, 21, 55]:
		for seat in 2:
			var dice := SeededRNG.new(AISeat.seat_seed(game_seed, seat))
			var before := dice.to_dict()
			AIPlayer.choose_temperament(game_seed, seat)
			assert_eq(dice.to_dict(), before, "seed %d seat %d: its own stream (TEMPERAMENT_SALT)" % [game_seed, seat + 1])
			assert_ne(AIPlayer.TEMPERAMENT_SALT, AIPaths.BRANCH_SALT, "not the fork's stream either")


func test_each_computer_seat_rolls_by_its_place() -> void:
	for game_seed in [5, 77, 4242]:
		assert_eq(AISeat.temperaments_for([CROWN, CLANS], {CLANS: "normal"}, game_seed), {CLANS: AIPlayer.choose_temperament(game_seed, 1)})
		assert_eq(AISeat.temperaments_for([CLANS, CROWN], {CLANS: "easy"}, game_seed), {CLANS: AIPlayer.choose_temperament(game_seed, 0)},
			"the seat, not the faction, rolls")
		assert_eq(AISeat.temperaments_for([CROWN, CLANS], {CROWN: "normal", CLANS: "normal"}, game_seed),
			{CROWN: AIPlayer.choose_temperament(game_seed, 0), CLANS: AIPlayer.choose_temperament(game_seed, 1)})
		assert_eq(AISeat.temperaments_for([CROWN, CLANS], {}, game_seed), {}, "people have no style")


func test_the_session_knows_the_temperaments_the_computer_knows() -> void:
	assert_eq(GameSession.COMPUTER_TEMPERAMENTS, AIPlayer.TEMPERAMENTS)
	assert_eq(AIPlayer.TEMPERAMENTS[0], "normal", "the first is everyone's unless a game says otherwise")
	for t in AIPlayer.TEMPERAMENTS:
		assert_true(AIPlayer.TEMPERAMENT_NAMES.has(t) and AIPlayer.TEMPERAMENT_HELP.has(t), "%s has a name and its words" % t)


func test_an_unknown_temperament_plays_normal_and_normal_plays_as_before() -> void:
	var ai := AIPlayer.new()
	assert_eq(ai.temperament(), "normal", "the default")
	ai.set_temperament("berserk")
	assert_eq(ai.temperament(), "normal")
	for game_seed in [4, 9]:
		var s := GameState.with_sieges(game_seed)
		for fid in [CROWN, CLANS]:
			var plain := AIPlayer.new().plan_orders(s, fid, SeededRNG.new(game_seed), "normal")
			assert_eq(_texts(_plan(s, fid, "normal", game_seed)), _texts(plain), "seed %d %s: set to normal changes nothing" % [game_seed, fid])


# --- off unless the game asks -----------------------------------------------------------------------

func test_a_game_without_temperaments_plays_steady_in_every_seat() -> void:
	var g := _start(_watch_config(SEED))
	var session: GameSession = g[0]
	var computer: AISeat = g[1]
	assert_eq(session.computer_temperaments(), {})
	for fid in [CROWN, CLANS]:
		assert_eq(session.computer_temperament(fid), "normal")
		assert_eq(computer.temperament(fid), "normal", "%s's brain plays steady" % fid)
	var hotseat := GameSession.new(GameState.new(5), [CROWN, CLANS], 5, AutoBattleResolver.new())
	assert_eq(hotseat.computer_temperament(CROWN), "", "a person's seat has no temperament")
	assert_eq(AISeat.new(hotseat, 5).temperament(CROWN), "")


func test_a_steady_game_is_the_game_from_before_record_and_dice() -> void:
	# Every default system, then none: the computer plays both seats from the same config, once without temperaments (as
	# every game before #184) and once with both seats set to steady. Same record, same dice after every turn.
	for game_seed in [31, 32]:
		for systems in [true, false]:
			var config := _watch_config(game_seed)
			if not systems:
				config = {"players": [CROWN, CLANS], "seed": game_seed, "ai": config.ai}
			var steady := config.duplicate(true)
			steady["temperaments"] = {CROWN: "normal", CLANS: "normal"}
			var a := _start(config)
			var b := _start(steady)
			var played_a := _play(a[0], a[1], 4)
			var played_b := _play(b[0], b[1], 4)
			var what := "seed %d, %s" % [game_seed, "every system" if systems else "the basic game"]
			assert_eq(played_b.record, played_a.record, "%s: the same record" % what)
			assert_eq(played_b.dice, played_a.dice, "%s: the same dice, turn by turn" % what)
			assert_false((b[0] as GameSession).record().has("temperaments"), "%s: a steady style is not recorded" % what)


func test_the_cw0_gate_configs_ask_for_no_temperament() -> void:
	# tests/test_cw0_byte_gate.gd replays these as watch mode does; none of them names a style, so all play steady.
	var configs := Gate.configs()
	assert_true(configs.size() > 0)
	for c in configs:
		assert_false(c.has("temperaments"), "%s names no style" % c.name)
		var session := GameSession.new(GameScreen.starting_state(c), c.players, int(c.seed), AutoBattleResolver.new(), c.ai)
		assert_eq(session.computer_temperaments(), {}, "%s: every computer plays steady" % c.name)


func test_an_aggressive_seat_is_kept_recorded_and_loaded_again() -> void:
	var config := _watch_config(SEED, {CROWN: "normal", CLANS: "aggressive"})
	var g := _start(config)
	var session: GameSession = g[0]
	var computer: AISeat = g[1]
	assert_eq(session.computer_temperaments(), {CLANS: "aggressive"}, "only the style that isn't steady is kept")
	assert_eq(computer.temperament(CLANS), "aggressive")
	assert_eq(computer.temperament(CROWN), "normal")
	_play(session, computer, 3)
	assert_eq(session.record().get("temperaments"), {CLANS: "aggressive"}, "the record names it")
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.make(session, SaveGame.computer_snapshot(computer, session),
		SaveGame.MANUAL, "Temperament", SAVED_AT)))
	var restored := SaveGame.restore(save)
	assert_eq(restored.errors, [])
	if restored.session == null:
		return
	assert_eq((restored.session as GameSession).computer_temperament(CLANS), "aggressive", "the loaded game keeps it")
	assert_eq((restored.computer as AISeat).temperament(CLANS), "aggressive", "and its computer plays it")
	assert_eq(restored.config.get("temperaments"), {CLANS: "aggressive"}, "the loaded game's config names it")
	# The loaded game plays on exactly as the live one.
	_play(session, computer, 5)
	_play(restored.session, restored.computer, 5)
	assert_eq(JSON.stringify((restored.session as GameSession).record()), JSON.stringify(session.record()), "the same next turns")
	# The load screen's line says so; a steady computer's line is as before.
	var header: Dictionary = save.header
	assert_true(SaveGame.seats_text(header).contains("(Computer, Normal, %s)" % AIPlayer.temperament_name("aggressive")), SaveGame.seats_text(header))
	assert_true(SaveGame.seats_text(header).contains("Aurel Crown (Computer, Normal)"), SaveGame.seats_text(header))


func test_a_style_the_game_does_not_have_is_refused_in_words() -> void:
	var s := GameState.new(5)
	var bad := GameSession.new(s, [CROWN, CLANS], 5, AutoBattleResolver.new(), {CLANS: "normal"}, {CLANS: "berserk"})
	assert_eq(bad.phase(), GameSession.Phase.INVALID)
	assert_true(" ".join(bad.setup_errors()).contains("styles are Steady and Aggressive"), " ".join(bad.setup_errors()))
	var human := GameSession.new(s, [CROWN, CLANS], 5, AutoBattleResolver.new(), {CLANS: "normal"}, {CROWN: "aggressive"})
	assert_eq(human.phase(), GameSession.Phase.INVALID, "a person has no style")
	assert_true(" ".join(human.setup_errors()).contains("does not play"), " ".join(human.setup_errors()))


# --- the stand-off ----------------------------------------------------------------------------------

func test_the_aggressive_computer_reads_a_stand_off_at_its_share_of_the_pile() -> void:
	for sieges in [false, true]:
		var s := GameState.with_sieges(SEED) if sieges else GameState.new(SEED)
		var crown := s.find_faction(CROWN)
		var income := int(TurnResolver.income_of(s, CROWN).total)
		var need := AIPlayer.SIEGE_STANDOFF_TURNS if sieges else AIPlayer.STANDOFF_TURNS
		s.armies = s.armies.filter(func(a): return a.owner != CROWN)  # the treasury alone is the pile
		# A pile between the aggressive threshold and the steady one.
		crown.gold = ceili(need * AIPlayer.AGGRESSIVE_STANDOFF * income)
		assert_true(float(crown.gold) / float(income) < need, "sieges %s: below the steady threshold" % sieges)
		assert_eq(AIPlayer.standoff_info(s, CROWN), {}, "sieges %s: no stand-off for a steady computer" % sieges)
		assert_false(AIPlayer.standoff_info(s, CROWN, "aggressive").is_empty(), "sieges %s: a stand-off for an aggressive one" % sieges)
		crown.gold -= 1
		assert_eq(AIPlayer.standoff_info(s, CROWN, "aggressive"), {}, "sieges %s: and not below its own threshold" % sieges)


# --- sieges and storms ------------------------------------------------------------------------------

## Turn 6: the Clans have besieged the Crown's Stonegate since turn 4 with `clans`; the Crown's other armies are far away.
func _clans_besieging(clans: Array, garrison: Array) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", garrison],
		["kingdom-2", CROWN, "rivermarch", ["spearmen"]],
		["beasts-1", CLANS, "stonegate", clans],
		["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)],
	], {"stonegate": CROWN, "rivermarch": CROWN, "blackwood": CLANS, "ebonpeak": CLANS})
	s.current_turn = 5
	s.find_province("stonegate").siege_since = 4
	return s


func test_the_aggressive_computer_storms_at_the_discounted_threshold() -> void:
	var steady := AISieges.STORM_WIN
	var bold := AISieges.STORM_WIN - AIPlayer.RISK_DISCOUNT
	var in_gap := 0
	var checked := 0
	# Garrisons and besiegers of many sizes; every one whose storm odds lie near the two thresholds is planned both ways.
	for m in range(2, 9):
		for bears in range(2, 6):
			for tuskers in range(0, 7, 3):
				var s := _clans_besieging(F.units("war_bear", bears) + F.units("tuskers", tuskers), F.units("spearmen", m) + ["knight_captain"])
				var odds := float(Forecast.storm_odds(s, CLANS, "stonegate").win_rate)
				if odds < bold - 0.1 or odds >= steady + 0.1:
					continue
				var what := "%d Spearmen against %d War Bears and %d Tuskers, odds %.2f" % [m, bears, tuskers, odds]
				var normal := _plan(s, CLANS, "normal")
				var aggressive := _plan(s, CLANS, "aggressive")
				assert_eq(not _storms(normal, "stonegate").is_empty(), odds >= steady, "%s: steady storms at %.2f" % [what, steady])
				assert_eq(not _storms(aggressive, "stonegate").is_empty(), odds >= bold, "%s: aggressive storms at %.2f" % [what, bold])
				_assert_legal(s, CLANS, aggressive, what)
				checked += 1
				if odds >= bold and odds < steady:
					in_gap += 1
	assert_true(checked > 0 and in_gap > 0, "some armies sat between the two thresholds (%d checked, %d between)" % [checked, in_gap])


func _sallies(orders: Array, army_id: String) -> Array:
	return orders.filter(func(o): return o is SiegeOrder and o.is_sally() and o.army_id == army_id)


func test_the_aggressive_garrison_sallies_at_the_discounted_odds() -> void:
	# The Crown's garrison in Stonegate, besieged by the Clans with no Crown army next to it (so no relief): it sallies at
	# SIEGE_SALLY_WIN, or that less RISK_DISCOUNT when aggressive. Garrisons and besiegers of many sizes; every one whose sally
	# odds (Forecast.sally_odds, the real battle rules) lie near the two thresholds is planned both ways.
	var steady := AISieges.SIEGE_SALLY_WIN
	var bold := AISieges.SIEGE_SALLY_WIN - AIPlayer.RISK_DISCOUNT
	var in_gap := 0
	var checked := 0
	for m in range(2, 12):
		for bears in range(2, 8):
			var s := _clans_besieging(F.units("war_bear", bears), F.units("spearmen", m) + ["knight_captain"])
			var odds := float(Forecast.sally_odds(s, CROWN, ["kingdom-1"]).get("win_rate", 0.0))
			if odds < bold - 0.1 or odds >= steady + 0.1:
				continue
			var what := "%d Spearmen against %d War Bears, sally odds %.2f" % [m, bears, odds]
			var normal := _plan(s, CROWN, "normal")
			var aggressive := _plan(s, CROWN, "aggressive")
			assert_eq(not _sallies(normal, "kingdom-1").is_empty(), odds >= steady, "%s: steady sallies at %.2f" % [what, steady])
			assert_eq(not _sallies(aggressive, "kingdom-1").is_empty(), odds >= bold, "%s: aggressive sallies at %.2f" % [what, bold])
			_assert_legal(s, CROWN, aggressive, what)
			checked += 1
			if odds >= bold and odds < steady:
				in_gap += 1
	assert_true(checked > 0 and in_gap > 0, "some garrisons sat between the two thresholds (%d checked, %d between)" % [checked, in_gap])


## Turn 6: the Clans' `clans` stand at Blackwood next to the Crown's Stonegate (a keep at full walls), whose garrison is
## `garrison`; nobody else is within reach.
func _clans_next_to_a_fort(clans: Array, garrison: Array) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", garrison],
		["kingdom-2", CROWN, "crownkeep", F.units("spearmen", 6)],
		["beasts-1", CLANS, "blackwood", clans],
		["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)],
	], {"stonegate": CROWN, "blackwood": CLANS, "ebonpeak": CLANS})
	s.current_turn = 5
	return s


func test_the_aggressive_computer_begins_a_siege_at_the_discounted_odds() -> void:
	var garrison := F.units("spearmen", 6) + F.units("crossbowmen", 2) + ["knight_captain"]
	var in_gap := 0
	var seen := 0
	for n in range(2, 18):
		var s := _clans_next_to_a_fort(F.units("tuskers", n), garrison)
		if float(Forecast.storm_odds(s, CLANS, "stonegate", [MoveOrder.new("beasts-1", "stonegate")]).win_rate) >= AISieges.STORM_WIN - AIPlayer.RISK_DISCOUNT:
			continue  # a storm, not a siege: the storm test covers it
		var normal := _plan(s, CLANS, "normal")
		var aggressive := _plan(s, CLANS, "aggressive")
		var n_in := _into(normal, "beasts-1", "stonegate")
		var a_in := _into(aggressive, "beasts-1", "stonegate")
		_assert_legal(s, CLANS, aggressive, "%d Tuskers" % n)
		seen += 1
		assert_true(a_in or not n_in, "%d Tuskers: whatever a steady computer besieges, an aggressive one does too" % n)
		if a_in and not n_in:
			in_gap += 1
	assert_true(seen > 0, "some armies were short of a storm")
	assert_true(in_gap > 0, "some army besieged only when aggressive")


# --- battles in the field ---------------------------------------------------------------------------

func test_the_aggressive_computer_attacks_an_army_at_the_discounted_odds() -> void:
	# No sieges: the Clans' army at Blackwood next to a Crown army at Stonegate, far from either capital, with no gold banked.
	var in_gap := 0
	var checked := 0
	for m in range(3, 9):
		for n in range(3, 12):
			var s := GameState.new(SEED)
			s.armies.clear()
			s.armies.append(F.army(s, ["kingdom-1", CROWN, "stonegate", F.units("spearmen", m) + ["knight_captain"]]))
			s.armies.append(F.army(s, ["kingdom-2", CROWN, "crownkeep", F.units("spearmen", 8)]))
			s.armies.append(F.army(s, ["beasts-1", CLANS, "blackwood", F.units("tuskers", n)]))
			s.armies.append(F.army(s, ["beasts-2", CLANS, "fangridge", F.units("tuskers", 2)]))
			s.find_faction(CLANS).gold = 0
			s.current_turn = 5
			var odds := float(Forecast.battle_odds(s, CLANS, ["beasts-1"], "stonegate").get("win_rate", 0.0))
			# The odds each temperament needs here: its stand-off (AGGRESSIVE_STANDOFF) makes it STANDOFF_WIN, else LIKELY_WIN.
			var need_n := AIPlayer.STANDOFF_WIN if not AIPlayer.standoff_info(s, CLANS).is_empty() else AIPlayer.LIKELY_WIN
			var need_a := (AIPlayer.STANDOFF_WIN if not AIPlayer.standoff_info(s, CLANS, "aggressive").is_empty() else AIPlayer.LIKELY_WIN) - AIPlayer.RISK_DISCOUNT
			if odds < need_a - 0.1 or odds >= need_n + 0.1:
				continue
			var what := "%d Spearmen against %d Tuskers, odds %.2f" % [m, n, odds]
			var n_in := _into(_plan(s, CLANS, "normal"), "beasts-1", "stonegate")
			var aggressive := _plan(s, CLANS, "aggressive")
			var a_in := _into(aggressive, "beasts-1", "stonegate")
			_assert_legal(s, CLANS, aggressive, what)
			assert_eq(n_in, odds >= need_n, "%s: steady attacks at %.2f" % [what, need_n])
			assert_eq(a_in, odds >= need_a, "%s: aggressive attacks at %.2f" % [what, need_a])
			checked += 1
			if a_in and not n_in:
				in_gap += 1
	assert_true(checked > 0 and in_gap > 0, "some fight was taken only when aggressive (%d checked, %d only aggressive)" % [checked, in_gap])


# --- going around -----------------------------------------------------------------------------------

func test_the_aggressive_main_army_goes_around_a_guarded_road() -> void:
	# The Clans hold the map but the Crown's capital and the three provinces around it, which a big garrison guards; Deepwood,
	# off the road, is nobody's. The Clans' army at Thornvale can't step next to Crownkeep safely: a steady computer masses
	# there, an aggressive one goes around toward Deepwood.
	for n in range(4, 20, 4):
		var s := GameState.with_sieges(SEED)
		s.armies = s.armies.filter(func(a): return a.owner == CROWN and a.ruler != null)
		s.armies.append(F.army(s, ["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 14) + F.units("crossbowmen", 6) + ["knight_captain"]]))
		s.armies.append(F.army(s, ["beasts-1", CLANS, "thornvale", F.units("tuskers", n)]))
		s.armies.append(F.army(s, ["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)]))
		for p in s.provinces:
			p.owner = CLANS
		for pid in ["crownkeep", "westwatch", "rivermarch", "highcrag"]:
			s.find_province(pid).owner = CROWN
		s.find_province("deepwood").owner = ""
		s.find_faction(CLANS).gold = 0
		s.current_turn = 5
		var steady := AIPlayer.new()
		var normal := steady.plan_orders(s, CLANS, SeededRNG.new(7), "normal")
		var bold := _brain("aggressive")
		var aggressive := bold.plan_orders(s, CLANS, SeededRNG.new(7), "normal")
		_assert_legal(s, CLANS, aggressive, "%d Tuskers" % n)
		var held := normal.filter(func(o): return o is MoveOrder and o.army_id == "beasts-1")
		var moved := aggressive.filter(func(o): return o is MoveOrder and o.army_id == "beasts-1")
		assert_eq(held, [], "%d Tuskers: a steady computer masses at Thornvale" % n)
		assert_eq(moved.size(), 1, "%d Tuskers: an aggressive one moves" % n)
		if moved.size() == 1:
			var d_before := _dist(s, "thornvale", "deepwood")
			assert_eq(_dist(s, String(moved[0].to), "deepwood"), d_before - 1, "%d Tuskers: one step toward Deepwood (%s)" % [n, moved[0].to])
			assert_true(d_before <= AIPlayer.MASS_REACH, "Deepwood is within MASS_REACH of Thornvale")
		assert_false(bold.last_plan_notes().filter(func(l): return String(l).begins_with("Going around Crownkeep")).is_empty(), "%d Tuskers: the note says so" % n)


func _dist(s: GameState, a: String, b: String) -> int:
	var seen := {a: 0}
	var queue := [a]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for nb in s.find_province(at).neighbors:
			if not seen.has(nb):
				seen[nb] = int(seen[at]) + 1
				queue.append(nb)
	return int(seen.get(b, 99))


# --- notes and the autoplay -------------------------------------------------------------------------

func test_the_aggressive_computer_says_how_it_plays_on_the_first_turn() -> void:
	var s := GameState.with_sieges(SEED)
	var ai := _brain("aggressive")
	ai.plan_orders(s, CLANS, SeededRNG.new(1), "normal")
	var line: Array = ai.last_plan_notes().filter(func(l): return String(l).contains("plays aggressively"))
	assert_eq(line.size(), 1, "one line says so")
	assert_true(String(line[0]).contains(AIPlayer.temperament_help("aggressive")), String(line[0]))
	var steady := AIPlayer.new()
	steady.plan_orders(s, CLANS, SeededRNG.new(1), "normal")
	assert_true(steady.last_plan_notes().filter(func(l): return String(l).contains("aggressive")).is_empty(), "a steady one says nothing new")


## A game with sieges where the Clans' garrison at Fangridge could hunt a small Crown army two moves away at Deepwood, the
## Clans' pile (units at recruit price, plus `gold`) worth `turns` turns of their income (`gold` is set to make it so).
func _clans_could_hunt(turns: float) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "deepwood", ["spearmen"]],
		["kingdom-2", CROWN, "crownkeep", F.units("spearmen", 4)],
		["beasts-1", CLANS, "fangridge", F.units("tuskers", 4)],
	], {}, SEED)
	var clans := s.find_faction(CLANS)
	clans.gold = 100000
	var value := int(AIPlayer.standoff_info(s, CLANS).get("value", 0))
	var income := int(TurnResolver.income_of(s, CLANS).total)
	clans.gold = maxi(0, ceili(turns * income) - value)
	s.current_turn = 5
	return s


func _hunt_line(s: GameState, temperament: String) -> String:
	var ai := _brain(temperament)
	ai.plan_orders(s, CLANS, SeededRNG.new(7), "normal")
	for l in ai.last_plan_notes():
		if String(l).contains("marches out of Fangridge") or String(l).contains("march out of Fangridge"):
			return String(l)
	return ""


func test_an_early_stand_off_is_called_pressing_on_and_a_long_one_breaking_it() -> void:
	# An aggressive computer reads its stand-off at AGGRESSIVE_STANDOFF of the pile, so in a game with sieges from its first
	# turns: its note then says it presses on, and only a pile a steady computer would call a stand-off is "built up while
	# both sides waited".
	var early := _clans_could_hunt(AIPlayer.SIEGE_STANDOFF_TURNS * AIPlayer.AGGRESSIVE_STANDOFF)
	assert_true(AIPlayer.standoff_info(early, CLANS).is_empty() and not AIPlayer.standoff_info(early, CLANS, "aggressive").is_empty(),
		"the pile lies between the two thresholds")
	var pressing := _hunt_line(early, "aggressive")
	assert_true(pressing.begins_with("Pressing on, as an aggressive computer does: what we field is worth"), pressing)
	assert_false(pressing.contains("while both sides waited"), pressing)
	assert_eq(_hunt_line(early, "normal"), "", "a steady computer is in no stand-off yet, and keeps its garrison")
	var long := _clans_could_hunt(AIPlayer.SIEGE_STANDOFF_TURNS)
	assert_false(AIPlayer.standoff_info(long, CLANS).is_empty(), "a stand-off for both")
	for t in AIPlayer.TEMPERAMENTS:
		var line := _hunt_line(long, t)
		assert_true(line.begins_with("Breaking the stand-off: what we have built up while both sides waited is worth"), "%s: %s" % [t, line])


func test_the_autoplay_plays_each_temperament() -> void:
	assert_eq(SiegeMatrix.temperament_policies(["ai", "ai"], ""), ["ai", "ai"])
	assert_eq(SiegeMatrix.temperament_policies(["ai", "ai"], "aggressive"), ["ai_aggressive", "ai_aggressive"])
	assert_eq(SiegeMatrix.temperament_policies(["ai", "ai"], "mixed"), ["ai_aggressive", "ai"])
	assert_eq(SiegeMatrix.temperament_policies(["turtle", "ai"], "roll"), ["turtle", "ai_roll"])
	assert_eq(Policies.make("ai").ai.temperament(), "normal", "plain ai keeps its games")
	assert_eq(Policies.make("ai_aggressive").ai.temperament(), "aggressive")
	for game_seed in [2, 6]:
		for seat in 2:
			var p = Policies.make("ai_roll")
			p.configure(game_seed, seat)
			assert_eq(p.ai.temperament(), AIPlayer.choose_temperament(game_seed, seat), "ai_roll rolls as an AI seat does")


# --- the screens ------------------------------------------------------------------------------------

func test_the_names_and_help_read_from_the_numbers() -> void:
	assert_eq(AIPlayer.temperament_name("aggressive"), "Aggressive")
	assert_eq(AIPlayer.temperament_name("normal"), "Steady")
	assert_true(AIPlayer.temperament_help("aggressive").contains("%d points" % AIPlayer.RISK_DISCOUNT_POINTS))
	assert_eq(AIPlayer.RISK_DISCOUNT, AIPlayer.RISK_DISCOUNT_POINTS / 100.0, "the points are the discount")
	assert_eq(AIPlayer.AGGRESSIVE_HELP.contains("twice as fast"), is_equal_approx(AIPlayer.AGGRESSIVE_STANDOFF, 0.5),
		"\"twice as fast\" is AGGRESSIVE_STANDOFF's half of the pile")
	assert_eq(AIPlayer.temperament_line("aggressive"), "Style: Aggressive. %s" % AIPlayer.temperament_help("aggressive"))
	assert_true(AISeat.tag_help("the Crown", "normal", "aggressive").contains(AIPlayer.temperament_line("aggressive")), "the seat's tooltip names it")
	assert_false(AISeat.tag_help("the Crown", "normal").contains("Style"), "and says nothing without one, as before")


func test_the_codex_explains_both_styles() -> void:
	var text := RulesCodex.text("computer_opponent")
	for t in AIPlayer.TEMPERAMENTS:
		assert_true(text.contains("%s: %s" % [AIPlayer.temperament_name(t), AIPlayer.temperament_help(t)]), "the codex explains %s" % t)


func test_the_new_game_screen_shows_each_computers_style_and_starts_with_it() -> void:
	var screen := NewGameScreen.new()
	screen.set_seats([CROWN, CLANS])
	screen.set_seat_kind(1, "human")
	screen.set_seat_kind(2, "computer")
	var seen := {}
	for game_seed in [11, 12, 13, 14, 15, 16, 17, 18]:
		screen.set_seed(game_seed)
		var want := AIPlayer.choose_temperament(game_seed, 1)
		seen[want] = true
		var label := screen.faction_labels[1]
		assert_true(label.text.contains("from the seed: %s." % AIPlayer.temperament_name(want)), label.text)
		assert_true(_flat(label.tooltip_text).contains(AIPlayer.temperament_line(want)), "seed %d: the tooltip says what it means" % game_seed)
		assert_false(screen.faction_labels[0].text.contains("style"), "the person's seat has no style")
		assert_eq(screen.config().get("temperaments"), {CLANS: want}, "seed %d: the game starts with the style shown" % game_seed)
	assert_eq(seen.size(), AIPlayer.TEMPERAMENTS.size(), "both styles come up")
	screen.set_seat_kind(1, "computer")
	assert_eq(screen.config().temperaments, AISeat.temperaments_for([CROWN, CLANS], {CROWN: "normal", CLANS: "normal"}, screen.config().seed),
		"watching: each computer has its own")
	screen.set_seat_kind(1, "human")
	screen.set_seat_kind(2, "human")
	assert_false(screen.config().has("temperaments"), "a hotseat config names no style")
	screen.free()


func test_quick_start_gives_the_computer_the_style_its_seat_rolls() -> void:
	for dice_seed in range(1, 9):
		var rng := RandomNumberGenerator.new()
		rng.seed = dice_seed
		var cfg := NewGameScreen.quick_start_config(rng)
		var computer: String = cfg.players[1]
		assert_eq(cfg.temperaments, {computer: AIPlayer.choose_temperament(cfg.seed, 1)}, "dice %d" % dice_seed)


func test_the_game_screen_plays_and_shows_the_style() -> void:
	for want in AIPlayer.TEMPERAMENTS:
		var game := load(GAME_SCENE).instantiate() as GameScreen
		game.start_game({"players": [CROWN, CLANS], "seed": SEED, "ai": {CLANS: "normal"}, "temperaments": {CLANS: want}})
		assert_eq(game.session.computer_temperament(CLANS), want, "the session has it")
		assert_eq(game.computer.temperament(CLANS), want, "the computer plays it")
		var names := game.opponent_box.find_children("OpponentName", "Label", true, false)
		assert_eq(names.size(), 1)
		if names.size() == 1:
			assert_true(_flat((names[0] as Label).tooltip_text).contains(AIPlayer.temperament_line(want)), (names[0] as Label).tooltip_text)
		var tags := game.opponent_box.find_children("ComputerTag", "Label", true, false)
		assert_eq(tags.size(), 1)
		if tags.size() == 1:
			assert_true(_flat((tags[0] as Label).tooltip_text).contains(AIPlayer.temperament_line(want)), "the tag's tooltip too")
		game.free()
