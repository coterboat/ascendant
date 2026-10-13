extends "res://tests/test_case.gd"
## UX-6 (design/UX_WAR_TABLE.md §5.2): ChronicleModel, the Chronicle's pure Read side. Pinned here:
##   - a template for EVERY event type the resolver, the muster pass and the fog filter make (a source scan holds the list to the code), each
##     with a kind, an image, a rank, and placeholders the event's own fields fill;
##   - headlines and details written per event type (not cut out of the report's prose), a generic fallback for a type with no template;
##   - grouping: a battle and the capture of the same province on the same turn are one card (several battles, several captures, a battle
##     without a capture, a capture without a battle), and nothing else groups;
##   - the order (importance, place, kind), the filter and the counts, the summary line, and when a turn opens the Chronicle;
##   - the current-state needs, which the Turn report's panel and the Chronicle both read;
##   - what a pin keeps: a JSON-safe payload with the battle's log dropped.

const Kit := preload("res://tests/muster_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
## The placeholders the model fills (fields_of): a template naming anything else is a typo.
const FIELDS := ["row", "place", "from", "to", "who", "Who", "factions", "order", "reason", "size", "foe", "Foe", "sides", "Winner", "toll",
	"armies", "capital", "units", "provinces", "Besieger", "fort", "from_walls", "to_walls", "node", "node_kind", "branch", "closed", "name",
	"kept_before", "kept_after", "ritual", "caster", "from_terrain",
	# an event's own numbers (the fog's safe ones and the resolver's)
	"income", "gold", "gold_before", "gold_after", "cost", "gained", "walls", "walls_before", "walls_max", "turn_of_siege", "battle_turn",
	"recruit_from", "successor_turn", "successor_power", "kept_power", "until_turn", "budget", "mandate_name", "ruler_name"]


# --- the table ------------------------------------------------------------------------------------------

func test_every_template_is_well_formed() -> void:
	var seen := 0
	for type in ChronicleModel.TABLE:
		for variant in ChronicleModel.TABLE[type]:
			var row: Array = ChronicleModel.TABLE[type][variant]
			var where := "%s/%s" % [type, variant]
			assert_eq(row.size(), 6, "%s: [kind, image, rank, headline, detail, flags]" % where)
			assert_true(ChronicleModel.KINDS.has(String(row[0])), "%s: a known kind" % where)
			assert_true(ChronicleModel.IMAGES.has(String(row[1])), "%s: a known medallion type (%s)" % [where, row[1]])
			assert_true(ChronicleModel.RANKS.has(String(row[2])), "%s: a known rank" % where)
			for f in String(row[5]):
				assert_true("iro".contains(f), "%s: flags are i, r, o" % where)
			for text in [row[3], row[4]]:
				for name in _placeholders(String(text)):
					assert_true(FIELDS.has(name), "%s: {%s} is a field the model fills" % [where, name])
			seen += 1
	assert_true(seen >= 60, "templates: %d" % seen)


func _placeholders(template: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("\\{([A-Za-z_]+)\\}")
	for m in re.search_all(template):
		out.append(m.get_string(1))
	return out


func test_every_medallion_type_is_complete() -> void:
	var kinds := {}
	for key in ChronicleModel.image_keys():
		var info := ChronicleModel.image_info(key)
		assert_true(ChronicleModel.KINDS.has(String(info.kind)), "%s: a known kind" % key)
		assert_true(UiIcons.NAMES.has(String(info.icon)) or String(info.icon) == "flag", "%s: an icon from the set, or the flag (%s)" % [key, info.icon])
		assert_true(["", "good", "bad"].has(String(info.tone)), "%s: a known tone" % key)
		assert_false(String(info.title).is_empty(), "%s has a title for the artist" % key)
		kinds[String(info.kind)] = true
	for k in ChronicleModel.KINDS:
		assert_true(kinds.has(k), "kind %s has at least one medallion type" % k)
	# Alex's list (§5.2): a battle won and lost, an army lost, a province taken and lost, fealty to you and to a rival, a siege begun,
	# walls breached, a ruler fallen and returned, research done, a spell learned, a ritual cast, recruits raised, the treasury, needs you.
	for key in ["battle_won", "battle_lost", "army_lost", "province_taken", "province_lost", "fealty_to_you", "fealty_to_rival", "siege_begun",
			"walls_breached", "ruler_fallen", "ruler_returned", "research_done", "spell_learned", "ritual_cast", "recruits_raised", "treasury", "needs_you"]:
		assert_true(ChronicleModel.IMAGES.has(key), "the spec's medallion %s exists" % key)


func test_a_template_exists_for_every_event_type_the_game_can_make() -> void:
	for type in ChronicleModel.EVENT_TYPES:
		var covered: bool = ChronicleModel.TABLE.has(type) or ChronicleModel.SKIPPED.has(type) or type == "border_battle"
		assert_true(covered, "event type %s has a template (or is skipped on purpose)" % type)
	for type in FogData.AUDIENCE:
		assert_true(ChronicleModel.EVENT_TYPES.has(type), "the fog audience table's %s is in the model's list" % type)
	for type in FogData.SYNTHETIC_TYPES:
		assert_true(ChronicleModel.EVENT_TYPES.has(type), "synthetic %s too" % type)
	for type in ChronicleModel.TABLE:
		assert_true(ChronicleModel.EVENT_TYPES.has(type) or type == "battle", "template %s is for a real event type" % type)


## The source scan: every event type the resolver writes by name is in the model's list, so a new event type fails here until it has a template.
func test_the_resolver_source_names_no_event_type_the_model_lacks() -> void:
	var re := RegEx.create_from_string("_event\\(\"([a-z_]+)\"")
	var found := {}
	for path in ["res://rules/turn_resolver.gd", "res://rules/siege_rules.gd", "res://rules/magic_rules.gd", "res://rules/muster_rules.gd"]:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			found[m.get_string(1)] = true
	assert_true(found.size() >= 35, "the scan found the resolver's event types (%d)" % found.size())
	for type in found:
		assert_true(ChronicleModel.EVENT_TYPES.has(type), "the resolver writes %s: the Chronicle needs a template for it" % type)
	var dynamic := RegEx.create_from_string("type = \"([a-z_]+)\"")
	for m in dynamic.search_all(FileAccess.get_file_as_string("res://rules/turn_resolver.gd")):
		assert_true(ChronicleModel.EVENT_TYPES.has(m.get_string(1)), "the muster pass writes %s" % m.get_string(1))
	for type in ["siege_lifted", "siege_ended", "storm_called_off", "sally_called_off", "sally_found_nothing"]:
		assert_true(ChronicleModel.EVENT_TYPES.has(type))


# --- one event, one announcement ---------------------------------------------------------------------------

func _state() -> GameState:
	var s := GameState.with_sieges(8, {}, {"paths": true, "rulers": true})
	return s


func _event(type: String, provinces: Array, factions: Array, armies: Array, numbers: Dictionary, text: String = "", extra: Dictionary = {}) -> Dictionary:
	var e := {"type": type, "phase": "x", "provinces": provinces, "factions": factions, "armies": armies, "cause": "test", "numbers": numbers,
		"text": text if not text.is_empty() else "The resolver's own words for %s." % type, "codex": "orders"}
	e.merge(extra, true)
	return e


## [event, the viewer who is its actor or party, the variant expected]: the events of the types a short fog game may not reach.
func _samples() -> Array:
	var s := _state()
	var out := []
	out.append([_event("vassal_joined", ["ebonpeak"], [CROWN], [], {"income": 6}), CROWN, "you"])
	out.append([_event("vassal_joined", ["ebonpeak"], [CLANS], [], {"income": 6}), CROWN, "rival"])
	out.append([_event("vassal_contested", ["thornvale"], [CLANS, CROWN], [], {"income": 6}), CROWN, "you"])
	out.append([_event("vassal_contested", ["thornvale"], [CLANS, "independents"], [], {"income": 6}), CROWN, "rival"])
	out.append([_event("ruler_died", ["thornvale"], [CROWN], ["kingdom-2"], {"ruler": "ever_regent", "kind": "undying", "name": "the Ever-Regent",
		"generation": 1, "kept_power": 5, "successor_turn": 9, "successor_power": 5}, "", {"codex": "ruler_death"}), CROWN, "you"])
	out.append([_event("ruler_died", ["thornvale"], [CLANS], [], {"ruler": "fang_chieftain", "kind": "mortal", "name": "the Ninth Fang",
		"generation": 1, "kept_power": 3, "successor_turn": 9, "successor_power": 2}), CROWN, "rival"])
	out.append([_event("ruler_arrived", ["crownkeep"], [CROWN], ["kingdom-9"], {"ruler": "ever_regent", "kind": "undying", "name": "the Ever-Regent",
		"generation": 2, "kept_power": 5, "max_hp": 19, "attack": 13, "defense": 8, "ability_rank": 2}), CROWN, "you"])
	out.append([_event("ruler_arrived", ["fangridge"], [CLANS], [], {"ruler": "fang_chieftain", "kind": "mortal", "name": "the Tenth Fang",
		"generation": 2, "kept_power": 2, "max_hp": 30, "attack": 14, "defense": 9, "ability_rank": 1}), CROWN, "rival"])
	out.append([_event("succession_waiting", ["crownkeep"], [CROWN], [], {"successor_turn": 9, "successor_power": 5, "successor_generation": 2}), CROWN, "you"])
	out.append([_event("succession_waiting", ["fangridge"], [CLANS], [], {"successor_turn": 9, "successor_power": 5, "successor_generation": 2}), CROWN, "rival"])
	out.append([_event("sacrificed", ["crownkeep"], [CROWN], ["kingdom-1"], {"mandate_name": "Drilled Ranks", "ruler_name": "the Ever-Regent", "cost": 3,
		"kept_before": 5, "kept_after": 2}), CROWN, "default"])
	out.append([_event("oath_sworn", [], [CROWN], [], {"node": "crown_oath_dawn", "branch": "celestial_host", "closed": "living_iron", "turn": 6}), CROWN, "you"])
	out.append([_event("oath_sworn", [], [CLANS], [], {"node": "beasts_oath_blood", "branch": "blood_pact", "closed": "thorn_wild", "turn": 6}), CROWN, "rival"])
	out.append([_event("transformed", [], [CROWN], [], {"node": "crown_celestial_host", "branch": "celestial_host", "turn": 9}), CROWN, "you"])
	out.append([_event("transformed", [], [CLANS], [], {"node": "beasts_blood_pact", "branch": "blood_pact", "turn": 9}), CROWN, "rival"])
	out.append([_event("research_done", [], [CROWN], [], {"node": "crown_drillyard", "cost": 10, "kind": "tier1", "turn": 2}), CROWN, "node"])
	out.append([_event("research_done", [], [CROWN], [], {"node": "sunlance", "cost": 10, "kind": "spell", "turn": 3}), CROWN, "spell"])
	out.append([_event("wild_spread", ["deepwood"], [CROWN], [], {"province": "deepwood", "from_terrain": "plains", "terrain": "forest"}), CROWN, "you"])
	out.append([_event("wild_spread", ["deepwood"], [CLANS], [], {"province": "deepwood", "from_terrain": "plains", "terrain": "forest"}), CROWN, "rival"])
	out.append([_event("fort_built", ["ebonpeak"], [CROWN], [], {"level": 1, "walls": 3, "recruits": 2, "recruit_from": 6}), CROWN, "you"])
	out.append([_event("fort_built", ["ebonpeak"], [CLANS], [], {"level": 1, "walls": 3, "province": "ebonpeak"}), CROWN, "rival"])
	out.append([_event("fort_raised", ["ebonpeak"], [CROWN], [], {"province": "ebonpeak"}), CROWN, "you"])
	out.append([_event("fort_raised", ["ebonpeak"], [CLANS], [], {"province": "ebonpeak"}), CROWN, "rival"])
	out.append([_event("construction_started", ["deepwood"], [CROWN], [], {"cost": 30, "to": 1, "stands": 8}), CROWN, "default"])
	out.append([_event("construction_halted", ["deepwood"], [CROWN], [], {}), CROWN, "default"])
	out.append([_event("construction_razed", ["deepwood"], [CLANS, CROWN], [], {"left": 1, "level": 0, "to": 1}), CROWN, "owner"])
	out.append([_event("construction_razed", ["deepwood"], [CROWN, CLANS], [], {"left": 1, "level": 0, "to": 1}), CROWN, "razer"])
	out.append([_event("walls_repaired", ["blackwood"], [CROWN], [], {"amount": 2, "from": 0, "to": 2, "walls_max": 6}), CROWN, "default"])
	out.append([_event("siege_started", ["blackwood"], [CLANS, CROWN], ["beasts-1"], {"besieger": CLANS, "owner": CROWN, "walls_before": 6, "walls": 3,
		"walls_max": 6, "turn_of_siege": 1, "troops": 37}), CROWN, "besieged"])
	out.append([_event("siege_started", ["blackwood"], [CROWN, CLANS], ["kingdom-1"], {"besieger": CROWN, "owner": CLANS, "walls_before": 6, "walls": 3,
		"walls_max": 6, "turn_of_siege": 1, "troops": 37}), CROWN, "besieging"])
	out.append([_event("walls_damaged", ["blackwood"], [CLANS, CROWN], ["beasts-1"], {"besieger": CLANS, "owner": CROWN, "walls_before": 3, "walls": 0,
		"walls_max": 6, "turn_of_siege": 2}), CROWN, "besieged"])
	out.append([_event("walls_breached", ["blackwood"], [CLANS, CROWN], ["beasts-1"], {"besieger": CLANS, "owner": CROWN, "walls_max": 6, "battle_turn": 4}), CROWN, "default"])
	out.append([_event("siege_lifted", ["blackwood"], [CROWN], [], {"owner": CROWN, "besieger": ""}), CROWN, "default"])
	out.append([_event("siege_ended", ["blackwood"], [CLANS, CROWN], ["beasts-1"], {"owner": CROWN, "besieger": CLANS}), CROWN, "default"])
	for t in ["storm_called_off", "sally_called_off", "sally_found_nothing"]:
		out.append([_event(t, ["blackwood"], [CROWN], ["kingdom-1"], {"why": "none_left"}), CROWN, "default"])
	out.append([_event("ritual_cast", ["crownkeep"], [CROWN], ["kingdom-1"], {"ritual": "dawn_blessing", "until_turn": 6, "global": false}), CROWN, "you"])
	out.append([_event("ritual_cast", ["fangridge"], [CLANS], [], {"ritual": "blood_moon", "until_turn": 6, "global": true}), CROWN, "rival"])
	out.append([_event("ritual_fell", ["crownkeep"], [CROWN, CLANS], [], {"ritual": "bloodrot", "faction": CLANS, "until_turn": 6, "budget": 12}), CROWN, "default"])
	out.append([_event("ritual_turned_aside", ["fangridge"], [CROWN, CLANS], ["kingdom-1"], {"ritual": "sunburst"}), CROWN, "default"])
	out.append([_event("curse_bit", ["crownkeep"], [CROWN, CLANS], ["kingdom-1"], {"ritual": "bloodrot", "until_turn": 6, "budget": 12, "province": "crownkeep"}), CROWN, "victim"])
	out.append([_event("curse_bit", ["crownkeep"], [CLANS, CROWN], ["kingdom-1"], {"ritual": "bloodrot", "until_turn": 6, "budget": 12, "province": "crownkeep"}), CROWN, "caster"])
	for t in ["enchantment_began", "enchantment_ended"]:
		out.append([_event(t, ["crownkeep"], [CROWN], [], {"ritual": "dawn_blessing", "until_turn": 6}), CROWN, "default"])
	for t in ["summoned", "summon_faded", "far_sight_reading", "blood_paid", "blessing_healed"]:
		out.append([_event(t, ["crownkeep"], [CROWN], ["kingdom-1"], {"ritual": "dawn_blessing"}), CROWN, "default"])
	out.append([_event("raided", ["stonegate"], [CROWN], [], {"gold": 16, "gold_before": 44, "gold_after": 60}), CROWN, "raider"])
	for t in ["mending", "ruler_healed", "path_healed", "research_gained", "research_sold"]:
		out.append([_event(t, ["crownkeep"], [CROWN], [], {"gained": 6, "gold": 5}), CROWN, "default"])
	out.append([_event("order_rejected", ["blackwood"], [CROWN], [], {}, "Order from Aurel Crown, \"recruit Seraphs at Wildmoor\", was rejected.",
		{"reason": "Wildmoor is not yours, so nobody of yours can recruit there; no gold is spent.", "order": {"type": "recruit", "at": "wildmoor"}}), CROWN, "default"])
	out.append([_event("army_moved", ["wildmoor", "blackwood"], [CLANS], [], {"total": {"shown": 5, "low": 3, "high": 7, "text": "about 5"}, "types": ["war_bear"]},
		"An army of the Thornmane Clans (about 5 fighters: War Bear) marched from Wildmoor to Blackwood."), CROWN, "seen"])
	out.append([_event("army_moved", ["wildmoor", "blackwood"], [CLANS], ["beasts-1"], {}, "The Thornmane Clans army marched."), CROWN, "seen"])
	out.append([_event("captured", ["blackwood"], [CLANS, CROWN], [], {"income": 8, "is_capital": false}, "", {"cause": "undefended_enemy", "armies": ["beasts-1"]}), CROWN, "lost"])
	out.append([_event("captured", ["blackwood"], [CLANS, "independents"], [], {"income": 8, "is_capital": false}, "", {"cause": "undefended_neutral", "armies": ["beasts-1"]}), CROWN, "seen"])
	out.append([_event("captured", ["blackwood"], [CROWN, CLANS], [], {"income": 8, "is_capital": true}, "", {"cause": "undefended_enemy", "armies": ["kingdom-1"]}), CROWN, "taken"])
	for t in ["sighting_changed", "sighting_lost", "memory_added"]:
		out.append([_event(t, ["blackwood"], [CLANS], [], {"total": 5, "turn": 4}, "", {"synthetic": true}), CROWN, "default"])
	return out


func test_every_sample_event_is_announced_with_its_own_fields() -> void:
	var s := _state()
	var types := {}
	var variants := {}
	for sample in _samples():
		var e: Dictionary = sample[0]
		var viewer: String = sample[1]
		var wanted: String = sample[2]
		var type := String(e.type)
		var ctx := {"state": s, "viewer": viewer, "turn": 3, "events": [e], "before": null, "fog": false}
		var got := ChronicleModel.variant(e, ctx)
		var where := "%s/%s" % [type, wanted]
		assert_eq(got, wanted, "%s: the variant" % where)
		var fields := ChronicleModel.fields_of(e, "A full report row.", ctx)
		var row: Array = ChronicleModel.TABLE[type][wanted]
		assert_false(ChronicleModel._fill(String(row[3]), fields).is_empty(), "%s: the headline's placeholders are all filled (%s)" % [where, row[3]])
		assert_false(ChronicleModel._fill(String(row[4]), fields).is_empty(), "%s: so is the detail's (%s)" % [where, row[4]])
		var items := ChronicleModel.build({"turn": 3, "events": [e]}, s, viewer)
		assert_eq(items.size(), 1, "%s: one announcement" % where)
		if items.size() == 1:
			_check_item(items[0], where)
			assert_eq(String(items[0].image), String(row[1]), "%s: its medallion" % where)
		types[type] = true
		variants[where] = true
	assert_true(types.size() >= 40, "types sampled: %d" % types.size())
	assert_true(variants.size() >= 60, "variants sampled: %d" % variants.size())


## Every field an announcement promises.
func _check_item(it: Dictionary, where: String) -> void:
	for key in ["id", "turn", "kind", "image", "rank", "headline", "detail", "province", "place", "codex", "battle", "source_rows", "important", "routine", "own", "type", "facts"]:
		assert_true(it.has(key), "%s: has %s" % [where, key])
	assert_true(ChronicleModel.KINDS.has(String(it.kind)), "%s: a known kind" % where)
	assert_true(ChronicleModel.IMAGES.has(String(it.image)) or ChronicleModel.KINDS.has(String(it.image)), "%s: a known image" % where)
	assert_false(String(it.headline).is_empty(), "%s: a headline" % where)
	assert_true(String(it.headline).length() <= 64, "%s: a short headline (%d): %s" % [where, String(it.headline).length(), it.headline])
	assert_false(String(it.detail).is_empty(), "%s: a detail" % where)
	assert_false((it.source_rows as Array).is_empty(), "%s: the report row it came from" % where)
	assert_true(String(it.codex).is_empty() or RulesCodex.ENTRIES.has(String(it.codex)), "%s: a codex entry that exists (%s)" % [where, it.codex])
	assert_false(String(it.codex).is_empty(), "%s: every notice has its codex link" % where)
	assert_false(String(it.headline).contains("{") or String(it.detail).contains("{"), "%s: no placeholder left in the text" % where)
	assert_true(String(it.headline).substr(0, 1) == String(it.headline).substr(0, 1).to_upper(), "%s: begins with a capital: %s" % [where, it.headline])
	assert_eq(JSON.stringify(ChronicleModel.pin_payload(it)).length() > 10, true, "%s: a pin payload serialises" % where)


func test_a_future_event_type_falls_back_to_a_generic_announcement() -> void:
	var s := _state()
	var e := _event("a_future_event", ["blackwood"], [CROWN], [], {}, "Something the resolver will say one day.", {"phase": "rituals"})
	var items := ChronicleModel.build({"turn": 4, "events": [e]}, s, CROWN)
	assert_eq(items.size(), 1, "an event type with no template is not lost")
	assert_eq(items[0].kind, "magic", "its kind comes from its phase")
	assert_eq(items[0].detail, "Something the resolver will say one day.", "its detail is its full row")
	assert_true(String(items[0].headline).contains("Blackwood"), "its headline names the place: %s" % items[0].headline)
	assert_false(String(items[0].codex).is_empty(), "and it has a codex link all the same")


func test_a_template_with_a_missing_field_falls_back_without_losing_the_row() -> void:
	var s := _state()
	# A research_done event with no node: the template can't fill, so the image's title and the whole row stand in.
	var e := _event("research_done", [], [CROWN], [], {}, "Something was researched.")
	var items := ChronicleModel.build({"turn": 4, "events": [e]}, s, CROWN)
	assert_eq(items.size(), 1)
	assert_eq(items[0].detail, "Something was researched.")
	assert_true(ChronicleModel.IMAGES.has(String(items[0].image)))


func test_a_rivals_private_business_is_never_announced_fog_or_not() -> void:
	var s := _state()
	var private := []
	for t in ["income", "recruited", "research_gained", "research_done", "mending", "ruler_healed", "path_healed", "blessing_healed", "sacrificed",
			"order_rejected", "construction_started", "walls_repaired", "blood_paid"]:
		private.append(_event(t, ["blackwood"], [CLANS], [], {"gold_before": 1, "gold_after": 2, "income": 1, "node": "beasts_boar_hide"}))
	assert_eq(ChronicleModel.build({"turn": 3, "events": private}, s, CROWN), [], "nothing of the Clans' own business is the Crown's news")
	var own := ChronicleModel.build({"turn": 3, "events": private.map(func(e): var c: Dictionary = e.duplicate(true); c.factions = [CROWN]; return c)}, s, CROWN)
	assert_true(own.size() >= 8, "while the same events of the Crown's own are (%d)" % own.size())


func test_the_viewers_own_marches_and_the_games_end_are_not_announced() -> void:
	var s := _state()
	var moved := _event("army_moved", ["crownkeep", "westwatch"], [CROWN], ["kingdom-1"], {}, "The Aurel Crown army moved.")
	var over := _event("game_over", ["crownkeep"], [CLANS], [], {"winner": CLANS}, "The game is over.")
	var folded := _event("army_changed", ["crownkeep"], [CROWN], ["kingdom-1"], {}, "Your army now holds 5 fighters.")
	assert_eq(ChronicleModel.build({"turn": 3, "events": [moved, over, folded]}, s, CROWN), [])


# --- real turns: grouping ------------------------------------------------------------------------------------

func _army(s: GameState, id: String, owner: String, loc: String, types: Array) -> void:
	var a := Army.new()
	a.id = id
	a.owner = owner
	a.location = loc
	for t in types:
		a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(owner), t), owner))
	s.armies.append(a)


## One turn with the four shapes of the grouping rule, resolved for real: the Crown wins at Wildmoor and takes it (a battle with its capture),
## loses at Blackwood (a battle without a capture), and walks into empty Deepwood (a capture without a battle).
func _grouping_turn() -> Dictionary:
	var s := GameState.new(8)
	s.armies.clear()
	for pid in ["thornvale", "stonegate", "greenglade", "highcrag", "westwatch"]:
		s.find_province(pid).owner = CROWN
	for pid in ["wildmoor", "blackwood", "deepwood", "fangridge", "bloodfen", "ebonpeak", "ironspike"]:
		s.find_province(pid).owner = CLANS
	_army(s, "kingdom-1", CROWN, "thornvale", ["knights", "knights", "knights", "knights"])
	_army(s, "kingdom-2", CROWN, "stonegate", ["spearmen"])
	_army(s, "kingdom-3", CROWN, "greenglade", ["spearmen", "spearmen"])
	_army(s, "beasts-1", CLANS, "wildmoor", ["war_bear"])
	_army(s, "beasts-2", CLANS, "blackwood", ["war_bear", "war_bear", "tuskers", "tuskers"])
	var orders := {CROWN: [MoveOrder.new("kingdom-1", "wildmoor"), MoveOrder.new("kingdom-2", "blackwood"), MoveOrder.new("kingdom-3", "deepwood")], CLANS: []}
	var r := TurnResolver.resolve(s, orders, 1, AutoBattleResolver.new())
	return {"report": {"turn": 1, "events": r.events, "header": "Turn 1", "fog": false}, "state": r.new_state}


## The cards of a place that are about what happened there: not the rivals' marches (in a game without fog the Clans see every Crown march).
func _by_place(items: Array, place: String) -> Array:
	return items.filter(func(it): return String(it.place) == place and String(it.type) != "army_moved")


func test_a_battle_and_the_capture_of_its_province_are_one_card_and_nothing_else_groups() -> void:
	var t := _grouping_turn()
	var types: Variant = t.report.events.map(func(e): return e.type)
	assert_eq(types.filter(func(x): return x == "battle").size(), 2, "two battles")
	assert_eq(types.filter(func(x): return x == "captured").size(), 2, "two captures")
	var items := ChronicleModel.build(t.report, t.state, CROWN)
	var wildmoor := _by_place(items, "Wildmoor")
	assert_eq(wildmoor.size(), 1, "the battle at Wildmoor and its capture are one card")
	assert_eq(wildmoor[0].image, "province_taken", "wearing the bigger news")
	assert_eq(wildmoor[0].source_rows.size(), 2, "the battle's row and the capture's row")
	assert_true(String(wildmoor[0].headline).contains("Won at Wildmoor") and String(wildmoor[0].headline).contains("province taken"), wildmoor[0].headline)
	assert_true(wildmoor[0].important and wildmoor[0].battle is Dictionary and not wildmoor[0].battle.is_empty(), "a battle you fought: important, with its report")
	assert_eq(wildmoor[0].facts, {"battle": "won", "province": 1}, "the summary counts both")
	var blackwood := _by_place(items, "Blackwood")
	assert_eq(blackwood.size(), 1, "a battle without a capture stands alone")
	assert_eq(blackwood[0].image, "army_lost", "and says an army was lost")
	assert_eq(blackwood[0].source_rows.size(), 1)
	var deepwood := _by_place(items, "Deepwood")
	assert_eq(deepwood.size(), 1, "a capture without a battle stands alone")
	assert_eq(deepwood[0].image, "province_taken")
	assert_eq(deepwood[0].kind, "land")
	assert_true(deepwood[0].battle.is_empty(), "with no battle to watch")
	# The Clans' side of the same turn: a lost battle and a lost province are one card; the win at Blackwood stands alone.
	var clans := ChronicleModel.build(t.report, t.state, CLANS)
	var w := _by_place(clans, "Wildmoor")
	assert_eq(w.size(), 1)
	assert_eq(w[0].image, "province_lost")
	assert_eq(_by_place(clans, "Blackwood")[0].image, "battle_won")
	assert_eq(_by_place(clans, "Deepwood")[0].image, "province_lost")
	# Every event row is somewhere: a card's source_rows hold every row of the report that makes news.
	var rows := 0
	for it in items:
		rows += (it.source_rows as Array).size()
	assert_true(rows >= 5, "the cards carry the report's rows (%d)" % rows)


func test_several_battles_and_several_captures_make_one_card_each_in_report_order() -> void:
	var t := _grouping_turn()
	var items := ChronicleModel.build(t.report, t.state, CROWN)
	var ids := items.map(func(it): return it.id)
	var unique := {}
	for id in ids:
		unique[id] = true
	assert_eq(unique.size(), ids.size(), "stable, unique ids: %s" % [ids])
	for it in items:
		assert_true(String(it.id).begins_with("t1.e"), "turn plus event index: %s" % it.id)
	# The same report built twice gives the same ids and texts: a pin, a dismissal and a sidecar can rely on them.
	assert_eq(JSON.stringify(ChronicleModel.build(t.report, t.state, CROWN)), JSON.stringify(items), "deterministic")


func test_a_recruit_line_stays_as_the_report_merges_it() -> void:
	var s := GameState.new(8)
	s.armies.clear()
	_army(s, "kingdom-1", CROWN, "crownkeep", ["spearmen"])
	var recruits := []
	for i in 3:
		recruits.append(RecruitOrder.new("knights"))
	var r := TurnResolver.resolve(s, {CROWN: recruits, CLANS: []}, 1, AutoBattleResolver.new())
	var report := {"turn": 1, "events": r.events, "header": "Turn 1", "fog": false}
	var rows := TurnReportText.rows(r.events, r.new_state, CROWN)
	var recruited_rows := rows.filter(func(row): return row.event.type == "recruited")
	var items := ChronicleModel.build(report, r.new_state, CROWN).filter(func(it): return it.type == "recruited")
	assert_eq(items.size(), recruited_rows.size(), "one card per report row: the folded recruit line is one card")
	assert_eq(items.size(), 1, "three knights at one place are one line")
	assert_true(String(items[0].headline).contains("3 Knights") or String(items[0].headline).contains("Knights"), items[0].headline)
	assert_eq(items[0].source_rows, [recruited_rows[0].text], "its full row")
	assert_eq(items[0].image, "recruits_raised")


func test_the_muster_events_are_announced_for_their_owner_only() -> void:
	var s := Kit.game("m1")
	var crown := Kit.crown(s)
	var other := Kit.army(s, CROWN, crown.location, ["spearmen"])
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer(crown.id, "", [0, 1]), MusterOrder.merge(other.id, crown.id), MusterOrder.swap(crown.id, other.id)]})
	var kinds: Variant = r.events.map(func(e): return e.type)
	assert_true(kinds.has("army_split") or kinds.has("units_transferred") or kinds.has("armies_merged"), "the pass made muster events: %s" % [kinds])
	var report := {"turn": 1, "events": r.events, "header": "Turn 1", "fog": false}
	var mine := ChronicleModel.build(report, r.new_state, CROWN).filter(func(it): return it.image == "muster")
	assert_true(mine.size() >= 1, "the Crown's musters are announced (%d)" % mine.size())
	for it in mine:
		assert_eq(it.kind, "realm")
		assert_true(it.routine or String(it.detail).contains("under"), "a plain muster you ordered is quiet: %s" % it.detail)
		assert_false(String(it.detail).is_empty())
	assert_eq(ChronicleModel.build(report, r.new_state, CLANS).filter(func(it): return it.image == "muster"), [], "the Clans are never told of the Crown's musters")


func test_a_muster_that_leaves_fighters_outside_a_blessing_is_worth_a_medallion() -> void:
	var s := Kit.game("magic")
	var crown := Kit.crown(s)
	var enchantment := Kit.bless(s, CROWN, "crownkeep")
	var plain := Kit.army(s, CROWN, "crownkeep", ["knights"])  # raised after the casting: not under the blessing
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer(plain.id, crown.id, [0])]})
	var events: Array = Kit.events(r, "units_transferred")
	assert_eq(events.size(), 1, "the transfer made its event")
	assert_false((events[0].numbers.outside as Array).is_empty(), "with the blessing's 'outside' count: %s" % [events[0].numbers])
	var report := {"turn": 1, "events": r.events, "header": "Turn 1", "fog": false}
	var items := ChronicleModel.build(report, r.new_state, CROWN).filter(func(it): return it.type == "units_transferred")
	assert_eq(items.size(), 1)
	assert_false(items[0].routine, "fighters left outside their blessing: a medallion, so the player knows")
	assert_true(String(items[0].detail).contains(" under "), "and the detail says it: %s" % items[0].detail)
	assert_eq(ChronicleModel.build(report, r.new_state, CLANS).filter(func(it): return it.image == "muster"), [], "a rival is never told")
	assert_true(enchantment != "")


# --- the order, the filter, the summary ----------------------------------------------------------------------------

func _mixed() -> Array:
	var t := _grouping_turn()
	var items := ChronicleModel.build(t.report, t.state, CROWN)
	var need := ChronicleModel.need_items([{"key": "research", "kind": "research", "text": "Choose what to research: 3 research is waiting.", "province": "",
		"codex": "research_order", "variant": "research"}], t.state, 1)
	return need + items


func test_importance_puts_needs_first_then_battles_land_and_the_realm() -> void:
	var order := ChronicleModel.sorted(_mixed(), "importance")
	assert_eq(order[0].kind, "needs_you", "needs you first")
	var ranks := order.map(func(it): return int(it.rank))
	var sorted_ranks := ranks.duplicate()
	sorted_ranks.sort()
	assert_eq(ranks, sorted_ranks, "by rank")
	var kinds := order.map(func(it): return it.kind)
	assert_true(kinds.find("battles") < kinds.find("land"), "battles you fought before your land")
	assert_true(kinds.find("land") < kinds.find("realm"), "your land before your realm")
	assert_eq(ChronicleModel.RANKS.needs_you, 0)
	var spec := ["needs_you", "fought", "army_lost", "your_land", "land_seen", "rulers", "magic", "realm", "abroad"]
	for i in spec.size() - 1:
		assert_true(int(ChronicleModel.RANKS[spec[i]]) < int(ChronicleModel.RANKS[spec[i + 1]]), "%s before %s" % [spec[i], spec[i + 1]])


func test_sorting_by_place_and_by_kind_is_stable() -> void:
	var items := _mixed()
	var places := ChronicleModel.sorted(items, "place").map(func(it): return String(it.place))
	var named := places.filter(func(p): return not p.is_empty())
	var sorted_names := named.duplicate()
	sorted_names.sort_custom(func(a, b): return a.to_lower() < b.to_lower())
	assert_eq(named, sorted_names, "A to Z")
	assert_true(places.slice(places.size() - places.count("")).all(func(p): return p.is_empty()), "no place last")
	var kinds := ChronicleModel.sorted(items, "kind").map(func(it): return ChronicleModel.KINDS.find(String(it.kind)))
	var sorted_kinds := kinds.duplicate()
	sorted_kinds.sort()
	assert_eq(kinds, sorted_kinds, "grouped by kind")
	assert_eq(JSON.stringify(ChronicleModel.sorted(items, "importance")), JSON.stringify(ChronicleModel.sorted(items.duplicate(true), "importance")), "deterministic")


func test_filtering_and_counting() -> void:
	var items := _mixed()
	var counts := ChronicleModel.counts(items)
	assert_eq(counts.needs_you, 1)
	assert_eq(counts.battles, 2)
	assert_eq(counts.land, 1)
	var shown := ChronicleModel.filtered(items, ["battles", "realm"])
	assert_eq(shown.size(), items.size() - int(counts.battles) - int(counts.realm), "hidden kinds are not listed")
	assert_eq(ChronicleModel.counts(items).battles, 2, "but still counted")
	assert_eq(ChronicleModel.filtered(items, []).size(), items.size())


func test_the_summary_line_counts_what_happened() -> void:
	var t := _grouping_turn()
	var items := ChronicleModel.build(t.report, t.state, CROWN)
	var sum := ChronicleModel.summary(items, t.report, t.state, CROWN)
	var texts: Variant = sum.chips.map(func(c): return String(c.text))
	assert_true(texts.has("1 battle won"), "%s" % [texts])
	assert_true(texts.has("1 army lost"), "%s" % [texts])
	assert_true(texts.has("+2 provinces"), "Wildmoor and Deepwood: %s" % [texts])
	assert_false(sum.gold.is_empty(), "the gold line")
	var income: Variant = t.report.events.filter(func(e): return e.type == "income" and e.factions[0] == CROWN)[0]
	assert_eq(sum.gold.text, "Gold %d → %d, +%d a turn" % [income.numbers.gold_before, income.numbers.gold_after, income.numbers.income], "5 → 23, +18 a turn")
	var rival := ChronicleModel.summary(ChronicleModel.build(t.report, t.state, CLANS), t.report, t.state, CLANS)
	var rt: Variant = rival.chips.map(func(c): return String(c.text))
	assert_true(rt.has("1 battle won") and rt.has("-2 provinces"), "the Clans: %s" % [rt])
	var quiet := ChronicleModel.summary([], {"events": []}, t.state, CROWN)
	assert_true(quiet.empty, "a quiet turn has no chips")


func test_the_summary_names_the_units_a_turn_raised_and_a_rivals_gains() -> void:
	var s := GameState.new(8)
	s.armies.clear()
	_army(s, "kingdom-1", CROWN, "crownkeep", ["spearmen"])
	var r := TurnResolver.resolve(s, {CROWN: [RecruitOrder.new("knights"), RecruitOrder.new("knights")], CLANS: []}, 1, AutoBattleResolver.new())
	var report := {"turn": 1, "events": r.events, "header": "Turn 1", "fog": false}
	var items := ChronicleModel.build(report, r.new_state, CROWN)
	var chips: Variant = ChronicleModel.summary(items, report, r.new_state, CROWN).chips.map(func(c): return String(c.text))
	assert_true(chips.has("+2 Knights"), "+2 Knights: %s" % [chips])
	var t := _grouping_turn()
	var seen := [{"facts": {"seen_capture": CLANS}}, {"facts": {"seen_capture": CLANS}}]
	var abroad: Variant = ChronicleModel.summary(seen, {"events": []}, t.state, CROWN).chips.map(func(c): return String(c.text))
	assert_true(abroad.has("Clans +2 provinces"), "Clans +2 provinces: %s" % [abroad])


# --- opening, needs, pins ------------------------------------------------------------------------------------------

func test_the_start_of_a_turn_opens_on_important_news_at_the_battle() -> void:
	var items := _mixed()
	var important := ChronicleModel.auto_open(items, "important")
	assert_true(important.open, "a battle you fought and land won opens it")
	var at: Dictionary = items.filter(func(it): return it.id == important.at)[0]
	assert_false(at.battle.is_empty(), "at the battle's own card, its report a click away")
	assert_true(ChronicleModel.auto_open(items, "needs_you").open)
	assert_true(ChronicleModel.auto_open(items, "always").open)
	assert_false(ChronicleModel.auto_open(items, "never").open)
	assert_false(ChronicleModel.auto_open(items, "report").open, "the full report is a modal, not the column")
	var quiet := items.filter(func(it): return not it.important)
	assert_false(ChronicleModel.auto_open(quiet, "important").open, "a quiet turn doesn't nag")
	assert_false(ChronicleModel.auto_open(quiet, "needs_you").open)
	assert_true(ChronicleModel.auto_open([], "always").open, "except by the player's own choice: every turn")
	var land_only := items.filter(func(it): return it.type == "captured")
	assert_true(ChronicleModel.auto_open(land_only, "important").open, "land won opens it with no battle")


func test_the_needs_are_one_pure_function_for_both_screens() -> void:
	var s := GameState.with_paths(8)
	var none := ChronicleModel.needs(s, CROWN, 1)
	var research := none.filter(func(n): return n.kind == "research")
	assert_eq(research.size(), 1, "no research target: the research need")
	assert_eq(String(research[0].text), PathView.needs_you(s, CROWN), "the same words the Turn report had")
	assert_eq(research[0].codex, "research_order")
	assert_eq(ChronicleModel.needs(s, CROWN, 1, [ResearchOrder.new("crown_drillyard")]).filter(func(n): return n.kind == "research").size(), 0, "settled once a research order is queued")
	var sieges := GameState.with_sieges(8, {}, {"rulers": true})
	assert_eq(ChronicleModel.needs(sieges, CROWN, 1), FortView.needs_you(sieges, CROWN, 1).map(func(l): return {"key": "siege.%s" % l.province, "kind": "siege",
		"text": l.text, "province": l.province, "codex": l.codex, "variant": l.codex}), "and the siege lines, as FortView writes them")
	var items := ChronicleModel.need_items(research, s, 1)
	assert_eq(items[0].id, "need.research.t1")
	assert_eq(items[0].kind, "needs_you")
	assert_true(items[0].important)
	assert_eq(items[0].image, "needs_you")


func test_a_pin_keeps_a_json_safe_payload_without_the_battle_log() -> void:
	var t := _grouping_turn()
	var items := ChronicleModel.build(t.report, t.state, CROWN)
	var battle: Dictionary = _by_place(items, "Wildmoor")[0]
	battle.battle.numbers["log"] = {"events": [1, 2, 3], "sides": []}
	var payload := ChronicleModel.pin_payload(battle)
	assert_false(payload.battle.numbers.has("log"), "the log is dropped")
	assert_true(battle.battle.numbers.has("log"), "and the live card keeps it")
	var back = JSON.parse_string(JSON.stringify(payload))
	var restored := ChronicleModel.from_payload(back)
	assert_eq(restored.headline, battle.headline)
	assert_eq(restored.detail, battle.detail)
	assert_eq(restored.turn, 1)
	assert_true(restored.turn is int, "whole numbers come back as ints")
	assert_eq(restored.battle.numbers.report.sides.size(), battle.battle.numbers.report.sides.size(), "the report stays, so Battle report still opens")
	assert_eq(restored.source_rows, battle.source_rows)
