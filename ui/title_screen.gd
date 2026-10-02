class_name TitleScreen
extends Control
## The title screen and the hub of the game flow (#8). See SceneFlow for every screen change.
##   New game     opens the NewGameScreen over the title. Start hands its config to a new GameScreen
##                (SceneFlow.make_game: start_game(config) runs before it enters the tree) and switches
##                to it; Back (or Esc) closes it and shows the title again.
##   Quick start  the same, with GameScreen.default_config() (every faction, a random seed).
##   Codex        opens the CodexPanel over the title; Close (or Esc) returns here.
##   Map preview  a developer preview of the map screen, kept small and grey at the bottom.
## Builds its overlays lazily, so the whole flow also runs before the screen is in the tree (tests):
## then nothing switches, and next_scene holds the screen it would have switched to.

const VERSION_TEXT := "milestone 1"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"

var new_game_button: Button
var quick_start_button: Button
var codex_button: Button
var map_preview_button: Button
var new_game_screen: NewGameScreen = null  # built on first use
var codex: CodexPanel = null  # built on first use
var next_scene: Node = null  # the screen this one handed over to (SceneFlow.switch)
var _bound := false


func _ready() -> void:
	_bind()


## Finds the buttons and wires them, once (from _ready, or from the first call before it).
func _bind() -> void:
	if _bound:
		return
	_bound = true
	$Center/Box/Subtitle.text = "A strategy game where every rule is visible. (%s)" % VERSION_TEXT
	new_game_button = $Center/Box/NewGameButton
	quick_start_button = $Center/Box/QuickStartButton
	codex_button = $Center/Box/CodexButton
	map_preview_button = $Center/Box/MapPreviewButton
	new_game_button.pressed.connect(open_new_game)
	quick_start_button.pressed.connect(quick_start)
	codex_button.pressed.connect(open_codex.bind(""))
	map_preview_button.pressed.connect(_on_map_preview_pressed)
	if is_inside_tree():
		new_game_button.grab_focus.call_deferred()


## Shows the new game screen over the title.
func open_new_game() -> void:
	_bind()
	if new_game_screen == null:
		new_game_screen = NewGameScreen.new()
		new_game_screen.start_requested.connect(start_game)
		new_game_screen.back_requested.connect(close_new_game)
		add_child(new_game_screen)
	_raise(new_game_screen)
	if new_game_screen.is_inside_tree():
		new_game_screen.start_button.grab_focus.call_deferred()


## Back on the new game screen: the title again.
func close_new_game() -> void:
	if new_game_screen:
		new_game_screen.visible = false
	if is_inside_tree():
		new_game_button.grab_focus.call_deferred()


## Starts a hotseat game with `config` ({"players", "seed"}, the NewGameScreen contract) and switches
## to its game screen. Returns the game screen.
func start_game(config: Dictionary) -> GameScreen:
	var game := SceneFlow.make_game(config)
	next_scene = game
	SceneFlow.switch(self, game)
	return game


## A game with the default setup: every faction in data order and a random seed.
func quick_start() -> GameScreen:
	return start_game(GameScreen.default_config())


## Opens the codex over the title, at `key` when given.
func open_codex(key: String = "") -> void:
	_bind()
	if codex == null:
		codex = load(CODEX_SCENE).instantiate()
		codex.name = "Codex"
		var bg := codex.get_node_or_null("Background") as PanelContainer
		if bg:
			bg.add_theme_stylebox_override("panel", UiPalette.panel_style())
		add_child(codex)
	_raise(codex)
	codex.open(key)


## Esc closes the codex in one press (its search box would otherwise take the first Esc).
func _input(event: InputEvent) -> void:
	if codex != null and codex.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		codex.close()


## Opens the map screen on a fresh default game (a developer preview, no turns).
func _on_map_preview_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


## Shows an overlay above everything else on the title.
func _raise(overlay: Control) -> void:
	move_child(overlay, get_child_count() - 1)
	overlay.visible = true
