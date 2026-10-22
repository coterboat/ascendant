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
## session.view_state(faction) (it never sees another seat's pending orders: the session hands out nothing but the
## state), asks that seat's AIPlayer for orders, queues each one through session.queue_order (the same
## OrderBook checks a person's orders get) and ends the turn. Its orders go into the session's history
## like anyone's, so GameSession.replay rebuilds the game without running the AI again.
##
## Determinism: one AIPlayer and one SeededRNG per computer seat for the whole game. The RNG is seeded
## with seat_seed(game_seed, seat) = game_seed * 7919 + (seat + 1) * 104729, the formula behind the
## autoplay's Simulator.policy_seed and the AI build pick in design/M2_RULER.md 6.1, so the same seed
## and the same human orders always give the same computer orders. A save stores rng_state() from the
## start of the turn, and restore() puts it back (SaveGame).
##
## Builds (M2, design/M2_RULER.md 6.1): in a game with rulers, the seat's build is the first draw of its
## RNG, AIPlayer.choose_build, made here when the seat is set up; its orders use the draws after it. The
## build screen picks a computer seat's build with the same call on the same seed (BuildScreen.computer_build),
## so the build in the starting state is the one rolled here, and build(faction) returns it. The brain
## always plays the build the state holds (AIPlayer.preset_for). A game without rulers makes no draw.
##
## Paths (M4, design/M4_ASCENSION.md §8.1): each brain is told its game seed and seat (AIPlayer.configure),
## so its side of the fork is AIPlayer.choose_branch's roll, the first draw of a stream of its own
## (seat_seed + AIPaths.BRANCH_SALT). The seat RNG makes no extra draw, so M1 and M2 games are unchanged,
## and a restored save rolls the same side.
##
## Temperament (#184): each brain plays the temperament the session gives its seat (GameSession.computer_temperament),
## "normal" unless the game's config said otherwise. The new game screen and Quick start roll one for every computer seat
## (temperaments_for: AIPlayer.choose_temperament, a stream of its own, so the seat RNG makes no extra draw); the session
## records it, so a loaded save plays on with the same one. A game started without temperaments plays "normal" in every
## seat, exactly as before. temperament(faction) returns it.
##
## Fog of war (M5-4, design/M5_MAGIC_FOG.md §10.1): the computer is handed its VIEW and nothing else. In a game with
## fog, view_state(faction) is FogRules.view_state: its own side whole and the rival's armies as the stand-ins it has
## sighted or remembers (AIFog drops the old ghosts before it plans). The seat never calls a truth accessor of the
## session (state, turn_report, battle_events, builds, record, history, victory): the build pick reads the view, and
## report_notes the filtered turn_report_for. Its orders are checked on the true state by the same OrderBook, which
## reads only public facts and the seat's own state (§2.10), so none are refused. With fog off, view_state is
## state(), and the games are the same as before.
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
var _builds := {}  # faction id -> AIPlayer.choose_build (games with rulers only): the RNG's first draw
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
		var view := session.state_for(fid)  # its view in a fog game (public facts all that is read here), else the state
		var rulers := view != null and RulerRules.has_rulers(view)
		_levels[fid] = String(seats[fid])
		_seats[fid] = seat
		_brains[fid] = AIPlayer.new()
		_brains[fid].configure(game_seed, seat)  # M4: the side of the fork is this seat's roll (no effect without paths)
		_brains[fid].set_temperament(session.computer_temperament(fid))  # #184: "normal" unless the game gave it another
		_rngs[fid] = SeededRNG.new(seat_seed(game_seed, seat))
		if rulers:
			_builds[fid] = AIPlayer.choose_build(view, fid, _rngs[fid])


## The RNG seed of the computer in the 0-based seat `seat`.
static func seat_seed(game_seed: int, seat: int) -> int:
	return game_seed * SEED_FACTOR + (seat + 1) * SEAT_FACTOR


## #184: the temperament each computer seat plays, as the new game screen and Quick start put it in a game's config
## ("temperaments"): {faction id: AIPlayer.choose_temperament(game_seed, its 0-based seat)} for every faction of
## `computer_seats` ({faction id: level}) seated in `players`. A pure function of the seed and the seating.
static func temperaments_for(players: Array, computer_seats: Dictionary, game_seed: int) -> Dictionary:
	var out := {}
	for i in players.size():
		var fid := String(players[i])
		if computer_seats.has(fid):
			out[fid] = AIPlayer.choose_temperament(game_seed, i)
	return out


## "Easy", "Normal".
static func level_name(level: String) -> String:
	return LEVEL_NAMES.get(level, String(level).capitalize())


## The tag shown next to a computer faction: "Computer (Normal)".
static func tag_text(level: String) -> String:
	return "Computer (%s)" % level_name(level)


## The tag's tooltip body: who plays the seat and how, in plain words (the codex link is added by the UI). #184: with a
## `temperament`, its style too (AIPlayer.temperament_help).
static func tag_help(faction_name: String, level: String, temperament: String = "") -> String:
	var how := "Easy makes more mistakes: it passes up some good attacks, recruits at random and keeps a thinner guard on its capital." if level == "easy" \
		else "Normal plays as well as it can: it checks the odds before every risky battle and never leaves its capital open."
	var style := "" if temperament.is_empty() else " " + AIPlayer.temperament_line(temperament)
	return "The computer plays %s at the %s level, by the same rules as you. It gives its orders at the same time as you, without seeing yours. %s%s After each turn, the turn report shows what it was thinking." % [
		faction_name, level_name(level), how, style]


func is_computer(faction_id: String) -> bool:
	return _brains.has(faction_id)


func level(faction_id: String) -> String:
	return String(_levels.get(faction_id, ""))


## The temperament the computer seat `faction_id` plays (#184): "normal" or "aggressive", or "" for a seat it doesn't play.
func temperament(faction_id: String) -> String:
	return _brains[faction_id].temperament() if _brains.has(faction_id) else ""


## The computer seats' faction ids, in seat order.
func factions() -> Array:
	var out := _seats.keys()
	out.sort_custom(func(a, b): return _seats[a] < _seats[b])
	return out


## The build the computer seat `faction_id` rolled ({"preset", "ruler", "mandates"}), or {} in a game
## without rulers. It is the build the build screen gave that seat (the same roll on the same seed).
func build(faction_id: String) -> Dictionary:
	return _builds.get(faction_id, {}).duplicate(true)


## The RNG state of each computer seat ({faction id: SeededRNG.to_dict()}), for a save or a test.
func rng_state() -> Dictionary:
	var out := {}
	for fid in _rngs:
		out[fid] = _rngs[fid].to_dict()
	return out


## Restores the computer seats of a saved game (SaveGame): each seat's RNG state, {faction id:
## SeededRNG.to_dict()} as rng_state() gave it at the start of the turn being played, so the computer
## plays on exactly as it would have without the save; and `notes`, {faction id: [lines]} for the 1-based
## `turn` the session last resolved, so that turn's report still shows what the computer was thinking.
## Returns plain-language problems ([] when every computer seat was restored).
func restore(rng_states: Dictionary, turn: int = 0, notes: Dictionary = {}) -> Array:
	var errors := []
	for fid in factions():
		var data = rng_states.get(fid)
		if not (data is Dictionary) or data.get("state") == null:
			errors.append("The save does not have the computer's dice for player %d, so it could not play on the same way." % (_seats[fid] + 1))
			continue
		_rngs[fid].set_state(Serial.to_int(data.state))
	if turn > 0:
		_notes[turn] = {}
		for fid in notes:
			if is_computer(String(fid)) and notes[fid] is Array:
				_notes[turn][String(fid)] = notes[fid].map(func(line): return str(line))
	return errors


## Orders the session refused, {"turn", "faction", "order", "why"}. AIPlayer checks every order with the
## rules first, so this should stay empty; it is kept so tests and tools can prove it.
func rejections() -> Array:
	return _rejected.duplicate(true)


## Plays the current seat if the computer has it: plans from the start-of-turn view (the state when there is no fog),
## queues every order and ends the turn. Returns "" when it played, otherwise why it could not.
func take_turn(session: GameSession) -> String:
	if session == null or session.phase() != GameSession.Phase.ORDERS:
		return "The computer can only give orders while a seat is giving orders."
	var fid := session.current_player()
	if not is_computer(fid):
		return "It is a person's turn, not the computer's."
	var turn := session.turn_number()
	var brain: AIPlayer = _brains[fid]
	var orders: Array = brain.plan_orders(session.view_state(fid), fid, _rngs[fid], _levels[fid])
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
## order: {"faction", "faction_name", "seat" (0-based), "level", "temperament" (#184), "notes": [plain-language lines]}.
## Empty before the first resolution. Never the notes of a turn that has not resolved. M5-4: read through the
## first computer seat's view (turn_report_for, state_for): the turn number and the faction names are public.
## Under fog the notes name the computer's hidden armies and plans; the screen keeps them back until the game is over
## (GameScreen), they stay in the save.
func report_notes(session: GameSession) -> Array:
	var out := []
	if session == null or _seats.is_empty():
		return out
	var reader: String = factions()[0]
	var turn := int(session.turn_report_for(reader).get("turn", 0))
	if turn <= 0 or turn > session.turns_played() or not _notes.has(turn):
		return out
	var state := session.state_for(reader)
	for fid in factions():
		if not _notes[turn].has(fid):
			continue
		var f: Faction = state.find_faction(fid) if state else null
		out.append({"faction": fid, "faction_name": f.faction_name if f else "The computer", "seat": _seats[fid],
			"level": _levels[fid], "temperament": temperament(fid), "notes": _notes[turn][fid].duplicate()})
	return out


## The computer's plan counters for `turn` (1-based), {faction id: AIPlayer.last_plan_stats()}.
func turn_stats(turn: int) -> Dictionary:
	return _stats.get(turn, {}).duplicate(true)
