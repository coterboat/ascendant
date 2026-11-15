extends "res://tests/test_case.gd"
## #292 (QA): under fog, the Rulers panel's enemy column said "kept power" twice on one line: "Kept power: kept power 10 at most:
## the most it could be with the mandates you know", and "Kept power: kept power 10, seen on turn 10". The row names it, and
## FogView.rival_summary's kept power line is written to stand alone (it goes in "What you know about ..." too). The row now says
## it once: "Kept power: 10 at most (the most it could be with the mandates you know)" before you have seen their ruler, and
## "Kept power: 10, seen on turn 10" after. The numbers come from the view and the intel.

const CROWN := "kingdom"
const CLANS := "beasts"


## A fog game the Crown plays, at its start.
func _fog_game() -> GameState:
	var s := GameState.with_rulers(95)
	s.setup_fog([])
	return s


## The Clans' column in the Rulers panel as the Crown sees it with `intel`: {"kept" (the kept power row's text), "known" (the
## "What you know about ..." line), "power" (the Clans' kept power in the Crown's view)}.
func _clans_column(s: GameState, intel: Dictionary) -> Dictionary:
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), intel)
	var panel := RulerPanel.new()
	panel.fog_intel = intel
	panel.show_for(view, CROWN, null)
	var col := panel.columns.get_node("Column_%s" % CLANS)
	var kept := col.find_child("KeptPowerLabel", true, false) as Label
	var known := col.find_child("KnownLabel", true, false) as Label
	var out := {"kept": kept.text if kept != null else "", "known": known.text if known != null else "",
		"power": view.find_faction(CLANS).kept_power}
	panel.free()
	return out


func test_an_unseen_rivals_kept_power_says_it_once() -> void:
	var s := _fog_game()
	var intel := FogRules.new_intel(s, CROWN)
	assert_true(int(intel[CLANS].kept_power) < 0, "the Crown hasn't seen the Clans' ruler yet")
	var col := _clans_column(s, intel)
	assert_eq(col.kept, "Kept power: %d at most (the most it could be with the mandates you know)" % int(col.power))
	assert_eq(String(col.kept).countn("kept power"), 1, "once: \"%s\"" % col.kept)
	assert_true(String(col.known).contains("kept power %d at most: the most it could be" % int(col.power)),
		"the \"What you know\" line still says it in its own words: \"%s\"" % col.known)


func test_a_seen_rivals_kept_power_says_it_once_with_the_turn() -> void:
	var s := _fog_game()
	var intel := FogRules.new_intel(s, CROWN)
	var seen_turn := s.current_turn + 9
	FogRules._learn_kept(intel[CLANS], s.find_faction(CLANS).kept_power, seen_turn)  # as seeing or fighting their ruler does
	var col := _clans_column(s, intel)
	assert_eq(int(col.power), s.find_faction(CLANS).kept_power, "the view has the kept power the Crown saw")
	assert_eq(col.kept, "Kept power: %d, seen on turn %d" % [int(col.power), seen_turn])
	assert_eq(String(col.kept).countn("kept power"), 1, "once: \"%s\"" % col.kept)
	assert_true(String(col.known).contains("kept power %d, seen on turn %d" % [int(col.power), seen_turn]),
		"the \"What you know\" line still says it in its own words: \"%s\"" % col.known)
