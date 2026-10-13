class_name NoticeMedallion
extends Control
## UX-6 (design/UX_WAR_TABLE.md §1.3, §5.2): one round image medallion in the notification stack, and the same image on the head of its
## card. Alex 10-10: "each one of these should have its own image associated with it". The medallion shows its announcement type's painted
## art (NoticeArt, assets/ui/notices/<image>.png, UX-ART) or, until it exists, the kind's icon on a coloured disc. Hover shows the headline
## and detail; a click opens its card in the Chronicle; a right-click dismisses it. A gilt ring says it is unread, a pin glyph that it is
## pinned, and a + or - mark the outcome (colour is never the only channel).
##
## An interactive medallion (the stack's) takes the mouse; a decorative one (a card's head) ignores it.

signal open_requested(id: String)
signal dismiss_requested(id: String)

const SIZE_STACK := 52.0
const SIZE_STACK_COMPACT := 46.0
const SIZE_CARD := 44.0

var id := ""
var image := ""
var kind := ""
var unread := false
var pinned := false
var interactive := true
var _hover := false
var _art_px := 0
var _art: Texture2D = null


func _init(item: Dictionary = {}, px: float = SIZE_STACK, is_interactive: bool = true) -> void:
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	interactive = is_interactive
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if interactive:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _set_hover(true))
		mouse_exited.connect(func(): _set_hover(false))
	if not item.is_empty():
		show_item(item)


## Shows an announcement: its image, its tooltip. `unread` and `pinned` are set by the caller.
func show_item(item: Dictionary) -> void:
	id = String(item.get("id", ""))
	image = String(item.get("image", ""))
	kind = String(item.get("kind", ""))
	_art = null
	_art_px = 0
	if interactive:
		tooltip_text = TooltipText.plain(String(item.get("headline", "")), "%s\n\nClick to read it in the Chronicle. Right-click to dismiss it." % String(item.get("detail", "")))
	name = "Notice_%s" % id.validate_node_name()
	queue_redraw()


func set_flags(is_unread: bool, is_pinned: bool) -> void:
	if is_unread == unread and is_pinned == pinned:
		return
	unread = is_unread
	pinned = is_pinned
	queue_redraw()


## True when painted art stands in for the placeholder disc.
func has_art() -> bool:
	return not NoticeArt.path_for(image, kind).is_empty()


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var b := event as InputEventMouseButton
	if b == null or not b.pressed:
		return
	if b.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		open_requested.emit(id)
	elif b.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		dismiss_requested.emit(id)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.5
	var c := size * 0.5
	var info := ChronicleModel.image_info(image)
	var tone := String(info.get("tone", ""))
	draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.35))  # a soft shadow
	draw_circle(c, r, NoticeArt.disc(kind))
	var px := int(r * 2.0)
	if _art == null or _art_px != px:
		_art = NoticeArt.texture(image, kind, px)
		_art_px = px
	if _art != null:
		draw_texture_rect(_art, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	else:
		_draw_icon(String(info.get("icon", ChronicleModel.KIND_ICONS.get(kind, "chronicle"))), c, r)
	var ring := UiPalette.GILT if unread else (Color.WHITE if _hover else UiPalette.PANEL_BORDER.lightened(0.25))
	draw_arc(c, r, 0.0, TAU, 56, ring, 3.0 if (unread or _hover) else 2.0, true)
	if tone != "":
		_draw_outcome(tone, c, r)
	if pinned:
		var pin_c := Vector2(c.x + r * 0.72, c.y - r * 0.72)
		draw_circle(pin_c, 8.5, UiPalette.PANEL_BG)
		draw_arc(pin_c, 8.5, 0.0, TAU, 20, UiPalette.GILT, 1.5, true)
		var tex := UiIcons.icon("pin", 12)
		draw_texture_rect(tex, Rect2(pin_c - Vector2(6, 6), Vector2(12, 12)), false, UiPalette.GILT)


## The kind's icon in the middle of the disc, cream on the dark colour.
func _draw_icon(icon_name: String, c: Vector2, r: float) -> void:
	var s := r * 1.05
	var tex := NoticeArt.icon(icon_name, int(s * 1.3))
	var half := Vector2(s, s) * 0.65
	draw_texture_rect(tex, Rect2(c - half, half * 2.0), false, UiPalette.TEXT_PRIMARY)


## A small + (good) or - (bad) disc at the lower right: the outcome without colour.
func _draw_outcome(tone: String, c: Vector2, r: float) -> void:
	var o := Vector2(c.x + r * 0.7, c.y + r * 0.7)
	var col := NoticeArt.ring(tone)
	draw_circle(o, 8.5, UiPalette.PANEL_BG)
	draw_arc(o, 8.5, 0.0, TAU, 20, col, 1.8, true)
	draw_line(o + Vector2(-4, 0), o + Vector2(4, 0), col, 2.0, true)
	if tone == "good":
		draw_line(o + Vector2(0, -4), o + Vector2(0, 4), col, 2.0, true)
