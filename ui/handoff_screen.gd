class_name HandoffScreen
extends Control
## Full-screen opaque cover shown between hotseat players (#7). It hides the board and the previous
## player's orders, names who should take the computer next, and waits for "Ready".
## Reads the session only; the one rules call it makes is GameSession.acknowledge_handoff() when the
## player presses Ready. Builds its children in code so it works outside the scene tree (tests).
## M5-2: Ready emits `uncovering` while the cover is still up (the host rebuilds the next seat's screen then), and
## `acknowledged` once it is down; under fog the cover says each player sees only their own view.

## M5-2 (§2.9): Ready was pressed and accepted, and the cover is still up: the host rebuilds the next seat's screen now.
## `acknowledged` follows once the cover is down.
signal uncovering
signal acknowledged

const BACKGROUND := Color(0.06, 0.07, 0.09, 1.0)

var session: GameSession = null
## M5-2: a fog game (the host sets it before show_for): the cover adds the fog line, FogView.COVER_LINE.
var fog := false
var title_label: Label
var turn_label: Label
var body_label: Label
var hint_label: Label
var error_label: Label
var ready_button: Button


func _init() -> void:
	name = "HandoffScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # swallow every click so nothing underneath can be used
	z_index = 100
	visible = false
	_build()


## Shows the cover for the session's current handoff. Returns false (and stays hidden) outside HANDOFF.
func show_for(game_session: GameSession) -> bool:
	session = game_session
	error_label.text = ""
	if session == null or session.phase() != GameSession.Phase.HANDOFF:
		visible = false
		return false
	var info := session.handoff_info()
	title_label.text = "Pass to %s" % info.get("faction_name", "the next player")
	turn_label.text = "Turn %d  ·  Player %d" % [session.turn_number(), info.get("seat", 0)]
	body_label.text = session.handoff_text()
	hint_label.text = "%s\n\n%s" % [FogView.COVER_LINE, RulesCodex.text("handoff")] if fog else RulesCodex.text("handoff")
	visible = true
	if is_inside_tree():
		ready_button.grab_focus.call_deferred()
	return true


func _on_ready_pressed() -> void:
	if session == null:
		return
	var why := session.acknowledge_handoff()
	if not why.is_empty():
		error_label.text = why
		return
	uncovering.emit()
	visible = false
	acknowledged.emit()


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(720, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	turn_label = _label("TurnLabel", 22, Color(0.75, 0.78, 0.85))
	box.add_child(turn_label)
	title_label = _label("TitleLabel", 48, Color(1, 1, 1))
	box.add_child(title_label)
	body_label = _label("BodyLabel", 22, Color(0.9, 0.9, 0.9))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body_label)
	hint_label = _label("HintLabel", 18, Color(0.65, 0.68, 0.75))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.text = RulesCodex.text("handoff")
	box.add_child(hint_label)

	ready_button = Button.new()
	ready_button.name = "ReadyButton"
	ready_button.text = "Ready"
	ready_button.custom_minimum_size = Vector2(240, 64)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ready_button.add_theme_font_size_override("font_size", 28)
	ready_button.tooltip_text = "Press when you have the computer and nobody else can see the screen."
	ready_button.pressed.connect(_on_ready_pressed)
	box.add_child(ready_button)

	error_label = _label("ErrorLabel", 18, Color(1.0, 0.55, 0.5))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(error_label)


func _label(node_name: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
