class_name BattleWhyPanel
extends PanelContainer
## The "why did that happen" panel (M3-4, #59; design/M3_BATTLES.md §7.3), docked right (384 x 664 at the
## base viewport) and synced with the playhead. Renderer-agnostic: it talks only to a BattlePlayer (and a
## BattleSelection), and its words come from BattleWhy (BattleExplain, BattleCaptions), so the 3D stage
## hosts it unchanged. Top to bottom:
##   Now                  the current beat in one line
##   This attack          the attack that landed last this round: hit chance and damage as breakdowns whose
##                        lines sum to the log's numbers (BattleExplain.explain_attack), the attack and the
##                        defense, the roll
##   Morale this round    each morale check so far: the result, and the morale and break % breakdowns
##   This round           the caption on screen, each side's totals so far, and a feed of the round's notable
##                        events (click one to jump right after it)
##   Pinned fighter       the selected fighter's §5.4 explanation, updated as playback advances
##   Why it went this way the report's factors as chips, lit when the factor has worth this round
## Every line links its codex entry (right-click or F1, CodexLink).
##
##   var panel := BattleWhyPanel.new()
##   panel.bind(player, selection)       selection may be null
##   panel.tick(real_delta)              once a frame: refreshes when something changed, at most every
##                                       LIVE_INTERVAL of real time while playing (at once while paused,
##                                       stepping or after a seek)
##   panel.refresh()                     refreshes now
##   panel.shown                         what it shows: {"position", "attack_event", "chance_values",
##                                       "chance_total", "damage_values", "damage_total", "morale_events",
##                                       "caption", "selected", "selected_lines", "chips"} (for tests)
##   signals codex_requested(key), close_requested (its x button)

signal codex_requested(key: String)
signal close_requested

const SIZE := Vector2(384, 664)
const LIVE_INTERVAL := 0.12
const BODY := 15
const NUMBER := 16
const HEAD := 15
const WIDTH := 330.0

var player: BattlePlayer = null
var selection: BattleSelection = null
var why: BattleWhy = null
var shown: Dictionary = {}
var _dirty := true
var _since := 0.0
var _chip_sig := ""

var now_label: Label
var attack_summary: Label
var attack_none: Label
var chance_grid: GridContainer
var damage_grid: GridContainer
var attack_desc: Label
var defense_desc: Label
var roll_label: Label
var attack_box: VBoxContainer
var morale_box: VBoxContainer
var morale_none: Label
var caption_labels: Array = []
var totals_label: Label
var feed_box: VBoxContainer
var feed_more: Label
var selected_label: Label
var chips_box: HFlowContainer
var close_button: Button


func _init() -> void:
	name = "BattleWhyPanel"
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.97)
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	_build()


func bind(p_player: BattlePlayer, p_selection: BattleSelection = null) -> void:
	if player != null:
		for sig in [player.beat, player.seeked, player.playing_changed]:
			for c in sig.get_connections():
				if c.callable.get_object() == self:
					sig.disconnect(c.callable)
	if selection != null and selection.changed.is_connected(_on_selection):
		selection.changed.disconnect(_on_selection)
	player = p_player
	selection = p_selection
	why = BattleWhy.new(player)
	player.beat.connect(_on_beat)
	player.seeked.connect(_on_seeked)
	player.playing_changed.connect(_on_playing_changed)
	if selection != null:
		selection.changed.connect(_on_selection)
	_chip_sig = ""
	refresh()


func tick(real_delta: float) -> void:
	_since += real_delta
	if _dirty and visible and player != null and (not player.is_playing() or _since >= LIVE_INTERVAL):
		refresh()


func _on_beat(_b: Dictionary, _st: Dictionary) -> void:
	_dirty = true
	if player != null and not player.is_playing() and visible:
		refresh()  # a step while paused


func _on_seeked(_st: Dictionary) -> void:
	_dirty = true
	if visible:
		refresh()


func _on_playing_changed(_playing: bool) -> void:
	_dirty = true
	if visible:
		refresh()


func _on_selection(_fid: int) -> void:
	_dirty = true
	if visible:
		refresh()


## Shows the playhead now.
func refresh() -> void:
	if player == null or why == null:
		return
	_dirty = false
	_since = 0.0
	var sel := selection.selected if selection != null else -1
	var m := why.at(player.next_beat(), player.live_state(), sel)
	shown = {"position": m.position, "attack_event": m.attack_event, "chance_values": [], "chance_total": -1, "damage_values": [],
		"damage_total": -1, "morale_events": [], "caption": [], "selected": sel, "selected_lines": [], "chips": m.chips}
	_set_line(now_label, String(m.now), TooltipText.plain("Now", "What the battle is doing at this point of the playback."), "battle_rounds")
	_fill_attack(m.attack)
	_fill_morale(m.morale)
	_fill_round(m)
	_fill_selected(m.selected)
	_fill_chips(m.chips)


func _fill_attack(a: Dictionary) -> void:
	attack_box.visible = not a.is_empty()
	attack_none.visible = a.is_empty()
	if a.is_empty():
		return
	_set_line(attack_summary, String(a.summary), TooltipText.plain("This attack", "The attack that landed last this round, from the battle's own numbers."),
		"battle_hit_chance")
	shown.chance_values = _fill_grid(chance_grid, a.chance, "%")
	shown.chance_total = int(a.chance.total)
	shown.damage_values = _fill_grid(damage_grid, a.damage, "")
	shown.damage_total = int(a.damage.total)
	_set_line(attack_desc, String(a.attack.description), TooltipText.from_breakdown(a.attack), String(a.attack.codex))
	_set_line(defense_desc, String(a.defense.description), TooltipText.from_breakdown(a.defense), String(a.defense.codex))
	_set_line(roll_label, String(a.roll), TooltipText.plain("The roll", "Every attack rolls 1 to 100 and hits on its hit chance or less. The roll is the battle's own, from the report."),
		"battle_hit_chance")


## Fills `grid` with breakdown `bd`: a heading row, each line and the total. Returns the line values shown.
func _fill_grid(grid: GridContainer, bd: Dictionary, unit: String) -> Array:
	var rows := [[String(bd.title), ""]]
	var values := []
	var first := true
	for l in bd.lines:
		var v := int(l.value)
		values.append(v)
		rows.append(["  " + String(l.label), (str(v) if first else "%+d" % v) + unit])
		first = false
	rows.append(["= " + String(bd.total_label), "%d%s" % [int(bd.total), unit]])
	var need := rows.size() * 2
	while grid.get_child_count() < need:
		var k := grid.get_child_count()
		var l := _label("", BODY if k % 2 == 0 else NUMBER, UiPalette.TEXT_PRIMARY)
		if k % 2 == 0:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = WIDTH - 70.0
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size.x = 60.0
		grid.add_child(l)
	for k in grid.get_child_count():
		var l: Label = grid.get_child(k)
		var r := k / 2
		l.visible = r < rows.size()
		if r < rows.size():
			l.text = String(rows[r][k % 2])
			var head := r == 0 or r == rows.size() - 1
			l.add_theme_color_override("font_color", UiPalette.GILT if head else UiPalette.TEXT_PRIMARY)
	var tip := TooltipText.from_breakdown(bd)
	grid.tooltip_text = tip
	CodexLink.detach(grid)
	CodexLink.attach(grid, String(bd.codex), codex_requested.emit)
	return values


func _fill_morale(list: Array) -> void:
	morale_none.visible = list.is_empty()
	while morale_box.get_child_count() < list.size():
		var l := _label("", BODY, UiPalette.TEXT_PRIMARY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = WIDTH
		morale_box.add_child(l)
	for k in morale_box.get_child_count():
		var l: Label = morale_box.get_child(k)
		l.visible = k < list.size()
		if k < list.size():
			var mx: Dictionary = list[k]
			var text := "%s Morale %d, so it breaks after losing %d%% (at %d hp or less)." % [String(mx.result), int(mx.morale.total),
				int(mx["break"].total), int(mx.break_hp)]
			_set_line(l, text, TooltipText.from_breakdown(mx.morale) + "\n\n" + TooltipText.from_breakdown(mx["break"]), String(mx.codex))
			shown.morale_events.append(mx)


func _fill_round(m: Dictionary) -> void:
	var lines: Array = m.caption
	shown.caption = lines
	for k in 2:
		var l: Label = caption_labels[k]
		l.visible = k < lines.size()
		if k < lines.size():
			_set_line(l, String(lines[k].text), TooltipText.plain("Round caption", "What mattered most in the round, worked out from the battle's own numbers."),
				String(lines[k].codex))
	if lines.is_empty() and int(m.round) <= 0:
		caption_labels[0].visible = true
		_set_line(caption_labels[0], "Round 1 hasn't started. After each round, a caption here says what mattered most.",
			TooltipText.plain("Round caption", "What mattered most in a round, worked out from the battle's own numbers."), "battle_rounds")
	totals_label.visible = not String(m.totals_text).is_empty()
	_set_line(totals_label, String(m.totals_text), TooltipText.plain("This round so far", "Damage dealt, hits and attacks of each side this round, and about how much damage average rolls would have dealt."),
		"battle_hit_chance")
	var feed: Array = m.feed
	while feed_box.get_child_count() < feed.size():
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = WIDTH
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", BODY)
		b.add_theme_color_override("font_color", UiPalette.LINK)
		b.pressed.connect(_jump.bind(b))
		feed_box.add_child(b)
	for k in feed_box.get_child_count():
		var b: Button = feed_box.get_child(k)
		b.visible = k < feed.size()
		if k < feed.size():
			var f: Dictionary = feed[k]
			b.text = "• " + String(f.text)
			b.set_meta("beat", int(f.beat))
			b.tooltip_text = "Jump right after it, to see why it happened."
			CodexLink.detach(b)
			CodexLink.attach(b, String(f.codex), codex_requested.emit)
	feed_more.visible = int(m.feed_more) > 0
	feed_more.text = "and %d earlier this round" % int(m.feed_more)


func _jump(b: Button) -> void:
	if player != null and b.has_meta("beat"):
		player.seek_beat(int(b.get_meta("beat")) + 1)


func _fill_selected(ex: Dictionary) -> void:
	if ex.is_empty():
		_set_line(selected_label, "Click a fighter, or press Tab, to pin what it is doing and why here.", "", "battle_playback")
		selected_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		return
	shown.selected_lines = ex.lines
	selected_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	_set_line(selected_label, "\n".join(ex.lines), TooltipText.plain(String(ex.title), "Pinned: this follows the fighter as the battle plays."), String(ex.codex))


func _fill_chips(chips: Array) -> void:
	var sig := ""
	for c in chips:
		sig += "%s|%s|" % [c.text, c.lit]
	if sig == _chip_sig:
		return
	_chip_sig = sig
	for c in chips_box.get_children():
		chips_box.remove_child(c)
		c.queue_free()
	for c in chips:
		var l := _label(String(c.text), BODY, UiPalette.TEXT_PRIMARY if c.lit else UiPalette.TEXT_SECONDARY)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UiPalette.GILT, 0.18) if c.lit else UiPalette.PANEL_BG
		style.border_color = UiPalette.GILT if c.lit else UiPalette.PANEL_BORDER
		style.set_border_width_all(2 if c.lit else 1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		l.add_theme_stylebox_override("normal", style)
		l.tooltip_text = TooltipText.plain(String(c.title), String(c.tip) + (" Lit: it mattered this round." if c.lit else ""))
		chips_box.add_child(l)
		CodexLink.attach(l, String(c.codex), codex_requested.emit)


func _set_line(l: Label, text: String, tip: String, codex: String) -> void:
	l.text = text
	l.tooltip_text = tip
	CodexLink.detach(l)
	CodexLink.attach(l, codex, codex_requested.emit)


## Every text on the panel a player can see or hover (for the no-raw-ids test).
func visible_texts() -> Array:
	var out := []
	_collect(self, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Label and not (n as Label).text.is_empty():
		out.append((n as Label).text)
	if n is Button and not (n as Button).text.is_empty():
		out.append((n as Button).text)
	if n is Control and not (n as Control).tooltip_text.is_empty():
		out.append((n as Control).tooltip_text)
	for ch in n.get_children():
		_collect(ch, out)


# --- building -------------------------------------------------------------------------------------

func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label("Why did that happen", 18, UiPalette.GILT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = TooltipText.plain("The why panel", "Follows the playback: what is happening now, the last attack's numbers, the round's morale checks and what mattered, and the fighter you pinned.")
	head.add_child(title)
	CodexLink.attach(title, "battle_playback", codex_requested.emit)
	close_button = Button.new()
	close_button.text = "×"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Close the why panel (%s)." % BattleControls.KEYS.why
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.pressed.connect(func(): close_requested.emit())
	head.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.custom_minimum_size.x = WIDTH
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_head(body, "Now")
	now_label = _wrapped(body)
	_head(body, "This attack")
	attack_none = _label("No attack has landed yet this round.", BODY, UiPalette.TEXT_SECONDARY)
	body.add_child(attack_none)
	attack_box = VBoxContainer.new()
	attack_box.add_theme_constant_override("separation", 3)
	body.add_child(attack_box)
	attack_summary = _wrapped(attack_box)
	chance_grid = _grid(attack_box)
	attack_desc = _wrapped(attack_box, 13, UiPalette.TEXT_SECONDARY)
	defense_desc = _wrapped(attack_box, 13, UiPalette.TEXT_SECONDARY)
	damage_grid = _grid(attack_box)
	roll_label = _wrapped(attack_box)
	_head(body, "Morale this round")
	morale_none = _label("No morale check yet this round.", BODY, UiPalette.TEXT_SECONDARY)
	body.add_child(morale_none)
	morale_box = VBoxContainer.new()
	body.add_child(morale_box)
	_head(body, "This round")
	for k in 2:
		caption_labels.append(_wrapped(body, BODY, UiPalette.TEXT_PRIMARY if k == 0 else UiPalette.TEXT_SECONDARY))
	totals_label = _wrapped(body, 13, UiPalette.TEXT_SECONDARY)
	feed_box = VBoxContainer.new()
	feed_box.add_theme_constant_override("separation", 0)
	body.add_child(feed_box)
	feed_more = _label("", 15, UiPalette.TEXT_SECONDARY)
	feed_more.visible = false
	body.add_child(feed_more)
	_head(body, "Pinned fighter")
	selected_label = _wrapped(body)
	_head(body, "Why it went this way")
	chips_box = HFlowContainer.new()
	chips_box.add_theme_constant_override("h_separation", 6)
	chips_box.add_theme_constant_override("v_separation", 6)
	chips_box.custom_minimum_size.x = WIDTH
	body.add_child(chips_box)


func _head(parent: Control, text: String) -> void:
	var l := _label(text.to_upper(), HEAD, UiPalette.GILT)
	l.add_theme_constant_override("line_spacing", 0)
	parent.add_child(l)


func _wrapped(parent: Control, font_size: int = BODY, col: Color = UiPalette.TEXT_PRIMARY) -> Label:
	font_size = maxi(font_size, UiPalette.TYPE_FLOOR)  # UI-FIT (#237): nothing the player reads below the floor
	var l := _label("", font_size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(l)
	return l


func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 0)
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(g)
	return g


func _label(text: String, font_size: int, col: Color) -> Label:
	font_size = maxi(font_size, UiPalette.TYPE_FLOOR)  # UI-FIT (#237): nothing the player reads below the floor
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
