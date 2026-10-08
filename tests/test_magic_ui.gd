extends "res://tests/test_case.gd"
## M5-8 (#119) magic on screen, headless in the M1 UI-test style (design/M5_MAGIC_FOG.md §3-§8, §11, §11.2): the Magic tab's
## cards (what researching one first does to your transformation, Shield of Law's field line, tier III and closed cards
## with their reasons), the battle spellbook previewed per army from the real cast step (against scripted battles), the
## spells a move forecast names, the cast dialog (only legal targets, the rules' forecast word for word, the ring on the
## board, the budget line), enchantment badges, the army panel's casters, a mage's card and the second-rank warning, the
## first-spell text and the report's rows, the Magic chip, the lock-in preview's magic row, and the build screen's Tithe of
## Blood line. Every expected number and word is derived from MagicRules, Forecast, Breakdown, AscensionRules and the real
## resolver, never hardcoded.

const Fx := preload("res://tests/magic_battle_fixtures.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 21
const LINK_LINE := "Codex: %s (right-click or F1 to open)"
## Ids that must never reach player-facing text.
const RAW_IDS := ["kingdom", "beasts", "sunlance", "shield_of_law", "briar_snare", "bloodbolt", "dawn_blessing", "sanctum_ward",
	"bloodrot", "call_the_pack", "far_sight", "tithe_of_blood", "ever_regent", "adepts", "shamans", "thornwolves", "_"]


# --- builders --------------------------------------------------------------------------------------------

## A magic game at the start with the Regent and the Ninth Fang (builds as GameState.with_magic takes them).
func _magic(builds: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.with_magic(SEED, builds, errors)
	assert_eq(errors, [], "the magic game sets up")
	return s


## A game screen at seat 1's orders (hotseat) for `s`, the players in `players` order.
func _screen(s: GameState, players: Array = [CROWN, CLANS]) -> GameScreen:
	var session := GameSession.new(s, players, 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Magic UI", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


## The Clans as the Ninth Fang with Tithe of Blood, Bloodrot, Call the Pack and Briar Snare known, an army of 2 Shamans and
## 6 Tuskers at Thornvale (two provinces from Crownkeep); the Crown knows Sanctum Ward. 200 gold each.
func _clans_state(fog: bool = false) -> GameState:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	assert_true(s != null)
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	s = AscensionRules.with_nodes(s, CROWN, ["sunlance", "shield_of_law", "sanctum_ward", "dawn_blessing"])
	if fog:
		s.setup_fog([])
	for f in s.factions:
		f.gold = 200
	Fx.army(s, CLANS, s.new_army_id(CLANS), "thornvale", ["shamans", "shamans", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers"])
	s.find_province("thornvale").owner = CLANS
	return s


func _army_at(s: GameState, fid: String, where: String) -> Army:
	for a in s.armies:
		if a.owner == fid and a.location == where and a.ruler == null:
			return a
	return null


func _texts(node: Node) -> String:
	var out := PackedStringArray()
	_collect(node, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).text)
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows the raw id '%s'" % [what, id])


## Every shown Label or Button under `root` whose text has a digit carries a breakdown (meta "breakdown") that starts its
## tooltip and whose lines sum to its total, unless it is a rule in words (meta "rule_text"). Returns how many it checked.
func _assert_numbers_explained(root: Node, what: String) -> int:
	var checked := 0
	var digit := RegEx.create_from_string("\\d")
	for n in root.find_children("*", "", true, false):
		if not (n is Label or n is Button):
			continue
		if not (n as CanvasItem).visible or not (n as CanvasItem).is_visible_in_tree() and n.is_inside_tree():
			continue
		var text: String = n.text
		if digit.search(text) == null or n.has_meta("rule_text"):
			continue
		if n is Button and (n as Button).text.begins_with("Research:"):
			continue  # the research chip is checked on its own
		checked += 1
		assert_true(n.has_meta("breakdown"), "%s: '%s' (%s) has a breakdown" % [what, text, n.name])
		if not n.has_meta("breakdown"):
			continue
		var b: Dictionary = n.get_meta("breakdown")
		assert_true((n as Control).tooltip_text.begins_with(TooltipText.from_breakdown(b)), "%s: '%s' shows its breakdown on hover" % [what, text])
		assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: '%s' breakdown lines sum to its total" % [what, text])
	return checked


## Every control under `root` with a codex link names an existing entry at the end of its tooltip. Returns how many.
func _assert_links_valid(root: Node, what: String) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Control and node.has_meta(CodexLink.META):
			var key := String(node.get_meta(CodexLink.META))
			assert_true(RulesCodex.ENTRIES.has(key), "%s: '%s' links codex key %s, which exists" % [what, node.name, key])
			var title := String(RulesCodex.entry(key).get("title", ""))
			assert_true((node as Control).tooltip_text.replace("\n", " ").ends_with(LINK_LINE % title), "%s: '%s' ends its tooltip with its codex line" % [what, node.name])
			n += 1
	return n


## Every shown Label or Button under `root` that shows a number or a rule has a codex link (itself or a parent).
func _assert_terms_linked(root: Node, what: String) -> int:
	var n := 0
	var digit := RegEx.create_from_string("\\d")
	for node in root.find_children("*", "", true, false):
		if not (node is Label or node is Button) or not (node as CanvasItem).visible:
			continue
		if digit.search(node.text) == null and not node.has_meta("rule_text"):
			continue
		if (node is Button and (node as Button).text.begins_with("Research:")) or String(node.name) == "Footer":
			continue
		n += 1
		assert_true(CodexLink.key_at(node) != "" or node.get_parent() is Container and CodexLink.key_at(node.get_parent()) != "",
			"%s: '%s' links a codex entry" % [what, String(node.text).left(60)])
	return n


# --- the cards ------------------------------------------------------------------------------------------

func test_a_card_says_what_researching_it_first_does_to_your_transformation() -> void:
	var s := _magic({CROWN: "regents_court"})
	for nid in MagicRules.arcana_ids(CROWN):
		var c := MagicView.card(s, CROWN, String(nid))
		var d := Forecast.arcana_delay(s, CROWN, String(nid))
		assert_true(d.applies, "%s has a delay line before the transformation" % nid)
		# From the research forecast's own ETA: the road to the nearest side with and without the node (and what it needs) first.
		var chain := MagicRules.reach_chain(s, CROWN, String(nid))
		var extra := 0
		for k in chain:
			extra += AscensionRules.node_cost(String(k))
		assert_eq(int(d.extra), extra, "%s adds its own cost and what it needs" % nid)
		var best := -1
		for side in PathData.BRANCHES:
			if String(PathData.BRANCHES[side].faction) != CROWN:
				continue
			var need := int(AscensionRules.road_need(s, CROWN, String(side)).need)
			best = need if best < 0 else mini(best, need)
		var pool := AscensionRules.research_points(s, CROWN)
		var rate := int(AscensionRules.research_rate(s, CROWN).rate)
		var was := AscensionRules.eta(best, pool, rate)
		var now := AscensionRules.eta(best + extra, pool, rate)
		assert_eq(int(d.delay), now - was, "%s: the delay is the difference of the two ETAs" % nid)
		assert_eq(int(d.before), s.current_turn + was)
		assert_eq(int(d.after), s.current_turn + now)
		assert_eq(Breakdown.sum_of_lines(d.breakdown), int(d.breakdown.total), "%s: the breakdown sums" % nid)
		assert_eq(int(d.breakdown.total), extra)
		assert_true(String(c.detail).contains(String(d.text)), "the hover has the sentence")
		assert_eq(String(c.delay_line), MagicView.delay_line(d))
		if int(d.delay) > 0:
			assert_true(String(c.delay_line).contains("by about"), c.delay_line)
			assert_true(String(c.delay_line).contains("%d → %d" % [int(d.before), int(d.after)]), c.delay_line)
	# Slack absorbs a cheap spell: with the research saved already, the first spell moves nothing.
	var rich := _magic({CROWN: "regents_court"})
	rich.find_faction(CROWN).research_points = 500
	var free := Forecast.arcana_delay(rich, CROWN, "sunlance")
	assert_eq(int(free.delay), 0)
	assert_true(String(free.text).contains("doesn't move your transformation"), free.text)
	# Nothing to say about a node already researched or closed, or once the people have transformed.
	var done := AscensionRules.with_nodes(_magic({CROWN: "regents_court"}), CROWN, ["sunlance"])
	assert_false(bool(Forecast.arcana_delay(done, CROWN, "sunlance").applies), "researched")
	assert_eq(String(MagicView.card(done, CROWN, "sunlance").delay_line), "")
	var transformed := AscensionRules.with_nodes(_magic({CROWN: "regents_court"}), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"])
	assert_false(bool(Forecast.arcana_delay(transformed, CROWN, "shield_of_law").applies), "after the transformation there is nothing to delay")
	# Without magic no card: the function says nothing.
	assert_false(bool(Forecast.arcana_delay(GameState.with_paths(SEED), CROWN, "sunlance").applies))


func test_the_research_panel_puts_the_delay_on_the_card_with_its_breakdown() -> void:
	var s := _magic({CROWN: "regents_court"})
	var panel := ResearchPanel.new()
	panel.show_for(s, CROWN)
	panel.show_magic()
	var seen := 0
	for nid in MagicRules.arcana_ids(CROWN):
		var card: PanelContainer = panel.cards[nid]
		var d := Forecast.arcana_delay(s, CROWN, String(nid))
		var label := card.find_child("Delay", true, false) as Label
		assert_true(label != null, "%s: a delay line on its face" % nid)
		if label == null:
			continue
		assert_eq(label.text, MagicView.delay_line(d))
		assert_eq(label.get_meta("breakdown"), d.breakdown)
		seen += 1
	assert_eq(seen, 8)
	_assert_numbers_explained(panel, "the Magic tab")
	panel.free()


func test_shield_of_laws_card_starts_with_its_field_line_and_hexes_and_shields_say_what_they_are_worth() -> void:
	var s := _magic({CROWN: "regents_court", CLANS: "beast_god_unbound"})
	var shield := MagicView.card(s, CROWN, "shield_of_law")
	assert_true(String(shield.detail).begins_with(MagicView.FIELD_LINE), "the card starts with the field-spell line")
	assert_false(String(MagicView.card(s, CROWN, "sunlance").detail).contains(MagicView.FIELD_LINE), "no other card has it")
	# A shield's and a hex's worth, from the battle's own hit chance and damage.
	var rival := Forecast.rival_of(s, CROWN)
	assert_eq(rival, CLANS)
	for case in [[CROWN, "shield_of_law"], [CLANS, "briar_snare"]]:
		var fid := String(case[0])
		var sid := String(case[1])
		var other := Forecast.rival_of(s, fid)
		var w := Forecast.spell_worth(s, fid, sid)
		assert_true(w.ok, sid)
		var hitters := Forecast.regular_types(s, other, 6, true)
		var best := String(hitters[0])
		for t in hitters:
			if int(RulerRules.unit_stats(s, other, String(t)).attack) > int(RulerRules.unit_stats(s, other, best).attack):
				best = String(t)
		var attack := int(RulerRules.unit_stats(s, other, best).attack)
		var defense := int(RulerRules.unit_stats(s, fid, String(Forecast.regular_types(s, fid, 1)[0])).defense)
		var part := int(MagicData.SPELLS[sid].value)
		var is_shield := String(MagicData.SPELLS[sid].kind) == "shield"
		var a2 := attack + (0 if is_shield else part)
		var d2 := defense + (part if is_shield else 0)
		var count := int(MagicRules.spell_numbers(sid, int(MagicRules.mastery_bonus(s, fid, String(MagicData.SPELLS[sid].school)).value)).count)
		var before := roundi(count * AutoBattleResolver.hit_chance(attack, defense) / 100.0 * AutoBattleResolver.damage(attack, defense))
		var after := roundi(count * AutoBattleResolver.hit_chance(a2, d2) / 100.0 * AutoBattleResolver.damage(a2, d2))
		assert_eq(int(w.saved), before - after, "%s: damage saved over its units, from the battle's numbers" % sid)
		assert_true(int(w.saved) > 0, sid)
		assert_eq(Breakdown.sum_of_lines(w.breakdown), int(w.breakdown.total))
		assert_eq(int(w.breakdown.total), int(w.saved))
		assert_true(String(MagicView.card(s, fid, sid).detail).contains(String(w.text)), "the hover has it")
		assert_false(String(w.text).contains("Spearmen deals"), String(w.text))
	# Bolts have no such line; a ritual neither.
	assert_false(bool(Forecast.spell_worth(s, CROWN, "sunlance").ok))
	assert_false(bool(Forecast.spell_worth(s, CROWN, "sanctum_ward").ok))


func test_tier_iii_and_closed_cards_show_their_reasons() -> void:
	var s := _magic({CROWN: "regents_court", CLANS: "beast_god_unbound"})
	for fid in [CROWN, CLANS]:
		for school in MagicRules.schools(fid):
			var greater := String(MagicRules.school_data(school).nodes[3])
			var node := AscensionRules.node_data(greater)
			var oath := String(Array(node.requires).filter(func(r): return AscensionRules.is_oath(String(r)))[0])
			var c := MagicView.card(s, fid, greater)
			assert_eq(String(c.state), AscensionRules.NEEDS)
			assert_true(String(c.state_line).contains(AscensionRules.node_ref(oath)), "%s: the face names its Oath (%s)" % [greater, c.state_line])
			assert_true(String(c.state_line).contains(AscensionRules.node_name(String(node.requires[0]))), "and the ritual it needs first: %s" % c.state_line)
			assert_true(String(c.reason).contains("Only that Oath opens"), c.reason)
			assert_true(String(c.reason).contains("%d research" % AscensionRules.node_cost(String(node.requires[0]))), "the cost of what it needs: %s" % c.reason)
			# Swear the other Oath: closed, with the plain reason.
			var other_school := String(MagicRules.schools(fid).filter(func(x): return x != school)[0])
			var other_oath := String(MagicRules.school_data(other_school).nodes[3])
			var other_oath_node := String(Array(AscensionRules.node_data(other_oath).requires).filter(func(r): return AscensionRules.is_oath(String(r)))[0])
			var swore := AscensionRules.with_nodes(s, fid, _ordinary_pair(fid) + [other_oath_node])
			var closed := MagicView.card(swore, fid, greater)
			assert_eq(String(closed.state), AscensionRules.CLOSED, "%s closes when you swear the other Oath" % greater)
			assert_true(String(closed.reason).contains("Closed"), closed.reason)
			assert_true(String(closed.reason).contains(AscensionRules.node_ref(other_oath_node).trim_prefix("the ")), closed.reason)
	# On the panel: the needs line is on the face, and a closed card shows its reason under the state.
	var swore_crown := AscensionRules.with_nodes(s, CROWN, _ordinary_pair(CROWN) + ["crown_oath_dawn"])
	var panel := ResearchPanel.new()
	panel.show_for(swore_crown, CROWN)
	panel.show_magic()
	var bastion: PanelContainer = panel.cards["bastion"]
	assert_eq(String(bastion.get_meta("state")), AscensionRules.CLOSED)
	var why := bastion.find_child("Reason", true, false) as Label
	assert_true(why != null and why.text.contains("Closed"), "the closed card's reason is on its face")
	var sunburst: PanelContainer = panel.cards["sunburst"]
	assert_true((sunburst.find_child("State", true, false) as Label).text.begins_with("Needs"), "tier III says what it needs")
	panel.free()
	var fresh := ResearchPanel.new()
	fresh.show_for(s, CROWN)
	fresh.show_magic()
	var state_text := (fresh.cards["sunburst"].find_child("State", true, false) as Label).text
	assert_true(state_text.contains("Dawn Blessing") and state_text.contains("Oath of the Dawn"), state_text)
	fresh.free()


## Two ordinary path nodes of `fid`, to open an Oath.
func _ordinary_pair(fid: String) -> Array:
	var out := []
	for nid in AscensionRules.node_ids(fid):
		if AscensionRules.is_ordinary(String(nid)) and out.size() < 2:
			out.append(String(nid))
	return out


# --- the spellbook, previewed from the real cast step -----------------------------------------------------

## The stand-in foe a preview fights, built here from the rival's roster: the first three regular non-mage units (front rank
## first), eight of each (Forecast.STAND_IN_*).
func _foe_types(s: GameState, fid: String) -> Array:
	var front := []
	var back := []
	for ut in s.find_faction(fid).unit_types:
		if ut.is_commander or ut.is_ruler or ut.summoned or MagicRules.is_mage(ut):
			continue
		(back if ut.trait_id == "Volley" else front).append(String(ut.id))
	var out := []
	for t in (front + back).slice(0, Forecast.STAND_IN_TYPES):
		for _i in Forecast.STAND_IN_EACH:
			out.append(t)
	return out


## The cast events of round 1 of a recorded battle, as [fighter name, spell id] in the order cast, for the fighters on `side`.
func _round_one(battle_log: Dictionary, side: int) -> Array:
	var names := {}
	for f in battle_log.fighters:
		names[int(f.id)] = f
	var out := []
	for e in Fx.events(battle_log, "cast", 1):
		var f: Dictionary = names[int(e.by)]
		if int(f.side) == side:
			out.append([String(f.name), String(e.spell)])
	return out


func _preview_pairs(result: Dictionary, fid: String) -> Array:
	var out := []
	for c in result.casts:
		if String(c.faction) == fid and int(c.round) == 1:
			out.append([String(c.caster), String(c.spell)])
	return out


## The scripted position of the spellbook tests: the Crown's Regent at Crownkeep, 2 Adepts with 6 Spearmen at Highcrag (hills),
## 3 Adepts with Spearmen and Knights at Stonegate (hills, a fort); the Clans know Briar Snare and Bloodbolt. Spells researched.
func _scripted() -> GameState:
	var s := Fx.game({CROWN: Fx.REGENT, CLANS: Fx.AVATAR})
	s = Fx.with_nodes(s, CROWN, ["sunlance", "shield_of_law", "dawn_blessing", "sanctum_ward"])
	s = Fx.with_nodes(s, CLANS, ["briar_snare", "bloodbolt"])
	Fx.army(s, CROWN, "kingdom-1", "highcrag", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "adepts", "adepts"])
	Fx.army(s, CROWN, "kingdom-2", "stonegate", ["spearmen", "spearmen", "spearmen", "spearmen", "knights", "knights", "adepts", "adepts", "adepts"])
	return s


func test_the_spellbook_preview_equals_the_resolvers_casts_on_scripted_battles() -> void:
	var s := _scripted()
	var checked := 0
	for book in [{"order": MagicData.SPELLBOOK[CROWN], "off": []}, {"order": ["shield_of_law", "sunlance", "sunburst"], "off": []},
			{"order": MagicData.SPELLBOOK[CROWN], "off": ["sunlance"]}, {"order": ["sunburst", "shield_of_law", "sunlance"], "off": ["shield_of_law"]}]:
		var order := SpellbookOrder.new(book.order, book.off)
		var rows := Forecast.spellbook_preview(s, CROWN, [order])
		assert_eq(rows.map(func(r): return String(r.province)), ["crownkeep", "highcrag", "stonegate"], "a row for each province with casters")
		var view := MagicView.spellbook_preview(s, CROWN, [order])
		assert_eq(view.map(func(r): return String(r.province)), ["crownkeep", "highcrag", "stonegate"], "the Magic tab lists the same rows")
		for row in rows:
			# The resolver's battle on a copy that holds the same spellbook and a foe built by hand from the roster.
			var real := s.deep_copy([])
			Fx.spellbook(real, CROWN, book.order, book.off)
			var mine := real.armies.filter(func(a): return a.owner == CROWN and a.location == row.province)
			var foe := Fx.army(real, CLANS, "beasts-90", row.province, _foe_types(real, CLANS))
			for defender in ["", CROWN]:
				if defender == CROWN and Dictionary(row.defend).is_empty():
					continue
				var key := "open" if defender.is_empty() else "defend"
				for seed_value in [3, 17, 4242]:  # spells never roll: the first round is the same whatever the seed
					var r := Fx.fight(real, mine + [foe], row.province, defender, seed_value)
					var side: int = (r.log as Dictionary).sides.find_custom(func(sd): return sd.faction == CROWN)
					assert_eq(_preview_pairs(row[key], CROWN), _round_one(r.log, side),
						"%s %s with %s: the preview casts what the resolver casts (seed %d)" % [row.province, key, JSON.stringify(book), seed_value])
					checked += 1
				# The skips the preview names are the skips the resolver's cast events carry.
				var rl := Fx.fight(real, mine + [foe], row.province, defender, 1).log as Dictionary
				var skipped := {}
				for e in Fx.events(rl, "cast", 1):
					for sk in e.get("skipped", []):
						skipped[String(sk.spell)] = String(sk.reason)
				var named := {}
				for sk in row[key].skips:
					named[String(sk.spell)] = String(sk.reason)
				assert_eq(named, skipped, "%s %s: the skips and their reasons" % [row.province, key])
		# The Magic tab's text is the forecast's.
		for i in rows.size():
			assert_eq(view[i].lines, rows[i].lines)
	assert_true(checked >= 40, "checked %d casts" % checked)
	# Shield of Law is skipped defending a fort or hills, said in words, and not skipped in the open.
	var plain := Forecast.spellbook_preview(s, CROWN)
	var highcrag: Dictionary = plain.filter(func(r): return r.province == "highcrag")[0]
	assert_true(_preview_pairs(highcrag.open, CROWN).any(func(p): return p[1] == "shield_of_law"), "in the open an Adept shields")
	assert_false(_preview_pairs(highcrag.defend, CROWN).any(func(p): return p[1] == "shield_of_law"), "defending the hills it doesn't")
	assert_true(String(highcrag.lines[1]).contains("Shield of Law is skipped"), highcrag.lines[1])
	assert_true(String(highcrag.lines[1]).contains("never covers a unit with a terrain or fort bonus"), highcrag.lines[1])
	# The Regent alone (Crownkeep, plains with a fort): Sunlance in the open and defending alike.
	var keep: Dictionary = plain.filter(func(r): return r.province == "crownkeep")[0]
	assert_eq(_preview_pairs(keep.open, CROWN).map(func(p): return p[1]), ["sunlance"])
	_assert_no_raw_ids(" ".join(plain.map(func(r): return String(r.text))), "the spellbook preview")


func test_the_preview_follows_a_queued_spellbook_order_and_the_panel_shows_it() -> void:
	var s := _scripted()
	var panel := ResearchPanel.new()
	panel.show_for(s, CROWN)
	panel.show_magic()
	var box := panel.sidebar.find_child("SpellbookPreview", true, false)
	assert_true(box != null)
	var titles := []
	for row in MagicView.spellbook_preview(s, CROWN):
		var t := panel.sidebar.find_child("PreviewTitle_%s" % String(row.province), true, false) as Label
		assert_true(t != null, "a title for %s" % row.province)
		if t != null:
			assert_eq(t.text, String(row.title))
			titles.append(t.text)
		var l0 := panel.sidebar.find_child("PreviewLine_%s_0" % String(row.province), true, false) as Label
		assert_eq(l0.text, String(row.lines[0]))
	assert_eq(titles.size(), 3)
	# Switch Sunlance off: the Adepts' Sunlance leaves the preview; the order is queued through the session.
	var off := SpellbookOrder.new(MagicData.SPELLBOOK[CROWN], ["sunlance"])
	panel.set_orders([off])
	var after := Forecast.spellbook_preview(s, CROWN, [off])
	for row in after:
		assert_false(_preview_pairs(row.open, CROWN).any(func(p): return p[1] == "sunlance"), "%s: Sunlance is off" % row.province)
		var l := panel.sidebar.find_child("PreviewLine_%s_0" % String(row.province), true, false) as Label
		assert_eq(l.text, String(row.lines[0]))
	panel.free()
	# No casters: it says so (and recruiting one is the way).
	var bare := _magic({CROWN: "warrior_king"})
	var p2 := ResearchPanel.new()
	p2.show_for(bare, CROWN)
	p2.show_magic()
	assert_true(p2.sidebar.find_child("PreviewNone", true, false) != null, "no caster: the preview says so")
	p2.free()


func test_a_move_forecast_names_the_spells_each_side_will_cast_and_equals_the_battle() -> void:
	var s := _scripted()
	Fx.army(s, CLANS, "beasts-1", "thornvale", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "shamans", "shamans"])
	var f := Forecast.spells_forecast(s, CROWN, ["kingdom-1"], "thornvale")
	assert_true(f.ok, f.text)
	# The real battle: the same armies, the Clans defending Thornvale.
	var real := s.deep_copy([])
	var mine := real.armies.filter(func(a): return a.id == "kingdom-1")
	var theirs := real.armies.filter(func(a): return a.id == "beasts-1")
	for seed_value in [5, 6]:
		var r := Fx.fight(real, mine + theirs, "thornvale", CLANS, seed_value)
		var sides: Array = (r.log as Dictionary).sides
		var crown_side := sides.find_custom(func(sd): return sd.faction == CROWN)
		var clans_side := sides.find_custom(func(sd): return sd.faction == CLANS)
		assert_eq(_preview_pairs(f.result, CROWN), _round_one(r.log, crown_side), "your casts")
		assert_eq(_preview_pairs(f.result, CLANS), _round_one(r.log, clans_side), "theirs")
	assert_true(String(f.text).begins_with("Your casters in round 1:"), f.text)
	assert_true(String(f.text).contains("Their casters in round 1: "), f.text)
	assert_false(String(f.text).contains("assumed"), "nothing is assumed without fog: their spells are public")
	# The orders controller puts it on the forecast line and the hover.
	var ctrl := OrdersController.new(s, CROWN)
	var odds := ctrl.move_odds("kingdom-1", "thornvale")
	assert_true(odds.enemy_present)
	assert_true(String(odds.line).contains(String(f.text)), odds.line)
	assert_true(String(odds.text).contains(String(f.text)))
	_assert_no_raw_ids(String(f.text), "the spells line")
	# No caster on either side: no line.
	var none := Fx.game()
	Fx.army(none, CROWN, "kingdom-1", "highcrag", ["spearmen", "spearmen"])
	Fx.army(none, CLANS, "beasts-1", "thornvale", ["tuskers", "tuskers"])
	assert_false(bool(Forecast.spells_forecast(none, CROWN, ["kingdom-1"], "thornvale").ok))
	assert_eq(String(OrdersController.new(none, CROWN).move_odds("kingdom-1", "thornvale").get("spells", {}).get("text", "")), "")


func test_under_fog_a_rivals_unknown_spells_are_assumed_and_it_says_so() -> void:
	var s := _scripted()
	s.fog = true
	Fx.army(s, CLANS, "beasts-1", "highcrag", ["tuskers", "tuskers", "tuskers", "tuskers", "shamans", "shamans"])
	var view := FogRules.view_state(s, CROWN, {}, {})
	assert_true(view.is_view)
	assert_eq(MagicRules.known_spells(view, CLANS), [], "their spells are private under fog")
	var asm := Forecast.assume_spells(view, CROWN, "highcrag")
	assert_eq(asm.assumed, {CLANS: Forecast.assumed_spell(CLANS)})
	assert_eq(Forecast.assumed_spell(CLANS), String(MagicData.SCHOOLS.wild.nodes[0]), "the first spell of their first school")
	var f := Forecast.spells_forecast(view, CROWN, ["kingdom-1"], "highcrag")
	assert_true(f.ok)
	assert_true(String(f.text).contains("(assumed: %s)" % MagicRules.spell_name(Forecast.assumed_spell(CLANS))), f.text)
	assert_eq(_preview_pairs(f.result, CLANS).map(func(p): return p[1]).filter(func(sp): return sp != Forecast.assumed_spell(CLANS)), [],
		"they cast only what is assumed")
	# The odds are worked out with the assumption, and the hover lists it.
	var vo := Forecast.view_odds(view, CROWN, ["kingdom-1"], "highcrag", {}, {})
	assert_eq(vo.assumed_spells, asm.assumed)
	assert_true(" ".join(vo.assumptions).contains("Spells assumed"), "the ⓘ lines name the assumption")
	var ctrl := OrdersController.new(view, CROWN)
	var odds := ctrl.move_odds("kingdom-1", "highcrag")
	assert_true(String(odds.line).contains("assumed"), odds.line)
	# Once you know one of their spells nothing is assumed.
	var known := AscensionRules.with_nodes(view, CLANS, ["bloodbolt"])
	assert_eq(Forecast.assume_spells(known, CROWN, "highcrag").assumed, {})


# --- the cast dialog -----------------------------------------------------------------------------------------

func test_the_dialog_offers_only_legal_targets_and_its_forecast_is_the_rules() -> void:
	var s := _clans_state()
	var game := _screen(s, [CLANS, CROWN])
	var map := game.map
	var army := _army_at(game.session.state(), CLANS, "thornvale")
	map.open_cast_dialog(army.id)
	var dialog := map.cast_dialog
	assert_true(dialog.visible)
	var ctrl := map.orders
	var state := game.session.state()
	var cases := 0
	for o in dialog.options:
		dialog.select_ritual(String(o.ritual))
		var legal := []
		for p in state.provinces:
			var probe := CastOrder.new(String(o.ritual), army.id, "" if String(MagicRules.spell_data(o.ritual).target) == "none" else p.id,
				CastOrder.GOLD, int(o.sizes[0]) if not o.sizes.is_empty() else 0)
			if OrderBook.check_order(state, CLANS, probe, []).is_empty():
				legal.append(p.id)
		if String(MagicRules.spell_data(o.ritual).target) == "none":
			assert_eq(dialog.target_buttons.keys(), [""], "no target to pick")
			continue
		var offered := dialog.target_buttons.keys()
		offered.sort()
		legal.sort()
		assert_eq(offered, legal, "%s: the dialog offers exactly the provinces the rules allow" % o.ritual)
		assert_eq(dialog.lit_provinces(), legal)
		# Its forecast is the rules' forecast, for every target, payment and size it offers.
		for pid in offered:
			dialog.select_target(String(pid))
			for pay in ([CastOrder.GOLD, CastOrder.BLOOD] if bool(o.blood) else [CastOrder.GOLD]):
				dialog.set_pay(pay)
				for size in (range(int(o.sizes[0]), int(o.sizes[1]) + 1) if not o.sizes.is_empty() else [0]):
					if not o.sizes.is_empty():
						dialog.set_wolves(size)
					var order := CastOrder.new(String(o.ritual), army.id, String(pid), pay, size)
					var fc := MagicRules.forecast_ritual(state, CLANS, order, [order])
					assert_eq(dialog.shown_forecast(), "\n".join(fc.lines), "%s on %s paid in %s: the rules' forecast, word for word" % [o.ritual, pid, pay])
					assert_eq(dialog.confirm_button.disabled, not fc.ok)
					cases += 1
	assert_true(cases >= 20, "checked %d choices" % cases)
	# A province out of range is no button, and the rules refuse it with their reason.
	dialog.select_ritual("bloodrot")
	assert_false(dialog.target_buttons.has("thornvale"), "your own province is no target for a curse")
	var far := CastOrder.new("bloodrot", army.id, "fangridge")
	assert_false(OrderBook.check_order(state, CLANS, far, []).is_empty())
	game.free()


func test_the_dialog_counts_its_casters_once_and_a_ruler_alone_casts() -> void:
	var s := _clans_state()
	var game := _screen(s, [CLANS, CROWN])
	var map := game.map
	var state := game.session.state()
	var army := _army_at(state, CLANS, "thornvale")
	assert_eq(MagicView.casters_phrase(state, army), "your 2 %s" % String(MagicData.MAGES[CLANS].name))
	map.open_cast_dialog(army.id)
	var intro: String = map.cast_dialog.intro_label.text
	assert_true(intro.contains("holds your 2 %s." % String(MagicData.MAGES[CLANS].name)), intro)
	assert_false(intro.contains(" and your "), "no caster is named twice")
	var fang := RulerRules.ruler_army(state, CLANS)
	assert_eq(MagicView.casters_phrase(state, fang), RulerRules.current_name(state, CLANS))
	map.open_cast_dialog(fang.id)
	var alone: String = map.cast_dialog.intro_label.text
	assert_true(alone.contains("casts from where it starts the turn"), alone)
	assert_false(alone.contains("holds %s" % RulerRules.current_name(state, CLANS)), "a ruler's army is the ruler: it holds no one else")
	game.free()


func test_the_dialogs_sections_budget_pin_and_numbers_match_the_rules() -> void:
	var s := _clans_state()
	var game := _screen(s, [CLANS, CROWN])
	var map := game.map
	var state := game.session.state()
	var army := _army_at(state, CLANS, "thornvale")
	# A move for the casting army: the dialog says casting cancels it.
	assert_eq(map.queue_move(army.id, "highcrag"), "")
	map.open_cast_dialog(army.id, "bloodrot")
	var dialog := map.cast_dialog
	dialog.select_target("crownkeep")
	var order := CastOrder.new("bloodrot", army.id, "crownkeep")
	var orders: Array = map.orders.orders()
	var fc := MagicRules.forecast_ritual(state, CLANS, order, orders + [order])
	assert_eq(fc.sections.map(func(sec): return sec.kind), ["effect", "risk", "pin"], "the effect, the risk by sight and the pin")
	assert_eq(Array(fc.sections).map(func(sec): return String(sec.text)), fc.lines, "the sections are the lines")
	var pin: String = fc.sections[2].text
	assert_true(pin.contains("(%s)" % MagicRules.fighters_words(state, army)), pin)
	assert_true(pin.contains("this cancels its move to Highcrag"), pin)
	assert_eq(dialog.shown_forecast(), "\n".join(fc.lines))
	# The risk, from what you can see: the Crown could ward Crownkeep (it knows Sanctum Ward), and none is there.
	var risk: String = fc.sections[1].text
	assert_true(risk.begins_with("No ward seen on Crownkeep at the start of the turn"), risk)
	var half := floori(float(int(MagicRules.price(state, CLANS, "bloodrot").gold)) / MagicData.TURNED_ASIDE)
	assert_true(risk.contains("%d gold" % half), risk)
	# The curse names how many fighters you can see there: every fighter of the Crown's at Crownkeep (the Regent's army included).
	var there := 0
	for a in state.armies:
		if a.location == "crownkeep" and a.owner != CLANS:
			there += a.units.size() + (1 if a.commander != null else 0) + (1 if a.ruler != null else 0)
	assert_true(there > 0)
	assert_true(String(fc.sections[0].text).contains("(%d you can see)" % there), fc.sections[0].text)
	assert_eq(MagicRules.seen_there_words(state, CLANS, "crownkeep"), "%d you can see" % there)
	# The numbers block: the price and the ritual's own number, each with its breakdown from Breakdown.
	var price := dialog.numbers_box.find_child("Number_Price", true, false) as Label
	assert_eq(price.get_meta("breakdown"), Breakdown.ritual_price(state, CLANS, "bloodrot", 0))
	var size := dialog.numbers_box.find_child("Number_Size", true, false) as Label
	assert_eq(size.get_meta("breakdown"), Breakdown.spell_number(state, CLANS, "bloodrot", String(fc.effect.caster)))
	# The budget line: gold after the queued rituals and recruits, this cast included.
	var budget := Forecast.cast_budget(state, CLANS, orders + [order])
	assert_eq(dialog.shown_budget(), String(budget.text))
	assert_eq(int(budget.gold_after), int(state.find_faction(CLANS).gold) - int(MagicRules.price(state, CLANS, "bloodrot").gold))
	assert_eq(Breakdown.sum_of_lines(budget.breakdown), int(budget.breakdown.total))
	assert_eq(budget_breakdown_of(dialog), budget.breakdown)
	dialog.set_pay(CastOrder.BLOOD)
	var in_blood := Forecast.cast_budget(state, CLANS, orders + [CastOrder.new("bloodrot", army.id, "crownkeep", CastOrder.BLOOD)])
	assert_eq(int(in_blood.gold_after), int(state.find_faction(CLANS).gold), "paid in blood: no gold leaves")
	assert_eq(dialog.shown_budget(), String(in_blood.text))
	assert_eq(String(dialog.numbers_box.find_child("Number_Price", true, false).text).begins_with("Price: %d hit points" % int(MagicRules.price(state, CLANS, "bloodrot").gold)), true)
	# A queued recruit counts too (the same line the orders list shows).
	assert_eq(map.queue_recruit("tuskers"), "")
	dialog.set_pay(CastOrder.GOLD)
	var with_recruit := Forecast.cast_budget(state, CLANS, map.orders.orders() + [order])
	assert_eq(dialog.shown_budget(), String(with_recruit.text))
	assert_true(int(with_recruit.gold_after) < int(budget.gold_after), "the recruit took its gold")
	game.free()


func budget_breakdown_of(dialog: CastDialog) -> Dictionary:
	return dialog.budget_label.get_meta("breakdown")


func test_a_ward_seen_turns_the_cast_aside_and_out_of_sight_it_is_a_guess() -> void:
	var s := _clans_state()
	# The Crown warded Crownkeep last turn: the forecast says it will be turned aside, with what it costs.
	var f := s.find_faction(CROWN)
	f.enchant_counter += 1
	s.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false})
	var army := _army_at(s, CLANS, "thornvale")
	var order := CastOrder.new("bloodrot", army.id, "crownkeep")
	var fc := MagicRules.forecast_ritual(s, CLANS, order, [order])
	assert_eq(fc.sections[0].kind, "effect")
	assert_true(String(fc.sections[0].text).contains("will be turned aside"), fc.sections[0].text)
	assert_true(String(fc.sections[0].text).contains("%d gold" % floori(float(int(MagicRules.price(s, CLANS, "bloodrot").gold)) / MagicData.TURNED_ASIDE)), fc.sections[0].text)
	assert_false(fc.sections.any(func(sec): return sec.kind == "risk"), "a ward seen is the outcome, not a risk")
	# The rules agree: the resolver turns it aside and charges half.
	var r := TurnResolver.resolve(s, {CLANS: [order]}, TurnResolver.seed_for_turn(s))
	assert_true(r.events.any(func(e): return String(e.type) == "ritual_turned_aside"))
	# Under fog Crownkeep is out of sight: nothing says a ward is there, and the risk says it can't be seen.
	var fog := _clans_state(true)
	var view := FogRules.view_state(fog, CLANS, {}, {})
	var cast_army := _army_at(view, CLANS, "thornvale")
	var far := CastOrder.new("bloodrot", cast_army.id, "crownkeep")
	var veiled := Forecast.veiled_provinces(view, CLANS)
	for p in view.provinces:
		assert_eq(veiled.has(p.id), String(FogRules.sight(view, CLANS).get(p.id, FogRules.VEILED)) == FogRules.VEILED, "%s: out of sight exactly when the view says so" % p.id)
	assert_true(veiled.has("crownkeep"), "the Crown's capital is out of the Clans' sight at the start")
	assert_eq(Forecast.veiled_provinces(fog, CLANS), {}, "no fog view, nothing is out of sight")
	var vf := MagicRules.forecast_ritual(view, CLANS, far, [far], veiled)
	assert_true(vf.ok, vf.text)
	# Without the caller's list the rules say nothing about sight (they never read the fog).
	var plain := MagicRules.forecast_ritual(view, CLANS, far, [far])
	assert_true(String(plain.sections.filter(func(sec): return sec.kind == "risk")[0].text).begins_with("No ward seen on Crownkeep"))
	var risk: Array = vf.sections.filter(func(sec): return sec.kind == "risk")
	assert_eq(risk.size(), 1)
	assert_true(String(risk[0].text).begins_with("Crownkeep is out of sight"), risk[0].text)
	assert_true(String(risk[0].text).contains("turned aside"), risk[0].text)
	# Far Sight on their capital: the casters that block its reading are named (a caster there blocks the reading, not the sight).
	var sight := CastOrder.new("far_sight", cast_army.id, "crownkeep")
	var sf := MagicRules.forecast_ritual(view, CLANS, sight, [sight])
	assert_true(sf.ok, sf.text)
	assert_true(String(sf.text).contains("blocks the reading, not the sight") or String(sf.text).contains("block the reading"), sf.text)


func test_the_dialog_lights_the_provinces_in_range_and_a_click_on_the_board_picks_one() -> void:
	var s := _clans_state()
	var game := _screen(s, [CLANS, CROWN])
	var map := game.map
	var army := _army_at(game.session.state(), CLANS, "thornvale")
	assert_false(map.casting())
	map.open_cast_dialog(army.id, "bloodrot")
	var dialog := map.cast_dialog
	assert_true(map.casting())
	var legal := dialog.lit_provinces()
	assert_true(legal.size() > 3)
	assert_eq(map.cast_lit().keys().size() + map.cast_ringed().keys().size(), legal.size(), "every province in range is lit; the chosen one is ringed")
	assert_eq(map.cast_ringed().keys(), [dialog.target])
	for id in map.regions:
		var mark: int = map.regions[id].cast_mark
		assert_eq(mark != ProvinceRegion.CAST_NONE, legal.has(id), "%s: lit exactly when it is a legal target" % id)
		assert_eq(mark == ProvinceRegion.CAST_RING, id == dialog.target)
	# A click on a lit province picks it as the target (and nothing else happens); one out of range changes nothing.
	var other := String(legal.filter(func(p): return p != dialog.target)[0])
	var selected_before := map.selected_province_id
	map.select_province(other)
	assert_eq(dialog.target, other)
	assert_eq(map.cast_ringed().keys(), [other], "the ring moves with the target")
	assert_eq(map.selected_province_id, selected_before, "the province selection did not change")
	map.select_province("thornvale")  # your own province: not a target of a curse
	assert_eq(dialog.target, other)
	assert_true(dialog.note_label.text.contains("Thornvale is out of this ritual's reach"), "the dialog says why nothing happened: %s" % dialog.note_label.text)
	assert_true(map.orders.orders().is_empty(), "no order was queued by clicking")
	map.select_province(legal[0])
	assert_eq(dialog.note_label.text, CastDialog.NOTE, "the usual note is back after a pick")
	# The 3D board's marks read the same sets.
	assert_eq(map.cast_lit().size() + map.cast_ringed().size(), legal.size())
	# A new state (a new turn, another seat) closes it: its orders are stale.
	map.set_state(game.session.state().deep_copy([]), CLANS)
	assert_false(map.casting(), "a new state closes the dialog")
	assert_eq(map.cast_lit().size() + map.cast_ringed().size(), 0)
	map.open_cast_dialog(army.id, "bloodrot")
	dialog = map.cast_dialog
	# Closing the dialog clears them.
	dialog.close()
	assert_false(map.casting())
	assert_eq(map.cast_lit().size() + map.cast_ringed().size(), 0)
	for id in map.regions:
		assert_eq(int(map.regions[id].cast_mark), ProvinceRegion.CAST_NONE)
	# Confirming queues the order and clears them too.
	map.open_cast_dialog(army.id, "bloodrot")
	map.cast_dialog.select_target(other)
	map.cast_dialog.confirm()
	assert_eq(map.cast_lit().size() + map.cast_ringed().size(), 0)
	assert_eq(map.orders.orders().size(), 1)
	game.free()


func test_the_dialogs_preview_equals_the_result_for_a_cast() -> void:
	var s := AscensionRules.with_nodes(_clans_state(), CLANS, ["wild_mastery"])
	var second := Fx.army(s, CLANS, s.new_army_id(CLANS), "thornvale", ["shamans"])
	var game := _screen(s, [CLANS, CROWN])
	var map := game.map
	var state := game.session.state()
	var first := _army_at(state, CLANS, "thornvale")
	# Bloodrot paid in blood from one army, the pack from the other, through the dialog.
	map.open_cast_dialog(first.id, "bloodrot")
	map.cast_dialog.select_target("crownkeep")
	map.cast_dialog.set_pay(CastOrder.BLOOD)
	var rot_fc: Dictionary = map.cast_dialog.forecast
	map.cast_dialog.confirm()
	map.open_cast_dialog(second.id, "call_the_pack")
	map.cast_dialog.set_wolves(4)
	var pack_fc: Dictionary = map.cast_dialog.forecast
	var budget_line: String = map.cast_dialog.shown_budget()
	map.cast_dialog.confirm()
	var orders: Array = map.orders.orders()
	assert_eq(orders.size(), 2)
	# The result: the rituals phase on the same orders.
	var r := TurnResolver.resolve(state, {CLANS: orders}, TurnResolver.seed_for_turn(state))
	var casts: Array = r.events.filter(func(e): return String(e.type) == "ritual_cast")
	assert_eq(casts.size(), 2)
	var rot: Dictionary = casts.filter(func(e): return e.numbers.ritual == "bloodrot")[0]
	var pack: Dictionary = casts.filter(func(e): return e.numbers.ritual == "call_the_pack")[0]
	for pair in [[rot_fc, rot], [pack_fc, pack]]:
		var fx: Dictionary = pair[0].effect
		var ev: Dictionary = pair[1]
		assert_eq(int(ev.numbers.gold), int(fx.gold), "%s: the gold" % fx.ritual)
		assert_eq(int(ev.numbers.hp), int(fx.hp), "the blood")
		assert_eq(int(ev.numbers.until_turn), int(fx.until_turn), "the last turn")
		assert_eq(int(ev.numbers.bonus), int(fx.bonus))
		assert_eq(ev.numbers.gives, fx.gives, "who bled, what each gave")
		assert_eq(ev.numbers.summon, fx.summon)
	var after: GameState = r.new_state
	# The enchantment is in the state with the forecast's last turn, and the wolves are in the new army as called.
	var curse: Dictionary = after.enchantments.filter(func(e): return String(e.ritual) == "bloodrot")[0]
	assert_eq(int(curse.until_turn), int(rot_fc.effect.until_turn))
	assert_eq(String(curse.province), "crownkeep")
	var wolves := after.find_army(String(pack_fc.effect.summon.army))
	assert_true(wolves != null and wolves.units.size() == 4, "the pack of the size picked")
	# The gold: the budget line said what is left before income; the income phase pays on top.
	var g := Forecast.gold_after_recruits(state, CLANS, [], orders, MagicRules.queued_gold(state, CLANS, orders))
	assert_true(budget_line.begins_with("Gold after your queued rituals and recruits:"), "the budget line was shown")
	assert_eq(after.find_faction(CLANS).gold, int(g.gold_next_turn), "gold after the turn is the forecast's: gold after rituals plus income")
	game.free()


func test_the_forecast_names_the_blessed_armies_with_their_size_and_bastion_its_count() -> void:
	var s := _scripted()
	s = Fx.with_nodes(s, CROWN, ["crown_drillyard", "crown_charters", "crown_oath_forge", "bastion"])
	s.find_faction(CROWN).gold = 200
	for pid in ["highcrag", "westwatch", "rivermarch"]:
		s.find_province(pid).owner = CROWN
	var regent := RulerRules.ruler_army(s, CROWN)
	var blessing := CastOrder.new("dawn_blessing", regent.id, "highcrag")
	var fc := MagicRules.forecast_ritual(s, CROWN, blessing, [blessing])
	assert_true(fc.ok, fc.text)
	var army := _army_at(s, CROWN, "highcrag")
	var text := String(fc.sections[0].text)
	assert_true(text.contains("blesses 1 army of yours there, %s (%s), through turn" % [TurnReportText.army_name(s, army.id, CROWN), MagicRules.fighters_words(s, army)]), text)
	assert_true(text.contains("Armies arriving this turn aren't blessed"), text)
	# Bastion: the count of forts used of the cap.
	var raise := CastOrder.new("bastion", regent.id, "westwatch")
	var rf := MagicRules.forecast_ritual(s, CROWN, raise, [raise])
	assert_true(rf.ok, rf.text)
	assert_true(String(rf.sections[0].text).contains("1 of %d Bastion forts used" % MagicData.BASTION_CAP), rf.sections[0].text)
	_assert_no_raw_ids(text + String(rf.sections[0].text), "the blessing and bastion forecasts")


# --- badges ------------------------------------------------------------------------------------------------

func test_enchantment_badges_show_what_the_state_shows() -> void:
	var s := _clans_state()
	s.enchantments.clear()
	var crown := s.find_faction(CROWN)
	var clans := s.find_faction(CLANS)
	crown.enchant_counter += 1
	clans.enchant_counter += 3
	s.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 2, "bonus": 0, "ending": false})
	s.enchantments.append({"id": "beasts-e1", "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": "westwatch",
		"armies": [], "cast_turn": 1, "until_turn": 4, "bonus": 1, "ending": false})
	s.enchantments.append({"id": "beasts-e2", "ritual": "far_sight", "faction": CLANS, "kind": "sight", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false})
	s.enchantments.append({"id": "beasts-e3", "ritual": "blood_moon", "faction": CLANS, "kind": "global", "province": "",
		"armies": [], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false})
	s.enchantments.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var keep := EnchantmentBadges.badges(s, CLANS, "crownkeep")
	assert_eq(keep.map(func(b): return String(b.ritual)), ["far_sight", "sanctum_ward"], "every ward and sight on the province, in id order")
	for b in keep:
		var e: Dictionary = s.enchantments.filter(func(x): return String(x.id) == String(b.id))[0]
		assert_eq(int(b.until_turn), int(e.until_turn))
		assert_eq(String(b.text), "%s · through turn %d" % [MagicRules.spell_name(String(e.ritual)), int(e.until_turn)])
		var tip := String(b.tooltip).replace("\n", " ")
		assert_true(tip.contains("Cast by the %s" % MagicRules._faction_display(s, String(e.faction))), tip)
		assert_true(tip.contains("through turn %d and ends in that turn's enchantments phase" % int(e.until_turn)), tip)
		assert_true(tip.contains(EnchantmentBadges.effect_text(s, e)), "the hover has the exact effect")
		assert_true(RulesCodex.ENTRIES.has(String(b.codex)), "its codex entry")
	var rot: Dictionary = EnchantmentBadges.badges(s, CLANS, "westwatch")[0]
	assert_true(String(rot.tooltip).replace("\n", " ").contains("%d hit points" % int(MagicRules.spell_numbers("bloodrot", 1).value)), "the curse's number with its mastery: %s" % rot.tooltip)
	assert_true(bool(rot.mine) and not bool(keep.filter(func(b): return b.ritual == "sanctum_ward")[0].mine), "yours are marked")
	assert_eq(EnchantmentBadges.badges(s, CLANS, "highcrag"), [], "none where nothing lies")
	# A blessing is on its armies and the Blood Moon is no province's: neither is a badge.
	assert_eq(EnchantmentBadges.badges(s, CLANS, "").size(), 0)
	# The map shows them on the 2D plates and mirrors them on the board's.
	var game := _screen(s, [CLANS, CROWN])
	var region: ProvinceRegion = game.map.regions["crownkeep"]
	assert_true(region.enchantment_badges != null, "the region has its badges")
	assert_eq(region.enchantment_badges.get_child_count(), 2)
	var first := region.enchantment_badges.get_child(0) as Control
	assert_true(first.tooltip_text.contains("Far Sight"), first.tooltip_text)
	assert_eq(_assert_links_valid(region.enchantment_badges, "the badges"), 2, "each badge links its ritual's codex entry")
	assert_true(game.map.regions["highcrag"].enchantment_badges == null, "no badge where nothing lies")
	_assert_numbers_explained(region.enchantment_badges, "the badges")
	_assert_no_raw_ids(_texts(region.enchantment_badges), "the badges")
	game.free()


func test_under_fog_a_rivals_badge_shows_only_where_you_can_see() -> void:
	var s := _clans_state(true)
	s.enchantments.clear()
	var crown := s.find_faction(CROWN)
	crown.enchant_counter += 1
	s.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 2, "bonus": 0, "ending": false})
	s.enchantments.append({"id": "kingdom-e2", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "highcrag",
		"armies": [], "cast_turn": 1, "until_turn": 2, "bonus": 0, "ending": false})
	var view := FogRules.view_state(s, CLANS, {}, {})
	var seen := view.enchantments.map(func(e): return String(e.province))
	var sight := FogRules.sight(view, CLANS)
	for pid in ["crownkeep", "highcrag"]:
		var visible := String(sight.get(pid, FogRules.VEILED)) != FogRules.VEILED
		assert_eq(seen.has(pid), visible, "%s: a rival's ward is in your view exactly when you see it" % pid)
		assert_eq(EnchantmentBadges.badges(view, CLANS, pid).size(), 1 if visible else 0)


# --- the army panel, the mage card and the second rank ----------------------------------------------------------

func test_the_army_panel_names_its_casters_and_each_spell_with_its_number() -> void:
	var s := _scripted()
	s.find_faction(CROWN).research_points = 0
	var game := _screen(s, [CROWN, CLANS])
	var map := game.map
	var state := game.session.state()
	for where in ["highcrag", "stonegate", "crownkeep"]:
		map.select_province(where)
		var line := map.details.find_child("CastersLine", true, false) as Label
		assert_true(line != null, "%s: a casters line" % where)
		var army: Army = state.armies.filter(func(a): return a.owner == CROWN and a.location == where and not MagicRules.casters(state, a).filter(func(c): return c.battle).is_empty())[0]
		var model := MagicView.army_line(state, army)
		assert_eq(line.text, String(model.header))
		assert_eq(line.get_meta("breakdown"), Breakdown.army_units(state, army.id))
		for sp in model.spells:
			var label := map.details.find_child("Spell_%s" % String(sp.spell), true, false) as Label
			assert_true(label != null and label.text == String(sp.text), "%s: %s" % [where, sp.text])
			var kind := MagicRules.RULER if army.ruler != null else MagicRules.MAGE
			assert_eq(label.get_meta("breakdown"), Breakdown.spell_number(state, CROWN, String(sp.spell), kind))
		# The numbers are the rules' own: mastery included.
		var best := 0
		for c in MagicRules.casters(state, army):
			if c.battle:
				best = maxi(best, int(MagicRules.mastery_bonus(state, CROWN, "sun", String(c.kind)).value))
		var lance: Array = model.spells.filter(func(x): return x.spell == "sunlance")
		if not lance.is_empty():
			assert_true(String(lance[0].text).begins_with("Sunlance %d damage" % int(MagicRules.spell_numbers("sunlance", best).value)), lance[0].text)
		for l in map.details.find_children("UnitCount", "Label", true, false):  # a mage's card carries the spellbook, in order
			if String(l.text).begins_with(String(MagicData.MAGES[CROWN].name)):
				var tip := String(l.tooltip_text).replace("\n", " ")
				assert_true(tip.contains("Your battle spellbook, in the order your %s try it:" % String(MagicData.MAGES[CROWN].name)), tip)
				assert_true(tip.contains(MagicView.mage_card(state, CROWN).split("\n")[1]), "the first spell, one line: %s" % tip)
		for name in ["CastersLine", "MasteryLine"]:
			var l := map.details.find_child(name, true, false) as Label
			if l != null:
				assert_true(l.has_meta("breakdown"), "%s: %s has a breakdown" % [where, name])
				var b: Dictionary = l.get_meta("breakdown")
				assert_true(l.tooltip_text.begins_with(TooltipText.from_breakdown(b)), "%s: %s shows it on hover" % [where, name])
				assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: %s breakdown sums" % [where, name])
		for sp in model.spells:
			var l2 := map.details.find_child("Spell_%s" % String(sp.spell), true, false) as Label
			assert_eq(Breakdown.sum_of_lines(l2.get_meta("breakdown")), int(l2.get_meta("breakdown").total))
	# The Regent's own Sunlance is listed with its mastery (rank - 1, capped).
	var regent_line := MagicView.army_line(state, RulerRules.ruler_army(state, CROWN))
	assert_true(String(regent_line.text).contains("Sunlance %d damage" % int(MagicRules.spell_numbers("sunlance", int(MagicRules.mastery_bonus(state, CROWN, "sun", MagicRules.RULER).value)).value)), regent_line.text)
	# A switched-off spell is listed as off.
	var off_state := state.deep_copy([])
	Fx.spellbook(off_state, CROWN, MagicData.SPELLBOOK[CROWN], ["shield_of_law"])
	var off_line := MagicView.army_line(off_state, _army_at(off_state, CROWN, "highcrag"))
	assert_true(String(off_line.text).contains("Shield of Law (off)"), off_line.text)
	# An army with no caster has no such line.
	assert_eq(MagicView.army_line(state, _army_at(Fx.game(), CROWN, "x")), {})
	game.free()


func test_a_mage_card_lists_the_spellbook_and_a_recruit_warns_when_the_second_rank_is_exposed() -> void:
	var s := _magic({CROWN: "regents_court"})
	s = AscensionRules.with_nodes(s, CROWN, ["sunlance"])
	var mage := String(MagicData.MAGES[CROWN].id)
	var ctrl := OrdersController.new(s, CROWN)
	var card := MagicView.mage_card(s, CROWN)
	var book := MagicRules.spellbook(s, CROWN)
	var lines := card.split("\n")
	assert_eq(lines.size(), book.order.size() + 2, "a heading, one line a spell, the rule")
	for i in book.order.size():
		assert_true(lines[1 + i].begins_with("%d. %s" % [i + 1, MagicRules.spell_name(String(book.order[i]))]), lines[1 + i])
	assert_true(card.contains("known: %d damage" % int(MagicRules.spell_numbers("sunlance", 0).value)))
	assert_true(card.contains("not researched (%d research)" % AscensionRules.node_cost("shield_of_law")))
	assert_true(card.contains("fights from the second rank: safe while your front rank is at least as big; Fangthrowers and Seraphs can always reach it"))
	assert_true(String(ctrl.recruit_breakdown(mage).description).contains(card), "the recruit card carries it")
	# The capital's army: count its ranks from the roster, derive the warning.
	var home := _army_at(s, CROWN, s.find_faction(CROWN).capital)
	var front := 0
	var second := 0
	for u in home.units:
		if u.type.trait_id == "Volley" or MagicRules.is_mage(u.type):
			second += 1
		else:
			front += 1
	var one := Forecast.second_rank(s, CROWN, mage)
	assert_true(one.ok)
	assert_eq(int(one.front), front)
	assert_eq(int(one.second), second + 1)
	assert_eq(bool(one.exposed), second + 1 > front)
	# Queue mages until the second rank outnumbers the front: the warning appears with its counts, and the counts are the army's.
	var orders: Array = []
	var exposed_at := -1
	for i in 8:
		var r := Forecast.second_rank(s, CROWN, mage, "", orders)
		if r.exposed and exposed_at < 0:
			exposed_at = i
			assert_true(String(r.text).contains("%d second-rank and %d front-rank fighters: its second rank is exposed" % [int(r.second), int(r.front)]), r.text)
			assert_eq(MagicView.recruit_warning(s, CROWN, mage, "", orders), String(r.text))
		orders.append(RecruitOrder.new(mage))
	assert_true(exposed_at > 0, "exposed after a few mages")
	# The result: resolve the turn with those recruits; the army's ranks are what the forecast counted at the last one.
	var gold_state := s.deep_copy([])
	gold_state.find_faction(CROWN).gold = 500
	var recruits: Array = []
	for i in exposed_at + 1:
		recruits.append(RecruitOrder.new(mage))
	var res := TurnResolver.resolve(gold_state, {CROWN: recruits}, TurnResolver.seed_for_turn(gold_state))
	var joined := _army_at(res.new_state, CROWN, s.find_faction(CROWN).capital)
	var f2 := 0
	var s2 := 0
	for u in joined.units:
		if u.type.trait_id == "Volley" or MagicRules.is_mage(u.type):
			s2 += 1
		else:
			f2 += 1
	var last := Forecast.second_rank(gold_state, CROWN, mage, "", recruits.slice(0, recruits.size() - 1))
	assert_eq(s2, int(last.second), "the forecast's second rank is the army's after the turn")
	assert_eq(f2, int(last.front), "and its front rank")
	assert_true(bool(last.exposed))
	# On the recruit button: a visible warning, once exposed.
	var rich := AscensionRules.with_nodes(_magic({CROWN: "regents_court"}), CROWN, ["sunlance"])
	rich.find_faction(CROWN).gold = 500
	var game := _screen(rich, [CROWN, CLANS])
	game.map.select_province(s.find_faction(CROWN).capital)
	assert_true(game.map.details.find_child("RecruitExposed_%s" % mage, true, false) == null, "no warning while the second rank is safe")
	for i in exposed_at + 1:
		game.map.queue_recruit(mage)
	game.map.select_province(s.find_faction(CROWN).capital)
	var warn := game.map.details.find_child("RecruitExposed_%s" % mage, true, false) as Label
	assert_true(warn != null, "the warning is on the page once the rank would be exposed (queued %d, exposed_at %d, warning '%s', gold %d)" % [
		game.map.orders.orders().size(), exposed_at, MagicView.recruit_warning(game.map.orders.view_state(), CROWN, mage, "", game.map.orders.orders()),
		game.map.orders.view_state().find_faction(CROWN).gold] + " " + str(game.map.details.get_children().map(func(n): return String(n.name)).slice(-14)))
	if warn != null:
		assert_eq(warn.text, MagicView.recruit_warning(game.map.orders.view_state(), CROWN, mage, "", game.map.orders.orders()))
	game.free()
	# Crossbowmen too: only when exposed, never a note when it isn't.
	assert_eq(MagicView.recruit_note(s, CROWN, "spearmen"), "", "a front-rank unit says nothing")


# --- the first spell, the report and the chip ----------------------------------------------------------------------

func test_the_first_spell_text_and_every_magic_row_of_the_report() -> void:
	var s := _magic({CROWN: "regents_court", CLANS: "beast_god_unbound"})
	# Research Sunlance with the pool full: the research phase finishes it this turn.
	var f := s.find_faction(CROWN)
	f.research_points = 30
	f.research_target = "sunlance"
	var r := TurnResolver.resolve(s, {}, TurnResolver.seed_for_turn(s))
	var done: Dictionary = r.events.filter(func(e): return String(e.type) == "research_done" and e.numbers.node == "sunlance")[0]
	var own := String(done.numbers.own_text)
	var cap := s.find_province(f.capital).name
	var mage_name := String(MagicData.MAGES[CROWN].name)
	assert_true(own.begins_with("You researched Sunlance"), own)
	assert_true(own.contains("You can now recruit %s at %s, from turn %d" % [mage_name, cap, s.current_turn + 2]), own)
	assert_true(own.contains("each Adept casts a spell every round instead of attacking"), own)
	assert_true(own.contains(String(MagicData.SPELLS.sunlance.text)), "the spell's own line: %s" % own)
	_assert_no_raw_ids(own, "the first-spell text")
	assert_eq(TurnReportText.own_text(done, CROWN), own, "the faction reads it in its own words")
	assert_eq(TurnReportText.own_text(done, CLANS), String(done.text), "a rival reads the plain event")
	var rows := TurnReportText.rows(r.events, r.new_state, CROWN)
	assert_true(rows.any(func(row): return String(row.text) == own), "the report shows it")
	# A second spell does not repeat the mage line.
	var more := AscensionRules.with_nodes(r.new_state, CROWN, [])
	more.find_faction(CROWN).research_points = 30
	more.find_faction(CROWN).research_target = "shield_of_law"
	var r2 := TurnResolver.resolve(more, {}, TurnResolver.seed_for_turn(more))
	var second := String(r2.events.filter(func(e): return String(e.type) == "research_done" and e.numbers.node == "shield_of_law")[0].numbers.own_text)
	assert_true(second.begins_with("You researched Shield of Law, a battle spell of Law."), second)
	assert_false(second.contains("You can now recruit"), "only the first spell opens the mage")
	# A ritual says how it is cast and for how much; a mastery node what it adds.
	var rit := AscensionRules.with_nodes(s, CROWN, ["sunlance"])
	rit.find_faction(CROWN).research_points = 40
	rit.find_faction(CROWN).research_target = "dawn_blessing"
	var r3 := TurnResolver.resolve(rit, {}, TurnResolver.seed_for_turn(rit))
	var ritual_text := String(r3.events.filter(func(e): return String(e.type) == "research_done" and e.numbers.node == "dawn_blessing")[0].numbers.own_text)
	assert_true(ritual_text.contains("a ritual of the Sun") and ritual_text.contains("%d gold" % int(MagicData.SPELLS.dawn_blessing.cost)), ritual_text)
	# Nothing left to research: the report row that sells it (research_sold), with its codex link.
	var all := _magic({CROWN: "regents_court"})
	var every: Array = []
	for nid in AscensionRules.node_ids(CROWN) + MagicRules.arcana_ids(CROWN):
		var side := String(AscensionRules.node_data(String(nid)).get("branch", ""))
		if side != "living_iron" and nid != "bastion":  # the Forge side and Bastion close when the Dawn is sworn
			every.append(nid)
	var finished := AscensionRules.with_nodes(all, CROWN, every)
	assert_true(AscensionRules.all_complete(finished, CROWN), "everything is researched or closed")
	finished.find_faction(CROWN).research_points = 11
	var r4 := TurnResolver.resolve(finished, {}, TurnResolver.seed_for_turn(finished))
	var sold: Dictionary = r4.events.filter(func(e): return String(e.type) == "research_sold")[0]
	var pool := 11 + int(AscensionRules.research_rate(finished, CROWN).rate)
	var expect := MagicRules.research_sold(pool)
	assert_eq(int(sold.numbers.gold), int(expect.gold), "the research the phase gained is sold at 2 a gold")
	assert_eq(int(sold.numbers.research), int(expect.research))
	assert_eq(String(sold.codex), "research_sold")
	assert_true(RulesCodex.ENTRIES.has(String(sold.codex)))
	assert_true(String(sold.text).contains(str(int(expect.gold))), sold.text)
	var chip := PathView.chip(finished, CROWN)
	assert_true(String(chip.text).contains("nothing left"), chip.text)
	assert_eq(String(chip.codex), "research_sold")
	assert_eq(Breakdown.research_sold(finished, CROWN).gold, MagicRules.research_sold(11).gold)


func test_a_curse_that_falls_on_you_says_how_to_stop_it() -> void:
	var s := _clans_state()
	var army := _army_at(s, CLANS, "thornvale")
	var order := CastOrder.new("bloodrot", army.id, "crownkeep")
	# The Crown knows Sanctum Ward: the line says to cast it, and what it does.
	var r := TurnResolver.resolve(s, {CLANS: [order]}, TurnResolver.seed_for_turn(s))
	var fell: Dictionary = r.events.filter(func(e): return String(e.type) == "ritual_fell")[0]
	var text := String(fell.text)
	assert_true(text.begins_with("Bloodrot fell on Crownkeep"), text)
	assert_true(text.contains("To stop it, the Aurel Crown can cast Sanctum Ward on Crownkeep (it bites once more, then ends), or move out."), text)
	assert_true(text.contains("%d hit points" % int(MagicRules.spell_numbers("bloodrot", 0).value)), "the curse's number")
	assert_true(text.contains("through turn %d" % int(fell.numbers.until_turn)), text)
	assert_true(String(TurnReportText.line(fell, r.events, r.new_state, CROWN)).contains("To stop it"), "the owner reads it")
	assert_eq(String(fell.codex), "spell_bloodrot")
	# Without Law the line says what would end it and what it takes to reach.
	var bare := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": []}})
	bare = AscensionRules.with_nodes(bare, CLANS, ["bloodbolt", "bloodrot"])
	for f in bare.factions:
		f.gold = 100
	var a2 := Fx.army(bare, CLANS, bare.new_army_id(CLANS), "thornvale", ["shamans"])
	bare.find_province("thornvale").owner = CLANS
	var r2 := TurnResolver.resolve(bare, {CLANS: [CastOrder.new("bloodrot", a2.id, "crownkeep")]}, TurnResolver.seed_for_turn(bare))
	var fell2: Dictionary = r2.events.filter(func(e): return String(e.type) == "ritual_fell")[0]
	var reach := MagicRules.reach_cost(bare, CROWN, "sanctum_ward")
	assert_eq(reach, AscensionRules.node_cost("shield_of_law") + AscensionRules.node_cost("sanctum_ward"))
	assert_true(String(fell2.text).contains("Sanctum Ward (Law: %d research to reach) would end it. Until then, move out or wait for the end of turn %d." % [reach, int(fell2.numbers.until_turn)]), fell2.text)
	_assert_no_raw_ids(text + String(fell2.text), "the curse lines")


func test_every_magic_event_row_has_a_line_and_a_valid_codex_link() -> void:
	var s := _clans_state()
	Fx.army(s, CROWN, "kingdom-9", "crownkeep", ["spearmen", "spearmen", "adepts"])
	var cast := _army_at(s, CLANS, "thornvale")
	var crown_army := _army_at(s, CROWN, "crownkeep")
	var crown := s.find_faction(CROWN)
	crown.gold = 200
	var orders := {CLANS: [CastOrder.new("bloodrot", cast.id, "crownkeep", CastOrder.BLOOD), CastOrder.new("call_the_pack", cast.id, "thornvale", CastOrder.GOLD, 3)],
		CROWN: [CastOrder.new("sanctum_ward", crown_army.id, "crownkeep")]}
	# One cast order an army: the pack needs its own army.
	var second := Fx.army(s, CLANS, s.new_army_id(CLANS), "thornvale", ["shamans"])
	orders[CLANS][1] = CastOrder.new("call_the_pack", second.id, "thornvale", CastOrder.GOLD, 3)
	var r := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s))
	var seen := {}
	for row in TurnReportText.rows(r.events, r.new_state, CLANS):
		var e: Dictionary = row.event
		seen[String(e.type)] = true
		if not ["ritual_cast", "ritual_turned_aside", "ritual_fell", "summoned", "fort_raised", "blessing_healed", "curse_bit", "enchantment_ended",
				"summon_faded", "research_sold", "blood_paid"].has(String(e.type)):
			continue
		assert_false(String(row.text).is_empty(), "%s has a line" % e.type)
		assert_true(RulesCodex.ENTRIES.has(String(e.codex)), "%s: its codex entry %s exists" % [e.type, e.codex])
		_assert_no_raw_ids(String(row.text), "the %s row" % e.type)
	for t in ["ritual_cast", "blood_paid", "ritual_fell", "curse_bit"]:
		assert_true(seen.has(t), "the turn had a %s row" % t)
	# The panel gives each its "?" button with the entry.
	var panel := TurnReportPanel.new()
	var report := {"turn": 1, "header": "Turn 1", "events": r.events}
	panel.show_report_data(report, CLANS, true, r.new_state)
	var keys := panel.codex_buttons().map(func(b): return String(b.get_meta("codex_key")))
	for k in keys:
		assert_true(RulesCodex.ENTRIES.has(k), "%s exists" % k)
	assert_true(keys.has("spell_bloodrot") and keys.has("mandate_tithe_of_blood"), "the cast and the blood link their entries")
	panel.free()


func test_the_magic_chip_counts_your_spells_and_opens_the_magic_tab() -> void:
	var s := _magic({CROWN: "regents_court"})
	var game := _screen(s, [CROWN, CLANS])
	var hud := game.research_hud
	assert_true(hud.magic_chip.visible, "the chip shows in a magic game")
	var c := MagicView.chip(game.session.state(), CROWN, game.session.current_orders())
	assert_eq(hud.magic_chip.text, String(c.text))
	assert_true(String(c.text).begins_with("Magic: no spell yet"), c.text)
	assert_true(c.attention, "with no spell the chip draws the eye")
	assert_eq(int(c.breakdown.total), 0)
	# Know two spells and queue a cast: the numbers follow.
	var s2 := AscensionRules.with_nodes(_clans_state(), CLANS, [])
	var g2 := _screen(s2, [CLANS, CROWN])
	var state2 := g2.session.state()
	var c2 := MagicView.chip(state2, CLANS, [])
	var known := MagicRules.known_spells(state2, CLANS)
	assert_eq(int(c2.breakdown.total), known.size())
	assert_eq(Breakdown.sum_of_lines(c2.breakdown), known.size(), "one line a spell")
	var mages := 0
	for a in state2.armies:
		if a.owner == CLANS:
			for u in a.units:
				if MagicRules.is_mage(u.type):
					mages += 1
	assert_true(String(c2.text).contains(TooltipText.count(known.size(), "spell")), c2.text)
	assert_true(String(c2.text).contains(TooltipText.count(mages, "mage")), c2.text)
	assert_false(c2.attention)
	var army := _army_at(state2, CLANS, "thornvale")
	assert_eq(g2.map.queue_cast("bloodrot", army.id, "crownkeep", CastOrder.GOLD, 0), "")
	var c3 := MagicView.chip(state2, CLANS, g2.map.orders.orders())
	assert_true(String(c3.text).contains("1 cast ordered"), c3.text)
	assert_true(String(c3.tooltip).contains(String(Forecast.cast_budget(state2, CLANS, g2.map.orders.orders()).text)), "the gold they leave")
	assert_eq(g2.research_hud.magic_chip.text, String(c3.text), "the chip on the top bar follows the orders")
	var chip := g2.research_hud.magic_chip
	assert_true(chip.has_meta("breakdown"), "the chip's numbers have a breakdown")
	assert_true(chip.tooltip_text.begins_with(TooltipText.from_breakdown(chip.get_meta("breakdown"))))
	assert_eq(Breakdown.sum_of_lines(chip.get_meta("breakdown")), int(chip.get_meta("breakdown").total))
	assert_eq(CodexLink.key_at(chip), "magic")
	# A click opens the Magic tab.
	g2.research_hud.magic_chip.pressed.emit()
	assert_true(g2.research_hud.panel.visible and g2.research_hud.panel.showing_magic, "the chip opens the Magic tab")
	g2.free()
	# No magic chip without magic.
	var plain := load(GAME_SCENE).instantiate() as GameScreen
	plain.start_game({"players": [CROWN, CLANS], "seed": SEED, "paths": true})
	if plain.handoff.visible:
		plain.handoff.ready_button.pressed.emit()
	assert_false(plain.research_hud.magic_chip.visible)
	plain.free()
	game.free()


func test_the_research_chip_says_what_a_spell_target_does_to_your_transformation() -> void:
	var s := _magic({CROWN: "regents_court"})
	var game := _screen(s, [CROWN, CLANS])
	assert_eq(game.session.queue_research("sunlance"), "")
	game.research_hud.refresh()
	var d := Forecast.arcana_delay(game.session.state(), CROWN, "sunlance", game.session.current_orders())
	assert_true(d.applies)
	assert_true(game.research_hud.chip.tooltip_text.replace("\n", " ").contains(String(d.text)), game.research_hud.chip.tooltip_text)
	game.free()


# --- the lock-in preview ------------------------------------------------------------------------------------------

func test_the_lock_in_preview_has_a_magic_row_equal_to_the_result() -> void:
	var s := _magic({CROWN: "regents_court", CLANS: "beast_god_unbound"})
	for fid in [CROWN, CLANS]:
		for side in PathData.BRANCHES:
			if String(PathData.BRANCHES[side].faction) != fid:
				continue
			var oath := String(PathData.BRANCHES[side].oath)
			var base := AscensionRules.with_nodes(s, fid, _ordinary_pair(fid))
			var p := PathView.preview(base, fid, oath)
			assert_true(p.ok, "%s: a preview" % side)
			var rows := MagicView.lock_in_rows(p, fid)
			var school := MagicView._aligned_school(fid, String(side))
			var greater := String(MagicRules.school_data(school).nodes[3])
			assert_true(String(rows.gain.text).contains("Opens %s (%s, greater working)" % [MagicRules.spell_name(greater), MagicRules.school_name(school)]), rows.gain.text)
			# The numbers equal the result of swearing the Oath and becoming the people: with_nodes on a copy.
			var result := AscensionRules.with_nodes(base, fid, [oath, String(PathData.BRANCHES[side].transformation)])
			var was_bonus := int(MagicRules.mastery_bonus(base, fid, school, MagicRules.MAGE).value)
			var now_bonus := int(MagicRules.mastery_bonus(result, fid, school, MagicRules.MAGE).value)
			assert_eq(now_bonus - was_bonus, int(MagicData.MASTERY.transformation), "the transformation adds +1 in its school")
			for sid in MagicRules.school_data(school).nodes:
				var sp := MagicRules.spell_data(String(sid))
				var per: Dictionary = sp.get("per_bonus", {})
				if sp.is_empty() or per.is_empty():
					continue
				var key := "value" if per.has("value") else ("count" if per.has("count") else "duration")
				var was := int(MagicRules.spell_numbers(String(sid), was_bonus)[key])
				var now := int(MagicRules.spell_numbers(String(sid), now_bonus)[key])
				if String(sp.kind) == "bolt":
					assert_true(String(rows.gain.text).contains("%d → %d" % [was, now]), "%s: %d → %d in %s" % [sid, was, now, rows.gain.text])
				elif String(sp.kind) == "blessing":
					assert_true(String(rows.gain.text).contains("heals %d a turn instead of %d" % [now, was]), rows.gain.text)
				elif String(sp.kind) == "curse":
					assert_true(String(rows.gain.text).contains("takes %d a turn instead of %d" % [now, was]), rows.gain.text)
			assert_eq(rows.gain.breakdown, Breakdown.mastery(p.after, fid, school, MagicRules.MAGE))
			assert_eq(Breakdown.sum_of_lines(rows.gain.breakdown), int(rows.gain.breakdown.total))
			# The closed side's greater working is struck through.
			var other := AscensionRules.other_branch(fid, String(side))
			var other_school := MagicView._aligned_school(fid, other)
			var closed := String(MagicRules.school_data(other_school).nodes[3])
			assert_true(bool(rows.lose.strike) and String(rows.lose.text).begins_with(MagicRules.spell_name(closed)), rows.lose.text)
			# The dialog shows both.
			var dialog := LockInPreview.new()
			dialog.show_for(base, fid, oath)
			assert_true(dialog.gain_box.find_child("MagicGain", true, false) != null)
			var struck := dialog.lose_box.find_child("MagicLose", true, false) as RichTextLabel
			assert_true(struck != null and struck.text.begins_with("[s]"), "struck through")
			assert_true(bool(struck.get_meta("struck", false)))
			_assert_numbers_explained(dialog.gain_box, "the lock-in gains")
			dialog.free()
	# Without magic, no row.
	var plain := GameState.with_paths(SEED)
	var pp := PathView.preview(AscensionRules.with_nodes(plain, CROWN, _ordinary_pair(CROWN)), CROWN, "crown_oath_dawn")
	assert_eq(MagicView.lock_in_rows(pp, CROWN), {"gain": {}, "lose": {}})


# --- the build screen -------------------------------------------------------------------------------------------

func test_the_build_screen_says_when_tithe_of_blood_is_first_used() -> void:
	for fog in [false, true]:
		var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
		b.begin({"players": [CLANS, CROWN], "seed": SEED, "ai": {CROWN: "normal"}, "magic": true, "fog": fog})
		if b.step == BuildScreen.Step.HANDOFF:
			b.acknowledge()
		var start := GameState.with_magic(SEED, {}, [])
		var expect := MagicRules.tithe_first_use(start, CLANS, fog)
		assert_false(expect.is_empty())
		assert_true(String(b.mandate_checks[MagicRules.TITHE_OF_BLOOD].tooltip_text).replace("\n", " ").contains(expect.left(40)), "the row's tooltip has the first use")
		assert_true(expect.contains("about turn %d" % (start.current_turn + AscensionRules.eta(MagicRules.reach_cost(start, CLANS, "call_the_pack"),
			AscensionRules.research_points(start, CLANS), int(AscensionRules.research_rate(start, CLANS).rate)))), expect)
		if fog:
			assert_true(expect.contains("Far Sight") and expect.contains("Shamans") or expect.contains("Far Sight"), expect)
		else:
			assert_false(expect.contains("Far Sight"), "without fog Far Sight is not on offer")
		b.free()
	# The effect line says you choose on each cast.
	assert_true(String(MandateData.MAGIC_MANDATES[0].effect).contains("You choose gold or blood on each cast"))


# --- no magic: nothing of this on screen -----------------------------------------------------------------------------

func test_without_magic_there_is_nothing_of_this_on_screen() -> void:
	var s := GameState.with_paths(SEED)
	assert_eq(Forecast.spellbook_preview(s, CROWN), [])
	assert_false(bool(Forecast.spells_forecast(s, CROWN, [], "highcrag").ok))
	assert_eq(MagicView.mage_card(s, CROWN), "")
	assert_eq(MagicView.recruit_warning(s, CROWN, "spearmen"), "")
	assert_eq(EnchantmentBadges.badges(s, CROWN, "crownkeep"), [])
	assert_true(EnchantmentBadges.make(s, "crownkeep", CROWN) == null)
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game({"players": [CROWN, CLANS], "seed": SEED})
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	assert_false(game.map.casting())
	game.map.select_province(game.session.state().find_faction(CROWN).capital)
	assert_true(game.map.details.find_child("CastersLine", true, false) == null, "no casters line")
	game.free()


# --- every number explained, every term linked --------------------------------------------------------------------------

func test_every_number_on_the_magic_screens_has_its_breakdown_and_every_term_its_codex_entry() -> void:
	var counted := 0
	var linked := 0
	# The Magic tab, both factions, at the start and with spells known and a queued spellbook.
	for fid in [CROWN, CLANS]:
		for known in [[], ["sunlance", "briar_snare"]]:
			var s := _magic({CROWN: "regents_court", CLANS: "beast_god_unbound"})
			if not known.is_empty():
				s = AscensionRules.with_nodes(s, fid, known)
			Fx.army(s, fid, s.new_army_id(fid), s.find_faction(fid).capital, ["spearmen" if fid == CROWN else "tuskers", "adepts" if fid == CROWN else "shamans"])
			var panel := ResearchPanel.new()
			panel.show_for(s, fid, [SpellbookOrder.new(MagicRules.spellbook(s, fid).order, [])])
			panel.show_magic()
			counted += _assert_numbers_explained(panel, "the Magic tab (%s)" % fid)
			linked += _assert_links_valid(panel, "the Magic tab (%s)" % fid)
			counted += _assert_terms_linked(panel, "the Magic tab (%s)" % fid)
			_assert_no_raw_ids(_texts(panel), "the Magic tab (%s)" % fid)
			panel.free()
	# The cast dialog for every ritual and target, the army panel, the badges and the chip.
	var s := _clans_state()
	s.find_faction(CROWN).enchant_counter += 1
	s.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false})
	var game := _screen(s, [CLANS, CROWN])
	var map := game.map
	var army := _army_at(game.session.state(), CLANS, "thornvale")
	map.select_province("thornvale")
	for name in ["CastersLine", "MasteryLine"]:
		var l := map.details.find_child(name, true, false) as Label
		assert_true(l != null and l.has_meta("breakdown"), "the army panel's %s has a breakdown" % name)
		counted += 1
	linked += _assert_links_valid(map.details, "the army panel")
	map.open_cast_dialog(army.id)
	for o in map.cast_dialog.options:
		map.cast_dialog.select_ritual(String(o.ritual))
		for pay in ([CastOrder.GOLD, CastOrder.BLOOD] if bool(o.blood) else [CastOrder.GOLD]):
			map.cast_dialog.set_pay(pay)
			counted += _assert_numbers_explained(map.cast_dialog, "the cast dialog (%s, %s)" % [o.ritual, pay])
			linked += _assert_links_valid(map.cast_dialog, "the cast dialog")
			_assert_no_raw_ids(_texts(map.cast_dialog), "the cast dialog (%s)" % o.ritual)
	map.close_cast_dialog()
	linked += _assert_links_valid(map.regions["crownkeep"].enchantment_badges, "the badges")
	assert_true(game.research_hud.magic_chip.has_meta("breakdown"))
	linked += _assert_links_valid(game.research_hud.magic_chip, "the Magic chip")
	game.free()
	assert_true(counted > 60, "%d numbers checked" % counted)
	assert_true(linked > 60, "%d links checked" % linked)
	# The new terms have entries, and each is explained in the words the screens use.
	for key in ["field_spell", "spellbook_preview", "arcana", "caster", "mastery", "spellbook", "ward", "curse", "enchantment", "pinned", "turned_aside",
			"trait_mage", "cast_order", "ritual", "greater_working", "research_sold", "view_odds", "mandate_tithe_of_blood", "magic"]:
		assert_true(RulesCodex.ENTRIES.has(key), "the codex has %s" % key)
		assert_false(RulesCodex.text(key).is_empty())
	assert_true(RulesCodex.text("arcana").contains("delay"), "the arcana entry explains the delay")
	assert_true(RulesCodex.text("enchantment").contains("badge"), "the enchantment entry explains the badge")
	assert_true(RulesCodex.text("view_odds").contains("assumed"), "the odds entry explains the assumed spells")
	assert_true(RulesCodex.text("field_spell").contains("terrain or fort bonus"))
