class_name TitleScreen
extends Control
## The title screen, the front door and the hub of the game flow (#8). See SceneFlow for every screen
## change. ASCENDANT large over a backdrop (Art.title_backdrop when it exists, otherwise the hills
## terrain dimmed to indigo), the tagline from the game brief, and both faction banners.
##   Continue     only when there is a save: loads the newest one that can be read (SaveStore.latest)
##                and switches to its game screen (SceneFlow.make_loaded_game). A save that turns out
##                to be damaged is explained under the buttons instead.
##   New game     opens the NewGameScreen over the title (you against the computer, every system on). Start
##                hands its config to a new GameScreen (SceneFlow.make_game: start_game(config) runs
##                before it enters the tree) and switches to it; Back (or Esc) closes it.
##   Load game    opens the LoadScreen over the title: every save, newest first, with delete.
##   Quick start  straight into a game: NewGameScreen.quick_start_config() (a random faction against the
##                computer at Normal, every system on, rulers on the balanced preset, a random seed).
##   Codex        opens the CodexPanel over the title; Close (or Esc) returns here.
##   Settings     opens the SettingsPanel (window mode, interface size, sound volumes).
##   Quit         closes the game.
##   Map preview  a developer preview of the map screen, kept small and grey at the bottom. MVP-1 (#141): it is hidden
##                unless the game is launched with `-- --dev` (dev_mode()), so a player never sees it.
## Builds its overlays lazily, so the whole flow also runs before the screen is in the tree (tests):
## then nothing switches, and next_scene holds the screen it would have switched to. `store` (the
## saves) can be set before the screen is used; tests give it a temporary folder.

const DEV_FLAG := "--dev"
const VERSION_TEXT := "MVP build"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"
## From design/GAME_BRIEF.md's one line.
const TAGLINE := "Simultaneous-turn fantasy strategy where every rule is visible."
const BANNERS := {"KingdomBanner": "kingdom", "BeastsBanner": "beasts"}

var continue_button: Button
var new_game_button: Button
var load_button: Button
var quick_start_button: Button
var codex_button: Button
var settings_button: Button
var quit_button: Button
var map_preview_button: Button
var error_label: Label
var new_game_screen: NewGameScreen = null  # built on first use
var load_screen: LoadScreen = null  # built on first use
var settings_panel: SettingsPanel = null  # built on first use
var codex: CodexPanel = null  # built on first use
var next_scene: Node = null  # the screen this one handed over to (SceneFlow.switch)
var store: SaveStore = null  # the saves; SaveStore.new() (user://saves) unless set first
var _bound := false


## True when the game was launched with `-- --dev`: the developer links (Map preview) show.
static func dev_mode() -> bool:
	return OS.get_cmdline_user_args().has(DEV_FLAG)


func _ready() -> void:
	_bind()
	if is_inside_tree():
		GameSettings.apply_saved_once(get_tree())
	# The title theme plays here and under the new game, build and load screens; no ambiance bed.
	GameAudio.music("music_title")
	GameAudio.ambiance("")


## Finds the buttons and wires them, once (from _ready, or from the first call before it).
func _bind() -> void:
	if _bound:
		return
	_bound = true
	if store == null:
		store = SaveStore.new()
	$Center/Box/Subtitle.text = TAGLINE
	$Version.text = VERSION_TEXT
	continue_button = $Center/Box/ContinueButton
	new_game_button = $Center/Box/NewGameButton
	load_button = $Center/Box/LoadGameButton
	quick_start_button = $Center/Box/QuickStartButton
	codex_button = $Center/Box/CodexButton
	settings_button = $Center/Box/SettingsButton
	quit_button = $Center/Box/QuitButton
	map_preview_button = $Center/Box/MapPreviewButton
	error_label = $Center/Box/ErrorLabel
	for b in [continue_button, new_game_button, load_button, quick_start_button, codex_button, settings_button, quit_button]:
		_style_menu_button(b, b == continue_button)
	_use_backdrop_art()
	var model := GameState.new()
	for node_name in BANNERS:
		var f := model.find_faction(BANNERS[node_name])
		var caption := get_node("%s/%s" % [node_name, node_name.replace("Banner", "Caption")]) as Label
		caption.text = f.faction_name if f else ""
	continue_button.pressed.connect(func(): continue_game())
	new_game_button.pressed.connect(open_new_game)
	load_button.pressed.connect(open_load_screen)
	quick_start_button.pressed.connect(func(): quick_start())
	codex_button.pressed.connect(open_codex.bind(""))
	settings_button.pressed.connect(open_settings)
	quit_button.pressed.connect(quit_game)
	map_preview_button.pressed.connect(_on_map_preview_pressed)
	var dev := dev_mode()
	map_preview_button.visible = dev
	$Center/Box/DevGap.visible = dev
	refresh_saves()


## Shows Continue only when there is a save to continue, with what it will load in its tooltip.
func refresh_saves() -> void:
	_bind()
	var latest := store.latest()
	continue_button.visible = not latest.is_empty()
	if not latest.is_empty():
		var h: Dictionary = latest.header
		continue_button.tooltip_text = "Play on from your latest save, \"%s\" (%s): %s\n%s" % [
			String(h.get("name", "")), SaveGame.when_text(Serial.to_int(h.get("saved_at", 0))),
			LoadScreen.details_text(h), TooltipText.wrap_text(SaveGame.ORDERS_NOTE)]
	_focus_first()


## Continue: loads the newest save that can be read. Returns the game screen, or null (with the reason
## under the buttons) when there is none or it can't be loaded.
func continue_game() -> GameScreen:
	_bind()
	var latest := store.latest()
	if latest.is_empty():
		show_error("There is no saved game to continue yet.")
		refresh_saves()
		return null
	var got := store.read(latest.path)
	if not got.errors.is_empty():
		show_error(SaveGame.error_text(got.errors))
		return null
	return load_save(got.save)


## Turns `save` into a game screen and switches to it. Returns it, or null after showing why not (on
## the load screen when it is open, otherwise under the title's buttons).
func load_save(save: Dictionary) -> GameScreen:
	var made := SceneFlow.make_loaded_game(save)
	if made.game == null:
		if load_screen != null and load_screen.visible:
			load_screen.show_error(made.error)
		else:
			show_error(made.error)
		return null
	next_scene = made.game
	SceneFlow.switch(self, made.game)
	return made.game


func show_error(text: String) -> void:
	error_label.text = text
	error_label.visible = not text.is_empty()


## Shows the new game screen over the title. `last_game` ({"players", "seed"} of the game just played,
## from the victory screen's New game) pre-fills it for a rematch: same seating, new seed.
func open_new_game(last_game: Dictionary = {}) -> void:
	_bind()
	if new_game_screen == null:
		new_game_screen = NewGameScreen.new()
		new_game_screen.start_requested.connect(start_game)
		new_game_screen.back_requested.connect(close_new_game)
		add_child(new_game_screen)
	if not last_game.is_empty():
		new_game_screen.prefill(last_game)
	_raise(new_game_screen)
	if new_game_screen.is_inside_tree():
		new_game_screen.start_button.grab_focus.call_deferred()


## Back on the new game screen: the title again.
func close_new_game() -> void:
	if new_game_screen:
		new_game_screen.visible = false
	_focus_first()


## The Load game button: every save over the title.
func open_load_screen() -> void:
	_bind()
	if load_screen == null:
		load_screen = LoadScreen.new()
		load_screen.load_requested.connect(func(save: Dictionary): load_save(save))
		load_screen.back_requested.connect(refresh_saves)
		add_child(load_screen)
	_raise(load_screen)
	load_screen.open(store)


func open_settings() -> void:
	_bind()
	if settings_panel == null:
		settings_panel = SettingsPanel.new()
		settings_panel.closed.connect(_focus_first)
		add_child(settings_panel)
	_raise(settings_panel)
	settings_panel.open()


func quit_game() -> void:
	if is_inside_tree():
		get_tree().quit()


## Starts a game with `config` (the NewGameScreen contract) and switches to its game screen. Returns
## the game screen.
func start_game(config: Dictionary) -> GameScreen:
	var game := SceneFlow.make_game(config)
	next_scene = game
	SceneFlow.switch(self, game)
	return game


## Straight into a game: you against the computer at Normal, a random faction, every system on, a random seed.
func quick_start() -> GameScreen:
	return start_game(NewGameScreen.quick_start_config())


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


## Opens the map screen on a fresh default game (a developer preview, no turns).
func _on_map_preview_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


## Shows an overlay above everything else on the title.
func _raise(overlay: Control) -> void:
	move_child(overlay, get_child_count() - 1)
	overlay.visible = true


func _focus_first() -> void:
	if is_inside_tree():
		_grab_first_focus.call_deferred()


## The deferred half of _focus_first. By then the title may already be gone: `-- --world3d` swaps in the 3D
## world preview on the same frame (world3d/launch.gd), so it checks again instead of focusing a button
## that is out of the tree (an engine error at boot).
func _grab_first_focus() -> void:
	var button: Button = continue_button if continue_button.visible else new_game_button
	if button.is_inside_tree():
		button.grab_focus()


## The painted title backdrop (Art.title_backdrop) once it is in the game, covering the screen under
## the vignette; until then the hills terrain, tiled and dimmed to the panel indigo.
func _use_backdrop_art() -> void:
	var art := Art.title_backdrop()
	if art == null:
		return
	var backdrop := $Backdrop as TextureRect
	backdrop.texture = art
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate = Color(0.8, 0.8, 0.86)


## The title's menu buttons: deep indigo plates with a thin border that turns gilt on hover and focus.
func _style_menu_button(b: Button, primary: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_BG if state_name == "normal" else UiPalette.PANEL_RAISED
		sb.bg_color.a = 0.92
		sb.border_color = UiPalette.GILT if primary or state_name != "normal" else UiPalette.PANEL_BORDER
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		if state_name == "focus":
			sb.draw_center = false
		b.add_theme_stylebox_override(state_name, sb)
	b.add_theme_color_override("font_hover_color", UiPalette.GILT)
	b.add_theme_color_override("font_focus_color", UiPalette.GILT if primary else UiPalette.TEXT_PRIMARY)
	if not primary:
		b.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
