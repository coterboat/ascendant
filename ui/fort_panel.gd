class_name FortPanel
extends VBoxContainer
## The fort section of the province panel (M3c S-3, #101; design/M3C_SIEGES.md §9.1-§9.3), under the "Fort:"
## line of a game with sieges. Everything a player needs to run a fort, or a siege of one, from the panel alone:
##   - the siege's state: "Besieged by the Thornmane Clans: turn 2 of the siege", or not;
##   - the walls (a WallsBar marking the storm steps), "Walls 5 of 6" and "+4 defense if stormed";
##   - the recruits a turn, and any construction;
##   - during a siege: who is inside and outside the walls, the siege damage, the turn the walls reach 0 and the
##     cut-off;
##   - the viewer's choices: Fortify or Upgrade with its preview, the Storm toggle (naming every army that goes),
##     the Sally ticks (one per army, the ruler's unticked) with what a sally risks, and whether a relief can come.
## Every number shows its breakdown on hover (meta BREAKDOWN), straight from Breakdown or from FortView's
## breakdowns that add up to SiegeRules; a line quoting the rules' own words carries meta REASON instead. Every
## line links its codex entry. The panel reads the state and the viewer's own orders (the map's
## OrdersController), never another seat's; the choices go back through the map (queue_fortify, set_storm,
## set_sally), so they are checked by OrderBook like every order.

## The meta a numbers label keeps its breakdown in (tests read it), and the meta of a line in the rules' words.
const BREAKDOWN := "breakdown"
const REASON := "rules_reason"
const FONT := 17

var map: MapScreen
var province_id := ""


## The fort section for `province_id` on `host`'s side panel, or null when there is nothing to show (no sieges,
## or no fort, no site and nothing the viewer could build there).
static func make(host: MapScreen, pid: String) -> FortPanel:
	var s := host.state
	var p := s.find_province(pid) if s != null else null
	if p == null or not s.sieges:
		return null
	if p.fort_level <= 0 and p.works.is_empty() and not _may_fortify_here(host, p):
		return null
	var panel := FortPanel.new()
	panel.map = host
	panel.province_id = pid
	panel._build()
	return panel


## Whether the viewer could ever fortify `p` (theirs, not a capital, below a keep): the Fortify button shows.
static func _may_fortify_here(host: MapScreen, p: Province) -> bool:
	return host.orders != null and not host.viewing_faction_id.is_empty() and p.owner == host.viewing_faction_id \
		and not p.is_capital and p.fort_level < FortData.MAX_BUILT and p.works.is_empty()


func _init() -> void:
	name = "FortSection"
	add_theme_constant_override("separation", 4)


func _build() -> void:
	var s := map.state
	var p := s.find_province(province_id)
	var viewer := map.viewing_faction_id
	var stands := p.fort_level > 0 and SiegeRules.siege_stands(s, province_id)
	if p.fort_level > 0:
		_add_status(p, stands)
		_add_walls(p)
		_add_recruits(p, viewer)
	if not p.works.is_empty():
		var c := Breakdown.construction(s, province_id)
		var to := int(p.works.to)
		var turns := int(SiegeRules.level_data(to).turns)
		var left := int(p.works.left)
		var text := "Building %s: %s left (%d of %d done), standing at the end of turn %d" % [SiegeRules.fort_phrase(to),
			_count(left, "turn of work", "turns of work"), turns - left, turns, s.current_turn + left]
		if not SiegeRules.besiegers(s, province_id).is_empty():
			text = "Building %s: %s left, stopped while an enemy army is here" % [SiegeRules.fort_phrase(to), _count(left, "turn of work", "turns of work")]
		_number("ConstructionLabel", text, c, UiPalette.GILT)
	if stands:
		_add_siege(p, viewer)
	if map.orders == null or s.find_faction(viewer) == null:
		return
	if stands and p.owner == viewer and p.walls > 0:
		_add_sally(p, viewer)
	elif p.fort_level > 0 and p.owner != viewer and not SiegeRules.garrison(s, province_id).is_empty() \
			and not map.orders.storm_armies(province_id).is_empty():
		_add_storm(p, viewer)
	if _may_fortify_here(map, p):
		_add_fortify(p)


# --- what the fort is ----------------------------------------------------------------------------------

func _add_status(p: Province, stands: bool) -> void:
	var s := map.state
	if stands:
		var who := FortView.besieger_name(s, province_id)
		var n := SiegeRules.turn_of_siege(s, province_id)
		var text := ("Breached, with the %s outside: turn %d of the siege" if p.walls <= 0 else "Besieged by the %s: turn %d of the siege") % [who, n]
		_number("SiegeStatusLabel", text, FortView.turn_of_siege_breakdown(s, province_id), UiPalette.NEGATIVE.lightened(0.15))
		return
	var quiet := "Not besieged: the walls repair while no army of another faction is here." \
		if p.walls < SiegeRules.walls_max(p.fort_level) else "Not besieged, walls whole."
	if p.walls <= 0:
		quiet = "Breached, and not besieged: the walls repair while no enemy is here."
	_rules_line("SiegeStatusLabel", quiet, "Not besieged", RulesCodex.text("siege"), "siege", UiPalette.TEXT_SECONDARY)


func _add_walls(p: Province) -> void:
	var s := map.state
	var walls := Breakdown.walls(s, province_id)
	var bar := WallsBar.new(p.walls, SiegeRules.walls_max(p.fort_level), 14.0, 1.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.tooltip_text = TooltipText.from_breakdown(walls)
	bar.set_meta(BREAKDOWN, walls)
	CodexLink.attach(bar, "walls", map.request_codex)
	add_child(bar)
	var row := HFlowContainer.new()
	row.name = "WallsRow"
	row.add_theme_constant_override("h_separation", 14)
	add_child(row)
	var w := _number("WallsLabel", "Walls %d of %d" % [p.walls, SiegeRules.walls_max(p.fort_level)], walls, UiPalette.TEXT_PRIMARY, row)
	var d := Breakdown.walls_defense(s, province_id)
	var text := "+%d defense if stormed" % int(d.total) if p.walls > 0 else "+0 defense: breached, nothing to storm"
	var sd := _number("StormDefenseLabel", text, d, UiPalette.TEXT_SECONDARY, row)
	for l in [w, sd]:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF  # in a flow row, each keeps its words together and wraps as a whole


func _add_recruits(p: Province, viewer: String) -> void:
	var s := map.state
	var mine := p.owner == viewer and map.orders != null
	var b := Breakdown.recruit_limit(s, province_id, viewer if mine else p.owner, map.orders.orders() if mine else [])
	var text := "Recruits: %d a turn (%s)" % [int(b.total), SiegeRules.level_word(p.fort_level)]
	if bool(SiegeRules.cut_off_info(s, province_id).cut_off):
		text += ", none this turn: cut off"
	elif mine:
		text += ", %d ordered" % int(b.ordered)
	_number("RecruitLimitLabel", text, b)


# --- the siege -----------------------------------------------------------------------------------------

func _add_siege(p: Province, viewer: String) -> void:
	var s := map.state
	var inside := SiegeRules.garrison(s, province_id)
	var outside := SiegeRules.besiegers(s, province_id)
	_number("InsideLabel", "Inside the walls: %s (%s)" % [_names(inside), _count(SiegeRules.troops(inside), "troop")],
		FortView.troops_breakdown(s, inside, "Inside the walls of %s" % p.name))
	var engines := SiegeRules.engines_of(outside)
	var force := _count(SiegeRules.troops(outside), "troop")
	if engines > 0:
		force += " and %s" % SiegeRules.engines_text(SiegeRules.besieging_faction(s, province_id), engines)
	_number("OutsideLabel", "Outside the walls: %s (%s)" % [_names(outside), force],
		FortView.troops_breakdown(s, outside, "Outside the walls of %s" % p.name))
	var dmg := Breakdown.siege_damage(s, province_id)
	_number("SiegeDamageLabel", "Siege damage: %d a turn" % int(dmg.total), dmg)
	var stay := FortView.IF_YOU_STAY if p.owner != viewer and outside.any(func(a): return a.owner == viewer) else FortView.IF_THEY_STAY
	if p.walls > 0:
		var turn := s.current_turn + 1
		var bb := FortView.breach_breakdown(s, province_id, int(dmg.total), stay)
		var end := int(bb.total)
		var when := "at the end of this turn (%d)" % end if end <= turn else "at the end of turn %d (in %s)" % [end, _count(end - turn + 1, "turn")]
		_number("BreachLabel", "The walls reach 0 %s, %s." % [when, stay], bb, UiPalette.GILT)
	else:
		var l := _rules_line("BreachLabel", "Breached: no walls and no %s for anyone; the garrison fights with +%d cover. The battle comes on its own this turn, in the open, unless one side leaves." % [
			p.terrain, FortData.COVER_DEFENSE], "The breach", RulesCodex.text("breach"), "breach", UiPalette.GILT)
		l.set_meta(REASON, true)
	_add_cut_off(p)


func _add_cut_off(p: Province) -> void:
	var s := map.state
	var info := SiegeRules.cut_off_info(s, province_id)
	var b := Breakdown.cut_off(s, province_id)
	var who := FortView.besieger_name(s, province_id)
	var text := ""
	if bool(info.cut_off):
		text = "Cut off by %s outside (%d needed): no recruits here, and its %d gold a turn goes to the %s." % [
			_count(int(info.besieger_troops), "troop"), int(info.need), p.income, who]
	elif bool(info.pickets):
		text = "Not cut off: the %s outside are only pickets (%d needed)." % [_count(int(info.besieger_troops), "troop"), int(info.need)]
	else:
		text = "Not cut off yet: from next turn (%d), if the %s outside stay (%d needed)." % [s.current_turn + 2,
			_count(int(info.besieger_troops), "troop"), int(info.need)]
	_number("CutOffLabel", text, b, UiPalette.NEGATIVE.lightened(0.2) if bool(info.cut_off) else UiPalette.TEXT_SECONDARY)


# --- the viewer's choices ------------------------------------------------------------------------------

func _add_sally(p: Province, viewer: String) -> void:
	var s := map.state
	var o := map.orders
	_heading("SallyHeading", "Sally: come out and fight", "sally")
	var inside := SiegeRules.garrison(s, province_id)
	var ticked := []
	for a in inside:
		var queued := o.sally_index(a.id) >= 0
		if queued:
			ticked.append(a.id)
		var tick := CheckBox.new()
		tick.name = "SallyTick_%s" % a.id.validate_node_name()
		var title := TurnReportText.army_name(s, a.id, a.owner)
		tick.text = "Sally with %s (%s)" % [title, "your ruler" if a.ruler != null else _count(a.units.size(), "troop")]
		tick.button_pressed = queued
		tick.focus_mode = Control.FOCUS_NONE
		tick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tick.add_theme_font_size_override("font_size", FONT)
		var tip := "Tick to bring %s out of the walls this turn to fight every army outside, in the open: nobody gets walls or ground, but your fighters from inside keep +%d cover. If it loses, it is destroyed; armies left inside are unharmed." % [
			title, FortData.COVER_DEFENSE]
		if a.ruler != null:
			tip = "This is your ruler's army. A sally risks your ruler: if the sally loses, the ruler falls with it. " + tip
		var check := o.sally_check(a.id)
		if not check.is_empty() and not queued:
			tick.disabled = true
			tip = "%s\n\n%s" % [String(check.reason), tip]
		tick.tooltip_text = TooltipText.plain(tick.text, tip)
		CodexLink.attach(tick, "sally", map.request_codex)
		var army_id: String = a.id
		tick.toggled.connect(func(on: bool): map.set_sally(army_id, on))
		add_child(tick)
		if not check.is_empty() and not queued:
			_reason("SallyReason_%s" % a.id.validate_node_name(), String(check.reason))
	var risk := FortView.staying_breakdown(s, province_id, inside, ticked)
	_number("SallyRisk", FortView.risk_text(s, province_id, inside, ticked), risk, UiPalette.TEXT_SECONDARY)
	var sally_odds := FortView.siege_odds("sally", s, viewer, province_id, o.orders())
	var odds := FortView.odds_text(sally_odds)
	if not odds.is_empty() and not ticked.is_empty():
		_number("SallyOdds", "Sallying now: %s." % odds, FortView.odds_breakdown(sally_odds, "Sally odds"), UiPalette.GILT)
	var relief := o.relief_into(province_id)
	var text := ""
	if not relief.is_empty():
		var ra := s.find_army(relief)
		text = "Relief from %s: %s marches in this turn and meets the siege lines in the open; the armies ticked above go out with it." % [
			s.find_province(ra.location).name, TurnReportText.army_name(s, ra.id, ra.owner)]
	else:
		var reach := []
		for a in TurnResolver._sorted_armies(s):
			if a.owner == viewer and a.location != province_id and p.neighbors.has(a.location):
				reach.append(s.find_province(a.location).name)
		if reach.is_empty():
			text = "Relief: no army of yours can reach %s this turn." % p.name
		else:
			text = "Relief: your %s at %s can reach %s this turn. Select one and click %s: the garrison comes out to join it." % [
				"army" if reach.size() == 1 else "armies", RulerRules._and_list(reach), p.name, p.name]
	var l := _rules_line("ReliefNote", text, "Relief", RulesCodex.text("relief"), "relief", UiPalette.TEXT_SECONDARY)
	l.set_meta(REASON, true)


func _add_storm(p: Province, viewer: String) -> void:
	var s := map.state
	var o := map.orders
	_heading("StormHeading", "Storm or wait", "storm")
	var toggle := CheckButton.new()
	toggle.name = "StormToggle"
	toggle.text = "Storm the walls this turn"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", FONT)
	toggle.button_pressed = o.storm_index(province_id) >= 0
	var check := o.storm_check(province_id)
	var tip := "Off: you wait, the siege goes on and the walls drop. On: every army of yours at %s attacks the garrison this turn, which defends with its walls (+%d defense) and its %s." % [
		p.name, SiegeRules.walls_defense(p.walls), p.terrain]
	if not check.is_empty():
		toggle.disabled = true
		tip = "%s\n\n%s" % [String(check.reason), tip]
	var fc := Forecast.siege(s, viewer, province_id, o.orders())
	if fc.ok and not String(fc.text).is_empty():
		tip += " " + String(fc.text)
	toggle.tooltip_text = TooltipText.plain("Storm", tip)
	CodexLink.attach(toggle, "storm", map.request_codex)
	var pid := province_id
	toggle.toggled.connect(func(on: bool): map.set_storm(pid, on))
	add_child(toggle)
	if not check.is_empty():
		_reason("StormReason", String(check.reason))
		return  # nothing to choose: the reason says why
	var armies := o.storm_armies(province_id)
	var here := armies.filter(func(a): return a.location == province_id).size()
	var b := FortView._make("Armies that storm %s" % p.name, RulesCodex.text("storm"), [
		FortView._line("Your armies at %s" % p.name, here, ""), FortView._line("Marching in this turn", armies.size() - here, "a storm from the march")],
		"Armies that storm", armies.size())
	b["codex"] = "storm"
	var ruler := armies.any(func(a): return a.ruler != null)
	var lead := "Storming this turn:" if toggle.button_pressed else "If you storm,"
	var text := ""
	if armies.size() == 1:
		text = "%s your army at %s goes: %s. To keep an army out, move it away." % [lead, p.name, _names(armies)]
	else:
		var who := "both of your armies" if armies.size() == 2 else "all %d of your armies" % armies.size()
		text = "%s %s at %s go%s: %s. To keep an army out, move it away." % [lead, who, p.name,
			", your ruler's included" if ruler else "", _names(armies)]
	_number("StormNote", text, b, UiPalette.TEXT_SECONDARY)
	var storm_odds := FortView.siege_odds("storm", s, viewer, province_id, o.orders())
	var odds := FortView.odds_text(storm_odds)
	if not odds.is_empty():
		_number("StormOdds", "Storming now: %s." % odds, FortView.odds_breakdown(storm_odds, "Storm odds"), UiPalette.GILT)


func _add_fortify(p: Province) -> void:
	var s := map.state
	var o := map.orders
	var to := SiegeRules.fortify_level(s, province_id)
	var i := o.fortify_index(province_id)
	if i >= 0:
		var fb := o.fortify_breakdown(i)
		var fc := o.fortify_preview(province_id)
		var text := "Fortify ordered: %s at %s for %d gold (%d gold left). It stands at the end of turn %d if no enemy army stands here, and takes recruits from turn %d. Cancel it in your orders." % [
			SiegeRules.fort_phrase(to), p.name, int(fc.cost), int(fb.total), int(fc.stands), int(fc.recruit_from)] if fc.ok else String(o.order_texts()[i])
		_number("FortifyQueued", text, fb, UiPalette.GILT)
		return
	var fc2 := o.fortify_preview(province_id)
	var button := Button.new()
	button.name = "FortifyButton"
	var verb := "Fortify: build a %s" % SiegeRules.level_word(to) if p.fort_level <= 0 else "Upgrade to a %s" % SiegeRules.level_word(to)
	button.text = "%s (%d gold, %s)" % [verb, int(SiegeRules.level_data(to).cost), _count(int(SiegeRules.level_data(to).turns), "turn")]
	button.focus_mode = Control.FOCUS_NONE
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", FONT)
	button.add_theme_color_override("font_color", UiPalette.GILT)
	button.disabled = not bool(fc2.ok)
	button.tooltip_text = TooltipText.plain(verb if p.fort_level > 0 else "Fortify", String(fc2.text) if fc2.ok else String(fc2.reason))
	CodexLink.attach(button, "fortify", map.request_codex)
	var pid := province_id
	button.pressed.connect(func(): map.queue_fortify(pid))
	add_child(button)
	if not fc2.ok:
		_reason("FortifyReason", String(fc2.reason))


# --- nodes ------------------------------------------------------------------------------------------

## A line showing a number: its breakdown on hover (and kept in meta BREAKDOWN), linked to its codex entry.
func _number(node_name: String, text: String, b: Dictionary, colour: Color = UiPalette.TEXT_PRIMARY, parent: Control = null) -> Label:
	var l := _label(node_name, text, colour, parent)
	l.tooltip_text = TooltipText.from_breakdown(b)
	l.set_meta(BREAKDOWN, b)
	CodexLink.attach(l, TooltipText.codex_for("", b) if b.has("codex") else "fort", map.request_codex)
	return l


## A line in the rules' own words, with a plain tooltip and its codex entry.
func _rules_line(node_name: String, text: String, title: String, rule: String, codex: String, colour: Color = UiPalette.TEXT_PRIMARY) -> Label:
	var l := _label(node_name, text, colour)
	l.tooltip_text = TooltipText.plain(title, rule)
	CodexLink.attach(l, codex, map.request_codex)
	return l


## The rules' reason an order can't be given, on screen under its control.
func _reason(node_name: String, reason: String) -> Label:
	var l := _label(node_name, reason, UiPalette.NEGATIVE.lightened(0.25))
	l.add_theme_font_size_override("font_size", FONT - 2)
	l.tooltip_text = TooltipText.plain("Why not", "%s Orders are checked with the same rules the turn uses." % reason)
	l.set_meta(REASON, true)
	CodexLink.attach(l, "orders", map.request_codex)
	return l


func _heading(node_name: String, text: String, codex: String) -> Label:
	var l := _label(node_name, text, UiPalette.GILT)
	l.add_theme_font_size_override("font_size", 18)
	l.tooltip_text = TooltipText.plain(text, RulesCodex.text(codex))
	CodexLink.attach(l, codex, map.request_codex)
	return l


func _label(node_name: String, text: String, colour: Color, parent: Control = null) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", FONT)
	l.add_theme_color_override("font_color", colour)
	(parent if parent != null else self).add_child(l)
	return l


## "the Crown's 3rd and King Corvane I" for armies.
func _names(armies: Array) -> String:
	return RulerRules._and_list(armies.map(func(a): return TurnReportText.army_name(map.state, a.id, a.owner)))


static func _count(n: int, singular: String, plural: String = "") -> String:
	return "%d %s" % [n, singular if n == 1 else (plural if not plural.is_empty() else singular + "s")]

