extends RefCounted
## The fog snapshot probe of the balance check (M5-11, #122; design/M5_MAGIC_FOG.md §13.2 band G13, §2.7, §10.1).
## On every PROBE_EVERY-th turn of a fog game, for each seat, it runs §2.7's snapshot test on the live game: everything
## hidden from the seat is changed (tests/fog_test_kit.gd's perturb_hidden, with the seat's memory and intel held fixed,
## plus the magic a rival keeps out of sight: its enchantment counter, its wards, curses and sights in veiled provinces,
## and its Bastion list), and then
##   * the seat's view must be byte-identical, view notes included;
##   * the computer, handed that view (a fresh brain, the seat's dice as they stand), must give the same orders as from
##     the real view, and every one of them must be legal on the true state and on the changed one.
## A mismatch is a leak: the view (or the brain) read something it should not. Pure: no nodes, no scenes.

const Kit := preload("res://tests/fog_test_kit.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const PROBE_EVERY := 10


static func new_log() -> Dictionary:
	return {"probes": 0, "views": 0, "view_mismatches": 0, "plans": 0, "plan_mismatches": 0, "illegal": 0, "skipped": 0, "first": ""}


## Whether the 1-based `turn` is a probe turn.
static func due(turn: int) -> bool:
	return turn > 0 and turn % PROBE_EVERY == 0


## Runs the probe for every seat at the start of `turn`. `rngs` are the seats' policy dice, `forced` their forced sides of
## the fork. Counters and the first failure go into `log` (new_log).
static func check(session: GameSession, seats: Array, game_seed: int, policy_names: Array, forced: Array, rngs: Array, turn: int, log: Dictionary) -> void:
	log.probes += 1
	for seat in seats.size():
		var fid := String(seats[seat])
		var truth := session.state()
		var base_view := session.view_state(fid)
		var memory := session.memory(fid)
		var intel := session.intel(fid)
		var p := Kit.perturb_hidden(truth, fid, hash([game_seed, turn, fid, "probe"]))
		if p.state == null or not (p.errors as Array).is_empty():
			log.skipped += 1
			continue
		hide_magic(p.state, fid)
		var other := FogRules.view_state(p.state, fid, memory, intel)
		var what := "turn %d, %s" % [turn, fid]
		log.views += 1
		if JSON.stringify(other.to_dict()) != JSON.stringify(base_view.to_dict()):
			log.view_mismatches += 1
			_first(log, "%s: the view changed when only hidden facts did" % what)
			continue
		var name := String(policy_names[seat])
		if not (name == "ai" or name == "ai_easy"):
			continue
		var forced_side := String(forced[seat]) if seat < forced.size() and forced[seat] != null else ""
		var orders1 := _plan(name, game_seed, seat, forced_side, base_view, fid, rngs[seat])
		var orders2 := _plan(name, game_seed, seat, forced_side, other, fid, rngs[seat])
		log.plans += 1
		if JSON.stringify(orders1.map(func(o): return o.to_dict())) != JSON.stringify(orders2.map(func(o): return o.to_dict())):
			log.plan_mismatches += 1
			_first(log, "%s: the computer gave other orders from an identical view" % what)
		for pair in [[orders1, truth], [orders2, p.state]]:
			var taken := []
			for o in pair[0]:
				var why: Dictionary = OrderBook.check_order(pair[1], fid, o, taken)
				if why.is_empty():
					taken.append(o)
				else:
					log.illegal += 1
					_first(log, "%s: the computer's order '%s' is illegal on the true state: %s" % [what, o.describe(), String(why.get("reason", ""))])


## One plan of a fresh brain on `view`, with a copy of the seat's dice.
static func _plan(name: String, game_seed: int, seat: int, forced_side: String, view: GameState, fid: String, rng: SeededRNG) -> Array:
	var policy = Policies.make(name)
	policy.configure(game_seed, seat, forced_side)
	return policy.orders(view.deep_copy(), fid, SeededRNG.from_dict(rng.to_dict()))


## Changes what a rival's magic keeps out of the seat's sight in the (already perturbed) true state `s`: its enchantment
## counter, its Bastion list, and its wards, curses and sights on provinces `viewer` cannot see at all.
static func hide_magic(s: GameState, viewer: String) -> void:
	for a in s.armies:  # the Free Holds garrisons' ids are public ("free-<province>"), which the M5-1 kit does not know
		if a.owner == IndependentData.FACTION_ID:
			a.id = IndependentData.army_id(a.location)
	if not s.magic:
		return
	var sight := FogRules.sight(s, viewer)
	var rival_count := 0
	for f in s.factions:
		if f.id == viewer:
			continue
		rival_count += 1
		f.enchant_counter = int(f.enchant_counter) + 7 + rival_count
		f.bastions = []
	var kept := []
	for e in s.enchantments:
		var hidden := String(e.faction) != viewer and ["ward", "curse", "sight"].has(String(e.kind)) \
			and String(sight.get(String(e.province), FogRules.VEILED)) == FogRules.VEILED
		if not hidden:
			kept.append(e)
	s.enchantments = kept


static func _first(log: Dictionary, text: String) -> void:
	if String(log.first).is_empty():
		log.first = text
