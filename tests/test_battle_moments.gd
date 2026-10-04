extends "res://tests/test_case.gd"
## M3-2 (#57): key moments, round captions and hover explanations for battle playback
## (design/M3_BATTLES.md §4.7, §4.8, §5.2, §5.4, §7.2): BattleMoments, BattleCaptions and BattleExplain on
## every fixture battle. Each moment kind is found where the fixture has it and nowhere else, with every
## "none" case of the turning point; every round has a caption whose numbers are the log's or the report's;
## the explanations' lines add up to the log's own chance, damage, morale and break %; the break threshold
## follows the resolver's rule; no text carries a raw id and every one links a codex entry that exists; a
## log cut short degrades gracefully; the same log gives the same words; and the biggest battle is quick.

const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const Dump := preload("res://tools/battle_log/dump.gd")

## Building every moment and caption of the biggest fixture must fit in a third of §8.2's 0.3 s "Watch to
## first frame" budget (placeholders), since the battle player builds them when Watch is pressed.
const MOMENTS_BUDGET_MS := 100.0
## One hover explanation must fit in one frame's playback CPU budget (§8.2: 4.0 ms max).
const HOVER_BUDGET_MS := 4.0

## Each fixture's key moments, pinned: kind -> the rounds it happens in (in event order). Kinds not listed
## have no moment in that fixture.
const PINNED := {
	"starting_plains": {"charge": [1], "first_blood": [2], "turning_point": [2], "rout": [5]},
	"forest_fort": {"first_blood": [1], "rout": [6]},
	"knights_charge": {"charge": [1], "first_blood": [1], "rout": [5]},
	"skirmish": {"first_blood": [1], "turning_point": [1], "rout": [2]},
	"iron_discipline": {"charge": [1], "first_blood": [1], "rout": [4]},
	"king_falls_wins": {"charge": [1], "first_blood": [1], "ruler_falls": [3], "rout": [3]},
	"dread_feast_frenzy": {"charge": [1], "first_blood": [1], "rout": [4]},
	"round_cap_defender": {},
	"border": {"charge": [1], "first_blood": [1], "turning_point": [2], "rout": [5]},
	"biggest": {"charge": [1], "first_blood": [1], "rout": [4]},
	"one_round": {"first_blood": [1], "rout": [1]},
	"mutual_rout": {"first_blood": [1], "rout": [2, 2]},
}
## Why each fixture without a turning point has none: a phrase of the reason.
const NO_TURNING_POINT := {
	"forest_fort": "ahead from the start",
	"knights_charge": "ahead from the start",
	"iron_discipline": "ahead from the start",
	"king_falls_wins": "ahead from the start",
	"dread_feast_frenzy": "ahead from the start",
	"biggest": "ahead from the start",
	"one_round": "lasted one round",
	"mutual_rout": "broke in the same round",
	"round_cap_defender": "Nobody broke in 8 rounds",
}
const NEW_CODEX := ["battle_playback", "battle_formation", "battle_strength", "battle_pending_damage", "battle_key_moments", "battle_auras"]


# --- helpers ------------------------------------------------------------------------------------------

## {"log" (normalized: ints as the resolver wrote them), "report"} of a stored fixture.
func _fixture(name: String) -> Dictionary:
	var path := Scenarios.fixture_path(name)
	assert_true(FileAccess.file_exists(path), "the fixture %s exists" % path)
	var fx = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (fx is Dictionary):
		fail("the fixture %s is JSON" % name)
		return {"log": {}, "report": {}}
	return {"log": BattleLog.from_json(JSON.stringify(fx.log, "", false)).log, "report": fx.report}


## Strings that would be raw ids in player-facing text: the log's own ids, faction, type, army, ruler,
## province and mandate ids, and the shapes of factor and battle ids.
func _raw_ids(battle_log: Dictionary) -> Array:
	var ids := {}
	for s in battle_log.sides:
		ids[String(s.faction)] = true
		for a in s.armies:
			ids[String(a.id)] = true
		for m in s.mandates:
			ids[String(m)] = true
	for f in battle_log.fighters:
		ids[String(f.type)] = true
		if not f.ruler.is_empty():
			ids[String(f.ruler.id)] = true
	for p in battle_log.provinces:
		ids[String(p)] = true
	if not String(battle_log.id).is_empty():
		ids[String(battle_log.id)] = true
	return ids.keys()


func _assert_plain(text: String, battle_log: Dictionary, what: String) -> void:
	assert_false(text.strip_edges().is_empty(), "%s: not blank" % what)
	var snake := RegEx.create_from_string("[a-z]+_[a-z_]+")
	assert_true(snake.search(text) == null, "%s: no snake_case id in \"%s\"" % [what, text])
	assert_false(text.contains("#"), "%s: no #id in \"%s\"" % [what, text])
	var word := RegEx.create_from_string("[A-Za-z0-9_-]+")
	var words := {}
	for m in word.search_all(text):
		words[m.get_string()] = true
	for id in _raw_ids(battle_log):
		assert_false(words.has(id), "%s: no raw id '%s' in \"%s\"" % [what, id, text])


func _assert_codex(key: String, what: String) -> void:
	assert_true(RulesCodex.ENTRIES.has(key), "%s links codex entry '%s', which exists" % [what, key])


## Every whole number written in `text` (a leading minus counts when it isn't a dash between words).
func _numbers(text: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("(?<![A-Za-z0-9])-?\\d+")
	for m in re.search_all(text):
		out.append(int(m.get_string()))
	return out


func _morale_in(battle_log: Dictionary, n: int, si: int) -> Dictionary:
	for e in battle_log.events:
		if e.t == "morale" and int(e.n) == n and int(e.side) == si:
			return e
	return {}


func _round_end(battle_log: Dictionary, n: int) -> Dictionary:
	for e in battle_log.events:
		if e.t == "round_end" and int(e.n) == n:
			return e
	return {}


## §5.2's turning point, worked out here independently from the morale events: the round, or 0.
func _turning_round(battle_log: Dictionary) -> int:
	var end: Dictionary = battle_log.events[BattleLog.find_event(battle_log, "end")]
	if end.how == "mutual" or end.how == "round_cap" or int(end.rounds) <= 1:
		return 0
	var w := int(end.winner)
	var ns: int = battle_log.sides.size()
	var m := []
	var brk := []
	for s in battle_log.sides:
		m.append(int(s.start_morale.break_pct))
		brk.append(int(s.start_morale.break_pct))
	var sole := []
	var lead := func(arr: Array) -> bool:
		for si in ns:
			if si != w and int(arr[si]) >= int(arr[w]):
				return false
		return true
	sole.append(lead.call(m))
	for n in range(1, int(end.rounds) + 1):
		for si in ns:
			var c := _morale_in(battle_log, n, si)
			if not c.is_empty():
				m[si] = int(c.break_pct) - int(c.lost_pct)
				brk[si] = int(c.break_pct)
		for e in battle_log.events:
			if e.t == "destroyed" and int(e.n) == n:
				m[int(e.side)] = int(brk[int(e.side)]) - 100
		sole.append(lead.call(m))
	for r in range(1, sole.size()):
		if sole[r - 1]:
			continue
		if not sole.slice(r).has(false):
			return r
	return 0


# --- key moments --------------------------------------------------------------------------------------

func test_each_moment_kind_is_found_where_the_fixture_has_it_and_nowhere_else() -> void:
	for name in Scenarios.NAMES:
		assert_true(PINNED.has(name), "%s: its moments are pinned" % name)
	for name in PINNED:
		var fx := _fixture(name)
		var lg: Dictionary = fx.log
		var moments := BattleMoments.key_moments(lg)
		var got := {}
		for m in moments:
			if not got.has(m.kind):
				got[m.kind] = []
			got[m.kind].append(int(m.round))
		assert_eq(got, PINNED[name], "%s: the key moments by kind and round" % name)
		var missing := BattleMoments.missing(lg)
		for kind in BattleMoments.KINDS:
			assert_eq(missing.has(kind), not PINNED[name].has(kind), "%s: %s is missing exactly when it has no moment" % [name, kind])
			if missing.has(kind):
				_assert_plain(String(missing[kind]), lg, "%s: the reason there is no %s" % [name, kind])
		var last := -1
		for m in moments:
			var e: Dictionary = lg.events[int(m.event)]
			var what := "%s: %s at event %d" % [name, m.kind, int(m.event)]
			assert_true(int(m.event) >= last, "%s: moments come in event order" % what)
			last = int(m.event)
			match m.kind:
				"first_blood":
					assert_eq(e.t, "death", "%s is a death" % what)
					assert_eq(BattleLog.find_event(lg, "death"), int(m.event), "%s is the first death" % what)
					assert_eq(int(m.fighter), int(e.f), "%s names the fallen fighter" % what)
				"ruler_falls":
					assert_eq(e.t, "death", "%s is a death" % what)
					assert_eq(lg.fighters[int(e.f)].role, "ruler", "%s is a ruler's death" % what)
				"charge":
					assert_true(e.t == "attack" and int(e.n) == 1 and e.bonus.has("Charge"), "%s is a round-1 attack with a Charge bonus" % what)
					var first := -1
					for i in lg.events.size():
						if lg.events[i].t == "attack" and lg.events[i].bonus.has("Charge"):
							first = i
							break
					assert_eq(int(m.event), first, "%s is the first charging attack" % what)
				"rout":
					assert_true(e.t == "rout" or e.t == "destroyed", "%s is a rout or destroyed event" % what)
					assert_eq(int(m.side), int(e.side), "%s names the side" % what)
				"turning_point":
					assert_eq(e.t, "morale", "%s is that round's first morale check" % what)
			if e.has("n"):
				assert_eq(int(m.round), int(e.n), "%s: its round is the event's" % what)
			assert_eq(String(m.title), String(BattleMoments.TITLES[m.kind]), "%s: its title" % what)
			_assert_plain(String(m.text), lg, what + " text")
			_assert_plain(String(m.explain), lg, what + " explanation")
			_assert_codex(String(m.codex), what)
			assert_true(["fighters", "side", "battle"].has(String(m.camera.frame)), "%s: a camera frame" % what)
			for fid in m.camera.fighters:
				assert_true(int(fid) >= 0 and int(fid) < lg.fighters.size(), "%s: the camera's fighters exist" % what)
			if m.camera.frame == "fighters":
				assert_false(m.camera.fighters.is_empty(), "%s: a fighters frame names who to keep in view" % what)


func test_moment_numbers_come_from_the_log_and_the_report() -> void:
	# The charge moment's hits and extra damage match the report's round-1 line.
	for name in ["starting_plains", "knights_charge", "king_falls_wins", "border", "biggest"]:
		var fx := _fixture(name)
		var m: Dictionary = BattleMoments.of_kind(fx.log, "charge")[0]
		var extra: int = _numbers(String(m.explain))[2]
		assert_true(String(fx.report.rounds[0].line).contains("charged home for %d extra damage" % extra),
			"%s: the charge's %d extra damage is the report's (%s)" % [name, extra, fx.report.rounds[0].line])
		assert_true(String(m.text).contains("+4 damage"), "%s: the plains charge bonus" % name)
	var forest := _fixture("iron_discipline")
	assert_true(String(BattleMoments.of_kind(forest.log, "charge")[0].text).contains("+3 damage"), "the forest blunts the charge to +3")
	# The ruler's fall, from King Corvane's death and the wound before it.
	var king := _fixture("king_falls_wins")
	var rm: Dictionary = BattleMoments.of_kind(king.log, "ruler_falls")[0]
	assert_eq(String(rm.text), "King Corvane I falls in round 3.")
	var wound: Dictionary = king.log.events[int(rm.event) - 1]
	assert_true(String(rm.explain).begins_with("King Corvane I had %d hp left" % int(wound.from)), "the ruler's hp before the blow: %s" % rm.explain)
	# The rout's numbers are its morale check's, and a decisive part is named.
	var ff := _fixture("forest_fort")
	var rout: Dictionary = BattleMoments.of_kind(ff.log, "rout")[0]
	var check := _morale_in(ff.log, 6, 1)
	assert_eq(String(rout.explain), "It had lost %d%%, and morale %d holds only to %d%%. Fury (-2 morale) made it break a round sooner." % [
		int(check.lost_pct), int(check.morale), int(check.break_pct)])


func test_the_turning_point_follows_the_rule_and_every_none_case_says_why() -> void:
	for name in PINNED:
		var lg: Dictionary = _fixture(name).log
		var tp := BattleMoments.turning_point(lg)
		assert_eq(int(tp.round), _turning_round(lg), "%s: the turning point is the rule's" % name)
		if int(tp.round) > 0:
			assert_eq(String(tp.reason), "", "%s: no reason needed" % name)
			assert_false(NO_TURNING_POINT.has(name), "%s: has a turning point" % name)
		else:
			assert_true(NO_TURNING_POINT.has(name), "%s: no turning point is expected" % name)
			assert_true(String(tp.reason).contains(String(NO_TURNING_POINT.get(name, "?"))), "%s: the reason says '%s': %s" % [name,
				NO_TURNING_POINT.get(name, ""), tp.reason])
			assert_eq(String(BattleMoments.missing(lg).turning_point), String(tp.reason), "%s: the disabled button gives that reason" % name)
	# Every "none" case of §5.2 appears in a fixture.
	var cases := {}
	for name in NO_TURNING_POINT:
		cases[NO_TURNING_POINT[name]] = true
	assert_eq(cases.size(), 4, "ahead from the start, one round, mutual rout and round cap are all pinned")
	# The turning point is deterministic: the same log, a copy and its JSON round trip give the same one.
	var lg: Dictionary = _fixture("border").log
	var a := BattleMoments.turning_point(lg)
	var b := BattleMoments.turning_point(lg.duplicate(true))
	var c := BattleMoments.turning_point(BattleLog.from_json(BattleLog.to_json(lg)).log)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "the same turning point twice")
	assert_eq(JSON.stringify(a), JSON.stringify(c), "the same turning point after a JSON round trip")
	assert_eq(int(a.round), 2, "border: round 2, where the Clans pull ahead and stay there")


# --- captions -----------------------------------------------------------------------------------------

func test_every_round_has_a_plain_caption_that_links_a_codex_entry() -> void:
	for name in PINNED:
		var fx := _fixture(name)
		var lg: Dictionary = fx.log
		var all := BattleCaptions.all_rounds(lg, fx.report)
		assert_eq(all.size(), int(fx.report.rounds_fought), "%s: a caption for every round" % name)
		var ids := {}
		for f in fx.report.all_factors:
			ids[String(f.id)] = true
		for rc in all:
			var n := int(rc.round)
			var lines: Array = rc.lines
			assert_true(lines.size() >= 1 and lines.size() <= 2, "%s round %d: one or two lines" % [name, n])
			assert_true(String(lines[0].text).begins_with("Round %d: " % n), "%s round %d: line 1 names the round: %s" % [name, n, lines[0].text])
			assert_eq(JSON.stringify(lines), JSON.stringify(BattleCaptions.for_round(lg, fx.report, n)), "%s round %d: for_round agrees" % [name, n])
			for l in lines:
				var what := "%s round %d (%s)" % [name, n, l.rule]
				_assert_plain(String(l.text), lg, what)
				_assert_codex(String(l.codex), what)
				if not String(l.factor).is_empty():
					assert_true(ids.has(String(l.factor)), "%s: factor %s is one of the report's" % [what, l.factor])
					assert_eq(BattleExplain.factor_entry(String(l.factor)).is_empty(), false, "%s: its factor has a codex entry" % what)


func test_every_number_in_a_caption_is_the_logs_or_the_reports() -> void:
	var rules_seen := {}
	for name in PINNED:
		var fx := _fixture(name)
		var lg: Dictionary = fx.log
		var tl := BattleTimeline.build(lg)
		for rc in BattleCaptions.all_rounds(lg, fx.report):
			var n := int(rc.round)
			var re := _round_end(lg, n)
			# What a caption may say for round n, all read from the log and the report.
			var allowed := {n: true, AutoBattleResolver.ROUND_CAP: true, AutoBattleResolver.PACK_LEADER_ATTACK: true}
			for si in lg.sides.size():
				for key in ["hp", "attacks", "hits", "dealt"]:
					allowed[int(re[key][si])] = true
				allowed[roundi(float(re.expected[si]))] = true
				for k in re.impact[si]:
					allowed[roundi(float(re.impact[si][k]))] = true
				var c := _morale_in(lg, n, si)
				if not c.is_empty():
					for key in ["morale", "base", "break_pct", "lost_pct", "hp"]:
						allowed[int(c[key])] = true
					var cmd := int(c.parts.get("commander", 0)) + int(c.parts.get("Inspire", 0))
					var ruler := int(c.parts.get("ruler", 0))
					for p in c.parts:
						allowed[int(c.parts[p])] = true
					for amount in [cmd, ruler]:
						allowed[amount] = true
						allowed[AutoBattleResolver.break_pct(int(c.morale) - amount)] = true
				var counts := BattleExplain.standing_counts(lg, tl.state_at(tl.round_start(n)), si)
				for v in counts:
					allowed[int(v)] = true
			for e in lg.events:
				if e.t == "death" and int(e.n) == n:
					var f: Dictionary = lg.fighters[int(e.f)]
					allowed[int(f.hp)] = true
					if not f.ruler.is_empty():
						allowed[int(f.ruler.kept_power)] = true
			# The lines shown, and every rule's line for this round even where a rule above it won (so the
			# rarer rules, such as an exposed rank or a ruler falling in a rout round, are checked on real logs).
			for l in rc.lines + _every_rule(lg, fx.report, n):
				rules_seen[String(l.rule)] = true
				for v in _numbers(String(l.text)):
					assert_true(allowed.has(v), "%s round %d: %d in \"%s\" is a number of the log or the report" % [name, n, v, l.text])
				_assert_rule_numbers(fx, n, l)
	for rule in ["left", "held", "exposed", "impact", "totals", "luck", "ruler", "round_cap"]:
		assert_true(rules_seen.has(rule), "the fixtures show a '%s' caption" % rule)
	# Pinned: the Crown's Crossbowmen are exposed in round 4 of starting_plains (its Spearmen fell in round 3),
	# where the Warchief holding the Clans' line is the caption; King Corvane falls in the rout round.
	var sp := _fixture("starting_plains")
	assert_eq(String(BattleCaptions._exposed(sp.log, sp.report, BattleCaptions._rounds(sp.log), 4).text),
		"Round 4: Aurel Crown's Crossbowmen are exposed: no front-rank fighter stands in front of them.")
	var kf := _fixture("king_falls_wins")
	var ruler: Dictionary = BattleCaptions._ruler_fell(kf.log, kf.report, BattleCaptions._rounds(kf.log)[3], 3)
	assert_eq(String(ruler.text), "Round 3: King Corvane I fell in the front rank (started with 18 hp, 0 kept power).")
	assert_eq(String(ruler.factor), "ruler", "the ruler's factor is in the report")


## Every caption rule's line for round `n` (BattleCaptions' rules one by one), whichever would win.
func _every_rule(battle_log: Dictionary, report: Dictionary, n: int) -> Array:
	var info := BattleCaptions._rounds(battle_log)
	if n >= info.size() or info[n].round_end < 0:
		return []
	var r: Dictionary = info[n]
	var out: Array = BattleCaptions._left(battle_log, report, r, n)
	for l in [BattleCaptions._ruler_fell(battle_log, report, r, n), BattleCaptions._held(battle_log, report, r, n),
			BattleCaptions._exposed(battle_log, report, info, n), BattleCaptions._impact(battle_log, report, r, n),
			BattleCaptions._totals(battle_log, report, r, n), BattleCaptions._luck(battle_log, report, r),
			BattleCaptions._round_cap(battle_log, report, n)]:
		if not l.is_empty():
			out.append(l)
	return out


## The exact numbers each kind of caption line must carry.
func _assert_rule_numbers(fx: Dictionary, n: int, l: Dictionary) -> void:
	var lg: Dictionary = fx.log
	var re := _round_end(lg, n)
	var text := String(l.text)
	var si := int(l.side)
	match String(l.rule):
		"left":
			var c := _morale_in(lg, n, si) if si >= 0 else {}
			if text.contains(" broke: it had lost "):
				assert_true(text.contains("lost %d%%, and morale %d holds only to %d%%" % [int(c.lost_pct), int(c.morale), int(c.break_pct)]), text)
		"held":
			var c := _morale_in(lg, n, si)
			assert_true(text.contains("%d%%" % int(c.lost_pct)) and text.contains("%d%%" % int(c.break_pct)), text)
		"totals":
			for s in lg.sides.size():
				if int(re.attacks[s]) > 0:
					var phrase := "%s dealt %d (%d of %d" % [lg.sides[s].name, int(re.dealt[s]), int(re.hits[s]), int(re.attacks[s])]
					assert_true(text.contains(phrase), "%s has \"%s\"" % [text, phrase])
					assert_true(String(fx.report.rounds[n - 1].line).contains("%s dealt %d damage (%d of %d hits)" % [lg.sides[s].name,
						int(re.dealt[s]), int(re.hits[s]), int(re.attacks[s])]), "the report's round line agrees with \"%s\"" % text)
		"luck":
			assert_eq(_numbers(text), [int(re.dealt[si]), roundi(float(re.expected[si]))], text)
			assert_true(float(re.dealt[si]) - float(re.expected[si]) >= BattleCaptions.LUCK_MIN, text)
		"impact":
			var worth := roundi(float(re.impact[si].get(String(l.factor), 0.0)))
			assert_true(text.contains("about %d damage" % worth), "%s: its worth is round_end.impact's %d" % [text, worth])
		"ruler":
			for e in lg.events:
				if e.t == "death" and int(e.n) == n and lg.fighters[int(e.f)].role == "ruler":
					var f: Dictionary = lg.fighters[int(e.f)]
					assert_true(text.contains("started with %d hp, %d kept power" % [int(f.hp), int(f.ruler.kept_power)]), text)


func test_the_same_log_gives_the_same_captions_and_moments() -> void:
	for name in ["starting_plains", "king_falls_wins", "mutual_rout"]:
		var fx := _fixture(name)
		var a := JSON.stringify([BattleCaptions.all_rounds(fx.log, fx.report), BattleMoments.key_moments(fx.log), BattleMoments.missing(fx.log)])
		var copy: Dictionary = BattleLog.from_json(BattleLog.to_json(fx.log)).log
		var b := JSON.stringify([BattleCaptions.all_rounds(copy, fx.report), BattleMoments.key_moments(copy), BattleMoments.missing(copy)])
		assert_eq(a, b, "%s: the same words from the same log" % name)
		var c := JSON.stringify([BattleCaptions.all_rounds(fx.log, fx.report), BattleMoments.key_moments(fx.log), BattleMoments.missing(fx.log)])
		assert_eq(a, c, "%s: and again" % name)
	# Pinned examples, as §4.8 words them.
	var sp := _fixture("starting_plains")
	assert_eq(BattleCaptions.text(BattleCaptions.for_round(sp.log, sp.report, 5)),
		"Round 5: Thornmane Clans broke: it had lost 66%, and morale 9 holds only to 65%.")
	assert_eq(BattleCaptions.text(BattleCaptions.for_round(sp.log, sp.report, 3)),
		"Round 3: the Warchief's +2 morale kept Thornmane Clans in the fight: it has lost 57%, and holds to 65% (55% without it).")
	var kc := _fixture("knights_charge")
	assert_eq(BattleCaptions.text(BattleCaptions.for_round(kc.log, kc.report, 1)), "Round 1: Aurel Crown's Knights' charge added about 7 damage.")
	var mr := _fixture("mutual_rout")
	assert_eq(BattleCaptions.for_round(mr.log, mr.report, 2).size(), 2, "a mutual rout says who kept the field")


# --- explanations -------------------------------------------------------------------------------------

func test_explain_attack_lines_sum_to_the_attacks_own_chance_and_damage() -> void:
	var clamped := 0
	var bonus := 0
	var minimum := 0
	for name in PINNED:
		var lg: Dictionary = _fixture(name).log
		for i in lg.events.size():
			var e: Dictionary = lg.events[i]
			if e.t != "attack":
				continue
			var x := BattleExplain.explain_attack(lg, i)
			var what := "%s event %d" % [name, i]
			assert_eq(Breakdown.sum_of_lines(x.chance), int(e.chance), "%s: the hit chance lines sum to the chance" % what)
			assert_eq(int(x.chance.total), int(e.chance), "%s: the chance is the log's" % what)
			assert_eq(Breakdown.sum_of_lines(x.damage), int(e.damage), "%s: the damage lines sum to the damage" % what)
			assert_eq(int(x.damage.total), int(e.damage), "%s: the damage is the log's" % what)
			assert_eq(Breakdown.sum_of_lines(x.attack), int(e.attack.value), "%s: attack" % what)
			assert_eq(Breakdown.sum_of_lines(x.defense), int(e.defense.value), "%s: defense" % what)
			var raw := int(e.base_hit) + AutoBattleResolver.HIT_PER_POINT * (int(e.attack.value) - int(e.defense.value))
			var has_clamp: bool = x.chance.lines.any(func(l): return String(l.label).begins_with("Never"))
			assert_eq(has_clamp, raw != int(e.chance), "%s: the clamp line shows exactly when the 30-90%% limits applied" % what)
			clamped += 1 if has_clamp else 0
			bonus += 1 if not e.bonus.is_empty() else 0
			minimum += 1 if x.damage.lines.any(func(l): return String(l.label).begins_with("At least")) else 0
			assert_true(String(x.roll).contains("Rolled %d of 100" % int(e.roll)), "%s: the roll" % what)
			for bd in [x.chance, x.damage, x.attack, x.defense]:
				_assert_codex(String(bd.codex), what)
				assert_true(TooltipText.from_breakdown(bd).contains("= %s: %d" % [bd.total_label, int(bd.total)]), "%s: renders as a tooltip" % what)
			if i % 7 == 0:  # the words, on a sample (the biggest battle has 898 attacks)
				for t in [x.chance.description, x.damage.description, x.attack.description, x.defense.description, x.roll, x.target_text, x.summary]:
					_assert_plain(String(t), lg, what)
	assert_true(clamped > 0, "the fixtures have clamped hit chances")
	assert_true(bonus > 0, "the fixtures have Charge bonuses")
	assert_eq(BattleExplain.explain_attack(_fixture("skirmish").log, 0), {}, "event 0 is a round, not an attack")
	# §5.4's worked example: 72% = base 60 + 4 x (attack 14 - defense 11); damage 5 = 7 - 2.
	var lg := {"terrain": "forest", "fighters": [{"name": "Tuskers", "side": 0, "role": "unit"}, {"name": "Spearmen", "side": 1, "role": "unit"}],
		"sides": [{"name": "Thornmane Clans"}, {"name": "Aurel Crown"}],
		"events": [{"t": "attack", "n": 2, "by": 0, "to": 1, "pool": 4, "pick": 2, "chance": 72, "roll": 37, "hit": true, "damage": 5, "bonus": {},
			"base_hit": 60, "attack": {"value": 14, "base": 11, "parts": {"Berserk": 3}}, "defense": {"value": 11, "base": 7,
			"parts": {"terrain": 2, "Shield Wall": 2}}, "reach": "front", "screened": false, "expected": 3.6}]}
	var x := BattleExplain.explain_attack(lg, 0)
	assert_eq(String(x.chance.description), "72% = base 60 + 4 x (attack 14 - defense 11)")
	assert_eq(String(x.damage.description), "5 = half of attack 14, rounded up (7) - a quarter of defense 11, rounded down (2)")
	assert_eq(String(x.roll), "Rolled 37 of 100: a hit (72 or less hits).")
	assert_eq(String(x.defense.description), "Spearmen's defense 11 = Spearmen 7 + forest (defending) 2 + Shield Wall 2")
	assert_eq(String(x.target_text), "attacking Aurel Crown's Spearmen, one of the 4 enemies it can reach")


func test_the_break_threshold_follows_the_resolvers_rule() -> void:
	assert_eq(BattleExplain.break_hp(76, 65), 26, "§4.7's example: 76 hp at morale 9 breaks at 26 hp or less")
	assert_eq(BattleExplain.break_text(76, 65), "breaks at 26 hp or less")
	var checks := 0
	for name in PINNED:
		var lg: Dictionary = _fixture(name).log
		for i in lg.events.size():
			var e: Dictionary = lg.events[i]
			if e.t != "morale":
				continue
			checks += 1
			var hp_start := int(lg.sides[int(e.side)].hp_start)
			var bp := int(e.break_pct)
			var what := "%s event %d (round %d)" % [name, i, int(e.n)]
			# The loss rule is the resolver's: it gives every morale check's own lost %.
			assert_eq(BattleExplain.lost_pct(hp_start, int(e.hp)), int(e.lost_pct), "%s: the lost %% rule is the resolver's" % what)
			var h := BattleExplain.break_hp(hp_start, bp)
			if h > 0:
				assert_true(BattleExplain.lost_pct(hp_start, h) >= bp, "%s: at %d hp the side breaks" % [what, h])
			if h + 1 <= hp_start:
				assert_true(BattleExplain.lost_pct(hp_start, h + 1) < bp, "%s: at %d hp it holds" % [what, h + 1])
			assert_eq(e.result != "holds", int(e.hp) <= h, "%s: it broke (or Iron Discipline held it) exactly when its hp was at or below %d" % [what, h])
			var xm := BattleExplain.explain_morale(lg, i)
			assert_eq(Breakdown.sum_of_lines(xm.morale), int(e.morale), "%s: the morale lines sum to its morale" % what)
			assert_eq(Breakdown.sum_of_lines(xm["break"]), bp, "%s: the break lines sum to its break %%" % what)
			assert_eq(int(xm.break_hp), h, what)
			_assert_plain(String(xm.result), lg, what)
			_assert_codex(String(xm.codex), what)
	assert_true(checks > 50, "every fixture's morale checks were checked (%d)" % checks)


func test_hovering_a_fighter_shows_the_logs_own_numbers() -> void:
	for name in ["starting_plains", "king_falls_wins", "dread_feast_frenzy", "skirmish", "round_cap_defender"]:
		var lg: Dictionary = _fixture(name).log
		var tl := BattleTimeline.build(lg)
		var points := [0, tl.size()]
		for n in range(1, tl.rounds() + 1):
			points.append(tl.round_start(n) + 1)  # the attacks beat
			points.append(tl.round_start(n) + 2)
		for i in points:
			var state := tl.state_at(i)
			for fid in lg.fighters.size():
				var x := BattleExplain.explain_fighter(tl, fid, i)
				var what := "%s fighter %d at event %d" % [name, fid, i]
				assert_eq(int(x.hp_value), int(state.fighters[fid].hp), "%s: hp" % what)
				assert_eq(int(x.pending), int(state.fighters[fid].pending), "%s: pending damage" % what)
				if int(x.attack_event) >= 0:
					var e: Dictionary = lg.events[int(x.attack_event)]
					assert_eq(int(e.by), fid, "%s: its own attack" % what)
					assert_eq(int(x.attack.chance.total), int(e.chance), "%s: the attack's chance is the log's" % what)
					assert_eq(int(x.attack.damage.total), int(e.damage), "%s: the attack's damage is the log's" % what)
					if state.beat == "attacks" and state.fighters[fid].alive:
						assert_eq(int(e.n), int(state.round), "%s: during the attacks it shows this round's attack" % what)
					else:
						assert_true(int(x.attack_event) < i, "%s: otherwise its last attack" % what)
				for t in x.lines:
					_assert_plain(String(t), lg, what)
				_assert_codex(String(x.codex), what)
				if i == tl.size():
					var fs: Dictionary = state.fighters[fid]
					if not fs.alive:
						assert_true(String(x.doing).begins_with("fell in round"), "%s: %s" % [what, x.doing])
					elif fs.fled:
						assert_true(String(x.doing).begins_with("fled"), "%s: %s" % [what, x.doing])
					elif fs.lost:
						assert_true(String(x.doing).begins_with("lost with its army"), "%s: %s" % [what, x.doing])
					elif int(state.winner) == int(lg.fighters[fid].side):
						assert_eq(String(x.doing), "won, still standing", what)
	# A fallen fighter's record is the log's: its attacks, hits and damage.
	var lg: Dictionary = _fixture("king_falls_wins").log
	var tl := BattleTimeline.build(lg)
	var king := -1
	for f in lg.fighters:
		if f.role == "ruler":
			king = int(f.id)
	var made := 0
	var hits := 0
	var dealt := 0
	for e in lg.events:
		if e.t == "attack" and int(e.by) == king:
			made += 1
			hits += 1 if e.hit else 0
			dealt += int(e.damage) if e.hit else 0
	var x := BattleExplain.explain_fighter(tl, king, tl.size())
	assert_eq(String(x.doing), "fell in round 3 after %d attacks (%d hits, %d damage)" % [made, hits, dealt])
	assert_true(String(x.who).ends_with("ruler, 0 kept power"), x.who)
	assert_true(x.gives.has("+2 morale to its side while it stands (ruler)"), str(x.gives))


func test_the_strength_bar_and_the_morale_tag() -> void:
	var lg: Dictionary = _fixture("starting_plains").log
	var tl := BattleTimeline.build(lg)
	var bar := BattleExplain.side_strength(lg, tl.state_at(0), 0)
	assert_eq(String(bar.text), "76 / 76 hp · morale 9 · breaks at 26 hp or less")
	assert_eq(int(bar.break_hp), 26)
	_assert_codex(String(bar.codex), "the strength bar")
	# Round 4: the Clans' War Bear fell, so the Crown's morale rose by its Fury.
	var found := false
	for i in lg.events.size():
		var e: Dictionary = lg.events[i]
		if e.t == "morale" and int(e.n) == 4 and int(e.side) == 1:
			var tag := BattleExplain.morale_change(lg, i)
			assert_eq(String(tag.text), "+2 morale: Thornmane Clans' War Bear fell (Fury -2)")
			assert_eq(int(tag.delta), 2)
			found = true
		elif e.t == "morale" and int(e.n) == 1:
			assert_eq(BattleExplain.morale_change(lg, i), {}, "no tag while morale is unchanged")
	assert_true(found, "the round-4 morale check")


# --- a log cut short, the codex, the tool, speed --------------------------------------------------------

func test_a_log_cut_short_degrades_gracefully() -> void:
	var fx := _fixture("starting_plains")
	var lg: Dictionary = fx.log.duplicate(true)
	var cut := 0
	for i in lg.events.size():
		if lg.events[i].t == "round" and int(lg.events[i].n) == 3:
			cut = i + 4
			break
	lg.events = lg.events.slice(0, cut)
	lg.truncated = true
	assert_eq(BattleLog.validate(lg), [], "a log cut short still validates")
	var all := BattleCaptions.all_rounds(lg, fx.report)
	assert_eq(all.size(), int(fx.report.rounds_fought), "every round of the report still has a caption")
	for rc in all:
		if int(rc.round) >= 3:
			assert_eq(String(rc.lines[0].rule), "cut", "round %d: the log stops before it ends" % int(rc.round))
		else:
			assert_ne(String(rc.lines[0].rule), "cut", "round %d is whole" % int(rc.round))
		_assert_codex(String(rc.lines[0].codex), "a cut caption")
	assert_eq(BattleCaptions.all_rounds(lg, {}).size(), 3, "without the report, the rounds the log holds")
	var kinds := BattleMoments.key_moments(lg).map(func(m): return m.kind)
	assert_eq(kinds, ["charge", "first_blood"], "the moments before the cut")
	var missing := BattleMoments.missing(lg)
	assert_true(String(missing.turning_point).contains("cut short"), missing.turning_point)
	assert_true(String(missing.rout).contains("cut short"), missing.rout)
	var tl := BattleTimeline.build(lg)
	for fid in lg.fighters.size():
		var x := BattleExplain.explain_fighter(tl, fid, tl.size())
		assert_false(x.lines.is_empty(), "fighter %d can still be explained" % fid)
	# An empty log gives nothing, with reasons, and no errors.
	var empty := {"sides": [], "fighters": [], "events": [], "truncated": true}
	assert_eq(BattleMoments.key_moments(empty), [])
	assert_eq(BattleMoments.missing(empty).size(), BattleMoments.KINDS.size())


func test_the_new_codex_entries_exist_in_one_block_after_the_battle_entries() -> void:
	var keys := RulesCodex.ENTRIES.keys()
	var at := keys.find("battle_odds") + 1
	assert_eq(keys.slice(at, at + NEW_CODEX.size()), NEW_CODEX, "the M3-2 block follows the battle entries")
	for key in NEW_CODEX:
		var e := RulesCodex.entry(key)
		assert_false(String(e.get("title", "")).is_empty(), "%s has a title" % key)
		var text := RulesCodex.text(key)
		assert_true(text.length() > 80, "%s explains itself" % key)
		assert_false(text.contains("[") or text.contains("_"), "%s: plain text, so tooltips can quote it" % key)
	assert_true(RulesCodex.text("battle_strength").contains("%d%%" % AutoBattleResolver.BREAK_BASE_PCT), "the break rule's numbers")
	for word in ["ahead from the start", "one round", "mutual rout", "round cap", "First to fall", "Turning point"]:
		assert_true(RulesCodex.text("battle_key_moments").contains(word), "battle_key_moments covers '%s'" % word)
	# The factor entries agree with the battle report viewer's, for every factor of every fixture.
	assert_eq(BattleExplain.FACTOR_ENTRIES, BattleReportViewer.FACTOR_ENTRIES, "the same factor map as the viewer")
	for name in PINNED:
		for f in _fixture(name).report.all_factors:
			assert_eq(BattleExplain.factor_entry(String(f.id)), BattleReportViewer._factor_entry(String(f.id)), "factor %s" % f.id)
	for kind in BattleMoments.KINDS:
		_assert_codex(String(BattleMoments.CODEX[kind]), "moment " + kind)


func test_the_dump_tool_prints_captions_and_moments() -> void:
	var fx := _fixture("king_falls_wins")
	var text := Dump.captions(fx.log, fx.report)
	assert_true(text.contains("Captions:") and text.contains("Key moments:"), "both sections")
	for rc in BattleCaptions.all_rounds(fx.log, fx.report):
		for l in rc.lines:
			assert_true(text.contains(String(l.text)), "the dump has \"%s\"" % l.text)
	for m in BattleMoments.key_moments(fx.log):
		assert_true(text.contains(String(m.text)), "the dump has \"%s\"" % m.text)
	assert_true(text.contains("Turning point: none."), "and the moments it doesn't have")


func test_moments_and_captions_for_the_biggest_battle_fit_the_budget() -> void:
	var fx := _fixture("biggest")
	var best := INF
	for run in 3:
		var t0 := Time.get_ticks_usec()
		BattleMoments.key_moments(fx.log)
		BattleMoments.missing(fx.log)
		BattleCaptions.all_rounds(fx.log, fx.report)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	assert_true(best <= MOMENTS_BUDGET_MS, "moments and captions for 277 fighters took %.1f ms (budget %.0f ms)" % [best, MOMENTS_BUDGET_MS])
	var tl := BattleTimeline.build(fx.log)
	var i := tl.round_start(3) + 50
	var state := tl.state_at(i)
	var hover := INF
	for run in 3:
		var t0 := Time.get_ticks_usec()
		for fid in range(0, fx.log.fighters.size(), 10):
			BattleExplain.explain_fighter(tl, fid, i, state)
		hover = minf(hover, (Time.get_ticks_usec() - t0) / 1000.0 / ceili(fx.log.fighters.size() / 10.0))
	assert_true(hover <= HOVER_BUDGET_MS, "one hover explanation took %.2f ms (budget %.1f ms)" % [hover, HOVER_BUDGET_MS])
