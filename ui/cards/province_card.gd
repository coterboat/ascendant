class_name ProvinceCard
extends CardBase
## UX-3 (design/UX_WAR_TABLE.md §3.2): the province card. Click land and you manage the land: its fort and its recruitment.
## Top to bottom:
##   - the header: the province's name on its terrain, with its owner's banner;
##   - the actions, on a province you can act in: Recruit (opens the Recruit section, RecruitSection: the capital's list, the
##     fort recruit section and the ruler's), Fortify (FortifyControls, today's fort panel flow) and the Fort panel (opens the
##     whole fort panel under the fort line: the siege, the garrison, Storm and Sally);
##   - the facts, each with its breakdown on hover and its codex link: owner, garrison, terrain, income, capital, the fort
##     (its level, walls, recruits a turn and how many are ordered), neighbours, vision under fog, and the enchantments on it;
##   - the armies here, each a button that selects it, with its portraits (UnitStrip).
## What each section shows is what the side panel showed: it was moved here, not rewritten, so every tooltip and codex link is
## the one it had. Sections the card builds closed are built all the same and hidden until their button opens them
## (SelectionCards.open_section), so a button's state survives the card being rebuilt by an order.

var province_id := ""
var actions: HFlowContainer = null
var recruit_button: Button = null
var fort_button: Button = null
var recruit_section: RecruitSection = null
var fort_panel: FortPanel = null
var fortify: FortifyControls = null
var armies_box: VBoxContainer = null

## UI-FIT (#237): the header strip's height and its banner's: a squeezed card at 125% keeps its facts down to the fort in view.
const HEADER_H := 64.0
const BANNER_H := 46.0


static func make(host: MapScreen, pid: String) -> ProvinceCard:
	var card := ProvinceCard.new()
	card.map = host
	card.province_id = pid
	card._build()
	return card


func _init() -> void:
	super()
	name = "ProvinceCard"


func _build() -> void:
	var p: Province = state.find_province(province_id) if state else null
	if p == null:
		add_heading("No province selected", 22)
		add_text("Click a province on the map to see its terrain, income, owner and armies.\nHover any number to see where it comes from.",
			"", UiPalette.TEXT_SECONDARY)
		return
	_add_header(p)
	add_status()
	_add_actions(p)
	_add_facts(p)
	_add_armies(p)


# --- the header and the actions --------------------------------------------------------------------

## The selected province's header: its name on a strip painted with its terrain tile, with its owner's
## banner at the right (no banner for a neutral province).
func _add_header(p: Province) -> void:
	var header := PanelContainer.new()
	header.name = "ProvinceHeader"
	var tex := Art.terrain(p.terrain)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.region_rect = Rect2(0, 0, 512, 160)
		sb.modulate_color = Color(0.72, 0.72, 0.72)
		sb.set_content_margin_all(8)
		sb.content_margin_left = 14
		header.add_theme_stylebox_override("panel", sb)
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = UiPalette.terrain_color(p.terrain).darkened(0.3)
		flat.set_content_margin_all(8)
		header.add_theme_stylebox_override("panel", flat)
	add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)
	var title := Label.new()
	title.name = "ProvinceName"
	title.text = p.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", UiFonts.name())
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	title.add_theme_constant_override("outline_size", 8)
	row.add_child(title)
	if not p.owner.is_empty():
		var banner := Art.banner_card(p.owner, BANNER_H)
		banner.name = "OwnerBanner"
		row.add_child(banner)
	header.custom_minimum_size = Vector2(0, HEADER_H)


## The actions on this province: Recruit, Fortify, the fort panel. Each only where the viewer can use it.
func _add_actions(p: Province) -> void:
	# Recruit is offered wherever the rules let this faction recruit (its capital, a fort of its own, and the province its ruler stands in
	# with Warband Muster, which the side panel offered too); Fortify and the fort panel decide for themselves.
	var can_act := orders != null and state.find_faction(viewing_faction_id) != null
	var cards := map.cards
	actions = HFlowContainer.new()
	actions.name = "ProvinceActions"
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	if can_act and RecruitSection.available(map, province_id):
		recruit_button = action_button("RecruitButton", "Recruit", "recruit",
			TooltipText.plain("Recruit", "Buy units here. They are paid, and join your armies, when the turn ends. Opens the recruit list for %s: every unit with its price, and the gold you have left after your orders. %s" % [
				p.name, RulesCodex.text("recruit")]), "recruit")
		recruit_button.toggle_mode = true
		recruit_button.button_pressed = cards.section_open("recruit")
		recruit_button.toggled.connect(func(on: bool): cards.open_section("recruit", on))
		actions.add_child(recruit_button)
	var panel := FortPanel.make(map, province_id, false, cards.section_open("fort"))
	if panel != null:
		fort_panel = panel
		fort_button = action_button("FortPanelButton", "Fort panel", "walls",
			TooltipText.plain("Fort panel", "The whole fort at %s: the siege, who is inside the walls and who is outside, the walls and when they fall, the garrison's odds, and the Storm, Sally and relief choices. %s" % [
				p.name, RulesCodex.text("fort_levels")]), "fort_levels")
		fort_button.toggle_mode = true
		fort_button.button_pressed = cards.section_open("fort")
		fort_button.toggled.connect(func(on: bool): cards.open_section("fort", on))
		actions.add_child(fort_button)
	if actions.get_child_count() > 0:
		add_child(actions)
		pinned_nodes.append(actions)
	else:
		actions.free()
		actions = null
	fortify = FortifyControls.make(map, province_id)
	if fortify != null:
		add_child(fortify)
		pinned_nodes.append(fortify)
	if can_act and RecruitSection.available(map, province_id):
		recruit_section = RecruitSection.make(map, province_id)
		recruit_section.visible = cards.section_open("recruit")
		add_child(recruit_section)


# --- the facts ---------------------------------------------------------------------------------------

func _add_facts(p: Province) -> void:
	var garrison := state.garrison_at(p.id)  # IND-1 (#142): the Free Holds garrison you must beat to take it
	var owner_name := "Nobody (neutral)" if p.owner.is_empty() else state.find_faction(p.owner).faction_name
	if garrison != null:
		owner_name = "Neutral, held by %s" % TurnReportText.army_name(state, garrison.id)
	var seats := map.seat_order()
	var owner_seat := UiPalette.seat_index(state, p.owner, seats)
	var owner_help := RulesCodex.text("neutral")
	if not p.owner.is_empty():
		var mark := "" if owner_seat < 0 else " It is Player %d, drawn in %s with a %s emblem." % [
			owner_seat + 1, UiPalette.seat_color_name(owner_seat), SeatEmblem.shape_of(owner_seat)]
		owner_help = "The faction that holds %s and earns its income.%s %s" % [p.name, mark, RulesCodex.text("capture")]
	var owner_label := add_text("Owner: %s" % owner_name, TooltipText.plain("Owner", owner_help))
	owner_label.name = "OwnerLabel"
	owner_label.add_theme_color_override("font_color", UiPalette.owner_color(state, p.owner, seats).lightened(0.3))
	link(owner_label, TooltipText.owner_kind(p.owner))
	if garrison != null:
		var n := garrison.units.size()
		var who := TurnReportText.army_name(state, garrison.id)
		var garrison_label := add_text("Garrison: %s, %d %s%s" % [who.trim_prefix("the "), n, "unit" if n == 1 else "units",
			" and a Hold Captain" if garrison.commander != null else ""], TooltipText.plain("Garrison of the %s" % IndependentData.FACTION_NAME,
			"To take %s you must beat %s: moving in starts a battle where it holds the ground. Select one of your armies next to it to see your odds. %s" % [
				p.name, who, RulesCodex.text("independents")]), UiPalette.TEXT_SECONDARY)
		garrison_label.name = "GarrisonLabel"
		link(garrison_label, "independents")
	# Terrain, capital and fort explain themselves with their codex entries' own words.
	var terrain_kind := TooltipText.terrain_kind(p.terrain)
	var terrain_label := add_text("Terrain: %s" % p.terrain.capitalize(), TooltipText.plain("Terrain: %s" % p.terrain.capitalize(),
		TooltipText.codex_text(terrain_kind)))
	terrain_label.name = "TerrainLabel"
	link(terrain_label, terrain_kind)
	var income := Breakdown.province_income(state, p.id)
	# The total its owner earns (Heavy Tithes and Royal Court included, M2); the tooltip breaks it down.
	var income_tip := TooltipText.from_breakdown(income)
	if FogView.active(state) and not p.owner.is_empty() and p.owner != viewing_faction_id and RulerRules.has_rulers(state):
		income_tip += "\n\n" + TooltipText.wrap_text("Under fog this counts only the mandates of theirs you know: they may earn more here.")
	var income_label := add_text("Income: %d gold per turn" % int(income.total), income_tip, UiPalette.GILT)
	income_label.name = "IncomeLabel"
	link(income_label, "province_income", income)
	var capital_text := "No"
	if p.is_capital:
		capital_text = "Yes"
		for f in state.factions:
			if f.capital == p.id:
				capital_text = "Yes, the capital of %s" % f.faction_name
	var capital_label := add_text("Capital: %s" % capital_text, TooltipText.plain("Capital", TooltipText.codex_text("capital")))
	capital_label.name = "CapitalLabel"
	link(capital_label, "capital")
	if state.sieges:
		_add_fort_block(p)  # M3c S-3: the level, the chip, then the fort section
	else:
		var fort_label := add_text("Fort: %s" % ("Yes" if p.has_fort else "No"), TooltipText.plain("Fort", TooltipText.codex_text("fort")))
		fort_label.name = "FortLabel"
		link(fort_label, "fort")
	var names := []
	for n in p.neighbors:
		var np := state.find_province(n)
		names.append(np.name if np else n)
	var neighbors_label := add_text("Neighbors: %s" % ", ".join(names), TooltipText.plain("Neighbors",
		"The provinces joined to %s by a road. %s" % [p.name, RulesCodex.text("move")]))
	neighbors_label.name = "NeighborsLabel"
	link(neighbors_label, "neighbors")
	if FogView.active(state):
		_add_vision_line(p)  # M5-2: in clear sight, glimpsed or out of sight, and why
	_add_enchantment_lines(p)  # M5-6: wards, curses and Far Sight on it
	_add_wake_lines(p)  # CW-3: the Wake on it


## M3c S-3: "Fort: Keep" (linked to the level's own entry), then the fort section (FortPanel) in a frame: its summary (the walls,
## the recruits a turn and how many are ordered, a construction, a siege that stands) always, the rest when the Fort panel is open.
## UI-FIT (#237): the board's fort chip is not repeated here: beside this line it said the level again, and its walls bar sat over
## the section's bigger one. The plates keep it.
func _add_fort_block(p: Province) -> void:
	var level_key: String = String(SiegeRules.level_data(p.fort_level).id) if p.fort_level > 0 else "fort_levels"
	var text := "Fort: %s" % (SiegeRules.level_name(p.fort_level) if p.fort_level > 0 else "none")
	var fort_label := add_text(text, TooltipText.plain(text, RulesCodex.text(level_key)), UiPalette.TEXT_PRIMARY)
	fort_label.name = "FortLabel"
	CodexLink.attach(fort_label, level_key, map.request_codex)
	if fort_panel == null:
		return
	var frame := PanelContainer.new()
	frame.name = "FortFrame"
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	frame.add_child(fort_panel)
	add_child(frame)


## M5-2: "Vision: Glimpsed", "Vision: Out of sight (last seen 2 turns ago)": the province's sight level for the
## viewer, with why it is seen or what is remembered of it on hover.
func _add_vision_line(p: Province) -> void:
	var level := FogView.vision_level(state, viewing_faction_id, p.id, map.fog_memory)
	var text := "Vision: %s" % String(FogView.LEVEL_TITLES.get(level, level))
	var seen_turn := int(map.fog_memory.get("provinces", {}).get(p.id, {}).get("seen_turn", -1))
	if level == FogRules.VEILED and seen_turn > 0:
		text += " (last seen %s)" % FogView._ago(state, seen_turn)
	var l := add_text(text, TooltipText.plain(String(FogView.LEVEL_TITLES.get(level, level)),
		"%s %s" % [FogView.province_text(state, viewing_faction_id, p.id, map.fog_memory), RulesCodex.text(String(FogView.LEVEL_CODEX.get(level, "sight")))]),
		UiPalette.TEXT_SECONDARY)
	l.name = "VisionLabel"
	CodexLink.attach(l, String(FogView.LEVEL_CODEX.get(level, "sight")), map.request_codex)


## M5-6: the enchantments on a province (§6.4, §11.2), each with who cast it, what it does and through which turn,
## from the state shown (under fog, the view: only the ones you can see).
func _add_enchantment_lines(p: Province) -> void:
	if not MagicRules.has_magic(state):
		return
	for e in state.enchantments:
		if String(e.province) != p.id or String(e.kind) == "blessing":
			continue
		var what := EnchantmentBadges.effect_text(state, e)  # M5-8: the badge's words
		var who := MagicRules._faction_display(state, String(e.faction))
		var line := add_text("%s (%s), through turn %d" % [MagicRules.spell_name(String(e.ritual)), who, int(e.until_turn)],
			TooltipText.plain(MagicRules.spell_name(String(e.ritual)), "%s %s" % [what, RulesCodex.text(String(e.kind))]),
			UiPalette.GILT)
		line.name = "Enchantment_%s" % String(e.ritual).validate_node_name()
		CodexLink.attach(line, MagicRules.spell_codex(String(e.ritual)), map.request_codex)


## CW-3 (#254, design/CANDLEWAKE.md §3.4): the marks on a province, in MarkRules' words: its stage and what it does, when the
## next one comes and when the dead rise, or a cold wake fading. Public, like owners and terrain; none on unmarked land.
func _add_wake_lines(p: Province) -> void:
	var lines := MarkRules.province_text(state, p.id)
	for i in lines.size():
		var line := add_text(String(lines[i]), TooltipText.plain("The Wake", RulesCodex.text(MarkRules.CODEX)), UiPalette.TEXT_SECONDARY)
		line.name = "Wake_%d" % i
		CodexLink.attach(line, MarkRules.CODEX, map.request_codex)


# --- the armies here ---------------------------------------------------------------------------------

## "Armies here", each a button that selects it (and the card of that army opens), with its portraits.
func _add_armies(p: Province) -> void:
	add_child(HSeparator.new())
	add_heading("Armies here", 20)
	armies_box = VBoxContainer.new()
	armies_box.name = "ArmiesHere"
	armies_box.add_theme_constant_override("separation", 6)
	add_child(armies_box)
	var any := false
	for a in state.armies:
		if a.location != p.id:
			continue
		any = true
		_add_army_row(a)
	if not any and FogView.active(state) and FogView.vision_level(state, viewing_faction_id, p.id, map.fog_memory) in [FogRules.VEILED, FogView.NEVER]:
		var unknown := add_text("None that you know of: you can't see %s now." % p.name, TooltipText.plain("Out of sight",
			FogView.province_text(state, viewing_faction_id, p.id, map.fog_memory)), UiPalette.TEXT_SECONDARY, armies_box)
		unknown.name = "NoArmiesKnown"
		link(unknown, "remembered")
	elif not any:
		var none := add_text("No armies here.", TooltipText.plain("No armies", RulesCodex.text("undefended")), UiPalette.TEXT_SECONDARY, armies_box)
		link(none, "no_armies")


func _add_army_row(a: Army) -> void:
	armies_box.add_child(ArmyRow.make(map, a))
