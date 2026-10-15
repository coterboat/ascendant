class_name ScrollMore
extends Control
## UI-FIT (#237): the cue over the bottom of a scroll while more of it is below the edge. A fade, so the line the edge cuts reads as
## going on rather than clipped, and "▾ More" at the bottom right: click it to scroll on by most of what shows (the wheel and two
## fingers on a trackpad scroll too, and its tooltip says so). It shows only while there is more below, and takes no click but its
## button's, so what is under the fade still takes hovers and clicks.
## Over the selection card's scroll (SelectionCards) and the build screen's columns (BuildScreen), the two the UX-9 walk found cut
## with nothing to say there was more.
##
##   ScrollMore.frame(scroll, bg) -> MarginContainer   the scroll in a frame with the cue over it: add the frame where the scroll went
##   has_more_below() -> bool, scroll_on()

## How tall the fade is over the scroll's bottom edge.
const FADE_H := 40.0
## The fade keeps clear of the scroll bar on the right.
const BAR_W := 12.0

var scroll: ScrollContainer
var button: Button
var bg := UiPalette.PANEL_BG


## `scroll` in a frame (a MarginContainer that sizes like it) with its cue over it; `bg` is what the fade fades into, the colour
## behind the scroll.
static func frame(target: ScrollContainer, background: Color = UiPalette.PANEL_BG) -> MarginContainer:
	var f := MarginContainer.new()
	f.name = "%sFrame" % target.name
	f.size_flags_horizontal = target.size_flags_horizontal
	f.size_flags_vertical = target.size_flags_vertical
	f.size_flags_stretch_ratio = target.size_flags_stretch_ratio
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if target.get_parent() != null:
		target.get_parent().remove_child(target)
	f.add_child(target)
	var cue := ScrollMore.new()
	cue.scroll = target
	cue.bg = background
	cue._build()
	f.add_child(cue)
	return f


func _build() -> void:
	name = "MoreCue"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	button = Button.new()
	button.name = "MoreButton"
	button.text = "▾ More"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UiPalette.TYPE_FLOOR)
	button.add_theme_color_override("font_color", UiPalette.GILT)
	button.add_theme_color_override("font_hover_color", UiPalette.TEXT_PRIMARY)
	button.tooltip_text = TooltipText.plain("More below", "There is more below. Scroll (the wheel, or two fingers on a trackpad), or click here to see the next part.")
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_right = -BAR_W - 2.0
	button.pressed.connect(scroll_on)
	add_child(button)
	var bar := scroll.get_v_scroll_bar()
	bar.value_changed.connect(func(_v: float): refresh())
	bar.changed.connect(refresh)
	resized.connect(queue_redraw)


## True while more of the scroll is below its bottom edge.
func has_more_below() -> bool:
	var bar := scroll.get_v_scroll_bar()
	return bar.max_value - bar.page - bar.value > 2.0


## "More": scrolls on by what shows less the fade, so the line the edge cut is near the top.
func scroll_on() -> void:
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(minf(bar.value + maxf(bar.page - FADE_H, FADE_H), bar.max_value - bar.page))


## Shows the cue while there is more below (the scroll's bar says when its range or place changes).
func refresh() -> void:
	visible = has_more_below()


func _draw() -> void:
	var h := minf(FADE_H, size.y)
	var r := Rect2(0, size.y - h, maxf(size.x - BAR_W, 0.0), h)
	var clear := Color(bg, 0.0)
	var solid := Color(bg, 0.97)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([clear, clear, solid, solid]))
