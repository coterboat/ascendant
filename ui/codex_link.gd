class_name CodexLink
## Links a number or term on screen to its codex entry (#8: "Terms in tooltips and reports link to
## their entry"). attach() ends the control's tooltip with
##   Codex: Income (right-click or F1 to open)
## stores the entry key in the control's "codex_key" meta, and makes a right-click on the control
## call `open` with the key. F1 while hovering does the same: the screen that hosts the codex
## (GameScreen, or MapScreen in the map preview) asks key_at() about the hovered control.
## Which entry explains which number is decided in TooltipText.CODEX. UI only: no rules here.

const META := "codex_key"
const HINT := "right-click or F1 to open"
const _HOOKED := "codex_link_hooked"


## Links `control` to the RulesCodex entry `key`. Does nothing for a key that is not an entry, so a
## missing entry never produces a dead link (tests check every linked key exists). Call it again after
## changing the tooltip of a control that lives on (the top bar labels): the right-click is hooked up
## once and always opens the control's current key.
static func attach(control: Control, key: String, open: Callable) -> void:
	if control == null or not RulesCodex.ENTRIES.has(key):
		return
	control.set_meta(META, key)
	control.tooltip_text = with_link(control.tooltip_text, key)
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS  # so the tooltip shows and the click arrives
	if control.has_meta(_HOOKED):
		return
	control.set_meta(_HOOKED, true)
	control.gui_input.connect(func(event: InputEvent):
		if is_open_click(event) and control.has_meta(META):
			if control.is_inside_tree():
				control.accept_event()
			open.call(String(control.get_meta(META))))


## Removes the link from a control that lives on (its tooltip is set again by the caller).
static func detach(control: Control) -> void:
	if control != null and control.has_meta(META):
		control.remove_meta(META)


## `tooltip` followed by the line naming the codex entry (replacing a codex line it already ends with).
static func with_link(tooltip: String, key: String) -> String:
	var line := TooltipText.wrap_text("Codex: %s (%s)" % [title(key), HINT])
	var text := tooltip
	var at := text.rfind("Codex: ")
	if at >= 0 and text.ends_with(")") and (at == 0 or text.substr(0, at).ends_with("\n\n")):
		text = text.substr(0, at).strip_edges()
	return line if text.strip_edges().is_empty() else "%s\n\n%s" % [text, line]


## The entry's player-facing title.
static func title(key: String) -> String:
	return String(RulesCodex.entry(key).get("title", ""))


## The codex key of `control` or its nearest linked parent, "" if none (F1 over a linked number).
static func key_at(control: Node) -> String:
	var n := control
	while n != null:
		if n.has_meta(META):
			return String(n.get_meta(META))
		n = n.get_parent()
	return ""


static func is_open_click(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT


static func is_open_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.keycode == KEY_F1


## A right-click, for tests and tools that drive a linked control without a mouse.
static func right_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	return e
