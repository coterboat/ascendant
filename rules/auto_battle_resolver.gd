class_name AutoBattleResolver
extends BattleResolver
## The real battle rules (#4). Pure and deterministic: every roll comes from the SeededRNG passed in,
## sides go in sorted faction id order, armies in sorted id order, units in army order, commanders
## last. Player-facing statement of these rules: RulesCodex "battle_*" and "trait_*" entries.
##
## A battle is fought in rounds, at most ROUND_CAP. Each round every standing fighter (unit or
## commander) attacks once, all at the same time (damage lands at the end of the round):
##   target  a random standing enemy it can reach (_targets). Units without Volley form the front
##           rank. Volley units (Crossbowmen) form the second rank: the front rank shields them while
##           at least as many front-rank units stand as second-rank ones, and attackers with Skirmish
##           (Fangthrowers) can always reach them. Commanders stand behind everyone and can only be
##           targeted once no unit stands in front of them.
##   hit     chance = BASE_HIT + HIT_PER_POINT per point of attack above the target's defense,
##           clamped to MIN_HIT..MAX_HIT percent. One roll of 1-100 per attack.
##   damage  ceil(attack / 2) - floor(target defense / 4), at least MIN_DAMAGE.
## Terrain helps only the defender (the faction that held the province): TERRAIN bonuses, plus
## FORT_DEFENSE in a province with a fort. Border battles and meetings where everyone arrived this
## turn have no defender, so nobody gets terrain.
## Morale: a side's morale = average morale of its units at the start (rounded down; a lone
## commander uses its own), +COMMANDER_MORALE while its commander stands, + trait effects (Inspire,
## Fury). At the end of each round a side breaks (routs) once it has lost at least
## BREAK_BASE_PCT + morale x MORALE_PCT_PER_POINT percent of its starting hp (clamped to
## MIN_BREAK_PCT..MAX_BREAK_PCT).
## A routed side leaves the battle and loses. The TurnResolver then destroys every army on a losing
## side, routed or not (including attackers still standing at the round cap): no retreats in M1.
## The battle ends when only one side is left in the field. If every remaining side drops out in the
## same round, the one with the largest share of its starting hp left keeps the field (then the
## defender, then a seeded roll). Round cap: after ROUND_CAP rounds the defender holds if it is still
## standing; with no defender, the side with the largest share of its starting hp left wins (ties: a
## seeded roll).
##
## Traits (data/factions.gd gives each unit type one), one effect each. The trait constants below are
## the single source of truth for their numbers: the rules read them, and every description players
## see is built from them (TRAIT_TEXT, which is data/factions.gd's trait_desc and the start of each
## RulesCodex trait_* entry, and TRAIT_SHORT):
##   Shield Wall  +SHIELD_WALL_DEFENSE defense while another friendly fighter stands.
##   Volley       fights from the second rank, shielded while its front rank is at least as big.
##   Charge       +CHARGE_DAMAGE damage on hits in round 1 (CHARGE_DAMAGE_FOREST in a forest).
##   Inspire      +INSPIRE_MORALE to its side's morale while it stands.
##   Berserk      +BERSERK_ATTACK attack while below full hp.
##   Skirmish     can attack the second rank as well as the front rank (see target above).
##   Fury         each standing War Bear gives enemy sides -FURY_MORALE morale (at most -FURY_MAX).
##   Pack Leader  +PACK_LEADER_ATTACK attack to every friendly unit while it stands.
##
## The report's "why" names the 1-3 factors worth the most hp to a side. Every factor is measured as
## what it added over doing without it, in expected damage (or hp kept from a rout), so they compare:
## a trait counts only its own effect (Charge: the charge bonus on its hits), and a commander counts
## the damage it dealt beyond what the same gold in its side's ordinary units would have dealt
## (_line_baseline). Its morale and its trait (Inspire, Pack Leader) are factors of their own.
##
## Rulers and mandates (M2-2, #30; design/M2_RULER.md §1.6, §2.3, §7.4). Only in a game with rulers
## (GameState.with_rulers): without a ruler on the field and without mandates, a battle is fought, and
## reported, exactly as above. The numbers come from data (RulerData, MandateData) through RulerRules
## (unit_stats, unit_max_hp, battle_effects, dread_value), the same functions every tooltip reads:
##   the ruler    fights beside its side's armies with the stats its kept power gives it. King Corvane,
##                the Great Thornmane and the Ninth Fang stand in the front rank; the Ever-Regent in the
##                second rank, with the Volley units and under the same shield rule (Skirmish reaches
##                him). +RULER_MORALE morale to its side while it stands. Not a unit: Royal Armories,
##                Veteran Levies and Pack Leader skip it. When it falls in a battle its side wins, its
##                army no longer holds it (army.ruler = null) and TurnResolver records the death.
##   Dread        the Great Thornmane: every enemy side in a province battle (not a border battle) has
##                its ability value less morale while the avatar stands. Adds to Fury.
##   Iron Discipline   a side that would break does not while one of its commanders stands, except at
##                     the end of the last round (ROUND_CAP), where the usual check applies (M2-8).
##   Drilled Ranks     the side's base hit chance is the mandate's base_hit (70) instead of BASE_HIT.
##   Veteran Levies    regular units have more maximum hp (RulerRules.unit_max_hp).
##   Royal Armories    regular units have more attack and defense (RulerRules.unit_stats), as named parts.
##   Blood Frenzy      every fighter below its maximum hp has more attack, a named part like Berserk.
##   Feast of Victory  after a battle the side wins, its standing fighters heal to full (_apply_losses).
## Each of these is a "why" factor measured like the rest: the ruler counts the damage it dealt (it costs
## no gold, so all of it is what it added), its morale is a factor of its own (morale_ruler), the stat
## mandates count what their parts added (mandate_*), Veteran Levies the damage its extra hp absorbed,
## Iron Discipline the hp it kept from a rout, and Dread is measured like Fury (ability_dread).
##
## The battle event log (M3-1, #56; design/M3_BATTLES.md §2). fight(..., record = true) also writes a
## complete log of the battle while it fights, from the same values it uses: every attack with its
## target roll, hit roll, chance, damage and their parts, every wound, death, morale check and rout,
## round by round, and the RNG state before and after. Schema, checks and helpers: BattleLog
## (rules/battle_log.gd). Recording is passive: it draws nothing from the RNG, reorders nothing and
## changes no state, so the report, the winner, the armies and the RNG state are the same with it on or
## off. resolve_battle() records (TurnResolver keeps the log in the event's numbers.log); estimate() and
## resolve() by default don't.

const ROUND_CAP := 8
const BASE_HIT := 60
const HIT_PER_POINT := 4
const MIN_HIT := 30
const MAX_HIT := 90
const MIN_DAMAGE := 1
const BREAK_BASE_PCT := 20
const MORALE_PCT_PER_POINT := 5
const MIN_BREAK_PCT := 25
const MAX_BREAK_PCT := 95
const COMMANDER_MORALE := 2
const TERRAIN := {
	"plains": {"defense": 0, "attack": 0},
	"forest": {"defense": 2, "attack": 0},
	"hills": {"defense": 1, "attack": 1},
}
const FORT_DEFENSE := 2
const SHIELD_WALL_DEFENSE := 2
const CHARGE_DAMAGE := 4
const CHARGE_DAMAGE_FOREST := 3
const INSPIRE_MORALE := 2
const BERSERK_ATTACK := 3
const FURY_MORALE := 2
const FURY_MAX := 3
const PACK_LEADER_ATTACK := 1

const SHIELD_WALL := "Shield Wall"
const VOLLEY := "Volley"
const CHARGE := "Charge"
const INSPIRE := "Inspire"
const BERSERK := "Berserk"
const SKIRMISH := "Skirmish"
const FURY := "Fury"
const PACK_LEADER := "Pack Leader"
## What each trait does, built from the constants the rules use: a unit type's trait description
## (data/factions.gd trait_desc, shown in unit tooltips) and the first sentence of its codex entry.
const TRAIT_TEXT := {
	SHIELD_WALL: "Gets +%d defense while any other fighter on its side still stands." % SHIELD_WALL_DEFENSE,
	VOLLEY: "Shoots from the second rank, behind its side's units without Volley. While at least as many of those stand as units with Volley, they shield it: only enemies with Skirmish can attack it. Commanders stand further back, so they don't count.",
	CHARGE: "Deals +%d damage with every hit in the first round of a battle" % CHARGE_DAMAGE + " (+%d in a forest)." % CHARGE_DAMAGE_FOREST,
	INSPIRE: "While it stands, its side gets +%d morale" % INSPIRE_MORALE + ", on top of the +%d any standing commander gives." % COMMANDER_MORALE,
	BERSERK: "Gets +%d attack while below full hit points." % BERSERK_ATTACK,
	SKIRMISH: "Can attack the enemy's second rank (its units with Volley) as well as its front rank, even while the front rank shields them.",
	FURY: "While it stands, every enemy side gets -%d morale" % FURY_MORALE + " (at most -%d in all, however many roar)." % FURY_MAX,
	PACK_LEADER: "While it stands, every unit on its side gets +%d attack." % PACK_LEADER_ATTACK,
}
## One-line summaries of TRAIT_TEXT, for odds reasons and compact lists.
const TRAIT_SHORT := {
	SHIELD_WALL: "+%d defense in a group" % SHIELD_WALL_DEFENSE,
	VOLLEY: "shoots from the second rank",
	CHARGE: "+%d damage in the first round" % CHARGE_DAMAGE,
	INSPIRE: "+%d morale" % INSPIRE_MORALE,
	BERSERK: "+%d attack when wounded" % BERSERK_ATTACK,
	SKIRMISH: "reaches the second rank",
	FURY: "-%d enemy morale" % FURY_MORALE,
	PACK_LEADER: "+%d attack to every unit" % PACK_LEADER_ATTACK,
}

## M2-2: the ruler's morale part and its "why" factor id, Dread's morale part, and the prefix of every
## mandate's part and factor id ("mandate_royal_armories"), which is also its RulesCodex entry.
const RULER := "ruler"
const DREAD := "Dread"
const MANDATE_PREFIX := "mandate_"
const RULER_RANK_WORDS := {"front": "in the front rank", "second": "from the second rank"}

## Odds estimate: the real battle is fought ODDS_SAMPLES times on fixed internal seeds.
const ODDS_SAMPLES := 24
const ODDS_SEED := 4040
const LIKELY_WIN := 0.65
const LIKELY_LOSS := 0.35

## Below this many hp of impact a factor is too small to be called a reason.
const MIN_IMPACT := 0.5


# --- entry points ---------------------------------------------------------------------------------

## The issue's shape: `attacker` against `defender` (each an Army or an Array of one faction's
## Armies) in `province`. The defender gets the terrain. Pure: the armies are not changed.
## Returns {"result": {"winner", "strengths", "tie_break", "roll", "why", "report"}, "report": {...}},
## plus "log" (BattleLog schema) when `record` is true.
## `state` is optional and only used for player-facing names.
static func resolve(attacker, defender, province: Province, rng: SeededRNG, state: GameState = null, record := false) -> Dictionary:
	var att: Array = attacker if attacker is Array else [attacker]
	var dfn: Array = defender if defender is Array else [defender]
	var dfid: String = dfn[0].owner
	var sides := [{"faction": att[0].owner, "armies": att}, {"faction": dfid, "armies": dfn}]
	sides.sort_custom(func(a, b): return a.faction < b.faction)
	var ctx := {"kind": "province", "defender": dfid, "province": province,
		"province_ids": [province.id] if province else [], "state": state}
	var r := fight(sides, ctx, rng, record)
	var out := {"result": r.result, "report": r.result.report}
	if record:
		out["log"] = r.log
	return out


## BattleResolver interface, called by TurnResolver for every battle (any number of sides).
## Applies the winner's losses to its armies (dead units removed, wounds kept, a fallen ruler leaves
## its army, Feast of Victory heals); the TurnResolver removes the losing armies. The battle dictionary
## may carry "state" for names, terrain, rulers and mandates. With Feast of Victory, the report gains
## "feast": {"faction", "name", "fighters", "healed"} (TurnResolver's aftermath line says so).
## M3-1: the result also carries "log", the battle's event log (BattleLog), with a "feast" event when
## Feast of Victory healed anyone. The battle dictionary may carry "max_events" (tests: a lowered cap).
func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
	var state = battle.get("state")
	var kind: String = battle.get("kind", "province")
	var pids: Array = battle.get("provinces", [])
	var province: Province = null
	if state is GameState and kind == "province" and not pids.is_empty():
		province = state.find_province(pids[0])
	var ctx := {"kind": kind, "defender": battle.get("defender", ""), "province": province,
		"province_ids": pids, "state": state if state is GameState else null}
	if battle.has("max_events"):
		ctx["max_events"] = battle.max_events
	var r := fight(battle.sides, ctx, rng, true)
	var healed := _feast_healed(r.sides, r.result.winner)  # read before _apply_losses heals them
	var feast := _apply_losses(r.sides, r.result.winner)
	if not feast.is_empty():
		r.result.report["feast"] = feast
		var wi := -1
		for i in r.sides.size():
			if r.sides[i].faction == r.result.winner:
				wi = i
		_log_push(r.log, int(ctx.get("max_events", BattleLog.MAX_EVENTS)), {"t": "feast", "side": wi, "healed": healed})
	r.result["log"] = r.log
	return r.result


## Pre-battle odds for `perspective` (a faction id among the sides): the real battle fought on
## ODDS_SAMPLES fixed seeds. Armies are not changed. Returns {"win_rate", "wins", "samples",
## "label": "likely win" | "close" | "likely loss", "reasons": [plain-language strings], "text"}.
static func estimate(sides: Array, ctx: Dictionary, perspective: String) -> Dictionary:
	var wins := 0
	var scores := {}  # factor key -> summed impact from the perspective's point of view
	var briefs := {}
	for i in ODDS_SAMPLES:
		var r := fight(sides, ctx, SeededRNG.new(odds_seed(i)))
		if r.result.winner == perspective:
			wins += 1
		for f in r.result.report.all_factors:
			if f.id == "luck":
				continue
			var key: String = "%s|%s" % [f.id, f.faction]
			var signed: float = f.impact if f.faction == perspective else -f.impact
			scores[key] = scores.get(key, 0.0) + signed
			briefs[key] = f.brief
	var rate := float(wins) / ODDS_SAMPLES
	var label := "close"
	if rate >= LIKELY_WIN:
		label = "likely win"
	elif rate <= LIKELY_LOSS:
		label = "likely loss"
	var keys: Array = scores.keys()
	keys.sort()
	var pos := keys.filter(func(k): return scores[k] > MIN_IMPACT)
	var neg := keys.filter(func(k): return scores[k] < -MIN_IMPACT)
	pos.sort_custom(func(a, b): return scores[a] > scores[b])
	neg.sort_custom(func(a, b): return scores[a] < scores[b])
	var reasons := []
	if label == "likely win":
		for k in pos.slice(0, 2):
			reasons.append(briefs[k])
	elif label == "likely loss":
		for k in neg.slice(0, 2):
			reasons.append(briefs[k])
	else:
		if not pos.is_empty():
			reasons.append(briefs[pos[0]])
		if not neg.is_empty():
			reasons.append(briefs[neg[0]])
	var name := _faction_name(perspective, ctx.get("state"))
	var text := "%s: %s won %d of %d test battles fought with these armies (%d%%)." % [
		_cap(label), name, wins, ODDS_SAMPLES, roundi(rate * 100)]
	if not reasons.is_empty():
		text += " Main reasons: %s." % "; ".join(reasons)
	text += " Each real battle still has its own rolls."
	return {"win_rate": rate, "wins": wins, "samples": ODDS_SAMPLES, "label": label, "reasons": reasons, "text": text}


## The fixed seed of odds sample `i` (exposed so tests can check estimate() against resolve()).
static func odds_seed(i: int) -> int:
	return ODDS_SEED + i * 7919


## `base` is the attacker's base hit chance: BASE_HIT, or Drilled Ranks' (RulerRules.battle_effects).
static func hit_chance(attack: int, defense: int, base: int = BASE_HIT) -> int:
	return clampi(base + HIT_PER_POINT * (attack - defense), MIN_HIT, MAX_HIT)


static func damage(attack: int, defense: int) -> int:
	return maxi(MIN_DAMAGE, ceili(attack * 0.5) - floori(defense * 0.25))


static func break_pct(morale: int) -> int:
	return clampi(BREAK_BASE_PCT + morale * MORALE_PCT_PER_POINT, MIN_BREAK_PCT, MAX_BREAK_PCT)


static func codex_id_for_trait(trait_id: String) -> String:
	return "trait_" + trait_id.to_lower().replace(" ", "_")


# --- the battle -----------------------------------------------------------------------------------

## Fights one battle without changing any army. `sides` = [{"faction", "armies"}] sorted by faction
## id; `ctx` = {"kind", "defender", "province" (Province or null), "province_ids", "state"}, and
## optionally "max_events" (the log's cap, BattleLog.MAX_EVENTS by default; tests lower it).
## Returns {"result": BattleResolver result with "report", "sides": internal side records}, plus "log"
## (the battle event log, BattleLog's schema) when `record` is true. Recording is passive (M3-1).
static func fight(sides_in: Array, ctx: Dictionary, rng: SeededRNG, record := false) -> Dictionary:
	var state = ctx.get("state")
	var kind: String = ctx.get("kind", "province")
	var province = ctx.get("province")
	var terrain := ""
	var fort := false
	if province != null and kind == "province":
		terrain = province.terrain
		fort = province.has_fort
	var defender_fid: String = ctx.get("defender", "")
	var sides := _build_sides(sides_in, defender_fid, state, kind)
	var env := {"terrain": terrain, "fort": fort, "kind": kind}
	# M3-1: the recorder, {"log", "cap"}, or null when not recording.
	var rec = null
	if record:
		rec = {"log": _log_header(sides, sides_in, ctx, env, rng, state), "cap": int(ctx.get("max_events", BattleLog.MAX_EVENTS))}

	var rounds := []
	var round_no := 0
	while round_no < ROUND_CAP and _standing(sides).size() > 1:
		round_no += 1
		rounds.append(_fight_round(sides, round_no, env, rng, rec))
	var impact_before := _impacts(sides) if rec != null else []
	_count_extra_hp(sides)

	var standing := _standing(sides)
	var winner_idx := -1
	var tie_break := "none"
	var roll := 0
	var tied := 0
	var end := ""
	if standing.size() == 1:
		winner_idx = standing[0]
		end = "rout"
		for s in sides:
			if s.destroyed and s.out_round == round_no:
				end = "destroyed"
		for s in sides:
			if s.routed and s.out_round == round_no:
				end = "rout"
	else:
		var pool := []
		if standing.is_empty():
			end = "mutual"
			for i in sides.size():
				if sides[i].out_round == round_no:
					pool.append(i)
		else:
			end = "round_cap"
			pool = standing
		var pick := _pick_best(sides, pool, defender_fid, end == "round_cap", rng)
		winner_idx = pick.index
		tie_break = pick.tie_break
		roll = pick.roll
		tied = int(pick.get("tied", 0))
		if end == "mutual":
			sides[winner_idx].routed = false
			sides[winner_idx].held_field = true

	var report := _report(sides, ctx, env, rounds, winner_idx, end, state)
	var strengths := {}
	for s in sides:
		strengths[s.faction] = s.strength
	var result := {"winner": sides[winner_idx].faction, "strengths": strengths, "tie_break": tie_break,
		"roll": roll, "why": report.why, "report": report}
	if rec == null:
		return {"result": result, "sides": sides}
	_log_push(rec.log, rec.cap, {"t": "end", "rounds": round_no, "winner": winner_idx, "how": end, "tie_break": tie_break,
		"roll": roll, "tied": tied, "impact": _impact_deltas(sides, impact_before)})
	rec.log.rng["after"] = Serial.int64_to_str(rng.get_state())
	return {"result": result, "sides": sides, "log": rec.log}


static func _build_sides(sides_in: Array, defender_fid: String, state, kind: String = "province") -> Array:
	var sides := []
	for i in sides_in.size():
		var sd: Dictionary = sides_in[i]
		var armies: Array = sd.armies.duplicate()
		armies.sort_custom(func(a, b): return a.id < b.id)
		# M2-2: what the side's mandates do in battle (nothing in a game without rulers).
		var effects := RulerRules.battle_effects(state if state is GameState else null, sd.faction)
		var mods_by_type := {}  # unit type id -> its part mods, from RulerRules.unit_stats
		var fighters := []
		var labels := []
		var morale_sum := 0
		var regulars := 0
		var strength := 0
		var line_attacks := []
		var line_cost := 0
		var ruler_info := {}
		for a in armies:
			labels.append(_army_label(a, state))
			for u in a.units:
				var mods := _unit_mods(mods_by_type, sd.faction, u.type, state)
				var max_hp: int = RulerRules.unit_max_hp(state, u) if state is GameState else u.type.hp
				fighters.append(_fighter(i, a, u, false, false, mods, max_hp))
				morale_sum += u.type.morale
				regulars += 1
				line_attacks.append(u.type.attack + _mods_total(mods.attack))
				line_cost += u.type.cost
			if a.commander:
				fighters.append(_fighter(i, a, a.commander, true))
			if a.ruler:
				# The ruler fights beside its side's armies: not a unit, so no unit mods (§1.3).
				var rf := _fighter(i, a, a.ruler, false, true)
				fighters.append(rf)
				ruler_info = _ruler_info(state, sd.faction, rf, kind)
			strength += StubBattleResolver.army_strength(a)
		if regulars == 0:
			# A commander fighting alone is compared with its faction's roster instead.
			for ut in _roster_types(sd.faction, state):
				line_attacks.append(ut.attack + _mods_total(_unit_mods(mods_by_type, sd.faction, ut, state).attack))
				line_cost += ut.cost
		var base_morale := 0
		if regulars > 0:
			base_morale = floori(float(morale_sum) / regulars)
		else:
			for f in fighters:
				base_morale = maxi(base_morale, f.type.morale)
		var hp := 0
		var power_attack := 0
		for f in fighters:
			hp += f.hp
			power_attack += f.type.attack
		sides.append({"faction": sd.faction, "name": _faction_name(sd.faction, state), "fighters": fighters,
			"armies": labels, "roster": _roster(armies), "is_defender": sd.faction == defender_fid, "base_morale": base_morale,
			"hp_start": hp, "count_start": fighters.size(), "regulars": regulars, "strength": strength, "power": hp * power_attack,
			"line_attacks": line_attacks, "line_cost": float(line_cost) / maxi(1, line_attacks.size()),
			"routed": false, "destroyed": false, "held_field": false, "out_round": 0, "rout_info": {},
			"attacks": 0, "hits": 0, "chance_sum": 0, "chance_min": 100, "chance_max": 0,
			"dealt": 0, "expected": 0.0, "luck_by": {}, "impact": {}, "triggers": {}, "trait_units": {},
			"volley_expected": 0.0, "cmd_expected": 0.0, "skirmish_reach": 0.0, "skirmish_targets": {}, "lost": [], "morale_log": [],
			# M2-2: the side's mandates and ruler.
			"mandates": effects.mandates, "base_hit": int(effects.base_hit), "base_hit_key": String(effects.base_hit_key),
			"frenzy": int(effects.wounded_attack), "frenzy_key": String(effects.wounded_attack_key),
			"iron": bool(effects.iron_discipline), "feast": bool(effects.feast_of_victory), "iron_held": [],
			"ruler_info": ruler_info, "dread": int(ruler_info.get("dread", 0)), "ruler_expected": 0.0, "ruler_dealt": 0,
			"ruler_fell": 0})
		for f in fighters:
			if not f.trait.is_empty():
				sides[i].trait_units[f.trait] = f.name
	return sides


## The attack, defense and maximum hp parts the side's mandates give a regular unit of type `ut`, from
## RulerRules.unit_stats (Royal Armories, Veteran Levies): {"attack": [{"key", "value"}], "defense": [...],
## "hp": [...]}, keyed "mandate_<id>". Empty for commanders, rulers, types outside the faction's roster
## and games without mandates. Cached per type in `cache`.
static func _unit_mods(cache: Dictionary, fid: String, ut: UnitType, state) -> Dictionary:
	if cache.has(ut.id):
		return cache[ut.id]
	var out := {"attack": [], "defense": [], "hp": []}
	if state is GameState and not ut.is_commander and not ut.is_ruler and not RulerRules.mandates(state, fid).is_empty():
		var us := RulerRules.unit_stats(state, fid, ut.id)
		if us.get("ok", false):
			for stat in out:
				for m in us.mods[stat]:
					out[stat].append({"key": MANDATE_PREFIX + String(m.mandate), "value": int(m.value)})
	cache[ut.id] = out
	return out


static func _mods_total(mods: Array) -> int:
	var total := 0
	for m in mods:
		total += int(m.value)
	return total


## The ruler on a side, for the report and the "why": {"id", "name", "rank" ("front" | "second"),
## "kept_power", "max_hp", "attack", "defense", "hp_start", and "dread" (its Dread in this battle: the
## morale every enemy side loses while it stands, only in a province battle; 0 otherwise)}.
static func _ruler_info(state, fid: String, rf: Dictionary, kind: String) -> Dictionary:
	var ut: UnitType = rf.type
	var f: Faction = state.find_faction(fid) if state is GameState else null
	var dread := 0
	if kind == "province" and state is GameState:
		dread = RulerRules.dread_value(state, fid)
	return {"id": ut.id, "name": ut.name, "rank": RulerRules.battle_rank(ut.id), "kept_power": f.kept_power if f != null else 0,
		"max_hp": int(rf.max), "attack": ut.attack, "defense": ut.defense, "hp_start": int(rf.hp), "dread": dread}


## Who fought on a side, for the report: unit types with counts in first-seen order (armies by id,
## units in army order), then the commanders. Ids for the viewer, names and text for players:
##   {"units": [{"id", "name", "count"}], "commanders": [{"id", "name"}],
##    "text": "Spearmen (2), Crossbowmen, led by Knight Captain" | "Warchief alone"}
## With a ruler on the side (M2-2), also "ruler": {"id", "name"}, and the text ends ", with King
## Corvane I" ("King Corvane I alone" when the ruler fought by itself).
static func _roster(armies: Array) -> Dictionary:
	var units := []
	var index := {}
	var commanders := []
	var ruler := {}
	for a in armies:
		for u in a.units:
			if not index.has(u.type.id):
				index[u.type.id] = units.size()
				units.append({"id": u.type.id, "name": u.type.name, "count": 0})
			units[index[u.type.id]].count += 1
		if a.commander:
			commanders.append({"id": a.commander.type.id, "name": a.commander.type.name})
		if a.ruler:
			ruler = {"id": a.ruler.type.id, "name": a.ruler.type.name}
	var parts := []
	for e in units:
		parts.append(e.name if e.count == 1 else "%s (%d)" % [e.name, e.count])
	var leaders := {}
	var leader_order := []
	for c in commanders:
		if not leaders.has(c.name):
			leaders[c.name] = 0
			leader_order.append(c.name)
		leaders[c.name] += 1
	var led := []
	for n in leader_order:
		led.append(n if leaders[n] == 1 else "%s (%d)" % [n, leaders[n]])
	var text := ", ".join(parts)
	if not led.is_empty():
		text = ("%s alone" % " and ".join(led)) if parts.is_empty() else "%s, led by %s" % [text, " and ".join(led)]
	if ruler.is_empty():
		return {"units": units, "commanders": commanders, "text": text}
	if text.is_empty():
		text = "%s alone" % ruler.name
	else:
		text = "%s, with %s" % [text.trim_suffix(" alone"), ruler.name] if not text.ends_with(" alone") \
			else "%s and %s" % [text.trim_suffix(" alone"), ruler.name]
	return {"units": units, "commanders": commanders, "ruler": ruler, "text": text}


## The unit types `fid` can recruit (not its commander), from the game state when there is one.
static func _roster_types(fid: String, state) -> Array:
	if state is GameState:
		var f: Faction = state.find_faction(fid)
		if f != null:
			return f.unit_types
	for f in FactionData.FACTIONS:
		if f.id == fid:
			return f.unit_types.map(func(u): return UnitType.from_dict(u))
	return []


## One fighter. Tier 0 is the front rank, 1 the second rank (Volley units, and a ruler whose battle rank
## is "second"), 2 the commanders behind everyone. `mods` are its mandate parts (_unit_mods) and
## `max_hp` its maximum hp with them (RulerRules.unit_max_hp; the type's hp when not given).
static func _fighter(side_idx: int, army: Army, unit: Unit, is_cmd: bool, is_ruler: bool = false, mods: Dictionary = {},
		max_hp: int = -1) -> Dictionary:
	var t: String = unit.type.trait_id
	var tier := 0
	if is_cmd:
		tier = 2
	elif is_ruler:
		tier = 1 if RulerRules.battle_rank(unit.type.id) == "second" else 0
	elif t == VOLLEY:
		tier = 1
	return {"side": side_idx, "army": army.id, "army_ref": army, "unit": unit, "type": unit.type, "name": unit.type.name,
		"trait": t, "cmd": is_cmd, "tier": tier, "hp": unit.current_hp, "hp0": unit.current_hp,
		"max": max_hp if max_hp > 0 else unit.type.hp, "alive": unit.current_hp > 0, "pending": 0,
		"ruler": is_ruler, "mods": mods if not mods.is_empty() else {"attack": [], "defense": [], "hp": []}, "taken": 0}


static func _standing(sides: Array) -> Array:
	var out := []
	for i in sides.size():
		if not sides[i].routed and not sides[i].destroyed:
			out.append(i)
	return out


## One round. `rec` is fight()'s recorder ({"log", "cap"}) when the battle is being recorded (M3-1),
## otherwise null; recording only reads what the round computes.
static func _fight_round(sides: Array, round_no: int, env: Dictionary, rng: SeededRNG, rec = null) -> Dictionary:
	var standing := _standing(sides)
	var dealt := {}
	var hits := {}
	var attacks := {}
	var charge := {}
	var berserk := {}
	for si in standing:
		dealt[si] = 0
		hits[si] = 0
		attacks[si] = 0
	# M3-1 recording: who hit whom, expected damage per side, impact at the round's start, and each side's
	# reachable tiers (no fighter falls before the round ends, so they hold for every attack of the round).
	var hit_by := {}
	var expected_by := {}
	var impact_before := []
	var reach := {}
	if rec != null:
		impact_before = _impacts(sides)
		reach = _log_round(rec, sides, standing, round_no)
	for si in standing:
		var side: Dictionary = sides[si]
		for f in side.fighters:
			if not f.alive:
				continue
			var pool := _targets(sides, si, standing, f)
			if pool.is_empty():
				continue
			var pick := rng.randi_range(0, pool.size() - 1)
			var t: Dictionary = pool[pick]
			var tside: Dictionary = sides[t.side]
			var atk := _attack(f, side, env)
			var dfn := _defense(t, tside, f, env)
			var bonus := 0
			if f.trait == CHARGE and round_no == 1:
				bonus = CHARGE_DAMAGE_FOREST if env.terrain == "forest" else CHARGE_DAMAGE
			var base: int = side.base_hit  # BASE_HIT, or Drilled Ranks'
			var chance := hit_chance(atk.value, dfn.value, base)
			var dmg := damage(atk.value, dfn.value) + bonus
			var expected := chance / 100.0 * dmg
			# What each modifier was worth on this attack, in expected damage.
			for p in atk.parts:
				var a2: int = atk.value - atk.parts[p]
				var gain: float = expected - hit_chance(a2, dfn.value, base) / 100.0 * (damage(a2, dfn.value) + bonus)
				_add_impact(side, p, gain)
			for p in dfn.parts:
				var d2: int = dfn.value - dfn.parts[p]
				var saved: float = hit_chance(atk.value, d2, base) / 100.0 * (damage(atk.value, d2) + bonus) - expected
				_add_impact(tside, p, saved)
			if base != BASE_HIT:
				# Drilled Ranks: what the side's higher base hit chance added to this attack.
				var plain_chance := hit_chance(atk.value, dfn.value)
				if plain_chance != chance:
					_add_impact(side, side.base_hit_key, (chance - plain_chance) / 100.0 * dmg)
					side.triggers[side.base_hit_key] = side.triggers.get(side.base_hit_key, 0) + 1
			if f.ruler:
				# The ruler costs no gold, so all the damage it deals is what it added (§7.4).
				side.ruler_expected += expected
				_add_impact(side, RULER, expected)
			if f.trait == SKIRMISH and t.tier == 1 and _screened(tside, t):
				# Only Skirmish reached this target past its front rank. Counted in full: every hit on a
				# shielded second-rank fighter takes away about as much of the damage it would have gone on
				# to deal from safety (Volley's own factor counts half of what it dealt while shielded).
				side.skirmish_reach += expected
				side.skirmish_targets[t.name] = int(side.skirmish_targets.get(t.name, 0)) + 1
				_add_impact(side, SKIRMISH, expected)
			if bonus > 0:
				_add_impact(side, CHARGE, chance / 100.0 * bonus)
			if f.cmd:
				side.cmd_expected += expected
				_add_impact(side, "commander", expected - _line_baseline(side, f, dfn.value, atk.parts.get("terrain", 0)))
			if f.tier == 1 and not f.ruler and _screened(side, f):
				side.volley_expected += expected
				_add_impact(side, VOLLEY, expected * 0.5)
			if atk.parts.has(BERSERK) and not berserk.has(si):
				berserk[si] = f.name
			var roll := rng.randi_range(1, 100)
			var hit := roll <= chance
			if rec != null:
				_log_attack(rec, round_no, f, t, reach, pool.size(), pick, chance, roll, hit, dmg, bonus, base, atk, dfn, expected)
				expected_by[si] = float(expected_by.get(si, 0.0)) + expected
				if hit:
					if not hit_by.has(t.id):
						hit_by[t.id] = []
					hit_by[t.id].append(f.id)
			side.attacks += 1
			side.chance_sum += chance
			side.chance_min = mini(side.chance_min, chance)
			side.chance_max = maxi(side.chance_max, chance)
			side.expected += expected
			# Luck of this attack in damage (what it did minus what an average roll would), by kind of
			# attack, so the report can say where a side's luck came from.
			var luck_key: String = f.name + ("|charge" if bonus > 0 else "")
			side.luck_by[luck_key] = side.luck_by.get(luck_key, 0.0) + (dmg if hit else 0) - expected
			attacks[si] += 1
			if hit:
				side.hits += 1
				side.dealt += dmg
				hits[si] += 1
				dealt[si] += dmg
				t.pending += dmg
				if bonus > 0:
					charge[si] = charge.get(si, 0) + bonus
				if f.ruler:
					side.ruler_dealt += dmg

	var highlights := []
	for si in standing:
		if charge.has(si):
			highlights.append("%s %s charged home for %d extra damage." % [_poss(sides[si].name), sides[si].trait_units[CHARGE], charge[si]])
		if berserk.has(si):
			highlights.append("%s wounded %s went berserk (+%d attack)." % [_poss(sides[si].name), berserk[si], BERSERK_ATTACK])
	for si in standing:
		for f in sides[si].fighters:
			if f.alive and f.pending > 0:
				var before: int = f.hp
				f.hp = maxi(0, f.hp - f.pending)
				f.taken += before - f.hp
				if rec != null:
					_log_push(rec.log, rec.cap, {"t": "wound", "n": round_no, "f": f.id, "from": before, "to": f.hp, "by": hit_by.get(f.id, [])})
					if f.hp == 0:
						_log_push(rec.log, rec.cap, {"t": "death", "n": round_no, "f": f.id, "by": hit_by.get(f.id, []).duplicate()})
				if f.hp == 0:
					f.alive = false
					sides[si].lost.append(f.name)
					highlights.append("%s %s fell." % [_poss(sides[si].name), _bare(f.name)])
					if f.ruler:
						sides[si].ruler_fell = round_no
			f.pending = 0

	# Morale is checked for every side before any of them leaves, so the order of sides never matters.
	var checks := {}
	for si in standing:
		var side: Dictionary = sides[si]
		var hp_now := _hp(side)
		if hp_now == 0:
			continue
		var m := _morale(sides, si, standing)
		var lost_pct := roundi(100.0 * (side.hp_start - hp_now) / maxi(1, side.hp_start))
		var entry := {"round": round_no, "morale": m.value, "parts": m.parts, "break_pct": break_pct(m.value),
			"lost_pct": lost_pct, "hp": hp_now}
		side.morale_log.append(entry)
		checks[si] = entry
	var outcomes := {}  # M3-1 recording: side index -> {"result", "held_by" (fighter id), "iron_last_round"}
	for si in standing:
		var side: Dictionary = sides[si]
		if _hp(side) == 0:
			side.destroyed = true
			side.out_round = round_no
			highlights.append("%s had no one left standing." % side.name)
		elif checks[si].lost_pct >= checks[si].break_pct:
			# Iron Discipline holds through every round but the last (M2-8, #36): at the end of round
			# ROUND_CAP the usual check applies, so a line it holds past its break point can't win by
			# stalling the attackers until the round cap.
			var holder := _iron_holder(side) if round_no < ROUND_CAP else ""
			var iron_last_round: bool = side.iron and holder.is_empty() and round_no >= ROUND_CAP and not _iron_holder(side).is_empty()
			if iron_last_round:
				highlights.append("%s holds a line only until the last round." % RulerRules.mandate_name(RulerRules.IRON_DISCIPLINE))
			if not holder.is_empty():
				# Iron Discipline: the side would break, but one of its commanders still stands (§2.3).
				checks[si]["held_by"] = holder
				side.iron_held.append(checks[si])
				if side.iron_held.size() == 1:
					highlights.append("%s would have broken after losing %d%% of its strength (morale %d holds only to %d%%), but %s held it while its %s stood." % [
						side.name, checks[si].lost_pct, checks[si].morale, checks[si].break_pct,
						RulerRules.mandate_name(RulerRules.IRON_DISCIPLINE), holder])
				if rec != null:
					outcomes[si] = {"result": "held", "held_by": _iron_holder_id(side), "iron_last_round": false}
				continue
			side.routed = true
			side.out_round = round_no
			side.rout_info = checks[si]
			highlights.append("%s broke and fled after losing %d%% of its strength (morale %d holds only to %d%%)." % [
				side.name, checks[si].lost_pct, checks[si].morale, checks[si].break_pct])
			if rec != null:
				outcomes[si] = {"result": "breaks", "held_by": -1, "iron_last_round": iron_last_round}
		elif rec != null:
			outcomes[si] = {"result": "holds", "held_by": -1, "iron_last_round": false}
	if rec != null:
		_log_round_end(rec, sides, standing, round_no, checks, outcomes, attacks, hits, dealt, expected_by, impact_before)

	var parts := []
	for si in standing:
		parts.append("%s dealt %d damage (%d of %d hits)" % [sides[si].name, dealt[si], hits[si], attacks[si]])
	var hp_after := {}
	for s in sides:
		hp_after[s.faction] = _hp(s)
	return {"round": round_no, "dealt": dealt.duplicate(), "highlights": highlights, "hp": hp_after,
		"line": "Round %d: %s.%s" % [round_no, ", ".join(parts), "" if highlights.is_empty() else " " + " ".join(highlights)]}


## Standing enemies fighter `attacker` of side `si` can reach. On each enemy side: its front rank
## (units without Volley), plus its second rank (Volley units) when the front rank no longer shields it
## (fewer front-rank units than second-rank ones stand) or when `attacker` has Skirmish; the second rank
## alone once the front rank has fallen; its commanders once no unit stands. Fighters keep their side's
## order, so a seed always picks the same target.
static func _targets(sides: Array, si: int, standing: Array, attacker: Dictionary = {}) -> Array:
	var reach: bool = attacker.get("trait", "") == SKIRMISH
	var pool := []
	for oi in standing:
		if oi == si:
			continue
		var tiers := _reachable_tiers(_tier_counts(sides[oi]), reach)
		for f in sides[oi].fighters:
			if f.alive and tiers.has(f.tier):
				pool.append(f)
	return pool


## The target rule's ranks (M3-1: factored out of _targets with no change in behaviour, so the battle
## log's "reach" is the rule itself): the tiers of a side with `counts` standing fighters per tier
## ([front, second, back]) that an enemy can attack. The front rank; the second rank too when it
## outnumbers the front rank or the attacker has Skirmish (`skirmish`); the second rank alone once the
## front rank has fallen; the commanders once no unit stands.
static func _reachable_tiers(counts: Array, skirmish: bool) -> Array:
	if counts[0] == 0:
		return [1] if counts[1] > 0 else [2]
	if counts[1] > 0 and (skirmish or counts[1] > counts[0]):
		return [0, 1]
	return [0]


## Standing fighters of `side` per tier: [front, second, back].
static func _tier_counts(side: Dictionary) -> Array:
	var counts := [0, 0, 0]
	for f in side.fighters:
		if f.alive:
			counts[f.tier] += 1
	return counts


## What the same gold as commander `f` would have dealt with this attack if it had been spent on its
## side's ordinary units, on average (the yardstick for the commander's "why" factor): the commander's
## cost in average units of its side (or of its faction's roster when it fights alone), each attacking
## a target with `defense` (with the side's terrain attack bonus `terrain_attack`), times the share of
## those units that would still be standing, taken as the share of the side's units still standing
## (or, for a lone commander, its own share of hit points left).
static func _line_baseline(side: Dictionary, f: Dictionary, defense: int, terrain_attack: int) -> float:
	var attacks: Array = side.line_attacks
	if attacks.is_empty() or side.line_cost <= 0.0:
		return 0.0
	var per_unit := 0.0
	for a in attacks:
		per_unit += hit_chance(a + terrain_attack, defense, side.base_hit) / 100.0 * damage(a + terrain_attack, defense)
	per_unit /= attacks.size()
	var standing := 0.0
	if side.regulars > 0:
		var alive := 0
		for o in side.fighters:
			if o.alive and not o.cmd:
				alive += 1
		standing = float(alive) / side.regulars
	else:
		standing = float(f.hp) / maxi(1, f.hp0)
	return per_unit * f.type.cost / side.line_cost * standing


## True when enemies without Skirmish can't reach fighter `f` because the ranks in front of it shield
## it: a second-rank (Volley) fighter while at least as many front-rank units as second-rank ones stand,
## a commander while any unit stands.
static func _screened(side: Dictionary, f: Dictionary) -> bool:
	var counts := [0, 0, 0]
	for o in side.fighters:
		if o.alive:
			counts[o.tier] += 1
	if f.tier == 1:
		return counts[0] > 0 and counts[0] >= counts[1]
	if f.tier == 2:
		return counts[0] + counts[1] > 0
	return false


static func _attack(f: Dictionary, side: Dictionary, env: Dictionary) -> Dictionary:
	var parts := {}
	if side.is_defender:
		var ta: int = TERRAIN.get(env.terrain, {}).get("attack", 0)
		if ta > 0:
			parts["terrain"] = ta
	if f.trait == BERSERK and f.hp < f.max:
		parts[BERSERK] = BERSERK_ATTACK
	var frenzy: int = side.get("frenzy", 0)
	if frenzy > 0 and f.hp < f.max:
		parts[side.frenzy_key] = frenzy  # Blood Frenzy: every fighter, the ruler included
	if not f.cmd and not f.get("ruler", false):
		for o in side.fighters:
			if o.alive and o.cmd and o.trait == PACK_LEADER:
				parts[PACK_LEADER] = PACK_LEADER_ATTACK
	for m in f.get("mods", {}).get("attack", []):
		parts[m.key] = int(parts.get(m.key, 0)) + int(m.value)  # Royal Armories
	var value: int = f.type.attack
	for p in parts:
		value += parts[p]
		side.triggers[p] = side.triggers.get(p, 0) + 1
	return {"value": value, "parts": parts}


static func _defense(t: Dictionary, tside: Dictionary, _attacker: Dictionary, env: Dictionary) -> Dictionary:
	var parts := {}
	if tside.is_defender:
		var td: int = TERRAIN.get(env.terrain, {}).get("defense", 0)
		if td > 0:
			parts["terrain"] = td
		if env.fort:
			parts["fort"] = FORT_DEFENSE
	if t.trait == SHIELD_WALL:
		for o in tside.fighters:
			if o.alive and o != t:
				parts[SHIELD_WALL] = SHIELD_WALL_DEFENSE
				break
	for m in t.get("mods", {}).get("defense", []):
		parts[m.key] = int(parts.get(m.key, 0)) + int(m.value)  # Royal Armories
	var value: int = t.type.defense
	for p in parts:
		value += parts[p]
		tside.triggers[p] = tside.triggers.get(p, 0) + 1
	return {"value": value, "parts": parts}


static func _morale(sides: Array, si: int, standing: Array) -> Dictionary:
	var side: Dictionary = sides[si]
	var parts := {}
	for f in side.fighters:
		if f.alive and f.cmd:
			parts["commander"] = COMMANDER_MORALE
			if f.trait == INSPIRE:
				parts[INSPIRE] = INSPIRE_MORALE
	var bears := 0
	for oi in standing:
		if oi == si:
			continue
		for f in sides[oi].fighters:
			if f.alive and f.trait == FURY:
				bears += 1
	if bears > 0:
		parts[FURY] = -mini(FURY_MAX, FURY_MORALE * bears)
	# M2-2: the side's own ruler while it stands, and an enemy avatar's Dread while it stands.
	for f in side.fighters:
		if f.alive and f.get("ruler", false):
			parts[RULER] = RulerData.RULER_MORALE
	var dread := 0
	for oi in standing:
		if oi != si and int(sides[oi].get("dread", 0)) > 0 and _ruler_standing(sides[oi]):
			dread += int(sides[oi].dread)
	if dread > 0:
		parts[DREAD] = -dread
	var value: int = side.base_morale
	for p in parts:
		value += parts[p]
	return {"value": value, "parts": parts}


static func _ruler_standing(side: Dictionary) -> bool:
	for f in side.fighters:
		if f.get("ruler", false) and f.alive:
			return true
	return false


## Iron Discipline (§2.3): the name of a commander of `side` still standing when the side has the
## mandate, so it does not break this round; "" otherwise (rulers don't count).
static func _iron_holder(side: Dictionary) -> String:
	if not side.iron:
		return ""
	for f in side.fighters:
		if f.alive and f.cmd:
			return f.name
	return ""


## The log id of the commander _iron_holder names (the same fighter), or -1. Recording only (M3-1).
static func _iron_holder_id(side: Dictionary) -> int:
	if not side.iron:
		return -1
	for f in side.fighters:
		if f.alive and f.cmd:
			return int(f.id)
	return -1


## Veteran Levies (§7.4): the damage each regular unit's extra maximum hp absorbed (up to the bonus, for
## a unit that took that much), added to the side's impact under the mandate's key once the battle ends.
static func _count_extra_hp(sides: Array) -> void:
	for s in sides:
		var absorbed := {}
		var keys := []
		for f in s.fighters:
			var left: int = f.taken
			for m in f.mods.hp:
				var a := mini(int(m.value), left)
				left -= a
				if not absorbed.has(m.key):
					absorbed[m.key] = 0
					keys.append(m.key)
				absorbed[m.key] += a
		for k in keys:
			if absorbed[k] > 0:
				_add_impact(s, k, float(absorbed[k]))


static func _hp(side: Dictionary) -> int:
	var total := 0
	for f in side.fighters:
		total += f.hp
	return total


static func _share(side: Dictionary) -> float:
	return float(_hp(side)) / maxi(1, side.hp_start)


static func _pick_best(sides: Array, pool: Array, defender_fid: String, defender_holds: bool, rng: SeededRNG) -> Dictionary:
	if defender_holds:
		for i in pool:
			if sides[i].faction == defender_fid:
				return {"index": i, "tie_break": "defender", "roll": 0}
	var best := -1.0
	var tied := []
	for i in pool:
		var sh := _share(sides[i])
		if sh > best + 0.000001:
			best = sh
			tied = [i]
		elif absf(sh - best) <= 0.000001:
			tied.append(i)
	if tied.size() == 1:
		return {"index": tied[0], "tie_break": "none", "roll": 0}
	for i in tied:
		if sides[i].faction == defender_fid:
			return {"index": i, "tie_break": "defender", "roll": 0}
	var r := rng.randi_range(0, tied.size() - 1)
	return {"index": tied[r], "tie_break": "roll", "roll": r, "tied": tied.size()}  # "tied": for the log (M3-1)


static func _add_impact(side: Dictionary, key: String, amount: float) -> void:
	side.impact[key] = side.impact.get(key, 0.0) + amount


## The winner's losses on its armies: fallen units and commanders leave them, a fallen ruler leaves its
## army (army.ruler = null; TurnResolver removes the empty army and records the death, M2-3's contract),
## and survivors keep their wounds, unless the side has Feast of Victory: then every fighter still
## standing heals to its maximum hp. Returns {"faction", "name", "fighters" (standing), "healed" (hp
## in all)} for a Feast that healed anyone, otherwise {}.
static func _apply_losses(sides: Array, winner: String) -> Dictionary:
	var feast := {}
	for s in sides:
		if s.faction != winner:
			continue
		var standing := 0
		var healed := 0
		for f in s.fighters:
			var army: Army = f.army_ref
			if f.alive:
				var hp: int = f.hp
				if s.feast:
					standing += 1
					healed += maxi(0, f.max - hp)
					hp = maxi(hp, f.max)
				f.unit.current_hp = hp
			elif f.cmd:
				army.commander = null
			elif f.ruler:
				army.ruler = null
			else:
				army.units.erase(f.unit)
		if s.feast and healed > 0:
			feast = {"faction": s.faction, "name": s.name, "fighters": standing, "healed": healed}
	return feast


# --- the battle event log (M3-1, design/M3_BATTLES.md §2.2-§2.3) ----------------------------------
# These only read the battle's values and append to the log: nothing here draws from the RNG or writes
# to a side or fighter, except the log id ("id") _log_header gives each fighter record.

const TIER_WORDS := ["front", "second", "back"]


## The log's header (top level, sides and fighters; events come as the battle is fought). Numbers each
## fighter record with its log id, in the resolver's fighter order.
static func _log_header(sides: Array, sides_in: Array, ctx: Dictionary, env: Dictionary, rng: SeededRNG, state) -> Dictionary:
	var fighters := []
	var side_logs := []
	var standing := _standing(sides)
	for si in sides.size():
		var s: Dictionary = sides[si]
		var ids := []
		for f in s.fighters:
			f["id"] = fighters.size()
			ids.append(f.id)
			fighters.append(_log_fighter(f, s))
		var armies: Array = sides_in[si].armies.duplicate()
		armies.sort_custom(func(a, b): return a.id < b.id)  # as _build_sides orders them (and their labels)
		var army_logs := []
		for ai in armies.size():
			army_logs.append({"id": armies[ai].id, "label": s.armies[ai]})
		var m := _morale(sides, si, standing)
		side_logs.append({"index": si, "faction": s.faction, "name": s.name, "defender": s.is_defender, "armies": army_logs,
			"fighters": ids, "hp_start": s.hp_start, "base_morale": s.base_morale,
			"start_morale": {"morale": m.value, "parts": m.parts, "break_pct": break_pct(m.value)},
			"base_hit": s.base_hit, "frenzy": s.frenzy, "iron": s.iron, "feast": s.feast, "dread": s.dread,
			"mandates": s.mandates.duplicate()})
	return {"v": BattleLog.VERSION, "id": "", "turn": 0, "index": 0, "kind": env.kind,
		"provinces": ctx.get("province_ids", []).duplicate(), "terrain": env.terrain, "fort": env.fort,
		"defender": ctx.get("defender", ""), "round_cap": ROUND_CAP,
		"rng": {"seed": Serial.int64_to_str(rng.get_seed()), "before": Serial.int64_to_str(rng.get_state()), "after": ""},
		"sides": side_logs, "fighters": fighters, "events": [], "truncated": false}


static func _log_fighter(f: Dictionary, s: Dictionary) -> Dictionary:
	var hp_parts := {}
	for m in f.mods.hp:
		hp_parts[m.key] = int(hp_parts.get(m.key, 0)) + int(m.value)
	var ruler := {}
	if f.ruler and not s.ruler_info.is_empty():
		ruler = {"id": s.ruler_info.id, "kept_power": s.ruler_info.kept_power, "rank": s.ruler_info.rank, "dread": s.ruler_info.dread}
	var ut: UnitType = f.type
	return {"id": f.id, "side": f.side, "army": f.army, "role": "commander" if f.cmd else ("ruler" if f.ruler else "unit"),
		"type": ut.id, "name": f.name, "trait": f.trait, "tier": f.tier, "hp": f.hp, "max_hp": f.max, "hp_parts": hp_parts,
		"attack": ut.attack, "defense": ut.defense, "morale": ut.morale, "cost": ut.cost, "ruler": ruler}


## Appends `ev` unless the log has reached `cap` events: then recording stops and the log is marked
## "truncated" (the battle itself goes on as usual).
static func _log_push(battle_log: Dictionary, cap: int, ev: Dictionary) -> void:
	BattleLog.append(battle_log, ev, cap)


## The round event, with each standing side's reachable tiers from the target rule. Returns them by side
## index ({"tiers", "skirmish_tiers"}) for the round's attack events.
static func _log_round(rec: Dictionary, sides: Array, standing: Array, round_no: int) -> Dictionary:
	var by_side := {}
	var reach := []
	for si in standing:
		var counts := _tier_counts(sides[si])
		var r := {"side": si, "tiers": _reachable_tiers(counts, false), "skirmish_tiers": _reachable_tiers(counts, true)}
		by_side[si] = r
		reach.append(r)
	_log_push(rec.log, rec.cap, {"t": "round", "n": round_no, "reach": reach})
	return by_side


static func _log_attack(rec: Dictionary, round_no: int, f: Dictionary, t: Dictionary, reach: Dictionary, pool: int, pick: int,
		chance: int, roll: int, hit: bool, dmg: int, bonus: int, base: int, atk: Dictionary, dfn: Dictionary, expected: float) -> void:
	var how: String = TIER_WORDS[t.tier]
	if not reach[t.side].tiers.has(t.tier):
		how = "skirmish"  # only Skirmish could reach it
	_log_push(rec.log, rec.cap, {"t": "attack", "n": round_no, "by": f.id, "to": t.id, "pool": pool, "pick": pick,
		"chance": chance, "roll": roll, "hit": hit, "damage": dmg, "bonus": {CHARGE: bonus} if bonus > 0 else {},
		"base_hit": base, "attack": {"value": atk.value, "base": f.type.attack, "parts": atk.parts},
		"defense": {"value": dfn.value, "base": t.type.defense, "parts": dfn.parts}, "reach": how,
		"screened": not reach[f.side].tiers.has(f.tier), "expected": _dec(expected, 10.0)})


## The round's morale checks, routs and destructions, and its round_end totals.
static func _log_round_end(rec: Dictionary, sides: Array, standing: Array, round_no: int, checks: Dictionary, outcomes: Dictionary,
		attacks: Dictionary, hits: Dictionary, dealt: Dictionary, expected_by: Dictionary, impact_before: Array) -> void:
	for si in standing:
		if not checks.has(si):
			continue
		var c: Dictionary = checks[si]
		var o: Dictionary = outcomes[si]
		_log_push(rec.log, rec.cap, {"t": "morale", "n": round_no, "side": si, "morale": c.morale, "base": sides[si].base_morale,
			"parts": c.parts.duplicate(), "break_pct": c.break_pct, "lost_pct": c.lost_pct, "hp": c.hp, "result": o.result,
			"held_by": o.held_by, "decisive": _decisive(c, o.result), "iron_last_round": o.iron_last_round})
	for si in standing:
		var s: Dictionary = sides[si]
		if s.destroyed:
			_log_push(rec.log, rec.cap, {"t": "destroyed", "n": round_no, "side": si})
		elif s.routed:
			var fled := []
			for f in s.fighters:
				if f.alive:
					fled.append(f.id)
			_log_push(rec.log, rec.cap, {"t": "rout", "n": round_no, "side": si, "fled": fled})
	var hp := []
	var att := []
	var hit := []
	var dlt := []
	var expd := []
	for si in sides.size():
		hp.append(_hp(sides[si]))
		att.append(int(attacks.get(si, 0)))
		hit.append(int(hits.get(si, 0)))
		dlt.append(int(dealt.get(si, 0)))
		expd.append(_dec(float(expected_by.get(si, 0.0)), 100.0))
	_log_push(rec.log, rec.cap, {"t": "round_end", "n": round_no, "hp": hp, "attacks": att, "hits": hit, "dealt": dlt,
		"expected": expd, "impact": _impact_deltas(sides, impact_before)})


## The parts that decided a morale check (§2.2): for "holds", each positive part without which the side
## would have broken; for "breaks", each negative part without which it would have held; [] for "held".
static func _decisive(check: Dictionary, result: String) -> Array:
	var out := []
	if result == "held":
		return out
	for p in check.parts:
		var v: int = check.parts[p]
		if result == "holds" and v > 0 and check.lost_pct >= break_pct(check.morale - v):
			out.append(p)
		elif result == "breaks" and v < 0 and check.lost_pct < break_pct(check.morale - v):
			out.append(p)
	return out


## A copy of every side's impact accumulator.
static func _impacts(sides: Array) -> Array:
	var out := []
	for s in sides:
		out.append(s.impact.duplicate())
	return out


## Per side, what each impact key gained since `before` (_impacts), to 2 decimals, zeros left out.
static func _impact_deltas(sides: Array, before: Array) -> Array:
	var out := []
	for si in sides.size():
		var d := {}
		var was: Dictionary = before[si]
		for k in sides[si].impact:
			var v := _dec(float(sides[si].impact[k]) - float(was.get(k, 0.0)), 100.0)
			if v != 0.0:
				d[k] = v
		out.append(d)
	return out


## `x` rounded to 1 / `per` (10.0: one decimal), as the double nearest that decimal, so the value
## survives a JSON round trip exactly (snappedf's multiply can land a bit off it: 4.6000000000000005).
static func _dec(x: float, per: float) -> float:
	return roundf(x * per) / per


## Feast of Victory's healing, read before _apply_losses applies it: [[fighter id, hp, max hp]] for each
## standing fighter of the winning side below its maximum, when that side has the mandate.
static func _feast_healed(sides: Array, winner: String) -> Array:
	var out := []
	for s in sides:
		if s.faction != winner or not s.feast:
			continue
		for f in s.fighters:
			if f.alive and f.hp < f.max:
				out.append([int(f.id), int(f.hp), int(f.max)])
	return out


# --- the report -----------------------------------------------------------------------------------

static func _report(sides: Array, ctx: Dictionary, env: Dictionary, rounds: Array, wi: int, end: String, state) -> Dictionary:
	var winner: Dictionary = sides[wi]
	var where := _place(ctx, state)
	var factors := _factors(sides, env, wi, end, rounds.size())
	var chosen := _choose(factors, wi)
	var clauses := []
	for c in chosen:
		clauses.append(c.clause)
	var why := "; ".join(clauses)

	var lines := []
	var who := []
	for s in sides:
		var role := "defending" if s.is_defender else ("attacking" if not String(ctx.get("defender", "")).is_empty() else "arrived")
		who.append("%s (%s) with the %s" % [s.name, role, " and the ".join(s.armies)])
	lines.append("Battle %s. %s." % [where, "; ".join(who)])
	for r in rounds:
		lines.append(r.line)
	var side_reports := []
	var losses := []
	for s in sides:
		var lost_count: int = s.lost.size()
		losses.append(_losses_text(s))
		var rate := 0 if s.attacks == 0 else roundi(100.0 * s.hits / s.attacks)
		var avg := 0 if s.attacks == 0 else roundi(float(s.chance_sum) / s.attacks)
		var sr := {"faction": s.faction, "name": s.name, "armies": s.armies.duplicate(),
			"roster": s.roster.duplicate(true),
			"defender": s.is_defender, "fighters_start": s.count_start, "fighters_lost": lost_count,
			"lost": s.lost.duplicate(), "hp_start": s.hp_start, "hp_end": _hp(s), "routed": s.routed,
			"destroyed": s.destroyed, "out_round": s.out_round, "attacks": s.attacks, "hits": s.hits,
			"hit_rate": rate, "expected_hit_rate": avg,
			"hit_chance_range": [s.chance_min if s.attacks > 0 else 0, s.chance_max],
			"damage_dealt": s.dealt, "damage_expected": snappedf(s.expected, 0.1),
			"triggers": s.triggers.duplicate(), "morale_log": s.morale_log.duplicate(true),
			"base_morale": s.base_morale}
		# M2-2: only a side with a ruler or battle mandates carries these, so an M1 report is unchanged.
		if not s.ruler_info.is_empty():
			sr["ruler"] = _ruler_report(s)
		if not s.mandates.is_empty():
			sr["mandates"] = _mandates_report(s)
		side_reports.append(sr)
	lines.append("Casualties: %s." % "; ".join(losses))
	var hit_parts := []
	for sr in side_reports:
		if sr.attacks > 0:
			var lo: int = sr.hit_chance_range[0]
			var hi: int = sr.hit_chance_range[1]
			var chances := ("a %d%% chance" % lo) if lo == hi else ("a %d-%d%% chance, about %d%% on average" % [lo, hi, sr.expected_hit_rate])
			hit_parts.append("%s hit %d%% of the time (%d of %d; each attack had %s)" % [sr.name, sr.hit_rate, sr.hits, sr.attacks, chances])
	if not hit_parts.is_empty():
		lines.append("Hits: %s." % "; ".join(hit_parts))
	var how := ""
	match end:
		"destroyed": how = "no enemy was left standing"
		"rout": how = "the enemy broke and fled"
		"mutual": how = "both sides broke in the same round, and %s had more of its strength left" % winner.name
		"round_cap":
			if winner.is_defender:
				how = "the attack was not decided after %d rounds, so the defender held" % ROUND_CAP
			else:
				how = "nothing was decided after %d rounds, and %s had more of its strength left" % [ROUND_CAP, winner.name]
	var n := rounds.size()
	lines.append("Result: %s won after %d %s: %s." % [winner.name, n, "round" if n == 1 else "rounds", how])
	lines.append("Why: %s." % _cap(why))
	var summary := "%s won after %d %s: %s. %s." % [winner.name, n, "round" if n == 1 else "rounds", why, "; ".join(losses)]
	var chosen_out := []
	for c in chosen:
		chosen_out.append({"id": c.id, "faction": c.faction, "impact": snappedf(c.impact, 0.1), "text": c.clause, "favors_winner": c.faction == winner.faction})
	var all_out := []
	for f in factors:
		all_out.append({"id": f.id, "faction": f.faction, "impact": snappedf(f.impact, 0.1), "brief": f.brief, "text": f.clause})
	return {"kind": env.kind, "provinces": ctx.get("province_ids", []).duplicate(), "place": where,
		"terrain": env.terrain, "fort": env.fort, "defender": ctx.get("defender", ""), "winner": winner.faction,
		"winner_name": winner.name, "end": end, "rounds_fought": n, "round_cap": ROUND_CAP,
		"rounds": rounds.duplicate(true), "sides": side_reports, "factors": chosen_out, "all_factors": all_out,
		"why": why, "summary": summary, "lines": lines}


## One side's losses for the casualty line, in plain words:
##   "Aurel Crown lost 1 of 4 fighters", "Thornmane Clans lost 2 of 3 fighters, and the last one fled",
##   "Thornmane Clans' only fighter fled", "Aurel Crown lost none of its 4 fighters".
static func _losses_text(s: Dictionary) -> String:
	var n: int = s.count_start
	var lost: int = s.lost.size()
	var fled: int = n - lost if s.routed else 0
	if n == 1:
		if lost == 1:
			return "%s lost its only fighter" % s.name
		return ("%s only fighter fled" % _poss(s.name)) if fled == 1 else "%s lost no fighters" % s.name
	if lost == 0:
		return ("%s lost no fighters, but all %d fled" % [s.name, n]) if fled > 0 else "%s lost none of its %d fighters" % [s.name, n]
	if lost == n:
		return ("%s lost both fighters" % s.name) if n == 2 else "%s lost all %d fighters" % [s.name, n]
	var text := "%s lost %d of %d fighters" % [s.name, lost, n]
	if fled == 1:
		text += ", and the last one fled"
	elif fled > 1:
		text += ", and the other %d fled" % fled
	return text


## A side's ruler in the report (§9): {"id", "name", "rank" ("front" | "second"), "kept_power",
## "max_hp", "attack", "defense", "hp_start", "hp_end", "fell" (its hp reached 0), "fell_round" (0 if it
## didn't), "damage_dealt", "damage_expected", and "dread" (the morale it took from every enemy side
## while it stood) when its Dread worked in this battle}. A ruler on a losing side is lost with its army
## even when it did not fall (TurnResolver).
static func _ruler_report(s: Dictionary) -> Dictionary:
	var info: Dictionary = s.ruler_info
	var hp_end := 0
	for f in s.fighters:
		if f.ruler:
			hp_end = f.hp
	var out := {"id": info.id, "name": info.name, "rank": info.rank, "kept_power": info.kept_power,
		"max_hp": info.max_hp, "attack": info.attack, "defense": info.defense, "hp_start": info.hp_start,
		"hp_end": hp_end, "fell": s.ruler_fell > 0, "fell_round": s.ruler_fell, "damage_dealt": s.ruler_dealt,
		"damage_expected": snappedf(s.ruler_expected, 0.1)}
	if int(info.dread) > 0:
		out["dread"] = int(info.dread)
	return out


## The battle mandates a side fought with, in the order taken: [{"id", "name", "effect", "codex"}].
static func _mandates_report(s: Dictionary) -> Array:
	var out := []
	for mid in s.mandates:
		var md := RulerRules.mandate_data(mid)
		out.append({"id": mid, "name": String(md.get("name", "")), "effect": String(md.get("effect", "")),
			"codex": String(md.get("codex", "mandates"))})
	return out


## Every candidate deciding factor: {"id", "side" (index it helped), "faction", "impact" (about how
## many hp it was worth to that side), "clause" (phrased for the report), "brief" (seed-free, for odds)}.
static func _factors(sides: Array, env: Dictionary, wi: int, end: String, rounds_fought: int) -> Array:
	var out := []
	var winner: Dictionary = sides[wi]
	for si in sides.size():
		var s: Dictionary = sides[si]
		var keys: Array = s.impact.keys()
		keys.sort()
		for k in keys:
			var v: float = s.impact[k]
			if v < 0.05:
				continue
			var won: bool = si == wi
			var c := ""
			var brief := ""
			var unit: String = s.trait_units.get(k, "")
			var who := _poss(s.name)
			var dmg := roundi(v)
			match k:
				"terrain":
					var td: int = TERRAIN[env.terrain].defense
					var ta: int = TERRAIN[env.terrain].attack
					var bonus := "+%d defense" % td + (" and +%d attack" % ta if ta > 0 else "")
					c = "the %s gave the defending %s %s, worth about %d damage" % [env.terrain, s.name, bonus, dmg] if won \
						else "even though the %s gave the defending %s %s" % [env.terrain, s.name, bonus]
					brief = "the %s gives the defending %s %s" % [env.terrain, s.name, bonus]
				"fort":
					c = "the fort gave the defending %s +%d defense, worth about %d damage" % [s.name, FORT_DEFENSE, dmg] if won \
						else "even though the fort gave the defending %s +%d defense" % [s.name, FORT_DEFENSE]
					brief = "the fort gives the defending %s +%d defense" % [s.name, FORT_DEFENSE]
				"commander":
					# v is the damage beyond what the same gold in ordinary units would have dealt.
					var cname := _commander_name(s)
					var total := roundi(s.cmd_expected)
					c = "%s %s fought from the back line and dealt about %d damage, about %d more than the same gold in ordinary units would have" % [
						who, cname, total, dmg] if won \
						else "even though %s %s dealt about %d damage from the back line" % [who, cname, total]
					brief = "%s %s (fights from the back line, +%d morale)" % [who, cname, COMMANDER_MORALE]
				SHIELD_WALL:
					c = "%s %s held their shield wall (+%d defense), turning aside about %d damage" % [who, unit, SHIELD_WALL_DEFENSE, dmg] if won \
						else "even though %s %s held their shield wall" % [who, unit]
				VOLLEY:
					c = "%s %s shot over their own front rank, out of reach, for about %d damage" % [who, unit, roundi(s.volley_expected)] if won \
						else "even though %s %s shot safely from the second rank" % [who, unit]
				CHARGE:
					c = "%s %s opened with a charge worth about %d extra damage%s" % [who, unit, dmg, " (the forest blunted it)" if env.terrain == "forest" else ""] if won \
						else "even though %s %s opened with a charge" % [who, unit]
				BERSERK:
					c = "%s %s went berserk once wounded (+%d attack), adding about %d damage" % [who, unit, BERSERK_ATTACK, dmg] if won \
						else "even though %s %s went berserk" % [who, unit]
				SKIRMISH:
					var behind := _the(_most_hit(s.skirmish_targets))
					c = "%s %s skirmished past the front line and hit %s behind it, for about %d damage" % [who, unit, behind, roundi(s.skirmish_reach)] if won \
						else "even though %s %s skirmished past the front line to %s" % [who, unit, behind]
				PACK_LEADER:
					c = "%s %s drove the pack (+%d attack to every unit), adding about %d damage" % [who, unit, PACK_LEADER_ATTACK, dmg] if won \
						else "even though %s %s drove the pack" % [who, unit]
				RULER:
					# The damage the ruler dealt (§7.4): it costs no gold, so all of it is what it added.
					var rname := String(s.ruler_info.name)
					var rank: String = RULER_RANK_WORDS.get(String(s.ruler_info.rank), "")
					c = "%s fought %s and dealt about %d damage%s" % [rname, rank, dmg, " before falling" if s.ruler_fell > 0 else ""] if won \
						else "even though %s fought %s and dealt about %d damage" % [rname, rank, dmg]
					brief = "%s (fights %s, +%d morale while it stands)" % [rname, rank, RulerData.RULER_MORALE]
				_:
					if not k.begins_with(MANDATE_PREFIX):
						continue
					var words := _mandate_words(s, k, dmg)
					if words.is_empty():
						continue
					c = String(words.done) + String(words.tail) if won else "even though %s" % words.done
					brief = String(words.brief)
			if brief.is_empty():
				brief = "%s %s (%s)" % [who, unit, TRAIT_SHORT.get(k, k)]
			out.append({"id": k, "side": si, "faction": s.faction, "impact": v, "clause": c, "brief": brief})

	# Morale: routs, and the morale effects that decided whether a side broke.
	for si in sides.size():
		var s: Dictionary = sides[si]
		if s.routed and si != wi:
			var ri: Dictionary = s.rout_info
			out.append({"id": "rout", "side": wi, "faction": winner.faction, "impact": float(ri.hp) * 0.5,
				"clause": "%s broke after losing %d%% of its strength (morale %d holds only to %d%%) and fled with %d hp unspent" % [
					s.name, ri.lost_pct, ri.morale, ri.break_pct, ri.hp],
				"brief": "%s is likely to break first (morale %d)" % [s.name, ri.morale]})
			var fury: int = ri.parts.get(FURY, 0)
			if fury < 0:
				var decisive: bool = ri.lost_pct < break_pct(ri.morale - fury)
				var bear_side := _side_with_trait(sides, FURY, si)
				if bear_side >= 0:
					var bs: Dictionary = sides[bear_side]
					out.append({"id": FURY, "side": bear_side, "faction": bs.faction,
						"impact": float(ri.hp) if decisive else float(-fury) * 0.5,
						"clause": ("%s %s roared (%d morale), and %s broke a round sooner than it would have" if decisive
							else "%s %s roared (%d morale) and shook %s") % [_poss(bs.name), bs.trait_units[FURY], fury, s.name] if bear_side == wi
							else "even though %s %s roared (%d morale)" % [_poss(bs.name), bs.trait_units[FURY], fury],
						"brief": "%s %s (%s)" % [_poss(bs.name), bs.trait_units[FURY], TRAIT_SHORT[FURY]]})
			# M2-2: the Great Thornmane's Dread, measured like Fury (§7.4).
			var dread: int = ri.parts.get(DREAD, 0)
			if dread < 0:
				var dread_side := _side_with_dread(sides, si)
				if dread_side >= 0:
					var ds: Dictionary = sides[dread_side]
					var decisive_dread: bool = ri.lost_pct < break_pct(ri.morale - dread)
					var whose := "%s %s (%d morale)" % [_poss(String(ds.ruler_info.name)), RulerRules.ability_name(String(ds.ruler_info.id)), dread]
					out.append({"id": "ability_dread", "side": dread_side, "faction": ds.faction,
						"impact": float(ri.hp) if decisive_dread else float(-dread) * 0.5,
						"clause": ("%s made %s break a round sooner than it would have" if decisive_dread else "%s shook %s") % [whose, s.name]
							if dread_side == wi else "even though %s shook %s" % [whose, s.name],
						"brief": "%s %s (%d enemy morale while it stands)" % [_poss(String(ds.ruler_info.name)),
							RulerRules.ability_name(String(ds.ruler_info.id)), dread]})
	for si in sides.size():
		var s: Dictionary = sides[si]
		for key in ["commander", INSPIRE]:
			var held_by_it := false
			var seen := false
			for e in s.morale_log:
				var part: int = e.parts.get(key, 0)
				if part > 0:
					seen = true
					if e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - part):
						held_by_it = true
			if not seen or key == "commander" and not held_by_it:
				continue
			var cname := _commander_name(s)
			var impact := float(_hp(s)) if held_by_it else float(INSPIRE_MORALE) * 0.5
			var c := ""
			if si == wi:
				# The commander's own +morale and Inspire's are separate factors, so their clauses differ
				# even when both kept the line from breaking.
				if key == "commander":
					c = "%s %s kept the line from breaking (+%d morale while it stands)" % [_poss(s.name), cname, COMMANDER_MORALE]
				else:
					c = ("%s %s inspired the line to hold (+%d morale from Inspire)" if held_by_it else "%s %s inspired the line (+%d morale from Inspire)") % [
						_poss(s.name), cname, INSPIRE_MORALE]
			else:
				c = "even though %s %s steadied the line" % [_poss(s.name), cname] if key == "commander" \
					else "even though %s %s inspired the line" % [_poss(s.name), cname]
			out.append({"id": "morale_" + key, "side": si, "faction": s.faction, "impact": impact, "clause": c,
				"brief": "%s %s (%s)" % [_poss(s.name), cname, "+%d morale" % (COMMANDER_MORALE + (INSPIRE_MORALE if key == INSPIRE else 0))]})
	# M2-2: the ruler's +morale kept the line, measured like the commander's (§7.4), and Iron Discipline
	# held a side past its breaking point while a commander stood: the hp it kept from a rout.
	for si in sides.size():
		var s: Dictionary = sides[si]
		var won: bool = si == wi
		if not s.ruler_info.is_empty():
			var held_by_ruler := false
			for e in s.morale_log:
				var part: int = e.parts.get(RULER, 0)
				if part > 0 and e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - part):
					held_by_ruler = true
			if held_by_ruler:
				var rname := String(s.ruler_info.name)
				out.append({"id": "morale_" + RULER, "side": si, "faction": s.faction, "impact": float(_hp(s)),
					"clause": "%s kept the line from breaking (+%d morale while it stands)" % [rname, RulerData.RULER_MORALE] if won
						else "even though %s steadied the line (+%d morale)" % [rname, RulerData.RULER_MORALE],
					"brief": "%s (+%d morale while it stands)" % [rname, RulerData.RULER_MORALE]})
		if not s.iron_held.is_empty():
			var last: Dictionary = s.iron_held.back()
			var iron := RulerRules.mandate_name(RulerRules.IRON_DISCIPLINE)
			var held := "%s held the %s line past its breaking point (lost %d%%, breaks at %d%%) while its %s stood" % [
				iron, s.name, last.lost_pct, last.break_pct, last.held_by]
			out.append({"id": MANDATE_PREFIX + RulerRules.IRON_DISCIPLINE, "side": si, "faction": s.faction, "impact": float(_hp(s)),
				"clause": held if won else "even though %s" % held,
				"brief": "%s keeps %s from breaking while one of its commanders stands" % [iron, s.name]})

	# Numbers: the bigger force, as a share of the fight's hp x attack. A side counts as the bigger force
	# only when it brought more hit points than every other side and at least as many fighters, and its
	# hp x attack was bigger too.
	var total_power := 0
	var total_hp := 0
	var biggest := 0
	for si in sides.size():
		total_power += sides[si].power
		total_hp += sides[si].hp_start
		if sides[si].hp_start > sides[biggest].hp_start:
			biggest = si
	var st: Dictionary = sides[biggest]
	var runner_up := -1  # the next biggest side, which the clause compares with
	var bigger := total_power > 0
	for si in sides.size():
		if si == biggest:
			continue
		var o: Dictionary = sides[si]
		if o.hp_start >= st.hp_start or o.count_start > st.count_start:
			bigger = false
		if runner_up < 0 or o.hp_start > sides[runner_up].hp_start:
			runner_up = si
	var even := 1.0 / sides.size()
	if bigger and runner_up >= 0 and float(st.power) / total_power > even:
		var o: Dictionary = sides[runner_up]
		var impact := (float(st.power) / total_power - even) * total_hp * 0.5
		var force := "%d %s (%d hp) against %d (%d hp)" % [st.count_start, "fighter" if st.count_start == 1 else "fighters",
			st.hp_start, o.count_start, o.hp_start]
		out.append({"id": "numbers", "side": biggest, "faction": st.faction, "impact": impact,
			"clause": "%s brought the bigger force: %s" % [st.name, force] if biggest == wi
				else "even though %s brought the bigger force (%s)" % [st.name, force],
			"brief": "%s has the bigger force (%d hp against %d)" % [st.name, st.hp_start, o.hp_start]})

	# Luck: damage dealt compared with what average rolls would have dealt (hit chance x damage of
	# every attack). The clause states exactly that, in damage, and gives hit rates only as separate
	# facts: a side whose big hits landed can be luckier in damage while hitting less often.
	var luck := []
	for s in sides:
		luck.append(s.dealt - s.expected)
	var others := 0.0
	var luckiest_other := -1
	for si in sides.size():
		if si == wi:
			continue
		others += luck[si] / (sides.size() - 1)
		if luckiest_other < 0 or luck[si] > luck[luckiest_other]:
			luckiest_other = si
	var adv: float = luck[wi] - others
	var lucky: int = wi if adv >= 0 else luckiest_other
	if lucky >= 0:
		# The side it is compared with: the unluckiest other side when the winner had the better
		# rolls, otherwise the winner. Either way luck[lucky] >= luck[other].
		var other := wi
		if lucky == wi:
			other = luckiest_other
			for si in sides.size():
				if si != wi and luck[si] < luck[other]:
					other = si
		var clause := _luck_clause(sides, lucky, other, luck)
		if lucky != wi:
			clause = "even though " + clause
		out.append({"id": "luck", "side": lucky, "faction": sides[lucky].faction, "impact": absf(adv), "clause": clause, "brief": "luck"})

	if end == "round_cap":
		out.append({"id": "round_cap", "side": wi, "faction": winner.faction, "impact": 1000000.0,
			"clause": ("the attackers could not break %s within %d rounds, so it held its ground" % [winner.name, ROUND_CAP]) if winner.is_defender
				else "after %d undecided rounds %s had more of its strength left" % [ROUND_CAP, winner.name],
			"brief": "%s only has to hold for %d rounds" % [winner.name, ROUND_CAP]})
	return out


## The luck clause, in the terms luck is measured in: how much more or less damage two sides' hits did
## than average rolls would have, then their hit rates as separate facts. `lucky` had the better rolls
## (luck[lucky] >= luck[other]), so the side named first is the one the rolls helped or hurt most:
##   "Aurel Crown's hits did about 9 more damage than average rolls would (mostly its Knights' charge),
##    and Thornmane Clans' about 4 less; hit rates: Aurel Crown 67% (about 77% expected), ..."
static func _luck_clause(sides: Array, lucky: int, other: int, luck: Array) -> String:
	var ls: Dictionary = sides[lucky]
	var os: Dictionary = sides[other]
	var a := roundi(luck[lucky])
	var b := roundi(luck[other])
	var text := "both sides' hits did about as much damage as average rolls would"
	if a > 0:
		text = "%s hits did about %d more damage than average rolls would%s, and %s" % [
			_poss(ls.name), a, _luck_source(ls, true), _luck_brief(os, b)]
	elif b < 0:
		text = "%s hits did about %d less damage than average rolls would%s, and %s" % [
			_poss(os.name), -b, _luck_source(os, false), _luck_brief(ls, a)]
	var rates := []
	for s in [ls, os]:
		var rate := 0 if s.attacks == 0 else roundi(100.0 * s.hits / s.attacks)
		var exp_rate := 0 if s.attacks == 0 else roundi(float(s.chance_sum) / s.attacks)
		rates.append("%s %d%% (about %d%% expected)" % [s.name, rate, exp_rate])
	return "%s; hit rates: %s" % [text, ", ".join(rates)]


## The second side's part of the luck clause: "Thornmane Clans' about 4 less", "... about as much".
static func _luck_brief(side: Dictionary, d: int) -> String:
	if d > 0:
		return "%s about %d more" % [_poss(side.name), d]
	if d < 0:
		return "%s about %d less" % [_poss(side.name), -d]
	return "%s about as much" % _poss(side.name)


## " (mostly its Knights' charge)" when one kind of attack made up at least half of a side's luck in
## that direction (landed hits for good luck, misses for bad luck), otherwise "".
static func _luck_source(side: Dictionary, good: bool) -> String:
	var total: float = absf(side.dealt - side.expected)
	var best_key := ""
	var best := 0.0
	var keys: Array = side.luck_by.keys()
	keys.sort()
	for k in keys:
		var v: float = side.luck_by[k] if good else -side.luck_by[k]
		if v > best + 0.000001:
			best = v
			best_key = k
	if best_key.is_empty() or best < total * 0.5:
		return ""
	var parts := best_key.split("|")
	var charge := parts.size() > 1
	if good:
		return " (mostly its %s %s)" % [_poss(parts[0]), "charge" if charge else "hits"]
	return " (mostly its %s %s)" % [_poss(parts[0]), "missed charges" if charge else "misses"]


## Picks the 1-3 factors that best explain the result: the biggest ones that helped the winner, plus
## the biggest one that helped a loser when it was large enough to be worth an "even though".
static func _choose(factors: Array, wi: int) -> Array:
	var pos := factors.filter(func(f): return f.side == wi and f.impact > MIN_IMPACT)
	var neg := factors.filter(func(f): return f.side != wi and f.impact > MIN_IMPACT)
	var order := func(a, b):
		if a.impact != b.impact:
			return a.impact > b.impact
		return a.id < b.id
	pos.sort_custom(order)
	neg.sort_custom(order)
	var chosen: Array = pos.slice(0, 3)
	if not neg.is_empty() and neg[0].id != "numbers" or not neg.is_empty() and pos.is_empty():
		var bar: float = pos[mini(1, pos.size() - 1)].impact if not pos.is_empty() else 0.0
		if neg[0].impact >= bar * 0.75 and neg[0].impact < 1000000.0:
			if chosen.size() == 3:
				chosen.pop_back()
			chosen.append(neg[0])
	if chosen.is_empty():
		var all := factors.duplicate()
		all.sort_custom(order)
		chosen = all.slice(0, 1)
	return chosen


# --- names ----------------------------------------------------------------------------------------

static func _faction_name(fid: String, state) -> String:
	if state is GameState:
		return TurnResolver._faction_name(state, fid)
	for f in FactionData.FACTIONS:
		if f.id == fid:
			return f.name
	return "an unknown faction"


static func _army_label(army: Army, state) -> String:
	if state is GameState:
		return TurnResolver.army_label(state, army)
	return "%s army (%s)" % [_faction_name(army.owner, state), TurnResolver._army_detail(army)]


static func _place(ctx: Dictionary, state) -> String:
	var pids: Array = ctx.get("province_ids", [])
	var province = ctx.get("province")
	if ctx.get("kind", "province") == "border":
		if state is GameState and pids.size() == 2:
			return "on the border between %s and %s" % [TurnResolver._province_name(state, pids[0]), TurnResolver._province_name(state, pids[1])]
		return "on a border"
	if province != null:
		return "of %s (%s%s)" % [province.name, province.terrain, ", fort" if province.has_fort else ""]
	return "in the field"


static func _commander_name(side: Dictionary) -> String:
	for f in side.fighters:
		if f.cmd:
			return f.name
	return "commander"


## The name hit most often in `counts` ({name: hits}; the first in name order on a tie), for the clause.
static func _most_hit(counts: Dictionary) -> String:
	var names: Array = counts.keys()
	names.sort()
	var best := ""
	for n in names:
		if best.is_empty() or counts[n] > counts[best]:
			best = n
	return best if not best.is_empty() else "second rank"


static func _side_with_trait(sides: Array, trait_id: String, not_side: int) -> int:
	for i in sides.size():
		if i != not_side and sides[i].trait_units.has(trait_id):
			return i
	return -1


## The first side other than `not_side` whose ruler has Dread in this battle, or -1.
static func _side_with_dread(sides: Array, not_side: int) -> int:
	for i in sides.size():
		if i != not_side and sides[i].dread > 0:
			return i
	return -1


## A stat mandate's part of the "why", from its data (§7.4): {"done" (what it did, the clause without
## its worth), "tail" (", worth about N damage"), "brief" (seed-free, for odds)}; {} for a mandate with
## no part to explain. `key` is "mandate_<id>", `dmg` its worth in damage (hp absorbed for Veteran Levies).
static func _mandate_words(s: Dictionary, key: String, dmg: int) -> Dictionary:
	var mid := key.trim_prefix(MANDATE_PREFIX)
	var md := RulerRules.mandate_data(mid)
	if md.is_empty():
		return {}
	var name := String(md.name)
	if md.has("base_hit"):
		return {"done": "%s raised %s base hit chance to %d%%" % [name, _poss(s.name), s.base_hit],
			"tail": ", worth about %d damage" % dmg,
			"brief": "%s raises %s base hit chance to %d%%" % [name, _poss(s.name), s.base_hit]}
	if md.has("wounded_attack"):
		return {"done": "%s gave %s wounded fighters +%d attack" % [name, _poss(s.name), s.frenzy],
			"tail": ", adding about %d damage" % dmg,
			"brief": "%s gives %s wounded fighters +%d attack" % [name, _poss(s.name), s.frenzy]}
	var units: Dictionary = md.get("units", {})
	if units.has("hp") and units.size() == 1:
		var bonus := RulerRules.units_bonus_text(mid)
		return {"done": "%s gave %s units %s" % [name, _poss(s.name), bonus],
			"tail": ", which absorbed about %d damage" % dmg,
			"brief": "%s gives %s units %s" % [name, _poss(s.name), bonus]}
	if not units.is_empty():
		var bonus := RulerRules.units_bonus_text(mid)
		return {"done": "%s gave every %s unit %s" % [name, s.name, bonus],
			"tail": ", worth about %d damage" % dmg,
			"brief": "%s gives every %s unit %s" % [name, s.name, bonus]}
	return {}


static func _poss(name: String) -> String:
	return name + ("'" if name.ends_with("s") else "'s")


## A name without its leading "the", for "Thornmane Clans' Great Thornmane fell." (other names unchanged).
static func _bare(name: String) -> String:
	return name.trim_prefix("the ")


## A name with "the" in front, unless it already has it: "the Crossbowmen", "the Ever-Regent".
static func _the(name: String) -> String:
	return name if name.begins_with("the ") else "the " + name


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)
