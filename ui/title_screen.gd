extends Control
## Placeholder title screen. Replaced by the new game screen in a later ticket.

const VERSION_TEXT := "milestone 1 skeleton"
const MAP_SCENE := "res://ui/map_screen.tscn"


func _ready() -> void:
	$Center/Box/Subtitle.text = "A strategy game where every rule is visible. (%s)" % VERSION_TEXT
	$Center/Box/MapPreviewButton.pressed.connect(_on_map_preview_pressed)


## Opens the map screen; with no state handed to it, it shows a fresh default M1 game.
func _on_map_preview_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
