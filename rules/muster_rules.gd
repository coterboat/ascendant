class_name MusterRules
## ARM-1 (design/ARM1_SPLIT_MERGE.md §1-§4): the rules of a MusterOrder, in pure code that planning and resolution
## both run, so the plan and the resolved turn can never disagree.
##
##   check(state, fid, order)          {} when the order may apply to this board, otherwise {"code", "reason"}
##   apply(state, fid, order)          applies it in place; {"ok", "code", "reason", "info"} (the info is what the
##                                     events and the forecast say: see apply())
##   project(state, fid, orders)       a copy of `state` with the faction's musters applied, in order, the ones that
##                                     fail skipped (they allocate nothing); null-safe: `state` itself when none
##   musters_of(orders)                the MusterOrders in a list, in the order given
##   event_sentence(state, e)          the plain sentence of one of the five structured muster events
##
## An order acts on the board as it stands when it applies: the start of the turn plus this faction's earlier
## musters, in order (so indices mean the same in the plan and in the resolution, and a unit sent from A to B can go
## on from B to C). A new army takes its id from GameState.new_army_id, in that same order.
##
## What may muster (§2): both armies yours and in the same province; neither holds a ruler (a ruler travels alone);
## a transfer moves at least one unit or the commander, with no unit place out of range or repeated; an army keeps at
## most one commander; engines (FortData.ARMY_ENGINES_MAX) move only when the order says so, to an army with a
## fighter; and a source left with no units and no commander disbands, so its engines must have moved.
##
## Blessings (§2.1): a fighter that leaves an army loses what it carried for that army (UnitStatus.clear_on_leave), and
## one that joins an army under a blessing is marked outside it (UnitStatus.OUTSIDE_BLESSING): units don't gain a
## blessing by joining. A disbanded army is forgotten by the blessings that listed it.

const EVENT_TYPES := ["army_split", "units_transferred", "armies_merged", "commanders_swapped", "army_disbanded"]
const CODEX := "muster"


# --- the list -----------------------------------------------------------------------------------------

## The MusterOrders in `orders`, in the order given.
static func musters_of(orders: Array) -> Array:
	return orders.filter(func(o): return o is MusterOrder)


static func has_musters(orders: Array) -> bool:
	for o in orders:
		if o is MusterOrder:
			return true
	return false


## A copy of `state` with `faction_id`'s musters in `orders` applied, in order (sequentially: each one acts on the board
## the earlier ones left). A muster that fails there is skipped and allocates nothing. `state` itself when there are none.
## Pure: `state` is never changed.
static func project(state: GameState, faction_id: String, orders: Array) -> GameState:
	var list := musters_of(orders)
	if list.is_empty():
		return state
	var copy := state.deep_copy([])
	if copy == null:
		return state
	apply_all(copy, faction_id, list)
	return copy


## Applies `list` (MusterOrders) to `state` in place, in order. Returns what each did: [{"order", "ok", "code",
## "reason", "info"}]. A failed one changes nothing and allocates no id.
static func apply_all(state: GameState, faction_id: String, list: Array) -> Array:
	var out := []
	for o in list:
		var r := apply(state, faction_id, o)
		r["order"] = o
		out.append(r)
	return out


# --- the checks ---------------------------------------------------------------------------------------

## {} when `order` may apply to `state` (the board as it stands when it applies), otherwise {"code", "reason"}.
static func check(state: GameState, faction_id: String, order: MusterOrder) -> Dictionary:
	var plan := _plan(state, faction_id, order)
	return {} if plan.ok else {"code": plan.code, "reason": plan.reason}


## Applies `order` to `state` in place. {"ok": false, "code", "reason"} and no change when it fails the checks. Otherwise
## {"ok": true, "info": {...}}, where info holds:
##   "kind"           transfer | merge | swap
##   "faction", "from", "to" (the target's id, a new army's real id), "created" (a new army), "province"
##   "units"          the moved units' type ids, in the order they now stand
##   "commander"      the moved commander's type id ("" when none moved); a swap has "commander" (a's goes to b) and
##                    "commander_b"
##   "engines"        engines moved
##   "disbanded"      army ids that went (the source, when it kept no unit and no commander)
##   "commander_left" a merge left the source's commander behind (both armies had one); "commander_stays" is its type id
##   "outside"        [{"army", "blessing", "count", "types"}]: the fighters that joined an army under a blessing and are outside it
static func apply(state: GameState, faction_id: String, order: MusterOrder) -> Dictionary:
	var plan := _plan(state, faction_id, order)
	if not plan.ok:
		return {"ok": false, "code": plan.code, "reason": plan.reason}
	var from: Army = plan.from
	var to: Army = plan.to
	var info := {"kind": order.kind, "faction": faction_id, "from": from.id, "to": "", "created": false, "province": from.location,
		"units": [], "commander": "", "engines": 0, "disbanded": [], "commander_left": false, "outside": []}
	if to == null:
		to = Army.new()
		to.id = state.new_army_id(faction_id)
		to.owner = faction_id
		to.location = from.location
		to.flame = from.flame  # CW-1: a split's new army keeps its source's flame (design/CANDLEWAKE.md §2.1, after ARM-1)
		state.armies.append(to)
		info["created"] = true
	info["to"] = to.id
	var joiners := []  # the fighters that joined `to`, for the blessing markers
	match order.kind:
		MusterOrder.SWAP:
			var a_cmd: Unit = from.commander
			var b_cmd: Unit = to.commander
			from.commander = b_cmd
			to.commander = a_cmd
			info["commander"] = a_cmd.type.id
			info["commander_b"] = b_cmd.type.id
			UnitStatus.clear_on_leave(a_cmd)
			UnitStatus.clear_on_leave(b_cmd)
			_join(state, to, a_cmd, info)
			_join(state, from, b_cmd, info)
		_:
			var moving: Array = plan.units  # indices, ascending
			var moved: Array[Unit] = []
			for i in moving:
				moved.append(from.units[i])
			var kept: Array[Unit] = []
			for i in from.units.size():
				if not moving.has(i):
					kept.append(from.units[i])
			from.units = kept
			for u in moved:
				UnitStatus.clear_on_leave(u)
				to.units.append(u)
				info["units"].append(u.type.id)
				joiners.append(u)
			if plan.commander:
				var cmd: Unit = from.commander
				from.commander = null
				UnitStatus.clear_on_leave(cmd)
				to.commander = cmd
				info["commander"] = cmd.type.id
				joiners.append(cmd)
			info["commander_left"] = plan.commander_left
			info["commander_stays"] = from.commander.type.id if plan.commander_left else ""
			var n: int = plan.engines
			from.engines -= n
			to.engines += n
			info["engines"] = n
			for u in joiners:
				_join(state, to, u, info)
			if from.units.is_empty() and from.commander == null and from.ruler == null:
				state.armies.erase(from)
				info["disbanded"].append(from.id)
				MagicRules.forget_army(state, from.id)
	return {"ok": true, "info": info}


## Marks `unit`, which just joined `army`, as outside the blessing that covers `army` (if one does).
static func _join(state: GameState, army: Army, unit: Unit, info: Dictionary) -> void:
	var blessing := MagicRules.blessing_of(state, army.id)
	if blessing.is_empty() or String(blessing.faction) != unit.owner:
		return
	unit.add_status(UnitStatus.OUTSIDE_BLESSING, String(blessing.id))
	for row in info.outside:
		if row.army == army.id:
			row.count += 1
			row.types.append(unit.type.id)
			return
	info.outside.append({"army": army.id, "blessing": String(blessing.id), "count": 1, "types": [unit.type.id]})


## What `order` would do, or why not: {"ok", "code", "reason"} and, when ok, "from" and "to" (the Army objects; "to" is null
## for a new army), "units" (the indices that move, ascending), "commander" (whether the source's commander moves),
## "commander_left", "engines" (how many move).
static func _plan(state: GameState, faction_id: String, order: MusterOrder) -> Dictionary:
	if not order.malformed.is_empty():
		return _no("malformed_muster", "That muster order is not well formed: %s." % order.malformed)
	var faction := state.find_faction(faction_id)
	if faction == null:
		return _no("unknown_faction", "Those orders are for a faction that is not in this game.")
	if not MusterOrder.KINDS.has(order.kind):
		return _no("unknown_muster", "A muster is a transfer, a merge or a swap, and this is none of them.")
	var from := state.find_army(order.from_army)
	if from == null:
		return _no("unknown_army", "There is no army to muster from: it may have been destroyed, or the order names an army this game never had.")
	if from.owner != faction_id:
		return _no("not_your_army", "%s at %s belongs to %s, not to %s. You can only muster your own armies." % [
			_cap(_name(state, from)), _place(state, from), _faction(state, from.owner), faction.faction_name])
	var to: Army = null
	if not (order.kind == MusterOrder.TRANSFER and order.to_army.is_empty()):
		if order.to_army.is_empty():
			return _no("unknown_army", "A %s needs a second army, and this order names none." % order.kind)
		to = state.find_army(order.to_army)
		if to == null:
			return _no("unknown_army", "There is no army to muster into: it may have been destroyed, or the order names an army this game never had.")
		if to.owner != faction_id:
			return _no("not_your_army", "%s at %s belongs to %s, not to %s. You can only muster your own armies." % [
				_cap(_name(state, to)), _place(state, to), _faction(state, to.owner), faction.faction_name])
		if to == from:
			return _no("same_army", "%s can't muster with itself. Name two different armies." % _cap(_name(state, from)))
		if to.location != from.location:
			return _no("different_province", "%s is at %s and %s is at %s. Armies muster only within one province, before any of them moves." % [
				_cap(_name(state, from)), _place(state, from), _name(state, to), _place(state, to)])
	for army in [from, to]:
		if army != null and army.ruler != null:
			return _no("ruler_army", "%s is %s's army, and a ruler travels alone: no units, commander or engines join or leave it." % [
				_cap(_name(state, army)), RulerRules.current_name(state, faction_id) if RulerRules.current_name(state, faction_id) != "" else "your ruler"])
	match order.kind:
		MusterOrder.SWAP:
			return _plan_swap(state, from, to)
		MusterOrder.MERGE:
			return _plan_merge(state, from, to)
	return _plan_transfer(state, order, from, to)


static func _plan_transfer(state: GameState, order: MusterOrder, from: Army, to: Army) -> Dictionary:
	var seen := {}
	for i in order.units:
		if not (i is int) or i < 0 or i >= from.units.size():
			return _no("bad_unit", "%s has %s, so there is no unit number %s in it." % [_cap(_name(state, from)),
				_count(from.units.size(), "unit", "units"), str(i + 1) if i is int else str(i)])
		if seen.has(i):
			return _no("duplicate_unit", "Unit number %d of %s is named twice in one order. Each unit goes once." % [i + 1, _name(state, from)])
		seen[i] = true
	if order.units.is_empty() and not order.commander:
		# Engines may move on their own between two armies that stand there (the receiver carries them); a new army has no fighter to
		# carry them, so an engines-only split is refused in words.
		if order.engines <= 0:
			return _no("empty_transfer", "That order moves no one. Choose at least one unit or the commander of %s to move, or some of its siege engines to another army." % _name(state, from))
		if to == null:
			return _no("engines_alone", "Siege engines ride only with a fighter, so they can't form an army of their own. Send them to an army of yours here, or split units or the commander off with them.")
	if order.commander and from.commander == null:
		return _no("no_commander", "%s has no commander to move." % _cap(_name(state, from)))
	if order.commander and to != null and to.commander != null:
		return _no("two_commanders", "%s already has a commander, %s, and an army keeps only one. Swap the commanders instead, or move the units alone." % [
			_cap(_name(state, to)), to.commander.type.name])
	if order.engines < 0:
		return _no("bad_engines", "An order can't move a negative number of engines.")
	if order.engines > from.engines:
		return _no("not_enough_engines", "%s carries %s, so it can't send %d." % [_cap(_name(state, from)),
			SiegeRules.engines_text(from.owner, from.engines) if from.engines > 0 else "no siege engines", order.engines])
	var units_left := from.units.size() - order.units.size()
	var commander_left := from.commander != null and not order.commander
	var disbands := units_left == 0 and not commander_left
	if disbands and from.engines - order.engines > 0:
		return _no("engines_stranded", "%s would be left with no fighter, and siege engines ride only with a fighter. Send its %s too." % [
			_cap(_name(state, from)), SiegeRules.engines_text(from.owner, from.engines - order.engines)])
	if order.engines > 0:
		var after := (to.engines if to != null else 0) + order.engines
		if after > FortData.ARMY_ENGINES_MAX:
			return _no("engine_cap", "%s would carry %d siege engines, and an army carries at most %d." % [
				_cap(_name(state, to)), after, FortData.ARMY_ENGINES_MAX])
	var indices := order.units.duplicate()
	indices.sort()
	return {"ok": true, "from": from, "to": to, "units": indices, "commander": order.commander, "commander_left": false,
		"engines": order.engines}


static func _plan_merge(state: GameState, from: Army, to: Army) -> Dictionary:
	var commander_moves := from.commander != null and to.commander == null
	var commander_left := from.commander != null and to.commander != null
	if from.units.is_empty() and not commander_moves and from.engines <= 0:
		# (with engines to send, the merge still moves them: the commander stays behind as an army of its own)
		return _no("nothing_to_merge", "Nothing would move: %s has no units or siege engines, and %s already has a commander, so its commander stays." % [
			_name(state, from), _name(state, to)])
	if from.engines > 0:
		var after := to.engines + from.engines
		if after > FortData.ARMY_ENGINES_MAX:
			return _no("engine_cap", "%s would carry %d siege engines with %s, and an army carries at most %d. Move some engines elsewhere first." % [
				_cap(_name(state, to)), after, _name(state, from), FortData.ARMY_ENGINES_MAX])
		if to.units.is_empty() and to.commander == null and from.units.is_empty() and not commander_moves:
			return _no("engines_stranded", "%s can't carry the siege engines." % _cap(_name(state, to)))
	var indices := []
	for i in from.units.size():
		indices.append(i)
	return {"ok": true, "from": from, "to": to, "units": indices, "commander": commander_moves, "commander_left": commander_left,
		"engines": from.engines}


static func _plan_swap(state: GameState, from: Army, to: Army) -> Dictionary:
	for army in [from, to]:
		if army.commander == null:
			return _no("no_commander", "%s has no commander to swap. To move a commander into an army without one, transfer it." % _cap(_name(state, army)))
	return {"ok": true, "from": from, "to": to, "units": [], "commander": false, "commander_left": false, "engines": 0}


static func _no(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}


# --- words --------------------------------------------------------------------------------------------

static func _name(state: GameState, army: Army) -> String:
	return TurnReportText.army_name(state, army.id, army.owner)


static func _place(state: GameState, army: Army) -> String:
	return TurnResolver._province_name(state, army.location)


static func _faction(state: GameState, fid: String) -> String:
	return TurnResolver._faction_name(state, fid)


static func _cap(text: String) -> String:
	return RulerRules._cap(text)


static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


const COUNT_WORDS := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]


## "two" for 2 up to twelve, then the digits.
static func count_word(n: int) -> String:
	return COUNT_WORDS[n] if n >= 0 and n < COUNT_WORDS.size() else str(n)


## "two Knights", "a Knight Captain", "three Spearmen and a Knight": the type ids in `type_ids` counted by type in the
## order of first appearance, named from `fid`'s roster (TurnResolver._unit_type_name for any other).
static func units_words(state: GameState, fid: String, type_ids: Array) -> String:
	var order := []
	var counts := {}
	for id in type_ids:
		if not counts.has(id):
			order.append(id)
			counts[id] = 0
		counts[id] += 1
	var parts := []
	for id in order:
		var name := _type_name(state, fid, String(id))
		var n: int = counts[id]
		parts.append(("a " + name) if n == 1 and not TurnReportText._plural_word(name) else (name if n == 1 else "%s %s" % [count_word(n), TurnReportText._plural_name(name)]))
	return RulerRules._and_list(parts)


## The plain sentence of a muster event `e` (one of EVENT_TYPES), as the record's text and the turn report say it. Names
## armies by their names for life; `state` is read only for names, so the state after the turn serves.
##   army_split          "Two Knights of the Crown's 1st formed the Crown's 4th at Crownkeep."
##   units_transferred   "Two Knights of the Crown's 1st joined the Crown's 2nd at Crownkeep. They aren't under its Dawn Blessing."
##   armies_merged       "The Crown's 2nd merged into the Crown's 1st at Crownkeep: three Spearmen and the Knight Captain joined it."
##   commanders_swapped  "The Crown's 1st and the Crown's 2nd swapped commanders at Crownkeep: ..."
##   army_disbanded      "The Crown's 2nd had no one left and was disbanded."
static func event_sentence(state: GameState, e: Dictionary) -> String:
	var n: Dictionary = e.get("numbers", {})
	var fid := String(Array(e.get("factions", [])).front()) if not Array(e.get("factions", [])).is_empty() else ""
	var where := TurnResolver._province_name(state, String(Array(e.get("provinces", [])).front())) if not Array(e.get("provinces", [])).is_empty() else ""
	match String(e.get("type", "")):
		"army_split":
			return "%s of %s formed %s at %s." % [_cap(_moved_words(state, fid, n)), _army(state, fid, n.from), _army(state, fid, n.to), where]
		"units_transferred":
			return "%s of %s joined %s at %s.%s" % [_cap(_moved_words(state, fid, n)), _army(state, fid, n.from), _army(state, fid, n.to), where,
				_outside_words(state, n)]
		"armies_merged":
			var line := "%s merged into %s at %s" % [_cap(_army(state, fid, n.from)), _army(state, fid, n.to), where]
			var moved := _moved_words(state, fid, n)
			line += ": %s joined it." % moved if moved != "no one" else " (no one moved)."
			if bool(n.get("commander_left", false)):
				line += " Both had a commander, so %s stays behind, and %s goes on as an army of its own." % [
					"the " + _type_name(state, fid, String(n.get("commander_stays", ""))) if not String(n.get("commander_stays", "")).is_empty() else "its commander",
					_army(state, fid, n.from)]
			return line + _outside_words(state, n)
		"commanders_swapped":
			var ca := _type_name(state, fid, String(n.get("a_commander", "")))
			var cb := _type_name(state, fid, String(n.get("b_commander", "")))
			var head := "%s and %s swapped commanders at %s" % [_cap(_army(state, fid, n.a)), _army(state, fid, n.b), where]
			if ca == cb:
				return "%s (both are %s).%s" % [head, TurnReportText._plural_name(ca), _outside_words(state, n)]
			return "%s: the %s now leads %s, and the %s leads %s.%s" % [head, ca, _army(state, fid, n.b), cb, _army(state, fid, n.a), _outside_words(state, n)]
		"army_disbanded":
			return "%s had no one left and was disbanded." % _cap(_army(state, fid, n.army))
	return String(e.get("text", ""))


## A unit type's name for players, from `fid`'s roster, commander or ruler (renamed by a transformation, if so).
static func _type_name(state: GameState, fid: String, type_id: String) -> String:
	var f := state.find_faction(fid)
	if f != null:
		for ut in f.unit_types:
			if ut.id == type_id:
				return ut.name
		if f.commander_type != null and f.commander_type.id == type_id:
			return f.commander_type.name
		if f.ruler_unit_type != null and f.ruler_unit_type.id == type_id:
			return f.ruler_unit_type.name
	return TurnResolver._unit_type_name(state, type_id)


static func _army(state: GameState, fid: String, army_id) -> String:
	return TurnReportText.army_name(state, String(army_id), fid)


## "two Knights and the Knight Captain", "a Siege Ram", "three Spearmen, the Knight Captain and 1 Siege Ram": who and what moved.
static func _moved_words(state: GameState, fid: String, n: Dictionary) -> String:
	var parts := []
	var units: Array = n.get("units", [])
	if not units.is_empty():
		parts.append(units_words(state, fid, units))
	var cmd := String(n.get("commander", ""))
	if not cmd.is_empty():
		parts.append("the " + _type_name(state, fid, cmd))
	var engines := int(n.get("engines", 0))
	if engines > 0:
		parts.append(SiegeRules.engines_text(fid, engines) if engines > 1 else "a " + SiegeRules.engines_text(fid, 1).trim_prefix("1 "))
	return RulerRules._and_list(parts) if not parts.is_empty() else "no one"


## " They aren't under its Dawn Blessing." when fighters joined an army under a blessing (§2.1).
static func _outside_words(state: GameState, n: Dictionary) -> String:
	var outside := 0
	var ritual := ""
	for row in n.get("outside", []):
		outside += int(row.count)
		if ritual.is_empty():
			var enchantment := MagicRules._enchantment(state, String(row.blessing))
			if not enchantment.is_empty():
				ritual = MagicRules.spell_name(String(enchantment.ritual))
	if outside <= 0:
		return ""
	return " %s under %s." % ["It isn't" if outside == 1 else "They aren't", "its " + ritual if not ritual.is_empty() else "its blessing"]


## A muster in a few words, for lists of removed orders: "Split 2 units from the Crown's 1st", "Merge the Crown's 2nd into the
## Crown's 1st", "Swap the commanders of the Crown's 1st and the Crown's 2nd". (It reads names only, so an order whose armies
## are gone still has a line.)
static func short_text(state: GameState, faction_id: String, order: MusterOrder) -> String:
	var from := TurnReportText.army_name(state, order.from_army, faction_id)
	var to := TurnReportText.army_name(state, order.to_army, faction_id) if not order.to_army.is_empty() else ""
	match order.kind:
		MusterOrder.MERGE:
			return "Merge %s into %s" % [from, to]
		MusterOrder.SWAP:
			return "Swap the commanders of %s and %s" % [from, to]
	var bits := []
	if not order.units.is_empty():
		bits.append(_count(order.units.size(), "unit", "units"))
	if order.commander:
		bits.append("the commander")
	if order.engines > 0:
		bits.append(_count(order.engines, "engine", "engines"))
	var what := RulerRules._and_list(bits)
	if order.to_army.is_empty():
		return "Split %s from %s" % [what, from]
	return "Move %s from %s to %s" % [what, from, to]


## A muster as the orders list says it, with the units named: "Split Spearmen and Knights from the Crown's 1st into a new army,
## the Crown's 2nd, at Crownkeep." `board` is the board this order applies to (the state after the earlier musters), so the unit
## places mean the units they will be. An order the board doesn't fit reads as its short text.
static func order_text(board: GameState, faction_id: String, order: MusterOrder) -> String:
	var from := board.find_army(order.from_army)
	var to := board.find_army(order.to_army) if not order.to_army.is_empty() else null
	if from == null or (to == null and not order.to_army.is_empty()):
		return short_text(board, faction_id, order) + "."
	var where := _place(board, from)
	var a := _army(board, faction_id, from.id)
	match order.kind:
		MusterOrder.MERGE:
			return "Merge %s into %s at %s." % [a, _army(board, faction_id, to.id), where]
		MusterOrder.SWAP:
			return "Swap the commanders of %s and %s at %s." % [a, _army(board, faction_id, to.id), where]
	var types := []
	var indices := order.units.duplicate()
	indices.sort()
	for i in indices:
		if i is int and i >= 0 and i < from.units.size():
			types.append(from.units[i].type.id)
	var numbers := {"units": types, "commander": from.commander.type.id if order.commander and from.commander != null else "",
		"engines": order.engines}
	var what := _moved_words(board, faction_id, numbers)
	if to == null:
		return "Split %s from %s into a new army, %s, at %s." % [what, a, _army(board, faction_id, board.peek_army_ids(faction_id, 1)[0]), where]
	return "Move %s from %s to %s at %s." % [what, a, _army(board, faction_id, to.id), where]
