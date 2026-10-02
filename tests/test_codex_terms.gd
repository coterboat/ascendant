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
