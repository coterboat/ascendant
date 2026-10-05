class_name BattleTimeline
extends RefCounted
## A battle event log folded into states for playback (M3-1, #56; design/M3_BATTLES.md §2.5). Pure: it
## reads only the log (BattleLog) and never calls the battle rules or draws a random number, so playing a
## battle back can't change it.
##
##   var tl := BattleTimeline.build(event.numbers.log)
##   tl.state_at(i)       the state before event i (0 = before the battle; events.size() = after it)
##   tl.final_state()     the state after every event
##   tl.round_start(n)    the index of round n's "round" event (-1 when there is none)
##   tl.display_order(n)  round n's attack events in the order to show them (round-robin across sides)
##   tl.statuses(state, fighter id)   what is active on a fighter, derived from the header and the hp
##
## A state is a Dictionary:
##   {"event": i, "round": n (0 before round 1), "beat": "deploy" | "attacks" | "wounds" | "morale" | "end",
##    "winner": side index once the end event is past, else -1,
##    "reach": the current round's "reach" entries (the round event's; [] before round 1),
##    "fighters": [{"hp", "pending" (damage that lands at the end of the round), "alive", "fled", "lost"}],
##    "sides": [{"hp", "pending", "morale", "break_pct", "lost_pct", "out" ("" | "routed" | "destroyed"), "held"}]}
## by fighter id and side index. "lost" marks fighters destroyed with their side's armies (the aftermath),
## "held" a side Iron Discipline kept from breaking at its last morale check.
## M5-7, in a log with magic only: each fighter also has "spells" ({part key: {"stat", "value", "by"}}: the hexes and
## shields on it this round, cleared at the next round event) and each side "bled" (hp its own casters bled and haven't
## got back). A cast event's beat is "casts"; a bolt's damage waits in "pending" like a hit's. Keyframes at every round
## event make state_at() cheap: at most one round of events is folded on top of one.

var _log: Dictionary = {}
var _keyframes: Array = []  # [state before event k] for k = 0 and every round event, in order
var _round_starts: Dictionary = {}  # round n -> its round event's index
var _final: Dictionary = {}


static func build(battle_log: Dictionary) -> BattleTimeline:
	var tl := BattleTimeline.new()
	tl._log = battle_log
	var state := initial_state(battle_log)
	tl._keyframes.append(state.duplicate(true))
	var events: Array = battle_log.get("events", [])
	for i in events.size():
		var e: Dictionary = events[i]
		if e.t == "round" and i > 0:
			tl._round_starts[int(e.n)] = i
			tl._keyframes.append(state.duplicate(true))
		elif e.t == "round":
			tl._round_starts[int(e.n)] = i
		apply(battle_log, state, i)
	tl._final = state
	return tl


## The log this timeline was built from.
func battle_log() -> Dictionary:
	return _log


## How many events the log has (state_at takes 0 to this).
func size() -> int:
	return _log.get("events", []).size()


## How many rounds were fought.
func rounds() -> int:
	return _round_starts.size()


## The state before event `i` (clamped to 0 .. size()). A new Dictionary each call.
func state_at(i: int) -> Dictionary:
	var n := size()
	i = clampi(i, 0, n)
	if i == n:
		return _final.duplicate(true)
	var best: Dictionary = _keyframes[0]
	for kf in _keyframes:
		if int(kf.event) <= i:
			best = kf
		else:
			break
	var state := best.duplicate(true)
	for k in range(int(best.event), i):
		apply(_log, state, k)
	return state


func final_state() -> Dictionary:
	return _final.duplicate(true)


## The index of round `n`'s "round" event, or -1.
func round_start(n: int) -> int:
	return int(_round_starts.get(n, -1))


## Round `n`'s attack events (indices), taken round-robin across sides: side 0's first, side 1's first,
## side 0's second, and so on, each side in log order (§2.5). Every attack of a round lands at the same
## moment in the rules, so any order is truthful; alternating keeps either side from seeming to strike first.
func display_order(n: int) -> Array:
	var by_side := {}
	var events: Array = _log.events
	var start := round_start(n)
	if start < 0:
		return []
	for i in range(start + 1, events.size()):
		var e: Dictionary = events[i]
		if e.t == "round":
			break
		if e.t != "attack":
			continue
		var si := int(_log.fighters[int(e.by)].side)
		if not by_side.has(si):
			by_side[si] = []
		by_side[si].append(i)
	var keys: Array = by_side.keys()
	keys.sort()
	var out := []
	var k := 0
	var more := true
	while more:
		more = false
		for si in keys:
			if k < by_side[si].size():
				out.append(by_side[si][k])
				more = true
		k += 1
	return out


## What is active on fighter `fid` in `state`, derived from the log's header and the state's hp (§2.5;
## the same conditions the battle rules apply when it attacks or is attacked):
##   {"standing": alive and not fled,
##    "shield_wall": Shield Wall, and another fighter of its side stands,
##    "berserk": Berserk, and below its maximum hp,
##    "blood_frenzy": its side has Blood Frenzy, and below its maximum hp,
##    "pack_leader": a unit, with a commander with Pack Leader standing on its side,
##    "shielded": its rank isn't one ordinary enemies can reach this round,
##    "auras": the morale it gives while it stands: "commander", "Inspire", "ruler" (its own side's) and
##             "Fury", "Dread" (every enemy side's)}
## M5-7, in a log with magic, also "snared" (a hex lowers its attack this round), "spell_shielded" (a shield raises its
## defense this round) and "spell_parts" ({part key: value}).
func statuses(state: Dictionary, fid: int) -> Dictionary:
	var f: Dictionary = _log.fighters[fid]
	var fs: Dictionary = state.fighters[fid]
	var side: Dictionary = _log.sides[int(f.side)]
	var below_max: bool = int(fs.hp) < int(f.max_hp)
	var others := false
	var pack := false
	for oid in side.fighters:
		var o: Dictionary = _log.fighters[int(oid)]
		if not state.fighters[int(oid)].alive:
			continue
		if int(oid) != fid:
			others = true
		if o.role == "commander" and o.trait == AutoBattleResolver.PACK_LEADER:
			pack = true
	var auras := []
	if fs.alive and not fs.fled:
		if f.role == "commander":
			auras.append("commander")
			if f.trait == AutoBattleResolver.INSPIRE:
				auras.append(AutoBattleResolver.INSPIRE)
		if f.role == "ruler":
			auras.append(AutoBattleResolver.RULER)
			if int(f.get("ruler", {}).get("dread", 0)) > 0:
				auras.append(AutoBattleResolver.DREAD)
		if f.trait == AutoBattleResolver.FURY:
			auras.append(AutoBattleResolver.FURY)
	var out := {"standing": fs.alive and not fs.fled,
		"shield_wall": f.trait == AutoBattleResolver.SHIELD_WALL and others,
		"berserk": f.trait == AutoBattleResolver.BERSERK and below_max,
		"blood_frenzy": int(side.frenzy) > 0 and below_max,
		"pack_leader": f.role == "unit" and pack,
		"shielded": not _reach_tiers(state, int(f.side)).has(int(f.tier)),
		"auras": auras}
	if fs.has("spells"):
		var parts := {}
		var snared := false
		var warded := false
		for k in fs.spells:
			parts[k] = int(fs.spells[k].value)
			if String(fs.spells[k].stat) == "attack" and int(fs.spells[k].value) < 0:
				snared = true
			if String(fs.spells[k].stat) == "defense" and int(fs.spells[k].value) > 0:
				warded = true
		out["snared"] = snared
		out["spell_shielded"] = warded
		out["spell_parts"] = parts
	return out


## The tiers ordinary enemies can reach on side `si`: the current round's, or, before round 1, the
## target rule applied to the standing fighters (AutoBattleResolver._reachable_tiers, a pure function).
func _reach_tiers(state: Dictionary, si: int) -> Array:
	for entry in state.reach:
		if int(entry.side) == si:
			return BattleLog._ints(entry.tiers)
	var counts := [0, 0, 0]
	for fid in _log.sides[si].fighters:
		if state.fighters[int(fid)].alive:
			counts[int(_log.fighters[int(fid)].tier)] += 1
	return AutoBattleResolver._reachable_tiers(counts, false)


# --- folding ------------------------------------------------------------------------------------------

## The state before the battle's first event: every fighter at its starting hp, each side at its starting
## morale, nothing pending.
static func initial_state(battle_log: Dictionary) -> Dictionary:
	var magic: bool = battle_log.get("magic", false)
	var fighters := []
	for f in battle_log.fighters:
		var fs := {"hp": int(f.hp), "pending": 0, "alive": int(f.hp) > 0, "fled": false, "lost": false}
		if magic:
			fs["spells"] = {}
		fighters.append(fs)
	var sides := []
	for s in battle_log.sides:
		var sm: Dictionary = s.start_morale
		var ss := {"hp": int(s.hp_start), "pending": 0, "morale": int(sm.morale), "break_pct": int(sm.break_pct), "lost_pct": 0,
			"out": "", "held": false}
		if magic:
			ss["bled"] = 0
		sides.append(ss)
	return {"event": 0, "round": 0, "beat": "deploy", "winner": -1, "reach": [], "fighters": fighters, "sides": sides}


## Applies event `i` of `battle_log` to `state` in place (state["event"] becomes i + 1).
static func apply(battle_log: Dictionary, state: Dictionary, i: int) -> void:
	var e: Dictionary = battle_log.events[i]
	var fighters: Array = state.fighters
	var sides: Array = state.sides
	match e.t:
		"round":
			state.round = int(e.n)
			state.beat = "attacks"
			state.reach = e.reach
			for fs in fighters:
				if fs.has("spells"):
					fs.spells = {}  # M5-7: last round's hexes and shields are gone
		"cast":
			# M5-7: a bolt's damage waits for the round's wounds; a hex or shield is on its targets for the round.
			state.beat = "casts"
			for t in e.targets:
				var tid := int(t)
				if String(e.kind) == "bolt":
					fighters[tid].pending += int(e.damage)
					sides[int(battle_log.fighters[tid].side)].pending += int(e.damage)
				elif e.has("part"):
					fighters[tid].spells["spell_" + String(e.spell)] = {"stat": String(e.part.stat), "value": int(e.part.value), "by": int(e.by)}
		"attack":
			state.beat = "attacks"
			if e.hit:
				var to := int(e.to)
				fighters[to].pending += int(e.damage)
				sides[int(battle_log.fighters[to].side)].pending += int(e.damage)
		"wound":
			state.beat = "wounds"
			var fid := int(e.f)
			var fs: Dictionary = fighters[fid]
			var s: Dictionary = sides[int(battle_log.fighters[fid].side)]
			s.pending -= int(fs.pending)
			s.hp -= int(e.from) - int(e.to)
			fs.pending = 0
			fs.hp = int(e.to)
			if e.has("bled"):
				s.bled = int(s.get("bled", 0)) + int(e.bled)  # M5-7: Bloodbolt's bleeding
		"death":
			state.beat = "wounds"
			fighters[int(e.f)].alive = false
		"heal":
			# M4-3: Lifedrinker, after the round's wounds and before its morale checks.
			state.beat = "wounds"
			var hid := int(e.f)
			sides[int(battle_log.fighters[hid].side)].hp += int(e.to) - int(e.from)
			fighters[hid].hp = int(e.to)
		"morale":
			state.beat = "morale"
			var s: Dictionary = sides[int(e.side)]
			s.morale = int(e.morale)
			s.break_pct = int(e.break_pct)
			s.lost_pct = int(e.lost_pct)
			s.held = e.result == "held"
		"rout":
			state.beat = "morale"
			sides[int(e.side)].out = "routed"
			for fid in e.fled:
				fighters[int(fid)].fled = true
		"destroyed":
			state.beat = "morale"
			sides[int(e.side)].out = "destroyed"
		"round_end":
			pass
		"end":
			state.beat = "end"
			state.winner = int(e.winner)
			if e.how == "mutual":
				# The winner of a mutual rout keeps the field (the resolver resets its rout).
				var w := int(e.winner)
				sides[w].out = ""
				for fid in battle_log.sides[w].fighters:
					fighters[int(fid)].fled = false
		"bleed_closed":
			# M5-7: the winner's bled hp come back after the battle.
			state.beat = "end"
			for h in e.closed:
				var cid := int(h[0])
				var cs: Dictionary = sides[int(battle_log.fighters[cid].side)]
				cs.hp += int(h[2]) - int(h[1])
				cs.bled = maxi(0, int(cs.get("bled", 0)) - (int(h[2]) - int(h[1])))
				fighters[cid].hp = int(h[2])
		"feast":
			state.beat = "end"
			for h in e.healed:
				var fid := int(h[0])
				sides[int(battle_log.fighters[fid].side)].hp += int(h[2]) - int(h[1])
				fighters[fid].hp = int(h[2])
		"aftermath":
			state.beat = "end"
			for fid in e.lost:
				fighters[int(fid)].lost = true
	state.event = i + 1
