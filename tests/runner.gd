extends SceneTree
## Headless test runner.
##   godot --headless --path . -s tests/runner.gd
## Finds every `test_*.gd` under res://tests/, runs each `test_*` method on a
## fresh instance, prints PASS/FAIL per test, and exits 1 on any failure.
## Engine or script errors raised while a test runs also fail that test.

const TEST_ROOT := "res://tests"


class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return out


func _initialize() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var passed := 0
	var failed := 0

	var files := _find_test_files(TEST_ROOT)
	files.sort()
	for path in files:
		catcher.take()
		var script: Script = load(path)
		var load_errors := catcher.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			failed += 1
			print("FAIL %s (could not load)" % path)
			for e in load_errors:
				print("     %s" % e)
			continue

		var names: Array[String] = []
		for m in script.get_script_method_list():
			var method_name: String = m["name"]
			if method_name.begins_with("test_") and not names.has(method_name):
				names.append(method_name)
		names.sort()

		for method_name in names:
			var instance: Object = script.new()
			if not instance.has_method("get_failures"):
				failed += 1
				print("FAIL %s (does not extend res://tests/test_case.gd)" % path)
				break
			catcher.take()
			instance.call(method_name)
			var problems: PackedStringArray = instance.get_failures()
			problems.append_array(catcher.take())
			var label := "%s::%s" % [path.trim_prefix(TEST_ROOT + "/"), method_name]
			if problems.is_empty():
				passed += 1
				print("PASS %s" % label)
			else:
				failed += 1
				print("FAIL %s" % label)
				for p in problems:
					print("     %s" % p)

	OS.remove_logger(catcher)
	print("\n%d passed, %d failed" % [passed, failed])
	if passed + failed == 0:
		print("no tests found under %s" % TEST_ROOT)
		quit(1)
		return
	quit(1 if failed > 0 else 0)


func _find_test_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			out.append_array(_find_test_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			out.append(dir_path.path_join(file))
	return out
