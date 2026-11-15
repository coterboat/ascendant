class_name AIMagic
extends RefCounted
## M5-10 (#121): how the computer plays magic (design/M5_MAGIC_FOG.md §10.2). Pure code: no nodes, no scenes, and no dice.
## Every choice is a rule with ties broken by id, so the same state always gives the same research, mages, rituals and
## orders. Like AIFog and AISieges, one instance is attached to a brain for each plan (attach ... end) and AIPlayer calls
## it behind one `has_magic` check, so with magic off none of this runs and games are the games of main. The only thing it
## keeps between plans is a note of its own last Far Sight (see learn), which never leaves the brain.
##
## What it does, in the order AIPlayer asks:
##   * The research plan (arcana_order, with AIPaths.sequence): its aligned school's tier I after its first ordinary
##     node, then the path as before; after the transformation the aligned tier II, tier III and mastery, then the rest of
##     the path, then the other school's tier I, tier II and mastery. The spellbook is the default: no SpellbookOrder.
##   * Mages as recruits (cast_profiles, mage_pressure, room_for_mage): AIPlayer's recruit value counts a mage by what
##     its spells would do over a battle, with the battle rules' own numbers; at most one mage for every MAGE_PER regular
##     units, and never more second-rank fighters (Volley and mages) than front-rank ones.
##   * Rituals (plan): at most one a turn from each army that holds anyway, never from an army that was ordered to
##     move, and never in a turn the capital needs its gold. The rules are in PRIORITY order and the first that
##     applies takes the best caster; rituals take at most RITUAL_SHARE of the gold the turn's troops leave.
##   * Tithe of Blood (sacrifice_picks, _pay): a Shaman's army pays in blood when it can give the price and keep two
##     thirds of its hit points, and no Shaman falls below the hit points Bloodbolt needs.
## Under fog the brain is handed its view, so everything read here is what a person in its seat is shown. Far Sight asks
## AIFog.unseen, the question scouting asks.

## Rituals take at most this share of the gold left after the troops the capital cannot do without (§10.2).
const RITUAL_SHARE_PCT := 40
const RITUAL_SHARE := RITUAL_SHARE_PCT / 100.0
## One mage for every this many regular units in an army, so its second rank is not exposed (§10.2). M5-11: 6 -> 4, the
## bottom of §13.3's range: the capital's garrison, where recruits stand, is small, and a cap of 6 kept the Crown at about
## 1% of its recruits being Adepts.
const MAGE_PER := 4
## A Shaman's army pays in blood only while it keeps this share of its hit points (§10.2: two thirds).
const TITHE_KEEP := 2.0 / 3.0
## A Far Sight that came to nothing is not tried on the same province again for this many turns (§10.2).
const SIGHT_MEMORY := 3
## The rituals, most important first (§10.2). The first rule that applies takes the best caster it can.
const PRIORITY := ["sanctum_ward", "dawn_blessing", "wake_the_greenwrath", "call_the_pack", "bloodrot", "blood_moon", "bastion", "far_sight"]
## The presets whose sacrifice picks start with Tithe of Blood in a game with magic (§10.2): no preset holds Feast.
const TITHE_FIRST := ["blood_of_the_fang"]
## The deepest a ward-ahead reaches: the capital with a rival province this many moves from it (§10.2).
const WARD_AHEAD := 2
## A rival's province this near the capital makes a pack worth calling: an enemy army within this many moves.
const PACK_REACH := 2

var ai = null  # the AIPlayer planning this turn (untyped: the two classes refer to each other)
## This plan's cast orders, in the order given, and the gold the ones paid in gold hold (AIPlayer._ritual_gold).
var casts: Array = []
var reserved := 0
var _budget := 0  # gold the rituals may still spend this plan
var _used := {}  # army id -> true once it casts
var _eligible: Array = []  # the armies that may cast, ruler first, then by id
var _group := {}  # the main army's group ({"loc", "armies"}), made once per plan

# What it remembers between plans: its own last Far Sight order, and the provinces where one came to nothing.
var _sight := {}  # {"province", "turn"}: ordered on the plan of that state turn
var _aside := {}  # province id -> the state turn of the plan whose Far Sight on it was turned aside or failed


# --- the data of the plan: research, mages and the sacrifice ---------------------------------------------

## `faction_id`'s arcana in the order the computer researches them on `branch_id`'s side of the fork (§10.2), or {}
## without magic data: {"aligned": [tier I, tier II, tier III, mastery] of the school its Oath opens, "other":
## [tier I, tier II, mastery] of the faction's other schools}. The aligned school is the one whose aligned Oath is
## `branch_id`'s; without a side, the faction's first school.
static func arcana_order(faction_id: String, branch_id: String) -> Dictionary:
	var schools := MagicRules.schools(faction_id)
	if schools.is_empty():
		return {}
	var aligned := String(schools[0])
	for sid in schools:
		if String(MagicRules.school_data(String(sid)).get("aligned_branch", "")) == branch_id and not branch_id.is_empty():
			aligned = String(sid)
			break
	var out := {"aligned": [], "other": []}
	for sid in schools:
		var nodes: Array = MagicRules.school_data(String(sid)).get("nodes", [])
		if nodes.size() < 4:
			continue
		if String(sid) == aligned:
			out.aligned = [nodes[0], nodes[1], nodes[3], nodes[2]]
		else:
			out.other.append_array([nodes[0], nodes[1], nodes[2]])
	return out


## The pick order of sacrifices in a game with magic (§10.2): Blood of the Fang puts Tithe of Blood first, since no
## preset holds Feast of Victory. Every other preset, and every game without magic, keeps `picks` as it is.
static func sacrifice_picks(state: GameState, preset_id: String, picks: Array) -> Array:
	if not MagicRules.has_magic(state) or not TITHE_FIRST.has(preset_id) or picks.has(MagicRules.TITHE_OF_BLOOD):
		return picks
	var out := [MagicRules.TITHE_OF_BLOOD]
	out.append_array(picks)
	return out


# --- mages as recruits (§10.2) ----------------------------------------------------------------------------

## Every faction's battle spells for the plan's rough guesses: {faction id: {"book": [spell ids, in the order its
## casters try them], "bonus": {school: mastery bonus of a mage}, "ruler_book": [the spells its ruler casts in battle, in
## the same order; #182]}} for each faction with a mage. The book is the
## spellbook with its switched-off spells and the spells not yet researched left out; a faction whose research is
## hidden (a rival in a fog view) casts the first tier I spell of its default spellbook, as the forecasts assume (§2.6).
static func cast_profiles(state: GameState) -> Dictionary:
	var out := {}
	if not MagicRules.has_magic(state):
		return out
	for f in state.factions:
		if MagicRules.mage_type(f.id) == null:
			continue
		var known := MagicRules.battle_spells(state, f.id, MagicRules.MAGE)
		var book := []
		var pages := MagicRules.spellbook(state, f.id)
		for sid in pages.order:
			if known.has(sid) and not pages.off.has(sid):
				book.append(String(sid))
		if known.is_empty():
			for sid in MagicRules.default_spellbook(f.id):
				if String(MagicRules.spell_data(String(sid)).get("tier", "")) == "I":
					book = [String(sid)]
					break
		var bonus := {}
		for school in MagicRules.schools(f.id):
			bonus[String(school)] = int(MagicRules.mastery_bonus(state, f.id, String(school), MagicRules.MAGE).value)
		# #182: the ruler's battle spells (the Ever-Regent's Sunlance and its schools' researched ones), its own spell first
		# as the spellbook's locked row, then the book's order without the switched-off ones.
		var ruler_spells := MagicRules.battle_spells(state, f.id, MagicRules.RULER)
		var ruler_book := []
		var own := String(MagicRules.ruler_magic(f.ruler_type).get("own_spell", "")) if f.has_ruler() else ""
		if ruler_spells.has(own):
			ruler_book.append(own)
		for sid in book:
			if ruler_spells.has(sid) and not ruler_book.has(sid):
				ruler_book.append(String(sid))
		out[f.id] = {"book": book, "bonus": bonus, "ruler_book": ruler_book}
	return out


## Whether Shield of Law has anything to cover when our units defend `province_id`: not behind a fort or on ground that
## gives a defence bonus, which the spell never covers (§5.2).
static func shield_ok(state: GameState, province_id: String) -> bool:
	var p := state.find_province(province_id) if state != null else null
	if p == null:
		return true
	return not p.has_fort and int(AutoBattleResolver.TERRAIN.get(p.terrain, {}).get("defense", 0)) <= 0


## Whether an army of `units` (the units it will hold, its mages among them) has room for one more mage (§10.2): at
## most one mage for every MAGE_PER regular units, so the second rank is never the bigger.
static func room_for_mage(units: Array) -> bool:
	var mages := 0
	var regulars := 0
	for u in units:
		if u.type.is_commander or u.type.is_ruler:
			continue
		if MagicRules.is_mage(u.type):
			mages += 1
		else:
			regulars += 1
	return (mages + 1) * MAGE_PER <= regulars


## The damage a round that side `s`'s mages are worth against `foe` (both AIPlayer._side_summary), by the rules' own
## numbers and the spread rule of §5.1: each mage in turn casts the first useful spell of its book that nobody has cast
## this round, and starts the book again when every useful one has been. A bolt is its damage; a hex or a shield is the
## damage its part moves, counted for each unit it covers (the units of the most numerous front-rank type with some left),
## which is what a hex takes off the enemy's hits and a shield takes off the hits on our units. Sunburst, which comes
## once a battle, is worth its first round over `rounds` (AIPlayer.ROUNDS_GUESS). A mage in a shielded second rank lasts
## longer, as Volley's does: `lasts` multiplies the whole (AIPlayer gives 1 + VOLLEY_SHIELD_VALUE x the share of the second
## rank the enemy cannot reach while the front rank is as big, otherwise 1). The two classes refer to each other, so the
## numbers come in as arguments rather than as AIPlayer's constants. #182: when side `s` fights with its ruler beside its mages
## (s.ruler_with[owner]), the ruler casts first each round (§5.1: "the Regent casts Sunlance, and the Adept casts Shield of Law"),
## so the mages' spread starts after its spell; the ruler's own cast is not counted (it is never recruited).
static func mage_pressure(s: Dictionary, foe: Dictionary, lasts: float, rounds: float) -> float:
	var total := 0.0
	var casts_by: Dictionary = s.get("casts", {})
	var mages: Dictionary = s.get("mages", {})
	for owner in mages:
		var profile: Dictionary = casts_by.get(owner, {})
		var book: Array = profile.get("book", [])
		if book.is_empty():
			continue
		var lead: Array = profile.get("ruler_book", []) if bool(s.get("ruler_with", {}).get(owner, false)) else []
		total += _round_value(int(mages[owner]), book, profile.get("bonus", {}), s, foe, rounds, lead)
	return total * lasts


## What `n` mages casting `book` are worth a round (mage_pressure). The spread rule is the resolver's: each mage casts the
## first useful spell nobody has cast this round, and once every useful spell has been cast, the first useful one again.
static func _round_value(n: int, book: Array, bonus: Dictionary, s: Dictionary, foe: Dictionary, rounds: float,
		lead: Array = []) -> float:
	var total := 0.0
	var done := {}
	var left := {}  # "<spell>|<type id>" -> units of that type still without the spell's part this round
	for sid in lead:  # #182: the ruler's cast this round, first: its first useful spell, which the mages then pass over
		var sp := MagicRules.spell_data(String(sid))
		if sp.has("round") or _cast_value(String(sid), sp, _bonus(bonus, sp), s, foe, left, false) <= 0.0:
			continue
		_cast_value(String(sid), sp, _bonus(bonus, sp), s, foe, left, true)
		done[sid] = true
		break
	for j in n:
		var pick := ""
		var again := ""
		for sid in book:
			var sp := MagicRules.spell_data(String(sid))
			if sp.has("round"):
				continue  # Sunburst: counted once, below
			if _cast_value(String(sid), sp, _bonus(bonus, sp), s, foe, left, false) <= 0.0:
				continue
			if not done.has(sid):
				pick = String(sid)
				break
			if again.is_empty():
				again = String(sid)
		if pick.is_empty():
			pick = again
		if pick.is_empty():
			break
		var pick_sp := MagicRules.spell_data(pick)
		total += _cast_value(pick, pick_sp, _bonus(bonus, pick_sp), s, foe, left, true)
		done[pick] = true
	for sid in book:
		var sp := MagicRules.spell_data(String(sid))
		if sp.has("round") and n > 0:
			total += _cast_value(String(sid), sp, _bonus(bonus, sp), s, foe, {}, false) / maxf(1.0, rounds)
	return total


## The mastery bonus of a mage in spell `sp`'s school.
static func _bonus(bonus: Dictionary, sp: Dictionary) -> int:
	return int(bonus.get(String(sp.get("school", "")), 0))


## The worth of one cast of `sid` (spell data `sp`) with `bonus` points of mastery: damage dealt or damage a part takes
## off. `left` tracks the units of each type a hex or a shield has not covered yet this round; `take` records this cast in it.
static func _cast_value(sid: String, sp: Dictionary, bonus: int, s: Dictionary, foe: Dictionary, left: Dictionary, take: bool) -> float:
	var nums := MagicRules.spell_numbers(sid, bonus)
	var ours := _defense_of(s)
	match String(sp.get("kind", "")):
		"bolt":
			return float(nums.value)
		"hex":
			var part := absf(float(sp.get("value", 0)))
			if sp.has("round"):
				# Sunburst: every enemy fighter in the front rank.
				var all := 0.0
				for k in foe.get("kinds", {}).values():
					if bool(k.get("front", false)):
						all += float(k.n) * _hex_saved(float(k.attack), ours, part)
				return all
			var group := _group_of(sid, foe, left)
			if group.is_empty():
				return 0.0
			var covered := mini(int(nums.count), int(group.n))
			if take:
				left[group.key] = int(group.n) - covered
			return float(covered) * _hex_saved(float(group.attack), ours, part)
		"shield":
			if not bool(s.get("shield_ok", true)):
				return 0.0
			var group := _group_of(sid, s, left)
			if group.is_empty():
				return 0.0
			var covered := mini(int(nums.count), int(group.n))
			var foes_n := 0.0
			var foe_attack := 0.0
			for k in foe.get("kinds", {}).values():
				if k.type.trait_id == AutoBattleResolver.MAGE or k.type.is_commander:
					continue
				foes_n += float(k.n)
				foe_attack += float(k.n) * float(k.attack)
			if foes_n <= 0.0:
				return 0.0
			foe_attack /= foes_n
			var defense := float(group.defense)
			var part := float(sp.get("value", 0))
			var per_attack := _hit_rate(foe_attack, defense) * _hit_damage(foe_attack, defense) \
				- _hit_rate(foe_attack, defense + part) * _hit_damage(foe_attack, defense + part)
			# Each enemy attack lands on a front-rank unit with the same chance, so a covered unit takes its share of them.
			var aimed := foes_n / maxf(1.0, float(s.get("front", 1)))
			if take:
				left[group.key] = int(group.n) - covered
			return float(covered) * aimed * maxf(0.0, per_attack)
	return 0.0


## The damage a hex of `part` attack takes off one attack of `attack` on `defense`: the expected damage before and after.
static func _hex_saved(attack: float, defense: float, part: float) -> float:
	return maxf(0.0, _hit_rate(attack, defense) * _hit_damage(attack, defense) \
		- _hit_rate(attack - part, defense) * _hit_damage(attack - part, defense))


## The most numerous front-rank type of `side` (an AIPlayer._side_summary) that `sid` has not covered yet this round, as
## {"key", "n" (units left), "attack", "defense"}, or {}. Ties go in the order the types were first met.
static func _group_of(sid: String, side: Dictionary, left: Dictionary) -> Dictionary:
	var best := {}
	for k in side.get("kinds", {}).values():
		if not bool(k.get("front", false)):
			continue
		var key := "%s|%s" % [sid, k.type.id]
		var n := int(left.get(key, k.n))
		if n <= 0:
			continue
		if best.is_empty() or n > int(best.n):
			best = {"key": key, "n": n, "attack": int(k.attack), "defense": int(k.get("defense", k.type.defense))}
	return best


## The chance one attack of `attack` hits `defense` by the battle rules (AutoBattleResolver.hit_chance, for a mean defense).
static func _hit_rate(attack: float, defense: float) -> float:
	return clampf(float(AutoBattleResolver.BASE_HIT) + float(AutoBattleResolver.HIT_PER_POINT) * (attack - defense),
		float(AutoBattleResolver.MIN_HIT), float(AutoBattleResolver.MAX_HIT)) / 100.0


## A side's mean defense, weighted by hit points, with Shield Wall's bonus while it has company (a _side_summary).
static func _defense_of(s: Dictionary) -> float:
	if float(s.hp) <= 0.0:
		return 0.0
	var total: float = s.def_hp
	if int(s.fighters) > 1:
		total += float(AutoBattleResolver.SHIELD_WALL_DEFENSE) * float(s.shield_hp)
	return total / float(s.hp)


## The damage of one hit of `attack` on `defense` by the battle rules, as a number to scale (not rounded to whole).
static func _hit_damage(attack: float, defense: float) -> float:
	return maxf(float(AutoBattleResolver.MIN_DAMAGE), ceilf(attack * 0.5) - floorf(defense * 0.25))


# --- one plan ---------------------------------------------------------------------------------------------

## Called by AIPlayer._begin on every plan: starts afresh and reads what last turn's Far Sight came to.
func attach(p_ai) -> void:
	ai = p_ai
	casts = []
	reserved = 0
	_budget = 0
	_used = {}
	_eligible = []
	_group = {}
	_learn()


## Lets go of the plan's state (AIPlayer calls it when the plan is done). What it remembers stays.
func end() -> void:
	ai = null
	casts = []
	_used = {}
	_eligible = []
	_group = {}


## Whether the Far Sight it ordered on the plan just before this one took effect: our own sight enchantment on that
## province, cast last turn. If not, the province is remembered as turned aside for SIGHT_MEMORY turns (§10.2). Nothing
## else is kept, and a brain without this memory (a loaded save) only tries once more.
func _learn() -> void:
	if _sight.is_empty() or ai == null or not MagicRules.has_magic(ai._state):
		return
	var turn: int = ai._state.current_turn
	if int(_sight.turn) + 1 != turn:
		if int(_sight.turn) < turn:
			_sight = {}
		return
	var took := false
	for e in ai._state.enchantments:
		if String(e.kind) == "sight" and String(e.faction) == ai._fid and String(e.province) == String(_sight.province) and int(e.cast_turn) == turn:
			took = true
	if not took:
		_aside[String(_sight.province)] = int(_sight.turn)
	_sight = {}


## The rituals of the turn, planned after the moves (an army that moves can't cast) and before the troops are bought (a
## ritual's gold is set aside first). Sets `casts` and `reserved`.
func plan() -> void:
	if ai == null or ai._me == null or not MagicRules.has_magic(ai._state):
		return
	if _crisis():
		return
	_budget = floori(RITUAL_SHARE * float(maxi(0, ai._me.gold - ai._gold_reserved)))
	_eligible = _eligible_armies()
	if _eligible.is_empty():
		return
	for ritual in PRIORITY:
		if MagicRules.knows(ai._state, ai._fid, ritual):
			_try(String(ritual))
	ai._ritual_gold = reserved


## True when the capital needs every gold piece for its troops: the essential recruits are the whole plan, so no ritual
## is paid, in gold or in blood (§10.2: rituals share what is left after them).
func _crisis() -> bool:
	return bool(ai._capital_short) or float(ai._home_rate) < float(ai.HOLD_TARGET[ai._level])


## The armies that may cast: those that hold anyway this turn (no move planned, and in a siege game no sally, storm or
## siege to keep), with a caster in them; our ruler's army first, then the others by id.
func _eligible_armies() -> Array:
	var out := []
	var armies: Array = []
	if ai._ruler != null:
		armies.append(ai._ruler)
	armies.append_array(ai._mine)
	for a in armies:
		if ai._moves.has(a.id):
			continue
		if ai._state.sieges and ai._sieges.engaged(a):
			continue
		if MagicRules.casters(ai._state, a).is_empty():
			continue
		out.append(a)
	return out


## Casts `ritual` once if the rule for it applies: the first of its proposals that an army can cast and pay for.
func _try(ritual: String) -> void:
	for p in _proposals(ritual):
		if _cast(ritual, p):
			return


## The places and reasons the rule for `ritual` proposes, best first: [{"target", "why", "only" (army ids, when the
## rule picks the caster itself)}].
func _proposals(ritual: String) -> Array:
	match ritual:
		"sanctum_ward":
			return _ward_proposals()
		"dawn_blessing":
			return _blessing_proposals()
		"wake_the_greenwrath":
			return _greenwrath_proposals()
		"call_the_pack":
			return _pack_proposals()
		"bloodrot":
			return _bloodrot_proposals()
		"blood_moon":
			return _moon_proposals()
		"bastion":
			return _bastion_proposals()
		"far_sight":
			return _sight_proposals()
	return []


# --- the rules (§10.2) ------------------------------------------------------------------------------------

## 1. Sanctum Ward: an own province is cursed; or (ward ahead) the capital is within WARD_AHEAD moves of a province a
## rival owns, that rival can curse, and the capital has no ward through next turn; or its capital was read by Far Sight
## last turn.
func _ward_proposals() -> Array:
	var st: GameState = ai._state
	var fid: String = ai._fid
	var cap: String = ai._me.capital
	var turn := st.current_turn + 1
	var out := []
	var cursed := []
	for e in st.enchantments:
		if String(e.kind) != "curse" or String(e.faction) == fid or e.get("ending", false) == true:
			continue
		var p := st.find_province(String(e.province))
		if p == null or p.owner != fid or _ward_through(p.id, turn) or cursed.has(p):
			continue
		cursed.append(p)
	cursed.sort_custom(func(a, b):
		if (a.id == cap) != (b.id == cap):
			return a.id == cap
		if a.income != b.income:
			return a.income > b.income
		return a.id < b.id)
	for p in cursed:
		out.append({"target": p.id, "why": "a rival's curse lies on %s" % p.name})
	var capital := st.find_province(cap)
	if capital != null and capital.owner == fid and not _ward_through(cap, turn + 1) and not out.any(func(o): return o.target == cap):
		var why := _ward_ahead_reason()
		if why.is_empty() and _read_by_far_sight(cap):
			why = "a rival's Far Sight read %s last turn" % capital.name
		if not why.is_empty():
			out.append({"target": cap, "why": why})
	return out


## Whether one of our wards on `pid` lasts through `turn`.
func _ward_through(pid: String, turn: int) -> bool:
	for e in ai._state.enchantments:
		if String(e.kind) == "ward" and String(e.faction) == ai._fid and String(e.province) == pid and int(e.until_turn) >= turn:
			return true
	return false


## "the Thornmane Clans own Wildmoor, 2 moves from Crownkeep, and can curse", or "": a rival that can curse owns a province
## within WARD_AHEAD of our capital.
func _ward_ahead_reason() -> String:
	var st: GameState = ai._state
	var cap: String = ai._me.capital
	for f in ai._sorted_factions():
		if f.id == ai._fid or not _can_curse(f.id):
			continue
		var near := []
		for p in ai._sorted_provinces():
			if p.owner == f.id and ai._d(p.id, cap) <= WARD_AHEAD:
				near.append(p)
		if not near.is_empty():
			near.sort_custom(func(a, b): return ai._d(a.id, cap) < ai._d(b.id, cap) or (ai._d(a.id, cap) == ai._d(b.id, cap) and a.id < b.id))
			return "the %s hold %s, %d %s from %s, and can curse" % [f.faction_name, near[0].name, ai._d(near[0].id, cap),
				"move" if ai._d(near[0].id, cap) == 1 else "moves", ai._province_name(cap)]
	return ""


## Whether `rival` can curse: its faction has the school of Blood and either its research shows Bloodrot (the research of
## every rival is public without fog) or it is hidden (a fog view), where a rival of the school is assumed to have it.
func _can_curse(rival: String) -> bool:
	if not MagicRules.faction_has_school(rival, "blood"):
		return false
	return AIFog.is_view(ai._state) or MagicRules.knows(ai._state, rival, "bloodrot")


## Whether a rival's Far Sight on `pid` was cast last turn (a sight enchantment of another faction, visible on our own
## province in our view).
func _read_by_far_sight(pid: String) -> bool:
	for e in ai._state.enchantments:
		if String(e.kind) == "sight" and String(e.faction) != ai._fid and String(e.province) == pid and int(e.cast_turn) >= ai._state.current_turn:
			return true
	return false


## 2. Dawn Blessing: the main army stands in an own province, will attack this turn or next, and the blessing covers fewer than half
## its fighters.
func _blessing_proposals() -> Array:
	var g := _main_group()
	if g.is_empty():
		return []
	var p: Province = ai._state.find_province(String(g.loc))
	if p == null or p.owner != ai._fid:
		return []
	# ARM-1 (design/ARM1_SPLIT_MERGE.md §2.1): a blessing is valued by the fighters it COVERS, not by the army ids it lists. The
	# group is worth blessing (or blessing again: the cast restarts a blessing and covers everyone in the armies it lists) when the
	# fighters it covers are fewer than half of the group's, however they came to be outside: an army with no blessing, or fighters
	# that joined a blessed one later (a muster, recruits). That is where the half-blessed morale is lost. Covered 0 casts.
	var fighters := 0
	var covered := 0
	for a in g.armies:
		var cov := MagicRules.blessing_coverage(ai._state, a)
		fighters += int(cov.total)
		covered += int(cov.covered)
	if covered * 2 >= fighters:
		return []
	var when := _attacks(g)
	if when.is_empty():
		return []
	return [{"target": p.id, "why": "the main army at %s will attack %s" % [p.name, when]}]


## 3. Wake the Greenwrath: a caster stands in a forest (the ritual itself refuses when it is already awake).
func _greenwrath_proposals() -> Array:
	var out := []
	for a in _eligible:
		var p: Province = ai._state.find_province(a.location)
		if p != null and p.terrain == MagicRules.FOREST:
			out.append({"target": p.id, "only": [a.id], "why": "a caster stands in the forest of %s" % p.name})
	return out


## 4. Call the Pack: no pack alive (the ritual refuses otherwise), and an enemy army within PACK_REACH of the caster.
func _pack_proposals() -> Array:
	var out := []
	for a in _eligible:
		var near := 99
		for e in ai._foes:
			near = mini(near, int(ai._d(e.location, a.location)))
		if near <= PACK_REACH:
			out.append({"target": a.location, "only": [a.id], "size": true,
				"why": "an enemy army is %d %s from %s" % [near, "move" if near == 1 else "moves", ai._province_name(a.location)]})
	return out


## 5. Bloodrot: the strongest enemy stack it can see within range, an enemy capital first. A province with a ward we can see,
## or already under our curse through next turn, is left alone.
func _bloodrot_proposals() -> Array:
	var st: GameState = ai._state
	var turn := st.current_turn + 1
	var stacks := {}
	for e in ai._foes:  # sorted by id
		if not stacks.has(e.location):
			stacks[e.location] = []
		stacks[e.location].append(e)
	var cands := []
	var pids: Array = stacks.keys()
	pids.sort()
	for pid in pids:
		var p := st.find_province(String(pid))
		if p == null or p.owner == ai._fid or not MagicRules.ward_on(st, p.id, ai._fid).is_empty():
			continue
		var cursed := false
		for e in st.enchantments:
			if String(e.kind) == "curse" and String(e.faction) == ai._fid and String(e.province) == p.id and int(e.until_turn) >= turn:
				cursed = true
		if cursed:
			continue
		var power: float = ai._power_units(ai._units(stacks[pid]), ai._units(ai._mine))
		cands.append({"target": p.id, "power": power, "capital": ai._is_enemy_capital(p.id),
			"why": "the strongest enemy stack we can see is at %s" % p.name})
	cands.sort_custom(func(a, b):
		if a.capital != b.capital:
			return a.capital
		if a.power != b.power:
			return a.power > b.power
		return a.target < b.target)
	return cands


## 6. Blood Moon: the main army will attack this turn.
func _moon_proposals() -> Array:
	var g := _main_group()
	if g.is_empty() or _attacks(g) != "this turn":
		return []
	for e in ai._state.enchantments:
		if String(e.kind) == "global" and String(e.faction) == ai._fid and int(e.until_turn) >= ai._state.current_turn + 1:
			return []  # our Moon is up through this turn's battles already
	return [{"target": "", "why": "the main army at %s attacks this turn" % ai._province_name(String(g.loc))}]


## 7. Bastion: our highest-income frontier province without a fort, while we have raised fewer than the cap.
func _bastion_proposals() -> Array:
	var st: GameState = ai._state
	if ai._me.bastions.size() >= MagicData.BASTION_CAP:
		return []
	var cands := []
	for p in ai._sorted_provinces():
		if p.owner != ai._fid or p.has_fort:
			continue
		var frontier := false
		for n in p.neighbors:
			var q := st.find_province(String(n))
			if q != null and q.owner != ai._fid:
				frontier = true
		if frontier:
			cands.append(p)
	cands.sort_custom(func(a, b): return a.income > b.income or (a.income == b.income and a.id < b.id))
	return cands.map(func(p): return {"target": p.id, "why": "%s, which earns %d gold, is on our frontier and has no fort" % [p.name, p.income]})


## 8. Far Sight (fog only): the objective, or else an enemy capital, if it is out of our sight and no Far Sight on it
## came to nothing in the last SIGHT_MEMORY turns.
func _sight_proposals() -> Array:
	var st: GameState = ai._state
	if not AIFog.is_view(st):
		return []
	var out := []
	var targets := []
	# The objective of the plan (AIFog.objective's, made from the main army: by now every free army has its job): the army a
	# stand-off hunts, otherwise the enemy capital nearest the main army.
	var objective := ""
	if not ai._hunt.is_empty():
		objective = String(ai._hunt.pid)
	else:
		var g := _main_group()
		if not g.is_empty():
			objective = String(ai._objective_for(String(g.loc)))
	if not objective.is_empty():
		targets.append(objective)
	var caps := []
	for f in ai._sorted_factions():
		if f.id != ai._fid:
			caps.append(String(f.capital))
	caps.sort_custom(func(a, b): return ai._d(ai._me.capital, a) < ai._d(ai._me.capital, b) or (ai._d(ai._me.capital, a) == ai._d(ai._me.capital, b) and a < b))
	for pid in caps:
		if not targets.has(pid):
			targets.append(pid)
	for pid in targets:
		var p := st.find_province(String(pid))
		if p == null or p.owner == ai._fid or not ai._fog.unseen(String(pid)):
			continue
		if _aside.has(pid) and st.current_turn - int(_aside[pid]) <= SIGHT_MEMORY:
			continue
		out.append({"target": p.id, "why": "%s is out of our sight" % p.name})
	return out


# --- the main army ----------------------------------------------------------------------------------------

## The strongest group of our armies standing in one province: {"loc", "armies"}, or {}. Ties go to the lower province id.
func _main_group() -> Dictionary:
	if not _group.is_empty():
		return _group
	var by_loc := {}
	for a in ai._mine:
		if not by_loc.has(a.location):
			by_loc[a.location] = []
		by_loc[a.location].append(a)
	var best := {}
	var best_power := -1.0
	var locs: Array = by_loc.keys()
	locs.sort()
	for loc in locs:
		var power := 0.0
		for a in by_loc[loc]:
			power += ai._army_power(a)
		if power > best_power + 0.000001:
			best = {"loc": String(loc), "armies": by_loc[loc]}
			best_power = power
	_group = best
	return best


## "this turn" when an army of the group is ordered into a province with an enemy army, a garrison or an enemy capital,
## "next turn" when the group will end the turn next to one, otherwise "".
func _attacks(g: Dictionary) -> String:
	for a in g.armies:
		if not ai._moves.has(a.id):
			continue
		var dest := String(ai._moves[a.id])
		if not ai._foes_at(dest).is_empty() or ai._holds.has(dest) or ai._is_enemy_capital(dest):
			return "this turn"
	var end := String(g.loc)
	if not g.armies.is_empty():
		end = String(ai._moves.get(g.armies[0].id, g.loc))
	for e in ai._foes:
		if ai._d(end, e.location) <= 1:
			return "next turn"
	for f in ai._state.factions:
		if f.id != ai._fid and f.id != IndependentData.FACTION_ID and ai._d(end, f.capital) <= 1 and ai._state.find_province(f.capital).owner != ai._fid:
			return "next turn"
	return ""


# --- casting ----------------------------------------------------------------------------------------------

## Casts `ritual` for proposal `p` if an eligible army can: the best caster (blood-paid first, then the higher mastery, then
## the earlier army) that the ritual's own checks accept (MagicRules.check_cast) and that we can pay. True when it did.
func _cast(ritual: String, p: Dictionary) -> bool:
	var st: GameState = ai._state
	var fid: String = ai._fid
	var best := {}
	for a in _eligible:
		if _used.has(a.id) or (p.has("only") and not p.only.has(a.id)):
			continue
		var caster := MagicRules.caster_for(st, fid, a, ritual)
		if caster.is_empty():
			continue
		var pay := _pay(ritual, a, caster, bool(p.get("size", false)))
		if pay.is_empty():
			continue
		var order := CastOrder.new(ritual, a.id, String(p.target), String(pay.pay), int(pay.size))
		if not MagicRules.check_cast(st, fid, order, casts).is_empty():
			continue
		var school := String(MagicRules.spell_data(ritual).get("school", ""))
		var bonus := 0 if school == MagicData.COMMON else int(MagicRules.mastery_bonus(st, fid, school, String(caster.kind)).value)
		var blood := 1 if pay.pay == CastOrder.BLOOD else 0
		if best.is_empty() or blood > int(best.blood) or (blood == int(best.blood) and bonus > int(best.bonus)):
			best = {"order": order, "army": a, "caster": caster, "pay": pay, "blood": blood, "bonus": bonus}
	if best.is_empty():
		return false
	var order: CastOrder = best.order
	casts.append(order)
	_used[best.army.id] = true
	if order.pay == CastOrder.GOLD:
		_budget -= int(best.pay.gold)
		reserved += int(best.pay.gold)
	if ritual == "far_sight":
		_sight = {"province": order.target, "turn": st.current_turn}
	_report(ritual, order, best, String(p.why))
	return true


## How `army` (with `caster`) pays for `ritual`: {"pay", "size", "gold" (what it holds back of the budget)} or {} when it can't:
## in blood when a Shaman's army can give the price and keep two thirds of its hit points (Tithe of Blood), otherwise in gold
## within what rituals may spend. Call the Pack's size is the most wolves that can be paid for (`sized`), at least the least.
func _pay(ritual: String, army: Army, caster: Dictionary, sized: bool) -> Dictionary:
	var st: GameState = ai._state
	var fid: String = ai._fid
	var least := 0
	var most := 0
	var each := int(MagicRules.spell_data(ritual).get("cost", 0))
	if sized:
		var sizes := MagicRules.pack_sizes(st, fid, army, ritual)  # CW-5: the pack's own ritual (Raise the Snuffed too)
		least = int(sizes[0])
		most = int(sizes[1])
	var tithe: bool = String(caster.kind) == MagicRules.MAGE and RulerRules.has_mandate(st, fid, MagicRules.TITHE_OF_BLOOD)
	if sized:
		# The biggest pack either purse can pay for: blood when it pays for as many wolves as gold would, else gold.
		var by_gold := mini(most, _budget / maxi(1, each))
		var by_blood := 0
		if tithe:
			for size in range(mini(most, _blood_room(army) / maxi(1, each)), least - 1, -1):
				if _blood_ok(army, size * each * MagicData.BLOOD_PER_GOLD):
					by_blood = size
					break
		if by_blood >= least and by_blood > 0 and by_blood >= by_gold:
			return {"pay": CastOrder.BLOOD, "size": by_blood, "gold": 0}
		if by_gold >= least and by_gold > 0:
			return {"pay": CastOrder.GOLD, "size": by_gold, "gold": by_gold * each}
		return {}
	if tithe and each > 0 and _blood_ok(army, each * MagicData.BLOOD_PER_GOLD):
		return {"pay": CastOrder.BLOOD, "size": 0, "gold": 0}
	if each <= _budget:
		return {"pay": CastOrder.GOLD, "size": 0, "gold": each}
	return {}


## The hit points the regular units of `army` hold now and could hold at most: {"now", "most"}. They are the units that can
## give blood (MagicRules.blood_plan): not summoned creatures, commanders or rulers.
func _blood_pool(army: Army) -> Dictionary:
	var now := 0
	var most := 0
	for u in army.units:
		if not (u.type.summoned or u.type.is_commander or u.type.is_ruler):
			now += u.current_hp
			most += RulerRules.unit_max_hp(ai._state, u)
	return {"now": now, "most": most}


## The most hit points `army` may give and still hold at least TITHE_KEEP of its hit points: measured against what it could
## hold at full health, so a garrison bled once is not bled again before it has healed.
func _blood_room(army: Army) -> int:
	var pool := _blood_pool(army)
	return maxi(0, int(pool.now) - int(ceil(float(pool.most) * TITHE_KEEP - 0.000001)))


## Whether `army` can pay `hp` in blood under the two-thirds rule, one soldier at a time (MagicRules.blood_plan), with no
## mage left too weak to cast Bloodbolt.
func _blood_ok(army: Army, hp: int) -> bool:
	if hp <= 0 or hp > _blood_room(army):
		return false
	var plan := MagicRules.blood_plan(ai._state, army.id, hp)
	if not plan.ok:
		return false
	var need := int(MagicRules.spell_data("bloodbolt").get("min_caster_hp", 0))
	for g in plan.gives:
		if MagicRules.is_mage_id(String(g.type)) and int(g.to) < need:
			return false
	return true


## Counts the cast and says what it does and why, in plain words.
func _report(ritual: String, order: CastOrder, best: Dictionary, why: String) -> void:
	var st: GameState = ai._state
	var army: Army = best.army
	var name := MagicRules.spell_name(ritual)
	var where := " on %s" % ai._province_name(order.target) if not order.target.is_empty() else ""
	var from := "%s at %s" % [String(best.caster.name) if String(best.caster.kind) == MagicRules.RULER else "the %s" % String(best.caster.name), ai._province_name(army.location)]
	var price := ""
	if order.pay == CastOrder.BLOOD:
		var hp := int(MagicRules.price(st, ai._fid, ritual, order.size).gold) * MagicData.BLOOD_PER_GOLD
		price = "paid in blood (%d hit points from the army)" % hp
	else:
		price = "%d gold" % int(best.pay.gold)
	var size := ", %d %s" % [order.size, String(MagicRules.pack_words(ritual).get("many", "wolves"))] if order.size > 0 else ""  # CW-5
	ai._note_top("Casting %s%s%s, from %s, %s: %s." % [name, where, size, from, price, why])
	ai._stats["rituals"] = int(ai._stats.get("rituals", 0)) + 1
	var key := "cast_" + ritual
	ai._stats[key] = int(ai._stats.get(key, 0)) + 1
	if order.pay == CastOrder.BLOOD:
		ai._stats["blood_paid"] = int(ai._stats.get("blood_paid", 0)) + 1


## The cast orders to hand over, checked once more against the plan's state in the order given (the cost of a surprise is a
## refused order): those whose army holds in the final orders `out` and that MagicRules.check_cast accepts.
func checked(out: Array) -> Array:
	var moving := {}
	for o in out:
		if o is MoveOrder:
			moving[o.army_id] = true
		elif o is SiegeOrder and not o.army_id.is_empty():
			moving[o.army_id] = true
	var kept := []
	for o in casts:
		if moving.has(o.army_id) or not MagicRules.check_cast(ai._state, ai._fid, o, kept).is_empty():
			ai._stats["dropped_invalid"] = int(ai._stats.get("dropped_invalid", 0)) + 1
			continue
		kept.append(o)
	if kept.size() != casts.size():
		reserved = MagicRules.queued_gold(ai._state, ai._fid, kept)  # a cast was dropped: its gold goes back to the troops
		ai._ritual_gold = reserved
	return kept
