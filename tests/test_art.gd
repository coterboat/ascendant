extends "res://tests/test_case.gd"
## Art on screen (#10): the single asset lookup (ui/art.gd) finds a portrait for every unit type and
## commander, a banner for every faction and a tile for every terrain in the data; anything missing
## (ruler portraits until they land, unknown ids) falls back to a placeholder without an error (the
## runner fails a test on any engine error). The screens use it: every province region is painted with
## its terrain, the recruit buttons and the army list show portraits, the battle report shows each
## side's banner and roster portraits, the victory screen flies the winner's banner, and the build
## screen and the ruler panel show ruler cards. Expected ids and counts come from the data.

const MAP_SCENE := "res://ui/map_screen.tscn"
const GAME_SCENE := "res://ui/game_screen.tscn"


# --- the lookup -----------------------------------------------------------------------------------

## Every unit type id in the faction data, commanders included: [[faction id, unit type id], ...].
func _unit_ids() -> Array:
	var out := []
	for f in FactionData.FACTIONS:
		for u in f.unit_types:
			out.append([String(f.id), String(u.id)])
		out.append([String(f.id), String(f.commander.id)])
	return out


func test_every_unit_type_has_a_portrait() -> void:
	var ids := _unit_ids()
	assert_eq(ids.size(), 8, "the M1 data has eight unit types with commanders")
	for pair in ids:
		var tex := Art.portrait(pair[1])
		assert_true(tex != null, "%s has a portrait" % pair[1])
		if tex == null:
			continue
		assert_eq(tex.get_size(), Vector2(384, 512), "%s ships at 384x512" % pair[1])
		assert_eq(Art.unit_faction(pair[1]), pair[0], "%s belongs to %s" % [pair[1], pair[0]])
		assert_true(Art.portrait(pair[1], pair[0]) == tex, "the faction-qualified lookup finds the same texture")
		assert_true(Art.portrait(pair[1]) == tex, "and it is cached: loaded once")


## M4's portraits (asc-3d-paths, M4_ASCENSION §12.1): every transformation's new unit is found by its unit
## id alone (Art knows which side of the fork adds it), and every unit a transformation changes has that
## look at assets/portraits/<faction>/<unit>__<transformation id>.webp; other pairs have none, quietly.
func test_every_transformation_has_its_new_unit_and_changed_unit_portraits() -> void:
	var count := 0
	for side in PathData.BRANCHES:
		var b: Dictionary = PathData.BRANCHES[side]
		var fid := String(b.faction)
		var trans := String(b.transformation)
		var fx := AscensionRules.node_effects(trans)
		var new_unit := String(fx.new_unit)
		assert_eq(Art.unit_faction(new_unit), fid, "%s belongs to %s" % [new_unit, fid])
		var tex := Art.portrait(new_unit)
		assert_true(tex != null, "%s has its portrait" % new_unit)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(384, 512), "%s's portrait is 384x512" % new_unit)
			assert_eq(tex.resource_path, Art.PORTRAIT_PATH % [fid, new_unit], "%s's portrait path" % new_unit)
		for type_id in fx.rename:
			count += 1
			var vt := Art.variant_portrait(String(type_id), fid, trans)
			assert_true(vt != null, "%s has its %s portrait" % [type_id, trans])
			if vt != null:
				assert_eq(vt.get_size(), Vector2(384, 512), "%s's %s portrait is 384x512" % [type_id, trans])
				assert_true(vt != Art.portrait(String(type_id)), "it isn't the base portrait")
			var card := PathPortrait.make(String(type_id), fid, String(b.colour), Vector2(96, 128))
			assert_true(card.shows_variant and card.has_art(), "the fork's card shows the %s look" % trans)
			card.free()
		var nc := PathPortrait.make(new_unit, fid, String(b.colour), Vector2(96, 128))
		assert_true(nc.has_art() and not nc.shows_variant, "the new unit's card shows its portrait")
		nc.free()
		assert_eq(Art.variant_portrait(new_unit, fid, trans), null, "a new unit has no changed look")
	assert_true(count > 0, "the transformations change units")
	assert_eq(Art.variant_portrait("crossbowmen", "kingdom", "crown_celestial_host"), null, "a unit the transformation doesn't change has none")
	assert_eq(Art.variant_portrait("spearmen", "kingdom", ""), null, "no transformation, no look")


func test_every_faction_has_a_banner_and_every_terrain_a_tile() -> void:
	for f in FactionData.FACTIONS:
		var b := Art.banner(f.id)
		assert_true(b != null, "%s has a banner" % f.id)
		if b != null:
			assert_eq(b.get_size(), Vector2(256, 384), "%s banner ships at 256x384" % f.id)
	var terrains := {}
	for p in MapData.PROVINCES:
		terrains[String(p.terrain)] = true
	for t in UiPalette.TERRAIN:
		terrains[String(t)] = true
	assert_true(terrains.size() >= 3, "plains, forest and hills at least")
	for t in terrains:
		var tex := Art.terrain(t)
		assert_true(tex != null, "%s has a terrain tile" % t)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(512, 512), "%s tile is 512x512" % t)


func test_missing_art_falls_back_quietly() -> void:
	assert_true(Art.portrait("no_such_unit") == null, "an unknown unit has no portrait")
	assert_true(Art.portrait("no_such_unit", "kingdom") == null, "nor with a faction")
	assert_true(Art.banner("no_such_faction") == null)
	assert_true(Art.terrain("swamp") == null, "a terrain without art yet")
	assert_true(Art.portrait("") == null and Art.banner("") == null and Art.terrain("") == null and Art.ruler_portrait("") == null)
	assert_true(Art.face(null) == null)
	# Placeholder cards for missing art: a unit card, a ruler card and a banner, all without art.
	var card := Art.portrait_card("no_such_unit", Vector2(96, 128))
	assert_false(card.has_art(), "an unknown unit gets the placeholder card")
	assert_eq(card.custom_minimum_size, Vector2(96, 128))
	card.free()
	var banner := Art.banner_card("no_such_faction", 48.0)
	assert_false(banner.has_art(), "an unknown faction gets the placeholder pennant")
	assert_eq(banner.custom_minimum_size, Vector2(32, 48), "banners keep their 2:3 shape")
	banner.free()
	var ruler := Art.ruler_card("no_such_ruler", "the Nameless", Vector2(72, 96))
	assert_false(ruler.has_art())
	assert_eq(ruler.initial, "N", "the placeholder shows the ruler's initial")
	ruler.free()


func test_ruler_cards_use_the_ruler_path_and_fall_back_to_the_placeholder() -> void:
	# Ruler portraits land in their own PR at assets/portraits/rulers/<ruler id>.webp: the card shows the
	# art when the file is there and the placeholder until then, either way without an error.
	for r in RulerData.RULERS:
		var rid := String(r.id)
		var path := Art.RULER_PORTRAIT_PATH % rid
		assert_eq(path, "res://assets/portraits/rulers/%s.webp" % rid)
		var card := Art.ruler_card(rid, RulerRules.ruler_name(rid, 1), Vector2(72, 96))
		assert_eq(card.has_art(), ResourceLoader.exists(path), "%s: art exactly when the file exists" % rid)
		assert_false(card.initial.is_empty(), "%s: the placeholder has an initial" % rid)
		card.free()


func test_face_crop_is_square_and_inside_the_portrait() -> void:
	var tex := Art.portrait("spearmen")
	var face := Art.face(tex) as AtlasTexture
	assert_true(face != null, "a face crop")
	if face == null:
		return
	assert_true(absf(face.region.size.x - face.region.size.y) < 1.0, "square: %s" % face.region)
	assert_true(Rect2(Vector2.ZERO, tex.get_size()).encloses(face.region), "inside the portrait")
	assert_true(Art.face(tex) == face, "cached per texture")


# --- the map --------------------------------------------------------------------------------------

func _map(state: GameState = null, fid: String = "kingdom") -> MapScreen:
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	screen.set_state(state if state else GameState.new(), fid)
	return screen


func test_every_province_region_is_painted_with_its_terrain() -> void:
	var screen := _map()
	assert_eq(screen.regions.size(), screen.state.provinces.size())
	for p in screen.state.provinces:
		var region: ProvinceRegion = screen.regions[p.id]
		assert_true(region.has_terrain_texture(), "%s is painted with its %s tile" % [p.name, p.terrain])
		assert_true(region._terrain_texture == Art.terrain(p.terrain), "%s uses the %s tile" % [p.name, p.terrain])
		assert_eq(region.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED, "%s tiles its texture" % p.name)
		# The name keeps a backing plaque so it reads on any tile.
		assert_true(region.name_label.get_theme_stylebox("normal") is StyleBoxFlat, "%s's name sits on a plaque" % p.name)
	# Neighbouring provinces line up: the UVs are the design-space position over the tile size.
	var r: ProvinceRegion = screen.regions["crownkeep"]
	assert_eq(r._uvs[0], (r.position + r._polygon[0]) / ProvinceRegion.TERRAIN_TILE)
	screen.free()


func test_top_bar_flies_the_viewing_factions_banner() -> void:
	var screen := _map()
	assert_true(screen.faction_crest.visible, "the crest shows for a player's view")
	assert_true(screen.faction_banner.texture == Art.banner("kingdom"), "the Aurel Crown's banner")
	assert_true(screen.faction_emblem.get_parent() == screen.faction_crest, "the seat emblem is pinned on the banner")
	assert_eq(screen.faction_crest.get_index(), 0, "first in the name group")
	assert_eq(screen.faction_label.get_index(), screen.faction_label.get_parent().get_child_count() - 1, "the name stays last in its group")
	screen.set_state(screen.state, "beasts")
	assert_true(screen.faction_banner.texture == Art.banner("beasts"), "follows the viewing faction")
	screen.free()


func test_recruit_buttons_show_portraits() -> void:
	var screen := _map()
	screen.select_province("crownkeep")
	var buttons := screen.details.find_children("Recruit_*", "Button", true, false)
	var f := screen.state.find_faction("kingdom")
	assert_eq(buttons.size(), screen.orders.recruitable_types().size(), "one button per recruitable type")
	for ut in screen.orders.recruitable_types():
		var b := screen.details.find_child("Recruit_%s" % ut.id, true, false) as Button
		assert_true(b != null, "a button for %s" % ut.id)
		if b == null:
			continue
		assert_true(b.icon != null, "%s's button shows its portrait" % ut.name)
		assert_true((b.icon as AtlasTexture).atlas == Art.portrait(ut.id, f.id), "the %s portrait" % ut.name)
		assert_eq(b.text, "Recruit %s (%d gold)" % [ut.name, screen.orders.recruit_cost(ut.id)], "name and cost stay in the text")
	screen.free()


func test_army_list_shows_portraits_with_counts() -> void:
	var screen := _map()
	var army: Army = screen.state.armies[0]
	screen.select_army(army.id)
	var counts := {}
	for u in army.units:
		counts[u.type.id] = int(counts.get(u.type.id, 0)) + 1
	for type_id in counts:
		var row := screen.details.find_child("UnitRow_%s" % type_id, true, false)
		assert_true(row != null, "a row for %s" % type_id)
		if row == null:
			continue
		var card := row.get_child(0) as Art.PortraitCard
		assert_true(card != null and card.has_art(), "%s's row shows its portrait" % type_id)
		assert_eq(card.count, counts[type_id], "%s's badge counts %d" % [type_id, counts[type_id]])
		var label := row.find_child("UnitCount", true, false) as Label
		assert_true(label != null and label.text.ends_with("×%d" % counts[type_id]), "the label names the count too")
	if army.commander:
		var crow := screen.details.find_child("UnitRow_%s" % army.commander.type.id, true, false)
		assert_true(crow != null, "the commander has a portrait row")
		if crow:
			assert_eq((crow.get_child(0) as Art.PortraitCard).frame, UiPalette.GILT, "commanders are framed in gilt")
	screen.free()


func test_province_header_is_painted_and_flies_the_owners_banner() -> void:
	var screen := _map()
	screen.select_province("crownkeep")
	var header := screen.details.find_child("ProvinceHeader", true, false) as PanelContainer
	assert_true(header != null and header.get_theme_stylebox("panel") is StyleBoxTexture, "painted with its terrain")
	var banner := screen.details.find_child("OwnerBanner", true, false) as Art.BannerCard
	assert_true(banner != null and banner.texture == Art.banner("kingdom"), "the owner's banner")
	screen.select_province("thornvale")
	assert_true(screen.details.find_child("OwnerBanner", true, false) == null, "no banner on a neutral province")
	screen.free()


func test_ruler_army_shows_a_ruler_card() -> void:
	var errors := []
	var s := GameState.with_rulers(7, {"kingdom": "warrior_king", "beasts": "clan_moot"}, errors)
	assert_eq(errors, [])
	var screen := _map(s, "kingdom")
	var ruler_army := RulerRules.ruler_army(s, "kingdom")
	screen.select_army(ruler_army.id)
	var row := screen.details.find_child("RulerRow", true, false)
	assert_true(row != null and row.get_child(0) is Art.PortraitCard, "the ruler's card beside its name")
	screen.open_ruler_panel()
	for fid in ["kingdom", "beasts"]:
		var col := screen.ruler_panel.columns.find_child("Column_%s" % fid, false, false)
		var card := col.find_child("RulerPortrait", true, false) as Art.PortraitCard
		assert_true(card != null, "%s's column shows a ruler card" % fid)
		var banner := col.find_child("FactionBanner", true, false) as Art.BannerCard
		assert_true(banner != null and banner.texture == Art.banner(fid), "%s's column flies its banner" % fid)
	screen.free()


# --- the reports and the other screens ------------------------------------------------------------

func test_battle_report_shows_banners_and_roster_portraits() -> void:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in [["kingdom-1", "kingdom", "stonegate", ["spearmen", "spearmen", "crossbowmen", "knight_captain"]],
			["beasts-2", "beasts", "blackwood", ["tuskers", "fangthrowers", "warchief"]]]:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		s.armies.append(a)
	var result := TurnResolver.resolve(s, {"beasts": [MoveOrder.new("beasts-2", "stonegate")], "kingdom": []}, 3, AutoBattleResolver.new())
	var battles: Array = result.events.filter(func(e): return GameSession.BATTLE_TYPES.has(e.type))
	assert_eq(battles.size(), 1)
	var v := BattleReportViewer.new()
	assert_true(v.show_event(battles[0], s))
	var cards: Array = v.section("sides").find_child("SideCards", true, false).get_children()
	var report: Dictionary = battles[0].numbers.report
	assert_eq(cards.size(), report.sides.size(), "one card per side")
	for i in cards.size():
		var sr: Dictionary = report.sides[i]
		var banner := cards[i].find_child("SideBanner", true, false) as Art.BannerCard
		assert_true(banner != null and banner.texture == Art.banner(sr.faction), "%s flies its banner" % sr.name)
		var strip: Node = cards[i].find_child("RosterPortraits", true, false)
		var expected: int = sr.roster.units.size() + sr.roster.commanders.size() + (0 if sr.roster.get("ruler", {}).is_empty() else 1)
		assert_eq(strip.get_child_count(), expected, "%s: one portrait per kind of fighter" % sr.name)
		for j in sr.roster.units.size():
			var card := strip.get_child(j) as Art.PortraitCard
			assert_true(card.has_art(), "%s has its portrait" % sr.roster.units[j].name)
			assert_eq(card.count, int(sr.roster.units[j].count), "with its count")
			assert_false(card.tooltip_text.is_empty(), "hovering names it")
	v.free()


func test_victory_screen_flies_the_winners_banner() -> void:
	var s := GameState.new(5)
	var summary := VictoryCheck.summary(s, ["kingdom", "beasts"],
		{"winner": "beasts", "fallen": [{"captor": "beasts", "capital": "crownkeep", "faction": "kingdom"}]}, 8, 8, 3)
	var v := VictoryScreen.new()
	v.show_victory(summary, s, ["kingdom", "beasts"])
	assert_eq(v.banner_box.get_child_count(), 1, "one banner for the winner")
	assert_true((v.banner_box.get_child(0) as Art.BannerCard).texture == Art.banner("beasts"), "the Thornmane Clans' banner")
	assert_true(v.banner_box.get_child(0).custom_minimum_size.y >= 192.0, "large: at least the bible's 192 px")
	assert_eq(v.provinces_box.find_children("RowBanner", "", true, false).size(), 2, "each faction's row flies its banner")
	var draw := VictoryCheck.summary(s, ["kingdom", "beasts"], {"draw": true, "fallen": [
		{"captor": "beasts", "capital": "crownkeep", "faction": "kingdom"}, {"captor": "kingdom", "capital": "fangridge", "faction": "beasts"}]}, 8, 8, 3)
	v.show_victory(draw, s, ["kingdom", "beasts"])
	assert_eq(v.banner_box.get_child_count(), 2, "both banners on a draw")
	v.free()


func test_build_screen_shows_the_banner_and_ruler_cards() -> void:
	var b := BuildScreen.new()
	b.begin({"players": ["kingdom", "beasts"], "seed": 7, "ai": {"beasts": "normal"}})
	var banner := b.body.find_child("HeaderBanner", true, false) as Art.BannerCard
	assert_true(banner != null and banner.texture == Art.banner("kingdom"), "the header flies the builder's banner")
	for rid in RulerRules.rulers_for("kingdom"):
		var card := (b.ruler_cards[rid] as Control).find_child("Portrait", true, false) as Art.PortraitCard
		assert_true(card != null, "%s's card shows a ruler portrait card" % rid)
		if card:
			assert_eq(card.has_art(), Art.ruler_portrait(rid) != null, "art when it exists, the placeholder until then")
	for pair in _unit_ids():
		if pair[0] == "kingdom":
			assert_true(b.body.find_child("UnitCell_%s" % pair[1], true, false) != null, "%s's roster row has its face" % pair[1])
	b.free()


func test_turn_report_recruit_rows_name_the_unit() -> void:
	for pair in _unit_ids():
		var unit_name := Art._unit_name(pair[1])
		var e := {"type": "recruited", "factions": [pair[0]], "text": "Some Faction recruited %s at Somewhere for 8 gold (1 gold left)." % unit_name}
		assert_eq(TurnReportPanel.recruited_unit(e), pair[1], "a recruit of %s" % unit_name)
	assert_eq(TurnReportPanel.recruited_unit({"type": "moved", "text": "recruited Spearmen "}), "", "only recruit events")
