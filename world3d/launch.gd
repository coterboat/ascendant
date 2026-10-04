## Autoload for the 3D world: `godot --path . -- --world3d` opens the 3D world preview (the spike's dev
## scene) instead of the title screen. In a windowed run it also starts baking the 3D board's land in
## the background (Board3D.prebake), so the first game's board is ready by the time it starts. Headless
## runs (tests, tools) do nothing here.
extends Node

const SCENE := "res://world3d/world_preview.tscn"


func _ready() -> void:
	if "--world3d" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(SCENE)
	elif DisplayServer.get_name() != "headless" and GameSettings.load_from().board == "3d":
		Board3D.prebake()
