extends "res://tests/test_case.gd"
## M5-10 (#121) acceptance, the computer with magic (design/M5_MAGIC_FOG.md §10.2, §18). What is proved:
##   1. The research plan: the aligned school's tier I after the first ordinary node, the rest of the arcana in the order of
##      §10.2, every step legal, and a game that follows it; with magic off the plan is the M4 one.
##   2. Mages as recruits: valued by their spells (the rules' own numbers), at most one for every AIMagic.MAGE_PER regular units, never
##      more second-rank fighters than front-rank ones.
##   3. Every ritual rule fires on a constructed board, ward ahead and the read capital included, and does not fire when its
##      condition fails; the gold share, the crisis, the pack's size, Bastion's cap, Tithe of Blood's payments and the
##      sacrifice pick.
##   4. It pins only armies that hold, and never an army ordered to attack.
##   5. 30 turns of a person against the computer with magic (with and without fog, both levels) give zero rejections, and the
##      same seed gives the same research, rituals and orders; computer against computer finishes its games.
##   6. With magic off, games are the games of main; under fog the magic plan reads only the view; no dice.
## Every number a case needs comes from the data and the rules, never typed in.

const CROWN := "kingdom"
const CLANS := "beasts"
const SEATS := ["kingdom", "beasts"]
const FIXTURE := "res://tests/fixtures/m5_base_records.json"
const AI_MAGIC := "res://ai/ai_magic.gd"
## What a faction needs to know every ritual of a line (as tests/test_rituals.gd): its school's tier I and II, the greater
## working's Oath and the Oath's two ordinary nodes.
const CROWN_FORGE := ["crown_drillyard", "crown_charters", "crown_oath_forge", "shield_of_law", "sanctum_ward", "bastion",
	"sunlance", "dawn_blessing"]
const CLANS_GROVE := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "briar_snare", "call_the_pack",
	"wake_the_greenwrath", "bloodbolt", "bloodrot"]
const CLANS_BLOOD := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "bloodbolt", "bloodrot", "blood_moon",
	"briar_snare", "call_the_pack"]
const TITHE_BUILD := {"ruler": "fang_chieftain", "mandates": ["iron_discipline", "tithe_of_blood"]}


# --- fixtures ---------------------------------------------------------------------------------------

## A magic game with `nodes` researched ({faction id: [node ids]}), Regent's Court and Blood of the Fang unless `builds`
## says otherwise, `gold` each, and the field armies replaced by `specs` ([[id, owner, location, [unit type ids]]]); the
## rulers' armies stay at their capitals unless `ruler_at` moves them. Province owners: `owners` {province id: faction id}
## on top of the capitals.
func _board(specs: Array, nodes: Dictionary = {}, owners: Dictionary = {}, gold: int = 200, builds: Dictionary = {},
		ruler_at: Dictionary = {}) -> GameState:
	var b := {CROWN: "regents_court", CLANS: "blood_of_the_fang"}
	b.merge(builds, true)
	var s := GameState.with_magic(7, b)
	assert_true(s != null, "the magic game starts")
	for fid in nodes:
		s = AscensionRules.with_nodes(s, fid, nodes[fid])
	for f in s.factions:
		f.gold = gold
	var rulers := []
	for a in s.armies:
		if a.ruler != null:
			a.location = ruler_at.get(a.owner, a.location)
			rulers.append(a)
	s.armies.clear()
	for a in rulers:
		s.armies.append(a)
	for spec in specs:
		_army(s, spec[1], spec[2], spec[3], String(spec[0]))
	for pid in owners:
		s.find_province(String(pid)).owner = String(owners[pid])
	return s


## A new army of `fid` at `at` holding units of these type ids (a commander's id makes it the commander), at full hp.
func _army(s: GameState, fid: String, at: String, types: Array, id: String = "") -> Army:
	var f := s.find_faction(fid)
	var a := Army.new()
	a.id = id if not id.is_empty() else s.new_army_id(fid)
	a.owner = fid
	a.location = at
	for t in types:
		var ut := TurnResolver.recruitable_type(f, String(t), s)
		assert_true(ut != null, "%s can field %s" % [fid, t])
		if ut.is_commander:
			a.commander = Unit.new(ut, fid)
		else:
			a.units.append(Unit.new(ut, fid))
	s.armies.append(a)
	return a


func _many(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


func _ruler(s: GameState, fid: String) -> Army:
	return RulerRules.ruler_army(s, fid)


## One plan of a fresh brain on `state`, as the seat plays it: {"orders", "notes", "stats", "rng", "json"}.
func _plan(state: GameState, fid: String, game_seed: int = 7, level: String = "normal") -> Dictionary:
	var seat := SEATS.find(fid)
	var brain := AIPlayer.new()
	brain.configure(game_seed, seat)
	var rng := SeededRNG.new(AISeat.seat_seed(game_seed, seat))
	var orders: Array = brain.plan_orders(state, fid, rng, level)
	var stats := brain.last_plan_stats()
	stats.erase("usec")
	stats.erase("odds_usec")
	var notes := brain.last_plan_notes()
	return {"orders": orders, "notes": notes, "stats": stats, "rng": rng.to_dict(),
		"json": JSON.stringify({"orders": orders.map(func(o): return o.to_dict()), "notes": notes, "stats": stats, "rng": rng.to_dict()})}


## The rituals the brain plans on `state` when its other plans are `moves` ({army id: destination}): the magic part of the
## plan on its own, so a rule is tested without the rest of the turn's choices. {"casts", "gold", "ai", "notes"}.
func _rituals(state: GameState, fid: String, moves: Dictionary = {}, brain: AIPlayer = null) -> Dictionary:
	var ai := brain if brain != null else AIPlayer.new()
	ai.configure(7, SEATS.find(fid))
	var view := AIFog.trusted_view(state)
	ai._begin(view, fid, SeededRNG.new(1), "normal")
	for id in moves:
		ai._moves[id] = moves[id]
		ai._busy[id] = true
	ai._magic.plan()
	return {"casts": ai._magic.casts.duplicate(), "gold": ai._magic.reserved, "ai": ai, "notes": ai.last_plan_notes()}


## The cast of `ritual` among `casts`, or null.
func _cast_of(casts: Array, ritual: String):
	for o in casts:
		if o.ritual == ritual:
			return o
	return null


func _rituals_in(casts: Array) -> Array:
	return casts.map(func(o): return o.ritual)


## Every order passes the checks GameSession's OrderBook runs on `state`, in order.
func _assert_legal(state: GameState, fid: String, orders: Array, what: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(state, fid, o), "", "%s: %s is accepted" % [what, o.describe()])


func _view(s: GameState, viewer: String = CROWN) -> GameState:
	return FogRules.view_state(s, viewer, FogRules.new_memory(s, viewer), FogRules.new_intel(s, viewer))


## Turns a fog game of this state: setup_fog on a copy.
func _fogged(s: GameState) -> GameState:
	var f := s.deep_copy()
	f.fog = true
	return f


## `a`'s cast, resolved on a copy of `s` so its enchantment is real: the state with the ritual cast.
func _with_cast(s: GameState, fid: String, order: CastOrder) -> GameState:
	var c := s.deep_copy()
	var fx := MagicRules.ritual_effect(c, fid, order)
	assert_eq(fx.outcome, MagicRules.CAST, "%s took effect: %s" % [order.ritual, fx.get("reason", "")])
	return c


# --- 1. the research plan (§10.2) -------------------------------------------------------------------

func test_the_research_plan_follows_the_spec_for_every_preset_and_side() -> void:
	var checked := 0
	for preset_id in AIPaths.AI_PATHS:
		var plan: Dictionary = AIPaths.AI_PATHS[preset_id]
		var fid := String(plan.faction)
		for weight in plan.weights:
			var branch := String(weight[0])
			var seq := AIPaths.sequence(fid, preset_id, branch, true)
			var side := AscensionRules.branch_data(branch)
			# The school the Oath opens, from the data.
			var aligned := ""
			for sid in MagicRules.schools(fid):
				if String(MagicRules.school_data(sid).aligned_branch) == branch:
					aligned = String(sid)
			assert_false(aligned.is_empty(), "%s: the %s Oath opens a school" % [preset_id, branch])
			var nodes: Array = MagicRules.school_data(aligned).nodes  # tier I, tier II, mastery, tier III
			var other_school := ""
			for sid in MagicRules.schools(fid):
				if String(sid) != aligned:
					other_school = String(sid)
			var other: Array = MagicRules.school_data(other_school).nodes
			var what := "%s on %s" % [preset_id, branch]
			var before: Array = plan.before
			assert_eq(seq[0], before[0], "%s: its first ordinary node first" % what)
			assert_eq(seq[1], nodes[0], "%s: then its aligned school's tier I" % what)
			assert_eq(seq.slice(2, 1 + before.size()), before.slice(1), "%s: then the rest of the ordinary nodes it listed" % what)
			var oath := seq.find(String(side.oath))
			assert_eq(oath, 1 + before.size(), "%s: then the Oath" % what)
			assert_eq(seq[oath + 1], String(side.transformation), "%s: and the transformation" % what)
			assert_eq(seq.slice(oath + 2, oath + 5), [nodes[1], nodes[3], nodes[2]], "%s: then the aligned tier II, tier III and mastery" % what)
			assert_eq(seq.slice(seq.size() - 3), [other[0], other[1], other[2]], "%s: the other school's tier I, II and mastery last" % what)
			var tier3_other: String = other[3]
			assert_false(seq.has(tier3_other), "%s: the other side's greater working is never planned (the Oath closes it)" % what)
			assert_eq(seq.size(), AscensionRules.node_ids(fid).filter(func(n): return AscensionRules.is_ordinary(n)).size() + 2 + 7,
				"%s: every ordinary node, the Oath and its transformation and 7 arcana nodes" % what)
			var seen := {}
			for n in seq:
				assert_false(seen.has(n), "%s: %s is listed once" % [what, n])
				seen[n] = true
			# Every step is legal when the ones before it are done.
			var s := _board([], {}, {}, 100, {})
			for i in seq.size():
				var done := AscensionRules.with_nodes(s, fid, seq.slice(0, i))
				assert_eq(AscensionRules.check_research(done, fid, String(seq[i])), {}, "%s: %s can be researched after %s" % [what, seq[i], seq.slice(0, i)])
			checked += 1
	assert_eq(checked, 12, "six presets, two sides each")


func test_without_magic_the_research_plan_is_the_one_of_m4() -> void:
	for preset_id in AIPaths.AI_PATHS:
		var plan: Dictionary = AIPaths.AI_PATHS[preset_id]
		var fid := String(plan.faction)
		for weight in plan.weights:
			var side := AscensionRules.branch_data(String(weight[0]))
			var want: Array = plan.before.duplicate()
			want.append(String(side.oath))
			want.append(String(side.transformation))
			for nid in AscensionRules.node_ids(fid):
				if AscensionRules.is_ordinary(nid) and not want.has(nid):
					want.append(nid)
			assert_eq(AIPaths.sequence(fid, preset_id, String(weight[0])), want, "%s on %s: the old order" % [preset_id, weight[0]])
			assert_eq(AIPaths.sequence(fid, preset_id, String(weight[0]), false), want, "and with magic false")
	# In a game with paths and no magic the order for the state is the same too.
	var paths := GameState.with_paths(5)
	var order := AIPaths.order_for(paths, CROWN, "warrior_king", "celestial_host")
	assert_eq(order, AIPaths.AI_PATHS.warrior_king.before[0], "the first ordinary node, as in M4")


func test_a_custom_build_researches_its_first_spell_after_its_first_ordinary_node() -> void:
	for fid in SEATS:
		var side := ""
		for b in PathData.BRANCHES:
			if String(PathData.BRANCHES[b].faction) == fid:
				side = String(b)
				break
		var seq := AIPaths.sequence(fid, "", side, true)
		var first_spell := ""
		for sid in MagicRules.schools(fid):
			if String(MagicRules.school_data(sid).aligned_branch) == side:
				first_spell = String(MagicRules.school_data(sid).nodes[0])
		assert_eq(seq[1], first_spell, "%s: a build with no preset plays the default plan" % fid)
	assert_eq(AIPaths.arcana_plan_for("not_a_preset"), {"first": 1})


func test_the_computer_researches_in_the_order_of_its_plan_and_swears_one_side() -> void:
	var played := 0
	for game_seed in [1, 2]:
		for pair in [["regents_court", "blood_of_the_fang"], ["warrior_king", "beast_god_unbound"]]:
			var s := GameState.with_magic(game_seed, {CROWN: RulerRules.preset_build(pair[0]), CLANS: RulerRules.preset_build(pair[1])})
			var session := GameSession.new(s, SEATS, game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
			var ai := AISeat.new(session, game_seed)
			while not session.is_over() and session.turns_played() < 40:
				if ai.play(session).played.is_empty():
					break
			var final := session.state()
			for fid in SEATS:
				var preset_id: String = pair[SEATS.find(fid)]
				var branch := AscensionRules.branch(final, fid)
				assert_false(branch.is_empty(), "%s swore a side in game %d" % [fid, game_seed])
				var seq := AIPaths.sequence(fid, preset_id, branch, true)
				var done := AscensionRules.researched(final, fid)
				assert_eq(done, seq.slice(0, done.size()), "%s (%s) researched its plan in order, nothing else" % [fid, preset_id])
				assert_true(done.size() >= 4, "%s got through the first nodes (%d)" % [fid, done.size()])
				assert_true(MagicRules.knows_a_spell(final, fid), "%s knows a spell" % fid)
			assert_eq(ai.rejections(), [], "no order was refused")
			played += 1
	assert_eq(played, 4)


func test_research_orders_come_only_when_the_target_is_not_the_plan() -> void:
	var s := _board([])
	var first := AIPaths.order_for(s, CROWN, "regents_court", "celestial_host")
	assert_eq(first, AIPaths.AI_PATHS.regents_court.before[0], "the first ordinary node")
	# Its target is that node already: no order. Once done, the next is the aligned tier I.
	AscensionRules.set_target(s, CROWN, first)
	assert_eq(AIPaths.order_for(s, CROWN, "regents_court", "celestial_host"), "")
	var done := AscensionRules.with_nodes(s, CROWN, [first])
	assert_eq(AIPaths.order_for(done, CROWN, "regents_court", "celestial_host"), "sunlance", "then the Sun's first spell (the Oath of the Dawn's school)")
	assert_eq(AIPaths.order_for(done, CROWN, "regents_court", "living_iron"), "shield_of_law", "or Law's, on the other side of the fork")


# --- 2. mages as recruits (§10.2) -------------------------------------------------------------------

## The units of `fid` for the rough guess, one per type id.
func _units(s: GameState, fid: String, types: Array) -> Array:
	var f := s.find_faction(fid)
	var out := []
	for t in types:
		out.append(Unit.new(TurnResolver.recruitable_type(f, String(t), s), fid))
	return out


## What a side's mages are worth a round against a foe, as AIPlayer asks (a shielded second rank lasts longer).
func _pressure(mine: Dictionary, foe: Dictionary, shielded: bool, foe_reach: float) -> float:
	var lasts := 1.0 + AIPlayer.VOLLEY_SHIELD_VALUE * (1.0 - foe_reach) if shielded else 1.0
	return AIMagic.mage_pressure(mine, foe, lasts, AIPlayer.ROUNDS_GUESS)


## The expected damage of one hit by the rules (the numbers of AutoBattleResolver, as constants and formulas).
func _hit(attack: int, defense: int) -> float:
	return float(AutoBattleResolver.hit_chance(attack, defense)) / 100.0 * float(AutoBattleResolver.damage(attack, defense))


func test_a_mage_counts_the_damage_of_its_spells_each_round() -> void:
	# Bolts: every mage's cast is the bolt's damage, mastery included, from the data.
	var s := _board([], {CROWN: ["sunlance"], CLANS: ["bloodbolt"]})
	var ctx := {"casts": AIMagic.cast_profiles(s)}
	for case in [[CROWN, "adepts", "sunlance", "spearmen"], [CLANS, "shamans", "bloodbolt", "spearmen"]]:
		var fid: String = case[0]
		var foe_fid := CLANS if fid == CROWN else CROWN
		var foe_type := "tuskers" if fid == CROWN else "spearmen"
		var mages := _units(s, fid, _many(case[1], 3))
		# An exposed second rank (more mages than front-rank fighters): no shield bonus on top.
		var mine := AIPlayer._side_summary(mages, ctx)
		var foe := AIPlayer._side_summary(_units(s, foe_fid, _many(foe_type, 6)), ctx)
		var value := float(MagicRules.spell_numbers(case[2], 0).value)
		assert_eq(_pressure(mine, foe, false, 0.0), 3.0 * value, "%s: three mages cast %s three times, %d damage each" % [fid, case[2], int(value)])
		assert_eq(mine.volley, 3, "%s: mages stand in the second rank" % fid)
		assert_eq(mine.front, 0)
		# Shielded by a front rank as big as theirs, they last longer, as Volley's shield is counted.
		var shielded := _pressure(mine, foe, true, 0.0)
		assert_eq(shielded, 3.0 * value * (1.0 + AIPlayer.VOLLEY_SHIELD_VALUE), "%s: a shielded second rank counts for more" % fid)
		assert_eq(_pressure(mine, foe, true, 1.0), 3.0 * value, "%s: not when the enemy reaches the second rank" % fid)
	# With the Sun's mastery node the bolt is a point stronger.
	var mastered := _board([], {CROWN: ["sunlance", "dawn_blessing", "sun_mastery"]})
	var mctx := {"casts": AIMagic.cast_profiles(mastered)}
	assert_eq(mctx.casts[CROWN].bonus.sun, 1, "the mastery node is +1 for a mage")
	var mine2 := AIPlayer._side_summary(_units(mastered, CROWN, ["adepts"]), mctx)
	var foe2 := AIPlayer._side_summary(_units(mastered, CLANS, ["tuskers"]), mctx)
	assert_eq(_pressure(mine2, foe2, false, 0.0), float(MagicRules.spell_numbers("sunlance", 1).value))


func test_the_expected_damage_used_here_is_the_battle_rules_own() -> void:
	for attack in [7, 9, 11, 13]:
		for defense in [4, 5, 8, 9, 13]:
			assert_true(absf(_expected_hit(float(attack), float(defense)) - _hit(attack, defense)) < 0.00001, "attack %d on defense %d" % [attack, defense])


func test_a_hex_is_worth_the_damage_it_takes_off_the_units_it_covers() -> void:
	var s := _board([], {CLANS: ["briar_snare"]})
	var ctx := {"casts": AIMagic.cast_profiles(s)}
	var part := absf(float(MagicRules.spell_data("briar_snare").value))
	var knights := TurnResolver.recruitable_type(s.find_faction(CROWN), "knights", s)
	for n_foes in [4, 6, 20]:
		var foe := AIPlayer._side_summary(_units(s, CROWN, _many("knights", n_foes)), ctx)
		# Our side: a Shaman with four Tuskers in front of it, whose mean defense the hex is measured against.
		var side := AIPlayer._side_summary(_units(s, CLANS, ["shamans"] + _many("tuskers", 4)), ctx)
		var covered := mini(int(MagicRules.spell_numbers("briar_snare", 0).count), n_foes)
		var d := AIPlayer._summary_defense(side)
		var each := _expected_hit(knights.attack, d) - _expected_hit(knights.attack - int(part), d)
		assert_true(each > 0.0, "a hex takes damage off the Knights' hits")
		var want := float(covered) * each
		assert_true(absf(_pressure(side, foe, false, 0.0) - want) < 0.0001,
			"%d Knights: the snare covers %d and saves %.2f a round (got %.2f)" % [n_foes, covered, want, _pressure(side, foe, false, 0.0)])
	# No front-rank enemy to snare (only a second rank): the mage's other spells or nothing.
	var rank2 := AIPlayer._side_summary(_units(s, CROWN, _many("crossbowmen", 5)), ctx)
	var us := AIPlayer._side_summary(_units(s, CLANS, ["shamans", "tuskers"]), ctx)
	assert_eq(_pressure(us, rank2, false, 0.0), 0.0, "nothing to snare in a second rank")


## The expected damage of one attack by the rules, with fractional defense (an average).
func _expected_hit(attack: float, defense: float) -> float:
	var hit := clampf(float(AutoBattleResolver.BASE_HIT) + float(AutoBattleResolver.HIT_PER_POINT) * (attack - defense),
		float(AutoBattleResolver.MIN_HIT), float(AutoBattleResolver.MAX_HIT)) / 100.0
	return hit * maxf(float(AutoBattleResolver.MIN_DAMAGE), ceilf(attack * 0.5) - floorf(defense * 0.25))


func test_casters_spread_over_the_spellbook_as_the_resolver_does() -> void:
	# Two Adepts know Sunlance and Shield of Law (in the default order). Where Shield of Law has something to cover, the
	# second casts it; behind a fort it is never useful, so the second casts Sunlance too.
	var s := _board([], {CROWN: ["sunlance", "shield_of_law"]})
	var open := {"casts": AIMagic.cast_profiles(s), "shield_ok": true}
	var walled := {"casts": AIMagic.cast_profiles(s), "shield_ok": false}
	assert_eq(open.casts[CROWN].book, ["sunlance", "shield_of_law"], "the default spellbook order, researched spells only")
	var army := ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "adepts", "adepts"]
	var foe_units := _units(s, CLANS, _many("tuskers", 6))
	var foe := AIPlayer._side_summary(foe_units, open)
	var lance := float(MagicRules.spell_numbers("sunlance", 0).value)
	var mine_open := AIPlayer._side_summary(_units(s, CROWN, army), open)
	var mine_walled := AIPlayer._side_summary(_units(s, CROWN, army), walled)
	var in_the_open := _pressure(mine_open, foe, false, 0.0)
	var behind_walls := _pressure(mine_walled, foe, false, 0.0)
	assert_eq(behind_walls, 2.0 * lance, "behind a fort both cast Sunlance")
	assert_true(in_the_open > lance, "in the open the second casts Shield of Law, which adds to the first's Sunlance (%.2f)" % in_the_open)
	assert_true(in_the_open != 2.0 * lance, "and not a second Sunlance")
	# Shield of Law's worth: the damage the 6 Spearmen it covers would otherwise take, from the data.
	var spear := TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen", s)
	var tusker := TurnResolver.recruitable_type(s.find_faction(CLANS), "tuskers", s)
	var def_with_wall := float(spear.defense) + float(AutoBattleResolver.SHIELD_WALL_DEFENSE)
	var covered := float(mini(6, 6))
	var aimed := 6.0 / 6.0  # six attackers on six front-rank targets
	var want := lance + covered * aimed * (_expected_hit(float(tusker.attack), float(spear.defense)) - _expected_hit(float(tusker.attack), float(spear.defense) + 4.0))
	assert_true(def_with_wall > 0.0)
	assert_true(absf(in_the_open - want) < 0.0001, "Sunlance plus the damage Shield of Law blocks: %.3f vs %.3f" % [in_the_open, want])


func test_a_mage_is_worth_recruiting_for_what_it_adds() -> void:
	var s := _board([], {CLANS: ["briar_snare", "bloodbolt"]})
	var ai := AIPlayer.new()
	ai.configure(7, 1)
	ai._begin(s, CLANS, SeededRNG.new(1), "normal")
	var base := ai._units([_army(s, CLANS, "fangridge", _many("tuskers", 6) + _many("fangthrowers", 6))])
	var foes := _units(s, CROWN, _many("spearmen", 8) + _many("knights", 4))
	var before: float = ai._recruit_value(base, foes)
	var shaman := TurnResolver.recruitable_type(s.find_faction(CLANS), "shamans", s)
	var with_one := base.duplicate()
	with_one.append(ai._recruit_unit(shaman))
	assert_true(float(ai._recruit_value(with_one, foes)) > before, "a Shaman with two spells to cast raises the garrison's value")
	# The same Shaman with no spell known (a rival's research hidden in a view assumes the first tier I one) still counts.
	var none := _board([])
	var ctx := {"casts": AIMagic.cast_profiles(none)}
	assert_eq(ctx.casts[CLANS].book, ["briar_snare"], "no spell researched: the assumed first tier I spell of the default spellbook")
	assert_eq(ctx.casts[CROWN].book, ["sunlance"], "the Crown's is Sunlance (Sunburst is a greater working)")


func test_at_most_one_mage_for_every_so_many_regular_units() -> void:
	var s := _board([], {CROWN: ["sunlance"], CLANS: ["bloodbolt"]})
	for fid in SEATS:
		var regular := "spearmen" if fid == CROWN else "tuskers"
		var mage := "adepts" if fid == CROWN else "shamans"
		var cmd := "knight_captain" if fid == CROWN else "warchief"
		var per := AIMagic.MAGE_PER
		assert_false(AIMagic.room_for_mage(_units(s, fid, _many(regular, per - 1))), "%s: %d regular units are too few" % [fid, per - 1])
		assert_true(AIMagic.room_for_mage(_units(s, fid, _many(regular, per))), "%s: %d are enough for one" % [fid, per])
		assert_false(AIMagic.room_for_mage(_units(s, fid, _many(regular, per) + [mage])), "%s: not for a second" % fid)
		assert_true(AIMagic.room_for_mage(_units(s, fid, _many(regular, 2 * per) + [mage])), "%s: twice as many take another" % fid)
		assert_false(AIMagic.room_for_mage(_units(s, fid, _many(regular, per - 1) + [cmd])), "%s: a commander is not a regular unit" % fid)
		assert_false(AIMagic.room_for_mage(_units(s, fid, _many(regular, per - 1) + [mage])), "%s: nor is a mage" % fid)
	assert_true(AIMagic.MAGE_PER >= 4 and AIMagic.MAGE_PER <= 8, "§13.3's range for the ratio: from 1 in 4 to 1 in 8")


func test_the_recruit_plan_keeps_the_mage_ratio_and_a_shielded_second_rank() -> void:
	# Plenty of gold, a garrison, a foe the mages are good against: the plan holds at most one mage per six regular units
	# (counting the recruits) and never has more second-rank fighters than front-rank ones.
	for case in [[CLANS, "shamans", ["briar_snare", "bloodbolt"], ["tuskers", "fangthrowers"], CROWN, "spearmen"],
			[CROWN, "adepts", ["sunlance", "shield_of_law"], ["spearmen", "crossbowmen"], CLANS, "tuskers"]]:
		var fid: String = case[0]
		var s := _board([], {fid: case[2]}, {}, 1000)
		var home: String = s.find_faction(fid).capital
		_army(s, fid, home, _many(case[3][0], 7) + _many(case[3][1], 2))
		_army(s, case[4], "ebonpeak" if fid == CLANS else "westwatch", _many(case[5], 6))
		var ai := AIPlayer.new()
		ai.configure(7, SEATS.find(fid))
		ai._begin(s, fid, SeededRNG.new(1), "normal")
		var base: Array = ai._armies_ending_at(home)
		var plan: Array = ai._plan_recruits(base)
		var units: Array = ai._units(base)
		for ut in plan:
			units.append(ai._recruit_unit(ut))
		var mages := units.filter(func(u): return MagicRules.is_mage(u.type)).size()
		var regulars := units.filter(func(u): return not MagicRules.is_mage(u.type) and not u.type.is_commander and not u.type.is_ruler).size()
		var ranks := AIPlayer._ranks(units)
		assert_true(mages * AIMagic.MAGE_PER <= regulars, "%s: %d mages among %d regular units" % [fid, mages, regulars])
		assert_true(ranks.volley <= ranks.front, "%s: the second rank (%d) is no bigger than the front (%d)" % [fid, ranks.volley, ranks.front])
		assert_true(plan.size() > 4, "%s: it bought troops (%d)" % [fid, plan.size()])
	# No spell researched: no mage is bought at all.
	var raw := _board([], {}, {}, 1000)
	_army(raw, CLANS, "fangridge", _many("tuskers", 12))
	var ai2 := AIPlayer.new()
	ai2._begin(raw, CLANS, SeededRNG.new(1), "normal")
	var plan2: Array = ai2._plan_recruits(ai2._armies_ending_at("fangridge"))
	assert_false(plan2.any(func(ut): return MagicRules.is_mage(ut)), "the mage gate: no spell, no mage")


func test_the_easy_computer_keeps_the_ratio_too() -> void:
	var s := _board([], {CLANS: ["briar_snare", "bloodbolt"]}, {}, 1000)
	_army(s, CLANS, "fangridge", _many("tuskers", 6))
	var checked := 0
	for game_seed in 12:
		var ai := AIPlayer.new()
		ai._begin(s, CLANS, SeededRNG.new(game_seed), "easy")
		var plan: Array = ai._plan_recruits([])
		var units: Array = ai._units(ai._mine_at("fangridge"))
		for ut in plan:
			units.append(ai._recruit_unit(ut))
		var mages := units.filter(func(u): return MagicRules.is_mage(u.type)).size()
		var regulars := units.filter(func(u): return not MagicRules.is_mage(u.type) and not u.type.is_commander and not u.type.is_ruler).size()
		assert_true(mages * AIMagic.MAGE_PER <= regulars, "seed %d: %d mages among %d regular units" % [game_seed, mages, regulars])
		checked += mages
	assert_true(checked > 0, "and it does buy mages (%d in all)" % checked)


# --- 3. the rituals (§10.2) -------------------------------------------------------------------------
# Each rule on a constructed board, with the moves of the rest of the turn given (`moves`), then the same board changed
# so the rule does not apply.

func test_sanctum_ward_when_an_own_province_is_cursed() -> void:
	var s := _board([
		[ "kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]],
		[ "beasts-s", CLANS, "thornvale", ["shamans"]],
	], {CROWN: CROWN_FORGE, CLANS: CLANS_BLOOD}, {"highcrag": CROWN})
	var cursed := _with_cast(s, CLANS, CastOrder.new("bloodrot", "beasts-s", "highcrag"))
	assert_eq(cursed.enchantments.filter(func(e): return e.kind == "curse").size(), 1, "highcrag is cursed")
	var r := _rituals(cursed, CROWN)
	var ward = _cast_of(r.casts, "sanctum_ward")
	assert_true(ward != null, "it wards the cursed province: %s" % [_rituals_in(r.casts)])
	assert_eq(ward.target, "highcrag", "the cursed province, not its capital")
	assert_eq(ward.pay, CastOrder.GOLD)
	assert_eq(MagicRules.check_cast(cursed, CROWN, ward, []), {}, "and the ritual is legal")
	assert_true(" ".join(r.notes).contains("a rival's curse lies on Highcrag"), " ".join(r.notes))
	# A curse already ending (a ward ended it) or already warded needs no ward; the capital's curse comes before others.
	var warded := _with_cast(cursed, CROWN, CastOrder.new("sanctum_ward", "kingdom-g", "highcrag"))
	assert_true(_cast_of(_rituals(warded, CROWN).casts, "sanctum_ward") == null or _cast_of(_rituals(warded, CROWN).casts, "sanctum_ward").target != "highcrag", "highcrag is warded already")
	var twice := _with_cast(_with_cast(s, CLANS, CastOrder.new("bloodrot", "beasts-s", "highcrag")), CLANS, CastOrder.new("bloodrot", "beasts-s", "crownkeep"))
	var first = _cast_of(_rituals(twice, CROWN).casts, "sanctum_ward")
	assert_eq(first.target, "crownkeep", "the capital first when both are cursed")
	# Nobody to cast it: no caster within 2 of the cursed province (Deepwood is three moves from Highcrag).
	var far := s.deep_copy()
	far.find_army("kingdom-g").location = "deepwood"
	_ruler(far, CROWN).location = "deepwood"
	var cursed_far := _with_cast(far, CLANS, CastOrder.new("bloodrot", "beasts-s", "highcrag"))
	assert_true(_cast_of(_rituals(cursed_far, CROWN).casts, "sanctum_ward") == null, "no caster within 2 of the cursed province: no ward")


func test_sanctum_ward_ahead_of_a_rival_that_can_curse() -> void:
	var specs := [["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]]]
	var nodes := {CROWN: CROWN_FORGE, CLANS: CLANS_BLOOD}
	var s := _board(specs, nodes, {"westwatch": CLANS})
	var r := _rituals(s, CROWN)
	var ward = _cast_of(r.casts, "sanctum_ward")
	assert_true(ward != null, "a rival that can curse owns a province next to the capital: %s" % [_rituals_in(r.casts)])
	assert_eq(ward.target, "crownkeep", "it wards its capital")
	assert_true(" ".join(r.notes).contains("hold Westwatch, 1 move from Crownkeep, and can curse"), " ".join(r.notes))
	# Two moves is still ahead; three is not.
	var two := _board(specs, nodes, {"stonegate": CLANS})
	assert_true(_cast_of(_rituals(two, CROWN).casts, "sanctum_ward") != null, "two moves from the capital")
	var three := _board(specs, nodes, {"blackwood": CLANS})
	assert_true(_cast_of(_rituals(three, CROWN).casts, "sanctum_ward") == null, "three moves from the capital: not yet")
	# Without fog the rival's research is public: no Bloodrot, no curse to fear.
	var tame := _board(specs, {CROWN: CROWN_FORGE}, {"westwatch": CLANS})
	assert_true(_cast_of(_rituals(tame, CROWN).casts, "sanctum_ward") == null, "a rival that has not learned Bloodrot")
	# Under fog it is hidden, so a rival of the school of Blood is assumed to have it.
	var fogged := _fogged(tame)
	assert_true(_cast_of(_rituals(_view(fogged), CROWN).casts, "sanctum_ward") != null, "hidden research: assumed, and warded ahead")
	# The ward lasts "through next turn" when cast: no second one while it does, and one when it runs out.
	var warded := _with_cast(s, CROWN, CastOrder.new("sanctum_ward", "kingdom-g", "crownkeep"))
	assert_true(_cast_of(_rituals(warded, CROWN).casts, "sanctum_ward") == null, "a ward through next turn is enough")
	var lapsing := warded.deep_copy()
	lapsing.current_turn += 1
	var again = _cast_of(_rituals(lapsing, CROWN).casts, "sanctum_ward")
	assert_true(again != null and again.target == "crownkeep", "the turn it would run out, it wards again")
	# No ward when the capital is not ours to ward.
	var lost := _board(specs, nodes, {"westwatch": CLANS, "crownkeep": CLANS})
	assert_true(_cast_of(_rituals(lost, CROWN).casts, "sanctum_ward") == null, "a capital we no longer hold")


func test_sanctum_ward_when_the_capital_was_read_by_far_sight_last_turn() -> void:
	var specs := [["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]], ["beasts-s", CLANS, "thornvale", ["shamans"]]]
	var s := _board(specs, {CROWN: CROWN_FORGE})
	var read := _with_cast(s, CLANS, CastOrder.new("far_sight", "beasts-s", "crownkeep"))
	assert_eq(read.enchantments.filter(func(e): return e.kind == "sight" and e.province == "crownkeep").size(), 1, "the capital is under a rival's sight")
	read.current_turn = 1  # the turn after the one it was cast on
	var seen := _view(_fogged(read))
	var r := _rituals(seen, CROWN)
	var ward = _cast_of(r.casts, "sanctum_ward")
	assert_true(ward != null and ward.target == "crownkeep", "it wards the capital that was read: %s" % [_rituals_in(r.casts)])
	assert_true(" ".join(r.notes).contains("a rival's Far Sight read Crownkeep last turn"), " ".join(r.notes))
	# Control: no sight on the capital, no rival near, no ward.
	assert_true(_cast_of(_rituals(_view(_fogged(s)), CROWN).casts, "sanctum_ward") == null, "nothing to ward against")
	# An older reading (two turns ago) is not "last turn".
	var old := read.deep_copy()
	old.current_turn = 2  # the sight (cast on turn 1, through turn 3) is still up, but it was cast the turn before last
	assert_true(_cast_of(_rituals(_view(_fogged(old)), CROWN).casts, "sanctum_ward") == null, "only last turn's reading counts")


func test_dawn_blessing_for_the_main_army_that_will_attack() -> void:
	var specs := [
		["kingdom-m", CROWN, "highcrag", ["knights", "knights", "knights", "spearmen", "spearmen", "knight_captain"]],
		["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]],
		["beasts-e", CLANS, "thornvale", ["tuskers", "tuskers"]],
	]
	var s := _board(specs, {CROWN: CROWN_FORGE}, {"highcrag": CROWN})
	var r := _rituals(s, CROWN, {"kingdom-m": "thornvale"})
	var bless = _cast_of(r.casts, "dawn_blessing")
	assert_true(bless != null, "the main army attacks this turn: %s" % [_rituals_in(r.casts)])
	assert_eq(bless.target, "highcrag", "where the main army stands")
	assert_ne(bless.army_id, "kingdom-m", "cast by an army that holds, never by the one that attacks")
	assert_true(" ".join(r.notes).contains("the main army at Highcrag will attack this turn"), " ".join(r.notes))
	# Next turn is enough: it stays where it is, next to the enemy.
	assert_true(_cast_of(_rituals(s, CROWN).casts, "dawn_blessing") != null, "it will attack next turn")
	# Not when it is out of the enemy's reach, already blessed, or not on our land.
	var calm := _board([specs[0], specs[1]], {CROWN: CROWN_FORGE}, {"highcrag": CROWN})
	assert_true(_cast_of(_rituals(calm, CROWN).casts, "dawn_blessing") == null, "no enemy near: it has no battle to be blessed for")
	var blessed := _with_cast(s, CROWN, CastOrder.new("dawn_blessing", "kingdom-g", "highcrag"))
	assert_true(_cast_of(_rituals(blessed, CROWN).casts, "dawn_blessing") == null, "already blessed")
	var abroad := _board(specs, {CROWN: CROWN_FORGE})
	assert_true(_cast_of(_rituals(abroad, CROWN, {"kingdom-m": "thornvale"}).casts, "dawn_blessing") == null, "an army on land that is not ours is not blessed")
	# The only caster is inside the army that attacks: it is not pinned, so nothing is cast.
	var alone := _board([["kingdom-m", CROWN, "highcrag", ["knights", "knights", "adepts"]], specs[2]], {CROWN: CROWN_FORGE}, {"highcrag": CROWN}, 200, {}, {CROWN: "crownkeep"})
	_ruler(alone, CROWN).location = "fangridge"
	var none := _rituals(alone, CROWN, {"kingdom-m": "thornvale"})
	assert_true(_cast_of(none.casts, "dawn_blessing") == null, "an army ordered to attack casts nothing: %s" % [_rituals_in(none.casts)])


## ARM-1 (design/ARM1_SPLIT_MERGE.md §2.1): a Dawn Blessing proposal values the fighters a blessing COVERS, not the army ids it
## lists. A partly covered main army (recruits and musters joined it after the cast) is worth blessing again once fewer than half
## of its fighters are covered, because that is where the half-blessed morale is lost; a mostly covered one is left alone.
func test_dawn_blessing_is_valued_by_the_fighters_it_covers() -> void:
	var specs := [
		["kingdom-m", CROWN, "highcrag", ["knights", "knights", "knights", "spearmen", "spearmen", "knight_captain"]],  # six fighters
		["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]],
		["beasts-e", CLANS, "thornvale", ["tuskers", "tuskers"]],
	]
	var s := _board(specs, {CROWN: CROWN_FORGE}, {"highcrag": CROWN})
	var blessed := _with_cast(s, CROWN, CastOrder.new("dawn_blessing", "kingdom-g", "highcrag"))
	var e: Dictionary = blessed.enchantments.filter(func(x): return x.kind == "blessing")[0]
	assert_eq(e.armies, ["kingdom-m"], "the blessing lists the main army")
	var main := blessed.find_army("kingdom-m")
	var fighters: Array = UnitStatus.army_fighters(main)
	assert_eq(fighters.size(), 6)
	assert_true(_cast_of(_rituals(blessed, CROWN, {"kingdom-m": "thornvale"}).casts, "dawn_blessing") == null, "all six covered: nothing to bless again")
	for i in 3:
		fighters[i].add_status(UnitStatus.OUTSIDE_BLESSING, String(e.id))
	assert_true(_cast_of(_rituals(blessed, CROWN, {"kingdom-m": "thornvale"}).casts, "dawn_blessing") == null,
		"three of six still covered: that is half, the morale holds, no new cast")
	fighters[3].add_status(UnitStatus.OUTSIDE_BLESSING, String(e.id))
	var again = _cast_of(_rituals(blessed, CROWN, {"kingdom-m": "thornvale"}).casts, "dawn_blessing")
	assert_true(again != null, "two of six covered: fewer than half, so the army is worth blessing again")
	assert_eq(again.target, "highcrag")
	var notes := " ".join(_rituals(blessed, CROWN, {"kingdom-m": "thornvale"}).notes)
	assert_true(notes.contains("the main army at Highcrag will attack this turn"), notes)
	# A recast that comes back legal: the cast is checked against this very state, and restarts the same blessing.
	_assert_legal(blessed, CROWN, [again], "the second blessing")


## ARM-1: the trigger is the covered share of the main group, nothing else. A group of a big blessed army and a small plain one has
## most of its fighters covered, so nothing is cast; a small blessed army with a big plain one is mostly uncovered, so it is.
func test_a_mixed_main_group_is_blessed_by_the_share_of_fighters_covered() -> void:
	var specs := [
		["kingdom-m", CROWN, "highcrag", ["knights", "knights", "knights", "spearmen", "spearmen", "knight_captain"]],  # six fighters
		["kingdom-s", CROWN, "highcrag", ["spearmen"]],  # one
		["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]],
		["beasts-e", CLANS, "thornvale", ["tuskers", "tuskers"]],
	]
	var s := _board(specs, {CROWN: CROWN_FORGE}, {"highcrag": CROWN})
	var moves := {"kingdom-m": "thornvale", "kingdom-s": "thornvale"}
	var none := _with_cast(s, CROWN, CastOrder.new("dawn_blessing", "kingdom-g", "highcrag"))
	assert_true(none.enchantments.filter(func(x): return x.kind == "blessing")[0].armies.size() == 2, "the cast blessed both armies there")
	# 1. The big army is blessed, the small one is not: 6 of 7 covered, no cast.
	var big := none.deep_copy()
	big.enchantments.filter(func(x): return x.kind == "blessing")[0].armies = ["kingdom-m"]
	assert_true(_cast_of(_rituals(big, CROWN, moves).casts, "dawn_blessing") == null, "6 of 7 fighters covered: nothing to cast, though one army is plain")
	# 2. The small army is blessed, the big one is not: 1 of 7 covered, a cast.
	var small := none.deep_copy()
	small.enchantments.filter(func(x): return x.kind == "blessing")[0].armies = ["kingdom-s"]
	var cast = _cast_of(_rituals(small, CROWN, moves).casts, "dawn_blessing")
	assert_true(cast != null, "1 of 7 fighters covered: it is worth blessing again")
	assert_eq(cast.target, "highcrag")
	# 3. Nothing blessed: covered 0 casts, as it always did.
	assert_true(_cast_of(_rituals(s, CROWN, moves).casts, "dawn_blessing") != null, "covered 0 casts")
	# 4. Exactly half covered (3 of 6) is not under half: no cast.
	var half := _board([specs[0], specs[2], specs[3]], {CROWN: CROWN_FORGE}, {"highcrag": CROWN})
	var blessed := _with_cast(half, CROWN, CastOrder.new("dawn_blessing", "kingdom-g", "highcrag"))
	var fighters: Array = UnitStatus.army_fighters(blessed.find_army("kingdom-m"))
	var e := String(blessed.enchantments.filter(func(x): return x.kind == "blessing")[0].id)
	for i in 3:
		fighters[i].add_status(UnitStatus.OUTSIDE_BLESSING, e)
	assert_true(_cast_of(_rituals(blessed, CROWN, {"kingdom-m": "thornvale"}).casts, "dawn_blessing") == null, "3 of 6 covered is half: the morale holds")


func test_wake_the_greenwrath_where_a_caster_stands_in_a_forest() -> void:
	var s := _board([["beasts-s", CLANS, "greenglade", ["shamans", "tuskers"]]], {CLANS: CLANS_GROVE}, {"greenglade": CLANS})
	var r := _rituals(s, CLANS)
	var wake = _cast_of(r.casts, "wake_the_greenwrath")
	assert_true(wake != null, "a Shaman in a forest wakes it: %s" % [_rituals_in(r.casts)])
	assert_eq(wake.target, "greenglade")
	assert_eq(wake.army_id, "beasts-s")
	# Awake already: nothing (the ritual refuses, and so does the AI).
	var awake := s.deep_copy()
	MagicRules.place_summon(awake, CLANS, "greenwrath", 1, "wildmoor", 0)
	assert_true(_cast_of(_rituals(awake, CLANS).casts, "wake_the_greenwrath") == null, "one at a time")
	# Not in a forest, or not known: nothing.
	var plain := _board([["beasts-s", CLANS, "bloodfen", ["shamans", "tuskers"]]], {CLANS: CLANS_GROVE})
	assert_true(_cast_of(_rituals(plain, CLANS).casts, "wake_the_greenwrath") == null, "plains")
	var unknown := _board([["beasts-s", CLANS, "greenglade", ["shamans", "tuskers"]]], {CLANS: CLANS_BLOOD}, {"greenglade": CLANS})
	assert_true(_cast_of(_rituals(unknown, CLANS).casts, "wake_the_greenwrath") == null, "the Oath of the Grove was not sworn")
	# The Greenwrath's price, from the data, is held back from the troops.
	assert_eq(r.gold, int(MagicRules.price(s, CLANS, "wake_the_greenwrath").gold))


func test_call_the_pack_the_full_size_it_can_afford() -> void:
	var nodes := {CLANS: CLANS_GROVE + ["wild_mastery", "beasts_thorn_wild"]}
	var specs := [["beasts-s", CLANS, "fangridge", ["shamans", "tuskers"]], ["kingdom-e", CROWN, "blackwood", ["spearmen"]]]
	var rich := _board(specs, nodes, {}, 300)
	var army := rich.find_army("beasts-s")
	var sizes := MagicRules.pack_sizes(rich, CLANS, army)
	assert_eq(sizes[1], sizes[0] + 2, "the Thorn Wild and Wild Mastery add 2 to the pack")
	var cast = _cast_of(_rituals(rich, CLANS).casts, "call_the_pack")
	assert_true(cast != null, "an enemy army two moves away")
	assert_eq(cast.size, sizes[1], "with gold to spare it calls the biggest pack")
	assert_eq(cast.army_id, "beasts-s")
	assert_eq(cast.target, "fangridge", "at the caster's own province")
	# What the share allows decides the size between the least and the most.
	var each := int(MagicData.SPELLS.call_the_pack.cost)
	for wolves in range(int(sizes[0]), int(sizes[1]) + 1):
		var gold := int(ceil(float(wolves * each) / AIMagic.RITUAL_SHARE))
		var poorer := _board(specs, nodes, {}, gold)
		var got = _cast_of(_rituals(poorer, CLANS).casts, "call_the_pack")
		assert_true(got != null, "%d gold lets it pay for %d wolves" % [gold, wolves])
		assert_eq(got.size, wolves, "%d gold, 40%% of it for rituals: %d wolves" % [gold, wolves])
		assert_true(got.size * each <= floori(AIMagic.RITUAL_SHARE * gold), "and never more than the share")
	var too_poor := _board(specs, nodes, {}, int(ceil(float(int(sizes[0]) * each) / AIMagic.RITUAL_SHARE)) - 3)
	assert_true(_cast_of(_rituals(too_poor, CLANS).casts, "call_the_pack") == null, "less than the smallest pack: none")
	# A pack that is out, no enemy near, or not known: none.
	var out := rich.deep_copy()
	MagicRules.place_summon(out, CLANS, "thornwolves", 3, "bloodfen", out.current_turn + 5)
	assert_true(_cast_of(_rituals(out, CLANS).casts, "call_the_pack") == null, "one pack at a time")
	var far := _board([specs[0], ["kingdom-e", CROWN, "crownkeep", ["spearmen"]]], nodes, {}, 300)
	assert_true(_cast_of(_rituals(far, CLANS).casts, "call_the_pack") == null, "no enemy within 2 moves")
	var unknown := _board(specs, {CLANS: CLANS_BLOOD.filter(func(n): return n != "call_the_pack")}, {}, 300)
	assert_true(_cast_of(_rituals(unknown, CLANS).casts, "call_the_pack") == null, "not researched")


func test_bloodrot_on_the_strongest_stack_in_reach_and_an_enemy_capital_first() -> void:
	var specs := [
		["beasts-s", CLANS, "thornvale", ["shamans", "tuskers"]],
		["kingdom-big", CROWN, "highcrag", ["knights", "knights", "knights", "knights", "spearmen", "spearmen", "spearmen", "spearmen"]],
		["kingdom-cap", CROWN, "crownkeep", ["spearmen", "spearmen"]],
	]
	var s := _board(specs, {CLANS: CLANS_BLOOD}, {"thornvale": CLANS, "highcrag": CROWN}, 200, {}, {CLANS: "thornvale"})
	var r := _rituals(s, CLANS)
	var rot = _cast_of(r.casts, "bloodrot")
	assert_true(rot != null, "%s" % [_rituals_in(r.casts)])
	assert_eq(rot.target, "crownkeep", "the enemy capital first, though a bigger stack stands at Highcrag")
	# Without a stack at the capital, the strongest is the target.
	var no_cap := _board([specs[0], specs[1]], {CLANS: CLANS_BLOOD}, {"thornvale": CLANS, "highcrag": CROWN}, 200, {}, {CLANS: "thornvale"})
	_ruler(no_cap, CROWN).location = "rivermarch"
	assert_eq(_cast_of(_rituals(no_cap, CLANS).casts, "bloodrot").target, "highcrag", "the strongest stack it can see")
	# A ward it can see turns the ritual aside, so it aims elsewhere; our own curse through this turn is left to bite.
	var guarded := _board([specs[0], specs[1], specs[2]], {CLANS: CLANS_BLOOD, CROWN: CROWN_FORGE}, {"thornvale": CLANS, "highcrag": CROWN}, 200, {}, {CLANS: "thornvale"})
	_army(guarded, CROWN, "crownkeep", ["adepts"], "kingdom-w")
	guarded = _with_cast(guarded, CROWN, CastOrder.new("sanctum_ward", "kingdom-w", "crownkeep"))
	assert_eq(_cast_of(_rituals(guarded, CLANS).casts, "bloodrot").target, "highcrag", "the warded capital is passed over")
	var biting := _with_cast(s, CLANS, CastOrder.new("bloodrot", "beasts-s", "crownkeep"))
	var next = _cast_of(_rituals(biting, CLANS).casts, "bloodrot")
	assert_true(next != null and next.target == "highcrag", "the capital is cursed through this turn already: the next stack")
	# Out of range of every caster, no enemy in sight, or not known: none.
	var away := _board(specs, {CLANS: CLANS_BLOOD}, {"thornvale": CLANS}, 200, {}, {CLANS: "fangridge"})
	away.find_army("beasts-s").location = "fangridge"
	assert_true(_cast_of(_rituals(away, CLANS).casts, "bloodrot") == null, "nothing within 2 of the caster")
	var unknown := _board(specs, {CLANS: ["bloodbolt"]}, {"thornvale": CLANS}, 200, {}, {CLANS: "thornvale"})
	assert_true(_cast_of(_rituals(unknown, CLANS).casts, "bloodrot") == null, "Bloodrot not researched")


func test_blood_moon_when_the_main_army_attacks_this_turn() -> void:
	var specs := [
		["beasts-m", CLANS, "bloodfen", ["tuskers", "tuskers", "tuskers", "war_bear", "warchief"]],
		["beasts-g", CLANS, "fangridge", ["shamans", "tuskers"]],
		["kingdom-e", CROWN, "deepwood", ["spearmen", "spearmen"]],
	]
	# Only the Moon is known here, so no other ritual takes the armies that hold.
	var s := _board(specs, {CLANS: ["blood_moon"]}, {"bloodfen": CLANS, "deepwood": CROWN})
	var r := _rituals(s, CLANS, {"beasts-m": "deepwood"})
	var moon = _cast_of(r.casts, "blood_moon")
	assert_true(moon != null, "the main army attacks: %s" % [_rituals_in(r.casts)])
	assert_eq(moon.target, "", "the Moon has no target")
	assert_ne(moon.army_id, "beasts-m", "cast from an army that holds")
	# Not attacking this turn (standing next to the enemy is not enough), nothing to cast with, or a moon already up.
	assert_true(_cast_of(_rituals(s, CLANS).casts, "blood_moon") == null, "the Moon is for this turn's battles")
	var no_pack: Array = CLANS_BLOOD.filter(func(n): return n != "call_the_pack" and n != "briar_snare")
	var full := _board(specs, {CLANS: no_pack}, {"bloodfen": CLANS, "deepwood": CROWN})
	var up := _with_cast(full, CLANS, CastOrder.new("blood_moon", "beasts-g", ""))
	assert_true(_cast_of(_rituals(up, CLANS, {"beasts-m": "deepwood"}).casts, "blood_moon") == null, "only one global ritual at a time")
	assert_true(_cast_of(_rituals(full, CLANS, {"beasts-m": "deepwood"}).casts, "blood_moon") != null, "(and it is the same board without the Moon up)")


func test_bastion_on_the_highest_income_frontier_province_without_a_fort_and_never_a_third() -> void:
	var s := _board([["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]]], {CROWN: CROWN_FORGE},
		{"westwatch": CROWN, "highcrag": CROWN, "rivermarch": CROWN})
	var r := _rituals(s, CROWN)
	var bastion = _cast_of(r.casts, "bastion")
	assert_true(bastion != null, "a frontier province without a fort: %s" % [_rituals_in(r.casts)])
	var best := ""
	var best_income := -1
	for pid in ["westwatch", "highcrag", "rivermarch"]:
		var p := s.find_province(pid)
		if p.income > best_income:
			best = pid
			best_income = p.income
	assert_eq(bastion.target, best, "the one that earns most (%d)" % best_income)
	assert_eq(MagicRules.check_cast(s, CROWN, bastion, []), {}, "and it is legal")
	# The cap: two ever raised, then none.
	var one := s.deep_copy()
	one.find_faction(CROWN).bastions = ["westwatch"]
	one.find_province("westwatch").has_fort = true
	assert_true(_cast_of(_rituals(one, CROWN).casts, "bastion") != null, "one raised: one more")
	var two := one.deep_copy()
	two.find_faction(CROWN).bastions = ["westwatch", "highcrag"]
	two.find_province("highcrag").has_fort = true
	assert_true(_cast_of(_rituals(two, CROWN).casts, "bastion") == null, "two raised: the cap")
	# The best site has a fort already: the next best. No frontier at all (the rival owns nothing near): none.
	var forted := s.deep_copy()
	forted.find_province(best).has_fort = true
	var next = _cast_of(_rituals(forted, CROWN).casts, "bastion")
	assert_true(next != null and next.target != best, "a province with a fort is passed over")


func test_far_sight_toward_an_objective_that_is_out_of_sight_and_only_under_fog() -> void:
	# Wildmoor has no fort and no ruler stands there: Fangridge, two moves off, is out of sight from an army (a ruler, a
	# commander, a scout or a fort would see two provinces).
	var specs := [["kingdom-g", CROWN, "wildmoor", ["spearmen", "adepts"]]]
	var s := _board(specs, {}, {"wildmoor": CROWN})
	var fogged := _fogged(s)
	var view := _view(fogged)
	var ai := AIPlayer.new()
	var r := _rituals(view, CROWN, {}, ai)
	var sight = _cast_of(r.casts, "far_sight")
	assert_true(sight != null, "the enemy capital is out of sight: %s" % [_rituals_in(r.casts)])
	assert_eq(sight.target, "fangridge", "the objective: the enemy capital")
	assert_true(ai._fog.unseen("fangridge"), "it asked AIFog.unseen")
	assert_eq(MagicRules.check_cast(s, CROWN, sight, []), {}, "legal on the true state")
	# Without fog the AI never offers it.
	assert_true(_cast_of(_rituals(s, CROWN).casts, "far_sight") == null, "no fog: no Far Sight")
	# In sight already (an army next to it): nothing to look at.
	var near := _board([["kingdom-g", CROWN, "ebonpeak", ["spearmen", "adepts"]]], {}, {"ebonpeak": CROWN})
	assert_true(_cast_of(_rituals(_view(_fogged(near)), CROWN).casts, "far_sight") == null, "the enemy capital is in view")
	# Out of the caster's range of 3: none.
	var far := _board([["kingdom-g", CROWN, "crownkeep", ["spearmen", "adepts"]]], {}, {}, 200, {}, {CROWN: "crownkeep"})
	assert_true(_cast_of(_rituals(_view(_fogged(far)), CROWN).casts, "far_sight") == null, "five moves away")


func test_far_sight_that_came_to_nothing_is_not_tried_again_for_three_turns() -> void:
	var specs := [["kingdom-g", CROWN, "wildmoor", ["spearmen", "adepts"]]]
	var base := _board(specs, {}, {"wildmoor": CROWN})
	var ai := AIPlayer.new()
	var t0 := _view(_fogged(base))
	assert_true(_cast_of(_rituals(t0, CROWN, {}, ai).casts, "far_sight") != null, "the first try")
	# The next turn there is no sight enchantment of ours on Fangridge: the ward turned it aside.
	var t1 := base.deep_copy()
	t1.current_turn = 1
	var cast_again = _cast_of(_rituals(_view(_fogged(t1)), CROWN, {}, ai).casts, "far_sight")
	assert_true(cast_again == null, "it remembers that it came to nothing")
	for later in [2, 3]:
		var t := base.deep_copy()
		t.current_turn = later
		assert_true(_cast_of(_rituals(_view(_fogged(t)), CROWN, {}, ai).casts, "far_sight") == null, "turn %d: still within the three turns" % later)
	var t4 := base.deep_copy()
	t4.current_turn = 4
	assert_true(_cast_of(_rituals(_view(_fogged(t4)), CROWN, {}, ai).casts, "far_sight") != null, "after three turns it tries again")
	# When it took effect (our own sight is on the capital), nothing is remembered against it.
	var ai2 := AIPlayer.new()
	var first := _rituals(_view(_fogged(base)), CROWN, {}, ai2)
	var order = _cast_of(first.casts, "far_sight")
	var done := _with_cast(base, CROWN, order)
	done.current_turn = 1
	var after := _view(_fogged(done))
	assert_true(_cast_of(_rituals(after, CROWN, {}, ai2).casts, "far_sight") == null, "its sight is on the capital: nothing is out of sight")
	assert_true(ai2._magic._aside.is_empty(), "and nothing was turned aside")


# --- the gold: the share, the crisis, the running budget ----------------------------------------------

## A board where several rituals apply to the Crown: a rival of the school of Blood next to the capital (a ward ahead), a
## frontier without a fort (Bastion), and casters in two armies that hold.
func _busy_crown(gold: int) -> GameState:
	return _board([
		["kingdom-g", CROWN, "crownkeep", ["spearmen", "spearmen", "adepts"]],
		["kingdom-h", CROWN, "highcrag", ["spearmen", "adepts"]],
	], {CROWN: CROWN_FORGE, CLANS: CLANS_BLOOD}, {"westwatch": CLANS, "highcrag": CROWN, "rivermarch": CROWN}, gold)


func test_rituals_take_at_most_forty_percent_of_the_gold() -> void:
	var counts := []
	for gold in [10, 20, 30, 60, 100, 200]:
		var r := _rituals(_busy_crown(gold), CROWN)
		var s := _busy_crown(gold)
		var paid := 0
		for o in r.casts:
			assert_eq(o.pay, CastOrder.GOLD)
			paid += int(MagicRules.price(s, CROWN, o.ritual, o.size).gold)
			assert_eq(MagicRules.check_cast(s, CROWN, o, r.casts.slice(0, r.casts.find(o))), {}, "%d gold: %s is legal in its place" % [gold, o.ritual])
		assert_eq(r.gold, paid, "%d gold: the gold held back is what the casts cost" % gold)
		assert_true(paid <= floori(AIMagic.RITUAL_SHARE * gold), "%d gold: %d spent on rituals is within 40%% (%d)" % [gold, paid, floori(AIMagic.RITUAL_SHARE * gold)])
		counts.append(r.casts.size())
	assert_eq(counts[0], 0, "10 gold: 4 for rituals buys nothing")
	assert_true(counts[counts.size() - 1] >= 2, "plenty of gold: the ward and the fort (%s)" % [counts])
	for i in range(1, counts.size()):
		assert_true(counts[i] >= counts[i - 1], "more gold never casts less (%s)" % [counts])
	assert_eq(AIMagic.RITUAL_SHARE, 0.4, "the spec's share")


## A Crown garrison that holds its capital against a Clans army next door it can beat (so the capital is not in danger),
## with the rival's province beside it and a second Crown army at Highcrag: the main army stands at Crownkeep, next to the
## enemy, and the Regent and the Adepts hold with it.
func _holding_crown(gold: int) -> GameState:
	return _board([
		["kingdom-g", CROWN, "crownkeep", _many("spearmen", 6) + ["knights", "knights", "adepts"]],
		["kingdom-h", CROWN, "highcrag", ["spearmen", "adepts"]],
		["beasts-e", CLANS, "westwatch", _many("tuskers", 5)],
	], {CROWN: CROWN_FORGE, CLANS: CLANS_BLOOD}, {"westwatch": CLANS, "highcrag": CROWN, "rivermarch": CROWN}, gold)


func test_the_troops_are_priced_from_the_gold_the_rituals_leave() -> void:
	var cast_somewhere := 0
	for gold in [30, 60, 120]:
		var s := _holding_crown(gold)
		var p := _plan(s, CROWN)
		var casts: Array = p.orders.filter(func(o): return o is CastOrder)
		var recruits: Array = p.orders.filter(func(o): return o is RecruitOrder)
		_assert_legal(s, CROWN, p.orders, "%d gold" % gold)
		var held := MagicRules.queued_gold(s, CROWN, p.orders)
		var spent := int(TurnResolver.price_recruits(s, CROWN, recruits, null, held).spent)
		assert_true(held + spent <= gold, "%d gold: rituals %d and troops %d fit" % [gold, held, spent])
		assert_true(held <= floori(AIMagic.RITUAL_SHARE * gold), "%d gold: rituals %d are within the share" % [gold, held])
		assert_true(spent > 0, "%d gold: and the troops are still bought" % gold)
		# The casts come before the recruits they were priced for, and no cast army moves.
		var last_cast := -1
		var first_recruit: int = p.orders.size()
		for i in p.orders.size():
			if p.orders[i] is CastOrder:
				last_cast = i
			elif p.orders[i] is RecruitOrder:
				first_recruit = mini(first_recruit, i)
		assert_true(casts.is_empty() or last_cast < first_recruit, "%d gold: the casts are queued before the recruits" % gold)
		var moving := {}
		for o in p.orders:
			if o is MoveOrder:
				moving[o.army_id] = true
		for o in casts:
			assert_false(moving.has(o.army_id), "%d gold: %s casts, so it holds" % [gold, o.army_id])
		cast_somewhere += casts.size()
		if gold >= 60:
			assert_false(casts.is_empty(), "%d gold: it casts (%s)" % [gold, p.notes])
			assert_eq(int(p.stats.get("rituals", 0)), casts.size(), "and the count says so")
	assert_true(cast_somewhere >= 2)


func test_no_ritual_while_the_capital_needs_every_recruit() -> void:
	var calm := _holding_crown(200)
	assert_true(_plan(calm, CROWN).orders.any(func(o): return o is CastOrder), "with the capital safe it casts")
	var threatened := calm.deep_copy()
	_army(threatened, CLANS, "westwatch", _many("war_bear", 14) + ["warchief"], "beasts-big")
	var p := _plan(threatened, CROWN)
	assert_false(p.orders.any(func(o): return o is CastOrder), "an army the garrison cannot beat next door: gold goes to troops, not to rituals: %s" % [p.orders.map(func(o): return o.describe())])
	assert_eq(int(p.stats.get("rituals", 0)), 0)
	assert_true(p.orders.any(func(o): return o is RecruitOrder), "the troops are bought")


# --- Tithe of Blood and the sacrifice pick ----------------------------------------------------------------

func _tithe_board(types: Array, hp: Dictionary = {}, nodes: Array = ["bloodbolt", "bloodrot"], build: Dictionary = TITHE_BUILD) -> GameState:
	var s := _board([["beasts-s", CLANS, "fangridge", types], ["kingdom-e", CROWN, "ebonpeak", ["spearmen"]]], {CLANS: nodes}, {}, 200, {CLANS: build})
	var army := s.find_army("beasts-s")
	for i in hp:
		army.units[int(i)].current_hp = int(hp[i])
	_ruler(s, CLANS).location = "bloodfen"  # the Ninth Fang stands where the Shamans' ritual is not its to cast: out of Bloodrot's reach
	return s


## The hit points the Shamans' army may give and still hold two thirds of its full health (rounded up), by the rule written
## out: its regular units' hit points now, less two thirds of what they could hold.
func _room(s: GameState, army_id: String) -> int:
	var now := 0
	var most := 0
	for u in s.find_army(army_id).units:
		now += u.current_hp
		most += RulerRules.unit_max_hp(s, u)
	return now - (2 * most + 2) / 3


func test_a_shamans_army_pays_in_blood_when_it_can_keep_two_thirds_of_its_hit_points() -> void:
	var healthy := _tithe_board(["shamans"] + _many("tuskers", 6))
	var rot = _cast_of(_rituals(healthy, CLANS).casts, "bloodrot")
	assert_true(rot != null, "it casts Bloodrot")
	assert_eq(rot.pay, CastOrder.BLOOD, "from a Shaman's army that can give the price and keep two thirds")
	var hp: int = int(MagicRules.price(healthy, CLANS, "bloodrot").gold) * MagicData.BLOOD_PER_GOLD
	assert_true(hp <= _room(healthy, "beasts-s"), "%d hit points of the %d it may give" % [hp, _room(healthy, "beasts-s")])
	assert_eq(MagicRules.check_cast(healthy, CLANS, rot, []), {}, "the order is legal")
	assert_eq(_rituals(healthy, CLANS).gold, 0, "and costs no gold")
	# A small army cannot keep two thirds: it pays in gold.
	var small := _tithe_board(["shamans", "tuskers"])
	assert_true(_room(small, "beasts-s") < hp)
	var gold = _cast_of(_rituals(small, CLANS).casts, "bloodrot")
	assert_true(gold != null and gold.pay == CastOrder.GOLD, "too few hit points to give: gold")
	# A garrison that has been bled is not bled again until it has healed: two thirds of its full health, not of what is left.
	var bled := _tithe_board(["shamans"] + _many("tuskers", 6), {1: 10, 2: 10, 3: 10, 4: 10, 5: 10, 6: 10})
	assert_true(_room(bled, "beasts-s") < hp)
	assert_eq(_cast_of(_rituals(bled, CLANS).casts, "bloodrot").pay, CastOrder.GOLD, "already wounded: gold")
	# A Shaman that would be bled below what Bloodbolt needs is left alone: with the soldiers as wounded as it, the Shaman
	# (first in the army) gives first.
	var wounded: Dictionary = {}
	for i in range(1, 19):
		wounded[i] = 10
	var guard := _tithe_board(["shamans"] + _many("tuskers", 18), wounded)
	assert_true(_room(guard, "beasts-s") >= hp, "the army could spare the hit points")
	var plan := MagicRules.blood_plan(guard, "beasts-s", hp)
	assert_true(plan.ok, "the price could be paid in blood")
	assert_true(plan.gives.any(func(g): return MagicRules.is_mage_id(g.type) and g.to < int(MagicData.SPELLS.bloodbolt.min_caster_hp)), "but the Shaman would be the first to give")
	assert_eq(_cast_of(_rituals(guard, CLANS).casts, "bloodrot").pay, CastOrder.GOLD, "so it pays in gold")
	# Without the mandate, always gold. A ruler always pays gold (the Shamans' army is out of it).
	var plain := _tithe_board(["shamans"] + _many("tuskers", 6), {}, ["bloodbolt", "bloodrot"], {"ruler": "fang_chieftain", "mandates": ["iron_discipline"]})
	assert_eq(_cast_of(_rituals(plain, CLANS).casts, "bloodrot").pay, CastOrder.GOLD, "no Tithe of Blood: gold")
	var ruler_only := _board([["kingdom-e", CROWN, "ebonpeak", ["spearmen"]]], {CLANS: ["bloodbolt", "bloodrot"]}, {}, 200, {CLANS: TITHE_BUILD})
	var by_ruler = _cast_of(_rituals(ruler_only, CLANS).casts, "bloodrot")
	assert_true(by_ruler != null and by_ruler.pay == CastOrder.GOLD, "the ruler stands alone: gold")


func test_call_the_pack_in_blood_is_as_big_as_blood_and_gold_allow() -> void:
	var nodes := ["briar_snare", "call_the_pack", "wild_mastery", "beasts_thorn_wild"]
	var each := int(MagicData.SPELLS.call_the_pack.cost)
	# Plenty of soldiers: the pack is the biggest one allowed and paid in blood.
	var big := _tithe_board(["shamans"] + _many("tuskers", 8), {}, nodes)
	var sizes := MagicRules.pack_sizes(big, CLANS, big.find_army("beasts-s"))
	var cast = _cast_of(_rituals(big, CLANS).casts, "call_the_pack")
	assert_true(cast != null and cast.pay == CastOrder.BLOOD and cast.size == int(sizes[1]), "the full pack, in blood: %s" % [cast.to_dict() if cast else "none"])
	assert_eq(_rituals(big, CLANS).gold, 0, "for no gold")
	# Few soldiers: blood pays for fewer wolves than the gold share does, so it takes the bigger pack, in gold.
	var thin := _tithe_board(["shamans"] + _many("tuskers", 3), {}, nodes)
	var by_blood := _room(thin, "beasts-s") / each
	var by_gold := floori(AIMagic.RITUAL_SHARE * 200.0) / each
	assert_true(by_blood < mini(int(sizes[1]), by_gold) and by_blood >= int(sizes[0]), "blood pays for %d wolves, gold for %d" % [by_blood, by_gold])
	var got = _cast_of(_rituals(thin, CLANS).casts, "call_the_pack")
	assert_true(got != null and got.pay == CastOrder.GOLD and got.size == mini(int(sizes[1]), by_gold), "the bigger pack, in gold: %s" % [got.to_dict() if got else "none"])
	# Gold for none (a share too small for the smallest pack): blood for what it can.
	var poor := _board([["beasts-s", CLANS, "fangridge", ["shamans"] + _many("tuskers", 3)], ["kingdom-e", CROWN, "ebonpeak", ["spearmen"]]], {CLANS: nodes}, {}, 20, {CLANS: TITHE_BUILD})
	_ruler(poor, CLANS).location = "bloodfen"
	var in_blood = _cast_of(_rituals(poor, CLANS).casts, "call_the_pack")
	assert_true(in_blood != null and in_blood.pay == CastOrder.BLOOD and in_blood.size == by_blood, "20 gold is too little: the pack is paid in blood")


func test_the_sacrifice_pick_puts_tithe_of_blood_first_for_blood_of_the_fang_in_a_game_with_magic() -> void:
	var magic := _board([])
	var picks := ["blood_frenzy", "veteran_levies"]
	assert_eq(AIMagic.sacrifice_picks(magic, "blood_of_the_fang", picks), ["tithe_of_blood", "blood_frenzy", "veteran_levies"])
	assert_eq(AIMagic.sacrifice_picks(magic, "clan_moot", picks), picks, "no other preset")
	assert_eq(AIMagic.sacrifice_picks(magic, "", picks), picks, "no build of its own")
	assert_eq(AIMagic.sacrifice_picks(GameState.with_paths(5), "blood_of_the_fang", picks), picks, "and nothing without magic")
	# In play: behind from turn 8, it sacrifices for Tithe of Blood first, then for what the preset lists.
	var s := _board([["kingdom-1", CROWN, "crownkeep", ["knights", "knights", "knights", "spearmen", "spearmen"]], ["beasts-1", CLANS, "fangridge", ["tuskers"]]],
		{}, {"westwatch": CROWN, "highcrag": CROWN, "rivermarch": CROWN, "stonegate": CROWN, "greenglade": CROWN, "thornvale": CROWN, "wildmoor": CROWN, "deepwood": CROWN})
	s.current_turn = 7
	var p := _plan(s, CLANS)
	assert_true(p.orders[0] is SacrificeOrder, "turn 8 and behind: it sacrifices: %s" % [p.orders.map(func(o): return o.describe())])
	assert_eq(p.orders[0].mandate_id, "tithe_of_blood", "for Tithe of Blood")
	assert_true(" ".join(p.notes).contains("for Tithe of Blood"), " ".join(p.notes))
	_assert_legal(s, CLANS, p.orders, "the sacrifice")
	var again := s.deep_copy()
	RulerRules.apply_sacrifice(again, CLANS, "tithe_of_blood", 1)
	var next := _plan(again, CLANS)
	assert_eq(RulerRules.kept_power(again, CLANS), 1, "the Tithe took the Ninth Fang's power down to 1")
	assert_false(next.orders.any(func(o): return o is SacrificeOrder), "and nothing else is affordable after it")
	# The same board in a game with paths and no magic: the preset's own first pick, as on main.
	var plain := GameState.with_paths(7, {CROWN: "regents_court", CLANS: "blood_of_the_fang"})
	_own_all(plain)
	plain.current_turn = 7
	var q := _plan(plain, CLANS)
	assert_true(q.orders[0] is SacrificeOrder and q.orders[0].mandate_id == "blood_frenzy", "without magic: Blood Frenzy first")


func _own_all(s: GameState) -> void:
	for pid in ["westwatch", "highcrag", "rivermarch", "stonegate", "greenglade", "thornvale", "wildmoor", "deepwood"]:
		s.find_province(pid).owner = CROWN


# --- the plan in words, and what it never does -------------------------------------------------------------

func test_the_notes_say_what_is_cast_and_why_in_plain_words() -> void:
	var s := _holding_crown(200)
	var p := _plan(s, CROWN)
	var said: String = " ".join(p.notes)
	assert_true(said.contains("Casting Sanctum Ward on Crownkeep, from the Ever-Regent at Crownkeep, %d gold: the Thornmane Clans hold Westwatch, 1 move from Crownkeep, and can curse." % int(MagicData.SPELLS.sanctum_ward.cost)), said)
	assert_true(said.contains("Casting Dawn Blessing on Crownkeep"), said)
	for raw in ["sanctum_ward", "dawn_blessing", "kingdom-", "beasts-", "crownkeep"]:
		assert_false(said.contains(raw), "no raw id in the notes: %s" % raw)
	var casts: Array = p.orders.filter(func(o): return o is CastOrder)
	assert_eq(int(p.stats.get("rituals", 0)), casts.size())
	assert_eq(int(p.stats.get("cast_sanctum_ward", 0)), 1)


func test_the_plan_never_casts_from_an_army_that_moves_or_attacks() -> void:
	# Across plans of many boards: an army with a cast order has no move order, and an army ordered to attack has no cast.
	var plans := 0
	var casts := 0
	for gold in [60, 120, 200]:
		for enemy in [3, 5, 8, 14]:
			var s := _holding_crown(gold)
			s.find_army("beasts-e").units.clear()
			var f := s.find_faction(CLANS)
			for i in enemy:
				s.find_army("beasts-e").units.append(Unit.new(TurnResolver.recruitable_type(f, "tuskers", s), CLANS))
			for fid in [CROWN, CLANS]:
				var p := _plan(s, fid)
				_assert_legal(s, fid, p.orders, "%s, %d gold, %d tuskers" % [fid, gold, enemy])
				var moving := {}
				for o in p.orders:
					if o is MoveOrder:
						moving[o.army_id] = o.to
				for o in p.orders:
					if o is CastOrder:
						casts += 1
						assert_false(moving.has(o.army_id), "%s casts %s and holds" % [o.army_id, o.ritual])
						var army := s.find_army(o.army_id)
						assert_true(army.owner == fid and not MagicRules.casters(s, army).is_empty(), "from an army with a caster in it")
				plans += 1
	assert_true(casts > 0, "and it did cast (%d casts in %d plans)" % [casts, plans])


func test_it_never_pins_an_army_that_would_attack() -> void:
	# The Adepts are in the army that attacks the enemy next door. Whatever the rules say, that army is not cast from.
	var s := _board([
		["kingdom-m", CROWN, "highcrag", _many("knights", 5) + ["spearmen", "adepts", "knight_captain"]],
		["beasts-e", CLANS, "thornvale", ["tuskers"]],
	], {CROWN: CROWN_FORGE}, {"highcrag": CROWN, "thornvale": CLANS}, 200, {}, {CROWN: "fangridge"})
	var p := _plan(s, CROWN)
	var attack = p.orders.filter(func(o): return o is MoveOrder and o.army_id == "kingdom-m" and o.to == "thornvale")
	assert_eq(attack.size(), 1, "the army attacks: %s" % [p.orders.map(func(o): return o.describe())])
	assert_false(p.orders.any(func(o): return o is CastOrder and o.army_id == "kingdom-m"), "and it is not pinned by a cast")
	_assert_legal(s, CROWN, p.orders, "an attack with a mage in it")


func test_the_magic_code_draws_no_dice_and_reads_no_clock() -> void:
	var code := _code(AI_MAGIC)
	assert_true(code.length() > 2000, "the file was read")
	for token in ["_rng", "randi", "randf", "RandomNumberGenerator", "SeededRNG", "shuffle", "pick_random", "randomize", "Time.", "OS."]:
		assert_false(code.contains(token), "ai_magic.gd uses no %s (design/M5_MAGIC_FOG.md §10.2: every choice is a rule, ties by id)" % token)
	# And it does not change the seat's dice: planning the same state twice leaves the generator where it was both times.
	var s := _holding_crown(200)
	assert_eq(_plan(s, CROWN).rng, _plan(s, CROWN).rng)
	assert_eq(_plan(s, CROWN).json, _plan(s, CROWN).json, "the same state gives the same plan, byte for byte")


## The code of `path` without its comments and the text inside quotes.
func _code(path: String) -> String:
	var out := []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var kept := ""
		var quote := ""
		for ch in line:
			if quote.is_empty():
				if ch == "#":
					break
				if ch == "\"" or ch == "'":
					quote = ch
				kept += ch
			else:
				if ch == quote:
					quote = ""
					kept += ch
		out.append(kept)
	return "\n".join(out)


# --- under fog: the magic plan reads only the view ----------------------------------------------------------

func test_the_magic_plan_ignores_what_the_view_hides() -> void:
	var specs := [
		["kingdom-g", CROWN, "crownkeep", _many("spearmen", 6) + ["knights", "knights", "adepts"]],
		["kingdom-h", CROWN, "highcrag", ["spearmen", "adepts"]],
		["beasts-e", CLANS, "westwatch", _many("tuskers", 5)],
		["beasts-far", CLANS, "fangridge", ["shamans", "tuskers", "tuskers"]],
	]
	var owners := {"westwatch": CLANS, "highcrag": CROWN, "rivermarch": CROWN}
	# (A rival's Oath would show in its view only if the Crown had been told of it, so these nodes are the unsworn ones.)
	var a := _fogged(_board(specs, {CROWN: CROWN_FORGE, CLANS: ["bloodbolt", "bloodrot"]}, owners, 200))
	# The same game with everything the Crown cannot see changed: the rival's gold, its research (no Bloodrot at all, other
	# nodes instead), its spellbook, a ward on its capital, and what stands at its capital.
	var b := _fogged(_board(specs, {CROWN: CROWN_FORGE, CLANS: ["briar_snare", "call_the_pack"]}, owners, 200))
	b.find_faction(CLANS).gold = 17
	b.find_faction(CLANS).research_points = 33
	b.find_faction(CLANS).spellbook = {"order": ["bloodbolt", "briar_snare"], "off": ["bloodbolt"]}
	b.find_army("beasts-far").units.clear()
	for t in _many("war_bear", 4):
		b.find_army("beasts-far").units.append(Unit.new(TurnResolver.recruitable_type(b.find_faction(CLANS), t, b), CLANS))
	var view_a := _view(a)
	var view_b := _view(b)
	assert_eq(JSON.stringify(view_b.to_dict()), JSON.stringify(view_a.to_dict()), "the Crown's views are byte-identical")
	var pa := _plan(view_a, CROWN)
	var pb := _plan(view_b, CROWN)
	assert_eq(pb.json, pa.json, "and so is everything the magic plan says: orders, notes, counters and dice")
	assert_true(pa.orders.any(func(o): return o is CastOrder and o.ritual == "sanctum_ward"), "it warded ahead on the assumption that the rival can curse")
	_assert_legal(a, CROWN, pa.orders, "on the true state")
	_assert_legal(b, CROWN, pb.orders, "on the other true state")
	# Not vacuous: without fog the rival's research is public, and the two games are told apart.
	var open_a := a.deep_copy()
	open_a.fog = false
	var open_b := b.deep_copy()
	open_b.fog = false
	assert_ne(_plan(open_a, CROWN).json, _plan(open_b, CROWN).json, "without fog the plans differ (a rival with no Bloodrot is not warded against)")
	# The leak a seat could make: handed the truth instead of the view, the plan differs.
	assert_ne(_plan(a, CROWN).json, _plan(b, CROWN).json, "handed the truth, the brain would plan differently")


func test_the_codex_says_how_the_computer_plays_magic() -> void:
	var text := RulesCodex.text("computer_opponent")
	for part in ["In a game with magic", "researches its faction's spells", "recruits mages", "one for every %d regular units" % AIMagic.MAGE_PER,
			"at most %d%% of the gold" % AIMagic.RITUAL_SHARE_PCT, "never from an army it has sent to attack", "wards its capital ahead",
			"pays a ritual in blood", "what it cast and why"]:
		assert_true(text.contains(part), "the entry says '%s': %s" % [part, text])
	for part in ["fog of war", "its own view", "same rules", "Easy", "Normal"]:
		assert_true(text.contains(part), "and still '%s'" % part)
	assert_false(text.contains("[") or text.contains("_"), "plain text, so tooltips can quote it")


func test_a_brain_never_asks_a_session_for_the_truth_when_it_casts() -> void:
	var source := _code("res://ai/ai_magic.gd")
	for forbidden in [".state()", ".turn_report()", ".record()", ".history()", "OBSERVER", "TurnResolver.resolve", "turn_seed", "FogRules.turn_for"]:
		assert_false(source.contains(forbidden), "ai_magic.gd never uses %s" % forbidden)


# --- 5. games: zero rejections, the same seed, the same everything ---------------------------------------

## A person (the greedy script) against the computer for up to `turns` turns, with magic. Returns what the test compares:
## {"record" (JSON), "rejections", "turns", "casts" (ritual -> count), "researched" (the computer's nodes, in order), "mages"}.
func _versus(ai_fid: String, level: String, fog: bool, game_seed: int, turns: int = 30, policy: String = "turtle") -> Dictionary:
	var human := CROWN if ai_fid == CLANS else CLANS
	var state := GameState.with_magic(game_seed, {})
	assert_true(state != null, "a magic game")
	if policy == "turtle":
		state.find_faction(human).gold = 300  # a person who can hold out
	if fog:
		state.setup_fog([])
	var session := GameSession.new(state, SEATS, game_seed, AutoBattleResolver.new(), {ai_fid: level})
	var computer := AISeat.new(session, game_seed)
	var person = _policy_named(policy)
	person.configure(game_seed, SEATS.find(human))
	var rng := SeededRNG.new(99 if policy == "turtle" else AISeat.seat_seed(game_seed, SEATS.find(human)))
	var played := 0
	computer.play(session)
	while not session.is_over() and played < turns:
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		if session.current_player() != human:
			break
		for o in person.orders(session.state(), human, rng):
			session.queue_order(o)
		assert_eq(session.end_turn(), "", "the person ends turn %d" % (played + 1))
		computer.play(session)
		played += 1
	var casts := {}
	var mages := 0
	for h in session.history():
		for o in h.orders.get(ai_fid, []):
			if o.type == "cast":
				casts[o.ritual] = int(casts.get(o.ritual, 0)) + 1
				assert_ne(o.pay, "", "a cast says how it is paid")
			elif o.type == "recruit" and MagicRules.is_mage_id(String(o.unit_type)):
				mages += 1
	return {"record": JSON.stringify(session.record()), "rejections": computer.rejections(), "turns": session.turns_played(),
		"casts": casts, "researched": AscensionRules.researched(session.state(), ai_fid), "mages": mages, "over": session.is_over(),
		"history": session.history()}


func _policy_named(policy_name: String):
	return preload("res://tools/autoplay/policies.gd").make(policy_name)


func test_thirty_turns_of_a_person_against_the_computer_with_magic_give_zero_rejections() -> void:
	var total := 0
	var all_casts := {}
	var researched := 0
	for ai_fid in [CLANS, CROWN]:
		for level in ["normal", "easy"]:
			for fog in [false, true]:
				var what := "%s %s %s" % [ai_fid, level, "fog" if fog else "no fog"]
				var a := _versus(ai_fid, level, fog, 41)
				assert_eq(a.rejections, [], "%s: the computer's orders are never refused" % what)
				assert_true(a.turns >= 8, "%s: the game ran (%d turns)" % [what, a.turns])
				total += int(a.turns)
				var b := _versus(ai_fid, level, fog, 41)
				assert_eq(b.record, a.record, "%s: the same seed gives the same orders, turn by turn" % what)
				assert_eq(b.researched, a.researched, "%s: the same research" % what)
				assert_eq(b.casts, a.casts, "%s: the same rituals" % what)
				for r in a.casts:
					all_casts[r] = int(all_casts.get(r, 0)) + int(a.casts[r])
				researched += a.researched.size()
				_check_holds(a.history, ai_fid, what)
	# Longer games: a person as good as the computer (the autoplay's brain at the keyboard), so the game goes the 30 turns.
	var long_turns := 0
	for ai_fid in [CLANS, CROWN]:
		for fog in [false, true]:
			var what := "%s vs a strong person, %s" % [ai_fid, "fog" if fog else "no fog"]
			var a := _versus(ai_fid, "normal", fog, 43, 30, "ai")
			assert_eq(a.rejections, [], "%s: the computer's orders are never refused" % what)
			long_turns += int(a.turns)
			var b := _versus(ai_fid, "normal", fog, 43, 30, "ai")
			assert_eq(b.record, a.record, "%s: the same seed gives the same orders, turn by turn" % what)
			assert_eq(b.researched, a.researched, "%s: the same research" % what)
			assert_eq(b.casts, a.casts, "%s: the same rituals" % what)
			for r in a.casts:
				all_casts[r] = int(all_casts.get(r, 0)) + int(a.casts[r])
			researched += a.researched.size()
			_check_holds(a.history, ai_fid, what)
	assert_true(total >= 100, "the games ran %d turns in all" % total)
	assert_true(long_turns >= 60, "and the long ones ran %d turns" % long_turns)
	assert_true(researched >= 16, "and the computers researched (%d nodes)" % researched)
	assert_true(all_casts.size() >= 1, "and cast: %s" % [all_casts])


## No army has a cast order and a move order in the same turn (a cast holds its army).
func _check_holds(history: Array, fid: String, what: String) -> void:
	for h in history:
		var casting := {}
		var moving := {}
		for o in h.orders.get(fid, []):
			if o.type == "cast":
				casting[o.army] = true
			elif o.type == "move":
				moving[o.army] = true
		for id in casting:
			assert_false(moving.has(id), "%s turn %d: %s casts and does not move" % [what, h.turn, id])


func test_computer_against_computer_with_magic_finishes_and_is_never_refused() -> void:
	var games := 0
	var battles := 0
	var casts := {}
	var mages := 0
	var fought := 0
	for pair in [["regents_court", "blood_of_the_fang"], ["warrior_king", "beast_god_unbound"], ["iron_crown", "clan_moot"]]:
		for game_seed in [3, 4]:
			for fog in [false, true]:
				var state := GameState.with_magic(game_seed, {CROWN: RulerRules.preset_build(pair[0]), CLANS: RulerRules.preset_build(pair[1])})
				if fog:
					state.setup_fog([])
				var session := GameSession.new(state, SEATS, game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
				var ai := AISeat.new(session, game_seed)
				while not session.is_over() and session.turns_played() < 80:
					if ai.play(session).played.is_empty():
						break
				var what := "%s v %s, seed %d%s" % [pair[0], pair[1], game_seed, ", fog" if fog else ""]
				assert_eq(ai.rejections(), [], "%s: no order refused" % what)
				assert_true(session.is_over(), "%s: the game finished (%d turns)" % [what, session.turns_played()])
				battles += session.battles_fought()
				fought += 1 if session.battles_fought() > 0 else 0
				for h in session.history():
					for fid in SEATS:
						for o in h.orders.get(fid, []):
							if o.type == "cast":
								casts[o.ritual] = int(casts.get(o.ritual, 0)) + 1
							elif o.type == "recruit" and MagicRules.is_mage_id(String(o.unit_type)):
								mages += 1
				_check_holds(session.history(), CROWN, what)
				_check_holds(session.history(), CLANS, what)
				games += 1
	assert_eq(games, 12)
	assert_true(battles >= games, "the computers still fight (%d battles in %d games)" % [battles, games])
	assert_true(fought >= games / 2, "most games had a battle (%d of %d)" % [fought, games])
	assert_true(mages > 0, "they recruit mages (%d)" % mages)
	assert_true(casts.size() >= 3, "and cast several kinds of ritual: %s" % [casts])


func test_magic_with_forts_sieges_free_holds_and_fog_is_never_refused() -> void:
	var casts := {}
	for flags in [["sieges"], ["sieges", "independents", "fog"]]:
		for game_seed in [5, 6]:
			var state := GameState.with_magic(game_seed, {CROWN: RulerRules.preset_build("regents_court"), CLANS: RulerRules.preset_build("blood_of_the_fang")})
			if flags.has("sieges"):
				assert_true(state.setup_sieges([]), "forts and sieges")
			if flags.has("independents"):
				assert_true(state.setup_independents([]), "Free Holds")
			if flags.has("fog"):
				assert_true(state.setup_fog([]), "fog")
			var session := GameSession.new(state, SEATS, game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
			var ai := AISeat.new(session, game_seed)
			while not session.is_over() and session.turns_played() < 40:
				if ai.play(session).played.is_empty():
					break
			var what := "%s, seed %d" % ["+".join(flags), game_seed]
			assert_eq(ai.rejections(), [], "%s: no order refused" % what)
			assert_true(session.turns_played() >= 8, "%s: the game ran (%d turns)" % [what, session.turns_played()])
			_check_holds(session.history(), CROWN, what)
			_check_holds(session.history(), CLANS, what)
			# A siege order and a cast never name the same army (a sally or a storm is a job, a cast holds).
			for h in session.history():
				for fid in SEATS:
					var cast_by := {}
					for o in h.orders.get(fid, []):
						if o.type == "cast":
							cast_by[o.army] = true
							casts[o.ritual] = int(casts.get(o.ritual, 0)) + 1
					for o in h.orders.get(fid, []):
						if o.type == "siege" and o.get("action", "") == "sally":
							assert_false(cast_by.has(o.army), "%s turn %d: a sallying army does not cast" % [what, h.turn])
	assert_true(casts.size() >= 1, "and they cast: %s" % [casts])


# --- 6. with magic off, the games of main ----------------------------------------------------------------

func _fixture_games() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data.get("games", []) if data is Dictionary else []


func test_with_magic_off_the_seat_plays_the_games_of_main() -> void:
	# The fixture's games with both seats played by AISeat: the same orders turn by turn as main recorded.
	var ran := 0
	for g in _fixture_games():
		var spec: Dictionary = g.spec
		if spec.policies != ["ai", "ai"] or (bool(spec.get("paths", false)) and spec.branches != ["", ""]):
			continue
		var start := GameState.from_dict(g.record.start_state, [])
		assert_false(start.magic, "%s: no magic" % g.name)
		var game_seed := Serial.to_int(g.record.game_seed)
		var session := GameSession.new(start, SEATS, game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
		var ai := AISeat.new(session, game_seed)
		var want: Array = g.record.history
		while not session.is_over() and session.turns_played() < want.size():
			if ai.play(session).played.is_empty():
				break
		assert_eq(session.turns_played(), want.size(), "%s: as many turns" % g.name)
		var got := session.history()
		for t in mini(got.size(), want.size()):
			assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(got[t].orders))), JSON.stringify(want[t].orders),
				"%s turn %d: the seat gives main's orders" % [g.name, t + 1])
			for fid in SEATS:
				assert_false(JSON.stringify(got[t].orders.get(fid, [])).contains("\"cast\""), "%s: no ritual without magic" % g.name)
		ran += 1
	assert_true(ran >= 4, "M1, M2 and M4 games ran (%d)" % ran)


func test_with_magic_off_nothing_of_the_magic_ai_runs() -> void:
	var s := GameState.with_paths(12, {CROWN: "regents_court", CLANS: "blood_of_the_fang"})
	assert_false(s.magic)
	assert_eq(AIMagic.cast_profiles(s), {}, "no spells to value")
	var p := _plan(s, CROWN)
	assert_false(p.orders.any(func(o): return o is CastOrder), "no cast")
	for key in p.stats:
		assert_false(String(key).begins_with("cast_") or key == "rituals" or key == "blood_paid", "no magic counter: %s" % key)
	var ai := AIPlayer.new()
	ai._begin(s, CROWN, SeededRNG.new(1), "normal")
	assert_eq(ai._ctx.get("casts", {}), {}, "the plan's numbers hold no spells")
	ai._magic.plan()
	assert_eq(ai._magic.casts, [])
	assert_eq(ai._ritual_gold, 0, "and no gold is held back")
	assert_eq(AIMagic.sacrifice_picks(s, "blood_of_the_fang", ["blood_frenzy"]), ["blood_frenzy"])
