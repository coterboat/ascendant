extends "res://tests/test_case.gd"
## CW-4's hand-off to the path panel (#255): the research panel's path view reads the sides of a faction's fork through
## AscensionRules (branches_for, branch_data, new_unit_data, province_rule_data, economy_rule_data), so a Candlewake player sees
## both sides of the Pouring, the Golden Wake and the Red Wake, with their routes, colours, frames and lock-in previews, and the
## Crown's and the Clans' panels read exactly as before.

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"


func _game(seats: Array = [CROWN, WAKE]) -> GameState:
	var errors := []
	var s := GameState.create(23, seats, {"paths": true}, {}, errors)
	assert_eq(errors, [], "the game starts")
	return s


func test_the_candlewakes_panel_lists_both_sides_of_the_pouring() -> void:
	var s := AscensionRules.with_nodes(_game(), WAKE, ["wake_thicker_tallow", "wake_sitting_up_early"])
	var sides := AscensionRules.branches_for(WAKE)
	assert_eq(sides, ["golden_wake", "red_wake"], "the Pouring's two sides")
	assert_eq(PathView.sidebar(s, WAKE).routes.map(func(r): return String(r.branch)), sides, "a route for each side")
	for side in sides:
		var b := AscensionRules.branch_data(side)
		var colour := String(b.colour)
		assert_true(PathView.FORK_COLOURS.has(colour) and PathView.FORK_GLYPHS.has(colour), "%s has its frame colour and glyph" % side)
		assert_eq(PathPortrait.transformation_of(WAKE, colour), String(b.transformation), "%s's frame names its transformation" % side)
		var p := PathView.preview(s, WAKE, String(b.oath))
		assert_true(bool(p.ok), "%s has a lock-in preview: %s" % [side, p.get("reason", "")])
		var new_id := String(AscensionRules.node_effects(String(b.transformation)).get("new_unit", ""))
		assert_eq(String(p.look.new_name), String(AscensionRules.new_unit_data(new_id).name), "%s shows its new unit" % side)
		assert_eq(Art.unit_faction(new_id), WAKE, "%s's new unit belongs to the Candlewake" % new_id)
		# What the other side would have brought, in the lose list.
		var other := AscensionRules.other_branch(WAKE, side)
		var other_new := String(AscensionRules.node_effects(String(AscensionRules.branch_data(other).transformation)).get("new_unit", ""))
		var lose := " ".join(Array(p.lose).map(func(l): return String(l.text)))
		assert_true(lose.contains("no %s" % String(AscensionRules.new_unit_data(other_new).name)), "%s: %s" % [side, lose])
		# The Oath's economy rule links its own codex entry.
		var gain: Array = Array(p.gain).filter(func(l): return String(l.get("codex", "")) == String(AscensionRules.economy_rule_data(String(b.oath)).codex))
		assert_false(gain.is_empty(), "%s: the Oath's rule links %s" % [side, AscensionRules.economy_rule_data(String(b.oath)).codex])


func test_the_crowns_and_the_clans_panels_are_as_they_were() -> void:
	var s := _game([CROWN, CLANS])
	assert_eq(PathView.sidebar(s, CROWN).routes.map(func(r): return String(r.branch)), ["celestial_host", "living_iron"])
	assert_eq(PathView.sidebar(s, CLANS).routes.map(func(r): return String(r.branch)), ["thorn_wild", "blood_pact"])
	assert_eq(PathPortrait.transformation_of(CROWN, "gilt"), "crown_celestial_host")
	assert_eq(PathPortrait.transformation_of(CLANS, "crimson"), "beasts_blood_pact")
