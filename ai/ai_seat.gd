class_name AISeat
extends RefCounted
## Plays the computer seats of a GameSession (#35, design/M2_RULER.md 6.2). Pure code: no nodes, no
## scenes, so a human-vs-computer game runs headless in tests exactly as it does on screen.
##
##   var session := GameSession.new(GameState.new(seed), ["kingdom", "beasts"], seed, resolver, {"beasts": "normal"})
##   var computer := AISeat.new(session, seed)
##   computer.play(session)   # after every human end_turn (and once at the start)
##
## When a computer seat's ORDERS phase starts, take_turn() reads the start-of-turn state from
## session.state() (it never sees another seat's pending orders: the session hands out nothing but the
## state), asks that seat's AIPlayer for orders, queues each one through session.queue_order (the same
## OrderBook checks a person's orders get) and ends the turn. Its orders go into the session's history
## like anyone's, so GameSession.replay rebuilds the game without running the AI again.
##
## Determinism: one AIPlayer and one SeededRNG per computer seat for the whole game. The RNG is seeded
## with seat_seed(game_seed, seat) = game_seed * 7919 + (seat + 1) * 104729, the formula behind the
## autoplay's Simulator.policy_seed and the AI build pick in design/M2_RULER.md 6.1, so the same seed
## and the same human orders always give the same computer orders. A save would store rng_state().
##
## Notes: AIPlayer.last_plan_notes() say what the computer is about to do, so they would give away its
## simultaneous orders. They are kept per planned turn, and report_notes(session) only ever returns the
## notes of the last RESOLVED turn. A computer in seat 1 has already planned the next turn when the
## human reads the report; those notes stay hidden until that turn resolves too.

const SEED_FACTOR := 7919
const SEAT_FACTOR := 104729
const LEVEL_NAMES := {"easy": "Easy", "normal": "Normal"}

var _levels := {}  # faction id -> level
var _seats := {}  # faction id -> 0-based seat
var _brains := {}  # faction id -> AIPlayer
var _rngs := {}  # faction id -> SeededRNG, one per seat for the whole game
var _notes := {}  # 1-based turn -> {faction id: Array of plain-language notes}
var _stats := {}  # 1-based turn -> {faction id: AIPlayer.last_plan_stats()}
var _rejected: Array = []  # {"turn", "faction", "order", "why"}: orders the session refused (expected: none)


## Sets up a brain and an RNG for every computer seat of `session`, seeded from `game_seed` (the game
## seed the session was started with).
func _init(session: GameSession = null, game_seed: int = 0) -> void:
	if session == null:
		return
	var players := session.players()
	var seats := session.computer_seats()
	for fid in seats:
		var seat := players.find(fid)
		if seat < 0:
			continue
		_levels[fid] = String(seats[fid])
		_seats[fid] = seat
		_brains[fid] = AIPlayer.new()
		_rngs[fid] = SeededRNG.new(seat_seed(game_seed, seat))


## The RNG seed of the computer in the 0-based seat `seat`.
static func seat_seed(game_seed: int, seat: int) -> int:
	return game_seed * SEED_FACTOR + (seat + 1) * SEAT_FACTOR


## "Easy", "Normal".
static func level_name(level: String) -> String:
	return LEVEL_NAMES.get(level, String(level).capitalize())


## The tag shown next to a computer faction: "Computer (Normal)".
static func tag_text(level: String) -> String:
	return "Computer (%s)" % level_name(level)


## The tag's tooltip body: who plays the seat and how, in plain words (the codex link is added by the UI).
static func tag_help(faction_name: String, level: String) -> String:
	var how := "Easy makes more mistakes: it passes up some good attacks, recruits at random and keeps a thinner guard on its capital." if level == "easy" \
		else "Normal plays as well as it can: it checks the odds before every risky battle and never leaves its capital open."
	return "The computer plays %s at the %s level, by the same rules as you. It gives its orders at the same time as you, without seeing yours. %s After each turn, the turn report shows what it was thinking." % [
		faction_name, level_name(level), how]


func is_computer(faction_id: String) -> bool:
	return _brains.has(faction_id)


func level(faction_id: String) -> String:
	return String(_levels.get(faction_id, ""))


## The computer seats' faction ids, in seat order.
func factions() -> Array:
	var out := _seats.keys()
	out.sort_custom(func(a, b): return _seats[a] < _seats[b])
	return out


## The RNG state of each computer seat ({faction id: SeededRNG.to_dict()}), for a save or a test.
func rng_state() -> Dictionary:
	var out := {}
	for fid in _rngs:
		out[fid] = _rngs[fid].to_dict()
	return out


## Orders the session refused, {"turn", "faction", "order", "why"}. AIPlayer checks every order with the
## rules first, so this should stay empty; it is kept so tests and tools can prove it.
func rejections() -> Array:
	return _rejected.duplicate(true)


## Plays the current seat if the computer has it: plans from the start-of-turn state, queues every
## order and ends the turn. Returns "" when it played, otherwise why it could not.
func take_turn(session: GameSession) -> String:
	if session == null or session.phase() != GameSession.Phase.ORDERS:
		return "The computer can only give orders while a seat is giving orders."
	var fid := session.current_player()
	if not is_computer(fid):
		return "It is a person's turn, not the computer's."
	var turn := session.turn_number()
	var brain: AIPlayer = _brains[fid]
	var orders: Array = brain.plan_orders(session.state(), fid, _rngs[fid], _levels[fid])
	for o in orders:
		var why := session.queue_order(o)
		if not why.is_empty():
			_rejected.append({"turn": turn, "faction": fid, "order": o.to_dict() if o.has_method("to_dict") else str(o), "why": why})
	if not _notes.has(turn):
		_notes[turn] = {}
		_stats[turn] = {}
	_notes[turn][fid] = brain.last_plan_notes()
	_stats[turn][fid] = brain.last_plan_stats()
	return session.end_turn()


## Plays every computer seat that is due, in seat order, until a person has to act, the game is over or
## a turn has resolved (so with no human seat, each call plays exactly one turn). Returns
## {"played": [faction ids, in the order they played], "resolved": whether a turn resolved}.
func play(session: GameSession) -> Dictionary:
	var played := []
	var resolved := false
	if session == null:
		return {"played": played, "resolved": resolved}
	var guard := session.players().size()
	while guard > 0 and session.is_computer_turn() and is_computer(session.current_player()):
		guard -= 1
		var fid := session.current_player()
		var before := session.turns_played()
		var why := take_turn(session)
		if not why.is_empty():
			push_error("The computer could not end its turn: %s" % why)
			break
		played.append(fid)
		if session.turns_played() > before:
			resolved = true
			break
	return {"played": played, "resolved": resolved}


## The computer's notes for the turn the session last resolved, one entry per computer seat in seat
## order: {"faction", "faction_name", "seat" (0-based), "level", "notes": [plain-language lines]}.
## Empty before the first resolution. Never the notes of a turn that has not resolved.
func report_notes(session: GameSession) -> Array:
	var out := []
	if session == null:
		return out
	var turn := int(session.turn_report().get("turn", 0))
	if turn <= 0 or turn > session.turns_played() or not _notes.has(turn):
		return out
	var state := session.state()
	for fid in factions():
		if not _notes[turn].has(fid):
			continue
		var f: Faction = state.find_faction(fid) if state else null
		out.append({"faction": fid, "faction_name": f.faction_name if f else "The computer", "seat": _seats[fid],
			"level": _levels[fid], "notes": _notes[turn][fid].duplicate()})
	return out


## The computer's plan counters for `turn` (1-based), {faction id: AIPlayer.last_plan_stats()}.
func turn_stats(turn: int) -> Dictionary:
	return _stats.get(turn, {}).duplicate(true)
