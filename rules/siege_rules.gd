class_name SiegeRules
## Forts and sieges (M3c, design/M3C_SIEGES.md §2, §3, §5, §12). Pure functions over GameState and the data in
## data/forts.gd: no nodes, no scenes, and no randomness: no siege rule draws a random number (§1.1, §3.9). This
## is the single source the resolver, forecasts, breakdowns, the AI and every screen read, so a number can never
## disagree with itself. Nothing here does anything in a game without sieges (GameState.sieges false).
##
## Levels and walls:    level_data, level_name, level_word, walls_max, walls_defense, wall_steps, damage_look,
##                      recruit_limit, may_recruit, repair_amount
## Who is where:        garrison, outside, besiegers, owner_armies, troops, engines_of, besieging_faction,
##                      is_besieged, siege_stands, is_cut_off, cut_off_info, turn_of_siege
## Siege damage:        siege_damage (with parts), siege_damage_at, engines_counted, turns_to_breach, breach_turn
## Checks:              check_fortify, check_siege_order, check_recruit_at, recruit_place, engine_type, is_engine
## The battles phase:   next_battle (§3.9, every crossing of orders), sallying_armies, storming_factions, called_off,
##                      siege_block
## The sieges phase:    siege_step, repair_step, works_step (TurnResolver._sieges_phase calls them in this order)
## Texts:               walls_text, damage_text, fort_phrase, in_turns_text and the event sentences
## validate(state, errors), called by GameState.validate.
##
## Turns are counted as players count them (1-based). While turn t resolves, `turn` is t = current_turn + 1, and
## a fort is cut off when 0 < siege_since < t, the siege still stands, and the besiegers have at least half the
## garrison's troops, rounded up (§3.3). Recruiting reads that at the start of the turn; income after battles.

const STORM := "storm"
const SALLY := "sally"
## The kinds of battle at a fort (§3.9): outside the walls, a storm of the walls, through the breach.
const OPEN := "open"
const BREACH := "breach"
## The looks the board draws (§10.1): one per step of WALL_STEP lost, and the breach at 0.
const LOOKS := ["intact", "damaged", "battered", "breached"]


# --- levels and walls ------------------------------------------------------------------------------

static func has_sieges(state: GameState) -> bool:
	return state != null and state.sieges


static func level_data(level: int) -> Dictionary:
	return FortData.level(level)


## "Palisade", "Keep", "Citadel" ("" for no fort).
static func level_name(level: int) -> String:
	return String(level_data(level).name) if level > 0 else ""


## "palisade", "keep", "citadel", for running text.
static func level_word(level: int) -> String:
	return level_name(level).to_lower()


## "a palisade", "a keep", "a citadel".
static func fort_phrase(level: int) -> String:
	return "a %s" % level_word(level)


static func walls_max(level: int) -> int:
	return int(level_data(level).walls)


## Steps of FortData.WALL_STEP wall strength standing, rounded up: 9 -> 3, 5 -> 2, 1 -> 1, 0 -> 0.
static func wall_steps(walls: int) -> int:
	return ceili(float(maxi(walls, 0)) / FortData.WALL_STEP)


## The defense every fighter of a stormed garrison gets (§4.1): WALLS_DEFENSE_PER_STEP for every step standing.
static func walls_defense(walls: int) -> int:
	return FortData.WALLS_DEFENSE_PER_STEP * wall_steps(walls)


## The board's damage look (§10.1): it changes exactly where the storm defense does. "intact" while every step
## stands, "damaged" with one lost, "battered" with two or more lost, "breached" at 0.
static func damage_look(level: int, walls: int) -> String:
	if level <= 0:
		return ""
	if walls <= 0:
		return LOOKS[3]
	var lost := wall_steps(walls_max(level)) - wall_steps(walls)
	return LOOKS[mini(lost, 2)]


static func recruit_limit(level: int) -> int:
	return int(level_data(level).recruits)


## Whether a fort of `level` may recruit `ut`: troops at any fort, commanders and engines at a keep or citadel.
static func may_recruit(level: int, ut: UnitType) -> bool:
	if level <= 0 or ut == null:
		return false
	if is_engine(ut):
		return bool(level_data(level).engines)
	if ut.is_commander:
		return bool(level_data(level).commanders)
	return true


static func repair_amount(level: int) -> int:
	return int(level_data(level).repair)


# --- who is where ----------------------------------------------------------------------------------

## The fort owner's armies in `province_id` that didn't move this turn (`moved`: army ids that left or arrived),
## in id order: the garrison, inside the walls (§3.1). At the start of a turn it is every army of the owner there.
static func garrison(state: GameState, province_id: String, moved: Dictionary = {}) -> Array:
	var p := state.find_province(province_id)
	var out := []
	if p == null or p.owner.is_empty():
		return out
	for a in _sorted_armies(state):
		if a.location == province_id and a.owner == p.owner and not moved.has(a.id):
			out.append(a)
	return out


## Everyone else in the province (§3.1): other factions' armies, and the owner's armies that arrived this turn.
static func outside(state: GameState, province_id: String, moved: Dictionary = {}) -> Array:
	var inside := garrison(state, province_id, moved)
	var out := []
	for a in _sorted_armies(state):
		if a.location == province_id and not inside.has(a):
			out.append(a)
	return out


## The other factions' armies in the province, in id order: the besiegers when a garrison is inside.
static func besiegers(state: GameState, province_id: String) -> Array:
	var p := state.find_province(province_id)
	var out := []
	if p == null:
		return out
	for a in _sorted_armies(state):
		if a.location == province_id and a.owner != p.owner:
			out.append(a)
	return out


## Every army of the owner in the province, moved or not.
static func owner_armies(state: GameState, province_id: String) -> Array:
	var p := state.find_province(province_id)
	var out := []
	if p == null or p.owner.is_empty():
		return out
	for a in _sorted_armies(state):
		if a.location == province_id and a.owner == p.owner:
			out.append(a)
	return out


## Troops in `armies`: every regular unit (commanders, rulers and engines are not troops).
static func troops(armies: Array) -> int:
	var n := 0
	for a in armies:
		n += a.units.size()
	return n


static func engines_of(armies: Array) -> int:
	var n := 0
	for a in armies:
		n += a.engines
	return n


## The faction besieging `province_id` (the first other faction there, by id), or "".
static func besieging_faction(state: GameState, province_id: String) -> String:
	var fids := []
	for a in besiegers(state, province_id):
		if not fids.has(a.owner):
			fids.append(a.owner)
	fids.sort()
	return String(fids[0]) if not fids.is_empty() else ""


## A siege is recorded at `province_id` (siege_since set by the sieges phase).
static func is_besieged(state: GameState, province_id: String) -> bool:
	var p := state.find_province(province_id) if has_sieges(state) else null
	return p != null and p.fort_level > 0 and p.siege_since > 0


## The owner's armies and another faction's are both in the province now.
static func siege_stands(state: GameState, province_id: String) -> bool:
	return not owner_armies(state, province_id).is_empty() and not besiegers(state, province_id).is_empty()


## The cut-off (§3.3): {"cut_off", "since" (the siege's first turn), "besieger", "besieger_troops",
## "garrison_troops", "need" (half the garrison's troops, rounded up), "pickets" (a siege that is too small),
## "turn"}. `turn` defaults to the turn being ordered or resolved.
static func cut_off_info(state: GameState, province_id: String, turn: int = -1) -> Dictionary:
	var t := turn if turn > 0 else state.current_turn + 1
	var out := {"cut_off": false, "since": 0, "besieger": "", "besieger_troops": 0, "garrison_troops": 0, "need": 0,
		"pickets": false, "turn": t}
	if not is_besieged(state, province_id):
		return out
	var p := state.find_province(province_id)
	out.since = p.siege_since
	if not siege_stands(state, province_id):
		return out
	var outside_troops := troops(besiegers(state, province_id))
	var inside_troops := troops(owner_armies(state, province_id))
	var need := ceili(float(inside_troops) / 2.0)
	out.besieger = besieging_faction(state, province_id)
	out.besieger_troops = outside_troops
	out.garrison_troops = inside_troops
	out.need = need
	out.pickets = outside_troops < need
	out.cut_off = p.siege_since < t and not out.pickets
	return out


static func is_cut_off(state: GameState, province_id: String, turn: int = -1) -> bool:
	return bool(cut_off_info(state, province_id, turn).cut_off)


## Which turn of its siege `turn` is (1 for the turn it began), or 0 with no siege.
static func turn_of_siege(state: GameState, province_id: String, turn: int = -1) -> int:
	if not is_besieged(state, province_id):
		return 0
	var t := turn if turn > 0 else state.current_turn + 1
	return t - state.find_province(province_id).siege_since + 1


# --- siege damage ----------------------------------------------------------------------------------

## Engines that count in a siege (§3.3): at most FortData.SIEGE.engines_max, and at most one for every
## troops_per_engine troops.
static func engines_counted(troop_count: int, engine_count: int) -> int:
	var s := FortData.SIEGE
	return maxi(0, mini(mini(engine_count, int(s.engines_max)), troop_count / int(s.troops_per_engine)))


## Siege damage a turn from `troop_count` troops and `engine_count` engines (§3.3): {"total", "parts": [{"key",
## "name", "value", "note"}] (they add up to the total), "troops", "engines", "engines_counted", "capped"}.
## `engine_name` names the engines in the parts ("Wallbreakers"); "engines" without it.
static func siege_damage(troop_count: int, engine_count: int, engine_name: String = "") -> Dictionary:
	var s := FortData.SIEGE
	var camp := int(s.camp)
	var from_troops := mini(int(s.troops_max), troop_count / int(s.per_troops))
	var counted := engines_counted(troop_count, engine_count)
	var from_engines := counted * int(s.engine)
	var raw := camp + from_troops + from_engines
	var total := mini(raw, int(s.max))
	var engines_word := engine_name if not engine_name.is_empty() else ("engine" if engine_count == 1 else "engines")
	var parts := [
		{"key": "camp", "name": "Siege camp", "value": camp, "note": "every siege drops the walls by at least %d" % camp},
		{"key": "troops", "name": "%d %s" % [troop_count, "troop" if troop_count == 1 else "troops"], "value": from_troops,
			"note": "%d for every %d troops, rounded down, at most %d" % [int(s.engine), int(s.per_troops), int(s.troops_max)]},
	]
	if engine_count > 0:
		parts.append({"key": "engines", "name": "%d %s" % [engine_count, engines_word], "value": from_engines,
			"note": "%d each, at most %d, and at most 1 for every %d troops: %d of them count" % [int(s.engine),
				int(s.engines_max), int(s.troops_per_engine), counted]})
	if raw > total:
		parts.append({"key": "cap", "name": "At most %d a turn" % int(s.max), "value": total - raw,
			"note": "siege damage is never more than %d a turn" % int(s.max)})
	return {"total": total, "parts": parts, "troops": troop_count, "engines": engine_count, "engines_counted": counted,
		"capped": raw > total}


## Siege damage at `province_id` from the armies outside it now plus `extra` armies (a forecast's arrivals).
static func siege_damage_at(state: GameState, province_id: String, extra: Array = []) -> Dictionary:
	var armies := besiegers(state, province_id)
	for a in extra:
		if not armies.has(a):
			armies.append(a)
	return siege_damage(troops(armies), engines_of(armies), engine_plural(_faction_of(armies)))


## Turns of siege until walls of `walls` reach 0 at `damage` a turn, the turn they start counting as 1; 0 when
## they are already 0, -1 when nothing drops them.
static func turns_to_breach(walls: int, damage: int) -> int:
	if walls <= 0:
		return 0
	if damage <= 0:
		return -1
	return ceili(float(walls) / damage)


## The turn at whose end the walls reach 0 when the siege drops them by `damage` from `turn` on (that turn
## included), or -1 when nothing drops them. Forecast equals result: when no army enters or leaves the
## province, the sieges phase of that turn breaches them.
static func breach_turn(walls: int, damage: int, turn: int) -> int:
	var n := turns_to_breach(walls, damage)
	if n < 0:
		return -1
	return turn + n - 1 if n > 0 else turn - 1


# --- engines ---------------------------------------------------------------------------------------

## The engine `faction_id` recruits, as a UnitType for the recruit checks and prices (never put in an army).
static func engine_type(faction_id: String) -> UnitType:
	var e := FortData.engine_for(faction_id)
	if e.is_empty():
		return null
	var ut := UnitType.new()
	ut.id = String(e.id)
	ut.name = String(e.name)
	ut.hp = 0
	ut.attack = 0
	ut.defense = 0
	ut.morale = 0
	ut.cost = int(e.cost)
	ut.trait_id = FortData.ENGINE_TRAIT
	ut.trait_description = String(e.text)
	return ut


static func is_engine(ut: UnitType) -> bool:
	return ut != null and ut.trait_id == FortData.ENGINE_TRAIT and not FortData.engine_by_id(ut.id).is_empty()


## The codex entry of the engine with this id ("unit_siege_ram"), or the Siege Engine trait's.
static func engine_codex(engine_id: String) -> String:
	return "unit_" + engine_id if not FortData.engine_by_id(engine_id).is_empty() else "trait_siege_engine"


## "Siege Rams", "Wallbreakers" ("engines" for a faction without one).
static func engine_plural(faction_id: String) -> String:
	var e := FortData.engine_for(faction_id)
	return String(e.plural) if not e.is_empty() else "engines"


## "1 Siege Ram", "2 Siege Rams".
static func engines_text(faction_id: String, n: int) -> String:
	var e := FortData.engine_for(faction_id)
	if e.is_empty():
		return "%d %s" % [n, "engine" if n == 1 else "engines"]
	return "%d %s" % [n, String(e.name) if n == 1 else String(e.plural)]


## Whether `army` can carry another engine: it has a fighter (a unit or a commander), isn't a ruler's army and
## carries fewer than FortData.ARMY_ENGINES_MAX.
static func can_carry(army: Army) -> bool:
	return army != null and army.ruler == null and (not army.units.is_empty() or army.commander != null) \
		and army.engines < FortData.ARMY_ENGINES_MAX


# --- checks ----------------------------------------------------------------------------------------

## Where a recruit with `at` appears (§2.3): the capital for "" (and, with sieges, for the capital's own id),
## the province for a fort's id. "ruler" is TurnResolver.muster_province's business.
static func recruit_place(state: GameState, faction: Faction, at: String) -> String:
	if at.is_empty() or at == RecruitOrder.AT_RULER:
		return faction.capital if faction != null else ""
	return at


## A recruit of `ut` at the fort in `place` (§2.3), with sieges on. `count_before` is how many recruits that
## faction already ordered there this turn; `start` the state the turn started from (`state` itself when
## null: every check made before the turn resolves). {} when legal, otherwise {"code", "reason"}. The capital's
## "is it still yours" check stays TurnResolver's (capital_not_held). Gold is the caller's.
static func check_recruit_at(state: GameState, faction_id: String, place: String, ut: UnitType, count_before: int,
		start: GameState = null) -> Dictionary:
	var st: GameState = start if start != null else state
	var sp := st.find_province(place)
	var now := state.find_province(place)
	if sp == null or now == null:
		return _reject("unknown_place", "Recruits are made at a fort you own: your capital, or another fort you hold.")
	var turn := state.current_turn + 1
	if sp.fort_level <= 0:
		return _reject("no_fort_there", "%s has no fort. Recruits are made at a fort you own: your capital, or another fort you hold." % sp.name)
	if sp.owner != faction_id or now.owner != faction_id:
		return _reject("fort_not_held", "%s is not yours, so nobody of yours can recruit there; no gold is spent." % sp.name)
	if sp.owned_since > 0 and sp.owned_since + FortData.CAPTURE_WAIT >= turn:
		return _reject("fort_just_taken", "You took %s on turn %d: it can take recruits from turn %d." % [sp.name, sp.owned_since,
			sp.owned_since + FortData.CAPTURE_WAIT + 1])
	var cut := cut_off_info(st, place, turn)
	if bool(cut.cut_off):
		return _reject("fort_cut_off", "%s is cut off by the %s siege: nobody can recruit there this turn, even if you lift the siege." % [
			sp.name, RulerRules._possessive(_faction_name(st, String(cut.besieger)))])
	if not may_recruit(sp.fort_level, ut):
		var what := "%s need" % engine_plural(faction_id) if is_engine(ut) else "Commanders need"
		return _reject("fort_level_too_low", "%s is %s: it recruits troops only. %s a keep or a citadel." % [sp.name,
			fort_phrase(sp.fort_level), what])
	var limit := recruit_limit(sp.fort_level)
	if count_before >= limit:
		return _reject("fort_full", "%s has taken %d of its %d recruits this turn (%s)." % [sp.name, count_before, limit,
			level_word(sp.fort_level)])
	return {}


## A Fortify order for `province_id` (§2.4): {} when legal, otherwise {"code", "reason"}. Read against `start`
## (the start of the turn; `state` when null), except that the province must still be the faction's in `state`
## (after this turn's capture). `given` is how many Fortify orders that faction already gave this turn. Gold is
## checked when it is paid (TurnResolver.price_recruits).
static func check_fortify(state: GameState, faction_id: String, province_id: String, start: GameState = null, given: int = 0) -> Dictionary:
	if not has_sieges(state):
		return _reject("no_sieges", "This game is played without forts and sieges, so nobody builds forts. Tick Forts & sieges on the new game screen to play with them.")
	var st: GameState = start if start != null else state
	var p := st.find_province(province_id)
	if p == null:
		return _reject("unknown_province", "That is not a province on the map.")
	if p.owner != faction_id:
		return _reject("fortify_not_owned", "You can build a fort only in a province you owned at the start of the turn, and %s is not yours." % p.name)
	if p.is_capital:
		return _reject("fortify_capital", "%s is a capital, and capitals are already citadels, the strongest fort." % p.name)
	if p.fort_level >= FortData.MAX_BUILT:
		return _reject("fortify_max", "%s is already %s: a keep is the most a fort outside a capital can be." % [p.name, fort_phrase(p.fort_level)])
	if not besiegers(st, province_id).is_empty():
		var why := "%s is besieged, and no work starts while an enemy army stands there." % p.name if is_besieged(st, province_id) \
			else "An enemy army stands in %s, and no work starts while it is there." % p.name
		return _reject("fortify_enemy_present", why)
	var site := site_of(st, faction_id)
	if not site.is_empty():
		var sp := st.find_province(String(site.province))
		var to := int(site.works.to)
		return _reject("fortify_one_at_a_time", "You are already building %s at %s (%d of %d turns of work done). You can build one fort at a time." % [
			fort_phrase(to), sp.name, int(level_data(to).turns) - int(site.works.left), int(level_data(to).turns)])
	if given > 0:
		return _reject("fortify_second", "You already gave a Fortify order this turn. You can build one fort at a time.")
	var now := state.find_province(province_id)
	if now == null or now.owner != faction_id:
		return _reject("fortify_lost", "You lost %s in this turn's battles, so the fort was not started; no gold is spent." % p.name)
	return {}


## The level a Fortify order at `province_id` builds (the next one), and what it costs.
static func fortify_level(state: GameState, province_id: String) -> int:
	var p := state.find_province(province_id)
	return mini((p.fort_level if p != null else 0) + 1, FortData.MAX_BUILT)


static func fortify_cost(state: GameState, province_id: String) -> int:
	return int(level_data(fortify_level(state, province_id)).cost)


## `faction_id`'s construction site: {"province", "works"}, or {} when it builds nothing.
static func site_of(state: GameState, faction_id: String) -> Dictionary:
	for p in _sorted_provinces(state):
		if not p.works.is_empty() and String(p.works.get("faction", "")) == faction_id:
			return {"province": p.id, "works": p.works}
	return {}


## A storm or sally order (§3.4, §3.5): {} when legal, otherwise {"code", "reason"}. Checked against `state`
## (the start of the turn), `moves` (every valid move order that faction gives this turn, wherever it comes in
## its list) and `given` (the siege orders of that faction already accepted).
static func check_siege_order(state: GameState, faction_id: String, order, moves: Array, given: Array = []) -> Dictionary:
	if not has_sieges(state):
		return _reject("no_sieges", "This game is played without forts and sieges, so there is nothing to storm or sally from.")
	if not (order is SiegeOrder):
		return _reject("unknown_order", "That is not an order this game knows.")
	if order.action == STORM:
		return _check_storm(state, faction_id, order, moves, given)
	if order.action == SALLY:
		return _check_sally(state, faction_id, order, moves, given)
	return _reject("unknown_siege_action", "A siege order either storms a fort or sallies out of one.")


static func _check_storm(state: GameState, fid: String, order: SiegeOrder, moves: Array, given: Array) -> Dictionary:
	var p := state.find_province(order.province)
	if p == null:
		return _reject("unknown_province", "That is not a province on the map.")
	if p.fort_level <= 0:
		return _reject("storm_no_fort", "%s has no fort, so there are no walls to storm. An army that moves in fights any enemy army there." % p.name)
	if p.owner == fid:
		return _reject("storm_own_fort", "%s is your own fort, and nobody storms their own walls. To fight the siege lines outside, sally out." % p.name)
	if p.walls <= 0:
		return _reject("storm_walls_down", "%s's walls are down: the battle there comes on its own." % p.name)
	# M5-1 (fog of war, design/M5_MAGIC_FOG.md §2.10): your own armies are checked before the garrison, so a storm
	# with no army of yours near never says whether anyone is inside: you see a fort's garrison only from there or next door.
	var here := false
	for a in state.armies:
		if a.owner == fid and a.location == p.id:
			here = true
	for m in moves:
		if m.to == p.id and state.find_army(m.army_id) != null:
			here = true
	if not here:
		return _reject("storm_no_army", "You have no army at %s and no move into it this turn, so nobody would storm. Move an army in and storm with it, or storm with the armies already besieging it." % p.name)
	if p.owner.is_empty() or garrison(state, p.id).is_empty():
		return _reject("storm_empty_fort", "Nobody is inside the walls of %s, so there is nothing to storm: an army that walks in takes it." % p.name)
	for o in given:
		if o is SiegeOrder and o.action == STORM and o.province == p.id:
			return _reject("storm_twice", "You already ordered a storm of %s this turn. A storm is ordered once for each fort, and every army of yours there takes part." % p.name)
	return {}


static func _check_sally(state: GameState, fid: String, order: SiegeOrder, moves: Array, given: Array) -> Dictionary:
	var army := state.find_army(order.army_id)
	if army == null:
		return _reject("unknown_army", "There is no such army on the map. It may have been destroyed.")
	if army.owner != fid:
		return _reject("not_your_army", "That army is not yours, so it can't sally.")
	var label := TurnResolver._army_name(state, army, true)  # its name for life, as the map and the report call it
	var p := state.find_province(army.location)
	if p == null or p.fort_level <= 0 or p.owner != fid:
		return _reject("sally_not_in_fort", "%s is not inside a fort of yours, so it can't sally. A sally comes out of your own besieged fort." % label)
	if not is_besieged(state, p.id):
		return _reject("sally_not_besieged", "%s is not besieged, so there is nobody outside its walls to sally against." % p.name)
	if p.walls <= 0:
		return _reject("sally_walls_down", "%s's walls are down: the battle there comes on its own." % p.name)
	for m in moves:
		if m.army_id == army.id:
			return _reject("sally_and_move", "%s has a move order this turn. Moving out is leaving the fort, not sallying: cancel the move to sally." % label)
	for o in given:
		if o is SiegeOrder and o.action == SALLY and o.army_id == army.id:
			return _reject("sally_twice", "%s already sallies this turn." % label)
	if not order.with_army.is_empty():
		var relief := state.find_army(order.with_army)
		var coming := false
		for m in moves:
			if relief != null and m.army_id == relief.id and m.to == p.id:
				coming = true
		if relief == null or relief.owner != fid or not coming:
			return _reject("sally_relief_missing", "That sally goes out with a relief army, but no army of yours is moving into %s this turn, so the garrison would stay inside." % p.name)
	return {}


# --- the battles phase (§3.9) ----------------------------------------------------------------------

## The next battle at a fort in a game with sieges (§3.9), or {} when there is none. TurnResolver._fort_battles asks
## again after each battle, on the armies still standing, because whether a storm follows depends on who won the
## battle outside the walls. `moved` holds the army ids that moved this turn; `siege_orders` the turn's recorded
## storms and sallies ({"storms": {province id: {faction id: true}}, "sallies": {army id: {"faction", "with",
## "from"}}}); `fought` the kinds of the battles this fort has already had this turn, in order.
## Returns {"kind": "open" | "storm" | "breach", "why" (§3.9's last column), "sides": {faction id: [armies]},
## "defender" (the owner in a storm, "" otherwise), "from_inside": [army ids], "siege": the battle's siege block
## (§4.4, siege_block)}.
##
## The rule: at a fort the only defender is a garrison being stormed. Every other battle there is in the open and
## nobody defends, but fighters coming from inside the walls (a sally, or the garrison at the breach) get cover.
## Inside a province the open battle outside the walls comes first (when two or more factions are outside,
## counting sallying armies as their owner's), then the storm (when one was ordered and stormers and garrison
## armies are still there). At a breached fort the garrison and the enemy fight once, through the breach.
static func next_battle(state: GameState, province_id: String, moved: Dictionary, siege_orders: Dictionary, fought: Array = []) -> Dictionary:
	var p := state.find_province(province_id)
	if p == null or p.fort_level <= 0 or fought.has(STORM) or fought.has(BREACH):
		return {}
	var by_faction := _armies_by_faction(state, province_id)
	if by_faction.size() < 2:
		return {}
	var owner := p.owner
	var inside := garrison(state, province_id, moved)
	var relief := []
	var enemies := []
	for a in _sorted_armies(state):
		if a.location != province_id:
			continue
		if a.owner == owner and moved.has(a.id):
			relief.append(a)
		elif a.owner != owner:
			enemies.append(a)
	var enemy_fids := _factions_of(enemies)
	# Rows 16 and 17: through the breach, on its own, in the open; a relief fights beside the garrison.
	if p.walls <= 0 and not inside.is_empty() and not enemies.is_empty():
		if not fought.is_empty():
			return {}
		return _plan(state, p, BREACH, BREACH, inside + relief, enemies, "", inside)
	# Rows 11 and 15 (an empty fort): whoever arrives meets in the open; nobody is inside.
	if inside.is_empty():
		if not fought.is_empty() or _factions_of(relief + enemies).size() < 2:
			return {}
		return _plan(state, p, OPEN, "empty", relief, enemies, "", [])
	var sallying := sallying_armies(state, province_id, moved, siege_orders)
	var stormers := storming_factions(state, province_id, siege_orders)
	# The open battle outside the walls (rows 3-8, 12, 15): at most one, before any storm.
	if fought.is_empty() and not enemies.is_empty() and (not relief.is_empty() or not sallying.is_empty() or enemy_fids.size() > 1):
		var why := "sally"
		if enemy_fids.size() > 1:
			why = "rivals"
		elif not relief.is_empty() and not sallying.is_empty():
			why = "relief_sally"
		elif not relief.is_empty():
			why = "relief"
		elif not stormers.is_empty():
			why = "gate"
		return _plan(state, p, OPEN, why, relief + sallying, enemies, "", sallying)
	# The storm (rows 2, 4, 7, 8, 12, 13): every army of the storming faction there against the armies that stayed
	# inside. Sallying armies are outside the walls this turn, so a storm never meets them.
	var staying := inside.filter(func(a): return not sallying.has(a))
	if stormers.is_empty() or staying.is_empty():
		return {}
	var fid := String(stormers[0])
	var attackers := enemies.filter(func(a): return a.owner == fid)
	return _plan(state, p, STORM, STORM, staying, attackers, owner, staying)


## The garrison armies of `province_id` that come out this turn (§3.4, §3.6): those with a sally order, except a
## sally tied to a relief army that isn't outside the walls when the battles start (row 18).
static func sallying_armies(state: GameState, province_id: String, moved: Dictionary, siege_orders: Dictionary) -> Array:
	var sallies: Dictionary = siege_orders.get("sallies", {})
	var out := []
	for a in garrison(state, province_id, moved):
		if not sallies.has(a.id):
			continue
		var tie := String(sallies[a.id].get("with", ""))
		if tie.is_empty() or _relief_outside(state, province_id, moved, tie):
			out.append(a)
	return out


## The factions that ordered a storm of `province_id` and still have an army there, in id order.
static func storming_factions(state: GameState, province_id: String, siege_orders: Dictionary) -> Array:
	var p := state.find_province(province_id)
	var out := []
	var storms: Dictionary = siege_orders.get("storms", {}).get(province_id, {})
	for fid in storms:
		if String(fid) == p.owner:
			continue
		for a in state.armies:
			if a.owner == String(fid) and a.location == province_id:
				out.append(String(fid))
				break
	out.sort()
	return out


## The orders at `province_id` that come to nothing when the battles start (§3.5, §3.6, row 9 of §3.9), for the
## battles phase's report lines: [{"type": "storm_called_off" | "sally_called_off" | "sally_found_nothing",
## "faction", "armies", "why", "text", "codex"}], storms first, then sallies by army id.
static func called_off(state: GameState, province_id: String, moved: Dictionary, siege_orders: Dictionary) -> Array:
	var p := state.find_province(province_id)
	var out := []
	if p == null or p.fort_level <= 0:
		return out
	var inside := garrison(state, province_id, moved)
	var storms: Dictionary = siege_orders.get("storms", {}).get(province_id, {})
	var fids: Array = storms.keys()
	fids.sort()
	for fid in fids:
		if String(fid) == p.owner:
			continue
		var name := _faction_name(state, String(fid))
		var here := state.armies.filter(func(a): return a.owner == String(fid) and a.location == province_id)
		if here.is_empty():
			out.append({"type": "storm_called_off", "faction": String(fid), "armies": [], "why": "no_army",
				"text": "The %s storm of %s was called off: none of their armies stood there after the march. It cost nothing." % [
					RulerRules._possessive(name), p.name], "codex": "storm"})
		elif inside.is_empty():
			out.append({"type": "storm_called_off", "faction": String(fid), "armies": here.map(func(a): return a.id), "why": "no_garrison",
				"text": "The %s storm of %s was called off: nobody was left inside the walls. It cost nothing." % [
					RulerRules._possessive(name), p.name], "codex": "storm"})
	var sallies: Dictionary = siege_orders.get("sallies", {})
	var outside_enemy := false
	for a in state.armies:
		if a.location == province_id and a.owner != p.owner:
			outside_enemy = true
	var found_nothing := []
	for a in inside:
		if not sallies.has(a.id):
			continue
		var tie := String(sallies[a.id].get("with", ""))
		if not tie.is_empty() and not _relief_outside(state, province_id, moved, tie):
			var from := String(sallies[a.id].get("from", ""))
			out.append({"type": "sally_called_off", "faction": a.owner, "armies": [a.id], "why": "relief_missing",
				"text": "The garrison of %s stayed inside: the relief from %s never arrived." % [p.name,
					_province_name(state, from) if not from.is_empty() else "outside"], "codex": "sally"})
		elif not outside_enemy:
			found_nothing.append(a.id)
	if not found_nothing.is_empty():
		out.append({"type": "sally_found_nothing", "faction": p.owner, "armies": found_nothing, "why": "besiegers_left",
			"text": "The garrison of %s came out to find the siege lines empty: the besiegers had left, so there was no battle." % p.name,
			"codex": "sally"})
	return out


## The siege block a battle at a fort carries (§4.4): {"kind", "why", "fort" (the level's id), "walls", "walls_max",
## "walls_defense" (the part each garrison fighter gets in a storm; 0 otherwise), "cover_defense"
## (FortData.COVER_DEFENSE for the from_inside fighters of a sally or breach battle; 0 otherwise), "garrison" (the
## owner's side index among the sides in faction id order, or -1), "from_inside", "turn_of_siege" (0 when there
## was no siege at the start of the turn)}. Walls never change during a battle.
static func siege_block(state: GameState, p: Province, kind: String, why: String, fids: Array, from_inside: Array) -> Dictionary:
	var ids := from_inside.map(func(a): return a.id if a is Army else String(a))
	return {"kind": kind, "why": why, "fort": String(level_data(p.fort_level).id), "walls": p.walls,
		"walls_max": walls_max(p.fort_level), "walls_defense": walls_defense(p.walls) if kind == STORM else 0,
		"cover_defense": FortData.COVER_DEFENSE if kind != STORM and not ids.is_empty() else 0,
		"garrison": fids.find(p.owner), "from_inside": ids, "turn_of_siege": turn_of_siege(state, p.id)}


static func _plan(state: GameState, p: Province, kind: String, why: String, owner_side: Array, others: Array, defender: String,
		from_inside: Array) -> Dictionary:
	var sides := {}
	for a in owner_side + others:
		if not sides.has(a.owner):
			sides[a.owner] = []
		sides[a.owner].append(a)
	var fids: Array = sides.keys()
	fids.sort()
	var ids := from_inside.map(func(a): return a.id)
	return {"kind": kind, "why": why, "sides": sides, "defender": defender, "from_inside": ids,
		"siege": siege_block(state, p, kind, why, fids, ids)}


## Whether the relief army `army_id` stands in `province_id`, having arrived this turn (outside the walls).
static func _relief_outside(state: GameState, province_id: String, moved: Dictionary, army_id: String) -> bool:
	var a := state.find_army(army_id)
	return a != null and a.location == province_id and moved.has(a.id)


static func _armies_by_faction(state: GameState, province_id: String) -> Dictionary:
	var out := {}
	for a in _sorted_armies(state):
		if a.location == province_id:
			if not out.has(a.owner):
				out[a.owner] = []
			out[a.owner].append(a)
	return out


static func _factions_of(armies: Array) -> Array:
	var out := []
	for a in armies:
		if not out.has(a.owner):
			out.append(a.owner)
	out.sort()
	return out


# --- the sieges phase (§3.3, §3.10, §2.5, §2.6) ----------------------------------------------------

## One fort's siege in the sieges phase, after battles (§3.3, §3.10). Changes `state`: records a new siege,
## drops the walls, lifts a siege or lets the fort fall. `turn` is the turn being resolved; `battle_sites` the
## provinces that had a battle this turn. Returns {} when nothing happens, otherwise {"kind": "started" |
## "damaged" | "lifted" | "fallen", "province", "owner", "besieger", "walls_before", "walls", "walls_max",
## "damage" (siege_damage's result for a siege), "breached", "turn_of_siege", "why"}.
## `beaten_by` names the faction whose armies outside the walls were destroyed there this turn, when there was one,
## so a siege lifted in battle can still say whose siege lines fell.
static func siege_step(state: GameState, province_id: String, turn: int, battle_sites: Dictionary = {}, beaten_by: String = "") -> Dictionary:
	var p := state.find_province(province_id)
	if p == null or p.fort_level <= 0 or p.owner.is_empty():
		return {}
	var mine := owner_armies(state, province_id)
	var theirs := besiegers(state, province_id)
	var besieger := besieging_faction(state, province_id)
	var out := {"kind": "", "province": p.id, "owner": p.owner, "besieger": besieger if not besieger.is_empty() else beaten_by,
		"walls_before": p.walls, "walls": p.walls, "walls_max": walls_max(p.fort_level), "damage": {}, "breached": false,
		"turn_of_siege": 0, "why": "", "fought": battle_sites.has(p.id)}
	if p.siege_since > 0 and theirs.is_empty():
		out.kind = "lifted"
		out.why = "beaten" if battle_sites.has(p.id) else "left"
		out.turn_of_siege = turn - p.siege_since + 1
		p.siege_since = 0
		return out
	if p.siege_since > 0 and mine.is_empty():
		out.kind = "fallen"
		out.why = "battle" if battle_sites.has(p.id) else "left"
		out.turn_of_siege = turn - p.siege_since + 1
		p.siege_since = 0
		return out
	if mine.is_empty() or theirs.is_empty():
		return {}
	out.kind = "damaged" if p.siege_since > 0 else "started"
	if p.siege_since <= 0:
		p.siege_since = turn
	out.turn_of_siege = turn - p.siege_since + 1
	var dmg := siege_damage(troops(theirs), engines_of(theirs), engine_plural(String(out.besieger)))
	out.damage = dmg
	p.walls = maxi(0, p.walls - int(dmg.total))
	out.walls = p.walls
	out.breached = out.walls_before > 0 and p.walls == 0
	return out


## Repair (§2.6): where no army of another faction stands, the walls rise by the level, up to the maximum.
## Returns {} when nothing changed, otherwise {"province", "owner", "from", "to", "amount", "level"}.
static func repair_step(state: GameState, province_id: String) -> Dictionary:
	var p := state.find_province(province_id)
	if p == null or p.fort_level <= 0 or p.owner.is_empty() or not besiegers(state, province_id).is_empty():
		return {}
	var top := walls_max(p.fort_level)
	if p.walls >= top:
		return {}
	var before := p.walls
	p.walls = mini(top, p.walls + repair_amount(p.fort_level))
	return {"province": p.id, "owner": p.owner, "from": before, "to": p.walls, "amount": repair_amount(p.fort_level), "level": p.fort_level}


## Construction (§2.4, §2.5): one turn of work where no enemy army stands; the level goes up at full walls when
## the last is done. Returns {} without a site, otherwise {"kind": "worked" | "halted" | "built", "province",
## "faction", "to", "left", "turns", "walls"}.
static func works_step(state: GameState, province_id: String) -> Dictionary:
	var p := state.find_province(province_id)
	if p == null or p.works.is_empty():
		return {}
	var fid := String(p.works.get("faction", ""))
	var to := int(p.works.get("to", 0))
	var out := {"kind": "", "province": p.id, "faction": fid, "to": to, "left": int(p.works.get("left", 0)),
		"turns": int(level_data(to).turns), "walls": p.walls}
	for a in state.armies:
		if a.location == p.id and a.owner != fid:
			out.kind = "halted"
			return out
	var left := int(p.works.left) - 1
	if left > 0:
		p.works["left"] = left
		out.kind = "worked"
		out.left = left
		return out
	p.fort_level = to
	p.has_fort = true
	p.walls = walls_max(to)
	p.fort_by = fid
	p.works = {}
	out.kind = "built"
	out.left = 0
	out.walls = p.walls
	return out


# --- texts -----------------------------------------------------------------------------------------

## "Walls 5 of 9: +4 defense if stormed." / "Walls 0 of 6: breached." ("" for a province without a fort).
static func walls_text(state: GameState, province_id: String) -> String:
	var p := state.find_province(province_id)
	if p == null or p.fort_level <= 0:
		return ""
	if p.walls <= 0:
		return "Walls 0 of %d: breached." % walls_max(p.fort_level)
	return "Walls %d of %d: +%d defense if stormed." % [p.walls, walls_max(p.fort_level), walls_defense(p.walls)]


## "siege camp 1, 24 troops +2, 2 Wallbreakers +2" from siege_damage's result (the cap last, when it bites).
static func damage_text(dmg: Dictionary) -> String:
	var bits := []
	for part in dmg.get("parts", []):
		if String(part.key) == "camp":
			bits.append("siege camp %d" % int(part.value))
		elif String(part.key) == "cap":
			bits.append("at most %d a turn" % int(FortData.SIEGE.max))
		else:
			bits.append("%s %+d" % [String(part.name), int(part.value)])
	return ", ".join(bits)


## "next turn (9)" / "in 3 turns (turn 11)" for walls that reach 0 at the end of `end_turn`, read at the start
## of turn `now`; "this turn (8)" when it is the turn being ordered ("at the end of this turn (8)" with `ending`).
static func in_turns_text(end_turn: int, now: int, ending: bool = false) -> String:
	var n := end_turn - now + 1
	if n <= 1:
		return ("at the end of this turn (%d)" if ending else "this turn (%d)") % end_turn
	if n == 2 and not ending:
		return "next turn (%d)" % end_turn
	return "in %d turns (turn %d)" % [n, end_turn]


## "next turn (8)" / "in 3 turns (turn 10)" for something that happens at the end of `end_turn`, told in the report
## of `resolved`, the turn that just resolved (§9.4: "The walls reach 0 next turn (8)").
static func report_when(end_turn: int, resolved: int) -> String:
	var n := end_turn - resolved
	if n <= 1:
		return "next turn (%d)" % end_turn
	return "in %d turns (turn %d)" % [n, end_turn]


## The sentence for a siege_step result (the sieges phase's events, §9.4). `state` is after the step.
static func step_text(state: GameState, info: Dictionary, turn: int) -> String:
	var p := state.find_province(String(info.province))
	var owner := _faction_name(state, String(info.owner))
	var besieger := _faction_name(state, String(info.besieger))
	match String(info.kind):
		"started", "damaged":
			var dmg: Dictionary = info.damage
			var walls := int(info.walls)
			var text := ""
			if String(info.kind) == "started":
				var force := "%d %s" % [int(dmg.troops), "troop" if int(dmg.troops) == 1 else "troops"]
				if int(dmg.engines) > 0:
					force += " and %s" % engines_text(String(info.besieger), int(dmg.engines))
				text = "The %s laid siege to %s with %s. Its walls dropped from %d to %d (siege damage %d)." % [besieger, p.name, force,
					int(info.walls_before), walls, int(dmg.total)]
				var cut := cut_off_info(state, p.id, turn + 1)
				if bool(cut.pickets):
					text += " They are only pickets, fewer than half the garrison's %d troops (%d), so %s is not cut off." % [
						int(cut.garrison_troops), int(cut.need), p.name]
				else:
					text += " From next turn (%d) %s is cut off: nobody can recruit there, and its %d gold a turn goes to the %s." % [
						turn + 1, p.name, p.income, besieger]
			else:
				text = "The siege of %s, turn %d: the walls dropped from %d to %d" % [p.name, int(info.turn_of_siege),
					int(info.walls_before), walls]
				text += " (+%d if stormed)." % walls_defense(walls) if walls > 0 else "."
			if walls > 0:
				var end := breach_turn(walls, int(dmg.total), turn + 1)
				text += " The walls reach 0 %s, if the besiegers stay as they are." % report_when(end, turn)
			return text
		"lifted":
			if String(info.why) == "beaten":
				return "The siege of %s is over: the %s siege lines were destroyed. Its walls repair from now on, and it takes recruits again from next turn (%d)." % [
					p.name, RulerRules._possessive(besieger) if not besieger.is_empty() else "enemy", turn + 1]
			return "The siege of %s is over: the besiegers left. Its walls repair from now on, and it takes recruits again from next turn (%d)." % [p.name, turn + 1]
		"fallen":
			if String(info.why) == "battle":
				return "%s fell: the battle there destroyed the %s garrison, and the %s %s the fort." % [p.name, RulerRules._possessive(owner),
					besieger, _verb(besieger, "take")]
			return "%s fell: the %s garrison left, and the %s %s the empty fort." % [p.name, RulerRules._possessive(owner), besieger,
				_verb(besieger, "take")]
	return ""


## "The walls of Stonegate are down (breached). ..." (§9.4).
static func breached_text(state: GameState, province_id: String, turn: int) -> String:
	var p := state.find_province(province_id)
	return "The walls of %s are down (breached). If both sides are still there next turn (%d), they fight there in the open, with no order." % [p.name, turn + 1]


static func repaired_text(state: GameState, info: Dictionary) -> String:
	var p := state.find_province(String(info.province))
	return "The walls of %s were repaired from %d to %d (+%d a turn, %s)." % [p.name, int(info.from), int(info.to), int(info.amount),
		level_word(int(info.level))]


static func works_text(state: GameState, info: Dictionary, turn: int) -> String:
	var p := state.find_province(String(info.province))
	var who := _faction_name(state, String(info.faction))
	var to := int(info.to)
	match String(info.kind):
		"halted":
			return "Work on the %s at %s stopped this turn: an enemy army stands there. Nothing done is lost (%d of %d turns of work done)." % [
				level_word(to), p.name, int(info.turns) - int(info.left), int(info.turns)]
		"built":
			return "The %s finished %s at %s (walls %d of %d). It takes recruits from next turn (%d), %d a turn." % [who, fort_phrase(to), p.name,
				int(info.walls), walls_max(to), turn + 1, recruit_limit(to)]
	return ""


# --- validation (§12) ------------------------------------------------------------------------------

## The fort and siege rules every state must keep, in plain words. Without sieges, no province may carry fort
## or siege data and no army may carry engines. Appends messages to `errors` (push_error when it isn't an Array).
static func validate(state: GameState, errors = null) -> bool:
	var ok := true
	if not state.sieges:
		for p in state.provinces:
			if p.fort_level != 0 or p.walls != 0 or not p.fort_by.is_empty() or not p.works.is_empty() or p.siege_since != 0 \
					or p.owned_since != 0 or not p.lost.is_empty():
				_report(errors, "Province '%s' has fort or siege data, but this game is played without forts and sieges." % p.id)
				ok = false
		for a in state.armies:
			if a.engines != 0:
				_report(errors, "Army '%s' carries siege engines, but this game is played without forts and sieges." % a.id)
				ok = false
		return ok
	var sites := {}
	var factions := {}
	for f in state.factions:
		factions[f.id] = true
	for p in state.provinces:
		if p.fort_level < 0 or p.fort_level > FortData.MAX_LEVEL:
			_report(errors, "Province '%s' has fort level %d; fort levels run from 0 to %d." % [p.id, p.fort_level, FortData.MAX_LEVEL])
			ok = false
			continue
		if p.fort_level == FortData.MAX_LEVEL and not p.is_capital:
			_report(errors, "Province '%s' is a citadel, but citadels stand only at capitals." % p.id)
			ok = false
		if p.walls < 0 or p.walls > walls_max(p.fort_level):
			_report(errors, "Province '%s' has %d wall strength, but its fort holds 0 to %d." % [p.id, p.walls, walls_max(p.fort_level)])
			ok = false
		if p.has_fort != (p.fort_level > 0):
			_report(errors, "Province '%s' %s, but its fort level is %d." % [p.id, "has a fort" if p.has_fort else "has no fort", p.fort_level])
			ok = false
		if p.fort_level == 0 and not p.fort_by.is_empty():
			_report(errors, "Province '%s' has no fort, so nobody can have built it." % p.id)
			ok = false
		if not p.works.is_empty():
			var fid := String(p.works.get("faction", ""))
			var to := int(p.works.get("to", 0))
			var left := int(p.works.get("left", 0))
			if fid != p.owner or fid.is_empty():
				_report(errors, "The construction at '%s' belongs to '%s', but the province is not theirs." % [p.id, fid])
				ok = false
			if to != p.fort_level + 1 or to > FortData.MAX_BUILT:
				_report(errors, "The construction at '%s' builds level %d on a level %d fort; a site builds the next level, at most a keep." % [p.id, to, p.fort_level])
				ok = false
			elif left < 1 or left > int(level_data(to).turns):
				_report(errors, "The construction at '%s' has %d turns of work left, but it needs 1 to %d." % [p.id, left, int(level_data(to).turns)])
				ok = false
			if sites.has(fid):
				_report(errors, "'%s' has two construction sites, at '%s' and '%s'; a faction builds one fort at a time." % [fid, sites[fid], p.id])
				ok = false
			sites[fid] = p.id
		var both := siege_stands(state, p.id)
		if both and p.siege_since <= 0:
			_report(errors, "Province '%s' holds armies of its owner and of another faction, but no siege is recorded there." % p.id)
			ok = false
		elif not both and p.siege_since != 0:
			_report(errors, "Province '%s' records a siege since turn %d, but its owner's armies and another faction's are not both there." % [p.id, p.siege_since])
			ok = false
		if p.siege_since > state.current_turn:
			_report(errors, "Province '%s' records a siege from turn %d, after the current turn %d." % [p.id, p.siege_since, state.current_turn])
			ok = false
		if both and p.fort_level <= 0:
			_report(errors, "Province '%s' holds armies of two factions, but it has no fort to besiege." % p.id)
			ok = false
		if p.owned_since < 0 or p.owned_since > state.current_turn or (p.owner.is_empty() and p.owned_since != 0):
			_report(errors, "Province '%s' says its owner took it on turn %d, which can't be (the current turn is %d)." % [p.id, p.owned_since, state.current_turn])
			ok = false
		if not p.lost.is_empty() and not factions.has(String(p.lost.get("faction", ""))):
			_report(errors, "Province '%s' was last lost by '%s', which is not a faction in this game." % [p.id, String(p.lost.get("faction", ""))])
			ok = false
	for a in state.armies:
		if a.engines < 0 or a.engines > FortData.ARMY_ENGINES_MAX:
			_report(errors, "Army '%s' carries %d siege engines; an army carries 0 to %d." % [a.id, a.engines, FortData.ARMY_ENGINES_MAX])
			ok = false
		if a.engines > 0 and (a.ruler != null or (a.units.is_empty() and a.commander == null)):
			_report(errors, "Army '%s' carries siege engines but has no fighter to work them; only an army with a unit or a commander, and never a ruler's army, carries engines." % a.id)
			ok = false
	return ok


# --- helpers ---------------------------------------------------------------------------------------

static func _reject(code: String, reason: String) -> Dictionary:
	return {"code": code, "reason": reason}


static func _faction_name(state: GameState, fid: String) -> String:
	var f := state.find_faction(fid) if state != null else null
	return f.faction_name if f else ""


## "takes" for "Aurel Crown", "take" for "Thornmane Clans": the verb agreeing with a faction's name.
static func _verb(name: String, verb: String) -> String:
	return verb if name.ends_with("s") else verb + "s"


static func _province_name(state: GameState, pid: String) -> String:
	var p := state.find_province(pid)
	return p.name if p else "a place not on the map"


static func _faction_of(armies: Array) -> String:
	return String(armies[0].owner) if not armies.is_empty() else ""


static func _sorted_armies(state: GameState) -> Array:
	var out: Array = state.armies.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _sorted_provinces(state: GameState) -> Array:
	var out: Array = state.provinces.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
