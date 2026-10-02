class_name Serial
## Helpers that keep serialized game data exact through a JSON round-trip.
## JSON has only one number type (a double), so after JSON.stringify + JSON.parse_string every int
## comes back as a float, and 64-bit values (seeds, RNG state) lose precision above 2^53.
## Rules: to_dict() stores 64-bit values as decimal strings (int64_to_str), and every from_dict()
## reads numbers back through to_int(), which accepts ints, floats and numeric strings.


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
