extends "res://tests/test_case.gd"
## M5-2 (#113) acceptance, fog on screen (design/M5_MAGIC_FOG.md §2.8-§2.10, §11.1, §18): every screen reads the
## per-viewer accessors (GameSession.state_for, turn_report_for, view_before, memory, intel), headless and M1 style:
## GameScreen and MapScreen driven through their API outside the tree.
## - a static scan finds no truth accessor (and no FogRules.OBSERVER) in ui/ outside the observer paths;
## - province tooltips show what is remembered and why a province is seen; a glimpsed army shows its ranges and last
##   turn; every number on a fog panel has a breakdown;
## - the handoff rebuilds the next seat's screen, and clears the board's kept frame, while the cover is still up;
## - forecast equals result under §2.10's conditions (the 20 fog games of tests/fog_test_kit.gd, plus built cases);
## - in hotseat, seat 2's panels are identical when seat 1's private facts change (FogTestKit.perturb_hidden);
## - the computer's notes stay hidden until the game is over;
## - the turn report is the viewer's, with its header line; Watch is for participants only; hotseat fog playback is
##   muted but for the ambient bed; the Vision map mode and its legend; scout lines; the forecasts' fog text; the rival
##   ruler "alive, location unknown"; "what you didn't see"; the victory screen's "fog lifts".
## With fog off nothing here shows: tests/test_fog_off.gd and every older test hold unchanged.

const Kit := preload("res://tests/fog_test_kit.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
## The truth accessors (§2.1). In ui/ only the observer paths may read them: the victory screen, save and load, battle
## regeneration for a participant, and the one place the game screen picks the observer (watch mode, game over).
const TRUTH := ["state", "turn_report", "battle_events", "builds", "record", "history", "victory"]
const OBSERVER_PATHS := {
	"res://ui/game_screen.gd": ["viewer", "load_game", "rebuild_battle_log", "_sync_chronicle", "_show_game_over", "_fog_lift_data"],
	"res://ui/victory_screen.gd": ["show_for"],
}


func _json(v) -> String:
	return JSON.stringify(v.to_dict() if v is GameState else v)


## Text as players read it: tooltips are wrapped, so compare without the line breaks.
static func _flat(text: String) -> String:
	return " ".join(text.replace("\n", " ").split(" ", false))


func _game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


func _map(view: GameState, viewer: String, memory: Dictionary, intel: Dictionary, before: GameState) -> MapScreen:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_fog(memory, intel, before)
	map.set_state(view, viewer)
	return map


## The first game of each kind in the kit (M1, M2, M4, sieges).
func _kinds() -> Array:
	return Kit.games().slice(0, Kit.KINDS.size())


## A hotseat game played `turns` turns by the computer's brain for both people, through the session (the same checks
## a click gets), standing at seat 1's orders behind no cover.
func _hotseat(config: Dictionary, turns: int) -> GameScreen:
	var game := _game(config)
	var brains := {}
	for i in game.session.players().size():
		var b := AIPlayer.new()
		b.configure(int(config.seed), i)
		brains[game.session.players()[i]] = [b, SeededRNG.new(int(config.seed) * 31 + i)]
	for t in turns:
		for i in game.session.players().size():
			if game.handoff.visible:
				game.handoff.ready_button.pressed.emit()
			game.close_turn_report()
			var fid := game.session.current_player()
			for o in brains[fid][0].plan_orders(game.session.state_for(fid), fid, brains[fid][1], "normal"):
				game.session.queue_order(o)
			game.end_turn()
		if game.session.is_over():
			break
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	return game


# --- the static scan (§2.1) -----------------------------------------------------------------------------

func test_no_truth_accessor_in_ui_outside_the_observer_paths() -> void:
	var files := _gd_files("res://ui")
	assert_true(files.size() >= 40, "the scan reads every ui script (%d)" % files.size())
	var re := RegEx.new()
	re.compile("\\.(%s)\\(\\)|\\bOBSERVER\\b|\\bsession\\._[a-z_]+" % "|".join(TRUTH))
	var fn_re := RegEx.new()
	fn_re.compile("^(?:static )?func ([A-Za-z0-9_]+)")
	var found := []
	var allowed_hits := 0
	for path in files:
		var fn := ""
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var m := fn_re.search(lines[i])
			if m != null:
				fn = m.get_string(1)
			var code := _code_part(lines[i])
			if code.is_empty() or re.search(code) == null:
				continue
			if Array(OBSERVER_PATHS.get(path, [])).has(fn):
				allowed_hits += 1
				continue
			found.append("%s:%d (%s): %s" % [path.get_file(), i + 1, fn, lines[i].strip_edges()])
	assert_eq(found, [], "every screen reads the per-viewer accessors")
	assert_true(allowed_hits > 0, "the observer paths are where the truth is read (%d reads)" % allowed_hits)


func _gd_files(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


## A line of code without its comment ("" for a comment line). A "#" inside a string doesn't start a comment.
static func _code_part(line: String) -> String:
	var s := line.strip_edges()
	if s.begins_with("#"):
		return ""
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote.is_empty() and (c == "\"" or c == "'"):
			quote = c
		elif c == quote and (i == 0 or line[i - 1] != "\\"):
			quote = ""
		elif quote.is_empty() and c == "#":
			return line.substr(0, i)
	return line


# --- the map: tooltips, armies, breakdowns (§11.1) ---------------------------------------------------------

func test_province_tooltips_show_memory_and_sources() -> void:
	var counts := {"clear": 0, "glimpse": 0, "remembered": 0, "never": 0, "fought": 0}
	for g in _kinds():
		for i in [g.turns.size() / 2, g.turns.size() - 1]:
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				var memory: Dictionary = t.memory_after[v]
				var map := _map(view, v, memory, t.intel_after[v], t.view_before[v])
				var sight := FogRules.sight(view, v)
				for pid in sight:
					var tip := _flat(map.regions[pid].tooltip_text)
					var name := view.find_province(pid).name
					var where := "%s turn %d, %s at %s" % [g.name, t.turn, v, pid]
					if sight[pid] != FogRules.VEILED:
						var sources := FogRules.sources(view, v, pid)
						assert_true(tip.contains(_flat(String(sources[0].text))), "%s: the tooltip says why it is seen: %s" % [where, tip])
						counts[sight[pid]] += 1
						continue
					assert_true(tip.contains("You can't see %s" % name), "%s: out of sight, and says so: %s" % [where, tip])
					var entry: Dictionary = memory.get("provinces", {}).get(pid, {})
					if int(entry.get("seen_turn", -1)) >= 0:
						var ago := view.current_turn - int(entry.seen_turn)
						assert_true(tip.contains("Last seen"), "%s: the last sighting: %s" % [where, tip])
						var when := "at the end of turn %d" % int(entry.seen_turn) if int(entry.seen_turn) > 0 else "at the start of the game"
						assert_true(tip.contains(when), "%s: when it was last seen (%s, %d turns before): %s" % [where, when, ago, tip])
						counts.remembered += 1
					else:
						assert_true(tip.contains("never seen"), "%s: never seen: %s" % [where, tip])
						counts.never += 1
					for fid in entry.get("fought", {}):
						assert_true(tip.contains("Last fought there on turn %d" % int(entry.fought[fid].turn)), "%s: the battle there: %s" % [where, tip])
						counts.fought += 1
				map.free()
	for key in ["clear", "glimpse", "remembered", "never"]:
		assert_true(int(counts[key]) > 0, "tooltips of every kind were checked: %s" % [counts])
	_notes.append("province tooltips checked: %s" % [counts])


func test_a_glimpsed_army_shows_its_ranges_and_last_turn() -> void:
	var checked := 0
	var with_last := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				var before: GameState = t.view_before[v]
				for a in view.armies:
					if a.owner == v or String(a.seen.get("level", "")) != FogRules.GLIMPSE or a.ruler != null or a.units.is_empty():
						continue
					if checked >= 12:
						break
					var map := _map(view, v, t.memory_after[v], t.intel_after[v], before)
					var total: Dictionary = a.seen.total
					var badge: Button = map.regions[a.location].army_box.get_node("Army_%s" % a.id.validate_node_name())
					assert_eq(badge.text, "≈%s" % FogView.about(total), "the badge shows the rounded total")
					map.selected_army_id = ""
					map.select_army(a.id)
					var panel := _flat(_texts(map.details))
					var where := "%s turn %d, %s, %s" % [g.name, t.turn, v, a.id]
					assert_true(panel.contains("about %d (%d-%d)" % [int(total.shown), int(total.low), int(total.high)]) or int(total.shown) <= 2,
						"%s: the total and its range: %s" % [where, panel])
					for type_id in a.seen.counts:
						var c: Dictionary = a.seen.counts[type_id]
						var type_name := FogRules.type_name(view, a.owner, String(type_id))
						assert_true(panel.contains("about %d %s (%d-%d)" % [int(c.shown), type_name, int(c.low), int(c.high)]),
							"%s: %s and its range: %s" % [where, type_name, panel])
					assert_true(panel.contains("Last turn:"), "%s: last turn's sighting: %s" % [where, panel])
					var last: Army = before.find_army(a.id) if before != null else null
					if last != null and String(last.seen.get("level", "")) != FogData.MEMORY:
						assert_true(panel.contains("Last turn: %s" % FogView.range_text(last.seen.total)), "%s: last turn's numbers: %s" % [where, panel])
						with_last += 1
					assert_true(panel.contains("Fight them to see them exactly"), "%s: how to see them exactly: %s" % [where, panel])
					checked += 1
					map.free()
	assert_true(checked > 0 and with_last > 0, "glimpsed armies were checked (%d, %d with last turn's numbers)" % [checked, with_last])
	_notes.append("glimpsed armies checked: %d, %d with last turn's numbers" % [checked, with_last])


## Every label or button on a fog panel that shows a number explains it on hover.
func test_every_number_has_a_breakdown() -> void:
	var digit := RegEx.new()
	digit.compile("[0-9]")
	var checked := 0
	for g in _kinds():
		var t: Dictionary = g.turns.back()
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			var map := _map(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
			var ids := [view.find_faction(v).capital]
			for a in view.armies:
				if a.owner != v and not ids.has(a.location):
					ids.append(a.location)
			for pid in ids:
				map.selected_army_id = ""
				map.select_province(pid)
				for c in map.details.find_children("*", "", true, false) + map.regions[pid].find_children("*", "", true, false):
					if not (c is Label or c is Button):
						continue
					var text := String(c.text)
					if digit.search(text) == null or c is Button and (c as Button).disabled:
						continue
					assert_false(String(c.tooltip_text).is_empty(), "%s turn %d, %s at %s: \"%s\" explains itself" % [g.name, t.turn, v, pid, text])
					checked += 1
			map.free()
	assert_true(checked > 0, "numbers were checked (%d)" % checked)
	_notes.append("numbers with a breakdown: %d" % checked)


# --- the handoff (§2.9) --------------------------------------------------------------------------------

func test_the_handoff_rebuilds_under_the_cover() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true})
	assert_eq(game.session.current_player(), CROWN)
	assert_true(game.map.state.is_view and game.map.state.view_of == CROWN, "seat 1 sees its own view")
	game.end_turn()
	assert_true(game.handoff.visible, "the cover is up")
	assert_true(_flat(game.handoff.body_label.text + " " + game.handoff.hint_label.text).contains(FogView.COVER_LINE),
		"the cover says each player sees only their own view")
	game.handoff.ready_button.pressed.emit()
	assert_false(game.handoff.visible, "Ready lifts the cover")
	var entry: Dictionary = game.handoff_log.back()
	assert_eq(String(entry.faction), CLANS, "the rebuild was for seat 2")
	assert_true(bool(entry.covered), "the board, overlay and panels were rebuilt while the cover was up")
	assert_true(bool(entry.frame_cleared), "the kept frame was cleared before the cover lifted")
	assert_eq(game.map.viewing_faction_id, CLANS)
	assert_true(game.map.state.is_view and game.map.state.view_of == CLANS, "seat 2 sees its own view")
	assert_eq(_json(game.map.state), _json(game.session.state_for(CLANS)), "the map is seat 2's view")
	game.free()


func test_hotseat_fog_mutes_the_playback_but_the_bed() -> void:
	var audio := GameAudio.new()
	audio.quiet = true
	GameAudio.current = audio
	var game := _hotseat({"players": [CROWN, CLANS], "seed": 4242, "fog": true}, 3)
	assert_eq(audio.ambiance_name, "amb_map", "the ambient bed plays")
	for cue in ["march", "recruit", "capital_captured", "ruler_death", "research_complete"]:
		assert_false(audio.history.has(cue), "no report cue (%s) in a hotseat fog game: %s" % [cue, audio.history])
	assert_true(game.session.turns_played() >= 1)
	game.free()
	# The control: the same hotseat game without fog sounds its report.
	audio.history.clear()
	var plain := _hotseat({"players": [CROWN, CLANS], "seed": 4242}, 3)
	assert_true(audio.history.has("march") or audio.history.has("recruit"), "without fog the report sounds: %s" % [audio.history])
	plain.free()
	GameAudio.current = null
	audio.free()


# --- the turn report (§2.8) -------------------------------------------------------------------------

func test_the_report_is_the_viewers_with_its_header() -> void:
	var game := _hotseat({"players": [CROWN, CLANS], "seed": 4242, "fog": true}, 2)
	game.open_turn_report()
	var report := game.session.turn_report_for(CROWN)
	assert_true(_flat(game.report_panel.header_label.text + " " + game.report_panel.fog_label.text).contains(FogView.REPORT_HEADER),
		"the header says the report shows what you saw")
	assert_true(game.report_panel.fog_label.visible)
	var want := []
	for row in TurnReportText.rows(report.events, game.session.state_for(CROWN), CROWN):
		if String(row.event.get("type", "")) != "game_over":
			want.append(String(row.text))
	var got := game.report_panel.event_rows().map(func(b): return b.text)
	assert_eq(got, want, "the rows are the viewer's report")
	for b in game.report_panel.watch_buttons():
		assert_true(Array(b.get_meta("event").get("factions", [])).has(CROWN), "Watch only for battles you fought")
	game.free()
	var plain := _hotseat({"players": [CROWN, CLANS], "seed": 4242}, 2)
	plain.open_turn_report()
	assert_false(plain.report_panel.fog_label.visible, "no fog line without fog")
	plain.free()


func test_watch_is_for_participants_only() -> void:
	var battle := {"type": "battle", "factions": [CROWN, CLANS], "provinces": ["highcrag"], "numbers": {"report": {"sides": []}}}
	assert_eq(BattleHost.fog_problem(battle, CROWN, true), "", "a participant may watch")
	assert_ne(BattleHost.fog_problem(battle, "nobody", true), "", "under fog nobody else may")
	assert_eq(BattleHost.fog_problem(battle, "nobody", false), "", "without fog anyone may")


func test_the_computers_notes_stay_hidden_until_game_over() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true, "ai": {CLANS: "normal"}})
	game.close_turn_report()
	game.end_turn()
	assert_true(game.session.turns_played() == 1)
	game.open_turn_report()
	var notes := game.computer.report_notes(game.session)
	assert_true(not notes.is_empty() and not Array(notes[0].notes).is_empty(), "the computer has notes to hide")
	var shown := _flat(" ".join(game.report_panel.computer_note_labels().map(func(l): return l.text)))
	for line in notes[0].notes:
		assert_false(shown.contains(_flat(String(line))), "under fog the note stays hidden: %s" % line)
	assert_true(shown.contains(_flat(FogView.NOTES_HIDDEN)), "and the section says why: %s" % shown)
	# Game over: the fog lifts and the notes show.
	game.session._phase = GameSession.Phase.GAME_OVER
	game.open_turn_report()
	shown = _flat(" ".join(game.report_panel.computer_note_labels().map(func(l): return l.text)))
	assert_true(shown.contains(_flat(String(notes[0].notes[0]))), "once the game is over the notes show: %s" % shown)
	game.free()
	# Without fog the notes show at once.
	var plain := _game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}})
	plain.close_turn_report()
	plain.end_turn()
	plain.open_turn_report()
	var plain_notes := plain.computer.report_notes(plain.session)
	shown = _flat(" ".join(plain.report_panel.computer_note_labels().map(func(l): return l.text)))
	assert_true(shown.contains(_flat(String(plain_notes[0].notes[0]))), "without fog the notes show: %s" % shown)
	plain.free()


func test_what_you_didnt_see() -> void:
	var s := GameState.new(77)
	s.setup_fog([])
	var crown_army := _army_of(s, CROWN)
	var target := _glimpsed_neighbour(s, crown_army)
	var clans_army := _army_of(s, CLANS)
	_set_units(s, clans_army, target, "tuskers", 8)
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	var shown := int(view.find_army(FogRules.view_id(CLANS, target)).seen.total.shown)
	var tuskers := FogRules.type_name(s, CLANS, "tuskers")
	# 11 Tuskers fought (3 joined during the turn), with a mandate the Crown hadn't seen.
	var event := {"type": "battle", "factions": [CROWN, CLANS], "provinces": [target], "armies": [crown_army.id, FogRules.view_id(CLANS, target)],
		"numbers": {"report": {"sides": [
			{"faction": CROWN, "roster": {"units": [], "commanders": []}},
			{"faction": CLANS, "roster": {"units": [{"id": "tuskers", "name": tuskers, "count": 11}], "commanders": []},
				"mandates": [{"id": "iron_discipline", "name": "Iron Discipline"}]}]}}}
	var text := FogView.missed_text(event, CROWN, view)
	assert_true(text.contains("You had glimpsed about %d %s at %s" % [shown, tuskers, s.find_province(target).name]), text)
	assert_true(text.contains("11 fought you"), text)
	assert_true(text.contains("Iron Discipline, which you hadn't seen"), text)
	# The odds against what was really there: the Crown's army against 11 Tuskers (the M1 game has no mandates), within
	# a sample or two of the odds on the truth (pooling renames the army, which reorders the fighters, §2.10).
	var real := GameState.new(77)
	real.setup_fog([])
	_set_units(real, _army_of(real, CLANS), target, "tuskers", 11)
	var truth_odds := roundi(float(Forecast.battle_odds(real, CROWN, [crown_army.id], target).win_rate) * 100)
	var re := RegEx.new()
	re.compile("Against what was really there, the odds were (\\d+)%")
	var m := re.search(text)
	assert_true(m != null, "the odds against what was there: %s" % text)
	if m != null:
		assert_true(absi(int(m.get_string(1)) - truth_odds) <= roundi(200.0 / AutoBattleResolver.ODDS_SAMPLES),
			"%s%% against the truth's %d%%" % [m.get_string(1), truth_odds])
	# A defence gives no such odds (the forecast is for an attack).
	var defended := event.duplicate(true)
	defended.numbers.report.sides[0]["defender"] = true
	assert_false(FogView.missed_text(defended, CROWN, view).contains("the odds were"), "no odds for a defence")
	# What you saw is what fought: nothing to say.
	event.numbers.report.sides[1].roster.units[0].count = shown
	event.numbers.report.sides[1].erase("mandates")
	assert_eq(FogView.missed_text(event, CROWN, view), "", "nothing you didn't see")


func test_the_first_fog_turn_has_its_hint_until_got_it() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true, "ai": {CLANS: "normal"}})
	assert_true(game.notice_panel.visible, "the first fog turn shows the hint")
	assert_eq(game.notice_label.text, GameScreen.FOG_HINT)
	assert_eq(game.notice_ok.text, "Got it")
	game.notice_ok.pressed.emit()
	assert_false(game.notice_panel.visible)
	assert_true(GameSettings.hint_seen("fog"), "Got it is remembered in the settings")
	game.free()
	# The hint is for the first turn only: it never sits over a turn report (the notice is above the overlays).
	var cfg0 := ConfigFile.new()
	cfg0.load(GameSettings.default_path)
	cfg0.erase_section(GameSettings.HINTS)
	cfg0.save(GameSettings.default_path)
	var later := _game({"players": [CROWN, CLANS], "seed": 4244, "fog": true, "ai": {CLANS: "normal"}})
	later.end_turn()
	assert_true(later.report_overlay.visible, "the turn 1 report opens")
	assert_false(later.notice_panel.visible and later.notice_label.text == GameScreen.FOG_HINT, "no hint over the report")
	later.free()
	GameSettings.mark_hint_seen("fog")
	var again := _game({"players": [CROWN, CLANS], "seed": 4243, "fog": true, "ai": {CLANS: "normal"}})
	assert_false(again.notice_panel.visible and again.notice_label.text == GameScreen.FOG_HINT, "never again")
	again.free()
	var plain := _game({"players": [CROWN, CLANS], "seed": 4243, "ai": {CLANS: "normal"}})
	assert_ne(plain.notice_label.text, GameScreen.FOG_HINT, "no hint without fog")
	plain.free()
	# Leave the run's settings as they were.
	var cfg := ConfigFile.new()
	if cfg.load(GameSettings.default_path) == OK and cfg.has_section(GameSettings.HINTS):
		cfg.erase_section(GameSettings.HINTS)
		cfg.save(GameSettings.default_path)


# --- forecasts (§2.10) ----------------------------------------------------------------------------------

func test_forecast_equals_result_under_the_conditions() -> void:
	var battles := 0
	var sights := 0
	var captures := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var view: GameState = t.view_before[v]
				var truth: GameState = t.before
				battles += _battle_cases(view, truth, v, "%s turn %d, %s" % [g.name, t.turn, v])
				# Sight in `move`: an army that arrived sees what its forecast said it would. A capture: an army that
				# arrived where no battle was fought takes what its forecast said it would.
				var given := []
				var sight_after := FogRules.sight(t.after, v)
				var fought := {}
				for e in t.events:
					if GameSession.BATTLE_TYPES.has(String(e.type)):
						for pid in e.provinces:
							fought[String(pid)] = true
				for o in t.orders[v]:
					if o is MoveOrder:
						var fc := Forecast.move(view, v, o, given)
						var mover := view.find_army(o.army_id)
						var arrived: Army = (t.after as GameState).find_army(o.army_id)
						if fc.ok and mover != null and arrived != null and arrived.location == o.to \
								and int(FogRules.army_sight(arrived).range) == int(fc.sight_range):
							for pid in fc.sees:
								assert_ne(String(sight_after.get(pid)), FogRules.VEILED, "%s turn %d, %s: %s sees %s as forecast" % [g.name, t.turn, v, o.army_id, pid])
							sights += 1
						if fc.ok and bool(fc.would_capture) and arrived != null and arrived.location == o.to and not fought.has(o.to) \
								and not (t.after as GameState).armies.any(func(r): return r.owner != v and r.location == o.to):
							assert_eq((t.after as GameState).find_province(o.to).owner, v, "%s turn %d, %s: %s captured %s as forecast" % [g.name, t.turn, v, o.army_id, o.to])
							captures += 1
					given.append(o)
	# Built cases: a rival army in clear sight (in your own province), and a glimpse whose truth is what it shows.
	var s := GameState.new(91)
	s.setup_fog([])
	var crown_army := _army_of(s, CROWN)
	var own := ""
	for n in s.find_province(crown_army.location).neighbors:
		if s.find_province(n).owner == CROWN:
			own = n
	if own.is_empty():
		own = s.find_province(crown_army.location).neighbors[0]
		s.find_province(own).owner = CROWN
	_set_units(s, _army_of(s, CLANS), own, "tuskers", 6)
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	var built := _battle_cases(view, s, CROWN, "built clear case")
	assert_true(built > 0, "the built clear-sight case ran")
	battles += built
	var s2 := GameState.new(92)
	s2.setup_fog([])
	var crown2 := _army_of(s2, CROWN)
	var target := _glimpsed_neighbour(s2, crown2)
	_set_units(s2, _army_of(s2, CLANS), target, "tuskers", 5)
	var view2 := FogRules.view_state(s2, CROWN, FogRules.new_memory(s2, CROWN), FogRules.new_intel(s2, CROWN))
	var vo := Forecast.view_odds(view2, CROWN, [crown2.id], target)
	var truth_odds := Forecast.battle_odds(s2, CROWN, [crown2.id], target)
	assert_eq(int(vo.wins), int(truth_odds.wins), "a glimpse that shows the truth forecasts the truth")
	var top: Dictionary = view2.find_army(FogRules.view_id(CLANS, target)).seen.total
	var s3 := GameState.new(92)
	s3.setup_fog([])
	_set_units(s3, _army_of(s3, CLANS), target, "tuskers", int(top.high))
	assert_eq(int(vo.top.wins), int(Forecast.battle_odds(s3, CROWN, [crown2.id], target).wins), "the second odds are at the top of the range (%d)" % int(top.high))
	assert_true(battles > 0 and sights > 0, "forecasts were checked: %d battles, %d sight lines" % [battles, sights])
	assert_true(captures > 0, "capture forecasts were checked (%d)" % captures)
	_notes.append("forecast equals result: %d battle forecasts (%d built), %d sight lines, %d captures, over %d games" % [
		battles, built, sights, captures, Kit.games().size()])


## Battle forecasts from `viewer`'s armies into every province next to them where §2.10's conditions hold: the view's
## stand-ins there equal the truth pooled the same way (the same fighters at the same hp: always so in clear sight, and
## so for a glimpse whose truth is exactly what it shows), and the rival's builds are what the view knows. The odds on
## the view must equal the odds on the pooled truth. Returns how many were compared.
func _battle_cases(view: GameState, truth: GameState, viewer: String, where: String) -> int:
	var n := 0
	var sight := FogRules.sight(view, viewer)
	for a in view.armies:
		if a.owner != viewer:
			continue
		for pid in [a.location] + Array(view.find_province(a.location).neighbors):
			if String(sight.get(pid)) == FogRules.VEILED or _pool_key(view, viewer, pid) != _pool_key(truth, viewer, pid):
				continue
			var rivals := {}
			for r in truth.armies:
				if r.owner != viewer and r.location == pid:
					rivals[r.owner] = true
			if rivals.size() != 1:
				continue
			var rival: String = rivals.keys()[0]
			if not _same_builds(view, truth, rival):
				continue
			var pooled := _pooled_truth(truth, view, viewer, pid)
			if pooled == null:
				continue
			var on_view := Forecast.battle_odds(view, viewer, [a.id], pid)
			var on_truth := Forecast.battle_odds(pooled, viewer, [a.id], pid)
			assert_eq(bool(on_view.get("ok", false)), bool(on_truth.get("ok", false)), "%s, %s into %s" % [where, a.id, pid])
			assert_eq(int(on_view.get("wins", -1)), int(on_truth.get("wins", -1)), "%s, %s into %s: forecast equals result" % [where, a.id, pid])
			var vo := Forecast.view_odds(view, viewer, [a.id], pid)
			assert_eq(int(vo.get("wins", -1)), int(on_view.get("wins", -1)), "%s: the fog forecast is the same fight" % where)
			n += 1
	return n


## The rival fighters at `pid` as a sorted list of "type:hp" (the ruler and commanders marked), whatever armies they are in.
static func _pool_key(s: GameState, viewer: String, pid: String) -> String:
	var out := []
	for a in s.armies:
		if a.owner == viewer or a.location != pid or String(a.seen.get("level", "")) == FogData.MEMORY:
			continue
		for u in a.units:
			out.append("%s:%s:%d" % [a.owner, u.type.id, u.current_hp])
		if a.commander != null:
			out.append("%s:c:%s:%d" % [a.owner, a.commander.type.id, a.commander.current_hp])
		if a.ruler != null:
			out.append("%s:r:%s:%d" % [a.owner, a.ruler.type.id, a.ruler.current_hp])
	out.sort()
	return ",".join(out)


## The truth with the rival armies at `pid` pooled as the view pools them (its stand-ins), nothing else changed.
func _pooled_truth(truth: GameState, view: GameState, viewer: String, pid: String) -> GameState:
	var d := truth.to_dict()
	d.armies = d.armies.filter(func(ad): return ad.owner == viewer or ad.location != pid)
	for a in view.armies:
		if a.owner != viewer and a.location == pid:
			var ad := a.to_dict()
			ad.erase("seen")
			d.armies.append(ad)
	var errors := []
	var out := GameState.from_dict(d, errors)
	return out


func _same_builds(view: GameState, truth: GameState, rival: String) -> bool:
	var fv := view.find_faction(rival)
	var ft := truth.find_faction(rival)
	var nodes := _sorted(AscensionRules.researched(view, rival)) == _sorted(AscensionRules.researched(truth, rival))
	if not ft.has_ruler():
		return nodes
	return _sorted(fv.mandates) == _sorted(ft.mandates) and fv.kept_power == ft.kept_power and nodes


static func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


func test_the_forecasts_fog_text() -> void:
	var s := GameState.new(93)
	s.setup_fog([])
	var army := _army_of(s, CROWN)
	var target := _glimpsed_neighbour(s, army)
	_set_units(s, _army_of(s, CLANS), target, "tuskers", 9)
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	var vo := Forecast.view_odds(view, CROWN, [army.id], target)
	assert_true(vo.ok and vo.fog, "a fog forecast")
	var short := String(vo.short)
	assert_true(short.begins_with("Odds against what you can see: "), short)
	assert_eq(short.count("%"), 2, "two odds: %s" % short)
	assert_true(short.contains("if they are at the top of the range") and short.contains("ⓘ"), short)
	var info := _flat("\n".join(vo.assumptions))
	var total: Dictionary = view.find_army(FogRules.view_id(CLANS, target)).seen.total
	assert_true(info.contains("about %d (%d-%d)" % [int(total.shown), int(total.low), int(total.high)]), "the sighting with its range: %s" % info)
	assert_true(info.contains("may have more you haven't seen"), info)
	# The map's hover preview and the order line carry it.
	var map := _map(view, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN), null)
	map.select_army(army.id)
	var preview := map.preview_move(target)
	assert_true(preview.contains(short), "the hover preview: %s" % preview)
	assert_true(preview.contains("Next turn this army will see") or preview.contains("sees nothing new"), "sight in move: %s" % preview)
	map.select_province(target)
	var line: Label = map.details.find_child("OrderLine", true, false)
	assert_true(line != null and _flat(line.tooltip_text).contains("may have more you haven't seen"), "the order line's ⓘ lists the guesses")
	map.free()
	# Out of sight: no odds.
	var far := ""
	var sight := FogRules.sight(view, CROWN)
	for pid in sight:
		if sight[pid] == FogRules.VEILED:
			far = pid
	# A glimpse of 1-2 is at the top of its range already: one odds, and the count reads "1-2", not "1-2 (1-2)".
	var s2 := GameState.new(93)
	s2.setup_fog([])
	var army2 := _army_of(s2, CROWN)
	_set_units(s2, _army_of(s2, CLANS), target, "tuskers", 1)
	var view2 := FogRules.view_state(s2, CROWN, FogRules.new_memory(s2, CROWN), FogRules.new_intel(s2, CROWN))
	var few := Forecast.view_odds(view2, CROWN, [army2.id], target)
	assert_eq(String(few.short).count("%"), 1, "one odds when the top adds no one: %s" % few.short)
	assert_false(few.has("top"))
	var move_text := String(Forecast.move(view2, CROWN, MoveOrder.new(army2.id, target)).text)
	assert_true(move_text.contains("1-2 fighters") and not move_text.contains("1-2 (1-2)"), move_text)
	var no := Forecast.view_odds(view, CROWN, [army.id], far, FogRules.new_memory(s, CROWN))
	assert_true(bool(no.no_odds), "no odds out of sight")
	assert_true(String(no.short).contains("You can't see %s" % s.find_province(far).name) and String(no.short).contains("never seen") \
		and String(no.short).ends_with("No odds."), String(no.short))


func test_scout_lines() -> void:
	var s := GameState.new(94)
	s.setup_fog([])
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	var army := _army_of(view, CROWN)
	var sight := FogRules.army_sight(army)
	assert_true(FogView.army_sight_line(army).begins_with("This army sees %d province" % int(sight.range)), FogView.army_sight_line(army))
	var map := _map(view, CROWN, {}, {}, null)
	map.select_army(army.id)
	assert_true(_flat(_texts(map.details)).contains(FogView.army_sight_line(army)), "the army panel says how far it sees")
	var scouts := 0
	for u in army.units:
		if FogRules.is_scout(u.type):
			assert_eq(FogView.scout_line(u.type), "Scout: sees %d provinces." % int(FogData.SIGHT.scout))
			var count: Label = map.details.find_child("UnitRow_%s" % u.type.id.validate_node_name(), true, false).find_child("UnitCount", true, false)
			assert_true(_flat(count.tooltip_text).contains("Scout: sees"), "the unit's tooltip names the scout")
			scouts += 1
			break
	assert_true(scouts > 0, "the Crown starts with a scout")
	# Sight in the move forecast: exactly the provinces in range of the destination that are out of sight now.
	var to: String = view.find_province(army.location).neighbors[0]
	var fc := Forecast.move(view, CROWN, MoveOrder.new(army.id, to))
	var want := []
	var now := FogRules.sight(view, CROWN)
	for pid in FogRules.distances(view, to, int(sight.range)):
		if now[pid] == FogRules.VEILED:
			want.append(pid)
	want.sort()
	var got: Array = fc.sees.duplicate()
	got.sort()
	assert_eq(got, want, "the provinces it will see that you can't see now")
	map.free()


# --- the Vision map mode is retired (UX-2); the legend's words stay (§11.1) -------------------------------------------

func test_the_vision_map_mode_is_retired_and_its_legend_text_is_kept() -> void:
	var g: Dictionary = _kinds()[0]
	var t: Dictionary = g.turns.back()
	var view: GameState = t.view_after[CROWN]
	var map := _map(view, CROWN, t.memory_after[CROWN], t.intel_after[CROWN], t.view_before[CROWN])
	assert_true(map.find_child("VisionButton", true, false) == null, "no Vision button")
	assert_true(map.find_child("VisionLegend", true, false) == null, "no Vision legend")
	assert_false(map.has_method("set_map_mode"), "no Vision map mode to switch to")
	# the 2D map still knows every province's level (its veil, the plate's hover) and the card's Vision line is as it was
	var sight := FogRules.sight(view, CROWN)
	var memory: Dictionary = t.memory_after[CROWN]
	for pid in sight:
		var want: String = sight[pid]
		if want == FogRules.VEILED and int(memory.provinces.get(pid, {}).get("seen_turn", -1)) < 0:
			want = "never"
		assert_eq(map.regions[pid].vision_level, want, "%s is veiled as %s" % [pid, want])
	# the legend's text stays in FogView for UX-7's Sight lens: a row per level with its words, and the plate and the ghost
	var rows := FogView.legend_rows(view)
	var text := _flat(" ".join(rows.map(func(r): return "%s %s %s" % [r.title, r.short, r.text])))
	for word in ["In clear sight", "Glimpsed", "Out of sight", "Never seen", "≈", "remembered"]:
		assert_true(text.contains(word), "the kept legend explains %s: %s" % [word, text])
	# UX-7: the Vision legend's job moved to the Sight lens: its legend card carries every row, each with its veil's swatch and its words
	map.lens_host.activate("sight")
	var card := map.lens_ui.legend
	assert_true(card.visible, "the Sight lens shows its legend")
	var shown := card.text()
	for r in rows:
		assert_true(shown.contains("%s: %s" % [r.title, r.short]), "the Sight lens's legend has the row %s" % r.title)
	var grid := card.find_child("SightRows", true, false)
	assert_true(grid != null and grid.get_child_count() == rows.size() * 2, "a swatch and a line per row")
	for l in grid.find_children("SightRow*", "Label", true, false):
		assert_false((l as Label).tooltip_text.is_empty(), "each row's hover says what it means")
	# and its "why do I see this": every province's sight sources, from FogRules.sight_sources, in each plate's hover
	var lens := map.lens_ui.result()
	for src in FogRules.sight_sources(view, CROWN):
		var e: Dictionary = lens.entries[String(src.province)]
		assert_true(String(e.text).begins_with("sees") or String(e.text) == "Far Sight", "%s is a source and its plate says what it sees" % src.province)
	map.lens_host.clear()
	map.free()


# --- panels: the rival ruler and research (§11.1) ------------------------------------------------------

func test_the_rival_ruler_is_alive_location_unknown() -> void:
	var s := GameState.with_rulers(95)
	s.setup_fog([])
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	assert_true(RulerRules.ruler_alive(view, CLANS) and RulerRules.ruler_army(view, CLANS) == null, "the Clans' ruler is out of sight")
	var panel := RulerPanel.new()
	panel.fog_intel = FogRules.new_intel(s, CROWN)
	panel.show_for(view, CROWN, null)
	var col := _flat(_texts(panel.columns.get_node("Column_%s" % CLANS)))
	assert_true(col.contains("Alive, location unknown"), col)
	assert_true(col.contains("What you know about the %s" % s.find_faction(CLANS).faction_name), col)
	assert_true(col.contains("the most it could be"), col)
	assert_true(col.contains("They may have more"), col)
	var own := _flat(_texts(panel.columns.get_node("Column_%s" % CROWN)))
	assert_true(own.contains("Alive at"), "your own ruler is where it is: %s" % own)
	panel.free()


# --- hotseat: seat 2's panels under seat 1's hidden facts (§2.9) ---------------------------------------

func test_hotseat_seat_2_panels_are_identical_under_perturb_hidden() -> void:
	var game := _hotseat({"players": [CROWN, CLANS], "seed": 4242, "fog": true, "paths": true}, 3)
	# Seat 1 gives no orders; seat 2 takes the computer.
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	assert_eq(game.session.current_player(), CLANS)
	var base := _dump(game)
	var changed := 0
	for k in 3:
		var p := Kit.perturb_hidden(game.session._state, CLANS, 4100 + k)
		assert_eq(p.errors, [], "the perturbed state is a valid game")
		if p.state == null:
			continue
		var truth: GameState = game.session._state
		game.session._state = p.state
		game.session._fog_cache.erase("state|" + CLANS)
		game._show_current_player()
		assert_eq(_dump(game), base, "perturbation %d: seat 2's screens are identical" % k)
		game.session._state = truth
		game.session._fog_cache.erase("state|" + CLANS)
		changed += 1
	assert_true(changed > 0)
	_notes.append("seat 2's screens compared under %d perturbations of seat 1's hidden facts (%d characters each)" % [changed, base.length()])
	game.free()


## Everything seat 2 can read: the Table (the realm plaque, the system row, the opponent plaque, the tray), every region and its badges, the side panel of every province, the
## ruler panel, the enemy's path and the turn report.
func _dump(game: GameScreen) -> String:
	var map := game.map
	game._show_current_player()
	var out := PackedStringArray([_texts(map.table())])
	var ids: Array = map.regions.keys()
	ids.sort()
	for pid in ids:
		out.append(_texts(map.regions[pid]) + map.regions[pid].tooltip_text)
	for pid in ids:
		map.selected_army_id = ""
		map.select_province(pid)
		out.append(_texts(map.details))
	map.open_ruler_panel()
	out.append(_texts(map.ruler_panel))
	map.close_ruler_panel()
	game.research_hud.open_panel()
	for fid in game.session.players():
		if fid != CLANS:
			game.research_hud.panel.show_enemy(fid)
			out.append(_texts(game.research_hud.panel))
	game.research_hud.close_all()
	game.open_turn_report()
	out.append(_texts(game.report_panel))
	game.close_turn_report()
	return "\n".join(out)


# --- the victory screen: the fog lifts (§2.1) -------------------------------------------------------------

func test_the_victory_screen_lifts_the_fog() -> void:
	var s := GameState.with_rulers(96)
	s.setup_fog([])
	var lift := FogView.lift(s, [CROWN, CLANS], [{"turn": 4, "faction": CROWN, "text": "You had glimpsed about 5 Tuskers at Thornvale; 8 fought you."}])
	var screen := VictoryScreen.new()
	screen.fog_lift = lift
	screen.show_victory({"winner": CROWN, "turn": 9, "turns_played": 9, "text": "", "provinces_held": {CROWN: 9, CLANS: 7}}, s, [CROWN, CLANS])
	var text := _flat(_texts(screen))
	assert_true(text.contains("The fog lifts"), text)
	for f in s.factions:
		assert_true(text.contains(f.faction_name), text)
		for mid in f.mandates:
			assert_true(text.contains(RulerRules.mandate_name(mid)), "%s's mandates: %s" % [f.id, text])
		assert_true(text.contains("kept power %d" % f.kept_power), text)
	assert_true(text.contains("You had glimpsed about 5 Tuskers at Thornvale"), "every what-you-didn't-see: %s" % text)
	screen.free()
	var plain := VictoryScreen.new()
	plain.show_victory({"winner": CROWN, "turn": 9, "turns_played": 9, "text": "", "provinces_held": {CROWN: 9, CLANS: 7}}, GameState.new(1), [CROWN, CLANS])
	assert_false(_flat(_texts(plain)).contains("The fog lifts"), "only fog games")
	plain.free()


# --- helpers ----------------------------------------------------------------------------------------

## Every visible text and tooltip under `root`, in tree order.
static func _texts(root: Node) -> String:
	var out := PackedStringArray()
	for c in [root] + root.find_children("*", "", true, false):
		if not _shown(c, root):
			continue
		if c is Label or c is Button or c is RichTextLabel:
			out.append(String(c.text))
		if c is Control and not String(c.tooltip_text).is_empty():
			out.append(String(c.tooltip_text))
	return "\n".join(out)


## True when `node` and every parent up to `root` are visible (in the tree or not).
static func _shown(node: Node, root: Node) -> bool:
	var n := node
	while n != null:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		if n == root:
			return true
		n = n.get_parent()
	return true


static func _army_of(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid and a.ruler == null:
			return a
	return null


## A neighbour of `army`'s province that `army`'s owner glimpses (not its own and with none of its armies).
static func _glimpsed_neighbour(s: GameState, army: Army) -> String:
	var sight := FogRules.sight(s, army.owner)
	for n in s.find_province(army.location).neighbors:
		if sight[n] == FogRules.GLIMPSE:
			return n
	return ""


## Puts `army` at `pid` with `n` units of `type_id` at full hp and no commander.
static func _set_units(s: GameState, army: Army, pid: String, type_id: String, n: int) -> void:
	var f := s.find_faction(army.owner)
	var ut: UnitType = null
	for t in f.unit_types:
		if t.id == type_id:
			ut = t
	army.location = pid
	army.commander = null
	army.units.clear()
	for i in n:
		army.units.append(Unit.new(ut, army.owner))
