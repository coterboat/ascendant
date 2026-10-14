class_name NoticeStack
extends VBoxContainer
## UX-6 (design/UX_WAR_TABLE.md §1.3, §5.2): the notification stack down the left edge, under the system row: one round image medallion
## per announcement (NoticeMedallion), in the order the Chronicle's list has (importance by default), newest news on top. Hover shows a
## medallion's headline; a click opens its card in the Chronicle; a right-click dismisses it. A "Hide" button folds the stack away to a
## small "Notices" button with the count, and back. Below 1600 logical width at most six medallions show, then "+N", which opens the
## Chronicle. Only the stack's own controls take the mouse (the Table lists it among its pieces); the slot around it ignores it, so the
## board keeps its picking everywhere else.
##
## The stack only draws what the Chronicle (ChronicleHud) hands it: it holds no game facts of its own.

signal open_requested(id: String)
signal dismiss_requested(id: String)
signal more_requested
signal fold_toggled(shown: bool)

const WIDTH := 64.0
const GAP := 6.0
const MAX_COMPACT := 6
## The height the toggle and the "+N" button take, so the capacity is what is left.
const CONTROL_H := 26.0

var toggle: Button
var more: Button
var shown := true
var medallions: Array[NoticeMedallion] = []
## Everything the stack was last told: how many medallions it could show, and how many the list held.
var capacity := 0
var total := 0
var _notable: Array = []


func _init() -> void:
	name = "NoticeStack"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_constant_override("separation", int(GAP))
	custom_minimum_size = Vector2(WIDTH, 0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(8, 4)
	toggle = Button.new()
	toggle.name = "FoldButton"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(WIDTH, CONTROL_H)
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.pressed.connect(_on_toggle)
	add_child(toggle)
	more = Button.new()
	more.name = "MoreButton"
	more.focus_mode = Control.FOCUS_NONE
	more.custom_minimum_size = Vector2(WIDTH, CONTROL_H)
	more.add_theme_font_size_override("font_size", 15)
	more.pressed.connect(more_requested.emit)
	add_child(more)
	visible = false


## How many medallions fit in `height` pixels (the slot's), at most MAX_COMPACT when `compact`.
static func capacity_for(height: float, compact: bool) -> int:
	var each := (NoticeMedallion.SIZE_STACK_COMPACT if compact else NoticeMedallion.SIZE_STACK) + GAP
	var room := height - 8.0 - 2.0 * (CONTROL_H + GAP)
	var n := maxi(int(floor(room / each)), 0)
	return mini(n, MAX_COMPACT) if compact else n


## Rebuilds the stack. `items` are the notable announcements in list order; `flags` maps an id to {"unread", "pinned"}; `room` is how many
## medallions fit; `folded` is the player's choice (the Notices button only).
func show_items(items: Array, flags: Dictionary, room: int, compact: bool, is_shown: bool) -> void:
	_notable = items
	total = items.size()
	capacity = room
	shown = is_shown
	for m in medallions:
		remove_child(m)
		m.queue_free()
	medallions.clear()
	visible = total > 0
	if total == 0:
		return
	var px := NoticeMedallion.SIZE_STACK_COMPACT if compact else NoticeMedallion.SIZE_STACK
	var unread := 0
	for it in items:
		if bool(flags.get(String(it.id), {}).get("unread", false)):
			unread += 1
	if shown:
		toggle.text = "Hide"
		toggle.tooltip_text = TooltipText.plain("Hide the notices", "Fold the medallions away. They stay in the Chronicle (the Chronicle button in the system row), and a small Notices button brings them back.")
		var n := mini(total, maxi(room, 1))
		for i in n:
			var it: Dictionary = items[i]
			var m := NoticeMedallion.new(it, px, true)
			m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			m.set_flags(bool(flags.get(String(it.id), {}).get("unread", false)), bool(flags.get(String(it.id), {}).get("pinned", false)))
			m.open_requested.connect(open_requested.emit)
			m.dismiss_requested.connect(dismiss_requested.emit)
			add_child(m)
			move_child(m, 1 + i)
			medallions.append(m)
		more.visible = total > n
		more.text = "+%d" % (total - n)
		more.tooltip_text = TooltipText.plain("More notices", "%s more. Open the Chronicle to read them all, sort them and filter them." % TooltipText.count(total - n, "notice"))
	else:
		toggle.text = "Notices" if unread == 0 else "Notices %d" % unread
		toggle.tooltip_text = TooltipText.plain("Show the notices", "%s waiting. Click to show the medallions again." % TooltipText.count(total, "notice"))
		more.visible = false
	reset_size()


func _on_toggle() -> void:
	shown = not shown
	fold_toggled.emit(shown)


## The medallion for an announcement id (tests, the live probe), or null.
func medallion(id: String) -> NoticeMedallion:
	for m in medallions:
		if m.id == id:
			return m
	return null
