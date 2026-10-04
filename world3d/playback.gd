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
##   apply_events(model, events)    -> the model after those events (only the events are read)
##   plan(before, events, after)    -> the beats: marches, battles, captures, recruits and arrivals
extends RefCounted

const BATTLES := ["battle", "border_battle"]


## What the board shows of a state: who owns each province and where every army stands.
static func model_of(state: GameState) -> Dictionary:
	var owners := {}
	for p in state.provinces:
		owners[p.id] = p.owner
	var armies := {}
	for a in state.armies:
		armies[a.id] = a.location
	return {"owners": owners, "armies": armies}


## The model after a turn's events, from the events alone:
##   army_moved             the army stands at the event's last province (a road move's way is in between)
##   battle, border_battle  every army in numbers.destroyed is gone
##   ruler_died             the ruler's army is gone (a ruler travels alone, so its army goes with it)
##   captured, vassal_joined   the province now belongs to the event's first faction
##   recruited              the army it joined (or formed) stands at the event's province
##   ruler_arrived          the new ruler's army stands at the capital
static func apply_events(model: Dictionary, events: Array) -> Dictionary:
	var owners: Dictionary = (model.get("owners", {}) as Dictionary).duplicate()
	var armies: Dictionary = (model.get("armies", {}) as Dictionary).duplicate()
	for e in events:
		var provs: Array = e.get("provinces", [])
		var ids: Array = e.get("armies", [])
		match String(e.get("type", "")):
			"army_moved":
				if not ids.is_empty() and not provs.is_empty():
					armies[ids[0]] = provs[provs.size() - 1]
			"battle", "border_battle":
				for aid in (e.get("numbers", {}) as Dictionary).get("destroyed", []):
					armies.erase(aid)
			"ruler_died":
				var aid := String((e.get("numbers", {}) as Dictionary).get("army", ""))
				if not aid.is_empty():
					armies.erase(aid)
			"captured", "vassal_joined":
				var fids: Array = e.get("factions", [])
				if not provs.is_empty() and not fids.is_empty():
					owners[provs[0]] = fids[0]
			"recruited", "ruler_arrived":
				if not ids.is_empty() and not provs.is_empty():
					armies[ids[0]] = provs[0]
	return {"owners": owners, "armies": armies}


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
static func plan(before: GameState, events: Array, after: GameState) -> Dictionary:
	var marches: Array = []
	var battles: Array = []
	var captures: Array = []
	var recruits: Array = []
	var arrivals: Array = []
	var fallen := {}
	var marching := {}  # army id -> index in marches
	var battle_at := {}  # province id -> battle index (province battles)
	for e in events:
		var t := String(e.get("type", ""))
		var provs: Array = e.get("provinces", [])
		var ids: Array = e.get("armies", [])
		if t in BATTLES:
			var n: Dictionary = e.get("numbers", {})
			var bi := battles.size()
			battles.append({"kind": t, "provinces": provs.duplicate(), "winner": String(n.get("winner", "")),
				"destroyed": (n.get("destroyed", []) as Array).duplicate(), "armies": ids.duplicate(), "text": TurnReportText.line(e, events, after)})
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
			captures.append({"province": provs[0], "owner": fids[0], "battle": int(battle_at.get(provs[0], -1)), "kind": t})
		elif t == "recruited":
			if ids.is_empty() or provs.is_empty():
				continue
			recruits.append({"army": ids[0], "province": provs[0], "new_army": bool((e.get("numbers", {}) as Dictionary).get("new_army", false))})
		elif t == "ruler_arrived":
			if not ids.is_empty() and not provs.is_empty():
				arrivals.append({"army": ids[0], "province": provs[0]})
		elif t == "ruler_died":
			var dead := String((e.get("numbers", {}) as Dictionary).get("army", ""))
			if not dead.is_empty() and not fallen.has(dead):
				fallen[dead] = battles.size() - 1
	## a march that fell in a battle is marked as fallen (a border battle's winner that lost every fighter)
	for m in marches:
		if fallen.has(m["army"]):
			m["survived"] = false
	return {"marches": marches, "battles": battles, "captures": captures, "recruits": recruits, "arrivals": arrivals,
		"fallen": fallen, "turn": after.current_turn}


## The province a battle is drawn at: a province battle's province, or a border battle's two ends.
static func battle_label(b: Dictionary, state: GameState) -> String:
	var provs: Array = b.get("provinces", [])
	var names: Array = []
	for pid in provs:
		var p := state.find_province(pid)
		names.append(p.name if p != null else "")
	if b.get("kind", "") == "border_battle" and names.size() >= 2:
		return "Battle on the border of %s and %s" % [names[0], names[1]]
	return "Battle at %s" % (names[0] if not names.is_empty() else "")
