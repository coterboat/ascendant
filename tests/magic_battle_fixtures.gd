extends RefCounted
## Constructed battles for the M5-7 tests (#118): a game with magic, its armies built by hand, its spells
## researched with AscensionRules.with_nodes and its enchantments written by hand (M5-6 writes them in a real
## game). Pure: nothing here changes a rule.

const CROWN := "kingdom"
const CLANS := "beasts"
const REGENT := {"ruler": "ever_regent", "mandates": []}
const KING := {"ruler": "aurel_king", "mandates": []}
const AVATAR := {"ruler": "thornmane_avatar", "mandates": []}
const FANG := {"ruler": "fang_chieftain", "mandates": []}


## A magic game with no armies but the rulers' own (at their capitals; a living ruler always has its army).
## `builds` as GameState.with_magic takes them (King Corvane and the Ninth Fang by default: neither casts in
## battle). Neither faction owns a mandate unless `mandates` says so ({fid: [ids]}).
static func game(builds: Dictionary = {}, mandates: Dictionary = {}) -> GameState:
	var b := {CROWN: KING, CLANS: FANG}
	for fid in builds:
		b[fid] = builds[fid]
	var s := GameState.with_magic(7, b, [])
	var keep: Array[Army] = []
	for a in s.armies:
		if a.ruler != null:
			keep.append(a)
	s.armies = keep
	for i in s.factions.size():
		var ruler := RulerRules.ruler_army(s, s.factions[i].id)
		if ruler != null:
			ruler.id = "%s-%d" % [s.factions[i].id, 9]
			s.next_army_ids[s.factions[i].id] = 10
	for f in s.factions:
		f.mandates = mandates.get(f.id, []).duplicate()
	return s


## `s` with `ids` researched by `fid` (path and arcana nodes alike).
static func with_nodes(s: GameState, fid: String, ids: Array) -> GameState:
	return AscensionRules.with_nodes(s, fid, ids)


## `fid`'s kept power set to `kept`, its ruler's stats refreshed, and its ruler army moved to `location`.
static func ruler_at(s: GameState, fid: String, location: String, kept: int = -1) -> Army:
	var f := s.find_faction(fid)
	if kept >= 0:
		f.kept_power = kept
	RulerRules.refresh_ruler_type(f)
	var a := RulerRules.ruler_army(s, fid)
	a.ruler = Unit.new(f.ruler_unit_type, fid)
	a.location = location
	return a


## An army of `fid` at `location` made of `type_ids`: roster units (mages included), the commander, and the
## summoned creatures (thornwolves, greenwrath). Every unit at its full maximum hp. Added to the state.
static func army(s: GameState, fid: String, id: String, location: String, type_ids: Array) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = fid
	a.location = location
	var f := s.find_faction(fid)
	for type_id in type_ids:
		if f.commander_type != null and type_id == f.commander_type.id:
			a.commander = Unit.new(f.commander_type, fid)
			continue
		var ut: UnitType = TurnResolver.recruitable_type(f, type_id)
		if ut == null:
			ut = MagicRules.summon_type(type_id)
		var u := Unit.new(ut, fid)
		u.current_hp = RulerRules.unit_max_hp(s, u)
		a.units.append(u)
	s.armies.append(a)
	return a


## An enchantment written by hand, in GameState.enchantments' saved form (MagicRules.ENCHANTMENT_KEYS).
static func enchant(s: GameState, ritual: String, fid: String, province: String = "", armies: Array = []) -> Dictionary:
	var f := s.find_faction(fid)
	f.enchant_counter += 1
	var e := {"id": "%s-e%d" % [fid, f.enchant_counter], "ritual": ritual, "faction": fid,
		"kind": String(MagicRules.spell_data(ritual).kind), "province": province, "armies": armies.duplicate(),
		"cast_turn": maxi(1, s.current_turn), "until_turn": maxi(1, s.current_turn) + 2, "bonus": 0, "ending": false}
	s.enchantments.append(e)
	s.enchantments.sort_custom(func(x, y): return String(x.id) < String(y.id))
	return e


## The spellbook `order` with `off` switched off, set as a SpellbookOrder would.
static func spellbook(s: GameState, fid: String, order: Array, off: Array = []) -> void:
	var o := SpellbookOrder.new(order, off)
	MagicRules.set_spellbook(s, fid, o)


## Fights one battle with the real resolver, recording its log: {"result", "sides", "log"}. `kind`
## "province" (in `where`, with `defender` holding it, or "" when everyone arrived) or "border" ("a|b").
static func fight(s: GameState, armies: Array, where: String, defender: String, seed_value: int, kind := "province") -> Dictionary:
	var r := AutoBattleResolver.fight(_sides(armies), _ctx(s, where, defender, kind), SeededRNG.new(seed_value), true)
	r["state"] = s
	return r


## The same battle through resolve_battle (the winner's losses applied, the bleed closed, Feast of Victory):
## the BattleResolver result, with "log" and "report".
static func resolve(s: GameState, armies: Array, where: String, defender: String, seed_value: int, kind := "province") -> Dictionary:
	var ctx := _ctx(s, where, defender, kind)
	var battle := {"kind": kind, "provinces": ctx.province_ids, "defender": defender, "sides": _sides(armies), "state": s}
	return AutoBattleResolver.new().resolve_battle(battle, SeededRNG.new(seed_value))


static func _sides(armies: Array) -> Array:
	var by_faction := {}
	for a in armies:
		if not by_faction.has(a.owner):
			by_faction[a.owner] = []
		by_faction[a.owner].append(a)
	var fids: Array = by_faction.keys()
	fids.sort()
	var sides := []
	for fid in fids:
		sides.append({"faction": fid, "armies": by_faction[fid]})
	return sides


static func _ctx(s: GameState, where: String, defender: String, kind: String) -> Dictionary:
	var pids: Array = Array(where.split("|")) if kind == "border" else [where]
	return {"kind": kind, "defender": defender, "province": s.find_province(pids[0]) if kind == "province" else null,
		"province_ids": pids, "state": s}


## The log's fighter ids of `type_id`.
static func fighters_of(battle_log: Dictionary, type_id: String) -> Array:
	var out := []
	for f in battle_log.fighters:
		if f.type == type_id:
			out.append(int(f.id))
	return out


## The log's events of type `t` (in round `n` when given).
static func events(battle_log: Dictionary, t: String, n: int = 0) -> Array:
	return battle_log.events.filter(func(e): return e.t == t and (n == 0 or int(e.get("n", 0)) == n))
