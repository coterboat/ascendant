class_name MapLens
extends RefCounted
## UX-7 (#217; design/UX_WAR_TABLE.md §4): the six map lenses, the pure part. A lens is an optional map view, off by default and
## one at a time, with its own overlay, palette and feel: Owner, Income, Threat, Magic, Making and Sight. This file works out what
## a lens shows and nothing else: no nodes, no scenes, no randomness. The board (WorldView.set_lens, BoardOverlay.set_lens), the
## 2D map (ProvinceRegion.set_lens) and the legend card (LensLegend) only draw what build() returns, so they cannot disagree.
##
## Fog safety (§4.0): build() reads ONLY the viewer's view (the state the map shows, FogRules.view_state in a fog game), the
## viewer's own orders and the viewer's own memory. Never the truth: tests/test_map_lens.gd perturbs everything hidden
## (FogTestKit.perturb_hidden) and holds the entries, the texture bytes, the plate values and the legend to be identical.
##
##   IDS, LENSES                       the six lenses in key order, each {"n" (its number and key, 1 to 6, the shader's lens_mode),
##                                     "title", "key", "question", "blend", "feel", "codex", "mood", "tone"}
##   build(id, state, viewer, seats, orders = [], memory = {})   {"id", "mode", "entries": {province id: entry}, "legend"}. An entry:
##       "value"      the number on the lens's scale (income, strength, marks, enchantments, closeness to a sight source)
##       "text"       what the plate says ("9", "≈34 · turn 4", "3 of 4", "sees 2", "Aurel Crown")
##       "dim"        true for a nothing-here value (no threat, no magic): the plate draws it faint
##       "icon"       the UiIcons name beside the plate value ("" for none: Owner's seat emblem, Making's pips)
##       "seat"       Owner: the owner's seat for its emblem (-1 nobody)
##       "pips"       Making: its marks (0 to 4), -1 for the other lenses; "pip_colour" their owner's colour
##       "tint", "strength"   the lens colour and how strongly it lies on the land (0 to 1): the texture's first row
##       "mark", "flag"       the hatch or ring (0 to 1) and the second mark (Threat's amber pulse, Sight's dashed ring for next
##                            turn) (0 or 1): the texture's second row
##       "far_sight"  Sight: a Far Sight target marker on this province
##       "title", "tooltip"   the plate hover's headline and its whole text: the lens value with its breakdown
##   texels(entries, ids)              the lens texture's bytes: Vision.WIDTH x 2 RGBA8, one column per province index (the terrain's
##                                     data order), row 0 the tint (rgb) and its strength (a), row 1 the mark (r), the flag (g) and
##                                     255 in a for a province that has an entry
##   mood(id)                          the land under the lens: {"mood": Vector4(drain, lightness, tone_k, 0), "tone": Color}
##   ramp(stops, t)                    a palette ramp; every lens scale runs in lightness, never hue alone (§4.0)
##   making_count(state, pid)          Making's first count (§4, Alex 10-10): {"marks", "lines"}
##   threat_strength(army)             the size guide Threat sums: attack + defense of every unit, its commander and its ruler
##   own_reach(state, viewer)          the provinces your armies can be in next turn, by the rules (Threat's amber)
##   sight_next(state, viewer, orders) next turn's sight from your queued marches (Sight's dashed ring)
## The legend: {"id", "n", "title", "question", "scale": {"kind": "ramp" | "swatches", "steps": [{"colour", "label", "pattern"}]},
##   "totals": [lines], "notes": [lines], "notes_2d": [lines the 2D map adds: the blend effects it leaves to the 3D board], "codex"}.

const Vision := preload("res://world3d/vision.gd")

const IDS := ["owner", "income", "threat", "magic", "making", "sight"]
## The lens_mode the shaders read for each lens is its "n"; 0 is no lens. "blend" is §4.0's compositing kind (wash, glow, hatch,
## ring, marks); "mood" mutes the land under it: x how much colour is drained, y its lightness, z how far it is pulled to "tone".
const LENSES := {
	"owner": {"n": 1, "title": "Owner", "key": KEY_1, "question": "Who holds what?", "blend": "wash", "feel": "a heraldic political map",
		"codex": "lens_owner", "mood": Vector4(0.55, 0.92, 0.0, 0.0), "tone": Color(0.5, 0.5, 0.5)},
	"income": {"n": 2, "title": "Income", "key": KEY_2, "question": "What is it worth?", "blend": "glow", "feel": "a treasury, warm metal",
		"codex": "lens_income", "mood": Vector4(0.7, 0.62, 0.35, 0.0), "tone": Color(0.36, 0.25, 0.14)},
	"threat": {"n": 3, "title": "Threat", "key": KEY_3, "question": "What could hit me next turn?", "blend": "hatch", "feel": "a war-room map, red pencil",
		"codex": "lens_threat", "mood": Vector4(0.85, 1.02, 0.45, 0.0), "tone": Color(0.86, 0.82, 0.72)},
	"magic": {"n": 4, "title": "Magic", "key": KEY_4, "question": "Where is magic at work?", "blend": "glow", "feel": "arcane, candle-dark",
		"codex": "lens_magic", "mood": Vector4(0.75, 0.62, 0.45, 0.0), "tone": Color(0.22, 0.18, 0.32)},
	"making": {"n": 5, "title": "Making", "key": KEY_5, "question": "How far has each faction made the land its own?", "blend": "marks",
		"feel": "a faction's hold on the land", "codex": "lens_making", "mood": Vector4(0.6, 0.85, 0.0, 0.0), "tone": Color(0.5, 0.5, 0.5)},
	"sight": {"n": 6, "title": "Sight", "key": KEY_6, "question": "Why do I see what I see?", "blend": "ring", "feel": "lantern light over a dark map",
		"codex": "lens_sight", "mood": Vector4(0.6, 0.5, 0.4, 0.0), "tone": Color(0.16, 0.18, 0.26)},
}

## The palettes (§4.1-4.6). Each scale runs in lightness: a test holds every ramp's luminance to one direction.
const INCOME_RAMP := [Color("#3A2412"), Color("#7A4E1E"), Color("#C8923A"), Color("#F6DC8A")]  # dark umber (poor) to bright gilt (rich)
const THREAT_RAMP := [Color("#F2B8B0"), Color("#D8545A"), Color("#A3161F"), Color("#5E0610")]  # rose to deep red ink: more is darker
const MAGIC_RAMP := [Color("#3B2163"), Color("#6A3FB0"), Color("#A884F0"), Color("#E3D4FF")]  # ink-violet, brighter for more
const SIGHT_RAMP := [Color("#5A3A12"), Color("#B9782A"), Color("#FFD27A")]  # lantern light, brightest at the source
const THREAT_INK := Color("#B01E28")
const AMBER := Color("#FFB23A")
## Sight: how strongly a province is lit by its nearest source, by steps from it (0 the source itself).
const SIGHT_GLOW := [1.0, 0.7, 0.45]
## Making's tint: the owner's colour, paler for fewer marks (each mark short of 4 lightens it this much), so it deepens with them.
const MAKING_PALE := 0.16
const MAKING_MAX := 4
const MAKING_HELD := [3, 6]  # turns held for the second and the third mark
const NEVER_SEEN := "never"


static func ids() -> Array:
	return IDS.duplicate()


static func lens(id: String) -> Dictionary:
	return LENSES.get(id, {})


## The shaders' lens_mode for a lens id: its number, or 0 for none.
static func mode_of(id: String) -> int:
	return int(lens(id).get("n", 0))


static func title_of(id: String) -> String:
	return String(lens(id).get("title", ""))


static func mood(id: String) -> Dictionary:
	var l := lens(id)
	if l.is_empty():
		return {"mood": Vector4(0, 1, 0, 0), "tone": Color(0.5, 0.5, 0.5)}
	return {"mood": l.mood, "tone": l.tone}


## A palette ramp at `t` (0 to 1), straight between its stops.
static func ramp(stops: Array, t: float) -> Color:
	if stops.is_empty():
		return Color.WHITE
	if stops.size() == 1:
		return stops[0]
	var x := clampf(t, 0.0, 1.0) * float(stops.size() - 1)
	var i := mini(int(floor(x)), stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], x - float(i))


static func luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


# --- build -----------------------------------------------------------------------------------------

## What lens `id` shows on `state` (the viewer's view) for `viewer` ("" watching nobody in particular), in the seat colours of
## `seats`, with the viewer's own `orders` (Sight's next turn) and memory (never-seen land). See the class comment.
static func build(id: String, state: GameState, viewer: String, seats: Array = [], orders: Array = [], memory: Dictionary = {}) -> Dictionary:
	var out := {"id": id, "mode": mode_of(id), "entries": {}, "legend": {}}
	if state == null or lens(id).is_empty():
		return out
	match id:
		"owner":
			_owner(out, state, viewer, seats)
		"income":
			_income(out, state, viewer, seats)
		"threat":
			_threat(out, state, viewer)
		"magic":
			_magic(out, state, viewer)
		"making":
			_making(out, state, viewer, seats)
		"sight":
			_sight(out, state, viewer, orders, memory)
	var l := lens(id)
	var legend: Dictionary = out.legend
	legend["id"] = id
	legend["n"] = int(l.n)
	legend["title"] = String(l.title)
	legend["question"] = String(l.question)
	legend["codex"] = String(l.codex)
	for k in ["scale", "totals", "notes", "notes_2d"]:
		if not legend.has(k):
			legend[k] = {} if k == "scale" else []
	for pid in out.entries:
		var e: Dictionary = out.entries[pid]
		e["tooltip"] = _tooltip(id, e)
	return out


## A blank entry for a province.
static func _entry(text: String = "") -> Dictionary:
	return {"value": 0.0, "text": text, "dim": false, "icon": "", "seat": -1, "pips": -1, "pip_colour": Color.WHITE, "tint": Color.BLACK,
		"strength": 0.0, "mark": 0.0, "flag": 0.0, "far_sight": false, "title": "", "lines": [], "body": ""}


## The plate's hover: the headline, the breakdown lines ("  label: value  (note)"), then the words.
static func _tooltip(id: String, e: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("%s lens: %s" % [title_of(id), String(e.title)])
	for line in e.lines:
		var note := String(line[2]) if line.size() > 2 else ""
		parts.append("  %s: %s%s" % [String(line[0]), String(line[1]), "" if note.is_empty() else "  (%s)" % note])
	var body := String(e.body)
	if not body.is_empty():
		parts.append("")
		parts.append(TooltipText.wrap_text(body))
	return "\n".join(parts)


static func _faction_name(state: GameState, fid: String) -> String:
	if fid.is_empty():
		return "Neutral"
	if fid == IndependentData.FACTION_ID:
		return IndependentData.FACTION_NAME
	var f := state.find_faction(fid)
	return f.faction_name if f != null else fid


static func _the(state: GameState, fid: String) -> String:
	return "the %s" % _faction_name(state, fid)


## Factions in seat order (the colours' order), then any the seats don't list.
static func _factions_in_order(state: GameState, seats: Array) -> Array:
	var out := []
	var order: Array = UiPalette.seat_order(state) if seats.is_empty() else seats
	for fid in order:
		if state.find_faction(String(fid)) != null and not out.has(String(fid)):
			out.append(String(fid))
	for f in state.factions:
		if not out.has(f.id):
			out.append(f.id)
	return out


# --- 1. Owner: who holds what? (wash) -----------------------------------------------------------------

static func _owner(out: Dictionary, state: GameState, viewer: String, seats: Array) -> void:
	var counts := {}
	var gold := {}
	for p in state.provinces:
		var e := _entry(_faction_name(state, p.owner))
		var seat := UiPalette.seat_index(state, p.owner, seats)
		e.seat = seat
		e.value = 1.0 if not p.owner.is_empty() else 0.0
		e.tint = UiPalette.owner_color(state, p.owner, seats) if not p.owner.is_empty() else UiPalette.NEUTRAL
		e.strength = 1.0 if not p.owner.is_empty() else 0.85
		e.title = ("%s: neutral" % p.name) if p.owner.is_empty() else ("%s: %s" % [p.name, _the(state, p.owner)])
		var lines := []
		if p.owner.is_empty():
			lines.append(["Owner", "nobody", "neutral: a slate wash and a shield emblem"])
		else:
			lines.append(["Owner", _faction_name(state, p.owner), "%s: %s, a %s emblem" % [
				"you" if p.owner == viewer else "Player %d" % (seat + 1), UiPalette.seat_color_name(seat), SeatEmblem.shape_of(seat)]])
			if state.sieges:
				lines.append(["Held since", "the start" if p.owned_since <= 0 else "turn %d" % p.owned_since, ""])
		for f in state.factions:
			if f.capital == p.id:
				lines.append(["Capital of", _faction_name(state, f.id), "" if p.owner == f.id else "held by %s" % _faction_name(state, p.owner)])
		e.lines = lines
		e.body = "Owners are public: fog of war never hides who holds a province. The plate's emblem says it without colour."
		out.entries[p.id] = e
		counts[p.owner] = int(counts.get(p.owner, 0)) + 1
		gold[p.owner] = int(gold.get(p.owner, 0)) + p.income
	# the scale is the sides themselves, each swatch with its emblem and its totals beside it
	var steps := []
	for fid in _factions_in_order(state, seats):
		var seat := UiPalette.seat_index(state, fid, seats)
		steps.append({"colour": UiPalette.owner_color(state, fid, seats), "pattern": SeatEmblem.shape_of(seat), "seat": seat,
			"label": "%s%s: %s, %d gold base" % [_faction_name(state, fid), " (you)" if fid == viewer else "",
				TooltipText.count(int(counts.get(fid, 0)), "province"), int(gold.get(fid, 0))]})
	steps.append({"colour": UiPalette.NEUTRAL, "label": "Neutral: %s" % TooltipText.count(int(counts.get("", 0)), "province"),
		"pattern": SeatEmblem.NOBODY_SHAPE, "seat": -1})
	out.legend = {"scale": {"kind": "swatches", "steps": steps}, "totals": [],
		"notes": ["Seat colours at full strength over muted land, with a thick border; each plate names the owner.", "Owners are public: fog never hides them."],
		"notes_2d": ["On the 2D map: a flat colour, without the 3D board's thick borders."]}


# --- 2. Income: what is it worth? (glow) --------------------------------------------------------------

static func _income(out: Dictionary, state: GameState, viewer: String, seats: Array) -> void:
	var lo := 1 << 30
	var hi := -1
	for p in state.provinces:
		lo = mini(lo, p.income)
		hi = maxi(hi, p.income)
	var sums := {}
	for p in state.provinces:
		var t := 0.5 if hi <= lo else float(p.income - lo) / float(hi - lo)
		var e := _entry(str(p.income))
		e.value = float(p.income)
		e.icon = "gold"
		e.tint = ramp(INCOME_RAMP, t)
		e.strength = 0.35 + 0.65 * t
		e.title = "%s: %d gold a turn, base" % [p.name, p.income]
		var lines := [["Base income", "%d gold" % p.income, "the province's own, before anything changes it"]]
		var body := "Base income is public. It is what the province pays its owner before mandates, paths and a siege's cut-off."
		if not viewer.is_empty() and p.owner == viewer:
			var actual := Breakdown.province_income(state, p.id)
			lines.append(["You get here", "%d gold" % int(actual.total), "with your own mandates and paths: the gold on the plate's hover"])
		elif not p.owner.is_empty():
			body += " What %s really get from it is theirs to know: this lens never works it out." % _the(state, p.owner)
		else:
			body += " Nobody gets it while it is neutral."
		e.lines = lines
		e.body = body
		out.entries[p.id] = e
		sums[p.owner] = int(sums.get(p.owner, 0)) + p.income
	var steps := []
	for k in 5:
		var t := float(k) / 4.0
		var g := int(round(lerpf(float(lo), float(hi), t)))
		steps.append({"colour": ramp(INCOME_RAMP, t), "label": "%d" % g if k in [0, 4] else "", "pattern": ""})
	var totals := []
	for fid in _factions_in_order(state, seats):
		totals.append("%s%s: %d gold a turn, base." % [_faction_name(state, fid), " (you)" if fid == viewer else "", int(sums.get(fid, 0))])
	totals.append("Neutral: %d gold a turn, base, paid to nobody." % int(sums.get("", 0)))
	out.legend = {"scale": {"kind": "ramp", "steps": steps, "low": "%d gold" % lo, "high": "%d gold" % hi}, "totals": totals,
		"notes": ["Base income only: these totals are what the land pays before mandates, paths and cut-offs, and say so. A rival's real income is never worked out here.",
			"Dark umber is poor land, bright gilt is rich; the plate gives the number."],
		"notes_2d": ["On the 2D map: a flat colour, without the 3D board's glow."]}


# --- 3. Threat: what could hit me next turn? (hatch) ----------------------------------------------------

## The size guide Threat adds up: attack + defense of every unit and its commander (Breakdown.army_strength, the army card's
## strength), and of its ruler. For a rival's stand-in it is what the view shows of it (the shown, rounded numbers).
static func threat_strength(army: Army) -> int:
	if army == null:
		return 0
	var total := StubBattleResolver.army_strength(army)
	if army.ruler != null:
		total += army.ruler.type.attack + army.ruler.type.defense
	return total


## The provinces `viewer`'s armies can be in next turn, by the rules on its own view: where each stands, each neighbour a move
## order to it would pass (TurnResolver.check_move), and each King's Roads or Forest Stride destination. {province id: [army ids]}.
static func own_reach(state: GameState, viewer: String) -> Dictionary:
	var out := {}
	if viewer.is_empty() or state.find_faction(viewer) == null:
		return out
	for a in state.armies:
		if a.owner != viewer:
			continue
		var places := [a.location]
		var here := state.find_province(a.location)
		if here != null:
			for n in here.neighbors:
				if TurnResolver.check_move(state, viewer, MoveOrder.new(a.id, n)).is_empty():
					places.append(n)
		places.append_array(RulerRules.road_destinations(state, viewer, a.id).keys())
		for pid in places:
			if not out.has(pid):
				out[pid] = []
			if not out[pid].has(a.id):
				out[pid].append(a.id)
	return out


static func _threat(out: Dictionary, state: GameState, viewer: String) -> void:
	var sided := not viewer.is_empty() and state.find_faction(viewer) != null
	var sums := {}
	var by := {}  # province id -> [{"army", "strength", "from", "level", "turn"}]
	var now := state.current_turn + 1
	if sided:
		for a in state.armies:
			if a.owner == viewer or a.owner.is_empty() or a.owner == IndependentData.FACTION_ID:
				continue
			var s := threat_strength(a)
			if s <= 0:
				continue
			var level := String(a.seen.get("level", FogRules.CLEAR)) if not a.seen.is_empty() else FogRules.CLEAR
			var turn := int(a.seen.get("turn", now)) if level == FogData.MEMORY else now
			var reach := [a.location]
			var p := state.find_province(a.location)
			if p != null:
				reach.append_array(p.neighbors)
			for pid in reach:
				sums[pid] = int(sums.get(pid, 0)) + s
				if not by.has(pid):
					by[pid] = []
				by[pid].append({"army": a, "strength": s, "from": a.location, "level": level, "turn": turn})
	var top := 0
	for pid in sums:
		top = maxi(top, int(sums[pid]))
	var reach_own := own_reach(state, viewer) if sided else {}
	var seen_total := 0
	var contested := 0
	for p in state.provinces:
		var total := int(sums.get(p.id, 0))
		var list: Array = by.get(p.id, [])
		var approx := false
		var oldest := now
		for c in list:
			approx = approx or String(c.level) != FogRules.CLEAR
			oldest = mini(oldest, int(c.turn))
		var t := 0.0 if top <= 0 else float(total) / float(top)
		var text := "%s%d" % ["≈" if approx else "", total]
		if oldest < now:
			text += " · turn %d" % oldest
		var e := _entry(text if sided else "–")
		e.value = float(total)
		e.dim = total <= 0
		e.icon = "strength"
		e.tint = ramp(THREAT_RAMP, t)
		e.strength = 0.0 if total <= 0 else 0.25 + 0.35 * t
		e.mark = 0.0 if total <= 0 else maxf(0.15, t)
		var reachable: bool = reach_own.has(p.id)
		e.flag = 1.0 if total > 0 and reachable else 0.0
		contested += 1 if e.flag > 0.5 else 0
		if not sided:
			e.title = "%s: nobody's side" % p.name
			e.body = "Threat is what could hit the player at the controls; watching, there is no side to threaten."
			out.entries[p.id] = e
			continue
		e.title = "%s: %s rival strength within one step" % [p.name, text] if total > 0 else "%s: no rival strength seen within one step" % p.name
		var lines := []
		for c in list:
			var a: Army = c.army
			var where := state.find_province(String(c.from))
			var how := "glimpsed now" if String(c.level) == FogRules.GLIMPSE else ("seen now" if String(c.level) == FogRules.CLEAR else "last seen turn %d" % int(c.turn))
			lines.append(["%s at %s" % [_faction_name(state, a.owner), where.name if where != null else String(c.from)],
				"%s%d" % ["≈" if String(c.level) != FogRules.CLEAR else "", int(c.strength)], "%s, %s" % [how, "here" if String(c.from) == p.id else "one step away"]])
		if lines.is_empty():
			lines.append(["Rival strength seen", "0", "none of their armies you have seen stands here or next door"])
		lines.append(["Your armies can get here", "yes" if reachable else "no", "the amber pulse" if e.flag > 0.5 else ""])
		e.lines = lines
		e.body = "An estimate from what you have seen and remember: the strength (attack + defense) of every rival army standing here or one step away, as the view shows it. Roads may reach further, and armies you can't see aren't counted."
		out.entries[p.id] = e
		if p.owner == viewer:
			seen_total = maxi(seen_total, total)
	var steps := []
	for k in 4:
		var t := float(k + 1) / 4.0
		steps.append({"colour": ramp(THREAT_RAMP, t), "label": "", "pattern": "hatch", "density": t})
	var totals := []
	if sided:
		var about := "≈" if FogView.active(state) else ""
		totals.append("The most rival strength next to any one province: %s." % ("%s%d" % [about, top] if top > 0 else "none seen"))
		totals.append("The most next to land of yours: %s." % ("%s%d" % [about, seen_total] if seen_total > 0 else "none seen"))
		totals.append("%s where your armies could meet it (amber)." % TooltipText.count(contested, "province"))
	else:
		totals.append("Nobody's side: watching, nothing is threatened.")
	out.legend = {"scale": {"kind": "ramp", "steps": steps, "low": "a little",
			"high": ("the most (%s%d)" % ["≈" if FogView.active(state) else "", top]) if top > 0 else "the most"},
		"totals": totals,
		"notes": ["An estimate from sightings only: one step; roads may reach further. Armies you can't see aren't counted.",
			"Denser red hatching, more strength. An amber pulse: your armies can get there too."],
		"notes_2d": ["On the 2D map: a flat red, darker for more, without the hatching or the pulse."]}


# --- 4. Magic: where is magic at work? (glow) -----------------------------------------------------------

static func _magic(out: Dictionary, state: GameState, viewer: String) -> void:
	var on := MagicRules.has_magic(state)
	var at := {}  # province id -> [{"name", "kind", "faction", "until"}]
	var globals := []
	if on:
		for e in state.enchantments:
			var kind := String(e.kind)
			var item := {"name": MagicRules.spell_name(String(e.ritual)), "kind": kind, "faction": String(e.faction), "until": int(e.until_turn)}
			if kind == "global":
				globals.append(item)
				continue
			var places := []
			if kind == "blessing":
				for aid in e.get("armies", []):
					var a := state.find_army(String(aid))
					if a != null and not places.has(a.location):
						places.append(a.location)
			elif not String(e.province).is_empty():
				places.append(String(e.province))
			for pid in places:
				if not at.has(pid):
					at[pid] = []
				at[pid].append(item)
		for f in state.factions:
			for pid in f.bastions:
				if not at.has(String(pid)):
					at[String(pid)] = []
				at[String(pid)].append({"name": "Bastion", "kind": "bastion", "faction": f.id, "until": -1})
	var top := 1
	for pid in at:
		top = maxi(top, (at[pid] as Array).size())
	var count_all := 0
	var mine := 0
	for p in state.provinces:
		var list: Array = at.get(p.id, [])
		var n := list.size()
		var t := float(n) / float(maxi(top, 3))
		var e := _entry(str(n) if n != 1 else String(list[0].name))
		e.value = float(n)
		e.dim = n == 0
		e.icon = "magic"
		e.tint = ramp(MAGIC_RAMP, t)
		e.strength = 0.0 if n == 0 else 0.45 + 0.55 * t
		e.mark = 0.0 if n == 0 else maxf(0.3, t)
		e.title = "%s: %s" % [p.name, "no magic you can see" if n == 0 else TooltipText.count(n, "enchantment") + " in play"]
		var lines := []
		for item in list:
			var whose := "yours" if String(item.faction) == viewer else _the(state, String(item.faction))
			var until := "for good" if int(item.until) < 0 else "through turn %d" % int(item.until)
			lines.append([String(item.name), String(item.kind).capitalize() if String(item.kind) != "sight" else "Far Sight", "%s, %s" % [whose, until]])
			mine += 1 if String(item.faction) == viewer else 0
		e.lines = lines
		e.body = "What is in play here, as far as you can see: wards, curses, blessings on the armies standing here, Far Sight, and your own Bastion forts. What could be cast is the cast dialog's."
		if not on:
			e.body = "This game is played without magic."
		out.entries[p.id] = e
		count_all += n
	var steps := []
	for k in 4:
		var t := float(k + 1) / 4.0
		steps.append({"colour": ramp(MAGIC_RAMP, t), "label": "", "pattern": "sigil"})
	var totals := []
	if not on:
		totals.append("This game is played without magic: there is nothing to show.")
	else:
		totals.append("In play where you can see: %s (%d yours)." % [TooltipText.count(count_all, "enchantment"), mine])
		for g in globals:
			totals.append("%s: everywhere, %s's, through turn %d." % [String(g.name), _faction_name(state, String(g.faction)), int(g.until)])
	out.legend = {"scale": {"kind": "ramp", "steps": steps, "low": "one", "high": "%d or more" % maxi(top, 3)}, "totals": totals,
		"notes": ["Only what is in play, and only what you can see: a rival's enchantment shows where you see its province.", "Brighter violet and more sigils, more at work."],
		"notes_2d": ["On the 2D map: a flat violet, without the 3D board's glow and sigils."]}


# --- 5. Making: how far has each faction made the land its own? (marks) ----------------------------------

## Making's first count (design/UX_WAR_TABLE.md §4; Alex 10-10: start here and see how it plays). A province someone owns has 1
## mark, +1 after 3 turns held and +1 after 6 (owned_since, kept in a game with forts and sieges), +1 where the owner's path shapes
## the land (Hallowed Land and Dread Lands everywhere it holds, the Forges at a fort, the Wild Spreads in a forest), at most 4; the
## owner's own capital always has 4. Under fog a rival's path counts only when its transformation is known to you (the view keeps
## only known path nodes). {"marks", "lines": [[label, value, note]]}. No rules effect of its own yet.
static func making_count(state: GameState, pid: String) -> Dictionary:
	var p := state.find_province(pid)
	if p == null or p.owner.is_empty():
		return {"marks": 0, "lines": [["Owner", "nobody", "neutral land has no making"]]}
	var f := state.find_faction(p.owner)
	if f != null and f.capital == p.id:
		return {"marks": MAKING_MAX, "lines": [["Capital", "4", "a faction's own capital always has all four"]]}
	var lines := [["Owned", "1", ""]]
	var n := 1
	if state.sieges:
		var held := maxi(0, state.current_turn - maxi(p.owned_since, 0))
		var since := "since the start" if p.owned_since <= 0 else "since turn %d" % p.owned_since
		for need in MAKING_HELD:
			if held >= need:
				n += 1
				lines.append(["Held %d turns" % need, "+1", since])
			else:
				lines.append(["Held %d turns" % need, "+0", "%s more to go (%s)" % [TooltipText.count(need - held, "turn"), since]])
	else:
		lines.append(["Turns held", "+0", "not kept in a game without forts and sieges"])
	var path := _path_mark(state, p)
	if not path.is_empty():
		n += 1
		lines.append([path, "+1", "the owner's path shapes the land"])
	n = mini(n, MAKING_MAX)
	return {"marks": n, "lines": lines}


## The name of the owner's path effect that shapes `p`, or "".
static func _path_mark(state: GameState, p: Province) -> String:
	if not AscensionRules.has_paths(state):
		return ""
	var rule := AscensionRules.province_rule(state, p.owner)
	match String(rule.get("id", "")):
		AscensionRules.HALLOWED_LAND, AscensionRules.DREAD_LANDS:
			return String(rule.name)
		AscensionRules.FORGES:
			return String(rule.name).capitalize() + " (a fort)" if p.has_fort else ""
		AscensionRules.WILD_SPREADS:
			return String(rule.name).capitalize() + " (a forest)" if p.terrain == AscensionRules.FOREST else ""
	return ""


static func _making(out: Dictionary, state: GameState, viewer: String, seats: Array) -> void:
	var sums := {}
	var lands := {}
	for p in state.provinces:
		var mc := making_count(state, p.id)
		var n := int(mc.marks)
		var colour := UiPalette.owner_color(state, p.owner, seats) if not p.owner.is_empty() else UiPalette.NEUTRAL
		var e := _entry("%d of %d" % [n, MAKING_MAX])
		e.value = float(n)
		e.dim = n == 0
		e.pips = n
		e.pip_colour = colour
		e.tint = colour.lerp(Color.WHITE, MAKING_PALE * float(MAKING_MAX - n)) if n > 0 else UiPalette.NEUTRAL
		e.strength = float(n) / float(MAKING_MAX)
		e.title = "%s: making %d of %d%s" % [p.name, n, MAKING_MAX, "" if p.owner.is_empty() else ", %s" % _the(state, p.owner)]
		e.lines = mc.lines
		e.body = "How deeply %s holds it. What it will do comes later: making has no rules effect yet." % (_the(state, p.owner) if not p.owner.is_empty() else "anyone")
		out.entries[p.id] = e
		if not p.owner.is_empty():
			sums[p.owner] = int(sums.get(p.owner, 0)) + n
			lands[p.owner] = int(lands.get(p.owner, 0)) + 1
	var steps := []
	var mine := UiPalette.owner_color(state, viewer, seats) if state.find_faction(viewer) != null else Color(0.6, 0.6, 0.6)
	for k in MAKING_MAX:
		steps.append({"colour": mine.lerp(Color.WHITE, MAKING_PALE * float(MAKING_MAX - k - 1)), "label": "", "pattern": "pips", "pips": k + 1})
	var totals := []
	for fid in _factions_in_order(state, seats):
		totals.append("%s%s: %d marks on %s." % [_faction_name(state, fid), " (you)" if fid == viewer else "", int(sums.get(fid, 0)),
			TooltipText.count(int(lands.get(fid, 0)), "province")])
	out.legend = {"scale": {"kind": "ramp", "steps": steps, "low": "1 mark", "high": "all 4"}, "totals": totals,
		"notes": ["How deeply each faction holds its land. What it will do comes later.",
			"A mark for owning it, one after 3 turns held and one after 6, and one where the owner's path shapes the land; a capital has all four."],
		"notes_2d": ["On the 2D map: a flat owner colour and the marks, without the 3D board's glow."]}


# --- 6. Sight (provisional): why do I see what I see? (ring) ---------------------------------------------

## Next turn's sight from `viewer`'s queued marches (Sight's dashed ring): {province id: steps to the nearest source}, worked out as
## FogRules.sight does from FogRules.sight_sources, with each of your armies that has a move order standing at its destination.
## Only your own armies and orders: information that is all yours.
static func sight_next(state: GameState, viewer: String, orders: Array) -> Dictionary:
	var moved := {}
	for o in orders:
		if o is MoveOrder:
			var a := state.find_army(o.army_id)
			if a != null and a.owner == viewer and state.find_province(o.to) != null:
				moved[o.army_id] = o.to
	var srcs := FogRules.sight_sources(state, viewer)
	for s in srcs:
		if String(s.kind) == "army" and moved.has(String(s.army)):
			s.province = moved[String(s.army)]
	return _lit(state, srcs)


## {province id: steps to the nearest of `srcs`}.
static func _lit(state: GameState, srcs: Array) -> Dictionary:
	var out := {}
	for s in srcs:
		var d := FogRules.distances(state, String(s.province), int(s.range))
		for pid in d:
			out[pid] = mini(int(out.get(pid, 99)), int(d[pid]))
	return out


static func _source_words(state: GameState, s: Dictionary) -> String:
	match String(s.kind):
		"owned":
			return "your land"
		"fort":
			return "your fort"
		"far_sight":
			return "Far Sight"
		"army":
			var why := String(s.why)
			var name := TurnReportText.army_name(state, String(s.army))
			match why:
				"ruler":
					return "%s (your ruler)" % name
				"commander":
					return "%s (a commander)" % name
				"scout":
					return "%s (a scout: %s)" % [name, String(s.scout)]
			return name
	return String(s.kind)


static func _sight(out: Dictionary, state: GameState, viewer: String, orders: Array, memory: Dictionary) -> void:
	var fog := FogView.active(state)
	var sided := not viewer.is_empty() and state.find_faction(viewer) != null
	var srcs := FogRules.sight_sources(state, viewer) if fog and sided else []
	var lit := _lit(state, srcs)
	var next := sight_next(state, viewer, orders) if fog and sided else {}
	var levels := Vision.levels(state, viewer, memory) if fog and sided else {}
	var at := {}
	for s in srcs:
		var pid := String(s.province)
		if not at.has(pid):
			at[pid] = []
		at[pid].append(s)
	var counts := {"owned": 0, "fort": 0, "army": 0, "far_sight": 0}
	for s in srcs:
		counts[String(s.kind)] = int(counts.get(String(s.kind), 0)) + 1
	var newly := 0
	for p in state.provinces:
		var level := String(levels.get(p.id, FogRules.CLEAR))
		var here: Array = at.get(p.id, [])
		var steps := int(lit.get(p.id, -1))
		var e := _entry()
		var best := 0
		var far := false
		for s in here:
			best = maxi(best, int(s.range))
			far = far or String(s.kind) == "far_sight"
		if not here.is_empty():
			e.text = "Far Sight" if far and best == 0 else "sees %d" % best
		elif steps >= 0:
			e.text = "glimpsed" if level == FogRules.GLIMPSE else "in sight"
		else:
			e.text = "never seen" if level == NEVER_SEEN else "unseen"
		e.dim = steps < 0
		e.icon = "sight"
		e.far_sight = far
		e.value = 0.0 if steps < 0 else float(SIGHT_GLOW[mini(steps, SIGHT_GLOW.size() - 1)])
		e.tint = ramp(SIGHT_RAMP, e.value)
		e.strength = e.value
		e.mark = e.value
		var soon := next.has(p.id) and steps < 0
		e.flag = 1.0 if soon else 0.0
		newly += 1 if soon else 0
		if not (fog and sided):
			e.text = "–"
			e.dim = true
			e.title = "%s: no fog" % p.name if not fog else "%s: nobody's sight" % p.name
			e.body = "Without fog of war you see everything: there is no sight to explain." if not fog else "Watching, you see as nobody in particular."
			out.entries[p.id] = e
			continue
		e.title = "%s: %s" % [p.name, String(FogView.LEVEL_TITLES.get(level, level)).to_lower()]
		var lines := []
		for s in srcs:
			var d := FogRules.distances(state, String(s.province), int(s.range))
			if d.has(p.id):
				var from := state.find_province(String(s.province))
				lines.append([_source_words(state, s), "range %d" % int(s.range), "%s%s" % [
					"here" if int(d[p.id]) == 0 else "%s away" % TooltipText.count(int(d[p.id]), "step"),
					"" if int(d[p.id]) == 0 or from == null else ", from %s" % from.name]])
		if lines.is_empty():
			lines.append(["Sources reaching it", "none", "out of range of your land, forts and armies"])
		if soon:
			lines.append(["Next turn", "in sight", "your queued marches bring it into range (the dashed ring)"])
		e.lines = lines
		e.body = Vision.words(level)
		out.entries[p.id] = e
	var steps_scale := []
	for k in SIGHT_GLOW.size():
		steps_scale.append({"colour": ramp(SIGHT_RAMP, SIGHT_GLOW[SIGHT_GLOW.size() - 1 - k]), "label": "", "pattern": "ring"})
	var totals := []
	var notes := []
	if not fog:
		totals.append("Fog of war is off: you see everything, so sight has nothing to show.")
	elif not sided:
		totals.append("Watching: nobody's sight to show.")
	else:
		var parts := [TooltipText.count(int(counts.owned), "province"), TooltipText.count(int(counts.fort), "fort"), TooltipText.count(int(counts.army), "army", "armies")]
		if int(counts.far_sight) > 0:
			parts.append("%d Far Sight" % int(counts.far_sight))
		totals.append("Your sources: %s." % RulerRules._and_list(parts))
		totals.append("In sight: %d of %d provinces; next turn %d more from your queued marches (dashed)." % [lit.size(), state.provinces.size(), newly])
	notes.append("Warm lantern rings light the land each source sees, brightest at the source; a target marks Far Sight. A dashed ring: next turn's sight from your queued marches.")
	notes.append("Provisional: the veil already shows sight. This lens explains it, and earns its place when spying gives it more to show.")
	out.legend = {"scale": {"kind": "ramp", "steps": steps_scale, "low": "two steps away", "high": "the source"}, "totals": totals, "notes": notes,
		"rows": FogView.legend_rows(state) if fog else [],
		"notes_2d": ["On the 2D map: land in sight is lit flat, without the 3D board's lantern rings."]}


# --- the ground's sums, on the CPU ----------------------------------------------------------------------

## The ground shader's compositing at one pixel (world3d/shaders/ground_common.gdshaderinc, paint_ground), on the CPU: the shader's copy
## of the arithmetic is the one the board draws, this is the one the tests read (headless has no renderer), as Vision.lit is for the veil.
## `base` is the painted land's colour (sRGB) at a pixel deep inside a province (its "inner" glow full, off any hatch line, sigil or
## mist streak), `level` its sight level ("" or "clear" for none), `entry` the lens's (MapLens.build; {} and id "" for no lens),
## `owner` its owner's colour (alpha 0 for nobody). `marks`: "selected" (the selection's lift inside the band), "band" (a pixel ON the
## selection's white band), "move" (a pixel at the edge of a legal move target: the gilt glow at its strongest). Returns the colour.
## Order (§4.0): terrain, the lens's wash or glow, the veil (the lens colour veiled as the land is), the owner (none under Owner and
## Making, its band only under the others, the full wash with no lens), the interaction marks last.
static func ground_probe(id: String, entry: Dictionary, level: String, base: Color, owner: Color = Color(0, 0, 0, 0), marks: Dictionary = {}) -> Color:
	var col := Vector3(base.r, base.g, base.b)
	var veil_l := 1.0
	var veil_drain := 0.0
	if not level.is_empty() and level != "clear":
		var lk := Vision.look(level)
		var tone: Color = lk["tint"]
		var luma0 := _luma(col)
		var lc := col.lerp(Vector3(luma0, luma0, luma0), float(lk["drain"]))
		lc = lc.lerp(Vector3(tone.r, tone.g, tone.b), float(lk["tint_k"]))
		lc *= luma0 * float(lk["lightness"]) / maxf(_luma(lc), 0.02)
		var flat := Vector3(tone.r, tone.g, tone.b)
		lc = flat.lerp(lc, float(lk["detail"]))
		col = lc.clamp(Vector3.ZERO, Vector3.ONE)
		veil_l = float(lk["lightness"])
		veil_drain = float(lk["drain"])
	var mode := mode_of(id)
	if mode > 0 and not entry.is_empty():
		var md := mood(id)
		var m: Vector4 = md.mood
		var tone2: Color = md.tone
		var t3 := Vector3(tone2.r, tone2.g, tone2.b)
		var l0 := _luma(col)
		var mc := col.lerp(Vector3(l0, l0, l0), m.x)
		mc = mc.lerp(t3 * (l0 / maxf(_luma(t3), 0.02)), m.z)
		col = mc * m.y
		var tint: Color = entry.get("tint", Color.BLACK)
		var lens_c := Vector3(tint.r, tint.g, tint.b) * veil_l
		var lcl := _luma(lens_c)
		lens_c = lens_c.lerp(Vector3(lcl, lcl, lcl), veil_drain * 0.6)
		var k := float(entry.get("strength", 0.0))
		match mode:
			1:
				col = col.lerp(lens_c, 0.62 * k)
			2:
				col = col.lerp(lens_c, k * 0.9)
			3:
				col = col.lerp(lens_c, k * 0.35)
			4, 5:
				col = col.lerp(lens_c, k * 0.8)
			6:
				col = col.lerp(lens_c, k * 0.3)
	if owner.a > 0.5 and mode == 0:
		var ow := (Vector3(owner.r, owner.g, owner.b) * 1.25).clamp(Vector3.ZERO, Vector3.ONE)
		col *= Vector3.ONE.lerp(ow, 0.3)
	if bool(marks.get("selected", false)):
		col = col * 1.10 + Vector3(0.03, 0.025, 0.0)
	if bool(marks.get("band", false)):
		col = col.lerp(Vector3.ONE, 0.95)
	if bool(marks.get("move", false)):
		col = col.lerp(Vector3(0.98, 0.80, 0.36), 0.6)
	col = col.clamp(Vector3.ZERO, Vector3.ONE)
	return Color(col.x, col.y, col.z)


static func _luma(v: Vector3) -> float:
	return 0.299 * v.x + 0.587 * v.y + 0.114 * v.z


# --- the texture --------------------------------------------------------------------------------------

## The lens texture's bytes for `entries` over the terrain's province `ids` (index = the data image's red channel): Vision.WIDTH
## columns, two rows, RGBA8. Row 0: the tint (rgb) and its strength (a). Row 1: the mark (r), the flag (g), 0 (b), and 255 (a) for a
## province with an entry. A column with no province, or no entry, is all 0: nothing is drawn there.
static func texels(entries: Dictionary, ids: Array) -> PackedByteArray:
	var w := Vision.WIDTH
	var out := PackedByteArray()
	out.resize(w * 2 * 4)
	out.fill(0)
	for i in mini(ids.size(), w):
		var e: Dictionary = entries.get(String(ids[i]), {})
		if e.is_empty():
			continue
		var c: Color = e.tint
		var o := i * 4
		out[o] = c.r8
		out[o + 1] = c.g8
		out[o + 2] = c.b8
		out[o + 3] = _byte(float(e.strength))
		var o2 := (w + i) * 4
		out[o2] = _byte(float(e.mark))
		out[o2 + 1] = _byte(float(e.flag))
		out[o2 + 2] = 0
		out[o2 + 3] = 255
	return out


static func _byte(v: float) -> int:
	return clampi(int(round(clampf(v, 0.0, 1.0) * 255.0)), 0, 255)


## Empty texels: no lens.
static func no_texels() -> PackedByteArray:
	return texels({}, [])
