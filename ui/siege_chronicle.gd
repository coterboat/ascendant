class_name SiegeChronicle
extends RefCounted
## What a game of forts and sieges has seen so far, for the screens (M3c S-3, #101; design/M3C_SIEGES.md §9.5 and
## §15's victory screen line). The resolver can't flag a game's first siege (the state keeps no history), so the
## game screen keeps this from the turn reports as turns resolve, and rebuilds it for a loaded game:
##   - the first-siege sentences (§9.5): the first siege, storm, sally and breach each end their report line
##     with two plain sentences and a codex link, once per player per game. "Seen" is kept per player (the
##     viewer the report is shown to: every hotseat seat reads its own), the way a one-time tip is remembered,
##     and the report of the turn it happened keeps it when reopened;
##   - the victory screen's numbers per faction: forts built, sieges won (a fort that fell to its besiegers, or
##     a siege its owner broke by beating the siege lines) and storms fought.
## Pure bookkeeping over events: it never changes a game.
##
##   add_turn(turn, events)         count a resolved turn's report (once per turn)
##   teach(events, viewer, turn)    [{"event", "kind", "title", "text", "codex"}] for the report `viewer` reads
##   mark_seen(players)             a loaded game: every player has seen what happened before
##   stats()                        {faction id: {"forts_built", "sieges_won", "storms"}}
##   rebuild(record, resolver)      the chronicle of a saved game, replayed from its record

const KINDS := ["siege", "storm", "sally", "breach"]
const TITLES := {"siege": "Your first siege", "storm": "The first storm", "sally": "The first sally", "breach": "The first breach"}
const CODEX := {"siege": "siege", "storm": "storm", "sally": "sally", "breach": "breach"}

var firsts := {}  # kind -> the turn of the game's first such event
var seen := {}  # viewer -> {kind -> the turn whose report showed it}
var counts := {}  # faction id -> {"forts_built", "sieges_won", "storms"}
var _turns := {}  # turns already counted


## The two plain sentences of each kind (§9.5), from the rules' numbers.
static func sentence(kind: String) -> String:
	match kind:
		"siege":
			return "A siege: the besiegers don't fight unless they storm the walls or the garrison comes out. Each turn the walls drop a little, and when they are down the battle comes on its own."
		"storm":
			return "A storm: the besiegers went over the walls instead of waiting for them to fall. Every fighter of the garrison had +%d defense for every %d wall strength still standing." % [
				FortData.WALLS_DEFENSE_PER_STEP, FortData.WALL_STEP]
		"sally":
			return "A sally: the garrison came out to fight the siege lines in the open, where nobody gets walls or ground. Its fighters from inside kept +%d cover." % FortData.COVER_DEFENSE
		"breach":
			return "A breach: with the walls at 0 nobody storms or sallies; the battle comes on its own, in the open, and the garrison keeps +%d cover among the ruins. The walls repair only once no enemy army is there." % FortData.COVER_DEFENSE
	return ""


## Which teaching moment `e` is: "siege" (a siege started), "breach" (walls reached 0), "storm" or "sally" (a
## battle at a fort, from its `siege` block, §4.4), or "".
static func kind_of(e: Dictionary) -> String:
	match String(e.get("type", "")):
		"siege_started":
			return "siege"
		"walls_breached":
			return "breach"
		"battle":
			var siege = e.get("numbers", {}).get("siege", {})
			if siege is Dictionary and not siege.is_empty():
				if String(siege.get("kind", "")) == "storm":
					return "storm"
				if ["sally", "relief_sally", "gate"].has(String(siege.get("why", ""))):
					return "sally"
	return ""


## Counts the report of `turn` (each turn once): its first-of-kind moments and each faction's numbers.
func add_turn(turn: int, events: Array) -> void:
	if turn <= 0 or _turns.has(turn):
		return
	_turns[turn] = true
	for e in events:
		var kind := kind_of(e)
		if not kind.is_empty() and (not firsts.has(kind) or int(firsts[kind]) > turn):
			firsts[kind] = turn
		var numbers: Dictionary = e.get("numbers", {})
		match String(e.get("type", "")):
			"fort_built":
				var factions: Array = e.get("factions", [])
				if not factions.is_empty():
					_add(String(factions[0]), "forts_built")
			"siege_ended":
				_add(String(numbers.get("besieger", "")), "sieges_won")
			"siege_lifted":
				if String(numbers.get("why", "")) == "beaten":
					_add(String(numbers.get("owner", "")), "sieges_won")
		if kind == "storm":
			for side in numbers.get("report", {}).get("sides", []):
				if side is Dictionary and not bool(side.get("defender", false)):
					_add(String(side.get("faction", "")), "storms")


## The first-siege sentences for the report of `turn` that `viewer` reads ("" for nobody in particular): for
## each kind `viewer` hasn't seen before this turn, the first such event in `events`. Marks them seen.
func teach(events: Array, viewer: String, turn: int) -> Array:
	var out := []
	if not seen.has(viewer):
		seen[viewer] = {}
	var mine: Dictionary = seen[viewer]
	for kind in KINDS:
		if mine.has(kind) and int(mine[kind]) != turn:
			continue
		for e in events:
			if kind_of(e) == kind:
				mine[kind] = turn
				out.append({"event": e, "kind": kind, "title": TITLES[kind], "text": sentence(kind), "codex": CODEX[kind]})
				break
	return out


## A loaded game: every player has seen every moment that happened before (each on the turn it happened).
func mark_seen(players: Array) -> void:
	for fid in players + [""]:
		if not seen.has(fid):
			seen[fid] = {}
		for kind in firsts:
			if not seen[fid].has(kind):
				seen[fid][kind] = int(firsts[kind])


## {faction id: {"forts_built", "sieges_won", "storms"}} for every faction counted.
func stats() -> Dictionary:
	return counts.duplicate(true)


func _add(fid: String, key: String) -> void:
	if fid.is_empty():
		return
	if not counts.has(fid):
		counts[fid] = {"forts_built": 0, "sieges_won": 0, "storms": 0}
	counts[fid][key] = int(counts[fid][key]) + 1


## The chronicle of a saved game (GameSession.record()), replayed turn by turn with `resolver` (the game's
## own battle resolver, so the battles come out the same). An empty chronicle for a game without sieges or a
## record that can't be read; the game's own loading reports those.
static func rebuild(game_record: Dictionary, resolver: BattleResolver = null) -> SiegeChronicle:
	var out := SiegeChronicle.new()
	var start = game_record.get("start_state")
	if not (start is Dictionary) or not bool(start.get("sieges", false)):
		return out
	var state := GameState.from_dict(start, [])
	if state == null:
		return out
	var history = game_record.get("history", [])
	if not (history is Array):
		return out
	for i in history.size():
		var entry = history[i]
		if not (entry is Dictionary):
			return out
		var orders := OrderBook.orders_from_dict(entry.get("orders", {}), [])
		var result := TurnResolver.resolve(state, orders, Serial.to_int(entry.get("seed", 0)), resolver)
		if result.new_state == null:
			return out
		state = result.new_state
		out.add_turn(i + 1, result.events)
	out.mark_seen(game_record.get("players", []))
	return out
