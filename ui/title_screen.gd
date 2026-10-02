extends Control
## Placeholder title screen. Replaced by the new game screen in a later ticket.

const VERSION_TEXT := "milestone 1 skeleton"
const MAP_SCENE := "res://ui/map_screen.tscn"
const GAME_SCENE := "res://ui/game_screen.tscn"


func _ready() -> void:
	$Center/Box/Subtitle.text = "A strategy game where every rule is visible. (%s)" % VERSION_TEXT
	$Center/Box/QuickStartButton.pressed.connect(_on_quick_start_pressed)
	$Center/Box/MapPreviewButton.pressed.connect(_on_map_preview_pressed)


## Starts a hotseat game with the default setup (GameScreen.default_config(): every faction, a random
## seed). The game screen starts it itself when it opens without a config.
func _on_quick_start_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


## Opens the map screen; with no state handed to it, it shows a fresh default M1 game.
func _on_map_preview_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
