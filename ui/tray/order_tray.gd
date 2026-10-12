class_name OrderTray
extends HBoxContainer
## UX-4 (design/UX_WAR_TABLE.md §3.4, issue #213): the orders in the tray along the bottom of the Table. One token for each queued order,
## the placed orders first in their numbered order (march, recruit, fortify, storm or siege, ritual, muster) and then the realm orders
## (research, spellbook, mandate) as icon tokens with no number; the gold the orders leave ends the tray. It fills TableHud's tray slot
## (tray_slot()).
##
## A token's hover is its order's sentence and breakdown; a click asks the map screen to focus its place and open its card (Change and
## Cancel); its cross, or a right-click, cancels it. Past seven tokens the strip scrolls sideways (the wheel, or its bar). Below 1600
## logical width (the compact Table) a token shows its number or icon only and the words are in the tooltip. While the tray is empty the
## tray's one line of "what to do now" shows in its place (TableHud.hint_label) and the gold line is hidden.
##
## It holds no rules: it reads the viewing faction's OrdersController (OrderMarks) and tells its host what was clicked (order_pressed,
## order_cancelled), which goes back through the map screen's order API. It is rebuilt by refresh() whenever the orders change, so the
## numbers always re-flow from the list.

## A token was clicked (its index in orders()): the host focuses its place and opens its card.
signal order_pressed(index: int)
## A token's cross was pressed or it was right-clicked (its index in orders()).
signal order_cancelled(index: int)
## The tray holds this many tokens now (the host shows the hint line while it is none).
signal changed(count: int)

## How many tokens show at once; past it the strip scrolls sideways.
const VISIBLE_TOKENS := 7
const GAP := 6
const GOLD_PX := 16
## The room the sideways scroll bar takes under the tokens when there are more than fit.
const SCROLL_BAR_H := 10.0

var scroll: ScrollContainer
var strip: HBoxContainer
var gold_box: HBoxContainer
var gold_icon: TextureRect
var gold_label: Label
var compact := false
## The host's codex opener (MapScreen.request_codex): the gold line's right-click.
var codex_opener := Callable()

var _controller: OrdersController = null
var _tokens: Array = []
var _last_count := 0
var _divider: Control = null
var _fit_queued := false


func _init() -> void:
	name = "OrderTray"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 10)
	scroll = ScrollContainer.new()
	scroll.name = "TokenScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.visible = false
	add_child(scroll)
	strip = HBoxContainer.new()
	strip.name = "Tokens"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_constant_override("separation", GAP)
	strip.minimum_size_changed.connect(_queue_fit)  # the tokens' real sizes are known once the tray is in the tree: fit again then
	scroll.add_child(strip)
	gold_box = HBoxContainer.new()
	gold_box.name = "GoldAfter"
	gold_box.mouse_filter = Control.MOUSE_FILTER_PASS
	gold_box.add_theme_constant_override("separation", 4)
	gold_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_box.visible = false
	add_child(gold_box)
	gold_icon = TextureRect.new()
	gold_icon.name = "GoldIcon"
	gold_icon.texture = UiIcons.icon("gold", GOLD_PX)
	gold_icon.self_modulate = UiPalette.GILT
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	gold_icon.custom_minimum_size = Vector2(GOLD_PX, GOLD_PX)
	gold_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_box.add_child(gold_icon)
	gold_label = Label.new()
	gold_label.name = "GoldAfterLabel"
	gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_label.add_theme_font_override("font", UiFonts.number())
	gold_label.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	gold_label.add_theme_color_override("font_color", UiPalette.GILT)
	gold_box.add_child(gold_label)


# --- API ------------------------------------------------------------------------------------------

## Rebuilds the tokens from `c`'s orders (the viewing faction's own; null or none gives an empty tray).
func refresh(c: OrdersController) -> void:
	_controller = c
	var keep := scroll.scroll_horizontal
	for t in _tokens:
		strip.remove_child(t)
		t.queue_free()
	_tokens.clear()
	if _divider != null:
		strip.remove_child(_divider)
		_divider.queue_free()
		_divider = null
	var all := OrderMarks.marks(c)
	var placed := all.filter(func(m): return not bool(m.realm))
	var realm := all.filter(func(m): return bool(m.realm))
	for m in placed:
		_add_token(m, c)
	if not placed.is_empty() and not realm.is_empty():
		_divider = VSeparator.new()
		_divider.name = "RealmDivider"
		_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(_divider)
	for m in realm:
		_add_token(m, c)
	_refresh_gold(c)
	scroll.visible = not _tokens.is_empty()
	_fit()
	scroll.scroll_horizontal = keep
	if all.size() > _last_count and not placed.is_empty() and all.size() > VISIBLE_TOKENS:
		_show_newest.call_deferred()
	var count := _tokens.size()
	_last_count = count
	changed.emit(count)


## The tokens now, placed ones by number and then the realm ones.
func tokens() -> Array:
	return _tokens.duplicate()


## The token of the order at `index` in orders(), or null.
func token_for(index: int) -> OrderToken:
	for t in _tokens:
		if (t as OrderToken).indices.has(index):
			return t
	return null


## How many tokens show without scrolling (VISIBLE_TOKENS at most).
func visible_tokens() -> int:
	return mini(_tokens.size(), VISIBLE_TOKENS)


## True when the strip has more tokens than fit and scrolls sideways.
func scrolls() -> bool:
	return _tokens.size() > VISIBLE_TOKENS


## The Table crossed 1600 logical width (TableHud.compact_changed).
func set_compact(on: bool) -> void:
	if on == compact:
		return
	compact = on
	for t in _tokens:
		(t as OrderToken).set_compact(on)
	_refresh_gold(_controller)
	_fit()


# --- internals ------------------------------------------------------------------------------------

func _add_token(m: Dictionary, c: OrdersController) -> void:
	var t := OrderToken.make(m, c, OrderToken.Look.TRAY, compact)
	t.pressed.connect(func(i: int): order_pressed.emit(i))
	t.cancel_requested.connect(func(i: int): order_cancelled.emit(i))
	strip.add_child(t)
	_tokens.append(t)


## The gold the orders leave: shown while an order is paid from gold (a recruit, a fortify, a ritual), with its breakdown.
func _refresh_gold(c: OrdersController) -> void:
	var paid := c != null and c.state != null and (not c.paid_orders().is_empty() or c.orders().any(func(o): return o is CastOrder))
	gold_box.visible = paid
	if not paid:
		return
	var g := c.gold_after_recruits()
	gold_label.text = str(int(g.gold_after)) if compact else "%d left" % int(g.gold_after)
	var title := "Gold after recruits and rituals" if int(g.get("rituals", 0)) > 0 else "Gold after recruits"
	gold_box.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(c.gold_breakdown()),
		TooltipText.wrap_text("%s: %d now, %d after your orders. The tray's orders are paid in the order given." % [title, int(g.gold_now), int(g.gold_after)])]
	CodexLink.attach(gold_box, TooltipText.codex_for("gold_after_recruits"), func(key): _open_codex(key))


## Sizes the scroll to the first VISIBLE_TOKENS tokens: all of them up to seven, so a short list never scrolls and a long one shows seven.
func _fit() -> void:
	if _tokens.is_empty():
		scroll.custom_minimum_size = Vector2.ZERO
		return
	var width := 0.0
	var height := 0.0
	var shown := 0
	for child in strip.get_children():
		if child == _divider:
			if shown < VISIBLE_TOKENS:
				width += GAP + (child as Control).get_combined_minimum_size().x
			continue
		if shown >= VISIBLE_TOKENS:
			break
		width += (child as Control).get_combined_minimum_size().x + (GAP if shown > 0 else 0)
		height = maxf(height, (child as Control).get_combined_minimum_size().y)
		shown += 1
	var scrolling := _tokens.size() > VISIBLE_TOKENS
	scroll.custom_minimum_size = Vector2(ceilf(width), ceilf(height) + (SCROLL_BAR_H if scrolling else 0.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if scrolling else ScrollContainer.SCROLL_MODE_DISABLED


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_run_fit.call_deferred()


func _run_fit() -> void:
	_fit_queued = false
	if is_instance_valid(scroll):
		_fit()


func _show_newest() -> void:
	if not is_instance_valid(scroll) or _tokens.is_empty():
		return
	var newest := -1
	for t in _tokens:
		if not bool((t as OrderToken).mark.get("realm", false)):
			newest = _tokens.find(t)
	if newest >= 0:
		scroll.ensure_control_visible(_tokens[newest])


func _open_codex(key: String) -> void:
	if codex_opener.is_valid():
		codex_opener.call(key)
