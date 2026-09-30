extends Control
## Placeholder title screen. Replaced by the new game screen in a later ticket.

const VERSION_TEXT := "milestone 1 skeleton"


func _ready() -> void:
	$Center/Box/Subtitle.text = "A strategy game where every rule is visible. (%s)" % VERSION_TEXT
