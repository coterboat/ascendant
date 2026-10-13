class_name ChronicleModel
extends RefCounted
## UX-6 (design/UX_WAR_TABLE.md §5.2): the Chronicle's Read side, as pure code. Nodes, scenes and the session are not here; the
## model turns the VIEWER'S report (GameSession.turn_report_for, filtered for fog exactly as the Turn report reads it) and the state
## as the viewer sees it (GameSession.state_for) into announcements, so a medallion, a card and a pin can only ever say what the
## viewer's own report says. Nothing here reads a state it was not handed, and the report's own text, the records and
## TurnReportText do not change.
##
## An ANNOUNCEMENT is a Dictionary:
##   id           "t<turn>.e<event index>" (the index of the first event it came from), or "need.<key>.t<turn>" for a current-state need
##   turn         the turn the report describes
##   kind         one of KINDS: the filter chip it belongs to
##   image        one of IMAGES: which medallion it wears (UX-ART paints one per key; assets/ui/notices/<image>.png)
##   rank         the importance rank (lower first): Needs you, battles you fought, an army lost, your land, rivals' land seen,
##                rulers, magic, realm, seen abroad
##   headline     a short line; detail  one or two sentences
##   province     the focus target ("" for none); place its name
##   codex        the RulesCodex entry the "?" opens ("" for none)
##   battle       the battle event for Watch and Battle report ({} for none)
##   source_rows  the full TurnReportText rows it came from (what the card expands to)
##   important    true opens the Chronicle at the start of a turn (a battle you fought, an army lost, land won or lost, a need)
##   routine      true is quiet: no medallion and no unread badge (the treasury, healing, sightings, a muster you ordered)
##   own          it concerns the viewer
##   type         the primary event type; index its event index; facts what the summary line counts
##
## HEADLINES AND DETAILS are TABLE's templates over each event's own fields, not cuts of the report's prose: a template is
## [kind, image, rank, headline, detail, flags] and {name} is filled from fields() (an event's numbers and the names in the viewer's
## state), {row} being the whole TurnReportText row. A template whose placeholder has no value (a fog-rebuilt event holds only its safe
## numbers) falls back to the image's title and the row, so nothing is lost; an event type with no template falls back the same way, by
## its phase (kind_of_phase). FogData.AUDIENCE decides whose events a viewer announces: its own, and the public ones of others
## (a rival's capture, a ruler's death); the private ones of a rival (its recruits, its gold) are never announced, fog or not.
##
## GROUPING is explicit: a battle and the capture of the same province on the same turn make one card (the capture joins the last
## battle fought at that province); a recruit line stays as TurnReportText merges it; nothing else groups.
##
## API (all static):
##   build(report, state, viewer, opts = {}) -> Array       the announcements of a report (opts: "before" the viewer's view at the start
##                                                          of the turn, for "what you didn't see"; "needs" a needs() list)
##   needs(state, viewer, report_turn, orders = []) -> Array   the current-state "needs you" lines (research, sieges): [{"key", "kind",
##                                                          "text", "province", "codex", "variant"}], both screens use it
##   need_items(needs, state, turn) -> Array                the needs as announcements
##   sorted(items, mode) / filtered(items, hidden_kinds) / counts(items)   the list the column and the stack show
##   summary(items, report, state, viewer) -> Dictionary    the line that heads the column
##   auto_open(items, mode) -> Dictionary                   {"open": bool, "at": id} for the start of a turn
##   pin_payload(item) / from_payload(payload)              what a pinned card keeps (no battle log)
##   image_keys() / image_info(key)                         the medallion types, for the art

const KINDS := ["needs_you", "battles", "land", "rulers", "magic", "realm", "abroad"]
const KIND_NAMES := {"needs_you": "Needs you", "battles": "Battles", "land": "Land", "rulers": "Rulers", "magic": "Magic",
	"realm": "Realm", "abroad": "Seen abroad"}
## The icon of each kind (UiIcons, except "flag", which the medallion draws itself), and what the chip's tooltip says.
const KIND_ICONS := {"needs_you": "needs-you", "battles": "battle", "land": "flag", "rulers": "ruler", "magic": "magic",
	"realm": "gold", "abroad": "sight"}
const KIND_HELP := {
	"needs_you": "Orders that were refused, and things only you can settle: research waiting for a choice, a fort under siege.",
	"battles": "Battles you fought, armies lost, sieges, storms and sallies.",
	"land": "Provinces taken and lost, fealty sworn, forts built and razed.",
	"rulers": "Rulers fallen and returned, sacrifices and the ruler's healing.",
	"magic": "Rituals cast and fallen, spells learned, enchantments and curses.",
	"realm": "Your treasury, the troops you raised, research done and your people's path.",
	"abroad": "What you saw of your rivals: marches, captures and heralds.",
}
## Importance, lowest first. The default order of the list and the stack: needs you, battles you fought, an army lost, your land, rivals'
## land seen, rulers, magic, realm, seen abroad.
const RANKS := {"needs_you": 0, "fought": 10, "army_lost": 11, "fought_minor": 15, "your_land": 20, "your_land_minor": 25,
	"land_seen": 30, "rulers": 40, "rulers_minor": 45, "magic": 50, "realm": 60, "realm_minor": 65, "abroad": 90}
const SORTS := ["importance", "place", "kind"]
const SORT_NAMES := {"importance": "Importance", "place": "Place", "kind": "Kind"}
## When the Chronicle opens by itself at the start of a turn (a setting). "report" is the old way: today's full report, as a modal.
const AUTO_OPEN := ["important", "needs_you", "always", "never", "report"]
const AUTO_OPEN_NAMES := {"important": "Important turns", "needs_you": "Needs you only", "always": "Every turn", "never": "Never",
	"report": "Full report"}
const AUTO_OPEN_HELP := {
	"important": "Opens at the start of a turn when something important happened: a battle you fought (at its card, its report a click away), an army lost, land won or lost, or anything that needs you. Quiet turns only light the medallions.",
	"needs_you": "Opens at the start of a turn only when something needs you: a refused order, research waiting for a choice, a fort under siege.",
	"always": "Opens at the start of every turn.",
	"never": "Never opens by itself: the medallions and the badge on the Chronicle button tell you there is news.",
	"report": "The old way: today's full turn report opens in front of the map at the start of every turn.",
}

## The medallion types. Each has its own round image (UX-ART paints them; until then the kind's disc with its icon). `tone` is the
## outcome ring ("good", "bad", "" for none): colour is never the only channel, the medallion also carries a + or a - for it.
const IMAGES := {
	"needs_you": {"kind": "needs_you", "icon": "needs-you", "tone": "", "title": "Needs you"},
	"battle_won": {"kind": "battles", "icon": "battle", "tone": "good", "title": "A battle won"},
	"battle_lost": {"kind": "battles", "icon": "battle", "tone": "bad", "title": "A battle lost"},
	"army_lost": {"kind": "battles", "icon": "garrison", "tone": "bad", "title": "An army lost"},
	"siege_begun": {"kind": "battles", "icon": "siege", "tone": "", "title": "A siege begun"},
	"walls_breached": {"kind": "battles", "icon": "walls", "tone": "", "title": "Walls breached"},
	"siege_ended": {"kind": "battles", "icon": "siege", "tone": "", "title": "A siege lifted or ended"},
	"order_void": {"kind": "battles", "icon": "march", "tone": "", "title": "A storm or sally that came to nothing"},
	"province_taken": {"kind": "land", "icon": "flag", "tone": "good", "title": "A province taken"},
	"province_lost": {"kind": "land", "icon": "flag", "tone": "bad", "title": "A province lost"},
	"province_seen": {"kind": "abroad", "icon": "flag", "tone": "", "title": "A rival takes a province"},
	"fealty_to_you": {"kind": "land", "icon": "flag", "tone": "good", "title": "Fealty sworn to you"},
	"fealty_to_rival": {"kind": "abroad", "icon": "flag", "tone": "", "title": "Fealty sworn to a rival"},
	"fealty_contested": {"kind": "land", "icon": "flag", "tone": "", "title": "Fealty sought by two"},
	"fort_built": {"kind": "land", "icon": "fortify", "tone": "", "title": "A fort finished or raised"},
	"fort_works": {"kind": "land", "icon": "fortify", "tone": "", "title": "Fort works begun, halted or razed"},
	"terrain_changed": {"kind": "land", "icon": "flag", "tone": "", "title": "The land changed"},
	"raided": {"kind": "land", "icon": "gold", "tone": "", "title": "Gold raided"},
	"ruler_fallen": {"kind": "rulers", "icon": "ruler", "tone": "bad", "title": "A ruler fallen"},
	"ruler_returned": {"kind": "rulers", "icon": "ruler", "tone": "good", "title": "A ruler returned"},
	"sacrifice": {"kind": "rulers", "icon": "ruler", "tone": "", "title": "Power given up"},
	"healing": {"kind": "rulers", "icon": "hp", "tone": "", "title": "The wounded healed"},
	"spell_learned": {"kind": "magic", "icon": "magic", "tone": "good", "title": "A spell learned"},
	"ritual_cast": {"kind": "magic", "icon": "magic", "tone": "", "title": "A ritual cast"},
	"research_done": {"kind": "realm", "icon": "research", "tone": "good", "title": "Research done"},
	"recruits_raised": {"kind": "realm", "icon": "recruit", "tone": "", "title": "Recruits raised"},
	"treasury": {"kind": "realm", "icon": "gold", "tone": "", "title": "The treasury"},
	"transformed": {"kind": "realm", "icon": "research", "tone": "good", "title": "Your people transformed"},
	"oath_sworn": {"kind": "realm", "icon": "research", "tone": "", "title": "An Oath sworn"},
	"muster": {"kind": "realm", "icon": "orders", "tone": "", "title": "Armies split, joined or swapped"},
	"army_seen": {"kind": "abroad", "icon": "march", "tone": "", "title": "A rival army on the move"},
	"sighting": {"kind": "abroad", "icon": "sight", "tone": "", "title": "A sighting"},
}

const FLAG_ROUTINE := "r"
const FLAG_IMPORTANT := "i"
const FLAG_OWN := "o"

## type -> variant -> [kind, image, rank, headline, detail, flags]. See the header. The variant of an event is variant().
const TABLE := {
	"order_rejected": {"default": ["needs_you", "needs_you", "needs_you", "{order} refused", "{reason}", "io"]},
	"army_moved": {"seen": ["abroad", "army_seen", "abroad", "{Who} on the move", "An army of {who} marched from {from} to {to}.{size}", "r"]},
	"battle": {
		"won": ["battles", "battle_won", "fought", "Won at {place}", "You beat {foe}: {toll}.", "io"],
		"lost": ["battles", "battle_lost", "fought", "Lost at {place}", "{Foe} beat you: {toll}.", "io"],
		"army_lost": ["battles", "army_lost", "army_lost", "Army lost at {place}", "{Foe} destroyed {armies}: {toll}.", "io"],
	},
	"captured": {
		"taken": ["land", "province_taken", "your_land", "{place} taken", "{place} is yours now. It pays {income} gold a turn.{capital}", "io"],
		"lost": ["land", "province_lost", "your_land", "{place} lost", "{place} passes to {who}. It paid you {income} gold a turn.{capital}", "io"],
		"seen": ["abroad", "province_seen", "land_seen", "{Who} took {place}", "{place} passes to {who}.", ""],
	},
	"vassal_joined": {
		"you": ["land", "fealty_to_you", "your_land", "{place} swore fealty to you", "{place} joined you without a fight. It pays {income} gold a turn.", "io"],
		"rival": ["abroad", "fealty_to_rival", "land_seen", "{place} swore fealty to {who}", "{place} joined {who} without a fight.", ""],
	},
	"vassal_contested": {
		"you": ["land", "fealty_contested", "your_land_minor", "{place} joined nobody", "{place} was sought by both {factions}, so it joined nobody this turn.", "o"],
		"rival": ["abroad", "fealty_contested", "abroad", "{place} joined nobody", "{place} was sought by both {factions}.", ""],
	},
	"raided": {"raider": ["realm", "raided", "realm", "Raided {place}", "You took {gold} gold from {place}.", "o"]},
	"siege_started": {
		"besieged": ["battles", "siege_begun", "fought", "{place} is besieged", "{Besieger} laid siege: the walls dropped to {walls} of {walls_max}.", "o"],
		"besieging": ["battles", "siege_begun", "fought", "You besiege {place}", "The walls dropped from {walls_before} to {walls} of {walls_max}.", "o"],
	},
	"walls_damaged": {
		"besieged": ["battles", "siege_begun", "fought", "Walls at {place}: {walls} of {walls_max}", "Siege turn {turn_of_siege}: the walls dropped from {walls_before} to {walls}.", "o"],
		"besieging": ["battles", "siege_begun", "fought", "Walls at {place}: {walls} of {walls_max}", "Siege turn {turn_of_siege}: the walls dropped from {walls_before} to {walls}.", "o"],
	},
	"walls_breached": {"default": ["battles", "walls_breached", "fought", "Walls of {place} are down", "If both sides are still there next turn ({battle_turn}), they fight in the open.", "o"]},
	"siege_lifted": {"default": ["battles", "siege_ended", "fought_minor", "Siege of {place} lifted", "{row}", "o"]},
	"siege_ended": {"default": ["battles", "siege_ended", "fought", "{place} fell", "{row}", "o"]},
	"storm_called_off": {"default": ["battles", "order_void", "fought_minor", "Storm called off at {place}", "{row}", "o"]},
	"sally_called_off": {"default": ["battles", "order_void", "fought_minor", "Sally called off at {place}", "{row}", "o"]},
	"sally_found_nothing": {"default": ["battles", "order_void", "fought_minor", "The sally at {place} found nothing", "{row}", "o"]},
	"fort_built": {
		"you": ["land", "fort_built", "your_land", "A {fort} finished at {place}", "Walls {walls}; it takes recruits from turn {recruit_from}.", "o"],
		"rival": ["abroad", "fort_built", "abroad", "{Who} built a fort at {place}", "A {fort} stands at {place}.", ""],
	},
	"fort_raised": {
		"you": ["land", "fort_built", "your_land", "A fort raised at {place}", "{row}", "o"],
		"rival": ["abroad", "fort_built", "abroad", "{Who} raised a fort at {place}", "{row}", ""],
	},
	"construction_started": {"default": ["land", "fort_works", "your_land_minor", "Work begun at {place}", "{row}", "or"]},
	"construction_halted": {"default": ["land", "fort_works", "your_land_minor", "Work halted at {place}", "{row}", "o"]},
	"construction_razed": {
		"owner": ["land", "fort_works", "your_land", "Works razed at {place}", "{Who} razed what you were building there when they took it.", "o"],
		"razer": ["land", "fort_works", "your_land_minor", "You razed works at {place}", "{row}", "o"],
	},
	"walls_repaired": {"default": ["land", "fort_built", "your_land_minor", "Walls repaired at {place}", "Walls {from_walls} to {to_walls} of {walls_max}.", "or"]},
	"wild_spread": {
		"you": ["land", "terrain_changed", "your_land_minor", "{place} turned to forest", "The Wild spread into {place}; it was {from_terrain}.", "o"],
		"rival": ["abroad", "terrain_changed", "abroad", "{place} turned to forest", "The Wild of {who} spread into {place}.", ""],
	},
	"recruited": {"default": ["realm", "recruits_raised", "realm", "Raised {units}", "At {place}, for {cost} gold ({gold_after} left).", "o"]},
	"income": {"default": ["realm", "treasury", "realm_minor", "Treasury +{income}", "Gold {gold_before} to {gold_after}, from {provinces}.", "or"]},
	"research_gained": {"default": ["realm", "research_done", "realm_minor", "Research +{gained}", "{row}", "or"]},
	"research_sold": {"default": ["realm", "treasury", "realm_minor", "Research sold for {gold} gold", "{row}", "or"]},
	"research_done": {
		"node": ["realm", "research_done", "realm", "{node} researched", "{node_kind}, {cost} research.", "o"],
		"spell": ["magic", "spell_learned", "magic", "{node} learned", "{node_kind}, {cost} research.", "o"],
	},
	"transformed": {
		"you": ["realm", "transformed", "realm", "You became the {branch}", "{node} is done: your people are the {branch} now.", "o"],
		"rival": ["abroad", "transformed", "abroad", "{Who} became the {branch}", "Their people are the {branch} now.", ""],
	},
	"oath_sworn": {
		"you": ["realm", "oath_sworn", "realm", "You swore {node}", "You are on the way to becoming the {branch}; {closed} is closed to you for good.", "o"],
		"rival": ["abroad", "oath_sworn", "abroad", "{Who} swore {node}", "{Who} are on the way to becoming the {branch}.", ""],
	},
	"path_healed": {"default": ["realm", "healing", "realm_minor", "The wounded healed", "{row}", "or"]},
	"mending": {"default": ["rulers", "healing", "rulers_minor", "Mending Light", "{row}", "or"]},
	"ruler_healed": {"default": ["rulers", "healing", "rulers_minor", "Your ruler healed", "{row}", "or"]},
	"sacrificed": {"default": ["rulers", "sacrifice", "rulers", "{mandate_name} bought", "{ruler_name} gave up {cost} power: kept power {kept_before} to {kept_after}.", "o"]},
	"ruler_died": {
		"you": ["rulers", "ruler_fallen", "army_lost", "{name} has fallen", "A successor with {successor_power} kept power is due at the end of turn {successor_turn}.", "io"],
		"rival": ["rulers", "ruler_fallen", "rulers", "{name} has fallen", "The ruler of {who} is dead. A successor is due at the end of turn {successor_turn}.", ""],
	},
	"ruler_arrived": {
		"you": ["rulers", "ruler_returned", "rulers", "{name} returns", "{name} stands at {place} again, with {kept_power} kept power.", "o"],
		"rival": ["rulers", "ruler_returned", "rulers", "{name} now rules {who}", "A new ruler, with {kept_power} kept power.", ""],
	},
	"succession_waiting": {
		"you": ["rulers", "ruler_fallen", "rulers", "Your heir waits", "The successor was due by turn {successor_turn} but waits until you hold your capital.", "o"],
		"rival": ["rulers", "ruler_fallen", "rulers", "The heir of {who} waits", "The successor was due by turn {successor_turn} but waits until they hold their capital.", ""],
	},
	"ritual_cast": {
		"you": ["magic", "ritual_cast", "magic", "{ritual} cast", "In effect through turn {until_turn}.", "o"],
		"rival": ["magic", "ritual_cast", "magic", "{Who} cast {ritual}", "In effect through turn {until_turn}.", ""],
	},
	"ritual_fell": {"default": ["magic", "ritual_cast", "your_land", "{ritual} fell on {place}", "Cast by {caster}, through turn {until_turn}.", "o"]},
	"ritual_turned_aside": {"default": ["magic", "ritual_cast", "magic", "A ritual turned aside", "{row}", "o"]},
	"curse_bit": {
		"victim": ["magic", "ritual_cast", "your_land", "{ritual} bit at {place}", "It takes up to {budget} hit points a turn from your fighters there.", "o"],
		"caster": ["magic", "ritual_cast", "magic", "Your {ritual} bit at {place}", "{row}", "o"],
	},
	"enchantment_began": {"default": ["magic", "ritual_cast", "magic", "{ritual} lies on {place}", "In effect through turn {until_turn}.", "o"]},
	"enchantment_ended": {"default": ["magic", "ritual_cast", "magic", "{ritual} ended at {place}", "{row}", "o"]},
	"summoned": {"default": ["magic", "ritual_cast", "magic", "A summoning answered", "{row}", "o"]},
	"summon_faded": {"default": ["magic", "ritual_cast", "magic", "A summoning faded", "{row}", "o"]},
	"far_sight_reading": {"default": ["magic", "ritual_cast", "magic", "Far Sight read {place}", "{row}", "o"]},
	"blood_paid": {"default": ["magic", "ritual_cast", "magic", "Paid in blood", "{row}", "o"]},
	"blessing_healed": {"default": ["magic", "healing", "realm_minor", "A blessing healed the wounded", "{row}", "or"]},
	"army_split": {"default": ["realm", "muster", "realm_minor", "Army split at {place}", "{row}", "or"]},
	"units_transferred": {"default": ["realm", "muster", "realm_minor", "Units moved at {place}", "{row}", "or"]},
	"armies_merged": {"default": ["realm", "muster", "realm_minor", "Armies merged at {place}", "{row}", "or"]},
	"commanders_swapped": {"default": ["realm", "muster", "realm_minor", "Commanders swapped at {place}", "{row}", "or"]},
	"army_disbanded": {"default": ["realm", "muster", "realm_minor", "An army disbanded", "{row}", "or"]},
	"sighting_changed": {"default": ["abroad", "sighting", "abroad", "Sighted at {place}", "{row}", "r"]},
	"sighting_lost": {"default": ["abroad", "sighting", "abroad", "Lost sight at {place}", "{row}", "r"]},
	"memory_added": {"default": ["abroad", "sighting", "abroad", "Out of sight at {place}", "{row}", "r"]},
}
## The event types that make no announcement: the game's end (the victory screen tells it) and the fold of the viewer's own army counts
## (a fog bookkeeping line the full report keeps). The viewer's own moves are skipped too: the board shows them.
const SKIPPED := ["game_over", "army_changed"]
## The event types the resolver and the fog filter make, so a test can hold TABLE to all of them.
const EVENT_TYPES := ["army_moved", "order_rejected", "battle", "border_battle", "captured", "recruited", "income", "wild_spread",
	"walls_repaired", "walls_damaged", "walls_breached", "vassal_joined", "vassal_contested", "transformed", "summoned", "summon_faded",
	"succession_waiting", "siege_started", "siege_lifted", "siege_ended", "sacrificed", "ruler_healed", "ruler_died", "ruler_arrived",
	"ritual_turned_aside", "ritual_fell", "ritual_cast", "research_sold", "research_gained", "research_done", "raided", "path_healed",
	"oath_sworn", "mending", "fort_raised", "fort_built", "far_sight_reading", "enchantment_ended", "enchantment_began", "curse_bit",
	"construction_started", "construction_razed", "construction_halted", "army_disbanded", "army_split", "units_transferred",
	"armies_merged", "commanders_swapped", "blessing_healed", "blood_paid", "storm_called_off", "sally_called_off", "sally_found_nothing",
	"game_over", "sighting_changed", "sighting_lost", "memory_added", "army_changed"]
## A report phase's kind, for an event type that has no template yet.
const PHASE_KINDS := {"orders": "needs_you", "movement": "abroad", "battles": "battles", "sieges": "battles", "capture": "land",
	"recruitment": "realm", "income": "realm", "research": "realm", "rulers": "rulers", "sacrifice": "rulers", "rituals": "magic",
	"enchantments": "magic", "view": "abroad", "victory": "realm"}
## The rank an event type with no template gets, by its kind.
const KIND_RANK := {"needs_you": "needs_you", "battles": "fought_minor", "land": "your_land_minor", "rulers": "rulers", "magic": "magic",
	"realm": "realm", "abroad": "abroad"}
## The codex entry a card falls back to when its event names none.
const CODEX_FALLBACK := {"needs_you": "orders", "battles": "defended", "land": "capture", "rulers": "ruler", "magic": "ritual",
	"realm": "income", "abroad": "sight"}


# --- building -------------------------------------------------------------------------------------

## The announcements of `report` (a GameSession.turn_report_for dictionary) as `viewer` reads it, `state` being the viewer's state
## after the turn. In report order, current-state needs (opts "needs", from needs()) first. Pure.
static func build(report: Dictionary, state: GameState, viewer: String, opts: Dictionary = {}) -> Array:
	var events: Array = report.get("events", [])
	var turn := int(report.get("turn", 0))
	var before: GameState = opts.get("before", null)
	var ctx := {"state": state, "viewer": viewer, "turn": turn, "events": events, "before": before,
		"fog": bool(report.get("fog", false))}
	var items: Array = []
	var battle_at := {}  # province id -> index in `items` of the last battle fought there this turn
	for row in TurnReportText.rows(events, state, viewer, null):
		var e: Dictionary = row.event
		var type := String(e.get("type", ""))
		if SKIPPED.has(type):
			continue
		if type == "captured":
			var provinces: Array = e.get("provinces", [])
			var pid := String(provinces[0]) if not provinces.is_empty() else ""
			if battle_at.has(pid):
				_join_capture(items[int(battle_at[pid])], e, String(row.text), ctx)
				continue
		var item := _describe(e, String(row.text), ctx)
		if item.is_empty():
			continue
		item["index"] = _index_in(events, e)
		item["id"] = "t%d.e%d" % [turn, int(item.index)]
		if type == "battle" and not e.get("provinces", []).is_empty():
			battle_at[String(e.provinces[0])] = items.size()  # the capture of its province joins it; a border battle takes nothing
		if before != null and bool(item.get("own", false)) and not (item.battle as Dictionary).is_empty():
			var missed := FogView.missed_text(e, viewer, before)  # "what you didn't see", under a battle you fought
			if not missed.is_empty():
				item.source_rows.append("What you didn't see: %s" % missed)
		items.append(item)
	var out: Array = []
	out.append_array(need_items(opts.get("needs", []), state, turn))
	out.append_array(items)
	return out


## The first event index of `e` in `events`: the event itself, or (a folded recruit line, which is a copy) the event its first unit's text names.
static func _index_in(events: Array, e: Dictionary) -> int:
	for i in events.size():
		if is_same(events[i], e):
			return i
	var texts: Array = e.get("numbers", {}).get("recruit_texts", [])
	var first := String(texts[0]) if not texts.is_empty() else String(e.get("text", ""))
	for i in events.size():
		if String(events[i].get("type", "")) == String(e.get("type", "")) and String(events[i].get("text", "")) == first:
			return i
	return events.size()


## One event as an announcement, or {} when it makes none.
static func _describe(e: Dictionary, row_text: String, ctx: Dictionary) -> Dictionary:
	var type := String(e.get("type", ""))
	var viewer: String = ctx.viewer
	if type == "army_moved" and _first_faction(e) == viewer:
		return {}  # your own march: the board shows it
	var involved := bool(e.get("synthetic", false)) or _involves(e, viewer)  # a fog fold event is the viewer's own sight
	if not involved and String(FogData.AUDIENCE.get(type, {"others": "none"}).get("others", "none")) == "none":
		return {}  # a rival's private business (its recruits, its gold): not announced, fog or not
	var variant_key := variant(e, ctx)
	if variant_key.is_empty():
		return {}
	var row: Array = []
	var table_type := "battle" if type == "border_battle" else type  # a border battle reads like any battle
	if TABLE.has(table_type) and TABLE[table_type].has(variant_key):
		row = TABLE[table_type][variant_key]
	var fields := fields_of(e, row_text, ctx)
	var kind: String
	var image: String
	var rank: int
	var flags := ""
	var headline := ""
	var detail := ""
	if row.is_empty():
		kind = kind_of_phase(String(e.get("phase", "")))
		image = kind
		rank = int(RANKS[String(KIND_RANK[kind])])
	else:
		kind = String(row[0])
		image = String(row[1])
		rank = int(RANKS[String(row[2])])
		flags = String(row[5])
		headline = _fill(String(row[3]), fields)
		detail = _fill(String(row[4]), fields)
	var place := String(fields.get("place", ""))
	if headline.is_empty():
		headline = String(IMAGES.get(image, {}).get("title", KIND_NAMES.get(kind, "News")))
		if not place.is_empty():
			headline += " · %s" % place
	if detail.is_empty():
		detail = row_text
	var provinces: Array = e.get("provinces", [])
	var focus := _focus(e, type)
	var entry := String(e.get("codex", ""))  # (tests/test_codex_panel.gd scans `codex = ...` lines for string literals: a local var first)
	if not RulesCodex.ENTRIES.has(entry):
		entry = String(CODEX_FALLBACK.get(kind, ""))
	var item := {"turn": ctx.turn, "kind": kind, "image": image, "rank": rank, "headline": headline, "detail": detail,
		"province": focus, "place": _province_name(ctx.state, focus) if not focus.is_empty() else "", "codex": entry,
		"battle": e if GameSession.BATTLE_TYPES.has(type) and involved else {}, "source_rows": [row_text],
		"important": flags.contains(FLAG_IMPORTANT), "routine": flags.contains(FLAG_ROUTINE),
		"own": flags.contains(FLAG_OWN), "type": type, "facts": facts_of(e, variant_key, fields, ctx), "variant": variant_key}
	if GameSession.BATTLE_TYPES.has(type) and not provinces.is_empty():
		item["provinces"] = provinces.duplicate()
	# A muster that left fighters outside their blessing is worth a medallion: the player should know (ARM-1, §2.1).
	if ["army_split", "units_transferred", "armies_merged", "commanders_swapped"].has(type) and not e.get("numbers", {}).get("outside", []).is_empty():
		item["routine"] = false
		item["detail"] = row_text
	return item


## True when the event is the viewer's own business, in the sense of the fog filter's audience table.
static func _involves(e: Dictionary, viewer: String) -> bool:
	var type := String(e.get("type", ""))
	var audience: Dictionary = FogData.AUDIENCE.get(type, {"whole": "actor", "others": "none"})
	var factions: Array = e.get("factions", [])
	match String(audience.whole):
		"all":
			return true
		"factions":
			return factions.has(viewer)
	return not factions.is_empty() and String(factions[0]) == viewer


static func _first_faction(e: Dictionary) -> String:
	var factions: Array = e.get("factions", [])
	return String(factions[0]) if not factions.is_empty() else ""


## The province a card focuses: where it happened (a march's end, a battle's province), or "".
static func _focus(e: Dictionary, type: String) -> String:
	var provinces: Array = e.get("provinces", [])
	if provinces.is_empty() or ["income", "research_gained", "research_sold"].has(type):
		return ""  # the whole realm's, not one place's
	if type == "army_moved":
		return String(provinces.back())
	return String(provinces[0])


## Which template of an event's type applies, "" for none (the event is not announced).
static func variant(e: Dictionary, ctx: Dictionary) -> String:
	var type := String(e.get("type", ""))
	var viewer: String = ctx.viewer
	var state: GameState = ctx.state
	var factions: Array = e.get("factions", [])
	var numbers: Dictionary = e.get("numbers", {})
	var mine := _first_faction(e) == viewer
	match type:
		"battle", "border_battle":
			if not factions.has(viewer):
				return ""  # a battle the viewer was not in is never announced (the fog audience table: both sides only)
			if String(numbers.get("winner", "")) == viewer:
				return "won"
			return "army_lost" if not _own_destroyed(numbers, viewer).is_empty() else "lost"
		"captured":
			if mine:
				return "taken"
			return "lost" if factions.size() > 1 and String(factions[1]) == viewer else "seen"
		"vassal_joined":
			return "you" if mine else "rival"
		"vassal_contested":
			return "you" if factions.has(viewer) else "rival"
		"raided":
			return "raider" if mine else ""
		"siege_started", "walls_damaged":
			return "besieged" if String(numbers.get("owner", "")) == viewer else "besieging"
		"fort_built", "fort_raised", "wild_spread", "ruler_died", "ruler_arrived", "succession_waiting", "ritual_cast", "transformed", "oath_sworn":
			return "you" if mine else "rival"
		"construction_razed":
			return "owner" if factions.size() > 1 and String(factions[1]) == viewer else "razer"
		"research_done":
			return "spell" if AscensionRules.is_arcana(String(numbers.get("node", ""))) else "node"
		"curse_bit":
			return "victim" if mine else "caster"
		"army_moved":
			return "seen"
	if TABLE.has(type):
		return "default"
	return "default"  # no template: the generic fallback


## The ids of the viewer's own armies a battle destroyed (view ids for a participant, which keep the owner's prefix).
static func _own_destroyed(numbers: Dictionary, viewer: String) -> Array:
	var out := []
	for id in numbers.get("destroyed", []):
		if TurnReportText.faction_of(String(id)) == viewer:
			out.append(String(id))
	return out


# --- fields and templates -------------------------------------------------------------------------

## `{name}` placeholders of `template` filled from `fields`; "" when any has no value (the caller falls back).
static func _fill(template: String, fields: Dictionary) -> String:
	var out := ""
	var i := 0
	while i < template.length():
		var open := template.find("{", i)
		if open < 0:
			out += template.substr(i)
			break
		var close := template.find("}", open)
		if close < 0:
			out += template.substr(i)
			break
		out += template.substr(i, open - i)
		var key := template.substr(open + 1, close - open - 1)
		if not fields.has(key) or str(fields[key]).is_empty() and not FILL_EMPTY_OK.has(key):
			return ""
		out += str(fields[key])
		i = close + 1
	return _cap(out)


## Placeholders that may be empty (an optional sentence tail).
const FILL_EMPTY_OK := ["capital", "size"]


## The placeholders an event offers: its own numbers and the names in the viewer's state. Only what the event holds goes in (a fog-rebuilt
## event holds its safe numbers), so a placeholder with no value is simply missing and the template falls back.
static func fields_of(e: Dictionary, row_text: String, ctx: Dictionary) -> Dictionary:
	var state: GameState = ctx.state
	var viewer: String = ctx.viewer
	var type := String(e.get("type", ""))
	var numbers: Dictionary = e.get("numbers", {})
	var factions: Array = e.get("factions", [])
	var provinces: Array = e.get("provinces", [])
	var f := {}
	for key in numbers:
		var v = numbers[key]
		if v is int or v is float or v is String:
			f[String(key)] = v
	f["row"] = row_text
	if not provinces.is_empty():
		f["place"] = _province_name(state, String(provinces[0]))
		f["from"] = _province_name(state, String(provinces[0]))
		f["to"] = _province_name(state, String(provinces.back()))
	if not factions.is_empty():
		f["who"] = _short(state, String(factions[0]))
		f["Who"] = _cap(String(f.who))
		f["factions"] = RulerRules._and_list(factions.map(func(id): return _short(state, String(id))))
	f["order"] = _order_word(e)
	if e.has("reason"):
		f["reason"] = String(e.reason)
	match type:
		"army_moved":
			# a rival's move you saw carries a glimpsed count ({"text": "about 20"}), never the true one
			var seen = numbers.get("total", 0)
			var count_text := String(seen.get("text", "")) if seen is Dictionary else (str(seen) if int(seen) > 0 else "")
			f["size"] = " %s fighters." % _cap(count_text) if not count_text.is_empty() else ""
		"battle", "border_battle":
			_battle_fields(e, state, viewer, f)
			if type == "border_battle" and provinces.size() > 1:
				f["place"] = "the %s-%s border" % [_province_name(state, String(provinces[0])), _province_name(state, String(provinces[1]))]
		"captured":
			var gone := factions.size() > 1 and String(factions[1]) == viewer
			var note := ""
			if bool(numbers.get("is_capital", false)):
				note = " It was your capital: you cannot recruit until you retake it." if gone \
					else " It is a capital: its owner cannot recruit until they retake it."
			f["capital"] = note
		"recruited":
			var names := TurnReportText._recruit_names(e, state)
			if not names.is_empty() and not String(names[0]).is_empty():
				f["units"] = TurnReportText._units_phrase(names)
		"income":
			var n := (numbers.get("by_province", {}) as Dictionary).size()
			f["provinces"] = TooltipText.count(n, "province") if n > 0 else "your land"
		"siege_started", "walls_damaged":
			f["Besieger"] = _cap(_short(state, String(numbers.get("besieger", ""))))
		"fort_built", "construction_started":
			f["fort"] = SiegeRules.level_word(int(numbers.get("level", numbers.get("to", 1))))
		"walls_repaired":
			f["from_walls"] = int(numbers.get("from", 0))
			f["to_walls"] = int(numbers.get("to", 0))
		"research_done":
			var nid := String(numbers.get("node", ""))
			f["node"] = AscensionRules.node_name(nid)
			f["node_kind"] = _cap(AscensionRules.kind_name(nid))
		"transformed", "oath_sworn":
			f["node"] = AscensionRules.node_name(String(numbers.get("node", "")))
			f["branch"] = AscensionRules.branch_name(String(numbers.get("branch", "")))
			f["closed"] = AscensionRules.branch_name(String(numbers.get("closed", "")))
		"ruler_died":
			f["name"] = String(numbers.get("name", ""))
		"ruler_arrived":
			f["name"] = String(numbers.get("name", ""))
		"sacrificed":
			f["kept_before"] = int(numbers.get("kept_before", 0))
			f["kept_after"] = int(numbers.get("kept_after", 0))
		"ritual_cast", "ritual_fell", "curse_bit", "enchantment_began", "enchantment_ended":
			var rid := String(numbers.get("ritual", ""))
			if not rid.is_empty():
				f["ritual"] = MagicRules.spell_name(rid)
			if type == "ritual_fell":
				f["caster"] = _short(state, String(numbers.get("faction", "")))
		"wild_spread":
			f["from_terrain"] = String(numbers.get("from_terrain", ""))
	return f


## The battle's placeholders: who the viewer fought, the toll on each side, the armies it lost, and who won.
static func _battle_fields(e: Dictionary, state: GameState, viewer: String, f: Dictionary) -> void:
	var numbers: Dictionary = e.get("numbers", {})
	var factions: Array = e.get("factions", [])
	var foes := factions.filter(func(id): return String(id) != viewer)
	if not foes.is_empty():
		f["foe"] = RulerRules._and_list(foes.map(func(id): return _short(state, String(id))))
		f["Foe"] = _cap(String(f.foe))
	f["sides"] = _cap(RulerRules._and_list(factions.map(func(id): return _short(state, String(id)))))
	var winner := String(numbers.get("winner", ""))
	if not winner.is_empty():
		f["Winner"] = _cap(_short(state, winner))
	var mine_start := 0
	var mine_lost := 0
	var their_lost := 0
	var counted := false
	for s in numbers.get("report", {}).get("sides", []):
		counted = true
		if String(s.get("faction", "")) == viewer:
			mine_start += int(s.get("fighters_start", 0))
			mine_lost += int(s.get("fighters_lost", 0))
		else:
			their_lost += int(s.get("fighters_lost", 0))
	if counted:
		var mine := "none of yours fell" if mine_lost == 0 else "%d of your %d fell" % [mine_lost, mine_start]
		var theirs := "none of theirs" if their_lost == 0 else "%d of theirs" % their_lost
		f["toll"] = "%s, %s" % [mine, theirs]
	var lost := _own_destroyed(numbers, viewer)
	if not lost.is_empty():
		f["armies"] = RulerRules._and_list(TurnReportText.sort_ids(lost).map(func(id): return TurnReportText.army_name(state, String(id), viewer)))


## "Move", "Recruit": what a refused order was (its own `order` block), for the headline.
static func _order_word(e: Dictionary) -> String:
	var order: Dictionary = e.get("order", {}) if e.get("order") is Dictionary else {}
	match String(order.get("type", "")):
		"move": return "Move"
		"recruit": return "Recruit"
		"cast": return "Cast"
		"fortify": return "Fortify"
		"research": return "Research"
		"sacrifice": return "Sacrifice"
		"muster": return "Split or merge"
		"siege": return "Siege order"
	return "An order was"


## What the summary line counts from an announcement.
static func facts_of(e: Dictionary, variant_key: String, f: Dictionary, ctx: Dictionary) -> Dictionary:
	var out := {}
	var type := String(e.get("type", ""))
	match type:
		"battle", "border_battle":
			if variant_key == "won":
				out["battle"] = "won"
			elif variant_key == "lost" or variant_key == "army_lost":
				out["battle"] = "lost"
			if variant_key == "army_lost":
				out["army_lost"] = _own_destroyed(e.get("numbers", {}), ctx.viewer).size()
		"captured":
			if variant_key == "taken":
				out["province"] = 1
			elif variant_key == "lost":
				out["province"] = -1
			else:
				out["seen_capture"] = _first_faction(e)
		"vassal_joined":
			if variant_key == "you":
				out["province"] = 1
		"recruited":
			out["units"] = TurnReportText._recruit_names(e, ctx.state).map(func(n): return _bare(String(n)))
		"ruler_died":
			if variant_key == "you":
				out["army_lost"] = 1
	return out


## The capture joins the battle card it followed: the title and detail say both, and the medallion is the bigger of the two.
static func _join_capture(card: Dictionary, e: Dictionary, row_text: String, ctx: Dictionary) -> void:
	var variant_key := variant(e, ctx)
	var fields := fields_of(e, row_text, ctx)
	var place := String(fields.get("place", card.place))
	var taken := variant_key == "taken"
	var lost := variant_key == "lost"
	var tail := "province taken" if taken else ("province lost" if lost else "province taken by %s" % fields.get("who", "a rival"))
	card.headline = "%s · %s" % [card.headline, tail]
	var sentence := "%s is yours now." % place if taken else ("%s passes to %s." % [place, fields.get("who", "a rival")])
	card.detail = "%s %s%s" % [card.detail, sentence, String(fields.get("capital", ""))]
	card.source_rows.append(row_text)
	if taken:
		card.image = "province_taken"
	elif lost:
		card.image = "province_lost"
	card.rank = mini(int(card.rank), int(RANKS["your_land"])) if taken or lost else int(card.rank)
	card.important = bool(card.important) or taken or lost
	var facts: Dictionary = card.facts
	var captured_facts := facts_of(e, variant_key, fields, ctx)
	for key in captured_facts:
		facts[key] = captured_facts[key]
	card["grouped"] = true


# --- needs (the current state, not events) --------------------------------------------------------

## The "needs you" lines the report builds from the state: research waiting for a choice (PathView.needs_you) and forts under siege
## (FortView.needs_you). [{"key", "kind": "research" | "siege", "text", "province", "codex", "variant"}]. A research need goes once a
## research order is queued (`orders`). The Turn report's panel and the Chronicle both read this.
static func needs(state: GameState, viewer: String, report_turn: int, orders: Array = []) -> Array:
	var out := []
	if state == null or viewer.is_empty():
		return out
	var research := PathView.needs_you(state, viewer)
	if not research.is_empty() and not orders.any(func(o): return o is ResearchOrder):
		out.append({"key": "research", "kind": "research", "text": research, "province": "", "codex": "research_order", "variant": "research"})
	for line in FortView.needs_you(state, viewer, report_turn):
		var codex := String(line.codex)
		out.append({"key": "siege.%s" % String(line.province), "kind": "siege", "text": String(line.text), "province": String(line.province),
			"codex": codex, "variant": codex})
	return out


## The needs as announcements, ids "need.<key>.t<turn>".
static func need_items(list: Array, state: GameState, turn: int) -> Array:
	var out := []
	for n in list:
		var pid := String(n.province)
		var place := _province_name(state, pid) if not pid.is_empty() else ""
		var headline := "Choose what to research"
		match String(n.variant):
			"breach":
				headline = "Walls are down at %s" % place
			"siege":
				headline = "%s is besieged" % place
			"storm":
				headline = "You besiege %s" % place
		out.append({"id": "need.%s.t%d" % [String(n.key), turn], "turn": turn, "kind": "needs_you", "image": "needs_you",
			"rank": int(RANKS["needs_you"]), "headline": headline, "detail": String(n.text), "province": pid, "place": place,
			"codex": String(n.codex) if RulesCodex.ENTRIES.has(String(n.codex)) else "orders", "battle": {}, "source_rows": [String(n.text)],
			"important": true, "routine": false, "own": true, "type": "need", "index": -1, "facts": {}, "variant": String(n.variant),
			"need": String(n.key)})
	return out


# --- the list -------------------------------------------------------------------------------------

## `items` in the order of `mode` (SORTS): importance (rank, then the report's order), place (the province's name, then rank), or kind
## (KINDS' order, then rank). A stable sort: ties keep the report's order.
static func sorted(items: Array, mode: String) -> Array:
	var keyed := []
	for i in items.size():
		keyed.append([items[i], i])
	keyed.sort_custom(func(a, b):
		var x: Dictionary = a[0]
		var y: Dictionary = b[0]
		match mode:
			"place":
				var px := String(x.place).to_lower()
				var py := String(y.place).to_lower()
				var ex := px.is_empty()
				var ey := py.is_empty()
				if ex != ey:
					return ey  # announcements with no place last
				if px != py:
					return px < py
			"kind":
				var kx := KINDS.find(String(x.kind))
				var ky := KINDS.find(String(y.kind))
				if kx != ky:
					return kx < ky
		if int(x.rank) != int(y.rank):
			return int(x.rank) < int(y.rank)
		return int(a[1]) < int(b[1]))
	return keyed.map(func(k): return k[0])


## The items whose kind is not in `hidden` (the filter chips).
static func filtered(items: Array, hidden: Array) -> Array:
	return items.filter(func(it): return not hidden.has(String(it.kind)))


## {kind: how many} over `items`.
static func counts(items: Array) -> Dictionary:
	var out := {}
	for k in KINDS:
		out[k] = 0
	for it in items:
		out[String(it.kind)] = int(out.get(String(it.kind), 0)) + 1
	return out


## The announcements that show as medallions and count as unread: not routine ones.
static func notable(items: Array) -> Array:
	return items.filter(func(it): return not bool(it.routine))


# --- the summary ----------------------------------------------------------------------------------

## The line that heads the column: chips such as "1 battle won", "+1 province", "+2 Knights", "Clans +2 provinces", and the gold
## "5 → 23, +18 a turn". {"chips": [{"text", "tip", "tone"}], "gold": {"text", "tip"} or {}, "empty": bool}.
static func summary(items: Array, report: Dictionary, state: GameState, viewer: String) -> Dictionary:
	var won := 0
	var lost := 0
	var armies := 0
	var provinces := 0
	var units := []
	var abroad := {}
	for it in items:
		var facts: Dictionary = it.get("facts", {})
		match String(facts.get("battle", "")):
			"won":
				won += 1
			"lost":
				lost += 1
		armies += int(facts.get("army_lost", 0))
		provinces += int(facts.get("province", 0))
		units.append_array(facts.get("units", []))
		var rival := String(facts.get("seen_capture", ""))
		if not rival.is_empty():
			abroad[rival] = int(abroad.get(rival, 0)) + 1
	var chips := []
	if won > 0:
		chips.append({"text": "%d %s won" % [won, "battle" if won == 1 else "battles"], "tone": "good", "tip": "Battles you fought and won this turn."})
	if lost > 0:
		chips.append({"text": "%d %s lost" % [lost, "battle" if lost == 1 else "battles"], "tone": "bad", "tip": "Battles you fought and lost this turn."})
	if armies > 0:
		chips.append({"text": "%d %s lost" % [armies, "army" if armies == 1 else "armies"], "tone": "bad", "tip": "Armies of yours that were destroyed."})
	if provinces != 0:
		chips.append({"text": "%s%d %s" % ["+" if provinces > 0 else "-", absi(provinces), "province" if absi(provinces) == 1 else "provinces"],
			"tone": "good" if provinces > 0 else "bad", "tip": "Provinces you took or lost this turn, net."})
	if not units.is_empty():
		chips.append({"text": "+%s" % _counted(units), "tone": "", "tip": "Troops you raised this turn."})
	var factions := abroad.keys()
	factions.sort()
	for fid in factions:
		var n := int(abroad[fid])
		chips.append({"text": "%s +%d %s" % [_short_name(state, String(fid)), n, "province" if n == 1 else "provinces"], "tone": "",
			"tip": "Provinces a rival took that you saw."})
	var gold := {}
	for e in report.get("events", []):
		if String(e.get("type", "")) == "income" and _first_faction(e) == viewer:
			var n: Dictionary = e.get("numbers", {})
			if n.has("gold_before") and n.has("gold_after"):
				gold = {"text": "Gold %d → %d, +%d a turn" % [int(n.gold_before), int(n.gold_after), int(n.get("income", 0))],
					"tip": "Your gold at the start of the income phase and after it, and what your provinces pay each turn."}
	return {"chips": chips, "gold": gold, "empty": chips.is_empty() and gold.is_empty()}


## "Clans": a faction's short name without the article, for the summary chips.
static func _short_name(state: GameState, fid: String) -> String:
	return _short(state, fid).trim_prefix("the ")


# --- opening --------------------------------------------------------------------------------------

## What the start of a turn does under `mode` (AUTO_OPEN): {"open": bool, "at": the id of the card to open at ("" for the top)}.
## "important" (the default) opens for a battle you fought (at that battle's card, its report a click away), an army lost, land won or lost,
## anything that needs you, and (later) a special event; "needs_you" only for a need or a refused order; "always" every turn; "never"
## and "report" never open the column (the second shows today's modal instead).
static func auto_open(items: Array, mode: String) -> Dictionary:
	var order := sorted(items, "importance")
	match mode:
		"always":
			return {"open": true, "at": String(order[0].id) if not order.is_empty() else ""}
		"needs_you":
			for it in order:
				if String(it.kind) == "needs_you":
					return {"open": true, "at": String(it.id)}
		"important":
			var first := ""
			for it in order:
				if not bool(it.important):
					continue
				if first.is_empty():
					first = String(it.id)
				if not (it.battle as Dictionary).is_empty():
					return {"open": true, "at": String(it.id)}  # a battle you fought opens at its own card, the report a click away
			if not first.is_empty():
				return {"open": true, "at": first}
	return {"open": false, "at": ""}


# --- what a pin keeps -----------------------------------------------------------------------------

## The payload a pinned card keeps (JSON-safe): exactly what it was shown with. The battle log (which can be large and is kept in memory
## only) is dropped; the battle's report stays, so Battle report still opens.
static func pin_payload(item: Dictionary) -> Dictionary:
	var out: Dictionary = item.duplicate(true)
	var battle: Dictionary = out.get("battle", {})
	if not battle.is_empty() and battle.get("numbers") is Dictionary:
		(battle.numbers as Dictionary).erase("log")
	out.erase("need")
	return out


## A pinned payload read back from JSON: whole numbers are ints again.
static func from_payload(payload: Dictionary) -> Dictionary:
	return _intify(payload)


static func _intify(v):
	if v is float:
		return int(v) if is_equal_approx(v, round(v)) and absf(v) < 1.0e15 else v
	if v is Array:
		return (v as Array).map(func(x): return _intify(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _intify(v[k])
		return out
	return v


# --- names ----------------------------------------------------------------------------------------

static func image_keys() -> Array:
	return IMAGES.keys()


static func image_info(key: String) -> Dictionary:
	return IMAGES.get(key, {})


## The kind of an event type that has no template, from its phase.
static func kind_of_phase(phase: String) -> String:
	return String(PHASE_KINDS.get(phase, "abroad"))


static func _short(state: GameState, fid: String) -> String:
	if fid.is_empty():
		return "a rival"
	return TurnReportText.faction_short(state, fid)


static func _province_name(state: GameState, pid: String) -> String:
	var p: Province = state.find_province(pid) if state != null else null
	if p != null:
		return p.name
	for d in MapData.PROVINCES:
		if String(d.id) == pid:
			return String(d.name)
	return "a place not on the map"


## "2 Knights" and "1 Siege Ram": each unit name once with its count, in the order they first came ("2 Knights and 1 Siege Ram").
static func _counted(names: Array) -> String:
	var order := []
	var counts := {}
	for n in names:
		if not counts.has(n):
			order.append(n)
			counts[n] = 0
		counts[n] += 1
	var parts := []
	for n in order:
		parts.append("%d %s" % [int(counts[n]), String(n) if int(counts[n]) == 1 else TurnReportText._plural_name(String(n))])
	return RulerRules._and_list(parts)


## "a Siege Ram" without its article, so the summary counts it like any unit: "+2 Siege Rams".
static func _bare(unit_name: String) -> String:
	for article in ["a ", "an "]:
		if unit_name.begins_with(article):
			return unit_name.trim_prefix(article)
	return unit_name


static func _cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if not text.is_empty() else text
