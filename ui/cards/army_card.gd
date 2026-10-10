class_name ArmyCard
extends CardBase
## UX-3 (design/UX_WAR_TABLE.md §3.1): the army card. Click an army and you manage troops: where they go, how they are split up,
## and which armies join (the last is ARM-1's, and has its place here but no behaviour yet). Top to bottom:
##   - the header: the army's name as the turn report calls it, where it is, and who is in it;
##   - the portraits (UnitStrip) with their hit-point bars, the commander and a ruler framed in gilt;
##   - strength (its breakdown on hover, as it was: a size guide, the move forecast has the real odds), the unit count, and under
##     fog how far it sees;
##   - the army's own orders, as the orders list words them, with their forecasts;
##   - the actions, the order types the army really owns, each calling today's flow through the map screen:
##       March          MoveOrder: the card collapses to a slim strip while you pick the destination (SelectionCards.begin_march)
##       Change route   a road MoveOrder only (change_via): sends it through its other legal province
##       Storm / Sally  at a fort it besieges or that besieges it: opens the fort panel (SiegeOrder: Storm now or wait, or Sally)
##       Cast a ritual  when a caster stands in it: the cast dialog
##       Cancel order   withdraws its order (cancel_order)
##   - the commander and the fighters by kind, each with its breakdown, the magic lines (blessing, summoned fading, casters and
##     their spells) and, for a ruler's army, the ruler's numbers and the Ruler panel button;
##   - your other armies in the same province (ArmyRow), each on its own row of portraits: where ARM-1 will put drag, Split,
##     Merge all and Swap commanders.
## A rival's army shows what FogView allows and no actions: under fog its sighting (the range of every kind, last turn's
## sighting, how to see it exactly), and without fog what the side panel always showed of it.

const STRENGTH_GUIDE := "For your real chances, select one of your armies next to this one and hover its province: the move forecast fights that battle with the full rules and shows the odds."

var army_id := ""
var panel: PanelContainer = null
var actions: HFlowContainer = null
var march_button: Button = null
var route_button: Button = null
var siege_button: Button = null
var cast_button: Button = null
var cancel_buttons: Array = []
var siege_panel: FortPanel = null
var others_box: VBoxContainer = null
var strip: UnitStrip = null
var muster_board: MusterBoard = null  # ARM-1: the card's Armies here (it is also others_box)


static func make(host: MapScreen, id: String) -> ArmyCard:
	var card := ArmyCard.new()
	card.map = host
	card.army_id = id
	card._build()
	return card


func _init() -> void:
	super()
	name = "ArmyCard"


## An army's header as [the one-line header: its report name and where it is ("The Crown's 1st at Crownkeep"), the line under
## it: who is in it ("Spearmen, Crossbowmen and Knight Captain"; a ruler's army: "Ruler of the Aurel Crown")], from
## TurnReportText.army_title's own words (#125).
static func header_parts(st: GameState, a: Army) -> Array:
	var name := TurnReportText.army_name(st, a.id, a.owner)
	var bare := TurnReportText.army_title(st, a, false)
	var placed := TurnReportText.army_title(st, a)
	var inside := bare.substr(name.length()).strip_edges().trim_prefix("(").trim_suffix(")")
	return [RulerRules._cap(name) + placed.substr(bare.length()), RulerRules._cap(inside)]


## The indexes (in orders.orders()) of the orders this army owns: its move, its cast and its sally. A storm is the fort's, not
## the army's, and shows in the fort panel.
func order_indexes(a: Army) -> Array:
	var out := []
	if orders == null:
		return out
	var list := orders.orders()
	for i in list.size():
		var o = list[i]
		if (o is MoveOrder or o is CastOrder) and o.army_id == a.id:
			out.append(i)
		elif o is SiegeOrder and o.is_sally() and o.army_id == a.id:
			out.append(i)
		elif o is MusterOrder and (o.from_army == a.id or o.to_army == a.id or orders.muster_forms(i) == a.id):
			out.append(i)  # ARM-1: the muster that formed, merged or changed this army
	return out


func _build() -> void:
	var a: Army = state.find_army(army_id) if state else null
	if a == null:
		add_text("This army is no longer on the map.", "", UiPalette.TEXT_SECONDARY)
		return
	add_status()
	if FogView.is_stand_in(a):
		_build_stand_in(a)
		return
	var mine := a.owner == viewing_faction_id and orders != null
	_build_panel(a, mine)
	if mine:
		_add_siege_section(a)
		if a.ruler != null:
			_add_other_armies(a, self)  # a ruler's card lists the others at its foot; an army's own has Armies here under its portraits


# --- your army or a rival's, seen exactly -------------------------------------------------------------

func _build_panel(a: Army, mine: bool) -> void:
	panel = PanelContainer.new()
	panel.name = "Army_%s" % a.id.validate_node_name()
	panel.add_theme_stylebox_override("panel", raised_style(UiPalette.owner_color(state, a.owner, map.seat_order()), 3))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var parts := header_parts(state, a)
	var title := add_text(String(parts[0]), "", UiPalette.TEXT_PRIMARY, box)  # the report's name and its place, on one line (#125)
	title.name = "ArmyTitle"
	title.add_theme_font_override("font", UiFonts.name())
	title.add_theme_font_size_override("font_size", UiPalette.TYPE_NAME)
	if a.ruler != null:
		# A ruler's army holds only its ruler (M2): show the ruler's numbers instead of units (RulerPanel).
		title.tooltip_text = RulerPanel.summary(state, a)
		CodexLink.attach(title, "ruler_army", map.request_codex)
	else:
		title.tooltip_text = TooltipText.from_breakdown(Breakdown.army_units(state, a.id))
		link(title, "army_units")
	# Who is in it goes on the line under the name (#125: a big army's header wrapped to three lines), on one line here: the
	# full list is its tooltip and the fighters are under it.
	var who := add_text(String(parts[1]), title.tooltip_text, UiPalette.TEXT_SECONDARY, box)
	who.name = "ArmyMembers"
	who.add_theme_font_size_override("font_size", 15)
	who.autowrap_mode = TextServer.AUTOWRAP_OFF
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if mine:
		_add_actions(a, box)  # pinned: SelectionCards lifts it out of the scroll
		_add_orders(a, box)

	# Hit points are shown for your own army, and for any army in a game without fog (the state is the truth there).
	strip = UnitStrip.make(state, a, Vector2(40, 40), map.request_codex, mine or not FogView.active(state))
	box.add_child(strip)

	if a.ruler == null:
		_add_stats(a, box)
		if mine:
			_add_other_armies(a, box)  # ARM-1: Armies here, right under the portraits, so a drag never has to scroll
	elif FogView.active(state):
		_add_sight_line(a, box)
	if a.ruler != null:
		RulerPanel.fill(box, state, a, map.request_codex, false)
		_add_magic_lines(a, box)  # M5-6
		var open := Button.new()
		open.name = "OpenRulerPanel"
		open.text = "Ruler panel: both rulers, mandates and sacrifice"
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		open.focus_mode = Control.FOCUS_NONE
		open.tooltip_text = TooltipText.plain("Ruler panel", "Every number of your ruler and the enemy's, explained, with the mandates each side has. Your living ruler can sacrifice power for a new mandate there.")
		CodexLink.attach(open, "ruler", map.request_codex)
		open.pressed.connect(map.open_ruler_panel)
		box.add_child(open)
		return
	_add_composition(a, box)
	_add_magic_lines(a, box)  # M5-6


## Units, strength and (under fog) sight: the numbers of the army, each explaining itself.
func _add_stats(a: Army, box: Control) -> void:
	var row := HFlowContainer.new()
	row.name = "ArmyStats"
	row.add_theme_constant_override("h_separation", 16)
	box.add_child(row)
	var unit_breakdown := Breakdown.army_units(state, a.id)
	var units := add_text("Units: %d" % a.units.size(), TooltipText.from_breakdown(unit_breakdown), UiPalette.TEXT_PRIMARY, row)
	units.name = "UnitsLabel"
	units.autowrap_mode = TextServer.AUTOWRAP_OFF
	link(units, "army_units", unit_breakdown)
	# A size guide only (RulesCodex "army_strength"): battles use the full rules, and the move forecast
	# has the real odds, so the label says "rough" and the tooltip points at the forecast.
	var sb := Breakdown.army_strength(state, a.id)
	sb.description = "%s %s" % [sb.get("description", ""), STRENGTH_GUIDE]
	var strength := add_text("Rough strength: %d" % int(sb.total), TooltipText.from_breakdown(sb), UiPalette.TEXT_SECONDARY, row)
	strength.name = "StrengthLabel"
	strength.autowrap_mode = TextServer.AUTOWRAP_OFF
	link(strength, "army_strength", sb)
	if FogView.active(state):
		_add_sight_line(a, box)  # M5-2: how far it sees


## The commander, then the fighters by kind, each with its portrait and count and the breakdown of the count.
func _add_composition(a: Army, box: Control) -> void:
	var commander_label: Label
	if a.commander:
		var row := unit_row(box, a.commander.type.id, a.owner, 1)
		commander_label = add_text("Commander: %s" % a.commander.type.name, TooltipText.plain("Commander: %s" % a.commander.type.name,
			Breakdown.unit_type_description(a.commander.type, RulerRules.price_text(state, a.owner, a.commander.type))), UiPalette.GILT, row)
		commander_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		commander_label = add_text("Commander: none", TooltipText.plain("No commander", "This army has no commander to lead it."),
			UiPalette.TEXT_SECONDARY, box)
	commander_label.name = "CommanderLabel"
	link(commander_label, "commander")
	var seen := []
	for u in a.units:
		if seen.has(u.type.name):
			continue
		seen.append(u.type.name)
		var b := Breakdown.unit_count(state, a.id, u.type.name)
		var row := unit_row(box, u.type.id, a.owner, int(b.total))
		var count_tip := TooltipText.from_breakdown(b)
		if FogView.active(state) and not FogView.scout_line(u.type).is_empty():
			count_tip += "\n\n" + TooltipText.wrap_text("%s %s" % [FogView.scout_line(u.type), RulesCodex.text("scouts")])
		if MagicRules.is_mage(u.type) and a.owner == viewing_faction_id and not FogView.is_stand_in(a):
			# M5-8: a mage's card lists the battle spellbook in order, one line a spell
			count_tip += "\n\n" + "\n".join(Array(MagicView.mage_card(state, a.owner).split("\n")).map(func(l): return TooltipText.wrap_text(String(l))))
		var count_label := add_text("%s ×%d" % [u.type.name, b.total], count_tip, UiPalette.TEXT_PRIMARY, row)
		count_label.name = "UnitCount"
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The count's tooltip has the unit's stats and trait; its entry is Units, which links on to each.
		link(count_label, "unit_count", b)


# --- the army's orders and actions --------------------------------------------------------------------

## The army's own orders: each as the orders list words it, with its forecast, and the Storm now row of a move into a fort.
func _add_orders(a: Army, box: Control) -> void:
	var list := order_indexes(a)
	if list.is_empty():
		return
	var ordered := VBoxContainer.new()
	ordered.name = "ArmyOrders"
	ordered.add_theme_constant_override("separation", 4)
	box.add_child(ordered)
	for i in list:
		var row := HBoxContainer.new()
		row.name = "ArmyOrder_%d" % i
		ordered.add_child(row)
		var line := add_order_line(row, i)
		line.add_theme_font_size_override("font_size", 16)
		add_storm_now_row(ordered, i, row)


## The order types the army owns, as buttons.
func _add_actions(a: Army, box: Control) -> void:
	actions = HFlowContainer.new()
	actions.name = "ArmyActions"
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	box.add_child(actions)
	pinned_nodes.append(actions)
	wants_forecast = true  # an army of yours: hovering a province shows what a march there would do
	var list := order_indexes(a)
	var cards := map.cards
	# March: MoveOrder through today's targeting; the card collapses to a strip while you pick the province.
	var holds := _march_refusal(a, list)
	march_button = action_button("MarchButton", "March", "march", "", "move")
	march_button.tooltip_text = TooltipText.plain("March", "Order this army to move. Press March, then click a province next to it (or, with King's Roads, two away); the card folds into a slim strip while you choose, and Esc cancels. Nothing moves until the turn ends. %s" % RulesCodex.text("move")) \
		if holds.is_empty() else TooltipText.plain("March", holds)
	CodexLink.attach(march_button, "move", map.request_codex)
	march_button.disabled = not holds.is_empty()
	march_button.pressed.connect(cards.begin_march)
	actions.add_child(march_button)
	# Change route: only for a road move with another way through (King's Roads).
	for i in list:
		var tip := via_tooltip(i)
		if tip.is_empty():
			continue
		route_button = action_button("ViaButton", "Change route", "", tip, "road_move")
		route_button.pressed.connect(map.change_via.bind(i))
		actions.add_child(route_button)
	# Storm or lift a siege: at a fort it besieges (Storm now or wait), or inside a fort that is besieged (Sally): the fort panel.
	var choice := FortPanel.siege_choice(map, a.location)
	if not choice.is_empty():
		siege_button = action_button("SiegeButton", "Storm the walls" if choice == "storm" else "Sally: lift the siege", "siege", "")
		siege_button.tooltip_text = TooltipText.plain(siege_button.text, ("Your armies at %s besiege its fort. Open the fort panel to storm it this turn or wait while the walls drop, with the odds of each. To lift a siege you are not part of, march away. %s" \
			if choice == "storm" else "Your fort at %s is besieged. Open the fort panel to sally out against the besiegers, which lifts the siege if the sally wins, or to stay inside. %s") % [
				state.find_province(a.location).name, RulesCodex.text("storm" if choice == "storm" else "sally")])
		CodexLink.attach(siege_button, "storm" if choice == "storm" else "sally", map.request_codex)
		siege_button.toggle_mode = true
		siege_button.button_pressed = cards.section_open("siege")
		siege_button.toggled.connect(func(on: bool): cards.open_section("siege", on))
		actions.add_child(siege_button)
	# Cast a ritual: when a caster stands in the army (today's cast dialog).
	cast_button = _cast_button(a)
	if cast_button != null:
		actions.add_child(cast_button)
	# Cancel its order.
	for i in list:
		var cancel := action_button("CancelButton", "Cancel order", "dismiss", "Cancel this order. Nothing happens until the turn ends, so you can change your mind.")
		if orders.orders()[i] is MusterOrder:  # ARM-1: say which: an army can have a muster and a move
			cancel.text = "Cancel muster"
			cancel.tooltip_text = TooltipText.plain("Cancel muster", "Cancel this split, merge or swap. Orders that rely on it, like a move for the army it formed, go with it, and the status line says which. Nothing happens until the turn ends.")
		cancel.pressed.connect(map.cancel_order.bind(i))
		cancel_buttons.append(cancel)
		actions.add_child(cancel)


## Why March is not offered, or "" when it is: an army that already has a move holds for it, one that casts holds still.
func _march_refusal(a: Army, list: Array) -> String:
	var name := RulerRules._cap(TurnReportText.army_name(state, a.id, a.owner))
	for i in list:
		var o = orders.orders()[i]
		if o is MoveOrder:
			return "%s already has a move order. Cancel it first, or change its route." % name
		if o is CastOrder:
			return "%s casts a ritual this turn, so it holds where it is. Cancel the ritual first." % name
		if o is SiegeOrder:
			return "%s sallies this turn. Cancel the sally first." % name
	return ""


## M5-6: "Cast a ritual…" for an army of yours that holds a caster and knows a ritual (the cast dialog); null otherwise.
func _cast_button(a: Army) -> Button:
	if not MagicRules.has_magic(state) or orders == null or a.owner != viewing_faction_id or FogView.is_stand_in(a):
		return null
	if MagicRules.casters(state, a).is_empty() or orders.cast_options(a.id).is_empty():
		return null  # its casters know no ritual yet (Far Sight is offered only under fog): the Magic tab says what to research
	var cast := action_button("CastRitual", "Cast a ritual…", "magic", TooltipText.plain("Cast a ritual", "%s%s. %s" % [
		RulerRules._cap(TurnReportText.army_name(state, a.id)), " casts rituals" if a.ruler != null else " holds %s" % MagicView.casters_phrase(state, a),
		RulesCodex.text("cast_order")]), "cast_order")
	cast.pressed.connect(map.open_cast_dialog.bind(a.id, ""))
	return cast


# --- the siege section --------------------------------------------------------------------------------

## The fort panel for the province the army stands in, shown when the siege action is open: Storm now or wait, or Sally.
func _add_siege_section(a: Army) -> void:
	if siege_button == null:
		return
	siege_panel = FortPanel.make(map, a.location, false, true)
	if siege_panel == null:
		return
	var frame := PanelContainer.new()
	frame.name = "SiegeFrame"
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	frame.add_child(siege_panel)
	frame.visible = map.cards.section_open("siege")
	add_child(frame)


# --- magic ---------------------------------------------------------------------------------------------

## M5-6 (design/M5_MAGIC_FOG.md §6.4, §11.2): an army's magic on its card: its blessing and when it ends, when its
## summoned creatures fade, and for an army of yours that holds a caster, each spell with its number. Only what the state shows:
## under fog a rival's blessing appears only where you can see it (the view's enchantments).
func _add_magic_lines(a: Army, box: Control) -> void:
	if not MagicRules.has_magic(state):
		return
	var blessing := MagicRules.blessing_of(state, a.id)
	if not blessing.is_empty():
		var heal := int(MagicRules.spell_numbers(String(blessing.ritual), int(blessing.bonus)).value)
		# ARM-1 (§2.1): the blessing covers fighters one by one; the ones that joined the army after it was cast are outside it
		var cov := MagicRules.blessing_coverage(state, a)
		var counts := ""
		var counts_tip := ""
		if int(cov.outside) > 0:
			counts = " (%s)" % MagicRules.coverage_words(cov)
			counts_tip = " It blesses %s. The others joined the army after it was cast, by a muster or as recruits, so it neither heals them nor counts them for morale; casting it again covers everyone in the army." % MagicRules.coverage_words(cov)
		var line := add_text("Blessed: %s, through turn %d%s" % [MagicRules.spell_name(String(blessing.ritual)), int(blessing.until_turn), counts],
			TooltipText.plain("Blessed", "This army heals %d hit points at the end of every turn through turn %d, one at a time to its most wounded fighter, wherever it goes, and a side at least half blessed fights with +1 morale.%s %s" % [
				heal, int(blessing.until_turn), counts_tip, RulesCodex.text("blessing")]), UiPalette.GILT, box)
		line.name = "BlessedLine"
		CodexLink.attach(line, "blessing", map.request_codex)
	var fading := {}
	for u in a.units:
		if u.until > 0:
			fading[u.type.name] = u.until
	for type_name in fading:
		var line := add_text("%s fade at the end of turn %d" % [type_name, int(fading[type_name])], TooltipText.plain("Summoned",
			RulesCodex.text("summoned")), UiPalette.TEXT_SECONDARY, box)
		line.name = "FadesLine"
		CodexLink.attach(line, "summoned", map.request_codex)
	if orders != null and a.owner == viewing_faction_id and not FogView.is_stand_in(a):
		_add_caster_lines(a, box)  # M5-8: "Casters: 2 Sunstone Adepts", then each spell with its number


## M5-8 (§11.2: "Casters: 2 Sunstone Adepts. Sunlance 4 damage, Shield of Law 6 units (mastery +0)."): the casters of one of
## your armies that cast in battle and each spell they cast in your spellbook's order, with its number now and its breakdown
## (mastery included). A spell the spellbook switches off says so. Nothing for an army with no such caster.
func _add_caster_lines(a: Army, box: Control) -> void:
	var line := MagicView.army_line(state, a)
	if line.is_empty():
		return
	var casters := MagicRules.casters(state, a).filter(func(c): return c.battle == true)
	var units_bd := Breakdown.army_units(state, a.id)
	var head := add_text(String(line.header), "%s\n\n%s" % [TooltipText.from_breakdown(units_bd), TooltipText.wrap_text("%s %s" % [
		RulesCodex.text("caster"), RulesCodex.text("mage")])], UiPalette.GILT, box)
	head.name = "CastersLine"
	head.add_theme_font_size_override("font_size", 16)
	head.set_meta("breakdown", units_bd)
	CodexLink.attach(head, "caster", map.request_codex)
	for s in line.spells:
		var l := add_text(String(s.text), TooltipText.from_breakdown(s.breakdown), UiPalette.TEXT_PRIMARY if s.on else UiPalette.TEXT_DISABLED, box)
		l.name = "Spell_%s" % String(s.spell)
		l.add_theme_font_size_override("font_size", 15)
		l.set_meta("breakdown", s.breakdown)
		CodexLink.attach(l, String(s.codex), map.request_codex)
	if line.spells.is_empty():
		var none := add_text("No spell known yet: research one in the Magic tab.", TooltipText.plain("No spell yet", RulesCodex.text("arcana")),
			UiPalette.TEXT_SECONDARY, box)
		none.name = "CastersNone"
		none.add_theme_font_size_override("font_size", 15)
		CodexLink.attach(none, "arcana", map.request_codex)
	elif casters.size() > 0:
		var mastery_bd := Breakdown.mastery(state, a.owner, String(MagicRules.spell_data(String(line.spells[0].spell)).school), String(casters[0].kind))
		var mastery := add_text(String(line.mastery_text), TooltipText.from_breakdown(mastery_bd), UiPalette.TEXT_SECONDARY, box)
		mastery.name = "MasteryLine"
		mastery.set_meta("breakdown", mastery_bd)
		mastery.add_theme_font_size_override("font_size", 14)
		CodexLink.attach(mastery, "mastery", map.request_codex)


## M5-2: one of your armies' sight line: "This army sees 2 provinces around it (it has Knights)."
func _add_sight_line(a: Army, box: Control) -> void:
	var line := FogView.army_sight_line(a)
	var l := add_text(line, TooltipText.plain("Sight", "%s %s" % [line, RulesCodex.text("sight")]), UiPalette.TEXT_SECONDARY, box)
	l.name = "ArmySight"
	l.add_theme_font_size_override("font_size", 15)
	link(l, "army_sight")


# --- your armies here (ARM-1) --------------------------------------------------------------------------

## Your armies in this province (design/ARM1_SPLIT_MERGE.md §8, UX_WAR_TABLE §3.5): the MusterBoard, where portraits are dragged between
## them or to a new army and Split, Merge all and Swap commanders reshape them, with the forecast before anything is ordered. It is
## shown for an army that has another of yours beside it, or more than one fighter to split. A ruler's army only lists the others,
## each a row that selects its army: a ruler travels alone.
func _add_other_armies(a: Army, parent: Control) -> void:
	var others := state.armies.filter(func(o): return o.location == a.location and o.id != a.id and o.owner == viewing_faction_id \
		and not FogView.is_stand_in(o))
	if a.ruler == null and (not others.is_empty() or a.units.size() + (1 if a.commander != null else 0) >= 2):
		muster_board = MusterBoard.make(map, a)
		parent.add_child(muster_board)
		others_box = muster_board
		if strip != null:
			muster_board.adopt_strip(strip)  # this army's own portraits are ticked and dragged from the top of the card
		return
	if others.is_empty():
		return
	add_heading("Your other armies here", 18, parent)
	others_box = VBoxContainer.new()
	others_box.name = "ArmiesHere"
	others_box.add_theme_constant_override("separation", 6)
	parent.add_child(others_box)
	var note := add_text("A ruler travels alone: its army can't be split, merged or swapped.", TooltipText.plain("Rulers travel alone", RulesCodex.text("ruler_army")),
		UiPalette.TEXT_SECONDARY, others_box)
	note.name = "RulerAlone"
	for o in others:
		others_box.add_child(ArmyRow.make(map, o, true))


# --- a rival's army, as FogView shows it ----------------------------------------------------------------

## M5-2: a rival army as the viewer sees it (§11.1): its sighting with the range of every type, its commander, last
## turn's sighting at that place, and how to see it exactly. A remembered army is greyed. Every number explains itself.
func _build_stand_in(a: Army) -> void:
	var level := String(a.seen.get("level", ""))
	panel = PanelContainer.new()
	panel.name = "Army_%s" % a.id.validate_node_name()
	var style := raised_style(UiPalette.owner_color(state, a.owner, map.seat_order()), 3)
	if level == FogData.MEMORY:
		style.bg_color = UiPalette.PANEL_BG
		panel.modulate = Color(1, 1, 1, 0.72)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var b := FogView.army_breakdown(state, viewing_faction_id, a, map.fog_before)
	var tip := TooltipText.from_breakdown(b)
	var kind := "remembered" if level == FogData.MEMORY else ("glimpse" if level == FogRules.GLIMPSE else "vision")
	var title := add_text(FogView.army_heading(state, a), tip, UiPalette.TEXT_PRIMARY, box)
	title.name = "ArmyTitle"
	title.add_theme_font_override("font", UiFonts.name())
	title.add_theme_font_size_override("font_size", UiPalette.TYPE_NAME)
	link(title, kind)
	if a.ruler != null:
		var note := add_text("A ruler is hard to hide: you see its name and numbers, but not its wounds or exactly where it goes next. Its kept power is what you know, or the most it could be.",
			TooltipText.plain("A rival ruler", RulesCodex.text("intel")), UiPalette.TEXT_SECONDARY, box)
		note.name = "RulerFogNote"
		link(note, "rival_known")
		RulerPanel.fill(box, state, a, map.request_codex)
		return
	var total: Dictionary = a.seen.get("total", {})
	var count_text := FogView.range_text(total)
	if level == FogData.MEMORY:
		count_text += ", %s" % FogView._ago(state, int(a.seen.get("turn", 0)))
	var count := add_text("Fighters: %s" % count_text, tip, UiPalette.TEXT_PRIMARY, box)
	count.name = "FightersLabel"
	link(count, kind, b)
	for line in b.lines:
		var type_id := String(line.get("type", ""))
		var row: Control = unit_row(box, type_id, a.owner, int(line.value)) if not type_id.is_empty() else box
		var ut: UnitType = null
		for u in a.units:
			if u.type.id == type_id:
				ut = u.type
		var unit_tip := tip
		if ut != null:
			unit_tip = "%s\n\n%s" % [tip, TooltipText.wrap_text("%s %s" % [Breakdown.unit_type_description(ut), FogView.scout_line(ut)])]
		var l := add_text(String(line.label), unit_tip, UiPalette.TEXT_PRIMARY, row)
		l.name = "UnitCount"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		link(l, "unit_count")
	if a.commander != null:
		var crow := unit_row(box, a.commander.type.id, a.owner, 1)
		var c := add_text("Led by a %s" % a.commander.type.name, TooltipText.plain("Commander: %s" % a.commander.type.name,
			Breakdown.unit_type_description(a.commander.type)), UiPalette.GILT, crow)
		c.name = "CommanderLabel"
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		link(c, "commander")
	var last := add_text("Last turn: %s" % FogView.last_turn_text(state, a, map.fog_before), TooltipText.plain("Last turn",
		"What you saw at %s at the start of the last turn, for comparison: a band crossing (about 15 to about 20) can be a few fighters, not five. %s" % [
			TurnResolver._province_name(state, a.location), RulesCodex.text("estimates")]), UiPalette.TEXT_SECONDARY, box)
	last.name = "LastTurnLabel"
	link(last, "glimpse")
	if level != FogRules.CLEAR:
		var how := add_text("Fight them, or cast Far Sight once you have a mage, to see them exactly." if state.magic else "Fight them to see them exactly.",
			TooltipText.plain("Seeing them exactly", RulesCodex.text("sight")), UiPalette.TEXT_SECONDARY, box)
		how.name = "SeeExactly"
		link(how, "vision")
