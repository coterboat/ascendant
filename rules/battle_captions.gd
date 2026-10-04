class_name BattleCaptions
## One caption per round of a battle being played back: what mattered in that round, in plain words (M3-2,
## #57; design/M3_BATTLES.md §4.8). Pure: it reads only the battle event log (BattleLog) and the battle's
## report (numbers.report), and every number in a caption is the log's or the report's own (a "worth" is
## a round_end.impact rounded to whole damage; "without it" is the resolver's break rule applied to the
## morale without that part). The same log and report always give the same captions. Renderer-agnostic:
## the 3D battle player and the 2D Simple view show the same lines.
##
##   BattleCaptions.for_round(log, report, n)   round n's caption: [LINE] (one or two lines)
##   BattleCaptions.all_rounds(log, report)     [{"round", "lines": [LINE]}] for every round fought
##   BattleCaptions.text(lines)                 the lines joined for a caption strip
##
## LINE = {"text", "rule", "factor" (a report factor id, or "" when none applies), "codex" (a RulesCodex
## entry), "side" (the side it is about, or -1)}. "factor" is set only when the report has a factor with
## that id, so the why panel can light that chip; "codex" always names an entry that exists.
##
## Line 1 is the first rule that matches (§4.8), "rule" says which:
##   "left"     a side broke or was wiped out ("Round 3: Thornmane Clans broke: it had lost 73%, and morale
##              7 holds only to 55%."); line 2 names a decisive part ("Fury (-2 morale) made it break a round
##              sooner."), Iron Discipline's last round, or, in a mutual rout, who kept the field
##   "ruler"    a ruler fell ("Round 2: King Corvane I fell in the front rank (started with 26 hp, 4 kept
##              power).")
##   "held"     a morale part kept a side from breaking ("Round 2: the Knight Captain's +2 morale kept Aurel
##              Crown in the fight: it has lost 62%, and holds to 70% (60% without it)."), or Iron
##              Discipline held it
##   "exposed"  a rank became reachable ("Round 3: Aurel Crown's Crossbowmen are exposed: only 1 front-rank
##              fighter stands in front of 2 in the second rank.")
##   "impact"   the biggest worth this round among the report's chosen factors ("Round 1: Aurel Crown's
##              Knights' charge added about 8 damage.")
##   "totals"   otherwise the round's totals ("Round 4: Aurel Crown dealt 12 (3 of 4 hits), Thornmane Clans
##              dealt 9 (2 of 3).")
## Line 2, when line 1 left it free: "round_cap" in the last round of a battle that ran to the round cap
## ("Nobody broke in 8 rounds, so the defender, Aurel Crown, holds its ground and wins."), otherwise "luck", when a side's damage this round beat what was expected by at
## least LUCK_MIN and by at least LUCK_SHARE of it ("Lucky round for Aurel Crown: 20 damage where about 12
## was expected.").
## A round the log doesn't hold (a log cut short at BattleLog.MAX_EVENTS) gets rule "cut": "Round 5: the
## playback log stops here; the battle report has the rest."

const LUCK_MIN := 5.0
const LUCK_SHARE := 0.25
## The smallest worth (in damage, rounded) a factor needs to be a round's caption.
const MIN_WORTH := 1


## Round `n`'s caption lines.
static func for_round(battle_log: Dictionary, report: Dictionary, n: int) -> Array:
	return _caption(battle_log, report, _rounds(battle_log), n)


## Every round's caption: [{"round", "lines"}], for each round fought (the report's count when the log was
## cut short, so every round has one).
static func all_rounds(battle_log: Dictionary, report: Dictionary) -> Array:
	var info := _rounds(battle_log)
	var count: int = info.size() - 1
	var end := BattleMoments._end(battle_log)
	if not end.is_empty():
		count = int(end.rounds)
	elif not report.is_empty():
		count = maxi(count, int(report.get("rounds_fought", 0)))
	var out := []
	for n in range(1, count + 1):
		out.append({"round": n, "lines": _caption(battle_log, report, info, n)})
	return out


## The caption lines' text, one line each.
static func text(lines: Array) -> String:
	var out := []
	for l in lines:
		out.append(String(l.text))
	return "\n".join(out)


# --- the rules ----------------------------------------------------------------------------------------

static func _caption(battle_log: Dictionary, report: Dictionary, info: Array, n: int) -> Array:
	if n < 1 or n >= info.size() or info[n].round_end < 0:
		return [_mk("Round %d: the playback log stops here; the battle report has the rest." % n, "cut", "", "battle_playback", -1, report)]
	var r: Dictionary = info[n]
	var lines := []
	var line2_used := false
	var left := _left(battle_log, report, r, n)
	if not left.is_empty():
		lines.append(left[0])
		if left.size() > 1:
			lines.append(left[1])
			line2_used = true
	if lines.is_empty():
		var l := _ruler_fell(battle_log, report, r, n)
		if l.is_empty():
			l = _held(battle_log, report, r, n)
		if l.is_empty():
			l = _exposed(battle_log, report, info, n)
		if l.is_empty():
			l = _impact(battle_log, report, r, n)
		if l.is_empty():
			l = _totals(battle_log, report, r, n)
		lines.append(l)
	if not line2_used:
		var cap := _round_cap(battle_log, report, n)
		if cap.is_empty():
			cap = _luck(battle_log, report, r)
		if not cap.is_empty():
			lines.append(cap)
	return lines


## Line 2 in the last round of a battle that ran to the round cap: who won, and why.
static func _round_cap(battle_log: Dictionary, report: Dictionary, n: int) -> Dictionary:
	var end := BattleMoments._end(battle_log)
	if end.is_empty() or end.how != "round_cap" or int(end.rounds) != n:
		return {}
	var w := int(end.winner)
	var name := String(battle_log.sides[w].name)
	var text := ""
	if end.tie_break == "defender":
		text = "Nobody broke in %d rounds, so the defender, %s, holds its ground and wins." % [n, name]
	else:
		text = "Nobody broke in %d rounds, so %s, with more of its strength left, wins." % [n, name]
	return _mk(text, "round_cap", "round_cap", "battle_round_cap", w, report)


## Rule 1: a side broke or had no one left this round.
static func _left(battle_log: Dictionary, report: Dictionary, r: Dictionary, n: int) -> Array:
	var sides: Array = battle_log.sides
	var routs: Array = r.routs
	if routs.is_empty():
		return []
	if routs.size() > 1:
		# A mutual rout (or several sides leaving at once).
		var parts := []
		var least := -1
		for x in routs:
			var si := int(x.side)
			var check: Dictionary = r.morale.get(si, {})
			if x.t == "destroyed" or check.is_empty():
				parts.append("%s had no one left" % sides[si].name)
			else:
				parts.append("%s had lost %d%% (morale %d holds only to %d%%)" % [sides[si].name, int(check.lost_pct), int(check.morale),
					int(check.break_pct)])
		var end := BattleMoments._end(battle_log)
		var first := _mk("Round %d: %s broke: %s." % [n, "both sides" if routs.size() == 2 else "every side", ", ".join(parts)], "left", "rout",
			"battle_morale", -1, report)
		if not end.is_empty() and end.how == "mutual":
			var w := int(end.winner)
			var wc: Dictionary = r.morale.get(w, {})
			var keeps := "%s keeps the field: it had lost the least%s." % [sides[w].name,
				(" (%d%%)" % int(wc.lost_pct)) if not wc.is_empty() else ""]
			return [first, _mk(keeps, "left", "rout", "battle_rounds", w, report)]
		return [first]
	var x: Dictionary = routs[0]
	var si := int(x.side)
	var name := String(sides[si].name)
	if x.t == "destroyed":
		return [_mk("Round %d: %s had no one left standing." % [n, name], "left", "", "battle_rounds", si, report)]
	var check: Dictionary = r.morale.get(si, {})
	if check.is_empty():
		return [_mk("Round %d: %s broke and fled." % [n, name], "left", "rout", "battle_morale", si, report)]
	var out := [_mk("Round %d: %s broke: it had lost %d%%, and morale %d holds only to %d%%." % [n, name, int(check.lost_pct),
		int(check.morale), int(check.break_pct)], "left", "rout", "battle_morale", si, report)]
	for p in check.decisive:
		var key := String(p)
		var factor := "ability_dread" if key == AutoBattleResolver.DREAD else key
		var what := "Dread" if key == AutoBattleResolver.DREAD else key
		out.append(_mk("%s (%d morale) made it break a round sooner." % [what, int(check.parts[p])], "left", factor,
			BattleExplain.factor_entry(factor), si, report))
		break
	if out.size() == 1 and check.iron_last_round:
		out.append(_mk("Iron Discipline holds a line only until the last round.", "left",
			AutoBattleResolver.MANDATE_PREFIX + RulerRules.IRON_DISCIPLINE, "mandate_iron_discipline", si, report))
	return out


## Rule 2: a ruler fell this round.
static func _ruler_fell(battle_log: Dictionary, report: Dictionary, r: Dictionary, n: int) -> Dictionary:
	for fid in r.deaths:
		var f: Dictionary = battle_log.fighters[int(fid)]
		if f.role != "ruler":
			continue
		var info: Dictionary = f.get("ruler", {})
		var rank := "in the front rank" if String(info.get("rank", "front")) == "front" else "in the second rank"
		return _mk("Round %d: %s fell %s (started with %d hp, %d kept power)." % [n, String(f.name), rank, int(f.hp),
			int(info.get("kept_power", 0))], "ruler", AutoBattleResolver.RULER, "ruler_in_battle", int(f.side), report)
	return {}


## Rule 3: a morale part kept a side from breaking this round (or Iron Discipline held it).
static func _held(battle_log: Dictionary, report: Dictionary, r: Dictionary, n: int) -> Dictionary:
	var sides: Array = battle_log.sides
	var keys: Array = r.morale.keys()
	keys.sort()
	for si in keys:
		var c: Dictionary = r.morale[si]
		var name := String(sides[si].name)
		if c.result == "held":
			var holder := "its commander"
			if int(c.held_by) >= 0:
				holder = "its " + BattleExplain._bare(String(battle_log.fighters[int(c.held_by)].name))
			return _mk("Round %d: Iron Discipline held %s line while %s stood: it had lost %d%%, past the %d%% where morale %d breaks." % [
				n, BattleExplain.poss(name), holder, int(c.lost_pct), int(c.break_pct), int(c.morale)], "held",
				AutoBattleResolver.MANDATE_PREFIX + RulerRules.IRON_DISCIPLINE, "mandate_iron_discipline", si, report)
		if c.result != "holds" or c.decisive.is_empty():
			continue
		var from_cmd: bool = c.decisive.has("commander") or c.decisive.has(AutoBattleResolver.INSPIRE)
		var amount := 0
		var who := ""
		var factor := ""
		if from_cmd:
			for p in ["commander", AutoBattleResolver.INSPIRE]:
				amount += int(c.parts.get(p, 0))
			who = _commanders(battle_log, si, r.standing_after)
			factor = "morale_commander" if c.decisive.has("commander") else "morale_" + AutoBattleResolver.INSPIRE
			if not _has_factor(report, factor) and _has_factor(report, "morale_" + AutoBattleResolver.INSPIRE):
				factor = "morale_" + AutoBattleResolver.INSPIRE
		elif c.decisive.has(AutoBattleResolver.RULER):
			amount = int(c.parts[AutoBattleResolver.RULER])
			who = _ruler_name(battle_log, si)
			factor = "morale_" + AutoBattleResolver.RULER
		else:
			continue
		var without := AutoBattleResolver.break_pct(int(c.morale) - amount)
		return _mk("Round %d: %s +%d morale kept %s in the fight: it has lost %d%%, and holds to %d%% (%d%% without it)." % [n,
			BattleExplain.poss(who), amount, name, int(c.lost_pct), int(c.break_pct), without], "held", factor,
			BattleExplain.factor_entry(factor), si, report)
	return {}


## Rule 4: a rank became reachable for ordinary attackers this round.
static func _exposed(battle_log: Dictionary, report: Dictionary, info: Array, n: int) -> Dictionary:
	if n < 2:
		return {}
	var now: Dictionary = info[n].reach
	var was: Dictionary = info[n - 1].reach
	var keys: Array = now.keys()
	keys.sort()
	for si in keys:
		if not was.has(si):
			continue
		var counts: Array = info[n].counts[si]
		for tier in [1, 2]:
			if not now[si].has(tier) or was[si].has(tier):
				continue
			var names := _tier_names(battle_log, si, tier, info[n].alive)
			if names.is_empty():
				continue
			var side_name := String(battle_log.sides[si].name)
			var who := "%s %s" % [BattleExplain.poss(side_name), names]
			var plural := names.ends_with("s") or names.ends_with("men") or names.contains(" and ")
			var are := "are" if plural else "is"
			var why := ""
			if tier == 2:
				why = "no unit stands in front of %s" % ("them" if plural else "it")
			elif counts[0] == 0:
				why = "no front-rank fighter stands in front of %s" % ("them" if plural else "it")
			else:
				why = "only %d front-rank %s in front of %d in the second rank" % [counts[0], "fighter stands" if counts[0] == 1 else "fighters stand",
					counts[1]]
			var codex := "battle_commanders" if tier == 2 else ("trait_volley" if _tier_has_trait(battle_log, si, 1, AutoBattleResolver.VOLLEY) else "ruler_rank")
			return _mk("Round %d: %s %s exposed: %s." % [n, who, are, why], "exposed", "", codex, si, report)
	return {}


## Rule 5: the round's biggest worth among the report's chosen factors.
static func _impact(battle_log: Dictionary, report: Dictionary, r: Dictionary, n: int) -> Dictionary:
	var re: Dictionary = r.end_event
	var best := {}
	for f in report.get("factors", []):
		var id := String(f.get("id", ""))
		if BattleLog.NON_IMPACT_FACTORS.has(id):
			continue
		var si := _side_of(battle_log, String(f.get("faction", "")))
		if si < 0:
			continue
		var worth := float(re.impact[si].get(id, 0.0))
		if roundi(worth) < MIN_WORTH:
			continue
		if best.is_empty() or worth > float(best.worth):
			best = {"id": id, "side": si, "worth": worth}
	if best.is_empty():
		return {}
	var phrase := _worth_phrase(battle_log, String(best.id), int(best.side), roundi(float(best.worth)))
	if phrase.is_empty():
		return {}
	return _mk("Round %d: %s." % [n, phrase], "impact", String(best.id), _codex_or(BattleExplain.factor_entry(String(best.id)), "battle_rounds"),
		int(best.side), report)


## Rule 6: the round's totals.
static func _totals(battle_log: Dictionary, report: Dictionary, r: Dictionary, n: int) -> Dictionary:
	var re: Dictionary = r.end_event
	var parts := []
	for si in battle_log.sides.size():
		if int(re.attacks[si]) == 0:
			continue
		var name := String(battle_log.sides[si].name)
		parts.append("%s dealt %d (%d of %d %s)" % [name, int(re.dealt[si]), int(re.hits[si]), int(re.attacks[si]),
			"hit" if int(re.attacks[si]) == 1 else "hits"])
	if parts.is_empty():
		return _mk("Round %d: nobody could attack." % n, "totals", "", "battle_rounds", -1, report)
	return _mk("Round %d: %s." % [n, ", ".join(parts)], "totals", "", "battle_hit_chance", -1, report)


## Line 2: a lucky round.
static func _luck(battle_log: Dictionary, report: Dictionary, r: Dictionary) -> Dictionary:
	var re: Dictionary = r.end_event
	var best := -1
	var best_diff := 0.0
	for si in battle_log.sides.size():
		var dealt := float(re.dealt[si])
		var expected := float(re.expected[si])
		var diff := dealt - expected
		if diff >= LUCK_MIN and diff >= LUCK_SHARE * expected and (best < 0 or diff > best_diff):
			best = si
			best_diff = diff
	if best < 0:
		return {}
	return _mk("Lucky round for %s: %d damage where about %d was expected." % [battle_log.sides[best].name, int(re.dealt[best]),
		roundi(float(re.expected[best]))], "luck", "luck", "battle_hit_chance", best, report)


# --- words --------------------------------------------------------------------------------------------

## A factor's worth this round in words, without the "Round n: ".
static func _worth_phrase(battle_log: Dictionary, id: String, si: int, worth: int) -> String:
	var side := String(battle_log.sides[si].name)
	var who := BattleExplain.poss(side)
	match id:
		"terrain":
			return "the %s was worth about %d damage to the defending %s" % [String(battle_log.terrain), worth, side]
		"fort":
			return "the fort was worth about %d damage to the defending %s" % [worth, side]
		AutoBattleResolver.WALLS:  # M3c
			var sg: Dictionary = battle_log.get("siege", {})
			return "the walls (%d of %d) were worth about %d damage to the defending %s" % [int(sg.get("walls", 0)), int(sg.get("walls_max", 0)),
				worth, side]
		AutoBattleResolver.COVER:
			return "the cover of the walls was worth about %d damage to %s garrison" % [worth, who]
		"commander":
			return "%s %s dealt about %d damage more than the same gold in ordinary units would have" % [who,
				BattleExplain._bare(_commanders(battle_log, si, [])), worth]
		AutoBattleResolver.RULER:
			return "%s dealt about %d damage" % [_ruler_name(battle_log, si), worth]
		AutoBattleResolver.CHARGE:
			return "%s %s charge added about %d damage" % [who, BattleExplain.poss(_trait_unit(battle_log, si, id)), worth]
		AutoBattleResolver.SHIELD_WALL:
			return "%s %s shield wall turned aside about %d damage" % [who, BattleExplain.poss(_trait_unit(battle_log, si, id)), worth]
		AutoBattleResolver.VOLLEY:
			return "%s %s shot from out of reach, worth about %d damage" % [who, _trait_unit(battle_log, si, id), worth]
		AutoBattleResolver.BERSERK:
			return "%s berserk %s added about %d damage" % [who, _trait_unit(battle_log, si, id), worth]
		AutoBattleResolver.SKIRMISH:
			return "%s %s skirmished past the front, worth about %d damage" % [who, _trait_unit(battle_log, si, id), worth]
		AutoBattleResolver.PACK_LEADER:
			return "%s %s drove the pack (+%d attack to every unit), adding about %d damage" % [who, _trait_unit(battle_log, si, id),
				AutoBattleResolver.PACK_LEADER_ATTACK, worth]
		# M4-3: the transformations' traits.
		AutoBattleResolver.WINGS:
			return "%s %s flew over the line, worth about %d damage" % [who, _trait_unit(battle_log, si, id), worth]
		AutoBattleResolver.IRON_HIDE:
			return "%s %s iron hide turned aside about %d damage" % [who, BattleExplain.poss(_trait_unit(battle_log, si, id)), worth]
		AutoBattleResolver.ROOTED:
			return "%s rooted %s turned aside about %d damage" % [who, _trait_unit(battle_log, si, id), worth]
		AutoBattleResolver.LIFEDRINKER:
			return "%s %s drank back %d hp" % [who, _trait_unit(battle_log, si, id), worth]
	if id.begins_with(AutoBattleResolver.PATH_PREFIX):
		return "%s was worth about %d damage to %s" % [AscensionRules.part_name(id), worth, side]  # M4-3: a path part
	if id.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return "%s was worth about %d damage to %s" % [RulerRules.mandate_name(id.trim_prefix(AutoBattleResolver.MANDATE_PREFIX)), worth, side]
	return ""


## The name of the first fighter of side `si` with trait `trait_id` ("Knights"), or the trait's name.
static func _trait_unit(battle_log: Dictionary, si: int, trait_id: String) -> String:
	for fid in battle_log.sides[si].fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		if f.trait == trait_id:
			return BattleExplain._bare(String(f.name))
	return trait_id


static func _tier_has_trait(battle_log: Dictionary, si: int, tier: int, trait_id: String) -> bool:
	for fid in battle_log.sides[si].fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		if int(f.tier) == tier and f.trait == trait_id:
			return true
	return false


## The standing fighters of side `si` in `tier` by name: "Crossbowmen", "Crossbowmen and the Ever-Regent".
static func _tier_names(battle_log: Dictionary, si: int, tier: int, alive: Array) -> String:
	var names := []
	for fid in battle_log.sides[si].fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		if int(f.tier) != tier or not alive[int(fid)]:
			continue
		var nm := String(f.name) if f.role == "ruler" else BattleExplain._bare(String(f.name))
		if not names.has(nm):
			names.append(nm)
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names.back()


## "the Knight Captain" (its one commander standing, or its first), or "its commanders" for several.
static func _commanders(battle_log: Dictionary, si: int, standing: Array) -> String:
	var names := []
	for fid in battle_log.sides[si].fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		if f.role == "commander" and (standing.is_empty() or standing[int(fid)]):
			names.append(String(f.name))
	if names.size() == 1:
		return BattleExplain._the(BattleExplain._bare(names[0]))
	if names.is_empty():
		return "its commander"
	return "%s commanders" % BattleExplain.poss(String(battle_log.sides[si].name))


static func _ruler_name(battle_log: Dictionary, si: int) -> String:
	for fid in battle_log.sides[si].fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		if f.role == "ruler":
			return String(f.name)
	return "its ruler"


static func _side_of(battle_log: Dictionary, faction: String) -> int:
	for s in battle_log.sides:
		if String(s.faction) == faction:
			return int(s.index)
	return -1


static func _has_factor(report: Dictionary, id: String) -> bool:
	for f in report.get("all_factors", []):
		if String(f.get("id", "")) == id:
			return true
	return false


static func _codex_or(key: String, fallback: String) -> String:
	return key if RulesCodex.ENTRIES.has(key) else fallback


static func _mk(text_value: String, rule: String, factor: String, codex: String, si: int, report: Dictionary) -> Dictionary:
	return {"text": text_value, "rule": rule, "factor": factor if not factor.is_empty() and _has_factor(report, factor) else "",
		"codex": _codex_or(codex, "battle_rounds"), "side": si}


# --- one pass over the log ----------------------------------------------------------------------------

## Per round (index n; index 0 unused): {"start" (round event index), "round_end" (-1 if missing),
## "end_event", "morale": {side: morale event}, "routs": [rout / destroyed events], "deaths": [fighter ids],
## "reach": {side: [ordinary tiers]}, "counts": {side: [front, second, back] standing at the round's start},
## "alive": [bool per fighter at the round's start], "standing_after": [bool per fighter after the round]}.
static func _rounds(battle_log: Dictionary) -> Array:
	var out := [{}]
	var fighters: Array = battle_log.get("fighters", [])
	var alive := []
	for f in fighters:
		alive.append(int(f.hp) > 0)
	var cur := {}
	for i in battle_log.get("events", []).size():
		var e: Dictionary = battle_log.events[i]
		match e.t:
			"round":
				cur = {"start": i, "round_end": -1, "end_event": {}, "morale": {}, "routs": [], "deaths": [], "reach": {}, "counts": {},
					"alive": alive.duplicate(), "standing_after": []}
				for entry in e.reach:
					var si := int(entry.side)
					cur.reach[si] = BattleLog._ints(entry.tiers)
					var counts := [0, 0, 0]
					for fid in battle_log.sides[si].fighters:
						if alive[int(fid)]:
							counts[int(fighters[int(fid)].tier)] += 1
					cur.counts[si] = counts
				out.append(cur)
			"death":
				alive[int(e.f)] = false
				if not cur.is_empty():
					cur.deaths.append(int(e.f))
			"morale":
				if not cur.is_empty():
					cur.morale[int(e.side)] = e
			"rout", "destroyed":
				if not cur.is_empty():
					cur.routs.append(e)
			"round_end":
				if not cur.is_empty():
					cur.round_end = i
					cur.end_event = e
					cur.standing_after = alive.duplicate()
	return out
