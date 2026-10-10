## The 2D over the 3D board (design/3D_DIRECTION.md 3.3, "text is never in 3D"): small Controls and
## drawings projected from the world every frame, at native resolution, through the board's project().
## Kept minimal, because the 3D armies are the markers (the critic's warning):
##   * each province's plate (UX-2's label diet, see _build_province_plates): its name, its owner's emblem and a crown on a
##     capital, always, with the marks that warn (cut off, besieged, an heir countdown, a Sworn Vassals pennant); its gold,
##     garrison and walls (an icon and a number each) and its enchantments on hover, keyboard focus or selection. The plate
##     itself carries the province's tooltip, with its sight level in words, and the codex link;
##   * each army's count plate above its formation: the seat emblem and the unit count, the 2D badge's
##     tooltip and codex link, a click selects the army (a ruler's plate wears the gilt ring);
##   * the order arrows: every queued move drawn as a ribbon along the roads it marches (a King's Roads
##     move bends through its middle province's centre, ringed in gilt), and a dashed preview of the
##     move a click would order while you hover;
##   * during a turn's playback: a clash marker at each battle, the phase's caption (Movement, Battles,
##     Captures, Recruits, as the turn report's headings) with what is happening, and the playback bar
##     (its phases, speed, skip);
##   * M3a.2: a gathered army's plate carries a march mark (ordered to march: it waits at the gate); a
##     ghost block's plate the gold left; the fortress close-up's chip (Esc or zoom out to leave) and a
##     compass while the view is turned;
##   * the board's legend in the corner, whose tooltip explains every mark on the land;
##   * M3c S-4, in a game with sieges: each plate carries the fort chip (FortChip, S-3's: the level, the walls bar
##     marking the storm steps, the besieger's chevrons, a site's turns of work), a province's tooltip says what the
##     board shows at its fort (SiegeBoard.describe), the legend explains the kits, damage looks, scaffolding, camp
##     rings, siege works, chevrons and packed garrisons, and a queued Fortify's ghost scaffold carries a plate.
## Reads the map screen (state, selection, orders, regions' marks) and never changes the game.
extends Control

const Terrain3D := preload("res://world3d/terrain3d.gd")
const Playback := preload("res://world3d/playback.gd")
const Models := preload("res://world3d/models.gd")
const Choreo := preload("res://world3d/choreo.gd")
const SiegeBoard := preload("res://world3d/siege_board.gd")
const Vision := preload("res://world3d/vision.gd")
const EnchantDecals := preload("res://world3d/enchant_decals.gd")
const ARROW := Color("#FFFFFF")
const ARROW_HALO := Color(0.102, 0.086, 0.071, 0.85)
const LEGEND := "The 3D board, what you see:\n- A province's colour wash and inner border: its owner, in their player colour. Its plate (name, owner's emblem, a crown on a capital) shows what warns (cut off, besieged, an heir countdown) and, on hover, Tab focus or selection, its gold, garrison and walls.\n- A white band inside a province: the one you selected. A cream band: the one under the mouse.\n- A soft gilt glow at the edges: where your selected army can march this turn.\n- A dashed gilt band: a King's Roads destination two provinces away.\n- Figures: each army as blocks of its units (a block per unit type, %s), its commander and banner bearer at the back. The plate above gives the exact count.\n- In the woods every block stands on a tray in its owner's colour (a gilt ring for a ruler's army), so woods-green figures never pass for trees.\n- Zoomed far out, each army becomes a stand: a base in its owner's colour (a gilt ring for a ruler's army), its banner, and one figure for each of its three most numerous unit types, under its count plate. Zoom in and the blocks come back.\n- A fortress's muster yard: its armies stand a block to a slot (a capital holds 6 blocks), facing the gate. An army the yard can't hold musters in the war camp outside the walls: tents, a fire and its smoke. A big camp means a big muster: war is coming.\n- Translucent figures in a yard: the recruits you queued, in the slot each will take. Only you see them.\n- An army in a column at its gate (or the edge of its province), facing a road, with a gilt arrow on its plate: one you ordered to march. It leaves when the turn ends. Only you see it gathered.\n- White arrows along the roads: your queued moves.\n- During a turn's playback the captions follow the turn report's phases: Movement, Battles, Captures, Recruits. Crossed swords mark a battle: the lines trade blows and the fallen lie where they fell. A capture's colour sweeps out from the arriving column.\n- View fortress (in the recruit panel) or a double-click on a fortress: a close-up of its yard. Esc or zooming out leaves it.%s\n\nDrag or WASD to pan, the wheel (or a pinch or two-finger scroll on a trackpad) to zoom, double-click to glide to a province, C your capital, F the whole map, L Look A or B. Settings can switch to the 2D map."

var board: Control ## board3d.gd
var _plates := {} ## province id -> {"root": _Plate, "name": Label, "dot": SeatEmblem, "glyph": Control, "pennant": Control, "badge": Label, "chip": FortChip or null (only while it warns),
## "cut": the cut-off mark or null, "marks": the row of always-on marks or null, "detail": the hover box, "parts": {part: Control}, "garrison": the garrison stat}
## M3c S-4: the forts and sieges part of the legend (a game with sieges), between the close-up line and the keys.
const SIEGE_LEGEND := "\n\nForts and sieges (M3c preview):\n- A fort's kit shows its level: a palisade (a ring of stakes round a small yard), a keep (a walled fort), a citadel (a capital's fortress). Each level is drawn bigger than the one below, so from the whole-map view the palisade is the smallest, the keep in the middle and the citadel the biggest. A fort someone built wears its builder's kit; a captured fort keeps its look and flies its new owner's colours. Its plate gives the exact walls (and the level, with the besieger's chevrons, while it is besieged, breached or being built) on hover.\n- Damaged walls: one step of 3 wall strength lost knocks a corner of the gate-side wall down; two steps (battered) knock it lower, with smoke, fire and rubble at its foot; at 0 the whole gate side is down to its footing, rubble in the gap: breached. The look changes exactly where a storm's defense does.\n- Scaffolding round a fort: a level being built. The new walls rise inside it as the work is done (solid up to the turns of work done, faint above). Translucent scaffolding is a Fortify you queued: only you see it.\n- A besieged fort: the besiegers camp in a ring round its walls (a tent and a fire behind each army, facing the walls), their siege works stand before the gate (ladders and mantlets, or a mound, stakes and logs), the siege engines they carry stand at the walls, and chevron banners in their colour are planted round the walls. The garrison stands packed inside, tighter the bigger it is; what doesn't fit packs at the gate.\n- During a turn's playback, Sieges: the camps go up, the camp and engines strike the walls in a burst of dust and the damage look changes; a breach collapses the gate side and shakes the camera; a lifted siege folds its camps. In the Battles, a sally's garrison files out of the gate two abreast, a storm meets at the walls, a breach battle in the gap. Recruits at any fort march in through its gate."
## IND-2 (#161): the Free Holds' part of the legend (a game with independents), between the siege lines and the keys.
const INDEPENDENTS_LEGEND := "\n\nThe Free Holds (independents):\n- A neutral province's garrison: plain local militia in undyed wool and grey (spearmen, slingers, the grey badger Wildkin of the deep woods, a grey-bearded Hold Captain at the back), on slate bases under a slate banner with a heater shield. They answer to no ruler, never move or heal, and everyone knows their strength even through fog (the plate gives the exact count). Take the province by beating them."
## UX-2: what makes a plate show its detail (hover, keyboard focus, selection, a lens), and the focus tip.
var _plate_hover := "" ## the province whose plate the mouse is over
var _plate_focus := "" ## the province whose plate has the keyboard focus
var _detail_sig := ""
var _always := {} ## part -> true: a lens shows that part of every plate (set_always)
var _focus_tip: PanelContainer = null
var _focus_label: Label = null
var _army_plates := {} ## army id -> PanelContainer
var _built_for: GameState = null
var _army_sig := ""
var _ghost_plates: Array = [] ## [PanelContainer], one per ghost block, in ghost_list() order
var _ghost_sig := ""
var _play_bar: PanelContainer
var _play_label: Label
var _speed_buttons := {}
var _legend: Label
var _legend_sieges := false
var _legend_fog := false ## M5-3: the legend's tooltip carries the fog section (a fog game)
var _fortify_plates := {} ## M3c S-4: province id -> the plate over a queued Fortify's ghost scaffold
var _caption: PanelContainer
var _caption_title: Label
var _caption_detail: Label
var _phase_label: Label
var _closeup_chip: PanelContainer
var _closeup_label: Label
var _playing := false
var _last_view := Transform3D() ## the camera when the plates were last placed
var _dirty := true ## something changed: place the plates and redraw this frame


## UX-1 (design/UX_WAR_TABLE.md §1.3): the Table (TableHud) places the playback bar, its caption and the close-up chip inside
## the board's safe area, clear of the plaques and the tray, so it positions them (hang) and this overlay leaves them alone.
## The one-line board legend at the top left is gone from the board: its hint and its whole tooltip are in the ? panel of the
## system row (legend_text() is still the text).
var hung := false


func play_bar() -> Control:
	return _play_bar


func caption_panel() -> Control:
	return _caption


func closeup_chip() -> Control:
	return _closeup_chip


func _init() -> void:
	name = "BoardOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_legend()
	_legend.visible = false  # UX-1: the ? panel has it
	_build_play_bar()
	_build_caption()
	_build_closeup_chip()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ------------------------------------------------------------------ building

## The map changed (state, selection, orders): rebuild what depends on it.
func refresh() -> void:
	var map: Control = board.map
	if map == null or map.state == null:
		return
	if _built_for != map.state:
		_built_for = map.state
		_build_province_plates()
		if map.state.sieges != _legend_sieges or Vision.active(map.state) != _legend_fog:
			_legend_tip()
	_build_fortify_plates()
	_update_province_marks()
	_dirty = true
	var sig := "%s|%s|%s|%s" % [map.state.get_instance_id(), map.selected_army_id, board.armies.armies.size(), JSON.stringify(board.armies.gathered)]
	if sig != _army_sig and not _playing:
		_army_sig = sig
		_build_army_plates()
	var ghosts: Array = board.armies.ghost_list()
	var gsig := ""
	for g in ghosts:
		gsig += "%s:%s;" % [g["province"], ",".join(PackedStringArray(g["types"]))]
	if gsig != _ghost_sig:
		_ghost_sig = gsig
		_build_ghost_plates(ghosts)
	_update_closeup_chip()
	## the legend, the playback bar, the caption and the close-up chip stay above every plate
	move_child(_legend, get_child_count() - 1)
	move_child(_play_bar, get_child_count() - 1)
	move_child(_caption, get_child_count() - 1)
	move_child(_closeup_chip, get_child_count() - 1)
	queue_redraw()


## A small dashed plate over each block of queued recruits: how many, and what they are.
func _build_ghost_plates(ghosts: Array) -> void:
	for g in _ghost_plates:
		remove_child(g)
		(g as Node).queue_free()
	_ghost_plates.clear()
	var map: Control = board.map
	var st: GameState = map.state
	for g in ghosts:
		var counts := {}
		var order: Array = []
		for t in g["types"]:
			if not counts.has(t):
				counts[t] = 0
				order.append(t)
			counts[t] += 1
		var parts: Array = []
		for t in order:
			parts.append("%d %s" % [counts[t], _unit_name(st, String(g["owner"]), t)])
		var p := st.find_province(g["province"])
		var where: String = p.name if p != null else "your capital"
		var gold_left := -1
		if map.orders != null:
			gold_left = int(map.orders.gold_after_recruits().get("gold_after", -1))
		var pc := PanelContainer.new()
		pc.name = "GhostPlate_%s" % String(g["province"])
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PANEL_BG, 0.75)
		sb.border_color = UiPalette.GILT
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		pc.add_theme_stylebox_override("panel", sb)
		var lb := Label.new()
		lb.text = ("+%d queued" % (g["types"] as Array).size()) + ("  ·  %d gold left" % gold_left if gold_left >= 0 else "")
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", UiPalette.GILT)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(lb)
		pc.mouse_filter = Control.MOUSE_FILTER_PASS
		pc.tooltip_text = TooltipText.plain("Queued recruits: %s" % ", ".join(parts),
			"They are paid when the turn ends and join your armies at %s. The translucent figures stand in the yard slot each will take (beside the army it joins, or a slot of its own; in the war camp outside the walls when the yard is full). Only you see them, and cancelling the order on the card removes them.%s" % [where,
				(" After them you have %d gold left." % gold_left) if gold_left >= 0 else ""])
		CodexLink.attach(pc, TooltipText.codex_for("recruit"), map.request_codex)
		add_child(pc)
		_ghost_plates.append(pc)


## M3c S-4: a plate over each ghost scaffold (the viewer's own queued Fortify orders): what will rise, and that only
## they see it. The order's own text is its tooltip.
func _build_fortify_plates() -> void:
	var want: Array = board.wv.fortify_ghosts()
	for pid in _fortify_plates.keys():
		if not want.has(pid):
			(_fortify_plates[pid] as Node).queue_free()
			_fortify_plates.erase(pid)
	var map: Control = board.map
	for pid in want:
		if _fortify_plates.has(pid):
			continue
		var p: Province = map.state.find_province(pid)
		var to: int = mini((p.fort_level if p != null else 0) + 1, FortData.MAX_BUILT)
		var pc := PanelContainer.new()
		pc.name = "FortifyPlate_%s" % pid
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PANEL_BG, 0.75)
		sb.border_color = UiPalette.GILT
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		pc.add_theme_stylebox_override("panel", sb)
		var lb := Label.new()
		lb.text = "%s queued" % SiegeRules.level_name(to)
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", UiPalette.GILT)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(lb)
		pc.mouse_filter = Control.MOUSE_FILTER_PASS
		var i: int = map.orders.fortify_index(pid) if map.orders != null and map.orders.has_method("fortify_index") else -1
		var order_text: String = String(map.orders.order_texts()[i]) if i >= 0 else ""
		pc.tooltip_text = TooltipText.plain("Fortify queued: %s at %s" % [SiegeRules.fort_phrase(to), p.name if p != null else pid],
			"The translucent scaffolding marks where it will rise. The gold is paid when the turn ends; from the next turn the scaffolding stands, and the walls rise inside it as the work is done. Only you see it.%s" % (("\n\n" + order_text) if not order_text.is_empty() else ""))
		CodexLink.attach(pc, "fortify", map.request_codex)
		add_child(pc)
		_fortify_plates[pid] = pc
	_dirty = true


func _unit_name(st: GameState, faction_id: String, type_id: String) -> String:
	var f := st.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, type_id) if f != null else null
	return ut.name if ut != null else "recruits"


## UX-2 (design/UX_WAR_TABLE.md 2.1, the label diet): a province plate shows what changes or warns, always, and what is static on
## hover, keyboard focus or selection.
##   always:  the name, the owner's emblem, a capital's crown, a Sworn Vassals pennant, an heir countdown, and the cut-off,
##            besieged, breached and under-construction marks
##   on hover, focus or select (the "Detail" box): gold, garrison and walls (an icon and a number each), and the enchantments
## The plate itself carries the province's tooltip (its level of sight in words, why, and the province's own) and its codex
## link (right-click, or F1 while it has the keyboard focus): they were the sight line's (SightLabel), which is gone. A lens
## that wants a part always on (UX-7: Income gold, Magic enchantments) calls set_always(part, true).
func _build_province_plates() -> void:
	for p in _plates.values():
		(p["root"] as Node).queue_free()
	_plates.clear()
	if _focus_tip != null:
		_focus_tip.visible = false
	_plate_hover = ""
	_plate_focus = ""
	_detail_sig = ""
	var map: Control = board.map
	var st: GameState = map.state
	var seats: Array = map.seat_order()
	for p in st.provinces:
		if board.wv.terrain.index_of(p.id) < 0:
			continue
		var pid: String = p.id
		var root := _Plate.new()
		root.name = "Plate_%s" % p.id
		root.overlay = self
		root.province_id = pid
		root.mouse_filter = Control.MOUSE_FILTER_PASS ## the plate carries the tooltip and the codex link; the wheel and drags go on to the board
		root.focus_mode = Control.FOCUS_ALL ## Tab reaches a plate: its detail opens and its tooltip shows (the focus tip)
		for side in ["left", "right", "top", "bottom"]:
			root.set("focus_neighbor_" + side, NodePath(".")) ## the arrow keys keep panning the board, not hopping between plates
		root.tooltip_text = " " ## the real text comes from _Plate._get_tooltip (plate_tooltip)
		root.add_theme_constant_override("separation", -2)
		root.alignment = BoxContainer.ALIGNMENT_CENTER
		root.mouse_entered.connect(func(): _plate_hover = pid)
		root.mouse_exited.connect(func():
			if _plate_hover == pid:
				_plate_hover = "")
		root.focus_entered.connect(func(): _on_plate_focus(pid, true))
		root.focus_exited.connect(func(): _on_plate_focus(pid, false))
		root.gui_input.connect(_on_plate_input.bind(pid, root))
		add_child(root)
		var row := HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 3)
		root.add_child(row)
		var glyph: Control = null
		if p.is_capital or (p.has_fort and not st.sieges): ## M3c S-4: with sieges the fort chip replaces the tower
			glyph = _Glyph.new()
			glyph.kind = "crown" if p.is_capital else "tower"
			glyph.custom_minimum_size = Vector2(20, 16)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(glyph)
		## the owner's emblem (its colour and its shape, so it never rests on colour alone): the seat's, or the slate shield of nobody
		var seat: int = UiPalette.seat_index(st, p.owner, seats)
		var dot := SeatEmblem.new(seat, SeatEmblem.Look.TOKEN, 14.0)
		dot.name = "OwnerDot"
		row.add_child(dot)
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = p.name
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 16 if p.is_capital else 15)
		name_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		name_label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
		name_label.add_theme_constant_override("outline_size", 5)
		var plaque := StyleBoxFlat.new()
		plaque.bg_color = Color(UiPalette.KEYLINE_INK, 0.55)
		plaque.set_corner_radius_all(6)
		plaque.content_margin_left = 6
		plaque.content_margin_right = 6
		plaque.content_margin_bottom = 1
		name_label.add_theme_stylebox_override("normal", plaque)
		row.add_child(name_label)
		var pl := {"root": root, "name": name_label, "dot": dot, "glyph": glyph, "pennant": null, "badge": null, "sprout": null, "chip": null, "cut": null,
			"marks": null, "detail": null, "parts": {}, "garrison": null}
		_plates[p.id] = pl
		## the marks that warn, always: cut off (a siege mark and the arrow to the besieger's colour), and the fort chip while it
		## is besieged, breached or being built (its level, its walls and its chevrons; a quiet fort's walls are on hover)
		if st.sieges and SiegeRules.is_cut_off(st, p.id):
			var mark := _CutMark.new()
			mark.name = "CutMark"
			mark.colour = UiPalette.owner_color(st, SiegeRules.besieging_faction(st, p.id), seats)
			mark.custom_minimum_size = Vector2(26, 14)
			mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mark.mouse_filter = Control.MOUSE_FILTER_PASS
			mark.tooltip_text = TooltipText.plain("Cut off", "%s is besieged and cut off: its %d gold a turn goes to the %s (the arrow, in their colour), and nobody can recruit there until the siege is lifted." % [
				p.name, p.income, FortView.besieger_name(st, p.id)])
			CodexLink.attach(mark, "cut_off", map.request_codex)
			_marks_row(pl).add_child(mark)
			pl["cut"] = mark
		var chip: FortChip = FortChip.make(st, p.id, seats, map.request_codex)
		if chip != null and FortView.state_of(st, p.id) in ["besieged", "breached", "building"]:
			chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_marks_row(pl).add_child(chip)
			pl["chip"] = chip
		elif chip != null:
			chip.free() ## a quiet fort's level is its model's, and its walls are the detail's: no chip until it warns
		## the detail: icon and number for the gold, the garrison and the walls, then the enchantments
		var detail := VBoxContainer.new()
		detail.name = "Detail"
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.add_theme_constant_override("separation", -1)
		detail.alignment = BoxContainer.ALIGNMENT_CENTER
		root.add_child(detail)
		pl["detail"] = detail
		var stats := PanelContainer.new()
		stats.name = "Stats"
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.KEYLINE_INK, 0.7)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		stats.add_theme_stylebox_override("panel", sb)
		detail.add_child(stats)
		var stat_row := HBoxContainer.new()
		stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat_row.add_theme_constant_override("separation", 8)
		stats.add_child(stat_row)
		var income := Breakdown.province_income(st, p.id)
		var gold := _stat("gold", "gold", UiPalette.GILT, "%d" % int(income.total), TooltipText.from_breakdown(income),
			TooltipText.codex_for("province_income", income), map)
		gold.get_child(1).name = "IncomeLabel"
		gold.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				board.map.select_province(pid)
				gold.accept_event())
		stat_row.add_child(gold)
		pl["parts"]["gold"] = gold
		var gar := _stat("garrison", "garrison", UiPalette.TEXT_PRIMARY, "", "", "defended", map)
		stat_row.add_child(gar)
		pl["parts"]["garrison"] = gar
		pl["garrison"] = gar
		if st.sieges and p.fort_level > 0:
			var walls := _stat("walls", "walls", UiPalette.TEXT_SECONDARY, "%d/%d" % [p.walls, SiegeRules.walls_max(p.fort_level)], FortChip.tooltip_for(st, p.id),
				FortChip.codex_for(st, p.id), map)
			if p.walls <= 0:
				(walls.get_child(1) as Label).add_theme_color_override("font_color", UiPalette.NEGATIVE.lightened(0.2))
			stat_row.add_child(walls)
			pl["parts"]["walls"] = walls
		stats.visible = stat_row.get_child_count() > 0
		## M5-8: the enchantment badges (wards, curses, Far Sight), the same as on the 2D map's plate
		var ench := EnchantmentBadges.make(st, p.id, map.viewing_faction_id, map.request_codex)
		if ench != null:
			ench.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			detail.add_child(ench)
			pl["parts"]["enchantments"] = ench
	update_sight()


## One stat of the detail: a 16 px icon (tinted by `colour`, as UiIcons are masks) and its number, with a hover and a codex link.
func _stat(part: String, icon: String, colour: Color, text: String, tip: String, codex: String, map: Control) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "Stat_%s" % part
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var tr := TextureRect.new()
	tr.name = "Icon"
	tr.texture = UiIcons.icon(icon, UiIcons.SIZE_SMALL)
	tr.modulate = colour
	tr.custom_minimum_size = Vector2(UiIcons.SIZE_SMALL, UiIcons.SIZE_SMALL)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var lb := Label.new()
	lb.name = "Number"
	lb.text = text
	lb.add_theme_font_override("font", UiFonts.number())
	lb.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	lb.add_theme_color_override("font_color", colour)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)
	box.tooltip_text = tip
	CodexLink.attach(box, codex, map.request_codex)
	return box


## The row of marks that warn, under the name; made when the first mark comes.
func _marks_row(pl: Dictionary) -> HBoxContainer:
	var marks: HBoxContainer = pl.get("marks")
	if marks == null:
		marks = HBoxContainer.new()
		marks.name = "Marks"
		marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marks.alignment = BoxContainer.ALIGNMENT_CENTER
		marks.add_theme_constant_override("separation", 3)
		(pl["root"] as Node).add_child(marks)
		(pl["root"] as Node).move_child(marks, 1) ## right under the name
		pl["marks"] = marks
	return marks


# ------------------------------------------------------------------ the plate's hover, focus and tooltip

## The plate that is a province's: a column of labels that carries the province's tooltip and codex link itself (so every plate
## says its sight and its facts on hover, and by keyboard focus in the focus tip), and draws a ring while it has the focus.
class _Plate extends VBoxContainer:
	var overlay: Control = null ## the BoardOverlay
	var province_id := ""

	func _get_tooltip(_at_position: Vector2) -> String:
		return overlay.plate_tooltip(province_id) if overlay != null else ""

	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			queue_redraw()

	func _draw() -> void:
		if has_focus():
			draw_rect(Rect2(Vector2.ZERO, size).grow(3.0), UiPalette.SELECTION, false, 2.0)


## What the plate of `pid` says on hover: the province's own tooltip (with the sight level in words and why, from Vision.words and
## FogView.province_text) and the codex link: the level's own entry when the province is not in clear sight (what the sight line's
## was), else Province's.
func plate_tooltip(pid: String) -> String:
	return province_tooltip(pid, plate_codex(pid))


## The codex key the plate links: the sight level's (vision_*, last_seen) for a glimpsed, out-of-sight or never-seen province, else
## Province's.
func plate_codex(pid: String) -> String:
	var level := String(board.vision_levels.get(pid, "")) if board != null else ""
	if level.is_empty() or level == FogRules.CLEAR:
		return TooltipText.codex_for("province")
	return String(FogView.LEVEL_CODEX.get(level, "sight"))


## A plate got or lost the keyboard focus: its detail opens, and the focus tip (a keyboard player's tooltip) follows.
func _on_plate_focus(pid: String, on: bool) -> void:
	if on:
		_plate_focus = pid
	elif _plate_focus == pid:
		_plate_focus = ""
	_poll_detail()
	_update_focus_tip()


## A plate's input: a right-click or F1 (with the focus on it) opens its codex entry; Enter or Space (with the focus) selects its
## province; a left click selects it too, as a click on the land under it does, and gives the keyboard focus back.
func _on_plate_input(event: InputEvent, pid: String, plate: Control) -> void:
	if board == null or board.map == null:
		return
	if CodexLink.is_open_click(event) or (CodexLink.is_open_key(event) and _plate_focus == pid):
		var key := String(plate.get_meta(CodexLink.META, ""))
		if not key.is_empty():
			plate.accept_event()
			board.map.request_codex(key)
		return
	if event.is_action_pressed("ui_accept") and _plate_focus == pid and not _playing:
		plate.accept_event()
		board.map.select_province(pid)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		plate.release_focus.call_deferred() ## a click is the mouse's: the keyboard focus (and its tip) stays out of it


## Part `part` ("gold", "garrison", "walls" or "enchantments") on every plate, or not (UX-7's lenses: Income shows the gold,
## Magic the enchantments). "all" is every part. The plate's own hover, focus and selection still show them all.
func set_always(part: String, on: bool) -> void:
	if on:
		_always[part] = true
	else:
		_always.erase(part)
	_detail_sig = ""
	_poll_detail()


## Whether `part` of `pid`'s plate is drawn now: always for a lens that wants it, else while the province is under the mouse, its
## plate is, it has the keyboard focus, or it is the selected province.
func shows_part(pid: String, part: String) -> bool:
	if _always.has("all") or _always.has(part):
		return true
	return plate_active(pid)


## True while a plate is hovered (its province under the mouse, or its plate), focused or selected: the plate of a province
## the player is looking at shows its detail.
func plate_active(pid: String) -> bool:
	if board == null or board.map == null:
		return false
	return pid == board.hover_id or pid == _plate_hover or pid == _plate_focus or pid == String(board.map.selected_province_id)


## Looks at what makes a plate show its detail (the province under the mouse, its plate, the focus, the selection) and shows or
## hides it when that changed. Called every frame (a few string compares), and when the focus or a lens changes.
func _poll_detail() -> void:
	if board == null or board.map == null or _plates.is_empty():
		return
	var sig := "%s|%s|%s|%s|%s" % [board.hover_id, _plate_hover, _plate_focus, board.map.selected_province_id, _always.keys()]
	if sig == _detail_sig:
		return
	_detail_sig = sig
	for id in _plates.keys():
		var pl: Dictionary = _plates[id]
		var any := false
		var parts: Dictionary = pl["parts"]
		for part in parts.keys():
			var on := shows_part(String(id), String(part))
			(parts[part] as Control).visible = on
			any = any or on
		var detail: Control = pl["detail"]
		detail.visible = any
		var stats: Control = detail.get_node_or_null("Stats")
		if stats != null:
			stats.visible = (parts.has("gold") and (parts["gold"] as Control).visible) or (parts.has("garrison") and (parts["garrison"] as Control).visible) \
				or (parts.has("walls") and (parts["walls"] as Control).visible)
		(pl["root"] as Control).reset_size()
	_dirty = true


## The focus tip: the focused plate's tooltip drawn on the board, because a keyboard player has no hover. One panel under the plate.
func _update_focus_tip() -> void:
	if _plate_focus.is_empty() or not _plates.has(_plate_focus):
		if _focus_tip != null:
			_focus_tip.visible = false
		return
	if _focus_tip == null:
		_focus_tip = PanelContainer.new()
		_focus_tip.name = "FocusTip"
		_focus_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PANEL_BG, 0.96)
		sb.border_color = UiPalette.SELECTION
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		_focus_tip.add_theme_stylebox_override("panel", sb)
		_focus_label = Label.new()
		_focus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_focus_label.custom_minimum_size = Vector2(380, 0)
		_focus_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		_focus_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		_focus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_tip.add_child(_focus_label)
		add_child(_focus_tip)
	_focus_label.text = plate_tooltip(_plate_focus)
	_focus_tip.visible = true
	_focus_tip.reset_size()
	move_child(_focus_tip, get_child_count() - 1)
	_dirty = true


## The focus tip under its plate, kept inside the board (the plate moves with the camera).
func _place_focus_tip() -> void:
	if _focus_tip == null or not _focus_tip.visible or not _plates.has(_plate_focus):
		return
	var root: Control = _plates[_plate_focus]["root"]
	if _focus_tip.size.x <= 1.0:
		_focus_tip.reset_size()
	var at := Vector2(root.position.x + root.size.x * 0.5 - _focus_tip.size.x * 0.5, root.position.y + root.size.y + 6.0)
	at.x = clampf(at.x, 8.0, maxf(8.0, size.x - _focus_tip.size.x - 8.0))
	if at.y + _focus_tip.size.y > size.y - 8.0: ## no room below: above the plate
		at.y = maxf(8.0, root.position.y - _focus_tip.size.y - 6.0)
	_focus_tip.position = at.round()


## The garrison of `pid` as the viewer may state it: {"count", "approx", "known", "text", "armies"}. The armies standing in the province
## that are its owner's (a neutral province's: the Free Holds' garrison), read from the state the board shows, which in a fog game is the
## viewer's view: a rival's garrison in clear sight is exact, glimpsed it is the plate's "≈" estimate, and out of sight it is not known
## ("?"), never what is really there.
func garrison_of(st: GameState, pid: String, level: String) -> Dictionary:
	var out := {"count": 0, "approx": false, "known": true, "text": "0", "armies": 0}
	var p := st.find_province(pid)
	if p == null:
		return out
	if level == FogRules.VEILED or level == FogView.NEVER:
		out.known = false
		out.text = "?"
		return out
	var owner_id: String = p.owner if not p.owner.is_empty() else IndependentData.FACTION_ID
	for a in st.armies:
		if a.location != pid or a.owner != owner_id or Vision.is_memory(a):
			continue
		out.armies += 1
		if Vision.is_stand_in(a) and String(a.seen.get("level", "")) == FogRules.GLIMPSE:
			out.approx = true
			out.count += int((a.seen.get("total", {}) as Dictionary).get("shown", a.units.size()))
		else:
			out.count += a.units.size()
	out.text = ("≈%d" if out.approx else "%d") % out.count
	return out


## The words of the garrison stat's hover: how many units stand there, how sure the viewer is, what it is for.
func garrison_tooltip(st: GameState, pid: String, g: Dictionary) -> String:
	var p := st.find_province(pid)
	var where: String = p.name if p != null else "the province"
	if not bool(g.known):
		return TooltipText.plain("Garrison: not known", "You can't see %s now, so you can't say who stands in it. A rival's armies out of sight show only as grey ghosts of what you last saw. Land in clear sight shows its garrison exactly." % where)
	var body := "%s units stand in %s, in %s, defending it." % [("About %d" % int(g.count)) if bool(g.approx) else str(int(g.count)), where,
		TooltipText.count(int(g.armies), "army", "armies")]
	if int(g.armies) == 0:
		body = "No army stands in %s: an enemy that marches in takes it without a battle." % where
	elif bool(g.approx):
		body += " You glimpse them, so the number is rounded."
	return TooltipText.plain("Garrison: %s" % String(g.text), body)


## The plates follow the ground's sight (Board3D._sync_vision): the garrison stat's number and words are the viewer's, level by level.
## Nothing is printed under a plate any more: the ground's four looks tell the levels apart, and the plate's hover names them.
func update_sight() -> void:
	if board == null or board.map == null or board.map.state == null:
		return
	var st: GameState = board.map.state
	for id in _plates.keys():
		var pl: Dictionary = _plates[id]
		var level := String(board.vision_levels.get(id, ""))
		var gar: Control = pl.get("garrison")
		if gar != null:
			var g := garrison_of(st, String(id), level)
			(gar.get_node("Number") as Label).text = String(g.text)
			gar.tooltip_text = garrison_tooltip(st, String(id), g)
			CodexLink.attach(gar, "defended", board.map.request_codex)
			pl["garrison_facts"] = g
		(pl["root"] as Control).set_meta(CodexLink.META, plate_codex(String(id)))
		(pl["root"] as Control).reset_size()
	_detail_sig = ""
	_poll_detail()
	_update_focus_tip()
	_dirty = true


## The map's Sworn Vassals pennants and heir countdowns, mirrored onto the plates (their tooltips are
## the regions' own, codex links included).
func _update_province_marks() -> void:
	var map: Control = board.map
	for id in _plates.keys():
		var pl: Dictionary = _plates[id]
		var region = map.regions.get(id)
		if region == null:
			continue
		var want_pennant: bool = region.vassal_marker != null
		if want_pennant and pl["pennant"] == null:
			var pen := _Pennant.new()
			pen.custom_minimum_size = Vector2(22, 24)
			pen.mouse_filter = Control.MOUSE_FILTER_PASS
			(pl["root"].get_child(0) as Control).add_child(pen)
			pl["pennant"] = pen
		if pl["pennant"] != null:
			var pen2: Control = pl["pennant"]
			pen2.visible = want_pennant
			if want_pennant:
				pen2.seat = region.vassal_seat
				pen2.tooltip_text = region.vassal_marker.tooltip_text
				pen2.set_meta(CodexLink.META, CodexLink.key_at(region.vassal_marker))
				if not pen2.has_meta("hooked"):
					pen2.set_meta("hooked", true)
					pen2.gui_input.connect(func(e: InputEvent):
						if CodexLink.is_open_click(e) and pen2.has_meta(CodexLink.META):
							map.request_codex(String(pen2.get_meta(CodexLink.META))))
				pen2.queue_redraw()
		var wm: Control = region.wild_marker if "wild_marker" in region else null
		if wm != null and pl.get("sprout") == null:
			var sp := _Sprout.new()
			sp.custom_minimum_size = Vector2(20, 22)
			sp.mouse_filter = Control.MOUSE_FILTER_PASS
			(pl["root"].get_child(0) as Control).add_child(sp)
			sp.gui_input.connect(func(e: InputEvent):
				if CodexLink.is_open_click(e) and sp.has_meta(CodexLink.META):
					map.request_codex(String(sp.get_meta(CodexLink.META))))
			pl["sprout"] = sp
		if pl.get("sprout") != null:
			var sp2: Control = pl["sprout"]
			sp2.visible = wm != null
			if wm != null:
				sp2.tooltip_text = wm.tooltip_text
				sp2.set_meta(CodexLink.META, CodexLink.key_at(wm))
		var cb: Label = region.countdown_badge
		if cb != null and pl["badge"] == null:
			var b := Label.new()
			b.name = "CountdownBadge"
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_color_override("font_color", UiPalette.GILT)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(UiPalette.PANEL_BG, 0.92)
			style.border_color = UiPalette.GILT
			style.set_border_width_all(1)
			style.set_corner_radius_all(6)
			style.content_margin_left = 5
			style.content_margin_right = 5
			b.add_theme_stylebox_override("normal", style)
			b.mouse_filter = Control.MOUSE_FILTER_PASS
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_marks_row(pl).add_child(b) ## UX-2: the heir countdown is one of the marks that are always on
			pl["badge"] = b
		if pl["badge"] != null:
			var b2: Label = pl["badge"]
			b2.visible = cb != null
			if cb != null:
				b2.text = cb.text
				b2.tooltip_text = cb.tooltip_text
				b2.set_meta(CodexLink.META, CodexLink.key_at(cb))


func _build_army_plates() -> void:
	for p in _army_plates.values():
		remove_child(p)
		(p as Node).queue_free()
	_army_plates.clear()
	var map: Control = board.map
	var st: GameState = map.state
	var seats: Array = map.seat_order()
	for a in st.armies:
		var seat: int = UiPalette.seat_index(st, a.owner, seats)
		var col: Color = UiPalette.seat_color(seat)
		var selected: bool = a.id == map.selected_army_id
		var pc := PanelContainer.new()
		pc.name = "ArmyPlate_%s" % a.id.validate_node_name()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PANEL_BG, 0.9)
		sb.border_color = UiPalette.SELECTION if selected else col
		sb.set_border_width_all(3 if selected else 2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 4
		sb.content_margin_right = 6
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		if a.ruler != null:
			## the ruler's second, gilt ring (STYLE_BIBLE.md 2.4)
			sb.shadow_color = UiPalette.GILT
			sb.shadow_size = 3
		pc.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(hb)
		var em := SeatEmblem.new(seat, SeatEmblem.Look.TOKEN, 15.0)
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(em)
		var lb := Label.new()
		lb.text = plate_text(st, a)
		lb.add_theme_font_size_override("font_size", 15)
		lb.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lb)
		if Vision.is_memory(a):
			pc.modulate = Color(0.78, 0.78, 0.82, 0.78) ## M5-3: a grey plate for a grey ghost, as the 2D badge is
		if board.armies.gathered.has(a.id):
			## ordered to march: it waits gathered at the gate (only its player sees this)
			var mk := _MarchMark.new()
			mk.name = "MarchMark"
			mk.custom_minimum_size = Vector2(16, 14)
			mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(mk)
		pc.tooltip_text = army_tooltip(a.id, false)
		pc.mouse_filter = Control.MOUSE_FILTER_PASS  ## the wheel and drags go on to the board
		pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		CodexLink.attach(pc, "ruler_army" if a.ruler != null else TooltipText.codex_for("army_units", Breakdown.army_units(st, a.id)), map.request_codex)
		var aid: String = a.id
		pc.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				board.click_army(aid)
				pc.accept_event())
		add_child(pc)
		_army_plates[a.id] = pc


# ------------------------------------------------------------------ tooltips

## The words on an army's plate: its exact number, or (M5-3, a rival in your view) the estimate ("≈20"), a remembered army's
## "≈10 · 3 turns ago", or "Ruler" / "Ruler · 3 turns ago" for a rival ruler.
func plate_text(st: GameState, a: Army) -> String:
	if a.ruler != null:
		return RulerPanel.badge_text(a) + (" · %s" % Vision.ago_text(st, int(a.seen.get("turn", 0))) if Vision.is_memory(a) else "")
	if Vision.is_stand_in(a):
		if a.units.is_empty() and a.commander != null:
			return a.commander.type.name ## a further commander's stand-in: the commander alone
		if String(a.seen.get("level", "")) != FogRules.CLEAR:
			return FogView.badge_text(st, a)
	return str(a.units.size())


## M5-3: what the board says of a rival army by its figures: a glimpse's blocks come from a rounded number, a memory is a ghost.
func fog_note(a: Army) -> String:
	if not Vision.is_stand_in(a):
		return ""
	match String(a.seen.get("level", "")):
		FogRules.GLIMPSE:
			return "Its figures stand in a block per unit type, drawn from the estimate on the plate: you glimpse it, so the real army is a little bigger or smaller, and there may be more you can't see."
		FogData.MEMORY:
			return "A grey ghost of what you saw there %s. It fades a step every %d turns, and the army may have moved on: a yard or a province under the veil shows only ghosts." % [
				Vision.ago_text(board.map.state, int(a.seen.get("turn", 0))), Vision.GHOST_STEP_TURNS]
	return "In clear sight: its figures stand in a block per unit type, as many as it has."

## A province's tooltip on the 3D board: its 2D region's own tooltip (name, terrain and how it grew,
## owner, the King's Roads or Forest Stride note when it is a road destination, its codex link), with the
## 2D marks replaced by the 3D board's in words, plus its income's breakdown lines.
func province_tooltip(pid: String, link_key: String = "") -> String:
	var map: Control = board.map
	var st: GameState = map.state
	var p := st.find_province(pid)
	var region = map.regions.get(pid)
	if p == null or region == null:
		return ""
	var seats: Array = map.seat_order()
	var seat: int = UiPalette.seat_index(st, p.owner, seats)
	var marks := "Neutral: no colour wash." if seat < 0 else "Player %d's province: %s wash and inner border, %s emblem on its armies' plates." % [
		seat + 1, UiPalette.seat_color_name(seat), SeatEmblem.shape_of(seat)]
	if p.is_capital:
		marks += " Capital (the crown, and the fortress whose yard musters its armies)."
	elif p.has_fort:
		marks += " Fort (the tower)."
	var text: String = String(region.tooltip_text)
	var at := text.rfind("\n\nCodex: ")
	if at >= 0:
		text = text.substr(0, at)
	text = text.replace(TooltipText.wrap_text(region.marks_text(p)), TooltipText.wrap_text(marks))
	text = text.replace(region.marks_text(p), marks)
	text = text.replace("dashed gilt ring", "dashed gilt band").replace("Click to see its terrain, income and armies.",
		"Click to see its terrain, income and armies; double-click to glide there.")
	## the income's breakdown lines (its long explanation is on the plate's gold, with the income's codex link)
	var income: Dictionary = Breakdown.province_income(st, pid).duplicate(true)
	income["description"] = ""
	text += "\n\n" + TooltipText.from_breakdown(income).strip_edges()
	## M3c S-4: what the board shows at its fort, in words (its kit, damage look, scaffolding, the camp ring)
	var fort_words := SiegeBoard.describe(st, pid, FortView.besieger_name(st, pid) if SiegeRules.is_besieged(st, pid) else "")
	if not fort_words.is_empty():
		text += "\n\n" + TooltipText.wrap_text("On the board: " + fort_words)
	var sight_words := Vision.words(String(board.vision_levels.get(pid, ""))) ## M5-3: how the ground shows its sight level
	if not sight_words.is_empty():
		text += "\n\n" + TooltipText.wrap_text("On the board: " + sight_words)
	return CodexLink.with_link(text, link_key if not link_key.is_empty() else TooltipText.codex_for("province"))


## M3c S-4: whether `pid`'s plate carries the fort chip (tests).
func has_fort_chip(pid: String) -> bool:
	return _plates.has(pid) and _plates[pid].get("chip") != null


## M3c S-4: whether `pid`'s plate carries the cut-off mark beside its gold (tests).
func has_cut_mark(pid: String) -> bool:
	return _plates.has(pid) and _plates[pid].get("cut") != null


## The legend's text for the state the board shows (the siege lines only in a game with sieges).
func legend_text() -> String:
	var st: GameState = board.map.state if board != null and board.map != null else null
	return LEGEND % [Models.block_rule_text(), (SIEGE_LEGEND if st != null and st.sieges else "") \
		+ (INDEPENDENTS_LEGEND if st != null and st.independents else "") + Vision.legend_lines(st) + EnchantDecals.legend_lines(st)] ## M5-9: magic's lines


## An army's tooltip: its 2D badge's own (its units' breakdown or the ruler's summary, whose it is, a
## heal forecast when Hallowed Land or the Forges will heal it), with how to read its figures.
func army_tooltip(aid: String, with_link: bool = true) -> String:
	var map: Control = board.map
	var st: GameState = map.state
	var a: Army = st.find_army(aid)
	if a == null:
		return ""
	var key: String = "ruler_army" if a.ruler != null else TooltipText.codex_for("army_units", Breakdown.army_units(st, a.id))
	var text := ""
	var region = map.regions.get(a.location)
	var badge: Control = region.army_box.get_node_or_null("Army_%s" % a.id.validate_node_name()) if region != null else null
	if badge != null:
		text = String(badge.tooltip_text)
		var at := text.rfind("\n\nCodex: ")
		if at >= 0:
			text = text.substr(0, at)
		text = text.replace(" badge, ", " plate, ").replace("outside the badge", "on the plate")
	else:
		text = RulerPanel.summary(st, a) if a.ruler != null else TooltipText.from_breakdown(Breakdown.army_units(st, a.id))
	if Vision.is_stand_in(a):
		if a.ruler == null:
			text += "\n\n" + TooltipText.wrap_text("Blocks: %s." % Models.block_rule_text())
		text += "\n\n" + TooltipText.wrap_text(fog_note(a))
	elif a.ruler == null:
		text += "\n\n" + TooltipText.wrap_text("Its figures stand in a block per unit type (%s); the plate has the exact number." % Models.block_rule_text())
	var where_note := standing_note(aid)
	if not where_note.is_empty():
		text += "\n\n" + TooltipText.wrap_text(where_note)
	return CodexLink.with_link(text, key) if with_link else text


## Where an army stands, in words, when the board says something by it: gathered at its gate (your march
## order), in a fortress's yard, or in the war camp outside it. "" otherwise.
func standing_note(aid: String) -> String:
	var map: Control = board.map
	var st: GameState = map.state
	var a: Army = st.find_army(aid)
	if a == null:
		return ""
	var gathered: Dictionary = board.armies.gathered
	if gathered.has(aid):
		var to := st.find_province(String(gathered[aid]))
		return "Ordered to march to %s: it has gathered in a column at %s, facing the road it will take, and leaves when the turn ends. Only you see it gathered." % [
			to.name if to != null else "its destination", "its gate" if not board.wv.yard_of(a.location, st).is_empty() else "the edge of its province"]
	var yard: Dictionary = board.wv.yard_of(a.location, st)
	if yard.is_empty():
		return ""
	var p := st.find_province(a.location)
	var pn: String = p.name if p != null else "the fort"
	## M3c S-4: a besieger in the camp ring, a garrison packed inside its walls
	if board.armies.ring_of(a.location).has(aid):
		return "It besieges %s: it camps in the ring round the walls (its tent and fire behind it, facing the walls), its side's chevron banners planted round them." % pn
	var lay: Dictionary = board.armies.layout_of(st, board.armies.plan_ctx)
	var m: Dictionary = lay["musters"].get(a.location, {})
	if m.has("overflow"):
		var inside: bool = (m.get("yard", {}) as Dictionary).has(aid)
		if SiegeRules.is_besieged(st, a.location):
			return ("The garrison of %s: it stands packed in the yard, inside the walls, the tighter the bigger the garrison." % pn) if inside else \
				("%s's yard is full, so this part of the garrison packs tight at the gate: the ground outside belongs to the besiegers." % pn)
		return ("It stands in %s's yard, inside the walls, facing the gate it will march out of." % pn) if inside else \
			("%s's yard is full, so this army musters in the war camp outside its gate (a tent behind every block)." % pn)
	if (m.get("camp", {}) as Dictionary).has(aid):
		return "%s's yard is full, so this army musters in the war camp outside its walls (a tent behind every block). A camp outgrowing its fortress is a muster getting ready for war." % pn
	return "It musters in %s's yard, a block to a slot, facing the gate it will march out of." % pn


# ------------------------------------------------------------------ every frame

func _process(_delta: float) -> void:
	if board == null or not board.prepared or board.map == null or not is_visible_in_tree():
		return
	_poll_detail() ## UX-2: a plate's detail follows the mouse, the focus and the selection
	## only when the camera moved, a turn is playing, or the map changed: an idle board costs nothing here
	var view: Transform3D = board.wv.cam_xform
	if not _dirty and not _playing and view.is_equal_approx(_last_view):
		return
	_dirty = false
	_last_view = view
	var t = board.wv.terrain
	var vp: Vector2 = size
	for id in _plates.keys():
		var pl: Dictionary = _plates[id]
		var root: Control = pl["root"]
		var i: int = t.index_of(id)
		var c: Vector2 = t.centres[i]
		var r: float = t.stage_r[i]
		## under the stage (south), so the armies' plates above it stay clear
		var s: Vector2 = board.project(c + Vector2(0, r * (0.95 if t.is_capital[i] else 1.15)), 2.0)
		if root.size.x <= 1.0:
			root.reset_size()
		root.position = (s - Vector2(root.size.x * 0.5, 0.0)).round()
		root.visible = s.x > -200 and s.x < vp.x + 200 and s.y > -60 and s.y < vp.y + 60
	_place_focus_tip()
	var placed: Array = []
	for id in _army_plates.keys():
		var pc: PanelContainer = _army_plates[id]
		if _playing:
			pc.visible = false
			continue
		var s2: Vector2 = board.army_plate_point(id)
		if s2.x < -9999:
			pc.visible = false
			continue
		if pc.size.x <= 1.0:
			pc.reset_size()
		var rect := Rect2(s2 - Vector2(pc.size.x * 0.5, pc.size.y), pc.size)
		## a simple declutter: a plate that would sit on another one moves up above it
		for k in 4:
			var hit := false
			for o in placed:
				if (o as Rect2).grow(1.0).intersects(rect):
					rect.position.y = (o as Rect2).position.y - rect.size.y - 2.0
					hit = true
			if not hit:
				break
		placed.append(rect)
		pc.position = rect.position.round()
		pc.visible = s2.x > -100 and s2.x < vp.x + 100 and s2.y > -50 and s2.y < vp.y + 50
	var ghosts: Array = board.armies.ghost_list()
	for i in _ghost_plates.size():
		var gp: PanelContainer = _ghost_plates[i]
		if i >= ghosts.size() or _playing:
			gp.visible = false
			continue
		var s3: Vector2 = board.project3(ghosts[i]["anchor"])
		if gp.size.x <= 1.0:
			gp.reset_size()
		var grect := Rect2(s3 - Vector2(gp.size.x * 0.5, gp.size.y), gp.size)
		for k in 4:
			var hit := false
			for o in placed:
				if (o as Rect2).grow(1.0).intersects(grect):
					grect.position.y = (o as Rect2).position.y - grect.size.y - 2.0
					hit = true
			if not hit:
				break
		placed.append(grect)
		gp.position = grect.position.round()
		gp.visible = s3.x > -100 and s3.x < vp.x + 100 and s3.y > -50 and s3.y < vp.y + 50
	for pid in _fortify_plates.keys():
		var fpc: PanelContainer = _fortify_plates[pid]
		var y: Dictionary = board.wv.fort_geom(pid, "palisade", String(board.wv.map_kits().get(pid, "")))
		var s4: Vector2 = board.project(y["centre"], 12.0)
		if fpc.size.x <= 1.0:
			fpc.reset_size()
		fpc.position = (s4 - Vector2(fpc.size.x * 0.5, fpc.size.y)).round()
		fpc.visible = not _playing and s4.x > -100 and s4.x < vp.x + 100 and s4.y > -50 and s4.y < vp.y + 50
	if _playing:
		_play_label.text = _play_text()
		_update_caption()
	queue_redraw()


func _draw() -> void:
	if board == null or not board.prepared or board.map == null:
		return
	var map: Control = board.map
	if not _playing and map.orders != null and map.state != null:
		for o in map.orders.orders():
			if o is MoveOrder:
				_draw_move(o.army_id, o.to, o.via if o.is_road_move() else "", false)
		## the hover preview: the move a click would order, dashed
		var army: Army = map.state.find_army(map.selected_army_id)
		var hov: String = board.hover_id
		if army != null and army.owner == map.viewing_faction_id and not hov.is_empty() and hov != army.location \
				and map.hover_panel.visible:
			var via := ""
			var dest: Dictionary = map.orders.road_destinations(army.id)
			if dest.has(hov) and not (dest[hov] as Array).is_empty():
				via = dest[hov][0]
			var here: Province = map.state.find_province(army.location)
			if (here != null and here.neighbors.has(hov)) or not via.is_empty():
				_draw_move(army.id, hov, via, true)
	if _playing:
		for c in board.armies.clashes_now():
			_draw_clash(board.project3(c["at"] + Vector3(0, 10, 0)), float(c["k"]), String(c["label"]))
	## a compass whenever the view is turned (the close-up looks in through the gate)
	var yaw: float = float(board.wv.rig.get("yaw", 0.0))
	if absf(wrapf(yaw, -180.0, 180.0)) > 2.0:
		_draw_compass(Vector2(size.x - 44.0, size.y - 52.0), deg_to_rad(yaw))


## A move along the roads: [army's province, (the way through), destination], each hop centre to the
## border crossing to the next centre, projected point by point so it lies along the land.
func _draw_move(army_id: String, to: String, via: String, preview: bool) -> void:
	var map: Control = board.map
	var army: Army = map.state.find_army(army_id)
	if army == null:
		return
	var t = board.wv.terrain
	var hops: Array = [army.location]
	if not via.is_empty():
		hops.append(via)
	hops.append(to)
	var pts := PackedVector2Array()
	for k in range(hops.size() - 1):
		if t.index_of(hops[k]) < 0 or t.index_of(hops[k + 1]) < 0:
			return
		var path: PackedVector2Array = t.road_path(hops[k], hops[k + 1])
		for q in range(path.size()):
			if k > 0 and q == 0:
				continue
			pts.append(path[q])
	## start at the edge of the army's stage, end at the edge of the destination's
	var start_r: float = t.stage_r[t.index_of(hops[0])] * 0.75
	var end_r: float = t.stage_r[t.index_of(to)] * 0.8
	var world := _trim(pts, start_r, end_r)
	var screen := PackedVector2Array()
	for p in _resample(world, 5.0):
		var s: Vector2 = board.project(p, 1.5)
		if s.x < -9999:
			return
		screen.append(s)
	if screen.size() < 2:
		return
	var tip: Vector2 = screen[screen.size() - 1]
	var back_i := screen.size() - 1
	while back_i > 0 and screen[back_i].distance_to(tip) < 22.0:
		back_i -= 1
	var dir: Vector2 = (tip - screen[back_i]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var base: Vector2 = tip - dir * 20.0
	var shaft := screen.slice(0, back_i + 1)
	shaft.append(base)
	if preview:
		_dashed(shaft, Color(UiPalette.GILT, 0.95), 5.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side * 9.0, base - side * 9.0]), Color(UiPalette.GILT, 0.95))
		return
	draw_polyline(shaft, ARROW_HALO, 12.0, true)
	draw_polyline(shaft, ARROW, 6.0, true)
	draw_colored_polygon(PackedVector2Array([tip + dir * 3.0, base + side * 15.0, base - side * 15.0]), ARROW_HALO)
	draw_colored_polygon(PackedVector2Array([tip, base + side * 11.0, base - side * 11.0]), ARROW)
	if not via.is_empty():
		var vs: Vector2 = board.project(t.centre_of(via), 1.5)
		draw_circle(vs, 11.0, UiPalette.KEYLINE_HALO)
		draw_circle(vs, 8.0, UiPalette.KEYLINE_INK)
		draw_circle(vs, 6.0, UiPalette.GILT)


static func _trim(pts: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	var lens := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total: float = lens[lens.size() - 1]
	if total <= a + b + 1.0:
		return pts
	var out := PackedVector2Array()
	out.append(_at(pts, lens, a))
	for i in range(1, pts.size() - 1):
		if lens[i] > a and lens[i] < total - b:
			out.append(pts[i])
	out.append(_at(pts, lens, total - b))
	return out


static func _at(pts: PackedVector2Array, lens: PackedFloat32Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		if d <= lens[i]:
			var seg: float = maxf(lens[i] - lens[i - 1], 0.001)
			return pts[i - 1].lerp(pts[i], (d - lens[i - 1]) / seg)
	return pts[pts.size() - 1]


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n: int = maxi(1, int(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(pts[pts.size() - 1])
	return out


func _dashed(pts: PackedVector2Array, col: Color, w: float) -> void:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if fmod(acc, 18.0) < 11.0:
			draw_line(a, b, Color(UiPalette.KEYLINE_INK, 0.7), w + 3.0, true)
			draw_line(a, b, col, w, true)
		acc += a.distance_to(b)


## A compass rose: the needle points to north on the screen (the view is turned by `yaw`).
func _draw_compass(at: Vector2, yaw: float) -> void:
	draw_circle(at, 22.0, Color(UiPalette.PANEL_BG, 0.85))
	draw_arc(at, 22.0, 0, TAU, 32, UiPalette.GILT, 1.5, true)
	var d := Vector2(sin(yaw), -cos(yaw))
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([at + d * 17.0, at + side * 5.0, at - side * 5.0]), UiPalette.NEGATIVE)
	draw_colored_polygon(PackedVector2Array([at - d * 17.0, at + side * 5.0, at - side * 5.0]), UiPalette.TEXT_SECONDARY)
	var f := get_theme_default_font()
	draw_string(f, at + d * 27.0 + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_PRIMARY)


## A battle's clash marker: crossed swords in a pulsing ring, with its label.
func _draw_clash(at: Vector2, k: float, label: String) -> void:
	if at.x < -9999:
		return
	var pulse: float = 1.0 + 0.18 * sin(k * TAU * 2.0)
	var r: float = 20.0 * pulse
	draw_circle(at, r + 3.0, Color(UiPalette.KEYLINE_INK, 0.85))
	draw_circle(at, r, Color(UiPalette.NEGATIVE.darkened(0.25), 0.92))
	draw_arc(at, r + 1.5, 0, TAU, 32, UiPalette.GILT, 2.0, true)
	for sgn in [-1.0, 1.0]:
		var d := Vector2(sgn, -1.0).normalized()
		draw_line(at - d * r * 0.62, at + d * r * 0.62, UiPalette.KEYLINE_INK, 6.0, true)
		draw_line(at - d * r * 0.62, at + d * r * 0.62, UiPalette.TEXT_PRIMARY, 3.0, true)
		var hilt: Vector2 = at - d * r * 0.42
		var side := Vector2(-d.y, d.x)
		draw_line(hilt - side * 5.0, hilt + side * 5.0, UiPalette.GILT, 3.0, true)
	var f := get_theme_default_font()
	var w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var box := Rect2(at + Vector2(-w * 0.5 - 7.0, r + 6.0), Vector2(w + 14.0, 22.0))
	draw_rect(box, Color(UiPalette.PANEL_BG, 0.92))
	draw_rect(box, UiPalette.GILT, false, 1.0)
	draw_string(f, box.position + Vector2(7.0, 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiPalette.TEXT_PRIMARY)


# ------------------------------------------------------------------ playback bar and legend

func begin_playback(plan: Dictionary, after: GameState) -> void:
	_playing = true
	_play_bar.set_meta("turn", int(plan.get("turn", after.current_turn)))
	_play_bar.set_meta("battles", (plan.get("battles", []) as Array).size())
	_play_bar.visible = true
	_closeup_chip.visible = false
	_mark_speed(board.armies.speed)
	_play_label.text = _play_text()
	_update_caption()
	queue_redraw()


func end_playback() -> void:
	_playing = false
	_play_bar.visible = false
	_caption.visible = false
	_army_sig = ""
	queue_redraw()


## The turn's phases on the playback bar ("Movement  ›  [Battles]  ›  Recruits", the one playing now in
## brackets); the caption under the bar names the phase and what is happening in it.
func _update_caption() -> void:
	var now: Dictionary = board.armies.phase_now()
	var parts: Array = []
	for p in board.armies.phases():
		parts.append(("[%s]" % p["caption"]) if not now.is_empty() and int(p["index"]) == int(now["index"]) else String(p["caption"]))
	_phase_label.text = "  ›  ".join(parts)
	_phase_label.visible = not parts.is_empty()
	if now.is_empty():
		_caption.visible = false
		return
	_caption.visible = true
	_caption_title.text = String(now["caption"])
	_caption_detail.text = String(now["detail"])
	_caption_detail.visible = not _caption_detail.text.is_empty()
	var help := String(Choreo.CAPTION_HELP.get(now["key"], ""))
	if not String(now.get("line", "")).is_empty():
		help = "%s\n\n%s" % [String(now["line"]), help] ## the turn report's own words for this battle
	_caption.tooltip_text = TooltipText.plain(String(now["caption"]), help)
	_caption.reset_size()
	if not hung:
		_caption.position = Vector2(round((size.x - _caption.size.x) * 0.5), _play_bar.position.y + _play_bar.size.y + 10.0)


## The phase the caption shows now ({} between phases, or when nothing plays).
func caption_now() -> Dictionary:
	return board.armies.phase_now() if _playing else {}


func _build_caption() -> void:
	_caption = PanelContainer.new()
	_caption.name = "PhaseCaption"
	_caption.visible = false
	_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.KEYLINE_INK, 0.62)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	_caption.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(box)
	_caption_title = Label.new()
	_caption_title.name = "CaptionTitle"
	_caption_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_title.add_theme_font_size_override("font_size", 30)
	_caption_title.add_theme_color_override("font_color", UiPalette.GILT)
	_caption_title.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	_caption_title.add_theme_constant_override("outline_size", 6)
	box.add_child(_caption_title)
	_caption_detail = Label.new()
	_caption_detail.name = "CaptionDetail"
	_caption_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_detail.add_theme_font_size_override("font_size", 17)
	_caption_detail.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	_caption_detail.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	_caption_detail.add_theme_constant_override("outline_size", 4)
	box.add_child(_caption_detail)
	add_child(_caption)


## The fortress close-up's chip at the top: which yard, and how to leave (Esc, zoom out, or its button).
func _build_closeup_chip() -> void:
	_closeup_chip = PanelContainer.new()
	_closeup_chip.name = "CloseupChip"
	_closeup_chip.visible = false
	_closeup_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.92)
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	_closeup_chip.add_theme_stylebox_override("panel", style)
	_closeup_chip.anchor_left = 0.5
	_closeup_chip.anchor_right = 0.5
	_closeup_chip.offset_top = 12
	_closeup_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_closeup_chip.add_child(row)
	_closeup_label = Label.new()
	_closeup_label.name = "CloseupLabel"
	_closeup_label.add_theme_font_size_override("font_size", 16)
	_closeup_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	_closeup_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_closeup_label)
	var leave := Button.new()
	leave.name = "LeaveCloseup"
	leave.text = "Back to the map (Esc)"
	leave.focus_mode = Control.FOCUS_NONE
	leave.add_theme_font_size_override("font_size", 15)
	leave.add_theme_color_override("font_color", UiPalette.GILT)
	leave.tooltip_text = "Leave the fortress view: the camera goes back where it was. Zooming out or pressing Esc does the same."
	leave.pressed.connect(func(): board.exit_closeup())
	row.add_child(leave)
	_closeup_chip.tooltip_text = TooltipText.plain("Fortress view",
		"A close look at this fortress's muster yard: every army stands a block to a slot, facing the gate, and an army the yard can't hold musters in the war camp outside. Each recruit you queue on the card appears at once as a translucent figure in the slot it will take; armies you ordered to march wait in a column at the gate. Esc or zooming out goes back to the map.")
	add_child(_closeup_chip)


func _update_closeup_chip() -> void:
	var pid: String = board.closeup
	_closeup_chip.visible = not pid.is_empty() and not _playing
	if pid.is_empty():
		return
	var p: Province = board.map.state.find_province(pid) if board.map != null and board.map.state != null else null
	_closeup_label.text = "Fortress view: %s's muster yard" % (p.name if p != null else "the")


func _play_text() -> String:
	var turn := int(_play_bar.get_meta("turn", 0))
	var n := int(_play_bar.get_meta("battles", 0))
	var what := "the armies march" if n == 0 else ("the armies march, and %s" % ("1 battle is fought" if n == 1 else "%d battles are fought" % n))
	return "Turn %d plays out: %s." % [turn, what]


func _build_play_bar() -> void:
	_play_bar = PanelContainer.new()
	_play_bar.name = "PlaybackBar"
	_play_bar.visible = false
	_play_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_play_bar.add_theme_stylebox_override("panel", style)
	_play_bar.anchor_left = 0.5
	_play_bar.anchor_right = 0.5
	_play_bar.offset_top = 12
	_play_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_play_bar.tooltip_text = TooltipText.plain("The turn plays out on the board",
		"The armies' moves, battles and captures of the turn that just resolved, exactly as the rules decided them: watching never changes anything. Space or a click on the land skips it, and the turn report opens next. The speed you pick is remembered.")
	add_child(_play_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_play_bar.add_child(row)
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", -2)
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(labels)
	_play_label = Label.new()
	_play_label.name = "PlaybackLabel"
	_play_label.add_theme_font_size_override("font_size", 17)
	_play_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	labels.add_child(_play_label)
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override("font_size", 14)
	_phase_label.add_theme_color_override("font_color", UiPalette.GILT)
	_phase_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var help: Array = []
	for k in Choreo.PHASES:
		help.append("%s: %s" % [Choreo.caption(k), Choreo.CAPTION_HELP[k]])
	_phase_label.tooltip_text = TooltipText.plain("The turn's phases", "They play in the turn report's order; a phase with nothing in it is skipped.\n\n" + "\n".join(help))
	labels.add_child(_phase_label)
	for v in GameSettings.PLAYBACK_SPEEDS:
		var b := Button.new()
		b.name = "Speed%d" % v
		b.text = "%d×" % v
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = "Play the turn at %d× speed. The speed is remembered for the next turns." % v
		var speed_v: int = v
		b.pressed.connect(func():
			board.set_playback_speed(float(speed_v))
			_mark_speed(float(speed_v)))
		row.add_child(b)
		_speed_buttons[v] = b
	var skip := Button.new()
	skip.name = "SkipButton"
	skip.text = "Skip (Space)"
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 15)
	skip.add_theme_color_override("font_color", UiPalette.GILT)
	skip.tooltip_text = "Skip to the end of the turn: the board shows where everything stands now, and the turn report opens."
	skip.pressed.connect(func(): board.skip_playback())
	row.add_child(skip)


func _mark_speed(v: float) -> void:
	for k in _speed_buttons.keys():
		(_speed_buttons[k] as Button).set_pressed_no_signal(is_equal_approx(float(k), v))


func _build_legend() -> void:
	_legend = Label.new()
	_legend.name = "BoardLegend"
	_legend.text = "Board: drag or WASD to pan · wheel or pinch to zoom · C your capital · F whole map  (hover for the legend)"
	_legend.add_theme_font_size_override("font_size", 13)
	_legend.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.72)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	_legend.add_theme_stylebox_override("normal", style)
	_legend.position = Vector2(10, 8)
	_legend.mouse_filter = Control.MOUSE_FILTER_PASS
	_legend_tip()
	add_child(_legend)


## The legend's tooltip for the state shown (refresh() rebuilds it when a game with sieges comes or goes).
func _legend_tip() -> void:
	var lines: Array = []
	for line in legend_text().split("\n"):
		lines.append(TooltipText.wrap_text(line) if line.begins_with("- ") or line.length() > TooltipText.WRAP else line)
	_legend.tooltip_text = "\n".join(lines)
	_legend_sieges = board != null and board.map != null and board.map.state != null and board.map.state.sieges
	_legend_fog = board != null and board.map != null and Vision.active(board.map.state)


## The march mark on a gathered army's plate: a small gilt arrow (ordered to march, waiting at the gate).
class _MarchMark extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array([c + Vector2(-6, -2), c + Vector2(1, -2), c + Vector2(1, -6), c + Vector2(7, 0),
			c + Vector2(1, 6), c + Vector2(1, 2), c + Vector2(-6, 2)])
		draw_colored_polygon(pts, UiPalette.GILT)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 1.2, true)


## A crown (a capital) or a tower (a fort), as the 2D map draws them.
class _Glyph extends Control:
	var kind := "crown"

	func _draw() -> void:
		var at := size * 0.5
		var pts: PackedVector2Array
		var col: Color = UiPalette.GILT
		if kind == "crown":
			var w := 8.0
			pts = PackedVector2Array([at + Vector2(-w, 5), at + Vector2(-w, -4), at + Vector2(-w * 0.5, 1), at + Vector2(0, -6),
				at + Vector2(w * 0.5, 1), at + Vector2(w, -4), at + Vector2(w, 5)])
		else:
			col = UiPalette.TEXT_SECONDARY
			pts = PackedVector2Array([at + Vector2(-6, 6), at + Vector2(-6, -5), at + Vector2(-3, -5), at + Vector2(-3, -2),
				at + Vector2(0, -2), at + Vector2(0, -5), at + Vector2(3, -5), at + Vector2(3, -2), at + Vector2(6, -2),
				at + Vector2(6, -5), at + Vector2(6, 6)])
		draw_colored_polygon(pts, col)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)


## M3c S-4: a cut-off province's siege mark beside its gold: a small chevron, then an arrow, in the besieger's colour.
class _CutMark extends Control:
	var colour := Color.WHITE

	func _draw() -> void:
		var c := Vector2(6, size.y * 0.5)
		var chev := PackedVector2Array([c + Vector2(-5, -1), c + Vector2(0, -5), c + Vector2(5, -1), c + Vector2(5, 3), c + Vector2(0, -1), c + Vector2(-5, 3)])
		draw_colored_polygon(chev, colour)
		var closed := chev.duplicate()
		closed.append(chev[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 1.2, true)
		var a := Vector2(14, size.y * 0.5)
		draw_line(a, a + Vector2(9, 0), UiPalette.KEYLINE_INK, 4.0)
		draw_line(a, a + Vector2(9, 0), colour, 2.0)
		draw_colored_polygon(PackedVector2Array([a + Vector2(12, 0), a + Vector2(7, -4), a + Vector2(7, 4)]), colour)


## The Wild Spreads' sprout (M4-2): the province turns to forest at the end of the turn.
class _Sprout extends Control:
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y - 3.0)
		draw_line(c, c + Vector2(0, -12), UiPalette.KEYLINE_INK, 4.0, true)
		draw_line(c, c + Vector2(0, -12), Color("#5E7F35"), 2.0, true)
		for sgn in [-1.0, 1.0]:
			var leaf := PackedVector2Array([c + Vector2(0, -8), c + Vector2(sgn * 8, -14), c + Vector2(sgn * 3, -6)])
			draw_colored_polygon(leaf, Color("#72C47A"))
			var closed := leaf.duplicate()
			closed.append(leaf[0])
			draw_polyline(closed, UiPalette.KEYLINE_INK, 1.2, true)


## The Sworn Vassals pennant (as ProvinceRegion draws it) in the joining faction's colour.
class _Pennant extends Control:
	var seat := -1

	func _draw() -> void:
		var colour := UiPalette.NEUTRAL if seat < 0 else UiPalette.seat_color(seat)
		var pole_x := 4.0
		draw_line(Vector2(pole_x, 1), Vector2(pole_x, 23), UiPalette.KEYLINE_INK, 3.0, true)
		var flag := PackedVector2Array([Vector2(pole_x + 1, 2), Vector2(21, 7), Vector2(pole_x + 1, 13)])
		draw_colored_polygon(flag, colour)
		var closed := flag.duplicate()
		closed.append(flag[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)
