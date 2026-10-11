class_name RecruitSection
extends CardBase
## UX-3 (design/UX_WAR_TABLE.md §3.2): the province card's Recruit section, moved from the side panel. The Recruit button on
## an owned province opens it, and it holds what the panel showed when that province was selected:
##   - a game with sieges: "Recruit at <fort>", a picker of every fort you own (each with its count this turn, greyed with the
##     rules' reason when it can't take recruits) and the recruit buttons for the fort selected (the engine too, at a keep or a
##     citadel), each with its price breakdown and, where it would leave a mage's rank exposed, the warning;
##   - a game without: "Recruit at <capital>" and its buttons;
##   - "View fortress" on the 3D board, at a capital;
##   - with Warband Muster, "Recruit with <ruler>": how many are left and one button per regular unit;
##   - "Gold after recruits", with its breakdown, so the price of the next recruit is never a surprise.
## Every button queues through the map screen (queue_recruit, queue_recruit_at, queue_recruit_with_ruler), so the order is checked
## by the same rules it always was. The card builds it hidden when the section is closed and the Recruit button shows it.

var province_id := ""


## True when the viewer can recruit in `pid` (the section has something to show): the capital, or a fort of yours in a game
## with sieges, or the province where your ruler stands when it can recruit in the field.
static func available(host: MapScreen, pid: String) -> bool:
	if host.orders == null or host.state == null:
		return false
	var f := host.state.find_faction(host.viewing_faction_id)
	if f == null:
		return false
	if host.state.sieges:
		if host.orders.recruit_places().any(func(r): return r.province == pid):
			return true
	elif pid == f.capital:
		return true
	var info := host.orders.ruler_recruit_info()
	return bool(info.get("ok", false)) and info.province == pid


static func make(host: MapScreen, pid: String) -> RecruitSection:
	var section := RecruitSection.new()
	section.map = host
	section.province_id = pid
	section._build()
	return section


func _init() -> void:
	super()
	name = "RecruitSection"


func _build() -> void:
	var f: Faction = state.find_faction(viewing_faction_id)
	if orders == null or f == null:
		return
	if state.sieges:
		_add_fort_recruit_section(f)  # M3c S-3: recruit at any fort you own
	elif province_id == f.capital:
		var capital := state.find_province(f.capital)
		add_heading("Recruit at %s" % capital.name, 18)
		_add_fortress_view_button(f.capital)
		for ut in orders.recruitable_types():
			var b := Button.new()
			b.name = "Recruit_%s" % ut.id.validate_node_name()
			b.text = "Recruit %s (%d gold)" % [ut.name, orders.recruit_cost(ut.id)]
			b.tooltip_text = TooltipText.from_breakdown(orders.recruit_breakdown(ut.id))
			_style_unit_button(b, ut.id, f.id)  # a scout's line joins the tooltip, then the codex link ends it
			link(b, "recruit")
			b.pressed.connect(map.queue_recruit.bind(ut.id))
			add_child(b)
			_add_rank_warning(ut.id, "")  # M5-8
	_add_ruler_recruit_section()
	add_gold_after(self)


## M5-8 (§3.2, §11.2): under a recruit button, "This army will have 8 second-rank and 6 front-rank fighters: its second rank is
## exposed", when recruiting it would leave the army's second rank exposed (MagicView.recruit_warning). Nothing otherwise.
func _add_rank_warning(unit_type_id: String, at: String) -> void:
	var rank := MagicView.recruit_warning(orders.view_state(), viewing_faction_id, unit_type_id, at, orders.orders())
	if rank.is_empty():
		return
	var warn := add_text(rank, TooltipText.plain("Exposed second rank", "%s %s" % [rank, RulesCodex.text("trait_mage")]), UiPalette.GILT)
	warn.name = "RecruitExposed_%s" % unit_type_id.validate_node_name()
	warn.add_theme_font_size_override("font_size", 15)
	warn.set_meta("rule_text", true)
	CodexLink.attach(warn, "trait_mage", map.request_codex)


## M3a.2: on the 3D board, "View fortress" swoops the camera into the capital's muster yard, where each
## queued recruit appears at once as a ghost in its slot (and back to the map when the view is open).
func _add_fortress_view_button(capital_id: String) -> void:
	var board := map.board
	if board == null or not board.has_method("can_closeup") or not board.can_closeup(capital_id):
		return
	var open: bool = String(board.closeup) == capital_id
	var b := Button.new()
	b.name = "ViewFortressButton"
	b.text = "Back to the map (Esc)" if open else "View fortress: see your muster yard"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", UiPalette.GILT)
	b.tooltip_text = TooltipText.plain("View fortress",
		"A close look at %s's muster yard. Your armies stand there a block to a slot, facing the gate, and each recruit you queue below appears at once as a translucent figure in the slot it will take. An army the yard can't hold musters in the war camp outside the walls. Esc or zooming out goes back to the map." % state.find_province(capital_id).name)
	b.pressed.connect(func():
		if String(board.closeup) == capital_id:
			board.exit_closeup()
		else:
			board.enter_closeup(capital_id))
	add_child(b)


## Warband Muster (§1.4): with the Ninth Fang's province selected, a "Recruit with the Ninth Fang"
## section: how many recruits are left this turn and one button per regular unit, at the same prices.
func _add_ruler_recruit_section() -> void:
	var info := orders.ruler_recruit_info()
	if not info.get("ok", false) or province_id != info.province:
		return
	var heading := add_heading("Recruit with %s" % info.ruler, 18)
	heading.name = "RulerRecruitHeading"
	var left := add_text("%d of %d left this turn (Warband Muster). They join your armies here at the end of the turn, even if %s moves on." % [
		info.left, info.limit, info.ruler],
		TooltipText.plain("Recruit with %s" % info.ruler, info.text), UiPalette.TEXT_SECONDARY)
	left.name = "RulerRecruitLeft"
	link(left, "field_recruit")
	for ut in orders.recruitable_types():
		var b := Button.new()
		b.name = "RecruitWithRuler_%s" % ut.id.validate_node_name()
		b.text = "Recruit %s with %s (%d gold)" % [ut.name, info.ruler, orders.recruit_cost(ut.id)]
		b.tooltip_text = TooltipText.from_breakdown(orders.recruit_breakdown(ut.id, RecruitOrder.AT_RULER))
		_style_unit_button(b, ut.id, viewing_faction_id)
		link(b, "field_recruit")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = info.left <= 0
		b.pressed.connect(map.queue_recruit_with_ruler.bind(ut.id))
		add_child(b)


## A recruit button: the unit's portrait (its face) at the left, then "Recruit <unit> (<cost> gold)",
## on a raised card that lights its border gilt on hover. M5-2: under fog a scout says so on its card.
func _style_unit_button(b: Button, unit_type_id: String, faction_id: String) -> void:
	if FogView.active(state):
		var f := state.find_faction(faction_id)
		for ut in (f.unit_types if f != null else []):
			if ut.id == unit_type_id and not FogView.scout_line(ut).is_empty():
				b.tooltip_text += "\n\n" + TooltipText.wrap_text("%s %s" % [FogView.scout_line(ut), RulesCodex.text("scouts")])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_PORTRAIT.y + 10)
	b.icon = Art.face(Art.unit_portrait(state, faction_id, unit_type_id))
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", int(ROW_PORTRAIT.x))
	b.add_theme_constant_override("h_separation", 12)
	b.add_theme_font_size_override("font_size", 17)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_RAISED.lightened(0.06 if state_name == "hover" else 0.0)
		sb.border_color = UiPalette.GILT if state_name in ["hover", "pressed"] else UiPalette.PANEL_BORDER
		sb.set_border_width_all(2 if state_name in ["hover", "pressed"] else 1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 5
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		if state_name == "disabled":
			sb.bg_color = UiPalette.PANEL_BG
		b.add_theme_stylebox_override(state_name, sb)
	b.add_theme_color_override("font_hover_color", UiPalette.GILT)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))


## The picker's one row when you own a single fort: "Crownkeep (citadel): 0 of 8 this turn" with its breakdown, and the rules' reason
## under it when the fort can't take recruits.
func _add_single_place(picker: Control, r: Dictionary) -> void:
	var level := SiegeRules.level_word(int(r.level))
	var limit := Breakdown.recruit_limit(state, String(r.province), viewing_faction_id, orders.orders())
	var tip := TooltipText.from_breakdown(limit)
	if not r.ok:
		tip = TooltipText.plain("%s can't take recruits" % r.name, String(r.reason)) + "\n\n" + tip
	var count := add_text("%s (%s): %d of %d this turn" % [r.name, level, int(r.count), int(r.limit)], tip, UiPalette.TEXT_PRIMARY, picker)
	count.name = "RecruitAt_%s" % String(r.province).validate_node_name()
	count.add_theme_font_size_override("font_size", 16)
	link(count, "recruit_at")
	if not r.ok:
		var why := add_text(String(r.reason), TooltipText.plain("Why not", String(r.reason)), UiPalette.NEGATIVE.lightened(0.25), picker)
		why.name = "RecruitAtReason_%s" % String(r.province).validate_node_name()
		why.add_theme_font_size_override("font_size", 15)


## M3c S-3: "Recruit at <fort>": a picker of every fort you own (each with its count this turn, greyed with the
## rules' reason when it can't take recruits), then the recruit buttons for the fort selected on the map.
func _add_fort_recruit_section(f: Faction) -> void:
	var places := orders.recruit_places()
	var here := places.filter(func(r): return r.province == province_id)
	if here.is_empty():
		return
	var place: Dictionary = here[0]
	var heading := add_heading("Recruit at %s" % place.name, 18)
	heading.name = "RecruitHeading"
	heading.tooltip_text = TooltipText.plain("Recruit at", RulesCodex.text("recruit_at_forts"))
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	link(heading, "recruit_at")
	var picker := VBoxContainer.new()
	picker.name = "RecruitAtPicker"
	picker.add_theme_constant_override("separation", 2)
	add_child(picker)
	if places.size() == 1:
		# One fort of yours: nothing to pick between, so its count is a line (the card is short on room), not a button.
		_add_single_place(picker, place)
		places = []
	for r in places:
		var b := Button.new()
		b.name = "RecruitAt_%s" % String(r.province).validate_node_name()
		b.toggle_mode = true
		b.button_pressed = r.province == province_id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		var level := SiegeRules.level_word(int(r.level))
		b.text = "%s (%s): %d of %d this turn" % [r.name, level, int(r.count), int(r.limit)]
		var limit := Breakdown.recruit_limit(state, String(r.province), viewing_faction_id, orders.orders())
		var tip := TooltipText.from_breakdown(limit)
		if not r.ok:
			b.disabled = true
			tip = TooltipText.plain("%s can't take recruits" % r.name, String(r.reason)) + "\n\n" + tip
		else:
			tip = TooltipText.plain("Recruit at %s" % r.name, "Click to recruit here: the buttons below make their recruits at %s, and they join your armies there." % r.name) + "\n\n" + tip
		b.tooltip_text = tip
		link(b, "recruit_at")
		var pid := String(r.province)
		b.pressed.connect(func():
			map.cards.carry_sections = true  # the picker moves between your forts: the Recruit section stays open
			map.select_province(pid))
		picker.add_child(b)
		if not r.ok:
			var why := add_text(String(r.reason), TooltipText.plain("Why not", String(r.reason)), UiPalette.NEGATIVE.lightened(0.25), picker)
			why.name = "RecruitAtReason_%s" % pid.validate_node_name()
			why.add_theme_font_size_override("font_size", 15)
	if place.province == f.capital:
		_add_fortress_view_button(f.capital)
	if not place.ok:
		return
	var at: String = "" if place.province == f.capital else String(place.province)
	for ut in orders.recruitable_types_at(String(place.province)):
		var b := Button.new()
		b.name = "Recruit_%s" % ut.id.validate_node_name()
		b.text = "Recruit %s (%d gold)" % [ut.name, orders.recruit_cost(ut.id)]
		var tip := TooltipText.from_breakdown(orders.recruit_breakdown(ut.id, at))
		var fc := Forecast.recruit_at(orders.view_state(), viewing_faction_id, ut.id, at, orders.orders())
		if not fc.ok and String(fc.code) != "not_enough_gold":
			b.disabled = true
			tip = TooltipText.plain("Can't recruit %s here" % ut.name, String(fc.reason)) + "\n\n" + tip
		b.tooltip_text = tip
		_style_unit_button(b, ut.id, f.id)
		link(b, "recruit_at" if not SiegeRules.is_engine(ut) else "recruit")
		if SiegeRules.is_engine(ut):
			CodexLink.attach(b, SiegeRules.engine_codex(ut.id), map.request_codex)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var type_id: String = ut.id
		b.pressed.connect(func(): map.queue_recruit_at(type_id, at))
		add_child(b)
		if b.disabled:
			var why := add_text(String(fc.reason), TooltipText.plain("Why not", String(fc.reason)), UiPalette.NEGATIVE.lightened(0.25))
			why.name = "RecruitReason_%s" % ut.id.validate_node_name()
			why.add_theme_font_size_override("font_size", 15)
		else:
			_add_rank_warning(ut.id, at)
