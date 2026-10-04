## Autoload for the 3D spike: `godot --path . -- --world3d` opens the 3D world preview instead of
## the title screen. Does nothing otherwise (tests and the 2D game are untouched).
extends Node

const SCENE := "res://world3d/world_preview.tscn"


func _ready() -> void:
	if "--world3d" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(SCENE)
