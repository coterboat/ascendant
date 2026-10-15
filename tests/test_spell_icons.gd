extends "res://tests/test_case.gd"
## UI-ICONS (#233): #224's magic art on screen. Every place below shows a spell's icon beside its name when the icon's file has landed
## (Art.spell_icon, #225) and keeps today's look when it hasn't (SpellIcons.source swapped for one that finds nothing):
##   the research panel's Magic tab (each arcana card that is a spell), the battle spellbook's rows and its preview (the spells each
##   caster army will cast), the cast dialog's rituals, the codex (a spell's entry in the list and on its page, and the blood
##   mandate's), the Chronicle's cards about a spell, and the build screen's blood mandate.
## And the four new portraits (the Adepts, the Shamans, the Thornwolves, the Greenwrath) show wherever a unit's portrait does, with
## Art.unit_faction finding the faction of a mage or a summon. Every spell and unit list comes from MagicData, never this file.

const Mx := preload("res://tests/magic_battle_fixtures.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"

static var _real_source: Callable = Callable()


func _no_art() -> void:
	if not _real_source.is_valid():
		_real_source = SpellIcons.source
	SpellIcons.source = func(_k: String) -> Texture2D: return null


func _art_back() -> void:
	if _real_source.is_valid():
		SpellIcons.source = _real_source


## The keys whose icon file is in the game (the ones a test expects on screen).
func _with_art() -> Array:
	return SpellIcons.keys().filter(func(k): return ResourceLoader.exists(Art.SPELL_ICON_PATH % k))


## The Clans with Tithe of Blood and four rituals and battle spells known, an army of Shamans and Tuskers at Thornvale; the Crown
## with its four (as test_magic_ui's Clans game).
func _clans_state() -> GameState:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	s = AscensionRules.with_nodes(s, CROWN, ["sunlance", "shield_of_law", "sanctum_ward", "dawn_blessing"])
	for f in s.factions:
		f.gold = 200
	Mx.army(s, CLANS, s.new_army_id(CLANS), "thornvale", ["shamans", "shamans", "tuskers", "tuskers", "tuskers", "tuskers"])
	s.find_province("thornvale").owner = CLANS
	return s


func test_every_spell_and_the_blood_mandate_has_its_icon() -> void:
	var keys := SpellIcons.keys()
	assert_eq(keys.size(), MagicData.SPELLS.size() + 1, "every spell, and the blood mandate")
	for id in MagicData.SPELLS:
		assert_true(keys.has(id), "%s can have an icon" % id)
		assert_eq(SpellIcons.of_codex(String(MagicData.SPELLS[id].codex)), String(id), "its codex entry leads to it")
	assert_eq(SpellIcons.of_codex("mandate_tithe_of_blood"), SpellIcons.BLOOD_MANDATE)
	assert_eq(SpellIcons.of_codex("fort"), "", "an entry about something else has none")
	var art := _with_art()
	assert_eq(art.size(), keys.size(), "#225 brought all %d files" % keys.size())
	for k in art:
		assert_true(SpellIcons.texture(k) != null, "%s's icon loads" % k)
	assert_true(SpellIcons.texture("spearmen") == null, "a key outside the set has none")
	_no_art()
	for k in keys:
		assert_true(SpellIcons.texture(k) == null and SpellIcons.rect(k, 24) == null, "%s: no art, no icon" % k)
	_art_back()


func test_the_magic_tab_cards_and_the_spellbook_wear_the_icons() -> void:
	for fid in [CROWN, CLANS]:
		var s := _clans_state()
		var panel := ResearchPanel.new()
		panel.show_for(s, fid)
		panel.show_magic()
		var art := _with_art()
		for nid in MagicRules.arcana_ids(fid):
			var card: PanelContainer = panel.cards[nid]
			var want := MagicData.SPELLS.has(nid) and art.has(nid)
			assert_eq(SpellIcons.shown_under(card), [nid] if want else [], "%s's card: %s" % [nid, "its icon" if want else "no icon"])
			assert_true(card.find_child("Name", true, false) != null, "%s keeps its name" % nid)
		var rows := MagicView.spellbook_rows(s, fid)
		for r in rows:
			var row := panel.sidebar.find_child("Spell_%s" % String(r.spell), true, false)
			assert_true(row != null, "%s's spellbook row" % r.spell)
			if row != null:
				assert_eq(SpellIcons.shown_under(row), [String(r.spell)] if art.has(String(r.spell)) else [], "%s's row wears its icon" % r.spell)
		panel.free()
		# without the art: today's look, every card and row still there
		_no_art()
		var bare := ResearchPanel.new()
		bare.show_for(s, fid)
		bare.show_magic()
		assert_eq(SpellIcons.shown_under(bare), [], "no art: no icon anywhere on the Magic tab")
		for nid in MagicRules.arcana_ids(fid):
			assert_true(bare.cards.has(nid), "%s's card is still there" % nid)
		for r in rows:
			assert_true(bare.sidebar.find_child("Spell_%s" % String(r.spell), true, false) != null, "%s's row is still there" % r.spell)
		bare.free()
		_art_back()


func test_the_spellbook_preview_shows_what_each_army_will_cast() -> void:
	var s := Mx.game({CROWN: Mx.REGENT, CLANS: Mx.AVATAR})
	s = Mx.with_nodes(s, CROWN, ["sunlance", "shield_of_law", "dawn_blessing", "sanctum_ward"])
	Mx.army(s, CROWN, "kingdom-1", "highcrag", ["spearmen", "spearmen", "spearmen", "spearmen", "adepts", "adepts"])
	var panel := ResearchPanel.new()
	panel.show_for(s, CROWN)
	panel.show_magic()
	var shown := 0
	for pv in MagicView.spellbook_preview(s, CROWN):
		var want := []
		for c in pv.preview.open.casts:
			if String(c.faction) == CROWN and not want.has(String(c.spell)) and _with_art().has(String(c.spell)):
				want.append(String(c.spell))
		var strip := panel.sidebar.find_child("PreviewSpells_%s" % String(pv.province), true, false)
		assert_eq(SpellIcons.shown_under(strip) if strip != null else [], want, "%s: the spells it will cast, in order" % pv.province)
		shown += want.size()
	assert_true(shown > 0, "the Adepts' army casts something")
	panel.free()


func test_the_cast_dialogs_rituals_wear_their_icons() -> void:
	var s := _clans_state()
	var session := GameSession.new(s, [CLANS, CROWN], 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Spell icons", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	var army: Army = null
	for a in game.session.state().armies:
		if a.owner == CLANS and a.location == "thornvale" and a.ruler == null:
			army = a
	game.map.open_cast_dialog(army.id)
	var dialog := game.map.cast_dialog
	assert_false(dialog.options.is_empty(), "the Shamans have rituals to cast")
	for o in dialog.options:
		var b: Button = dialog.ritual_buttons[o.ritual]
		var want := SpellIcons.texture(String(o.ritual))
		assert_eq(b.icon, want, "%s's button: %s" % [o.ritual, "its icon" if want != null else "no icon"])
	_no_art()
	game.map.open_cast_dialog(army.id)
	for o in dialog.options:
		assert_true((dialog.ritual_buttons[o.ritual] as Button).icon == null, "no art: %s's button as it was" % o.ritual)
	_art_back()
	game.free()


func test_the_codex_shows_a_spells_icon_in_its_list_and_on_its_page() -> void:
	var codex: CodexPanel = load("res://ui/codex_panel.tscn").instantiate()
	for id in MagicData.SPELLS:
		var key := String(MagicData.SPELLS[id].codex)
		assert_true(codex.show_entry(key), "%s's entry" % id)
		assert_eq(codex.shown_icon(), SpellIcons.texture(String(id)), "%s's page shows its icon" % id)
		var idx := codex._shown_keys.find(key)
		assert_eq(codex._list.get_item_icon(idx), SpellIcons.texture(String(id)), "and its line in the list")
	assert_true(codex.show_entry("mandate_tithe_of_blood"))
	assert_eq(codex.shown_icon(), SpellIcons.texture(SpellIcons.BLOOD_MANDATE), "the blood mandate's page too")
	assert_true(codex.show_entry("fort"))
	assert_true(codex.shown_icon() == null, "an entry about something else has no icon")
	codex.free()
	_no_art()
	var bare: CodexPanel = load("res://ui/codex_panel.tscn").instantiate()
	assert_true(bare.show_entry(String(MagicData.SPELLS["sunlance"].codex)))
	assert_true(bare.shown_icon() == null, "no art: the page as it was")
	bare.free()
	_art_back()


func test_a_chronicle_card_about_a_spell_wears_its_icon() -> void:
	for id in MagicData.SPELLS:
		assert_eq(ChronicleModel.spell_of({"type": "ritual_cast", "numbers": {"ritual": id}}), String(id), "a ritual cast is about %s" % id)
		assert_eq(ChronicleModel.spell_of({"type": "research_done", "numbers": {"node": id}}), String(id), "learning %s is about it" % id)
	assert_eq(ChronicleModel.spell_of({"type": "research_done", "numbers": {"node": "crown_drillyard"}}), "", "research of a path node is not")
	assert_eq(ChronicleModel.spell_of({"type": "income", "numbers": {}}), "")
	var item := {"id": "t1.e0", "turn": 1, "kind": "magic", "image": "ritual_cast", "rank": 50, "headline": "Ritual cast", "detail": "A ritual.",
		"province": "", "place": "", "codex": "magic", "battle": {}, "source_rows": ["A ritual."], "important": false, "routine": false,
		"own": true, "type": "ritual_cast", "facts": {}, "variant": "", "spell": "sunlance"}
	var card := NoticeCard.new()
	card.setup(item, {})
	assert_eq(SpellIcons.shown_under(card), ["sunlance"] if _with_art().has("sunlance") else [], "the card wears Sunlance's icon")
	card.free()
	item.erase("spell")
	var plain := NoticeCard.new()
	plain.setup(item, {})
	assert_eq(SpellIcons.shown_under(plain), [], "a card about no spell has none")
	plain.free()


func test_the_blood_mandate_wears_its_icon_on_the_build_screen() -> void:
	var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
	b.begin({"players": [CLANS, CROWN], "seed": 9, "magic": true, "ai": {CROWN: "normal"}})
	if b.step == BuildScreen.Step.HANDOFF:
		b.acknowledge()
	assert_true(b.mandate_rows.has(SpellIcons.BLOOD_MANDATE), "the Clans' builder lists Tithe of Blood in a magic game")
	var row: Control = b.mandate_rows.get(SpellIcons.BLOOD_MANDATE, null)
	if row != null:
		assert_eq(SpellIcons.shown_under(row), [SpellIcons.BLOOD_MANDATE] if _with_art().has(SpellIcons.BLOOD_MANDATE) else [], "its row wears the icon")
	for mid in b.mandate_rows:
		if mid != SpellIcons.BLOOD_MANDATE:
			assert_eq(SpellIcons.shown_under(b.mandate_rows[mid]), [], "%s has no icon in the spell set" % mid)
	b.free()


# --- the portraits -------------------------------------------------------------------------------------

func test_the_new_units_portraits_show_wherever_a_units_portrait_does() -> void:
	var ids := []
	for fid in MagicData.MAGES:
		ids.append([String(MagicData.MAGES[fid].id), String(fid)])
	for sid in MagicData.SUMMONS:
		ids.append([String(sid), String(MagicData.SUMMONS[sid].faction)])
	assert_eq(ids.size(), MagicData.MAGES.size() + MagicData.SUMMONS.size())
	var s := _clans_state()
	for pair in ids:
		var id: String = pair[0]
		var fid: String = pair[1]
		assert_eq(Art.unit_faction(id), fid, "%s belongs to %s" % [id, fid])
		var has_file := ResourceLoader.exists(Art.PORTRAIT_PATH % [fid, id])
		assert_true(has_file, "%s's portrait is in the game (#225)" % id)
		assert_eq(Art.portrait(id, "") != null, has_file, "%s: found with no faction given (the battle cards, the turn report)" % id)
		assert_eq(Art.portrait(id, fid) != null, has_file, "and with its owner's (the cards, the recruit list)")
		assert_eq(Art.unit_portrait(s, fid, id) != null, has_file, "and as the unit wears it in a game")
		var card := Art.portrait_card(id, Vector2(48, 64), "")
		assert_true(card.has_art() == has_file, "%s's portrait card shows the art" % id)
		card.free()
