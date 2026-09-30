extends RefCounted
## Base class for tests. Extend it in a file named `test_*.gd` under `tests/`
## and add methods named `test_*`. The runner calls each one on a fresh
## instance; any failed assertion or engine/script error fails that test.

var _failures: PackedStringArray = []


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true" + _suffix(message))


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false" + _suffix(message))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		_fail("expected %s, got %s%s" % [var_to_str(expected), var_to_str(actual), _suffix(message)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		_fail("did not expect %s%s" % [var_to_str(unexpected), _suffix(message)])


func fail(message: String) -> void:
	_fail(message)


func get_failures() -> PackedStringArray:
	return _failures


func _fail(message: String) -> void:
	_failures.append(message)


func _same(a: Variant, b: Variant) -> bool:
	# Loose on int vs float so assert_eq(2, 2.0) passes; strict on everything else.
	if typeof(a) != typeof(b) and not (_is_number(a) and _is_number(b)):
		return false
	return a == b


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _suffix(message: String) -> String:
	return "" if message.is_empty() else " (%s)" % message
