extends RefCounted
## A battle event log as readable text, round by round, for debugging (M3-1, #56): who attacked whom with
## which rolls and parts, every wound, death, morale check and rout, the round totals and their "why"
## worth, then the report's own lines and the checks (BattleLog.validate, verify_draws, cross_check), so
## the two can be read side by side. Fighters are "#id Name" with the log's ids. A developer tool: the
## text uses ids and is not player-facing.
##
##   print(Dump.text(log, report))
##   print(Dump.captions(log, report))   M3-2 (#57): the round captions and key moments, as players read them


static func text(battle_log: Dictionary, report: Dictionary = {}) -> String:
	var L := []
	var sides: Array = battle_log.sides
	var fighters: Array = battle_log.fighters
	var where := ""
	if battle_log.kind == "border":
		where = "border battle between %s" % " and ".join(battle_log.provinces)
	else:
		where = "%s (%s%s)" % [", ".join(battle_log.provinces), battle_log.terrain, ", fort" if battle_log.fort else ""]
	L.append("Battle %s: %s, turn %d, battle %d. Defender: %s. Seed %s, RNG %s -> %s.%s" % [
		battle_log.id if not String(battle_log.id).is_empty() else "(outside a game)", where, int(battle_log.turn), int(battle_log.index),
		battle_log.defender if not String(battle_log.defender).is_empty() else "nobody", battle_log.rng.seed, battle_log.rng.before,
		battle_log.rng.after, " TRUNCATED at %d events." % battle_log.events.size() if battle_log.truncated else ""])
	for s in sides:
		var sm: Dictionary = s.start_morale
		L.append("Side %d: %s (%s), %d fighters, %d hp. Morale %d (base %d%s), breaks at %d%%. Base hit %d%s%s%s%s." % [
			int(s.index), s.name, "defending" if s.defender else "attacking", s.fighters.size(), int(s.hp_start), int(sm.morale),
			int(s.base_morale), _parts(sm.parts), int(sm.break_pct), int(s.base_hit),
			", Blood Frenzy +%d" % int(s.frenzy) if int(s.frenzy) > 0 else "", ", Iron Discipline" if s.iron else "",
			", Feast of Victory" if s.feast else "", ", Dread %d" % int(s.dread) if int(s.dread) > 0 else ""])
		if not s.mandates.is_empty():
			L.append("  mandates: %s" % ", ".join(s.mandates))
		for a in s.armies:
			L.append("  army %s: %s" % [a.id, a.label])
		for fid in s.fighters:
			var f: Dictionary = fighters[int(fid)]
			var extra := ""
			if not f.hp_parts.is_empty():
				extra += " hp parts%s" % _parts(f.hp_parts)
			if not f.ruler.is_empty():
				extra += " ruler %s kept %d, %s rank%s" % [f.ruler.id, int(f.ruler.kept_power), f.ruler.rank,
					", Dread %d" % int(f.ruler.dread) if int(f.ruler.dread) > 0 else ""]
			L.append("  %s: %s, %s rank, %d/%d hp, attack %d, defense %d%s%s (army %s)" % [_who(battle_log, int(fid)), f.role,
				AutoBattleResolver.TIER_WORDS[int(f.tier)], int(f.hp), int(f.max_hp), int(f.attack), int(f.defense),
				", " + f.trait if not String(f.trait).is_empty() else "", extra, f.army])
	for e in battle_log.events:
		match e.t:
			"round":
				var reach := []
				for r in e.reach:
					reach.append("%s reachable in ranks %s (Skirmish: %s)" % [sides[int(r.side)].name, str(r.tiers), str(r.skirmish_tiers)])
				L.append("")
				L.append("Round %d: %s." % [int(e.n), "; ".join(reach)])
			"attack":
				var bonus := ""
				for b in e.bonus:
					bonus += " +%d %s" % [int(e.bonus[b]), b]
				L.append("  %s -> %s: target %d of %d, roll %d vs %d%%: %s%s (attack %d = %d%s; defense %d = %d%s; base hit %d; %s%s; expected %s)" % [
					_who(battle_log, int(e.by)), _who(battle_log, int(e.to)), int(e.pick) + 1, int(e.pool), int(e.roll), int(e.chance),
					"HIT %d damage" % int(e.damage) if e.hit else "miss", bonus, int(e.attack.value), int(e.attack.base), _parts(e.attack.parts),
					int(e.defense.value), int(e.defense.base), _parts(e.defense.parts), int(e.base_hit), e.reach,
					", from safety" if e.screened else "", str(e.expected)])
			"wound":
				L.append("  wound: %s %d -> %d hp (hit by %s)" % [_who(battle_log, int(e.f)), int(e.from), int(e.to), _list(battle_log, e.by)])
			"death":
				L.append("  DEATH: %s fell" % _who(battle_log, int(e.f)))
			"morale":
				L.append("  morale %s: %d (base %d%s), lost %d%% (%d hp left), breaks at %d%%: %s%s%s%s" % [sides[int(e.side)].name,
					int(e.morale), int(e.base), _parts(e.parts), int(e.lost_pct), int(e.hp), int(e.break_pct), e.result,
					" by %s" % _who(battle_log, int(e.held_by)) if int(e.held_by) >= 0 else "",
					"; decided by %s" % ", ".join(e.decisive) if not e.decisive.is_empty() else "",
					"; Iron Discipline doesn't hold the last round" if e.iron_last_round else ""])
			"rout":
				L.append("  ROUT: %s broke; fled: %s" % [sides[int(e.side)].name, _list(battle_log, e.fled)])
			"destroyed":
				L.append("  DESTROYED: %s has no one left standing" % sides[int(e.side)].name)
			"round_end":
				var parts := []
				for si in sides.size():
					parts.append("%s %d hp, %d of %d hits, %d dealt (about %s expected)%s" % [sides[si].name, int(e.hp[si]), int(e.hits[si]),
						int(e.attacks[si]), int(e.dealt[si]), str(e.expected[si]), _worth(e.impact[si])])
				L.append("  end of round %d: %s" % [int(e.n), "; ".join(parts)])
			"end":
				L.append("")
				L.append("End: %s wins after %d rounds (%s), tie break %s%s.%s" % [sides[int(e.winner)].name, int(e.rounds), e.how, e.tie_break,
					" (roll %d of %d)" % [int(e.roll), int(e.tied)] if e.tie_break == "roll" else "", _after_rounds(sides, e.impact)])
			"feast":
				var healed := []
				for h in e.healed:
					healed.append("%s %d -> %d" % [_who(battle_log, int(h[0])), int(h[1]), int(h[2])])
				L.append("Feast of Victory (%s): %s" % [sides[int(e.side)].name, ", ".join(healed)])
			"aftermath":
				L.append("Aftermath: armies destroyed %s; lost %s; rulers dead %s." % [str(e.destroyed_armies), _list(battle_log, e.lost),
					_list(battle_log, e.fallen_rulers)])
				L.append("  \"%s\"" % e.text)
	if not report.is_empty():
		L.append("")
		L.append("The report:")
		for line in report.get("lines", []):
			L.append("  " + str(line))
	L.append("")
	var v := BattleLog.validate(battle_log)
	var d := BattleLog.verify_draws(battle_log)
	var c: Array = BattleLog.cross_check(battle_log, report) if not report.is_empty() else ["(no report to check against)"]
	L.append("Checks: validate %s; verify_draws %s; cross_check %s. %d events, %d bytes of JSON." % [_ok(v), _ok(d), _ok(c),
		battle_log.events.size(), BattleLog.to_json(battle_log).to_utf8_buffer().size()])
	for reason in v + d + c:
		L.append("  - " + str(reason))
	return "\n".join(L)


static func _who(battle_log: Dictionary, fid: int) -> String:
	if fid < 0 or fid >= battle_log.fighters.size():
		return "#%d" % fid
	var f: Dictionary = battle_log.fighters[fid]
	return "#%d %s (%s)" % [fid, f.name, battle_log.sides[int(f.side)].name]


static func _list(battle_log: Dictionary, ids) -> String:
	if not (ids is Array) or ids.is_empty():
		return "none"
	var out := []
	for fid in ids:
		out.append(_who(battle_log, int(fid)))
	return ", ".join(out)


static func _parts(parts: Dictionary) -> String:
	var out := ""
	for p in parts:
		out += " %s %s" % ["+" + str(parts[p]) if float(parts[p]) >= 0 else str(parts[p]), p]
	return out


static func _worth(impact: Dictionary) -> String:
	if impact.is_empty():
		return ""
	var out := []
	for k in impact:
		out.append("%s %s" % [k, str(impact[k])])
	return " [worth: %s]" % ", ".join(out)


static func _after_rounds(sides: Array, impact: Array) -> String:
	var out := []
	for si in impact.size():
		if not impact[si].is_empty():
			out.append("%s%s" % [sides[si].name, _worth(impact[si])])
	return "" if out.is_empty() else " After the rounds: %s." % "; ".join(out)


static func _ok(reasons: Array) -> String:
	return "ok" if reasons.is_empty() else "%d problems" % reasons.size()


## The battle's round captions (BattleCaptions) and key moments (BattleMoments), as the battle player
## shows them, with each line's rule, report factor and codex entry, and the camera hint of each moment
## (M3-2, #57). The caption and moment texts are player-facing; the bracketed tags are for developers.
static func captions(battle_log: Dictionary, report: Dictionary = {}) -> String:
	var L := []
	var where := ""
	if battle_log.kind == "border":
		where = "border battle between %s" % " and ".join(battle_log.provinces)
	else:
		where = "%s (%s%s)" % [", ".join(battle_log.provinces), battle_log.terrain, ", fort" if battle_log.fort else ""]
	L.append("Battle %s: %s. %s" % [battle_log.id if not String(battle_log.id).is_empty() else "(outside a game)", where,
		String(report.get("summary", ""))])
	L.append("")
	L.append("Captions:")
	for rc in BattleCaptions.all_rounds(battle_log, report):
		for line in rc.lines:
			L.append("  %s" % line.text)
			L.append("      [%s%s; codex %s]" % [line.rule, ", factor " + line.factor if not String(line.factor).is_empty() else "", line.codex])
	L.append("")
	L.append("Key moments:")
	for m in BattleMoments.key_moments(battle_log):
		L.append("  %s (event %d, round %d): %s" % [m.title, int(m.event), int(m.round), m.text])
		L.append("      %s" % m.explain)
		L.append("      [camera %s, fighters %s, side %d%s; codex %s]" % [m.camera.frame, str(m.camera.fighters), int(m.camera.side),
			", " + String(m.camera.rank) if not String(m.camera.rank).is_empty() else "", m.codex])
	var missing := BattleMoments.missing(battle_log)
	for kind in BattleMoments.KINDS:
		if missing.has(kind):
			L.append("  %s: none. %s" % [BattleMoments.TITLES[kind], missing[kind]])
	return "\n".join(L)
