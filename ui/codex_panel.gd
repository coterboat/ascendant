class_name CodexPanel
extends Control
## In-game codex (#8): every RulesCodex entry listed by its player-facing title, searchable, with the
## selected entry's text on the right. Reads RulesCodex only; it holds no rules text of its own.
## Links written as [url=codex:<key>]...[/url] in entry text open that entry. Entries without explicit
## links get one automatic link per other entry whose title (letters and spaces only: Income, Hit
## points, Morale and routs, ...) appears in the text as whole words; a longer title wins an overlap.
## UI-ICONS (#233): a spell's entry (and the blood mandate's) shows its painted icon beside its name in the list and above its
## title on its page, once the icon's file has landed (SpellIcons).
## #272: a page whose key has a plate (Art.codex_plate: assets/concept/codex/<key>.webp) shows it at the top of the page, on a band
## as wide as the page: the plate scaled to the page's width with its aspect kept, no taller than PLATE_MAX_SHARE of the panel
## (a square plate then sits centred on its own parchment). The band's height is set as the page is shown, from the page's width,
## so the title and text are laid out once, below it, with no jump. A page without a plate is laid out exactly as before.
## Esc closes the panel, in one press, even while the search box has focus: the panel takes Esc in
## _input, before the focused search box would use it to stop editing. Hosts need no Esc code of their
## own; the panel only skips Esc when another overlay is open above it among its siblings.

signal closed

const LINK_PREFIX := "codex:"
## #272: the plate's band is at most this share of the panel's height, so a page's text still starts in view under its plate.
const PLATE_MAX_SHARE := 0.34

## UX-1 (§1.4): inside a game, Esc on the codex calls the game's one cancel dispatcher (UiCancel.cancel) instead of closing
## the panel itself, so a stack of panels closes one layer a press. Unset (the new game and build screens): it closes itself.
var cancel_router := Callable()
var _shown_keys: Array[String] = []
var _current := ""
var _bound := false
var _search: LineEdit
var _list: ItemList
var _no_matches: Label
var _title: Label
var _icon: TextureRect  # UI-ICONS: the shown entry's spell icon (hidden when it has none)
var _page: Control  # the right column: the plate, the icon, the title and the text
var _plate: Art.PlateCard  # #272: the shown entry's plate, at the top of the page (hidden when it has none)
var _body: RichTextLabel
var _close: Button


func _ready() -> void:
	_bind()


## Finds the child nodes, wires them and fills the list, once. Runs from _ready, or from the first API
## call when the panel is used before the tree is live (the headless test runner).
func _bind() -> void:
	if _bound:
		return
	_bound = true
	_search = %Search
	_list = %EntryList
	_no_matches = %NoMatches
	_title = %EntryTitle
	_body = %EntryText
	_close = %CloseButton
	_list.fixed_icon_size = Vector2i(22, 22)
	_icon = TextureRect.new()
	_icon.name = "EntryIcon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_icon.custom_minimum_size = Vector2(64, 64)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	_title.get_parent().add_child(_icon)
	_title.get_parent().move_child(_icon, _title.get_index())
	_page = _title.get_parent() as Control
	_plate = Art.PlateCard.new()
	_plate.name = "EntryPlate"
	_plate.visible = false
	_page.add_child(_plate)
	_page.move_child(_plate, 0)
	_page.resized.connect(_fit_plate)
	_search.text_changed.connect(filter)
	_list.item_selected.connect(_on_item_selected)
	_body.meta_clicked.connect(follow_link)
	_close.pressed.connect(close)
	filter("")
	var keys := entry_keys()
	if not keys.is_empty():
		show_entry(keys[0])


## Esc closes the panel. _input runs before the GUI hands the key to the focused control, so the search
## box never takes the first Esc.
func _input(event: InputEvent) -> void:
	handle_cancel(event)


## Closes the panel for Esc (ui_cancel) while it is open and on top. Returns whether it did.
## UX-1 (§1.4): inside a game the Esc goes through the screen's one dispatcher (UiCancel) instead, which closes this panel as
## the topmost modal; `cancel_router` is that dispatcher's cancel(). Without one (the new game and build screens) the panel closes itself.
func handle_cancel(event: InputEvent) -> bool:
	var shown := is_visible_in_tree() if is_inside_tree() else visible
	if not shown or not event.is_action_pressed("ui_cancel") or not is_on_top():
		return false
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if cancel_router.is_valid():
		cancel_router.call()
		if visible:
			close()  # the router closed something else (it should not): this one was on top, and Esc was pressed
	else:
		close()
	return true


## True unless another overlay is visible above the panel among its siblings (drawn on top of it).
func is_on_top() -> bool:
	var parent := get_parent()
	if parent == null:
		return true
	for i in range(get_index() + 1, parent.get_child_count()):
		var above := parent.get_child(i) as CanvasItem
		if above != null and above.visible:
			return false
	return true


## The factions whose own entries the list holds (#285): the game's seated factions (GameScreen.open_codex sets them), or the
## factions a new game can seat (the title's codex). Shared entries are always listed.
var factions: Array = FactionData.playable(false)


## Lists the entries for a game seating `ids` (#285), keeping the search.
func set_factions(ids: Array) -> void:
	factions = ids.duplicate()
	if _search != null:
		filter(_search.text)


## Every codex key the list can hold, in RulesCodex order: the shared entries and the seated factions' own (#285).
func entry_keys() -> Array[String]:
	_bind()
	var keys: Array[String] = []
	for key in RulesCodex.ENTRIES:
		if RulesCodex.shown_for(String(key), factions):
			keys.append(String(key))
	return keys


## Keys currently in the list, after the search filter.
func listed_keys() -> Array[String]:
	_bind()
	return _shown_keys.duplicate()


## Key of the entry shown on the right, or "" if none.
func current_key() -> String:
	_bind()
	return _current


## UI-ICONS: the spell icon shown above the entry's title, or null.
func shown_icon() -> Texture2D:
	_bind()
	return _icon.texture if _icon.visible else null


## #272: the plate shown at the top of the entry's page, or null.
func shown_plate() -> Texture2D:
	_bind()
	return _plate.texture if _plate.visible else null


## Plain text of the entry on the right, as the player reads it (links stripped).
func shown_text() -> String:
	_bind()
	return _body.get_parsed_text()


## Narrows the list to entries whose title or text contains `text`, ignoring case. Empty shows all.
## Returns how many entries match. Keeps the search box in sync when called from code.
func filter(text: String) -> int:
	_bind()
	if _search.text != text:
		_search.text = text
	var needle := text.strip_edges().to_lower()
	_shown_keys.clear()
	_list.clear()
	for key in entry_keys():
		var e := RulesCodex.entry(key)
		var title := String(e.get("title", ""))
		var body := String(e.get("text", ""))
		if needle.is_empty() or title.to_lower().contains(needle) or body.to_lower().contains(needle):
			var idx := _list.add_item(title, SpellIcons.texture(SpellIcons.of_codex(key)))
			_list.set_item_metadata(idx, key)
			_shown_keys.append(key)
	_no_matches.visible = _shown_keys.is_empty()
	_select_current_in_list()
	return _shown_keys.size()


## Shows the entry for `key` and selects it in the list, clearing the search if it hides that entry.
## Returns false, changing nothing, for an unknown key.
func show_entry(key: String) -> bool:
	_bind()
	if not RulesCodex.ENTRIES.has(key):
		return false
	_current = key
	if not _shown_keys.has(key):
		filter("")
	var e := RulesCodex.entry(key)
	_title.text = String(e.get("title", ""))
	_icon.texture = SpellIcons.texture(SpellIcons.of_codex(key))
	_icon.visible = _icon.texture != null
	var plate := Art.codex_plate(key)
	_plate.texture = plate
	_plate.visible = plate != null
	_fit_plate()
	_body.text = _linked_text(key, String(e.get("text", "")))
	if _body.is_inside_tree():
		_body.scroll_to_line(0)
	_select_current_in_list()
	return true


## Opens the entry a link points at ("codex:<key>"). Returns false for other links or unknown keys.
func follow_link(meta: Variant) -> bool:
	var target := str(meta)
	if not target.begins_with(LINK_PREFIX):
		return false
	return show_entry(target.trim_prefix(LINK_PREFIX))


## Shows the panel, optionally at an entry (e.g. from a "?" next to a tooltip or turn report line).
func open(key: String = "") -> void:
	_bind()
	show()
	if not key.is_empty():
		show_entry(key)
	if is_inside_tree():
		_search.grab_focus()


## Hides the panel and emits `closed` so the host can free it or restore focus.
func close() -> void:
	_bind()
	hide()
	closed.emit()


func _on_item_selected(index: int) -> void:
	show_entry(String(_list.get_item_metadata(index)))


## #272: the height of the plate's band on a page `page_width` wide, in a panel `panel_height` tall, for a plate of `plate_size`:
## the plate scaled to the page's width with its aspect kept, but no taller than PLATE_MAX_SHARE of the panel. 0 without a size.
static func plate_height(plate_size: Vector2, page_width: float, panel_height: float) -> float:
	if plate_size.x <= 0.0 or plate_size.y <= 0.0 or page_width <= 0.0:
		return 0.0
	return floorf(minf(page_width * plate_size.y / plate_size.x, panel_height * PLATE_MAX_SHARE))


## Sizes the plate's band for the page as it is now. Runs as a page is shown, so its height is known before the page is laid out
## (no jump), and again whenever the page is resized (the window, the interface size).
func _fit_plate() -> void:
	var h := 0.0
	if _plate.visible and _plate.texture != null:
		h = plate_height(_plate.texture.get_size(), _page.size.x, size.y)
	if _plate.custom_minimum_size.y != h:
		_plate.custom_minimum_size = Vector2(0.0, h)


func _select_current_in_list() -> void:
	var idx := _shown_keys.find(_current)
	if idx >= 0:
		_list.select(idx)
		_list.ensure_current_is_visible()
	else:
		_list.deselect_all()


## Entry text as BBCode. Text that already has BBCode (explicit codex links) is used as written;
## otherwise the first whole-word mention of each other entry's title (letters and spaces only, so
## "Shield Wall (Spearmen)" is left out) becomes a link to it. Where two mentions overlap, the one that
## starts first wins, then the longer one ("Morale and routs" over "Morale").
func _linked_text(key: String, text: String) -> String:
	if text.contains("["):
		return text
	var plain_title := RegEx.create_from_string("^[A-Za-z]+( [A-Za-z]+)*$")
	var spans := []
	for other in entry_keys():
		var title := String(RulesCodex.entry(other).get("title", ""))
		if other == key or plain_title.search(title) == null:
			continue
		var m := RegEx.create_from_string("(?i)\\b" + title.replace(" ", "\\s+") + "\\b").search(text)
		if m:
			spans.append([m.get_start(), m.get_end(), other])
	spans.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var out := ""
	var at := 0
	for s in spans:
		if s[0] < at:
			continue
		out += text.substr(at, s[0] - at)
		out += "[url=%s%s]%s[/url]" % [LINK_PREFIX, s[2], text.substr(s[0], s[1] - s[0])]
		at = s[1]
	return out + text.substr(at)
