class_name BuildScreen
extends Control
## The pre-game build screen (M2-5, #33; design/M2_RULER.md §4). Before a game with rulers, every human
## seat in seat order picks a build: one of its faction's two rulers and the mandates it buys with its
## power. Computer seats pick a preset in secret (§6.1, computer_preset), and nothing about their build
## is shown before the game starts. RulesCodex "build_screen" explains the screen to the player.
##
## Flow (begin): with two people, a cover goes up before each builder ("Pass the computer to player
## 2 ..."), and the screen under it is emptied, so the other player's build is never on screen; after the
## last builder, a last cover passes the computer back to player 1 for turn 1. With one person there is
## no cover at all. Lock in build moves on; when every human seat has locked in, `finished` hands over
## the game config: the new game screen's {"players", "seed", "ai"} plus "rulers": true and "builds"
## {faction id: {"ruler", "mandates"}} for every seat (a computer seat's build also names its "preset"),
## which GameScreen.start_game turns into the starting state (GameState.with_rulers).
##
## Layout (one screen at 1600x900, no scrolling): the header and the presets on top, then three columns:
##   ruler      the two ruler cards (name, rank, body, ability, succession), and the picked ruler at this
##              build's kept power next to spending or keeping everything, with a risk line and the
##              succession this build leaves
##   power      the keep-versus-spend meter and the mandate list; a mandate that no longer fits is
##              disabled with build_errors' reason
##   nation     what changes for your nation: the roster with every changed stat marked, the starting
##              army, gold and income, and the effects that are not numbers
## The screen does no math of its own: every number comes from RulerRules or Breakdown on the starting
## state this build would give (GameState.with_rulers), and its tooltip is that breakdown, so the two
## can't disagree. Each number label keeps the breakdown in its "breakdown" meta and the call that made
## it in "breakdown_source" (tests recompute it); a line of rule text keeps its codex key in "rule_codex".
## Every number and term links to its codex entry: right-click it, or press F1 while hovering, and the
## screen's own codex opens on top.
##
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   begin(config, last_builds)   starts the build phase for config ({"players", "seed", "ai"}).
##                                `last_builds` ({faction id: build}) are a rematch's builds of the human
##                                seats: each starts there instead of at the balanced preset
##   step                         IDLE, HANDOFF (a cover before a builder), BUILDING, START_HANDOFF (the
##                                cover before turn 1), DONE
##   seat, faction_id             the 0-based seat building now (or next, under a cover), its faction
##   current_build() -> {"ruler", "mandates"}
##   select_ruler(ruler_id) -> bool, set_mandate(mandate_id, on) -> bool, apply_preset(preset_id) -> bool,
##   clear_build()                the ruler cards, the mandate boxes, the preset buttons and Clear
##   lock_in() -> bool            the Lock in build button
##   acknowledge() -> bool        Ready / Start the game on a cover
##   back()                       the Back button (Esc): drops every build chosen so far, emits back_requested
##   computer_preset(faction_id, game_seed, seat) -> String   the preset a computer seat plays (static)
##   number_labels() -> Array     every label on screen that shows a number (for tests)

signal finished(config: Dictionary)
signal back_requested

enum Step { IDLE, HANDOFF, BUILDING, START_HANDOFF, DONE }

const SCENE := "res://ui/build_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"
const BACKGROUND := Color("#14131F")
const COVER_BACKGROUND := Color(0.06, 0.07, 0.09, 1.0)  # the handoff cover's (HandoffScreen)
const BREAKDOWN := "breakdown"  # meta: the breakdown dictionary behind a number on screen
const SOURCE := "breakdown_source"  # meta: the rules call that made it, [function name, arguments...]
const RULE := "rule_codex"  # meta: a line of rule text (its numbers are the rule itself), and its codex key
## Spent power pips take the colour of their mandate's area; kept pips are gilt (§4).
const AREA_COLORS := {"battle": Color("#C8664F"), "units": Color("#6F94D6"), "economy": Color("#78B36A"), "map": Color("#A980C8")}
const AREA_NAMES := {"battle": "battle", "units": "units", "economy": "economy", "map": "the map"}
const EMPTY_PIP := Color("#34324C")
const STATS := ["hp", "attack", "defense", "cost"]
const STAT_HEADS := {"hp": "Hit points", "attack": "Attack", "defense": "Defense", "cost": "Cost"}
const RULER_STATS := ["hp", "attack", "defense"]
const BODY_SIZE := 15
const SMALL_SIZE := 13

var game_config := {}  # the config being built for; "rulers" and "builds" are added at the end
var step: Step = Step.IDLE
var seat := -1
var faction_id := ""
var ruler_id := ""
var mandates: Array = []  # mandate ids in the order taken
var locked := {}  # faction id -> the build a human seat locked in
var remembered := {}  # faction id -> last game's build of a human seat (rematch)
var from_rematch := false  # the build on screen started from `remembered`

# Nodes. The page holds everything of one builder; it is emptied under every cover.
var page: VBoxContainer
var body: VBoxContainer  # rebuilt for each builder
var footer_note: Label
var back_button: Button
var lock_button: Button
var cover: Control
var cover_turn: Label
var cover_title: Label
var cover_body: Label
var cover_hint: Label
var ready_button: Button
var codex: CodexPanel = null  # built on first use

var header_label: Label
var intro_label: Label
var preset_buttons := {}  # preset id -> Button
var clear_button: Button
var ruler_buttons := {}  # ruler id -> CheckBox (a radio button in one group)
var ruler_cards := {}  # ruler id -> PanelContainer
var meter_label: Label
var meter_pips: Array[Panel] = []
var meter_sentence: Label
var mandate_checks := {}  # mandate id -> CheckBox
var mandate_reasons := {}  # mandate id -> Label ("Needs 4 power; 2 left.")
var mandate_rows := {}  # mandate id -> Control
var other_box: VBoxContainer
var _card_labels := {}  # ruler id -> {"body": [Label x3], "ability": Label, "succession": Label}
var _grid_labels := {}  # "hp" / "attack" / "defense" / "rank" -> [now, spend all, keep all] Labels
var _ruler_lines := {}  # "morale" / "ability" / "risk" / "succession" -> Label
var _roster_cells := {}  # unit type id -> {stat: [value Label, old value Label, Arrow]}
var _economy := {}  # "gold" / "income" -> Label
var _starting_label: Label
var _changes := {}  # mandate id -> what it alone changes for this faction (tooltip lines), per builder
var _model: GameState  # data only: faction names, capitals, rosters
var _ruler_group: ButtonGroup
var _icons := {}  # the outlined unticked icons, by size and shape


func _init() -> void:
	name = "BuildScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_model = GameState.new()
	_build()


## F1 over a linked number opens its codex entry (a right-click is handled by the link itself).
func _input(event: InputEvent) -> void:
	if not is_inside_tree() or not is_visible_in_tree() or not CodexLink.is_open_key(event):
		return
	var key := CodexLink.key_at(get_viewport().gui_get_hovered_control())
	if not key.is_empty():
		get_viewport().set_input_as_handled()
		open_codex(key)


# --- the flow -------------------------------------------------------------------------------------

## Starts the build phase for `config` ({"players", "seed", "ai"}, the new game screen's config). With
## no human seat (watch mode) there is nobody to ask: it finishes at once with the computers' presets.
func begin(config: Dictionary, last_builds: Dictionary = {}) -> void:
	game_config = config.duplicate(true)
	game_config.erase("builds")
	locked = {}
	remembered = {}
	for fid in last_builds:
		var b := RulerRules.normalize_build(last_builds[fid])
		remembered[String(fid)] = {"ruler": b.ruler, "mandates": b.mandates}
	visible = true
	close_codex()
	if human_seats().is_empty():
		_finish()
		return
	_go_to(0)


## 0-based seats people play, in seat order.
func human_seats() -> Array:
	var out := []
	var players := _players()
	var ai := _ai()
	for i in players.size():
		if not ai.has(String(players[i])):
			out.append(i)
	return out


## The build on screen: {"ruler", "mandates"} (mandates in the order taken).
func current_build() -> Dictionary:
	return {"ruler": ruler_id, "mandates": mandates.duplicate()}


func select_ruler(rid: String) -> bool:
	if step != Step.BUILDING or not RulerRules.rulers_for(faction_id).has(rid):
		return false
	ruler_id = rid
	_refresh()
	return true


## Ticks (on) or clears a mandate. Returns false, changing nothing, when the build would be illegal.
func set_mandate(mandate_id: String, on: bool) -> bool:
	if step != Step.BUILDING or not RulerRules.available_mandates(faction_id).has(mandate_id):
		_refresh()
		return false
	if on == mandates.has(mandate_id):
		_refresh()
		return true
	var next := mandates.duplicate()
	if on:
		next.append(mandate_id)
	else:
		next.erase(mandate_id)
	if not RulerRules.build_errors(faction_id, {"ruler": ruler_id, "mandates": next}).is_empty():
		_refresh()
		return false
	mandates = next
	_refresh()
	return true


## The faction's preset `preset_id`: its ruler and mandates.
func apply_preset(preset_id: String) -> bool:
	var b := RulerRules.preset_build(preset_id)
	if step != Step.BUILDING or b.is_empty() or RulerRules.preset_data(preset_id).get("faction", "") != faction_id:
		return false
	ruler_id = b.ruler
	mandates = b.mandates.duplicate()
	_refresh()
	return true


## No mandates: the picked ruler keeps all its power.
func clear_build() -> void:
	if step != Step.BUILDING:
		return
	mandates = []
	_refresh()


## Locks in the build on screen for this seat and moves on: the next builder's cover, the cover before
## turn 1, or the game. Every build the screen allows is legal, so this only fails outside BUILDING.
func lock_in() -> bool:
	if step != Step.BUILDING or not RulerRules.build_errors(faction_id, current_build()).is_empty():
		return false
	locked[faction_id] = current_build()
	var humans := human_seats()
	var next := humans.find(seat) + 1
	if next < humans.size():
		_go_to(next)
	elif humans.size() > 1:
		_show_start_cover()
	else:
		_finish()
	return true


## Ready (or Start the game) on a cover.
func acknowledge() -> bool:
	match step:
		Step.HANDOFF:
			_start_building()
			return true
		Step.START_HANDOFF:
			_finish()
			return true
	return false


## Back to the game setup. Every build chosen so far is dropped, so nobody can come back to a build
## that is not theirs.
func back() -> void:
	locked = {}
	_reset()
	step = Step.IDLE
	visible = false
	back_requested.emit()


## Esc: closes the codex if it is open, otherwise goes back while a build is on screen. Returns whether
## it did something. Under a cover Esc does nothing, so nobody drops the builds by accident.
func handle_cancel() -> bool:
	if codex != null and codex.visible:
		codex.close()
		return true
	if step == Step.BUILDING:
		back()
		return true
	return false


## The preset a computer seat plays (§6.1): presets[faction][roll], where the roll is the first draw of
## the seat's computer RNG, seeded like AISeat's (AISeat.seat_seed). The same seed and seat always give
## the same preset.
static func computer_preset(fid: String, game_seed: int, seat_index: int) -> String:
	var presets := RulerRules.presets_for(fid)
	if presets.is_empty():
		return ""
	var rng := SeededRNG.new(AISeat.seat_seed(game_seed, seat_index))
	return String(presets[rng.randi_range(0, presets.size() - 1)].id)


## Every visible label on the build page that shows a number (each carries the "breakdown" meta).
func number_labels() -> Array:
	var out := []
	_collect_numbers(page, out)
	return out


func open_codex(key: String = "") -> void:
	if codex == null:
		codex = load(CODEX_SCENE).instantiate()
		codex.name = "Codex"
		var bg := codex.get_node_or_null("Background") as PanelContainer
		if bg:
			bg.add_theme_stylebox_override("panel", UiPalette.panel_style())
		add_child(codex)
	move_child(codex, get_child_count() - 1)
	codex.open(key)


func close_codex() -> void:
	if codex != null and codex.visible:
		codex.close()


# --- the flow, inside -------------------------------------------------------------------------------

## Moves to the human seat at `index` (in human_seats()): behind a cover with two people, else at once.
func _go_to(index: int) -> void:
	var humans := human_seats()
	seat = humans[index]
	faction_id = String(_players()[seat])
	_reset()
	if humans.size() > 1:
		step = Step.HANDOFF
		var f := _model.find_faction(faction_id)
		cover_turn.text = "Builds  ·  Player %d" % (seat + 1)
		cover_title.text = "Pass to %s" % (f.faction_name if f else "the next player")
		cover_body.text = "Pass the computer to player %d to choose a ruler and mandates for the %s. Continue only when nobody else can see the screen." % [
			seat + 1, f.faction_name if f else "next faction"]
		if not locked.is_empty():
			cover_body.text += " The build already locked in stays hidden until the game starts."
		ready_button.text = "Ready"
		ready_button.tooltip_text = "Press when you have the computer and nobody else can see the screen."
		_show_cover()
		return
	_start_building()


func _start_building() -> void:
	step = Step.BUILDING
	from_rematch = remembered.has(faction_id) and RulerRules.build_errors(faction_id, remembered[faction_id]).is_empty()
	var start: Dictionary = remembered[faction_id] if from_rematch else RulerRules.preset_build(RulerRules.balanced_preset(faction_id))
	ruler_id = String(start.get("ruler", ""))
	mandates = Array(start.get("mandates", [])).duplicate()
	cover.visible = false
	page.visible = true
	_build_body()
	_refresh()
	if is_inside_tree():
		lock_button.grab_focus.call_deferred()


## Two people: every build is locked in, so the computer goes back to player 1 for the first orders.
func _show_start_cover() -> void:
	_reset()
	step = Step.START_HANDOFF
	var players := _players()
	var f := _model.find_faction(String(players[0])) if not players.is_empty() else null
	cover_turn.text = "Builds locked in"
	cover_title.text = "Pass to %s" % (f.faction_name if f else "player 1")
	cover_body.text = "Every build is locked in. Pass the computer to player 1, who plays the %s and gives the first orders. From the first turn both builds are public: hover a ruler's army to see its build." % (
		f.faction_name if f else "first faction")
	ready_button.text = "Start the game"
	ready_button.tooltip_text = "Press when player 1 has the computer. The game starts with player 1's orders for turn 1."
	_show_cover()


func _show_cover() -> void:
	page.visible = false
	cover.visible = true
	if is_inside_tree():
		ready_button.grab_focus.call_deferred()


## Empties the page (nothing of a build stays in the tree) and hides the cover.
func _reset() -> void:
	close_codex()
	_clear(body)
	preset_buttons = {}
	ruler_buttons = {}
	ruler_cards = {}
	mandate_checks = {}
	mandate_reasons = {}
	mandate_rows = {}
	meter_pips = []
	_card_labels = {}
	_grid_labels = {}
	_ruler_lines = {}
	_roster_cells = {}
	_economy = {}
	_changes = {}
	ruler_id = ""
	mandates = []
	from_rematch = false
	# The footer stays, so it must not keep naming the last build either.
	lock_button.tooltip_text = ""
	footer_note.visible = false
	page.visible = false
	cover.visible = false


func _finish() -> void:
	var cfg := game_config.duplicate(true)
	cfg["rulers"] = true
	var builds := {}
	var players := _players()
	for i in players.size():
		var fid := String(players[i])
		builds[fid] = locked[fid].duplicate(true) if locked.has(fid) else RulerRules.preset_build(computer_preset(fid, _seed(), i))
	cfg["builds"] = builds
	_reset()
	step = Step.DONE
	visible = false
	finished.emit(cfg)


func _players() -> Array:
	return Array(game_config.get("players", []))


func _ai() -> Dictionary:
	return game_config.get("ai", {}) if game_config.get("ai") is Dictionary else {}


func _seed() -> int:
	return int(game_config.get("seed", 0))


# --- what the build gives: every number from RulerRules and Breakdown --------------------------------

## The starting state this build gives (what GameScreen.starting_state builds), or null.
func _state_for(build: Dictionary) -> GameState:
	return GameState.with_rulers(_seed(), {faction_id: build}, [])


func _kept() -> int:
	return RulerRules.kept_after(current_build())


func _capital_name() -> String:
	var f := _model.find_faction(faction_id)
	var p := _model.find_province(f.capital) if f else null
	return p.name if p else "the capital"


## The successor's kept power if the ruler died with this build (§5.2), as a breakdown whose lines sum
## up: kept power now, then what the succession takes. From RulerRules.successor_for.
static func successor_breakdown(rid: String, kept: int, capital_name: String) -> Dictionary:
	var next := RulerRules.successor_for(rid, kept, 1)
	var rule: Dictionary = RulerRules.ruler_data(rid).get("succession", {})
	var note := "the same kept power"
	match String(rule.get("power", "same")):
		"half":
			note = "half, rounded down"
		"minus":
			note = "%d less, never below 0" % int(rule.get("minus", 0))
	var kind: Dictionary = RulerData.KINDS.get(String(next.kind), {})
	return {"title": "If %s dies" % RulerRules.ruler_name(rid, 1),
		"description": RulerRules.succession_text(rid, kept, 1, capital_name),
		"lines": [{"label": "Kept power of %s" % RulerRules.ruler_name(rid, 1), "value": kept, "note": "with this build"},
			{"label": "Succession", "value": int(next.kept_power) - kept, "note": note}],
		"total_label": "Kept power of %s" % next.heir_name, "total": int(next.kept_power),
		"codex": String(kind.get("codex", "succession"))}


## What `mandate_id` alone changes for this faction's roster, one line per changed number, from
## RulerRules.unit_stats with and without it: "Spearmen: hit points 10 to 12". (Words, not arrows: the
## game's font has no arrow glyphs.)
func _change_lines(mandate_id: String) -> Array:
	if _changes.has(mandate_id):
		return _changes[mandate_id]
	var out := []
	var rid := String(RulerRules.rulers_for(faction_id)[0])
	var plain := _state_for({"ruler": rid, "mandates": []})
	var with_it := _state_for({"ruler": rid, "mandates": [mandate_id]})
	if plain != null and with_it != null:
		for ut_id in _roster_ids():
			var a := RulerRules.unit_stats(plain, faction_id, ut_id)
			var b := RulerRules.unit_stats(with_it, faction_id, ut_id)
			var parts := []
			for stat in STATS:
				if int(a[stat]) != int(b[stat]):
					parts.append("%s %d to %d%s" % [String(STAT_HEADS[stat]).to_lower(), int(a[stat]), int(b[stat]), " gold" if stat == "cost" else ""])
			if not parts.is_empty():
				out.append("%s: %s" % [a.name, ", ".join(parts)])
	_changes[mandate_id] = out
	return out


## The roster in the side panel's order: the regular units, then the commander.
func _roster_ids() -> Array:
	var out := []
	var f := _model.find_faction(faction_id)
	if f == null:
		return out
	for ut in f.unit_types:
		out.append(ut.id)
	if f.commander_type:
		out.append(f.commander_type.id)
	return out


# --- refresh: the build on screen -> every label ------------------------------------------------------

func _refresh() -> void:
	if step != Step.BUILDING or ruler_buttons.is_empty():
		return
	var build := current_build()
	var kept := _kept()
	var state := _state_for(build)
	var base := _state_for({"ruler": ruler_id, "mandates": []})
	var f := _model.find_faction(faction_id)
	var rname := RulerRules.ruler_name(ruler_id, 1)

	# Presets: the one this build is shows pressed.
	for pid in preset_buttons:
		var p := RulerRules.preset_build(pid)
		(preset_buttons[pid] as Button).set_pressed_no_signal(p.ruler == ruler_id and p.mandates == mandates)
	clear_button.set_pressed_no_signal(mandates.is_empty())

	# Ruler cards, each at this build's kept power.
	for rid in ruler_buttons:
		(ruler_buttons[rid] as CheckBox).set_pressed_no_signal(rid == ruler_id)
		_style_card(ruler_cards[rid], rid == ruler_id)
		var cl: Dictionary = _card_labels[rid]
		var heads := ["Hit points %d", "attack %d", "defense %d"]
		for i in RULER_STATS.size():
			var stat: String = RULER_STATS[i]
			var b := Breakdown.ruler_stat_at(rid, stat, kept)
			_number(cl.body[i], heads[i] % int(b.total), b, ["ruler_stat_at", rid, stat, kept])
		var rank := Breakdown.ability_rank_at(rid, kept)
		_number(cl.ability, "rank %d: %s" % [int(rank.total), RulerRules.ability_short(rid, int(rank.total))], rank,
			["ability_rank_at", rid, kept])
		var sb := successor_breakdown(rid, kept, _capital_name())
		_number(cl.succession, _succession_short(rid), sb, ["successor", rid, kept])

	# The picked ruler at this kept power, next to spending all (0 kept) and keeping all (10 kept).
	var keeps := [kept, 0, RulerData.POWER_POOL]
	for stat in RULER_STATS:
		for i in 3:
			var b := Breakdown.ruler_stat_at(ruler_id, stat, keeps[i])
			_number(_grid_labels[stat][i], str(int(b.total)), b, ["ruler_stat_at", ruler_id, stat, keeps[i]])
	for i in 3:
		var b := Breakdown.ability_rank_at(ruler_id, keeps[i])
		_number(_grid_labels.rank[i], str(int(b.total)), b, ["ability_rank_at", ruler_id, keeps[i]])
	var morale := Breakdown.ruler_stat_at(ruler_id, "morale", kept)
	_number(_ruler_lines.morale, "Morale %d when it fights alone, and +%d to its side while it stands." % [int(morale.total), RulerData.RULER_MORALE],
		morale, ["ruler_stat_at", ruler_id, "morale", kept])
	var rank_now := Breakdown.ability_rank_at(ruler_id, kept)
	_number(_ruler_lines.ability, "%s at rank %d: %s" % [RulerRules.ability_name(ruler_id), int(rank_now.total),
		RulerRules.ability_text(ruler_id, int(rank_now.total))], rank_now, ["ability_rank_at", ruler_id, kept])
	_rule(_ruler_lines.risk, _risk_text(ruler_id, kept), TooltipText.plain("Where %s fights" % rname,
		"%s %s" % [RulesCodex.text("ruler_rank"), RulesCodex.text("ruler_death")]), "ruler_rank")
	_number(_ruler_lines.succession, RulerRules.succession_text(ruler_id, kept, 1, _capital_name()),
		successor_breakdown(ruler_id, kept, _capital_name()), ["successor", ruler_id, kept])

	# The keep-versus-spend meter.
	var kb := Breakdown.build_kept_power(build)
	_number(meter_label, "Power pool %d  ·  spent %d  ·  kept %d" % [RulerData.POWER_POOL, RulerRules.build_cost(build), int(kb.total)],
		kb, ["build_kept_power"])
	var pips := []
	for i in kept:
		pips.append({"color": UiPalette.GILT, "tip": TooltipText.plain("Kept power", "%s keeps this power: it adds to the ruler's hit points, attack, defense and ability rank." % RulerRules._cap(rname))})
	for mid in mandates:
		var md := RulerRules.mandate_data(mid)
		for i in int(md.cost):
			pips.append({"color": AREA_COLORS.get(String(md.area), EMPTY_PIP), "tip": TooltipText.plain("Spent on %s" % md.name, String(md.effect))})
	for i in meter_pips.size():
		var pip := meter_pips[i]
		var info: Dictionary = pips[i] if i < pips.size() else {"color": EMPTY_PIP, "tip": "Unused power."}
		(pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = info.color
		pip.tooltip_text = info.tip
	meter_sentence.text = "Power you keep makes %s stronger in person; power you spend buys mandates your whole nation keeps all game, even if the ruler dies." % rname

	# Mandates: ticked, free to tick, or disabled with the reason.
	for mid in mandate_checks:
		var check: CheckBox = mandate_checks[mid]
		var md := RulerRules.mandate_data(mid)
		var taken := mandates.has(mid)
		var with_it := mandates.duplicate()
		if not taken:
			with_it.append(mid)
		var errors := RulerRules.build_errors(faction_id, {"ruler": ruler_id, "mandates": with_it})
		check.set_pressed_no_signal(taken)
		check.disabled = not taken and not errors.is_empty()
		var tip := _mandate_tooltip(mid, errors if check.disabled else [])
		check.tooltip_text = tip
		CodexLink.attach(check, String(md.codex), open_codex)
		var reason: Label = mandate_reasons[mid]
		reason.visible = check.disabled
		if check.disabled:
			_number(reason, "Needs %d power; %d left." % [int(md.cost), kept], kb, ["build_kept_power"], "",
				TooltipText.wrap_text("You can't take %s: %s" % [md.name, " ".join(errors)]))
		var row: Control = mandate_rows[mid]
		row.modulate = Color(1, 1, 1, 0.55) if check.disabled else Color(1, 1, 1, 1)

	# What changes for your nation: the roster, with every number a mandate changes marked.
	for ut_id in _roster_cells:
		for stat in STATS:
			var cells: Array = _roster_cells[ut_id][stat]
			var now := Breakdown.unit_stat(state, faction_id, ut_id, stat) if state else {}
			var was := Breakdown.unit_stat(base, faction_id, ut_id, stat) if base else {}
			var changed := int(now.get("total", 0)) != int(was.get("total", 0))
			var up := int(now.get("total", 0)) > int(was.get("total", 0))
			var good: bool = up != (stat == "cost")  # a higher stat is good, a higher price is not
			var color: Color = (UiPalette.POSITIVE if good else UiPalette.NEGATIVE) if changed else UiPalette.TEXT_PRIMARY
			_number(cells[0], str(int(now.get("total", 0))), now, ["unit_stat", "build", ut_id, stat])
			cells[0].add_theme_color_override("font_color", color)
			var arrow: Arrow = cells[2]
			arrow.visible = changed
			arrow.up = up
			arrow.color = color
			cells[1].visible = changed
			if changed:
				_number(cells[1], "was %d" % int(was.total), was, ["unit_stat", "base", ut_id, stat])
	var army := _starting_army_text(state)
	_rule(_starting_label, army, TooltipText.plain("Your starting armies", "%s %s" % [RulesCodex.text("ruler_army"),
		"Mandates that change unit numbers count for the starting army too."]), "ruler_army")
	if state and f:
		var gold := Breakdown.gold(state, faction_id)
		var gold_now := state.find_faction(faction_id).gold
		_number(_economy.gold, "Gold: %d to start, %d on turn 2 before recruits" % [gold_now, int(gold.total)], gold, ["gold"], "gold")
		var income := Breakdown.province_income(state, f.capital)
		_number(_economy.income, "Income on turn 1: %d from %s" % [int(income.total), _capital_name()], income, ["province_income", f.capital], "province_income")

	# The effects that are not numbers, one line per mandate.
	_clear(other_box)
	var others := 0
	for mid in mandates:
		var md := RulerRules.mandate_data(mid)
		if md.has("units") or md.has("recruit_divisor"):
			continue
		others += 1
		var l := _label("Other_%s" % mid, "", SMALL_SIZE, UiPalette.TEXT_PRIMARY, true)
		other_box.add_child(l)
		var vassal: Dictionary = Forecast.vassal(state, faction_id) if mid == RulerRules.SWORN_VASSALS and state else {}
		if not String(vassal.get("province", "")).is_empty():
			# §4: the province Sworn Vassals would take on turn 1, from the capture phase's own pick.
			var pid := String(vassal.province)
			var p := state.find_province(pid)
			_number(l, "%s: %s (%d gold) would join you at the end of turn 1." % [md.name, p.name, p.income],
				Breakdown.province_income(state, pid), ["province_income", pid], "",
				TooltipText.wrap_text("%s %s" % [md.effect, String(vassal.text)]))
			CodexLink.attach(l, String(md.codex), open_codex)
		else:
			_rule(l, "%s: %s" % [md.name, md.effect], _mandate_tooltip(mid, []), String(md.codex))
	if others == 0:
		var none := _label("NoOtherEffects", "", SMALL_SIZE, UiPalette.TEXT_SECONDARY, true)
		none.text = "None: no mandate of this build works outside the numbers above." if not mandates.is_empty() \
			else "None: with no mandates nothing changes for your nation, and all the power stays with your ruler."
		none.tooltip_text = TooltipText.plain("Other effects", RulesCodex.text("mandates"))
		none.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(none, "mandates", open_codex)
		other_box.add_child(none)

	footer_note.visible = from_rematch
	lock_button.tooltip_text = TooltipText.plain("Lock in build", "Lock in %s with %s for the %s. %s" % [
		rname, _mandate_list(mandates), f.faction_name if f else "", _after_lock_text()])


## "Mortal line: an heir in 2 turns, with half the kept power" (from the ruler's data and successor_for).
func _succession_short(rid: String) -> String:
	var next := RulerRules.successor_for(rid, RulerData.POWER_POOL, 1)
	var rule: Dictionary = RulerRules.ruler_data(rid).get("succession", {})
	var delay := int(next.delay)
	var turns := TooltipText.count(delay, "turn")
	match String(rule.get("power", "same")):
		"half":
			return "%s: an heir in %s, with half the kept power" % [RulerRules._cap(RulerRules.kind_name(rid)), turns]
		"minus":
			return "%s: back in %s, with %d less kept power for good" % [RulerRules._cap(RulerRules.kind_name(rid)), turns, int(rule.get("minus", 0))]
	return "%s: back in %s, with all its kept power" % [RulerRules._cap(RulerRules.kind_name(rid)), turns]


## The risk line (§4): where the ruler stands in battle and what little or much kept power means there.
func _risk_text(rid: String, kept: int) -> String:
	var front := RulerRules.battle_rank(rid) == "front"
	var text := "Front rank: enemies can attack it from the first round." if front \
		else "Second rank: enemies reach it only once every front-rank fighter on its side has fallen."
	if kept <= 2:
		text += " With this little kept power it is likely to fall in a real battle, even when its side wins: keep it at home." if front \
			else " With this little kept power it is safer behind the front, but a ruler on a losing side is lost with its army."
	elif kept >= RulerData.POWER_POOL - 1:
		text += " With this much kept power it rarely falls in an even battle."
	else:
		text += " A ruler on a losing side is lost with its army, so pick its battles."
	return text


## "Army 1 at Crownkeep: Spearmen, Crossbowmen and Knights, led by a Knight Captain. Beside it, King
## Corvane I travels alone, as his own army." From the starting state.
func _starting_army_text(state: GameState) -> String:
	if state == null:
		return ""
	var f := state.find_faction(faction_id)
	var parts := PackedStringArray()
	for a in state.armies:
		if a.owner != faction_id or a.ruler != null:
			continue
		var names := []
		for u in a.units:
			names.append(u.type.name)
		var text := "Starting army at %s: %s" % [_capital_name(), RulerRules._and_list(names)]
		if a.commander:
			text += ", led by a %s" % a.commander.type.name
		parts.append(text + ".")
	if f and f.has_ruler():
		parts.append("Beside it, %s travels alone, as a ruler's own army." % RulerRules.current_name(state, faction_id))
	return " ".join(parts)


## A mandate's tooltip: its cost and rule, what it alone changes for this faction, and why it can't be
## taken now (build_errors' reasons) when it can't.
func _mandate_tooltip(mid: String, errors: Array) -> String:
	var md := RulerRules.mandate_data(mid)
	var f := _model.find_faction(faction_id)
	var lines := PackedStringArray()
	lines.append("%s (%s)" % [md.name, TooltipText.count(int(md.cost), "power", "power")])
	lines.append(TooltipText.wrap_text(String(md.effect)))
	lines.append("")
	var changes := _change_lines(mid)
	if changes.is_empty():
		lines.append(TooltipText.wrap_text("It changes no unit numbers for the %s: it works in %s." % [
			f.faction_name if f else "faction", AREA_NAMES.get(String(md.area), "the game")]))
	else:
		lines.append("What it changes for the %s:" % (f.faction_name if f else "faction"))
		for c in changes:
			lines.append("  " + c)
	if not errors.is_empty():
		lines.append("")
		lines.append(TooltipText.wrap_text("You can't take it now: %s" % " ".join(errors)))
	return "\n".join(lines)


static func _mandate_list(ids: Array) -> String:
	if ids.is_empty():
		return "no mandates"
	var names := []
	for mid in ids:
		names.append(RulerRules.mandate_name(mid))
	return RulerRules._and_list(names)


func _after_lock_text() -> String:
	var humans := human_seats()
	var next := humans.find(seat) + 1
	if next < humans.size():
		return "Then the screen is covered so you can pass the computer to player %d, who never sees your build." % (int(humans[next]) + 1)
	if humans.size() > 1:
		return "Then the screen is covered so you can pass the computer back to player 1 for the first turn."
	return "Then the game starts."


# --- labels ---------------------------------------------------------------------------------------

## Shows a number: `text`, its breakdown as the tooltip, a codex link, and the breakdown and the rules
## call behind it in metas.
func _number(l: Label, text: String, breakdown: Dictionary, source: Array, kind: String = "", extra: String = "") -> void:
	l.text = text
	l.tooltip_text = TooltipText.from_breakdown(breakdown) + ("" if extra.is_empty() else "\n\n" + extra)
	l.set_meta(BREAKDOWN, breakdown)
	l.set_meta(SOURCE, source)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	var key := TooltipText.codex_for(kind, breakdown)
	if key.is_empty():
		CodexLink.detach(l)
	else:
		CodexLink.attach(l, key, open_codex)


## Shows a line of rule text, linked to its codex entry.
func _rule(l: Label, text: String, tooltip: String, key: String) -> void:
	l.text = text
	l.tooltip_text = tooltip
	l.set_meta(RULE, key)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, key, open_codex)


func _collect_numbers(node: Node, out: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label and (node as Label).has_meta(BREAKDOWN):
		out.append(node)
	for c in node.get_children():
		_collect_numbers(c, out)


# --- nodes ----------------------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 24)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	add_child(margin)
	page = VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", 6)
	page.visible = false
	margin.add_child(page)
	body = VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	page.add_child(body)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 16)
	footer.alignment = BoxContainer.ALIGNMENT_END  # the buttons stay right, with or without the note
	page.add_child(footer)
	footer_note = _label("RematchNote", "Rematch: your build from the last game is picked. A preset or Clear starts over.", BODY_SIZE, UiPalette.GILT, true)
	footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_note.visible = false
	footer.add_child(footer_note)
	back_button = _button("BackButton", "Back", 150, "Back to the game setup (Esc). The builds chosen so far are dropped, so every player picks again.")
	back_button.pressed.connect(back)
	footer.add_child(back_button)
	lock_button = _button("LockInButton", "Lock in build", 240, "")
	lock_button.add_theme_font_size_override("font_size", 24)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_RAISED.lightened(0.08 if state_name == "hover" else 0.0)
		sb.border_color = UiPalette.GILT
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		lock_button.add_theme_stylebox_override(state_name, sb)
	lock_button.pressed.connect(func(): lock_in())
	footer.add_child(lock_button)

	_build_cover()


## The handoff cover between builders, like the in-game HandoffScreen: opaque, and the page under it
## is emptied.
func _build_cover() -> void:
	cover = Control.new()
	cover.name = "Cover"
	cover.visible = false
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = COVER_BACKGROUND
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	cover_turn = _center_label("CoverTurn", 22, Color(0.75, 0.78, 0.85))
	box.add_child(cover_turn)
	cover_title = _center_label("CoverTitle", 48, Color(1, 1, 1))
	box.add_child(cover_title)
	cover_body = _center_label("CoverBody", 22, Color(0.9, 0.9, 0.9))
	box.add_child(cover_body)
	cover_hint = _center_label("CoverHint", 18, Color(0.65, 0.68, 0.75))
	cover_hint.text = "Builds are picked in secret and are public from the first turn, so battle odds can count the enemy's mandates."
	cover_hint.tooltip_text = TooltipText.plain(CodexLink.title("build_screen"), RulesCodex.text("build_screen"))
	CodexLink.attach(cover_hint, "build_screen", open_codex)
	box.add_child(cover_hint)
	ready_button = Button.new()
	ready_button.name = "ReadyButton"
	ready_button.text = "Ready"
	ready_button.custom_minimum_size = Vector2(260, 64)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ready_button.add_theme_font_size_override("font_size", 28)
	ready_button.pressed.connect(func(): acknowledge())
	box.add_child(ready_button)


## The page of one builder: header, presets and the three columns.
func _build_body() -> void:
	_clear(body)
	var f := _model.find_faction(faction_id)
	var fname := f.faction_name if f else "your faction"

	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 12)
	body.add_child(head)
	head.add_child(SeatEmblem.new(seat, SeatEmblem.Look.TOKEN, 26.0))
	header_label = _label("HeaderLabel", "Player %d, %s: choose your ruler and how much power to keep." % [seat + 1, fname], 24, UiPalette.TEXT_PRIMARY)
	header_label.add_theme_color_override("font_color", UiPalette.seat_color(seat).lightened(0.35))
	header_label.tooltip_text = TooltipText.plain(CodexLink.title("build_screen"), RulesCodex.text("build_screen"))
	header_label.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(header_label, "build_screen", open_codex)
	head.add_child(header_label)
	intro_label = _label("IntroLabel", "", BODY_SIZE, UiPalette.TEXT_SECONDARY, true)
	intro_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_label.text = "Your build is secret until the game starts. Hover any number to see where it comes from; right-click it for the rule."
	head.add_child(intro_label)

	var presets := HBoxContainer.new()
	presets.name = "Presets"
	presets.add_theme_constant_override("separation", 10)
	body.add_child(presets)
	var plabel := _label("PresetsLabel", "Presets:", 18, UiPalette.GILT)
	plabel.tooltip_text = TooltipText.plain(CodexLink.title("build_presets"), RulesCodex.text("build_presets"))
	plabel.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(plabel, "build_presets", open_codex)
	presets.add_child(plabel)
	for p in RulerRules.presets_for(faction_id):
		var pid := String(p.id)
		var b := _button("Preset_%s" % pid, "%s (%s)" % [p.name, p.style], 0, _preset_tooltip(p))
		_style_chip(b)
		b.pressed.connect(func(): apply_preset(pid))
		CodexLink.attach(b, "build_presets", open_codex)
		presets.add_child(b)
		preset_buttons[pid] = b
	clear_button = _button("ClearButton", "Clear (keep all)", 0, TooltipText.plain("Clear", "No mandates: your ruler keeps all %d power, for the most hit points, attack, defense and ability rank it can have. Your nation gets nothing extra." % RulerData.POWER_POOL))
	_style_chip(clear_button)
	clear_button.pressed.connect(clear_build)
	CodexLink.attach(clear_button, "kept_power", open_codex)
	presets.add_child(clear_button)

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	body.add_child(columns)
	columns.add_child(_ruler_column())
	columns.add_child(_power_column())
	columns.add_child(_nation_column())


func _preset_tooltip(p: Dictionary) -> String:
	var b := RulerRules.preset_build(String(p.id))
	var text := "%s with %s, keeping %d of %d power." % [RulerRules._cap(RulerRules.ruler_name(b.ruler, 1)), _mandate_list(b.mandates),
		RulerRules.kept_after(b), RulerData.POWER_POOL]
	if String(p.style) == BuildPresetData.BALANCED:
		text += " This is the build each player starts with."
	text += " A computer player picks one of these three presets."
	return TooltipText.plain("%s (%s)" % [p.name, p.style], text)


func _ruler_column() -> Control:
	var panel := _column("RulerColumn", 1.0)
	var col := panel.get_child(0) as VBoxContainer
	col.add_child(_heading("RulerHeading", "1. Your ruler", "ruler"))
	_ruler_group = ButtonGroup.new()
	for rid in RulerRules.rulers_for(faction_id):
		col.add_child(_ruler_card(rid))
	var sub := _heading("RulerPreviewHeading", "Your ruler with this build", "ruler_power")
	col.add_child(sub)
	var grid := GridContainer.new()
	grid.name = "RulerGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	var head_tips := ["", "With this build.", "If you spent all %d power on mandates (0 kept)." % RulerData.POWER_POOL,
		"If you kept all %d power (no mandates)." % RulerData.POWER_POOL]
	var heads := ["", "Now", "Spend all", "Keep all"]
	for i in heads.size():
		var h := _label("GridHead%d" % i, heads[i], SMALL_SIZE, UiPalette.TEXT_SECONDARY)
		if not String(head_tips[i]).is_empty():
			h.tooltip_text = TooltipText.plain(heads[i], head_tips[i])
			h.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(h)
	var rows := {"hp": "Hit points", "attack": "Attack", "defense": "Defense", "rank": "Ability rank"}
	for key in rows:
		var name_label := _label("Grid_%s" % key, rows[key], BODY_SIZE, UiPalette.TEXT_PRIMARY)
		name_label.tooltip_text = TooltipText.plain(rows[key], RulesCodex.text("ability_rank") if key == "rank" else RulesCodex.text("kept_power"))
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(name_label, "ability_rank" if key == "rank" else "ruler_power", open_codex)
		grid.add_child(name_label)
		var cells := []
		for i in 3:
			var l := _label("Grid_%s_%d" % [key, i], "", BODY_SIZE + 1 if i == 0 else BODY_SIZE, UiPalette.GILT if i == 0 else UiPalette.TEXT_DISABLED)
			grid.add_child(l)
			cells.append(l)
		_grid_labels[key] = cells
	for key in ["morale", "ability", "risk", "succession"]:
		var l := _label("Ruler_%s" % key, "", SMALL_SIZE, UiPalette.TEXT_SECONDARY if key == "risk" else UiPalette.TEXT_PRIMARY, true)
		col.add_child(l)
		_ruler_lines[key] = l
	return panel


func _ruler_card(rid: String) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_%s" % rid
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style(false))
	card.gui_input.connect(func(event: InputEvent):
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			select_ruler(rid))
	ruler_cards[rid] = card
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(row)
	row.add_child(_portrait(rid))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(box)
	var rname := RulerRules._cap(RulerRules.ruler_name(rid, 1))
	var pick := CheckBox.new()
	pick.name = "Pick_%s" % rid
	pick.text = rname
	pick.button_group = _ruler_group
	pick.add_theme_font_size_override("font_size", 20)
	_style_box(pick)
	pick.tooltip_text = TooltipText.plain(rname, "%s %s." % [String(RulerRules.ruler_data(rid).get("flavour", "")),
		RulerRules._cap(RulerRules.kind_line(rid))])
	pick.pressed.connect(func(): select_ruler(rid))
	CodexLink.attach(pick, "ruler_" + rid, open_codex)
	box.add_child(pick)
	ruler_buttons[rid] = pick
	var rank := _label("Rank_%s" % rid, "", SMALL_SIZE, UiPalette.TEXT_SECONDARY)
	_rule(rank, RulerRules._cap(String(RulerData.BATTLE_RANKS.get(RulerRules.battle_rank(rid), ""))),
		TooltipText.plain(CodexLink.title("ruler_rank"), RulesCodex.text("ruler_rank")), "ruler_rank")
	box.add_child(rank)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(stats)
	var body_labels := []
	for i in RULER_STATS.size():
		if i > 0:
			stats.add_child(_label("Dot", "·", SMALL_SIZE, UiPalette.TEXT_DISABLED))
		var l := _label("Body_%s_%s" % [rid, RULER_STATS[i]], "", SMALL_SIZE + 1, UiPalette.TEXT_PRIMARY)
		stats.add_child(l)
		body_labels.append(l)
	var ability := HBoxContainer.new()
	ability.add_theme_constant_override("separation", 5)
	ability.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(ability)
	var ability_name := _label("AbilityName_%s" % rid, "", SMALL_SIZE + 1, UiPalette.GILT)
	var akey := "ability_" + String(RulerRules.ruler_data(rid).get("ability", ""))
	_rule(ability_name, RulerRules.ability_name(rid), TooltipText.plain(CodexLink.title(akey), RulesCodex.text(akey)), akey)
	ability.add_child(ability_name)
	var ability_value := _label("Ability_%s" % rid, "", SMALL_SIZE + 1, UiPalette.TEXT_PRIMARY)
	ability.add_child(ability_value)
	var succession := _label("Succession_%s" % rid, "", SMALL_SIZE, UiPalette.TEXT_SECONDARY, true)
	box.add_child(succession)
	_card_labels[rid] = {"body": body_labels, "ability": ability_value, "succession": succession}
	return card


## The ruler's portrait: a placeholder frame with the ruler's initial until the portraits arrive (M2-9).
func _portrait(rid: String) -> Control:
	var frame := PanelContainer.new()
	frame.name = "Portrait"
	frame.custom_minimum_size = Vector2(72, 96)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED.darkened(0.25)
	style.border_color = UiPalette.GILT.darkened(0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", style)
	var initial := ""
	for w in RulerRules.ruler_name(rid, 1).split(" ", false):
		if w.length() > 1 and w[0] == w[0].to_upper():
			initial = w[0]
	var l := _label("Initial", initial, 40, UiPalette.GILT.darkened(0.15))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(l)
	return frame


func _power_column() -> Control:
	var panel := _column("PowerColumn", 1.2)
	var col := panel.get_child(0) as VBoxContainer
	col.add_child(_heading("PowerHeading", "2. Keep or spend power", "ruler_power"))
	meter_label = _label("MeterLabel", "", 19, UiPalette.GILT)
	col.add_child(meter_label)
	var bar := HBoxContainer.new()
	bar.name = "Meter"
	bar.add_theme_constant_override("separation", 4)
	col.add_child(bar)
	for i in RulerData.POWER_POOL:
		var pip := Panel.new()
		pip.name = "Pip%d" % i
		pip.custom_minimum_size = Vector2(0, 22)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = EMPTY_PIP
		style.set_corner_radius_all(3)
		style.border_color = UiPalette.KEYLINE_INK
		style.set_border_width_all(1)
		pip.add_theme_stylebox_override("panel", style)
		pip.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.add_child(pip)
		meter_pips.append(pip)
	var ends := HBoxContainer.new()
	ends.name = "MeterEnds"
	col.add_child(ends)
	var keep_end := _label("KeepEnd", "Kept: your ruler", SMALL_SIZE, UiPalette.GILT)
	keep_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keep_end.tooltip_text = TooltipText.plain(CodexLink.title("kept_power"), RulesCodex.text("kept_power"))
	keep_end.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(keep_end, "kept_power", open_codex)
	ends.add_child(keep_end)
	var spend_end := _label("SpendEnd", "Spent: mandates", SMALL_SIZE, UiPalette.TEXT_SECONDARY)
	spend_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spend_end.tooltip_text = TooltipText.plain(CodexLink.title("mandates"), RulesCodex.text("mandates"))
	spend_end.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(spend_end, "mandates", open_codex)
	ends.add_child(spend_end)
	meter_sentence = _label("MeterSentence", "", BODY_SIZE - 1, UiPalette.TEXT_SECONDARY, true)
	meter_sentence.tooltip_text = TooltipText.plain(CodexLink.title("ruler_power"), RulesCodex.text("ruler_power"))
	meter_sentence.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(meter_sentence, "ruler_power", open_codex)
	col.add_child(meter_sentence)
	col.add_child(_heading("MandatesHeading", "Mandates for your whole nation", "mandates"))
	var f := _model.find_faction(faction_id)
	for mid in RulerRules.available_mandates(faction_id):
		col.add_child(_mandate_row(mid, f.faction_name if f else ""))
	return panel


func _mandate_row(mid: String, fname: String) -> Control:
	var md := RulerRules.mandate_data(mid)
	var row := VBoxContainer.new()
	row.name = "Mandate_%s" % mid
	row.add_theme_constant_override("separation", 0)
	mandate_rows[mid] = row
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	row.add_child(top)
	var check := CheckBox.new()
	check.name = "Check_%s" % mid
	check.text = String(md.name)
	check.add_theme_font_size_override("font_size", 15)
	_style_box(check)
	check.toggled.connect(func(on: bool): set_mandate(mid, on))
	top.add_child(check)
	mandate_checks[mid] = check
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_PASS
	pips.tooltip_text = TooltipText.plain("%s costs %s" % [md.name, TooltipText.count(int(md.cost), "power", "power")],
		"%s Its cost comes off the pool of %d; what is left is the ruler's kept power." % [String(md.effect), RulerData.POWER_POOL])
	for i in int(md.cost):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(12, 12)
		pip.mouse_filter = Control.MOUSE_FILTER_PASS
		var style := StyleBoxFlat.new()
		style.bg_color = AREA_COLORS.get(String(md.area), EMPTY_PIP)
		style.set_corner_radius_all(6)
		pip.add_theme_stylebox_override("panel", style)
		pip.tooltip_text = pips.tooltip_text
		pips.add_child(pip)
	top.add_child(pips)
	if not String(md.faction).is_empty():
		var tag := _label("Only_%s" % mid, "%s only" % fname, SMALL_SIZE - 1, UiPalette.GILT.darkened(0.1))
		tag.tooltip_text = TooltipText.plain("%s only" % fname, "Only the %s can take %s." % [fname, md.name])
		tag.mouse_filter = Control.MOUSE_FILTER_PASS
		top.add_child(tag)
	var reason := _label("Reason_%s" % mid, "", SMALL_SIZE, UiPalette.NEGATIVE)
	reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reason.visible = false
	top.add_child(reason)
	mandate_reasons[mid] = reason
	var effect := _label("Effect_%s" % mid, "", SMALL_SIZE, UiPalette.TEXT_SECONDARY, true)
	_rule(effect, String(md.effect), _mandate_tooltip(mid, []), String(md.codex))
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 26)
	indent.add_child(effect)
	row.add_child(indent)
	return row


func _nation_column() -> Control:
	var panel := _column("NationColumn", 0.92)
	var col := panel.get_child(0) as VBoxContainer
	col.add_child(_heading("NationHeading", "3. What changes for your nation", "mandates"))
	var grid := GridContainer.new()
	grid.name = "Roster"
	grid.columns = 1 + STATS.size()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)
	var stat_keys := {"hp": "stat_hit_points", "attack": "stat_attack", "defense": "stat_defense", "cost": "stat_cost"}
	var corner := _label("RosterCorner", "Your army", SMALL_SIZE, UiPalette.TEXT_SECONDARY)
	corner.tooltip_text = TooltipText.plain("Your army", "Your units and your commander with this build's mandates. A marked number is one a mandate changes: the arrow says which way, and the number under it is what it was without mandates.")
	corner.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(corner, "units", open_codex)
	grid.add_child(corner)
	for stat in STATS:
		var h := _label("RosterHead_%s" % stat, STAT_HEADS[stat], SMALL_SIZE, UiPalette.TEXT_SECONDARY)
		h.tooltip_text = TooltipText.plain(STAT_HEADS[stat], RulesCodex.text(stat_keys[stat]))
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(h, stat_keys[stat], open_codex)
		grid.add_child(h)
	var f := _model.find_faction(faction_id)
	for ut_id in _roster_ids():
		var ut: UnitType = TurnResolver.recruitable_type(f, ut_id)
		var unit_label := _label("Unit_%s" % ut_id, ut.name, BODY_SIZE, UiPalette.GILT if ut.is_commander else UiPalette.TEXT_PRIMARY)
		unit_label.tooltip_text = TooltipText.plain(ut.name + (", your commander" if ut.is_commander else ""),
			"%s: %s" % [ut.trait_id, AutoBattleResolver.TRAIT_SHORT.get(ut.trait_id, ut.get_trait_desc())])
		unit_label.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(unit_label, "commander" if ut.is_commander else "units", open_codex)
		grid.add_child(unit_label)
		var cells := {}
		for stat in STATS:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", -3)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 4)
			cell.add_child(line)
			var value := _label("Value_%s_%s" % [ut_id, stat], "", BODY_SIZE, UiPalette.TEXT_PRIMARY)
			line.add_child(value)
			var arrow := Arrow.new()
			arrow.name = "Arrow_%s_%s" % [ut_id, stat]
			arrow.visible = false
			line.add_child(arrow)
			var was := _label("Was_%s_%s" % [ut_id, stat], "", SMALL_SIZE - 2, UiPalette.TEXT_DISABLED)
			was.visible = false
			cell.add_child(was)
			grid.add_child(cell)
			cells[stat] = [value, was, arrow]
		_roster_cells[ut_id] = cells
	_starting_label = _label("StartingArmy", "", SMALL_SIZE, UiPalette.TEXT_SECONDARY, true)
	col.add_child(_starting_label)
	col.add_child(_heading("EconomyHeading", "Gold", "gold"))
	for key in ["gold", "income"]:
		var l := _label("Economy_%s" % key, "", BODY_SIZE, UiPalette.TEXT_PRIMARY, true)
		col.add_child(l)
		_economy[key] = l
	var prices := _label("RecruitPrices", "Recruit prices are the Cost column above.", SMALL_SIZE, UiPalette.TEXT_SECONDARY, true)
	prices.tooltip_text = TooltipText.plain(CodexLink.title("stat_cost"), RulesCodex.text("stat_cost"))
	prices.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(prices, "stat_cost", open_codex)
	col.add_child(prices)
	col.add_child(_heading("OtherHeading", "Other effects", "mandates"))
	other_box = VBoxContainer.new()
	other_box.name = "OtherEffects"
	other_box.add_theme_constant_override("separation", 4)
	col.add_child(other_box)
	return panel


## A column of the page: a panel holding a VBoxContainer (its first child), which the caller fills.
func _column(node_name: String, ratio: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(12))
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	return panel


func _heading(node_name: String, text: String, key: String) -> Label:
	var l := _label(node_name, text, 19, UiPalette.GILT)
	l.tooltip_text = TooltipText.plain(CodexLink.title(key), RulesCodex.text(key))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, key, open_codex)
	return l


func _card_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED if selected else UiPalette.PANEL_BG.lightened(0.03)
	style.border_color = UiPalette.GILT if selected else UiPalette.PANEL_BORDER
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	return style


func _style_card(card: PanelContainer, selected: bool) -> void:
	card.add_theme_stylebox_override("panel", _card_style(selected))


## A preset button: a bordered chip that turns gilt while the build on screen is that preset.
func _style_chip(b: Button) -> void:
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 17)
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var on: bool = state_name in ["pressed", "hover_pressed"]
		sb.bg_color = UiPalette.PANEL_RAISED.lightened(0.1 if state_name.begins_with("hover") else 0.0)
		sb.border_color = UiPalette.GILT if on else UiPalette.PANEL_BORDER
		sb.set_border_width_all(2 if on else 1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		if state_name == "focus":
			sb.draw_center = false
			sb.border_color = UiPalette.TEXT_SECONDARY
		b.add_theme_stylebox_override(state_name, sb)
	for color_name in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(color_name, UiPalette.GILT)


## Check boxes and radio buttons: the theme's unticked icon is a dark square that vanishes on the dark
## panels, so it gets a light outline (sized like the ticked icon, so the text never moves), and the
## ticked one turns gilt.
func _style_box(b: CheckBox) -> void:
	b.add_theme_color_override("checkbox_checked_color", UiPalette.GILT)
	for icon_name in ["unchecked", "radio_unchecked"]:
		var size := b.get_theme_icon(icon_name.replace("unchecked", "checked")).get_size()
		b.add_theme_icon_override(icon_name, _outline_icon(Vector2i(maxi(int(size.x), 12), maxi(int(size.y), 12)), icon_name.begins_with("radio")))


## An empty box (or ring) with a light outline. Made once per size and shape.
func _outline_icon(size: Vector2i, round: bool) -> Texture2D:
	var cache_key := "%dx%d%s" % [size.x, size.y, "o" if round else "x"]
	if _icons.has(cache_key):
		return _icons[cache_key]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size) / 2.0 - Vector2(0.5, 0.5)
	var r := minf(size.x, size.y) / 2.0 - 1.0
	for x in size.x:
		for y in size.y:
			var inside: bool
			var edge: bool
			if round:
				var d := Vector2(x, y).distance_to(c)
				inside = d <= r
				edge = d > r - 2.0
			else:
				inside = x >= 1 and y >= 1 and x <= size.x - 2 and y <= size.y - 2
				edge = x <= 2 or y <= 2 or x >= size.x - 3 or y >= size.y - 3
			if inside:
				img.set_pixel(x, y, UiPalette.TEXT_SECONDARY if edge else UiPalette.PANEL_RAISED)
	_icons[cache_key] = ImageTexture.create_from_image(img)
	return _icons[cache_key]


func _label(node_name: String, text: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(80, 0)
	return l


func _center_label(node_name: String, font_size: int, color: Color) -> Label:
	var l := _label(node_name, "", font_size, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(node_name: String, text: String, width: int, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(width, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.tooltip_text = tooltip
	return b


## Frees every child of `box`. In a running game the engine frees them at the end of the frame (so a
## control can never be freed inside its own signal); outside the tree (headless tests) no frame comes,
## so they are freed at once.
static func _clear(box: Node) -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		if box.is_inside_tree():
			c.queue_free()
		else:
			c.free()


## The small triangle beside a number a mandate changes: up or down, in the number's colour. Drawn,
## because the game's font has no arrow glyphs.
class Arrow extends Control:
	var up := true:
		set(value):
			up = value
			queue_redraw()
	var color := Color.WHITE:
		set(value):
			color = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(11, 10)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(w / 2.0, 0), Vector2(w, h), Vector2(0, h)]) if up \
			else PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w / 2.0, h)])
		draw_colored_polygon(pts, color)
