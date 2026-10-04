class_name CodexPanel
extends Control
## In-game codex (#8): every RulesCodex entry listed by its player-facing title, searchable, with the
## selected entry's text on the right. Reads RulesCodex only; it holds no rules text of its own.
## Links written as [url=codex:<key>]...[/url] in entry text open that entry. Entries without explicit
## links get one automatic link per other entry whose title (letters and spaces only: Income, Hit
## points, Morale and routs, ...) appears in the text as whole words; a longer title wins an overlap.
## Esc closes the panel, in one press, even while the search box has focus: the panel takes Esc in
## _input, before the focused search box would use it to stop editing. Hosts need no Esc code of their
## own; the panel only skips Esc when another overlay is open above it among its siblings.

signal closed

const LINK_PREFIX := "codex:"

var _shown_keys: Array[String] = []
var _current := ""
var _bound := false
var _search: LineEdit
var _list: ItemList
var _no_matches: Label
var _title: Label
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
func handle_cancel(event: InputEvent) -> bool:
	var shown := is_visible_in_tree() if is_inside_tree() else visible
	if not shown or not event.is_action_pressed("ui_cancel") or not is_on_top():
		return false
	if is_inside_tree():
		get_viewport().set_input_as_handled()
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


## Every codex key, in RulesCodex order.
func entry_keys() -> Array[String]:
	_bind()
	var keys: Array[String] = []
	for key in RulesCodex.ENTRIES:
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
			var idx := _list.add_item(title)
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
