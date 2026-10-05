class_name FogView
## Fog of war on screen (M5-2, #113; design/M5_MAGIC_FOG.md §2.4-§2.10, §11.1): the words and numbers the screens show
## about what their viewer can see. Pure functions over the viewer's view (FogRules.view_state: a GameState with
## is_view set) and its memory and intel (GameSession.memory, intel), never the truth, so a screen that reads only these
## can't leak. On a state that is not a fog view, every function says nothing ("", [] or {}).
##
##   active(state)                          true for a fog view
##   vision_level(state, viewer, pid, memory)   "clear" | "glimpse" | "veiled" | "never" (out of sight, never seen)
##   province_text(state, viewer, pid, memory)  why it is seen, or what you remember of it (the province tooltip)
##   badge_text(state, army), about(rc), range_text(rc)   "≈20", "≈10 · 2 turns ago", "about 20 (18-22)"
##   army_breakdown(state, viewer, army, before)   a stand-in's numbers with their ranges and last turn's sighting
##   army_sight_line(army), scout_line(type)    "This army sees 2 provinces (it has Knights)." / "Scout: sees 2 provinces."
##   rival_summary(state, viewer, fid, intel)   what you know of a rival: its ruler, where it is, its mandates
##   missed_text(battle, viewer, before)        "what you didn't see" in a battle you fought (§2.8)
##   lift(truth, players, missed)               the victory screen's "the fog lifts" (§2.1): the truth at the end
##   legend_rows(state)                         the Vision map mode's legend
## Sight levels and sources come from FogRules; estimates from the view notes FogRules wrote (Army.seen).

const REPORT_HEADER := "Fog of war: this report shows what you saw."
const COVER_LINE := "Fog of war is on: each player sees only their own view. Continue only when nobody else can see the screen."
const NOTES_HIDDEN := "Hidden while the fog of war lasts: the computer's notes name its hidden armies and plans. They show here once the game is over."
## The Vision map mode's level for a province out of sight that was never seen.
const NEVER := "never"
const LEVEL_TITLES := {"clear": "In clear sight", "glimpse": "Glimpsed", "veiled": "Out of sight", "never": "Never seen"}
const LEVEL_CODEX := {"clear": "vision_clear", "glimpse": "vision_glimpsed", "veiled": "vision_out_of_sight", "never": "last_seen"}


static func active(state: GameState) -> bool:
	return state != null and state.fog and state.is_view


## A rival army in a view (a stand-in or a remembered ghost) rather than a true army.
static func is_stand_in(army: Army) -> bool:
	return army != null and not army.seen.is_empty()


## The Vision map mode's level of `pid` for `viewer`: its sight level, or "never" when it is out of sight and was never
## seen. "" without fog.
static func vision_level(state: GameState, viewer: String, pid: String, memory: Dictionary) -> String:
	if not active(state):
		return ""
	var level := String(FogRules.sight(state, viewer).get(pid, FogRules.VEILED))
	if level == FogRules.VEILED and int(memory.get("provinces", {}).get(pid, {}).get("seen_turn", -1)) < 0:
		return NEVER
	return level


# --- numbers as players read them (§2.4) ---------------------------------------------------------------

## The number of a round count without "about": "20", or "1-2".
static func about(rc: Dictionary) -> String:
	return FogData.FEW_TEXT if String(rc.get("text", "")) == FogData.FEW_TEXT else str(int(rc.get("shown", 0)))


## A round count with its range: "about 20 (18-22)", "1-2", or "20" when it is exact.
static func range_text(rc: Dictionary) -> String:
	var shown := int(rc.get("shown", 0))
	var low := int(rc.get("low", shown))
	var high := int(rc.get("high", shown))
	if String(rc.get("text", "")) == FogData.FEW_TEXT:
		return FogData.FEW_TEXT
	if low == high:
		return str(shown)
	return "about %d (%d-%d)" % [shown, low, high]


## A stand-in's badge (§11.1, §12.1): "≈20" glimpsed, "≈10 · 2 turns ago" remembered, "20 units" in clear sight. "" for
## an army that is not a stand-in, or a ruler's.
static func badge_text(state: GameState, army: Army) -> String:
	if not is_stand_in(army) or army.ruler != null:
		return ""
	if army.units.is_empty() and army.commander != null:
		return army.commander.type.name  # a further commander's stand-in ("-c2"): the commander alone
	var total: Dictionary = army.seen.get("total", {})
	match String(army.seen.get("level", "")):
		FogRules.GLIMPSE:
			return "≈%s" % about(total)
		FogData.MEMORY:
			return "≈%s · %s" % [about(total), _ago(state, int(army.seen.get("turn", 0)))]
	return TooltipText.count(army.units.size(), "unit")


## "this turn", "1 turn ago", "3 turns ago", or "at the start" for a sighting taken after `turn` resolved turns.
static func _ago(state: GameState, turn: int) -> String:
	if turn <= 0:
		return "at the start"
	var ago := state.current_turn + 1 - turn
	return "1 turn ago" if ago == 1 else "%d turns ago" % ago


# --- provinces (§11.1) ----------------------------------------------------------------------------

## The province tooltip's fog paragraph: in sight, why ("Glimpsed from your army at Highcrag (range 1)."); out of
## sight, what you remember ("You can't see Wildmoor now. Last seen 3 turns ago, at the end of turn 6: ..."), the
## battles you fought there, and how close your sight reaches. "" without fog.
static func province_text(state: GameState, viewer: String, pid: String, memory: Dictionary) -> String:
	if not active(state) or state.find_province(pid) == null:
		return ""
	var p := state.find_province(pid)
	var level := String(FogRules.sight(state, viewer).get(pid, FogRules.VEILED))
	var entry: Dictionary = memory.get("provinces", {}).get(pid, {})
	var parts := []
	if level != FogRules.VEILED:
		for s in FogRules.sources(state, viewer, pid):
			parts.append(String(s.text))
	else:
		var seen_turn := int(entry.get("seen_turn", -1))
		if seen_turn < 0:
			parts.append("You can't see %s now: never seen." % p.name)
		else:
			parts.append("You can't see %s now. Last seen %s: %s." % [p.name, Forecast.seen_when(state, seen_turn), _remembered(state, viewer, pid)])
		var near := []
		var sight := FogRules.sight(state, viewer)
		for n in p.neighbors:
			if String(sight.get(n, FogRules.VEILED)) != FogRules.VEILED:
				near.append(state.find_province(n).name)
		parts.append("You see as far as %s, next to it." % RulerRules._and_list(near) if not near.is_empty()
			else "Your sight doesn't reach any province next to it.")
	var fought: Dictionary = entry.get("fought", {})
	for fid in fought:
		parts.append(_fought_text(state, String(fid), fought[fid]))
	return " ".join(parts)


## What `viewer` remembers at `pid` (a veiled province): its ghosts' sightings, or "no army there".
static func _remembered(state: GameState, viewer: String, pid: String) -> String:
	var rivals := []
	for a in state.armies:
		if a.location == pid and a.owner != viewer and String(a.seen.get("level", "")) == FogData.MEMORY and not rivals.has(a.owner):
			rivals.append(a.owner)
	if rivals.is_empty():
		return "no army there"
	rivals.sort()
	return "; ".join(rivals.map(func(fid): return Forecast.sighting_text(state, viewer, String(fid), pid).trim_prefix("Remembered there: ").trim_suffix(".")))


## "Last fought there on turn 4: 6 Tuskers of the Thornmane Clans survived, 18 hp in all." (memory's step 3).
static func _fought_text(state: GameState, fid: String, f: Dictionary) -> String:
	var who := Forecast._faction_name(state, fid)
	var survivors: Dictionary = f.get("survivors", {})
	if survivors.is_empty():
		return "Last fought there on turn %d: none of the %s survived." % [int(f.get("turn", 0)), who]
	var names := []
	for type_id in survivors:
		var n := int(survivors[type_id])
		names.append("%d %s" % [n, FogRules.type_name(state, fid, String(type_id))])
	return "Last fought there on turn %d: %s of the %s survived, %d hp in all." % [int(f.get("turn", 0)), RulerRules._and_list(names), who, int(f.get("hp", 0))]


# --- armies (§2.4, §11.1) --------------------------------------------------------------------------

## A stand-in's heading for the side panel: "≈20 fighters of the Thornmane Clans at Thornvale, glimpsed".
static func army_heading(state: GameState, army: Army) -> String:
	var who := Forecast._faction_name(state, army.owner)
	var place := TurnResolver._province_name(state, army.location)
	if army.ruler != null:
		return "%s, ruler of the %s, at %s (%s)" % [RulerRules._cap(army.ruler.type.name), who, place, _level_word(army)]
	var total: Dictionary = army.seen.get("total", {})
	match String(army.seen.get("level", "")):
		FogRules.GLIMPSE:
			return "≈%s fighters of the %s at %s, glimpsed" % [about(total), who, place]
		FogData.MEMORY:
			return "≈%s fighters of the %s at %s, remembered" % [about(total), who, place]
	return "%d fighters of the %s at %s, in clear sight" % [int(total.get("shown", army.units.size())), who, place]


static func _level_word(army: Army) -> String:
	match String(army.seen.get("level", "")):
		FogRules.GLIMPSE:
			return "glimpsed"
		FogData.MEMORY:
			return "remembered"
	return "in clear sight"


## A stand-in's numbers (§11.1's hover on a glimpsed army), Breakdown-shaped so every number explains itself: one line
## per type with its range ("about 15 Tuskers (13-17)"), summing to the shown total, and a description with the
## total's range, its commander, last turn's sighting at that place (from `before`, the view at the start of the last
## resolved turn), why you see it and how to see it exactly. {} for an army that is not a stand-in.
static func army_breakdown(state: GameState, viewer: String, army: Army, before: GameState) -> Dictionary:
	if not is_stand_in(army):
		return {}
	var note := army.seen
	var level := String(note.get("level", ""))
	var who := Forecast._faction_name(state, army.owner)
	var lines := []
	var by_type := {}
	for u in army.units:
		by_type[u.type.id] = int(by_type.get(u.type.id, 0)) + 1
	var counts: Dictionary = note.get("counts", {})
	var n := 0
	for type_id in counts:
		var here := int(by_type.get(type_id, 0))
		if here <= 0:
			continue
		var c: Dictionary = counts[type_id]
		var name := FogRules.type_name(state, army.owner, String(type_id))
		var label := "%d %s" % [here, name]
		var line_note := "exactly"
		if level == FogRules.GLIMPSE:
			label = "about %d %s (%d-%d)" % [int(c.shown), name, int(c.low), int(c.high)]
			line_note = "a glimpse, rounded"
		elif level == FogData.MEMORY:
			label = "%s %s" % [range_text(c) if int(c.low) != int(c.high) else str(int(c.shown)), name]
			line_note = "as you last saw them"
		lines.append({"label": label, "value": here, "note": line_note, "type": String(type_id)})
		n += here
	var total: Dictionary = note.get("total", FogRules.round_count(n))
	var desc := PackedStringArray()
	var sources := FogRules.sources(state, viewer, army.location)
	match level:
		FogRules.GLIMPSE:
			desc.append("%s fighters of the %s." % [range_text(total), who])
			if not sources.is_empty():
				desc.append(String(sources[0].text))
			if int(total.low) != int(total.high):
				desc.append("About %d means %d-%d: a glimpse rounds the total, then shares it out over the types, so wounds, exact counts and how many armies they are stay hidden." % [
					int(total.shown), int(total.low), int(total.high)])
		FogData.MEMORY:
			desc.append("Remembered: you last saw %s fighters of the %s here %s. They may have moved since." % [range_text(total), who,
				Forecast.seen_when(state, int(note.get("turn", 0)))])
		_:
			desc.append("%d fighters of the %s, in clear sight: every fighter and its wounds, though not how they split into armies." % [int(total.shown), who])
	if army.commander != null:
		desc.append("Led by a %s." % army.commander.type.name)
	desc.append("Last turn: %s." % last_turn_text(state, army, before))
	if level != FogRules.CLEAR:
		desc.append("Fight them, or cast Far Sight once you have a mage, to see them exactly." if state.magic else "Fight them to see them exactly.")
	var b := {"title": army_heading(state, army), "description": " ".join(desc), "lines": lines,
		"total_label": "About" if level == FogRules.GLIMPSE else "Fighters", "total": n, "codex": "estimates" if level != FogRules.CLEAR else "vision_clear"}
	if level == FogData.MEMORY:
		b.codex = "last_seen"
	return b


## Last turn's sighting at the stand-in's place, from the view at the start of the last resolved turn: "about 15
## (13-17)", "remembered here, about 10 (8-12)", "none seen here".
static func last_turn_text(state: GameState, army: Army, before: GameState) -> String:
	if before == null:
		return "nothing seen here yet"
	var last := before.find_army(army.id)
	if last == null:
		return "none seen here"
	if String(last.seen.get("level", "")) == FogData.MEMORY:
		return "remembered here, %s" % range_text(last.seen.get("total", {}))
	return range_text(last.seen.get("total", {}))


## How far one of your armies sees (§2.3, §11.1): "This army sees 2 provinces (it has Knights)."
static func army_sight_line(army: Army) -> String:
	var s := FogRules.army_sight(army)
	var r := int(s.range)
	var span := "This army sees %d province%s around it" % [r, "" if r == 1 else "s"]
	match String(s.why):
		"scout":
			return "%s (it has %s)." % [span, String(s.scout)]
		"commander":
			return "%s (it has a commander)." % span
		"ruler":
			return "%s (your ruler is with it)." % span
	return "%s. A commander, a ruler or a scout would make it 2." % span


## A unit card's scout line (§11.1): "Scout: sees 2 provinces." for a scout type, "" otherwise.
static func scout_line(ut: UnitType) -> String:
	return "Scout: sees %d provinces." % int(FogData.SIGHT.scout) if FogRules.is_scout(ut) else ""


# --- rivals (§2.6, §11.1) -------------------------------------------------------------------------

## What `viewer` knows about rival `fid` (§11.1's rival panel): {"text": "What you know about the Thornmane Clans: the
## Great Thornmane (kept power 7, seen on turn 5). Mandates: Iron Discipline. They may have more.", "where" (the
## ruler's place: "Alive, location unknown", "Alive, glimpsed at Thornvale", "Alive, last seen at Wildmoor 2 turns
## ago", or a dead ruler's line), "kept" (the kept power line), "mandates" (the mandates line), "path" (the nodes you
## know, or "")}. {} without fog.
static func rival_summary(state: GameState, viewer: String, fid: String, intel: Dictionary) -> Dictionary:
	if not active(state) or state.find_faction(fid) == null:
		return {}
	var f := state.find_faction(fid)
	var k: Dictionary = intel.get(fid, {})
	var out := {"where": "", "kept": "", "mandates": "", "path": ""}
	var bits := PackedStringArray()
	if f.has_ruler():
		var name := RulerRules.current_name(state, fid)
		var known := int(k.get("kept_power", -1)) >= 0
		out.kept = "kept power %d, seen on turn %d" % [f.kept_power, int(k.get("kept_turn", 0))] if known \
			else "kept power %d at most: the most it could be with the mandates you know" % f.kept_power
		bits.append("%s (%s)" % [name, out.kept])
		out.where = ruler_where(state, viewer, fid)
		var names := f.mandates.map(func(mid): return RulerRules.mandate_name(String(mid)))
		out.mandates = "Mandates: %s." % RulerRules._and_list(names) if not names.is_empty() else "Mandates: none you know of."
	if state.paths:
		var nodes := AscensionRules.researched(state, fid).map(func(nid): return AscensionRules.node_name(String(nid)))
		out.path = "Path: %s." % RulerRules._and_list(nodes) if not nodes.is_empty() else ""
	var text := "What you know about the %s: %s." % [f.faction_name, ", ".join(bits) if not bits.is_empty() else "their land and their roster"]
	for part in [out.mandates, out.path]:
		if not String(part).is_empty():
			text += " " + String(part)
	out["text"] = text + " They may have more."
	return out


## Where a rival's ruler is, as far as `viewer` knows (§2.7's liveness): "Alive, location unknown" when it is alive and
## neither seen nor remembered.
static func ruler_where(state: GameState, viewer: String, fid: String) -> String:
	if not RulerRules.ruler_alive(state, fid):
		return "Dead: %s" % RulerRules.countdown_text(state, fid) if not RulerRules.countdown_text(state, fid).is_empty() else "Dead"
	var army := RulerRules.ruler_army(state, fid)
	if army == null:
		return "Alive, location unknown"
	var place := TurnResolver._province_name(state, army.location)
	match String(army.seen.get("level", "")):
		FogRules.GLIMPSE:
			return "Alive, glimpsed at %s" % place
		FogData.MEMORY:
			return "Alive, last seen at %s %s" % [place, Forecast.seen_when(state, int(army.seen.get("turn", 0)))]
	return "Alive at %s" % place


# --- what you didn't see (§2.8) -------------------------------------------------------------------

## The "what you didn't see" line of a battle `viewer` fought (the participant's copy of the event from
## GameSession.turn_report_for), against `before`, its view at the start of that turn: "You had glimpsed about 10
## Tuskers at Thornvale; 14 fought you (armies can join during a turn), with Iron Discipline, which you hadn't seen."
## "" when the enemy that fought is what the view showed (counts by type and mandates), or for anyone but a participant.
static func missed_text(event: Dictionary, viewer: String, before: GameState) -> String:
	if not GameSession.BATTLE_TYPES.has(String(event.get("type", ""))) or not Array(event.get("factions", [])).has(viewer) or before == null:
		return ""
	var report: Dictionary = event.get("numbers", {}).get("report", {})
	var out := PackedStringArray()
	for side in report.get("sides", []):
		var fid := String(side.get("faction", ""))
		if fid == viewer or fid.is_empty():
			continue
		var truth := {}
		var names := {}
		for u in side.get("roster", {}).get("units", []):
			truth[String(u.id)] = int(truth.get(String(u.id), 0)) + int(u.count)
			names[String(u.id)] = String(u.name)
		var seen := {}
		var level := ""
		var place := ""
		for aid in event.get("armies", []):
			var a := before.find_army(String(aid))
			if a == null or a.owner != fid:
				continue
			if level.is_empty() or String(a.seen.get("level", "")) == FogRules.CLEAR:
				level = String(a.seen.get("level", ""))
			place = TurnResolver._province_name(before, a.location)
			for u in a.units:
				seen[u.type.id] = int(seen.get(u.type.id, 0)) + 1
				names[u.type.id] = u.type.name
		var known: Array = []
		var bf := before.find_faction(fid)
		if bf != null:
			known = bf.mandates
		var unseen := []
		for m in side.get("mandates", []):
			if not known.has(String(m.get("id", ""))):
				unseen.append(String(m.get("name", m.get("id", ""))))
		var differs := _counts_differ(seen, truth)
		if not differs and unseen.is_empty():
			continue
		var fname := Forecast._faction_name(before, fid)
		var where := place if not place.is_empty() else TurnResolver._province_name(before, String(Array(event.get("provinces", [""]))[0]))
		var text := ""
		if seen.is_empty():
			text = "You hadn't seen this army of the %s before the battle at %s" % [fname, where]
		else:
			var verb := String({"glimpse": "had glimpsed", "memory": "remembered", "clear": "had seen"}.get(level, "had seen"))
			var parts := []
			for type_id in seen:
				parts.append("%s %d %s" % ["about" if level != FogRules.CLEAR else "", int(seen[type_id]), names.get(type_id, type_id)])
			text = "You %s %s at %s" % [verb, RulerRules._and_list(parts.map(func(s): return String(s).strip_edges())), where]
		var total := 0
		for type_id in truth:
			total += int(truth[type_id])
		if differs:
			text += "; %d fought you (armies can join during a turn)" % total
		if not unseen.is_empty():
			text += ", with %s, which you hadn't seen" % RulerRules._and_list(unseen)
		text += "."
		var odds := missed_odds(event, viewer, before, side)
		if odds >= 0:
			text += " Against what was really there, the odds were %d%%." % odds
		out.append(text)
	return " ".join(out)


## The odds against what was really there (§2.8), in percent: for a battle `viewer` attacked in a province (not at a
## fort), its armies there against `side`, the enemy's true starting side as the battle report gives it (its roster at
## full health, the mandates it fought with, its ruler's kept power), on `before`, the viewer's view at the start of the
## turn. -1 when it can't be worked out that way (a border battle, a defence, a battle at a fort).
static func missed_odds(event: Dictionary, viewer: String, before: GameState, side: Dictionary) -> int:
	if String(event.get("type", "")) != "battle" or before == null or Array(event.get("provinces", [])).is_empty():
		return -1
	var report: Dictionary = event.get("numbers", {}).get("report", {})
	for sr in report.get("sides", []):
		if String(sr.get("faction", "")) == viewer and bool(sr.get("defender", false)):
			return -1
	var pid := String(event.provinces[0])
	var p := before.find_province(pid)
	if p == null or (before.sieges and p.fort_level > 0):
		return -1
	var fid := String(side.get("faction", ""))
	var named := {}
	for aid in event.get("armies", []):
		named[String(aid)] = true
	var mine := []
	var d := before.to_dict()
	var kept := []
	for ad in d.armies:
		if String(ad.owner) == viewer and named.has(String(ad.id)):
			mine.append(String(ad.id))
		if String(ad.owner) == fid and (String(ad.location) == pid or named.has(String(ad.id))):
			continue
		kept.append(ad)
	if mine.is_empty():
		return -1
	var units := []
	for u in side.get("roster", {}).get("units", []):
		for i in int(u.count):
			units.append({"type_id": String(u.id), "current_hp": 1, "owner": fid})
	var commanders: Array = side.get("roster", {}).get("commanders", [])
	var first := {"id": FogRules.view_id(fid, pid), "owner": fid, "location": pid, "units": units,
		"commander": {"type_id": String(commanders[0].id), "current_hp": 1, "owner": fid} if not commanders.is_empty() else {}}
	kept.append(first)
	for i in range(1, commanders.size()):
		kept.append({"id": FogRules.view_id(fid, pid, "c%d" % (i + 1)), "owner": fid, "location": pid, "units": [],
			"commander": {"type_id": String(commanders[i].id), "current_hp": 1, "owner": fid}})
	var ruler: Dictionary = side.get("ruler", {})
	for f in d.factions:
		if String(f.id) != fid or not f.has("ruler_type"):
			continue
		f.mandates = side.get("mandates", []).map(func(m): return String(m.get("id", "")))
		if not ruler.is_empty():
			f.kept_power = int(ruler.get("kept_power", f.kept_power))
			kept.append({"id": FogRules.view_id(fid, pid, "ruler"), "owner": fid, "location": pid, "units": [], "commander": {},
				"ruler": {"type_id": String(f.ruler_type), "current_hp": maxi(1, int(ruler.get("hp_start", 1))), "owner": fid}})
	d.armies = kept
	var state := GameState.from_dict(d, [])
	if state == null:
		return -1
	for a in state.armies:
		if a.owner == fid and a.location == pid:
			for u in a.units:
				u.current_hp = RulerRules.unit_max_hp(state, u)
			if a.commander != null:
				a.commander.current_hp = a.commander.type.hp
	var odds := Forecast.battle_odds(state, viewer, mine, pid)
	return roundi(float(odds.win_rate) * 100) if bool(odds.get("ok", false)) else -1


## Every "what you didn't see" of the last resolved turn, for each player of `session`: [{"turn", "faction" (who didn't
## see it), "text"}], from each player's own report and view at the turn's start (per-viewer accessors only).
static func missed_of_turn(session: GameSession) -> Array:
	var out := []
	for fid in session.players():
		var report := session.turn_report_for(String(fid))
		if not bool(report.get("fog", false)):
			continue
		var before := session.view_before(String(fid))
		for e in report.get("events", []):
			var text := missed_text(e, String(fid), before)
			if not text.is_empty():
				out.append({"turn": int(report.get("turn", 0)), "faction": String(fid), "text": text})
	return out


static func _counts_differ(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if int(a[k]) != int(b.get(k, 0)):
			return true
	for k in b:
		if int(b[k]) != int(a.get(k, 0)):
			return true
	return false


# --- the fog lifts (§2.1) -------------------------------------------------------------------------

## The victory screen's "the fog lifts": {"factions": [{"faction", "name", "lines": [what it really had at the end:
## ruler and kept power, mandates, path, gold]}], "missed": every "what you didn't see" of the game ([{"turn",
## "faction" (who didn't see it), "text"}])}. `truth` is the final true state (the observer's: the game is over).
static func lift(truth: GameState, players: Array, missed: Array) -> Dictionary:
	var rows := []
	for fid in players:
		var f := truth.find_faction(String(fid))
		if f == null:
			continue
		var lines := []
		if f.has_ruler():
			var names := f.mandates.map(func(mid): return RulerRules.mandate_name(String(mid)))
			lines.append("%s, kept power %d. Mandates: %s." % [RulerRules._cap(RulerRules.current_name(truth, f.id)), f.kept_power,
				RulerRules._and_list(names) if not names.is_empty() else "none"])
		if truth.paths:
			var nodes := AscensionRules.researched(truth, f.id).map(func(nid): return AscensionRules.node_name(String(nid)))
			lines.append("Path: %s." % (RulerRules._and_list(nodes) if not nodes.is_empty() else "nothing researched"))
		var fighters := 0
		var armies := 0
		for a in truth.armies:
			if a.owner == f.id:
				armies += 1
				fighters += a.units.size() + (1 if a.commander != null else 0)
		lines.append("At the end: %d gold, %s with %s." % [f.gold, TooltipText.count(armies, "army", "armies"), TooltipText.count(fighters, "fighter")])
		rows.append({"faction": f.id, "name": f.faction_name, "lines": lines})
	return {"factions": rows, "missed": missed.duplicate(true)}


# --- the Vision map mode (§11.1) -------------------------------------------------------------------

## The Vision map mode's legend: [{"key", "title", "text", "codex"}], one row per mark.
static func legend_rows(state: GameState) -> Array:
	var rows := [
		{"key": "clear", "title": "In clear sight", "text": "No veil: land you own or stand in. You see every army there exactly.", "codex": "vision_clear"},
		{"key": "glimpse", "title": "Glimpsed", "text": "A light veil: next to your land and armies, two away from forts, commanders, rulers and scouts. Armies show rounded.", "codex": "vision_glimpsed"},
		{"key": "veiled", "title": "Out of sight", "text": "A dark veil with hatching: you see only what you saw there last. Owners, terrain and forts stay true.", "codex": "vision_out_of_sight"},
		{"key": "never", "title": "Never seen", "text": "The darkest veil: you have never seen an army there.", "codex": "last_seen"},
		{"key": "plate", "title": "≈20", "text": "A glimpsed army: about 20 fighters, rounded. Hover it for the range.", "codex": "estimates"},
		{"key": "ghost", "title": "≈10 · 3 turns ago", "text": "A grey badge: an army you remembered, last seen there 3 turns ago. It may have moved.", "codex": "last_seen"},
	]
	if state != null and state.magic:
		rows.append({"key": "eye", "title": "The eye", "text": "Your Far Sight: that province is in clear sight.", "codex": "sight"})
	return rows
