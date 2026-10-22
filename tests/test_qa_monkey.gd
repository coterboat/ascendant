extends "res://tests/test_case.gd"
## QA-1 (#250): the monkey's events.log reads back what it wrote (tools/qa/monkey_log.gd). The first draft's replay looked for
## "# options" while the run wrote "# f=2 options", so a replay never found its seed. The monkey itself never runs in the tests (it
## needs a window); its log format does.

const MonkeyLog := preload("res://tools/qa/monkey_log.gd")


func _motion(p: Vector2, held: int) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = held
	return m


func test_every_event_kind_reads_back_as_it_was_sent() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.double_click = true
	press.position = Vector2(132.7, 676.1)
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(10, 20)
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	key.echo = true
	key.unicode = "a".unicode_at(0)
	for e in [_motion(Vector2(970.0, 856.0), 0), _motion(Vector2(157.5, 694.7), MOUSE_BUTTON_MASK_LEFT), press, wheel, key]:
		var line := MonkeyLog.event_line(3689, e, "click button Button \"Split\"", "GameScreen>ArmyCard>MusterBoard")
		var back := MonkeyLog.parse_event_line(line)
		assert_eq(int(back.get("frame", -1)), 3689, "the frame of %s" % line)
		assert_eq(String(back.get("what", "")), "click button Button \"Split\"", "what it aimed at, from %s" % line)
		assert_eq(String(back.get("screen", "")), "GameScreen>ArmyCard>MusterBoard", "the screen, from %s" % line)
		var again := MonkeyLog.decode(back.event, Vector2.ZERO)
		assert_true(again != null and again.get_class() == e.get_class(), "%s decodes to a %s" % [line, e.get_class()])
		assert_eq(MonkeyLog.encode(again), MonkeyLog.encode(e), "%s sends the same event again" % line)


func test_an_event_with_nothing_aimed_at_keeps_its_screen() -> void:
	var back := MonkeyLog.parse_event_line(MonkeyLog.event_line(7, _motion(Vector2(1, 2), 0), "", "GameScreen"))
	assert_eq(String(back.what), "", "a step of a travel aims at nothing")
	assert_eq(String(back.screen), "GameScreen", "and still names its screen")


func test_notes_are_never_read_as_events() -> void:
	for line in [MonkeyLog.note_line(2, "options {\"seed\":7}"), "# f=3688 HOVER-FREED: Godot holds Label", "", "garbage"]:
		assert_true(MonkeyLog.parse_event_line(line).is_empty(), "%s is not an event" % line)


func test_the_replay_finds_the_options_the_run_wrote() -> void:
	var opts := {"seed": 7, "ui_scale": 125, "fog": false, "human": "beasts", "window": [1280, 720]}
	var lines := PackedStringArray([MonkeyLog.note_line(2, "the window moved off the real cursor, to (712, 736)"),
		MonkeyLog.note_line(2, "options " + JSON.stringify(opts)), MonkeyLog.note_line(6, "config {\"seed\":683407369}")])
	var read := MonkeyLog.note_json(lines, "options")
	assert_eq(int(read.get("seed", 0)), 7, "the options note gives back the seed")
	assert_eq(int(read.get("ui_scale", 0)), 125, "the interface size")
	assert_eq(bool(read.get("fog", true)), false, "fog")
	assert_eq(String(read.get("human", "")), "beasts", "the faction")
	assert_eq(Array(read.get("window", [])).map(func(v): return int(v)), [1280, 720], "the window")
	assert_eq(int(MonkeyLog.note_json(lines, "config").get("seed", 0)), 683407369, "and the config note its game seed")
	# the first draft wrote its options without a frame: still read
	assert_eq(int(MonkeyLog.note_json(PackedStringArray(["# options {\"seed\":3}"]), "options").get("seed", 0)), 3, "an old log's options")
	assert_true(MonkeyLog.note_json(PackedStringArray(["1\t{}\t  @ x"]), "options").is_empty(), "no options note, no options")


func test_window_sizes_parse() -> void:
	assert_eq(MonkeyLog.parse_size("1280x720"), Vector2i(1280, 720), "1280x720")
	assert_eq(MonkeyLog.parse_size("1600X900"), Vector2i(1600, 900), "upper-case X")
	assert_eq(MonkeyLog.parse_size("big"), Vector2i.ZERO, "not a size")
