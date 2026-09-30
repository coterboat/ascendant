extends SceneTree
## Compile check.
##   godot --headless --path . -s tools/compile_check.gd
## Parses and compiles every project `.gd` file and exits 1 if any fail.
## Skips hidden directories (.godot/, .git/, ...) and any directory holding a
## `.gdignore` file, which is how Godot marks non-project content.


func _initialize() -> void:
	var files := _find_scripts("res://")
	files.sort()
	var bad := PackedStringArray()
	for path in files:
		var script := GDScript.new()
		script.source_code = FileAccess.get_file_as_string(path)
		# Compile under the real path so relative preloads and error lines match.
		script.take_over_path(path)
		var err := script.reload()
		if err != OK:
			bad.append(path)
			print("FAIL %s (%s)" % [path, error_string(err)])
		else:
			print("ok   %s" % path)

	print("\n%d scripts checked, %d failed" % [files.size(), bad.size()])
	quit(1 if not bad.is_empty() or files.is_empty() else 0)


func _find_scripts(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	if dir.file_exists(".gdignore"):
		return out
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			out.append_array(_find_scripts(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
