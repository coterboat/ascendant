class_name BattleReportViewer
extends Control
## The full battle report (#7): opens from a battle row of the turn report and shows the report that
## AutoBattleResolver (#4) attaches to battle events (event.numbers.report), in readable sections:
##   1. why        the result and the "why" summary, on top
##   2. sides      who fought: each side's armies, roster, fighters, starting morale, whether it defended,
##                 its ruler and the mandates in play (M2-2), the traits and mandates that changed attacks,
##                 and Skirmish's reach
##   3. terrain    terrain and fort modifiers
##   4. rounds     round by round highlights
##   5. casualties losses per side, a ruler's death and Feast of Victory
##   6. routs      morale checks: who broke and fled, who held (and when Iron Discipline held a side)
##   7. hits       hit rates against the chances each side had
##   8. round_cap  only when the battle ran out of rounds
## Reads the report only: every number comes from the report (or the rules' terrain and fort bonus
## constants), every explanation from RulesCodex. Never changes rules state.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   show_event(event, state = null, seats = []) -> bool   a battle event from the turn report. Returns
##                                             false and shows "No detailed report for this battle."
##                                             when the event carries no report (e.g. StubBattleResolver).
##   show_report(report, state = null, seats = []) -> bool an AutoBattleResolver report dictionary
##   close()                                   hides the viewer and emits `closed` (Close button, Esc)
##   section_names() -> Array[String]          the sections shown, in display order
##   section(name) -> Control                  one section's node, or null
##   side_color(faction_id) -> Color           the colour a side is drawn in
##   signal codex_requested(key)               a section heading or the "why" was right-clicked (or F1)
## `seats` is the seat order (GameSession.players()): player colours follow the seat, the same way the
## map draws them (UiPalette.faction_color). Without it, the state's faction order stands in.
## Art (#10): each "Who fought" card flies its side's banner and shows its roster as portrait cards (a
## count badge on each, commanders framed in gilt, a ruler's card last; Art falls back to a placeholder
## card for any portrait that has not landed yet), above the roster in words.

signal closed
## A linked heading or the "why" was right-clicked: open the codex at `key` (the host does).
signal codex_requested(key: String)

const SECTION_ORDER := ["why", "sides", "terrain", "rounds", "casualties", "routs", "hits", "round_cap"]
const NO_REPORT_TEXT := "No detailed report for this battle."
const NEGATIVE := UiPalette.NEGATIVE  # design/STYLE_BIBLE.md 1.3 "negative"
## Portrait cards in "Who fought" (3:4), and the banner beside each side's name.
const ROSTER_PORTRAIT := Vector2(78, 104)
const SIDE_BANNER_HEIGHT := 84.0

## RulesCodex entry that explains each deciding factor of the "why" (factor ids from the report). A
## mandate's factor id ("mandate_royal_armories") is its own entry (_factor_entry).
const FACTOR_ENTRIES := {
	"terrain": "battle_terrain",
	"fort": "battle_terrain",
	"commander": "battle_commanders",
	"morale_commander": "battle_morale",
	"morale_Inspire": "trait_inspire",
	"rout": "battle_morale",
	"numbers": "battle_rounds",
	"luck": "battle_hit_chance",
	"round_cap": "battle_round_cap",
	"ruler": "ruler_in_battle",
	"morale_ruler": "ruler_in_battle",
	"ability_dread": "ability_dread",
}
## Player-facing names for the morale effects in a morale check.
const MORALE_PART_NAMES := {
	"commander": "Its commander still standing",
	"Inspire": "Inspire (its commander's trait)",
	"Fury": "Fury (enemy War Bears roaring)",
	"ruler": "Its ruler still standing",
	"Dread": "Dread (the enemy's Great Thornmane)",
}

var title_label: Label
var close_button: Button
var message_label: Label
var scroll: ScrollContainer
var content: VBoxContainer
var _sections := {}  # section name -> Control, for the report on screen
var _report := {}
var _event := {}
var _state: GameState = null
var _seats: Array = []


func _init() -> void:
	name = "BattleReportViewer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		close()


## Shows the report a battle event carries. Returns false, showing a plain message instead, when the
## event has no detailed report.
func show_event(event: Dictionary, state: GameState = null, seats: Array = []) -> bool:
	_event = event.duplicate(true)
	_seats = seats.duplicate()
	var numbers: Dictionary = event.get("numbers", {})
	var report: Dictionary = numbers.get("report", {})
	if report.is_empty():
		_state = state
		_show_no_report(str(event.get("text", "")))
		return false
	return _show(report, state)


## Shows an AutoBattleResolver report dictionary (the "report" of a battle result).
func show_report(report: Dictionary, state: GameState = null, seats: Array = []) -> bool:
	_event = {}
	_seats = seats.duplicate()
	if report.is_empty():
		_state = state
		_show_no_report("")
		return false
	return _show(report, state)


## Hides the viewer and tells the host, which can free it or give focus back.
func close() -> void:
	visible = false
	closed.emit()


## Names of the sections on screen, in display order (empty when there is no report).
func section_names() -> Array[String]:
	var out: Array[String] = []
	for c in content.get_children():
		var key := String(c.get_meta("section", ""))
		if not key.is_empty() and (c as Control).visible:
			out.append(key)
	return out


func section(section_name: String) -> Control:
	return _sections.get(section_name)


# --- building the report --------------------------------------------------------------------------

func _show(report: Dictionary, state: GameState) -> bool:
	_report = report.duplicate(true)
	_state = state
	_clear()
	title_label.text = "Battle %s" % String(report.get("place", "in the field"))
	message_label.visible = false
	_add_why()
	_add_sides()
	_add_terrain()
	_add_rounds()
	_add_casualties()
	_add_routs()
	_add_hits()
	if report.get("end", "") == "round_cap":
		_add_round_cap()
	_show_viewer()
	return true


func _show_no_report(event_text: String) -> void:
	_report = {}
	_clear()
	title_label.text = "Battle report"
	message_label.text = NO_REPORT_TEXT
	message_label.visible = true
	if not event_text.is_empty():
		var l := _text(content, event_text, _tip("Battles", RulesCodex.text("battle_rounds")), 20, UiPalette.TEXT_SECONDARY)
		l.name = "EventText"
	_show_viewer()


func _show_viewer() -> void:
	visible = true
	if is_inside_tree():
		scroll.scroll_vertical = 0
		close_button.grab_focus.call_deferred()


func _add_why() -> void:
	var box := _section("why", "", "")
	var panel := PanelContainer.new()
	panel.name = "WhyPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.GILT
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)

	var result := _text(inner, _result_sentence(), _tip("How a battle ends", RulesCodex.text("battle_rounds")), 30, UiPalette.GILT)
	result.name = "ResultLabel"
	CodexLink.attach(result, "battle_rounds", codex_requested.emit)
	var why := String(_report.get("why", ""))
	var why_text := "Why: %s." % _cap(why) if not why.is_empty() else "Why: the report gives no single reason."
	var why_label := _text(inner, why_text, _why_tooltip(), 24, UiPalette.TEXT_PRIMARY)
	why_label.name = "WhyLabel"
	CodexLink.attach(why_label, _why_entry(), codex_requested.emit)


func _add_sides() -> void:
	var box := _section("sides", "Who fought",
		_tip("Who fought", "Each side's armies as they stood when the battle began. Fighters are units, commanders and rulers. %s" % RulesCodex.text("battle_commanders")),
		"battle_commanders")
	var row := HBoxContainer.new()
	row.name = "SideCards"
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for sr in _sides():
		var card := _card(_side_color(sr))
		row.add_child(card)
		var col: VBoxContainer = card.get_child(0)
		var head := HBoxContainer.new()
		head.name = "SideHeader"
		head.add_theme_constant_override("separation", 12)
		col.add_child(head)
		var banner := Art.banner_card(String(sr.get("faction", "")), SIDE_BANNER_HEIGHT)
		banner.name = "SideBanner"
		head.add_child(banner)
		var titles := VBoxContainer.new()
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		titles.alignment = BoxContainer.ALIGNMENT_CENTER
		titles.add_theme_constant_override("separation", 2)
		head.add_child(titles)
		var name_label := _text(titles, String(sr.get("name", "")), _role_tooltip(sr), 26, _side_color(sr).lightened(0.3))
		name_label.name = "SideName"
		_text(titles, _role_text(sr), _role_tooltip(sr), 18, UiPalette.TEXT_SECONDARY)
		col.add_child(_roster_strip(sr))
		for label in sr.get("armies", []):
			_text(col, "Army: %s" % label, _tip("Army",
				"An army on this side when the battle began: how many units it had (its commander is not counted as a unit) and who led it."), 17)
		var roster: Dictionary = sr.get("roster", {})
		if not String(roster.get("text", "")).is_empty():
			var roster_label := _text(col, "Roster: %s" % roster.text, _tip("Roster",
				"Every kind of fighter this side brought, with how many of each when there were more than one: its units, then who led them, then its ruler if it fought."), 17)
			roster_label.name = "Roster"
		_text(col, "Fighters: %d, with %d hit points in all" % [int(sr.get("fighters_start", 0)), int(sr.get("hp_start", 0))],
			_tip("Fighters and hit points", "Every unit, commander and ruler fights. The hit points are the total of all of theirs when the battle began; wounded fighters start with fewer."), 17)
		_text(col, "Starting morale: %d" % int(sr.get("base_morale", 0)),
			_tip("Starting morale", "The average morale of this side's units, rounded down. A standing commander or ruler and some traits add to it or take from it every round (see Morale and routs below). %s" % RulesCodex.text("battle_morale")), 17)
		_add_ruler_lines(col, sr)
		_add_mandate_lines(col, sr)
		var triggers: Dictionary = sr.get("triggers", {})
		var trait_keys: Array = triggers.keys().filter(func(k): return k != "terrain" and k != "fort")
		trait_keys.sort()
		for key in trait_keys:
			var n := int(triggers[key])
			var entry := RulesCodex.entry(_part_entry(String(key)))
			var what := "mandate" if String(key).begins_with(AutoBattleResolver.MANDATE_PREFIX) else "trait"
			_text(col, "%s: changed %d %s" % [_part_name(String(key)), n, "attack" if n == 1 else "attacks"],
				_tip(String(entry.get("title", _part_name(String(key)))), "Counted once for every attack this %s changed in the battle. %s" % [what, String(entry.get("text", ""))]), 17)
		# Skirmish is about reach since #41 (it attacks the second rank), so it sits with the side that has it.
		for f in _report.get("all_factors", []):
			if f.get("id", "") == AutoBattleResolver.SKIRMISH and f.get("faction", "") == sr.get("faction", ""):
				_text(col, "Skirmish: %s." % _cap(String(f.get("brief", ""))),
					_tip(String(RulesCodex.entry("trait_skirmish").get("title", "Skirmish")), RulesCodex.text("trait_skirmish")), 17, UiPalette.TEXT_SECONDARY)


## A side's fighters as portrait cards: each unit type with its count, then its commanders (gilt
## frame), then its ruler. Hovering a card names it. Art.portrait_card shows a placeholder card when a
## portrait is missing (rulers have none yet).
func _roster_strip(sr: Dictionary) -> HFlowContainer:
	var strip := HFlowContainer.new()
	strip.name = "RosterPortraits"
	strip.add_theme_constant_override("h_separation", 8)
	strip.add_theme_constant_override("v_separation", 8)
	var roster: Dictionary = sr.get("roster", {})
	var fid := String(sr.get("faction", ""))
	for u in roster.get("units", []):
		var n := int(u.get("count", 1))
		var card := Art.portrait_card(String(u.get("id", "")), ROSTER_PORTRAIT, fid)
		card.count = n
		_name_card(card, String(u.get("name", "")) if n == 1 else "%s ×%d" % [u.get("name", ""), n], "A unit on this side when the battle began.")
		strip.add_child(card)
	for c in roster.get("commanders", []):
		var card := Art.portrait_card(String(c.get("id", "")), ROSTER_PORTRAIT, fid)
		_name_card(card, String(c.get("name", "")), "The commander who led this side. %s" % RulesCodex.text("battle_commanders"))
		strip.add_child(card)
	var ruler: Dictionary = roster.get("ruler", {})
	if not ruler.is_empty():
		var card := Art.ruler_card(String(ruler.get("id", "")), String(ruler.get("name", "")), ROSTER_PORTRAIT)
		_name_card(card, _cap(String(ruler.get("name", ""))), "This side's ruler fought in person. %s" % RulesCodex.text("ruler_in_battle"))
		strip.add_child(card)
	return strip


func _name_card(card: Control, title: String, description: String) -> void:
	card.tooltip_text = _tip(title, description)
	card.mouse_filter = Control.MOUSE_FILTER_PASS


## The side's ruler in "Who fought" (M2-2): its rank and numbers, then how it ended, and its Dread when
## that worked in this battle. Nothing for a side without a ruler.
func _add_ruler_lines(col: VBoxContainer, sr: Dictionary) -> void:
	var r: Dictionary = sr.get("ruler", {})
	if r.is_empty():
		return
	var name := String(r.get("name", ""))
	var rank := "the front rank" if String(r.get("rank", "front")) == "front" else "the second rank"
	var tip := _tip("Rulers in battle", "%s %s" % [RulesCodex.text("ruler_in_battle"), RulesCodex.text("ruler_rank")])
	var line := _text(col, "Ruler: %s, in %s: %d hit points, attack %d, defense %d (%d kept power), +%d morale to its side while it stands" % [
		_cap(name), rank, int(r.get("max_hp", 0)), int(r.get("attack", 0)), int(r.get("defense", 0)), int(r.get("kept_power", 0)),
		RulerData.RULER_MORALE], tip, 17)
	line.name = "RulerLine"
	CodexLink.attach(line, "ruler_in_battle", codex_requested.emit)
	var ending := ""
	if r.get("fell", false):
		ending = "%s fell in round %d, after dealing %d damage." % [_cap(name), int(r.get("fell_round", 0)), int(r.get("damage_dealt", 0))]
	elif String(sr.get("faction", "")) == String(_report.get("winner", "")):
		ending = "%s dealt %d damage and ended the battle with %d of %d hit points." % [_cap(name), int(r.get("damage_dealt", 0)),
			int(r.get("hp_end", 0)), int(r.get("max_hp", 0))]
	else:
		ending = "%s dealt %d damage and was still standing with %d of %d hit points, but was lost with its side." % [_cap(name),
			int(r.get("damage_dealt", 0)), int(r.get("hp_end", 0)), int(r.get("max_hp", 0))]
	var end_label := _text(col, ending, _tip("When a ruler dies", RulesCodex.text("ruler_death")), 17, UiPalette.TEXT_SECONDARY)
	end_label.name = "RulerEnding"
	CodexLink.attach(end_label, "ruler_death", codex_requested.emit)
	if int(r.get("dread", 0)) > 0:
		var ability := RulerRules.ability_name(String(r.get("id", "")))
		var dread := _text(col, "%s: every enemy side had %d less morale while %s stood." % [ability, int(r.dread), name],
			_tip(String(RulesCodex.entry("ability_dread").get("title", ability)), RulesCodex.text("ability_dread")), 17)
		dread.name = "DreadLine"
		CodexLink.attach(dread, "ability_dread", codex_requested.emit)


## The battle mandates a side fought with (M2-2), one line each with its codex entry.
func _add_mandate_lines(col: VBoxContainer, sr: Dictionary) -> void:
	var mandates: Array = sr.get("mandates", [])
	if mandates.is_empty():
		return
	var names := []
	for m in mandates:
		names.append(String(m.get("name", "")))
	var head := _text(col, "Mandates in play: %s" % ", ".join(names), _tip("Mandates", RulesCodex.text("mandates")), 17)
	head.name = "MandatesLine"
	CodexLink.attach(head, "mandates", codex_requested.emit)
	for m in mandates:
		var key := String(m.get("codex", "mandates"))
		var l := _text(col, "  %s: %s" % [m.get("name", ""), RulerRules.mandate_battle_text(String(m.get("id", "")))],
			_tip(String(RulesCodex.entry(key).get("title", m.get("name", ""))), RulesCodex.text(key)), 17, UiPalette.TEXT_SECONDARY)
		CodexLink.attach(l, key, codex_requested.emit)


func _add_terrain() -> void:
	var tip := _tip("Terrain in battle", RulesCodex.text("battle_terrain"))
	var box := _section("terrain", "Terrain and fort", tip, "battle_terrain")
	var terrain := String(_report.get("terrain", ""))
	var defender := _defender_side()
	if _report.get("kind", "province") == "border":
		_text(box, "This was a border battle: the armies met between two provinces while swapping places, so nobody was defending and nobody got terrain or fort bonuses.",
			_tip("Armies swapping places", RulesCodex.text("swap")))
		return
	if not terrain.is_empty():
		_text(box, "Terrain: %s" % terrain.capitalize(), tip, 20)
	if defender.is_empty():
		_text(box, "Everyone arrived at the same time, so nobody was defending and nobody got terrain or fort bonuses.",
			_tip("Armies meeting in a province", RulesCodex.text("same_province")))
		return
	var who := String(defender.get("name", ""))
	var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(terrain, {})
	var parts := []
	if int(bonus.get("defense", 0)) > 0:
		parts.append("+%d defense" % int(bonus.defense))
	if int(bonus.get("attack", 0)) > 0:
		parts.append("+%d attack" % int(bonus.attack))
	if terrain.is_empty():
		_text(box, "No terrain bonus applied here.", tip)
	elif parts.is_empty():
		_text(box, "%s give no bonus, even to the defending %s." % [terrain.capitalize(), who], tip)
	else:
		_text(box, "The defending %s got %s from the %s." % [who, " and ".join(parts), terrain], tip)
	if _report.get("fort", false):
		_text(box, "Fort: the defending %s got +%d defense more from the fort." % [who, AutoBattleResolver.FORT_DEFENSE], tip)
	else:
		_text(box, "Fort: none here.", tip)
	var triggers: Dictionary = defender.get("triggers", {})
	for key in ["terrain", "fort"]:
		var n := int(triggers.get(key, 0))
		if n > 0:
			_text(box, "The %s bonus changed %d %s." % ["terrain" if key == "terrain" else "fort", n, "attack" if n == 1 else "attacks"],
				_tip("Bonus used", "Counted once for every attack the bonus changed: each time the defender was attacked, and each attack it made with an attack bonus. %s" % RulesCodex.text("battle_terrain")), 17, UiPalette.TEXT_SECONDARY)


func _add_rounds() -> void:
	var box := _section("rounds", "Round by round", _tip("Battles", RulesCodex.text("battle_rounds")), "battle_rounds")
	var sides := _sides()
	var cap := int(_report.get("round_cap", AutoBattleResolver.ROUND_CAP))
	for r in _report.get("rounds", []):
		var n := int(r.get("round", 0))
		var heading := _text(box, "Round %d" % n,
			_tip("Round %d of at most %d" % [n, cap], "Every unit and commander still standing attacks once, all at the same time, so a unit that falls still strikes that round."), 20, UiPalette.TEXT_PRIMARY)
		heading.name = "Round%d" % n
		var highlights: Array = r.get("highlights", [])
		var line := String(r.get("line", ""))
		var summary := line.trim_prefix("Round %d: " % n)
		var tail := (" " + " ".join(highlights)) if not highlights.is_empty() else ""
		var split := not tail.is_empty() and summary.ends_with(tail)
		if split:
			summary = summary.trim_suffix(tail)
		_text(box, summary, _tip("Damage and hits", RulesCodex.text("battle_hit_chance")), 17)
		if split or tail.is_empty():
			for h in highlights:
				_text(box, "  - %s" % h, _highlight_tooltip(String(h)), 17, UiPalette.TEXT_SECONDARY)
		var hp: Dictionary = r.get("hp", {})
		var parts := []
		for sr in sides:
			parts.append("%s %d of %d" % [sr.get("name", ""), int(hp.get(sr.get("faction", ""), 0)), int(sr.get("hp_start", 0))])
		if not parts.is_empty():
			_text(box, "Hit points left: %s" % ", ".join(parts),
				_tip("Hit points left", "The hit points each side still had standing at the end of this round, out of what it started with. A side breaks once it has lost too much (see Morale and routs)."), 17, UiPalette.TEXT_SECONDARY)


func _add_casualties() -> void:
	var tip := _tip("Casualties", "Fighters are units, commanders and rulers. A unit or commander that falls is gone for good; a ruler that falls dies, and its successor comes later. %s" % RulesCodex.text("battle_rounds"))
	var box := _section("casualties", "Casualties", tip, "battle_rounds")
	var winner := String(_report.get("winner", ""))
	for sr in _sides():
		var lost: Array = sr.get("lost", [])
		var start := int(sr.get("fighters_start", 0))
		var text := "%s lost %d of %d %s" % [sr.get("name", ""), lost.size(), start, "fighter" if start == 1 else "fighters"]
		text += (": %s." % _grouped(lost)) if not lost.is_empty() else "."
		_text(box, text, tip, 18)
		_text(box, "Hit points left: %d of %d" % [int(sr.get("hp_end", 0)), int(sr.get("hp_start", 0))],
			_tip("Hit points left", "What this side had left standing when the battle ended, out of what it started with."), 17, UiPalette.TEXT_SECONDARY)
		if sr.get("routed", false):
			var fled := start - lost.size()
			var fled_text := "Its last fighter standing fled when it broke." if fled == 1 else "The other %d fled when it broke." % fled
			_text(box, fled_text, _tip("Morale and routs", RulesCodex.text("battle_morale")), 17, UiPalette.TEXT_SECONDARY)
		var feast: Dictionary = _report.get("feast", {})
		if String(sr.get("faction", "")) == winner and String(feast.get("faction", "")) == winner:
			var n := int(feast.get("fighters", 0))
			var feast_label := _text(box, "It won, and Feast of Victory healed its %s to full (+%d hit points)." % [
				"only surviving fighter" if n == 1 else "%d surviving fighters" % n, int(feast.get("healed", 0))],
				_tip(String(RulesCodex.entry("mandate_feast_of_victory").get("title", "")), RulesCodex.text("mandate_feast_of_victory")), 17, UiPalette.POSITIVE)
			feast_label.name = "FeastLine"
			CodexLink.attach(feast_label, "mandate_feast_of_victory", codex_requested.emit)
		elif String(sr.get("faction", "")) == winner and sr.get("mandates", []).any(func(m): return m.get("id", "") == RulerRules.FEAST_OF_VICTORY):
			var none := _text(box, "It won, and its survivors were already at full hit points, so Feast of Victory had nothing to heal.",
				_tip(String(RulesCodex.entry("mandate_feast_of_victory").get("title", "")), RulesCodex.text("mandate_feast_of_victory")), 17, UiPalette.TEXT_SECONDARY)
			CodexLink.attach(none, "mandate_feast_of_victory", codex_requested.emit)
		elif String(sr.get("faction", "")) == winner:
			_text(box, "It won, so its wounded survivors stay in its armies, still wounded.", tip, 17, UiPalette.TEXT_SECONDARY)
		else:
			_text(box, "It lost, so all of its armies there were destroyed or scattered (there are no retreats yet).", tip, 17, UiPalette.TEXT_SECONDARY)
		var r: Dictionary = sr.get("ruler", {})
		if not r.is_empty() and (r.get("fell", false) or String(sr.get("faction", "")) != winner):
			var death := "%s fell, though its side won: a ruler whose hit points reach 0 dies." % _cap(String(r.get("name", ""))) \
				if String(sr.get("faction", "")) == winner else "Its ruler, %s, was lost with it." % r.get("name", "")
			var death_label := _text(box, death, _tip("When a ruler dies", RulesCodex.text("ruler_death")), 17, NEGATIVE.lightened(0.15))
			CodexLink.attach(death_label, "ruler_death", codex_requested.emit)


func _add_routs() -> void:
	var box := _section("routs", "Morale and routs", _tip("Morale and routs", RulesCodex.text("battle_morale")), "battle_morale")
	var winner := String(_report.get("winner", ""))
	for sr in _sides():
		var checks: Array = sr.get("morale_log", [])
		var who := String(sr.get("name", ""))
		if sr.get("destroyed", false):
			_text(box, "%s never broke: it fought until no one was left standing." % who, _tip("Morale and routs", RulesCodex.text("battle_morale")), 18)
			continue
		if checks.is_empty():
			continue
		var e: Dictionary = checks.back()
		if sr.get("routed", false):
			for entry in checks:
				if int(entry.get("round", 0)) == int(sr.get("out_round", 0)):
					e = entry
			_text(box, "%s broke and fled in round %d: it had lost %d%% of its hit points, and its morale of %d holds only to %d%%." % [
				who, int(e.get("round", 0)), int(e.get("lost_pct", 0)), int(e.get("morale", 0)), int(e.get("break_pct", 0))],
				_morale_tooltip(sr, e), 18, NEGATIVE.lightened(0.15))
		elif _report.get("end", "") == "mutual" and String(sr.get("faction", "")) == winner:
			_text(box, "%s broke in round %d too, but kept the field: every side broke in the same round, and it had the most strength left. Its morale was %d, which holds to %d%% losses; it had lost %d%%." % [
				who, int(e.get("round", 0)), int(e.get("morale", 0)), int(e.get("break_pct", 0)), int(e.get("lost_pct", 0))],
				_morale_tooltip(sr, e), 18)
		elif e.has("held_by"):
			_text(box, "%s did not break, though it lost %d%% of its hit points and its morale of %d holds only to %d%%: Iron Discipline held it while its %s stood." % [
				who, int(e.get("lost_pct", 0)), int(e.get("morale", 0)), int(e.get("break_pct", 0)), String(e.get("held_by", ""))],
				_morale_tooltip(sr, e), 18)
		else:
			_text(box, "%s did not break: it lost %d%% of its hit points, and its morale of %d holds to %d%% losses." % [
				who, int(e.get("lost_pct", 0)), int(e.get("morale", 0)), int(e.get("break_pct", 0))],
				_morale_tooltip(sr, e), 18)
		# Iron Discipline (M2-2): rounds the side would have broken in but held while a commander stood.
		var held: Array = checks.filter(func(c): return c.has("held_by"))
		if not held.is_empty():
			var last: Dictionary = held.back()
			var rounds: Array = held.map(func(c): return str(int(c.get("round", 0))))
			var iron := _text(box, "Iron Discipline held %s in %s %s: it had lost %d%% with morale %d, which holds only to %d%%, but its %s still stood." % [
				who, "round" if held.size() == 1 else "rounds", ", ".join(rounds), int(last.get("lost_pct", 0)), int(last.get("morale", 0)),
				int(last.get("break_pct", 0)), String(last.get("held_by", ""))],
				_tip(String(RulesCodex.entry("mandate_iron_discipline").get("title", "")), RulesCodex.text("mandate_iron_discipline")), 17, UiPalette.TEXT_SECONDARY)
			iron.name = "IronLine"
			CodexLink.attach(iron, "mandate_iron_discipline", codex_requested.emit)


func _add_hits() -> void:
	var tip := _tip("Hit chance and damage", RulesCodex.text("battle_hit_chance"))
	var box := _section("hits", "Hit rates and luck", tip, "battle_hit_chance")
	for sr in _sides():
		var attacks := int(sr.get("attacks", 0))
		var who := String(sr.get("name", ""))
		if attacks == 0:
			_text(box, "%s made no attacks." % who, tip, 18)
			continue
		var rate := int(sr.get("hit_rate", 0))
		var expected := int(sr.get("expected_hit_rate", 0))
		var span: Array = sr.get("hit_chance_range", [0, 0])
		var lo := int(span[0]) if span.size() > 0 else 0
		var hi := int(span[1]) if span.size() > 1 else lo
		_text(box, "%s hit %d%% of the time (%d of %s)." % [who, rate, int(sr.get("hits", 0)), TooltipText.count(attacks, "attack")], tip, 18)
		var chance := "Each attack had a %d%% chance to hit." % lo if lo == hi \
			else "Each attack had a %d-%d%% chance to hit, about %d%% on average." % [lo, hi, expected]
		_text(box, chance, tip, 17, UiPalette.TEXT_SECONDARY)
		_text(box, "Damage dealt: %d (about %d expected from those chances)" % [int(sr.get("damage_dealt", 0)), roundi(float(sr.get("damage_expected", 0.0)))],
			_tip("Expected damage", "The damage this side would deal on average with the hit chances it had. More than expected means the dice were kind. %s" % RulesCodex.text("battle_hit_chance")), 17, UiPalette.TEXT_SECONDARY)
		var luck := "Luck: it hit about as often as its chances said."
		var color := UiPalette.TEXT_SECONDARY
		if rate > expected:
			luck = "Luck: it hit more often than its chances said."
			color = UiPalette.POSITIVE
		elif rate < expected:
			luck = "Luck: it hit less often than its chances said."
			color = NEGATIVE
		_text(box, luck, tip, 17, color)


func _add_round_cap() -> void:
	var tip := _tip(String(RulesCodex.entry("battle_round_cap").get("title", "Round limit")), RulesCodex.text("battle_round_cap"))
	var box := _section("round_cap", "Round limit reached", tip, "battle_round_cap")
	var cap := int(_report.get("round_cap", AutoBattleResolver.ROUND_CAP))
	_text(box, "Nobody had won after %s, so the battle stopped there." % TooltipText.count(cap, "round"), tip, 18)
	var winner := _winner_side()
	var who := String(winner.get("name", _report.get("winner_name", "")))
	if winner.get("defender", false):
		_text(box, "%s was defending, so it held its ground and won." % who, tip, 18)
	else:
		_text(box, "Nobody was defending, so %s won by having the larger share of its starting hit points left." % who, tip, 18)
	var numbers: Dictionary = _event.get("numbers", {})
	if numbers.get("tie_break", "") == "roll":
		_text(box, "The shares were exactly equal, so a seeded roll picked the winner.", tip, 17, UiPalette.TEXT_SECONDARY)


# --- text -----------------------------------------------------------------------------------------

## The report's own "Result: ..." line when it has one, otherwise "<winner> won after N rounds."
func _result_sentence() -> String:
	for line in _report.get("lines", []):
		if String(line).begins_with("Result: "):
			return String(line).trim_prefix("Result: ")
	var n := int(_report.get("rounds_fought", 0))
	return "%s won after %d %s." % [_report.get("winner_name", "The winner"), n, "round" if n == 1 else "rounds"]


func _why_tooltip() -> String:
	var titles := []
	for f in _report.get("factors", []):
		var key := _factor_entry(String(f.get("id", "")))
		var title := String(RulesCodex.entry(key).get("title", ""))
		if not title.is_empty() and not titles.has(title):
			titles.append(title)
	var text := "The biggest reasons this battle went the way it did, worked out from the battle itself. \"About N damage\" is how much damage a reason was worth on average, given the hit chances. An \"even though\" names the biggest thing that helped the loser."
	if not titles.is_empty():
		text += " The codex explains these in full (%s)." % ", ".join(titles)
	return _tip("Why", text)


func _role_text(sr: Dictionary) -> String:
	if _report.get("kind", "province") == "border":
		return "Met the enemy on the border while swapping places."
	if sr.get("defender", false):
		return "Defending: it was already holding the province."
	if _defender_side().is_empty():
		return "Arrived at the same time as the enemy: nobody was defending."
	return "Attacking: it moved into the province."


func _role_tooltip(sr: Dictionary) -> String:
	if _report.get("kind", "province") == "border":
		return _tip("Armies swapping places", RulesCodex.text("swap"))
	if sr.get("defender", false):
		return _tip("Holding a province", "%s %s" % [RulesCodex.text("hold"), RulesCodex.text("battle_terrain")])
	if _defender_side().is_empty():
		return _tip("Armies meeting in a province", RulesCodex.text("same_province"))
	return _tip("Moving into a defended province", RulesCodex.text("defended"))


func _highlight_tooltip(h: String) -> String:
	var key := "battle_rounds"
	if h.contains("charged"):
		key = "trait_charge"
	elif h.contains("berserk"):
		key = "trait_berserk"
	elif h.contains("Iron Discipline"):
		key = "mandate_iron_discipline"
	elif h.contains("broke"):
		key = "battle_morale"
	var entry := RulesCodex.entry(key)
	return _tip(String(entry.get("title", "")), String(entry.get("text", "")))


## A morale check as a breakdown: the side's average unit morale plus each effect, equal to the
## morale the report says it had. All values come from the report.
func _morale_tooltip(sr: Dictionary, e: Dictionary) -> String:
	var lines := [{"label": "Average morale of its units", "value": int(sr.get("base_morale", 0)), "note": "rounded down"}]
	var parts: Dictionary = e.get("parts", {})
	var keys: Array = parts.keys()
	keys.sort()
	for k in keys:
		lines.append({"label": MORALE_PART_NAMES.get(k, String(k)), "value": int(parts[k]), "note": ""})
	var b := {"title": "Morale of %s in round %d" % [sr.get("name", ""), int(e.get("round", 0))],
		"description": "This morale holds until the side has lost %d%% of its starting hit points; it had lost %d%%. %s" % [
			int(e.get("break_pct", 0)), int(e.get("lost_pct", 0)), RulesCodex.text("battle_morale")],
		"lines": lines, "total_label": "Morale", "total": int(e.get("morale", 0))}
	return TooltipText.from_breakdown(b)


## The codex entry of the biggest reason in the "why" (battles in general when there is none).
func _why_entry() -> String:
	for f in _report.get("factors", []):
		var key := _factor_entry(String(f.get("id", "")))
		if RulesCodex.ENTRIES.has(key):
			return key
	return "battle_rounds"


static func _factor_entry(factor_id: String) -> String:
	if FACTOR_ENTRIES.has(factor_id):
		return FACTOR_ENTRIES[factor_id]
	if factor_id.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return factor_id if RulesCodex.ENTRIES.has(factor_id) else "mandates"
	var trait_entry := AutoBattleResolver.codex_id_for_trait(factor_id.trim_prefix("morale_"))
	return trait_entry if RulesCodex.ENTRIES.has(trait_entry) else ""


## The player-facing name of an attack or defense part counted in a side's triggers: a trait's name, or
## a mandate's ("mandate_royal_armories" is Royal Armories).
static func _part_name(key: String) -> String:
	if key.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return RulerRules.mandate_name(key.trim_prefix(AutoBattleResolver.MANDATE_PREFIX))
	return key


## The RulesCodex entry of an attack or defense part: the trait's or the mandate's.
static func _part_entry(key: String) -> String:
	if key.begins_with(AutoBattleResolver.MANDATE_PREFIX):
		return _factor_entry(key)
	return AutoBattleResolver.codex_id_for_trait(key)


## "Spearmen (2), Crossbowmen" from ["Spearmen", "Crossbowmen", "Spearmen"], in first-seen order.
static func _grouped(names: Array) -> String:
	var counts := {}
	var order := []
	for n in names:
		if not counts.has(n):
			counts[n] = 0
			order.append(n)
		counts[n] += 1
	var parts := []
	for n in order:
		parts.append(n if counts[n] == 1 else "%s (%d)" % [n, counts[n]])
	return ", ".join(parts)


static func _tip(title: String, description: String) -> String:
	return TooltipText.plain(title, description) if not title.is_empty() else TooltipText.wrap_text(description)


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)


# --- report helpers -------------------------------------------------------------------------------

func _sides() -> Array:
	return _report.get("sides", [])


func _defender_side() -> Dictionary:
	for sr in _sides():
		if sr.get("defender", false):
			return sr
	return {}


func _winner_side() -> Dictionary:
	for sr in _sides():
		if sr.get("faction", "") == _report.get("winner", ""):
			return sr
	return {}


func _side_color(sr: Dictionary) -> Color:
	return side_color(String(sr.get("faction", "")))


## The seat colour a side is drawn in: by `seats` when given, otherwise the state's faction order,
## otherwise the faction data order (UiPalette.seat_order).
func side_color(faction_id: String) -> Color:
	return UiPalette.faction_color(_seats if not _seats.is_empty() else UiPalette.seat_order(_state), faction_id)


# --- nodes ----------------------------------------------------------------------------------------

func _section(key: String, heading: String, tooltip: String, codex_key: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Section_%s" % key
	box.set_meta("section", key)
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(box)
	_sections[key] = box
	if not heading.is_empty():
		var h := _text(box, heading, tooltip, 26, UiPalette.GILT)
		h.name = "Heading"
		CodexLink.attach(h, codex_key, codex_requested.emit)
	return box


func _card(color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = color
	style.border_width_left = 6
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	return card


## A wrapped line of text. Labels with a tooltip take the mouse so the tooltip shows.
func _text(parent: Control, text: String, tooltip: String = "", font_size: int = 18, color: Color = UiPalette.TEXT_PRIMARY) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _clear() -> void:
	_sections.clear()
	for c in content.get_children():
		if c == message_label:
			continue
		content.remove_child(c)
		c.queue_free()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Background"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_top = 40
	panel.offset_right = -80
	panel.offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	column.add_child(header)
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	title_label.text = "Battle report"
	header.add_child(title_label)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(120, 44)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.tooltip_text = "Close the battle report and go back to the turn report (Esc)."
	close_button.pressed.connect(close)
	header.add_child(close_button)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 22)
	scroll.add_child(content)

	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.add_theme_font_size_override("font_size", 26)
	message_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	message_label.visible = false
	content.add_child(message_label)
