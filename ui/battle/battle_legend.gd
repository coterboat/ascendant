class_name BattleLegend
extends PanelContainer
## The battle legend (M3-4, #59; design/M3_BATTLES.md §7.1): every mark on the battle screen, each row
## drawn by the same function the screen draws it with, with a one-line meaning and a link to its codex
## entry (left-click, right-click or F1). Toggled with L or the Legend button; Esc closes it.
##
## Renderer-agnostic: the legend draws whatever rows its host gives it. overlay_rows() are the marks of the
## 2D overlay both renderers share (strength bars, break notch and tags, hp bars, status glyphs, floating
## numbers, key-moment icons, emblems); field_rows() are the Simple view's own (cards, rank columns, fallen
## markers, lunges and rout slides, projectiles, impacts, dust, shake). The 3D stage passes overlay_rows()
## plus rows of its own.
##
##   var legend := BattleLegend.new()
##   legend.set_rows(BattleLegend.overlay_rows() + BattleLegend.field_rows())
##   legend.reduced_motion = true        the motion rows say what reduced motion does instead (§7.4)
##   signals codex_requested(key), close_requested
##
## A row is {"id", "title", "text", "codex" (a RulesCodex entry), "drawn_by" ("Class.function": the
## screen's own drawing function the swatch calls), "draw": Callable(canvas_item, rect)}, plus "reduced"
## (its text with reduced motion on) and "node" (a Callable making a styled node for the swatch instead,
## for marks that are labels on screen).

signal codex_requested(key: String)
signal close_requested

const SWATCH := Vector2(104, 40)
const ROW_W := 372.0
const GAP := 10.0

var rows: Array = []
var reduced_motion := false:
	set(value):
		if value == reduced_motion:
			return
		reduced_motion = value
		if not rows.is_empty():
			set_rows(rows)
var row_nodes: Array = []
var _grid: GridContainer
var _title: Label


func _init() -> void:
	name = "BattleLegend"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.text = "Legend: what every mark means"
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", UiPalette.GILT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var hint := Label.new()
	hint.text = "Click a row for its codex entry · L or Esc closes"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	head.add_child(hint)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close the legend (L or Esc)."
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(func(): close_requested.emit())
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)


## Lays the legend out in `rect` (the host's field): as many columns as fit.
func place(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	custom_minimum_size = rect.size
	_grid.columns = maxi(1, int((rect.size.x - 28.0 + GAP) / (ROW_W + GAP)))


func set_rows(p_rows: Array) -> void:
	rows = p_rows
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	row_nodes = []
	for r in rows:
		var row := HBoxContainer.new()
		row.name = "Row_%s" % String(r.id)
		row.custom_minimum_size = Vector2(ROW_W, SWATCH.y)
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var sw := Swatch.new()
		sw.draw_fn = r.draw
		sw.custom_minimum_size = SWATCH
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if r.has("node"):
			var n: Control = r.node.call()
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sw.add_child(n)
		row.add_child(sw)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(words)
		var t := Label.new()
		t.text = String(r.title)
		t.add_theme_font_size_override("font_size", 15)
		t.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(t)
		var m := Label.new()
		m.text = _text_of(r)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size.x = ROW_W - SWATCH.x - 10.0
		m.add_theme_font_size_override("font_size", 12)
		m.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(m)
		row.tooltip_text = TooltipText.plain(String(r.title), _text_of(r))
		CodexLink.attach(row, String(r.codex), codex_requested.emit)
		var key := String(r.codex)
		row.gui_input.connect(func(e: InputEvent):
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				codex_requested.emit(key))
		_grid.add_child(row)
		row_nodes.append(row)


func _text_of(r: Dictionary) -> String:
	if reduced_motion and r.has("reduced"):
		return String(r.reduced)
	return String(r.text)


## Every text on the legend (for the no-raw-ids test).
func visible_texts() -> Array:
	var out := [_title.text]
	for n in row_nodes:
		out.append((n as Control).tooltip_text)
	return out


## A swatch: calls its row's drawing function with its own rect.
class Swatch extends Control:
	var draw_fn: Callable

	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self, Rect2(Vector2.ZERO, size))


# --- the rows ---------------------------------------------------------------------------------------

static func _row(id: String, title: String, text: String, codex: String, drawn_by: String, draw: Callable, reduced: String = "",
		node: Callable = Callable()) -> Dictionary:
	var r := {"id": id, "title": title, "text": text, "codex": codex, "drawn_by": drawn_by, "draw": draw}
	if not reduced.is_empty():
		r.reduced = reduced
	if node.is_valid():
		r.node = node
	return r


static func _font(ci: CanvasItem) -> Font:
	return (ci as Control).get_theme_default_font() if ci is Control else ThemeDB.fallback_font


static func _number(ci: CanvasItem, pos: Vector2, text: String, col: Color, font_size: int) -> void:
	BattleEffects.draw_number(ci, _font(ci), {"pos": pos, "text": text, "color": col, "size": font_size, "age": 0.0, "life": 1.0})


static func _glyph_row(id: String, title: String, text: String, codex: String) -> Dictionary:
	return _row(id, title, text, codex, "BattleCard.draw_glyph", func(ci: CanvasItem, r: Rect2): BattleCard.draw_glyph(ci, id, r.get_center(), 22.0))


static func _moment_row(kind: String, text: String) -> Dictionary:
	return _row("moment_" + kind, "%s (key moment)" % String(BattleMoments.TITLES[kind]), text, "battle_key_moments", "BattleScrubber.draw_moment_icon",
		func(ci: CanvasItem, r: Rect2): BattleScrubber.draw_moment_icon(ci, kind, r.get_center(), 22.0))


## The 2D overlay both renderers draw: the top bar's strength bars and tags, hp bars, status glyphs,
## floating numbers, key-moment icons and emblems. `seat` colours the side-coloured rows.
static func overlay_rows(seat: int = 0) -> Array:
	var bar := func(ci: CanvasItem, r: Rect2, fill: float, pending: float, out: String, held: bool):
		BattleStrengthBar.paint(ci, Rect2(r.position + Vector2(2, 13), Vector2(r.size.x - 4, 14)), seat, false, fill, pending, 0.35, out, held)
	return [
		_row("emblem", "Side colour and emblem", "Each side's colour always comes with its emblem shape, on the bars, rings and cards, so colour is never the only sign.",
			"battle_formation", "SeatEmblem.draw_emblem", func(ci: CanvasItem, r: Rect2):
				SeatEmblem.draw_emblem(ci, r.get_center() - Vector2(14, 0), 11.0, seat)
				SeatEmblem.draw_emblem(ci, r.get_center() + Vector2(14, 0), 11.0, (seat + 1) % UiPalette.PLAYER_COLORS.size())),
		_row("strength_bar", "Strength bar", "The hit points a side has left of what it started with. Whoever stays further above their notch is winning.",
			"battle_strength", "BattleStrengthBar.paint", func(ci: CanvasItem, r: Rect2): bar.call(ci, r, 0.7, 0.0, "", false)),
		_row("strength_pending", "Hatched red on a bar", "Damage dealt this round that lands at the end of the round: a fighter that will fall still strikes first.",
			"battle_pending_damage", "BattleStrengthBar.paint", func(ci: CanvasItem, r: Rect2): bar.call(ci, r, 0.7, 0.2, "", false)),
		_row("notch", "Break notch", "The white line on a strength bar: the side breaks and flees once its hit points fall to it (\"breaks at 26 hp or less\").",
			"battle_strength", "BattleStrengthBar.draw_notch", func(ci: CanvasItem, r: Rect2):
				ci.draw_rect(Rect2(r.position.x + 4, r.position.y + 13, r.size.x - 8, 14), UiPalette.PANEL_RAISED)
				BattleStrengthBar.draw_notch(ci, r.get_center().x, r.position.y + 13, r.position.y + 27, false)),
		_row("tag", "Morale tag", "Under a bar after each morale check: whether the side holds or breaks, and why its morale changed (\"-4 morale: the Knight Captain fell\").",
			"battle_morale", "BattleStrengthBar.style_tag", Callable(), "", func() -> Control:
				var l := Label.new()
				l.text = "-4 morale"
				BattleStrengthBar.style_tag(l, 13)
				l.position = Vector2(0, 10)
				return l),
		_row("broke", "BROKE", "The side broke: its loss reached its break line, and its survivors flee.", "battle_morale", "BattleStrengthBar.paint",
			func(ci: CanvasItem, r: Rect2): bar.call(ci, r, 0.25, 0.0, "routed", false)),
		_row("no_one_left", "NO ONE LEFT", "Every fighter of the side fell.", "battle_morale", "BattleStrengthBar.paint",
			func(ci: CanvasItem, r: Rect2): bar.call(ci, r, 0.0, 0.0, "destroyed", false)),
		_glyph_row("iron", "Iron Discipline", "A gilt chain on the notch and on the commander: Iron Discipline holds a side that should have broken, while the commander stands.",
			"mandate_iron_discipline"),
		_row("hp_bar", "A fighter's hit points", "Green is hit points left; hatched red is damage that lands at the end of the round.", "battle_pending_damage",
			"BattleCard.draw_hp_bar", func(ci: CanvasItem, r: Rect2): BattleCard.draw_hp_bar(ci, Rect2(r.position.x + 4, r.get_center().y - 4, r.size.x - 8, 8), 7, 10, 3)),
		_glyph_row("aura_up", "Morale aura ▲", "Raises its own side's morale while it stands: a commander, Inspire or a ruler.", "battle_auras"),
		_glyph_row("aura_down", "Morale aura ▼", "Lowers every enemy side's morale while it stands: Fury or Dread.", "battle_auras"),
		_glyph_row("shield_wall", "Shield Wall", "Extra defense while another fighter of its side stands.", "trait_shield_wall"),
		_glyph_row("berserk", "Berserk", "Extra attack while wounded.", "trait_berserk"),
		_glyph_row("blood_frenzy", "Blood Frenzy", "The mandate: extra attack while wounded.", "mandate_blood_frenzy"),
		_glyph_row("pack_leader", "Pack Leader", "Extra attack from its commander while the commander stands.", "trait_pack_leader"),
		_glyph_row("shielded", "Shielded", "Ordinary enemies can't reach it this round: its front rank still stands in front of it.", "battle_formation"),
		_glyph_row("exposed", "Exposed", "Too few stand in front of it: every enemy can reach it now.", "battle_formation"),
		_row("number", "White number", "Damage of a hit, landing at the end of the round. Big hits (8 or more) get a bigger number.", "battle_hit_chance",
			"BattleEffects.draw_number", func(ci: CanvasItem, r: Rect2):
				_number(ci, r.get_center() + Vector2(-12, 7), "5", UiPalette.TEXT_PRIMARY, 18)
				_number(ci, r.get_center() + Vector2(14, 8), "9", UiPalette.TEXT_PRIMARY, 24)),
		_row("miss", "Grey \"miss\"", "The attack missed: its roll was above its hit chance.", "battle_hit_chance", "BattleEffects.draw_number",
			func(ci: CanvasItem, r: Rect2): _number(ci, r.get_center() + Vector2(0, 6), "miss", UiPalette.TEXT_SECONDARY, 16)),
		_row("heal", "Green \"+hp\"", "Hit points healed: Lifedrinker drinking back damage it dealt, or Feast of Victory after the battle.", "trait_lifedrinker",
			"BattleEffects.draw_number", func(ci: CanvasItem, r: Rect2): _number(ci, r.get_center() + Vector2(0, 6), "+3 hp", UiPalette.POSITIVE, 16)),
		_row("iron_hide", "Small grey \"-1\"", "Iron Hide took 1 damage off the hit beside it.", "trait_iron_hide", "BattleEffects.draw_number",
			func(ci: CanvasItem, r: Rect2):
				_number(ci, r.get_center() + Vector2(-8, 7), "4", UiPalette.TEXT_PRIMARY, 18)
				_number(ci, r.get_center() + Vector2(14, 9), "-1", UiPalette.TEXT_SECONDARY, 13)),
		_moment_row("first_blood", "The first fighter to fall."),
		_moment_row("charge", "A charge in round 1."),
		_moment_row("ruler_falls", "A ruler falls."),
		_moment_row("turning_point", "From here on the winner stayed further from breaking."),
		_moment_row("rout", "A side breaks or has no one left."),
	]


## The Simple view's own field: cards, rank columns, fallen markers, motion, projectiles, impacts and dust.
static func field_rows(seat: int = 0) -> Array:
	var col := UiPalette.seat_color(seat)
	var card := func(ci: CanvasItem, r: Rect2, ruler: bool, commander: bool):
		var c := Rect2(r.get_center() - Vector2(13, 18), Vector2(26, 34))
		BattleCard.draw_ground(ci, Vector2(c.get_center().x, c.end.y), Vector2(16, 4), col, ruler)
		ci.draw_rect(c.grow(-3), UiPalette.PANEL_RAISED)
		BattleCard.draw_frame(ci, c, col, ruler, commander, false)
		return c
	var proj := func(ci: CanvasItem, r: Rect2, kind: String, arc: float):
		BattleEffects.draw_projectile(ci, {"from": r.position + Vector2(4, r.size.y * 0.7), "to": r.end - Vector2(4, r.size.y * 0.3), "arc": arc,
			"kind": kind, "hit": true, "s": 0.8, "age": 0.75, "life": 1.0})
	return [
		_row("card", "A fighter", "A portrait card in its side's colour, with its emblem and a ground ring. Hover it to see what it is doing and why; click it to pin that.",
			"battle_formation", "BattleCard.draw_frame", func(ci: CanvasItem, r: Rect2): card.call(ci, r, false, false)),
		_row("ruler", "A ruler", "The outer gilt ring, a second gilt ground ring and its name plate with its hit points.", "ruler_in_battle",
			"BattleCard.draw_plate", func(ci: CanvasItem, r: Rect2):
				var c: Rect2 = card.call(ci, r, true, false)
				BattleCard.draw_plate(ci, _font(ci), Rect2(c.position.x - 20, c.position.y, c.size.x + 40, c.size.y), "King", 0.9, false, 4.0)),
		_row("commander", "A commander", "A gilt inner frame and a standard. It stands in the back line and lifts its side's morale while it stands.",
			"battle_commanders", "BattleCard.draw_standard", func(ci: CanvasItem, r: Rect2):
				var c: Rect2 = card.call(ci, r, false, true)
				BattleCard.draw_standard(ci, c.position + Vector2(5, c.size.y - 4), 12.0)),
		_row("ranks", "Rank columns", "The front rank stands nearest the centre, then the second rank, then commanders at the back. Places within a rank are only for show.",
			"battle_formation", "BattleCard.draw_frame", func(ci: CanvasItem, r: Rect2):
				for k in 3:
					var c := Rect2(r.position + Vector2(6 + k * 20, 8 + (k % 2) * 2), Vector2(14, 20))
					BattleCard.draw_frame(ci, c, col, false, k == 2, false)),
		_row("fallen", "Fallen marker", "A fighter that fell stays where it fell, grey and faded, so losses can be counted.", "battle_playback",
			"BattleCard.draw_frame", func(ci: CanvasItem, r: Rect2):
				var c := Rect2(r.get_center() - Vector2(13, 17), Vector2(26, 34))
				ci.draw_set_transform(c.get_center(), -0.21, Vector2.ONE)
				var local := Rect2(-c.size / 2.0, c.size)
				ci.draw_rect(local.grow(-3), Color(0.35, 0.35, 0.35, 0.4))
				BattleCard.draw_frame(ci, local, Color(0.5, 0.5, 0.5, 0.4), false, false, false)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)),
		_row("lunge", "Lunge", "A melee attack: the card steps toward its target and back. Every fighter attacks once a round.", "battle_rounds",
			"BattleCard.draw_frame", func(ci: CanvasItem, r: Rect2):
				var c: Rect2 = card.call(ci, r, false, false)
				_arrow(ci, Vector2(c.end.x + 2, c.get_center().y), Vector2(r.end.x - 2, c.get_center().y)),
			"A melee attack. With reduced motion, attacks play in place: no lunge."),
		_row("rout_slide", "Fleeing", "A side that broke: its cards turn and run to their back edge, fading out.", "battle_morale", "BattleCard.draw_frame",
			func(ci: CanvasItem, r: Rect2):
				var c := Rect2(r.get_center() - Vector2(4, 17), Vector2(26, 34))
				ci.draw_rect(c.grow(-3), Color(UiPalette.PANEL_RAISED, 0.5))
				BattleCard.draw_frame(ci, c, Color(col, 0.5), false, false, false)
				_arrow(ci, Vector2(c.position.x - 2, c.get_center().y), Vector2(r.position.x + 2, c.get_center().y)),
			"A side that broke. With reduced motion, its cards fade where they stand."),
		_row("bolt", "Bolt", "A Crossbowmen shot (Volley): it shoots from the second rank.", "trait_volley", "BattleEffects.draw_projectile",
			func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "bolt", 0.08)),
		_row("javelin", "Javelin", "A Fangthrowers throw (Skirmish): it can reach past the enemy's front.", "trait_skirmish", "BattleEffects.draw_projectile",
			func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "javelin", 0.18)),
		_row("arcane", "Arcane bolt", "The Ever-Regent's gilt bolt.", "ruler_ever_regent", "BattleEffects.draw_projectile",
			func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "arcane", 0.0)),
		_row("wings", "Gilt streak", "A Wings dive: the fighter flies over the lines onto its target instead of lunging.", "trait_wings", "BattleEffects.draw_projectile",
			func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "dive", 0.3)),
		_row("impact", "Impact", "A hit landing. It never flashes more than three times a second.", "battle_hit_chance", "BattleEffects.draw_impact",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 13.0, "ring": false, "bright": false, "frames": 9, "age": 0.0, "life": 1.0}),
			"A hit landing. With reduced motion, impacts are a still ring."),
		_row("big_impact", "Big impact", "A big hit: 8 damage or more, such as a charge.", "battle_hit_chance", "BattleEffects.draw_impact",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 19.0, "ring": false, "bright": false, "frames": 9, "age": 0.0, "life": 1.0})),
		_row("ring", "Still ring", "An impact with reduced motion on.", "battle_hit_chance", "BattleEffects.draw_impact",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 16.0, "ring": true, "bright": false, "frames": 0, "age": 0.0, "life": 1.0})),
		_row("dust", "Dust", "A fighter falling, or a missed shot landing.", "battle_playback", "BattleEffects.draw_dust",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_dust(ci, {"pos": r.get_center() + Vector2(0, 8), "s": 1.0, "age": 0.15, "life": 0.4})),
		_row("shake", "Screen shake", "Only for a big hit or a fallen ruler, never more than once in three quarters of a second.", "battle_playback",
			"BattleEffects.draw_impact", func(ci: CanvasItem, r: Rect2):
				BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 15.0, "ring": false, "bright": false, "frames": 9, "age": 0.0, "life": 1.0})
				ci.draw_line(r.get_center() + Vector2(-26, -8), r.get_center() + Vector2(-26, 8), UiPalette.TEXT_SECONDARY, 2.0)
				ci.draw_line(r.get_center() + Vector2(26, -8), r.get_center() + Vector2(26, 8), UiPalette.TEXT_SECONDARY, 2.0),
			"The screen never shakes with reduced motion (or with screen shake off)."),
	]


static func _arrow(ci: CanvasItem, from: Vector2, to: Vector2) -> void:
	ci.draw_line(from, to, UiPalette.TEXT_SECONDARY, 2.0)
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([to, to - d * 7 + n * 4, to - d * 7 - n * 4]), UiPalette.TEXT_SECONDARY)
