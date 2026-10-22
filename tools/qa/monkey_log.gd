extends RefCounted
## QA-1 (#250): the monkey's events.log, written and read in one place, so a replay always reads what a run wrote (the first draft's
## replay looked for "# options" while the run wrote "# f=2 options"). Pure: no scene tree; tests/test_qa_monkey.gd checks that every
## line it writes reads back.
##
## The log is one line per input event and `#` lines for notes:
##   <frame> TAB <the event as json> TAB <what the hand aimed at, or nothing>  @ <the screen and the panels up>
##   # f=<frame> <note>                      (the options, the game's config, turns, errors, slow frames, shots, STUCK, the end)
## <frame> counts from the moment the board was ready (frame 0), so a replay sends each event on the same frame of the game.

const SEP := "  @ "  # between what the hand aimed at and the screen it was on


## One input event as the log's json: mouse motion ("mm"), a mouse button or the wheel ("mb"), or a key ("key").
static func encode(e: InputEvent) -> Dictionary:
	if e is InputEventMouseMotion:
		return {"k": "mm", "x": snappedf(e.position.x, 0.1), "y": snappedf(e.position.y, 0.1), "m": e.button_mask}
	if e is InputEventMouseButton:
		return {"k": "mb", "b": e.button_index, "p": int(e.pressed), "d": int(e.double_click), "x": snappedf(e.position.x, 0.1),
			"y": snappedf(e.position.y, 0.1), "m": e.button_mask}
	var ke := e as InputEventKey
	if ke == null:
		return {}
	return {"k": "key", "c": ke.keycode, "p": int(ke.pressed), "e": int(ke.echo), "u": ke.unicode}


## The event `d` (encode's json) again, ready for Input.parse_input_event. `from` is where the pointer was before it (a motion's
## relative). Null for anything else.
static func decode(d: Dictionary, from: Vector2 = Vector2.ZERO) -> InputEvent:
	match String(d.get("k", "")):
		"mm":
			var m := InputEventMouseMotion.new()
			var p := Vector2(float(d.x), float(d.y))
			m.position = p
			m.global_position = p
			m.relative = p - from
			m.velocity = (p - from) * 60.0
			m.button_mask = int(d.m)
			return m
		"mb":
			var b := InputEventMouseButton.new()
			b.button_index = int(d.b) as MouseButton
			b.pressed = bool(d.p)
			b.double_click = bool(d.d)
			b.position = Vector2(float(d.x), float(d.y))
			b.global_position = b.position
			b.button_mask = int(d.m)
			b.factor = 1.0
			return b
		"key":
			var k := InputEventKey.new()
			k.keycode = int(d.c) as Key
			k.physical_keycode = int(d.c) as Key
			k.pressed = bool(d.p)
			k.echo = bool(d.get("e", 0))
			k.unicode = int(d.get("u", 0))
			return k
	return null


## Where a mouse event leaves the pointer, or `from` for a key.
static func pointer_after(d: Dictionary, from: Vector2) -> Vector2:
	return Vector2(float(d.x), float(d.y)) if d.has("x") else from


static func event_line(frame: int, e: InputEvent, what: String, screen: String) -> String:
	return "%d\t%s\t%s%s%s" % [frame, JSON.stringify(encode(e)), what.replace("\t", " ").replace("\n", " "), SEP, screen]


static func note_line(frame: int, text: String) -> String:
	return "# f=%d %s" % [frame, text.replace("\n", " | ")]


## An event line back: {"frame", "event" (encode's json), "what", "screen"}, or {} for a note or anything else.
static func parse_event_line(line: String) -> Dictionary:
	if line.is_empty() or line.begins_with("#"):
		return {}
	var parts := line.split("\t", true, 2)
	if parts.size() < 2 or not parts[0].is_valid_int():
		return {}
	var d = JSON.parse_string(parts[1])
	if not (d is Dictionary):
		return {}
	var rest := parts[2] if parts.size() > 2 else ""
	var at := rest.find(SEP)
	return {"frame": int(parts[0]), "event": d, "what": rest if at < 0 else rest.substr(0, at),
		"screen": "" if at < 0 else rest.substr(at + SEP.length())}


## A note line back: {"frame", "text"}, or {} for an event line. Reads the old draft's "# options ..." (no frame) as frame -1.
static func parse_note_line(line: String) -> Dictionary:
	if not line.begins_with("# "):
		return {}
	var body := line.substr(2)
	if body.begins_with("f="):
		var sp := body.find(" ")
		var f := body.substr(2, sp - 2) if sp > 0 else body.substr(2)
		if f.is_valid_int():
			return {"frame": int(f), "text": body.substr(sp + 1) if sp > 0 else ""}
	return {"frame": -1, "text": body}


## The json of the first note that starts with `key` ("options", "config"), from the log's lines, or {}.
static func note_json(lines: PackedStringArray, key: String) -> Dictionary:
	for line in lines:
		var n := parse_note_line(line)
		if n.is_empty() or not String(n.text).begins_with(key + " {"):
			continue
		var d = JSON.parse_string(String(n.text).substr(key.length() + 1))
		return d if d is Dictionary else {}
	return {}


## The log's first lines (its header: the options and config notes come first), at most `n`.
static func head(path: String, n: int = 40) -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached() and out.size() < n:
		out.append(f.get_line())
	return out


## "1600x900" -> Vector2i(1600, 900); Vector2i.ZERO when it isn't one.
static func parse_size(s: String) -> Vector2i:
	var wh := s.to_lower().split("x")
	if wh.size() != 2 or not wh[0].is_valid_int() or not wh[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(wh[0]), int(wh[1]))
