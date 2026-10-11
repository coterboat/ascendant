class_name MusterOrder
## Order (ARM-1, design/ARM1_SPLIT_MERGE.md §1): move units, a commander and engines between two of your armies
## standing in the same province, or split them off into a new army there. Three kinds:
##   transfer  `units` (indices into `from`'s units, on the board as it stands when this order applies), the
##             commander if `commander`, and `engines` engines go from `from` to `to`, or to a new army when `to` is "".
##   merge     everything in `from` goes to `to` (its commander too if `to` has none; engines if `to` can carry them).
##   swap      the two armies exchange commanders in one step, so neither is ever leaderless.
## All of a faction's musters come before all its other orders, in the order given (RulerRules.state_after_orders
## plans them on a projected board; TurnResolver._muster_phase resolves them first in the orders phase), so a new
## army gets the same real id the plan showed and can be given a move the same turn. Checked by MusterRules.
## The issuing faction is the key it is filed under in orders_by_faction.
##
## Saved as {"type": "muster", "kind", "from", "to", ...}: a transfer also "units", "commander" and "engines"; a merge
## and a swap just the three. The parser (parse, OrderBook.order_from_dict) is STRICT, unlike the older lenient ones:
## a missing key, an extra key or a wrong type makes the dictionary malformed, and a malformed muster in a record is
## an error, never silently skipped (a MusterOrder with `malformed` set is returned so nothing can drop it).

const TYPE := "muster"
const TRANSFER := "transfer"
const MERGE := "merge"
const SWAP := "swap"
const KINDS := [TRANSFER, MERGE, SWAP]
## The keys each kind is saved with, "type" first: exactly these, nothing else.
const KEYS := {
	TRANSFER: ["type", "kind", "from", "to", "units", "commander", "engines"],
	MERGE: ["type", "kind", "from", "to"],
	SWAP: ["type", "kind", "from", "to"],
}

var kind: String = TRANSFER
var from_army: String = ""  # the source army (swap: the first army)
var to_army: String = ""  # the target army; "" for a new army (transfer only; swap: the second army)
var units: Array = []  # transfer: indices into from_army's units, on the board when this order applies
var commander: bool = false  # transfer: the commander goes too
var engines: int = 0  # transfer: how many of from_army's engines go
## "" for an order a game made; for one a record held that is not a muster at all, the plain reason (the order is then
## kept so a loader can fail on it; `raw` is what the record held).
var malformed: String = ""
var raw: Dictionary = {}


func _init(p_kind: String = TRANSFER, p_from: String = "", p_to: String = "", p_units: Array = [], p_commander: bool = false,
		p_engines: int = 0) -> void:
	kind = p_kind
	from_army = p_from
	to_army = p_to
	units = p_units.duplicate()
	commander = p_commander
	engines = p_engines


## A transfer of `unit_indices` (and the commander, and some engines) from `from` to `to`, or to a new army ("").
static func transfer(from: String, to: String, unit_indices: Array, with_commander: bool = false, with_engines: int = 0) -> MusterOrder:
	return MusterOrder.new(TRANSFER, from, to, unit_indices, with_commander, with_engines)


## Everything in `from` into `to`.
static func merge(from: String, to: String) -> MusterOrder:
	return MusterOrder.new(MERGE, from, to)


## `a` and `b` exchange commanders.
static func swap(a: String, b: String) -> MusterOrder:
	return MusterOrder.new(SWAP, a, b)


func is_transfer() -> bool:
	return kind == TRANSFER


func is_new_army() -> bool:
	return kind == TRANSFER and to_army.is_empty()


func to_dict() -> Dictionary:
	if not malformed.is_empty():
		return raw.duplicate(true)  # a corrupt record's order is handed back as it was read
	var d := {"type": TYPE, "kind": kind, "from": from_army, "to": to_army}
	if kind == TRANSFER:
		d["units"] = units.duplicate()
		d["commander"] = commander
		d["engines"] = engines
	return d


## A copy of this order.
func copy() -> MusterOrder:
	var c := MusterOrder.new(kind, from_army, to_army, units, commander, engines)
	c.malformed = malformed
	c.raw = raw.duplicate(true)
	return c


func describe() -> String:
	match kind:
		MERGE:
			return "merge %s into %s" % [from_army, to_army]
		SWAP:
			return "swap the commanders of %s and %s" % [from_army, to_army]
	var bits := []
	if not units.is_empty():
		bits.append("units %s" % str(units))
	if commander:
		bits.append("the commander")
	if engines > 0:
		bits.append("%d engines" % engines)
	return "move %s from %s to %s" % [", ".join(bits), from_army, to_army if not to_army.is_empty() else "a new army"]


## Reads a saved muster (STRICT): {"order": MusterOrder, "problem": ""} when `data` is well formed, otherwise {"order": a
## MusterOrder with `malformed` and `raw` set, "problem": the plain reason}. The checks are exactly these: a "type" of
## "muster"; a "kind" that is transfer, merge or swap; exactly the keys of that kind (no more, no fewer); "from" and
## "to" text; for a transfer "units" a list of unique non-negative whole numbers, "commander" true or false and "engines"
## a non-negative whole number. A whole number may arrive as a float, as JSON gives every number.
static func parse(data: Dictionary) -> Dictionary:
	var why := _problem(data)
	if not why.is_empty():
		var bad := MusterOrder.new()
		bad.malformed = why
		bad.raw = data.duplicate(true)
		return {"order": bad, "problem": why}
	var order := MusterOrder.new(String(data.kind), String(data["from"]), String(data["to"]))
	if order.kind == TRANSFER:
		order.units = Array(data.units).map(func(i): return int(i))
		order.commander = bool(data.commander)
		order.engines = int(data.engines)
	return {"order": order, "problem": ""}


static func _problem(data: Dictionary) -> String:
	if data.get("type") != TYPE:
		return "it is not a muster order"
	var kind = data.get("kind")
	if not (kind is String):
		return "it has no 'kind' (transfer, merge or swap)"
	if not KINDS.has(kind):
		return "it has the kind '%s', but a muster is a transfer, a merge or a swap" % kind
	var keys: Array = KEYS[kind]
	for key in keys:
		if not data.has(key):
			return "a %s has no '%s'" % [kind, key]
	for key in data:
		if not keys.has(str(key)):
			return "a %s holds '%s', which it never holds" % [kind, key]
	for key in ["from", "to"]:
		if not (data[key] is String):
			return "'%s' should be an army id as text, not %s" % [key, Serial._type_words(typeof(data[key]))]
	if kind != TRANSFER:
		return ""
	var units = data.units
	if not (units is Array):
		return "'units' should be a list of unit places, not %s" % Serial._type_words(typeof(units))
	var seen := {}
	for i in units:
		if not _whole(i) or int(i) < 0:
			return "'units' should hold whole numbers from 0, and it holds %s" % str(i)
		if seen.has(int(i)):
			return "'units' names unit place %d twice" % int(i)
		seen[int(i)] = true
	if typeof(data.commander) != TYPE_BOOL:
		return "'commander' should be true or false, not %s" % Serial._type_words(typeof(data.commander))
	if not _whole(data.engines) or int(data.engines) < 0:
		return "'engines' should be a whole number from 0, not %s" % str(data.engines)
	return ""


## True for an int, or a float with no fraction (JSON reads every number as a float); never a bool or text.
static func _whole(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(v) and v == floorf(v) and absf(v) < 9007199254740992.0
	return false
