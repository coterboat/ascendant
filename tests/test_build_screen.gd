extends "res://tests/test_case.gd"
## The pre-game build screen (M2-5, #33; design/M2_RULER.md §4), headless through the real screens: the
## "Rulers (M2 preview)" box on the new game screen (off: the M1 flow, unchanged; on: Start goes to the
## build screen), the balanced preset as the default, every number's breakdown equal to the RulerRules /
## Breakdown output, unaffordable mandates disabled with build_errors' reason, presets and Clear, the
## hotseat cover that never lets the other build on screen, computer seats' seeded presets, Start giving
## a game whose factions carry exactly the chosen builds, the rematch keeping the box and the builds,
## the codex links, and no raw ids anywhere.

const NEW_GAME_SCENE := "res://ui/new_game_screen.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
const SEED := 4242
const HOTSEAT := {"players": ["kingdom", "beasts"], "seed": SEED}
const VS_COMPUTER := {"players": ["kingdom", "beasts"], "seed": SEED, "ai": {"beasts": "normal"}}
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "rivermarch", "aurel_king",
	"ever_regent", "thornmane_avatar", "fang_chieftain", "iron_discipline", "drilled_ranks", "veteran_levies",
	"heavy_tithes", "muster_grounds", "sworn_vassals", "royal_armories", "kings_roads", "blood_frenzy",
	"feast_of_victory", "warrior_king", "iron_crown", "regents_court", "beast_god_unbound", "clan_moot",
	"blood_of_the_fang", "royal_court", "mending_light", "warband_muster", "knight_captain", "warchief",
	"war_bear", "spearmen", "tuskers", "fangthrowers", "codex:", "_"]
## Labels with a digit that is not a game number: the player's seat in the header, the step numbers.
const NOT_NUMBERS := ["HeaderLabel", "RulerHeading", "PowerHeading", "NationHeading"]


# --- helpers --------------------------------------------------------------------------------------

func _setup() -> NewGameScreen:
	var screen := load(NEW_GAME_SCENE).instantiate() as NewGameScreen
	screen.set_seed(SEED)
	return screen


## A build screen already building for `config`'s first human seat (past the cover, if there is one).
func _builder(config: Dictionary) -> BuildScreen:
	var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
	b.begin(config)
	if b.step == BuildScreen.Step.HANDOFF:
		b.acknowledge()
	assert_eq(b.step, BuildScreen.Step.BUILDING, "building")
	return b


func _strip_flavour(text: String) -> String:
	# King Corvane's flavour line says "kingdom", the word, which is also the faction's raw id.
	var out := text
	for r in RulerData.RULERS:
		out = out.replace(TooltipText.wrap_text(String(r.flavour)), "").replace(String(r.flavour), "")
	return out


## Every text a player can see under `node`: labels, buttons, tooltips and dropdown items.
func _text(node: Node, visible_only: bool = true) -> String:
	var out := PackedStringArray()
	_collect(node, out, visible_only)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray, visible_only: bool) -> void:
	if visible_only and node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	elif node is LineEdit:
		out.append((node as LineEdit).text)
	if node is OptionButton:
		for i in (node as OptionButton).item_count:
			out.append((node as OptionButton).get_item_text(i))
			out.append((node as OptionButton).get_popup().get_item_tooltip(i))
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect(c, out, visible_only)


## Only what labels and buttons say (no tooltips, which quote the codex's general rules).
func _label_text(node: Node) -> String:
	var out := PackedStringArray()
	for c in _visible_controls(node, []):
		if c is Label or c is Button:
			out.append(c.text)
	return "\n".join(out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.strip_edges().is_empty(), "%s has text" % what)
	var t := _strip_flavour(text)
	for id in RAW_IDS:
		assert_false(t.contains(id), "%s shows no raw id '%s'" % [what, id])


func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


func _visible_controls(node: Node, out: Array) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Control:
		out.append(node)
	for c in node.get_children():
		_visible_controls(c, out)
	return out


## The breakdown the rules give for a number label's source (BuildScreen's "breakdown_source" meta),
## computed here from the build on screen, independently of the screen.
func _expected(b: BuildScreen, source: Array) -> Dictionary:
	var build := b.current_build()
	var fid := b.faction_id
	match String(source[0]):
		"ruler_stat_at":
			return Breakdown.ruler_stat_at(source[1], source[2], source[3])
		"ability_rank_at":
			return Breakdown.ability_rank_at(source[1], source[2])
		"build_kept_power":
			return Breakdown.build_kept_power(build)
		"unit_stat":
			var used: Dictionary = build if source[1] == "build" else {"ruler": build.ruler, "mandates": []}
			return Breakdown.unit_stat(GameState.with_rulers(SEED, {fid: used}, []), fid, source[2], source[3])
		"gold":
			return Breakdown.gold(GameState.with_rulers(SEED, {fid: build}, []), fid)
		"province_income":
			return Breakdown.province_income(GameState.with_rulers(SEED, {fid: build}, []), source[1])
		"successor":
			# No Breakdown function for it yet: the screen builds it from RulerRules.successor_for, so check
			# its numbers and words against RulerRules here.
			var rid := String(source[1])
			var k := int(source[2])
			var model := GameState.new()
			var capital := model.find_province(model.find_faction(fid).capital).name
			var bd := BuildScreen.successor_breakdown(rid, k, capital)
			assert_eq(int(bd.total), int(RulerRules.successor_for(rid, k, 1).kept_power), "the successor's kept power is successor_for's")
			assert_eq(int(bd.lines[0].value), k, "from the kept power shown")
			assert_eq(String(bd.description), RulerRules.succession_text(rid, k, 1, capital))
			return bd
	fail("unknown breakdown source %s" % [source])
	return {}


## Checks every number on the build page against the rules, for the build on screen.
func _assert_numbers(b: BuildScreen, what: String) -> int:
	var kept := RulerRules.kept_after(b.current_build())
	var checked := 0
	for l in b.number_labels():
		var label := l as Label
		var bd: Dictionary = label.get_meta(BuildScreen.BREAKDOWN)
		var source: Array = label.get_meta(BuildScreen.SOURCE)
		var where := "%s: %s '%s'" % [what, label.name, label.text]
		assert_true(label.tooltip_text.begins_with(TooltipText.from_breakdown(bd)), "%s: its tooltip is its breakdown" % where)
		assert_eq(Breakdown.sum_of_lines(bd), int(bd.total), "%s: the lines sum to the total" % where)
		assert_eq(bd, _expected(b, source), "%s: the breakdown is the rules' (%s)" % [where, source])
		assert_ne(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s takes the mouse" % where)
		# The kept power a number is shown for is this build's, or spending / keeping everything.
		if String(source[0]) in ["ruler_stat_at", "ability_rank_at", "successor"]:
			var at: int = source[3] if String(source[0]) == "ruler_stat_at" else source[2]
			assert_true(at == kept or at == 0 or at == RulerData.POWER_POOL, "%s: shown for kept power %d" % [where, at])
			assert_true(RulerRules.rulers_for(b.faction_id).has(String(source[1])), "%s: one of the faction's rulers" % where)
		checked += 1
	# Every label or button with a digit is a checked number, a line of rule text, or not a game number.
	for c in _visible_controls(b.page, []):
		if not (c is Label or c is Button) or not _has_digit(c.text):
			continue
		var ok: bool = c.has_meta(BuildScreen.BREAKDOWN) or c.has_meta(BuildScreen.RULE) or NOT_NUMBERS.has(String(c.name))
		assert_true(ok, "%s: '%s' (%s) has a breakdown or is rule text" % [what, c.text, c.name])
		assert_false(c.tooltip_text.strip_edges().is_empty(), "%s: '%s' has a tooltip" % [what, c.text])
		if c.has_meta(BuildScreen.RULE):
			assert_true(RulesCodex.ENTRIES.has(String(c.get_meta(BuildScreen.RULE))), "%s: '%s' links a codex entry" % [what, c.text])
	return checked


# --- the new game screen --------------------------------------------------------------------------

func test_rulers_box_is_off_by_default_and_the_m1_flow_is_unchanged() -> void:
	var screen := _setup()
	assert_false(screen.rulers_on(), "rulers are off by default")
	assert_false(screen.rulers_toggle.button_pressed)
	assert_eq(screen.rulers_toggle.text, "Rulers (M2 preview)")
	assert_eq(screen.config(), {"players": ["kingdom", "beasts"], "seed": SEED}, "exactly the M1 config")
	assert_eq(screen.start_button.text, "Start")
	assert_false(screen.rulers_label.visible)
	var started := []
	screen.start_requested.connect(func(c: Dictionary): started.append(c))
	screen.start_button.pressed.emit()
	assert_eq(started, [{"players": ["kingdom", "beasts"], "seed": SEED}], "Start starts at once, as before")
	assert_eq(screen.build_screen, null, "no build screen")
	screen.free()

	# Through the title: the game has no rulers, and Quick start neither.
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title._ready()
	title.new_game_button.pressed.emit()
	title.new_game_screen.set_seed(SEED)
	title.new_game_screen.start_button.pressed.emit()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "Start switches to the game")
	if game:
		assert_eq(game.config, {"players": ["kingdom", "beasts"], "seed": SEED})
		assert_false(RulerRules.has_rulers(game.session.state()), "an M1 game")
		game.free()
	title.next_scene = null
	title.quick_start_button.pressed.emit()
	var quick := title.next_scene as GameScreen
	assert_true(quick != null)
	if quick:
		assert_false(quick.config.has("rulers") or quick.config.has("builds"), "Quick start is unchanged")
		assert_false(RulerRules.has_rulers(quick.session.state()))
		quick.free()
	title.free()


func test_rulers_box_on_goes_to_the_build_screen() -> void:
	var screen := _setup()
	var started := []
	var backs := [0]
	screen.start_requested.connect(func(c: Dictionary): started.append(c))
	screen.back_requested.connect(func(): backs[0] += 1)
	screen.rulers_toggle.button_pressed = true  # a click: emits toggled
	assert_true(screen.rulers_on())
	assert_eq(screen.config(), {"players": ["kingdom", "beasts"], "seed": SEED, "rulers": true})
	assert_eq(screen.start_button.text, "Choose builds")
	assert_true(screen.start_button.tooltip_text.contains("build screen"), screen.start_button.tooltip_text)
	assert_true(screen.rulers_label.visible, "the box explains itself")
	for l in screen.faction_labels:
		assert_true(l.text.ends_with("Picks a ruler and mandates on the build screen."), l.text)

	screen.start_button.pressed.emit()
	assert_eq(started, [], "nothing starts before the builds")
	var b := screen.build_screen
	assert_true(b != null and b.visible, "Start opens the build screen")
	if b == null:
		screen.free()
		return
	assert_eq(b.get_index(), screen.get_child_count() - 1, "on top of the setup")
	assert_true(screen.build_screen_open())
	assert_eq(b.step, BuildScreen.Step.HANDOFF, "two people: a cover first")
	assert_true(b.cover.visible)
	assert_true(b.cover_title.text == "Pass to Aurel Crown", b.cover_title.text)
	assert_true(b.cover_body.text.begins_with("Pass the computer to player 1 to choose a ruler and mandates"), b.cover_body.text)
	b.ready_button.pressed.emit()
	assert_eq(b.step, BuildScreen.Step.BUILDING)
	assert_eq(b.header_label.text, "Player 1, Aurel Crown: choose your ruler and how much power to keep.")

	# Esc on the setup while building is the build screen's Back: the setup again, nothing started.
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	screen._unhandled_input(esc)
	assert_false(b.visible, "Esc goes back from the build screen")
	assert_eq(backs[0], 0, "and not out of the setup")
	assert_true(screen.visible)
	assert_eq(started, [])
	# Back drops what was chosen: the next build phase starts from the cover again.
	screen.start()
	assert_eq(b.step, BuildScreen.Step.HANDOFF)
	b.acknowledge()
	b.apply_preset("warrior_king")
	b.lock_in()
	b.acknowledge()  # player 2 is building
	b.back_button.pressed.emit()
	assert_false(b.visible)
	assert_eq(b.locked, {}, "Back drops the builds locked in so far")
	screen.start()
	b.acknowledge()
	assert_eq(b.seat, 0, "player 1 picks again")
	assert_eq(b.current_build(), _balanced("kingdom"), "from the balanced preset, not the dropped build")
	screen.free()


# --- the build screen -----------------------------------------------------------------------------

func _balanced(fid: String) -> Dictionary:
	var p := RulerRules.preset_build(RulerRules.balanced_preset(fid))
	return {"ruler": p.ruler, "mandates": p.mandates}


func test_the_default_build_is_the_balanced_preset() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var fid: String = players[0]
		var b := _builder({"players": players, "seed": SEED, "ai": {players[1]: "normal"}})
		assert_eq(b.step, BuildScreen.Step.BUILDING, "one person: no cover")
		assert_false(b.cover.visible)
		assert_eq(b.faction_id, fid)
		assert_eq(b.current_build(), _balanced(fid), "%s starts at its balanced preset" % fid)
		var balanced := RulerRules.balanced_preset(fid)
		for pid in b.preset_buttons:
			assert_eq((b.preset_buttons[pid] as Button).button_pressed, pid == balanced, "%s's button shows whether it is the build" % pid)
		assert_true((b.ruler_buttons[_balanced(fid).ruler] as CheckBox).button_pressed, "its ruler is picked")
		assert_false(b.footer_note.visible, "not a rematch")
		b.free()


func test_every_number_has_the_rules_breakdown() -> void:
	var total := 0
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var fid: String = players[0]
		var b := _builder({"players": players, "seed": SEED, "ai": {players[1]: "normal"}})
		var builds := []
		for p in RulerRules.presets_for(fid):
			builds.append(RulerRules.preset_build(p.id))
		for rid in RulerRules.rulers_for(fid):
			builds.append({"ruler": rid, "mandates": []})
			builds.append({"ruler": rid, "mandates": ["muster_grounds", "veteran_levies", "drilled_ranks"]})
		for build in builds:
			b.select_ruler(build.ruler)
			b.clear_build()
			for mid in build.mandates:
				assert_true(b.set_mandate(mid, true), "%s can take %s" % [fid, mid])
			assert_eq(b.current_build(), {"ruler": build.ruler, "mandates": build.mandates})
			var checked := _assert_numbers(b, "%s %s" % [build.ruler, build.mandates])
			assert_true(checked >= 40, "every number is checked (%d)" % checked)
			total += checked
		b.free()
	assert_true(total > 400, "numbers checked: %d" % total)


func test_the_numbers_are_the_specs() -> void:
	# Regent's Court: the Ever-Regent with Royal Armories and King's Roads keeps 4 (§6.1, §1.3).
	var b := _builder(VS_COMPUTER)
	assert_eq(b.meter_label.text, "Power pool 10  ·  spent 6  ·  kept 4")
	assert_eq(b.meter_label.get_meta(BuildScreen.BREAKDOWN), Breakdown.build_kept_power(b.current_build()))
	var gilt := 0
	for pip in b.meter_pips:
		if (pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == UiPalette.GILT:
			gilt += 1
	assert_eq(gilt, 4, "4 kept pips are gilt")
	assert_eq((b.meter_pips[4].get_theme_stylebox("panel") as StyleBoxFlat).bg_color, BuildScreen.AREA_COLORS.units, "Royal Armories' pips")
	assert_eq((b.meter_pips[8].get_theme_stylebox("panel") as StyleBoxFlat).bg_color, BuildScreen.AREA_COLORS.map, "King's Roads' pips")
	assert_true(b.meter_sentence.text.contains("Power you keep makes the Ever-Regent stronger in person"), b.meter_sentence.text)
	assert_eq(b._grid_labels.hp[0].text, "22", "Regent hp at 4 kept: 14 + 2 x 4")
	assert_eq(b._grid_labels.attack[0].text, "14")
	assert_eq(b._grid_labels.defense[0].text, "8")
	assert_eq(b._grid_labels.rank[0].text, "2")
	assert_eq(b._grid_labels.hp[1].text, "14", "spend all")
	assert_eq(b._grid_labels.hp[2].text, "34", "keep all")
	assert_eq(b._grid_labels.attack[0].get_meta(BuildScreen.BREAKDOWN), Breakdown.ruler_stat_at("ever_regent", "attack", 4))
	# Royal Armories: Spearmen attack 6 -> 7, marked with the old value.
	var cells: Array = b._roster_cells["spearmen"]["attack"]
	assert_eq(cells[0].text, "7")
	assert_true(cells[2].visible and cells[2].up, "an up arrow")
	assert_true(cells[1].visible)
	assert_eq(cells[1].text, "was 6")
	assert_false(b._roster_cells["spearmen"]["hp"][2].visible, "no arrow on an unchanged number")
	assert_eq(cells[0].get_meta(BuildScreen.BREAKDOWN).lines[1].label, "Royal Armories")
	assert_false(b._roster_cells["knight_captain"]["attack"][1].visible, "commanders don't get Royal Armories")
	assert_eq(b._roster_cells["knight_captain"]["attack"][0].text, "14")
	# The King at 4 kept power: attack 11 = 9 + 2 (§1.3, §7.1).
	b.select_ruler("aurel_king")
	assert_eq(b._grid_labels.attack[0].text, "11")
	assert_eq(int(b._grid_labels.attack[0].get_meta(BuildScreen.BREAKDOWN).lines[1].value), 2)
	assert_true(b._ruler_lines.succession.text.contains("Corvane II is crowned at Crownkeep 2 turns later"), b._ruler_lines.succession.text)
	assert_true(b._ruler_lines.succession.text.contains("(now 4, so 2)"), b._ruler_lines.succession.text)
	assert_eq(int(b._ruler_lines.succession.get_meta(BuildScreen.BREAKDOWN).total), 2)
	# Muster Grounds: Knights 20 -> 16 gold, a fifth off; cheaper is marked as good.
	b.apply_preset("warrior_king")
	assert_true(b.set_mandate("muster_grounds", true))
	var knights: Array = b._roster_cells["knights"]["cost"]
	assert_eq(knights[0].text, "16")
	assert_true(knights[2].visible and not knights[2].up, "a down arrow")
	assert_eq(knights[1].text, "was 20")
	assert_eq(knights[0].get_theme_color("font_color"), UiPalette.POSITIVE, "a lower price is good")
	assert_eq(knights[2].color, UiPalette.POSITIVE)
	# Gold and income from the starting state: the King starts at Crownkeep, so with 6 kept power (ability
	# rank 3) Royal Court adds 4 gold there on turn 1 (§1.4), and the preview shows it.
	assert_eq(b._economy.income.text, "Income on turn 1: 16 from Crownkeep")
	var income: Dictionary = b._economy.income.get_meta(BuildScreen.BREAKDOWN)
	assert_eq(income.lines.map(func(l): return [l.label, l.value]), [["Base income of Crownkeep", 12], ["Royal Court", 4]])
	assert_eq(b._economy.gold.text, "Gold: 50 to start, 66 on turn 2 before recruits")
	assert_true(b.set_mandate("heavy_tithes", true))
	assert_eq(b._economy.income.text, "Income on turn 1: 15 from Crownkeep", "Heavy Tithes +1, but with 2 kept power Royal Court drops to rank 1 (+2)")
	assert_true(b.set_mandate("heavy_tithes", false))
	# Other effects: one line per mandate that is not a number.
	# Sworn Vassals names the province it would take on turn 1 (Forecast.vassal, the capture phase's pick).
	assert_true(b.set_mandate("sworn_vassals", true))
	var others := b.other_box.get_children().filter(func(n): return not n.is_queued_for_deletion())
	assert_eq(others.map(func(l): return l.text), ["Sworn Vassals: Rivermarch (9 gold) would join you at the end of turn 1."])
	var start := GameState.with_rulers(SEED, {"kingdom": b.current_build()}, [])
	assert_eq(Forecast.vassal(start, "kingdom").province, "rivermarch")
	assert_eq(others[0].get_meta(BuildScreen.BREAKDOWN), Breakdown.province_income(start, "rivermarch"))
	assert_eq(String(others[0].get_meta(CodexLink.META)), "mandate_sworn_vassals")
	assert_true(others[0].tooltip_text.replace("\n", " ").contains(String(Forecast.vassal(start, "kingdom").text)), "the forecast's own words")
	# A mandate that is no number gets its rule as the line.
	assert_true(b.set_mandate("sworn_vassals", false))
	assert_true(b.set_mandate("kings_roads", true))
	others = b.other_box.get_children()
	assert_eq(others.map(func(l): return l.text), ["King's Roads: %s" % RulerRules.mandate_data("kings_roads").effect])
	b.free()


func test_an_unaffordable_mandate_is_disabled_with_its_reason() -> void:
	var b := _builder(VS_COMPUTER)
	assert_true(b.apply_preset("regents_court"))
	assert_true(b.set_mandate("drilled_ranks", true))  # 4 + 2 + 2: 2 power left
	var kept := RulerRules.kept_after(b.current_build())
	assert_eq(kept, 2)
	for mid in RulerRules.available_mandates("kingdom"):
		var check: CheckBox = b.mandate_checks[mid]
		var reason: Label = b.mandate_reasons[mid]
		var cost := RulerRules.mandate_cost(mid)
		var taken: bool = b.current_build().mandates.has(mid)
		if taken:
			assert_false(check.disabled, "%s is ticked and can be cleared" % mid)
			assert_true(check.button_pressed)
			continue
		var with_it: Array = b.current_build().mandates + [mid]
		var errors := RulerRules.build_errors("kingdom", {"ruler": b.ruler_id, "mandates": with_it})
		assert_eq(check.disabled, cost > kept, "%s (cost %d) is disabled only when it doesn't fit" % [mid, cost])
		assert_eq(check.disabled, not errors.is_empty(), "%s: disabled exactly when build_errors objects" % mid)
		assert_eq(reason.visible, check.disabled)
		if check.disabled:
			assert_eq(reason.text, "Needs %d power; %d left." % [cost, kept])
			var why := TooltipText.wrap_text("You can't take it now: %s" % " ".join(errors))
			assert_true(check.tooltip_text.contains(why), "%s's tooltip gives build_errors' reason: %s" % [mid, check.tooltip_text])
			assert_true(reason.tooltip_text.contains(TooltipText.wrap_text("You can't take %s: %s" % [RulerRules.mandate_name(mid), " ".join(errors)])), reason.tooltip_text)
			assert_true(errors[0].contains("the power pool is only 10"), errors[0])
			# A click on a disabled box changes nothing.
			var before := b.current_build()
			check.toggled.emit(true)
			assert_eq(b.current_build(), before, "%s can't be ticked" % mid)
			assert_false(check.button_pressed)
			assert_false(b.set_mandate(mid, true))
	assert_true(b.mandate_checks["heavy_tithes"].disabled, "4 power doesn't fit in 2")
	assert_false(b.mandate_checks["veteran_levies"].disabled, "2 does")
	# Clearing a mandate frees its power again.
	b.mandate_checks["royal_armories"].toggled.emit(false)
	assert_eq(b.current_build().mandates, ["kings_roads", "drilled_ranks"])
	assert_false(b.mandate_checks["heavy_tithes"].disabled, "with 6 left it fits")
	b.free()


func test_presets_clear_rulers_and_mandates_apply() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var fid: String = players[0]
		var b := _builder({"players": players, "seed": SEED, "ai": {players[1]: "easy"}})
		for p in RulerRules.presets_for(fid):
			(b.preset_buttons[p.id] as Button).pressed.emit()
			var want := RulerRules.preset_build(p.id)
			assert_eq(b.current_build(), {"ruler": want.ruler, "mandates": want.mandates}, "%s applies" % p.id)
			for other in b.preset_buttons:
				assert_eq((b.preset_buttons[other] as Button).button_pressed, other == p.id)
			assert_true((b.ruler_buttons[want.ruler] as CheckBox).button_pressed)
			assert_true(b.meter_label.text.ends_with("kept %d" % RulerRules.kept_after(want)), b.meter_label.text)
		assert_false(b.apply_preset("no_such_preset"))
		assert_false(b.apply_preset("iron_crown" if fid == "beasts" else "clan_moot"), "not another faction's preset")
		# Clear keeps the ruler and drops every mandate.
		var ruler := b.ruler_id
		b.clear_button.pressed.emit()
		assert_eq(b.current_build(), {"ruler": ruler, "mandates": []})
		assert_true(b.clear_button.button_pressed)
		assert_true(b.meter_label.text.ends_with("kept 10"), b.meter_label.text)
		# The other ruler's card, through its button; the mandates stay.
		var other_ruler: String = RulerRules.rulers_for(fid).filter(func(r): return r != ruler)[0]
		b.mandate_checks["drilled_ranks"].toggled.emit(true)
		b.mandate_checks["veteran_levies"].toggled.emit(true)
		(b.ruler_buttons[other_ruler] as CheckBox).pressed.emit()
		assert_eq(b.current_build(), {"ruler": other_ruler, "mandates": ["drilled_ranks", "veteran_levies"]}, "mandates in the order taken")
		assert_eq(((b.ruler_cards[other_ruler] as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).border_color, UiPalette.GILT, "the picked card is gilt")
		assert_false(b.select_ruler("aurel_king" if fid == "beasts" else "fang_chieftain"), "not another faction's ruler")
		b.free()


func test_the_hotseat_handoff_never_shows_the_other_build() -> void:
	var seen := []
	for first in [{"ruler": "aurel_king", "mandates": []}, {"ruler": "ever_regent", "mandates": ["heavy_tithes", "muster_grounds", "kings_roads"]}]:
		var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
		var done := []
		b.finished.connect(func(c: Dictionary): done.append(c))
		b.begin(HOTSEAT)
		assert_eq(b.step, BuildScreen.Step.HANDOFF)
		assert_false(b.page.visible, "nothing under the first cover")
		assert_eq(b.body.get_child_count(), 0)
		b.acknowledge()
		b.select_ruler(first.ruler)
		b.clear_build()
		for mid in first.mandates:
			b.set_mandate(mid, true)
		assert_eq(b.current_build(), first)
		b.lock_button.pressed.emit()
		# The cover before player 2: player 1's build is gone from the screen, hidden or not.
		assert_eq(b.step, BuildScreen.Step.HANDOFF)
		assert_true(b.cover.visible)
		assert_false(b.page.visible)
		assert_eq(b.body.get_child_count(), 0, "the page is emptied under the cover")
		assert_eq(b.cover_title.text, "Pass to Thornmane Clans")
		var under := _text(b, false)
		for word in ["King Corvane", "Ever-Regent", "Heavy Tithes", "Muster Grounds", "Royal Court", "Mending Light"]:
			assert_false(under.contains(word), "nothing of player 1's build behind the cover: %s" % word)
		b.ready_button.pressed.emit()
		assert_eq(b.faction_id, "beasts")
		assert_eq(b.current_build(), _balanced("beasts"), "player 2 starts at the balanced preset")
		var shown := _label_text(b)
		for word in ["King Corvane", "Ever-Regent", "Aurel Crown", "Crownkeep", "Royal Court", "Mending Light"]:
			assert_false(shown.contains(word), "player 2's screen never names player 1's build: %s" % word)
		seen.append(_text(b, false))
		b.lock_in()
		assert_eq(b.step, BuildScreen.Step.START_HANDOFF, "the cover that hands the computer back to player 1")
		assert_eq(b.body.get_child_count(), 0)
		assert_true(b.cover_body.text.contains("Pass the computer to player 1"), b.cover_body.text)
		assert_false(_text(b, false).contains("Blood of the Fang"))
		assert_eq(done, [], "the game waits for player 1")
		b.ready_button.pressed.emit()
		assert_eq(done.size(), 1)
		assert_eq(done[0].builds, {"kingdom": first, "beasts": _balanced("beasts")})
		b.free()
	assert_eq(seen[0], seen[1], "player 2's whole screen, hidden parts and tooltips too, is the same whatever player 1 picked")


func test_a_computer_seat_gets_a_seeded_preset() -> void:
	# §6.1: presets[faction][roll], the first draw of the seat's computer RNG.
	var rolled := {}
	for s in 40:
		for seat in 2:
			var fid: String = ["kingdom", "beasts"][seat]
			var expected: String = RulerRules.presets_for(fid)[SeededRNG.new(AISeat.seat_seed(s, seat)).randi_range(0, 2)].id
			assert_eq(BuildScreen.computer_preset(fid, s, seat), expected)
			assert_eq(BuildScreen.computer_preset(fid, s, seat), expected, "the same seed, the same preset")
			rolled[expected] = true
	assert_eq(rolled.size(), 6, "every preset comes up for some seed")

	# Through the screens: one person, no cover, and nothing about the computer's build on screen.
	var screen := _setup()
	screen.set_rulers(true)
	screen.set_seat_kind(2, "computer")
	assert_true(screen.faction_labels[1].text.ends_with("Its build: one of its three presets, picked at random from the seed."), screen.faction_labels[1].text)
	var started := []
	screen.start_requested.connect(func(c: Dictionary): started.append(c))
	screen.start_button.pressed.emit()
	var b := screen.build_screen
	assert_eq(b.step, BuildScreen.Step.BUILDING, "no cover with one person")
	var shown := _label_text(b)
	for p in RulerRules.presets_for("beasts"):
		assert_false(shown.contains(String(p.name)), "the computer's presets are not on screen: %s" % p.name)
	for rid in RulerRules.rulers_for("beasts"):
		assert_false(shown.contains(RulerRules.ruler_name(rid)), "nor its rulers")
	# Nothing on the build screen depends on which preset the computer rolled: two seeds that roll
	# different presets give the very same screen, hidden parts and tooltips included.
	var other_seed := SEED + 1
	while BuildScreen.computer_preset("beasts", other_seed, 1) == BuildScreen.computer_preset("beasts", SEED, 1):
		other_seed += 1
	var twin := _builder({"players": ["kingdom", "beasts"], "seed": other_seed, "ai": {"beasts": "normal"}})
	assert_eq(_text(twin, false), _text(b, false), "the computer's build leaves no trace before the game")
	twin.free()
	b.lock_in()
	assert_eq(started.size(), 1, "the game starts after the only human locks in")
	var pid := BuildScreen.computer_preset("beasts", SEED, 1)
	assert_eq(started[0].builds.beasts, RulerRules.preset_build(pid), "the computer plays its seeded preset")
	assert_eq(started[0].ai, {"beasts": "normal"}, "and is still the computer")
	assert_eq(started[0].builds.kingdom, _balanced("kingdom"))
	screen.free()

	# Watch mode: nobody to ask, so both computers roll and the game starts at once.
	var watch := _setup()
	watch.set_rulers(true)
	watch.set_seat_kind(1, "computer")
	watch.set_seat_kind(2, "computer")
	assert_eq(watch.start_button.text, "Start")
	var w := []
	watch.start_requested.connect(func(c: Dictionary): w.append(c))
	watch.start()
	assert_eq(w.size(), 1)
	assert_eq(w[0].builds, {"kingdom": RulerRules.preset_build(BuildScreen.computer_preset("kingdom", SEED, 0)),
		"beasts": RulerRules.preset_build(BuildScreen.computer_preset("beasts", SEED, 1))})
	assert_false(watch.build_screen.visible)
	watch.free()


func test_start_gives_a_game_whose_factions_carry_exactly_the_chosen_builds() -> void:
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title._ready()
	title.new_game_button.pressed.emit()
	var setup := title.new_game_screen
	setup.set_seed(SEED)
	setup.swap_seats()  # Thornmane Clans are player 1
	setup.rulers_toggle.button_pressed = true
	setup.start_button.pressed.emit()
	var b := setup.build_screen
	var chosen := {"beasts": {"ruler": "thornmane_avatar", "mandates": ["feast_of_victory", "veteran_levies"]},
		"kingdom": {"ruler": "aurel_king", "mandates": ["heavy_tithes", "royal_armories", "drilled_ranks"]}}
	for fid in ["beasts", "kingdom"]:
		b.ready_button.pressed.emit()
		assert_eq(b.faction_id, fid)
		(b.ruler_buttons[chosen[fid].ruler] as CheckBox).pressed.emit()
		b.clear_button.pressed.emit()
		for mid in chosen[fid].mandates:
			(b.mandate_checks[mid] as CheckBox).toggled.emit(true)
		assert_eq(b.current_build(), chosen[fid])
		b.lock_button.pressed.emit()
	assert_eq(title.next_scene, null, "the game waits behind the last cover")
	assert_eq(b.ready_button.text, "Start the game")
	b.ready_button.pressed.emit()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "Start the game switches to the game screen")
	if game == null:
		title.free()
		return
	assert_eq(game.config, {"players": ["beasts", "kingdom"], "seed": SEED, "rulers": true, "builds": chosen})
	var s := game.session.state()
	for fid in chosen:
		var f := s.find_faction(fid)
		assert_eq(f.ruler_type, chosen[fid].ruler, "%s's ruler" % fid)
		assert_eq(f.mandates, chosen[fid].mandates, "%s's mandates, in the order taken" % fid)
		assert_eq(f.kept_power, RulerRules.kept_after(chosen[fid]))
		assert_eq(game.session.builds()[fid].mandates, chosen[fid].mandates)
		var army := RulerRules.ruler_army(s, fid)
		assert_true(army != null and army.location == f.capital, "%s's ruler waits at its capital" % fid)
	assert_eq(game.session.phase(), GameSession.Phase.ORDERS)
	assert_eq(game.session.current_player(), "beasts", "player 1 gives the first orders")
	assert_false(game.handoff.visible)
	game.free()
	title.free()


func test_rematch_keeps_the_rulers_box_and_each_seats_last_build() -> void:
	var builds := {"kingdom": {"ruler": "aurel_king", "mandates": ["muster_grounds"]},
		"beasts": {"ruler": "fang_chieftain", "mandates": ["sworn_vassals", "iron_discipline"]}}
	var game := SceneFlow.make_game({"players": ["kingdom", "beasts"], "seed": SEED, "rulers": true, "builds": builds})
	game.victory_screen.new_game_button.pressed.emit()  # what the victory screen's New game does
	var title := game.next_scene as TitleScreen
	var setup := title.new_game_screen
	assert_true(setup.rulers_on(), "the rulers box stays ticked")
	assert_true(setup.rematch_label.visible)
	assert_ne(setup.config().seed, SEED, "a new seed")
	setup.start()
	var b := setup.build_screen
	for fid in ["kingdom", "beasts"]:
		b.acknowledge()
		assert_eq(b.current_build(), builds[fid], "%s starts at its last build" % fid)
		assert_true(b.footer_note.visible, "and the screen says why")
		b.lock_in()
	title.free()
	game.free()

	# Against the computer: the human keeps their build; the computer rolls again from the new seed.
	var vs := SceneFlow.make_game({"players": ["kingdom", "beasts"], "seed": SEED, "ai": {"beasts": "normal"}, "rulers": true,
		"builds": {"kingdom": builds.kingdom, "beasts": RulerRules.preset_build("clan_moot")}})
	vs.victory_screen.new_game_button.pressed.emit()
	var title2 := vs.next_scene as TitleScreen
	var setup2 := title2.new_game_screen
	var started := []
	setup2.start_requested.connect(func(c: Dictionary): started.append(c))
	setup2.start()
	assert_eq(setup2.build_screen.current_build(), builds.kingdom)
	setup2.build_screen.lock_in()
	var new_seed: int = started[0].seed
	assert_eq(started[0].builds.beasts, RulerRules.preset_build(BuildScreen.computer_preset("beasts", new_seed, 1)), "a fresh seeded preset")
	var rematch := title2.next_scene as GameScreen
	assert_true(rematch != null, "the title started the rematch")
	if rematch:
		assert_eq(rematch.session.builds().kingdom.mandates, builds.kingdom.mandates)
		rematch.free()
	title2.free()
	vs.free()

	# A rematch of a game without rulers leaves the box off.
	var m1 := SceneFlow.make_game({"players": ["kingdom", "beasts"], "seed": SEED})
	m1.victory_screen.new_game_button.pressed.emit()
	var title3 := m1.next_scene as TitleScreen
	assert_false(title3.new_game_screen.rulers_on())
	assert_false(title3.new_game_screen.config().has("rulers"))
	title3.free()
	m1.free()


func test_codex_links_on_the_build_screen() -> void:
	var b := _builder(VS_COMPUTER)
	for rid in RulerRules.rulers_for("kingdom"):
		assert_eq(String(b.ruler_buttons[rid].get_meta(CodexLink.META)), "ruler_" + rid, "the name links the ruler's entry")
		var cl: Dictionary = b._card_labels[rid]
		for l in cl.body:
			assert_eq(String(l.get_meta(CodexLink.META)), "ruler_power", "the body links ruler power")
		assert_eq(String(cl.ability.get_meta(CodexLink.META)), "ability_rank")
		var kind := String(RulerRules.ruler_data(rid).kind)
		assert_eq(String(cl.succession.get_meta(CodexLink.META)), String(RulerData.KINDS[kind].codex), "the succession kind's entry")
		var card := b.ruler_cards[rid] as Control
		var rank := card.find_child("Rank_%s" % rid, true, false) as Label
		assert_eq(String(rank.get_meta(CodexLink.META)), "ruler_rank")
		var ability := card.find_child("AbilityName_%s" % rid, true, false) as Label
		assert_eq(String(ability.get_meta(CodexLink.META)), "ability_" + String(RulerRules.ruler_data(rid).ability))
	for mid in b.mandate_checks:
		assert_eq(String(b.mandate_checks[mid].get_meta(CodexLink.META)), String(RulerRules.mandate_data(mid).codex))
	assert_eq(String(b.meter_label.get_meta(CodexLink.META)), "kept_power")
	for key in ["build_screen", "build_presets", "ruler_power", "mandates"]:
		assert_true(_text(b).contains("Codex: %s (right-click or F1 to open)" % CodexLink.title(key)), "links %s" % key)
	# A right-click opens the screen's own codex on top, at that entry.
	b._grid_labels.attack[0].gui_input.emit(CodexLink.right_click())
	assert_true(b.codex != null and b.codex.visible, "the codex opens")
	assert_eq(b.codex.current_key(), "ruler_power")
	assert_eq(b.codex.get_index(), b.get_child_count() - 1, "on top")
	assert_true(b.handle_cancel(), "Esc closes the codex first")
	assert_false(b.codex.visible)
	assert_eq(b.step, BuildScreen.Step.BUILDING, "and keeps the build")
	b.free()


func test_the_codex_explains_the_build_screen() -> void:
	var e := RulesCodex.entry("build_screen")
	assert_eq(String(e.get("title", "")), "Choosing builds")
	var text := RulesCodex.text("build_screen")
	for part in ["balanced preset", "power bar", "covered between builders", "presets in secret", "seed", "public from the first turn"]:
		assert_true(text.contains(part), "the entry says '%s'" % part)
	assert_false(text.contains("[") or text.contains("_"), "plain text, so tooltips can quote it")
	var keys := RulesCodex.ENTRIES.keys()
	assert_eq(keys.find("build_screen"), keys.find("computer_opponent") + 1, "right after the computer opponent")


func test_no_raw_ids_on_the_new_game_and_build_screens() -> void:
	var screen := _setup()
	screen.set_rulers(true)
	_assert_no_raw_ids(_text(screen), "new game screen with rulers")
	screen.start()
	var b := screen.build_screen
	_assert_no_raw_ids(_text(screen), "the first cover")
	b.acknowledge()
	for p in RulerRules.presets_for("kingdom"):
		b.apply_preset(p.id)
		_assert_no_raw_ids(_text(screen), "Aurel Crown, %s" % p.name)
	b.select_ruler("aurel_king")
	b.clear_build()
	_assert_no_raw_ids(_text(screen), "Aurel Crown, keep everything")
	b.lock_in()
	_assert_no_raw_ids(_text(screen), "the cover before player 2")
	b.acknowledge()
	for p in RulerRules.presets_for("beasts"):
		b.apply_preset(p.id)
		_assert_no_raw_ids(_text(screen), "Thornmane Clans, %s" % p.name)
	b.lock_in()
	_assert_no_raw_ids(_text(screen), "the cover before turn 1")
	screen.free()
	var vs := _setup()
	vs.set_rulers(true)
	vs.set_seat_kind(2, "computer")
	_assert_no_raw_ids(_text(vs), "new game screen against the computer with rulers")
	for t in _text(vs).split("\n"):
		assert_false(t.contains("_"), "no underscores on screen: %s" % t)
	vs.free()
