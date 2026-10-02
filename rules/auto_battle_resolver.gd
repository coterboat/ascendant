class_name AutoBattleResolver
extends BattleResolver
## The real battle rules (#4). Pure and deterministic: every roll comes from the SeededRNG passed in,
## sides go in sorted faction id order, armies in sorted id order, units in army order, commanders
## last. Player-facing statement of these rules: RulesCodex "battle_*" and "trait_*" entries.
##
## A battle is fought in rounds, at most ROUND_CAP. Each round every standing fighter (unit or
## commander) attacks once, all at the same time (damage lands at the end of the round):
##   target  a random standing enemy from the front rank. Volley units (Crossbowmen) stand behind the
##           other units and commanders stand behind everyone: they can only be targeted once nothing
##           in front of them stands.
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
## Traits (data/factions.gd), one effect each:
##   Shield Wall  +SHIELD_WALL_DEFENSE defense while another friendly fighter stands.
##   Volley       fights from the second rank (see target above).
##   Charge       +CHARGE_DAMAGE damage on hits in round 1 (CHARGE_DAMAGE_FOREST in a forest).
##   Inspire      +INSPIRE_MORALE to its side's morale while it stands.
##   Berserk      +BERSERK_ATTACK attack while below full hp.
##   Skirmish     ignores the defender's forest and hills defense bonus (not forts).
##   Fury         each standing War Bear gives enemy sides -FURY_MORALE morale (at most -FURY_MAX).
##   Pack Leader  +PACK_LEADER_ATTACK attack to every friendly unit while it stands.

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
const CHARGE_DAMAGE_FOREST := 2
const INSPIRE_MORALE := 2
const BERSERK_ATTACK := 3
const FURY_MORALE := 2
const FURY_MAX := 4
const PACK_LEADER_ATTACK := 1

const SHIELD_WALL := "Shield Wall"
const VOLLEY := "Volley"
const CHARGE := "Charge"
const INSPIRE := "Inspire"
const BERSERK := "Berserk"
const SKIRMISH := "Skirmish"
const FURY := "Fury"
const PACK_LEADER := "Pack Leader"
const TRAIT_SHORT := {
	SHIELD_WALL: "+2 defense in a group",
	VOLLEY: "shoots from the second rank",
	CHARGE: "bonus damage in the first round",
	INSPIRE: "+2 morale",
	BERSERK: "+3 attack when wounded",
	SKIRMISH: "ignores forest and hills cover",
	FURY: "-2 enemy morale",
	PACK_LEADER: "+1 attack to every unit",
}

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
## Returns {"result": {"winner", "strengths", "tie_break", "roll", "why", "report"}, "report": {...}}.
## `state` is optional and only used for player-facing names.
static func resolve(attacker, defender, province: Province, rng: SeededRNG, state: GameState = null) -> Dictionary:
	var att: Array = attacker if attacker is Array else [attacker]
	var dfn: Array = defender if defender is Array else [defender]
	var dfid: String = dfn[0].owner
	var sides := [{"faction": att[0].owner, "armies": att}, {"faction": dfid, "armies": dfn}]
	sides.sort_custom(func(a, b): return a.faction < b.faction)
	var ctx := {"kind": "province", "defender": dfid, "province": province,
		"province_ids": [province.id] if province else [], "state": state}
	var r := fight(sides, ctx, rng)
	return {"result": r.result, "report": r.result.report}


## BattleResolver interface, called by TurnResolver for every battle (any number of sides).
## Applies the winner's losses to its armies (dead units removed, wounds kept); the TurnResolver
## removes the losing armies. The battle dictionary may carry "state" for names and terrain.
func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
	var state = battle.get("state")
	var kind: String = battle.get("kind", "province")
	var pids: Array = battle.get("provinces", [])
	var province: Province = null
	if state is GameState and kind == "province" and not pids.is_empty():
		province = state.find_province(pids[0])
	var ctx := {"kind": kind, "defender": battle.get("defender", ""), "province": province,
		"province_ids": pids, "state": state if state is GameState else null}
	var r := fight(battle.sides, ctx, rng)
	_apply_losses(r.sides, r.result.winner)
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


static func hit_chance(attack: int, defense: int) -> int:
	return clampi(BASE_HIT + HIT_PER_POINT * (attack - defense), MIN_HIT, MAX_HIT)


static func damage(attack: int, defense: int) -> int:
	return maxi(MIN_DAMAGE, ceili(attack * 0.5) - floori(defense * 0.25))


static func break_pct(morale: int) -> int:
	return clampi(BREAK_BASE_PCT + morale * MORALE_PCT_PER_POINT, MIN_BREAK_PCT, MAX_BREAK_PCT)


static func codex_id_for_trait(trait_id: String) -> String:
	return "trait_" + trait_id.to_lower().replace(" ", "_")


# --- the battle -----------------------------------------------------------------------------------

## Fights one battle without changing any army. `sides` = [{"faction", "armies"}] sorted by faction
## id; `ctx` = {"kind", "defender", "province" (Province or null), "province_ids", "state"}.
## Returns {"result": BattleResolver result with "report", "sides": internal side records}.
static func fight(sides_in: Array, ctx: Dictionary, rng: SeededRNG) -> Dictionary:
	var state = ctx.get("state")
	var kind: String = ctx.get("kind", "province")
	var province = ctx.get("province")
	var terrain := ""
	var fort := false
	if province != null and kind == "province":
		terrain = province.terrain
		fort = province.has_fort
	var defender_fid: String = ctx.get("defender", "")
	var sides := _build_sides(sides_in, defender_fid, state)
	var env := {"terrain": terrain, "fort": fort, "kind": kind}

	var rounds := []
	var round_no := 0
	while round_no < ROUND_CAP and _standing(sides).size() > 1:
		round_no += 1
		rounds.append(_fight_round(sides, round_no, env, rng))

	var standing := _standing(sides)
	var winner_idx := -1
	var tie_break := "none"
	var roll := 0
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
		if end == "mutual":
			sides[winner_idx].routed = false
			sides[winner_idx].held_field = true

	var report := _report(sides, ctx, env, rounds, winner_idx, end, state)
	var strengths := {}
	for s in sides:
		strengths[s.faction] = s.strength
	var result := {"winner": sides[winner_idx].faction, "strengths": strengths, "tie_break": tie_break,
		"roll": roll, "why": report.why, "report": report}
	return {"result": result, "sides": sides}


static func _build_sides(sides_in: Array, defender_fid: String, state) -> Array:
	var sides := []
	for i in sides_in.size():
		var sd: Dictionary = sides_in[i]
		var armies: Array = sd.armies.duplicate()
		armies.sort_custom(func(a, b): return a.id < b.id)
		var fighters := []
		var labels := []
		var morale_sum := 0
		var regulars := 0
		var strength := 0
		for a in armies:
			labels.append(_army_label(a, state))
			for u in a.units:
				fighters.append(_fighter(i, a, u, false))
				morale_sum += u.type.morale
				regulars += 1
			if a.commander:
				fighters.append(_fighter(i, a, a.commander, true))
			strength += StubBattleResolver.army_strength(a)
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
			"armies": labels, "is_defender": sd.faction == defender_fid, "base_morale": base_morale,
			"hp_start": hp, "count_start": fighters.size(), "strength": strength, "power": hp * power_attack,
			"routed": false, "destroyed": false, "held_field": false, "out_round": 0, "rout_info": {},
			"attacks": 0, "hits": 0, "chance_sum": 0, "chance_min": 100, "chance_max": 0,
			"dealt": 0, "expected": 0.0, "luck_by": {}, "impact": {}, "triggers": {}, "trait_units": {},
			"volley_expected": 0.0, "lost": [], "morale_log": []})
		for f in fighters:
			if not f.trait.is_empty():
				sides[i].trait_units[f.trait] = f.name
	return sides


static func _fighter(side_idx: int, army: Army, unit: Unit, is_cmd: bool) -> Dictionary:
	var t: String = unit.type.trait_id
	var tier := 0
	if is_cmd:
		tier = 2
	elif t == VOLLEY:
		tier = 1
	return {"side": side_idx, "army": army.id, "army_ref": army, "unit": unit, "type": unit.type, "name": unit.type.name,
		"trait": t, "cmd": is_cmd, "tier": tier, "hp": unit.current_hp, "max": unit.type.hp,
		"alive": unit.current_hp > 0, "pending": 0}


static func _standing(sides: Array) -> Array:
	var out := []
	for i in sides.size():
		if not sides[i].routed and not sides[i].destroyed:
			out.append(i)
	return out


static func _fight_round(sides: Array, round_no: int, env: Dictionary, rng: SeededRNG) -> Dictionary:
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
	for si in standing:
		var side: Dictionary = sides[si]
		for f in side.fighters:
			if not f.alive:
				continue
			var pool := _targets(sides, si, standing)
			if pool.is_empty():
				continue
			var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			var tside: Dictionary = sides[t.side]
			var atk := _attack(f, side, env)
			var dfn := _defense(t, tside, f, env)
			var bonus := 0
			if f.trait == CHARGE and round_no == 1:
				bonus = CHARGE_DAMAGE_FOREST if env.terrain == "forest" else CHARGE_DAMAGE
			var chance := hit_chance(atk.value, dfn.value)
			var dmg := damage(atk.value, dfn.value) + bonus
			var expected := chance / 100.0 * dmg
			# What each modifier was worth on this attack, in expected damage.
			for p in atk.parts:
				var a2: int = atk.value - atk.parts[p]
				var gain: float = expected - hit_chance(a2, dfn.value) / 100.0 * (damage(a2, dfn.value) + bonus)
				_add_impact(side, p, gain)
			for p in dfn.parts:
				var d2: int = dfn.value - dfn.parts[p]
				var saved: float = hit_chance(atk.value, d2) / 100.0 * (damage(atk.value, d2) + bonus) - expected
				_add_impact(tside, p, saved)
			if dfn.skirmish > 0:
				var d3: int = dfn.value + dfn.skirmish
				_add_impact(side, SKIRMISH, expected - hit_chance(atk.value, d3) / 100.0 * (damage(atk.value, d3) + bonus))
			if bonus > 0:
				_add_impact(side, CHARGE, chance / 100.0 * bonus)
			if f.cmd:
				_add_impact(side, "commander", expected)
			if f.tier == 1 and _screened(side, f):
				side.volley_expected += expected
				_add_impact(side, VOLLEY, expected * 0.5)
			if atk.parts.has(BERSERK) and not berserk.has(si):
				berserk[si] = f.name
			var hit := rng.randi_range(1, 100) <= chance
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

	var highlights := []
	for si in standing:
		if charge.has(si):
			highlights.append("%s %s charged home for %d extra damage." % [_poss(sides[si].name), sides[si].trait_units[CHARGE], charge[si]])
		if berserk.has(si):
			highlights.append("%s wounded %s went berserk (+%d attack)." % [_poss(sides[si].name), berserk[si], BERSERK_ATTACK])
	for si in standing:
		for f in sides[si].fighters:
			if f.alive and f.pending > 0:
				f.hp = maxi(0, f.hp - f.pending)
				if f.hp == 0:
					f.alive = false
					sides[si].lost.append(f.name)
					highlights.append("%s %s fell." % [_poss(sides[si].name), f.name])
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
	for si in standing:
		var side: Dictionary = sides[si]
		if _hp(side) == 0:
			side.destroyed = true
			side.out_round = round_no
			highlights.append("%s had no one left standing." % side.name)
		elif checks[si].lost_pct >= checks[si].break_pct:
			side.routed = true
			side.out_round = round_no
			side.rout_info = checks[si]
			highlights.append("%s broke and fled after losing %d%% of its strength (morale %d holds only to %d%%)." % [
				side.name, checks[si].lost_pct, checks[si].morale, checks[si].break_pct])

	var parts := []
	for si in standing:
		parts.append("%s dealt %d damage (%d of %d hits)" % [sides[si].name, dealt[si], hits[si], attacks[si]])
	var hp_after := {}
	for s in sides:
		hp_after[s.faction] = _hp(s)
	return {"round": round_no, "dealt": dealt.duplicate(), "highlights": highlights, "hp": hp_after,
		"line": "Round %d: %s.%s" % [round_no, ", ".join(parts), "" if highlights.is_empty() else " " + " ".join(highlights)]}


## Standing enemies `si` can reach: on each enemy side, those in its front-most occupied rank.
static func _targets(sides: Array, si: int, standing: Array) -> Array:
	var pool := []
	for oi in standing:
		if oi == si:
			continue
		var best := 99
		for f in sides[oi].fighters:
			if f.alive:
				best = mini(best, f.tier)
		for f in sides[oi].fighters:
			if f.alive and f.tier == best:
				pool.append(f)
	return pool


static func _screened(side: Dictionary, f: Dictionary) -> bool:
	for o in side.fighters:
		if o.alive and o.tier < f.tier:
			return true
	return false


static func _attack(f: Dictionary, side: Dictionary, env: Dictionary) -> Dictionary:
	var parts := {}
	if side.is_defender:
		var ta: int = TERRAIN.get(env.terrain, {}).get("attack", 0)
		if ta > 0:
			parts["terrain"] = ta
	if f.trait == BERSERK and f.hp < f.max:
		parts[BERSERK] = BERSERK_ATTACK
	if not f.cmd:
		for o in side.fighters:
			if o.alive and o.cmd and o.trait == PACK_LEADER:
				parts[PACK_LEADER] = PACK_LEADER_ATTACK
	var value: int = f.type.attack
	for p in parts:
		value += parts[p]
		side.triggers[p] = side.triggers.get(p, 0) + 1
	return {"value": value, "parts": parts}


static func _defense(t: Dictionary, tside: Dictionary, attacker: Dictionary, env: Dictionary) -> Dictionary:
	var parts := {}
	var skirmish := 0
	if tside.is_defender:
		var td: int = TERRAIN.get(env.terrain, {}).get("defense", 0)
		if td > 0:
			if attacker.trait == SKIRMISH:
				skirmish = td
			else:
				parts["terrain"] = td
		if env.fort:
			parts["fort"] = FORT_DEFENSE
	if t.trait == SHIELD_WALL:
		for o in tside.fighters:
			if o.alive and o != t:
				parts[SHIELD_WALL] = SHIELD_WALL_DEFENSE
				break
	var value: int = t.type.defense
	for p in parts:
		value += parts[p]
		tside.triggers[p] = tside.triggers.get(p, 0) + 1
	return {"value": value, "parts": parts, "skirmish": skirmish}


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
	var value: int = side.base_morale
	for p in parts:
		value += parts[p]
	return {"value": value, "parts": parts}


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
	return {"index": tied[r], "tie_break": "roll", "roll": r}


static func _add_impact(side: Dictionary, key: String, amount: float) -> void:
	side.impact[key] = side.impact.get(key, 0.0) + amount


static func _apply_losses(sides: Array, winner: String) -> void:
	for s in sides:
		if s.faction != winner:
			continue
		for f in s.fighters:
			var army: Army = f.army_ref
			if f.alive:
				f.unit.current_hp = f.hp
			elif f.cmd:
				army.commander = null
			else:
				army.units.erase(f.unit)


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
		var fled := ""
		if s.routed:
			fled = " and the other %d fled" % (s.count_start - lost_count)
		losses.append("%s lost %d of %d %s%s" % [s.name, lost_count, s.count_start,
			"fighter" if s.count_start == 1 else "fighters", fled])
		var rate := 0 if s.attacks == 0 else roundi(100.0 * s.hits / s.attacks)
		var avg := 0 if s.attacks == 0 else roundi(float(s.chance_sum) / s.attacks)
		side_reports.append({"faction": s.faction, "name": s.name, "armies": s.armies.duplicate(),
			"defender": s.is_defender, "fighters_start": s.count_start, "fighters_lost": lost_count,
			"lost": s.lost.duplicate(), "hp_start": s.hp_start, "hp_end": _hp(s), "routed": s.routed,
			"destroyed": s.destroyed, "out_round": s.out_round, "attacks": s.attacks, "hits": s.hits,
			"hit_rate": rate, "expected_hit_rate": avg,
			"hit_chance_range": [s.chance_min if s.attacks > 0 else 0, s.chance_max],
			"damage_dealt": s.dealt, "damage_expected": snappedf(s.expected, 0.1),
			"triggers": s.triggers.duplicate(), "morale_log": s.morale_log.duplicate(true),
			"base_morale": s.base_morale})
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
					var cname := _commander_name(s)
					c = "%s %s fought from the back line and dealt about %d damage" % [who, cname, dmg] if won \
						else "even though %s %s dealt about %d damage" % [who, cname, dmg]
					brief = "%s %s (+%d morale, hits hard)" % [who, cname, COMMANDER_MORALE]
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
					c = "%s %s ignored the %s cover, adding about %d damage" % [who, unit, env.terrain, dmg] if won \
						else "even though %s %s ignored the %s cover" % [who, unit, env.terrain]
				PACK_LEADER:
					c = "%s %s drove the pack (+%d attack to every unit), adding about %d damage" % [who, unit, PACK_LEADER_ATTACK, dmg] if won \
						else "even though %s %s drove the pack" % [who, unit]
				_:
					continue
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
				c = ("%s %s kept the line from breaking (+%d morale)" if held_by_it else "%s %s inspired the line (+%d morale)") % [
					_poss(s.name), cname, COMMANDER_MORALE if key == "commander" else INSPIRE_MORALE]
			else:
				c = "even though %s %s steadied the line" % [_poss(s.name), cname]
			out.append({"id": "morale_" + key, "side": si, "faction": s.faction, "impact": impact, "clause": c,
				"brief": "%s %s (%s)" % [_poss(s.name), cname, "+%d morale" % (COMMANDER_MORALE + (INSPIRE_MORALE if key == INSPIRE else 0))]})

	# Numbers: who brought the bigger force (hp x attack), as a share of the fight.
	var total_power := 0
	var total_hp := 0
	var strongest := 0
	for si in sides.size():
		total_power += sides[si].power
		total_hp += sides[si].hp_start
		if sides[si].power > sides[strongest].power:
			strongest = si
	if total_power > 0:
		var st: Dictionary = sides[strongest]
		var share := float(st.power) / total_power
		var even := 1.0 / sides.size()
		var impact := (share - even) * total_hp * 0.5
		var other := 0 if strongest != 0 else 1
		var o: Dictionary = sides[other]
		var force := "%d %s (%d hp) against %d (%d hp)" % [st.count_start, "fighter" if st.count_start == 1 else "fighters",
			st.hp_start, o.count_start, o.hp_start]
		out.append({"id": "numbers", "side": strongest, "faction": st.faction, "impact": impact,
			"clause": "%s brought the bigger force: %s" % [st.name, force] if strongest == wi
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


static func _side_with_trait(sides: Array, trait_id: String, not_side: int) -> int:
	for i in sides.size():
		if i != not_side and sides[i].trait_units.has(trait_id):
			return i
	return -1


static func _poss(name: String) -> String:
	return name + ("'" if name.ends_with("s") else "'s")


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)
