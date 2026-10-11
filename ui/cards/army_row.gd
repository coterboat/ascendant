class_name ArmyRow
extends PanelContainer
## UX-3 (design/UX_WAR_TABLE.md §3.1, §3.2): one army in a list on a card: its name and place as a button that selects it, with
## its portraits under it (UnitStrip, hit-point bars and all). The province card lists the armies there with it, and the army card
## lays out your other armies in the same province with it, each on its own row: the place ARM-1 (design/ARM1_SPLIT_MERGE.md §8)
## will give drag, Split, Merge all and Swap commanders. Nothing of that is built here yet: a row only selects.
##
## A rival's army shows only what FogView allows: under fog a stand-in is its sighting ("about 8 fighters ... glimpsed"), greyed
## when it is only remembered, and never has portraits (it holds no true fighters).

const PORTRAIT := Vector2(28, 28)

var army_id := ""
var button: Button
var strip: UnitStrip = null


static func make(host: MapScreen, a: Army, compact: bool = false) -> ArmyRow:
	var row := ArmyRow.new()
	row.name = "ArmyRow_%s" % a.id.validate_node_name()
	row.army_id = a.id
	row._build(host, a, compact)
	return row


func _build(host: MapScreen, a: Army, compact: bool) -> void:
	var state := host.state
	var selected := a.id == host.selected_army_id
	var stand_in := FogView.is_stand_in(a)
	var style := CardBase.raised_style(UiPalette.SELECTION if selected else UiPalette.owner_color(state, a.owner, host.seat_order()), 3 if selected else 2)
	style.set_content_margin_all(6)
	if stand_in and String(a.seen.get("level", "")) == FogData.MEMORY:
		style.bg_color = UiPalette.PANEL_BG
		modulate = Color(1, 1, 1, 0.72)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	button = Button.new()
	button.name = "ArmyButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY if compact else 17)
	if stand_in:
		var level := String(a.seen.get("level", ""))
		var tip := TooltipText.from_breakdown(FogView.army_breakdown(state, host.viewing_faction_id, a, host.fog_before))
		button.text = FogView.army_heading(state, a)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = false
		button.tooltip_text = tip + "\n\nClick to select it."
		var kind := "remembered" if level == FogData.MEMORY else ("glimpse" if level == FogRules.GLIMPSE else "vision")
		CodexLink.attach(button, TooltipText.codex_for(kind), host.request_codex)
	else:
		var parts := ArmyCard.header_parts(state, a)
		button.text = String(parts[0])  # the turn report's name for it (#55) and its place, on one line (#125)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.tooltip_text = (RulerPanel.summary(state, a) if a.ruler != null else TooltipText.from_breakdown(Breakdown.army_units(state, a.id))) \
			+ "\n\nClick to select this army."
		CodexLink.attach(button, "ruler_army" if a.ruler != null else TooltipText.codex_for("army_units"), host.request_codex)
	button.pressed.connect(host.select_army.bind(a.id))
	box.add_child(button)
	if not stand_in:
		# Hit points are shown for your own armies, and for any army in a game without fog (the state is the truth there).
		strip = UnitStrip.make(state, a, PORTRAIT, host.request_codex, a.owner == host.viewing_faction_id or not FogView.active(state))
		box.add_child(strip)
