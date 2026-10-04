extends "res://tests/test_case.gd"
## #8's minimal codex: every M1 term in the issue has its own entry, in plain words that match the
## rules, and every codex link on the map points at the term's real entry and resolves.
## #8 lists: province, income, terrain types, each stat, each trait, army, commander, move, recruit,
## capture, simultaneous resolution and its phase order. The M1 polish job adds fort, capital, neutral
## provinces, gold, units and unit traits as a general term.

const GAME_SCENE := "res://ui/game_screen.tscn"
const PANEL_SCENE := "res://ui/codex_panel.tscn"
const LINK_LINE := "Codex: %s (right-click or F1 to open)"

## #8 term -> [codex key, its title].
const TERMS := {
	"province": ["province", "Province"],
	"income": ["income", "Income"],
	"plains": ["terrain_plains", "Plains"],
	"forest": ["terrain_forest", "Forest"],
	"hills": ["terrain_hills", "Hills"],
	"hit points": ["stat_hit_points", "Hit points"],
	"attack": ["stat_attack", "Attack"],
	"defense": ["stat_defense", "Defense"],
	"morale": ["stat_morale", "Morale"],
	"cost": ["stat_cost", "Cost"],
	"unit traits": ["unit_traits", "Unit traits"],
	"army": ["army", "Army"],
	"commander": ["commander", "Commander"],
	"move": ["move", "Moving"],
	"recruit": ["recruit", "Recruiting"],
	"capture": ["capture", "Capturing provinces"],
	"simultaneous resolution and its phase order": ["phase_order", "How a turn resolves"],
	"fort": ["fort", "Fort"],
	"capital": ["capital", "Capital"],
	"neutral provinces": ["neutral", "Neutral provinces"],
	"gold": ["gold", "Gold"],
	"units": ["units", "Units"],
}


func test_every_m1_term_has_its_own_entry() -> void:
	for term in TERMS:
		var key: String = TERMS[term][0]
		assert_true(RulesCodex.ENTRIES.has(key), "#8 term '%s' has codex entry %s" % [term, key])
		var e := RulesCodex.entry(key)
		assert_eq(String(e.get("title", "")), TERMS[term][1], "the entry for '%s' is titled for players" % term)
		var text := RulesCodex.text(key)
		assert_true(text.length() > 60, "'%s' is explained, not just named: %s" % [term, text])
		assert_false(text.contains("_") or String(e.get("title", "")).contains("_"), "no raw ids in the entry for '%s'" % term)
	# Each trait of every unit type and commander (#8: "each trait").
	for f in GameState.new().factions:
		var types: Array = f.unit_types.duplicate()
		types.append(f.commander_type)
		for ut in types:
			var key := AutoBattleResolver.codex_id_for_trait(ut.trait_id)
			assert_true(RulesCodex.ENTRIES.has(key), "the trait of %s (%s) has codex entry %s" % [ut.name, ut.trait_id, key])
	# Every terrain on the map has an entry of its own, not just Terrain in battle.
	for p in MapData.PROVINCES:
		var kind := TooltipText.terrain_kind(p.terrain)
		assert_ne(kind, "terrain", "terrain '%s' has its own codex kind" % p.terrain)
		assert_true(RulesCodex.ENTRIES.has(TooltipText.codex_for(kind)), "terrain '%s' has an entry" % p.terrain)


## The new block is plain text (tooltips quote it), and the codex panel turns mentions of other entries
## into links, multi-word titles included.
func test_new_entries_are_plain_text_and_the_panel_links_them() -> void:
	for term in TERMS:
		assert_false(RulesCodex.text(TERMS[term][0]).contains("["), "'%s' has no BBCode, so tooltips can quote it" % term)
	var panel = load(PANEL_SCENE).instantiate()
	panel.show_entry("units")
	var body := (panel.get_node("%EntryText") as RichTextLabel).text
	for target in ["stat_hit_points", "stat_attack", "stat_defense", "stat_morale", "stat_cost", "army"]:
		assert_true(body.contains("[url=codex:%s]" % target), "Units links to %s: %s" % [target, body])
	panel.show_entry("stat_morale")
	body = (panel.get_node("%EntryText") as RichTextLabel).text
	assert_true(body.contains("[url=codex:battle_morale]Morale and routs[/url]"), "a multi-word title links, and beats the shorter Morale: %s" % body)
	assert_false(body.contains("[url=codex:stat_morale]"), "an entry never links to itself")
	panel.free()


## The terrain and fort entries quote the battle rules' own numbers (AutoBattleResolver), so a balance
## change that forgets the codex fails here.
func test_terrain_and_fort_entries_match_the_battle_rules() -> void:
	var t := AutoBattleResolver.TERRAIN
	assert_eq(int(t.plains.defense) + int(t.plains.attack), 0, "plains give nothing")
	assert_true(RulesCodex.text("terrain_plains").contains("no bonus"), RulesCodex.text("terrain_plains"))
	assert_true(RulesCodex.text("terrain_forest").contains("+%d defense" % t.forest.defense), RulesCodex.text("terrain_forest"))
	assert_eq(int(t.forest.attack), 0)
	assert_true(RulesCodex.text("terrain_hills").contains("+%d defense and +%d attack" % [t.hills.defense, t.hills.attack]), RulesCodex.text("terrain_hills"))
	assert_true(RulesCodex.text("fort").contains("+%d defense" % AutoBattleResolver.FORT_DEFENSE), RulesCodex.text("fort"))
	for key in ["terrain_forest", "terrain_hills", "fort"]:
		assert_true(RulesCodex.text(key).contains("holding"), "%s says only the holding army (the defender) gets it" % key)


## Every number and term on the map links to its real entry, for every province and both seatings.
func test_map_terms_link_to_their_real_entries() -> void:
	for seats in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var game := load(GAME_SCENE).instantiate() as GameScreen
		game.start_game({"players": seats, "seed": 11})
		var map := game.map
		var s := map.state
		assert_eq(String(map.gold_label.get_meta(CodexLink.META)), "gold")
		for p in s.provinces:
			map.selected_army_id = ""
			map.select_province(p.id)
			_assert_links_resolve(map, p.name)
			var region: ProvinceRegion = map.regions[p.id]
			assert_eq(String(region.get_meta(CodexLink.META)), "province", "%s's region links to Province" % p.name)
			assert_eq(_key(map, "OwnerLabel"), "neutral" if p.owner.is_empty() else "province", "%s's owner" % p.name)
			assert_eq(_key(map, "TerrainLabel"), "terrain_" + p.terrain, "%s's terrain" % p.name)
			assert_eq(_key(map, "CapitalLabel"), "capital")
			assert_eq(_key(map, "FortLabel"), "fort")
			assert_eq(_key(map, "NeighborsLabel"), "province")
			assert_eq(_key(map, "IncomeLabel"), "income")
			var terrain := map.details.find_children("TerrainLabel", "Label", true, false)[0] as Label
			assert_true(terrain.tooltip_text.replace("\n", " ").contains(RulesCodex.text("terrain_" + p.terrain).left(30)),
				"the terrain tooltip uses the codex's words: %s" % terrain.tooltip_text)
		for a in s.armies:
			map.select_army(a.id)
			_assert_links_resolve(map, "army %s" % a.id)
			assert_eq(_key(map, "ArmyHeader"), "army")
			assert_eq(_key(map, "UnitsLabel"), "army")
			assert_eq(_key(map, "CommanderLabel"), "commander")
			assert_eq(_key(map, "StrengthLabel"), "army_strength")
			for count in map.details.find_children("UnitCount", "Label", true, false):
				assert_eq(String(count.get_meta(CodexLink.META)), "units", "unit count '%s'" % count.text)
		game.free()


## Every linked control under `root` names an existing entry at the end of its tooltip.
func _assert_links_resolve(root: Node, where: String) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Control and n.has_meta(CodexLink.META)):
			continue
		var key := String(n.get_meta(CodexLink.META))
		assert_true(RulesCodex.ENTRIES.has(key), "%s: '%s' links %s, which exists" % [where, n.name, key])
		var title := String(RulesCodex.entry(key).get("title", ""))
		assert_true((n as Control).tooltip_text.replace("\n", " ").ends_with(LINK_LINE % title),
			"%s: '%s' ends its tooltip with its entry: %s" % [where, n.name, (n as Control).tooltip_text])


func _key(map: MapScreen, node_name: String) -> String:
	var found := map.details.find_children(node_name, "", true, false)
	if found.is_empty():
		fail("the side panel has %s" % node_name)
		return ""
	return String(found[0].get_meta(CodexLink.META, ""))


## M2_RULER §7.2 (#50): the M1 entries a game with rulers changes keep their M1 rule first, so an M1
## game still reads right, then say what rulers add in an "In a game with rulers" sentence. They take
## no numbers of their own: the mandate entries and data/mandates.gd hold those, so retuned mandates
## can never leave these entries wrong. Plain text, since tooltips quote them.
func test_m1_entries_say_what_a_game_with_rulers_changes() -> void:
	var m1_rule := {
		"orders": "Each turn you can move each army once, to a province next to it, and recruit units at your capital.",
		"move": "An army moves one province per turn, to a neighbor of the province it is in.",
		"recruit": "Recruit units from your own roster at your capital.",
		"income": "At the end of the turn, each faction earns the income of every province it owns",
		"victory": "Capture the enemy capital to win.",
	}
	var m2_rules := {
		"orders": ["King's Roads", "road move", "Warband Muster", "Ninth Fang", "one Sacrifice order per turn", "before every other order"],
		"move": ["King's Roads", "two provinces", "road move", "never fights a border battle"],
		"recruit": ["never join the ruler's army", "Muster Grounds", "Warband Muster", "Ninth Fang"],
		"income": ["Heavy Tithes", "Royal Court", "King Corvane"],
		"victory": ["a ruler's death never ends the game", "only the capital decides"],
		"ruler_army": ["one province per turn", "road move with King's Roads", "Warband Muster", "a successor arrives"],
	}
	var digits := RegEx.create_from_string("[0-9]")
	for id in m2_rules:
		var text := RulesCodex.text(id)
		for phrase in m2_rules[id]:
			assert_true(text.contains(phrase), "%s mentions '%s': %s" % [id, phrase, text])
		if m1_rule.has(id):
			assert_true(text.begins_with(m1_rule[id]), "%s states its M1 rule first: %s" % [id, text])
			assert_true(text.find("In a game with rulers") > m1_rule[id].length(), "%s adds the rulers part after it: %s" % [id, text])
		assert_true(digits.search(text) == null, "%s has no numbers of its own: %s" % [id, text])
		assert_false(text.contains("[") or text.contains("_"), "%s is plain text with no ids: %s" % [id, text])


## M3c S-3 (#101, design/M3C_SIEGES.md §9.6, §15): every forts-and-sieges term has its own entry in plain words,
## and every control of the fort panel, the recruit picker, the siege order lines and the plates' fort chips links
## to a real entry, for both sides of a siege, a construction site, a quiet capital and a breach.
func test_siege_terms_have_entries_and_every_fort_control_links_one() -> void:
	var terms := ["fort", "fort_levels", "palisade", "keep", "citadel", "recruit_at_forts", "fortify", "construction", "walls",
		"repair", "siege", "inside_outside", "siege_damage", "cut_off", "storm", "sally", "relief", "breach", "empty_fort",
		"trait_siege_engine", "unit_siege_ram", "unit_wallbreakers"]
	for key in terms:
		assert_true(RulesCodex.ENTRIES.has(key), "the siege term %s has an entry" % key)
		var text := RulesCodex.text(key)
		assert_true(text.length() > 60, "%s is explained: %s" % [key, text])
		assert_false(text.contains("[") or text.contains("_"), "%s is plain text with no ids" % key)
	for kind in TooltipText.CODEX:
		assert_true(RulesCodex.ENTRIES.has(String(TooltipText.CODEX[kind])), "the %s kind links a real entry" % kind)
	var Fx := preload("res://tests/siege_fixtures.gd")
	var s: GameState = load("res://tests/test_fort_panel.gd").besieged_keep(true)
	Fx.rich(s, "kingdom")
	s.find_province("rivermarch").owner = "kingdom"
	s.find_province("rivermarch").works = {"faction": "kingdom", "to": 1, "left": 1, "turn": 1}
	s.find_province("blackwood").owner = "kingdom"
	s.armies.append(Fx.army(s, ["beasts-9", "beasts", "thornvale", Fx.units("tuskers", 6)]))
	for viewer in ["kingdom", "beasts"]:
		var map: MapScreen = load("res://ui/map_screen.tscn").instantiate()
		map.set_state(s, viewer)
		if viewer == "kingdom":
			map.queue_move("kingdom-7", "stonegate")  # a relief, with its tied sallies
			map.queue_recruit_at("spearmen", "blackwood")
		else:
			map.queue_move("beasts-9", "stonegate")  # a siege from the march, with Storm now on its line
			map.set_storm("stonegate", true)
		for pid in ["stonegate", "rivermarch", "crownkeep", "blackwood", "westwatch"]:
			map.selected_army_id = ""
			map.select_province(pid)
			_assert_links_resolve(map.details, "%s sees %s" % [viewer, pid])
		for region in map.regions.values():
			if region.fort_chip != null:
				_assert_links_resolve(region.fort_chip, "%s's chip at %s" % [viewer, region.province_id])
		map.free()
	# A queued Fortify order.
	var quiet := GameState.with_sieges(5)
	quiet.find_province("rivermarch").owner = "kingdom"
	var m1: MapScreen = load("res://ui/map_screen.tscn").instantiate()
	m1.set_state(quiet, "kingdom")
	assert_eq(m1.queue_fortify("rivermarch"), "")
	m1.select_province("rivermarch")
	assert_true(not m1.details.find_children("FortifyQueued", "", true, false).is_empty())
	_assert_links_resolve(m1.details, "a queued Fortify")
	_assert_links_resolve(m1.regions["rivermarch"], "the Fortify ghost")
	m1.free()
	# A breach.
	s.find_province("stonegate").walls = 0
	var m2: MapScreen = load("res://ui/map_screen.tscn").instantiate()
	m2.set_state(s, "beasts")
	m2.select_province("stonegate")
	_assert_links_resolve(m2.details, "the breach")
	m2.free()
