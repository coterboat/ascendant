class_name BattleWhy
extends RefCounted
## What the "why did that happen" panel says at any point of a battle's playback (M3-4, #59;
## design/M3_BATTLES.md §7.3). Pure and renderer-agnostic: it reads only a BattlePlayer (its beats, log and
## report) and BattleExplain / BattleCaptions, so the 2D Simple view and the 3D stage show the same words,
## and tests check every number without a screen. BattleWhyPanel draws it.
##
##   var why := BattleWhy.new(player)
##   why.at(player.next_beat(), player.live_state(), selected_fid) -> {
##     "position"      beats fired so far (the playhead)
##     "round"         the round on (0 before round 1)
##     "now"           the current beat in one line ("Round 2 · damage lands: 3 fighters fell.")
##     "attack_event"  the log event of the attack that landed last this round (-1 when none yet)
##     "attack"        BattleExplain.explain_attack of it ({} when none): chance and damage breakdowns that
##                     sum to the log's numbers, the attack and defense, the roll
##     "morale"        [BattleExplain.explain_morale] for this round's morale checks so far
##     "caption"       the caption on screen (BattleCaptions lines of the last caption beat fired)
##     "totals"        [{side, name, attacks, hits, dealt, expected}] this round so far; "totals_text"
##     "feed"          this round's notable events so far, newest last, at most FEED_MAX:
##                     [{beat, event, kind, text, codex}]; "feed_more" counts the older ones left out
##     "selected"      BattleExplain.explain_fighter of the selected fighter now ({} when none)
##     "chips"         the report's factors: [{id, side, title, codex, worth, lit, text, tip}]; a chip is lit
##                     when its factor has worth this round ("Charge: +8 this round")
##   }
##
## Feed entries are the round's casts (M5-7), deaths, exposed ranks, morale checks, routs, heals, charges, big hits
## (damage >= BattlePlayer.BIG_HIT), lucky hits (chance <= LUCKY_CHANCE) and unlucky misses (chance >=
## UNLUCKY_CHANCE). Jumping to one lands right after its beat (BattlePlayer.seek_beat(beat + 1)), so the
## panel then explains it.

const LUCKY_CHANCE := 40
const UNLUCKY_CHANCE := 80
const FEED_MAX := 8

var _player: BattlePlayer
var _log: Dictionary
var _report: Dictionary
var _n := 0
var _round_at := PackedInt32Array()  # per position p (beats fired): the round on
var _attack_at := PackedInt32Array()  # per p: the event of the last attack landed in that round, -1
var _caption_at := PackedInt32Array()  # per p: the beat of the last caption fired, -1
var _totals_at: Array = []  # per p: [[attacks, hits, dealt, expected] per side] this round so far (shared arrays)
var _rounds := {}  # round -> {"attacks": A, "morale": [[beat, event]], "feed": [entries], "end": round_end event,
                   #           "rout": {side: beat}, "last_attack_beat": beat}


func _init(player: BattlePlayer) -> void:
	_player = player
	_log = player.battle_log()
	_report = player.report()
	_build()


# --- building -------------------------------------------------------------------------------------

func _build() -> void:
	var beats := _player.beats()
	_n = beats.size()
	_round_at.resize(_n + 1)
	_attack_at.resize(_n + 1)
	_caption_at.resize(_n + 1)
	_totals_at.resize(_n + 1)
	var events: Array = _log.events
	var tl := _player.timeline()
	_rounds = {0: _new_round(0)}
	for i in events.size():
		if events[i].t == "round_end":
			if not _rounds.has(int(events[i].n)):
				_rounds[int(events[i].n)] = _new_round(int(events[i].n))
			_rounds[int(events[i].n)].end = i
	var rnd := 0
	var atk := -1
	var cap := -1
	var tot := _zero_totals()
	var charged := {}
	var prev_tiers := {}
	_round_at[0] = 0
	_attack_at[0] = -1
	_caption_at[0] = -1
	_totals_at[0] = tot
	for k in _n:
		var b: Dictionary = beats[k]
		var ev := int(b.event)
		match String(b.kind):
			"round_start":
				rnd = int(b.round)
				atk = -1
				tot = _zero_totals()
				if not _rounds.has(rnd):
					_rounds[rnd] = _new_round(rnd)
				_rounds[rnd].attacks = tl.display_order(rnd).size()
				_exposed(k, ev, rnd, prev_tiers, tl)
			"attack_landed":
				atk = ev
				var e: Dictionary = events[ev]
				var si := int(_log.fighters[int(e.by)].side)
				tot = tot.duplicate(true)
				tot[si][0] += 1
				if e.hit:
					tot[si][1] += 1
					tot[si][2] += int(e.damage)
				tot[si][3] += float(e.get("expected", 0.0))
				_rounds[rnd].last_attack_beat = k
				_attack_feed(k, ev, e, rnd, si, charged)
			"caption":
				cap = k
			"death":
				var f: Dictionary = _log.fighters[int(b.fighter)]
				var ruler: bool = f.role == "ruler"
				_feed(rnd, k, ev, "death", "%s fell." % _cap(BattleExplain.label(_log, int(b.fighter))),
					"ruler_death" if ruler else "battle_pending_damage")
			"heal":
				if String(_log.events[ev].get("spell", "")) == "blood_moon":
					_feed(rnd, k, ev, "heal", "%s healed back %d hp under the Blood Moon." % [_cap(BattleExplain.label(_log, int(b.fighter))),
						int(b.data.healed)], "spell_blood_moon")
				elif String(_log.events[ev].get("trait", "")) == AutoBattleResolver.SIPHON:  # CW-2: a Gleaner's heal
					_feed(rnd, k, ev, "heal", "%s drank %d hp (Siphon)." % [_cap(BattleExplain.label(_log, int(b.fighter))),
						int(b.data.healed)], AutoBattleResolver.codex_id_for_trait(AutoBattleResolver.SIPHON))
				else:
					_feed(rnd, k, ev, "heal", "%s drank back %d hp (Lifedrinker)." % [_cap(BattleExplain.label(_log, int(b.fighter))),
						int(b.data.healed)], "trait_lifedrinker")
			"cast":
				# M5-7: every cast is a notable event.
				_feed(rnd, k, ev, "cast", "Spell: %s" % String(b.data.text), "spell_" + String(b.data.spell))
			"morale":
				_rounds[rnd].morale.append([k, ev])
				var me: Dictionary = events[ev]
				var word: String = {"holds": "holds", "breaks": "breaks", "held": "is held by Iron Discipline"}.get(String(me.result), "")
				_feed(rnd, k, ev, "morale", "Morale: %s %s (lost %d%%, breaks at %d%%)." % [_side_name(int(me.side)), word,
					int(me.lost_pct), int(me.break_pct)], "mandate_iron_discipline" if me.result == "held" else "battle_morale")
			"rout":
				_rounds[rnd].rout[int(b.side)] = k
				_feed(rnd, k, ev, "rout", "%s broke and fled." % _side_name(int(b.side)), "battle_morale")
			"destroyed":
				_rounds[rnd].rout[int(b.side)] = k
				_feed(rnd, k, ev, "rout", "No one of %s is left standing." % _side_name(int(b.side)), "battle_morale")
		_round_at[k + 1] = rnd
		_attack_at[k + 1] = atk
		_caption_at[k + 1] = cap
		_totals_at[k + 1] = tot


func _new_round(n: int) -> Dictionary:
	return {"round": n, "attacks": 0, "morale": [], "feed": [], "end": -1, "rout": {}, "last_attack_beat": -1}


func _zero_totals() -> Array:
	var out := []
	for s in _log.sides:
		out.append([0, 0, 0, 0.0])
	return out


func _feed(rnd: int, beat: int, ev: int, kind: String, text: String, codex: String) -> void:
	_rounds[rnd].feed.append({"beat": beat, "event": ev, "kind": kind, "text": text, "codex": codex})


func _attack_feed(k: int, ev: int, e: Dictionary, rnd: int, si: int, charged: Dictionary) -> void:
	var who := _cap(BattleExplain.label(_log, int(e.by)))
	var whom := BattleExplain.label(_log, int(e.to))
	if e.hit and e.bonus.has(AutoBattleResolver.CHARGE) and not charged.has(si):
		charged[si] = true
		_feed(rnd, k, ev, "charge", "Charge: %s hit %s for %d (Charge +%d)." % [who, whom, int(e.damage), int(e.bonus[AutoBattleResolver.CHARGE])],
			"trait_charge")
	elif e.hit and int(e.damage) >= BattlePlayer.BIG_HIT:
		_feed(rnd, k, ev, "big", "Big hit: %s hit %s for %d." % [who, whom, int(e.damage)], "battle_hit_chance")
	elif e.hit and int(e.chance) <= LUCKY_CHANCE:
		_feed(rnd, k, ev, "lucky", "Lucky hit: %s hit %s with only %d%% to hit." % [who, whom, int(e.chance)], "battle_hit_chance")
	elif not e.hit and int(e.chance) >= UNLUCKY_CHANCE:
		_feed(rnd, k, ev, "unlucky", "Unlucky miss: %s missed %s with %d%% to hit." % [who, whom, int(e.chance)], "battle_hit_chance")


## A feed entry for each side whose second rank or back line every enemy can reach from this round on.
func _exposed(k: int, ev: int, rnd: int, prev_tiers: Dictionary, tl: BattleTimeline) -> void:
	if ev < 0:
		return
	var st := tl.state_at(ev)
	for entry in _log.events[ev].get("reach", []):
		var si := int(entry.side)
		var tiers: Array = BattleLog._ints(entry.tiers)
		var before: Array = prev_tiers.get(si, [0])
		var counts := BattleExplain.standing_counts(_log, st, si)
		for t in [1, 2]:
			if tiers.has(t) and not before.has(t) and counts[t] > 0:
				_feed(rnd, k, ev, "exposed", "%s %s is exposed: every enemy can reach it now." % [BattleExplain.poss(_side_name(si)),
					BattleExplain.RANK_WORDS[t]], "battle_formation")
		prev_tiers[si] = tiers


# --- reading it -----------------------------------------------------------------------------------

## The panel's content with `p` beats fired, at `state` (the player's live state), with fighter
## `selected` pinned (-1 for none).
func at(p: int, state: Dictionary, selected: int = -1) -> Dictionary:
	p = clampi(p, 0, _n)
	var n := _round_at[p]
	var info: Dictionary = _rounds.get(n, _new_round(n))
	var out := {"position": p, "round": n}
	var totals := []
	var tot: Array = _totals_at[p]
	for si in _log.sides.size():
		totals.append({"side": si, "name": _side_name(si), "attacks": int(tot[si][0]), "hits": int(tot[si][1]), "dealt": int(tot[si][2]),
			"expected": float(tot[si][3])})
	out.totals = totals
	out.totals_text = _totals_text(totals) if n >= 1 else ""
	var feed := []
	for f in info.feed:
		if int(f.beat) < p:
			feed.append(f)
	out.feed_more = maxi(0, feed.size() - FEED_MAX)
	out.feed = feed.slice(feed.size() - FEED_MAX) if feed.size() > FEED_MAX else feed
	out.now = _now(p, n, state, info, totals, feed)
	out.attack_event = _attack_at[p]
	out.attack = BattleExplain.explain_attack(_log, out.attack_event) if out.attack_event >= 0 else {}
	var morale := []
	for m in info.morale:
		if int(m[0]) < p:
			morale.append(BattleExplain.explain_morale(_log, int(m[1])))
	out.morale = morale
	var cb := _caption_at[p]
	out.caption = _player.beats()[cb].data.lines if cb >= 0 else []
	out.selected = _player.explain(selected) if selected >= 0 else {}
	out.chips = _chips(p, n, info, state)
	return out


func _now(p: int, n: int, state: Dictionary, info: Dictionary, totals: Array, feed: Array) -> String:
	if p >= _n or int(state.winner) >= 0:
		var end_i := BattleLog.find_event(_log, "end")
		if end_i < 0:
			return "The playback stops here: this battle's log was cut short."
		var e: Dictionary = _log.events[end_i]
		var rounds := int(e.rounds)
		if _log.sides.size() > 2:
			# #265: with more than two sides, who left the field, and when.
			return "Battle over after %d %s: %s won (%s)." % [rounds, "round" if rounds == 1 else "rounds", _side_name(int(e.winner)), how_it_ended(_log)]
		var how: String = {"rout": "the enemy broke", "destroyed": "no enemy was left standing",
			"round_cap": "the last round ended with both sides standing", "mutual": "both sides broke, and it kept the field"}.get(String(e.how), "")
		return "Battle over after %d %s: %s won (%s)." % [rounds, "round" if rounds == 1 else "rounds", _side_name(int(e.winner)), how]
	if n <= 0:
		var parts := []
		for si in _log.sides.size():
			parts.append("%s with %d fighters" % [_side_name(si), _log.sides[si].fighters.size()])
		if parts.size() > 2:
			return "Before round 1: the armies deploy, each side against every other: %s." % RulerRules._and_list(parts)
		return "Before round 1: the armies deploy, %s." % " against ".join(parts)
	match String(state.beat):
		"casts":
			var cast := feed.filter(func(f): return f.kind == "cast").size()
			return "Round %d · spells: %d cast so far. Spells always land: they don't roll." % [n, cast]
		"attacks":
			var landed := 0
			var hits := 0
			for t in totals:
				landed += int(t.attacks)
				hits += int(t.hits)
			return "Round %d · attacks: %d of %d have landed, %d %s." % [n, landed, int(info.attacks), hits, "hit" if hits == 1 else "hits"]
		"wounds":
			var fell := feed.filter(func(f): return f.kind == "death").size()
			var words := "nobody fell" if fell == 0 else ("1 fighter fell" if fell == 1 else "%d fighters fell" % fell)
			return "Round %d · damage lands: %s." % [n, words]
		"morale":
			var checks := []
			for m in info.morale:
				if int(m[0]) < p:
					var me: Dictionary = _log.events[int(m[1])]
					checks.append("%s %s" % [_side_name(int(me.side)), {"holds": "holds", "breaks": "breaks",
						"held": "is held by Iron Discipline"}.get(String(me.result), "")])
			return "Round %d · morale: %s." % [n, ", ".join(checks) if not checks.is_empty() else "each side checks"]
	return "Round %d." % n


## #265: how a battle of more than two sides ended, naming each side: every side but the winner as it left the field, in
## the order they left it ("Free Holds broke in round 3", "Thornmane Clans had no one left in round 4"; last, any "still
## stood when the rounds ran out"), then, when the winner was not simply the last side standing, why it kept the field (a
## mutual rout, the round cap). "" without an end event. Every word is the log's.
static func how_it_ended(battle_log: Dictionary) -> String:
	var end_i := BattleLog.find_event(battle_log, "end")
	if end_i < 0:
		return ""
	var e: Dictionary = battle_log.events[end_i]
	var sides: Array = battle_log.sides
	var w := int(e.winner)
	var left_at := {}  # side -> [event kind, round]
	for ev in battle_log.events:
		if (ev.t == "rout" or ev.t == "destroyed") and not left_at.has(int(ev.side)):
			left_at[int(ev.side)] = [String(ev.t), int(ev.n)]
	var losers := []
	for si in sides.size():
		if si != w:
			losers.append(si)
	losers.sort_custom(func(a, b):
		var ra := int(left_at[a][1]) if left_at.has(a) else 1 << 20
		var rb := int(left_at[b][1]) if left_at.has(b) else 1 << 20
		return ra < rb or (ra == rb and a < b))
	var parts := []
	for si in losers:
		var name := String(sides[si].name)
		if left_at.has(si):
			parts.append("%s %s in round %d" % [name, "broke" if left_at[si][0] == "rout" else "had no one left", int(left_at[si][1])])
		else:
			parts.append("%s still stood when the rounds ran out" % name)
	var text := RulerRules._and_list(parts)
	if w < 0 or w >= sides.size():
		return text
	var wname := String(sides[w].name)
	match String(e.how):
		"mutual":
			text += "; %s broke in round %d too, but had lost the least, so it kept the field" % [wname, int(e.rounds)]
		"round_cap":
			text += "; the defender held" if sides[w].get("defender", false) else "; %s had the most of its strength left" % wname
	return text


## #265: the result of a battle of more than two sides in one sentence, naming each side: "Aurel Crown won after 4 rounds:
## Free Holds broke in round 3 and Thornmane Clans broke in round 4." (how_it_ended). "" without an end event.
static func result_sentence(battle_log: Dictionary) -> String:
	var end_i := BattleLog.find_event(battle_log, "end")
	if end_i < 0:
		return ""
	var e: Dictionary = battle_log.events[end_i]
	var n := int(e.rounds)
	return "%s won after %d %s: %s." % [String(battle_log.sides[int(e.winner)].name), n, "round" if n == 1 else "rounds", how_it_ended(battle_log)]


func _totals_text(totals: Array) -> String:
	var parts := []
	for t in totals:
		parts.append("%s dealt %d (%d of %d %s, about %d expected)" % [t.name, int(t.dealt), int(t.hits), int(t.attacks),
			"hit" if int(t.attacks) == 1 else "hits", roundi(float(t.expected))])
	return " · ".join(parts)


## The report's chosen factors as chips. A factor the resolver measures attack by attack is lit for the
## whole round when it was worth something this round (round_end.impact); luck once the round's attacks
## have landed and it was a lucky round (BattleCaptions' rule); a morale factor once a morale check it
## decided has happened; a rout once the side broke.
func _chips(p: int, n: int, info: Dictionary, state: Dictionary) -> Array:
	var out := []
	var re := int(info.end)
	var attacks_done := int(info.last_attack_beat) < p
	for f in _report.get("factors", []):
		var id := String(f.get("id", ""))
		var codex := BattleExplain.factor_entry(id)
		if id.is_empty() or not RulesCodex.ENTRIES.has(codex):
			continue
		var si := _side_of_faction(String(f.get("faction", "")))
		var title := _factor_title(id)
		var worth := 0.0
		var lit_text := ""
		if n >= 1 and re >= 0 and si >= 0:
			var e: Dictionary = _log.events[re]
			if id == "luck":
				var diff := float(e.dealt[si]) - float(e.expected[si])
				if attacks_done and diff >= BattleCaptions.LUCK_MIN and diff >= BattleCaptions.LUCK_SHARE * float(e.expected[si]):
					worth = diff
					lit_text = "%s: +%d damage this round" % [title, roundi(diff)]
			elif id == "rout":
				if info.rout.has(si) and int(info.rout[si]) < p:
					worth = 1.0
					lit_text = "%s: %s broke this round" % [title, _side_name(si)]
			elif BattleLog._non_impact(id):
				var part := _morale_part(id)
				for m in info.morale:
					if int(m[0]) >= p or part.is_empty():
						continue
					var me: Dictionary = _log.events[int(m[1])]
					if me.get("decisive", []).has(part) or (part == "iron" and me.result == "held"):
						worth = 1.0
						lit_text = "%s: it decided a morale check this round" % title
			else:
				worth = float(e.impact[si].get(id, 0.0))
				if roundi(worth) >= BattleCaptions.MIN_WORTH:
					lit_text = "%s: +%d this round" % [title, roundi(worth)]
		var lit := not lit_text.is_empty()
		var text := String(f.get("text", ""))
		out.append({"id": id, "side": si, "title": title, "codex": codex, "worth": worth if lit else 0.0, "lit": lit,
			"text": lit_text if lit else title, "tip": _cap(text) + "." if not text.is_empty() else title})
	return out


## The morale part a non-impact factor stands for ("" for none): morale_commander -> "commander".
static func _morale_part(id: String) -> String:
	if id == "mandate_iron_discipline":
		return "iron"
	if id == "ability_dread":
		return "Dread"
	if id == "Fury":
		return "Fury"
	if id.begins_with("morale_"):
		return id.trim_prefix("morale_")
	return ""


## A factor's short player-facing name for its chip.
func _factor_title(id: String) -> String:
	match id:
		"terrain":
			return "Terrain"
		"fort":
			return "Fort"
		"commander", "morale_commander":
			return "Commander"
		"morale_Inspire":
			return "Inspire"
		"rout":
			return "Breaking"
		"numbers":
			return "Numbers"
		"luck":
			return "Luck"
		"round_cap":
			return "Round cap"
		"ruler", "morale_ruler":
			return "Ruler"
		"ability_dread":
			return "Dread"
	var title := _cap(BattleExplain.part_name(_log, id.trim_prefix("morale_")))
	if title.contains("_"):
		title = String(RulesCodex.entry(BattleExplain.factor_entry(id)).get("title", "Battle"))
	return title


func _side_name(si: int) -> String:
	return String(_log.sides[si].name) if si >= 0 and si < _log.sides.size() else ""


func _side_of_faction(faction: String) -> int:
	for s in _log.sides:
		if String(s.faction) == faction:
			return int(s.index)
	return -1


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)
