extends "res://tests/test_case.gd"
## CW-12's hand-off to the codex (#263): the codex links a term where it stands as the term, never inside a unit's own name. The
## candlebeasts' page names "the Guttering Bear", and "Guttering" is an entry of its own (an army at flame 0); "Hundred-Wick" holds
## "Wick", the faction rule. Where the term stands alone in the same text, it links as before.

const CROWN := "kingdom"
const WAKE := "candlewake"


func _panel() -> CodexPanel:
	var panel: CodexPanel = load("res://ui/codex_panel.tscn").instantiate()
	panel.set_factions([CROWN, WAKE])
	return panel


func test_a_term_inside_a_units_name_is_not_linked() -> void:
	var panel := _panel()
	var linked := panel._linked_text("candlebeasts", RulesCodex.text("candlebeasts"))
	assert_true(linked.contains("Guttering Bear"), "the Bear is named whole: %s" % linked)
	assert_false(linked.contains("[url=%sguttering]" % CodexPanel.LINK_PREFIX), "and Guttering isn't linked inside it")
	var text := "The Guttering Bear melts. An army at flame 0 is guttering: a Hundred-Wick's army too. Wick moves every flame."
	var out := panel._linked_text("trait_flare", text)
	assert_true(out.contains("is [url=%sguttering]guttering[/url]" % CodexPanel.LINK_PREFIX), "the term alone links: %s" % out)
	assert_true(out.contains("The Guttering Bear"), "the name stays plain")
	assert_true(out.contains("a Hundred-Wick's"), "so does Hundred-Wick")
	assert_true(out.contains("[url=%swick]Wick[/url] moves" % CodexPanel.LINK_PREFIX), "Wick alone links: %s" % out)
	panel.free()


func test_texts_without_such_names_link_as_before() -> void:
	var panel := _panel()
	var text := "A province pays its income in gold every turn, and a fort guards it."
	var out := panel._linked_text("the_wake", text)
	for word in ["province", "income", "gold", "fort"]:
		assert_true(out.contains("]%s[/url]" % word), "%s links: %s" % [word, out])
	panel.free()
