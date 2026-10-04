class_name GameScreen
extends Control
## The one main screen of a hotseat game (#6, #7, #8). It hosts the MapScreen for the player at the
## controls and adds a HUD to its top bar (Results, Turn report, Codex, End turn, Menu). On
## top of the map it shows the turn report at the start of each player's turn, the battle report
## viewer, the codex, the victory screen and the handoff cover between players.
## Everything goes through GameSession: this screen reads the session and calls its API. It never
## changes rules state itself and holds no rules math. The map's orders are backed by the session's
## order books (OrdersController in session mode), and every forecast comes from Forecast.
##
## Layers, bottom to top:
##   the map (this Control)
##   Overlays (CanvasLayer 10): victory screen, turn report, battle report viewer, codex, setup errors,
##             quit confirmation, the game menu, the save dialog, the load screen and settings. Each opens
##             on top of whatever is already open (_raise), so the codex opened from a report's "?" sits
##             above the report, and closing it shows the report again.
##   NoticeLayer (CanvasLayer 15): a small notice under the top bar ("Game saved", "Game loaded"). It
##             never blocks the map, and it sits under the handoff cover.
##   HandoffLayer (CanvasLayer 20): the handoff cover, above everything, so nothing leaks between players.
##
## Saving (SaveGame, SaveStore): the game saves itself at the start of every turn, once the last turn
## has resolved and before any computer seat plans the new one (and at the start of turn 1); the store
## keeps the last three autosaves. Menu (the top bar, or Esc) has Save game (name it, or keep the
## timestamped default), Load game, Settings and Quit to title. A save is always the game as it stood at
## the start of the turn, with the computer's dice from that moment, so orders queued during a turn are
## not saved: the save dialog, the quit question and the load notice all say so. Loading (load_game)
## replays the save into a new session; a hotseat game comes back behind the handoff cover.
##
## Codex links (#8): every number on the map (and in the reports and the victory screen) names its
## codex entry in its tooltip; right-click or F1 while hovering opens the codex there (CodexLink).
## Colours follow the seat: the map, the battle report and the victory screen get the session's seat
## order (UiPalette).
##
## Computer seats (#35): config "ai" ({faction id: "easy" or "normal"}) gives seats to the computer.
## One AISeat plays them for the whole game (one AIPlayer and one seeded RNG per seat). After every
## End turn (and at the start) it plays each computer seat that is due, so with one human there is no
## handoff at all: the human ends the turn, the computer gives its orders from the start-of-turn state
## (never seeing the human's), the turn resolves and the human gets the turn report, with the
## computer's notes for that turn in a collapsible section. A computer in seat 1 plays at the start of
## each turn, before the human, from the same start-of-turn state. The top bar names the computer
## faction with its "Computer (Normal)" tag. Two humans play exactly as before. With no human seat at
## all (watch mode), End turn becomes Next turn and plays one whole turn per press.
##
## API:
##   start_game(config)   config = {"players": [faction ids in seat order], "seed": int, "ai": {faction id:
##                        level}}. "ai" is optional (absent: every seat is human). Missing keys get
##                        default_config() values: every faction in data order and a random seed.
##                        Rulers (M2) are opt-in until battles and succession handle them: config
##                        "rulers": true, or "builds": {faction id: build or preset id}, or the
##                        `-- --rulers` command-line switch for playtests (starting_state()).
##                        If the screen enters the tree without start_game(), it starts a default game.
##   load_game(save)      plays on from a save (SaveGame): "" or why it can't be loaded, in plain words.
##                        Used by SceneFlow.make_loaded_game and by Menu > Load game (in place).
##   save_game(name)      Menu > Save game: a manual save. "" or why not. autosave() is the turn-start one.
##   open_menu()          the Menu button and Esc: Resume, Save game, Load game, Settings, Quit to title.
##   end_turn()           the End turn button: hands off to the next player, or resolves the turn. With
##                        computer seats, the computer then plays at once. In watch mode: next_turn().
##   next_turn()          watch mode only: both computers give their orders and the turn resolves.
##   open_turn_report()   the Turn report button: the last resolved turn's report.
##   open_codex(key)      the Codex button, a report's "?", a right-click on a linked number.
##   show_results()       the Results button once the game is over: the victory screen again.
##   open_ruler_panel()   the Ruler button (M2-6, games with rulers only): the map's ruler panel.
##   session              the GameSession being played. Read it; act through the API above.
##   computer             the AISeat playing the computer seats (it has none in a hotseat game).
##   save_store           where saves go (SaveStore, user://saves unless set before the game starts).
##   next_scene           the screen this one switched to (SceneFlow), e.g. the title after "New game".

const SCENE := "res://ui/game_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"

var session: GameSession = null
var computer: AISeat = null  # plays the computer seats of `session`
var config := {}  # the config the running game was started with (defaults filled in)
var next_scene: Node = null  # the screen this one handed over to (SceneFlow.switch)
var save_store: SaveStore = null  # SaveStore.new() unless set before start_game / load_game
var autosave_enabled := true
var loaded_header := {}  # the header of the save this game was loaded from ({} for a new game)

# Nodes. Bound or built by _bind(), so the screen also works before it is in the tree (tests).
var map: MapScreen
var overlays: CanvasLayer  # every modal above the map; the last one opened is on top
var handoff: HandoffScreen  # on its own CanvasLayer above everything else
var end_turn_button: Button
var report_button: Button
var codex_button: Button
var results_button: Button  # only once the game is over
var ruler_button: Button  # M2-6: opens the ruler panel; only in a game with rulers
var research_hud: ResearchHud  # M4-4: the research chip, the research panel and the lock-in preview
var report_overlay: Control
var report_panel: TurnReportPanel
var battle_viewer: BattleReportViewer
var codex: CodexPanel
var victory_screen: VictoryScreen
var error_overlay: Control
var error_title: Label
var error_label: Label
var quit_overlay: Control
var opponent_box: HBoxContainer  # top bar: the computer seats, each with its tag (#35)
var menu_overlay: Control  # Menu: Resume, Save game, Load game, Settings, Quit to title
var menu_text: Label
var menu_save_button: Button
var save_overlay: Control  # the save dialog
var save_name_edit: LineEdit
var save_note: Label
var save_error: Label
var load_screen: LoadScreen
var settings_panel: SettingsPanel
var quit_text: Label
var notice_panel: PanelContainer  # on the NoticeLayer: "Game saved", "Game loaded"
var notice_title: Label
var notice_label: Label
var _report_seen := 0  # the last turn report shown to the only human, so each one opens once
var _snapshot := {}  # SaveGame.computer_snapshot from the start of the turn being played
var _turn_start_turns := -1  # session.turns_played() when the current turn started (and was autosaved)
var _last_autosave_turn := 0  # the turn the last autosave was made at the start of (0: none)
var _bound := false


func _ready() -> void:
	_bind()
	if session == null:
		start_game(default_config())


## Every faction in data order, and a random seed.
static func default_config() -> Dictionary:
	var players := []
	for f in FactionData.FACTIONS:
		players.append(f.id)
	return {"players": players, "seed": randi()}


## Starts a new hotseat game. See the class comment for `game_config`.
func start_game(game_config: Dictionary = {}) -> void:
	_bind()
	config = default_config()
	config.merge(game_config, true)
	config.players = Array(config.players).duplicate()
	config.seed = int(config.seed)
	var ai := {}
	var ai_errors := []
	if config.get("ai") is Dictionary:
		for fid in config.ai:
			ai[String(fid)] = String(config.ai[fid])
	elif config.get("ai") != null:
		ai_errors.append("The computer seats must be listed as faction and level, like Thornmane Clans: Normal.")
	if ai.is_empty():
		config.erase("ai")  # a hotseat game's config stays {"players", "seed"}
	else:
		config.ai = ai
	_reset_screens()
	loaded_header = {}
	# The state's seed and the game seed are the same, so GameSession's turn seeds match TurnResolver's.
	session = GameSession.new(starting_state(config), config.players, config.seed, AutoBattleResolver.new(), ai)
	computer = AISeat.new(session, config.seed)
	map.session = session
	_build_opponent_tag()
	if session.phase() == GameSession.Phase.INVALID or not ai_errors.is_empty():
		_show_setup_errors(ai_errors + session.setup_errors())
		return
	_turn_start_turns = -1
	_check_turn_start()  # the turn-1 autosave, before a computer in seat 1 plans
	_advance()


## Plays on from `save` (SaveGame): the record is replayed into a new session at the start of the
## saved turn, and each computer seat gets its dice back, so the game goes on exactly as it would have.
## A game with two people opens on the handoff cover; otherwise the player at the controls gets the
## last turn's report and a notice that orders given during the turn were not saved. Returns "" or why
## the save can't be loaded, in plain words (the running game, if any, is then left as it was).
func load_game(save: Dictionary) -> String:
	_bind()
	var restored := SaveGame.restore(save, AutoBattleResolver.new())
	if not restored.errors.is_empty():
		return SaveGame.error_text(restored.errors)
	_reset_screens()
	config = restored.config
	loaded_header = restored.header
	session = restored.session
	computer = restored.computer
	map.session = session
	_build_opponent_tag()
	# The save is the start of this turn: it counts as this turn's autosave.
	_turn_start_turns = session.turns_played()
	_snapshot = SaveGame.computer_snapshot(computer, session)
	_last_autosave_turn = session.turn_number()
	_advance()
	var saved_name := String(loaded_header.get("name", "your save"))
	show_notice("Game loaded", "\"%s\": the start of turn %d. %s" % [saved_name, session.turn_number(), SaveGame.ORDERS_NOTE])
	return ""


## Saves the game as it stood at the start of this turn, under `save_name` ("" gives "Saved <date and
## time>"). Returns "" or why it could not be saved.
func save_game(save_name: String = "") -> String:
	var why := _cannot_save()
	if not why.is_empty():
		return why
	var result := _store().write(SaveGame.make(session, _snapshot, SaveGame.MANUAL, save_name, _now()))
	return String(result.error)


## The start-of-turn autosave. Returns "" or why it could not be saved.
func autosave() -> String:
	var why := _cannot_save()
	if not why.is_empty():
		return why
	var result := _store().write(SaveGame.make(session, _snapshot, SaveGame.AUTO, "", _now()))
	if String(result.error).is_empty():
		_last_autosave_turn = session.turn_number()
	return String(result.error)


## "" when the game can be saved now, otherwise why not.
func _cannot_save() -> String:
	if session == null or session.phase() == GameSession.Phase.INVALID:
		return "There is no game to save."
	if session.is_over():
		return "The game is over, so there is nothing left to save."
	return ""


func _store() -> SaveStore:
	if save_store == null:
		save_store = SaveStore.new()
	return save_store


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


## A new turn has started when the session has resolved more turns than when the last one started:
## take the computer's snapshot for saves (no computer seat has planned the new turn yet) and autosave.
func _check_turn_start() -> void:
	if session == null or session.turns_played() == _turn_start_turns:
		return
	_turn_start_turns = session.turns_played()
	_snapshot = SaveGame.computer_snapshot(computer, session)
	if autosave_enabled and not session.is_over():
		var why := autosave()
		if not why.is_empty():
			show_notice("Autosave failed", why)


## The starting state for `game_config`: the M1 game, or with rulers when the config asks for them
## ("rulers": true, or "builds") or the game was launched with `-- --rulers`; with paths (M4-1) when it has
## "paths": true or the game was launched with `-- --paths`. Factions without a
## build get their balanced preset. Null when a build is illegal (the session then explains).
static func starting_state(game_config: Dictionary) -> GameState:
	var seed_value := int(game_config.get("seed", 0))
	if game_config.get("paths", false) or OS.get_cmdline_user_args().has("--paths"):
		return GameState.with_paths(seed_value, game_config.get("builds", {}), [])  # M4-1: paths need rulers
	if game_config.get("rulers", false) or game_config.has("builds") or OS.get_cmdline_user_args().has("--rulers"):
		return GameState.with_rulers(seed_value, game_config.get("builds", {}), [])
	return GameState.new(seed_value)


## Ends the current player's turn. Returns "" or the session's reason it could not.
func end_turn() -> String:
	if session == null:
		return "No game is running."
	if is_watching():
		return next_turn()
	var why := session.end_turn()
	if not why.is_empty():
		map.set_hint(why)
		return why
	_check_turn_start()  # the last seat's End turn resolved the turn: autosave before a computer plans
	_close_overlays()
	notice_panel.visible = false
	_advance()
	return ""


## Watch mode (no human seat): every computer seat gives its orders and the turn resolves, then the
## turn report opens. Returns "" or why it could not.
func next_turn() -> String:
	if not is_watching():
		return "Next turn is only for games where the computer plays every seat."
	_close_overlays()
	computer.play(session)
	_check_turn_start()
	if session.is_over():
		_show_game_over()
		return ""
	_show_watch()
	open_turn_report()
	return ""


## True while nobody but the computer plays (watch mode) and the game is running.
func is_watching() -> bool:
	return session != null and session.human_seats() == 0 and session.is_computer_turn()


## Shows the last resolved turn's report on top. Does nothing before the first turn is resolved.
func open_turn_report() -> void:
	_bind()
	if session == null or session.turn_report().turn == 0:
		return
	# The computer's notes are those of the turn the report shows, which has resolved (AISeat.report_notes).
	report_panel.show_report(session, computer.report_notes(session) if computer else [])
	_report_seen = maxi(_report_seen, session.turn_report().turn)
	_raise(report_overlay)


func close_turn_report() -> void:
	report_overlay.visible = false


## Opens the codex on top of everything open, at `key` when given. Closing it shows what was under it.
func open_codex(key: String = "") -> void:
	_bind()
	_raise(codex)
	codex.open(key)


## The Ruler button (M2-6): the map's ruler panel, your ruler and the enemy's, with the sacrifice dialog.
func open_ruler_panel() -> void:
	_bind()
	map.open_ruler_panel()


## The victory screen again (the Results button after "View the map").
func show_results() -> void:
	_bind()
	if session != null and victory_screen.show_for(session):
		_raise(victory_screen)


# --- the turn cycle -------------------------------------------------------------------------------

## After a seat ends its turn, and at the start: the computer plays every computer seat that is due
## (not in watch mode, where Next turn does), then the screen shows whoever acts next. With one human,
## each newly resolved turn's report opens as their turn starts; there is no handoff to wait behind.
func _advance() -> void:
	if session.human_seats() > 0:
		computer.play(session)
		_check_turn_start()  # a computer in the last seat resolved the turn
	match session.phase():
		GameSession.Phase.HANDOFF:
			_show_handoff()
		GameSession.Phase.ORDERS:
			if session.is_computer_turn():
				_show_watch()
				return
			_show_current_player()
			if session.human_seats() == 1 and session.turn_report().turn > _report_seen:
				open_turn_report()
		GameSession.Phase.GAME_OVER:
			_show_game_over()

## The current player's ORDERS phase: their map, their orders, their capital selected for recruiting.
func _show_current_player() -> void:
	var fid := session.current_player()
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	map.set_state(session.state(), fid)
	var f := map.state.find_faction(fid)
	var capital: Province = map.state.find_province(f.capital) if f else null
	if capital and capital.owner == fid:
		map.select_province(capital.id)
	_update_hud()


## Watch mode: the map seen by nobody in particular, waiting for Next turn.
func _show_watch() -> void:
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	map.set_state(session.state(), "")
	map.faction_label.text = "Watching"
	map.faction_label.tooltip_text = TooltipText.plain("Watching the computer play",
		"The computer plays every seat, so you only watch. Press Next turn to have each computer give its orders and resolve the turn. The turn report shows what each one was thinking.")
	CodexLink.attach(map.faction_label, "computer_opponent", open_codex)
	_update_hud()


## Covers everything and hides the map until the next player presses Ready.
func _show_handoff() -> void:
	map.clear_preview()
	map.visible = false
	handoff.show_for(session)
	_update_hud()


func _on_handoff_acknowledged() -> void:
	_show_current_player()
	if session.turn_report().turn > 0:
		open_turn_report()


## The final map, seen by nobody in particular, under the victory screen.
func _show_game_over() -> void:
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	map.set_state(session.state(), "")
	map.faction_label.text = "Game over"
	map.faction_label.tooltip_text = TooltipText.plain("Game over", "Nobody gives orders any more. The map shows the final positions.")
	CodexLink.attach(map.faction_label, TooltipText.codex_for("draw" if session.victory().get("draw", false) else "game_over"), open_codex)
	_update_hud()
	_show_victory(session.victory())


## Clicking a report line closes the report and shows that province on the map.
func _on_report_focus(province_id: String) -> void:
	close_turn_report()
	map.selected_army_id = ""  # so the click can't be taken as a move order for a selected army
	map.focus_province(province_id)


func _on_quit_requested() -> void:
	if session == null or session.is_over() or session.phase() == GameSession.Phase.INVALID:
		_go_to_title()
		return
	quit_text.text = _saved_text() + " Orders you have given this turn are not saved."
	_raise(quit_overlay)


## "The game saved itself at the start of turn 4." (or that it has not been saved yet).
func _saved_text() -> String:
	if session != null and _last_autosave_turn == session.turn_number():
		return "The game saved itself at the start of turn %d." % _last_autosave_turn
	return "This turn has not been saved."


# --- the menu, saving and loading -----------------------------------------------------------------

## The Menu button (and Esc with nothing open): Resume, Save game, Load game, Settings, Quit to title.
func open_menu() -> void:
	_bind()
	var why := _cannot_save()
	menu_save_button.disabled = not why.is_empty()
	menu_save_button.tooltip_text = why if not why.is_empty() else "Save this game under a name of your choice. %s" % SaveGame.ORDERS_NOTE
	menu_text.text = why
	if why.is_empty():
		menu_text.text = "Turn %d. %s" % [session.turn_number(),
			"Autosaved when it began." if _last_autosave_turn == session.turn_number() else "Not saved yet."]
	_raise(menu_overlay)


func close_menu() -> void:
	menu_overlay.visible = false


## Menu > Save game: the dialog with a name box (empty keeps the timestamped default).
func open_save_dialog() -> void:
	_bind()
	var why := _cannot_save()
	if not why.is_empty():
		show_notice("Can't save", why)
		return
	save_name_edit.text = ""
	save_name_edit.placeholder_text = SaveGame.default_name(SaveGame.MANUAL, _now())
	save_note.text = "Saves the game as it stood at the start of turn %d. Orders you have given this turn are not saved: when you load it, turn %d starts again from the beginning." % [
		session.turn_number(), session.turn_number()]
	save_error.visible = false
	_raise(save_overlay)
	if save_name_edit.is_inside_tree():
		save_name_edit.grab_focus.call_deferred()


## The save dialog's Save button (or Enter in the name box).
func confirm_save() -> String:
	var typed := save_name_edit.text.strip_edges()
	var why := save_game(typed)
	if not why.is_empty():
		save_error.text = why
		save_error.visible = true
		return why
	save_overlay.visible = false
	menu_overlay.visible = false
	show_notice("Game saved", "Saved as \"%s\". %s" % [typed if not typed.is_empty() else save_name_edit.placeholder_text, SaveGame.ORDERS_NOTE])
	return ""


## Menu > Load game: every save; loading one replaces this game (load_game).
func open_load_screen() -> void:
	_bind()
	_raise(load_screen)
	load_screen.open(_store())


func _on_load_requested(save: Dictionary) -> void:
	var why := load_game(save)
	if not why.is_empty():
		load_screen.show_error(why)


func open_settings() -> void:
	_bind()
	_raise(settings_panel)
	settings_panel.open()


## A small notice under the top bar that never blocks the map. OK hides it, and so does End turn.
func show_notice(title: String, text: String) -> void:
	_bind()
	notice_title.text = title
	notice_label.text = text
	notice_panel.visible = true


func _go_to_title() -> void:
	_switch(SceneFlow.make_title())


## "New game" on the victory screen: the new game screen (over the title, where Back leads), set up
## for a rematch: the same players in the same seats, and a new seed.
func _go_to_new_game() -> void:
	_switch(SceneFlow.make_title(true, config))


func _switch(next: Node) -> void:
	next_scene = next
	SceneFlow.switch(self, next)


func _close_overlays() -> void:
	report_overlay.visible = false
	battle_viewer.visible = false
	quit_overlay.visible = false
	menu_overlay.visible = false
	save_overlay.visible = false
	load_screen.visible = false
	settings_panel.visible = false
	if codex.visible:
		codex.close()


## Before a game starts or loads: nothing of the last game stays on screen.
func _reset_screens() -> void:
	_close_overlays()
	victory_screen.visible = false
	error_overlay.visible = false
	handoff.visible = false
	notice_panel.visible = false
	_report_seen = 0


## Shows an overlay above every other overlay: the last one opened is always on top.
func _raise(overlay: Control) -> void:
	overlays.move_child(overlay, overlays.get_child_count() - 1)
	overlay.visible = true


## F1 over a number linked to the codex opens its entry (right-click is handled by the link itself).
## Esc on the codex is the codex panel's own business (CodexPanel.handle_cancel).
func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if not CodexLink.is_open_key(event):
		return
	var key := CodexLink.key_at(get_viewport().gui_get_hovered_control())
	if not key.is_empty():
		get_viewport().set_input_as_handled()
		open_codex(key)


## The visible overlay drawn on top, or null.
func _top_overlay() -> Control:
	for i in range(overlays.get_child_count() - 1, -1, -1):
		var overlay := overlays.get_child(i) as Control
		if overlay != null and overlay.visible:
			return overlay
	return null


## Esc closes the topmost plain overlay (the report, the quit question, the menu, the save dialog), or
## opens the menu when nothing is open. The battle report viewer, the codex, the load screen and the
## settings close themselves, the victory screen stays, and under the handoff cover Esc does nothing.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or handoff.visible:
		return
	var top := _top_overlay()
	if top != null and top in [quit_overlay, report_overlay, menu_overlay, save_overlay]:
		top.visible = false
		if is_inside_tree():
			get_viewport().set_input_as_handled()
	elif top == null and session != null:
		open_menu()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


# --- the real screens (#7, #8) ----------------------------------------------------------------------

## The battle report viewer on top of the turn report, coloured by seat.
func _show_battle_report(event: Dictionary) -> void:
	_bind()
	var state: GameState = session.state() if session else null
	var seats: Array = session.players() if session else []
	battle_viewer.show_event(event, state, seats)
	_raise(battle_viewer)


## The victory screen over the final map.
func _show_victory(_victory: Dictionary) -> void:
	_bind()
	show_results()


func _show_setup_errors(errors: Array) -> void:
	map.visible = false
	error_title.text = "This game could not start"
	error_label.text = " ".join(PackedStringArray(errors))
	_raise(error_overlay)
	_update_hud()


# --- HUD ------------------------------------------------------------------------------------------

func _update_hud() -> void:
	if research_hud:
		research_hud.refresh()  # M4-4: the chip, and the research panel follows the seat
	var watching := is_watching()
	var playing: bool = session != null and session.phase() == GameSession.Phase.ORDERS and not watching
	var n: int = session.current_orders().size() if playing else 0
	end_turn_button.disabled = not (playing or watching)
	end_turn_button.text = "End turn (%s)" % _count(n, "order") if playing else "End turn"
	end_turn_button.tooltip_text = _end_turn_tooltip(n)
	if watching:
		end_turn_button.text = "Next turn"
		end_turn_button.tooltip_text = TooltipText.plain("Next turn", "Each computer gives its orders from the map as it stands now, without seeing the other's, and the turn resolves. The turn report then shows what happened and what each computer was thinking.")
	opponent_box.visible = opponent_box.get_child_count() > 0 and session != null and not session.is_over() \
		and session.phase() != GameSession.Phase.INVALID
	var has_report: bool = session != null and session.turn_report().turn > 0
	report_button.disabled = not has_report
	var report_help := "Read again what happened last turn. Click a line to see it on the map."
	if not has_report:
		report_help = "Nothing has happened yet. The report of each turn appears here once every player has ended the turn."
	report_button.tooltip_text = TooltipText.plain("Turn report", report_help)
	results_button.visible = session != null and session.is_over()
	ruler_button.visible = session != null and map.state != null and RulerRules.has_rulers(map.state) \
		and session.phase() != GameSession.Phase.INVALID
	if session == null or map.state == null or session.phase() == GameSession.Phase.INVALID:
		return
	map.turn_label.text = "Turn %d" % session.turn_number()
	map.turn_label.tooltip_text = _turn_tooltip()
	CodexLink.attach(map.turn_label, TooltipText.codex_for("turn"), open_codex)
	# The hint wraps to at most two lines at 1600 px (tests/test_top_bar.gd); the tooltip says the rest.
	if watching:
		map.set_hint("Watching the computer play both sides. Press Next turn to play a turn.",
			TooltipText.plain("Watching", "Nobody but the computer plays in this game. Next turn plays one turn; the turn report shows what each computer was thinking. Hover any number to see where it comes from."))
	elif playing and session.human_seats() == 1:
		# Against the computer the seat count means nothing to the player, and the opponent tag needs the room.
		map.set_hint("Move: select an army, then a neighbor. Recruit: select your capital.", _orders_help())
	elif playing:
		map.set_hint("Player %d of %d: select an army, then click a neighboring province to move it. Select your capital to recruit." % [
			session.current_seat(), session.players().size()], _orders_help())
	elif session.is_over():
		map.set_hint("The game is over. Results shows the summary; Turn report shows the last turn.",
			TooltipText.plain("Game over", "Results shows who won and the game in numbers. Turn report shows how the last turn went. The map shows the final positions; hover any number to see where it comes from."))


## The top bar hint's tooltip during orders: the whole how-to, which doesn't fit in the bar.
func _orders_help() -> String:
	var how := "Select one of your armies, then click a neighboring province to move it there; hover a province first to see the forecast and battle odds. Select your capital to recruit. Each order is listed in the side panel, where you can cancel it. Hover any number to see where it comes from; right-click it, or press F1, to open its codex entry. End turn when you are done."
	if session.human_seats() == 1 and not session.computer_seats().is_empty():
		return TooltipText.plain("You give orders as %s" % session.current_player_name(), how)
	return TooltipText.plain("Player %d of %d: %s gives orders" % [session.current_seat(), session.players().size(), session.current_player_name()], how)


## "the computer (Thornmane Clans, Normal)" for every computer seat but the current one, joined.
func _computer_names() -> String:
	var names := []
	var state := map.state if map.state else session.state()
	for fid in session.players():
		if session.is_computer(fid) and fid != session.current_player():
			var f := state.find_faction(fid)
			names.append("the computer (%s, %s)" % [f.faction_name if f else "an unknown faction", AISeat.level_name(session.computer_level(fid))])
	return " and ".join(names)


func _end_turn_tooltip(n: int) -> String:
	if session == null or session.phase() != GameSession.Phase.ORDERS:
		var idle := "The game is over, so there are no more turns." if session and session.is_over() else "Nobody is giving orders right now."
		return TooltipText.plain("End turn", idle)
	var seat := session.current_seat()
	var players := session.players()
	var text := "End your turn with %s queued. " % _count(n, "order")
	if session.human_seats() == 1 and not session.computer_seats().is_empty():
		var names := _computer_names()
		text += "%s%s gives its orders from the map as it stood at the start of this turn, never seeing yours, and all orders resolve together as soon as you end your turn. Then the turn report shows what happened." % [
			names.left(1).to_upper(), names.substr(1)]
		return TooltipText.plain("End turn", text)
	if seat < players.size():
		var next: Faction = map.state.find_faction(players[seat]) if map.state else null
		text += "The screen is then covered so you can pass the computer to player %d (%s), whose orders stay hidden from you. Nothing happens until the last player ends their turn." % [
			seat + 1, next.faction_name if next else "the next player"]
	else:
		text += "You are the last player this turn, so everyone's orders resolve together as soon as you end it."
	return TooltipText.plain("End turn", text)


## The session's 1-based turn, with the game seed so the game can be replayed.
func _turn_tooltip() -> String:
	var state := map.state
	# The seed opens its own paragraph so the wrapping never splits it.
	var seed_text := "\n\n" + TooltipText.wrap_text("Game seed %d. Start a game with the same players and this seed, give the same orders, and every turn and battle plays out the same." % config.seed)
	if session.is_over():
		return TooltipText.plain("Turn %d" % session.turn_number(), "The game ended on turn %d." % session.turn_number()) + seed_text
	var who := "Player %d of %d is giving orders. %s" % [session.current_seat(), session.players().size(), RulesCodex.text("hotseat")]
	if not session.computer_seats().is_empty():
		who = "Every seat gives its orders for this turn from the same start-of-turn map, and nobody sees anyone else's. %s" % RulesCodex.text("phase_order")
	var b := {"title": "Turn %d" % session.turn_number(),
		"description": who,
		"lines": [{"label": "Turns resolved so far", "value": state.current_turn, "note": ""},
			{"label": "This turn", "value": session.turn_number() - state.current_turn, "note": "the turn being ordered now"}],
		"total_label": "Turn being played", "total": session.turn_number()}
	return TooltipText.from_breakdown(b) + seed_text


## "no orders", "1 order", "3 orders".
static func _count(n: int, noun: String) -> String:
	return "no %ss" % noun if n == 0 else TooltipText.count(n, noun)


# --- building the screen --------------------------------------------------------------------------

## Finds the scene's nodes, builds the HUD and overlays and wires their signals, once.
func _bind() -> void:
	if _bound:
		return
	_bound = true
	map = $Map
	overlays = $Overlays
	handoff = $HandoffLayer/Handoff
	handoff.acknowledged.connect(_on_handoff_acknowledged)
	map.intercept_back = true
	map.back_requested.connect(open_menu)
	map.orders_changed.connect(_update_hud)
	map.codex_requested.connect(open_codex)
	_build_hud()
	_build_overlays()


func _build_hud() -> void:
	results_button = _hud_button("ResultsButton", "Results", show_results)
	results_button.tooltip_text = TooltipText.plain("Results", "The game is over: see who won, the turns played, the battles and the provinces each side held.")
	results_button.add_theme_color_override("font_color", UiPalette.GILT)
	results_button.visible = false
	map.add_top_bar_control(results_button)
	ruler_button = _hud_button("RulerButton", "Ruler", open_ruler_panel)
	ruler_button.tooltip_text = TooltipText.plain("Ruler", "Your ruler and the enemy ruler, every number explained, with the mandates each side has and how succession works. Builds are public. Your living ruler can sacrifice power for a new mandate here.")
	ruler_button.visible = false
	CodexLink.attach(ruler_button, "ruler", open_codex)
	map.add_top_bar_control(ruler_button)
	report_button = _hud_button("TurnReportButton", "Turn report", open_turn_report)
	map.add_top_bar_control(report_button)
	codex_button = _hud_button("CodexButton", "Codex", open_codex.bind(""))
	codex_button.tooltip_text = TooltipText.plain("Codex", "Every rule of the game in plain language, searchable. Right-click a number, or hover it and press F1, to open the codex at the rule behind it.")
	map.add_top_bar_control(codex_button)
	end_turn_button = _hud_button("EndTurnButton", "End turn", end_turn)
	end_turn_button.custom_minimum_size = Vector2(210, 0)
	end_turn_button.add_theme_font_size_override("font_size", 18)
	end_turn_button.add_theme_color_override("font_color", UiPalette.GILT)
	map.add_top_bar_control(end_turn_button)
	map.back_button.text = "Menu"
	map.back_button.tooltip_text = TooltipText.plain("Menu",
		"Save the game, load another, change the settings or quit to the title screen (Esc). The game also saves itself at the start of every turn.")
	# The computer seats sit right after the player's own name, in its group (#35); filled per game.
	opponent_box = HBoxContainer.new()
	opponent_box.name = "OpponentTag"
	opponent_box.add_theme_constant_override("separation", 5)
	opponent_box.visible = false
	map.faction_label.get_parent().add_child(opponent_box)
	research_hud = ResearchHud.new(self)  # M4-4: the research chip (paths games only)


## The top bar's opponent tag: every computer seat as "vs", its emblem and its name, with the
## "Computer (Normal)" chip under them: two compact lines, so the hint keeps its room. Empty in a
## hotseat game.
func _build_opponent_tag() -> void:
	for c in opponent_box.get_children():
		opponent_box.remove_child(c)
		c.queue_free()
	opponent_box.visible = false
	if session == null or session.phase() == GameSession.Phase.INVALID:
		return
	var state := session.state()
	var players := session.players()
	for i in players.size():
		var fid := String(players[i])
		if not session.is_computer(fid):
			continue
		var stack := VBoxContainer.new()
		stack.name = "Seat%d" % (i + 1)
		stack.add_theme_constant_override("separation", 1)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		opponent_box.add_child(stack)
		var line := HBoxContainer.new()
		line.name = "Line"
		line.add_theme_constant_override("separation", 4)
		stack.add_child(line)
		if opponent_box.get_child_count() > 1 or session.human_seats() > 0:
			var vs := Label.new()
			vs.name = "Versus"
			vs.text = "vs"
			vs.custom_minimum_size = Vector2(24, 0)
			vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vs.add_theme_font_size_override("font_size", 14)
			vs.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
			line.add_child(vs)
		var emblem := SeatEmblem.new(i, SeatEmblem.Look.TOKEN, 16.0)
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(emblem)
		var f := state.find_faction(fid)
		var faction_name := f.faction_name if f else "An unknown faction"
		var name_label := Label.new()
		name_label.name = "OpponentName"
		name_label.text = faction_name
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", UiPalette.seat_color(i).lightened(0.3))
		name_label.tooltip_text = TooltipText.plain("%s is played by the computer" % faction_name, AISeat.tag_help(faction_name, session.computer_level(fid)))
		CodexLink.attach(name_label, "computer_opponent", open_codex)
		line.add_child(name_label)
		var tag := VictoryScreen.computer_tag(faction_name, session.computer_level(fid), open_codex)
		tag.add_theme_font_size_override("font_size", 11)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_END
		(tag.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_top = 0
		(tag.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_bottom = 1
		stack.add_child(tag)


func _hud_button(node_name: String, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func(): action.call())
	return b


func _build_overlays() -> void:
	# Bottom to top when nothing has been raised yet: victory screen, turn report, battle report,
	# codex, setup errors, quit confirmation.
	victory_screen = VictoryScreen.new()
	victory_screen.new_game_requested.connect(_go_to_new_game)
	victory_screen.title_requested.connect(_go_to_title)
	victory_screen.codex_requested.connect(open_codex)
	victory_screen.add_action("FinalReportButton", "Final turn report",
		"Read the report of the last turn, which ended the game.").pressed.connect(open_turn_report)
	victory_screen.add_action("ViewMapButton", "View the map",
		"Close this and look at the final map. Results in the top bar brings this back.").pressed.connect(
			func(): victory_screen.visible = false)
	overlays.add_child(victory_screen)

	report_overlay = _report_overlay()

	battle_viewer = BattleReportViewer.new()
	battle_viewer.codex_requested.connect(open_codex)
	overlays.add_child(battle_viewer)

	codex = load(CODEX_SCENE).instantiate()
	codex.name = "Codex"
	codex.visible = false
	# The codex panel's default background lets the map show through its text; use the opaque panel.
	var codex_bg := codex.get_node_or_null("Background") as PanelContainer
	if codex_bg:
		codex_bg.add_theme_stylebox_override("panel", UiPalette.panel_style())
	overlays.add_child(codex)

	var e := _overlay("SetupErrors", Vector2(820, 0), 0.55)
	error_overlay = e[0]
	error_title = _label("ErrorTitle", 40, UiPalette.GILT)
	e[1].add_child(error_title)
	error_label = _label("ErrorText", 22, UiPalette.TEXT_PRIMARY)
	e[1].add_child(error_label)
	_overlay_button(_button_row(e[1]), "ErrorTitleButton", "Back to title", _go_to_title, "Go back to the title screen.")

	var q := _overlay("QuitConfirm", Vector2(640, 0))
	quit_overlay = q[0]
	var qtitle := _label("QuitTitle", 30, UiPalette.GILT)
	qtitle.text = "Quit to the title screen?"
	q[1].add_child(qtitle)
	quit_text = _label("QuitText", 20, UiPalette.TEXT_PRIMARY)
	quit_text.text = "This turn has not been saved."
	q[1].add_child(quit_text)
	var qrow := _button_row(q[1])
	_overlay_button(qrow, "KeepPlayingButton", "Keep playing", func(): quit_overlay.visible = false, "Go back to the game.")
	_overlay_button(qrow, "ConfirmQuitButton", "Quit to title", _go_to_title, "Leave this game for the title screen. Continue on the title screen brings back the latest save.")

	_build_menu()
	_build_save_dialog()

	load_screen = LoadScreen.new()
	load_screen.load_requested.connect(_on_load_requested)
	overlays.add_child(load_screen)

	settings_panel = SettingsPanel.new()
	overlays.add_child(settings_panel)

	_build_notice()


## Menu: Resume, Save game, Load game, Settings, Quit to title.
func _build_menu() -> void:
	var m := _overlay("GameMenu", Vector2(460, 0))
	menu_overlay = m[0]
	var title := _label("MenuTitle", 34, UiPalette.GILT)
	title.text = "Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m[1].add_child(title)
	menu_text = _label("MenuText", 17, UiPalette.TEXT_SECONDARY)
	menu_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m[1].add_child(menu_text)
	_menu_button(m[1], "ResumeButton", "Resume", close_menu, "Back to the game (Esc).")
	menu_save_button = _menu_button(m[1], "SaveGameButton", "Save game", open_save_dialog, "")
	_menu_button(m[1], "LoadGameButton", "Load game", open_load_screen, "Play on from a saved game instead of this one.")
	_menu_button(m[1], "SettingsButton", "Settings", open_settings, "Window or fullscreen, and how big the interface is drawn.")
	_menu_button(m[1], "QuitToTitleButton", "Quit to title", _on_quit_requested, "Leave this game for the title screen. You are asked to confirm first.")


func _menu_button(box: VBoxContainer, node_name: String, text: String, action: Callable, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func(): action.call())
	box.add_child(b)
	return b


## The save dialog: a name (empty keeps the timestamped default), what is saved, Cancel and Save.
func _build_save_dialog() -> void:
	var d := _overlay("SaveDialog", Vector2(640, 0))
	save_overlay = d[0]
	var title := _label("SaveTitle", 32, UiPalette.GILT)
	title.text = "Save game"
	d[1].add_child(title)
	save_name_edit = LineEdit.new()
	save_name_edit.name = "SaveNameEdit"
	save_name_edit.custom_minimum_size = Vector2(0, 46)
	save_name_edit.add_theme_font_size_override("font_size", 20)
	save_name_edit.max_length = 60
	save_name_edit.tooltip_text = "Name this save, or leave it empty to name it after the date and time."
	save_name_edit.text_submitted.connect(func(_t: String): confirm_save())
	d[1].add_child(save_name_edit)
	save_note = _label("SaveNote", 17, UiPalette.TEXT_SECONDARY)
	d[1].add_child(save_note)
	save_error = _label("SaveError", 18, UiPalette.NEGATIVE)
	save_error.visible = false
	d[1].add_child(save_error)
	var row := _button_row(d[1])
	_overlay_button(row, "CancelSaveButton", "Cancel", func(): save_overlay.visible = false, "Don't save.")
	_overlay_button(row, "ConfirmSaveButton", "Save", func(): confirm_save(), "Save the game under this name.")


## The NoticeLayer's notice: a title, a line and OK, under the top bar.
func _build_notice() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NoticeLayer"
	layer.layer = 15
	add_child(layer)
	notice_panel = PanelContainer.new()
	notice_panel.name = "Notice"
	notice_panel.visible = false
	notice_panel.anchor_left = 0.5
	notice_panel.anchor_right = 0.5
	notice_panel.offset_left = -400
	notice_panel.offset_right = 400
	notice_panel.offset_top = 84
	notice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := UiPalette.panel_style(16)
	style.border_color = UiPalette.GILT
	notice_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(notice_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	notice_panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	notice_title = _label("NoticeTitle", 20, UiPalette.GILT)
	text.add_child(notice_title)
	notice_label = _label("NoticeText", 17, UiPalette.TEXT_PRIMARY)
	text.add_child(notice_label)
	var ok := Button.new()
	ok.name = "NoticeOkButton"
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(80, 40)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.add_theme_font_size_override("font_size", 18)
	ok.tooltip_text = "Hide this notice."
	ok.pressed.connect(func(): notice_panel.visible = false)
	row.add_child(ok)


## The turn report panel in a modal frame with a footer: a hint and a Close button.
func _report_overlay() -> Control:
	var overlay := _overlay_base("ReportOverlay", 0.45)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(1040, 760)
	box.add_theme_constant_override("separation", 0)
	center.add_child(box)
	report_panel = TurnReportPanel.new()
	report_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_panel.province_focus_requested.connect(_on_report_focus)
	report_panel.battle_report_requested.connect(func(e: Dictionary): _show_battle_report(e))
	report_panel.codex_requested.connect(open_codex)
	box.add_child(report_panel)
	var footer := PanelContainer.new()
	footer.name = "Footer"
	var style := StyleBoxFlat.new()
	style.bg_color = TurnReportPanel.BACKGROUND  # matches the report panel, opaque
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_top = 1
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 16
	footer.add_theme_stylebox_override("panel", style)
	box.add_child(footer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	footer.add_child(row)
	var hint := _label("ReportHint", 16, UiPalette.TEXT_SECONDARY)
	hint.text = "Click a line to see it on the map. Battles have a full report, and ? explains the rule behind a line. Reopen this from Turn report in the top bar."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(hint)
	var close := Button.new()
	close.name = "CloseReportButton"
	close.text = "Close"
	close.custom_minimum_size = Vector2(140, 44)
	close.add_theme_font_size_override("font_size", 20)
	close.tooltip_text = "Close the report and give your orders."
	close.pressed.connect(close_turn_report)
	row.add_child(close)
	return overlay


## A hidden full-screen overlay: a dim backdrop that swallows clicks.
func _overlay_base(node_name: String, dim_alpha: float) -> Control:
	var overlay := Control.new()
	overlay.name = node_name
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, dim_alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	overlays.add_child(overlay)
	return overlay


## An overlay with a centred panel. Returns [overlay, the panel's VBoxContainer].
func _overlay(node_name: String, panel_size: Vector2, dim_alpha: float = 0.6) -> Array:
	var overlay := _overlay_base(node_name, dim_alpha)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = panel_size
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(28))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return [overlay, box]


func _button_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	return row


func _overlay_button(row: HBoxContainer, node_name: String, text: String, action: Callable, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func(): action.call())
	row.add_child(b)
	return b


func _label(node_name: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
