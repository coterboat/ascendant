class_name FortChip
extends PanelContainer
## The fort chip on a province plate (M3c S-3, #101; design/M3C_SIEGES.md §9.1 "the fort chip on the province
## plate", §10.1): a tower glyph, the level ("Keep"), the walls bar marking the storm steps (WallsBar), and
##   - besieged: the chip's edge and two chevrons in the besieger's player colour (the bible's "besieged" marker);
##   - breached: "Keep: breached" over an empty bar;
##   - construction: a scaffold glyph and the turns of work done ("Palisade 1/2" on a site with no fort yet).
## Its tooltip is the walls breakdown (Breakdown.walls) with what the siege does, linked to Siege, Walls or
## Construction. Built only in a game with sieges, from the state alone, so it shows nothing private: a queued
## Fortify is drawn by the plate itself, only in its owner's view (ProvinceRegion.set_fortify_ghost).
## make() is also the seam for the 3D board's plates (world3d/board_overlay.gd, S-4's): add FortChip.make(...)
## to a plate and it reads the same.

const FONT_SIZE := 12
const BAR_HEIGHT := 7.0

var province_id := ""
var kind := ""  # FortView.state_of: "besieged", "breached", "building", "quiet"
var besieged := false
var label: Label
var walls_bar: WallsBar = null  # null on a construction site with no fort yet
var works_label: Label = null  # "1/3" beside the scaffold glyph while a level is being built


## The chip for `province_id`, or null when there is nothing to show (no sieges, or no fort and no site).
## `seats` picks the besieger's colour (UiPalette.seat_order).
## `open` gets the codex key on a right-click (or F1) over the chip.
static func make(state: GameState, province_id: String, seats: Array = [], open: Callable = Callable()) -> FortChip:
	var p := state.find_province(province_id) if state != null else null
	if p == null or not state.sieges or (p.fort_level <= 0 and p.works.is_empty()):
		return null
	var chip := FortChip.new()
	chip.setup(state, p, seats, open)
	return chip


func setup(state: GameState, p: Province, seats: Array, open: Callable = Callable()) -> void:
	province_id = p.id
	name = "FortChip"
	kind = FortView.state_of(state, p.id)
	besieged = SiegeRules.siege_stands(state, p.id) and p.fort_level > 0
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var edge := UiPalette.KEYLINE_INK
	var besieger := SiegeRules.besieging_faction(state, p.id)
	if besieged:
		edge = UiPalette.faction_color(seats if not seats.is_empty() else UiPalette.seat_order(state), besieger)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.KEYLINE_INK, 0.72)
	style.border_color = edge
	style.set_border_width_all(2 if besieged else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 4
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(_glyph("tower" if p.fort_level > 0 else "scaffold", UiPalette.TEXT_SECONDARY))
	label = Label.new()
	label.name = "LevelLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var works_text := ""
	if not p.works.is_empty():
		var to := int(p.works.get("to", 0))
		var turns := int(SiegeRules.level_data(to).turns)
		works_text = "%d/%d" % [turns - int(p.works.get("left", 0)), turns]
	if p.fort_level <= 0:
		label.text = "%s %s" % [SiegeRules.level_name(int(p.works.get("to", 1))), works_text]
	else:
		label.text = SiegeRules.level_name(p.fort_level) + (": breached" if p.walls <= 0 else "")
		walls_bar = WallsBar.new(p.walls, SiegeRules.walls_max(p.fort_level), BAR_HEIGHT)
		walls_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		walls_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(walls_bar)
		if p.walls <= 0:
			walls_bar.visible = false  # "breached" says it, and the plate stays narrow
			label.add_theme_color_override("font_color", UiPalette.NEGATIVE.lightened(0.2))
		if not works_text.is_empty():
			row.add_child(_glyph("scaffold", UiPalette.GILT))
			works_label = Label.new()
			works_label.name = "WorksLabel"
			works_label.text = works_text
			works_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			works_label.add_theme_font_size_override("font_size", FONT_SIZE - 1)
			works_label.add_theme_color_override("font_color", UiPalette.GILT)
			row.add_child(works_label)
	if besieged:
		row.add_child(_glyph("chevron", edge))
	tooltip_text = tooltip_for(state, p.id)
	CodexLink.attach(self, codex_for(state, p.id), open if open.is_valid() else func(_k): pass)


## What the chip's hover says: the walls breakdown (Breakdown.walls) and, under it, the siege or the work.
static func tooltip_for(state: GameState, province_id: String) -> String:
	var p := state.find_province(province_id)
	if p.fort_level <= 0:
		return TooltipText.from_breakdown(Breakdown.construction(state, province_id))
	var text := TooltipText.from_breakdown(Breakdown.walls(state, province_id))
	var more := []
	if SiegeRules.siege_stands(state, province_id):
		var who := FortView.besieger_name(state, province_id)
		if p.walls <= 0:
			more.append("Breached, with the %s outside: the battle there comes on its own this turn, in the open, unless one side leaves." % who)
		else:
			var dmg := SiegeRules.siege_damage_at(state, province_id)
			var end := SiegeRules.breach_turn(p.walls, int(dmg.total), state.current_turn + 1)
			more.append("Besieged by the %s (turn %d of the siege): the walls drop by %d a turn and reach 0 %s, %s." % [
				who, SiegeRules.turn_of_siege(state, province_id), int(dmg.total), TurnReportText.reader_end(end, state.current_turn + 1),
				FortView.IF_THEY_STAY])
		var cut := SiegeRules.cut_off_info(state, province_id)
		if bool(cut.cut_off):
			more.append("Cut off: nobody can recruit here, and its %d gold a turn goes to the %s." % [p.income, who])
	elif p.walls <= 0:
		more.append("Breached: the walls repair %d a turn while no enemy army is here." % SiegeRules.repair_amount(p.fort_level))
	if not p.works.is_empty():
		var to := int(p.works.get("to", 0))
		more.append("Building %s: %d of %d turns of work done." % [SiegeRules.fort_phrase(to),
			int(SiegeRules.level_data(to).turns) - int(p.works.get("left", 0)), int(SiegeRules.level_data(to).turns)])
	more.append("Select the province for the fort panel: walls, siege, recruits and orders.")
	return "%s\n\n%s" % [text, TooltipText.wrap_text(" ".join(more))]


## The codex entry the chip links: Siege while besieged, Construction on a bare site, Walls otherwise.
static func codex_for(state: GameState, province_id: String) -> String:
	var p := state.find_province(province_id)
	if p.fort_level <= 0:
		return "construction"
	if SiegeRules.siege_stands(state, province_id):
		return "siege"
	return "walls"


func _glyph(glyph_kind: String, colour: Color) -> Control:
	var g := Glyph.new()
	g.kind = glyph_kind
	g.colour = colour
	g.name = "Glyph_%s" % glyph_kind
	return g


## A small code-drawn mark: a crenellated tower, a scaffold lattice, or two chevrons (besieged).
class Glyph extends Control:
	var kind := "tower"
	var colour := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match kind:
			"tower":
				var pts := PackedVector2Array([Vector2(1, h - 1), Vector2(1, 2), Vector2(4, 2), Vector2(4, 4), Vector2(w * 0.5 - 1, 4),
					Vector2(w * 0.5 - 1, 2), Vector2(w * 0.5 + 1, 2), Vector2(w * 0.5 + 1, 4), Vector2(w - 4, 4), Vector2(w - 4, 2),
					Vector2(w - 1, 2), Vector2(w - 1, h - 1)])
				draw_colored_polygon(pts, colour)
				var closed := pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, UiPalette.KEYLINE_INK, 1.0, true)
			"scaffold":
				for x in [2.0, w - 2.0]:
					draw_line(Vector2(x, 1), Vector2(x, h - 1), colour, 1.5)
				for y in [3.0, h * 0.5 + 1.0, h - 2.0]:
					draw_line(Vector2(1, y), Vector2(w - 1, y), colour, 1.5)
				draw_line(Vector2(2, h - 2), Vector2(w - 2, 3), colour, 1.0)
			"chevron":
				for k in 2:
					var y := 2.0 + k * 5.0
					draw_polyline(PackedVector2Array([Vector2(1, y + 4), Vector2(w * 0.5, y), Vector2(w - 1, y + 4)]), colour, 2.0, true)
