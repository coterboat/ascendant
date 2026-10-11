class_name MusterBoard
extends VBoxContainer
## ARM-1 (design/ARM1_SPLIT_MERGE.md §8, design/UX_WAR_TABLE.md §3.5): "Armies here", the army card's place to reshape your armies in
## a province. Each of your armies in the province is a row of portraits; drag fighters (or the commander) from one row onto
## another, or onto "New army", and the order is given; or press Split, Merge all or Swap commanders. A click on a portrait ticks it
## (a gilt frame) for the next drag or Split. The forecast under the rows updates as the pointer crosses a row, before anything is
## ordered (MusterForecast): each army's make-up, strength and sight before and after, the orders it would drop, where your recruits
## would join, the blessing it would leave behind and the battle note when one part holds and another marches. The rules' refusals
## are the order book's own words (MusterForecast.refusal). A ruler's army is greyed with its reason: a ruler travels alone.
##
## Armies are read from the BOARD (MapScreen.board_state): the real armies and the ones queued musters form, with their real ids, so a
## new army can be selected and given a move at once. Every order goes through MapScreen.queue_muster, so it is checked, listed
## in the orders list with its sentence and undone with Cancel order like any other.

const PORTRAIT := Vector2(32, 32)
const RESERVED_H := 96.0  # the forecast box keeps this much height, so the card does not jump as the pointer crosses the rows
const HINT := "Drag fighters between your armies, or onto New army. Click a portrait to tick it first to move several. Hover a button or cross an army to see what each army becomes before you order anything."

## The partner each army last had (the army Merge all and Swap commanders work with) is kept across the card's rebuilds in the
## orders controller (OrdersController.muster_partners), so it lasts as long as the plan does and no longer.

var map: MapScreen
var army_id := ""
var partner_id := ""
var rows := {}  # army id -> Row, in the order shown
var new_zone: DropZone = null
var picks := {}  # army id -> {"units": {index: true}, "commander": bool}
var engines_going := 0
var split_button: Button = null
var merge_button: Button = null
var swap_button: Button = null
var engines_button: Button = null  # only for an army that carries engines: sends the stepper's engines to the partner army
var engines_row: HBoxContainer = null
var engines_label: Label = null
var forecast_box: PanelContainer = null
var forecast_lines: VBoxContainer = null
var message: Label = null
var _board: GameState = null
var _preview_key := ""
var _preview: Dictionary = {}


static func make(host: MapScreen, army: Army) -> MusterBoard:
	var b := MusterBoard.new()
	b.name = "ArmiesHere"
	b.map = host
	b.army_id = army.id
	b._build()
	return b


func _init() -> void:
	add_theme_constant_override("separation", 6)


# --- building ---------------------------------------------------------------------------------------------------

func _build() -> void:
	_board = map.board_state()
	var me := _board.find_army(army_id)
	if me == null:
		return
	var heading := Label.new()
	heading.text = "Armies here"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", UiPalette.GILT)
	add_child(heading)
	CodexLink.attach(heading, MusterRules.CODEX, map.request_codex)
	var mine: Array = _board.armies.filter(func(o): return o.location == me.location and o.owner == map.viewing_faction_id and not FogView.is_stand_in(o))
	var ids: Array = TurnReportText.sort_ids(mine.map(func(o): return o.id))
	var candidates := []
	for id in ids:
		var o: Army = _board.find_army(String(id))
		if String(id) != army_id and o.ruler == null:
			candidates.append(String(id))
	partner_id = String(map.orders.muster_partners.get(army_id, ""))
	if not candidates.has(partner_id):
		partner_id = String(candidates[0]) if not candidates.is_empty() else ""
	# The forecast sits right under the heading, where the pointer travelling from the card's portraits to a row passes it.
	forecast_box = PanelContainer.new()
	forecast_box.name = "MusterForecast"
	forecast_box.custom_minimum_size = Vector2(0, RESERVED_H)
	forecast_box.add_theme_stylebox_override("panel", CardBase.raised_style(UiPalette.PANEL_BORDER, 1))
	add_child(forecast_box)
	forecast_lines = VBoxContainer.new()
	forecast_lines.add_theme_constant_override("separation", 3)
	forecast_box.add_child(forecast_lines)
	# The actions and New army come before the other armies' rows: they are what most orders use, and what a squeezed card must not hide.
	_add_engines(me)
	_add_buttons(me)
	new_zone = DropZone.make(self)
	add_child(new_zone)
	for id in ids:
		if String(id) == army_id:
			continue  # this army is the card's own strip above (adopt_strip): its portraits can be ticked and dragged from there
		var row := Row.make(self, _board.find_army(String(id)))
		rows[String(id)] = row
		add_child(row)
	message = Label.new()
	message.name = "MusterMessage"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	message.add_theme_color_override("font_color", UiPalette.NEGATIVE.lightened(0.25))
	message.visible = false
	add_child(message)
	clear_preview()


func _fid() -> String:
	return map.viewing_faction_id


## The card's own portraits (the strip under its name) are this army's: they are ticked and dragged like a row's.
func adopt_strip(strip: UnitStrip) -> void:
	for chip in strip.chips():
		chip.pick_toggle = pick_toggle
		chip.drag_data = drag_data
		chip.drag_label = MusterBoard.drag_words


## The engines stepper: how many of this army's siege engines go with the next split or drag from it. Only for an army that carries any.
func _add_engines(me: Army) -> void:
	if me.engines <= 0 or me.ruler != null:
		return
	engines_row = HBoxContainer.new()
	engines_row.name = "EnginesRow"
	engines_row.add_theme_constant_override("separation", 6)
	add_child(engines_row)
	engines_label = Label.new()
	engines_label.name = "EnginesLabel"
	engines_label.add_theme_font_size_override("font_size", 16)
	engines_label.tooltip_text = TooltipText.plain("Siege engines", "Engines move only when you say so. This many of %s go with the next fighters you drag or split off, or alone to your partner army with Send engines (never to a new army: it has no one to carry them). An army carries at most %d. %s" % [
		TurnReportText.army_name(_board, me.id, me.owner), FortData.ARMY_ENGINES_MAX, RulesCodex.text("muster")])
	engines_label.mouse_filter = Control.MOUSE_FILTER_PASS
	engines_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	engines_row.add_child(engines_label)
	for step in [-1, 1]:
		var b := Button.new()
		b.name = "EnginesLess" if step < 0 else "EnginesMore"
		b.text = "−" if step < 0 else "+"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(36, 32)
		b.tooltip_text = "Send %s engine with the next fighters." % ("one fewer" if step < 0 else "one more")
		b.pressed.connect(_step_engines.bind(step))
		engines_row.add_child(b)
	_show_engines()


func _step_engines(step: int) -> void:
	var me := _board.find_army(army_id)
	if me == null:
		return
	engines_going = clampi(engines_going + step, 0, me.engines)
	_show_engines()
	_refresh_buttons()


func _show_engines() -> void:
	if engines_label == null:
		return
	var me := _board.find_army(army_id)
	var of := me.engines if me != null else 0
	engines_label.text = "Engines going with them: %d of %d" % [engines_going, of]


## Split, Merge all and Swap commanders. Each is disabled with the order book's reason when the rules refuse it, and shows its forecast
## while the pointer is over it.
func _add_buttons(me: Army) -> void:
	var flow := HFlowContainer.new()
	flow.name = "MusterActions"
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	add_child(flow)
	split_button = _make_button("SplitButton", "Split")
	merge_button = _make_button("MergeAllButton", "Merge all")
	swap_button = _make_button("SwapCommandersButton", "Swap commanders")
	if me.engines > 0 and me.ruler == null:
		engines_button = _make_button("SendEnginesButton", "Send engines")
	for pair in _button_pairs():
		var b: Button = pair[0]
		b.pressed.connect(_press.bind(String(pair[1])))
		b.mouse_entered.connect(_hover.bind(String(pair[1])))
		b.mouse_exited.connect(clear_preview)
		flow.add_child(b)
	_refresh_buttons()


## [[button, kind]] of the buttons this card has.
func _button_pairs() -> Array:
	var out := [[split_button, "split"], [merge_button, "merge"], [swap_button, "swap"]]
	if engines_button != null:
		out.append([engines_button, "engines"])
	return out


## An action button in the card's style (CardBase.action_button), linked to the muster codex entry.
func _make_button(node_name: String, label: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	b.custom_minimum_size = Vector2(0, 36)
	CodexLink.attach(b, MusterRules.CODEX, map.request_codex)
	return b


## The order a button gives, or null when it has none to give (nothing to split, no partner).
func button_order(kind: String) -> MusterOrder:
	match kind:
		"split":
			var me := _board.find_army(army_id)
			if me == null:
				return null
			var pick: Dictionary = picks.get(army_id, {"units": {}, "commander": false})
			var idx: Array = pick.units.keys()
			var with_commander: bool = bool(pick.commander)
			if idx.is_empty() and not with_commander:
				# Nothing ticked: split the back half off, if there is a half to split.
				if me.units.size() < 2:
					return null
				for i in range(me.units.size() - me.units.size() / 2, me.units.size()):
					idx.append(i)
			return MusterOrder.transfer(army_id, "", idx, with_commander, engines_going)
		"merge":
			return MusterOrder.merge(army_id, partner_id) if not partner_id.is_empty() else null
		"swap":
			return MusterOrder.swap(army_id, partner_id) if not partner_id.is_empty() else null
		"engines":
			# The stepper's engines alone, to the partner army (an engines-only transfer: the partner carries them)
			return MusterOrder.transfer(army_id, partner_id, [], false, engines_going) if not partner_id.is_empty() and engines_going > 0 else null
	return null


func _refresh_buttons() -> void:
	var texts := {"split": "Split", "merge": "Merge all", "swap": "Swap commanders", "engines": "Send engines"}
	for pair in _button_pairs():
		var b: Button = pair[0]
		var kind := String(pair[1])
		var order := button_order(kind)
		var why := ""
		var body := ""
		match kind:
			"split":
				body = "Split the fighters you ticked off into a new army that can be given its own move this turn, or, with none ticked, the back half of this army. %s" % RulesCodex.text("muster")
				if order == null:
					why = "Click portraits to tick the fighters to split off. An army of one fighter can't be split."
			"merge":
				body = "Merge everything in this army into your partner army (%s), and its commander too if that army has none. %s" % [
					TurnReportText.army_name(_board, partner_id, _fid()) if not partner_id.is_empty() else "none yet", RulesCodex.text("muster")]
				if order == null:
					why = "You have no other army here to merge with. Armies muster only within one province."
			"swap":
				body = "This army and your partner army (%s) exchange commanders at once, so neither is ever without one. %s" % [
					TurnReportText.army_name(_board, partner_id, _fid()) if not partner_id.is_empty() else "none yet", RulesCodex.text("muster")]
				if order == null:
					why = "You have no other army here to swap commanders with."
			"engines":
				body = "Send the engines the stepper says (%d) from this army to your partner army (%s), without any fighters: it carries them from here on. %s" % [
					engines_going, TurnReportText.army_name(_board, partner_id, _fid()) if not partner_id.is_empty() else "none yet", RulesCodex.text("muster")]
				if partner_id.is_empty():
					why = "You have no other army here to carry the engines."
				elif order == null:
					why = "Use the engines stepper to say how many engines to send."
		if order != null:
			var check := MusterForecast.refusal(_board, _fid(), order)
			if not check.is_empty():
				why = String(check.reason)
		b.text = String(texts[kind]) if kind == "split" or partner_id.is_empty() else "%s: %s" % [texts[kind], _short_partner()]
		b.disabled = not why.is_empty()
		b.tooltip_text = TooltipText.plain(String(texts[kind]), why if not why.is_empty() else body)
		CodexLink.attach(b, MusterRules.CODEX, map.request_codex)  # the tooltip changed: end it with the codex line again


func _short_partner() -> String:
	return TurnReportText.army_name(_board, partner_id, _fid())


func _press(kind: String) -> void:
	var order := button_order(kind)
	if order == null:
		return
	_give(order)


func _hover(kind: String) -> void:
	var order := button_order(kind)
	if order != null:
		preview(order)


# --- picking and dragging -----------------------------------------------------------------------------------------

## A click on a chip: ticks or unticks that fighter for the next drag or Split.
func pick_toggle(chip: UnitStrip.Chip) -> void:
	var army := _board.find_army(chip.army_id)
	if army == null or chip.is_ruler:
		return
	if not picks.has(chip.army_id):
		picks[chip.army_id] = {"units": {}, "commander": false}
	var pick: Dictionary = picks[chip.army_id]
	if chip.is_commander:
		pick.commander = not bool(pick.commander)
		chip.set_picked(bool(pick.commander))
	else:
		var i := army.units.find(chip.unit_ref)
		if i < 0:
			return
		if pick.units.has(i):
			pick.units.erase(i)
		else:
			pick.units[i] = true
		chip.set_picked(pick.units.has(i))
	if chip.army_id == army_id:
		_refresh_buttons()


## The payload of a drag that starts on `chip`: its army and the fighters it takes (every ticked chip of that army when this one is
## ticked, otherwise just this one), or null for a fighter that cannot move (a ruler).
func drag_data(chip: UnitStrip.Chip) -> Variant:
	if chip.is_ruler:
		return null
	var army := _board.find_army(chip.army_id)
	if army == null:
		return null
	var units := []
	var commander := false
	var pick: Dictionary = picks.get(chip.army_id, {"units": {}, "commander": false})
	if chip.picked:
		units = pick.units.keys()
		commander = bool(pick.commander)
	elif chip.is_commander:
		commander = true
	else:
		var i := army.units.find(chip.unit_ref)
		if i >= 0:
			units = [i]
	units.sort()
	if units.is_empty() and not commander:
		return null
	return {"kind": "muster", "from": chip.army_id, "units": units, "commander": commander}


static func drag_words(data: Dictionary) -> String:
	var n: int = Array(data.get("units", [])).size() + (1 if bool(data.get("commander", false)) else 0)
	return "1 fighter" if n == 1 else "%d fighters" % n


## The transfer a drop of `data` on army `to_id` ("" for a new army) is, or null when it is no transfer (same army).
func order_for_drop(data: Variant, to_id: String) -> MusterOrder:
	if not (data is Dictionary) or String(data.get("kind", "")) != "muster":
		return null
	var from := String(data.get("from", ""))
	if from == to_id:
		return null
	return MusterOrder.transfer(from, to_id, Array(data.get("units", [])), bool(data.get("commander", false)), engines_going if from == army_id else 0)


## Whether a drop of `data` on `to_id` would be allowed: this is the forecast's moment, the pointer being over that row.
func can_drop(data: Variant, to_id: String) -> bool:
	var order := order_for_drop(data, to_id)
	if order == null:
		return false
	preview(order)
	return bool(_preview.get("ok", false))


func drop(data: Variant, to_id: String) -> void:
	var order := order_for_drop(data, to_id)
	if order != null:
		_give(order)


func _give(order: MusterOrder) -> void:
	map.orders.muster_partners[army_id] = partner_id
	var reason := map.queue_muster(order)
	if not reason.is_empty() and is_instance_valid(message):
		message.text = reason
		message.visible = true


## The partner Merge all and Swap commanders work with.
func set_partner(id: String) -> void:
	if not rows.has(id) or id == army_id:
		return
	partner_id = id
	map.orders.muster_partners[army_id] = id
	for rid in rows:
		rows[rid].show_partner(rid == partner_id)
	_refresh_buttons()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_inside_tree():
		clear_preview()


# --- the forecast -------------------------------------------------------------------------------------------------------

## Shows what `order` would do, before anything is ordered. Cached by the order, so the pointer crossing a row asks the rules once.
func preview(order: MusterOrder) -> void:
	var key := JSON.stringify(order.to_dict())
	if key == _preview_key:
		return
	_preview_key = key
	_preview = MusterForecast.of(map.orders.state, _fid(), order, map.orders.orders())
	_render(_preview)


func clear_preview() -> void:
	_preview_key = ""
	_preview = {}
	_render({})


func _render(f: Dictionary) -> void:
	if forecast_lines == null:
		return
	for c in forecast_lines.get_children():
		forecast_lines.remove_child(c)
		c.queue_free()
	if f.is_empty():
		_line(HINT, UiPalette.TEXT_SECONDARY, "ForecastHint")
		return
	if not bool(f.get("ok", false)):
		_line(String(f.get("reason", "")), UiPalette.NEGATIVE.lightened(0.25), "ForecastRefusal")
		return
	_line("If you order this:", UiPalette.GILT, "ForecastTitle")
	for l in f.lines:
		_line(String(l), UiPalette.TEXT_PRIMARY, "ForecastArmy")
	for row in f.outside:
		_line(RulerRules._cap(String(row.text)) + ".", UiPalette.GILT, "ForecastBlessing")
	if bool(f.info.get("commander_left", false)):
		_line("Both armies have a commander, so the commander of %s stays behind as an army of its own." % TurnReportText.army_name(_board, String(f.info.from), _fid()),
			UiPalette.TEXT_SECONDARY, "ForecastCommander")
	for d in f.dropped:
		_line(String(d.text), UiPalette.NEGATIVE.lightened(0.25), "ForecastDropped")
	for r in f.recruits:
		if String(r.was) != String(r.army):
			_line("Your %s recruit %s." % [r.unit, r.text], UiPalette.TEXT_SECONDARY, "ForecastRecruit")
	if not String(f.battle).is_empty():
		_line(String(f.battle), UiPalette.TEXT_SECONDARY, "ForecastBattle")


func _line(text: String, colour: Color, node_name: String) -> void:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	l.add_theme_color_override("font_color", colour)
	l.tooltip_text = TooltipText.plain("Muster forecast", "What the order would do, worked out with the rules the turn uses, before you give it. Strength is the army card's rough size guide (attack plus defense of its fighters); sight is how many provinces around it the army sees. %s" % RulesCodex.text("muster"))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, MusterRules.CODEX, map.request_codex)
	forecast_lines.add_child(l)


# --- one army of yours ---------------------------------------------------------------------------------------------------

## An army's row: its name (a button that selects it), what it holds, its portraits (which can be ticked and dragged) and, for
## a ruler's army, why it cannot take part. A drop on the row, or on any of its portraits, is a transfer into it.
class Row extends PanelContainer:
	var board: MusterBoard
	var army_id := ""
	var name_button: Button
	var summary: Label
	var partner_check: CheckBox = null
	var strip: UnitStrip
	var greyed := false

	static func make(b: MusterBoard, a: Army) -> Row:
		var row := Row.new()
		row.board = b
		row.army_id = a.id
		row.name = "ArmyRow_%s" % a.id.validate_node_name()  # as the province card's rows are named (UX-3)
		row._build(a)
		return row

	func _build(a: Army) -> void:
		var state: GameState = board._board
		greyed = a.ruler != null
		var style := CardBase.raised_style(UiPalette.owner_color(state, a.owner, board.map.seat_order()), 2)
		style.set_content_margin_all(6)
		add_theme_stylebox_override("panel", style)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		add_child(box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		box.add_child(head)
		name_button = Button.new()
		name_button.name = "ArmyButton"
		name_button.text = RulerRules._cap(TurnReportText.army_name(state, a.id, a.owner))
		name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_button.focus_mode = Control.FOCUS_NONE
		name_button.flat = true
		name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_button.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
		name_button.tooltip_text = TooltipText.plain("Select this army", "Click to select %s: its card, its march and its orders." % TurnReportText.army_name(state, a.id, a.owner))
		name_button.pressed.connect(board.map.select_army.bind(a.id))
		head.add_child(name_button)
		if not greyed:
			partner_check = CheckBox.new()
			partner_check.name = "PartnerCheck"
			partner_check.text = "Partner"
			partner_check.focus_mode = Control.FOCUS_NONE
			partner_check.button_pressed = a.id == board.partner_id
			partner_check.tooltip_text = TooltipText.plain("Partner", "Merge all and Swap commanders work between the army you selected and its partner. Tick the army you want to work with.")
			partner_check.pressed.connect(board.set_partner.bind(a.id))
			head.add_child(partner_check)
		if a.ruler != null:
			# A ruler's army can't take part: one greyed line with its reason, no portraits to drag
			var why := Label.new()
			why.name = "MusterRefusal"
			why.text = "A ruler travels alone: it can't be split, merged or swapped."
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
			why.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
			why.mouse_filter = Control.MOUSE_FILTER_PASS
			why.tooltip_text = TooltipText.plain("Rulers travel alone", RulesCodex.text("ruler_army"))
			box.add_child(why)
			modulate = Color(1, 1, 1, 0.6)
			return
		summary = Label.new()
		summary.name = "MusterSummary"
		summary.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		summary.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var s := MusterForecast.army_summary(state, a)
		summary.text = "%d %s%s, strength %d, sees %d" % [s.units.size(), "unit" if s.units.size() == 1 else "units",
			", %s" % s.commander_name if not String(s.commander_name).is_empty() else ", no commander", int(s.strength), int(s.sight)]
		if int(s.engines) > 0:
			summary.text += ", %d engine%s" % [int(s.engines), "" if int(s.engines) == 1 else "s"]
		# Every number explains itself: the strength's breakdown, and how far it sees
		var sb := Breakdown.army_strength(state, a.id)
		summary.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(sb), TooltipText.wrap_text("It sees %d province%s around it." % [int(s.sight), "" if int(s.sight) == 1 else "s"])]
		summary.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(summary, "army_strength", board.map.request_codex)
		box.add_child(summary)
		strip = UnitStrip.make(state, a, MusterBoard.PORTRAIT, board.map.request_codex, true)
		box.add_child(strip)
		for chip in strip.chips():
			chip.pick_toggle = board.pick_toggle
			chip.drag_data = board.drag_data
			chip.drag_label = MusterBoard.drag_words
			chip.drop_row = self

	func show_partner(on: bool) -> void:
		if partner_check != null:
			partner_check.button_pressed = on

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if greyed:
			return false
		return board.can_drop(data, army_id)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		board.drop(data, army_id)


## "New army": drop fighters here to split them off into an army of their own, which can be given a move at once.
class DropZone extends PanelContainer:
	var board: MusterBoard

	static func make(b: MusterBoard) -> DropZone:
		var z := DropZone.new()
		z.board = b
		z.name = "NewArmyZone"
		var style := CardBase.raised_style(UiPalette.PANEL_BORDER, 2)
		style.bg_color = Color(UiPalette.PANEL_RAISED, 0.5)
		style.set_content_margin_all(8)
		z.add_theme_stylebox_override("panel", style)
		var l := Label.new()
		l.text = "New army: drop fighters here"
		l.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
		l.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		z.add_child(l)
		z.tooltip_text = TooltipText.plain("New army", "Drop fighters here to split them off into a new army at this place. It gets the next number, appears at once, and can be given a move this turn. %s" % RulesCodex.text("muster"))
		return z

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return board.can_drop(data, "")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		board.drop(data, "")
