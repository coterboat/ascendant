class_name BattleExplain
## Plain-language explanations of a battle being played back (M3-2, #57; design/M3_BATTLES.md §4.7, §5.4).
## Pure: it reads only a battle event log (BattleLog), its BattleTimeline and the resolver's constants
## (HIT_PER_POINT, MIN_HIT, MAX_HIT, MIN_DAMAGE, the break rule), and never recomputes a number with other
## rules: every hit chance, damage, morale and break percentage shown is the log's own, and the lines
## that explain it add up to it. Renderer-agnostic: the 3D battle player and the 2D Simple view both
## show these, so nothing here knows about screens, positions or nodes.
##
##   BattleExplain.explain_attack(log, i)         attack event i: hit chance, damage, attack and defense
##                                                as Breakdown-style dictionaries, the roll and the target
##   BattleExplain.explain_fighter(tl, fid, i)    hovering fighter fid at the state before event i (§5.4):
##                                                who, hit points, what it is doing, its (last) attack, who
##                                                can reach it, what it gives, its statuses
##   BattleExplain.explain_morale(log, i)         morale event i: morale and break % as breakdowns, result
##   BattleExplain.morale_change(log, i)          the notch tag when morale changed (§4.7)
##   BattleExplain.break_hp(hp_start, break_pct)  the hp at or below which a side breaks (§4.7)
##   BattleExplain.side_strength(log, state, si)  a side's strength bar: hp, pending, morale, break line
##
## A Breakdown-style dictionary is {"title", "description", "lines": [{"label", "value", "note"}],
## "total_label", "total", "codex"} with total = the sum of the line values (rules/breakdown.gd), ready for
## TooltipText.from_breakdown. Every text names fighters and sides by their player-facing names, never by
## log ids, and every result carries a "codex" key naming a RulesCodex entry.

## Player-facing names of the morale parts in a morale check (the same words as the battle report viewer).
const MORALE_PART_NAMES := {
	"commander": "Its commander still standing",
	"Inspire": "Inspire (its commander's trait)",
	"Fury": "Fury (enemy War Bears roaring)",
	"ruler": "Its ruler still standing",
	"Dread": "Dread (the enemy's Great Thornmane)",
}
## The RulesCodex entry behind each report factor id that isn't a trait or a mandate (the battle report
## viewer's FACTOR_ENTRIES; tests/test_battle_moments.gd checks the two agree).
const FACTOR_ENTRIES := {
	"terrain": "battle_terrain",
	"fort": "battle_terrain",
	"commander": "battle_commanders",
	"morale_commander": "battle_morale",
	"morale_Inspire": "trait_inspire",
	"rout": "battle_morale",
	"numbers": "battle_rounds",
	"luck": "battle_hit_chance",
	"round_cap": "battle_round_cap",
	"ruler": "ruler_in_battle",
	"morale_ruler": "ruler_in_battle",
	"ability_dread": "ability_dread",
}
const RANK_WORDS := ["front rank", "second rank", "back line"]


# --- attacks ------------------------------------------------------------------------------------------

## Attack event `i` explained from its own numbers: {"title", "attacker", "target", "round", "hit" (bool),
## "chance": Breakdown (its lines sum to the attack's chance: base, Drilled Ranks, 4 x (attack - defense),
## the clamp line when the 30-90% limits applied), "damage": Breakdown (half the attack rounded up, minus a
## quarter of the defense rounded down, the minimum line, each bonus such as Charge; sums to the damage
## on a hit), "attack" and "defense": Breakdowns (the fighter's own number plus each part), "roll" (text),
## "target_text", "reach" (text), "summary" (one line), "codex"}. {} when event i is not an attack.
static func explain_attack(battle_log: Dictionary, i: int) -> Dictionary:
	var events: Array = battle_log.get("events", [])
	if i < 0 or i >= events.size() or events[i].t != "attack":
		return {}
	var e: Dictionary = events[i]
	var a: Dictionary = battle_log.fighters[int(e.by)]
	var t: Dictionary = battle_log.fighters[int(e.to)]
	var atk := int(e.attack.value)
	var dfn := int(e.defense.value)
	var base := int(e.base_hit)
	var chance := int(e.chance)
	var damage := int(e.damage)

	# Hit chance: base + 4 x (attack - defense), clamped to 30..90 (AutoBattleResolver.hit_chance).
	var lines := [_line("Base hit chance", AutoBattleResolver.BASE_HIT, "every attack starts here")]
	if base != AutoBattleResolver.BASE_HIT:
		lines.append(_line(RulerRules.mandate_name(RulerRules.DRILLED_RANKS), base - AutoBattleResolver.BASE_HIT,
			"its side's base hit chance is %d%%" % base))
	var diff := atk - dfn
	var per := AutoBattleResolver.HIT_PER_POINT
	lines.append(_line("%d x (attack %d - defense %d)" % [per, atk, dfn], per * diff,
		"%d%% for every point of attack %s the target's defense" % [per, "below" if diff < 0 else "above"]))
	var raw := base + per * diff
	if raw > AutoBattleResolver.MAX_HIT:
		lines.append(_line("Never above %d%%" % AutoBattleResolver.MAX_HIT, AutoBattleResolver.MAX_HIT - raw, "the highest a hit chance goes"))
	elif raw < AutoBattleResolver.MIN_HIT:
		lines.append(_line("Never below %d%%" % AutoBattleResolver.MIN_HIT, AutoBattleResolver.MIN_HIT - raw, "the lowest a hit chance goes"))
	var formula := "%d%% = base %d + %d x (attack %d - defense %d)" % [chance, base, per, atk, dfn]
	if raw != chance:
		formula += ", kept within %d-%d%%" % [AutoBattleResolver.MIN_HIT, AutoBattleResolver.MAX_HIT]
	var chance_bd := _make("Hit chance of %s against %s" % [_bare(a.name), _bare(t.name)], formula, lines, "Hit chance", chance,
		"battle_hit_chance")

	# Damage on a hit: ceil(attack / 2) - floor(defense / 4), at least 1, plus the bonus (Charge in round 1).
	var half := ceili(atk * 0.5)
	var quarter := floori(dfn * 0.25)
	var dlines := [_line("Half of attack %d, rounded up" % atk, half, ""), _line("A quarter of defense %d, rounded down" % dfn, -quarter, "")]
	if half - quarter < AutoBattleResolver.MIN_DAMAGE:
		dlines.append(_line("At least %d" % AutoBattleResolver.MIN_DAMAGE, AutoBattleResolver.MIN_DAMAGE - (half - quarter),
			"every hit deals at least %d" % AutoBattleResolver.MIN_DAMAGE))
	var dtext := "%d = half of attack %d, rounded up (%d) - a quarter of defense %d, rounded down (%d)" % [damage, atk, half, dfn, quarter]
	if half - quarter < AutoBattleResolver.MIN_DAMAGE:
		dtext += ", raised to the minimum of %d" % AutoBattleResolver.MIN_DAMAGE
	for b in e.bonus:
		var v := int(e.bonus[b])
		var note := "round %d only" % int(e.n)
		if String(b) == AutoBattleResolver.CHARGE:
			note = "Charge: every hit in round 1" + (" (less in a forest)" if v == AutoBattleResolver.CHARGE_DAMAGE_FOREST and battle_log.get("terrain", "") == "forest" else "")
		dlines.append(_line(String(b), v, note))
		dtext += ", + %s %d" % [String(b), v]
	var damage_bd := _make("Damage of %s on a hit" % _bare(a.name), dtext, dlines, "Damage on a hit", damage, "battle_hit_chance")

	var side_a: Dictionary = battle_log.sides[int(a.side)]
	var side_t: Dictionary = battle_log.sides[int(t.side)]
	var attack_bd := _stat_breakdown(battle_log, e.attack, a, "Attack", side_a)
	var defense_bd := _stat_breakdown(battle_log, e.defense, t, "Defense", side_t)
	var roll := "Rolled %d of 100: %s (%d or less hits)." % [int(e.roll), "a hit" if e.hit else "a miss", chance]
	var target_text := "attacking %s, %s" % [_label(battle_log, int(e.to)), _pool_words(int(e.pool))]
	var reach := _reach_words(String(e.reach), bool(e.screened))
	var summary := "Round %d: %s %s %s %s: %d%% to hit, rolled %d, %s." % [int(e.n), poss(side_a.name), _bare(a.name),
		"hit" if e.hit else "missed", _label(battle_log, int(e.to)), chance, int(e.roll),
		("%d damage" % damage) if e.hit else "no damage"]
	return {"title": "%s attacking %s" % [_bare(a.name), _bare(t.name)], "attacker": int(e.by), "target": int(e.to), "round": int(e.n),
		"hit": bool(e.hit), "chance": chance_bd, "damage": damage_bd, "attack": attack_bd, "defense": defense_bd, "roll": roll,
		"target_text": target_text, "reach": reach, "summary": summary, "codex": "battle_hit_chance"}


## An attack's attack or defense value as a breakdown: the fighter's own number, then each part.
static func _stat_breakdown(battle_log: Dictionary, stat: Dictionary, f: Dictionary, label: String, side: Dictionary) -> Dictionary:
	var lines := [_line(_bare(f.name), int(stat.base), "its own %s" % label.to_lower())]
	var words := ["%s %d" % [_bare(f.name), int(stat.base)]]
	for p in stat.parts:
		var v := int(stat.parts[p])
		lines.append(_line(part_name(battle_log, String(p)), v, _part_note(battle_log, String(p))))
		words.append("%s %d" % [part_name(battle_log, String(p)), v])
	var who := "%s %s" % [poss(_bare(f.name)), label.to_lower()]
	return _make("%s of %s (%s)" % [label, _bare(f.name), side.name], "%s %d = %s" % [_cap(who), int(stat.value), " + ".join(words)], lines,
		label, int(stat.value), "stat_attack" if label == "Attack" else "stat_defense")


# --- fighters -----------------------------------------------------------------------------------------

## Hovering fighter `fid` at the state before event `i` of the timeline's log (§5.4). `state` may be passed
## when the caller already has tl.state_at(i). Returns {"fighter", "event", "title" (who), "who", "hp" (text),
## "hp_value", "pending", "doing" (text), "attack": explain_attack of its current or last attack ({} when
## it has none), "attack_event" (-1 when none), "reach" (text), "gives" ([text]), "statuses" ([text]),
## "lines" ([text], the whole tooltip in §5.4's order), "codex"}.
static func explain_fighter(tl: BattleTimeline, fid: int, i: int, state: Dictionary = {}) -> Dictionary:
	var battle_log := tl.battle_log()
	var events: Array = battle_log.events
	i = clampi(i, 0, events.size())
	if state.is_empty():
		state = tl.state_at(i)
	var f: Dictionary = battle_log.fighters[fid]
	var fs: Dictionary = state.fighters[fid]
	var side: Dictionary = battle_log.sides[int(f.side)]
	var round_no := int(state.round)

	var who := "%s · %s · %s" % [_cap(String(f.name)), side.name, RANK_WORDS[int(f.tier)]]
	if f.role == "ruler":
		who += " · ruler, %d kept power" % int(f.get("ruler", {}).get("kept_power", 0))
	elif f.role == "commander":
		who += " · commander"
	var hp_text := "%d of %d hp" % [int(fs.hp), int(f.max_hp)]
	if int(fs.pending) > 0:
		hp_text += " (%d damage lands at the end of this round)" % int(fs.pending)

	# Its attacks: this round's (any display order is truthful, so during the attacks beat it is "now"),
	# and its last one before event i.
	var current := -1
	var last := -1
	var made := 0
	var hits := 0
	var dealt := 0
	for k in events.size():
		var e: Dictionary = events[k]
		if e.t != "attack" or int(e.by) != fid:
			continue
		if k < i:
			last = k
			made += 1
			if e.hit:
				hits += 1
				dealt += int(e.damage)
		if int(e.n) == round_no and state.beat == "attacks":
			current = k
	var doing := ""
	var died_round := _death_round(battle_log, fid, i)
	if not fs.alive:
		doing = "fell in round %d after %d %s (%d %s, %d damage)" % [died_round, made, "attack" if made == 1 else "attacks", hits,
			"hit" if hits == 1 else "hits", dealt]
	elif fs.fled:
		doing = "fled, and was lost with its army" if fs.lost else "fled"
	elif fs.lost:
		doing = "lost with its army: its side lost the battle"
	elif int(state.winner) >= 0:
		doing = "won, still standing" if int(state.winner) == int(f.side) else "still standing, but its side lost"
	elif current >= 0:
		var ce: Dictionary = events[current]
		doing = "attacking %s, %s" % [_label(battle_log, int(ce.to)), _pool_words(int(ce.pool))]
	elif i >= events.size() and battle_log.get("truncated", false):
		doing = "the playback stops here: this battle's log was cut short"
	else:
		doing = "waiting for the next round"
	var shown := current if current >= 0 else last
	var attack := explain_attack(battle_log, shown) if shown >= 0 else {}

	var reach := _fighter_reach(battle_log, state, fid)
	var gives := _gives(battle_log, f)
	var statuses := _status_words(battle_log, tl.statuses(state, fid))
	var lines := [who, hp_text, _cap(doing) + "."]
	if not attack.is_empty():
		var head := "This attack:" if current >= 0 else "Its last attack (round %d):" % int(attack.round)
		lines.append(head)
		lines.append("  Hit chance %s" % attack.chance.description)
		lines.append("    %s" % attack.attack.description)
		lines.append("    %s" % attack.defense.description)
		lines.append("  Damage on a hit %s" % attack.damage.description)
		lines.append("  " + String(attack.roll))
	lines.append("Who can reach it: %s." % reach)
	for g in gives:
		lines.append(_cap(g) + ".")
	for s in statuses:
		lines.append(_cap(s) + ".")
	var codex := fighter_codex(f)
	lines.append("F1 or right-click: the codex (%s)." % RulesCodex.entry(codex).get("title", ""))
	return {"fighter": fid, "event": i, "title": who, "who": who, "hp": hp_text, "hp_value": int(fs.hp), "pending": int(fs.pending),
		"doing": doing, "attack": attack, "attack_event": shown, "reach": reach, "gives": gives, "statuses": statuses, "lines": lines,
		"codex": codex}


## The RulesCodex entry for a fighter: its trait's, a ruler's or a commander's, otherwise units.
static func fighter_codex(f: Dictionary) -> String:
	if f.role == "ruler":
		return "ruler_in_battle"
	if not String(f.trait).is_empty():
		var key := AutoBattleResolver.codex_id_for_trait(String(f.trait))
		if RulesCodex.ENTRIES.has(key):
			return key
	return "battle_commanders" if f.role == "commander" else "units"


## Who can reach fighter `fid` this round (§5.4 line 7), from the round's reach (or, before round 1, the
## target rule applied to the standing fighters).
static func _fighter_reach(battle_log: Dictionary, state: Dictionary, fid: int) -> String:
	var f: Dictionary = battle_log.fighters[fid]
	var si := int(f.side)
	var tier := int(f.tier)
	var counts := standing_counts(battle_log, state, si)
	var tiers := []
	var skirmish := []
	var found := false
	for entry in state.reach:
		if int(entry.side) == si:
			tiers = BattleLog._ints(entry.tiers)
			skirmish = BattleLog._ints(entry.skirmish_tiers)
			found = true
	if not found:
		tiers = AutoBattleResolver._reachable_tiers(counts, false)
		skirmish = AutoBattleResolver._reachable_tiers(counts, true)
	if tiers.has(tier):
		if tier == 1 and counts[0] > 0:
			return "every enemy (second rank, exposed: only %d front-rank %s in front of %d in its rank)" % [counts[0],
				"fighter stands" if counts[0] == 1 else "fighters stand", counts[1]]
		return "every enemy (%s)" % RANK_WORDS[tier]
	if skirmish.has(tier):
		return "only enemies with Skirmish: %d front-rank %s the %d in its rank" % [counts[0], "fighter shields" if counts[0] == 1 else "fighters shield",
			counts[1]]
	return "nobody yet: units still stand in front of it"


## What a fighter gives while it stands (§5.4 line 8), from the resolver's constants and the log's header.
static func _gives(battle_log: Dictionary, f: Dictionary) -> Array:
	var out := []
	if f.role == "commander":
		out.append("+%d morale to its side while it stands (commander)" % AutoBattleResolver.COMMANDER_MORALE)
		if f.trait == AutoBattleResolver.INSPIRE:
			out.append("+%d more morale to its side while it stands (Inspire)" % AutoBattleResolver.INSPIRE_MORALE)
		if f.trait == AutoBattleResolver.PACK_LEADER:
			out.append("+%d attack to every unit of its side while it stands (Pack Leader)" % AutoBattleResolver.PACK_LEADER_ATTACK)
	if f.role == "ruler":
		out.append("+%d morale to its side while it stands (ruler)" % RulerData.RULER_MORALE)
		var dread := int(f.get("ruler", {}).get("dread", 0))
		if dread > 0:
			out.append("-%d morale to every enemy side while it stands (Dread)" % dread)
	if f.trait == AutoBattleResolver.FURY:
		out.append("-%d morale to every enemy side while it stands (Fury, at most -%d in all)" % [AutoBattleResolver.FURY_MORALE,
			AutoBattleResolver.FURY_MAX])
	return out


## BattleTimeline.statuses as player-facing words, with the numbers from the resolver's constants.
static func _status_words(battle_log: Dictionary, st: Dictionary) -> Array:
	var out := []
	if st.shield_wall:
		out.append("Shield Wall: +%d defense while another fighter of its side stands" % AutoBattleResolver.SHIELD_WALL_DEFENSE)
	if st.berserk:
		out.append("Berserk: +%d attack while wounded" % AutoBattleResolver.BERSERK_ATTACK)
	if st.blood_frenzy:
		var frenzy := 0
		for s in battle_log.sides:
			frenzy = maxi(frenzy, int(s.frenzy))
		out.append("%s: +%d attack while wounded" % [RulerRules.mandate_name(RulerRules.BLOOD_FRENZY), frenzy])
	if st.pack_leader:
		out.append("Pack Leader: +%d attack from its commander" % AutoBattleResolver.PACK_LEADER_ATTACK)
	if st.shielded and st.standing:
		out.append("shielded: ordinary enemies can't reach it this round")
	return out


# --- morale -------------------------------------------------------------------------------------------

## Morale event `i` explained: {"side", "round", "morale": Breakdown (its base and parts sum to the morale),
## "break": Breakdown (20 + 5 x morale, with the clamp line; sums to break %), "break_hp" (the hp at or
## below which it breaks), "result" (text), "codex"}. {} when event i is not a morale check.
static func explain_morale(battle_log: Dictionary, i: int) -> Dictionary:
	var events: Array = battle_log.get("events", [])
	if i < 0 or i >= events.size() or events[i].t != "morale":
		return {}
	var e: Dictionary = events[i]
	var si := int(e.side)
	var side: Dictionary = battle_log.sides[si]
	var lines := [_line("Average morale of its units", int(e.base), "at the start of the battle")]
	for p in e.parts:
		lines.append(_line(String(MORALE_PART_NAMES.get(String(p), String(p))), int(e.parts[p]), ""))
	var morale_bd := _make("Morale of %s, round %d" % [side.name, int(e.n)], "", lines, "Morale", int(e.morale), "battle_morale")
	var bp := break_breakdown(int(e.morale), int(e.break_pct))
	var hp_start := int(side.hp_start)
	var at := break_hp(hp_start, int(e.break_pct))
	var result := ""
	match String(e.result):
		"holds":
			result = "%s has lost %d%% of its %d hp (%d left) and breaks at %d%%: it holds." % [side.name, int(e.lost_pct), hp_start,
				int(e.hp), int(e.break_pct)]
		"breaks":
			result = "%s has lost %d%% of its %d hp (%d left) and breaks at %d%%: it breaks and flees." % [side.name, int(e.lost_pct),
				hp_start, int(e.hp), int(e.break_pct)]
			if e.iron_last_round:
				result += " Iron Discipline holds a line only until the last round."
		"held":
			result = "%s has lost %d%% of its %d hp (%d left), past the %d%% where it breaks, but Iron Discipline holds it while %s stands." % [
				side.name, int(e.lost_pct), hp_start, int(e.hp), int(e.break_pct), _the(_fighter_name(battle_log, int(e.held_by)))]
	morale_bd.description = result
	return {"side": si, "round": int(e.n), "morale": morale_bd, "break": bp, "break_hp": at, "result": result,
		"codex": "mandate_iron_discipline" if e.result == "held" else "battle_morale"}


## The break percentage for `morale` as a breakdown that sums to `break_pct` (the log's value): 20, plus 5
## per point of morale, with the 25-95% clamp line when it applies (AutoBattleResolver.break_pct).
static func break_breakdown(morale: int, break_pct: int) -> Dictionary:
	var per := AutoBattleResolver.MORALE_PCT_PER_POINT
	var lines := [_line("Every side", AutoBattleResolver.BREAK_BASE_PCT, "breaks once it has lost this much"),
		_line("%d%% x morale %d" % [per, morale], per * morale, "%d%% more for every point of morale" % per)]
	var raw := AutoBattleResolver.BREAK_BASE_PCT + per * morale
	if raw > AutoBattleResolver.MAX_BREAK_PCT:
		lines.append(_line("At most %d%%" % AutoBattleResolver.MAX_BREAK_PCT, AutoBattleResolver.MAX_BREAK_PCT - raw, ""))
	elif raw < AutoBattleResolver.MIN_BREAK_PCT:
		lines.append(_line("At least %d%%" % AutoBattleResolver.MIN_BREAK_PCT, AutoBattleResolver.MIN_BREAK_PCT - raw, ""))
	return _make("Where morale %d breaks" % morale, "A side breaks at the end of a round once it has lost %d%% of the hit points it started with." % break_pct,
		lines, "Breaks after losing (%)", break_pct, "battle_morale")


## The hp at or below which a side that started with `hp_start` hp breaks at `break_pct` (§4.7): the
## largest h with roundi(100 x (hp_start - h) / hp_start) >= break_pct, the resolver's own loss rule
## (lost_pct in AutoBattleResolver._fight_round). 0 when it never breaks before it has no one left.
static func break_hp(hp_start: int, break_pct: int) -> int:
	var h := clampi(int(floor(hp_start * (1.0 - break_pct / 100.0))), 0, hp_start)
	while h + 1 <= hp_start and lost_pct(hp_start, h + 1) >= break_pct:
		h += 1
	while h > 0 and lost_pct(hp_start, h) < break_pct:
		h -= 1
	return h


## The share of its starting hp a side with `hp` left has lost, in whole percent, as the resolver rounds it.
static func lost_pct(hp_start: int, hp: int) -> int:
	return roundi(100.0 * (hp_start - hp) / maxi(1, hp_start))


## "breaks at 26 hp or less" (§4.7).
static func break_text(hp_start: int, break_pct: int) -> String:
	var h := break_hp(hp_start, break_pct)
	return "breaks at %d hp or less" % h if h > 0 else "breaks only when no one is left"


## A side's strength bar at `state` (§4.8): {"hp", "hp_start", "pending", "morale", "break_pct", "break_hp",
## "notch" (the break line as a share of hp_start), "fill" (hp left as a share), "out", "held", "text"}.
static func side_strength(battle_log: Dictionary, state: Dictionary, si: int) -> Dictionary:
	var side: Dictionary = battle_log.sides[si]
	var ss: Dictionary = state.sides[si]
	var hp_start := int(side.hp_start)
	var bp := int(ss.break_pct)
	var text := "%d / %d hp · morale %d · %s" % [int(ss.hp), hp_start, int(ss.morale), break_text(hp_start, bp)]
	if ss.out == "routed":
		text += " · broke"
	elif ss.out == "destroyed":
		text += " · no one left"
	return {"hp": int(ss.hp), "hp_start": hp_start, "pending": int(ss.pending), "morale": int(ss.morale), "break_pct": bp,
		"break_hp": break_hp(hp_start, bp), "notch": 1.0 - bp / 100.0, "fill": float(ss.hp) / maxi(1, hp_start), "out": ss.out,
		"held": ss.held, "text": text, "codex": "battle_strength"}


## The notch tag for morale event `i` when the side's morale changed since its last check (or since the
## start): {"delta", "text", "codex"}, e.g. "-4 morale: the Knight Captain fell (commander +2, Inspire +2)".
## {} when it didn't change or event i is not a morale check.
static func morale_change(battle_log: Dictionary, i: int) -> Dictionary:
	var events: Array = battle_log.get("events", [])
	if i < 0 or i >= events.size() or events[i].t != "morale":
		return {}
	var e: Dictionary = events[i]
	var si := int(e.side)
	var before: Dictionary = battle_log.sides[si].start_morale.parts
	var was := int(battle_log.sides[si].start_morale.morale)
	for k in range(i - 1, -1, -1):
		if events[k].t == "morale" and int(events[k].side) == si:
			before = events[k].parts
			was = int(events[k].morale)
			break
	var delta := int(e.morale) - was
	if delta == 0:
		return {}
	var gone := []
	var causes := []
	for p in before:
		var now := int(e.parts.get(p, 0))
		if now == int(before[p]):
			continue
		if now == 0:
			gone.append("%s %+d" % [String(p), int(before[p])])
		else:
			gone.append("%s %+d to %+d" % [String(p), int(before[p]), now])
		var cause := _part_cause(battle_log, String(p), si, i)
		if not cause.is_empty() and not causes.has(cause):
			causes.append(cause)
	var text := "%+d morale" % delta
	if not causes.is_empty():
		text += ": " + " and ".join(causes)
	if not gone.is_empty():
		text += " (%s)" % ", ".join(gone)
	return {"delta": delta, "text": text, "codex": "battle_morale"}


## Why morale part `p` of side `si` changed by event `i`: the source that fell this or an earlier round.
static func _part_cause(battle_log: Dictionary, p: String, si: int, i: int) -> String:
	var role := ""
	var on_enemy := false
	match p:
		"commander", AutoBattleResolver.INSPIRE:
			role = "commander"
		AutoBattleResolver.RULER:
			role = "ruler"
		AutoBattleResolver.FURY:
			on_enemy = true
		AutoBattleResolver.DREAD:
			role = "ruler"
			on_enemy = true
	var names := []
	var events: Array = battle_log.events
	for k in range(i - 1, -1, -1):
		var e: Dictionary = events[k]
		if e.t == "morale" and int(e.side) == si and k < i:
			break  # only what fell since the side's last check
		if e.t != "death":
			continue
		var f: Dictionary = battle_log.fighters[int(e.f)]
		if (int(f.side) != si) != on_enemy:
			continue
		if p == AutoBattleResolver.FURY and f.trait != AutoBattleResolver.FURY:
			continue
		if not role.is_empty() and f.role != role:
			continue
		var who := _the(_bare(f.name)) if f.role != "ruler" else String(f.name)
		if on_enemy:
			who = "%s %s" % [poss(battle_log.sides[int(f.side)].name), _bare(f.name)]
		if not names.has(who):
			names.append(who)
	if names.is_empty():
		return ""
	return "%s fell" % " and ".join(names)


# --- shared words (BattleMoments and BattleCaptions use these) -----------------------------------------

## The player-facing name of an attack, defense or morale part key: a mandate's name for "mandate_<id>",
## "hills (defending)" for terrain, "fort (defending)", a trait's own name.
static func part_name(battle_log: Dictionary, key: String) -> String:
	if key.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return RulerRules.mandate_name(key.trim_prefix(AutoBattleResolver.MANDATE_PREFIX))
	if key == "terrain":
		return "%s (defending)" % String(battle_log.get("terrain", "terrain"))
	if key == "fort":
		return "fort (defending)"
	return key


static func _part_note(battle_log: Dictionary, key: String) -> String:
	if key == "terrain" or key == "fort":
		return "only the defender gets the ground"
	if key.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return "mandate"
	return "trait"


## The RulesCodex entry for a report factor id (the battle report viewer's rule: FACTOR_ENTRIES, then the
## mandate's own entry, then the trait's), or "" when there is none.
static func factor_entry(factor_id: String) -> String:
	if FACTOR_ENTRIES.has(factor_id):
		return FACTOR_ENTRIES[factor_id]
	if factor_id.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return factor_id if RulesCodex.ENTRIES.has(factor_id) else "mandates"
	var trait_entry := AutoBattleResolver.codex_id_for_trait(factor_id.trim_prefix("morale_"))
	return trait_entry if RulesCodex.ENTRIES.has(trait_entry) else ""


## Standing fighters of side `si` per rank at `state`: [front, second, back].
static func standing_counts(battle_log: Dictionary, state: Dictionary, si: int) -> Array:
	var counts := [0, 0, 0]
	for fid in battle_log.sides[si].fighters:
		var fs: Dictionary = state.fighters[int(fid)]
		if fs.alive and not fs.fled:
			counts[int(battle_log.fighters[int(fid)].tier)] += 1
	return counts


## "Aurel Crown's Spearmen", "King Corvane I" (a ruler's own name).
static func _label(battle_log: Dictionary, fid: int) -> String:
	var f: Dictionary = battle_log.fighters[fid]
	if f.role == "ruler":
		return String(f.name)
	return "%s %s" % [poss(battle_log.sides[int(f.side)].name), _bare(f.name)]


static func label(battle_log: Dictionary, fid: int) -> String:
	return _label(battle_log, fid)


static func _fighter_name(battle_log: Dictionary, fid: int) -> String:
	if fid < 0 or fid >= battle_log.fighters.size():
		return "its commander"
	return String(battle_log.fighters[fid].name)


static func _death_round(battle_log: Dictionary, fid: int, before: int) -> int:
	var events: Array = battle_log.events
	for k in mini(before, events.size()):
		if events[k].t == "death" and int(events[k].f) == fid:
			return int(events[k].n)
	return 0


static func _pool_words(pool: int) -> String:
	return "the only enemy it can reach" if pool == 1 else "one of the %d enemies it can reach" % pool


static func _reach_words(reach: String, screened: bool) -> String:
	var out := ""
	match reach:
		"front": out = "a front-rank target"
		"second": out = "a second-rank target its front rank no longer shields"
		"back": out = "a commander at the back, with no unit left in front of it"
		"skirmish": out = "a second-rank target only Skirmish could reach"
	if screened:
		out += ", shooting from safety: ordinary enemies couldn't reach the attacker"
	return out


static func poss(name: String) -> String:
	return name + ("'" if name.ends_with("s") else "'s")


static func _bare(name: String) -> String:
	return name.trim_prefix("the ")


static func _the(name: String) -> String:
	if name.begins_with("the ") or name.begins_with("King ") or name.begins_with("its "):
		return name
	return "the " + name


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)


static func _make(title: String, description: String, lines: Array, total_label: String, total: int, codex: String) -> Dictionary:
	return {"title": title, "description": description, "lines": lines, "total_label": total_label, "total": total, "codex": codex}


static func _line(text: String, value: int, note: String) -> Dictionary:
	return {"label": text, "value": value, "note": note}
