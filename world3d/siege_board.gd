## Forts and sieges on the 3D board (M3c S-4, #102; design/M3C_SIEGES.md §10.1, §10.2), the pure part (no nodes):
## what the board draws of every fort in a game with sieges, read from the state, and how a resolved turn's events
## change it. world3d/playback.gd folds this into the board model, so "playback equals the state" covers it: applying
## a turn's events to the board model of the state before gives the board model of the state after (tests/
## test_board3d_sieges.gd, over autoplayed siege games and a scripted siege). Nothing here rolls dice or resolves
## anything: the numbers come from the state, SiegeRules and the events.
##
## The forts part of the board model (only in a game with sieges):
##   "forts"   {province id: {"level" 1 palisade / 2 keep / 3 citadel, "walls", "look" (SiegeRules.damage_look:
##             intact, damaged, battered, breached), "kit" (the faction that built the level; "" for a fort on the map,
##             which wears the nearest capital's kit)}}
##   "works"   {province id: {"to" the level being built, "left" turns of work left, "faction"}}: construction sites
##   "sieges"  {province id: {"besieger" faction id, "camps": [the besieging army ids, sorted]}}: one camp each in the
##             ring round the walls
##   "inside"  {province id: [the fort owner's army ids there, sorted]}: who stands inside the walls (Playback derives
##             it from its own owners and armies after the events, so it follows them)
##
## How the events move it (apply_events, the events alone):
##   siege_started, walls_damaged   the walls and look from numbers.walls; the siege's besieger and its camps (the
##                                  event's armies: everyone outside the walls after battles)
##   walls_breached                 the walls are 0: breached
##   siege_lifted, siege_ended      the siege is over: the camps go
##   walls_repaired                 the walls rise to numbers.to
##   construction_started           a site: numbers.to, numbers.left
##   construction_halted            no work this turn
##   fort_built                     the new level stands at numbers.walls, in the builder's kit; the site goes
##   construction_razed             the site goes (the fort keeps the level it had)
##   (no event)                     every other site standing at the start of the turn got one turn of work: the rules
##                                  report a halted or razed site and a finished level, and nothing else
##
## What the board draws (board_table, the table world_view.gd draws and reports back with fort_table()):
##   {province id: {"kind" palisade / fort / fortress ("" for a site with no fort yet), "kit" the faction whose kit it
##   wears, "look", "level", "walls", "scaffold" {} or {"to_kind", "kit", "rise" 0..1, "faction"}, "besieger" the
##   faction whose chevron banners ring the walls ("" with no siege)}}
extends RefCounted

const LEVEL_KINDS := ["", "palisade", "fort", "fortress"] ## the model table's kind for each fort level
## Every event the board plays as a fort beat (Playback.plan's "forts"), in the phase the report gives it.
const FORT_EVENTS := ["siege_started", "walls_damaged", "walls_breached", "siege_lifted", "siege_ended", "walls_repaired",
	"construction_started", "construction_halted", "fort_built", "construction_razed"]
const CHEVRONS := 8 ## the bible's "besieged" marker: a fort icon plus 8 chevrons, as banners planted round the walls


static func on(state: GameState) -> bool:
	return state != null and state.sieges


## The forts part of the board model of `state` ({} in a game without sieges).
static func model_of(state: GameState) -> Dictionary:
	if not on(state):
		return {}
	var forts := {}
	var works := {}
	var sieges := {}
	for p in state.provinces:
		if p.fort_level > 0:
			forts[p.id] = {"level": p.fort_level, "walls": p.walls, "look": SiegeRules.damage_look(p.fort_level, p.walls), "kit": p.fort_by}
		if not p.works.is_empty():
			works[p.id] = {"to": int(p.works.get("to", 0)), "left": int(p.works.get("left", 0)), "faction": String(p.works.get("faction", ""))}
		if SiegeRules.is_besieged(state, p.id):
			var camps: Array = []
			for a in SiegeRules.besiegers(state, p.id):
				camps.append(a.id)
			camps.sort()
			sieges[p.id] = {"besieger": SiegeRules.besieging_faction(state, p.id), "camps": camps}
	return {"forts": forts, "works": works, "sieges": sieges}


## Who stands inside the walls: every fort's owner's armies there, sorted. `owners` province id -> owner, `at` army
## id -> province id, `army_owner` army id -> faction id.
static func inside_of(forts: Dictionary, owners: Dictionary, at: Dictionary, army_owner: Dictionary) -> Dictionary:
	var out := {}
	for pid in forts.keys():
		var owner := String(owners.get(pid, ""))
		if owner.is_empty():
			continue
		var list: Array = []
		for aid in at.keys():
			if String(at[aid]) == pid and String(army_owner.get(aid, "")) == owner:
				list.append(aid)
		if not list.is_empty():
			list.sort()
			out[pid] = list
	return out


## The forts part of `model` after `events`, from the events alone (see the top). `model` is model_of()'s shape.
static func apply_events(model: Dictionary, events: Array) -> Dictionary:
	if model.is_empty():
		return {}
	var forts: Dictionary = (model.get("forts", {}) as Dictionary).duplicate(true)
	var works: Dictionary = (model.get("works", {}) as Dictionary).duplicate(true)
	var sieges: Dictionary = (model.get("sieges", {}) as Dictionary).duplicate(true)
	var worked := worked_sites(works)
	for e in events:
		apply_one(forts, works, sieges, e, worked)
	finish_work(works, worked)
	return {"forts": forts, "works": works, "sieges": sieges}


## The sites standing at the start of a turn: each gets a turn of work unless an event stops it (apply_one).
static func worked_sites(works: Dictionary) -> Dictionary:
	var out := {}
	for pid in works.keys():
		out[pid] = true
	return out


## The turn of work every site still in `worked` got (the rules report no event for it).
static func finish_work(works: Dictionary, worked: Dictionary) -> void:
	for pid in worked.keys():
		if works.has(pid):
			works[pid]["left"] = int(works[pid]["left"]) - 1


## One event onto the forts part (apply_events; the playback applies them one beat at a time). `worked` collects
## the sites this turn's events stopped (halted, razed, finished): pass {} when that doesn't matter.
static func apply_one(forts: Dictionary, works: Dictionary, sieges: Dictionary, e: Dictionary, worked: Dictionary = {}) -> void:
	var t := String(e.get("type", ""))
	if not FORT_EVENTS.has(t) and t != "captured":
		return
	var provs: Array = e.get("provinces", [])
	if provs.is_empty():
		return
	var pid := String(provs[0])
	var n: Dictionary = e.get("numbers", {})
	match t:
		"siege_started", "walls_damaged":
			_set_walls(forts, pid, int(n.get("walls", 0)))
			var camps: Array = (e.get("armies", []) as Array).duplicate()
			camps.sort()
			sieges[pid] = {"besieger": String(n.get("besieger", "")), "camps": camps}
		"walls_breached":
			_set_walls(forts, pid, 0)
		"siege_lifted", "siege_ended":
			sieges.erase(pid)
		"walls_repaired":
			_set_walls(forts, pid, int(n.get("to", 0)))
		"construction_started":
			var fids: Array = e.get("factions", [])
			works[pid] = {"to": int(n.get("to", 0)), "left": int(n.get("left", 0)), "faction": String(fids[0]) if not fids.is_empty() else ""}
		"construction_halted":
			worked.erase(pid)
		"fort_built":
			var fids2: Array = e.get("factions", [])
			var level := int(n.get("level", 0))
			forts[pid] = {"level": level, "walls": int(n.get("walls", 0)), "look": SiegeRules.damage_look(level, int(n.get("walls", 0))),
				"kit": String(fids2[0]) if not fids2.is_empty() else ""}
			works.erase(pid)
			worked.erase(pid)
		"construction_razed":
			works.erase(pid)
			worked.erase(pid)
		"captured":
			if n.has("fort_level") and forts.has(pid):
				_set_walls(forts, pid, int(n.get("walls", forts[pid]["walls"])))


static func _set_walls(forts: Dictionary, pid: String, walls: int) -> void:
	if not forts.has(pid):
		return
	forts[pid]["walls"] = walls
	forts[pid]["look"] = SiegeRules.damage_look(int(forts[pid]["level"]), walls)


## What the board draws at every fort and construction site of a forts model (see the top). `map_kits` gives the
## kit of a fort on the map (province id -> faction id: a capital its own faction's, any other fort the nearest
## capital's, WorldView.map_kits); a fort someone built wears its builder's kit, and a captured fort keeps its look.
static func board_table(model: Dictionary, map_kits: Dictionary) -> Dictionary:
	var out := {}
	if model.is_empty():
		return out
	var forts: Dictionary = model.get("forts", {})
	var works: Dictionary = model.get("works", {})
	var sieges: Dictionary = model.get("sieges", {})
	var ids: Array = forts.keys() + works.keys().filter(func(k): return not forts.has(k))
	ids.sort()
	for pid in ids:
		var f: Dictionary = forts.get(pid, {})
		var level := int(f.get("level", 0))
		var row := {"kind": kind_of(level), "kit": kit_of(pid, f, map_kits) if level > 0 else "", "look": String(f.get("look", "")),
			"level": level, "walls": int(f.get("walls", 0)), "scaffold": {}, "besieger": ""}
		if works.has(pid):
			var w: Dictionary = works[pid]
			var builder := String(w.get("faction", ""))
			row["scaffold"] = {"to_kind": kind_of(int(w.get("to", 0))), "kit": builder if not builder.is_empty() else String(map_kits.get(pid, "")),
				"rise": risen(w), "faction": builder}
		if sieges.has(pid) and level > 0:
			row["besieger"] = String((sieges[pid] as Dictionary).get("besieger", ""))
		out[pid] = row
	return out


## The kit a fort wears: its builder's, else the map's (a capital its faction's, a map fort the nearest capital's).
static func kit_of(pid: String, fort: Dictionary, map_kits: Dictionary) -> String:
	var by := String(fort.get("kit", ""))
	return by if not by.is_empty() else String(map_kits.get(pid, ""))


## What the board draws at one province in a game with sieges, from the state: {"level", "walls", "walls_max",
## "look", "kit" (fort_by, "" for a map fort), "owner", "works": {} or {"to", "left", "turns", "done", "faction"},
## "besieger" ("" when there is no siege), "besiegers": [army ids], "garrison": [army ids], "cut_off": bool,
## "engines": the engines the besiegers carry}. {} for a province with neither a fort nor a site.
static func fort_view(state: GameState, province_id: String) -> Dictionary:
	if not on(state):
		return {}
	var p := state.find_province(province_id)
	if p == null or (p.fort_level <= 0 and p.works.is_empty()):
		return {}
	var out := {"level": p.fort_level, "walls": p.walls, "walls_max": SiegeRules.walls_max(p.fort_level),
		"look": SiegeRules.damage_look(p.fort_level, p.walls), "kit": p.fort_by, "owner": p.owner, "works": {},
		"besieger": "", "besiegers": [], "garrison": [], "cut_off": false, "engines": 0}
	if not p.works.is_empty():
		out["works"] = works_view(p.works)
	if SiegeRules.is_besieged(state, province_id):
		out["besieger"] = SiegeRules.besieging_faction(state, province_id)
		var ids: Array = []
		var engines := 0
		for a in SiegeRules.besiegers(state, province_id):
			ids.append(a.id)
			engines += a.engines
		out["besiegers"] = ids
		out["engines"] = engines
		out["cut_off"] = SiegeRules.is_cut_off(state, province_id)
	for a in SiegeRules.owner_armies(state, province_id):
		(out["garrison"] as Array).append(a.id)
	return out


## A site as the board draws it: {"to", "left", "turns", "done", "faction"} ({} for none).
static func works_view(w: Dictionary) -> Dictionary:
	if w.is_empty():
		return {}
	var to := int(w.get("to", 0))
	var turns := int(SiegeRules.level_data(to).turns)
	var left := int(w.get("left", 0))
	return {"to": to, "left": left, "turns": turns, "done": turns - left, "faction": String(w.get("faction", ""))}


## The model table's kind for a fort level: "palisade", "fort" (a keep) or "fortress" (a citadel); "" for none.
static func kind_of(level: int) -> String:
	return LEVEL_KINDS[clampi(level, 0, LEVEL_KINDS.size() - 1)]


## The model table's kind for a damage look of a level ("fort_damaged", "fortress_breached"; a battered fort wears
## the damaged model with smoke, fire and rubble on top; "" for an intact one).
static func look_kind(level: int, look: String) -> String:
	if look == "" or look == "intact" or level <= 0:
		return ""
	return "%s_%s" % [kind_of(level), "damaged" if look == "battered" else look]


## How far up a site's next level stands (0 just ordered .. 1 done): the turns of work done over the turns it needs.
static func risen(works: Dictionary) -> float:
	if works.is_empty():
		return 0.0
	var turns := maxi(1, int(SiegeRules.level_data(int(works.get("to", 1))).turns))
	return clampf(float(turns - int(works.get("left", turns))) / turns, 0.0, 1.0)


## The camp slots round a fort for `n` besieging armies: angles (radians from the gate's direction) in the order the
## armies take them, beside the gate first (the siege works stand right before the gate), then round the walls.
static func ring_angles(n: int) -> Array:
	var out: Array = []
	var k := 0
	while out.size() < n and k < 16:
		var a: float = deg_to_rad(40.0 + 46.0 * float(k / 2))
		out.append(a if k % 2 == 0 else -a)
		k += 1
	return out


## The angles the besieged marker's chevron banners stand at round the walls (the bible's "fort icon plus 8 chevrons").
static func chevron_angles() -> Array:
	var out: Array = []
	for k in CHEVRONS:
		out.append(TAU * (k + 0.5) / float(CHEVRONS))
	return out


## The playback caption's words for a fort beat (Playback.plan's "forts" entry) in `state` (the state after).
static func beat_label(beat: Dictionary, state: GameState) -> String:
	var p := state.find_province(String(beat.get("province", ""))) if state != null else null
	var pn: String = p.name if p != null else "a fort"
	var n: Dictionary = beat.get("numbers", {})
	match String(beat.get("kind", "")):
		"siege_started":
			return "The siege of %s begins: the walls drop to %d of %d" % [pn, int(n.get("walls", 0)), int(n.get("walls_max", 0))]
		"walls_damaged":
			return "The siege of %s, turn %d: the walls drop to %d of %d" % [pn, int(n.get("turn_of_siege", 0)), int(n.get("walls", 0)), int(n.get("walls_max", 0))]
		"walls_breached":
			return "The walls of %s are breached" % pn
		"siege_lifted":
			return "The siege of %s is lifted" % pn
		"siege_ended":
			return "%s falls" % pn
		"walls_repaired":
			return "Masons repair the walls of %s: %d of %d" % [pn, int(n.get("to", 0)), int(n.get("walls_max", 0))]
		"construction_started":
			return "Scaffolding goes up at %s: %s" % [pn, SiegeRules.fort_phrase(int(n.get("to", 0)))]
		"construction_halted":
			return "Work stops at %s: an enemy army stands there" % pn
		"fort_built":
			return "%s stands at %s" % [SiegeRules.level_name(int(n.get("level", 0))), pn]
		"construction_razed":
			return "The half-built %s at %s is razed" % [SiegeRules.level_word(int(n.get("to", 0))), pn]
	return pn


## In words, what the board shows at a fort (the province tooltip's lines on the 3D board). `besieger_name` names
## the besieging faction.
static func describe(state: GameState, province_id: String, besieger_name: String = "") -> String:
	var v := fort_view(state, province_id)
	if v.is_empty():
		return ""
	var bits: Array = []
	var level := int(v["level"])
	if level > 0:
		var word := SiegeRules.level_name(level)
		match String(v["look"]):
			"intact":
				bits.append("%s, walls %d of %d: whole." % [word, int(v["walls"]), int(v["walls_max"])])
			"damaged":
				bits.append("%s, walls %d of %d: damaged, a corner of the wall knocked down (one step of %d wall strength is down: a storm meets %d defense less)." % [word,
					int(v["walls"]), int(v["walls_max"]), FortData.WALL_STEP, FortData.WALLS_DEFENSE_PER_STEP])
			"battered":
				bits.append("%s, walls %d of %d: battered, the knocked-down corner smoking with rubble at its foot (two steps of %d are down)." % [word, int(v["walls"]),
					int(v["walls_max"]), FortData.WALL_STEP])
			"breached":
				bits.append("%s, walls 0 of %d: breached, the gate side's wall down to its footing, with rubble in the gap." % [word, int(v["walls_max"])])
	var w: Dictionary = v["works"]
	if not w.is_empty():
		bits.append("In scaffolding: %s rising, %d of %d turns of work done (the solid part is built, the faint part is still to come)." % [
			SiegeRules.fort_phrase(int(w["to"])), int(w["done"]), int(w["turns"])])
	if not String(v["besieger"]).is_empty():
		var who := besieger_name if not besieger_name.is_empty() else String(v["besieger"])
		var engines := int(v["engines"])
		bits.append("Besieged by the %s: their camps ring the walls (one per army), their siege works stand before the gate, and %d chevron banners in their colour are planted round the walls%s. The garrison stands packed inside." % [
			who, CHEVRONS, (", with %d siege %s at the walls" % [engines, "engine" if engines == 1 else "engines"]) if engines > 0 else ""])
		if bool(v["cut_off"]):
			bits.append("Cut off: its income goes to the %s (the chevron and arrow in their colour beside its gold)." % who)
	return " ".join(bits)
