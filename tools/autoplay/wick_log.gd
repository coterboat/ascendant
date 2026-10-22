extends RefCounted
## CW-11 (#262, design/CANDLEWAKE.md §9): what a game with a Wick faction (the Candlewake) did with its flame and its Wake, turn by
## turn, for the W bands. Pure functions over the start-of-turn state, the end-of-turn state and the turn's events, like MagicLog:
## the simulator calls record_turn after every turn of a game where WickRules.in_play.
##
##   var log := WickLog.new_log()
##   WickLog.record_turn(log, turn, start_state, state, events)   # after every resolved turn
##
## The log, per Wick faction id: {
##   "battle_flames": [the flame each of its armies fought at, one per army per battle (W1)],
##   "guttered": turns with a guttered event (W2), "army_turns": {army id: [turns seen, turns at the cap]} (W2),
##   "harvest": units Half-Death's Harvest raised (W3), "risen": units the Risen raised (W6),
##   "wake_line_at": {turn: its Wake-Line-or-deeper provinces at the end of that turn} for WAKE_TURNS (W4),
##   "wake_cost": gold the Wake's income parts took (W4), "income": its income summed over the turns (W4)}.
## A battle's flame is WickRules.battle_flame on the start-of-turn army: the flame the battle phase begins with but for a Kindle
## cast in this turn's rituals phase, which the report counts as the flame before it (a slight understatement, never more).

## The turns whose Wake-Line count W4 reads (turn 12), and its neighbours for the report.
const WAKE_TURNS := [8, 12, 16]


static func new_log() -> Dictionary:
	return {}


static func _side(log: Dictionary, fid: String) -> Dictionary:
	if not log.has(fid):
		log[fid] = {"battle_flames": [], "guttered": 0, "army_turns": {}, "harvest": 0, "risen": 0, "wake_line_at": {},
			"wake_cost": 0, "income": 0}
	return log[fid]


## Records one resolved turn (1-based `turn`): `start` is the state the turn began with, `state` the state after it, `events` its
## turn report's events. Does nothing in a game where no faction keeps a flame.
static func record_turn(log: Dictionary, turn: int, start: GameState, state: GameState, events: Array) -> void:
	if not WickRules.in_play(state):
		return
	var guttered := {}
	for e in events:
		var type := String(e.get("type", ""))
		var n: Dictionary = e.get("numbers", {})
		if WickRules.BATTLE_TYPES.has(type):
			for aid in e.get("armies", []):
				var a: Army = start.find_army(String(aid)) if start != null else null
				if a != null and WickRules.carries_flame(a):
					_side(log, a.owner).battle_flames.append(WickRules.battle_flame(start, a))
		elif type == "guttered":
			var a := state.find_army(String(n.get("army", "")))
			if a != null:
				guttered[a.owner] = true
		elif type == "harvest":
			var a := state.find_army(String(n.get("army", "")))
			var owner: String = a.owner if a != null else _wick_owner(state)
			_side(log, owner).harvest += int(n.get("count", 0))
		elif type == "risen":
			var a := state.find_army(String(n.get("army", "")))
			var owner: String = a.owner if a != null else String(state.find_province(String(n.get("province", ""))).owner)
			_side(log, owner).risen += int(n.get("count", 0))
	for fid in guttered:
		_side(log, fid).guttered += 1
	for f in state.factions:
		if not WickRules.has_wick(f.id):
			continue
		var side := _side(log, f.id)
		var cap := WickRules.cap(state, f.id)
		for a in state.armies:
			if a.owner != f.id or not WickRules.carries_flame(a):
				continue
			var seen: Array = side.army_turns.get(a.id, [0, 0])
			seen[0] += 1
			if a.flame >= cap:
				seen[1] += 1
			side.army_turns[a.id] = seen
		var income := TurnResolver.income_of(state, f.id)
		side.income += int(income.total)
		for p in state.provinces:
			if p.owner != f.id:
				continue
			for part in MarkRules.income_parts(state, p):
				if int(part.value) < 0:
					side.wake_cost -= int(part.value)
		if WAKE_TURNS.has(turn):
			side.wake_line_at[turn] = wake_line_count(state, f.id)


## The provinces `faction_id` holds whose own mark stands at the Wake-Line or deeper, as the land looks now.
static func wake_line_count(state: GameState, faction_id: String) -> int:
	var line := MarkData.stage_index(faction_id, WickRules.PYRE_STAGE)
	if line <= 0:
		return 0
	var n := 0
	for p in state.provinces:
		if p.owner == faction_id and MarkRules.stage_now(state, p.id) >= line:
			n += 1
	return n


static func _wick_owner(state: GameState) -> String:
	for f in state.factions:
		if WickRules.has_wick(f.id):
			return f.id
	return ""

