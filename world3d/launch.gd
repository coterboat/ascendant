## Autoload for the 3D world: `godot --path . -- --world3d` opens the 3D world preview (the spike's dev
## scene) instead of the title screen; `-- --battle3d --fixture NAME` plays a battle fixture on the 3D
## battle stage (world3d/battle_watch3d.tscn). In a windowed run it also starts baking the 3D board's land in
## the background (Board3D.prebake), so the first game's board is ready by the time it starts. Headless
## runs (tests, tools) do nothing here.
extends Node

const SCENE := "res://world3d/world_preview.tscn"
const BATTLE_SCENE := "res://world3d/battle_watch3d.tscn"


func _ready() -> void:
	if "--world3d" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(SCENE)
	elif "--battle3d" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() != "headless":
			Board3D.prebake() ## headless, the stage bakes the land itself when it first shows
		get_tree().change_scene_to_file.call_deferred(BATTLE_SCENE)
	elif DisplayServer.get_name() != "headless" and GameSettings.load_from().board == "3d":
		Board3D.prebake()


## Quitting while the land still bakes (the first seconds of a windowed run; longer on a busy machine): finish
## the bake first, or the exit tears its GDScript down under it and the process crashes or hangs on the way
## out. The bake reads meshes back through the RenderingServer, which only answers between frames, so the
## wait keeps flushing it (a bare wait here would deadlock), for EXIT_WAIT_MS at most. Headless runs (tests,
## tools) never prebake here and are left alone.
const EXIT_WAIT_MS := 20000


func _exit_tree() -> void:
	if Board3D._task < 0 or DisplayServer.get_name() == "headless":
		return
	var until := Time.get_ticks_msec() + EXIT_WAIT_MS
	while not WorkerThreadPool.is_task_completed(Board3D._task):
		if Time.get_ticks_msec() > until:
			return
		RenderingServer.force_sync()
		OS.delay_msec(2)
	WorkerThreadPool.wait_for_task_completion(Board3D._task)
	Board3D._task = -1
