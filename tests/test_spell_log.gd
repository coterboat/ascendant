extends "res://tests/test_case.gd"
## M5-7 (#118), design/M5_MAGIC_FOG.md §5.4: battle spells in the battle event log. The scripted magic scenarios
## (tools/battle_log/scenarios.gd MAGIC_NAMES) pass validate, verify_draws and cross_check; the log's magic
## additions (the "magic" flag, sides' casters, spellbook and enchantments, fighters' mastery, the cast event, the
## bleed and its closing, the moon's heal) are read back by BattleTimeline; a tampered cast is caught; and playback
## never changes the outcome, at M3's three levels (rules, the player, and no RNG in the battle UI).

const MB := preload("res://tests/magic_battle_fixtures.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const CROWN := "kingdom"
const CLANS := "beasts"

static var _runs := {}


func _run(name: String) -> Dictionary:
	if not _runs.has(name):
		var sd := Scenarios.find_seed(name)
		_runs[name] = Scenarios.run(name, maxi(1, sd)) if sd > 0 else {"log": {}, "report": {}, "errors": ["%s shows nothing on any seed" % name]}
		_runs[name]["seed"] = sd
	return _runs[name]


func test_every_magic_scenario_passes_the_log_checks() -> void:
	assert_true(Scenarios.MAGIC_NAMES.size() >= 5, "at least five scripted magic battles")
	var spells := {}
	for name in Scenarios.MAGIC_NAMES:
		assert_true(Scenarios.WHAT.has(name), "%s says what it is for" % name)
		var r := _run(name)
		assert_eq(r.errors, [], "%s fights" % name)
		if not r.errors.is_empty():
			continue
		assert_true(Scenarios.shows(name, r.log, r.report), "%s shows what it is for" % name)
		assert_true(r.log.get("magic", false), "%s: a magic log" % name)
		assert_eq(BattleLog.validate(r.log), [], "%s: validate" % name)
		assert_eq(BattleLog.verify_draws(r.log), [], "%s: verify_draws (casts draw nothing)" % name)
		assert_eq(BattleLog.cross_check(r.log, r.report), [], "%s: cross_check" % name)
		for e in MB.events(r.log, "cast"):
			spells[String(e.spell)] = true
		# A JSON round trip keeps it exactly.
		var back := BattleLog.from_json(BattleLog.to_json(r.log))
		assert_eq(back.errors, [], "%s: reads back" % name)
		assert_eq(back.log, r.log, "%s: the same log after JSON" % name)
	for sid in ["sunlance", "shield_of_law", "sunburst", "briar_snare", "bloodbolt"]:
		assert_true(spells.has(sid), "the scenarios cast %s" % sid)


func test_the_magic_additions_are_in_the_log_and_only_there() -> void:
	var r := _run("magic_shamans")
	var lg: Dictionary = r.log
	for s in lg.sides:
		for key in ["casters", "spellbook", "enchantments"]:
			assert_true(s.has(key), "side %d has %s" % [int(s.index), key])
		for fid in s.casters:
			assert_true(lg.fighters[int(fid)].has("mastery"), "caster %d has its mastery" % int(fid))
	var clans := 0 if lg.sides[0].faction == CLANS else 1
	assert_eq(lg.sides[clans].spellbook, MagicData.SPELLBOOK[CLANS], "the Clans' spellbook, on spells in order")
	var cast: Dictionary = MB.events(lg, "cast")[0]
	for key in ["n", "by", "spell", "school", "kind", "bonus", "targets", "damage", "self", "why"]:
		assert_true(cast.has(key), "a cast has %s" % key)
	assert_eq(String(cast.school), String(MagicData.SPELLS[String(cast.spell)].school), "its school is the data's")
	assert_eq(String(cast.kind), String(MagicData.SPELLS[String(cast.spell)].kind), "its kind is the data's")
	# Within a round: round, then every cast, then the attacks.
	var events: Array = lg.events
	for i in events.size():
		if events[i].t != "cast":
			continue
		var k := i - 1
		while events[k].t == "cast":
			k -= 1
		assert_eq(String(events[k].t), "round", "event %d: casts come right after the round event" % i)
	# The report's sides gain casters and spells_cast in a magic game, with the casts counted.
	var sr: Dictionary = r.report.sides[clans]
	assert_true(sr.has("casters") and sr.has("spells_cast"), "the report's side lists its casters and spells")
	var counted := 0
	for sid in sr.spells_cast:
		counted += int(sr.spells_cast[sid])
	assert_eq(counted, MB.events(lg, "cast").filter(func(e): return int(lg.fighters[int(e.by)].side) == clans).size(), "every cast counted")
	# Not in a log without magic.
	var plain := Scenarios.run("starting_plains", maxi(1, Scenarios.fixture_seed("starting_plains")))
	assert_false(plain.log.has("magic"), "an M1 log has no magic flag")
	assert_false(plain.log.sides[0].has("casters"), "no casters")
	assert_false(plain.report.sides[0].has("spells_cast"), "no spells cast in the report")


func test_the_timeline_folds_casts_bleeds_and_statuses() -> void:
	var r := _run("magic_shamans")
	var lg: Dictionary = r.log
	var tl := BattleTimeline.build(lg)
	for i in lg.events.size():
		var e: Dictionary = lg.events[i]
		if e.t != "cast":
			continue
		var before := tl.state_at(i)
		var after := tl.state_at(i + 1)
		assert_eq(String(after.beat), "casts", "event %d: the casts beat" % i)
		for id in e.targets:
			var fid := int(id)
			if String(e.kind) == "bolt":
				assert_eq(int(after.fighters[fid].pending) - int(before.fighters[fid].pending), int(e.damage), "a bolt's damage waits as pending")
			else:
				var st := tl.statuses(after, fid)
				var key := "snared" if String(e.kind) == "hex" else "spell_shielded"
				assert_true(bool(st.get(key, false)), "event %d: fighter %d is %s" % [i, fid, key])
				assert_true(st.get("spell_parts", {}).has("spell_" + String(e.spell)), "its part")
	# The next round clears them.
	for n in range(2, tl.rounds() + 1):
		var st := tl.state_at(tl.round_start(n) + 1)
		for fid in lg.fighters.size():
			assert_false(bool(tl.statuses(st, fid).get("snared", false)), "round %d starts with nobody snared" % n)
	# The bleed, the closed bleed and the moon's heal fold into hp exactly as final_hp does.
	for name in Scenarios.MAGIC_NAMES:
		var x := _run(name)
		if not x.errors.is_empty():
			continue
		var fin := BattleTimeline.build(x.log).final_state()
		var hp := BattleLog.final_hp(x.log)
		for fid in x.log.fighters.size():
			assert_eq(int(fin.fighters[fid].hp), int(hp[fid]), "%s: fighter %d's hp folded" % [name, fid])


func test_a_tampered_cast_is_caught() -> void:
	var r := _run("magic_regent")
	var lg: Dictionary = r.log.duplicate(true)
	var i := BattleLog.find_event(lg, "cast")
	var bolt := -1
	for k in lg.events.size():
		if lg.events[k].t == "cast" and lg.events[k].kind == "bolt":
			bolt = k
			break
	assert_true(bolt >= 0, "a bolt to tamper with")
	lg.events[bolt].damage = int(lg.events[bolt].damage) + 3
	assert_false(BattleLog.cross_check(lg, r.report).is_empty(), "cast damage must equal its part of the wounds")
	var bad: Dictionary = r.log.duplicate(true)
	bad.events[i].spell = "fireball"
	assert_false(BattleLog.validate(bad).is_empty(), "an unknown spell is caught")
	bad = r.log.duplicate(true)
	bad.events[i].by = int(lg.sides[0].fighters[0]) if not Array(lg.sides[0].casters).has(lg.sides[0].fighters[0]) else int(lg.sides[1].fighters[0])
	assert_false(BattleLog.validate(bad).is_empty() and BattleLog.cross_check(bad, r.report).is_empty(), "a cast by a fighter that isn't a caster is caught")
	# A caster that also attacked in the round it cast.
	bad = r.log.duplicate(true)
	var c: Dictionary = bad.events[i]
	for k in bad.events.size():
		var e: Dictionary = bad.events[k]
		if e.t == "attack" and int(e.n) == int(c.n):
			e.by = int(c.by)
			break
	assert_false(BattleLog.cross_check(bad, r.report).is_empty(), "a caster that casts doesn't attack that round")


func test_playback_never_changes_the_outcome() -> void:
	for name in Scenarios.MAGIC_NAMES:
		var r := _run(name)
		if not r.errors.is_empty():
			continue
		# Rules: recording on or off, the same report, winner and RNG state.
		var d := Scenarios.direct(name)
		var sd := int(r.seed)
		var on := AutoBattleResolver.fight(d.sides, d.ctx, SeededRNG.new(sd), true)
		var rng := SeededRNG.new(sd)
		var off := AutoBattleResolver.fight(d.sides, d.ctx, rng, false)
		assert_eq(JSON.stringify(off.result.report), JSON.stringify(on.result.report), "%s: the same report with recording off" % name)
		assert_eq(Serial.int64_to_str(rng.get_state()), String(on.log.rng.after), "%s: the same RNG state" % name)
		# The player: playing it to the end changes neither the log nor the report, and its state at every
		# beat that shows a log event other than an attack is the timeline's.
		var lg_before := JSON.stringify(r.log)
		var rep_before := JSON.stringify(r.report)
		var p := BattlePlayer.new(r.log, r.report)
		var tl := p.timeline()
		assert_true(p.beats().any(func(b): return b.kind == "cast"), "%s: the player has cast beats" % name)
		for b in p.beats():
			assert_true(BattlePlayer.KINDS.has(b.kind), "%s: a known beat kind %s" % [name, b.kind])
		p.play()
		var guard := 0
		while p.next_beat() < p.beats().size() and guard < 100000:
			var b: Dictionary = p.beats()[p.next_beat()]
			if int(b.event) >= 0 and String(b.kind) != "attack_started" and String(b.kind) != "attack_landed" and String(b.kind) != "moment" \
					and String(r.log.events[int(b.event)].t) != "attack":
				assert_eq(p.state(), tl.state_at(int(b.event)), "%s: the state before beat %d (%s)" % [name, int(b.i), b.kind])
			p.advance(0.05)
			guard += 1
		assert_eq(p.state(), tl.final_state(), "%s: the end state" % name)
		assert_eq(JSON.stringify(r.log), lg_before, "%s: the log is unchanged by playback" % name)
		assert_eq(JSON.stringify(r.report), rep_before, "%s: the report is unchanged by playback" % name)
		# The why panel and the captions read it without changing it.
		var why := BattleWhy.new(p)
		var seen_cast := false
		for k in p.beats().size() + 1:
			var w := why.at(k, tl.state_at(0))
			for f in w.feed:
				if String(f.kind) == "cast":
					seen_cast = true
		assert_true(seen_cast, "%s: the why panel's feed lists casts" % name)
		assert_eq(JSON.stringify(r.log), lg_before, "%s: still unchanged" % name)
