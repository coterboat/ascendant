class_name FortifyControls
extends VBoxContainer
## UX-3 (design/UX_WAR_TABLE.md §3.2): the province card's Fortify action, moved out of the fort panel (FortPanel) so it sits
## in the card's action row and not behind the panel. It is the panel's own Fortify, unchanged:
##   - the button "Fortify: build a Palisade (20 gold, 2 turns)" or "Upgrade to a Keep (...)", greyed with the rules' reason
##     under it when the order can't be given (too little gold, an enemy army there, ...);
##   - once ordered, the line "Fortify ordered: a Palisade at Greenglade for 20 gold (...). It stands at the end of turn 3..."
##     with its cost breakdown.
## The order goes through the map screen's queue_fortify (OrdersController, checked by the same rules as ever). Only in a game
## with sieges, and only for a province of yours that is not a capital and can still be built up.

var map: MapScreen
var province_id := ""


## The Fortify controls for `pid`, or null when the viewer can't fortify there (not theirs, a capital, already a citadel or
## being built, or a game without sieges).
static func make(host: MapScreen, pid: String) -> FortifyControls:
	var s := host.state
	var p := s.find_province(pid) if s != null else null
	if p == null or not s.sieges or host.orders == null or not FortPanel._may_fortify_here(host, p):
		return null
	var box := FortifyControls.new()
	box.map = host
	box.province_id = pid
	box._build(p)
	return box


func _init() -> void:
	name = "FortifyControls"
	add_theme_constant_override("separation", 4)


func _build(p: Province) -> void:
	var s := map.state
	var o := map.orders
	var to := SiegeRules.fortify_level(s, province_id)
	var i := o.fortify_index(province_id)
	if i >= 0:
		var fb := o.fortify_breakdown(i)
		var fc := o.fortify_preview(province_id)
		var text := "Fortify ordered: %s at %s for %d gold (%d gold left). It stands at the end of turn %d if no enemy army stands here, and takes recruits from turn %d. Cancel it in your orders." % [
			SiegeRules.fort_phrase(to), p.name, int(fc.cost), int(fb.total), int(fc.stands), int(fc.recruit_from)] if fc.ok else String(o.order_texts()[i])
		var queued := _label("FortifyQueued", text, UiPalette.GILT)
		queued.tooltip_text = TooltipText.from_breakdown(fb)
		queued.set_meta(FortPanel.BREAKDOWN, fb)
		CodexLink.attach(queued, TooltipText.codex_for("", fb) if fb.has("codex") else "fort", map.request_codex)
		return
	var fc2 := o.fortify_preview(province_id)
	var button := Button.new()
	button.name = "FortifyButton"
	var verb := "Fortify: build a %s" % SiegeRules.level_word(to) if p.fort_level <= 0 else "Upgrade to a %s" % SiegeRules.level_word(to)
	button.text = "%s (%d gold, %s)" % [verb, int(SiegeRules.level_data(to).cost), FortPanel._count(int(SiegeRules.level_data(to).turns), "turn")]
	button.icon = UiIcons.icon("fortify", 20)
	button.expand_icon = false
	button.add_theme_color_override("icon_normal_color", UiPalette.GILT)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
	button.focus_mode = Control.FOCUS_NONE
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", FortPanel.FONT)
	button.add_theme_color_override("font_color", UiPalette.GILT)
	button.disabled = not bool(fc2.ok)
	button.tooltip_text = TooltipText.plain(verb if p.fort_level > 0 else "Fortify", String(fc2.text) if fc2.ok else String(fc2.reason))
	CodexLink.attach(button, "fortify", map.request_codex)
	var pid := province_id
	button.pressed.connect(func(): map.queue_fortify(pid))
	add_child(button)
	if not fc2.ok:
		var l := _label("FortifyReason", String(fc2.reason), UiPalette.NEGATIVE.lightened(0.25))
		l.add_theme_font_size_override("font_size", FortPanel.FONT - 2)
		l.tooltip_text = TooltipText.plain("Why not", "%s Orders are checked with the same rules the turn uses." % String(fc2.reason))
		l.set_meta(FortPanel.REASON, true)
		CodexLink.attach(l, "orders", map.request_codex)


func _label(node_name: String, text: String, colour: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", FortPanel.FONT)
	l.add_theme_color_override("font_color", colour)
	add_child(l)
	return l
