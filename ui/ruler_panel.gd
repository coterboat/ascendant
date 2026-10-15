class_name RulerPanel
extends Control
## The ruler panel (M2-6, #34; design/M2_RULER.md §1.5, §2.4, §5.4, §7.1): your ruler with a breakdown
## behind every number (hit points, attack, defense, morale, kept power, ability rank and effect), its
## succession rule, a countdown while a successor is pending ("heir in 2 turns"), and your mandates with
## what each does for you now. Beside it the enemy ruler, read-only: builds are public from turn 1. From
## here a living ruler can sacrifice power for a new mandate: the button opens the sacrifice dialog
## (sacrifice_requested; MapScreen hosts both). Every number links its codex entry (right-click or F1).
## Opened from the top bar's Ruler button (GameScreen) or the ruler's army in the side panel
## (MapScreen.open_ruler_panel). Reads the state and the orders; never changes them.
##
## The static helpers further down are the ruler's army on the map (M2, #29): its badge text, its summary
## tooltip, and the lines the map's side panel shows for it, with a breakdown behind every number and a
## codex link on each. UI only: every number and sentence comes from RulerRules, Breakdown and Forecast,
## so nothing here can disagree with the rules.
## Art (#10): each column flies its faction's banner by the heading and shows the ruler's portrait card
## (Art.ruler_card: a styled placeholder with the ruler's initial until the ruler portraits land) to the
## left of its numbers.
## M5-2 fog of war (#113, design/M5_MAGIC_FOG.md §2.6, §11.1): in a fog game `state` is the viewer's view, and the enemy
## column says what you know of them (FogView.rival_summary, with `fog_intel`, the viewer's intel): their ruler "alive,
## location unknown" (or glimpsed, or last seen), its kept power as seen or the most it could be, the mandates you know,
## and that they may have more.

signal closed
signal sacrifice_requested
signal codex_requested(key: String)

const PANEL_SIZE := Vector2(1320, 800)
const FOOTER := "Builds are public from turn 1, so both rulers are shown. Only you can sacrifice for your own ruler, and the other player learns of it from the turn report. Hover a number for where it comes from; right-click it, or press F1, for its codex entry."
## M5-2: under fog a rival's build is learned, not public (design/M5_MAGIC_FOG.md §2.6).
const FOG_FOOTER := "Fog of war is on: you see a rival's ruler, mandates and kept power only as you have seen or fought them, and they may have more. Only you can sacrifice for your own ruler. Hover a number for where it comes from; right-click it, or press F1, for its codex entry."
const PORTRAIT_SIZE := Vector2(120, 160)

var state: GameState = null
var viewing_faction_id := ""
var orders: OrdersController = null  # the viewing faction's orders (a queued sacrifice shows here)
var columns: HBoxContainer  # one column per faction: yours first, then the others, read-only
var close_button: Button
var sacrifice_button: Button = null  # in your column, while you can give orders
var footer_label: Label
## M5-2: the viewer's intel (GameSession.intel) in a fog game: when a rival's kept power was seen. {} without fog.
var fog_intel := {}


func _init() -> void:
	name = "RulerPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(22))
	center.add_child(panel)
	PanelFit.attach(panel, center)  # MVP-3 (#177): a panel bigger than a 1280x720 viewport (125%) shrinks to fit it
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.name = "Head"
	box.add_child(head)
	var title := Label.new()
	title.name = "Title"
	title.text = "Rulers"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.GILT)
	head.add_child(title)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(120, 40)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.tooltip_text = "Close the ruler panel and go back to the map."
	close_button.pressed.connect(close)
	head.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	columns = HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 28)
	scroll.add_child(columns)
	footer_label = Label.new()
	footer_label.name = "Footer"
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label.add_theme_font_size_override("font_size", 15)
	footer_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	footer_label.text = FOOTER
	box.add_child(footer_label)


## Shows the panel for `viewing_fid` (your column first, every other faction read-only after it) on
## `p_state`. `p_orders` are your orders (a queued sacrifice is shown, and the Sacrifice button is only
## there while they can change); null for a read-only panel.
func show_for(p_state: GameState, viewing_fid: String, p_orders: OrdersController = null) -> void:
	state = p_state
	viewing_faction_id = viewing_fid
	orders = p_orders
	refresh()
	visible = true


## Rebuilds the columns from the state and orders (after an order was queued or cancelled).
func refresh() -> void:
	for c in columns.get_children():
		columns.remove_child(c)
		c.queue_free()
	sacrifice_button = null
	if state == null:
		return
	var fids := []
	if state.find_faction(viewing_faction_id) != null:
		fids.append(viewing_faction_id)
	for f in state.factions:
		if not fids.has(f.id):
			fids.append(f.id)
	for fid in fids:
		var col := _column(fid, fid == viewing_faction_id)
		columns.add_child(col)
	footer_label.text = FOG_FOOTER if FogView.active(state) else FOOTER  # M5-2: under fog, builds are learned


func close() -> void:
	visible = false
	closed.emit()


## The column of one faction's ruler. Yours (`own`) adds the queued sacrifice and the Sacrifice button.
func _column(fid: String, own: bool) -> VBoxContainer:
	var f := state.find_faction(fid)
	var outer := VBoxContainer.new()
	outer.name = "Column_%s" % fid.validate_node_name()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.custom_minimum_size = Vector2(560, 0)
	outer.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.name = "HeadingRow"
	head.add_theme_constant_override("separation", 10)
	outer.add_child(head)
	var banner := Art.banner_card(fid, 48.0)
	banner.name = "FactionBanner"
	head.add_child(banner)
	var heading := _heading(head, "%s: %s" % ["Your ruler" if own else "Enemy ruler (read-only)", f.faction_name], 21)
	heading.name = "FactionHeading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_theme_color_override("font_color", UiPalette.owner_color(state, fid).lightened(0.3))
	var people := AscensionRules.people_name(state, fid)  # M4-4: the people line (design/M4_ASCENSION.md §9.1)
	if not people.is_empty():
		heading.text += " · %s" % people
		heading.tooltip_text = TooltipText.plain("%s · %s" % [f.faction_name, people], "%s %s" % [
			AscensionRules.province_rule_sentence(state, fid, own), RulesCodex.text("transformation")])
		_codex_link(heading, "transformation")
	if not f.has_ruler():
		_text(outer, "The %s has no ruler in this game." % f.faction_name, TooltipText.plain("No ruler", RulesCodex.text("ruler")),
			UiPalette.TEXT_SECONDARY)
		return outer
	var rid := f.ruler_type
	var name := RulerRules.current_name(state, fid)
	# The ruler's portrait card at the left, every line about the ruler at its right.
	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 16)
	outer.add_child(body)
	var card := Art.ruler_card(rid, name, PORTRAIT_SIZE)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.tooltip_text = TooltipText.plain(RulerRules._cap(name), String(RulerRules.ruler_data(rid).get("flavour", "")))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(card)
	var col := VBoxContainer.new()
	col.name = "Lines"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	body.add_child(col)
	var who := _text(col, RulerRules._cap(name), TooltipText.plain("%s, ruler of the %s" % [RulerRules._cap(name), f.faction_name],
		"%s %s" % [String(RulerRules.ruler_data(rid).get("flavour", "")), RulesCodex.text("ruler")]), UiPalette.GILT)
	who.name = "RulerName"
	who.add_theme_font_size_override("font_size", 20)
	_codex_link(who, "ruler_" + rid)
	var kind := _text(col, RulerRules.kind_line(rid), TooltipText.plain("Where %s fights" % name, RulesCodex.text("ruler_rank")),
		UiPalette.TEXT_SECONDARY)
	kind.name = "KindLabel"
	_codex_link(kind, "ruler_rank")
	if not own and FogView.active(state):
		_rival_under_fog(col, f)  # M5-2: what you know of them
		return outer
	if RulerRules.has_living_ruler(state, fid):
		_living(col, f)
	elif not RulerRules.succession_info(state, fid).is_empty():
		_dead(col, f)
	else:
		var away := _text(col, "Not on the map right now.", TooltipText.plain("The ruler's army", RulesCodex.text("ruler_army")),
			UiPalette.TEXT_SECONDARY)
		away.name = "StatusLabel"
		_codex_link(away, "ruler_army")
		_power_and_ability(col, f)
	var succession := _text(col, "Succession: %s" % _succession_line(f), TooltipText.plain("Succession",
		RulerRules.succession_text(rid, f.kept_power, f.ruler_generation, _province_name(state, f.capital))), UiPalette.TEXT_SECONDARY)
	succession.name = "SuccessionLabel"
	_codex_link(succession, String(RulerData.KINDS.get(String(RulerRules.ruler_data(rid).get("kind", "")), {}).get("codex", "succession")))
	col.add_child(HSeparator.new())
	_mandates(col, f, own)
	if own:
		_sacrifice_section(col, f)
	return outer


## M5-2: an enemy column under fog (§11.1): what you know of them, where their ruler is as far as you know, its kept
## power as seen or the most it could be, and the mandates you know. A dead ruler's succession is heralded, so it shows
## as without fog.
func _rival_under_fog(col: VBoxContainer, f: Faction) -> void:
	var sum := FogView.rival_summary(state, viewing_faction_id, f.id, fog_intel)
	var known := _text(col, String(sum.text), TooltipText.plain("What you know about the %s" % f.faction_name, RulesCodex.text("intel")),
		UiPalette.TEXT_PRIMARY)
	known.name = "KnownLabel"
	_codex_link(known, "intel")
	if not RulerRules.ruler_alive(state, f.id) and not RulerRules.succession_info(state, f.id).is_empty():
		_dead(col, f)
	else:
		var where := _text(col, String(sum.where), TooltipText.plain("Where their ruler is", "%s %s" % [
			"Under fog you see a rival ruler only where you can see; it is remembered where you saw it last.", RulesCodex.text("ruler_army")]))
		where.name = "StatusLabel"
		_codex_link(where, "ruler_army")
		var kept := _text(col, "Kept power: %s" % String(sum.kept), TooltipText.plain("Their kept power", RulesCodex.text("intel")))
		kept.name = "KeptPowerLabel"
		_codex_link(kept, "intel")
		var rank := Breakdown.ability_rank(state, f.id)
		var ability := _text(col, "Ability: %s, rank %d at most (from that kept power)" % [RulerRules.ability_name(f.ruler_type), int(rank.total)],
			TooltipText.from_breakdown(rank), UiPalette.TEXT_SECONDARY)
		ability.name = "AbilityLabel"
		_codex_link(ability, String(rank.codex))
	col.add_child(HSeparator.new())
	var heading := _heading(col, "Mandates you know of (%d)" % f.mandates.size(), 18)
	heading.name = "MandatesHeading"
	heading.tooltip_text = TooltipText.plain("Mandates of the %s" % f.faction_name, "%s %s" % [RulesCodex.text("mandates"), RulesCodex.text("intel")])
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_codex_link(heading, "intel")
	for mid in f.mandates:
		var md := RulerRules.mandate_data(mid)
		var row := _text(col, String(md.get("name", mid)), TooltipText.plain(String(md.get("name", "")), _their(String(md.get("effect", "")))))
		row.name = "Mandate_%s" % String(mid).validate_node_name()
		_codex_link(row, String(md.get("codex", "mandates")))
	var more := _text(col, "They may have more you haven't seen: you learn a mandate when a battle you fought or a report line names it.",
		TooltipText.plain("They may have more", RulesCodex.text("intel")), UiPalette.TEXT_SECONDARY)
	more.name = "MayHaveMore"
	_codex_link(more, "intel")


## A living ruler's numbers, each with its breakdown and codex link.
func _living(col: VBoxContainer, f: Faction) -> void:
	var fid := f.id
	var army := RulerRules.ruler_army(state, fid)
	var status := _text(col, "Alive at %s" % _province_name(state, army.location), TooltipText.plain("Where the ruler is",
		"%s. %s" % [RulerRules._cap(TurnReportText.army_title(state, army)), RulesCodex.text("ruler_army")]))
	status.name = "StatusLabel"
	_codex_link(status, "ruler_army")
	var hp := Breakdown.ruler_stat(state, fid, "hp")
	var hp_label := _text(col, "Hit points: %d of %d" % [army.ruler.current_hp, int(hp.total)], "%s\n\n%s" % [
		TooltipText.from_breakdown(hp), TooltipText.wrap_text("%s has %d of its %d hit points now. %s" % [
			RulerRules._cap(RulerRules.current_name(state, fid)), army.ruler.current_hp, int(hp.total), RulesCodex.text("ruler_healing")])])
	hp_label.name = "HpLabel"
	_codex_link(hp_label, String(hp.codex))
	for stat in ["attack", "defense", "morale"]:
		var b := Breakdown.ruler_stat(state, fid, stat)
		var shown := "Morale: %d alone, +%d to its side while it stands" % [int(b.total), RulerData.RULER_MORALE] if stat == "morale" \
			else "%s: %d" % [stat.capitalize(), int(b.total)]
		var l := _text(col, shown, TooltipText.from_breakdown(b))
		l.name = "%sLabel" % stat.capitalize()
		_codex_link(l, String(b.codex))
	_power_and_ability(col, f)


## A dead ruler: the countdown to its successor, the kept power it died with, and the successor's
## numbers when it arrives (each with its breakdown).
func _dead(col: VBoxContainer, f: Faction) -> void:
	var fid := f.id
	var info := RulerRules.succession_info(state, fid)
	var countdown := Breakdown.successor_countdown(state, fid)
	var line := "Dead: %s" % RulerRules.countdown_text(state, fid)
	var status := _text(col, line, "%s\n\n%s" % [TooltipText.from_breakdown(countdown),
		TooltipText.wrap_text("Until then the %s has no ruler: no %s, no ruler in battle and no sacrifices. Its mandates stay." % [
			f.faction_name, RulerRules.ability_name(f.ruler_type)])], UiPalette.NEGATIVE)
	status.name = "CountdownLabel"
	_codex_link(status, String(countdown.codex))
	var when := _text(col, RulerRules.successor_sentence(info), TooltipText.plain("The successor", RulesCodex.text(String(info.codex))),
		UiPalette.TEXT_PRIMARY)
	when.name = "SuccessorLabel"
	_codex_link(when, String(info.codex))
	var kept := Breakdown.kept_power(state, fid)
	var kept_label := _text(col, "Kept power at death: %d; the successor will have %d" % [int(kept.total), int(info.successor_power)],
		"%s\n\n%s" % [TooltipText.from_breakdown(kept), TooltipText.wrap_text(RulerRules.succession_text(f.ruler_type, f.kept_power,
			f.ruler_generation, _province_name(state, f.capital)))])
	kept_label.name = "KeptPowerLabel"
	_codex_link(kept_label, String(kept.codex))
	var gen := int(info.successor_generation)
	var power := int(info.successor_power)
	_heading(col, "When %s arrives" % String(info.successor_name), 17)
	for stat in ["hp", "attack", "defense"]:
		var b := Breakdown.ruler_stat_at(f.ruler_type, stat, power, gen)
		var l := _text(col, "%s: %d" % [String(RulerRules.STAT_NAMES.get(stat, stat)) if stat != "hp" else "Hit points", int(b.total)],
			TooltipText.from_breakdown(b), UiPalette.TEXT_SECONDARY)
		l.name = "Successor%sLabel" % stat.capitalize()
		_codex_link(l, String(b.codex))
	var rank := Breakdown.ability_rank_at(f.ruler_type, power, gen)
	var ability := _text(col, "Ability: %s, rank %d (%s)" % [RulerRules.ability_name(f.ruler_type), int(rank.total),
		RulerRules.ability_short(f.ruler_type, int(rank.total))], TooltipText.from_breakdown(rank), UiPalette.TEXT_SECONDARY)
	ability.name = "SuccessorAbilityLabel"
	_codex_link(ability, String(rank.codex))


## Kept power and the ability, rank and effect, for a living ruler.
func _power_and_ability(col: VBoxContainer, f: Faction) -> void:
	var fid := f.id
	var kept := Breakdown.kept_power(state, fid)
	var kept_label := _text(col, "Kept power: %d of %d" % [int(kept.total), RulerData.POWER_POOL], TooltipText.from_breakdown(kept))
	kept_label.name = "KeptPowerLabel"
	_codex_link(kept_label, String(kept.codex))
	var rank := Breakdown.ability_rank(state, fid)
	var ability := _text(col, "Ability: %s, rank %d (%s)" % [RulerRules.ability_name(f.ruler_type), int(rank.total),
		RulerRules.ability_short(f.ruler_type, int(rank.total))], TooltipText.from_breakdown(rank))
	ability.name = "AbilityLabel"
	_codex_link(ability, String(rank.codex))
	var effect := _text(col, RulerRules.ability_text(f.ruler_type, int(rank.total), f.ruler_generation),
		TooltipText.plain(RulerRules.ability_name(f.ruler_type), RulesCodex.text("ability_" + RulerRules.ruler_data(f.ruler_type).ability)),
		UiPalette.TEXT_SECONDARY)
	effect.name = "AbilityEffectLabel"
	effect.add_theme_font_size_override("font_size", 15)
	_codex_link(effect, "ability_" + String(RulerRules.ruler_data(f.ruler_type).ability))


## The faction's mandates, each with its cost, how it was bought, its effect and what it does now.
func _mandates(col: VBoxContainer, f: Faction, own: bool) -> void:
	var heading := _heading(col, "Mandates (%d)" % f.mandates.size(), 18)
	heading.name = "MandatesHeading"
	heading.tooltip_text = TooltipText.plain("Mandates of the %s" % f.faction_name, RulesCodex.text("mandates"))
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_codex_link(heading, "mandates")
	if f.mandates.is_empty():
		_text(col, "None: %s kept all of its power." % RulerRules.current_name(state, f.id) if f.kept_power == RulerData.POWER_POOL \
			else "None.", "", UiPalette.TEXT_SECONDARY)
	var sacrificed := {}
	for sac in f.sacrifices:
		sacrificed[str(sac.get("mandate", ""))] = sac
	for mid in f.mandates:
		var md := RulerRules.mandate_data(mid)
		var how := "%d power, chosen before the game" % int(md.get("cost", 0))
		if sacrificed.has(mid):
			how = "%d power, sacrificed for on turn %d" % [int(sacrificed[mid].get("cost", 0)), int(sacrificed[mid].get("turn", 0))]
		var now := Forecast.mandate_now(state, f.id, mid, orders.orders() if own and orders else [], viewing_faction_id)
		var rule := String(md.get("effect", "")) if own else _their(String(md.get("effect", "")))
		var tip := TooltipText.plain(String(md.get("name", "")), "%s %s" % [rule, now])
		if sacrificed.has(mid):
			tip = "%s\n\n%s" % [TooltipText.from_breakdown(Breakdown.sacrifice_cost(mid)), tip]
		var row := _text(col, "%s (%s)" % [String(md.get("name", "")), how], tip)
		row.name = "Mandate_%s" % mid.validate_node_name()
		_codex_link(row, String(md.get("codex", "mandates")))
		var effect := _text(col, "    %s" % rule, "", UiPalette.TEXT_SECONDARY)
		effect.name = "MandateEffect_%s" % mid.validate_node_name()
		effect.add_theme_font_size_override("font_size", 15)


## Your column's sacrifice part: the queued Sacrifice order, or the button that opens the dialog
## (disabled, with the reason, when no sacrifice is possible).
func _sacrifice_section(col: VBoxContainer, f: Faction) -> void:
	col.add_child(HSeparator.new())
	var heading := _heading(col, "Sacrifice", 18)
	heading.name = "SacrificeHeading"
	heading.tooltip_text = TooltipText.plain("Sacrifice", RulesCodex.text("sacrifice"))
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_codex_link(heading, "sacrifice")
	var can_order := orders != null and (orders.session == null or orders.session.current_player() == f.id) \
		and (orders.session == null or orders.session.phase() == GameSession.Phase.ORDERS)
	var queued: SacrificeOrder = orders.queued_sacrifice() if orders != null else null
	var note := ""
	if queued != null:
		var b := Breakdown.sacrifice_kept_power(state, f.id, queued.mandate_id)
		var q := _text(col, "Queued this turn: %s for %d power. Kept power %d → %d when the turn resolves." % [
			RulerRules.mandate_name(queued.mandate_id), RulerRules.sacrifice_cost(queued.mandate_id), RulerRules.kept_power(state, f.id),
			int(b.total)], TooltipText.from_breakdown(b), UiPalette.GILT)
		q.name = "QueuedSacrificeLabel"
		_codex_link(q, "sacrifice")
		note = "One sacrifice per turn: cancel it from its token in the tray to choose another."
	elif not can_order:
		note = "You can sacrifice only while you give orders for your own turn."
	else:
		var check := RulerRules.sacrifice_check(state, f.id, "")
		if check.get("code", "") in ["no_ruler", "no_living_ruler"]:
			note = String(check.reason)
		else:
			var cheapest := -1
			for o in Forecast.sacrifice_options(state, f.id, orders.orders()):
				if o.ok:
					cheapest = 0
					break
				if not o.owned and o.code == "not_enough_power" and (cheapest < 0 or int(o.cost) < cheapest):
					cheapest = int(o.cost)
			if cheapest > 0:
				note = "No mandate fits: the cheapest one left costs %d power by sacrifice, and %s keeps %d." % [cheapest,
					RulerRules.current_name(state, f.id), f.kept_power]
			elif cheapest < 0:
				note = "Every mandate on your list is yours already."
	if not can_order and queued == null:
		var l := _text(col, note, "", UiPalette.TEXT_SECONDARY)
		l.name = "SacrificeNote"
		return
	sacrifice_button = Button.new()
	sacrifice_button.name = "SacrificeButton"
	sacrifice_button.text = "Sacrifice power for a mandate…"
	sacrifice_button.focus_mode = Control.FOCUS_NONE
	sacrifice_button.add_theme_font_size_override("font_size", 18)
	sacrifice_button.disabled = not note.is_empty()
	sacrifice_button.tooltip_text = TooltipText.plain("Sacrifice power for a mandate", "%s %s" % [
		note if not note.is_empty() else "Choose a mandate and see everything it changes, before and after, before you confirm.",
		RulesCodex.text("sacrifice")])
	_codex_link(sacrifice_button, "sacrifice")
	sacrifice_button.pressed.connect(func(): sacrifice_requested.emit())
	col.add_child(sacrifice_button)
	if not note.is_empty():
		var l := _text(col, note, "", UiPalette.TEXT_SECONDARY)
		l.name = "SacrificeNote"


## A mandate's rule as the other player reads it, in the enemy's column: "Your side never breaks while
## one of your commanders stands" becomes "Its side never breaks while one of its commanders stands".
static func _their(rule: String) -> String:
	var text := rule
	for pair in [["Your ", "Its "], [" your ", " its "], ["you own", "it owns"], ["joins you", "joins it"], ["you win", "it wins"]]:
		text = text.replace(pair[0], pair[1])
	return text


func _succession_line(f: Faction) -> String:
	var next := RulerRules.successor_for(f.ruler_type, f.kept_power, f.ruler_generation)
	var later := "%d %s" % [int(next.delay), "turn" if int(next.delay) == 1 else "turns"]
	match String(RulerRules.ruler_data(f.ruler_type).get("kind", "")):
		"undying":
			return "undying, re-forms %s later with the same kept power" % later
		"god":
			return "god, returns %s later with %d less kept power for good" % [later, int(RulerRules.ruler_data(f.ruler_type).succession.get("minus", 0))]
	return "mortal line, an heir %s later with half the kept power" % later


func _heading(parent: Control, text: String, font_size: int) -> Label:
	font_size = maxi(font_size, UiPalette.TYPE_FLOOR)  # UI-FIT (#237): nothing the player reads below the floor
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	parent.add_child(l)
	return l


func _codex_link(control: Control, key: String) -> void:
	CodexLink.attach(control, key, codex_requested.emit)


# --- the ruler's army on the map (M2, #29) --------------------------------------------------------


## The ruler's badge on its province (instead of "3 units"): a ruler's army holds only the ruler.
static func badge_text(_army: Army) -> String:
	return "Ruler"


## A few lines about the ruler for the badge and the side panel header:
##   King Corvane I (ruler of the Aurel Crown) at Crownkeep
##     mortal line, fights in the front rank
##     Hit points 46 of 46, attack 14, defense 13, morale 10 (+2 to its side while it stands)
##     Kept power 10 of 10, ability rank 4: Royal Court +5 gold
##     Mandates: none
##   <the succession rule>
static func summary(state: GameState, army: Army) -> String:
	if army == null or army.ruler == null:
		return ""
	var f := state.find_faction(army.owner)
	if f == null or not f.has_ruler():
		return RulerRules._cap(TurnReportText.army_title(state, army))
	var s := RulerRules.ruler_stats(f.ruler_type, f.kept_power, f.ruler_generation)
	var lines := PackedStringArray()
	lines.append(RulerRules._cap(TurnReportText.army_title(state, army)))  # as the map and the turn report name it
	lines.append("  %s" % RulerRules.kind_line(f.ruler_type))
	lines.append("  Hit points %d of %d, attack %d, defense %d, morale %d (+%d to its side while it stands)" % [
		army.ruler.current_hp, s.hp, s.attack, s.defense, s.morale, s.morale_bonus])
	lines.append("  Kept power %d of %d, ability rank %d: %s %s" % [f.kept_power, RulerData.POWER_POOL, s.ability_rank,
		s.ability_name, RulerRules.ability_short(f.ruler_type, s.ability_rank)])
	lines.append("  Mandates: %s" % _mandate_names(f))
	lines.append("")
	lines.append(TooltipText.wrap_text(RulerRules.succession_text(f.ruler_type, f.kept_power, f.ruler_generation,
		_province_name(state, f.capital))))
	return "\n".join(lines)


## Adds the ruler's lines under the army header in the map's army card. Each line's tooltip is its
## breakdown (or rule) and links its codex entry; right-clicks call `request_codex`. `with_portrait` false leaves the ruler's
## face out of the first line (the army card shows it in its portrait row, with the hit-point bar).
static func fill(box: Control, state: GameState, army: Army, request_codex: Callable, with_portrait: bool = true) -> void:
	var f := state.find_faction(army.owner)
	if f == null or not f.has_ruler() or army.ruler == null:
		return
	var fid := f.id
	var rid := f.ruler_type
	var name := RulerRules.current_name(state, fid)
	# The ruler's face beside its name (Art: a placeholder card until the ruler portraits land).
	var row := HBoxContainer.new()
	row.name = "RulerRow"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if with_portrait:
		row.add_child(Art.ruler_card(rid, name, Vector2(44, 44), Art.Crop.FACE))
	var ruler_label := _text(row, "Ruler: %s" % name, TooltipText.plain("%s, ruler of the %s" % [RulerRules._cap(name), f.faction_name],
		"%s It %s. %s" % [String(RulerRules.ruler_data(rid).get("flavour", "")), RulerData.BATTLE_RANKS.get(RulerRules.battle_rank(rid), ""),
			RulesCodex.text("ruler_army")]), UiPalette.GILT)
	ruler_label.name = "RulerLabel"
	ruler_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CodexLink.attach(ruler_label, "ruler_" + rid, request_codex)

	var hp := Breakdown.ruler_stat(state, fid, "hp")
	var hp_label := _text(box, "Hit points: %d of %d" % [army.ruler.current_hp, int(hp.total)], "%s\n\n%s" % [
		TooltipText.from_breakdown(hp), TooltipText.wrap_text("%s has %d of its %d hit points now." % [
			RulerRules._cap(name), army.ruler.current_hp, int(hp.total)])])
	hp_label.name = "RulerHpLabel"
	_link(hp_label, hp, request_codex)
	for stat in ["attack", "defense", "morale"]:
		var b := Breakdown.ruler_stat(state, fid, stat)
		var shown := "Morale: %d alone, +%d to its side" % [int(b.total), RulerData.RULER_MORALE] if stat == "morale" \
			else "%s: %d" % [stat.capitalize(), int(b.total)]
		var l := _text(box, shown, TooltipText.from_breakdown(b))
		l.name = "Ruler%sLabel" % stat.capitalize()
		_link(l, b, request_codex)

	var kept := Breakdown.kept_power(state, fid)
	var kept_label := _text(box, "Kept power: %d of %d" % [int(kept.total), RulerData.POWER_POOL], TooltipText.from_breakdown(kept))
	kept_label.name = "KeptPowerLabel"
	_link(kept_label, kept, request_codex)

	var rank := Breakdown.ability_rank(state, fid)
	var ability_label := _text(box, "Ability: %s, rank %d (%s)" % [RulerRules.ability_name(rid), int(rank.total),
		RulerRules.ability_short(rid, int(rank.total))], TooltipText.from_breakdown(rank))
	ability_label.name = "AbilityLabel"
	_link(ability_label, rank, request_codex)

	var mandate_lines := PackedStringArray()
	for mid in f.mandates:
		var md := RulerRules.mandate_data(mid)
		mandate_lines.append(TooltipText.wrap_text("%s (%d power): %s" % [md.get("name", ""), int(md.get("cost", 0)), md.get("effect", "")]))
	var mandates_tip := TooltipText.plain("Mandates of the %s" % f.faction_name, RulesCodex.text("mandates"))
	if not mandate_lines.is_empty():
		mandates_tip = "%s\n\n%s" % [mandates_tip, "\n".join(mandate_lines)]
	var mandates_label := _text(box, "Mandates: %s" % _mandate_names(f), mandates_tip, UiPalette.TEXT_SECONDARY)
	mandates_label.name = "MandatesLabel"
	CodexLink.attach(mandates_label, "mandates", request_codex)

	var kind_key := String(RulerData.KINDS.get(String(RulerRules.ruler_data(rid).get("kind", "")), {}).get("codex", "succession"))
	var succession_label := _text(box, "Succession: %s" % RulerRules.kind_name(rid), TooltipText.plain("Succession",
		RulerRules.succession_text(rid, f.kept_power, f.ruler_generation, _province_name(state, f.capital))), UiPalette.TEXT_SECONDARY)
	succession_label.name = "SuccessionLabel"
	CodexLink.attach(succession_label, kind_key, request_codex)


static func _mandate_names(f: Faction) -> String:
	var names := []
	for mid in f.mandates:
		names.append(RulerRules.mandate_name(mid))
	return "none" if names.is_empty() else ", ".join(names)


static func _link(control: Control, breakdown: Dictionary, request_codex: Callable) -> void:
	CodexLink.attach(control, String(breakdown.get("codex", "")), request_codex)


static func _province_name(state: GameState, pid: String) -> String:
	var p := state.find_province(pid)
	return p.name if p else "the capital"


## A line of text in the side panel's style (MapScreen._add_text): wraps, and takes the mouse when it
## has a tooltip so the tooltip shows.
static func _text(parent: Control, text: String, tooltip: String, color: Color = UiPalette.TEXT_PRIMARY) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
