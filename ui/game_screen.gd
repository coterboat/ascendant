class_name GameScreen
extends Control
## The one main screen of a hotseat game (#6, #7, #8). It hosts the MapScreen for the player at the
## controls and fills the Table over it (UX-1, #194; design/UX_WAR_TABLE.md §1): the system row's Research, Magic, Ruler,
## Chronicle, Turn report, Lenses, Codex and ? buttons, the opponent plaque and Menu, the End turn seal (Results takes its place
## at the end of a game). On top of the map it shows the turn report at the start of each player's turn, the battle report
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
##   NoticeLayer (CanvasLayer 15): a small notice under the realm plaque ("Game saved", "Game loaded"). It
##             never blocks the map, and it sits under the handoff cover.
##   HandoffLayer (CanvasLayer 20): the handoff cover, above everything, so nothing leaks between players.
##
## Saving (SaveGame, SaveStore): the game saves itself at the start of every turn, once the last turn
## has resolved and before any computer seat plans the new one (and at the start of turn 1); the store
## keeps the last three autosaves. Menu (top right, or Esc) has Save game (name it, or keep the
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
## each turn, before the human, from the same start-of-turn state. The opponent plaque (top right) names the computer
## faction with its "Computer (Normal)" tag. Two humans play exactly as before. With no human seat at
## all (watch mode), End turn becomes Next turn and plays one whole turn per press.
##
## Sound (GameAudio, through its static shortcuts; it never sees the session): the map theme and the map
## bed while a game runs, end_turn on End turn, turn_start on the handoff cover and when a new turn
## starts for the only human, the turn report's headline cues (GameAudio.report_cues) as each new report
## opens, battle music and bed over the ducked map theme while the battle report viewer is open, and the
## victory or defeat sting with the victory screen (GameAudio.ending_sting). Buttons click by themselves.
##
## API:
##   start_game(config)   config = {"players": [faction ids in seat order], "seed": int, "ai": {faction id:
##                        level}}. "ai" is optional (absent: every seat is human). Missing keys get
##                        default_config() values: every faction in data order and a random seed.
##                        A system is in the game only when the config asks for it (MVP-2, #163: the new game screen and
##                        Quick start ask for all six, NewGameScreen.default_systems; a config without the keys is the
##                        basic game, byte for byte as before): "rulers": true, or "builds": {faction id: build or preset
##                        id}, "paths", "sieges", "magic", "fog", "independents", or the `-- --rulers` (and so on)
##                        command-line switches for playtests (starting_state()).
##                        If the screen enters the tree without start_game(), it starts a default game.
##   load_game(save)      plays on from a save (SaveGame): "" or why it can't be loaded, in plain words.
##                        Used by SceneFlow.make_loaded_game and by Menu > Load game (in place).
##   save_game(name)      Menu > Save game: a manual save. "" or why not. autosave() is the turn-start one.
##   open_menu()          the Menu button and Esc: Resume, Save game, Load game, Settings, Quit to title.
##   end_turn()           the End turn button: hands off to the next player, or resolves the turn. With
##                        computer seats, the computer then plays at once. In watch mode: next_turn().
##   next_turn()          watch mode only: both computers give their orders and the turn resolves.
##   open_turn_report()   the Turn report button: the last resolved turn's report, through the ReportHost (the modal
##                        report until UX-6's Chronicle registers as the presenter).
##   open_controls_help() the ? button: every key and mouse binding (ControlsHelp).
##   report_host          the report seam (UX-1): turn resolved, report ready, opened, closed (ReportHost).
##   watch_battles(events, start = 0) -> String   M3-5: plays battle events (report order) in the battle
##                        host, from events[start]; "" or why not (no game, behind the handoff cover).
##   watch_battle(event) -> String   M3-5: one battle, with the report's other battles as its queue.
##   open_codex(key)      the Codex button, a report's "?", a right-click on a linked number.
##   show_results()       the Results button once the game is over: the victory screen again.
##   open_ruler_panel()   the Ruler button (M2-6, games with rulers only): the map's ruler panel.
##   seal_nudging()       true while the End turn seal pulses: a new player (fewer than two turns ended in this
##                        installation) with an order queued.
## Esc (and a right-click on empty board) go through the map's one dispatcher, map.ui_cancel (UiCancel, §1.4); this screen
## registers its overlays as the "modal" layer and the menu as the last step.
##   session              the GameSession being played. Read it; act through the API above.
##   computer             the AISeat playing the computer seats (it has none in a hotseat game).
##   save_store           where saves go (SaveStore, user://saves unless set before the game starts).
##   next_scene           the screen this one switched to (SceneFlow), e.g. the title after "New game".
##
## Forts and sieges (M3c S-3, #101): `chronicle` (SiegeChronicle) keeps what the game has seen from each resolved
## turn's report (and is rebuilt from the record when a game loads): the turn report's first-siege sentences,
## once per player, and the victory screen's forts built, sieges won and storms.
##
## The 3D board (M3a.1): with Settings "Board: 3D world" (the default), the map is drawn as the 3D world
## (Board3D, world3d/board3d.gd) once this screen is in the tree; "2D map" keeps the 2D board. After a
## turn resolves, its moves, battles and captures play out on the board (from the start-of-turn state
## and the report's events) before the turn report opens. The board stops rendering while the handoff
## cover or a modal overlay covers it. use_board("3d" / "2d") switches it (tests and tools).
## M3a.2: the turn's start is kept with its report (_replay), so every hotseat seat sees the playback
## behind its own handoff, and the report's "Watch this turn again" (watch_turn_again) plays it once more.
##
## Watching battles (M3-5, #60): one BattleHost on the Overlays layer plays every battle playback. The turn
## report's Watch buttons and "Watch your battles (N)", and the battle report viewer's Watch, open it
## (watch_battle(event), watch_battles(events, start)); its Full report opens the viewer over it. With
## Settings "Watch my battles at the start of each turn" on, the player's battles start by themselves once
## the turn's board playback has finished and the report has opened, after any handoff, once per player and
## turn (never in watch mode, or for a loaded game's last turn). Nothing is watched behind the handoff cover,
## and a handoff closes the battle screen. The viewer's side gets the victory or defeat sting (watch_viewer).
##
## Fog of war (M5-2, #113; design/M5_MAGIC_FOG.md §2.1, §2.8, §2.9, §12.1): every screen reads the session through
## viewer() and the per-viewer accessors (state_for, turn_report_for, view_before, memory, intel): the map, its panels and
## tooltips, the Table, the turn report (with its fog header and "what you didn't see"), the battle screens (only
## battles you fought), the board's playback (from view_before, through your own report) and the report's sound. The
## truth is read only on the observer paths: viewer() picks the observer in watch mode and once the game is over (the
## fog lifts), the victory screen, saving and loading, and rebuilding the log of a battle you fought (tests/test_fog_ui.gd
## scans for it). In a hotseat fog game the cover adds its fog line, Ready rebuilds the next seat's screen and clears
## the board's kept frame before the cover lifts (handoff_log records it), and the playback is silent but for the
## ambient bed, because the other player is in the room. The computer's notes name its hidden armies, so under fog they
## wait until the game is over. With fog off every accessor is the truth and nothing here changes.

const SCENE := "res://ui/game_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"
## Sound timing: turn_start lands just after End turn's sound, the report's cues after turn_start.
const TURN_START_DELAY := 0.45
const REPORT_CUE_DELAY := 1.1
## M3-5: the z_index of an overlay opened over the battle screen (above its result card and legend).
const OVER_BATTLE_Z := BattleHost.OVER_Z
## MVP-3 (#177): how dark the turn report's backdrop is (it was 0.45, which left the card's text half readable).
const REPORT_DIM := 0.82
## The Ruler button's help (without fog).
const RULER_HELP := "Your ruler and the enemy ruler, every number explained, with the mandates each side has and how succession works. Builds are public. Your living ruler can sacrifice power for a new mandate here."

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
var end_turn_button: Button  # the seal: "End turn" and the order count
var report_button: Button  # the system row's Turn report, until UX-6's Chronicle
var codex_button: Button
var help_button: Button  # the system row's ?: every key and mouse binding
var chronicle_button: Button  # a placeholder for UX-6: the Chronicle
var lenses_button: Button  # the system row's Lenses (UX-7): its picker of the six map lenses (MapScreen.lens_ui)
var results_button: Button  # only once the game is over: it takes the seal's place
var ruler_button: Button  # M2-6: opens the ruler panel; only in a game with rulers
var research_hud: ResearchHud  # M4-4: the research chip, the research panel and the lock-in preview
var first_game_guide: FirstGameGuide  # MVP-1 (#141): the card with the first turn's three steps (turn 1 of a first game)
var report_overlay: Control
var report_panel: TurnReportPanel
var battle_viewer: BattleReportViewer
var battle_host: BattleHost  # M3-5: every battle playback
var codex: CodexPanel
var victory_screen: VictoryScreen
var error_overlay: Control
var error_title: Label
var error_label: Label
var quit_overlay: Control
var opponent_box: HBoxContainer  # the opponent plaque (top right): each rival with its banner, name and tag (#35)
var report_host := ReportHost.new()  # UX-1: the report lifecycle seam; this screen's modal report is its default presenter
var help_overlay: Control  # the ? panel: every key and mouse binding
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
var notice_ok: Button
var _report_seen := 0  # the last turn report shown to the only human, so each one opens once
var _snapshot := {}  # SaveGame.computer_snapshot from the start of the turn being played
var _turn_start_turns := -1  # session.turns_played() when the current turn started (and was autosaved)
var _last_autosave_turn := 0  # the turn the last autosave was made at the start of (0: none)
var _audio_turn := 0  # the turn turn_start last sounded for
var _battle_audio := false  # the battle report viewer's music is on
var _bound := false
var _opponents_key := ""  # the viewer and turn the opponent plaque was built for
var _turn_from := -1  # M3a.1: current_turn when the turn being resolved started (M5-2: its state is view_before)
var _played_for := {}  # M3a.1: faction id -> the report turn already played out on the board for them
var _replay := {}  # M3a.2: {"turn"}: the last resolved turn, played for every seat and by "Watch this turn again"
## M5-2: one entry per handoff, {"seat", "faction", "covered", "frame_cleared"}: the next seat's screen was rebuilt, and
## the board's kept frame cleared, while the cover was still up (§2.9).
var handoff_log: Array = []
## M5-2: every "what you didn't see" of the game so far ([{"turn", "faction", "text"}]), for the victory screen; from
## turn _fog_missed_from on (a loaded game replays the earlier turns when the game ends).
var fog_missed: Array = []
var _fog_missed_from := 1
var _fog_missed_turns := {}
var _fog_hint_up := false  # M5-2: the notice shows the first fog turn's hint (its button says Got it)
var _auto_watched := {}  # M3-5: faction id -> the report turn whose battles auto-watch already played for them
var chronicle := SiegeChronicle.new()  # M3c S-3: the first-siege sentences and the victory screen's siege numbers


func _ready() -> void:
	_bind()
	if session == null:
		start_game(default_config())
	_apply_board_setting()


## Every faction in data order, and a random seed: the basic game, with no system. It is what a game screen shown with no
## game starts (the editor's Run Current Scene, tests); a player's defaults live in the new game screen and Quick start.
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
	_start_audio()
	loaded_header = {}
	_turn_from = -1
	_played_for = {}
	fog_missed = []
	_fog_missed_from = 1
	_fog_missed_turns = {}
	_auto_watched = {}
	chronicle = SiegeChronicle.new()
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
	_turn_from = -1
	_played_for = {}
	_start_audio()
	config = restored.config
	loaded_header = restored.header
	session = restored.session
	computer = restored.computer
	chronicle = SiegeChronicle.rebuild(session.record(), AutoBattleResolver.new())  # M3c S-3: empty without sieges
	map.session = session
	_build_opponent_tag()
	# M3-5: a loaded game doesn't auto-watch the battles of the turn it was saved after.
	_auto_watched = {}
	for fid in session.players():
		_auto_watched[String(fid)] = _report_turn()
	fog_missed = []
	_fog_missed_from = session.turns_played() + 1
	_fog_missed_turns = {}
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
	_sync_chronicle()
	if _turn_start_turns > 0:
		report_host.notify_resolved(_turn_start_turns)  # UX-1: the report seam hears that a turn resolved
	if autosave_enabled and not session.is_over():
		var why := autosave()
		if not why.is_empty():
			show_notice("Autosave failed", why)


## M3c S-3: the chronicle counts the turn that just resolved (each turn once). An observer path (the victory screen's
## numbers): it reads the whole report; what a player is taught comes from their own report (TurnReportPanel).
## M5-2: in a fog game it also keeps each player's "what you didn't see" of the turn, for the victory screen.
func _sync_chronicle() -> void:
	if session != null and session.turn_report().turn > 0:
		var report := session.turn_report()
		chronicle.add_turn(int(report.turn), report.events)
		if session.state().fog and not _fog_missed_turns.has(int(report.turn)) and int(report.turn) >= _fog_missed_from:
			_fog_missed_turns[int(report.turn)] = true
			fog_missed.append_array(FogView.missed_of_turn(session))


## A game starts or loads: the map theme and the map bed (crossfading from whatever played before).
func _start_audio() -> void:
	_audio_turn = 0
	GameAudio.music("music_map")
	GameAudio.ambiance("amb_map")


## turn_start, once per turn for the player at the controls (the handoff cover sounds it in a hotseat
## game). True when it sounded.
func _cue_turn_start() -> bool:
	if session.turn_number() == _audio_turn:
		return false
	_audio_turn = session.turn_number()
	GameAudio.sfx("turn_start", TURN_START_DELAY)
	return true


## The headline cues of the report that just opened (GameAudio.report_cues), from `delay_s`: the viewer's own report.
## M5-2: none in a hotseat fog game, where the other player is in the room (§2.9).
func _cue_report(delay_s: float) -> void:
	if _hotseat_fog():
		return
	GameAudio.report(_report().get("events", []), delay_s)


## The starting state for `game_config`: the M1 game, or with rulers when the config asks for them
## ("rulers": true, or "builds") or the game was launched with `-- --rulers`; with paths (M4-1) when it has
## "paths": true or the game was launched with `-- --paths`; with forts and sieges (M3c) when it has "sieges": true or
## the game was launched with `-- --sieges`; with magic (M5-5, paths and rulers included) when it has "magic": true or
## the game was launched with `-- --magic`; and with fog of war (M5-1) on top of any of these when it has "fog": true
## or the game was launched with `-- --fog`. Factions without a
## build get their balanced preset. Null when a build is illegal (the session then explains).
static func starting_state(game_config: Dictionary) -> GameState:
	var state := _starting_state(game_config)
	if state != null and (game_config.get("independents", false) or OS.get_cmdline_user_args().has("--independents")):
		state.setup_independents([])  # IND-1 (#142): Free Holds garrisons in every neutral province
	if state != null and (game_config.get("fog", false) or OS.get_cmdline_user_args().has("--fog")):
		state.setup_fog([])  # M5-1: fog is a lens on whichever game the other boxes make
	return state


static func _starting_state(game_config: Dictionary) -> GameState:
	var seed_value := int(game_config.get("seed", 0))
	var args := OS.get_cmdline_user_args()
	if game_config.get("magic", false) or args.has("--magic"):
		# M5-5 (#116): magic needs paths (GameState.with_magic), and works with forts and sieges too.
		var state := GameState.with_magic(seed_value, game_config.get("builds", {}), [])
		if state != null and (game_config.get("sieges", false) or args.has("--sieges")):
			state.setup_sieges([])
		return state
	if game_config.get("sieges", false) or args.has("--sieges"):
		# M3c S-1a (#98): forts and sieges, with or without rulers and paths (GameState.with_sieges).
		var paths: bool = game_config.get("paths", false) or args.has("--paths")
		var rulers: bool = paths or game_config.get("rulers", false) or game_config.has("builds") or args.has("--rulers")
		return GameState.with_sieges(seed_value, game_config.get("builds", {}), {"rulers": rulers, "paths": paths}, [])
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
	_turn_from = session.turn_number() - 1  # M3a.1: the board plays the turn from its start if this End turn resolves it
	var why := session.end_turn()
	if not why.is_empty():
		map.set_hint(why)
		return why
	GameAudio.sfx("end_turn")
	_note_turn_ended()
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
	_turn_from = session.turn_number() - 1
	GameAudio.sfx("end_turn")
	computer.play(session)
	_check_turn_start()
	if session.is_over():
		_show_game_over()
		return ""
	_show_watch()
	_open_report_when_played(TURN_START_DELAY)
	return ""


## True while nobody but the computer plays (watch mode) and the game is running.
func is_watching() -> bool:
	return session != null and session.human_seats() == 0 and session.is_computer_turn()


## Shows the last resolved turn's report on top. Does nothing before the first turn is resolved. UX-1: through the ReportHost,
## whose presenter is this screen's modal report until UX-6's Chronicle registers (the Turn report button, the victory screen's
## Final turn report and every call site come here).
func open_turn_report() -> void:
	_bind()
	report_host.open()


## The ReportHost's presenter (the modal report): opens the last resolved turn's report. True when it opened.
func open_report() -> bool:
	_bind()
	if session == null or _report_turn() == 0:
		return false
	# The computer's notes are those of the turn the report shows, which has resolved (AISeat.report_notes).
	_sync_chronicle()
	report_panel.chronicle = chronicle  # M3c S-3: the first-siege sentences
	report_panel.show_report(session, _computer_notes(), viewer())  # M5-2: the viewer's report
	_keep_replay()
	report_panel.set_watch_again(can_watch_again())
	_report_seen = maxi(_report_seen, _report_turn())
	_raise(report_overlay)
	report_host.notify_opened(_report_turn())
	return true


func close_report() -> void:
	_hide_report_overlay()


func is_report_open() -> bool:
	return report_overlay != null and report_overlay.visible


## The ReportHost's "the report is ready": the modal opens at once, sounds its headline cues and starts the battles the person
## fought when Settings ask (UX-6's Chronicle decides for itself what ready means: a medallion, an auto-open for a battle).
func on_report_ready(_turn: int, context: Dictionary) -> void:
	open_report()
	_cue_report(float(context.get("cue_delay", 0.2)))
	auto_watch()


## Hides the modal report (and tells the report host it closed, once).
func _hide_report_overlay() -> void:
	if report_overlay != null and report_overlay.visible:
		report_overlay.visible = false
		report_host.notify_closed(_report_turn())


## The computer's notes for the report (AISeat.report_notes). M5-2: under fog they name its hidden armies and plans, so
## while a person is looking (the game isn't over) each computer seat shows only why they are hidden (§2.9).
func _computer_notes() -> Array:
	if computer == null:
		return []
	if map.state == null or not map.state.fog or session.is_over() or session.human_seats() == 0:
		return computer.report_notes(session)  # no fog, or nobody but the computer plays, or the fog has lifted
	var out := []
	var players := session.players()
	for fid in session.computer_seats():
		var f := map.state.find_faction(String(fid))
		out.append({"faction": fid, "faction_name": f.faction_name if f else "The computer", "seat": players.find(fid),
			"level": session.computer_level(String(fid)), "notes": [FogView.NOTES_HIDDEN], "hidden": true})
	return out


# --- whose eyes (M5-2, fog of war) ---------------------------------------------------------------------

## Whose eyes the screen shows (§2.1): the person at the controls (the seat giving orders in a hotseat game, the only
## person in a game against the computer), FogRules.OBSERVER when nobody in particular is looking (watch mode, and once
## the game is over: the fog lifts), and "" behind the handoff cover. The one place the screen picks the observer.
func viewer() -> String:
	if session == null or session.phase() == GameSession.Phase.INVALID:
		return ""
	if session.is_over() or session.human_seats() == 0:
		return FogRules.OBSERVER
	if session.human_seats() == 1:
		for fid in session.players():
			if not session.is_computer(String(fid)):
				return String(fid)
	if session.phase() == GameSession.Phase.ORDERS and not session.is_computer(session.current_player()):
		return session.current_player()
	return ""


## The last resolved turn's report as viewer() reads it (GameSession.turn_report_for).
func _report() -> Dictionary:
	return session.turn_report_for(viewer()) if session != null else {}


## The last resolved turn (0 before the first): the report's turn, which is public.
func _report_turn() -> int:
	return int(_report().get("turn", 0))


## Shows the game on the map as `faction_id` sees it ("" for nobody in particular: viewer()'s eyes, the observer in watch
## mode and at game over): its view, with what it remembers and knows and its view at the start of the last turn.
func _set_map_for(faction_id: String) -> void:
	var eyes := faction_id if not faction_id.is_empty() else viewer()
	var st := session.state_for(eyes)
	var fog := st != null and st.is_view
	map.set_fog(session.memory(eyes) if fog else {}, session.intel(eyes) if fog else {}, session.view_before(eyes) if fog else null)
	map.set_state(st, faction_id)


## A hotseat game with fog (§2.9): the playback and the report make no sound but the ambient bed.
func _hotseat_fog() -> bool:
	return session != null and session.human_seats() > 1 and map.state != null and map.state.fog


func close_turn_report() -> void:
	_bind()
	report_host.close()


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
	_sync_chronicle()
	victory_screen.siege_stats = chronicle.stats()  # M3c S-3: forts built, sieges won, storms
	victory_screen.fog_lift = _fog_lift_data()  # M5-2: the fog lifts
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
			var new_turn := _cue_turn_start()
			if session.human_seats() == 1 and _report_turn() > _report_seen:
				_open_report_when_played(REPORT_CUE_DELAY if new_turn else 0.2)
		GameSession.Phase.GAME_OVER:
			_show_game_over()

## The current player's ORDERS phase: their map (their view, in a fog game), their orders, their capital selected for
## recruiting. `play`: the last turn plays out on the board (false while the handoff cover is still up).
func _show_current_player(play: bool = true) -> void:
	var fid := session.current_player()
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	_set_map_for(fid)
	if play:
		_play_on_board(fid)
	var f := map.state.find_faction(fid)
	var capital: Province = map.state.find_province(f.capital) if f else null
	if capital and capital.owner == fid:
		map.select_province(capital.id)
	_fog_hint()
	_update_hud()


## M5-2 (§11.1): the first fog turn's one-line hint, until a player presses Got it (remembered in the settings). Only
## on the game's first turn, before any report: the notice sits above the overlays, and must never cover a report.
const FOG_HINT := "Fog of war is on. You see exactly where you own land or stand; next to that you glimpse armies roughly (two away from forts, commanders, rulers and scouts); beyond, only what you saw last."


func _fog_hint() -> void:
	if not FogView.active(map.state) or _report_turn() > 0 or GameSettings.hint_seen("fog"):
		return
	if first_game_guide != null:
		# MVP-3 (#177): one card at a time. The first-game guide has a fog line that says the same, and when it is up the
		# banner would stack beside it (covering the board hint and the research panel's tabs).
		first_game_guide.sync(session, map.state)
		if first_game_guide.explains_fog():
			return
	show_notice("Fog of war", FOG_HINT)
	_fog_hint_up = true
	notice_ok.text = "Got it"


## Watch mode: the map seen by nobody in particular, waiting for Next turn.
func _show_watch() -> void:
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	_set_map_for("")
	_play_on_board("")
	map.faction_label.text = "Watching"
	map.faction_label.tooltip_text = TooltipText.plain("Watching the computer play",
		"The computer plays every seat, so you only watch. Press Next turn to have each computer give its orders and resolve the turn. The turn report shows what each one was thinking.")
	CodexLink.attach(map.faction_label, "computer_opponent", open_codex)
	_update_hud()


## Covers everything and hides the map until the next player presses Ready.
func _show_handoff() -> void:
	battle_host.close()  # M3-5: nothing is watched behind the handoff cover
	map.clear_preview()
	map.visible = false
	handoff.fog = map.state != null and map.state.fog  # M5-2: the cover's fog line
	if handoff.show_for(session):
		_audio_turn = session.turn_number()
		GameAudio.sfx("turn_start", TURN_START_DELAY)
	_update_hud()


## M5-2 (§2.9): Ready was pressed and the cover is still up: the next seat's board, overlays and panels are rebuilt
## now, and the board's kept frame is cleared, so the first frame the next player sees is theirs.
func _rebuild_under_cover() -> void:
	_close_overlays()
	_show_current_player(false)
	var cleared := _clear_kept_frame()
	handoff_log.append({"seat": session.current_seat(), "faction": session.current_player(), "covered": handoff.visible,
		"frame_cleared": cleared and handoff.visible})


## The 3D board keeps the last frame it drew while it is covered (Board3D: its SubViewport stops updating). After a
## handoff that frame is the last seat's, so its viewport is told to clear and draw once more, from the new seat's
## board, before the cover lifts. The 2D map keeps no frame. True when done.
func _clear_kept_frame() -> bool:
	if map.board == null:
		return true
	for vp in map.board.find_children("*", "SubViewport", true, false):
		(vp as SubViewport).render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	map.board.queue_redraw()
	return true


## The cover is down (after _rebuild_under_cover): the last turn plays on the board, then the report opens.
func _on_handoff_acknowledged() -> void:
	_play_on_board(session.current_player())
	if _report_turn() > 0:
		_open_report_when_played(0.2)


## The final map, seen by nobody in particular, under the victory screen.
func _show_game_over() -> void:
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	_set_map_for("")  # the observer: the fog lifts
	var played := _play_on_board("")
	map.faction_label.text = "Game over"
	map.faction_label.tooltip_text = TooltipText.plain("Game over", "Nobody gives orders any more. The map shows the final positions.")
	CodexLink.attach(map.faction_label, TooltipText.codex_for("draw" if session.victory().get("draw", false) else "game_over"), open_codex)
	_update_hud()
	_battle_audio = false
	if played:
		## the last turn plays out on the board first, then the sting and the victory screen
		map.board.playback_finished.connect(func():
			GameAudio.music(GameAudio.ending_sting(session.victory(), session.players(), session.computer_seats()))
			_show_victory(session.victory()), CONNECT_ONE_SHOT)
	else:
		GameAudio.music(GameAudio.ending_sting(session.victory(), session.players(), session.computer_seats()))
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


## A small notice under the realm plaque that never blocks the map. OK hides it, and so does End turn.
func show_notice(title: String, text: String) -> void:
	_bind()
	notice_title.text = title
	notice_label.text = text
	notice_panel.visible = true
	_fog_hint_up = false
	notice_ok.text = "OK"


## The notice's button: OK hides it; on the first fog turn's hint it is Got it, and the hint never shows again.
func _on_notice_ok() -> void:
	notice_panel.visible = false
	if _fog_hint_up:
		_fog_hint_up = false
		GameSettings.mark_hint_seen("fog")


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
	_hide_report_overlay()
	battle_host.close()
	battle_viewer.visible = false
	_set_battle_audio(false)
	quit_overlay.visible = false
	menu_overlay.visible = false
	save_overlay.visible = false
	load_screen.visible = false
	settings_panel.visible = false
	help_overlay.visible = false
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
## M3-5: the battle screen draws its result card, why panel and legend with a raised z_index, so an
## overlay opened over it (the report viewer, the codex, the settings) is lifted above those
## (OVER_BATTLE_Z), and raising the battle screen again puts every overlay back level.
func _raise(overlay: Control) -> void:
	overlays.move_child(overlay, overlays.get_child_count() - 1)
	overlay.visible = true
	if overlay == battle_host:
		for c in overlays.get_children():
			if c is CanvasItem:
				(c as CanvasItem).z_index = 0
	elif battle_host != null:
		overlay.z_index = OVER_BATTLE_Z if battle_host.visible else 0


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


## Esc: the map's one dispatcher (UiCancel, §1.4) closes the topmost thing, one per press: a modal (the overlays here, the map's
## ruler panel and dialogs), march targeting, the Chronicle, the selection card, a lens, the board's close-up, and with
## nothing left it opens the menu. Panels with an Esc handler of their own (research, settings, the load screen, the battle
## screens) still close themselves first when they are on top; the codex asks the dispatcher. Under the handoff cover Esc does nothing.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or handoff.visible or session == null:
		return
	if not map.ui_cancel.cancel().is_empty() and is_inside_tree():
		get_viewport().set_input_as_handled()


## The "modal" layer's provider: something on the Overlays layer is open.
func _modal_open() -> bool:
	return overlays != null and _top_overlay() != null


## Closes the topmost overlay. The victory screen and the setup error stay (they have their own buttons): they take the Esc and
## nothing closes.
func _close_top_modal() -> void:
	var top := _top_overlay()
	if top == null or top == victory_screen or top == error_overlay:
		return
	if top == codex:
		codex.close()
	elif top == settings_panel:
		settings_panel.close()
	elif top == load_screen:
		if load_screen.confirm_overlay.visible:
			load_screen.cancel_delete()
		else:
			load_screen.back()
	elif top == battle_host:
		battle_host.close()
	elif top == battle_viewer:
		battle_viewer.close()
	elif top == report_overlay:
		close_turn_report()
	elif research_hud != null and top == research_hud.preview:
		research_hud.preview.visible = false
	elif research_hud != null and top == research_hud.panel:
		research_hud.panel.close()
	else:
		top.visible = false  # the quit question, the menu, the save dialog, the ? panel


## This screen's layers in the map's UiCancel: its overlays (above the map's own panels) and the menu as the last step.
func _register_cancel_layers() -> void:
	map.ui_cancel.register("modal", _modal_open, _close_top_modal, 100)
	map.ui_cancel.set_menu_opener(func(): if session != null: open_menu())
	codex.cancel_router = func(): map.ui_cancel.cancel()


# --- the real screens (#7, #8) ----------------------------------------------------------------------

## The battle report viewer on top of the turn report, coloured by seat.
func _show_battle_report(event: Dictionary) -> void:
	_bind()
	var state: GameState = map.state if session else null  # M5-2: the viewer's own view
	var seats: Array = session.players() if session else []
	battle_viewer.show_event(event, state, seats)
	_raise(battle_viewer)
	_set_battle_audio(true)


## Battle music and bed over the ducked map theme while the battle report viewer is open.
func _set_battle_audio(on: bool) -> void:
	if on == _battle_audio:
		return
	_battle_audio = on
	GameAudio.battle(on)


func _on_battle_viewer_visibility() -> void:
	if not battle_viewer.visible:
		_set_battle_audio(false)


## M5-2 (§2.1): the victory screen's "the fog lifts", from the observer once the game is over: what every faction
## really had, and every "what you didn't see" of the game. A loaded game replays its record for the turns before it
## was loaded. {} while the game runs, or without fog.
func _fog_lift_data() -> Dictionary:
	if session == null or not session.is_over():
		return {}
	var truth := session.state_for(FogRules.OBSERVER)
	if truth == null or not truth.fog:
		return {}
	if _fog_missed_from > 1:
		var earlier := replay_missed(session.record(), _fog_missed_from - 1)
		fog_missed = earlier + fog_missed
		_fog_missed_from = 1
	return FogView.lift(truth, session.players(), fog_missed)


## Every "what you didn't see" of the first `up_to` turns of a saved game (FogView.missed_of_turn), replayed from its
## record through a session's own order checks, every seat played by hand. Nothing in the game changes.
static func replay_missed(game_record: Dictionary, up_to: int = 0) -> Array:
	var out := []
	var errors := []
	var start := GameState.from_dict(game_record.get("start_state", {}), errors)
	if start == null:
		return out
	var players: Array = game_record.get("players", [])
	var s := GameSession.new(start, players, Serial.to_int(game_record.get("game_seed", 0)), AutoBattleResolver.new())
	var history: Array = game_record.get("history", [])
	for i in history.size():
		if (up_to > 0 and i >= up_to) or s.is_over() or s.phase() == GameSession.Phase.INVALID:
			break
		var orders := OrderBook.orders_from_dict(history[i].get("orders", {}), [])
		for k in players.size():
			if s.phase() == GameSession.Phase.HANDOFF:
				s.acknowledge_handoff()
			if s.phase() != GameSession.Phase.ORDERS:
				break
			for o in orders.get(s.current_player(), []):
				s.queue_order(o)
			s.end_turn()
		out.append_array(FogView.missed_of_turn(s))
	return out


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
	if first_game_guide:
		first_game_guide.sync(session, map.state)  # MVP-1: ticks from the viewer's own orders; hidden behind the cover
	var watching := is_watching()
	var playing: bool = session != null and session.phase() == GameSession.Phase.ORDERS and not watching
	var n: int = session.current_orders().size() if playing else 0
	var over: bool = session != null and session.is_over()
	var hud := map.table()
	# The seal: "End turn" and the order count (UX-1; it was the top bar's "End turn (2 orders)"). Results takes its place at the
	# end of a game.
	end_turn_button.disabled = not (playing or watching)
	end_turn_button.text = "End turn\n%s" % _count(n, "order") if playing else "End turn"
	end_turn_button.tooltip_text = _end_turn_tooltip(n)
	if watching:
		end_turn_button.text = "Next turn"
		end_turn_button.tooltip_text = TooltipText.plain("Next turn", "Each computer gives its orders from the map as it stands now, without seeing the other's, and the turn resolves. The turn report then shows what happened and what each computer was thinking.")
	end_turn_button.visible = not over
	results_button.visible = over
	hud.set_seal_pulse(playing and n > 0 and not _seal_learned())  # a new player: a gentle nudge once an order is queued
	_refresh_opponents()
	var has_report: bool = session != null and _report_turn() > 0
	report_button.disabled = not has_report
	var report_help := "Read again what happened last turn. Click a line to see it on the map."
	if not has_report:
		report_help = "Nothing has happened yet. The report of each turn appears here once every player has ended the turn."
	report_button.tooltip_text = TooltipText.plain("Turn report", report_help)
	ruler_button.visible = session != null and map.state != null and RulerRules.has_rulers(map.state) \
		and session.phase() != GameSession.Phase.INVALID
	if ruler_button.visible:  # M5-2: under fog, builds are learned, not public
		ruler_button.tooltip_text = TooltipText.plain("Ruler", "Your ruler with every number explained, and what you know of the enemy's: under fog of war their mandates and kept power are learned by seeing or fighting them, and they may have more. Your living ruler can sacrifice power for a new mandate here.") \
			if FogView.active(map.state) else TooltipText.plain("Ruler", RULER_HELP)
	if session == null or map.state == null or session.phase() == GameSession.Phase.INVALID:
		return
	map.turn_label.text = "Turn %d" % session.turn_number()
	map.turn_label.tooltip_text = _turn_tooltip()
	CodexLink.attach(map.turn_label, TooltipText.codex_for("turn"), open_codex)
	# The tray's one line of "what to do now" (two lines at most); the tooltip says the rest. The ? panel has all of it.
	if watching:
		map.set_hint("Watching the computer play both sides. Press Next turn to play a turn.",
			TooltipText.plain("Watching", "Nobody but the computer plays in this game. Next turn plays one turn; the turn report shows what each computer was thinking. Hover any number to see where it comes from."))
	elif playing and session.human_seats() == 1:
		# Against the computer the seat count means nothing to the player, and the opponent plaque needs the room.
		map.set_hint(ControlsHelp.QUICK, _orders_help())
	elif playing:
		map.set_hint("Player %d of %d: select an army, then click a neighboring province to move it there. Select your capital to recruit." % [
			session.current_seat(), session.players().size()], _orders_help())
	elif over:
		map.set_hint("The game is over. Results shows the summary; Turn report shows the last turn.",
			TooltipText.plain("Game over", "Results shows who won and the game in numbers. Turn report shows how the last turn went. The map shows the final positions; hover any number to see where it comes from."))


## UX-1: the End turn seal pulses for a new player: someone who has ended fewer than two turns in this installation.
const SEAL_HINTS := ["seal_turn_1", "seal_turn_2"]
var _seal_turns := -1  # turns a person has ended, from the settings' hints (-1: not read yet)


## True while the seal pulses (a person gives orders, one is queued, and they are still new to the game).
func seal_nudging() -> bool:
	return _bind_ok() and map.table().seal_pulsing()


func _bind_ok() -> bool:
	_bind()
	return map != null


func _seal_learned() -> bool:
	if _seal_turns < 0:
		_seal_turns = 0
		for h in SEAL_HINTS:
			if GameSettings.hint_seen(h):
				_seal_turns += 1
	return _seal_turns >= SEAL_HINTS.size()


## A person ended a turn with the seal: after two the pulse is learned for good (remembered in the settings' hints).
func _note_turn_ended() -> void:
	if _seal_learned():
		return
	GameSettings.mark_hint_seen(SEAL_HINTS[_seal_turns])
	_seal_turns += 1


## The tray hint's tooltip during orders: the whole how-to, which doesn't fit in the tray (the ? panel has it too).
func _orders_help() -> String:
	var how := ControlsHelp.HOW_TO_ORDER
	if session.human_seats() == 1 and not session.computer_seats().is_empty():
		return TooltipText.plain("You give orders as %s" % session.current_player_name(), how)
	return TooltipText.plain("Player %d of %d: %s gives orders" % [session.current_seat(), session.players().size(), session.current_player_name()], how)


## "the computer (Thornmane Clans, Normal)" for every computer seat but the current one, joined.
func _computer_names() -> String:
	var names := []
	var state := map.state
	if state == null:
		return ""
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
	handoff.uncovering.connect(_rebuild_under_cover)  # M5-2: rebuilt while the cover is up
	handoff.acknowledged.connect(_on_handoff_acknowledged)
	map.intercept_back = true
	map.back_requested.connect(open_menu)
	map.orders_changed.connect(_update_hud)
	map.codex_requested.connect(open_codex)
	report_host.set_presenter(self)  # UX-1: the modal report is the report host's presenter until UX-6
	_build_hud()
	_build_overlays()
	_register_cancel_layers()
	first_game_guide = FirstGameGuide.new()  # over the map, under every overlay layer
	first_game_guide.codex_requested.connect(open_codex)
	add_child(first_game_guide)
	map.table().hang("guide", first_game_guide)  # the Table places it under the realm plaque, inside the safe area


func _build_hud() -> void:
	var hud := map.table()
	# The seal (bottom right of the tray): End turn with the order count, and Results in its place at the end of a game.
	results_button = _hud_button("ResultsButton", "Results", show_results)
	results_button.tooltip_text = TooltipText.plain("Results", "The game is over: see who won, the turns played, the battles and the provinces each side held.")
	results_button.add_theme_color_override("font_color", UiPalette.GILT)
	results_button.add_theme_font_size_override("font_size", 18)
	results_button.custom_minimum_size = Vector2(TableHud.SEAL_W, 58)
	results_button.visible = false
	hud.add_seal_item(results_button)
	end_turn_button = _hud_button("EndTurnButton", "End turn", end_turn)
	end_turn_button.custom_minimum_size = Vector2(TableHud.SEAL_W, 58)
	end_turn_button.add_theme_font_size_override("font_size", 18)
	end_turn_button.add_theme_color_override("font_color", UiPalette.GILT)
	hud.add_seal_item(end_turn_button)
	# The system row, under the realm plaque: today's panels as they are (modal, with their dimmers), as icon buttons (UiIcons),
	# icons only below 1600 logical width; the tooltips name them.
	ruler_button = _hud_button("RulerButton", "Ruler", open_ruler_panel)
	ruler_button.tooltip_text = TooltipText.plain("Ruler", RULER_HELP)
	ruler_button.visible = false
	CodexLink.attach(ruler_button, "ruler", open_codex)
	hud.add_system_button("ruler", ruler_button)
	chronicle_button = hud.make_system_button("chronicle", "Chronicle", TooltipText.plain("Chronicle",
		"The turn's announcements and your plan for it, in one column you open and close. It arrives in a later update; until then Turn report has what happened last turn."), Callable())
	chronicle_button.disabled = true  # UX-6 fills it
	report_button = _hud_button("TurnReportButton", "Turn report", open_turn_report)
	hud.add_system_button("report", report_button)
	lenses_button = map.lens_ui.button  # UX-7: the map screen's lenses (LensUi) made it, with its picker
	codex_button = _hud_button("CodexButton", "Codex", open_codex.bind(""))
	codex_button.tooltip_text = TooltipText.plain("Codex", "Every rule of the game in plain language, searchable. Right-click a number, or hover it and press F1, to open the codex at the rule behind it.")
	hud.add_system_button("codex", codex_button)
	help_button = hud.make_system_button("help", "?", TooltipText.plain("Keys and mouse", "Every key and mouse binding, and how to give orders."), open_controls_help)
	help_button.custom_minimum_size.x = 34
	for b in [ruler_button, report_button, codex_button]:
		b.add_theme_font_size_override("font_size", 15)
	map.back_button.text = "Menu"
	map.back_button.tooltip_text = TooltipText.plain("Menu",
		"Save the game, load another, change the settings or quit to the title screen (Esc). The game also saves itself at the start of every turn.")
	# The rivals, top right: each with its banner, name and tag (#35); filled per game and per viewer (_refresh_opponents).
	opponent_box = HBoxContainer.new()
	opponent_box.name = "OpponentTag"
	opponent_box.add_theme_constant_override("separation", 10)
	opponent_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_box.visible = false
	hud.opponent_slot.add_child(opponent_box)
	hud.compact_changed.connect(func(_on): _refresh_opponent_labels())
	research_hud = ResearchHud.new(self)  # M4-4: the research chip (paths games only)


## The opponent plaque (top right, §1.3): every rival with its banner, emblem and name, a tag under them ("Computer (Normal)" for the
## computer, "Player 2" for a person in a hotseat game) and, in a fog game, a "last seen" line (in the name's tooltip when the
## window is under 1600 logical wide). A click-through to its codex entry is the right-click on any of it. Rebuilt whenever
## the viewer or the turn changes (a hotseat handoff shows the next player's rivals).
func _build_opponent_tag() -> void:
	_opponents_key = ""
	_refresh_opponents()


func _refresh_opponents() -> void:
	var hud := map.table()
	var key := ""
	if session != null and session.phase() != GameSession.Phase.INVALID and not session.is_over():
		key = "%d|%s|%d|%s" % [session.get_instance_id(), viewer(), session.turn_number(), str(map.state != null and FogView.active(map.state))]
	if key == _opponents_key:
		_refresh_opponent_labels()
		return
	_opponents_key = key
	for c in opponent_box.get_children():
		opponent_box.remove_child(c)
		c.queue_free()
	opponent_box.visible = false
	hud.opponent_panel.visible = false
	if key.is_empty():
		return
	var eyes := viewer()
	var state := session.state_for(eyes)  # names only, which are public
	if state == null:
		return
	var players := session.players()
	var any_computer := false
	for i in players.size():
		var fid := String(players[i])
		if fid == eyes:
			continue
		var f := state.find_faction(fid)
		var faction_name := f.faction_name if f else "An unknown faction"
		var computer_seat := session.is_computer(fid)
		any_computer = any_computer or computer_seat
		var stack := VBoxContainer.new()
		stack.name = "Seat%d" % (i + 1)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 1)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		opponent_box.add_child(stack)
		var line := HBoxContainer.new()
		line.name = "Line"
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		var banner := Art.banner_card(fid, 30.0)
		banner.name = "RivalBanner"
		line.add_child(banner)
		var emblem := SeatEmblem.new(i, SeatEmblem.Look.TOKEN, 16.0)
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(emblem)
		var name_label := Label.new()
		name_label.name = "OpponentName"
		name_label.text = faction_name
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", UiPalette.seat_color(i).lightened(0.3))
		name_label.set_meta("seat_help", TooltipText.plain("%s is played by the computer" % faction_name, AISeat.tag_help(faction_name, session.computer_level(fid)))
			if computer_seat else TooltipText.plain("%s is played by a person" % faction_name,
				"Player %d, at the same screen: orders stay hidden between turns behind the cover. %s" % [i + 1, RulesCodex.text("hotseat")]))
		name_label.tooltip_text = String(name_label.get_meta("seat_help"))
		CodexLink.attach(name_label, "computer_opponent" if computer_seat else "hotseat", open_codex)
		line.add_child(name_label)
		var tag: Label
		if computer_seat:
			tag = VictoryScreen.computer_tag(faction_name, session.computer_level(fid), open_codex)
		else:
			tag = _player_tag(i, faction_name)
		tag.add_theme_font_size_override("font_size", 11)
		(tag.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_top = 0
		(tag.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_bottom = 1
		# The tag and, in a fog game, the "last seen" line share the row under the name (the plaque is 72 px tall at most).
		var under := HBoxContainer.new()
		under.name = "Under"
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		under.add_theme_constant_override("separation", 8)
		stack.add_child(under)
		under.add_child(tag)
		var seen := Label.new()
		seen.name = "LastSeen"
		seen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seen.add_theme_font_size_override("font_size", 12)
		seen.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		seen.set_meta("rival", fid)
		under.add_child(seen)
	opponent_box.visible = opponent_box.get_child_count() > 0
	hud.opponent_panel.visible = opponent_box.visible
	CodexLink.attach(hud.opponent_panel, "computer_opponent" if any_computer else "hotseat", open_codex)
	_refresh_opponent_labels()


## A person's tag under a rival's name in a hotseat game: "Player 2", in the computer tag's chip.
func _player_tag(seat_index: int, faction_name: String) -> Label:
	var tag := VictoryScreen.computer_tag(faction_name, "normal")
	tag.name = "PlayerTag"
	tag.text = "Player %d" % (seat_index + 1)
	tag.tooltip_text = TooltipText.plain(tag.text, "%s is played by a person at this screen. %s" % [faction_name, RulesCodex.text("hotseat")])
	CodexLink.attach(tag, "hotseat", open_codex)
	return tag


## Every rival's "last seen" line (fog games): shown under the name at 1600 logical width and over, in the name's tooltip below.
func _refresh_opponent_labels() -> void:
	var hud := map.table()
	for stack in opponent_box.get_children():
		var seen := stack.find_child("LastSeen", true, false) as Label
		var name_label := stack.find_child("OpponentName", true, false) as Label
		if seen == null or name_label == null:
			continue
		var text := last_seen_text(map.state, viewer(), String(seen.get_meta("rival")), map.fog_memory)
		seen.text = text
		seen.visible = not text.is_empty() and not hud.compact
		var tip := String(name_label.get_meta("seat_help", ""))
		if not text.is_empty():
			tip = "%s\n\n%s" % [tip, TooltipText.wrap_text("%s: %s. Under fog of war you see only what your armies and land can see." % [name_label.text, text])]
		name_label.tooltip_text = tip
		CodexLink.attach(name_label, "computer_opponent" if session != null and session.is_computer(String(seen.get_meta("rival"))) else "hotseat", open_codex)


## What `viewer` knows of when rival `fid` was last seen (a fog game; "" without fog): "in sight now" while any of their armies
## or land is in clear sight or glimpsed, "last seen turn 6" (the end of turn 6) from the latest sighting remembered, and "not
## seen yet". It reads the viewer's own view and memory, never the truth.
static func last_seen_text(view: GameState, viewer_id: String, rival: String, memory: Dictionary) -> String:
	if view == null or not FogView.active(view) or view.find_faction(rival) == null:
		return ""
	var latest := 0
	for a in view.armies:
		if a.owner != rival:
			continue
		var level := String(a.seen.get("level", FogRules.CLEAR)) if FogView.is_stand_in(a) else FogRules.CLEAR
		if level == FogRules.CLEAR or level == FogRules.GLIMPSE:
			return "in sight now"
		latest = maxi(latest, int(a.seen.get("turn", 0)))
	for p in view.provinces:
		if p.owner != rival:
			continue
		var level := FogView.vision_level(view, viewer_id, p.id, memory)
		if level == FogRules.CLEAR or level == FogRules.GLIMPSE:
			return "in sight now"
		latest = maxi(latest, int(memory.get("provinces", {}).get(p.id, {}).get("seen_turn", 0)))
	return "last seen turn %d" % latest if latest > 0 else "not seen yet"


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
		"Close this and look at the final map. Results (where End turn was) brings this back.").pressed.connect(
			func(): victory_screen.visible = false)
	overlays.add_child(victory_screen)

	report_overlay = _report_overlay()

	battle_host = BattleHost.new()  # M3-5: under the report viewer and the codex it opens
	battle_host.rebuild_with = func(e: Dictionary) -> Dictionary: return rebuild_battle_log(session, e)
	battle_host.codex_requested.connect(open_codex)
	battle_host.report_requested.connect(_show_battle_report)
	overlays.add_child(battle_host)

	battle_viewer = BattleReportViewer.new()
	battle_viewer.can_rebuild = true
	battle_viewer.codex_requested.connect(open_codex)
	battle_viewer.closed.connect(_set_battle_audio.bind(false))
	battle_viewer.visibility_changed.connect(_on_battle_viewer_visibility)
	battle_viewer.watch_requested.connect(func(e: Dictionary):
		battle_viewer.close()
		watch_battle(e))
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
	_build_help()

	load_screen = LoadScreen.new()
	load_screen.load_requested.connect(_on_load_requested)
	overlays.add_child(load_screen)

	settings_panel = SettingsPanel.new()
	settings_panel.closed.connect(_apply_board_setting)
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
	_menu_button(m[1], "SettingsButton", "Settings", open_settings, "Window or fullscreen, how big the interface is drawn, and the sound volumes.")
	_menu_button(m[1], "QuitToTitleButton", "Quit to title", _on_quit_requested, "Leave this game for the title screen. You are asked to confirm first.")


## The ? panel (UX-1, §1.3): every key and mouse binding and today's hint text in full, from ControlsHelp (and, on the 3D board,
## the board's own legend text). Filled each time it opens, so a lens key or a game's own lines are there.
func _build_help() -> void:
	var h := _overlay("ControlsHelp", Vector2(860, 0))
	help_overlay = h[0]
	var title := _label("HelpTitle", 30, UiPalette.GILT)
	title.text = "Keys and mouse"
	h[1].add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 430)
	h[1].add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "HelpBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	_overlay_button(_button_row(h[1]), "CloseHelpButton", "Close", func(): help_overlay.visible = false, "Close this list (Esc).")


## Opens the ? panel: every key and mouse binding, the how-to, and the board's legend.
func open_controls_help() -> void:
	_bind()
	var body := help_overlay.find_child("HelpBody", true, false) as VBoxContainer
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var lens_keys := []
	for id in map.lens_host.ids():
		lens_keys.append([OS.get_keycode_string(map.lens_host.key_of(id)), map.lens_host.title_of(id)])
	for section in ControlsHelp.sections(lens_keys):
		var head := _label("HelpHeading", 20, UiPalette.GILT)
		head.text = String(section.title)
		body.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		body.add_child(grid)
		for row in section.rows:
			var keys := _label("HelpKeys", 16, UiPalette.TEXT_PRIMARY)
			keys.text = String(row.keys)
			keys.custom_minimum_size = Vector2(250, 0)
			keys.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			grid.add_child(keys)
			var what := _label("HelpText", 16, UiPalette.TEXT_SECONDARY)
			what.text = String(row.text)
			what.custom_minimum_size = Vector2(500, 0)
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(what)
	var legend := _board_legend()
	if not legend.is_empty():
		var head := _label("HelpHeading", 20, UiPalette.GILT)
		head.text = "What the 3D board shows"
		body.add_child(head)
		var text := _label("HelpLegend", 15, UiPalette.TEXT_SECONDARY)
		text.text = legend
		body.add_child(text)
	_raise(help_overlay)


## The 3D board's own legend (what its colours, figures and marks mean), when the board is up; "" on the 2D map.
func _board_legend() -> String:
	if map.board == null or map.board.get("overlay") == null:
		return ""
	return String(map.board.overlay.legend_text())


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


## The NoticeLayer's notice: a title, a line and OK, under the realm plaque.
func _build_notice() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NoticeLayer"
	layer.layer = 15
	add_child(layer)
	notice_panel = PanelContainer.new()
	notice_panel.name = "Notice"
	notice_panel.visible = false
	var style := UiPalette.panel_style(16)
	style.border_color = UiPalette.GILT
	notice_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(notice_panel)
	map.table().hang("notice", notice_panel)  # UX-1: under the realm plaque, inside the board's safe area (TableHud)
	# The title and OK share a row and the text has the whole width under them: the notice lives in the Table's left column (400 px),
	# and a shorter notice leaves the selection card more room under it.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	notice_panel.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	notice_title = _label("NoticeTitle", 20, UiPalette.GILT)
	notice_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(notice_title)
	var ok := Button.new()
	ok.name = "NoticeOkButton"
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(64, 32)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.add_theme_font_size_override("font_size", 16)
	ok.tooltip_text = "Hide this notice."
	ok.pressed.connect(_on_notice_ok)
	head.add_child(ok)
	notice_ok = ok
	notice_label = _label("NoticeText", 17, UiPalette.TEXT_PRIMARY)
	column.add_child(notice_label)


## The turn report panel in a modal frame with a footer: a hint and a Close button.
func _report_overlay() -> Control:
	# MVP-3 (#177): dim enough that what the box doesn't cover (the card's half-cut lines down its edge) stays quiet.
	var overlay := _overlay_base("ReportOverlay", REPORT_DIM)
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
	PanelFit.attach(box, center)  # MVP-3 (#177): at 125% the 760 px box is taller than the 720 px viewport: it shrinks to fit
	report_panel = TurnReportPanel.new()
	report_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_panel.province_focus_requested.connect(_on_report_focus)
	report_panel.battle_report_requested.connect(func(e: Dictionary): _show_battle_report(e))
	report_panel.codex_requested.connect(open_codex)
	report_panel.watch_again_requested.connect(func(): watch_turn_again())
	report_panel.watch_requested.connect(func(e: Dictionary): watch_battle(e))
	report_panel.watch_battles_requested.connect(func(events: Array): watch_battles(events))
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
	hint.text = "Click a line to see it on the map. Battles have a full report, and ? explains the rule behind a line. Reopen this from Turn report in the system row."
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


# --- the 3D board (M3a.1) ---------------------------------------------------------------------------

## Draws the map as the 3D world ("3d") or the 2D map ("2d"). The 3D board needs a viewport, so outside
## the tree (headless tests that never add the screen) the map stays 2D.
func use_board(kind: String) -> void:
	_bind()
	if kind == "3d" and map.board == null:
		var b := Board3D.new()
		b.cover_check = _board_covered
		map.set_board(b)
	elif kind != "3d" and map.board != null:
		map.set_board(null)


## Settings "Board" (default 3D), when the screen enters the tree and when the settings close.
func _apply_board_setting() -> void:
	if not is_inside_tree():
		return
	use_board(GameSettings.load_from().board)


## True while the handoff cover or a modal overlay hides the board (it then stops rendering).
func _board_covered() -> bool:
	return handoff.visible or _top_overlay() != null


## If the turn just resolved hasn't been played out for `faction_id` yet, plays it on the 3D board: from
## the start-of-turn state, through the report's events, to the state the map now shows. True if it plays.
## M5-2: the turn as `viewer()` saw it (§2.8, §12.1): from its view at the turn's start (view_before), through its own
## report, to the map it now shows. In a hotseat fog game the playback is silent but for the ambient bed (§2.9).
func _play_on_board(faction_id: String) -> bool:
	_keep_replay()
	if map.board == null or session == null or not can_watch_again():
		return false
	var report := _report()
	if int(_played_for.get(faction_id, 0)) == int(report.turn):
		return false
	_played_for[faction_id] = int(report.turn)
	return _play_turn(report)


func _play_turn(report: Dictionary) -> bool:
	var before := session.view_before(viewer())
	if before == null:
		return false
	var hush := _hotseat_fog()
	GameAudio.hush(hush)
	var played: bool = map.board.play_turn(before, report.events, map.state)
	if hush and played:
		map.board.playback_finished.connect(func(): GameAudio.hush(false), CONNECT_ONE_SHOT)
	elif hush:
		GameAudio.hush(false)
	return played


## M3a.2: notes the turn the report describes, the first time it is seen after resolving here (a loaded game's last
## turn is not played), for every seat's playback and replays.
func _keep_replay() -> void:
	if session == null or _turn_from < 0:
		return
	var turn := _report_turn()
	if turn > 0 and int(_replay.get("turn", 0)) != turn and _turn_from == turn - 1:
		_replay = {"turn": turn}


## True when the last resolved turn can be played on the 3D board (it resolved while this screen was up).
func can_watch_again() -> bool:
	return map != null and map.board != null and session != null and _report_turn() > 0 \
		and int(_replay.get("turn", 0)) == _report_turn()


## "Watch this turn again" (the turn report's button): closes the report, plays the turn on the board
## once more from its start, and opens the report again when it ends. Returns false when it can't.
func watch_turn_again() -> bool:
	if not can_watch_again():
		return false
	close_turn_report()
	if not _play_turn(_report()):
		open_turn_report()
		return false
	map.board.playback_finished.connect(func():
		if session != null and _report_turn() > 0:
			open_turn_report(), CONNECT_ONE_SHOT)
	return true


## The turn's report is ready to show (with its headline cues after `cue_delay` seconds), after the board's playback when one
## is running: the report host tells its presenter (the modal report opens, then the player's battles auto-watch when Settings
## ask, M3-5).
func _open_report_when_played(cue_delay: float) -> void:
	if map.board != null and map.board.is_playing():
		map.board.playback_finished.connect(func():
			if session != null and _report_turn() > 0:
				report_host.notify_ready(_report_turn(), {"cue_delay": 0.2}), CONNECT_ONE_SHOT)
		return
	report_host.notify_ready(_report_turn(), {"cue_delay": cue_delay})


# --- watching battles (M3-5) ----------------------------------------------------------------------

## Plays `events` (battle events, in report order) in the battle host from events[start], over whatever is
## open (the turn report, which shows again when it closes). "" or why not.
func watch_battles(events: Array, start: int = 0) -> String:
	_bind()
	if session == null or session.phase() == GameSession.Phase.INVALID:
		return "No game is running."
	if handoff.visible:
		return "Battles can't be watched behind the handoff cover."
	var why := battle_host.open(events, start, session, watch_viewer(), map.state)  # M5-2: the viewer's own view
	if why.is_empty():
		_raise(battle_host)
	return why


## Plays one battle of the last report, with the report's other battles that can be watched as its queue.
func watch_battle(event: Dictionary) -> String:
	_bind()
	if session == null:
		return "No game is running."
	var battles := BattleHost.watchable(BattleHost.battles_of(_report().get("events", []), ""), true)  # M5-2: your report's
	for i in battles.size():
		if same_battle(battles[i], event):
			return watch_battles(battles, i)
	return watch_battles([event])


## Whether two battle events are the same battle of the report (copies of it): same text, same provinces.
static func same_battle(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("text", "")) == String(b.get("text", "")) and Array(a.get("provinces", [])) == Array(b.get("provinces", []))


## Whose side the battle screen takes for its victory and defeat stings: the only person at the table, or
## the player giving orders now in a hotseat game; "" for nobody in particular (watch mode, a finished
## hotseat game).
func watch_viewer() -> String:
	if session == null:
		return ""
	if session.human_seats() == 1:
		for fid in session.players():
			if not session.is_computer(String(fid)):
				return String(fid)
	if session.phase() == GameSession.Phase.ORDERS and not session.is_computer(session.current_player()):
		return session.current_player()
	return ""


## Settings "Watch my battles at the start of each turn": once the new turn's report has opened (after the
## board's playback and any handoff), the player at the controls watches their battles, once per turn.
## Never in watch mode, behind the handoff cover, or when they fought none. True when it started.
func auto_watch() -> bool:
	if session == null or handoff.visible or session.phase() != GameSession.Phase.ORDERS or is_watching():
		return false
	var fid := session.current_player()
	var turn := _report_turn()
	if session.is_computer(fid) or turn <= 0 or int(_auto_watched.get(fid, 0)) >= turn:
		return false
	if not GameSettings.load_from().auto_watch_battles:
		return false
	_auto_watched[fid] = turn
	var mine := BattleHost.watchable(BattleHost.battles_of(_report().get("events", []), fid), true)
	if mine.is_empty():
		return false
	return watch_battles(mine).is_empty()


## Rebuilds the log of a battle of the last turn that isn't kept, from the game record (BattleLog.regenerate),
## and checks it against the battle's report (BattleLog.cross_check). {"log", "errors"}: "log" is {} with the
## plain reason when it can't. The battle host calls this (rebuild_with); the record is a copy, so nothing
## in the game changes.
static func rebuild_battle_log(game_session: GameSession, event: Dictionary) -> Dictionary:
	if game_session == null:
		return {"log": {}, "errors": [BattleHost.NOT_KEPT]}
	var report := game_session.turn_report()
	var k := -1
	var n := 0
	for e in report.events:
		if not GameSession.BATTLE_TYPES.has(String(e.get("type", ""))):
			continue
		if same_battle(e, event):
			k = n
			break
		n += 1
	if k < 0:
		return {"log": {}, "errors": ["This battle isn't in the last turn's report, so its playback can't be rebuilt."]}
	var out := BattleLog.regenerate(game_session.record(), int(report.turn), k)
	if (out.log as Dictionary).is_empty():
		return {"log": {}, "errors": out.errors if not out.errors.is_empty() else [BattleHost.NOT_KEPT]}
	var numbers: Dictionary = event.get("numbers", {})
	if not BattleLog.cross_check(out.log, numbers.get("report", {})).is_empty():
		return {"log": {}, "errors": ["The rebuilt playback doesn't match this battle's report, so it isn't shown."]}
	return {"log": out.log, "errors": []}
