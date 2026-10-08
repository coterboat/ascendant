## Turn playback on the 3D board, the pure part (no nodes): what a resolved turn's events say happened
## on the land, as the beats the board plays (world3d/armies.gd), and the board model they lead to.
##
## The board only ever READS the game: it is given the state before the turn, the resolver's events and
## the state after, and it never calls the resolver or changes a state (design/3D_DIRECTION.md 2, "the
## one invariant"). tests/test_board3d.gd checks that applying a turn's events to the board model of the
## state before gives exactly the board model of the state after, over many autoplayed turns: the
## playback is driven by the events, and it can't disagree with the game.
##
##   model_of(state)                -> {"owners": {province id: faction id or ""}, "armies": {army id: province id}}
##                                     M3c S-4, in a game with sieges also "forts", "works", "sieges", "inside" and
##                                     "army_owner" (world3d/siege_board.gd: levels, damage looks, construction, the
##                                     camp rings, who stands inside the walls)
##   apply_events(model, events)    -> the model after those events (only the events are read)
##   plan(before, events, after)    -> the beats: marches, battles, captures, recruits and arrivals; with sieges the
##                                     fort beats (sieges, walls, construction) and each battle's siege block
##
## Under fog (M5-3, #114; design/M5_MAGIC_FOG.md §2.8, §12.1) the same three functions run on one viewer's view: `before`
## and `after` are its views (FogRules.view_state, GameSession.view_before / state_for) and `events` its own turn report
## (GameSession.turn_report_for), synthetic events included. Nothing here reads the truth, so nothing it plans can come
## from state the viewer is not shown:
##   * a rival column the viewer saw march (a rebuilt `army_moved`: pooled and rounded, no true ids) becomes a "seen"
##     march of its stand-in's block (the stand-ins of that faction at the place it left), to the border and a fade when
##     the road led out of sight;
##   * the synthetic events (sighting_changed, memory_added, sighting_lost, army_changed) set or remove the army they name
##     in the board model, exactly as FogRules.apply_view_events does, and are listed as "sightings" for the re-form;
##   * a ritual's beat starts at its caster only when the viewer's own report names it (the viewer's own cast); a ritual
##     that fell on the viewer's land from a hidden caster starts at the target ("rituals").
extends RefCounted

const SiegeBoard := preload("res://world3d/siege_board.gd")
const BATTLES := ["battle", "border_battle"]
## M5-3: the ritual events the board's beats read (design/M5_MAGIC_FOG.md §12.3): who sees which is FogData.AUDIENCE's.
const RITUAL_EVENTS := ["ritual_cast", "ritual_turned_aside", "ritual_fell"]


## What the board shows of a state: who owns each province and where every army stands (with sieges, its forts).
static func model_of(state: GameState) -> Dictionary:
	var owners := {}
	for p in state.provinces:
		owners[p.id] = p.owner
	var armies := {}
	var army_owner := {}
	for a in state.armies:
		armies[a.id] = a.location
		army_owner[a.id] = a.owner
	var out := {"owners": owners, "armies": armies}
	var forts := SiegeBoard.model_of(state)
	if not forts.is_empty():
		out.merge(forts)
		out["army_owner"] = army_owner
		out["inside"] = SiegeBoard.inside_of(forts["forts"], owners, armies, army_owner)
	return out


## The model after a turn's events, from the events alone:
##   army_moved             the army stands at the event's last province (a road move's way is in between)
##   battle, border_battle  every army in numbers.destroyed is gone
##   ruler_died             the ruler's army is gone (a ruler travels alone, so its army goes with it)
##   captured, vassal_joined   the province now belongs to the event's first faction
##   recruited              the army it joined (or formed) stands at the event's province
##   ruler_arrived          the new ruler's army stands at the capital
##   M3c S-4, with sieges: the forts part moves as SiegeBoard.apply_events says; a new army (recruited, ruler_arrived)
##   belongs to the event's faction, and who stands inside follows the owners and armies
static func apply_events(model: Dictionary, events: Array) -> Dictionary:
	var owners: Dictionary = (model.get("owners", {}) as Dictionary).duplicate()
	var armies: Dictionary = (model.get("armies", {}) as Dictionary).duplicate()
	var army_owner: Dictionary = (model.get("army_owner", {}) as Dictionary).duplicate()
	for e in events:
		var provs: Array = e.get("provinces", [])
		var ids: Array = e.get("armies", [])
		if bool(e.get("synthetic", false)):
			## M5-3: what is left over between the viewer's view before and after (FogRules.synthetic_events): a sighting
			## that appeared, changed or became a memory stands where it says; one that went is gone
			var sn: Dictionary = e.get("numbers", {})
			var vid := String(sn.get("view_id", ""))
			if String(e.get("type", "")) == "sighting_lost" or bool(sn.get("gone", false)):
				armies.erase(vid)
				army_owner.erase(vid)
			else:
				armies[vid] = String(sn.get("location", ""))
				army_owner[vid] = String(sn.get("owner", ""))
			continue
		if model.has("forts") and String(e.get("type", "")) in ["recruited", "ruler_arrived"] and not ids.is_empty():
			var fids0: Array = e.get("factions", [])
			if not army_owner.has(ids[0]) and not fids0.is_empty():
				army_owner[ids[0]] = fids0[0]
		match String(e.get("type", "")):
			"army_moved":
				if not ids.is_empty() and not provs.is_empty():
					armies[ids[0]] = provs[provs.size() - 1]
			"battle", "border_battle":
				for aid in (e.get("numbers", {}) as Dictionary).get("destroyed", []):
					armies.erase(aid)
			"ruler_died":
				var aid := String((e.get("numbers", {}) as Dictionary).get("army", ""))
				if aid.is_empty() and not ids.is_empty():
					aid = String(ids[0]) ## M5-3: a ruler's death as a rival's viewer is told it names the stand-in, not true numbers
				if not aid.is_empty():
					armies.erase(aid)
			"captured", "vassal_joined":
				var fids: Array = e.get("factions", [])
				if not provs.is_empty() and not fids.is_empty():
					owners[provs[0]] = fids[0]
			"recruited", "ruler_arrived":
				if not ids.is_empty() and not provs.is_empty():
					armies[ids[0]] = provs[0]
	var out := {"owners": owners, "armies": armies}
	if model.has("forts"):
		out.merge(SiegeBoard.apply_events(model, events))
		for aid in army_owner.keys():
			if not armies.has(aid):
				army_owner.erase(aid)
		out["army_owner"] = army_owner
		out["inside"] = SiegeBoard.inside_of(out["forts"], owners, armies, army_owner)
	return out


## The beats of a turn, in the order they play:
##   "marches"   [{"army", "owner", "hops": [province ids from start to end], "to_border": bool
##                (a border battle's loser: it marches to the crossing and falls there), "survived"}]
##   "battles"   [{"kind", "provinces", "winner", "destroyed": [army ids], "armies": [army ids], "text" (the turn
##                report's own line for it, TurnReportText.line, so the board and the report say the same)}]
##   "captures"  [{"province", "owner", "battle": index into battles or -1}]
##   "recruits"  [{"army", "province", "new_army": bool}]
##   "arrivals"  [{"army", "province"}] (a successor ruler at the capital)
##   "fallen"    {army id: index of the battle it fell in}
##   "turn"      the 1-based turn that resolved
## M3c S-4, in a game with sieges: a battle at a fort also carries "siege" (the battle's siege block, numbers.siege:
## its "kind" storm / open / breach, "why", "from_inside" ...; {} elsewhere), and
##   "forts"     [{"kind": the event type (SiegeBoard.FORT_EVENTS), "province", "phase", "numbers", "armies",
##                "factions", "text" (the turn report's own line, TurnReportText.line), "label" (the caption's words,
##                SiegeBoard.beat_label), "event" (the event itself, for SiegeBoard.apply_one)}] in report order: the
##                sieges phase's beats, a site started in recruitment, a site razed in capture
static func plan(before: GameState, events: Array, after: GameState) -> Dictionary:
	var marches: Array = []
	var battles: Array = []
	var captures: Array = []
	var recruits: Array = []
	var arrivals: Array = []
	var forts: Array = []
	var rituals: Array = []
	var sightings: Array = []
	var claimed := {}  # M5-3: stand-in ids a seen march has taken
	var fallen := {}
	var marching := {}  # army id -> index in marches
	var battle_at := {}  # province id -> battle index (province battles)
	for e in events:
		var t := String(e.get("type", ""))
		var provs: Array = e.get("provinces", [])
		var ids: Array = e.get("armies", [])
		if bool(e.get("synthetic", false)):
			var sn: Dictionary = e.get("numbers", {})
			sightings.append({"kind": t, "id": String(sn.get("view_id", "")), "province": String(sn.get("location", "")),
				"owner": String(sn.get("owner", "")), "level": String(sn.get("level", "")), "gone": t == "sighting_lost" or bool(sn.get("gone", false))})
			continue
		if t in RITUAL_EVENTS:
			rituals.append(_ritual_beat(e, before))
			continue
		if SiegeBoard.FORT_EVENTS.has(t) and not provs.is_empty():
			var fb := {"kind": t, "province": provs[0], "phase": String(e.get("phase", "")),
				"numbers": (e.get("numbers", {}) as Dictionary).duplicate(true), "armies": ids.duplicate(),
				"factions": (e.get("factions", []) as Array).duplicate(), "text": TurnReportText.line(e, events, after),
				"event": e, "rebuilt": bool(e.get("rebuilt", false))}
			fb["label"] = SiegeBoard.beat_label(fb, after)
			forts.append(fb)
			continue
		if t in BATTLES:
			var n: Dictionary = e.get("numbers", {})
			var bi := battles.size()
			battles.append({"kind": t, "provinces": provs.duplicate(), "winner": String(n.get("winner", "")),
				"destroyed": (n.get("destroyed", []) as Array).duplicate(), "armies": ids.duplicate(), "text": TurnReportText.line(e, events, after),
				"siege": (n.get("siege", {}) as Dictionary).duplicate(true)})
			for aid in n.get("destroyed", []):
				fallen[aid] = bi
			if t == "battle" and not provs.is_empty():
				battle_at[provs[0]] = bi
			elif t == "border_battle" and provs.size() >= 2:
				## the losers never complete their moves (no army_moved): they march to the crossing and fall
				for aid in n.get("destroyed", []):
					var a := before.find_army(aid)
					if a == null:
						continue
					var other: String = provs[1] if a.location == provs[0] else provs[0]
					marching[aid] = marches.size()
					marches.append({"army": aid, "owner": a.owner, "hops": [a.location, other], "to_border": true, "survived": false})
		elif t == "army_moved":
			if bool(e.get("rebuilt", false)):
				## M5-3: a rival column the viewer saw (pooled and rounded: no true ids): its stand-in's block marches
				marches.append_array(_seen_marches(before, after, e, claimed))
				continue
			if ids.is_empty() or provs.size() < 2:
				continue
			var aid2 := String(ids[0])
			var a2 := before.find_army(aid2)
			marching[aid2] = marches.size()
			marches.append({"army": aid2, "owner": a2.owner if a2 != null else String((e.get("factions", [""]) as Array)[0]),
				"hops": provs.duplicate(), "to_border": false, "survived": after.find_army(aid2) != null})
		elif t == "captured" or t == "vassal_joined":
			var fids: Array = e.get("factions", [])
			if provs.is_empty() or fids.is_empty():
				continue
			captures.append({"province": provs[0], "owner": fids[0], "battle": int(battle_at.get(provs[0], -1)), "kind": t,
				"rebuilt": bool(e.get("rebuilt", false))})
		elif t == "recruited":
			if ids.is_empty() or provs.is_empty():
				continue
			recruits.append({"army": ids[0], "province": provs[0], "new_army": bool((e.get("numbers", {}) as Dictionary).get("new_army", false))})
		elif t == "ruler_arrived":
			if not ids.is_empty() and not provs.is_empty():
				arrivals.append({"army": ids[0], "province": provs[0]})
		elif t == "ruler_died":
			var dead := String((e.get("numbers", {}) as Dictionary).get("army", ""))
			if dead.is_empty() and not ids.is_empty():
				dead = String(ids[0]) ## M5-3: told as a rival's viewer, it names the ruler's stand-in
			if not dead.is_empty() and not fallen.has(dead):
				fallen[dead] = battles.size() - 1
	## a march that fell in a battle is marked as fallen (a border battle's winner that lost every fighter)
	for m in marches:
		if fallen.has(m["army"]):
			m["survived"] = false
	return {"marches": marches, "battles": battles, "captures": captures, "recruits": recruits, "arrivals": arrivals,
		"fallen": fallen, "turn": after.current_turn, "forts": forts, "rituals": rituals, "sightings": sightings}


## M5-3: the seen marches of one rebuilt `army_moved` (FogRules._rebuilt_move: the armies of one rival that left a province
## the viewer could see by the same first step, pooled): the block of each stand-in of that faction at the place it left that
## no other seen march has taken (the ruler's only when the move names a ruler), under the alias "~seen~<stand-in id>". The
## march walks to the border and fades when the faction has no sighting at its end in the view after (the road led out
## of sight), else the whole way to the stage; either way the view after's own stand-ins fade in beside it. Pure: the stand-ins
## are read from `before`, the viewer's own view.
static func _seen_marches(before: GameState, after: GameState, e: Dictionary, claimed: Dictionary) -> Array:
	var n: Dictionary = e.get("numbers", {})
	var fid := String(n.get("faction", ""))
	var from := String(e.get("view_from", n.get("from", "")))
	var to := String(e.get("view_to", n.get("to", "")))
	var out: Array = []
	if fid.is_empty() or from.is_empty() or to.is_empty():
		return out
	var named: Array = n.get("types", [])
	var away := true
	for a in after.armies:
		if a.owner == fid and a.location == to and String(a.seen.get("level", "")) != FogData.MEMORY:
			away = false
			break
	var ids: Array = []
	for a in before.armies:
		if a.owner != fid or a.location != from or (String(a.seen.get("level", "")) != FogRules.GLIMPSE and String(a.seen.get("level", "")) != FogRules.CLEAR):
			continue
		if claimed.has(a.id) or (a.ruler != null and not named.has(a.ruler.type.id)):
			continue
		ids.append(a.id)
	ids.sort()
	for id in ids:
		claimed[id] = true
		out.append({"army": "~seen~" + String(id), "alias_of": String(id), "owner": fid, "hops": [from, to], "to_border": away,
			"survived": false, "seen": true})
	return out


## M5-3: one ritual's beat: {"kind" (the event type), "ritual", "faction" (the caster's), "from", "at", "global"}. `from` is where
## it starts: the viewer's own cast at its caster (the event names it), a turned-aside ritual of the viewer's at its caster's army;
## "" for everything else, so a ritual that fell on the viewer's land from a hidden caster starts at the target, and a heralded
## global ritual (no province) starts nowhere.
static func _ritual_beat(e: Dictionary, before: GameState) -> Dictionary:
	var t := String(e.get("type", ""))
	var provs: Array = e.get("provinces", [])
	var n: Dictionary = e.get("numbers", {})
	var facs: Array = e.get("factions", [])
	var from := ""
	var at := String(provs.back()) if not provs.is_empty() else ""
	match t:
		"ritual_cast":
			if not bool(e.get("rebuilt", false)) and not provs.is_empty():
				from = String(provs[0])
		"ritual_turned_aside":
			var ids: Array = e.get("armies", [])
			var caster := before.find_army(String(ids[0])) if not ids.is_empty() and before != null else null
			if caster != null and caster.seen.is_empty():
				from = caster.location
	return {"kind": t, "ritual": String(n.get("ritual", "")), "faction": String(facs[0]) if not facs.is_empty() else "", "from": from, "at": at,
		"global": bool(n.get("global", false)) or at.is_empty()}


## True when a plan has nothing to play (no march, battle, capture, recruit, arrival or fort beat). M5-3: a turn that only changes
## what the viewer sees (sightings: a block fading into the veil, a ghost appearing) is not played for itself: it would be a few
## seconds of nothing most turns of a fog game. The board shows the view after at once, and the report says what was seen;
## in a turn that does play, the sightings animate with the re-form.
static func is_empty(plan: Dictionary) -> bool:
	for k in ["marches", "battles", "recruits", "arrivals", "captures", "forts"]:
		if not (plan.get(k, []) as Array).is_empty():
			return false
	return true


## The province a battle is drawn at: a province battle's province, or a border battle's two ends.
static func battle_label(b: Dictionary, state: GameState) -> String:
	var provs: Array = b.get("provinces", [])
	var names: Array = []
	for pid in provs:
		var p := state.find_province(pid)
		names.append(p.name if p != null else "")
	if b.get("kind", "") == "border_battle" and names.size() >= 2:
		return "Battle on the border of %s and %s" % [names[0], names[1]]
	var at: String = names[0] if not names.is_empty() else ""
	## M3c S-4: a battle at a fort's walls says which (its siege block's "why", design/M3C_SIEGES.md §3.9)
	match String((b.get("siege", {}) as Dictionary).get("why", "")):
		"storm":
			return "Storm of %s" % at
		"breach":
			return "Battle in the breach at %s" % at
		"sally", "gate":
			return "The garrison of %s sallies" % at
		"relief":
			return "Relief of %s" % at
		"relief_sally":
			return "Relief of %s, the garrison sallying" % at
	return "Battle at %s" % at
