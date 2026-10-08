extends RefCounted
## What a game with magic writes down for the balance check (M5-11, #122; design/M5_MAGIC_FOG.md §13.2). Pure: no nodes,
## no scenes. Simulator.play_game calls these hooks; the bands themselves are judged in magic_matrix.gd. Kept apart from
## simulator.gd so a game without magic runs none of it and its result is the result of main.
##
## A game's log (result.magic):
##   "arcana"    {faction id: {node id: the turn at whose end it was researched}} (the magic nodes only)
##   "casts"     one row per ritual order that reached the rituals phase: {"faction", "ritual", "turn", "outcome" ("cast" or
##               "turned_aside"), "pay" ("gold" or "blood"), "gold", "hp" (what was paid), "price" (the ritual's price in
##               gold), "caster" ("mage" or "ruler"), "kind", "target", "army", "size" (Call the Pack's wolves), "read" (the
##               rival Far Sight read), "blocked"}
##   "healed"    {ritual id: hit points healed in the enchantments phase} (Dawn Blessing)
##   "drained"   {ritual id: hit points a curse took} (Bloodrot)
##   "moon"      hit points the Blood Moon healed back in battles
##   "spells"    {faction id: {battle spell id: casts}} over the game's battles
##   "sold"      {faction id: gold from research sold}
##   "forecast"  the ritual forecast check: {"checks", "mismatches", "turned_aside" (set aside from the check), "unseen"
##               (a target out of clear sight, set aside), "first" (the first mismatch, in words)}
##   "hp"        the hit point ledger check: {"checks", "mismatches", "first"}

const RITUAL_EVENTS := ["ritual_cast", "ritual_turned_aside"]
const BATTLE_TYPES := ["battle", "border_battle"]
## Numbers of a ritual event the forecast check leaves out: they name things a view shows differently or a forecast never
## knows (the id of an army a rival's ritual will make, say). Everything else must be the forecast's.
const FORECAST_SKIP := []


static func new_log() -> Dictionary:
	return {"arcana": {}, "casts": [], "healed": {}, "drained": {}, "moon": 0, "spells": {}, "sold": {},
		"forecast": {"checks": 0, "mismatches": 0, "turned_aside": 0, "unseen": 0, "first": ""},
		"hp": {"checks": 0, "mismatches": 0, "first": ""}}


## The factors a battle report credits to a spell or ritual, as the spell's id ("spell_sunlance" and
## "morale_spell_dawn_blessing" are Sunlance and Dawn Blessing), or "" for any other factor.
static func spell_of(factor_id: String) -> String:
	if factor_id.begins_with("morale_spell_"):
		return factor_id.trim_prefix("morale_spell_")
	if factor_id.begins_with("spell_"):
		return factor_id.trim_prefix("spell_")
	return ""


## What a battle record keeps of a magic game's battle report (Simulator._battle_record merges it): {"top" (the first
## "why" factor's id), "spells" ({faction id: [battle spell ids cast]}), "casters" ({faction id: casters present}),
## "moon" ({faction id: hit points healed back}), "worth" ({faction id: what its spells and blessings were worth, in the
## report's damage terms, over all factors})}.
static func battle_extras(report: Dictionary) -> Dictionary:
	var spells := {}
	var casters := {}
	var moon := {}
	for sr in report.get("sides", []):
		var fid := String(sr.get("faction", ""))
		var cast: Array = sr.get("spells_cast", {}).keys()
		cast.sort()
		spells[fid] = cast
		var n := 0
		for c in sr.get("casters", []):
			n += int(c.get("count", 0))
		casters[fid] = n
		if int(sr.get("moon_healed", 0)) > 0:
			moon[fid] = int(sr.moon_healed)
	var worth := {}
	for f in report.get("all_factors", []):
		if not spell_of(String(f.get("id", ""))).is_empty():
			var fid := String(f.get("faction", ""))
			worth[fid] = float(worth.get(fid, 0.0)) + float(f.get("impact", 0.0))
	var chosen: Array = report.get("factors", [])
	return {"top": String(chosen[0].get("id", "")) if not chosen.is_empty() else "", "spells": spells, "casters": casters, "moon": moon,
		"worth": worth}


## Notes what the turn's events say (casts, healing, curses, the Blood Moon, research sold) in the game's log.
static func record_turn(log: Dictionary, turn: int, events: Array) -> void:
	for e in events:
		var type := String(e.get("type", ""))
		var n: Dictionary = e.get("numbers", {})
		var fids: Array = e.get("factions", [])
		if RITUAL_EVENTS.has(type):
			var summon: Dictionary = n.get("summon", {})
			log.casts.append({"faction": String(fids[0]) if not fids.is_empty() else "", "ritual": String(n.get("ritual", "")), "turn": turn,
				"outcome": "cast" if type == "ritual_cast" else "turned_aside", "pay": String(n.get("pay", "gold")), "gold": int(n.get("gold", 0)),
				"hp": int(n.get("hp", 0)), "price": int(n.get("price", 0)), "caster": String(n.get("caster", "")), "kind": String(n.get("kind", "")),
				"target": String(n.get("target", "")), "army": String(n.get("army", "")), "size": int(summon.get("count", 0)),
				"read": String(n.get("read", "")), "blocked": String(n.get("blocked", ""))})
		elif type == "blessing_healed":
			_add(log.healed, String(n.get("ritual", "")), int(n.get("total", 0)))
		elif type == "curse_bit":
			_add(log.drained, String(n.get("ritual", "")), int(n.get("total", 0)))
		elif type == "research_sold" and not fids.is_empty():
			_add(log.sold, String(fids[0]), int(n.get("gold", 0)))
		elif BATTLE_TYPES.has(type):
			for sr in n.get("report", {}).get("sides", []):
				var fid := String(sr.get("faction", ""))
				for sid in sr.get("spells_cast", {}):
					if not log.spells.has(fid):
						log.spells[fid] = {}
					_add(log.spells[fid], String(sid), int(sr.spells_cast[sid]))
				log.moon += int(sr.get("moon_healed", 0))


## The magic nodes each faction had researched when the game ended (turn at whose end), into the log.
static func finish(log: Dictionary, final_state: GameState) -> void:
	for f in final_state.factions:
		var done := {}
		for nid in MagicRules.arcana_ids(f.id):
			var t := AscensionRules.researched_turn(final_state, f.id, String(nid))
			if t > 0:
				done[String(nid)] = t
		log.arcana[f.id] = done


static func _add(d: Dictionary, key: String, by: int) -> void:
	d[key] = int(d.get(key, 0)) + by


# --- the ritual forecast check (band G13) ---------------------------------------------------------------------

## The forecasts of the ritual orders a seat queued, made from `view` (what the seat saw: the state, or its view under fog)
## with `accepted` (the orders the session took): [{"faction", "army", "ritual", "ok", "reason", "numbers" (what the
## forecast says the ritual event will carry), "clear" (the target was in clear sight when the order was given)}].
## `sight` is FogRules.sight of the true state for the seat (empty without fog: everything is in clear sight).
static func forecast_orders(view: GameState, fid: String, accepted: Array, sight: Dictionary) -> Array:
	var out := []
	for o in accepted:
		if not (o is CastOrder):
			continue
		var fc := MagicRules.forecast_ritual(view, fid, o, accepted)
		var clear: bool = o.target.is_empty() or sight.is_empty() or String(sight.get(o.target, FogRules.VEILED)) == FogRules.CLEAR
		out.append({"faction": fid, "army": o.army_id, "ritual": o.ritual, "ok": bool(fc.get("ok", false)), "reason": String(fc.get("reason", "")),
			"numbers": TurnResolver._ritual_numbers(fc.effect) if bool(fc.get("ok", false)) else {}, "clear": clear})
	return out


## Compares the forecasts made at the start of the turn with the turn's events, into the log's "forecast" counters: for
## a ritual that took effect with its target in clear sight, the event's numbers must be the forecast's. A ritual a
## ward turned aside, or one aimed out of clear sight, is set aside (counted); a ritual that failed at resolution is a
## mismatch (nothing but a ward can stop a legal order).
static func check_forecasts(log: Dictionary, pending: Array, events: Array, turn: int) -> void:
	var out: Dictionary = log.forecast
	for p in pending:
		var found := {}
		var failed := {}
		for e in events:
			var n: Dictionary = e.get("numbers", {})
			var fids: Array = e.get("factions", [])
			if fids.is_empty() or String(fids[0]) != String(p.faction):
				continue
			var type := String(e.get("type", ""))
			if RITUAL_EVENTS.has(type) and String(n.get("army", "")) == String(p.army) and String(n.get("ritual", "")) == String(p.ritual):
				found = e
			elif type == "order_rejected" and String(e.get("phase", "")) == "rituals" and String(n.get("army", "")) == String(p.army):
				failed = e
		if not found.is_empty() and String(found.type) == "ritual_turned_aside":
			out.turned_aside += 1
			continue
		if not bool(p.clear):
			out.unseen += 1
			continue
		out.checks += 1
		var why := ""
		if not bool(p.ok):
			why = "the forecast refused an order the session accepted (%s)" % p.reason
		elif found.is_empty():
			why = "the forecast promised the ritual and the rituals phase did not cast it%s" % ((": " + str(failed.get("numbers", {}).get("reason", ""))) if not failed.is_empty() else "")
		else:
			var got: Dictionary = found.numbers
			var diff := []
			var keys: Array = p.numbers.keys()
			for k in got.keys():
				if not keys.has(k):
					keys.append(k)
			keys.sort()
			for k in keys:
				if FORECAST_SKIP.has(k):
					continue
				if JSON.stringify(p.numbers.get(k)) != JSON.stringify(got.get(k)):
					diff.append("%s: forecast %s, result %s" % [k, JSON.stringify(p.numbers.get(k)), JSON.stringify(got.get(k))])
			if not diff.is_empty():
				why = "numbers differ (%s)" % "; ".join(diff)
		if not why.is_empty():
			out.mismatches += 1
			if String(out.first).is_empty():
				out.first = "turn %d, %s's %s from %s: %s" % [turn, p.faction, p.ritual, p.army, why]


# --- the hit point ledger (band G13) ---------------------------------------------------------------------------

## Hit points move outside battles in six ways, each in an event: Mending Light, a ruler's own healing, Hallowed Land and
## the Forges, a blessing, a curse and blood paid. For every army that took part in no battle and kept the same fighters
## all turn, the change in its hit points must be exactly those events' sum. Returns [{"check": "hp_ledger", "detail"}].
## (Bleeding and the Blood Moon's healing back happen inside battles: the battle reports hold them, and every turn the
## invariants hold every fighter to 1..max hit points.)
static func hp_ledger(prev: GameState, state: GameState, events: Array, tally: Dictionary = {}) -> Array:
	var out := []
	if prev == null or not state.magic:
		return out
	var net := {}
	var touched := {}
	var transformed := {}
	var named := {}  # army id -> the types of the events that name it, for the report of a mismatch
	for e in events:
		var type := String(e.get("type", ""))
		var n: Dictionary = e.get("numbers", {})
		var armies: Array = e.get("armies", [])
		for aid in armies:
			if not named.has(String(aid)):
				named[String(aid)] = []
			named[String(aid)].append(type)
		if BATTLE_TYPES.has(type) or type == "recruited" or type == "summoned" or type == "summon_faded" or type == "vassal_joined" \
				or type == "ruler_died" or type == "ruler_arrived" or type == "sacrificed":
			for aid in armies:
				touched[String(aid)] = true
			for aid in n.get("destroyed", []):
				touched[String(aid)] = true
		# M4: a transformation or a node of the path changes its people's hit points (numbers.hp_total), and M2-6: so does a
		# sacrifice for Veteran Levies. All of the faction's armies are set aside that turn.
		if type == "transformed" or type == "sacrificed" or (type == "research_done" and int(n.get("hp_total", 0)) != 0):
			for fid in e.get("factions", []):
				transformed[String(fid)] = true
		match type:
			"mending":
				for h in n.get("healed", []):
					_add(net, String(h.get("army", "")), int(h.get("healed", 0)))
			"ruler_healed":
				if not armies.is_empty():
					_add(net, String(armies[0]), int(n.get("healed", 0)))
			"path_healed":
				for h in n.get("healed", []):
					_add(net, String(h.get("army", "")), int(h.get("after", 0)) - int(h.get("before", 0)))
			"blessing_healed":
				_add(net, String(n.get("army", "")), int(n.get("total", 0)))
			"curse_bit":
				for t in n.get("taken", []):
					_add(net, String(t.get("army", "")), int(t.get("to", 0)) - int(t.get("from", 0)))
			"blood_paid":
				_add(net, String(n.get("army", "")), -int(n.get("hp", 0)))
	for a in state.armies:
		var was := prev.find_army(a.id)
		if was == null or touched.has(a.id) or transformed.has(a.owner) or _members(was).size() != _members(a).size():
			continue
		var before := _hp(was)
		var after := _hp(a)
		tally["checks"] = int(tally.get("checks", 0)) + 1
		if after - before != int(net.get(a.id, 0)):
			tally["mismatches"] = int(tally.get("mismatches", 0)) + 1
			out.append({"check": "hp_ledger", "detail": "Army %s (%s) went from %d to %d hit points (%+d), but the events explain %+d (events naming it: %s)." % [
				a.id, a.owner, before, after, after - before, int(net.get(a.id, 0)), ", ".join(named.get(a.id, ["none"]))]})
	return out


static func _members(a: Army) -> Array:
	var out: Array = a.units.duplicate()
	if a.commander != null:
		out.append(a.commander)
	if a.ruler != null:
		out.append(a.ruler)
	return out


static func _hp(a: Army) -> int:
	var total := 0
	for u in _members(a):
		total += u.current_hp
	return total
