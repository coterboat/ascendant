extends "res://tests/test_case.gd"
## M5-7 (#118), design/M5_MAGIC_FOG.md §5.4: battle spells on screen. §5.4's Briar Snare caption, exactly; every
## spell cast is captioned at least once (the "first spell" rule); Sunburst's "greater" line; every spell factor
## has a phrase and a codex entry; the `spell` key moment and its reason when there is none; and BattleExplain's
## lines for a caster, a skipped spell, a hexed or shielded target and a bolt on a ruler.

const MB := preload("res://tests/magic_battle_fixtures.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const SPELL_FACTORS := ["spell_sunlance", "spell_shield_of_law", "spell_sunburst", "spell_briar_snare", "spell_bloodbolt", "spell_blood_moon"]

static var _runs := {}


func _run(name: String) -> Dictionary:
	if not _runs.has(name):
		var sd := Scenarios.find_seed(name)
		_runs[name] = Scenarios.run(name, maxi(1, sd))
	return _runs[name]


func _all_lines(lg: Dictionary, report: Dictionary) -> Array:
	var out := []
	for rc in BattleCaptions.all_rounds(lg, report):
		for l in rc.lines:
			out.append(l)
	return out


func test_the_briar_snare_caption_reads_exactly_as_the_spec() -> void:
	var minus := "−"
	for sd in range(1, 80):
		var s := MB.with_nodes(MB.game(), CLANS, ["briar_snare"])
		var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["knights", "knights", "knights", "knights", "knights", "knights", "knights", "knights"])
		var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers",
			"shamans"])
		var r := MB.fight(s, [a, b], "rivermarch", "", sd)
		for rc in BattleCaptions.all_rounds(r.log, r.result.report):
			var l: Dictionary = rc.lines[0]
			if l.rule != "impact" or l.factor != "spell_briar_snare":
				continue
			var n := int(rc.round)
			var clans := int(l.side)
			var snared := 0
			for e in MB.events(r.log, "cast", n):
				if e.spell == "briar_snare":
					snared += Array(e.targets).size()
			var re: Dictionary = MB.events(r.log, "round_end", n)[0]
			var worth := roundi(float(re.impact[clans]["spell_briar_snare"]))
			var want := "Round %d: the Thornmane Shamans' Briar Snare slowed %d Knights: %s%d attack this round, about %d damage saved." % [
				n, snared, minus, -int(MagicData.SPELLS.briar_snare.value), worth]
			assert_eq(String(l.text), want, "§5.4's caption, with this battle's numbers")
			assert_eq(String(l.codex), "spell_briar_snare", "it links the spell's codex entry")
			return
	fail("no battle captioned Briar Snare as its round's biggest worth")


func test_every_spell_cast_is_captioned_at_least_once() -> void:
	for name in Scenarios.MAGIC_NAMES:
		var r := _run(name)
		if not r.errors.is_empty():
			fail("%s: %s" % [name, r.errors])
			continue
		var text := " ".join(_all_lines(r.log, r.report).map(func(l): return String(l.text)))
		var cast := {}
		for e in MB.events(r.log, "cast"):
			cast[String(e.spell)] = true
		for sid in cast:
			assert_true(text.contains(MagicRules.spell_name(sid)), "%s: %s is named in a caption" % [name, MagicRules.spell_name(sid)])
		var firsts := _all_lines(r.log, r.report).filter(func(l): return l.rule == "first_spell")
		for l in firsts:
			assert_true(RulesCodex.ENTRIES.has(String(l.codex)) and String(l.codex).begins_with("spell_"), "%s: a first-spell line links its spell" % name)


func test_sunburst_gets_the_greater_line() -> void:
	var r := _run("magic_sunburst")
	assert_eq(r.errors, [])
	var first: Dictionary = BattleCaptions.for_round(r.log, r.report, 1)[0]
	var burst: Dictionary = MB.events(r.log, "cast", 1).filter(func(e): return e.spell == "sunburst")[0]
	var crown := int(r.log.fighters[int(burst.by)].side)
	var other := 1 - crown
	var want := "Round 1: the %s's Sunstone Adepts called down Sunburst: the %d %s fighters in the front rank have −%d attack this round." % [
		String(r.log.sides[crown].name).trim_prefix("the "), Array(burst.targets).size(), String(r.log.sides[other].name), -int(MagicData.SPELLS.sunburst.value)]
	if first.rule == "left" or first.rule == "ruler":
		return  # a rule above "greater" took line 1
	assert_eq(String(first.rule), "greater", "a tier III cast takes line 1")
	assert_eq(String(first.text), want)


func test_every_spell_factor_has_a_phrase_and_a_codex_entry() -> void:
	var seen := {}
	for name in Scenarios.MAGIC_NAMES:
		var r := _run(name)
		if not r.errors.is_empty():
			continue
		for f in r.report.all_factors:
			var id := String(f.id)
			if not id.begins_with("spell_") and not id.begins_with("morale_spell_"):
				continue
			seen[id] = true
			assert_true(RulesCodex.ENTRIES.has(BattleExplain.factor_entry(id)), "%s has a codex entry" % id)
			assert_eq(String(f.get("codex", "")), BattleExplain.factor_entry(id), "%s: the report names the same entry" % id)
			assert_false(String(f.brief).is_empty() or String(f.text).is_empty(), "%s has a clause and a brief" % id)
			if id.begins_with("morale_"):
				continue
			var si := BattleCaptions._side_of(r.log, String(f.faction))
			for n in range(1, int(r.report.rounds_fought) + 1):
				var re: Array = MB.events(r.log, "round_end", n)
				if re.is_empty() or roundi(float(re[0].impact[si].get(id, 0.0))) < 1:
					continue
				var phrase := BattleCaptions._worth_phrase(r.log, id, si, roundi(float(re[0].impact[si][id])), n)
				assert_false(phrase.is_empty(), "%s has a caption phrase" % id)
				assert_true(phrase.contains(MagicRules.spell_name(id.trim_prefix("spell_"))), "%s's phrase names it: %s" % [id, phrase])
				break
	for id in SPELL_FACTORS:
		assert_true(RulesCodex.ENTRIES.has(BattleExplain.factor_entry(id)), "%s has a codex entry" % id)
	assert_true(RulesCodex.ENTRIES.has(BattleExplain.factor_entry("morale_spell_dawn_blessing")), "the blessing's morale factor")
	for id in ["spell_sunlance", "spell_shield_of_law", "spell_briar_snare", "spell_bloodbolt"]:
		assert_true(seen.has(id), "the scenarios measure %s" % id)


func test_the_spell_moment() -> void:
	var r := _run("magic_shamans")
	var spells := BattleMoments.of_kind(r.log, "spell")
	assert_false(spells.is_empty(), "a first-spell moment")
	var first_cast := BattleLog.find_event(r.log, "cast")
	assert_eq(int(spells[0].event), first_cast, "it marks the first cast")
	assert_eq(String(spells[0].title), "First spell")
	assert_true(String(spells[0].text).contains(MagicRules.spell_name(String(r.log.events[first_cast].spell))), "and names the spell: %s" % spells[0].text)
	assert_true(RulesCodex.ENTRIES.has(String(spells[0].codex)))
	# Each tier III cast is a moment too.
	var burst := _run("magic_sunburst")
	var bm := BattleMoments.of_kind(burst.log, "spell")
	assert_true(bm.any(func(m): return String(burst.log.events[int(m.event)].get("spell", "")) == "sunburst"), "Sunburst is a moment")
	# None: the reason.
	var s := MB.game()
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers"])
	var plain := MB.fight(s, [a, b], "rivermarch", "", 1)
	assert_eq(String(BattleMoments.missing(plain.log).get("spell", "")), "No spells: neither side has a caster.")
	var m1 := Scenarios.run("starting_plains", maxi(1, Scenarios.fixture_seed("starting_plains")))
	assert_true(String(BattleMoments.missing(m1.log).get("spell", "")).contains("without magic"), "a battle without magic says so")


func test_battle_explain_lines_for_casters_skips_targets_and_resistance() -> void:
	var r := _run("magic_shamans")
	var lg: Dictionary = r.log
	var tl := BattleTimeline.build(lg)
	var i := BattleLog.find_event(lg, "cast")
	var c: Dictionary = lg.events[i]
	var x := BattleExplain.explain_cast(lg, i)
	assert_true(String(x.summary).contains(MagicRules.spell_name(String(c.spell))), "the cast's summary: %s" % x.summary)
	assert_true(String(x.why).contains("spellbook"), "why it cast that spell: %s" % x.why)
	assert_true(String(x.text).contains("Spells always land: they don't roll."), "spells never roll")
	assert_eq(String(x.codex), "spell_" + String(c.spell))
	# Hovering the caster during the casts beat.
	var hover := BattleExplain.explain_fighter(tl, int(c.by), i + 1)
	assert_true(String(hover.doing).begins_with("casting %s" % MagicRules.spell_name(String(c.spell))), "the hover says it is casting: %s" % hover.doing)
	assert_true(hover.lines.any(func(l): return String(l).contains("Spells always land")), "and that spells always land")
	# A hexed attacker's attack breakdown names the spell.
	for e in lg.events:
		if e.t == "attack" and e.attack.parts.has("spell_briar_snare"):
			var ex := BattleExplain.explain_attack(lg, lg.events.find(e))
			assert_true(String(ex.attack.description).contains("Briar Snare"), "the attack names Briar Snare: %s" % ex.attack.description)
			break
	# A skipped spell names its reason; a bolt on a ruler its resistance.
	var reg := _run("magic_regent")
	for k in reg.log.events.size():
		var e: Dictionary = reg.log.events[k]
		if e.t == "cast" and not Array(e.get("skipped", [])).is_empty():
			var ex := BattleExplain.explain_cast(reg.log, k)
			assert_true(String(ex.text).contains("skipped"), "a skipped spell is named: %s" % ex.text)
			break
	var s := MB.with_nodes(MB.game({CLANS: MB.AVATAR}), CROWN, ["sunlance"])
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "adepts"])
	var avatar := MB.ruler_at(s, CLANS, "rivermarch", 6)
	var rr := MB.fight(s, [a, avatar], "rivermarch", "", 1)
	var ci := BattleLog.find_event(rr.log, "cast")
	var line := String(BattleExplain.explain_cast(rr.log, ci).text)
	var rank := RulerRules.ability_rank(6)
	var lance := int(MagicData.SPELLS.sunlance.value)
	assert_true(line.contains("Sunlance %d − the Great Thornmane's spell resistance %d (ability rank %d) = %d" % [lance, rank / MagicData.RULER_RESIST,
		rank, lance - rank / MagicData.RULER_RESIST]), "the resistance line: %s" % line)
