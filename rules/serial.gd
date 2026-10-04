class_name Serial
## Helpers that keep serialized game data exact through a JSON round-trip.
## JSON has only one number type (a double), so after JSON.stringify + JSON.parse_string every int
## comes back as a float, and 64-bit values (seeds, RNG state) lose precision above 2^53.
## Rules: to_dict() stores 64-bit values as decimal strings (int64_to_str), and every from_dict()
## reads numbers back through to_int(), which accepts ints, floats and numeric strings.
##
## Load checks (#49): a from_dict() checks the type of every list, group, text and true/false field
## before using it (expect, expect_dicts, check), so data with a field of the wrong type (hand-edited,
## corrupted, or written by a tool) fails to load with a plain-language reason, never a script error:
##   "The 'units' field of army 'kingdom-1' should be a list, but the saved data has text there."
## The loader then returns null. A missing or null field still means its default, and numbers stay
## lenient (to_int).

## How load errors name a value's type.
const TYPE_WORDS := {TYPE_NIL: "nothing", TYPE_BOOL: "true or false", TYPE_INT: "a number", TYPE_FLOAT: "a number",
	TYPE_STRING: "text", TYPE_STRING_NAME: "text", TYPE_ARRAY: "a list", TYPE_DICTIONARY: "a group of named values"}


## Reads an int from a dict value that may be an int, a float (after JSON) or a numeric string.
static func to_int(value: Variant, default: int = 0) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_BOOL:
			return 1 if value else 0
		TYPE_STRING, TYPE_STRING_NAME:
			var text := String(value)
			if text.is_valid_int():
				return text.to_int()
	return default


## Stores a full-range 64-bit int as a string so JSON can't round it.
static func int64_to_str(value: int) -> String:
	return str(value)


## Reads a list of strings (for example province neighbors) from a dict value.
static func to_string_array(value: Variant) -> Array:
	var out := []
	if value is Array:
		for v in value:
			out.append(str(v))
	return out


# --- load checks (#49) ----------------------------------------------------------------------------

## True when `value` has `type` (TYPE_STRING also takes a StringName). Otherwise reports "<what> should
## be a list, but the saved data has text there." and returns false. `what` names the value in plain
## words, e.g. "unit 2 of army 'kingdom-1'" or "the replay".
static func check(value: Variant, type: int, errors, what: String) -> bool:
	var actual := typeof(value)
	if actual == type or (type == TYPE_STRING and actual == TYPE_STRING_NAME):
		return true
	report(errors, "%s should be %s, but the saved data has %s there." % [cap(what), _type_words(type), _type_words(actual)])
	return false


## Reads data[key] for a from_dict(): `default` when the key is missing or null, the value when it has
## `type`, and null when it has another type, after reporting "The 'units' field of army 'kingdom-1'
## should be a list, but the saved data has text there." (`who` names whose field it is). Pass a
## default that is not null, so null always means "stop loading".
static func expect(data: Dictionary, key: String, type: int, errors, who: String, default: Variant) -> Variant:
	var value = data.get(key)
	if value == null:
		return default
	return value if check(value, type, errors, "the '%s' field of %s" % [key, who]) else null


## Reads data[key] as a list of groups of named values (provinces, armies, units, ...): [] when it is
## missing, null after a report when it is not a list or one of its entries is not a group, e.g.
## "Unit 2 of army 'kingdom-1' should be a group of named values, but the saved data has text there."
## (`entry` "unit", `who` "army 'kingdom-1'").
static func expect_dicts(data: Dictionary, key: String, errors, who: String, entry: String) -> Variant:
	var list = expect(data, key, TYPE_ARRAY, errors, who, [])
	if list == null:
		return null
	for i in list.size():
		if not check(list[i], TYPE_DICTIONARY, errors, "%s %d of %s" % [entry, i + 1, who]):
			return null
	return list


## How load errors name an entry of a list: "army 'kingdom-1'" by its id when it has one, otherwise
## "army number 3" by its place in the list (`index` 2), or "the army" when that isn't known either.
static func label(kind: String, data: Dictionary, index: int = -1) -> String:
	var id = data.get("id")
	if (id is String or id is StringName) and not String(id).is_empty():
		return "%s '%s'" % [kind, id]
	return "%s number %d" % [kind, index + 1] if index >= 0 else "the %s" % kind


## Appends `msg` to `errors` when it is an Array, otherwise push_error: the loaders' convention.
static func report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)


## `text` with its first letter capitalised, to start a sentence with a label ("The army ...").
static func cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _type_words(type: int) -> String:
	return TYPE_WORDS.get(type, "a value of the wrong kind")
