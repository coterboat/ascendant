class_name AIPlayer
extends RefCounted
## Computer opponent (pre-M2 "AI player brain"). Pure code: no nodes, no scenes.
##
##   var ai := AIPlayer.new()
##   var orders: Array = ai.plan_orders(state, "beasts", SeededRNG.new(seed), "normal")
##   var why: Array = ai.last_plan_notes()   # plain-language reasons, for a "what is the AI doing" tooltip
##
## plan_orders reads the start-of-turn state (it never changes it) and returns MoveOrder and
## RecruitOrder objects for `faction_id`. Every move is pre-checked with TurnResolver.check_move and
## every recruit with TurnResolver.price_recruits, so the rules accept each order it returns. In a game
## with sieges it also returns SiegeOrder and FortifyOrder objects (ai/ai_sieges.gd, design/M3C_SIEGES.md §8),
## checked with SiegeRules.check_siege_order and TurnResolver.price_recruits.
## Determinism: the same state, rng state and difficulty always give the same orders. Armies,
## provinces and factions are walked in sorted id order, and every random choice (tie-breaks, and the
## easy level's skipped moves and recruits) comes from `rng`.
##
## Strategy, in priority order each turn:
##   1. Capital first. Enemy armies next to the capital can attack it this turn: the armies in the
##      capital hold, and armies next door are recalled until Forecast.battle_odds, run from the
##      enemy's side so the garrison defends with terrain and fort, calls the capital a likely win as
##      defender (or nobody is left to recall). The capital is never left open: the only exception
##      is a sally, when every adjacent enemy army stands in one province and the garrison alone
##      crushes it (SALLY_WIN); that army can then only get in by beating the garrison on the
##      border. Enemy armies two or three moves away keep the garrison home when this turn's
##      recruits alone would not hold the capital against them.
##   2. Enemy capital. An undefended enemy capital next to a free army is walked into (it wins the
##      game). A defended one is attacked once the odds are at least even.
##   3. Battles. Free armies next to an enemy army attack it together when the odds are a likely win,
##      or merely close when that enemy army stands next to a capital we might not hold. The odds
##      count the enemy armies next to the target as if they move in and join the defense. Targets
##      are taken in order of the enemy strength we expect to destroy; stragglers are not worth a step
##      away from the enemy capital.
##   4. Field moves. Armies next to a stronger enemy pull back. Others take safe, undefended
##      provinces for income. The strongest free army pushes toward the enemy capital while the road
##      is safe and it has most of our nearby strength with it (MASS_SHARE); otherwise it waits and
##      every other free army marches to join it, so attacks are made by massed armies.
##   5. Recruits. All gold is spent at the capital (recruits double as the garrison), on the mix that
##      most raises the rough odds of the army that will stand there against the enemy's armies, with
##      a commander first when the capital is threatened and nobody there has one.
## Unit strengths are never hardcoded. The rough strength guess (_power_units) uses only unit stats
## from the state, and only ranks options and skips forecasts that cannot change a decision. Every
## decision that risks an army or the capital is checked with Forecast.battle_odds, which fights the
## real battle rules; calls are capped per plan (ODDS_BUDGET, MAX_ODDS_CALLS) and cached within a plan.
##
## Games with rulers (M2, design/M2_RULER.md §6.1, §6.3; ticket M2-7, #35):
##   * Build: choose_build(state, faction, rng) is the AI seat's build, presets[faction][rng.randi_range(0, 2)]
##     (BuildPresetData), the first draw of the seat's RNG. The build screen's computer seats and AISeat
##     both call it. plan_orders plays whatever build the state holds: preset_for() finds the preset by
##     its ruler and pre-game mandates, which gives the ruler role and the sacrifice picks.
##   * Sacrifice, first, at most one per turn and only when RulerRules.sacrifice_check allows it: the
##     preset's first affordable pick, when an enemy army next to the capital could win there (the
##     defenders' odds are close or a likely loss), or from turn SACRIFICE_TURN when our income is at
##     most SACRIFICE_INCOME_SHARE of the strongest enemy's. The rest of the plan is made on the state
##     with the sacrifice applied (RulerRules.with_sacrifice), the state OrderBook checks it against.
##   * Ruler: the ruler's army is planned on its own, never as part of a group. A ruler with the "home"
##     role, or on a build of its own keeping LOW_KEPT power or less, stays at (or walks back to) the
##     capital. A preset's ruler plays its preset's role (#131: every preset's is "field", the spend
##     presets' 0-kept rulers too, since mandates outlive a ruler). A
##     "field" ruler goes with the strongest army (hp x attack), joins its attack only when the
##     forecast with the ruler is RULER_JOIN_WIN or better, and never ends a turn alone next to an
##     enemy army or where the forecast as defender is below RULER_GUARD_WIN; otherwise it holds or
##     falls back toward the capital.
##   * Mandates: road moves (King's Roads) when they shorten a march, a return home or a recall, and
##     recruits with the Ninth Fang (Warband Muster) wherever it stands in its own land, unless the
##     capital needs the defenders. Muster Grounds prices come from RulerRules.recruit_price.
##   * Recruits are trait-aware (_recruit_value): Shield Wall, Charge, Berserk, Inspire, Pack Leader,
##     Fury, Volley and Skirmish are valued with AutoBattleResolver's own trait constants, a Volley unit
##     is only recruited while at least as many front-rank units stand with it (the shield holds), and
##     Skirmish is worth more the more Volley units the enemy fields.
##   * Our own ruler is left out of the rough strength guess and enemy rulers are counted in it, which
##     errs on the safe side whether or not battles count rulers yet; every battle that risks our ruler
##     is checked with the forecast, which fights the real battle rules.
##   * The rough strength guess (#131, every game) judges when a side breaks as the battle rules do: its
##     commander's, Inspire's and its ruler's morale, less the foe's Fury and Dread; Iron Discipline holds
##     while a commander stands; Drilled Ranks' base hit; unit numbers from RulerRules.unit_stats.
##
## Games with paths (M4, design/M4_ASCENSION.md §8; ticket M4-5, #70). #131: the unit numbers, the hp a
## recruit arrives with and the threats by road move below hold in every game (they are the rules' own and
## so are right without paths too); the rest runs only with paths:
##   * Research: the build preset's plan (AIPaths.AI_PATHS): its ordinary nodes, then the chosen side's
##     Oath and transformation, then the rest. A ResearchOrder only when our own target is empty or off the
##     plan, pre-checked with AscensionRules.check_research. The side of the fork is choose_branch, a seeded
##     roll on its own stream (AIPaths.BRANCH_SALT), never the seat RNG. configure(game_seed, seat) tells the
##     brain whose seat it plays (AISeat and the autoplay do); otherwise the state's seed and the faction's
##     place in it stand in. A rival's research target is never read: only its completed nodes and side.
##   * Recruits: unit numbers come from RulerRules.unit_stats (mandates and path parts), recruits arrive at
##     the hp the recruitment phase gives (Blood Levy included), and the new traits are valued with the
##     battle rules' constants: Wings (worth more the more commanders the enemy fields; it reaches the
##     second rank like Skirmish), Iron Hide (each enemy hit deals IRON_HIDE_DAMAGE less, which hurts many
##     small hits most), Rooted (#94: a forest battle, with its ROOTED_DEFENSE, or an open one, weighted by the
##     share of forest provinces on our front) and Lifedrinker (#94: each hit heals its damage over
##     LIFEDRINK_DIVISOR rounded up, from the first round for a recruit that arrives wounded, else LIFEDRINK_SHARE
##     of the time; healing lands before morale is checked, so it counts in full against breaking).
##   * Wounded units (#94): a unit's maximum hp is known with paths, so one below it (every Blood Levy recruit
##     arrives so) counts Berserk and Blood Frenzy in full, in the rough guess and in recruiting; the others
##     count them BERSERK_SHARE of the time in recruiting, as before.
##   * Moves: Forest Stride road moves follow the King's Roads logic (marches, returns home, recalls), and
##     enemy armies that can reach a province by a road move this turn count as threats to it (the capital
##     checks and every "is this step safe" check).
##   * Captures: a province is worth the income we would draw from it with our path lines (Market Charters,
##     Deep Mines, Bounty of the Wild, Tithe of Light, Forge Tithe), plus what its owner loses, plus
##     RAID_WEIGHT of the Raiding Parties windfall.
##   * Sacrifice: once transformed, the mandate the transformation opened goes last in the preset's picks;
##     a forsworn pick is skipped (RulerRules.sacrifice_check refuses it).
##   * Notes name only what is public: nodes already completed, the side once sworn and its transformation
##     (which the Oath's own report names as the next research). The target is never named before it is done.
##
## Stand-offs (#94; every game, with or without rulers and paths). When neither side can win an attack, both
## used to recruit into their capitals forever. standoff_info reads a stand-off from the state alone (every unit
## we field and our treasury, at recruit prices, worth STANDOFF_TURNS turns of income: the pile a quiet game
## builds), and the plan then breaks it by position: it hunts the enemy army that keeps the garrison home (the
## garrison marches out), besieges the enemy capital past guarded roads where it is at least even, or raids the
## foe's unguarded provinces; attacks at even odds (STANDOFF_WIN) are made, and the garrison sallies at a
## likely win. Its notes say so in plain words ("Breaking the stand-off: ..."), and the turn report shows them
## once the turn resolves (AISeat.report_notes). Nothing is kept between turns.
## Gold is never banked: when every recruit adds only a sliver against an overwhelming foe, the best sliver buys.
##
## Fog of war (M5-4, #115; design/M5_MAGIC_FOG.md §10.1; ai/ai_fog.gd). In a fog game the state it is handed is the
## seat's VIEW (FogRules.view_state), and it plans from that alone: a rival's armies are the stand-ins it sighted or
## remembers, at the shown numbers. Nothing else changes in how it reads a state, so the same view always gives the
## same orders, whatever is hidden from it. Four rules are new, all rules with no draw from the seat's RNG:
##   * Remembered armies older than AIFog.MEMORY_TRUST turns are dropped from the view before the plan is made.
##   * Attacks are judged against the shown numbers, as a person sees them; the defence of the capital (the garrison,
##     the recall, the sacrifice, the ruler's safety) is judged against the top of each sighting's total (AIFog.top).
##   * When the objective is out of sight, the nearest free scout army takes one safe step toward it (AIFog.scout).
##   * Its notes say what it did and why in the same plain words ("Scouting: ..."); the screen keeps them back until
##     the game is over (AISeat.report_notes).
##
## Temperament (#184). Each computer seat plays "normal" or "aggressive", a pure roll of the game seed and the seat
## (choose_temperament, a stream of its own: TEMPERAMENT_SALT), set with set_temperament before the first plan; AISeat
## rolls it, and the new game screen shows it. With "normal" nothing below changes, so every normal game is the same as
## before. The aggressive computer discounts the risk of a fight by RISK_DISCOUNT: it storms, besieges, stays in a siege,
## attacks through a breach, attacks an army and attacks a capital at odds that much worse; it reads a stand-off at
## AGGRESSIVE_STANDOFF of the pile; and when a held fort or capital stops its main army, it goes around it to take a
## province from the Free Holds or raid (_go_around) instead of massing at the walls. Its first turn's note says so in plain words.
##
## Games with magic (M5-10, #121; design/M5_MAGIC_FOG.md §10.2; ai/ai_magic.gd). Every rule is a rule with ties by id and no
## draw from the seat's RNG; with magic off none of it runs and games are the same as before:
##   * Research: AIPaths.sequence puts the arcana in the plan (the aligned school's tier I after the first ordinary node, then
##     the path, then the aligned tier II, tier III and mastery, the other ordinary nodes, the other school's spells).
##   * Mages: _side_summary counts a mage in the second rank and AIMagic.mage_pressure values its spells with the battle
##     rules' numbers (a bolt, or what a hex or a shield moves), so _recruit_value buys mages for what they add; _plan_recruits
##     keeps at most one mage for every AIMagic.MAGE_PER regular units and never more second-rank fighters than front-rank ones.
##   * Rituals: AIMagic.plan, after the moves, casts at most one ritual from each army that holds anyway (never one with a move
##     order, so never one ordered to attack), in the order of §10.2's table; they take at most AIMagic.RITUAL_SHARE of the gold
##     the troops leave and none in a turn the capital needs its recruits. The gold is set aside first (_ritual_gold) and the
##     recruits are priced from the rest. A Shamans' army pays in blood under Tithe of Blood when it keeps two thirds of its hp.
##   * The sacrifice: Blood of the Fang puts Tithe of Blood first in its picks (AIMagic.sacrifice_picks).
##   * Its notes say "Casting Sanctum Ward on Crownkeep ...: why" in plain words.

const DIFFICULTIES := ["easy", "normal"]

## Win rates the AI acts on (Forecast.battle_odds labels LIKELY_WIN or more "likely win").
const LIKELY_WIN := 0.65
## Attacking an enemy army that stands next to our capital: "close" is good enough.
const URGENT_WIN := 0.45
## Attacking the enemy capital, which wins the game: at least even odds.
const CAPITAL_WIN := 0.5
## Capital defense: our win rate as defender we want before we stop recalling armies.
const HOLD_TARGET := {"easy": 0.5, "normal": 0.65}
## Forecast budget per plan, in rough milliseconds: each Forecast.battle_odds call fights the real
## battle many times, costing about ODDS_BASE + ODDS_PER_FIGHTER x f + ODDS_PER_FIGHTER_SQ x f^2 for
## f fighters (long, even battles between big armies cost the most). A capital defense check may
## overdraw the budget by up to ESSENTIAL_OVERDRAFT; past that the rough guess decides.
const ODDS_BUDGET := {"easy": 35.0, "normal": 60.0}
const ODDS_BASE := 6.0
const ODDS_PER_FIGHTER := 0.8
const ODDS_PER_FIGHTER_SQ := 0.035
const ESSENTIAL_OVERDRAFT := 40.0
const MAX_ODDS_CALLS := {"easy": 4, "normal": 6}
## Rough-guess power ratios (ours / theirs, see _ratio). Power is hp x damage, so a ratio of 2 is
## about 1.4 times the numbers.
const SURE_RATIO := 4.0  # this lopsided either way: no need to ask the forecast
const HOPELESS_RATIO := 0.3
const RETREAT_RATIO := 0.9  # pull back when the enemy next door is stronger than this
const SAFE_RATIO := 1.2  # step into a province only if we would be this much stronger there
const MASS_SHARE := 0.6  # the main army pushes on only with this share of our free field strength
const MASS_REACH := 3  # ...counting the armies at most this many moves from it
const STRAGGLER_SHARE := 0.15  # enemy armies this small are not worth a step away from the objective
const GARRISON_RATIO := 1.3  # recruits alone must be this strong for the garrison to leave
const SURPLUS_RATIO := 2.5  # extra armies in a threatened capital may leave if the rest are this strong
const WALK_IN_RATIO := 0.8  # walk into an undefended enemy capital unless rescuers are stronger
## IND-1 (#142): attack a Free Holds garrison only at these odds or better (per level). A garrison never moves, so it
## is never a threat, only a price on its province: the armies marching in together must clear it.
const HOLD_ATTACK_RATE := {"easy": 0.55, "normal": 0.7}
## Sally: the garrison may attack the enemy army next to the capital when it wins this surely. That
## army can then only reach the capital by fighting the garrison on the border (RulesCodex "swap").
const SALLY_WIN := 0.9
## Rough value of holding ground for the guess (the forecast uses the real terrain and fort rules).
const HOLD_BONUS := 1.15
const FORT_BONUS := 1.25
## Easy level: chance to let a good attack or capture pass.
const EASY_SKIP := 0.3
## Random spread (in gold per turn) added to capture and road choices, so the AI is not perfectly
## predictable and games on different seeds differ. Drawn from the plan's rng, so still deterministic.
const JITTER := {"easy": 4.0, "normal": 3.0}
const MAX_NOTES := 14

## M2 (design/M2_RULER.md §6.3). A ruler on a build of its own (no preset) keeping this much power or less
## is too easy to kill to risk in the field: it stays at or near the capital. #131: a preset's ruler plays the
## preset's role instead, so the spend presets' 0-kept rulers march: losing one costs nothing, since a
## faction's mandates outlive its ruler, and kept home they never fought.
const LOW_KEPT := 2
## Our ruler joins an attack only when the forecast, with the ruler fighting, is at least this.
const RULER_JOIN_WIN := 0.65
## Our ruler ends a turn where an enemy army could attack it only if its side would win as defender
## at least this often.
const RULER_GUARD_WIN := 0.5
## Sacrifice (b): from this turn on, when our income is at most this share of the strongest enemy's.
const SACRIFICE_TURN := 8
const SACRIFICE_INCOME_SHARE := 0.8
## Trait-aware recruiting (_recruit_value). A shielded Volley unit shoots while the front rank takes
## the hits: its damage counts this much more, times the share of enemy units without Skirmish (those
## can't reach it).
const VOLLEY_SHIELD_VALUE := 0.5
## A Skirmish unit's damage counts this much more against an enemy whose units all have Volley, scaled
## by the enemy's Volley share: it hits the second rank the others can't reach.
const SKIRMISH_REACH_VALUE := 1.0
## Rounds a battle lasts, roughly, for Charge (first round only) and Berserk (wounded about half the time).
const ROUNDS_GUESS := 3.0
const BERSERK_SHARE := 0.5
## Warband Muster: recruits go with the ruler, away from the capital, only while no enemy army is
## within this many moves of the capital (and half of them stay home while no army of ours is there).
const FIELD_RECRUIT_SAFE := 3

## M4 (paths). Wings: while an enemy commander stands, Wings units attack commanders. A side keeps its
## commander bonuses (COMMANDER_MORALE, Inspire, Pack Leader) only for the share of the battle its
## commander survives the foe's Wings: their expected damage on it over ROUNDS_GUESS rounds against its hp.
## Lifedrinker heals a share of its hits' damage (AutoBattleResolver.LIFEDRINK_DIVISOR) at the end of each
## round it still stands: counted for ROUNDS_GUESS rounds, this share of the time (like BERSERK_SHARE).
const LIFEDRINK_SHARE := 0.5
## Raiding Parties: a capture's one-off gold counts this much against gold per turn.
const RAID_WEIGHT := 0.5

## Stand-offs (#94). The state keeps no record of battles, so a stand-off is read from what piles up while
## nobody fights (standoff_info): every unit a faction fields and its treasury, at today's recruit prices,
## against its income. The computer spends all its gold every turn, so each quiet turn adds about a turn of
## income to the pile and every battle takes some away: a pile worth STANDOFF_TURNS turns of income is about
## that many turns of building up with nothing lost. Then the computer picks what to do by position:
##   hunt   an enemy army (not in its capital) within MASS_REACH of our capital or our strongest army, that
##          our armies within MASS_REACH of it beat at STANDOFF_WIN or better by the rough guess (its ground,
##          and the enemy armies next to it joining in): the garrison the army kept home marches out against
##          it, and the main army goes for it.
##   siege  no army to hunt: the main army pushes on to the enemy capital wherever it is at least even
##          (STANDOFF_SAFE) rather than SAFE_RATIO stronger, and camps next to it until the odds of taking it
##          are even (CAPITAL_WIN, _strike_capitals).
##   raid   even that road is guarded: the nearest province of the foe within MASS_REACH that no army holds
##          and that it can reach safely, to cut the foe's income and draw its army out.
## And any attack at STANDOFF_WIN or better is made: after a long wait, an even fight is worth taking.
## The garrison sallies against the one enemy army next to the capital at STANDOFF_SALLY_WIN instead of
## SALLY_WIN during a stand-off.
const STANDOFF_TURNS := 20.0
## M3c S-7 (#105): with forts and sieges a stand-off is read sooner. Two computers that each hold their keep or capital against
## the other's stack would otherwise mass for ever; at 12 turns of income the games that stalled for 24 turns or more
## are gone and the games at the turn cap halve (design/M3C_SIEGES.md §11.4). Without sieges STANDOFF_TURNS still rules.
const SIEGE_STANDOFF_TURNS := 12.0
const STANDOFF_WIN := 0.5
const STANDOFF_SAFE := 1.0
const STANDOFF_SALLY_WIN := LIKELY_WIN
## Temperament (#184): the computer's style, rolled per seat from the seed (choose_temperament). "normal" plays as before.
const TEMPERAMENTS := ["normal", "aggressive"]
const TEMPERAMENT_NAMES := {"normal": "Steady", "aggressive": "Aggressive"}
## The roll's own stream: SeededRNG(AISeat.seat_seed(game_seed, seat) + TEMPERAMENT_SALT), so the seat's RNG and the
## side of the fork (AIPaths.BRANCH_SALT) are untouched.
const TEMPERAMENT_SALT := 13
## The share of seats that roll aggressive.
const AGGRESSIVE_SHARE := 0.5
## Aggressive: every storm, siege, breach, army and capital attack needs odds this much lower.
const RISK_DISCOUNT := 0.1
## Aggressive: a stand-off is read at this share of the pile (STANDOFF_TURNS, SIEGE_STANDOFF_TURNS).
const AGGRESSIVE_STANDOFF := 0.5
## A note names at most this many armies, then says how many more (a Warband Muster host is many small armies).
const NAMED_ARMIES := 2

var _notes: Array = []
var _stats := {}
var _state: GameState = null
var _fid := ""
var _me: Faction = null
var _rng: SeededRNG = null
var _level := "normal"
var _budget := 0.0
var _cache := {}
var _nbrs := {}  # province id -> sorted neighbor ids
var _dist := {}  # province id -> {province id: steps}
var _mine: Array = []  # our armies, sorted by id
var _foes: Array = []  # every other faction's armies, sorted by id
var _moves := {}  # army id -> destination
var _busy := {}  # army id -> true once it has a job this turn (holding or moving)
var _scratch: GameState = null
var _capital_short := false
var _home_rate := 1.0  # our win rate as defender of the capital this turn (1.0: nothing can attack it)
var _recruit_plan: Array = []  # UnitType, in recruit order
var _vias := {}  # army id -> the province a road move (King's Roads) goes through
var _last_via := ""  # the way through of the road move a field-move helper just chose ("" for one step)
var _ruler: Army = null  # our living ruler's army: planned on its own, never part of _mine
var _preset := {}  # the build preset we play (preset_for), {} without rulers
var _sacrifice := ""  # the mandate this turn's Sacrifice order is for, or ""
var _head := 0  # notes put at the top (build, sacrifice, ruler, mandates) so far
# M4 (paths): unused, and never read, in a game without paths.
var _paths := false  # the game has paths
var _game_seed := 0  # configure(): the game seed and 0-based seat this brain plays (choose_branch)
var _seat := -1  # -1: not configured; the state's seed and the faction's place in it stand in
var _forced_branch := ""  # configure(): a side the autoplay forces (--branches), or ""
var _branch := ""  # the side of the fork we plan for this turn
var _ctx := {}  # {"stats": {"<faction>|<type id>": {"attack", "defense", "morale", "hp"}}, "forest_share", "front", "forest",
	# "iron_discipline": {faction: bool}, "frenzy": {faction: Blood Frenzy's attack}}
var _threat_cache := {}  # province id -> enemy armies that can reach it this turn (_threats_to)
var _holds := {}  # IND-1: province id -> the Free Holds garrison there (never in _foes)
var _arrival := {}  # unit type id -> the hp a recruit of it arrives with
# #94 stand-offs: read afresh from the state every plan, never carried over.
var _standoff := {}  # standoff_info for us, or {} when there is no stand-off
var _hunt := {}  # the enemy army a stand-off hunts (_choose_hunt): {"pid", "rate", "force"}, or {}
var _sally_to := ""  # where the garrison sallies to this turn (_sally), or ""
var _foe_cache := {}  # #131: _foe_side's cache of the foe summaries for _recruit_value, this plan only
## M3c S-6 (#104): forts and sieges (ai/ai_sieges.gd), called behind one `state.sieges` check each.
var _sieges := AISieges.new()
var _fog := AIFog.new()  # M5-4: stale ghosts, the top of each sighting and scouting in a fog game (ai/ai_fog.gd)
var _scratch_top: GameState = null  # M5-4: _scratch for the top of the view (the capital's defence), made once per plan
var _gold_reserved := 0  # M3c: gold set aside for Fortify and engines before the troops are planned (0 without sieges)
var _magic := AIMagic.new()  # M5-10: the research plan's mages, rituals and Tithe of Blood (ai/ai_magic.gd); nothing runs without magic
var _ritual_gold := 0  # M5-10: gold the rituals of this turn hold back from the troops (0 without magic)
var _temperament := "normal"  # #184: set_temperament(); kept for the whole game


## Orders for `faction_id` this turn. See the class comment. Unknown difficulties play as "normal".
func plan_orders(state: GameState, faction_id: String, rng: SeededRNG, difficulty: String = "normal") -> Array:
	var started := Time.get_ticks_usec()
	state = AIFog.trusted_view(state)  # M5-4: in a fog game, the view without its old ghosts; any other state as it is
	_begin(state, faction_id, rng, difficulty)
	if _me == null:
		return []
	var out := []
	_note_build()
	_note_temperament()
	_sacrifice = _choose_sacrifice()
	if not _sacrifice.is_empty():
		# The sacrifice phase resolves first, so every other order is planned (and checked by
		# OrderBook) on the state with the sacrifice applied.
		_rebase(RulerRules.with_sacrifice(state, faction_id, _sacrifice))
		out.append(SacrificeOrder.new(_sacrifice))
		_stats.sacrifices = 1
	var research := _plan_research()  # M4: "" without paths, and on most turns with them
	if not research.is_empty():
		out.append(ResearchOrder.new(research))
	_plan_standoff()  # #94: read from the state alone, every plan
	_recruit_plan = _plan_recruits([])  # a fresh army, for judging next turn's garrison
	_defend_capital()
	if _state.sieges:
		_sieges.defend_forts()  # M3c: our besieged forts (relief, sallies, leaving, holding)
		_sieges.attack_forts()  # ...and enemy forts (storms, sieges, engines), in place of _strike_capitals
	else:
		_strike_capitals()
	_attack_armies()
	if _state.sieges:
		_sieges.keep_garrisons()  # M3c: a reachable keep keeps an army
	_fog.scout()  # M5-4: a free scout army looks toward an objective it cannot see (nothing in a game without fog)
	_field_moves()
	_ruler_moves()
	if _state.sieges:
		_sieges.plan_builds()  # M3c: Fortify, with its gold set aside before the troops are planned
	_magic.plan()  # M5-10: rituals from the armies that hold anyway, their gold set aside before the troops are planned (nothing without magic)
	if _level != "easy":
		_recruit_plan = _plan_recruits(_armies_ending_at(_me.capital))
	_guard_holds()  # IND-1: no march into a garrison the armies going there together can't beat
	out.append_array(_checked_moves())
	out.append_array(_magic.checked(out))  # M5-10: the casts, after the moves they were planned around and before the recruits they were priced for
	if _state.sieges:
		out.append_array(_sieges.siege_orders(out))
		out.append_array(_sieges.checked_recruits())  # M3c: recruits across our forts, Fortify and engines
	else:
		out.append_array(_checked_recruits())
	_stats["usec"] = Time.get_ticks_usec() - started  # reporting only; never feeds a decision
	# Let go of this turn's state; only the notes and counters are kept.
	_state = null
	_me = null
	_scratch = null
	_cache = {}
	_mine = []
	_foes = []
	_ruler = null
	_ctx = {}
	_threat_cache = {}
	_holds = {}
	_arrival = {}
	_hunt = {}
	_foe_cache = {}
	_scratch_top = null
	_sieges.end()
	_fog.end()
	_magic.end()
	return out


## Tells the brain whose seat it plays (M4, paths): the game seed and the 0-based seat, as AISeat.seat_seed
## takes them, so the side of the fork is choose_branch's roll for that seat. `forced_branch` (a PathData
## branch id of the faction, e.g. "blood_pact") replaces the roll, for the autoplay's --branches. Without
## a call the state's seed and the faction's place in the state stand in. No effect without paths.
func configure(game_seed: int, seat: int, forced_branch: String = "") -> void:
	_game_seed = game_seed
	_seat = seat
	_forced_branch = forced_branch


## Sets the brain's temperament (#184) for every plan after it: "normal" or "aggressive" (anything else plays "normal").
func set_temperament(temperament: String) -> void:
	_temperament = temperament if TEMPERAMENTS.has(temperament) else "normal"


func temperament() -> String:
	return _temperament


## The temperament of the computer in 0-based `seat` (#184): "aggressive" for AGGRESSIVE_SHARE of the rolls, else
## "normal". The first draw of SeededRNG(AISeat.seat_seed(game_seed, seat) + TEMPERAMENT_SALT), a stream of its own, so
## the seat's RNG and its side of the fork are untouched. A pure function of the seed and the seat.
static func choose_temperament(game_seed: int, seat: int) -> String:
	var roll := SeededRNG.new(AISeat.seat_seed(game_seed, seat) + TEMPERAMENT_SALT).randf()
	return "aggressive" if roll < AGGRESSIVE_SHARE else "normal"


## "Steady", "Aggressive": the temperament's name on screen.
static func temperament_name(temperament: String) -> String:
	return String(TEMPERAMENT_NAMES.get(temperament, TEMPERAMENT_NAMES.normal))


## What the temperament means, in plain words, for a tooltip or the new game screen.
static func temperament_help(temperament: String) -> String:
	if temperament == "aggressive":
		return "It takes fights at worse odds (%d points less on every storm, siege and attack), loses patience in a stand-off twice as fast, and goes around a fort it won't attack to take land from the Free Holds or raid." % roundi(RISK_DISCOUNT * 100.0)
	return "It fights only at good odds and masses its armies before it pushes on."


## The side of the fork the computer in 0-based `seat` swears to in a game with paths (design/M4_ASCENSION.md
## §8.1): a weighted pick by the preset's fork weights, the first draw of
## SeededRNG(AISeat.seat_seed(game_seed, seat) + AIPaths.BRANCH_SALT), a stream of its own, so the seat's
## RNG and every M1/M2 game are untouched. A pure function of the seed, seat and preset (AIPaths.choose_branch).
## `faction_id` defaults to the preset's faction; a custom build ("" preset) needs it.
static func choose_branch(game_seed: int, seat: int, preset_id: String, faction_id: String = "") -> String:
	var fid := faction_id
	if fid.is_empty():
		fid = String(AIPaths.AI_PATHS.get(preset_id, {}).get("faction", ""))
	return AIPaths.choose_branch(game_seed, seat, preset_id, fid)


## The build an AI seat plays in a game with rulers (design/M2_RULER.md §6.1): one of the faction's
## three presets, presets[faction][rng.randi_range(0, 2)], as {"preset", "ruler", "mandates"}
## (RulerRules.preset_build). Call it with the seat's own RNG before its first plan: this is that RNG's
## first draw, so the same seed always gives the same build and the same orders after it. The build
## screen (BuildScreen.computer_preset), AISeat and the autoplay all pick through here, so the presets
## on screen and the computer's builds are the same data. `state_or_faction` may be the GameState, the
## Faction or null; the presets come from data/build_presets.gd. {} (and no draw) for a faction without presets.
static func choose_build(state_or_faction, faction_id: String, rng: SeededRNG) -> Dictionary:
	var fid := faction_id
	if fid.is_empty() and state_or_faction is Faction:
		fid = state_or_faction.id
	if state_or_faction is GameState and state_or_faction.find_faction(fid) == null:
		return {}
	var presets := RulerRules.presets_for(fid)
	if presets.is_empty() or rng == null:
		return {}
	return RulerRules.preset_build(String(presets[rng.randi_range(0, presets.size() - 1)].id))


## The preset `faction_id` plays (BuildPresetData, with "faction"): the one whose ruler and pre-game
## mandates (its mandates minus the ones it bought by sacrifice) match the faction's. A build that is no
## preset gets a stand-in: "home" when it started with LOW_KEPT power or less, otherwise "field", and
## the sacrifice picks of the faction's first preset with the same ruler that has any. {} without a ruler.
static func preset_for(state: GameState, faction_id: String) -> Dictionary:
	var f: Faction = state.find_faction(faction_id) if state != null else null
	if f == null or not f.has_ruler():
		return {}
	var bought := []
	for s in f.sacrifices:
		bought.append(String(s.get("mandate", "")))
	var start := []
	for mid in f.mandates:
		if not bought.has(mid):
			start.append(String(mid))
	var start_sorted := start.duplicate()
	start_sorted.sort()
	var picks := []
	for p in RulerRules.presets_for(faction_id):
		if p.ruler != f.ruler_type:
			continue
		var m: Array = p.mandates.duplicate()
		m.sort()
		if m == start_sorted:
			var out: Dictionary = p.duplicate(true)
			out["faction"] = faction_id
			return out
		if picks.is_empty():
			picks = p.ai_sacrifices.duplicate()
	var kept := RulerRules.kept_after({"ruler": f.ruler_type, "mandates": start})
	return {"id": "", "name": "", "style": "custom", "faction": faction_id, "ruler": f.ruler_type, "mandates": start,
		"ai_role": "home" if kept <= LOW_KEPT else "field", "ai_sacrifices": picks}


## Plain-language reasons for the last plan, most important first. Names only, never ids.
func last_plan_notes() -> Array:
	return _notes.duplicate()


## Counters for the last plan: {"odds_calls", "odds_cached", "odds_skipped", "attacks", "held_back",
## "captures", "recalls", "retreats", "recruits", "dropped_invalid", "usec"}, plus "odds_usec" and
## "odds_fighters_max" when a forecast ran. The timings are for reports only and never steer a plan.
func last_plan_stats() -> Dictionary:
	return _stats.duplicate()


# --- setup ----------------------------------------------------------------------------------------

func _begin(state: GameState, faction_id: String, rng: SeededRNG, difficulty: String) -> void:
	_state = state
	_fid = faction_id
	_rng = rng if rng != null else SeededRNG.new(0)
	_level = difficulty if DIFFICULTIES.has(difficulty) else "normal"
	_notes = []
	_head = 0
	_stats = {"odds_calls": 0, "odds_cached": 0, "odds_skipped": 0, "attacks": 0, "held_back": 0,
		"captures": 0, "recalls": 0, "retreats": 0, "recruits": 0, "dropped_invalid": 0, "usec": 0,
		"sacrifices": 0, "road_moves": 0, "field_recruits": 0, "ruler_moves": 0}
	_budget = ODDS_BUDGET[_level]
	_cache = {}
	_moves = {}
	_vias = {}
	_busy = {}
	_scratch = null
	_scratch_top = null
	_capital_short = false
	_home_rate = 1.0
	_recruit_plan = []
	_mine = []
	_foes = []
	_ruler = null
	_preset = {}
	_sacrifice = ""
	_standoff = {}
	_hunt = {}
	_sally_to = ""
	_foe_cache = {}
	_gold_reserved = 0
	_ritual_gold = 0
	_me = state.find_faction(faction_id) if state != null else null
	if _me == null:
		return
	if state.sieges:
		_sieges.attach(self)  # M3c: forts and sieges (ai/ai_sieges.gd) for this plan
	_fog.attach(self)  # M5-4: fog of war (ai/ai_fog.gd) for this plan; _collect_armies finds the top of the view
	_magic.attach(self)  # M5-10: magic (ai/ai_magic.gd) for this plan; it reads what last turn's Far Sight came to
	_nbrs = {}
	for p in state.provinces:
		var n: Array = p.neighbors.duplicate()
		n.sort()
		_nbrs[p.id] = n
	_dist = {}
	for p in state.provinces:
		_dist[p.id] = _bfs(p.id)
	_collect_armies()
	_preset = preset_for(state, faction_id)
	_paths = AscensionRules.has_paths(state)
	_branch = ""
	_ctx = {}
	_threat_cache = {}
	_arrival = {}
	if _paths:
		_branch = _plan_branch()
	_build_ctx()  # #131: every game, not only with paths: the battle rules' numbers are the same


## Sorts the state's armies into ours (_mine, without our ruler's army), our ruler's army and the foes'.
func _collect_armies() -> void:
	_mine = []
	_foes = []
	_holds = {}
	_ruler = null
	for a in _state.armies:
		if a.owner == IndependentData.FACTION_ID:
			_holds[a.location] = a  # IND-1: a garrison is a price on its province, not a foe
			continue
		if a.owner == _fid:
			if a.ruler != null:
				_ruler = a
			else:
				_mine.append(a)
		else:
			_foes.append(a)
	_mine.sort_custom(func(x, y): return x.id < y.id)
	_foes.sort_custom(func(x, y): return x.id < y.id)
	_scratch_top = null
	_fog.refresh()  # M5-4: the top of the view's sightings (null in a game without fog)


## Plans the rest of the turn on `state` instead (the state with this turn's sacrifice applied). The map
## is the same; the armies, the faction and every cached forecast are taken afresh.
func _rebase(state: GameState) -> void:
	if state == null:
		return
	_state = state
	_me = state.find_faction(_fid)
	_cache = {}
	_scratch = null
	_scratch_top = null
	_moves = {}
	_vias = {}
	_busy = {}
	_collect_armies()
	_foe_cache = {}
	_build_ctx()  # a sacrifice can change unit numbers (Royal Armories, Veteran Levies)


func _bfs(from_id: String) -> Dictionary:
	var dist := {from_id: 0}
	var queue: Array = [from_id]
	var i := 0
	while i < queue.size():
		var pid: String = queue[i]
		i += 1
		for n in _nbrs.get(pid, []):
			if not dist.has(n):
				dist[n] = int(dist[pid]) + 1
				queue.append(n)
	return dist


# --- 1. the capital -------------------------------------------------------------------------------

func _defend_capital() -> void:
	var cap := _state.find_province(_me.capital)
	if cap == null or cap.owner != _fid:
		return
	if _state.sieges and _sieges.capital_besieged():
		return  # M3c: a besieged capital is AISieges.defend_forts' business
	var home := _mine_at(cap.id)
	var threats := _fog.top(_threats_to(cap.id))  # M4: plus enemy road moves (King's Roads, Forest Stride) with paths; M5-4: at the top of each sighting
	if threats.is_empty():
		_size_garrison(cap, home)
		return
	var where := _places_text(threats)
	var guard := _home_guard()  # our ruler, when it holds the capital this turn
	var recallable := []
	for n in _nbrs[cap.id]:
		for a in _mine_at(n):
			recallable.append(a)
	# King's Roads: armies two provinces away through our own land can be back this turn too.
	var road := _road_recalls(cap.id)
	var road_ids: Array = road.keys()
	road_ids.sort()
	for id in road_ids:
		recallable.append(_state.find_army(str(id)))
	recallable.sort_custom(func(x, y): return _army_power(x) > _army_power(y) or (_army_power(x) == _army_power(y) and x.id < y.id))

	if home.is_empty():
		# Nobody holds the capital (or only our ruler does), so recalled armies arrive together with any
		# attacker. Bring back everyone who can make it.
		for a in recallable:
			_move(a, cap.id, str(road.get(a.id, "")))
			_stats.recalls += 1
		_home_rate = 0.0
		if recallable.is_empty():
			if guard.is_empty():
				_note("%s is open: an enemy army at %s could walk in next turn, and none of our armies can get there in time." % [cap.name, where])
			else:
				_home_rate = _defense_rate(cap.id, guard, threats)
				_note("Only %s holds %s: an enemy army at %s could attack next turn, and none of our armies can get there in time (odds as defender: %s)." % [
					RulerRules.current_name(_state, _fid), cap.name, where, _odds_words(_home_rate)])
		else:
			var rate := _defense_rate(cap.id, recallable + guard, threats)
			_home_rate = rate
			_note("Rushing %s back to %s: %s and an enemy army at %s could attack next turn (odds: %s)." % [
				_count_text(recallable), cap.name, "it is empty" if guard.is_empty() else "only %s holds it" % RulerRules.current_name(_state, _fid),
				where, _odds_words(rate)])
		return

	# Keep the smallest set of home armies that holds; any extra armies may leave.
	var keep := _keepers(cap.id, home, threats)
	for a in keep:
		_hold(a)
	var defenders: Array = keep.duplicate()
	var recalled := []
	var rate := _defense_rate(cap.id, defenders + guard, threats)
	while rate < HOLD_TARGET[_level] and not recallable.is_empty():
		var a: Army = recallable.pop_front()
		recalled.append(a)
		defenders.append(a)
		rate = _defense_rate(cap.id, defenders + guard, threats)
	for a in recalled:
		_move(a, cap.id, str(road.get(a.id, "")))
		_stats.recalls += 1
	_home_rate = rate
	if recalled.is_empty() and _sally(cap, home, threats):
		return
	if recalled.is_empty():
		_note("Holding %s: an enemy army at %s could attack next turn (odds as defender: %s)." % [cap.name, where, _odds_words(rate)])
	else:
		_note("Recalling %s to %s: an enemy army at %s could attack next turn (odds as defender with them: %s)." % [
			_count_text(recalled), cap.name, where, _odds_words(rate)])
	if keep.size() < home.size():
		_note("%s is safe without %s, so %s free to act." % [cap.name, _count_text(home.size() - keep.size()),
			"it is" if home.size() - keep.size() == 1 else "they are"])


## Every enemy army next to the capital stands in one province and the whole garrison would crush
## it: attack it instead of waiting. Moving in, it would have to fight the garrison on the border
## first, and nobody else can reach the capital this turn; this turn's recruits regroup there.
## Returns true when the garrison sallies.
func _sally(cap: Province, home: Array, threats: Array) -> bool:
	var at: String = threats[0].location
	for e in threats:
		if e.location != at:
			return false
	if not _nbrs[cap.id].has(at):
		return false  # M4: an army two provinces off (a road move) can't be met on the border
	# Judged with the garrison alone: on the border it meets that army without the armies joining
	# from elsewhere (and without terrain, which only makes this estimate safer).
	var odds := _attack_rate(home, at)
	var need := SALLY_WIN if _standoff.is_empty() else STANDOFF_SALLY_WIN  # #94: a stand-off accepts a likely win
	if odds.rate < need:
		return false
	var attackers: Array = home.duplicate()
	for a in _free_next_to(at):
		if not attackers.has(a):
			attackers.append(a)
	for a in attackers:
		_move(a, at)
	_sally_to = at
	_stats.attacks += 1
	_home_rate = odds.rate
	var tail := "" if odds.rate >= SALLY_WIN else " After a long stand-off, a likely win is worth the risk."
	_note("Sallying out of %s to destroy the enemy army at %s (odds: %s): it cannot slip into %s without fighting us on the way.%s" % [
		cap.name, _province_name(at), _odds_words(odds.rate, odds.label), cap.name, tail])
	return true


## Home armies that must stay: all of them, unless the strongest few are already lopsidedly enough.
func _keepers(pid: String, home: Array, threats: Array) -> Array:
	if home.size() < 2:
		return home.duplicate()
	var by_power := home.duplicate()
	by_power.sort_custom(func(x, y): return _army_power(x) > _army_power(y) or (_army_power(x) == _army_power(y) and x.id < y.id))
	var keep := []
	for a in by_power:
		keep.append(a)
		if _ratio(keep, threats, _ground_bonus(pid), 1.0) >= SURPLUS_RATIO:
			break
	return keep


## Our win rate holding `pid` with `defenders` against `threats` attacking it together: the worst
## case over the attacking factions. Forecast.battle_odds is run from the attacker's side on a scratch
## copy of the state where the defenders stand in `pid`.
func _defense_rate(pid: String, defenders: Array, threats: Array) -> float:
	threats = _fog.top(threats)  # M5-4: a defence is judged against the top of each sighting (the same armies in a game without fog)
	if _state.sieges and _sieges.walls_stand(pid):
		return _sieges.defense_rate(pid, defenders, threats)  # M3c: behind walls the enemy storms or besieges
	if defenders.is_empty():
		return 0.0
	var ratio := _ratio(defenders, threats, _ground_bonus(pid), 1.0)
	if ratio >= SURE_RATIO:
		return 0.95
	if ratio <= HOPELESS_RATIO:
		return 0.05
	var st := _scratch_with(defenders, pid, true)
	var by_faction := {}
	for e in threats:
		if not by_faction.has(e.owner):
			by_faction[e.owner] = []
		by_faction[e.owner].append(e.id)
	var fids: Array = by_faction.keys()
	fids.sort()
	var worst := 1.0
	for fid in fids:
		var r: Dictionary = _odds(st, fid, by_faction[fid], pid, true) if st != null else {}
		var their: float = float(r.win_rate) if r.has("win_rate") else _rate_from_ratio(1.0 / maxf(ratio, 0.001))
		worst = minf(worst, 1.0 - their)
	return worst


## With no enemy next door, enemy armies two or three moves away may still need a garrison: the home
## armies stay unless this turn's recruits alone would hold the capital against them.
func _size_garrison(cap: Province, home: Array) -> void:
	var near := []
	var far := []
	for e in _foes:
		var d := _d(e.location, cap.id)
		if d == 2:
			near.append(e)
		elif d == 3:
			far.append(e)
	if near.is_empty() and far.is_empty():
		return
	var threat: Array = _fog.top(near + far)  # M5-4: at the top of each sighting
	if not home.is_empty() and _hunting_the_pin(threat):
		# #94: a stand-off, and the army that keeps the garrison home is one we can beat: the garrison
		# marches out against it (_field_moves) instead. Nobody can reach the capital this turn.
		_stats.hunts = 1
		_note_top("Breaking the stand-off: what we have built up while both sides waited is worth %d turns of our income, so %s (%s) %s out of %s against %s at %s (rough odds: %s) instead of guarding it." % [
			floori(float(_standoff.turns)), _army_names(home), _units_text(home), "marches" if home.size() == 1 else "march", cap.name,
			_army_names(_foes_at(_hunt.pid)), _province_name(_hunt.pid), _odds_words(float(_hunt.rate))])
		return
	var recruits := _recruit_units()
	var need := GARRISON_RATIO if not near.is_empty() else GARRISON_RATIO * 0.6
	var bonus := _ground_bonus(cap.id)
	if _ratio_units(recruits, _units(threat), bonus, 1.0) >= need:
		return
	if home.is_empty():
		if not near.is_empty():
			_capital_short = _ratio_units(recruits, _units(threat), bonus, 1.0) < 1.0
		return
	for a in home:
		_hold(a)
	var garrison: Array = recruits + _units(home)
	if not near.is_empty() and _ratio_units(garrison, _units(threat), bonus, 1.0) < 1.0:
		_capital_short = true
	var where := _places_text(near if not near.is_empty() else far)
	_note("Keeping the garrison in %s: an enemy army at %s is %s moves away." % [cap.name, where, "two" if not near.is_empty() else "three"])


# --- 2. the enemy capital -------------------------------------------------------------------------

func _strike_capitals() -> void:
	for f in _sorted_factions():
		if f.id == _fid:
			continue
		var ec := _state.find_province(f.capital)
		if ec == null or ec.owner == _fid:
			continue
		var attackers := _free_next_to(ec.id)
		if attackers.is_empty():
			continue
		var held := _foes_at(ec.id)
		if held.is_empty():
			var rescuers := _foes_next_to(ec.id)
			if rescuers.is_empty() or _ratio(attackers, rescuers, 1.0, 1.0) >= WALK_IN_RATIO:
				for a in attackers:
					_move(a, ec.id)
				_stats.attacks += 1
				_note("Marching into %s: the %s capital is undefended, and taking it wins the game." % [ec.name, f.faction_name])
			else:
				_note("Not walking into %s yet: the %s armies next to it could rush back and win." % [ec.name, f.faction_name])
			continue
		var odds := _attack_rate(attackers, ec.id)
		if odds.rate >= _risk(CAPITAL_WIN):
			for a in attackers:
				_move(a, ec.id)
			_stats.attacks += 1
			_note("Attacking %s, the %s capital, with %s (odds: %s%s)." % [ec.name, f.faction_name, _count_text(attackers), _odds_words(odds.rate, odds.label), _joiners_text(odds)])
		else:
			_stats.held_back += 1
			_note("Not attacking %s yet (odds: %s%s); massing more armies next to it." % [ec.name, _odds_words(odds.rate, odds.label), _joiners_text(odds)])


# --- 3. battles -----------------------------------------------------------------------------------

func _attack_armies() -> void:
	var near_home: Array = _nbrs.get(_me.capital, [])
	var cands := []
	for p in _sorted_provinces():
		if _is_enemy_capital(p.id):
			continue
		if _state.sieges and _sieges.skips_battle(p.id):
			continue  # M3c: a garrison or a siege of ours: AISieges decides
		var held := _foes_at(p.id)
		if held.is_empty():
			continue
		var att := _free_next_to(p.id)
		if att.is_empty():
			continue
		var urgent: bool = near_home.has(p.id) and _home_rate < HOLD_TARGET[_level]
		# Worth: the enemy strength we expect to destroy, more next to our capital.
		var ratio := _ratio(att, held, 1.0, _ground_bonus(p.id))
		var worth := _power_units(_units(held), _units(att)) * _rate_from_ratio(ratio) * (1.5 if near_home.has(p.id) else 1.0)
		cands.append({"pid": p.id, "urgent": urgent, "worth": worth})
	cands.sort_custom(func(x, y):
		if x.urgent != y.urgent:
			return x.urgent
		if x.worth != y.worth:
			return x.worth > y.worth
		return x.pid < y.pid)
	for c in cands:
		var att := _attackers_for(c.pid, c.urgent)
		if att.is_empty():
			continue
		var p := _state.find_province(c.pid)
		var odds := _attack_rate(att, c.pid)
		var need := URGENT_WIN if c.urgent else _risk(LIKELY_WIN)
		if not c.urgent and not _standoff.is_empty():
			need = _risk(STANDOFF_WIN)  # #94: after a long stand-off an even fight is worth taking
		if odds.rate < need:
			_stats.held_back += 1
			if odds.rate > HOPELESS_RATIO or c.urgent:
				_note("Not attacking the enemy at %s (odds: %s%s)." % [p.name, _odds_words(odds.rate, odds.label), _joiners_text(odds)])
			continue
		if _skips():
			_note("Letting a chance to attack %s pass." % p.name)
			continue
		for a in att:
			_move(a, c.pid)
		_stats.attacks += 1
		var why := " before it reaches %s" % _province_name(_me.capital) if c.urgent else ""
		var tail := ""
		if not c.urgent and odds.rate < LIKELY_WIN:
			tail = ": after a long stand-off, even odds are worth taking" if not _standoff.is_empty() else ": it plays aggressively and takes the risk"
		_note("Attacking the enemy at %s with %s%s (odds: %s%s)%s." % [p.name, _count_text(att), why, _odds_words(odds.rate, odds.label), _joiners_text(odds), tail])


## Free armies next to `pid` that should attack it. A small enemy army (a straggler) is not worth a
## step away from the enemy capital, unless it threatens our capital: those armies stay on course.
func _attackers_for(pid: String, urgent: bool) -> Array:
	var att := _free_next_to(pid)
	if urgent or att.is_empty():
		return att
	var held := _foes_at(pid)
	if _power_units(_units(held), _units(att)) >= STRAGGLER_SHARE * _power_units(_units(att), _units(held)):
		return att
	return att.filter(func(a):
		var obj := _objective_for(a.location)
		return obj.is_empty() or _d(pid, obj) <= _d(a.location, obj))


## {"rate", "label", "helpers"} for our `attackers` attacking `pid` now. Enemy armies next to `pid`
## could move in and join the defense in the same turn, so they are counted as if they do ("helpers":
## how many). The rough guess decides when it is lopsided or the forecast budget is spent, otherwise
## Forecast.battle_odds, on a scratch copy of the state with those armies moved in.
func _attack_rate(attackers: Array, pid: String) -> Dictionary:
	var helpers := _foes_next_to(pid)
	var foes: Array = _foes_at(pid) + helpers
	var ratio := _ratio(attackers, foes, 1.0, _ground_bonus(pid))
	if ratio >= SURE_RATIO:
		return {"rate": 0.95, "label": "likely win", "helpers": helpers.size()}
	if ratio <= HOPELESS_RATIO:
		return {"rate": 0.05, "label": "likely loss", "helpers": helpers.size()}
	var ids := []
	for a in attackers:
		ids.append(a.id)
	var st: GameState = _state if helpers.is_empty() else _scratch_with(helpers, pid)
	var r: Dictionary = _odds(st, _fid, ids, pid, false) if st != null else {}
	if r.has("win_rate"):
		return {"rate": float(r.win_rate), "label": str(r.get("label", "")), "helpers": helpers.size()}
	var rate := _rate_from_ratio(ratio)
	return {"rate": rate, "label": _label_for(rate), "helpers": helpers.size()}


# --- 4. field moves -------------------------------------------------------------------------------

func _field_moves() -> void:
	var groups := _free_groups()
	if groups.is_empty():
		return
	var main: Dictionary = groups[0]
	var objective := _objective_for(main.loc)
	if not _hunt.is_empty():
		objective = String(_hunt.pid)  # #94: in a stand-off the main army marches on the army it hunts
	elif _state.sieges:
		objective = _sieges.target_from(main.loc, objective, main.armies)  # M3c: a fort on the road we could take first
	var claimed := {}
	var main_dest: String = main.loc
	# Mass before pushing: the main army waits while a big share of our strength is still on its way.
	var nearby := 0.0
	var waiting_for := 0
	for g in groups:
		if _d(g.loc, main.loc) <= MASS_REACH:
			nearby += float(g.power)
			if g.loc != main.loc:
				waiting_for += 1
	main["massed"] = float(main.power) >= MASS_SHARE * nearby
	main["waiting_for"] = waiting_for
	for i in groups.size():
		var g: Dictionary = groups[i]
		_last_via = ""
		var dest := _field_move(g, i == 0, objective, main_dest, claimed)
		if i == 0:
			main_dest = dest
		for a in g.armies:
			if dest == g.loc:
				_hold(a)
			else:
				_move(a, dest, _last_via)


func _field_move(g: Dictionary, is_main: bool, objective: String, main_dest: String, claimed: Dictionary) -> String:
	var here: String = g.loc
	var armies: Array = g.armies
	var here_name := _province_name(here)
	# A clearly stronger enemy next door: pull back.
	var danger := _foes_next_to(here)
	if not danger.is_empty() and _ratio(armies, danger, _ground_bonus(here), 1.0) < RETREAT_RATIO:
		var back := _retreat_step(g)
		if back != here:
			_stats.retreats += 1
			_note("Pulling back from %s to %s: a stronger enemy army is next to it." % [here_name, _province_name(back)])
			return back
	# The capital will be short of defenders soon: armies close to home go back.
	var cap: String = _me.capital
	if _capital_short and here != cap and _d(here, cap) <= 2:
		var step := _road_or_step(here, cap, armies)
		if not step.is_empty():
			_note("Sending %s from %s back toward %s: enemy armies are closing in on it." % [_count_text(armies), here_name, _province_name(cap)])
			return step
	# Take a safe, undefended province next door.
	var capture := _best_capture(g, is_main, objective, claimed)
	if not capture.is_empty():
		if _skips():
			return here
		claimed[capture] = true
		_stats.captures += 1
		var p := _state.find_province(capture)
		if _paths:
			_note(_capture_note(p))
		else:
			_note("Taking %s for %d gold per turn%s." % [p.name, p.income, "" if p.owner.is_empty() else " (and %s lose it)" % _faction_name(p.owner)])
		return capture
	if is_main:
		return _advance(g, objective)
	if not _hunt.is_empty() and _d(here, String(_hunt.pid)) <= 1:
		return here  # #94: next to the army we hunt, wait there for the main army
	return _join(g, main_dest)


## The neighbor (or `here`) where the group is safest, judged with the friendly armies that will be
## there. Ties: closer to our capital, then sorted id.
func _retreat_step(g: Dictionary) -> String:
	var here: String = g.loc
	var options: Array = [here]
	for n in _nbrs[here]:
		if _foes_at(n).is_empty():
			options.append(n)
	var best := here
	var best_ratio := -1.0
	for pid in options:
		var friends: Array = g.armies + _friends_ending_at(pid, g.armies)
		var threat := _foes_next_to(pid)
		var r := 99.0 if threat.is_empty() else _ratio(friends, threat, _ground_bonus(pid), 1.0)
		var better := r > best_ratio + 0.0001
		if not better and absf(r - best_ratio) <= 0.0001:
			better = _d(pid, _me.capital) < _d(best, _me.capital) or (_d(pid, _me.capital) == _d(best, _me.capital) and pid < best)
		if better:
			best = pid
			best_ratio = r
	return best


func _best_capture(g: Dictionary, is_main: bool, objective: String, claimed: Dictionary) -> String:
	var here: String = g.loc
	var best := ""
	var best_score := 0.0
	for n in _nbrs[here]:
		var p := _state.find_province(n)
		if p == null or p.owner == _fid or claimed.has(n) or not _foes_at(n).is_empty():
			continue
		if is_main and not objective.is_empty() and _d(n, objective) > _d(here, objective):
			continue
		if not _safe_at(g.armies, n):
			continue
		var hold_rate := _hold_rate(g.armies, n)  # IND-1: 1.0 where no garrison stands
		if hold_rate < _risk(float(HOLD_ATTACK_RATE[_level])):
			continue
		var score: float
		if _paths:
			score = _capture_worth(p) + _rng.randf() * float(JITTER[_level])
		else:
			score = float(p.income) * (1.0 if p.owner.is_empty() else 2.0) + _rng.randf() * float(JITTER[_level])
		if not objective.is_empty():
			score -= 0.01 * _d(n, objective)
		if _state.sieges:
			score += _sieges.muster_value(p)  # M3c: a fort is a recruiting post
		score *= hold_rate  # IND-1: a garrison's fight discounts the prize
		if score > best_score:
			best = n
			best_score = score
	return best


## The main army: one step toward the objective while the step is safe, otherwise hold and mass.
func _advance(g: Dictionary, objective: String) -> String:
	var here: String = g.loc
	if objective.is_empty():
		return here
	var d_here := _d(here, objective)
	if d_here <= 1:
		if _temperament == "aggressive":
			var around := _go_around(here, objective, g.armies)  # #184: not massing at walls it won't attack
			if not around.is_empty():
				return around
		return here  # next to the enemy capital: _strike_capitals decides when to go in
	if not g.get("massed", true):
		_note("Massing at %s: waiting for %s to join before pushing on to %s." % [_province_name(here),
			_count_text(int(g.get("waiting_for", 1))), _province_name(objective)])
		return here
	var road := _road_step(here, objective, g.armies)  # King's Roads: two provinces through our own land
	if not road.is_empty():
		return road
	if _state.sieges:
		var around := _sieges.route_step(here, objective, g.armies)  # M3c: around armies we can't fight
		if not around.is_empty():
			return around
	var options := []
	for n in _nbrs[here]:
		if _d(n, objective) == d_here - 1 and _foes_at(n).is_empty() and _safe_at(g.armies, n):
			options.append(n)
	if options.is_empty():
		# #94: in a stand-off, besiege the enemy capital anyway where we are at least even, else raid.
		# M3c: with sieges, the step next to a target fort is judged by the siege-start odds instead.
		var other := _sieges.approach_step(here, objective, g.armies) if _state.sieges else _siege_step(here, objective, g.armies)
		if other.is_empty():
			other = _raid_step(here, g.armies)
		if other.is_empty() and _temperament == "aggressive":
			other = _go_around(here, objective, g.armies)  # #184
		if not other.is_empty():
			return other
		_note("Massing at %s before pushing on to %s: the road ahead is guarded by stronger armies." % [_province_name(here), _province_name(objective)])
		return here
	var step := _pick_step(options)
	return step


## #184, the aggressive temperament: the main army at `here` would otherwise wait (next to a fort or capital that it
## doesn't attack this turn, or before a guarded road), so it goes around: one step toward the nearest province within
## MASS_REACH that isn't ours and isn't `objective`, with no enemy army in it, where `armies` are safe and beat its Free
## Holds garrison, if any, at _risk(HOLD_ATTACK_RATE). Land to take from the Free Holds, or the foe's to raid. Ties: what it is
## worth to us, then id. "" when there is none.
func _go_around(here: String, objective: String, armies: Array) -> String:
	var best := ""
	var best_step := ""
	var best_d := MASS_REACH + 1
	var best_worth := -1.0
	for p in _sorted_provinces():
		if p.owner == _fid or p.id == objective or not _foes_at(p.id).is_empty():
			continue
		var d := _d(here, p.id)
		if d < 1 or d > best_d:
			continue
		var worth: float = _capture_worth(p) if _paths else float(p.income) * (1.0 if p.owner.is_empty() else 2.0)
		if d == best_d and worth <= best_worth + 0.0001:
			continue
		if not _safe_at(armies, p.id) or _hold_rate(armies, p.id) < _risk(float(HOLD_ATTACK_RATE[_level])):
			continue
		var step: String = p.id if d == 1 else _step_toward(here, p.id, armies)
		if step.is_empty():
			continue
		best = p.id
		best_step = step
		best_d = d
		best_worth = worth
	if best.is_empty():
		return ""
	_stats.go_arounds = 1
	var target := _state.find_province(best)
	var what := "%s, to raid the %s" % [target.name, _faction_name(target.owner)]
	if target.owner.is_empty():
		what = "%s, held by the Free Holds" % target.name if _holds.has(best) else "%s, which nobody holds" % target.name
	_note("Going around %s: %s %s for %s rather than wait at its walls (it plays aggressively)." % [_province_name(objective),
		_army_names(armies), "heads" if armies.size() == 1 else "head", what])
	return best_step


## Every other free army: one safe step toward where the main army will be.
func _join(g: Dictionary, main_dest: String) -> String:
	var here: String = g.loc
	if here == main_dest:
		return here
	var step := _road_or_step(here, main_dest, g.armies)
	return here if step.is_empty() else step


## A step from `here` toward `target` for `armies` (all standing in `here`): a road move two provinces
## along (King's Roads) when one is legal, safe and gets closer than one step would, otherwise
## _step_toward's one safe step. A road move sets _last_via. "" when there is no safe step.
func _road_or_step(here: String, target: String, armies: Array) -> String:
	var road := _road_step(here, target, armies)
	return road if not road.is_empty() else _step_toward(here, target, armies)


## The best road move (King's Roads, RulerRules.road_destinations) from `here` toward `target` for
## `armies`: the legal two-province move that ends closest to `target`, closer than one step could, in
## a province with no enemy army and safe for the armies that will be there (_safe_at). Ties go to the
## first by id; the way through is the first legal one by id (as the orders UI picks). Sets _last_via.
## "" without King's Roads or when no road move helps.
func _road_step(here: String, target: String, armies: Array) -> String:
	if armies.is_empty() or not RulerRules.has_road_moves(_state, _fid):  # M4: or Forest Stride
		return ""
	var d_here := _d(here, target)
	if d_here < 2:
		return ""
	var dests := RulerRules.road_destinations(_state, _fid, armies[0].id)
	var keys: Array = dests.keys()
	keys.sort()
	var best := ""
	var best_d := d_here - 1  # a road move has to beat a single step
	for to in keys:
		var d := _d(to, target)
		if d >= best_d or not _foes_at(to).is_empty():
			continue
		var friends: Array = armies + _friends_ending_at(to, armies)
		if not _safe_at(friends, to):
			continue
		best = to
		best_d = d
	if best.is_empty():
		return ""
	_last_via = String(dests[best][0])
	return best


## King's Roads recalls: our free armies two provinces from the capital that a road move brings home
## this turn, {army id: the province it goes through}. {} without King's Roads.
func _road_recalls(cap_id: String) -> Dictionary:
	var out := {}
	if not RulerRules.has_road_moves(_state, _fid):  # M4: or Forest Stride
		return out
	for a in _mine:
		if _busy.has(a.id) or _d(a.location, cap_id) != 2:
			continue
		var vias := RulerRules.road_vias(_state, _fid, a.id, cap_id)
		if not vias.is_empty():
			out[a.id] = String(vias[0])
	return out


## A safe step from `here` that gets closer to `target`, or "" when there is none. Stepping into
## `target` itself counts the friendly armies that will be there.
func _step_toward(here: String, target: String, armies: Array) -> String:
	var d_here := _d(here, target)
	var options := []
	for n in _nbrs[here]:
		if _d(n, target) != d_here - 1 or not _foes_at(n).is_empty():
			continue
		var friends: Array = armies + _friends_ending_at(n, armies)
		if _safe_at(friends, n):
			options.append(n)
	return "" if options.is_empty() else _pick_step(options)


## Among equally good steps: provinces we don't own first (they get captured on the way), then the
## highest income give or take a little random spread (JITTER), then a roll of the rng.
func _pick_step(options: Array) -> String:
	var best := []
	var best_key := -1.0
	for n in options:
		var p := _state.find_province(n)
		var gold: float = float(p.income)
		if _paths:
			gold = float(_income_if_ours(p)) + (RAID_WEIGHT * _raid_gold(p) if p.owner != _fid else 0.0)
		var key: float = gold + (100.0 if p.owner != _fid else 0.0) + _rng.randf() * float(JITTER[_level])
		if key > best_key + 0.0001:
			best_key = key
			best = [n]
		elif absf(key - best_key) <= 0.0001:
			best.append(n)
	if best.size() == 1:
		return best[0]
	return best[_rng.randi_range(0, best.size() - 1)]


func _safe_at(armies: Array, pid: String) -> bool:
	var threat := _threats_to(pid)
	return threat.is_empty() or _ratio(armies, threat, _ground_bonus(pid), 1.0) >= SAFE_RATIO


## The nearest enemy capital from `from_id` (ties: faction id order), or "".
func _objective_for(from_id: String) -> String:
	var best := ""
	var best_d := 1 << 30
	for f in _sorted_factions():
		if f.id == _fid:
			continue
		var p := _state.find_province(f.capital)
		if p == null or p.owner == _fid:
			continue
		var d := _d(from_id, p.id)
		if d < best_d:
			best = p.id
			best_d = d
	return best


# --- 5. recruits ----------------------------------------------------------------------------------

## Units to recruit this turn, in order, for the army that will stand in the capital after this
## turn's moves (`base`, our armies there). Recruits appear there, so they are next turn's garrison.
func _plan_recruits(base: Array) -> Array:
	var cap := _state.find_province(_me.capital)
	if cap == null or cap.owner != _fid:
		return []
	var roster: Array = []
	for ut in _me.unit_types:
		if ut.cost > 0 and not (MagicRules.is_mage(ut) and not MagicRules.knows_a_spell(_state, _fid)):  # M5-5: the mage gate
			roster.append(ut)
	var cmd: UnitType = _me.commander_type if _me.commander_type != null and _me.commander_type.cost > 0 else null
	var gold := _me.gold - _gold_reserved - _ritual_gold  # M3c: less what Fortify and engines take (0 without sieges); M5-10: and the rituals (0 without magic)
	var out := []
	if _level == "easy":
		# Cruder: random affordable picks until the gold runs out.
		var pool: Array = roster.duplicate()
		if cmd != null:
			pool.append(cmd)
		var garrison: Array = _units(_mine_at(cap.id)) if _state.magic else []  # M5-10: the mage ratio counts who stands here already
		for _i in 16:
			var affordable := pool.filter(func(ut): return _price(ut) <= gold and not (_state.magic and MagicRules.is_mage(ut) and not AIMagic.room_for_mage(garrison)))
			if affordable.is_empty():
				break
			var pick: UnitType = affordable[_rng.randi_range(0, affordable.size() - 1)]
			out.append(pick)
			if _state.magic:
				garrison.append(_recruit_unit(pick))
			gold -= _price(pick)
		return out
	# Normal: each pick most raises the garrison's trait-aware odds against the enemy's armies per gold
	# spent (_recruit_value). Prices are the ones the recruitment phase charges (Muster Grounds included).
	var foe_units := _units(_foes)
	var units: Array = _units(base)
	var has_cmd := false
	for a in base:
		if a.commander != null:
			has_cmd = true
	var threatened := false
	for e in _foes:
		if _d(e.location, cap.id) <= 2:
			threatened = true
	# A threatened capital with no commander gets one first: a commander steadies the whole army.
	if cmd != null and threatened and not has_cmd and _price(cmd) <= gold:
		out.append(cmd)
		units.append(_recruit_unit(cmd))
		gold -= _price(cmd)
	var value := _recruit_value(units, foe_units)
	for _i in 40:
		var best: UnitType = null
		var best_gain := 0.0
		var best_value := value
		var ranks := _ranks(units)
		# #94: against an overwhelming foe every gain is a sliver below the tie margin; gold has no other use,
		# so the best gain above nothing at all still buys (banked gold only feeds a stand-off).
		var sliver: UnitType = null
		var sliver_gain := 0.0
		var sliver_value := value
		for ut in roster:
			var price := _price(ut)
			if price > gold or price <= 0:
				continue
			# Volley holds its shield only while at least as many front-rank units stand: never recruit
			# past that (AutoBattleResolver._targets).
			if ut.trait_id == AutoBattleResolver.VOLLEY and ranks.volley + 1 > ranks.front:
				continue
			# M5-10: a mage fights from the second rank too, and the army holds at most one for every AIMagic.MAGE_PER regulars.
			if MagicRules.is_mage(ut) and (ranks.volley + 1 > ranks.front or not AIMagic.room_for_mage(units)):
				continue
			var trial: Array = units.duplicate()
			trial.append(_recruit_unit(ut))
			var v := _recruit_value(trial, foe_units)
			var gain := (v - value) / float(price)
			if gain > best_gain + 0.000001:
				best = ut
				best_gain = gain
				best_value = v
			if gain > sliver_gain:
				sliver = ut
				sliver_gain = gain
				sliver_value = v
		if best == null:
			best = sliver
			best_value = sliver_value
		if best == null:
			break
		out.append(best)
		units.append(_recruit_unit(best))
		gold -= _price(best)
		value = best_value
	return out


## What one `ut` costs us now: RulerRules.recruit_price, the recruitment phase's price.
func _price(ut: UnitType) -> int:
	return RulerRules.recruit_price(_state, _fid, ut)


## {"front", "volley"}: the regular units among `units` that stand in the front rank (no Volley) and in
## the second rank (Volley), as AutoBattleResolver ranks them. Commanders and rulers are left out.
static func _ranks(units: Array) -> Dictionary:
	var out := {"front": 0, "volley": 0}
	for u in units:
		if u.type.is_commander or u.type.is_ruler:
			continue
		if u.type.trait_id == AutoBattleResolver.VOLLEY or MagicRules.is_mage(u.type):  # M5-10: mages fight from the second rank
			out.volley += 1
		else:
			out.front += 1
	return out


## How well `units` would fight `foe_units` (or the enemy rosters, before any enemy army is seen),
## trait-aware: our _trait_power over theirs. Rulers are left out (they are never recruited).
func _recruit_value(units: Array, foe_units: Array) -> float:
	if units.is_empty():
		return 0.0
	var foes: Array = foe_units if not foe_units.is_empty() else _roster_units()
	var share := float(_ctx.get("forest_share", 0.0))
	if share <= 0.0 or share >= 1.0 or not (_foe_side(foes).rooted or units.any(func(u): return u.type.trait_id == AutoBattleResolver.ROOTED)):
		return _value_of(_side_summary(units, _ctx), _foe_summary(foes, "ctx", _ctx))
	# #94: Rooted works in a forest battle or not at all, and defense is not worth the same for every point (hit
	# chances stop at MIN_HIT, damage drops in steps of four), so half its ROOTED_DEFENSE on every battle misjudges
	# it: the value is that of a forest battle and of an open one, weighted by the forest share of our front.
	var forest := _ctx.duplicate()
	forest["forest_share"] = 1.0
	var open := _ctx.duplicate()
	open["forest_share"] = 0.0
	return share * _value_of(_side_summary(units, forest), _foe_summary(foes, "forest", forest)) \
		+ (1.0 - share) * _value_of(_side_summary(units, open), _foe_summary(foes, "open", open))


## #131: the foe side of _recruit_value, summed once per plan instead of for every unit the planner tries. A
## recruit plan tries every unit type up to 40 times against the same foe armies; with hundreds of foe units in a
## stand-off, summing them again each time was most of a plan's time. Kept while `foes` is the same Array;
## _begin, _rebase and the end of a plan clear it, so nothing carries over between plans.
func _foe_side(foes: Array) -> Dictionary:
	if not is_same(_foe_cache.get("foes"), foes):
		_foe_cache = {"foes": foes, "rooted": foes.any(func(u): return u.type.trait_id == AutoBattleResolver.ROOTED)}
	return _foe_cache


## The cached _side_summary of `foes` under `ctx`, one per `variant` ("ctx", "forest", "open").
func _foe_summary(foes: Array, variant: String, ctx: Dictionary) -> Dictionary:
	var side := _foe_side(foes)
	if not side.has(variant):
		side[variant] = _side_summary(foes, ctx)
	return side[variant]


## Our _trait_power over theirs.
static func _value_of(ours: Dictionary, theirs: Dictionary) -> float:
	return _trait_power(ours, theirs) / maxf(_trait_power(theirs, ours), 0.001)


## Totals of one side for _trait_power: {"hp", "morale", "regulars", "best_morale", "cmd", "inspire",
## "pack", "bears", "front", "volley", "skirmish", "fighters", "def_hp", "shield_hp", "kinds": {type id:
## {"type", "n", "attack"}}}, and for the M4 traits "commanders", "wings", "iron_hide_hp", "rooted".
## Rulers are skipped. `ctx` (M4, a game with paths: AIPlayer._ctx) gives every type's attack, defense
## and morale with its faction's mandates and path parts, and the share of forest provinces on our front
## for Rooted; without it the unit types' own numbers are used, exactly as before paths.
static func _side_summary(units: Array, ctx: Dictionary = {}) -> Dictionary:
	var s := {"hp": 0.0, "morale": 0, "regulars": 0, "best_morale": 0, "cmd": false, "inspire": false, "pack": false,
		"bears": 0, "front": 0, "volley": 0, "skirmish": 0, "fighters": 0, "def_hp": 0.0, "shield_hp": 0.0, "kinds": {},
		"commanders": 0, "cmd_hp": 0.0, "cmd_def_hp": 0.0, "wings": 0, "iron_hide_hp": 0.0, "rooted": 0,
		"iron_discipline": false, "frenzy": 0, "wounded_aware": false,
		"mages": {}, "mages_n": 0, "casts": ctx.get("casts", {}), "shield_ok": ctx.get("shield_ok", true)}  # M5-10: mages cast, from the second rank
	var stats: Dictionary = ctx.get("stats", {})
	var disciplined: Dictionary = ctx.get("iron_discipline", {})
	var frenzy: Dictionary = ctx.get("frenzy", {})
	s.wounded_aware = not stats.is_empty()  # #94: with paths, a unit's maximum hp is known, so who is wounded is too
	for u in units:
		var ut: UnitType = u.type
		if ut.is_ruler:
			continue
		var attack: int = ut.attack
		var defense: int = ut.defense
		var morale: int = ut.morale
		var max_hp: int = ut.hp
		if not stats.is_empty():
			var st: Dictionary = stats.get(u.owner + "|" + ut.id, {})
			if not st.is_empty():
				attack = int(st.attack)
				defense = int(st.defense)
				morale = int(st.morale)
				max_hp = int(st.get("hp", ut.hp))
		var hp := float(u.current_hp)
		s.hp += hp
		s.def_hp += hp * defense
		s.fighters += 1
		if disciplined.get(u.owner, false):
			s.iron_discipline = true
		s.frenzy = maxi(int(s.frenzy), int(frenzy.get(u.owner, 0)))
		if ut.is_commander:
			s.cmd = true
			s.commanders += 1
			s.cmd_hp += hp
			s.cmd_def_hp += hp * defense
			s.best_morale = maxi(s.best_morale, morale)
			if ut.trait_id == AutoBattleResolver.INSPIRE:
				s.inspire = true
			elif ut.trait_id == AutoBattleResolver.PACK_LEADER:
				s.pack = true
		else:
			s.morale += morale
			s.regulars += 1
			if ut.trait_id == AutoBattleResolver.VOLLEY:
				s.volley += 1
			elif ut.trait_id == AutoBattleResolver.MAGE:
				s.volley += 1  # M5-10: a mage stands in the second rank, under the same shield rule as Volley
				s.mages_n += 1
				s.mages[u.owner] = int(s.mages.get(u.owner, 0)) + 1
			else:
				s.front += 1
			if ut.trait_id == AutoBattleResolver.SKIRMISH:
				s.skirmish += 1
			elif ut.trait_id == AutoBattleResolver.FURY:
				s.bears += 1
			elif ut.trait_id == AutoBattleResolver.SHIELD_WALL:
				s.shield_hp += hp
			elif ut.trait_id == AutoBattleResolver.WINGS:
				s.wings += 1
			elif ut.trait_id == AutoBattleResolver.IRON_HIDE:
				s.iron_hide_hp += hp
			elif ut.trait_id == AutoBattleResolver.ROOTED:
				# Rooted: +ROOTED_DEFENSE in a province battle in a forest, counted by the forest share of our front.
				s.rooted += 1
				s.def_hp += hp * AutoBattleResolver.ROOTED_DEFENSE * float(ctx.get("forest_share", 0.0))
		if not s.kinds.has(ut.id):
			s.kinds[ut.id] = {"type": ut, "n": 0, "attack": attack, "wounded": 0, "defense": defense,
				"front": not ut.is_commander and ut.trait_id != AutoBattleResolver.VOLLEY and ut.trait_id != AutoBattleResolver.MAGE}
		s.kinds[ut.id].n += 1
		if u.current_hp < max_hp:
			s.kinds[ut.id].wounded += 1  # #94: Lifedrinker heals from the first round (Blood Levy recruits arrive so)
	return s


## Rough fighting power of side `s` against side `foe` (both _side_summary), with the traits counted the
## way AutoBattleResolver applies them, from its own constants: the hp the side can lose before it
## breaks (morale with commanders, Inspire and the foe's Fury) x the damage it deals per round. Shield
## Wall raises our defense, Pack Leader and (about half the time) Berserk our attack, Charge adds its
## first-round damage; a shielded Volley unit's damage counts more (less against Skirmish), and a
## Skirmish unit's more against an enemy with Volley units, which only Skirmish reaches behind its front.
## M4 traits: the foe's Wings put our commander bonuses at risk (_wings_keep) and reach our second rank
## like Skirmish; the foe's Iron Hide takes IRON_HIDE_DAMAGE off our hits on it (never below
## MIN_DAMAGE); our Lifedrinker hits heal us (LIFEDRINK_DIVISOR, LIFEDRINK_SHARE of ROUNDS_GUESS rounds).
static func _trait_power(s: Dictionary, foe: Dictionary) -> float:
	if float(s.hp) <= 0.0:
		return 0.0
	var foe_def := _summary_defense(foe)
	var m: float = float(s.morale) / s.regulars if int(s.regulars) > 0 else float(s.best_morale)
	# The foe's Wings dive at our commanders while one stands: their bonuses count for less.
	var keep := 1.0
	if int(foe.get("wings", 0)) > 0 and int(s.get("commanders", 0)) > 0:
		keep = _wings_keep(s, foe)
	if s.cmd:
		m += AutoBattleResolver.COMMANDER_MORALE if keep >= 1.0 else AutoBattleResolver.COMMANDER_MORALE * keep
	if s.inspire:
		m += AutoBattleResolver.INSPIRE_MORALE if keep >= 1.0 else AutoBattleResolver.INSPIRE_MORALE * keep
	m -= mini(AutoBattleResolver.FURY_MAX, AutoBattleResolver.FURY_MORALE * int(foe.bears))
	var hold := clampf(AutoBattleResolver.BREAK_BASE_PCT + AutoBattleResolver.MORALE_PCT_PER_POINT * m,
		AutoBattleResolver.MIN_BREAK_PCT, AutoBattleResolver.MAX_BREAK_PCT) / 100.0
	if s.get("iron_discipline", false) and s.cmd:
		# M4 (paths only): Iron Discipline, a side never breaks while one of its commanders stands, for the
		# share of the battle its commander survives the foe's Wings.
		hold = keep * AutoBattleResolver.MAX_BREAK_PCT / 100.0 + (1.0 - keep) * hold
	var shielded: bool = int(s.volley) > 0 and int(s.front) >= int(s.volley)
	# Enemy Skirmish units reach our shielded Volley units anyway; ours reach the enemy's. Both pick
	# their targets at random among the ranks they reach, so it is the share of each side's units that counts.
	var foe_regulars := maxf(1.0, float(foe.regulars))
	var foe_reach := float(foe.skirmish + foe.get("wings", 0)) / foe_regulars
	var our_targets := float(foe.volley) / foe_regulars
	var hide_share := float(foe.get("iron_hide_hp", 0.0)) / float(foe.hp) if float(foe.hp) > 0.0 else 0.0
	var dmg := 0.0
	var drink := 0.0
	for kind in s.kinds.values():
		# #94: with paths, the units already wounded (every Blood Levy recruit) have Berserk and Blood Frenzy from
		# the first blow; the others about BERSERK_SHARE of the time. Without paths, every unit is the latter.
		var parts := [[int(kind.n), false]]
		if s.get("wounded_aware", false):
			parts = [[int(kind.get("wounded", 0)), true], [int(kind.n) - int(kind.get("wounded", 0)), false]]
		for part in parts:
			if int(part[0]) <= 0:
				continue
			var k: Dictionary = kind.duplicate()
			k.n = int(part[0])
			k.wounded = int(part[0]) if part[1] else 0
			var took := _kind_power(k, s, foe_def, keep, hide_share, shielded, foe_reach, our_targets, bool(part[1]))
			dmg += float(took.dmg)
			drink += float(took.drink)
	if int(s.get("mages_n", 0)) > 0:
		# M5-10: a mage casts instead of attacking; shielded in the second rank it lasts longer, as Volley does
		dmg += AIMagic.mage_pressure(s, foe, 1.0 + VOLLEY_SHIELD_VALUE * (1.0 - foe_reach) if shielded else 1.0, ROUNDS_GUESS)
	# What the side can lose before it breaks. Lifedrinker's healing lands before morale is checked, so every
	# hp healed is an hp not lost: it counts in full, not just the share the side would lose of it (#94).
	return (float(s.hp) * hold + drink * ROUNDS_GUESS) * dmg


## The damage a round and the healing a round (Lifedrinker) of one kind of units `k` ({"type", "n", "attack",
## "wounded"}) of side `s`, all `hurt` (below their maximum hp) or none, for _trait_power. {"dmg", "drink"}.
static func _kind_power(k: Dictionary, s: Dictionary, foe_def: float, keep: float, hide_share: float, shielded: bool,
		foe_reach: float, our_targets: float, hurt: bool) -> Dictionary:
	var dmg := 0.0
	var drink := 0.0
	var ut: UnitType = k.type
	if ut.trait_id == AutoBattleResolver.MAGE:
		return {"dmg": 0.0, "drink": 0.0}  # M5-10: its spells are counted together (AIMagic.mage_pressure)
	var atk := float(k.attack)
	if not ut.is_commander and s.pack:
		atk += AutoBattleResolver.PACK_LEADER_ATTACK if keep >= 1.0 else AutoBattleResolver.PACK_LEADER_ATTACK * keep
	var wound_share := 1.0 if hurt else BERSERK_SHARE
	if ut.trait_id == AutoBattleResolver.BERSERK:
		atk += AutoBattleResolver.BERSERK_ATTACK * wound_share
	atk += float(s.get("frenzy", 0)) * wound_share  # Blood Frenzy: every fighter below its maximum hp
	var hit := _hit_rate(atk, foe_def)
	var raw := maxf(AutoBattleResolver.MIN_DAMAGE, ceilf(atk * 0.5) - floorf(foe_def * 0.25))
	var per_hit := raw
	var hidden := maxf(AutoBattleResolver.MIN_DAMAGE, raw - AutoBattleResolver.IRON_HIDE_DAMAGE)
	if hide_share > 0.0:
		# Iron Hide: every hit on it deals IRON_HIDE_DAMAGE less, but at least MIN_DAMAGE.
		per_hit = (1.0 - hide_share) * raw + hide_share * hidden
	var per := hit * per_hit
	if ut.trait_id == AutoBattleResolver.CHARGE:
		per += hit * AutoBattleResolver.CHARGE_DAMAGE / ROUNDS_GUESS
	if ut.trait_id == AutoBattleResolver.VOLLEY and shielded:
		per *= 1.0 + VOLLEY_SHIELD_VALUE * (1.0 - foe_reach)
	if ut.trait_id == AutoBattleResolver.SKIRMISH or ut.trait_id == AutoBattleResolver.WINGS:
		per *= 1.0 + SKIRMISH_REACH_VALUE * our_targets
	dmg += per * int(k.n)
	if ut.trait_id == AutoBattleResolver.LIFEDRINKER:
		# #94: each hit heals the damage it dealt over LIFEDRINK_DIVISOR, rounded up (the rules' own rounding),
		# from the first round for a unit already wounded (a Blood Levy recruit), else LIFEDRINK_SHARE of the time.
		var div := float(AutoBattleResolver.LIFEDRINK_DIVISOR)
		var heal := hit * ((1.0 - hide_share) * ceilf(raw / div) + hide_share * ceilf(hidden / div))
		var wounded := float(k.get("wounded", 0))
		drink += heal * (wounded + (float(k.n) - wounded) * LIFEDRINK_SHARE)
	return {"dmg": dmg, "drink": drink}


## The share of a battle side `s` keeps its commander bonuses against the foe's Wings units: 1 minus their
## expected damage on one of its commanders (the average one) over ROUNDS_GUESS rounds, against its hp, with
## the battle rules' hit and damage formulas. Worth nothing against a side without commanders.
static func _wings_keep(s: Dictionary, foe: Dictionary) -> float:
	var n := int(s.get("commanders", 0))
	if n <= 0 or float(s.cmd_hp) <= 0.0:
		return 1.0
	var cmd_hp := float(s.cmd_hp) / n
	var cmd_def := float(s.cmd_def_hp) / float(s.cmd_hp)
	var dmg := 0.0
	for k in foe.kinds.values():
		if k.type.trait_id != AutoBattleResolver.WINGS:
			continue
		var atk := float(k.attack)
		dmg += _hit_rate(atk, cmd_def) * maxf(AutoBattleResolver.MIN_DAMAGE, ceilf(atk * 0.5) - floorf(cmd_def * 0.25)) * int(k.n)
	return 1.0 - minf(1.0, dmg * ROUNDS_GUESS / cmd_hp)


## A side's average defense, weighted by hp, with Shield Wall's bonus while it has company.
static func _summary_defense(s: Dictionary) -> float:
	if float(s.hp) <= 0.0:
		return 0.0
	var total: float = s.def_hp
	if int(s.fighters) > 1:
		total += AutoBattleResolver.SHIELD_WALL_DEFENSE * float(s.shield_hp)
	return total / float(s.hp)


## Chance one attack with `atk` hits `def`, AutoBattleResolver's rule: BASE_HIT plus HIT_PER_POINT per
## point of attack over defense, within MIN_HIT..MAX_HIT percent.
static func _hit_rate(atk: float, def: float) -> float:
	return clampf(AutoBattleResolver.BASE_HIT + AutoBattleResolver.HIT_PER_POINT * (atk - def),
		AutoBattleResolver.MIN_HIT, AutoBattleResolver.MAX_HIT) / 100.0


## One unit of each type the other factions can recruit, as a stand-in enemy.
func _roster_units() -> Array:
	var out := []
	for f in _state.factions:
		if f.id == _fid:
			continue
		for ut in f.unit_types:
			out.append(Unit.new(ut, f.id))
	return out


## The planned recruits as unit objects, for strength guesses about next turn's garrison.
func _recruit_units() -> Array:
	var out := []
	for ut in _recruit_plan:
		out.append(_recruit_unit(ut))
	return out


# --- orders ---------------------------------------------------------------------------------------

func _checked_moves() -> Array:
	var ids: Array = _moves.keys()
	ids.sort()
	var ordered := {}
	var out := []
	var roads := []
	for id in ids:
		var order := MoveOrder.new(str(id), str(_moves[id]), str(_vias.get(id, "")))
		if TurnResolver.check_move(_state, _fid, order, ordered).is_empty():
			ordered[order.army_id] = true
			out.append(order)
			if order.is_road_move():
				_stats.road_moves += 1
				roads.append(order)
		else:
			_stats.dropped_invalid += 1
	# M4: a road move uses King's Roads or Forest Stride (TurnResolver.road_rule); without paths every one
	# is a King's Roads move, and the note is as before.
	var kings := roads.filter(func(o): return TurnResolver.road_rule(_state, _fid, o) != "forest_stride")
	var stride := roads.filter(func(o): return TurnResolver.road_rule(_state, _fid, o) == "forest_stride")
	if not kings.is_empty():
		var parts := []
		for o in kings.slice(0, 2):
			var a := _state.find_army(o.army_id)
			var who := "%s at %s" % ["our ruler" if a != null and a.ruler != null else "the army", _province_name(a.location if a else "")]
			parts.append("%s goes through %s to %s" % [who, _province_name(o.via), _province_name(o.to)])
		var more := "" if kings.size() <= 2 else " (and %d more)" % (kings.size() - 2)
		_note_top("Using the King's Roads: %s%s, two provinces in one turn through our own land." % [" and ".join(parts), more])
	if not stride.is_empty():
		var parts := []
		for o in stride.slice(0, 2):
			var a := _state.find_army(o.army_id)
			var who := "%s at %s" % ["our ruler" if a != null and a.ruler != null else "the army", _province_name(a.location if a else "")]
			parts.append("%s goes through the forest of %s to %s" % [who, _province_name(o.via), _province_name(o.to)])
		var more := "" if stride.size() <= 2 else " (and %d more)" % (stride.size() - 2)
		_note_top("Using Forest Stride: %s%s, two provinces in one turn through our own forest." % [" and ".join(parts), more])
	return out


func _checked_recruits() -> Array:
	var field := _field_recruit_count()
	var out := []
	var home := {"counts": {}, "names": [], "spent": 0}
	var away := {"counts": {}, "names": [], "spent": 0}
	for ut in _recruit_plan:
		# Warband Muster: the first regular units of the plan go with the ruler, up to its limit.
		var order := RecruitOrder.new(ut.id, RecruitOrder.AT_RULER if field > 0 and not ut.is_commander else RecruitOrder.AT_CAPITAL)
		var trial := out.duplicate()
		trial.append(order)
		var r: Dictionary = TurnResolver.price_recruits(_state, _fid, trial, null, _ritual_gold).results.back()  # M5-10: less the rituals' gold
		if not r.ok and order.is_with_ruler():
			order = RecruitOrder.new(ut.id)
			trial = out.duplicate()
			trial.append(order)
			r = TurnResolver.price_recruits(_state, _fid, trial, null, _ritual_gold).results.back()
		if not r.ok:
			_stats.dropped_invalid += 1
			continue
		out.append(order)
		var tally: Dictionary = away if order.is_with_ruler() else home
		if order.is_with_ruler():
			field -= 1
			_stats.field_recruits += 1
		tally.spent += int(r.cost)
		if not tally.counts.has(ut.name):
			tally.counts[ut.name] = 0
			tally.names.append(ut.name)
		tally.counts[ut.name] += 1
	_stats.recruits = out.size()
	if not home.names.is_empty():
		_note("Recruiting at %s for %d gold: %s." % [_province_name(_me.capital), home.spent, _tally_text(home)])
	if _paths:
		# M4: why a unit with a path trait (Seraphs, the Iron Colossus, Briarwardens, Bloodsworn) is in the plan.
		var counts := {}
		var types := []
		for o in out:
			var ut := TurnResolver.recruitable_type(_me, o.unit_type_id)
			if ut == null or not AutoBattleResolver.PATH_TRAITS.has(ut.trait_id):
				continue
			if not counts.has(ut.id):
				counts[ut.id] = 0
				types.append(ut)
			counts[ut.id] += 1
		for ut in types:
			var why := _path_recruit_reason(ut, int(counts[ut.id]))
			if not why.is_empty():
				_note_top(why)
				_stats["path_recruits"] = int(_stats.get("path_recruits", 0)) + int(counts[ut.id])
	if not away.names.is_empty():
		var dest: String = _ruler.location if _ruler != null else ""  # they gather where the ruler starts the turn
		_note_top("Recruiting with %s for %d gold: %s, joining our armies at %s at the end of the turn (Warband Muster)." % [
			RulerRules.current_name(_state, _fid), away.spent, _tally_text(away), _province_name(dest)])
	return out


## "Tuskers x2, War Bear x1" from a recruit tally.
static func _tally_text(tally: Dictionary) -> String:
	var parts := []
	for n in tally.names:
		parts.append("%s x%d" % [n, tally.counts[n]])
	return ", ".join(parts)


## How many of this turn's recruits go with our ruler (Warband Muster, §1.4): up to its limit while it
## stands in our own land, unless it is away from a capital that needs the defenders this turn. The
## recruits gather where it starts the turn; at the capital they are the same as capital recruits.
func _field_recruit_count() -> int:
	if _ruler == null:
		return 0
	var limit := RulerRules.field_recruit_limit(_state, _fid)
	if limit <= 0:
		return 0
	var where := _state.find_province(_ruler.location)
	if where == null or where.owner != _fid:
		return 0
	var away: bool = _ruler.location != _me.capital
	if away and (_capital_short or _home_rate < HOLD_TARGET[_level] or _foe_within(_me.capital, FIELD_RECRUIT_SAFE)):
		_note("Recruiting at %s rather than with %s: enemy armies are close enough to need the defenders at home." % [
			_province_name(_me.capital), RulerRules.current_name(_state, _fid)])
		return 0
	if away and _armies_ending_at(_me.capital).is_empty():
		# Nobody else will stand in the capital: at least half of this turn's regular recruits stay there.
		var regulars := _recruit_plan.filter(func(ut): return not ut.is_commander).size()
		return mini(limit, regulars / 2)
	return limit


## True when an enemy army stands within `steps` moves of `pid`.
func _foe_within(pid: String, steps: int) -> bool:
	for e in _foes:
		if _d(e.location, pid) <= steps:
			return true
	return false


func _move(a: Army, dest: String, via: String = "") -> void:
	if dest == a.location:
		_hold(a)
		return
	_moves[a.id] = dest
	if via.is_empty():
		_vias.erase(a.id)
	else:
		_vias[a.id] = via
	_busy[a.id] = true


func _hold(a: Army) -> void:
	_moves.erase(a.id)
	_vias.erase(a.id)
	_busy[a.id] = true


# --- IND-1: Free Holds garrisons (#142) ------------------------------------------------------------

## Our win rate if `attackers` attack the garrison of `pid` together; 1.0 where no garrison stands. The rough
## guess decides when it is lopsided, otherwise Forecast.battle_odds (the same forecast players see).
func _hold_rate(attackers: Array, pid: String) -> float:
	var g: Army = _holds.get(pid)
	if g == null or attackers.is_empty():
		return 1.0
	var ratio := _ratio(attackers, [g], 1.0, _ground_bonus(pid))
	if ratio >= SURE_RATIO:
		return 0.95
	if ratio <= HOPELESS_RATIO:
		return 0.05
	var ids := []
	for a in attackers:
		ids.append(a.id)
	var r: Dictionary = _odds(_state, _fid, ids, pid, false)
	return float(r.win_rate) if r.has("win_rate") else _rate_from_ratio(ratio)


## Every province with a garrison that this plan marches into: the armies going there together must beat it at
## HOLD_ATTACK_RATE or better, or they all hold where they are (and mass for next turn).
func _guard_holds() -> void:
	var into := {}  # province id -> our armies moving there
	for id in _moves:
		var dest := String(_moves[id])
		if _holds.has(dest):
			if not into.has(dest):
				into[dest] = []
			into[dest].append(_state.find_army(String(id)))
	var pids: Array = into.keys()
	pids.sort()
	for pid in pids:
		var rate := _hold_rate(into[pid], pid)
		if rate >= _risk(float(HOLD_ATTACK_RATE[_level])):
			_note("Attacking the %s: %d%% to win." % [TurnReportText.army_name(_state, _holds[pid].id).trim_prefix("the "), roundi(rate * 100.0)])
			continue
		for a in into[pid]:
			_hold(a)
		_note("Holding back from %s: its garrison is too strong for now (%d%% to win)." % [_province_name(pid), roundi(rate * 100.0)])


## #184: the odds a fight needs, `base` less RISK_DISCOUNT for the aggressive temperament (and `base` itself otherwise).
func _risk(base: float) -> float:
	return base - RISK_DISCOUNT if _temperament == "aggressive" else base


func _skips() -> bool:
	return _level == "easy" and _rng.randf() < EASY_SKIP


# --- M2: the build, sacrifices and the ruler (design/M2_RULER.md §6.1, §6.3) ---------------------

## Turn 1 of a game with rulers: which build we play and what it means for the ruler, in a note.
## #184: on the first turn, the aggressive computer says how it plays (a steady one says nothing, as before).
func _note_temperament() -> void:
	if _temperament != "aggressive" or _state.current_turn != 0:
		return
	_note_top("%s plays aggressively: it storms, besieges and attacks at odds %d points worse than a steady computer, loses patience in a stand-off twice as fast, and goes around a fort it won't attack to take land from the Free Holds or raid." % [
		_me.faction_name, roundi(RISK_DISCOUNT * 100.0)])


func _note_build() -> void:
	if _preset.is_empty() or _state.current_turn != 0:
		return
	var who := RulerRules._cap(RulerRules.current_name(_state, _fid))
	var kept := RulerRules.kept_power(_state, _fid)
	var names := []
	for mid in _preset.mandates:
		names.append(RulerRules.mandate_name(mid))
	var build := "%s plays %s" % [_me.faction_name, _preset.name] if not String(_preset.name).is_empty() else "%s plays its own build" % _me.faction_name
	var spend := "keeps all %d power" % kept if names.is_empty() else "spends %d power on %s and keeps %d" % [
		RulerData.POWER_POOL - kept, RulerRules._and_list(names), kept]
	var role := "stays home in %s, where a ruler with little power is safest" % _province_name(_me.capital) if _ruler_role() == "home" \
		else "marches with the main army and fights beside it when the odds are good"
	var text := "%s: %s %s, and %s." % [build, who, spend, role]
	var picks := []
	for mid in _preset.get("ai_sacrifices", []):
		picks.append(RulerRules.mandate_name(mid))
	if not picks.is_empty():
		text += " If %s is in danger, or the economy falls behind from turn %d, the ruler sacrifices power for %s." % [
			_province_name(_me.capital), SACRIFICE_TURN, ", then ".join(picks)]
	_note_top(text)


## "home" (the ruler stays at or near the capital) or "field" (it goes with the strongest army): the
## preset's role. A build of its own (preset_for's stand-in) plays home while it keeps LOW_KEPT power or less.
func _ruler_role() -> String:
	if _preset.is_empty():
		return "home"
	if String(_preset.get("id", "")).is_empty() and RulerRules.kept_power(_state, _fid) <= LOW_KEPT:
		return "home"
	return String(_preset.get("ai_role", "home"))


## The mandate to sacrifice for this turn, or "" (§6.3): the preset's first pick that
## RulerRules.sacrifice_check allows, when (a) an enemy army next to the capital could win there (the
## defenders' odds, with every army that could come back, are close or a likely loss), or (b) from turn
## SACRIFICE_TURN, our income is at most SACRIFICE_INCOME_SHARE of the strongest enemy's.
func _choose_sacrifice() -> String:
	if _ruler == null or _preset.is_empty():
		return ""
	var pick := ""
	var picks: Array = _preset.get("ai_sacrifices", []).duplicate()
	picks = AIMagic.sacrifice_picks(_state, String(_preset.get("id", "")), picks)  # M5-10: Blood of the Fang puts Tithe of Blood first (a game with magic)
	if _paths:
		# M4: once transformed, the mandate it opened goes last; a forsworn pick fails sacrifice_check.
		for mid in AscensionRules.opened_mandates(_state, _fid):
			if not picks.has(mid):
				picks.append(mid)
	for mid in picks:
		if RulerRules.sacrifice_check(_state, _fid, String(mid)).is_empty():
			pick = String(mid)
			break
	if pick.is_empty():
		return ""
	var why := _capital_danger()
	if why.is_empty():
		why = _falling_behind()
	if why.is_empty():
		return ""
	var kept := RulerRules.kept_power(_state, _fid)
	var cost := RulerRules.sacrifice_cost(pick)
	var opened := ""
	if _paths and AscensionRules.opened_mandates(_state, _fid).has(pick):
		opened = "; %s opened it" % AscensionRules.branch_ref(AscensionRules.branch(_state, _fid))
	_note_top("Sacrificing %d of %s's power for %s (%d, +%d for a mid-game sacrifice%s), kept power %d to %d: %s." % [
		cost, RulerRules.current_name(_state, _fid), RulerRules.mandate_name(pick), RulerRules.mandate_cost(pick),
		MandateData.SACRIFICE_PREMIUM, opened, kept, kept - cost, why])
	return pick


## Why the capital is in danger, or "": an enemy army next to it, and our odds as defender with every
## army that could be back this turn (and the ruler, when it is there) are close or worse.
func _capital_danger() -> String:
	var cap := _state.find_province(_me.capital)
	if cap == null or cap.owner != _fid:
		return ""
	var threats := _fog.top(_threats_to(cap.id))  # M5-4: at the top of each sighting
	if threats.is_empty():
		return ""
	var defenders := _mine_at(cap.id)
	for n in _nbrs[cap.id]:
		defenders.append_array(_mine_at(n))
	if _ruler != null and _ruler.location == cap.id:
		defenders.append(_ruler)
	var rate := _defense_rate(cap.id, defenders, threats) if not defenders.is_empty() else 0.0
	if rate >= LIKELY_WIN:
		return ""
	return "an enemy army at %s threatens %s, and our odds as defender are only %s" % [_places_text(threats), cap.name, _odds_words(rate)]


## Why we are falling behind, or "": from turn SACRIFICE_TURN, our income is at most
## SACRIFICE_INCOME_SHARE of the strongest enemy's.
func _falling_behind() -> String:
	var turn := _state.current_turn + 1
	if turn < SACRIFICE_TURN:
		return ""
	var ours: int = TurnResolver.income_of(_state, _fid).total
	var best := 0
	var best_name := ""
	for f in _sorted_factions():
		if f.id == _fid:
			continue
		var theirs: int = TurnResolver.income_of(_state, f.id).total
		if theirs > best:
			best = theirs
			best_name = f.faction_name
	if best <= 0 or float(ours) > SACRIFICE_INCOME_SHARE * best:
		return ""
	return "on turn %d our income is %d gold against %d for the %s, so the war has to be won with what we have" % [turn, ours, best, best_name]


## Our ruler when it holds the capital this turn (a home ruler standing there), as [army]; [] otherwise.
## The capital's defense counts it.
func _home_guard() -> Array:
	if _ruler != null and _ruler.location == _me.capital and _ruler_role() == "home":
		return [_ruler]
	return []


## Our strongest army by hp x attack (units and commander; ties: first by id), or null.
func _lead_army() -> Army:
	var best: Army = null
	var best_power := -1
	for a in _mine:
		var p := 0
		for u in _members(a):
			p += u.current_hp * u.type.attack
		if p > best_power:
			best = a
			best_power = p
	return best


## Plans our ruler's army, after every other army (§6.3). Home: it holds the capital, or walks back to
## it. Field: it goes where the strongest army ends the turn (the same move, or a step along the
## shortest path, by road when that is quicker). Either way it only ends the turn somewhere safe
## (_ruler_spot); otherwise it tries holding, then falling back toward the capital, and at worst takes
## the safest of those.
func _ruler_moves() -> void:
	if _ruler == null:
		var info := RulerRules.succession_info(_state, _fid)
		if not info.is_empty():
			_note_top("No ruler this turn: %s" % RulerRules.successor_sentence(info))
		return
	if _state.sieges and _sieges.keeps_ruler():
		return  # M3c: inside a besieged fort the ruler stays (or leaves with its garrison)
	var here: String = _ruler.location
	var cap: String = _me.capital
	var who := RulerRules._cap(RulerRules.current_name(_state, _fid))
	var kept := RulerRules.kept_power(_state, _fid)
	var options := []  # [{"to", "via", "why"}], best first
	if _ruler_role() == "home":
		var reason := "with %d kept power %s is easy to kill" % [kept, RulerRules.current_name(_state, _fid)] if kept <= LOW_KEPT \
			else "its build keeps it home"
		if here == cap and (_ruler_spot(cap).ok or _sally_to.is_empty()):
			_hold(_ruler)
			_note_top("%s stays in %s: %s." % [who, _province_name(cap), reason])
			return
		if here == cap:
			# The garrison sallies (a stand-off lets it at a likely win, #94), and an enemy army is next door: the
			# ruler goes with the garrison rather than wait in the capital alone.
			options.append({"to": _sally_to, "via": "", "why": "with the garrison's sally out of %s" % _province_name(cap)})
			options.append({"to": here, "via": "", "why": reason})
		else:
			options.append_array(_ruler_steps(cap, "to head back to %s: %s" % [_province_name(cap), reason]))
			options.append({"to": here, "via": "", "why": "holding: the way back to %s isn't safe this turn" % _province_name(cap)})
	else:
		var lead := _lead_army()
		if lead == null:
			if here != cap:
				options.append_array(_ruler_steps(cap, "back to %s: we have no army for it to march with" % _province_name(cap)))
			options.append({"to": here, "via": "", "why": "we have no army for it to march with"})
		else:
			var dest: String = _moves.get(lead.id, lead.location)
			var main_name := _province_name(dest)
			if here == lead.location or dest == here:
				var why := "with the main army"
				options.append({"to": dest, "via": str(_vias.get(lead.id, "")) if here == lead.location else "", "why": why})
			else:
				options.append_array(_ruler_steps(dest, "to rejoin the main army at %s" % main_name))
			if here != dest:
				options.append({"to": here, "via": "", "why": "holding: it can't join the main army safely this turn"})
			if here != cap:
				options.append_array(_ruler_steps(cap, "falling back toward %s: it can't stay with the main army safely" % _province_name(cap)))
	var best := {}
	var best_spot := {}
	for o in options:
		if not o.via.is_empty() and RulerRules.road_vias(_state, _fid, _ruler.id, o.to).is_empty():
			continue
		var spot := _ruler_spot(o.to)
		if spot.ok:
			best = o
			best_spot = spot
			break
		if best.is_empty() or float(spot.rate) > float(best_spot.rate) + 0.0001:
			best = o
			best_spot = spot
	if best.is_empty():
		_hold(_ruler)
		return
	if best.to == here:
		_hold(_ruler)
	else:
		# A road move is checked again: the way through must still be legal for the ruler's army.
		var via: String = best.via
		if not via.is_empty() and not RulerRules.road_vias(_state, _fid, _ruler.id, best.to).has(via):
			via = ""
		_move(_ruler, best.to, via)
		_stats.ruler_moves += 1
	_note_top(_ruler_note(who, best, best_spot))


## Steps for our ruler toward `target`: a road move (King's Roads) that gets closer than one step, then
## the one-step moves that get closer, provinces without an enemy army first. [{"to", "via", "why"}].
func _ruler_steps(target: String, why: String) -> Array:
	var here: String = _ruler.location
	var d_here := _d(here, target)
	var out := []
	if d_here <= 0:
		return out
	if RulerRules.has_road_moves(_state, _fid) and d_here >= 2:  # M4: or Forest Stride
		var dests := RulerRules.road_destinations(_state, _fid, _ruler.id)
		var keys: Array = dests.keys()
		keys.sort()
		var best := ""
		var best_d := d_here - 1
		for to in keys:
			if _d(to, target) < best_d:
				best = to
				best_d = _d(to, target)
		if not best.is_empty():
			out.append({"to": best, "via": String(dests[best][0]), "why": why})
	var quiet := []
	var held := []
	for n in _nbrs[here]:
		if _d(n, target) != d_here - 1:
			continue
		if _foes_at(n).is_empty():
			quiet.append({"to": n, "via": "", "why": why})
		else:
			held.append({"to": n, "via": "", "why": why})
	out.append_array(quiet)
	out.append_array(held)
	return out


## Whether our ruler can safely end the turn in `pid`, given the moves planned so far:
## {"ok", "rate", "label", "kind"}. kind "attack": an enemy army holds `pid`, so the ruler would fight
## beside our armies moving in, never alone, and only at RULER_JOIN_WIN or better with it. "guard": an
## enemy army next door could attack `pid`; our armies ending there, with the ruler, must hold at
## RULER_GUARD_WIN or better, and the ruler is never left there alone. "quiet": no enemy army can reach it.
func _ruler_spot(pid: String) -> Dictionary:
	var friends := _armies_ending_at(pid)
	var held := _foes_at(pid)
	if not held.is_empty():
		if friends.is_empty():
			return {"ok": false, "rate": 0.0, "label": "likely loss", "kind": "alone"}
		var odds := _attack_rate(friends + [_ruler], pid)
		return {"ok": float(odds.rate) >= RULER_JOIN_WIN, "rate": float(odds.rate), "label": str(odds.label), "kind": "attack"}
	var threats := _foes_next_to(pid)
	if threats.is_empty():
		return {"ok": true, "rate": 1.0, "label": "", "kind": "quiet"}
	if friends.is_empty():
		return {"ok": false, "rate": 0.0, "label": "likely loss", "kind": "alone"}
	var rate := _defense_rate(pid, friends + [_ruler], threats)
	return {"ok": rate >= RULER_GUARD_WIN, "rate": rate, "label": _label_for(rate), "kind": "guard"}


## The ruler's note: where it goes, why, and the odds when a battle could follow.
func _ruler_note(who: String, o: Dictionary, spot: Dictionary) -> String:
	var here: String = _ruler.location
	var place := _province_name(o.to)
	var road := "" if String(o.via).is_empty() else " by the King's Roads through %s" % _province_name(o.via)
	if not road.is_empty() and TurnResolver.road_rule(_state, _fid, MoveOrder.new(_ruler.id, String(o.to), String(o.via))) == "forest_stride":
		road = " by Forest Stride through the forest of %s" % _province_name(o.via)  # M4
	var odds := ""
	match String(spot.get("kind", "")):
		"attack":
			odds = " (odds with %s fighting: %s)" % [RulerRules.current_name(_state, _fid), _odds_words(float(spot.rate), str(spot.label))]
		"guard":
			odds = " (odds if attacked there: %s)" % _odds_words(float(spot.rate))
		"alone":
			odds = " (nowhere safer within reach)"
	if o.to == here:
		return "%s holds at %s, %s%s." % [who, place, o.why, odds]
	if String(spot.get("kind", "")) == "attack":
		return "%s attacks %s%s %s%s." % [who, place, road, o.why, odds]
	return "%s moves to %s%s, %s%s." % [who, place, road, o.why, odds]


## Adds `text` after the notes already put at the top (build, sacrifice, ruler, mandates), ahead of the
## plan's other notes; the last ordinary note gives way when the list is full.
func _note_top(text: String) -> void:
	if _notes.has(text):
		return
	_notes.insert(mini(_head, _notes.size()), text)
	_head += 1
	if _notes.size() > MAX_NOTES:
		_notes.pop_back()


# --- M4: paths of ascension (design/M4_ASCENSION.md §8; #70) --------------------------------------

## The side of the fork we plan for: the one we swore, else the autoplay's forced side, else choose_branch
## for our seat (configure), or for the state's seed and our place in the state when not configured.
func _plan_branch() -> String:
	var sworn := AscensionRules.branch(_state, _fid)
	if not sworn.is_empty():
		return sworn
	if not _forced_branch.is_empty() and String(AscensionRules.branch_data(_forced_branch).get("faction", "")) == _fid:
		return _forced_branch
	var game_seed := _game_seed
	var seat := _seat
	if seat < 0:
		game_seed = _state.seed_value
		seat = 0
		for i in _state.factions.size():
			if _state.factions[i].id == _fid:
				seat = i
	return AIPaths.choose_branch(game_seed, seat, String(_preset.get("id", "")), _fid)


## This plan's unit numbers and front (paths only): every faction's roster and commander numbers with its
## mandates and path parts (RulerRules.unit_stats; both are public), and the forest share of our front for
## Rooted. Taken again after a sacrifice.
func _build_ctx() -> void:
	_threat_cache = {}
	_arrival = {}
	var stats := {}
	for f in _state.factions:
		var types: Array = f.unit_types.duplicate()
		if f.commander_type != null:
			types.append(f.commander_type)
		for ut in types:
			var st := RulerRules.unit_stats(_state, f.id, ut.id)
			if st.get("ok", false):
				stats[f.id + "|" + ut.id] = {"attack": int(st.attack), "defense": int(st.defense), "morale": int(st.morale), "hp": int(st.hp)}
	# Our front: the provinces we own next to one we don't, and those neighbours.
	var front := {}
	for p in _state.provinces:
		if p.owner != _fid:
			continue
		for n in _nbrs.get(p.id, []):
			var q := _state.find_province(n)
			if q != null and q.owner != _fid:
				front[p.id] = true
				front[n] = true
	var forest := 0
	for pid in front:
		if _state.find_province(pid).terrain == AscensionRules.FOREST:
			forest += 1
	var disciplined := {}
	var frenzy := {}
	var base_hit := {}
	var dread := {}
	for f in _state.factions:
		var fx := RulerRules.battle_effects(_state, f.id)
		disciplined[f.id] = fx.iron_discipline
		frenzy[f.id] = int(fx.wounded_attack)  # #94: Blood Frenzy, for every fighter below its maximum hp
		base_hit[f.id] = int(fx.base_hit)  # #131: Drilled Ranks
		dread[f.id] = RulerRules.dread_value(_state, f.id)  # #131: its ruler's Dread, while it stands
	_ctx = {"stats": stats, "front": front.size(), "forest": forest, "iron_discipline": disciplined, "frenzy": frenzy,
		"base_hit": base_hit, "dread": dread,
		"forest_share": float(forest) / float(front.size()) if not front.is_empty() else 0.0}
	if _state.magic:
		# M5-10: every faction's battle spells, for the worth of a mage (AIMagic.mage_pressure), and whether Shield of Law has
		# anything to cover where our garrison stands.
		_ctx["casts"] = AIMagic.cast_profiles(_state)
		_ctx["shield_ok"] = AIMagic.shield_ok(_state, _me.capital)


## A unit's attack, defense and morale for this plan: unit_stats' totals (mandates and path parts), or its type's
## for a type unit_stats doesn't know.
func _eff(u: Unit) -> Dictionary:
	var st: Dictionary = _ctx.get("stats", {}).get(u.owner + "|" + u.type.id, {})
	if st.is_empty():
		return {"attack": u.type.attack, "defense": u.type.defense, "morale": u.type.morale}
	return st


## A recruit of `ut` as a unit, for the recruit plan's guesses, at the hp the recruitment phase gives it (its
## maximum with every part, Veteran Levies included, less Blood Levy's share).
func _recruit_unit(ut: UnitType) -> Unit:
	var u := Unit.new(ut, _fid)
	if not _arrival.has(ut.id):
		_arrival[ut.id] = AscensionRules.arrival_hp(_state, _fid, ut, RulerRules.unit_max_hp(_state, u))
	u.current_hp = int(_arrival[ut.id])
	return u


## Enemy armies that could reach `pid` this turn: those next to it, and those two provinces off with a legal
## road move into it (King's Roads or Forest Stride, RulerRules.road_vias from their side).
func _threats_to(pid: String) -> Array:
	var near := _foes_next_to(pid)
	if _threat_cache.has(pid):
		return _threat_cache[pid].duplicate()
	var by_road := {}
	for e in _foes:
		if near.has(e) or _d(e.location, pid) != 2:
			continue
		if not by_road.has(e.owner):
			by_road[e.owner] = RulerRules.has_road_moves(_state, e.owner)
		if by_road[e.owner] and not RulerRules.road_vias(_state, e.owner, e.id, pid).is_empty():
			near.append(e)
	_threat_cache[pid] = near.duplicate()
	return near


## The gold a turn `p` would earn us (paths): its base income plus our path lines for it (the
## income_terrain of our researched nodes for its terrain; Tithe of Light's n more at the capital for one
## more province) and Forge Tithe's fort gold. Never below 0. The same numbers RulerRules.province_income_parts
## gives once we own it.
func _income_if_ours(p: Province) -> int:
	if p.owner == _fid:
		return int(RulerRules.province_income_parts(_state, p.id).total)
	var total := p.income
	for nid in AscensionRules.researched(_state, _fid):
		var fx := AscensionRules.node_effects(nid)
		total += int(fx.get("income_terrain", {}).get(p.terrain, 0))
		total += int(fx.get("tithe_per_province", 0))
	var fort := AscensionRules.mandate_value(_state, _fid, "fort_income", 0)
	if fort > 0 and p.has_fort:
		total += fort
	return maxi(0, total)


## Raiding Parties' one-off gold if our armies capture `p` (AscensionRules.capture_gold), else 0.
func _raid_gold(p: Province) -> float:
	return float(AscensionRules.capture_gold(_state, _fid, p).get("gold", 0))


## What capturing `p` is worth a turn (paths): our income from it, what its owner loses, and RAID_WEIGHT of
## the Raiding Parties windfall.
func _capture_worth(p: Province) -> float:
	var theirs := 0.0
	if not p.owner.is_empty() and p.owner != _fid:
		theirs = float(RulerRules.province_income_parts(_state, p.id).total)
	return float(_income_if_ours(p)) + theirs + RAID_WEIGHT * _raid_gold(p)


## The capture note in a game with paths: the gold a turn with our path lines, and Raiding Parties' gold.
func _capture_note(p: Province) -> String:
	var gold := _income_if_ours(p)
	var lines := ""
	if gold != p.income:
		lines = " (%d base, with %s)" % [p.income, _income_line_names(p)]
	var raid := AscensionRules.capture_gold(_state, _fid, p)
	var windfall := ""
	if int(raid.get("gold", 0)) > 0:
		windfall = " and %d gold at once (%s: %s)" % [int(raid.gold), AscensionRules.node_name(String(raid.node)),
			AscensionRules.times_text(int(raid.times))]
	return "Taking %s for %d gold per turn%s%s%s." % [p.name, gold, lines, windfall,
		"" if p.owner.is_empty() else " (and %s lose it)" % _faction_name(p.owner)]


## The names of our income lines that change what `p` would earn us: "Market Charters and Tithe of Light".
func _income_line_names(p: Province) -> String:
	var names := []
	for nid in AscensionRules.researched(_state, _fid):
		var fx := AscensionRules.node_effects(nid)
		if int(fx.get("income_terrain", {}).get(p.terrain, 0)) != 0 or int(fx.get("tithe_per_province", 0)) != 0:
			names.append(AscensionRules.part_name(nid))
	if p.has_fort and AscensionRules.mandate_value(_state, _fid, "fort_income", 0) > 0:
		names.append(RulerRules.mandate_name(RulerRules.FORGE_TITHE))
	return RulerRules._and_list(names) if not names.is_empty() else "our path"


## This turn's research (paths): the node to order ("" for no ResearchOrder), with the research notes.
## Only our own target is read.
func _plan_research() -> String:
	if not _paths:
		return ""
	var nid := AIPaths.order_for(_state, _fid, String(_preset.get("id", "")), _branch)
	_note_research(not nid.is_empty())
	if not nid.is_empty():
		_stats["research_orders"] = 1
	return nid


## Notes on research that are public by now (the turn report already named them): what we completed at the
## end of last turn, the Oath we swore (and that we picked the side by a roll), the transformation and what
## it brought. A new research order is mentioned without naming its node: the target stays secret.
func _note_research(ordering: bool) -> void:
	var last := _state.current_turn
	var lines := []
	if last > 0:
		for nid in AIPaths.done_on(_state, _fid, last):
			lines.append(_research_done_note(nid))
	if ordering:
		var secret := "what we research next stays secret until it is done"
		if lines.is_empty():
			lines.append("Choosing our next research along our path: %s." % secret)
		else:
			lines[lines.size() - 1] = String(lines.back()).trim_suffix(".") + "; %s." % secret
	for line in lines:
		_note_top(line)


## The note for a node we completed last turn.
func _research_done_note(nid: String) -> String:
	var kind := AscensionRules.node_kind(nid)
	if kind == PathData.OATH:
		var side := String(AscensionRules.node_data(nid).get("branch", ""))
		var other := AscensionRules.other_branch(_fid, side)
		var next := String(AscensionRules.branch_data(side).get("transformation", ""))
		var when := ""
		if AscensionRules.research_target(_state, _fid) == next:
			var n := AscensionRules.eta(AscensionRules.node_cost(next), AscensionRules.research_points(_state, _fid),
				int(AscensionRules.research_rate(_state, _fid).rate))
			when = " in about %d %s" % [n, "turn" if n == 1 else "turns"] if n > 0 else ""
		var odds := AIPaths.branch_odds(String(_preset.get("id", "")), _fid)
		var pct := int(odds.get(side, 0))
		var roll := "we picked our side of the fork by a roll"
		if pct > 0:
			roll += " (%s)" % ("even odds" if pct == 50 else "%d%% for this side" % pct)
		return "We swore %s last turn: we will become %s%s, and %s is closed to us; %s." % [
			AscensionRules.node_ref(nid), AscensionRules.branch_ref(side), when, AscensionRules.branch_ref(other), roll]
	if kind == PathData.TRANSFORMATION:
		var fx := AscensionRules.node_effects(nid)
		var parts := []
		var renames: Dictionary = fx.get("rename", {})
		for type_id in renames:
			parts.append("our %s are %s now" % [AscensionRules.base_unit_name(_fid, String(type_id)), String(renames[type_id])])
		var new_id := String(fx.get("new_unit", ""))
		if not new_id.is_empty():
			var ut := TurnResolver.recruitable_type(_me, new_id)
			parts.append("we can recruit %s at %s" % [ut.name if ut != null else AscensionRules.base_unit_name(_fid, new_id),
				_province_name(_me.capital)])
		var opened := String(fx.get("opens_mandate", ""))
		var mandates := ""
		if not opened.is_empty():
			mandates = " %s can now be bought by sacrifice" % RulerRules.mandate_name(opened)
			var gone := String(fx.get("forswears", ""))
			if not gone.is_empty():
				mandates += " and %s no longer can" % RulerRules.mandate_name(gone)
			mandates += "."
		return "We became %s last turn: %s.%s" % [AscensionRules.branch_ref(String(AscensionRules.node_data(nid).get("branch", ""))),
			RulerRules._and_list(parts), mandates]
	return "Our research finished last turn. %s" % AscensionRules.done_text(_state, _fid, nid)


## Why we recruit a unit with a path trait, in plain words with the rules' own numbers, or "".
func _path_recruit_reason(ut: UnitType, n: int) -> String:
	var what := "%s x%d" % [ut.name, n]
	var short := String(AutoBattleResolver.TRAIT_SHORT.get(ut.trait_id, ""))
	match ut.trait_id:
		AutoBattleResolver.WINGS:
			var cmds := 0
			for e in _foes:
				if e.commander != null:
					cmds += 1
			if cmds > 0:
				return "Recruiting %s for %s (Wings: %s): the enemy fields %d %s." % [what, "their wings" if n > 1 else "its wings",
					short, cmds, "commander" if cmds == 1 else "commanders"]
			return "Recruiting %s (Wings: %s, and it reaches any rank)." % [what, short]
		AutoBattleResolver.ROOTED:
			return "Recruiting %s (Rooted: %s): %d of the %d provinces on our front are forest." % [what, short,
				int(_ctx.get("forest", 0)), int(_ctx.get("front", 0))]
		AutoBattleResolver.IRON_HIDE:
			return "Recruiting %s (Iron Hide: %s), which blunts many small hits most." % [what, short]
		AutoBattleResolver.LIFEDRINKER:
			return "Recruiting %s (Lifedrinker: %s), so it lasts in a long fight." % [what, short]
	return ""


# --- #94: stand-offs ------------------------------------------------------------------------------

## The stand-off decision (#94), made once per plan before any army moves; the one place to extend it (the
## sieges AI, S-6 / #104, turns it into a siege). It sets _standoff (standoff_info: are we in one?) and, in one,
## _hunt (_choose_hunt: the enemy army to go after, or {}). The rest of the plan only reads those two:
##   _size_garrison     the garrison marches out against the hunted army instead of staying home (hunt)
##   _field_moves       the main army's objective is the hunted army; one next to it waits for the main army
##   _advance           with nothing to hunt and the road guarded: _siege_step, else _raid_step
##   _attack_armies     attacks at STANDOFF_WIN instead of LIKELY_WIN
##   _sally             the garrison sallies at STANDOFF_SALLY_WIN instead of SALLY_WIN
func _plan_standoff() -> void:
	_standoff = standoff_info(_state, _fid, _temperament)
	_hunt = {}
	if _state.sieges:
		_sieges.begin()  # M3c: the main army's fort target; a stand-off's "siege" is a real one
	if _standoff.is_empty():
		return
	_stats.standoff = 1
	_hunt = _choose_hunt()


## Whether `faction_id` has reached a stand-off in `state`, read from the state alone (no battle history,
## no saved AI state): every unit it fields (rulers left out) at today's recruit price, plus its treasury,
## worth STANDOFF_TURNS turns of its income or more. {"turns" (the pile in turns of income), "value" (its
## units' worth), "gold", "income", "units"}, or {} when it isn't one (or the faction is unknown). #184: the aggressive
## `temperament` reads it at AGGRESSIVE_STANDOFF of the pile.
static func standoff_info(state: GameState, faction_id: String, temperament: String = "normal") -> Dictionary:
	var f: Faction = state.find_faction(faction_id) if state != null else null
	if f == null:
		return {}
	var income := int(TurnResolver.income_of(state, faction_id).total)
	var prices := {}
	var value := 0
	var units := 0
	for a in state.armies:
		if a.owner != faction_id:
			continue
		var members: Array = a.units.duplicate()
		if a.commander != null:
			members.append(a.commander)
		for u in members:
			if not prices.has(u.type.id):
				prices[u.type.id] = maxi(0, RulerRules.recruit_price(state, faction_id, u.type))
			value += int(prices[u.type.id])
			units += 1
	var turns := float(value + maxi(0, f.gold)) / float(maxi(1, income))
	var need := SIEGE_STANDOFF_TURNS if state.sieges else STANDOFF_TURNS
	if temperament == "aggressive":
		need *= AGGRESSIVE_STANDOFF
	if turns < need:
		return {}
	return {"turns": turns, "value": value, "gold": f.gold, "income": income, "units": units}


## The enemy army a stand-off hunts, or {} (see STANDOFF_TURNS): enemy armies outside their capitals within
## MASS_REACH of our capital or of our strongest army, that our armies within MASS_REACH of them beat at
## STANDOFF_WIN or better by the rough guess, on their ground and with the enemy armies next to them joining
## in. The nearest to our capital first, then the strongest, then by province id. {"pid", "rate", "force", "power"}.
func _choose_hunt() -> Dictionary:
	var cap: String = _me.capital
	var groups := _free_groups()  # nothing has a job yet: every army but our ruler's
	var lead: String = groups[0].loc if not groups.is_empty() else ""
	var best := {}
	var seen := {}
	for e in _foes:
		var pid: String = e.location
		if seen.has(pid) or _is_enemy_capital(pid):
			continue
		seen[pid] = true
		if _d(pid, cap) > MASS_REACH and (lead.is_empty() or _d(pid, lead) > MASS_REACH):
			continue
		var force := _mine.filter(func(a): return _d(a.location, pid) <= MASS_REACH)
		if force.is_empty():
			continue
		var held := _foes_at(pid)
		# Capped like _attack_rate's sure win: the rough guess never promises more than that.
		var rate := minf(0.95, _rate_from_ratio(_ratio(force, held + _foes_next_to(pid), 1.0, _ground_bonus(pid))))
		if rate < STANDOFF_WIN:
			continue
		var power := _power_units(_units(held), _units(force))
		var better := best.is_empty() or _d(pid, cap) < _d(best.pid, cap)
		if not better and _d(pid, cap) == _d(best.pid, cap):
			better = power > float(best.power) or (power == float(best.power) and pid < String(best.pid))
		if better:
			best = {"pid": pid, "rate": rate, "force": force, "power": power}
	return best


## True when this plan hunts the strongest of `threat` (the enemy armies near our capital that would keep
## the garrison home), so the garrison may march out against it.
func _hunting_the_pin(threat: Array) -> bool:
	if _hunt.is_empty():
		return false
	var mine := _units(_mine)
	var by := {}
	for e in threat:
		by[e.location] = true
	var pin := ""
	var pin_power := -1.0
	var locs: Array = by.keys()
	locs.sort()
	for loc in locs:
		var p := _power_units(_units(_foes_at(loc)), mine)
		if p > pin_power:
			pin = loc
			pin_power = p
	return pin == String(_hunt.pid)


## The turn report's names for `armies` (TurnReportText.army_name, #55), in number order: "the Crown's 3rd",
## "the Clans' 5th and the Clans' 8th"; past NAMED_ARMIES, the first ones and how many more ("the Clans' 1st,
## the Clans' 3rd and 16 more armies").
func _army_names(armies: Array) -> String:
	var ids := TurnReportText.sort_ids(armies.map(func(a): return a.id))
	var names := []
	for id in ids.slice(0, NAMED_ARMIES if ids.size() > NAMED_ARMIES + 1 else ids.size()):
		names.append(TurnReportText.army_name(_state, String(id)))
	if ids.size() > names.size():
		names.append("%d more armies" % (ids.size() - names.size()))
	return RulerRules._and_list(names) if not names.is_empty() else "nobody"


## "52 units": the units and commanders of `armies`.
func _units_text(armies: Array) -> String:
	var n := _units(armies).size()
	return "%d %s" % [n, "unit" if n == 1 else "units"]


## A siege step in a stand-off with nothing to hunt: one step from `here` toward the enemy capital
## `objective` where `armies` are at least even (STANDOFF_SAFE), or "".
func _siege_step(here: String, objective: String, armies: Array) -> String:
	if _standoff.is_empty() or not _hunt.is_empty() or objective.is_empty() or not _is_enemy_capital(objective):
		return ""
	var d_here := _d(here, objective)
	var options := []
	for n in _nbrs[here]:
		if _d(n, objective) != d_here - 1 or not _foes_at(n).is_empty():
			continue
		var threat := _threats_to(n)
		var friends: Array = armies + _friends_ending_at(n, armies)
		if threat.is_empty() or _ratio(friends, threat, _ground_bonus(n), 1.0) >= STANDOFF_SAFE:
			options.append(n)
	if options.is_empty():
		return ""
	var step := _pick_step(options)
	_stats.sieges = 1
	_note_top("Breaking the stand-off: %s %s on to %s past stronger armies on the road, to camp next to %s until the odds of taking it are even." % [
		_army_names(armies), "pushes" if armies.size() == 1 else "push", _province_name(step), _province_name(objective)])
	return step


## A raid in a stand-off: from `here`, a safe step toward the nearest province of an enemy within MASS_REACH
## that no army holds and that `armies` could hold safely (ties: what it is worth to us, then id), or "".
func _raid_step(here: String, armies: Array) -> String:
	if _standoff.is_empty():
		return ""
	var best := ""
	var best_step := ""
	var best_d := MASS_REACH + 1
	var best_worth := -1.0
	for p in _sorted_provinces():
		if p.owner.is_empty() or p.owner == _fid or not _foes_at(p.id).is_empty():
			continue
		var d := _d(here, p.id)
		if d < 1 or d > MASS_REACH or d > best_d:
			continue
		if not _safe_at(armies, p.id):
			continue
		var step: String = p.id if d == 1 else _step_toward(here, p.id, armies)
		if step.is_empty():
			continue
		var worth: float = _capture_worth(p) if _paths else float(p.income) * 2.0
		if d < best_d or worth > best_worth + 0.0001:
			best = p.id
			best_step = step
			best_d = d
			best_worth = worth
	if best.is_empty():
		return ""
	_stats.raids = 1
	var target := _state.find_province(best)
	_note_top("Breaking the stand-off: %s %s for %s, which the %s left unguarded, to cut their income and draw their army out." % [
		_army_names(armies), "heads" if armies.size() == 1 else "head", target.name, _faction_name(target.owner)])
	return best_step


# --- forecasts ------------------------------------------------------------------------------------

## Forecast.battle_odds of `attacker` attacking `pid` with `ids` on `st`, cached within this plan.
## Returns {} when the budget does not allow the call (callers fall back to the rough guess).
func _odds(st: GameState, attacker: String, ids: Array, pid: String, essential: bool) -> Dictionary:
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	var fighters := 0
	var sig := []
	for id in sorted_ids:
		var a := st.find_army(str(id))
		if a != null:
			fighters += a.units.size() + (1 if a.commander != null else 0) + (1 if a.ruler != null else 0)
	for a in st.armies:
		if a.location == pid and a.owner != attacker:
			fighters += a.units.size() + (1 if a.commander != null else 0) + (1 if a.ruler != null else 0)
			sig.append(a.id)
	sig.sort()
	var key := "%s|%s|%s|%s" % [attacker, ",".join(sorted_ids), pid, ",".join(sig)]
	if _scratch_top != null and st == _scratch_top:
		key = "top|" + key  # M5-4: the same ids with more fighters in them
	if _cache.has(key):
		_stats.odds_cached += 1
		return _cache[key]
	var cost := ODDS_BASE + ODDS_PER_FIGHTER * fighters + ODDS_PER_FIGHTER_SQ * fighters * fighters
	var allowed: bool = _stats.odds_calls < MAX_ODDS_CALLS[_level] and _budget >= cost
	if essential and _budget + ESSENTIAL_OVERDRAFT >= cost:
		allowed = true
	if not allowed:
		_stats.odds_skipped += 1
		return {}
	_budget -= cost
	_stats.odds_calls += 1
	var t0 := Time.get_ticks_usec()
	var r := Forecast.battle_odds(st, attacker, sorted_ids, pid)
	_stats["odds_usec"] = int(_stats.get("odds_usec", 0)) + Time.get_ticks_usec() - t0  # reporting only
	_stats["odds_cost"] = float(_stats.get("odds_cost", 0.0)) + cost
	_stats["odds_fighters_max"] = maxi(int(_stats.get("odds_fighters_max", 0)), fighters)
	if not r.get("ok", false):
		r = {}
	_cache[key] = r
	return r


## A scratch copy of the state (made once per plan) where `placed` armies stand in `pid`, our other
## armies that really are in `pid` stand next door instead (they are not counted on to stay), and
## every other army is where it really is. The real state is never changed.
func _scratch_with(placed: Array, pid: String, top: bool = false) -> GameState:
	# M5-4: `top` copies the view with every sighting at the top of its range instead (AIFog.top_view), for the capital's
	# defence; the same armies and ids, so a battle is fought by the same names. Without fog there is only the state.
	var at_top: bool = top and _fog.top_state != null
	var scratch: GameState = _scratch_top if at_top else _scratch
	if scratch == null:
		scratch = (_fog.top_state if at_top else _state).deep_copy([])
		if scratch == null:
			return null
		if at_top:
			_scratch_top = scratch
		else:
			_scratch = scratch
	var ids := {}
	for a in placed:
		ids[a.id] = true
	var aside: String = _nbrs[pid][0] if not _nbrs.get(pid, []).is_empty() else pid
	for a in scratch.armies:
		var real := _state.find_army(a.id)
		if real == null:
			continue
		if ids.has(a.id):
			a.location = pid
		elif a.owner == _fid and real.location == pid:
			a.location = aside
		else:
			a.location = real.location
	return scratch


# --- rough strength guess -------------------------------------------------------------------------

## Rough fighting power of `units` against `foe_units` (Lanchester-style): the hp the side can lose
## before it breaks x the damage it deals per round. Only unit stats from the state go in. The damage
## per attack follows the shape of the published battle rules (RulesCodex: hit chance rises with
## attack over defense, damage is about half the attack minus a quarter of the defense) and the
## breaking point is the battle rules' own (#131): BREAK_BASE_PCT plus MORALE_PCT_PER_POINT for each
## point of the side's morale with its commander, Inspire and ruler, less the foe's Fury and Dread, and
## Iron Discipline's no-rout while a commander stands. Terrain, forts and most traits are left to
## Forecast.battle_odds, which decides every battle that matters.
func _power_units(units: Array, foe_units: Array) -> float:
	if units.is_empty():
		return 0.0
	var hp := 0.0
	var def_total := 0.0
	var foe_bears := 0
	var foe_dread := 0
	for u in foe_units:
		hp += u.current_hp
		def_total += u.current_hp * int(_eff(u).defense)
		if u.type.trait_id == AutoBattleResolver.FURY:
			foe_bears += 1
		if u.type.is_ruler:
			foe_dread = maxi(foe_dread, int(_ctx.get("dread", {}).get(u.owner, 0)))
	var foe_def := def_total / hp if hp > 0.0 else 0.0
	var fid: String = units[0].owner
	var base_hit := int(_ctx.get("base_hit", {}).get(fid, AutoBattleResolver.BASE_HIT))
	hp = 0.0
	var dmg := 0.0
	var morale := 0.0
	var regulars := 0
	var best := 0
	var led := false
	var inspire := false
	var ruler := false
	for u in units:
		var st := _eff(u)
		hp += u.current_hp
		dmg += _pressure(int(st.attack) + _wounded_attack(u), foe_def, base_hit)
		if u.type.is_ruler:
			ruler = true
			best = maxi(best, int(st.morale))
		elif u.type.is_commander:
			led = true
			inspire = inspire or u.type.trait_id == AutoBattleResolver.INSPIRE
			best = maxi(best, int(st.morale))
		else:
			morale += int(st.morale)
			regulars += 1
	# #131: the morale the battle rules give a side (AutoBattleResolver._morale): its commander's, Inspire's and its
	# ruler's, less the foe's Fury and Dread. They decide when a side breaks, and the rough guess used to leave them out.
	var m := morale / regulars if regulars > 0 else float(best)
	if led:
		m += AutoBattleResolver.COMMANDER_MORALE
	if inspire:
		m += AutoBattleResolver.INSPIRE_MORALE
	if ruler:
		m += RulerData.RULER_MORALE
	m -= mini(AutoBattleResolver.FURY_MAX, AutoBattleResolver.FURY_MORALE * foe_bears) + foe_dread
	var hold := clampf(AutoBattleResolver.BREAK_BASE_PCT + AutoBattleResolver.MORALE_PCT_PER_POINT * m,
		AutoBattleResolver.MIN_BREAK_PCT, AutoBattleResolver.MAX_BREAK_PCT) / 100.0
	if led and bool(_ctx.get("iron_discipline", {}).get(fid, false)):
		hold = AutoBattleResolver.MAX_BREAK_PCT / 100.0  # Iron Discipline: no rout while a commander stands
	return hp * hold * dmg


## The attack a unit gets for being below its maximum hp now (paths, #94): Berserk's BERSERK_ATTACK and its
## faction's Blood Frenzy. Every Blood Levy recruit arrives wounded, so a Blood Pact army fights with them on.
func _wounded_attack(u: Unit) -> int:
	var st: Dictionary = _ctx.get("stats", {}).get(u.owner + "|" + u.type.id, {})
	if u.current_hp >= int(st.get("hp", u.type.hp)):
		return 0
	var bonus := int(_ctx.get("frenzy", {}).get(u.owner, 0))
	if u.type.trait_id == AutoBattleResolver.BERSERK:
		bonus += AutoBattleResolver.BERSERK_ATTACK
	return bonus


## Rough expected damage of one attack with `attack` against `foe_def` defense, with `base_hit` (Drilled Ranks).
static func _pressure(attack: int, foe_def: float, base_hit: int = AutoBattleResolver.BASE_HIT) -> float:
	var atk := float(attack)
	var hit := clampf(base_hit / 100.0 + 0.04 * (atk - foe_def), 0.3, 0.9)
	return hit * maxf(1.0, ceilf(atk * 0.5) - floorf(foe_def * 0.25))


static func _avg_defense(units: Array) -> float:
	var hp := 0.0
	var total := 0.0
	for u in units:
		hp += u.current_hp
		total += u.current_hp * u.type.defense
	return total / hp if hp > 0.0 else 0.0


func _ratio_units(ours: Array, theirs: Array, our_bonus: float, their_bonus: float) -> float:
	var them := _power_units(theirs, ours) * their_bonus
	if them <= 0.0:
		return 99.0
	return _power_units(ours, theirs) * our_bonus / them


func _ratio(ours: Array, theirs: Array, our_bonus: float, their_bonus: float) -> float:
	return _ratio_units(_units(ours), _units(theirs), our_bonus, their_bonus)


func _army_power(a: Army) -> float:
	return _power_units(_members(a), _units(_foes))


func _ground_bonus(pid: String) -> float:
	if _state.sieges:
		return _sieges.ground_bonus(pid)  # M3c: a fort's walls, which only a storm has to face
	var p := _state.find_province(pid)
	if p == null:
		return 1.0
	return HOLD_BONUS * (FORT_BONUS if p.has_fort else 1.0)


## Win chance from a power ratio, for when the forecast budget is spent.
static func _rate_from_ratio(r: float) -> float:
	var r2 := r * r
	return r2 / (1.0 + r2)


static func _label_for(rate: float) -> String:
	if rate >= LIKELY_WIN:
		return "likely win"
	if rate <= 1.0 - LIKELY_WIN:
		return "likely loss"
	return "close"


# --- lookups --------------------------------------------------------------------------------------

func _d(a: String, b: String) -> int:
	return int(_dist.get(a, {}).get(b, 999))


## The fighters of `a` for the rough guess: its units and commander, plus an enemy ruler (our own ruler
## is left out, so the guess errs on the safe side whether or not battles count rulers yet).
func _members(a: Army) -> Array:
	var out: Array = a.units.duplicate()
	if a.commander != null:
		out.append(a.commander)
	if a.ruler != null and a.owner != _fid:
		out.append(a.ruler)
	return out


func _units(armies: Array) -> Array:
	var out := []
	for a in armies:
		out.append_array(_members(a))
	return out


func _mine_at(pid: String) -> Array:
	return _mine.filter(func(a): return a.location == pid)


func _foes_at(pid: String) -> Array:
	return _foes.filter(func(a): return a.location == pid)


## Enemy armies that could move into `pid` this turn (they stand next to it).
func _foes_next_to(pid: String) -> Array:
	var near: Array = _nbrs.get(pid, [])
	return _foes.filter(func(a): return near.has(a.location))


## Our armies without a job yet that stand next to `pid`, sorted by id.
func _free_next_to(pid: String) -> Array:
	var near: Array = _nbrs.get(pid, [])
	return _mine.filter(func(a): return not _busy.has(a.id) and near.has(a.location))


## Our other armies that will be in `pid` after this turn's moves planned so far (holding there or
## moving in), excluding `exclude`.
func _friends_ending_at(pid: String, exclude: Array) -> Array:
	var out := []
	for a in _mine:
		if exclude.has(a):
			continue
		var dest: String = _moves.get(a.id, a.location)
		if dest == pid and (_busy.has(a.id) or a.location == pid):
			out.append(a)
	return out


## Our armies that will stand in `pid` after the moves planned so far.
func _armies_ending_at(pid: String) -> Array:
	return _mine.filter(func(a): return str(_moves.get(a.id, a.location)) == pid)


## Our free armies grouped by province: [{"loc", "armies", "power"}], strongest first.
func _free_groups() -> Array:
	var by_loc := {}
	for a in _mine:
		if _busy.has(a.id):
			continue
		if not by_loc.has(a.location):
			by_loc[a.location] = []
		by_loc[a.location].append(a)
	var foe_units := _units(_foes)
	var locs: Array = by_loc.keys()
	locs.sort()
	var groups := []
	for loc in locs:
		groups.append({"loc": loc, "armies": by_loc[loc], "power": _power_units(_units(by_loc[loc]), foe_units)})
	groups.sort_custom(func(x, y): return x.power > y.power or (x.power == y.power and x.loc < y.loc))
	return groups


func _is_enemy_capital(pid: String) -> bool:
	for f in _state.factions:
		if f.id != _fid and f.capital == pid:
			return true
	return false


func _sorted_factions() -> Array:
	var out: Array = _state.factions.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func _sorted_provinces() -> Array:
	var out: Array = _state.provinces.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


# --- plain-language notes -------------------------------------------------------------------------

func _note(text: String) -> void:
	if _notes.size() < MAX_NOTES and not _notes.has(text):
		_notes.append(text)


func _province_name(pid: String) -> String:
	var p := _state.find_province(pid)
	return p.name if p != null else "an unknown place"


func _faction_name(fid: String) -> String:
	var f := _state.find_faction(fid)
	return f.faction_name if f != null else "an unknown faction"


## "Westwatch" or "Westwatch and Highcrag": where these armies stand, by name, sorted.
func _places_text(armies: Array) -> String:
	var names := []
	for a in armies:
		var n := _province_name(a.location)
		if not names.has(n):
			names.append(n)
	names.sort()
	return " and ".join(names)


## "1 army" / "3 armies" for an Array of armies or a count.
static func _count_text(what) -> String:
	var n: int = what.size() if what is Array else int(what)
	return "%d %s" % [n, "army" if n == 1 else "armies"]


## ", even if the enemy army next to it joins in" when an attack's odds count possible reinforcements.
static func _joiners_text(odds: Dictionary) -> String:
	var n := int(odds.get("helpers", 0))
	if n == 0:
		return ""
	return ", even if the enemy %s next to it %s in" % ["army" if n == 1 else "armies", "joins" if n == 1 else "join"]


static func _odds_words(rate: float, label: String = "") -> String:
	var l := label if not label.is_empty() else _label_for(rate)
	return "%s, %d%%" % [l, roundi(rate * 100.0)]
