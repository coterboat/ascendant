class_name BattleMoments
## The key moments of a battle, found in its event log (M3-2, #57; design/M3_BATTLES.md §5.2). Pure: it
## reads only the log (BattleLog), never the rules or an RNG, so the same log always gives the same
## moments. Renderer-agnostic: each moment carries a camera hint (who and where) that the 3D battle player
## and the 2D Simple view both read.
##
##   BattleMoments.key_moments(log)     every moment, in event order
##   BattleMoments.missing(log)         {kind: plain reason} for each kind with no moment ("No charge:
##                                      neither side has Charge."), for the disabled buttons
##   BattleMoments.turning_point(log)   {"round", "event", "reason", "winner", "margins"}: §5.2's rule
##
## A moment is {"kind", "round", "event" (index into log.events), "fighter" (id or -1), "side" (index or
## -1), "title" (the button's name: "First to fall"), "text" (one line, §5.2's examples), "explain" (why,
## from the log's numbers), "codex" (a RulesCodex entry), "camera"}. The camera hint is
## {"frame": "fighters" | "side" | "battle", "fighters": [ids to keep in view], "side": index or -1,
## "rank": "front rank" | "second rank" | "back line" | ""}: "fighters" frames those fighters (the first is
## the subject), "side" a whole side, "battle" everyone. A player jumps to the moment's event (§5.2: its
## display beat minus a 0.5 s lead-in); the hint only says what to keep in view.
##
## Kinds (KINDS, the order of the control bar's buttons):
##   first_blood    the first death: the first fighter to fall, not the first hit
##   charge         the first round-1 attack with a Charge bonus
##   ruler_falls    each death of a ruler fighter
##   turning_point  the first round r >= 1 after which the eventual winner stayed the sole side furthest
##                  from breaking to the end, and was not after round r - 1 (margin = break % - lost %
##                  from that round's morale checks; round 0 is the start; a side out of the battle keeps
##                  its last margin, and a side wiped out has lost 100%). None when the winner led from the
##                  start, the battle lasted one round, or it ended in a mutual rout or at the round cap.
##   rout           each rout or destroyed event

const KINDS := ["first_blood", "charge", "ruler_falls", "turning_point", "rout"]
const TITLES := {"first_blood": "First to fall", "charge": "Charge", "ruler_falls": "Ruler falls", "turning_point": "Turning point",
	"rout": "Rout"}
const CODEX := {"first_blood": "battle_pending_damage", "charge": "trait_charge", "ruler_falls": "ruler_in_battle",
	"turning_point": "battle_key_moments", "rout": "battle_morale"}


## Every key moment of `battle_log`, in event order (a truncated log gives the moments it holds).
static func key_moments(battle_log: Dictionary) -> Array:
	var out := []
	var events: Array = battle_log.get("events", [])
	var first_blood := false
	var charge := false
	for i in events.size():
		var e: Dictionary = events[i]
		match e.t:
			"death":
				var f: Dictionary = battle_log.fighters[int(e.f)]
				if not first_blood:
					first_blood = true
					out.append(_first_blood(battle_log, i))
				if f.role == "ruler":
					out.append(_ruler_falls(battle_log, i))
			"attack":
				if not charge and int(e.n) == 1 and e.bonus.has(AutoBattleResolver.CHARGE):
					charge = true
					out.append(_charge(battle_log, i))
			"rout", "destroyed":
				out.append(_rout(battle_log, i))
	var tp := turning_point(battle_log)
	if int(tp.round) > 0:
		out.append(_turning(battle_log, tp))
	out.sort_custom(func(a, b): return a.event < b.event if a.event != b.event else KINDS.find(a.kind) < KINDS.find(b.kind))
	return out


## The moments of one kind, in event order.
static func of_kind(battle_log: Dictionary, kind: String) -> Array:
	return key_moments(battle_log).filter(func(m): return m.kind == kind)


## {kind: plain reason} for every kind in KINDS that has no moment in `battle_log`.
static func missing(battle_log: Dictionary) -> Dictionary:
	var have := {}
	for m in key_moments(battle_log):
		have[m.kind] = true
	var out := {}
	var events: Array = battle_log.get("events", [])
	var cut: bool = battle_log.get("truncated", false)
	for kind in KINDS:
		if have.has(kind):
			continue
		match kind:
			"first_blood":
				out[kind] = "The log was cut short before anyone fell." if cut else "No one fell: every fighter was still standing at the end."
			"charge":
				var chargers := false
				for f in battle_log.get("fighters", []):
					if f.trait == AutoBattleResolver.CHARGE:
						chargers = true
				out[kind] = "No charge: neither side has Charge." if not chargers else "No charge: no attack in round 1 carried the Charge bonus."
			"ruler_falls":
				var rulers: Array = battle_log.get("fighters", []).filter(func(f): return f.role == "ruler")
				out[kind] = "No ruler fought in this battle." if rulers.is_empty() else "No ruler fell."
			"turning_point":
				out[kind] = String(turning_point(battle_log).reason)
			"rout":
				if cut:
					out[kind] = "The log was cut short before any side broke."
				else:
					var end := _end(battle_log)
					out[kind] = "Nobody broke: the battle ran to the round cap." if not end.is_empty() and end.how == "round_cap" \
						else "No side broke or was wiped out."
	return out


## §5.2's turning point: {"round" (0 when there is none), "event" (the round's first morale check, -1 when
## none), "reason" ("" when there is one, else why not, in plain words), "winner" (side index, -1 when the
## log has no end), "margins": [[margin per side] for round 0 (the start) and every round]}.
static func turning_point(battle_log: Dictionary) -> Dictionary:
	var out := {"round": 0, "event": -1, "reason": "", "winner": -1, "margins": []}
	var end := _end(battle_log)
	if end.is_empty():
		out.reason = "The log was cut short before the end, so there is no turning point to show."
		return out
	var w := int(end.winner)
	out.winner = w
	var sides: Array = battle_log.sides
	var margins := []
	var m := []
	for s in sides:
		m.append(int(s.start_morale.break_pct))
	margins.append(m.duplicate())
	var first_check := {}  # round -> index of its first morale event
	var events: Array = battle_log.events
	var rounds := int(end.rounds)
	var last_break := m.duplicate()
	for i in events.size():
		var e: Dictionary = events[i]
		match e.t:
			"morale":
				m[int(e.side)] = int(e.break_pct) - int(e.lost_pct)
				last_break[int(e.side)] = int(e.break_pct)
				if not first_check.has(int(e.n)):
					first_check[int(e.n)] = i
			"destroyed":
				m[int(e.side)] = int(last_break[int(e.side)]) - 100
			"round_end":
				margins.append(m.duplicate())
	out.margins = margins
	var name := String(sides[w].name)
	if end.how == "mutual":
		out.reason = "Both sides broke in the same round, so neither stayed ahead: the result card says who kept the field."
		return out
	if end.how == "round_cap":
		out.reason = "Nobody broke in %d rounds, so neither pulled away: the result card says who held." % rounds
		return out
	if rounds <= 1:
		out.reason = "The battle lasted one round, so there was no time for a turning point."
		return out
	var leads := []
	for r in margins.size():
		leads.append(_leader(margins[r]) == w)
	if not leads.has(false):
		out.reason = "%s was ahead from the start: it stayed further from breaking after every round." % _cap(name)
		return out
	for r in range(1, margins.size()):
		if leads[r - 1]:
			continue
		var holds := true
		for k in range(r, margins.size()):
			if not leads[k]:
				holds = false
				break
		if holds:
			out.round = r
			out.event = int(first_check.get(r, _round_end_index(battle_log, r)))
			return out
	out.reason = "Neither side stayed further from breaking to the end."
	return out


## The side with the largest margin, or -1 on a tie.
static func _leader(margins: Array) -> int:
	var best := -1
	var tied := false
	for si in margins.size():
		if best < 0 or int(margins[si]) > int(margins[best]):
			best = si
			tied = false
		elif int(margins[si]) == int(margins[best]):
			tied = true
	return -1 if tied else best


# --- the moments --------------------------------------------------------------------------------------

static func _first_blood(battle_log: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = battle_log.events[i]
	var fid := int(e.f)
	var f: Dictionary = battle_log.fighters[fid]
	var hit := _hits_on(battle_log, fid, int(e.n))
	var explain := "%s had %d hp left and took %d damage from %d %s this round: %s." % [
		_cap(BattleExplain.label(battle_log, fid)), _hp_before(battle_log, i), int(hit.damage), int(hit.count), "hit" if int(hit.count) == 1 else "hits",
		_names(battle_log, hit.by)]
	if _attacked(battle_log, fid, int(e.n)):
		explain += " Damage lands at the end of the round, so it still made its own attack."
	return _moment("first_blood", i, int(e.n), fid, int(f.side),
		"First to fall: %s, round %d." % [BattleExplain.label(battle_log, fid), int(e.n)], explain,
		{"frame": "fighters", "fighters": [fid] + _uniq(hit.by), "side": int(f.side), "rank": BattleExplain.RANK_WORDS[int(f.tier)]})


static func _charge(battle_log: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = battle_log.events[i]
	var a: Dictionary = battle_log.fighters[int(e.by)]
	var si := int(a.side)
	var bonus := int(e.bonus[AutoBattleResolver.CHARGE])
	var made := 0
	var landed := 0
	var extra := 0
	var chargers := []
	for k in range(i, battle_log.events.size()):
		var x: Dictionary = battle_log.events[k]
		if x.t == "round":
			break
		if x.t != "attack" or not x.bonus.has(AutoBattleResolver.CHARGE) or int(battle_log.fighters[int(x.by)].side) != si:
			continue
		made += 1
		chargers.append(int(x.by))
		if x.hit:
			landed += 1
			extra += int(x.bonus[AutoBattleResolver.CHARGE])
	var who := "%s %s" % [BattleExplain.poss(battle_log.sides[si].name), BattleExplain._bare(a.name)]
	var text := "%s charge: +%d damage on each hit this round." % [_cap(who), bonus]
	var explain := "%d of %d charging %s hit, for %d extra damage." % [landed, made, "attack" if made == 1 else "attacks", extra]
	if bonus == AutoBattleResolver.CHARGE_DAMAGE_FOREST and battle_log.get("terrain", "") == "forest":
		explain += " The forest slows the horses: +%d instead of +%d." % [AutoBattleResolver.CHARGE_DAMAGE_FOREST, AutoBattleResolver.CHARGE_DAMAGE]
	return _moment("charge", i, 1, int(e.by), si, text, explain,
		{"frame": "fighters", "fighters": chargers, "side": si, "rank": BattleExplain.RANK_WORDS[int(a.tier)]})


static func _ruler_falls(battle_log: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = battle_log.events[i]
	var fid := int(e.f)
	var f: Dictionary = battle_log.fighters[fid]
	var si := int(f.side)
	var hit := _hits_on(battle_log, fid, int(e.n))
	var explain := "%s had %d hp left and took %d damage from %d %s: %s. %s loses the +%d morale its ruler gave while it stood." % [
		_cap(String(f.name)), _hp_before(battle_log, i), int(hit.damage), int(hit.count), "hit" if int(hit.count) == 1 else "hits",
		_names(battle_log, hit.by), battle_log.sides[si].name, RulerData.RULER_MORALE]
	return _moment("ruler_falls", i, int(e.n), fid, si, "%s falls in round %d." % [_cap(String(f.name)), int(e.n)], explain,
		{"frame": "fighters", "fighters": [fid] + _uniq(hit.by), "side": si, "rank": BattleExplain.RANK_WORDS[int(f.tier)]})


static func _rout(battle_log: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = battle_log.events[i]
	var si := int(e.side)
	var name := String(battle_log.sides[si].name)
	var text := ""
	var explain := ""
	var fighters := []
	if e.t == "destroyed":
		text = "%s has no one left standing in round %d." % [_cap(name), int(e.n)]
		explain = "Every fighter of %s fell, so it is out of the battle." % name
	else:
		text = "%s breaks in round %d." % [_cap(name), int(e.n)]
		fighters = BattleLog._ints(e.fled)
		var check := _morale_of(battle_log, si, int(e.n))
		if not check.is_empty():
			explain = "It had lost %d%%, and morale %d holds only to %d%%." % [int(check.lost_pct), int(check.morale), int(check.break_pct)]
			for p in check.decisive:
				explain += " %s (%d morale) made it break a round sooner." % [_part(String(p)), int(check.parts[p])]
			if check.iron_last_round:
				explain += " Iron Discipline holds a line only until the last round."
		var end := _end(battle_log)
		if not end.is_empty() and end.how == "mutual" and int(end.winner) == si:
			explain += " Both sides broke in the same round; %s had lost the least, so it keeps the field." % name
	return _moment("rout", i, int(e.n), -1, si, text, explain.strip_edges(), {"frame": "side", "fighters": fighters, "side": si, "rank": ""})


static func _turning(battle_log: Dictionary, tp: Dictionary) -> Dictionary:
	var w := int(tp.winner)
	var r := int(tp.round)
	var name := String(battle_log.sides[w].name)
	var now: Array = tp.margins[r]
	var before: Array = tp.margins[r - 1]
	var other := -1
	for si in now.size():
		if si != w and (other < 0 or int(now[si]) > int(now[other])):
			other = si
	var oname := String(battle_log.sides[other].name) if other >= 0 else "the enemy"
	var explain := "After round %d %s could still lose %d%% more of its strength before breaking, %s %d%%." % [r, name, int(now[w]), oname,
		int(now[other]) if other >= 0 else 0]
	var lead := _leader(before)
	if r - 1 == 0:
		explain += " At the start %s" % ("%s was further from breaking (%d%% to %d%%)." % [battle_log.sides[lead].name, int(before[lead]), int(before[w])]
			if lead >= 0 else "both were as far from breaking (%d%% each)." % int(before[w]))
	else:
		explain += " After round %d %s" % [r - 1, "%s was further from breaking (%d%% to %d%%)." % [battle_log.sides[lead].name, int(before[lead]),
			int(before[w])] if lead >= 0 else "both were as far from breaking (%d%% each)." % int(before[w])]
	return _moment("turning_point", int(tp.event), r, -1, w,
		"Turning point, round %d: from here on %s stayed further from breaking." % [r, name], explain,
		{"frame": "battle", "fighters": [], "side": w, "rank": ""})


# --- helpers ------------------------------------------------------------------------------------------

static func _moment(kind: String, i: int, n: int, fid: int, si: int, text: String, explain: String, camera: Dictionary) -> Dictionary:
	return {"kind": kind, "round": n, "event": i, "fighter": fid, "side": si, "title": TITLES[kind], "text": text, "explain": explain,
		"codex": CODEX[kind], "camera": camera}


## The hits on fighter `fid` in round `n`: {"count", "damage", "by": [attacker ids in attack order]}.
static func _hits_on(battle_log: Dictionary, fid: int, n: int) -> Dictionary:
	var out := {"count": 0, "damage": 0, "by": []}
	for e in battle_log.events:
		if e.t == "attack" and int(e.n) == n and int(e.to) == fid and e.hit:
			out.count += 1
			out.damage += int(e.damage)
			out.by.append(int(e.by))
	return out


## The hp fighter had before the wound that killed it (the wound right before death event `i`).
static func _hp_before(battle_log: Dictionary, i: int) -> int:
	if i > 0 and battle_log.events[i - 1].t == "wound":
		return int(battle_log.events[i - 1].from)
	return 0


## "Thornmane Clans' Tuskers (2) and War Bear" for attacker ids, grouped by side, then by name, in first-seen
## order (a ruler by its own name).
static func _names(battle_log: Dictionary, ids: Array) -> String:
	var by_side := {}
	var side_order := []
	for fid in ids:
		var f: Dictionary = battle_log.fighters[int(fid)]
		var si := int(f.side)
		if not by_side.has(si):
			by_side[si] = {"counts": {}, "order": []}
			side_order.append(si)
		var nm := String(f.name) if f.role == "ruler" else BattleExplain._bare(String(f.name))
		var g: Dictionary = by_side[si]
		if not g.counts.has(nm):
			g.counts[nm] = 0
			g.order.append(nm)
		g.counts[nm] += 1
	var groups := []
	for si in side_order:
		var g: Dictionary = by_side[si]
		var parts := []
		for nm in g.order:
			parts.append(nm if g.counts[nm] == 1 else "%s (%d)" % [nm, g.counts[nm]])
		groups.append("%s %s" % [BattleExplain.poss(String(battle_log.sides[si].name)), _and(parts)])
	return _and(groups)


static func _and(parts: Array) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts.back()


## Whether fighter `fid` made an attack in round `n`.
static func _attacked(battle_log: Dictionary, fid: int, n: int) -> bool:
	for e in battle_log.events:
		if e.t == "attack" and int(e.n) == n and int(e.by) == fid:
			return true
	return false


static func _uniq(ids: Array) -> Array:
	var out := []
	for v in ids:
		if not out.has(int(v)):
			out.append(int(v))
	return out


static func _morale_of(battle_log: Dictionary, si: int, n: int) -> Dictionary:
	for e in battle_log.events:
		if e.t == "morale" and int(e.side) == si and int(e.n) == n:
			return e
	return {}


static func _end(battle_log: Dictionary) -> Dictionary:
	var k := BattleLog.find_event(battle_log, "end") if battle_log.has("events") else -1
	return battle_log.events[k] if k >= 0 else {}


static func _round_end_index(battle_log: Dictionary, n: int) -> int:
	var events: Array = battle_log.events
	for i in events.size():
		if events[i].t == "round_end" and int(events[i].n) == n:
			return i
	return -1


static func _part(key: String) -> String:
	match key:
		AutoBattleResolver.DREAD:
			return "Dread"
		AutoBattleResolver.FURY:
			return "Fury"
	return key


static func _cap(text: String) -> String:
	return BattleExplain._cap(text)
