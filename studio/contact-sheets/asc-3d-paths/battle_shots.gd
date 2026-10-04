extends SceneTree
## Plays a battle fixture on the 3D battle stage (world3d/battle_watch3d.tscn) and captures frames.
##   $GODOT --path . --always-on-top --resolution 1600x900 -s <absolute path to this file> -- --fixture NAME --out=DIR
## (batch asc-3d-paths: path_wings, path_iron_hide and path_lifedrinker show Seraphs, the Iron Colossus and Bloodsworn)
var out := ""
var name_ := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for k in args.size():
		if args[k] == "--fixture" and k + 1 < args.size():
			name_ = args[k + 1]
		elif String(args[k]).begins_with("--out="):
			out = String(args[k]).trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://world3d/battle_watch3d.tscn")
	_run.call_deferred()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var marks := [3.0, 6.0, 9.0, 13.0, 18.0]
	var mi := 0
	while mi < marks.size() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 >= marks[mi]:
			await process_frame
			var img: Image = root.get_texture().get_image()
			img.save_png(out.path_join("%s_t%02d.png" % [name_, int(marks[mi])]))
			print("shot ", name_, " ", marks[mi])
			mi += 1
	quit()
