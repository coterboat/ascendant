class_name GameSession
extends RefCounted
## Hotseat game flow for M1 (#7) and the win condition (#8). Pure rules code: no nodes, no scenes.
## The UI (handoff screen, turn report panel, battle report viewer, victory screen) drives this
## object; everything here is deterministic from the starting state, the seat order and the game
## seed, so a whole game can be replayed from record().
##
##   var session := GameSession.new(GameState.new(seed), ["kingdom", "beasts"], seed)
##
## Phases (phase()):
##   ORDERS     the current player (current_player()) queues orders with queue_move / queue_recruit /
##              queue_order and withdraws them with cancel_order. Orders are checked by OrderBook, so a
##              rejection carries the rules code's plain-language reason. Only the current player's
##              orders are visible (current_orders()); nothing returns another player's pending orders.
##   HANDOFF    after end_turn(): the UI hides the map and orders and shows handoff_text()
##              ("Pass the computer to player 2, who plays Thornmane Clans."). acknowledge_handoff()
##              (alias begin_turn()) starts that player's ORDERS phase.
##   GAME_OVER  a capital fell (VictoryCheck). victory() has the summary; every action is rejected.
##   INVALID    the session could not start; setup_errors() says why; every action is rejected.
##
## Turn cycle: seat 1 ORDERS -> end_turn -> HANDOFF -> seat 2 ORDERS -> ... -> the last seat's
## end_turn resolves the turn (TurnResolver.resolve with every seat's orders, the turn seed and the
## battle resolver) -> turn_report() holds the new events -> HANDOFF to seat 1, or GAME_OVER.
## Actions return "" when they worked, otherwise a plain-language reason to show the player.
##
## Turn seeds: turn_seed(game_seed, turn) = game_seed * 1000003 + turn, where `turn` is the state's
## current_turn before resolving (0 for the first turn). This is TurnResolver.seed_for_turn's formula,
## so when the game seed equals the state's seed_value both give the same seed. 64-bit overflow wraps,
## which is deterministic.
##
## Turn report: the events TurnResolver.resolve returned for the last resolved turn (each has "type",
## "phase", "provinces" to focus the map, "text", "codex"), plus, on the final turn, one "game_over"
## event in phase "victory" carrying the victory summary text.

enum Phase { ORDERS, HANDOFF, GAME_OVER, INVALID }

const PHASE_NAMES := ["orders", "handoff", "game_over", "invalid"]
## Report phases in display order: the resolver's phases, then the victory event.
const REPORT_PHASES := ["orders", "movement", "battles", "capture", "recruitment", "income", "victory"]
const BATTLE_TYPES := ["battle", "border_battle"]
## RulesCodex entries this flow links to (handoff screen, victory screen, final report).
const CODEX_KEYS := ["hotseat", "handoff", "victory", "simultaneous_capture"]

var _state: GameState
var _start_dict := {}
var _players: Array = []  # faction ids in seat order
var _game_seed: int = 0
var _battle_resolver: BattleResolver = null
var _phase: Phase = Phase.ORDERS
var _seat := 0  # index into _players: whose turn it is (ORDERS) or who is next (HANDOFF)
var _books := {}  # faction id -> OrderBook holding only that faction's orders
var _history: Array = []  # one record per resolved turn: {"turn", "seed", "orders"}
var _report: Array = []
var _report_turn := 0
var _battles := 0
var _victory := {}
var _setup_errors: Array = []
var _start_builds := {}  # faction id -> RulerRules.build_of at the start; {} in a game without rulers


func _init(state: GameState = null, players: Array = [], game_seed: int = 0, battle_resolver: BattleResolver = null) -> void:
	_game_seed = game_seed
	_battle_resolver = battle_resolver
	if state == null:
		_setup_errors.append("There is no game to play: the starting state is missing.")
	else:
		var copy_errors := []
		_state = state.deep_copy(copy_errors)
		if _state == null:
			_setup_errors.append_array(copy_errors)
	if _state != null:
		_check_players(players)
	if not _setup_errors.is_empty():
		_phase = Phase.INVALID
		return
	_players = players.duplicate()
	_start_dict = _state.to_dict()
	for f in _state.factions:
		if f.has_ruler():
			_start_builds[f.id] = RulerRules.build_of(_state, f.id)
	for fid in _players:
		_books[fid] = OrderBook.new()


## Seed for resolving `turn` (the state's current_turn before resolving) in a game with `game_seed`.
static func turn_seed(game_seed: int, turn: int) -> int:
	return game_seed * 1000003 + turn


# --- reading the session --------------------------------------------------------------------------

func phase() -> Phase:
	return _phase


func phase_name() -> String:
	return PHASE_NAMES[_phase]


func is_over() -> bool:
	return _phase == Phase.GAME_OVER


func setup_errors() -> Array:
	return _setup_errors.duplicate()


## Faction ids in seat order (seat 1 first).
func players() -> Array:
	return _players.duplicate()


## Faction id of the player whose turn it is (ORDERS) or who is next (HANDOFF). "" otherwise.
func current_player() -> String:
	if _phase == Phase.ORDERS or _phase == Phase.HANDOFF:
		return _players[_seat]
	return ""


## Display name of current_player()'s faction.
func current_player_name() -> String:
	var fid := current_player()
	return "" if fid.is_empty() else TurnResolver._faction_name(_state, fid)


## 1-based seat of current_player(), or 0.
func current_seat() -> int:
	return _seat + 1 if not current_player().is_empty() else 0


## The 1-based turn being ordered. After the game ends, the turn it ended on.
func turn_number() -> int:
	if _state == null:
		return 0
	return _report_turn if _phase == Phase.GAME_OVER else _state.current_turn + 1


## A copy of the current game state (the start-of-turn state while players give orders).
## The live state is never handed out, so the UI can't change it by accident.
func state() -> GameState:
	return _state.deep_copy() if _state != null else null


## The current player's queued orders, in the order given. Empty outside the ORDERS phase, so the
## handoff screen can never show them. There is deliberately no way to read another seat's orders.
func current_orders() -> Array:
	if _phase != Phase.ORDERS:
		return []
	return _books[current_player()].orders_for(current_player())


## Plain-language lines for current_orders(), for the orders list.
func current_order_texts() -> Array:
	var out := []
	for o in current_orders():
		out.append(describe_order(current_player(), o))
	return out


## One order in plain language, using display names only:
##   "Move the Aurel Crown army at Crownkeep (3 units, led by Knight Captain) to Westwatch."
##   "Recruit Spearmen at Crownkeep for 8 gold."
func describe_order(faction_id: String, order) -> String:
	if order is MoveOrder:
		var army := _state.find_army(order.army_id)
		var who := "the %s" % TurnResolver.army_label(_state, army) if army else "an army that no longer exists"
		return "Move %s to %s." % [who, TurnResolver._province_name(_state, order.to)]
	if order is RecruitOrder:
		var faction := _state.find_faction(faction_id)
		var ut: UnitType = TurnResolver.recruitable_type(faction, order.unit_type_id) if faction else null
		if ut == null:
			return "Recruit %s." % TurnResolver._unit_type_name(_state, order.unit_type_id)
		return "Recruit %s at %s for %d gold." % [ut.name, TurnResolver._province_name(_state, faction.capital), ut.cost]
	return "An order this game does not know."


## What the handoff screen shows. "" outside the HANDOFF phase.
func handoff_text() -> String:
	if _phase != Phase.HANDOFF:
		return ""
	var text := "Pass the computer to player %d, who plays %s." % [_seat + 1, current_player_name()]
	if _seat == 0 and _report_turn > 0:
		text = "Turn %d is resolved. %s The turn %d results are waiting." % [_report_turn, text, _report_turn]
	return text + " Continue only when nobody else can see the screen."


## {"seat", "faction", "faction_name", "text", "codex"} for the handoff screen, or {} outside HANDOFF.
func handoff_info() -> Dictionary:
	if _phase != Phase.HANDOFF:
		return {}
	return {"seat": _seat + 1, "faction": current_player(), "faction_name": current_player_name(),
		"text": handoff_text(), "codex": "handoff"}


## The last resolved turn's report: {"turn", "header", "events"}. Events are copies.
func turn_report() -> Dictionary:
	var header := "Turn %d results" % _report_turn if _report_turn > 0 else "No turns have been resolved yet."
	return {"turn": _report_turn, "header": header, "events": _report.duplicate(true)}


## Only the battle events of the last report (for opening the battle report viewer).
func battle_events() -> Array:
	return _report.filter(func(e): return BATTLE_TYPES.has(e.type)).duplicate(true)


## The victory summary (see VictoryCheck.summary), or {} while the game is running.
func victory() -> Dictionary:
	return _victory.duplicate(true)


func winner() -> String:
	return _victory.get("winner", "")


func turns_played() -> int:
	return _history.size()


func battles_fought() -> int:
	return _battles


## One JSON-safe record per resolved turn: {"turn": 1-based, "seed": int64 as a string,
## "orders": {faction id: [order dicts]}}.
func history() -> Array:
	return _history.duplicate(true)


## Each faction's ruler build at the start of the game (M2): {faction id: {"ruler", "ruler_name",
## "kept_power", "mandates", "mandate_names", "status", "generation"}}. {} in a game without rulers.
func builds() -> Dictionary:
	return _start_builds.duplicate(true)


## Everything replay() needs to rebuild this game: JSON-safe. A game with rulers also carries
## "builds" (see builds()) for reports; replay() doesn't need it, since builds live in "start_state".
func record() -> Dictionary:
	var rec := {"start_state": _start_dict.duplicate(true), "players": _players.duplicate(),
		"game_seed": Serial.int64_to_str(_game_seed), "history": history()}
	if not _start_builds.is_empty():
		rec["builds"] = builds()
	return rec


# --- actions --------------------------------------------------------------------------------------

## Queues an order for the current player. "" when accepted, otherwise why it was rejected.
func queue_order(order) -> String:
	var why := _not_ordering("give orders")
	if not why.is_empty():
		return why
	return _books[current_player()].submit(_state, current_player(), order)


func queue_move(army_id: String, to: String) -> String:
	return queue_order(MoveOrder.new(army_id, to))


func queue_recruit(unit_type_id: String) -> String:
	return queue_order(RecruitOrder.new(unit_type_id))


## Withdraws the current player's order at `index` (0-based, as in current_orders()).
func cancel_order(index: int) -> String:
	var why := _not_ordering("cancel orders")
	if not why.is_empty():
		return why
	var fid := current_player()
	var count: int = _books[fid].orders_for(fid).size()
	if index < 0 or index >= count:
		return "There is no order number %d to cancel. You have %d %s queued." % [index + 1, count,
			"order" if count == 1 else "orders"]
	_books[fid].remove(fid, index)
	return ""


## Ends the current player's turn: hands off to the next seat, or resolves the turn after the last.
func end_turn() -> String:
	var why := _not_ordering("end the turn")
	if not why.is_empty():
		return why
	if _seat < _players.size() - 1:
		_seat += 1
		_phase = Phase.HANDOFF
		return ""
	return _resolve_turn()


## The next player confirms they have the computer: their ORDERS phase starts.
func acknowledge_handoff() -> String:
	match _phase:
		Phase.HANDOFF:
			_phase = Phase.ORDERS
			return ""
		Phase.ORDERS:
			return "There is nothing to hand over: it is already player %d's turn (%s)." % [_seat + 1, current_player_name()]
	return _closed_reason("start a turn")


func begin_turn() -> String:
	return acknowledge_handoff()


# --- replay ---------------------------------------------------------------------------------------

## Rebuilds a game from record() (or the same data after a JSON round-trip) by resolving every turn
## again with its recorded orders and seed. Returns {"state": GameState or null, "events": the last
## turn's resolver events, "errors": plain-language problems}.
static func replay(game_record: Dictionary, battle_resolver: BattleResolver = null) -> Dictionary:
	var errors := []
	if not game_record.has("start_state"):
		return {"state": null, "events": [], "errors": ["This replay has no starting state."]}
	var state := GameState.from_dict(game_record.start_state, errors)
	if state == null:
		return {"state": null, "events": [], "errors": errors}
	var events: Array = []
	for entry in game_record.get("history", []):
		var orders := OrderBook.orders_from_dict(entry.get("orders", {}), errors)
		var result := TurnResolver.resolve(state, orders, Serial.to_int(entry.get("seed", 0)), battle_resolver)
		if result.new_state == null:
			errors.append_array(result.get("errors", []))
			return {"state": null, "events": [], "errors": errors}
		state = result.new_state
		events = result.events
	return {"state": state, "events": events, "errors": errors}


# --- internals ------------------------------------------------------------------------------------

func _check_players(players: Array) -> void:
	if players.size() < 2:
		_setup_errors.append("A hotseat game needs at least two players.")
	var seen := {}
	for i in players.size():
		var fid := str(players[i])
		var f := _state.find_faction(fid)
		if f == null:
			_setup_errors.append("Player %d is set to a faction that is not in this game." % (i + 1))
		elif seen.has(fid):
			_setup_errors.append("Two players are set to %s. Each faction can have only one player." % f.faction_name)
		seen[fid] = true


func _resolve_turn() -> String:
	var orders := {}
	var recorded := {}
	for fid in _players:
		orders[fid] = _books[fid].orders_for(fid)
		recorded[fid] = _books[fid].to_dict().get(fid, [])
	var turn := _state.current_turn
	var seed_value := turn_seed(_game_seed, turn)
	var result := TurnResolver.resolve(_state, orders, seed_value, _battle_resolver)
	if result.new_state == null:
		return "This turn could not be resolved: %s" % " ".join(result.get("errors", []))
	_state = result.new_state
	_history.append({"turn": turn + 1, "seed": Serial.int64_to_str(seed_value), "orders": recorded})
	var events: Array = result.events
	for e in events:
		if BATTLE_TYPES.has(e.type):
			_battles += 1
	_report_turn = turn + 1
	for fid in _players:
		_books[fid].clear()
	var check := VictoryCheck.check(_state, _players)
	if check.over:
		_victory = VictoryCheck.summary(_state, _players, check, _report_turn, _history.size(), _battles)
		events.append(_victory.event.duplicate(true))
		_phase = Phase.GAME_OVER
	else:
		_seat = 0
		_phase = Phase.HANDOFF
	_report = events
	return ""


## "" in the ORDERS phase, otherwise why `action` isn't possible now.
func _not_ordering(action: String) -> String:
	if _phase == Phase.ORDERS:
		return ""
	if _phase == Phase.HANDOFF:
		return "You can't %s right now: the computer is being passed to player %d (%s), who needs to start their turn first." % [
			action, _seat + 1, current_player_name()]
	return _closed_reason(action)


func _closed_reason(action: String) -> String:
	if _phase == Phase.GAME_OVER:
		return "The game is over, so you can't %s. Start a new game to play again." % action
	return "This game could not start, so you can't %s. %s" % [action, " ".join(_setup_errors)]
