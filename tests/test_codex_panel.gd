extends "res://tests/test_case.gd"
## In-game codex panel (#8): lists every RulesCodex entry by title, shows text, search, links, no raw
## ids. Also the #8 criterion: every codex key the rules and session code link to exists in RulesCodex.

const PANEL_SCENE := "res://ui/codex_panel.tscn"


## The runner calls tests before the tree is live, so _ready does not fire; any panel API call binds it.
func _make_panel():
	var panel = load(PANEL_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	panel.entry_keys()
	return panel


func _free(panel) -> void:
	panel.get_parent().remove_child(panel)
	panel.free()


func test_lists_every_codex_entry_by_title() -> void:
	var panel = _make_panel()
	var keys: Array[String] = panel.entry_keys()
	assert_eq(keys.size(), RulesCodex.ENTRIES.size())
	for key in RulesCodex.ENTRIES:
		assert_true(keys.has(key), "panel offers %s" % key)
	var list: ItemList = panel.get_node("%EntryList")
	assert_eq(list.item_count, RulesCodex.ENTRIES.size())
	for i in list.item_count:
		var key := String(list.get_item_metadata(i))
		assert_eq(list.get_item_text(i), String(RulesCodex.entry(key).title), "row %d shows the title" % i)
	assert_eq(panel.current_key(), keys[0], "opens on the first entry")
	_free(panel)


func test_show_entry_shows_its_text() -> void:
	var panel = _make_panel()
	var list: ItemList = panel.get_node("%EntryList")
	var title: Label = panel.get_node("%EntryTitle")
	for key in RulesCodex.ENTRIES:
		assert_true(panel.show_entry(key), key)
		assert_eq(panel.current_key(), key)
		assert_eq(title.text, String(RulesCodex.entry(key).title))
		assert_eq(String(panel.shown_text()).strip_edges(), RulesCodex.text(key).strip_edges(), "text of %s" % key)
		var selected := list.get_selected_items()
		assert_eq(selected.size(), 1)
		if selected.size() == 1:
			assert_eq(String(list.get_item_metadata(selected[0])), key, "list selects %s" % key)
	_free(panel)


func test_show_entry_rejects_unknown_keys() -> void:
	var panel = _make_panel()
	panel.show_entry("income")
	assert_false(panel.show_entry("no_such_entry"))
	assert_false(panel.show_entry(""))
	assert_eq(panel.current_key(), "income", "an unknown key changes nothing")
	_free(panel)


func test_filter_narrows_the_list() -> void:
	var panel = _make_panel()
	var list: ItemList = panel.get_node("%EntryList")
	var total := RulesCodex.ENTRIES.size()
	var n: int = panel.filter("swapping")
	assert_true(n >= 1 and n < total, "search narrows the list (got %d of %d)" % [n, total])
	assert_eq(list.item_count, n)
	assert_true(panel.listed_keys().has("swap"))
	for key in panel.listed_keys():
		var e := RulesCodex.entry(key)
		assert_true((String(e.title) + " " + String(e.text)).to_lower().contains("swapping"), key)
	assert_true(panel.filter("CAPITAL") > 0, "search ignores case")
	assert_true(panel.listed_keys().has("victory"))
	assert_eq(panel.filter("no rule says this"), 0)
	assert_true((panel.get_node("%NoMatches") as Label).visible, "says nothing matches")
	assert_eq(panel.filter(""), total, "empty search lists everything")
	assert_false((panel.get_node("%NoMatches") as Label).visible)
	assert_eq((panel.get_node("%Search") as LineEdit).text, "", "search box follows filter()")
	_free(panel)


func test_codex_link_opens_its_entry() -> void:
	var panel = _make_panel()
	panel.show_entry("phase_order")
	assert_true(panel.follow_link("codex:income"))
	assert_eq(panel.current_key(), "income")
	# Clicking a link in the text arrives as meta_clicked on the RichTextLabel.
	(panel.get_node("%EntryText") as RichTextLabel).meta_clicked.emit("codex:swap")
	assert_eq(panel.current_key(), "swap")
	assert_false(panel.follow_link("codex:no_such_entry"))
	assert_false(panel.follow_link("https://example.com"))
	assert_eq(panel.current_key(), "swap")
	# A link to an entry the search hides clears the search so the list shows it.
	panel.filter("swapping")
	assert_true(panel.follow_link("codex:income"))
	assert_true(panel.listed_keys().has("income"))
	_free(panel)


func test_automatic_links_point_at_other_entries() -> void:
	var panel = _make_panel()
	var body: RichTextLabel = panel.get_node("%EntryText")
	var link := RegEx.create_from_string("\\[url=codex:([A-Za-z0-9_]+)\\]")
	var found := 0
	for key in RulesCodex.ENTRIES:
		panel.show_entry(key)
		for m in link.search_all(body.text):
			found += 1
			var target := m.get_string(1)
			assert_true(RulesCodex.ENTRIES.has(target), "%s links to a real entry (%s)" % [key, target])
			assert_ne(target, key, "%s does not link to itself" % key)
	assert_true(found > 0, "entries mentioning another entry's one-word title link to it")
	_free(panel)


func test_no_raw_ids_in_player_facing_text() -> void:
	var panel = _make_panel()
	var list: ItemList = panel.get_node("%EntryList")
	var seen: Array[String] = [
		(panel.get_node("%Heading") as Label).text,
		(panel.get_node("%CloseButton") as Button).text,
		(panel.get_node("%Search") as LineEdit).placeholder_text,
		(panel.get_node("%NoMatches") as Label).text,
	]
	for i in list.item_count:
		seen.append(list.get_item_text(i))
	for key in RulesCodex.ENTRIES:
		panel.show_entry(key)
		seen.append((panel.get_node("%EntryTitle") as Label).text)
		seen.append(panel.shown_text())
	for s in seen:
		assert_false(s.strip_edges().is_empty(), "no blank player-facing text")
		assert_false(s.contains("codex:"), "no link target in: %s" % s)
		assert_false(s.contains("_"), "no raw id in: %s" % s)
		for key in RulesCodex.ENTRIES:
			assert_ne(s, key, "raw id shown: %s" % key)
	_free(panel)


func test_close_button_emits_closed() -> void:
	var panel = _make_panel()
	var hits := [0]
	panel.closed.connect(func(): hits[0] += 1)
	(panel.get_node("%CloseButton") as Button).pressed.emit()
	assert_eq(hits[0], 1)
	assert_false(panel.visible, "closing hides the panel")
	panel.open("victory")
	assert_true(panel.visible)
	assert_eq(panel.current_key(), "victory")
	_free(panel)


# --- #8 criterion: every codex key the code links to exists ---------------------------------------

func test_every_codex_key_the_game_links_exists() -> void:
	var keys := {}
	for key in GameSession.CODEX_KEYS:
		keys[key] = "GameSession.CODEX_KEYS"
	var scripts := _scripts_under("res://rules")
	scripts.append_array(_scripts_under("res://ui"))
	for path in scripts:
		if path.ends_with("rules_codex.gd"):
			continue
		for key in _codex_keys_in_source(FileAccess.get_file_as_string(path)):
			keys[key] = path
	var link := RegEx.create_from_string("codex:([A-Za-z0-9_]+)")
	for id in RulesCodex.ENTRIES:
		for m in link.search_all(RulesCodex.text(id)):
			keys[m.get_string(1)] = "RulesCodex entry " + id
	# The scan must actually see the resolver's and the session's links, or it proves nothing.
	for expected in ["orders", "move", "swap", "same_province", "defended", "capture", "recruit", "income",
			"handoff", "victory", "simultaneous_capture"]:
		assert_true(keys.has(expected), "scan found codex key %s" % expected)
	for key in keys:
		assert_true(RulesCodex.ENTRIES.has(key), "codex key %s (from %s) exists in RulesCodex" % [key, keys[key]])


func _scripts_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			out.append_array(_scripts_under(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out


## Codex keys written in source: `codex = "..."` (every literal on that line), `"codex": "..."`, and
## the string literals in the last argument (the codex id) of each TurnResolver `_event(...)` call.
func _codex_keys_in_source(src: String) -> Array[String]:
	var out: Array[String] = []
	var literal := RegEx.create_from_string("\"([a-z][a-z0-9_]*)\"")
	var assign := RegEx.create_from_string("\\bcodex\\s*:?=\\s*([^\\n]+)")
	for m in assign.search_all(src):
		for l in literal.search_all(m.get_string(1)):
			out.append(l.get_string(1))
	var keyed := RegEx.create_from_string("\"codex\"\\s*:\\s*\"([a-z][a-z0-9_]*)\"")
	for m in keyed.search_all(src):
		out.append(m.get_string(1))
	var call := RegEx.create_from_string("(?<![A-Za-z0-9_])_event\\(")
	for m in call.search_all(src):
		for l in literal.search_all(_last_argument(src, m.get_end())):
			out.append(l.get_string(1))
	return out


## Text of the last top-level argument of the call whose argument list starts at `from`.
func _last_argument(src: String, from: int) -> String:
	var depth := 0
	var start := from
	var i := from
	while i < src.length():
		var c := src[i]
		if c == "\"":
			i += 1
			while i < src.length() and src[i] != "\"":
				i += 2 if src[i] == "\\" else 1
		elif c in ["(", "[", "{"]:
			depth += 1
		elif c in [")", "]", "}"]:
			if depth == 0:
				return src.substr(start, i - start)
			depth -= 1
		elif c == "," and depth == 0:
			start = i + 1
		i += 1
	return ""
