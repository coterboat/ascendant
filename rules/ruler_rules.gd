class_name RulerRules
## The ruler and mandate rules (M2 "the ruler", design/M2_RULER.md §1, §2, §9). Pure functions over
## GameState and the data in data/rulers.gd, data/mandates.gd and data/build_presets.gd: no nodes, no
## scenes, no randomness. This is the single source battles, the resolver, forecasts, breakdowns and
## screens read, so a number can never disagree with itself. Player-facing text: RulesCodex "ruler*",
## "succession*", "mandate*", "ability_*" and "build*".
##
## Rulers are OPT-IN at game setup for now (director's note on #29): GameState.new(seed) is the M1
## game, and GameState.with_rulers(seed, builds) gives every faction a ruler (Faction.has_ruler()).
##
## Reading a faction's ruler (for M2-2 .. M2-7):
##   has_rulers(state)                      any faction has a ruler
##   kept_power(state, fid)                 0..10
##   mandates(state, fid), has_mandate(state, fid, mandate_id)
##   ruler_army(state, fid), ruler_unit(state, fid)
##                                          the living ruler's army / Unit (null when none on the map)
##   current_name(state, fid)               "King Corvane I"
##   build_of(state, fid)                   {"ruler", "ruler_name", "kept_power", "mandates", "status"}
##   ruler_stats(ruler_id, kept, gen)       hp, attack, defense, morale, battle rank, ability rank...
##   unit_stats(state, fid, unit_type_id)   a roster unit's numbers with the faction's mandates
## Builds, before turn 1:
##   build_errors(fid, build)               plain-language reasons a build is illegal ([] if legal)
##   apply_build(state, fid, build)         sets the ruler, kept power and mandates; places its army
## A build is {"ruler": ruler id, "mandates": [mandate ids, in the order taken]}; anywhere a build is
## taken, a preset id (BuildPresetData) may stand in for one.
## Death and succession (M2-3, #31; TurnResolver calls these):
##   has_living_ruler(state, fid)           alive and on the map (no ability, ruler morale or sacrifice otherwise)
##   ruler_alive(state, fid)                alive, wherever it is (M5: a view may not know where; §2.7)
##   record_death(state, fid, turn)         dead; the successor falls due at the end of turn + delay
##   succession_info(state, fid)            who succeeds a dead ruler, where, when, with what kept power
##   crown_successor(state, fid, turn)      the due successor arrives at the capital, if the faction holds it
##   heal_ruler, apply_mending_light        the rulers phase's healing
##   death_text, arrival_text, waiting_text, healed_text, mending_text   the turn report's sentences
## Mid-game sacrifice (M2-6, #34; the sacrifice phase, OrderBook and the sacrifice dialog call these):
##   sacrifice_cost(mandate_id)             the mandate's price + MandateData.SACRIFICE_PREMIUM
##   sacrifice_check(state, fid, mid, already)   {} or {"code", "reason"}: living ruler, own list, not owned, power, one per turn
##   apply_sacrifice(state, fid, mid, turn) the effect: kept power, mandate, record, ruler hp, Veteran Levies
##   state_after_orders(state, fid, orders) the state a faction's other orders are checked against
##   successor_countdown, countdown_text    "heir in 2 turns" while a successor is pending
## Battles (M2-2, #30; AutoBattleResolver reads these with unit_stats and unit_max_hp):
##   battle_effects(state, fid)             base hit chance, Blood Frenzy, Iron Discipline, Feast, battle mandates
##   dread_value(state, fid)                the morale the Great Thornmane's Dread takes from every enemy side
##   mandate_battle_text(mid)               what a battle mandate does, for the battle report
##   fill_regular_units(state, fid)         the starting army at its maximum hp (Veteran Levies)

const ALIVE := "alive"
const DEAD := "dead"

const ROMAN := [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"],
	[40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
const ORDINAL_UNITS := ["First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth"]
const ORDINAL_TEENS := ["Tenth", "Eleventh", "Twelfth", "Thirteenth", "Fourteenth", "Fifteenth", "Sixteenth",
	"Seventeenth", "Eighteenth", "Nineteenth"]
const TENS := ["Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
const TENS_ORDINAL := ["Twentieth", "Thirtieth", "Fortieth", "Fiftieth", "Sixtieth", "Seventieth", "Eightieth", "Ninetieth"]

## Player-facing names of the stats a ruler has (the breakdown titles use them).
const STAT_NAMES := {"hp": "Maximum hit points", "attack": "Attack", "defense": "Defense", "cost": "Recruit cost", "morale": "Morale"}


# --- data lookups ---------------------------------------------------------------------------------

static func ruler_data(ruler_id: String) -> Dictionary:
	for r in RulerData.RULERS:
		if r.id == ruler_id:
			return r
	return {}


static func mandate_data(mandate_id: String) -> Dictionary:
	for m in MandateData.MANDATES:
		if m.id == mandate_id:
			return m
	for m in MandateData.PATH_MANDATES:  # M4-2: the mandates a transformation opens (sacrifice only)
		if m.id == mandate_id:
			return m
	return {}


static func ability_data(ruler_id: String) -> Dictionary:
	return RulerData.ABILITIES.get(ruler_data(ruler_id).get("ability", ""), {})


## The preset with this id, with its "faction" added, or {}.
static func preset_data(preset_id: String) -> Dictionary:
	for fid in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[fid]:
			if p.id == preset_id:
				var out: Dictionary = p.duplicate(true)
				out["faction"] = fid
				return out
	return {}


## The rulers `faction_id` can choose, in data order.
static func rulers_for(faction_id: String) -> Array:
	var out := []
	for r in RulerData.RULERS:
		if r.faction == faction_id:
			out.append(r.id)
	return out


## The mandates `faction_id` can take: the shared ones, then its own, in data order (§2.1): the pre-game
## build list. M4-2: given a `state` with paths, the list a ruler sacrifices from mid-game also has the
## mandates the faction's transformation opened (MandateData.PATH_MANDATES), last. A forsworn mandate stays
## on the list, so the sacrifice dialog can show why it can't be bought (sacrifice_check).
static func available_mandates(faction_id: String, state: GameState = null) -> Array:
	var shared := []
	var own := []
	for m in MandateData.MANDATES:
		if String(m.faction).is_empty():
			shared.append(m.id)
		elif m.faction == faction_id:
			own.append(m.id)
	var opened := []
	if state != null:
		for mid in AscensionRules.opened_mandates(state, faction_id):
			if String(mandate_data(mid).get("faction", "")) == faction_id:
				opened.append(mid)
	return shared + own + opened


## The faction's preset dictionaries, in data order (an AI seat rolls an index into this list).
static func presets_for(faction_id: String) -> Array:
	return BuildPresetData.PRESETS.get(faction_id, []).duplicate(true)


## Id of the faction's balanced preset: the build a game with rulers gives a faction that chose none.
static func balanced_preset(faction_id: String) -> String:
	for p in BuildPresetData.PRESETS.get(faction_id, []):
		if p.style == BuildPresetData.BALANCED:
			return p.id
	return ""


## The build a preset stands for: {"preset", "ruler", "mandates"}, or {} for an unknown id.
static func preset_build(preset_id: String) -> Dictionary:
	var p := preset_data(preset_id)
	if p.is_empty():
		return {}
	return {"preset": p.id, "ruler": p.ruler, "mandates": p.mandates.duplicate()}


static func mandate_name(mandate_id: String) -> String:
	return String(mandate_data(mandate_id).get("name", "an unknown mandate"))


static func mandate_cost(mandate_id: String) -> int:
	return int(mandate_data(mandate_id).get("cost", 0))


## "mortal line", "undying" or "god".
static func kind_name(ruler_id: String) -> String:
	return String(RulerData.KINDS.get(ruler_data(ruler_id).get("kind", ""), {}).get("name", ""))


## "front" or "second" (§1.6). M2-2 puts a second-rank ruler behind the front, like Volley units.
static func battle_rank(ruler_id: String) -> String:
	return String(ruler_data(ruler_id).get("battle_rank", "front"))


## The ruler's one-line description for cards and tooltips: "mortal line, fights in the front rank".
static func kind_line(ruler_id: String) -> String:
	return "%s, %s" % [kind_name(ruler_id), RulerData.BATTLE_RANKS.get(battle_rank(ruler_id), "")]


# --- a ruler's numbers (§1.1-1.4) -----------------------------------------------------------------

## {"base", "gain", "per", "from_kept"} for `stat` ("hp", "attack" or "defense") at kept power `kept`:
## the stat is base + from_kept, where from_kept = gain x (kept / per, rounded down) (§1.3).
static func stat_parts(ruler_id: String, stat: String, kept: int) -> Dictionary:
	var spec: Dictionary = ruler_data(ruler_id).get("stats", {}).get(stat, {})
	if spec.is_empty():
		return {"base": 0, "gain": 0, "per": 1, "from_kept": 0}
	var per := maxi(1, int(spec.per))
	var k := clampi(kept, 0, RulerData.POWER_POOL)
	return {"base": int(spec.base), "gain": int(spec.gain), "per": per, "from_kept": int(spec.gain) * floori(float(k) / per)}


static func stat_value(ruler_id: String, stat: String, kept: int) -> int:
	var parts := stat_parts(ruler_id, stat, kept)
	return parts.base + parts.from_kept


## 1 + kept power / 3, rounded down: rank 1 at 0-2 kept, 2 at 3-5, 3 at 6-8, 4 at 9-10 (§1.1).
static func ability_rank(kept: int) -> int:
	var k := clampi(kept, 0, RulerData.POWER_POOL)
	return clampi(1 + floori(float(k) / RulerData.ABILITY_RANK_PER), 1, RulerData.MAX_ABILITY_RANK)


## The ruler's ability effect at `rank` (gold, hp healed, morale taken, recruits), from §1.4.
static func ability_value(ruler_id: String, rank: int) -> int:
	var values: Array = ability_data(ruler_id).get("values", [])
	if values.is_empty():
		return 0
	return int(values[clampi(rank, 1, values.size()) - 1])


static func ability_name(ruler_id: String) -> String:
	return String(ability_data(ruler_id).get("name", ""))


## The ability's rule at `rank`, with the ruler's name: "In the income phase, the province King
## Corvane I is in earns 3 more gold, if you own it."
static func ability_text(ruler_id: String, rank: int, generation: int = 1) -> String:
	var effect := String(ability_data(ruler_id).get("effect", ""))
	return effect.format({"ruler": ruler_name(ruler_id, generation), "value": ability_value(ruler_id, rank)})


## Short form for labels: "+3 gold", "heal 6", "-1 enemy morale", "2 recruits in the field" ("1 recruit
## in the field": the word after the number agrees with it).
static func ability_short(ruler_id: String, rank: int) -> String:
	var template := String(ability_data(ruler_id).get("short", ""))
	var value := ability_value(ruler_id, rank)
	var words := template.split(" ")
	var at := words.find("{value}")
	if value == 1 and at >= 0 and at + 1 < words.size() and words[at + 1].ends_with("s"):
		words[at + 1] = words[at + 1].trim_suffix("s")
	return " ".join(words).format({"value": value})


## Everything about a ruler at kept power `kept`: {"ruler", "name", "kept_power", "hp", "attack",
## "defense", "morale" (its own, when it fights with no regular units), "morale_bonus" (to its side
## while it stands), "battle_rank", "kind", "ability", "ability_name", "ability_rank", "ability_value"}.
static func ruler_stats(ruler_id: String, kept: int, generation: int = 1) -> Dictionary:
	var r := ruler_data(ruler_id)
	var rank := ability_rank(kept)
	return {
		"ruler": ruler_id, "name": ruler_name(ruler_id, generation), "kept_power": clampi(kept, 0, RulerData.POWER_POOL),
		"hp": stat_value(ruler_id, "hp", kept), "attack": stat_value(ruler_id, "attack", kept),
		"defense": stat_value(ruler_id, "defense", kept), "morale": int(r.get("morale", 0)),
		"morale_bonus": RulerData.RULER_MORALE, "battle_rank": battle_rank(ruler_id), "kind": String(r.get("kind", "")),
		"ability": String(r.get("ability", "")), "ability_name": ability_name(ruler_id), "ability_rank": rank,
		"ability_value": ability_value(ruler_id, rank),
	}


## The name of generation `generation` (1 = the first ruler): "King Corvane I", "King Corvane II",
## "the Ninth Fang", "the Tenth Fang"; the Ever-Regent and the Great Thornmane keep their names.
static func ruler_name(ruler_id: String, generation: int = 1) -> String:
	var r := ruler_data(ruler_id)
	if r.is_empty():
		return "an unknown ruler"
	var naming: Dictionary = r.get("naming", {})
	var g := maxi(1, generation)
	match String(naming.get("style", "fixed")):
		"regnal":
			return String(naming.ruler) % roman(g)
		"ordinal":
			return String(naming.ruler) % ordinal_word(int(naming.get("first", 1)) + g - 1)
	return String(r.name)


## The successor's name before taking over: "Corvane II" (crowned as King Corvane II), "the Tenth
## Fang". Rulers that come back as themselves keep their names.
static func heir_name(ruler_id: String, generation: int) -> String:
	var naming: Dictionary = ruler_data(ruler_id).get("naming", {})
	if String(naming.get("style", "")) == "regnal" and naming.has("heir"):
		return String(naming.heir) % roman(maxi(1, generation))
	return ruler_name(ruler_id, generation)


## Who takes over if this ruler dies with `kept` power (§5.2): {"delay" (turns), "kept_power",
## "generation", "name", "heir_name", "kind"}. record_death and crown_successor apply it (M2-3, #31).
static func successor_for(ruler_id: String, kept: int, generation: int = 1) -> Dictionary:
	var r := ruler_data(ruler_id)
	var s: Dictionary = r.get("succession", {})
	var k := clampi(kept, 0, RulerData.POWER_POOL)
	var power := k
	match String(s.get("power", "same")):
		"half":
			power = floori(float(k) / 2)
		"minus":
			power = maxi(0, k - int(s.get("minus", 0)))
	var next := maxi(1, generation) + 1
	return {"delay": int(s.get("delay", 0)), "kept_power": power, "generation": next,
		"name": ruler_name(ruler_id, next), "heir_name": heir_name(ruler_id, next), "kind": String(r.get("kind", ""))}


## The succession rule for this ruler right now, in one sentence, for the ruler's tooltip.
static func succession_text(ruler_id: String, kept: int, generation: int, capital_name: String) -> String:
	var r := ruler_data(ruler_id)
	var next := successor_for(ruler_id, kept, generation)
	var name := ruler_name(ruler_id, generation)
	var later := "%d %s later" % [next.delay, "turn" if next.delay == 1 else "turns"]
	match String(r.get("kind", "")):
		"mortal":
			return "Mortal line: if %s dies, %s is crowned at %s %s with half the kept power, rounded down (now %d, so %d). Mandates always stay." % [
				name, next.heir_name, capital_name, later, kept, next.kept_power]
		"undying":
			return "Undying: if %s is destroyed, it re-forms at %s %s with the same kept power (now %d). Mandates always stay." % [
				name, capital_name, later, kept]
		"god":
			return "God: if the body of %s is slain, the god returns at %s %s with %d less kept power for good, never below 0 (now %d, so %d). Mandates always stay." % [
				name, capital_name, later, int(r.succession.get("minus", 0)), kept, next.kept_power]
	return ""


# --- death, healing and succession (§1.7, §5; M2-3, #31) ------------------------------------------
# A ruler dies when, after a battle, its army is gone (its side lost, and every losing army is
# destroyed) or its army no longer holds it (it fell while its side won: the battle resolver sets
# army.ruler to null). TurnResolver records the death right after that battle (record_death) and
# runs the rulers phase at the end of the turn: apply_mending_light, then heal_ruler, then
# crown_successor for every successor that is due. The rules and the turn report's sentences live
# here; TurnResolver turns them into events.

## A living ruler heals 1 / RULER_HEAL_DIVISOR of its maximum hp at the end of every turn, rounded up.
const RULER_HEAL_DIVISOR := 4
## The ability that heals your units and commanders in the rulers phase (§1.4).
const MENDING_LIGHT := "mending_light"
## How the turn report says a ruler of each kind died: [fell while its side won, lost with its side].
const DEATH_VERBS := {"mortal": ["fell", "was lost"], "undying": ["was struck down", "was broken"],
	"god": ["was slain", "was destroyed"]}


## True when the faction's ruler is alive and on the map. A faction without one has no province
## ability, no ruler in battle and can't sacrifice (§5.1).
static func has_living_ruler(state: GameState, faction_id: String) -> bool:
	var f := state.find_faction(faction_id)
	return f != null and f.has_ruler() and f.ruler_status == ALIVE and ruler_army(state, faction_id) != null


## True when the faction's ruler is alive, from its status alone (M5, design/M5_MAGIC_FOG.md §2.7): unlike
## has_living_ruler it doesn't need the ruler's army on the map, because under fog a player's view may know a
## rival ruler lives without knowing where. Screens that show a rival's ruler read this and handle "alive, location
## unknown" (M5-1 adds the view handling). has_living_ruler is unchanged.
static func ruler_alive(state: GameState, faction_id: String) -> bool:
	var f := state.find_faction(faction_id)
	return f != null and f.has_ruler() and f.ruler_status == ALIVE


## Hit points a living ruler with `max_hp` heals in the rulers phase: a quarter, rounded up (§1.7).
## A 46-hp King heals 12.
static func ruler_heal_amount(max_hp: int) -> int:
	return ceili(float(maxi(0, max_hp)) / RULER_HEAL_DIVISOR)


## True when the faction holds its capital, the only place successors arrive (§5.2).
static func holds_capital(state: GameState, faction_id: String) -> bool:
	var f := state.find_faction(faction_id)
	var capital := state.find_province(f.capital) if f != null else null
	return capital != null and capital.owner == faction_id


## Kept power the faction started the game with: the pool minus its pre-game mandates.
static func starting_kept_power(state: GameState, faction_id: String) -> int:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return 0
	var sacrificed := {}
	for sac in f.sacrifices:
		sacrificed[str(sac.get("mandate", ""))] = true
	var cost := 0
	for mid in f.mandates:
		if not sacrificed.has(mid):
			cost += mandate_cost(mid)
	return RulerData.POWER_POOL - cost


## Records that `faction_id`'s ruler died during `turn` (1-based, as players see it), §5.1: its status
## becomes dead, its army is removed if anything is left of it, and its successor falls due at the
## end of turn `turn` + the kind's delay with the kind's share of the kept power at the moment of
## death (successor_for). Mandates stay. Returns succession_info(), or {} when the faction has no
## living ruler to lose (nothing changes then).
static func record_death(state: GameState, faction_id: String, turn: int) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler() or f.ruler_status != ALIVE:
		return {}
	var army := ruler_army(state, faction_id)
	if army != null:
		army.ruler = null
		if army.units.is_empty() and army.commander == null:
			state.armies.erase(army)
	var next := successor_for(f.ruler_type, f.kept_power, f.ruler_generation)
	f.ruler_status = DEAD
	f.successor_turn = maxi(1, turn + int(next.delay))  # never 0: 0 means "no successor due"
	f.successor_power = int(next.kept_power)
	return succession_info(state, faction_id)


## A dead ruler's succession, for reports and screens: {"faction", "ruler", "kind", "name" (the ruler
## who died), "kept_power" (at death), "generation" (of the one who died), "successor_turn" (the
## successor arrives at the end of it), "successor_power", "successor_generation", "successor_name"
## (as ruler: "King Corvane II"), "heir_name" (before taking over: "Corvane II"), "delay", "minus"
## (the god's loss), "capital", "capital_name", "codex" (the kind's RulesCodex entry)}.
## {} unless the faction's ruler is dead.
static func succession_info(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler() or f.ruler_status != DEAD:
		return {}
	var r := ruler_data(f.ruler_type)
	var kind := String(r.get("kind", ""))
	var spec: Dictionary = r.get("succession", {})
	var next_gen := maxi(1, f.ruler_generation) + 1
	return {"faction": faction_id, "ruler": f.ruler_type, "kind": kind,
		"name": ruler_name(f.ruler_type, f.ruler_generation), "kept_power": f.kept_power,
		"generation": f.ruler_generation, "successor_turn": f.successor_turn, "successor_power": f.successor_power,
		"successor_generation": next_gen, "successor_name": ruler_name(f.ruler_type, next_gen),
		"heir_name": heir_name(f.ruler_type, next_gen), "delay": int(spec.get("delay", 0)),
		"minus": int(spec.get("minus", 0)), "capital": f.capital, "capital_name": _province_name(state, f.capital),
		"codex": String(RulerData.KINDS.get(kind, {}).get("codex", "succession"))}


## True when the faction's dead ruler has a successor due by the end of `turn`. It still arrives only
## if the faction holds its capital then (crown_successor).
static func successor_due(state: GameState, faction_id: String, turn: int) -> bool:
	var f := state.find_faction(faction_id)
	return f != null and f.has_ruler() and f.ruler_status == DEAD and f.successor_turn > 0 and turn >= f.successor_turn


## The successor takes over at the end of `turn` (§5.2): kept power becomes the successor's, the
## generation goes up by 1, the ruler is alive again and stands at full hp in a new ruler's army at
## the capital (never joined to another army). Only when the successor is due by `turn` and the
## faction holds its capital; otherwise nothing changes and it returns null, and the successor waits
## for the end of the first turn the faction holds its capital again. Returns the new ruler's army.
static func crown_successor(state: GameState, faction_id: String, turn: int) -> Army:
	if not successor_due(state, faction_id, turn) or not holds_capital(state, faction_id):
		return null
	var f := state.find_faction(faction_id)
	f.kept_power = clampi(f.successor_power, 0, RulerData.POWER_POOL)
	f.ruler_generation = maxi(1, f.ruler_generation) + 1
	f.ruler_status = ALIVE
	f.successor_turn = 0
	f.successor_power = 0
	refresh_ruler_type(f)
	var army := Army.new()
	army.id = state.new_army_id(faction_id)
	army.owner = faction_id
	army.location = f.capital
	army.ruler = Unit.new(f.ruler_unit_type, faction_id)  # a new Unit starts at its type's full hp
	state.armies.append(army)
	refresh_ruler(state, faction_id)
	return army


## The rulers phase's ruler healing (§1.7): the faction's living ruler heals ruler_heal_amount of its
## maximum hp, never above it. Returns {"army", "province", "name", "healed", "hp_before", "hp_after",
## "max_hp", "share"}; "healed" is 0 when it was at full hp, and the dictionary is just {"healed": 0}
## without a living ruler on the map.
static func heal_ruler(state: GameState, faction_id: String) -> Dictionary:
	if not has_living_ruler(state, faction_id):
		return {"healed": 0}
	var army := ruler_army(state, faction_id)
	var unit := army.ruler
	var max_hp := unit.type.hp
	var before := unit.current_hp
	var share := ruler_heal_amount(max_hp)
	unit.current_hp = clampi(before + share, 1, max_hp)
	return {"army": army.id, "province": army.location, "name": unit.type.name, "healed": unit.current_hp - before,
		"hp_before": before, "hp_after": unit.current_hp, "max_hp": max_hp, "share": share}


## Mending Light (§1.4), in the rulers phase before ruler healing: with a living Ever-Regent on the
## map, each wounded unit and commander of the faction in the Regent's province (any of its armies
## there) heals the ability's value at the Regent's ability rank, up to its maximum. Rulers are not
## healed by it. Armies go in id order, then units in order, then the commander. Returns {"province",
## "rank", "amount", "healed": [{"army", "name", "healed", "hp_after", "max_hp"}], "total", "ruler",
## "name"}; "healed" is empty when nobody needed it, the ruler is dead, or its ability is another one.
static func apply_mending_light(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not has_living_ruler(state, faction_id) or String(ruler_data(f.ruler_type).get("ability", "")) != MENDING_LIGHT:
		return {"healed": [], "total": 0}
	var regent := ruler_army(state, faction_id)
	var rank := ability_rank(f.kept_power)
	var amount := ability_value(f.ruler_type, rank)
	var armies: Array = state.armies.duplicate()
	armies.sort_custom(func(a, b): return a.id < b.id)
	var healed := []
	var total := 0
	for a in armies:
		if a.owner != faction_id or a.location != regent.location:
			continue
		var members: Array = a.units.duplicate()
		if a.commander != null:
			members.append(a.commander)
		for u in members:
			var max_hp := unit_max_hp(state, u)  # M2-2: Veteran Levies raises a regular unit's maximum
			var gain := clampi(max_hp - u.current_hp, 0, amount)
			if gain == 0:
				continue
			u.current_hp += gain
			total += gain
			healed.append({"army": a.id, "name": u.type.name, "healed": gain, "hp_after": u.current_hp, "max_hp": max_hp})
	return {"province": regent.location, "rank": rank, "amount": amount, "healed": healed, "total": total,
		"ruler": f.ruler_type, "name": current_name(state, faction_id)}


## ability_short in words that never start with a minus sign, for report sentences: "+3 gold",
## "heal 6", "2 less enemy morale", "2 recruits in the field" ("1 recruit in the field").
static func ability_effect(ruler_id: String, rank: int) -> String:
	var template := String(ability_data(ruler_id).get("short", ""))
	var value := ability_value(ruler_id, rank)
	if template.begins_with("-{value} "):
		return "%d less %s" % [value, template.trim_prefix("-{value} ")]
	var words := template.split(" ")
	var at := words.find("{value}")
	if value == 1 and at >= 0 and at + 1 < words.size() and words[at + 1].ends_with("s"):
		words[at + 1] = words[at + 1].trim_suffix("s")  # "1 recruit", not "1 recruits"
	return " ".join(words).format({"value": value})


## The ruler_died sentence for the turn report (§5.4): who died and how, who succeeds, where, when and
## with how much kept power, and what the faction lacks until then. `info` is record_death()'s
## result; `fell` is true when the ruler fell while its side won the battle, false when it was lost
## with its side; `place` is "at Blackwood" or "on the border between Stonegate and Blackwood".
static func death_text(state: GameState, faction_id: String, info: Dictionary, fell: bool, place: String) -> String:
	var side := "the %s" % _faction_name(state, faction_id)
	var kind := String(info.get("kind", ""))
	var name := String(info.get("name", ""))
	var subject := "%s's body" % _cap(name) if kind == "god" else _cap(name)
	var verbs: Array = DEATH_VERBS.get(kind, DEATH_VERBS.mortal)
	var how: String
	if fell:
		how = "%s %s in the battle %s, though %s won it." % [subject, verbs[0], place, side]
	else:
		how = "%s %s when %s lost the battle %s. A ruler on a losing side is lost with its army; there are no retreats yet." % [
			subject, verbs[1], side, place]
	var due := int(info.get("successor_turn", 0))
	var when := "at the end of turn %d, ready for orders on turn %d" % [due, due + 1]
	var capital := String(info.get("capital_name", ""))
	var kept := int(info.get("kept_power", 0))
	var next_kept := int(info.get("successor_power", 0))
	var next: String
	match kind:
		"undying":
			next = "%s cannot truly die and re-forms at %s %s, with the same %d kept power." % [_cap(name), capital, when, next_kept]
		"god":
			if next_kept < kept:
				next = "The god takes a new body at %s %s, weaker for good: %d kept power instead of %d (%d less, never below 0)." % [
					capital, when, next_kept, kept, int(info.get("minus", 0))]
			else:
				next = "The god takes a new body at %s %s, with %d kept power: it had none left to lose, and kept power never goes below 0." % [
					capital, when, next_kept]
		_:
			next = "The line goes on: %s will be crowned at %s %s, with %d kept power (half of %d, rounded down)." % [
				String(info.get("heir_name", "")), capital, when, next_kept, kept]
	var until := "Until then %s has no ruler: no %s, no ruler in battle and no sacrifices." % [side,
		ability_name(String(info.get("ruler", "")))]
	if not mandates(state, faction_id).is_empty():
		until += " Its mandates stay."
	return "%s %s %s" % [how, next, until]


## The ruler_arrived sentence (§5.4): who took over where, with what kept power and numbers. Call it
## right after crown_successor; `kept_before` is the kept power of the ruler who died, `next_turn` the
## first turn the new ruler can be given orders.
static func arrival_text(state: GameState, faction_id: String, kept_before: int, next_turn: int) -> String:
	var f := state.find_faction(faction_id)
	var rid := f.ruler_type
	var name := ruler_name(rid, f.ruler_generation)
	var stats := ruler_stats(rid, f.kept_power, f.ruler_generation)
	var capital := _province_name(state, f.capital)
	var head: String
	match String(ruler_data(rid).get("kind", "")):
		"undying":
			head = "%s re-formed at %s with the same %d kept power" % [_cap(name), capital, f.kept_power]
		"god":
			var lost := kept_before - f.kept_power
			head = "%s took a new body at %s with %d kept power, %s" % [_cap(name), capital, f.kept_power,
				"%d less than before, for good" % lost if lost > 0 else "no less than before: kept power never goes below 0"]
		_:
			var heir := heir_name(rid, f.ruler_generation)
			head = "%s was crowned at %s%s with %d kept power" % [_cap(heir), capital,
				"" if heir == name else " as %s" % name, f.kept_power]
	return "%s: %d hit points, attack %d, defense %d, %s %s (ability rank %d). The new ruler's army stands at %s, ready for orders on turn %d." % [
		head, stats.hp, stats.attack, stats.defense, stats.ability_name, ability_effect(rid, stats.ability_rank),
		stats.ability_rank, capital, next_turn]


## The succession_waiting sentence: a successor fell due, but the faction doesn't hold its capital.
static func waiting_text(state: GameState, faction_id: String) -> String:
	var info := succession_info(state, faction_id)
	if info.is_empty():
		return ""
	var side := "the %s" % _faction_name(state, faction_id)
	var capital := String(info.capital_name)
	var who: String
	match String(info.kind):
		"undying":
			who = "%s was due to re-form" % _cap(info.name)
		"god":
			who = "%s was due to take a new body" % _cap(info.name)
		_:
			who = "%s was due to be crowned" % _cap(info.heir_name)
	return "%s at %s at the end of turn %d, but %s doesn't hold %s. Successors arrive only at the capital, so this waits until the end of the first turn %s holds %s again." % [
		who, capital, int(info.successor_turn), side, capital, side, capital]


## The ruler_healed sentence (§1.7). `info` is heal_ruler()'s result; `place` the province's name.
static func healed_text(info: Dictionary, place: String) -> String:
	return "%s healed %d hit points at %s (a living ruler heals a quarter of its maximum, rounded up, at the end of every turn): now %d of %d." % [
		_cap(String(info.get("name", ""))), int(info.get("healed", 0)), place, int(info.get("hp_after", 0)), int(info.get("max_hp", 0))]


## The mending sentence (§1.4). `info` is apply_mending_light()'s result; `place` the province's name.
static func mending_text(state: GameState, faction_id: String, info: Dictionary, place: String) -> String:
	var order := []
	var counts := {}
	var gains := {}
	for h in info.get("healed", []):
		if not counts.has(h.name):
			order.append(h.name)
			counts[h.name] = 0
			gains[h.name] = 0
		counts[h.name] += 1
		gains[h.name] += int(h.healed)
	var parts := []
	for type_name in order:
		parts.append(("%s +%d" % [type_name, gains[type_name]]) if counts[type_name] == 1
			else ("%d %s +%d" % [counts[type_name], type_name, gains[type_name]]))
	var n: int = info.get("healed", []).size()
	return "%s (rank %d, heal %d): %s healed %d wounded %s of the %s at %s, %d hit points in all (%s)." % [
		ability_name(String(info.get("ruler", ""))), int(info.get("rank", 0)), int(info.get("amount", 0)),
		String(info.get("name", "")), n, "fighter" if n == 1 else "fighters", _faction_name(state, faction_id), place,
		int(info.get("total", 0)), ", ".join(parts)]


## The ruler's stats as a UnitType: is_ruler, cost 0, no trait (§9). Its id is the ruler's id.
static func make_unit_type(ruler_id: String, kept: int, generation: int = 1) -> UnitType:
	var stats := ruler_stats(ruler_id, kept, generation)
	var ut := UnitType.new()
	ut.id = ruler_id
	ut.name = stats.name
	ut.hp = stats.hp
	ut.attack = stats.attack
	ut.defense = stats.defense
	ut.morale = stats.morale
	ut.cost = 0
	ut.trait_id = ""
	ut.trait_description = ""
	ut.is_commander = false
	ut.is_ruler = true
	return ut


## Rebuilds faction.ruler_unit_type from its ruler, kept power and generation (null without a ruler).
## Call it whenever kept power or the generation changes; GameState.from_dict calls it on load.
static func refresh_ruler_type(faction: Faction) -> void:
	if faction == null:
		return
	if not faction.has_ruler() or ruler_data(faction.ruler_type).is_empty():
		faction.ruler_unit_type = null
		return
	faction.ruler_unit_type = make_unit_type(faction.ruler_type, faction.kept_power, faction.ruler_generation)


## refresh_ruler_type, then points the living ruler at the new stats. Its current hp is kept but never
## above the new maximum or below 1. (A sacrifice's own hp rule, §2.4, is M2-6's to apply first.)
static func refresh_ruler(state: GameState, faction_id: String) -> void:
	var f := state.find_faction(faction_id)
	refresh_ruler_type(f)
	var unit := ruler_unit(state, faction_id)
	if unit != null and f.ruler_unit_type != null:
		unit.type = f.ruler_unit_type
		unit.current_hp = clampi(unit.current_hp, 1, unit.type.hp)


static func roman(n: int) -> String:
	var out := ""
	var left := maxi(1, n)
	for pair in ROMAN:
		while left >= pair[0]:
			out += pair[1]
			left -= pair[0]
	return out


## "First" .. "Ninety-ninth"; past that, "100th", "101st", ...
static func ordinal_word(n: int) -> String:
	if n >= 1 and n <= 9:
		return ORDINAL_UNITS[n - 1]
	if n >= 10 and n <= 19:
		return ORDINAL_TEENS[n - 10]
	if n >= 20 and n <= 99:
		var tens := floori(n / 10.0)
		var units := n % 10
		if units == 0:
			return TENS_ORDINAL[tens - 2]
		return "%s-%s" % [TENS[tens - 2], String(ORDINAL_UNITS[units - 1]).to_lower()]
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


# --- reading a game -------------------------------------------------------------------------------

static func has_rulers(state: GameState) -> bool:
	for f in state.factions:
		if f.has_ruler():
			return true
	return false


## The army holding `faction_id`'s living ruler, or null (no rulers, or none on the map right now).
static func ruler_army(state: GameState, faction_id: String) -> Army:
	for a in state.armies:
		if a.owner == faction_id and a.ruler != null:
			return a
	return null


static func ruler_unit(state: GameState, faction_id: String) -> Unit:
	var a := ruler_army(state, faction_id)
	return a.ruler if a else null


static func kept_power(state: GameState, faction_id: String) -> int:
	var f := state.find_faction(faction_id)
	return f.kept_power if f and f.has_ruler() else 0


## Mandate ids the faction owns, in the order taken. Faction-wide and permanent: they stay when the ruler dies.
static func mandates(state: GameState, faction_id: String) -> Array:
	var f := state.find_faction(faction_id)
	return f.mandates.duplicate() if f and f.has_ruler() else []


static func has_mandate(state: GameState, faction_id: String, mandate_id: String) -> bool:
	return mandates(state, faction_id).has(mandate_id)


## The name of the faction's current ruler ("King Corvane I"), or "" without one.
static func current_name(state: GameState, faction_id: String) -> String:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return ""
	return ruler_name(f.ruler_type, f.ruler_generation)


## The faction's build as the record and the victory screen show it: {"ruler", "ruler_name",
## "kept_power", "mandates", "mandate_names", "status", "generation"}, or {} without a ruler.
static func build_of(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return {}
	var names := []
	for mid in f.mandates:
		names.append(mandate_name(mid))
	return {"ruler": f.ruler_type, "ruler_name": current_name(state, faction_id), "kept_power": f.kept_power,
		"mandates": f.mandates.duplicate(), "mandate_names": names, "status": f.ruler_status,
		"generation": f.ruler_generation}


# --- builds (§2.1) --------------------------------------------------------------------------------

## A build as {"preset", "ruler", "mandates"} with string ids, from a build dictionary or a preset id.
static func normalize_build(build) -> Dictionary:
	if build is String or build is StringName:
		var p := preset_build(String(build))
		return p if not p.is_empty() else {"preset": String(build), "ruler": "", "mandates": []}
	if build is Dictionary:
		return {"preset": str(build.get("preset", "")), "ruler": str(build.get("ruler", "")),
			"mandates": Serial.to_string_array(build.get("mandates", []))}
	return {"preset": "", "ruler": "", "mandates": []}


## Total power the build's mandates cost (each listed mandate once).
static func build_cost(build) -> int:
	var total := 0
	var seen := {}
	for mid in normalize_build(build).mandates:
		if not seen.has(mid):
			seen[mid] = true
			total += mandate_cost(mid)
	return total


## Kept power after the build: the pool minus its mandates. An empty build keeps all 10.
static func kept_after(build) -> int:
	return RulerData.POWER_POOL - build_cost(build)


## Why `build` is not a legal pre-game build for `faction_id`, one plain-language reason each; [] when
## it is legal. Checks: a ruler of that faction, known mandates, none twice, none exclusive to
## another faction, and a total cost within the pool of 10 (§2.1).
static func build_errors(faction_id: String, build) -> Array:
	var choices := rulers_for(faction_id)
	if choices.is_empty():
		return ["That faction is not in this game, so it has no rulers to choose from."]
	var fname := _faction_display(faction_id)
	if build is String or build is StringName:
		var preset := preset_data(String(build))
		var names := []
		for p in BuildPresetData.PRESETS.get(faction_id, []):
			names.append(p.name)
		if preset.is_empty():
			return ["'%s' is not a build preset in this game. The %s presets are %s." % [String(build), fname, _and_list(names)]]
		if preset.faction != faction_id:
			return ["%s is %s preset, not one of the %s. Its presets are %s." % [preset.name,
				_a(_faction_display(preset.faction)), _possessive(fname), _and_list(names)]]
	elif not (build is Dictionary):
		return ["A build names a ruler and the mandates it buys."]
	var b := normalize_build(build)
	var errors := []
	var ruler_names := []
	for rid in choices:
		ruler_names.append(ruler_name(rid))
	var can_choose := "The %s can choose %s." % [fname, _or_list(ruler_names)]
	if b.ruler.is_empty():
		errors.append("No ruler is chosen. %s" % can_choose)
	elif ruler_data(b.ruler).is_empty():
		errors.append("'%s' is not a ruler in this game. %s" % [b.ruler, can_choose])
	elif ruler_data(b.ruler).faction != faction_id:
		errors.append("%s leads the %s, not the %s. %s" % [_cap(ruler_name(b.ruler)),
			_faction_display(ruler_data(b.ruler).faction), fname, can_choose])
	if build is Dictionary and build.has("mandates") and not (build.mandates is Array):
		errors.append("The mandates must be a list of mandates.")
		return errors
	var seen := {}
	var twice := {}
	var cost := 0
	var parts := []
	for mid in b.mandates:
		var md := mandate_data(mid)
		if md.is_empty():
			errors.append("'%s' is not a mandate in this game." % mid)
			continue
		if seen.has(mid):
			if not twice.has(mid):
				twice[mid] = true
				errors.append("%s is in the build twice. Each mandate can be taken only once." % md.name)
			continue
		seen[mid] = true
		if not String(md.faction).is_empty() and md.faction != faction_id:
			errors.append("%s is %s mandate, so the %s can't take it." % [md.name, _a(_faction_display(md.faction)), fname])
		elif md.get("sacrifice_only", false):
			errors.append(path_mandate_reason(mid, fname))
		cost += int(md.cost)
		parts.append("%s %d" % [md.name, int(md.cost)])
	if cost > RulerData.POWER_POOL:
		errors.append("These mandates cost %d power (%s), but the power pool is only %d. Drop mandates worth at least %d power." % [
			cost, " + ".join(parts), RulerData.POWER_POOL, cost - RulerData.POWER_POOL])
	return errors


## Applies a legal pre-game build to `faction_id` in `state`: its ruler, kept power = 10 minus the
## mandates' cost, its mandates, generation 1, alive. The ruler starts at full hp in its own army at the
## faction's capital (a new army, or the ruler army it already has). Returns the reasons it was not
## applied ([] when it was); nothing changes then. Only before turn 1: later, mandates come by sacrifice.
static func apply_build(state: GameState, faction_id: String, build) -> Array:
	var f := state.find_faction(faction_id)
	if f == null:
		return ["That faction is not in this game."]
	var errors := build_errors(faction_id, build)
	if state.current_turn != 0:
		errors.append("Builds are chosen before the game starts. Later, mandates can only be bought by sacrifice.")
	var capital := state.find_province(f.capital)
	if capital == null:
		errors.append("The %s has no capital on this map for its ruler to start in." % f.faction_name)
	if not errors.is_empty():
		return errors
	var b := normalize_build(build)
	f.ruler_type = b.ruler
	f.mandates = b.mandates.duplicate()
	f.kept_power = kept_after(b)
	f.ruler_generation = 1
	f.ruler_status = ALIVE
	f.successor_turn = 0
	f.successor_power = 0
	f.sacrifices = []
	refresh_ruler_type(f)
	var army := ruler_army(state, faction_id)
	if army == null:
		army = Army.new()
		army.id = state.new_army_id(faction_id)
		army.owner = faction_id
		army.location = capital.id
		state.armies.append(army)
	army.ruler = Unit.new(f.ruler_unit_type, faction_id)
	fill_regular_units(state, faction_id)  # M2-2: the starting army at its maximum, Veteran Levies included
	return []


# --- regular units with mandates (§2.3) -----------------------------------------------------------

## A roster unit's or commander's numbers for `faction_id` with its mandates: Royal Armories (+1 attack
## and defense) and Veteran Levies (+2 max hp) for regular units, Muster Grounds (a fifth off, rounded
## down) for every recruit. The numbers come from MandateData. M4: in a game with paths, the path's parts
## on regular units follow the mandates' (AscensionRules.unit_parts and price_parts: Drillyard, Arbalests,
## Remount Stables, ...), and "morale" is one of the stats. Returns {"ok", "unit_type", "name",
## "is_commander", "hp", "attack", "defense", "morale", "cost", "base": {stat: the type's value},
## "mods": {stat: [{"key", "name", "value", and "mandate" (its id; "" for a path part) or "node"}]}};
## "ok" is false for a type the faction can't recruit. Path parts' keys are "path_<node id>", mandates'
## "mandate_<id>". The cost is recruit_price's (price_mods), the price the recruitment phase charges (M2-4).
static func unit_stats(state: GameState, faction_id: String, unit_type_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	if ut == null:
		return {"ok": false}
	var base := {"hp": ut.hp, "attack": ut.attack, "defense": ut.defense, "cost": ut.cost, "morale": ut.morale}
	var mods := {"hp": [], "attack": [], "defense": [], "cost": price_mods(state, faction_id, ut), "morale": []}
	for mid in mandates(state, faction_id):
		var md := mandate_data(mid)
		if not ut.is_commander:
			var bonus: Dictionary = md.get("units", {})
			for stat in bonus:
				mods[stat].append({"mandate": mid, "key": AutoBattleResolver.MANDATE_PREFIX + mid, "name": md.name,
					"value": int(bonus[stat])})
	var path := AscensionRules.unit_parts(state, faction_id, ut)  # M4: [] without paths
	for stat in path:
		mods[stat].append_array(path[stat])
	var out := {"ok": true, "unit_type": ut.id, "name": ut.name, "is_commander": ut.is_commander,
		"base": base, "mods": mods}
	for stat in base:
		var total: int = base[stat]
		for m in mods[stat]:
			total += m.value
		out[stat] = total
	return out


# --- rulers and mandates in battle (M2-2, #30; §1.6, §2.3) -----------------------------------------
# AutoBattleResolver reads these (and unit_stats, unit_max_hp), so the battle, the odds forecast and every
# tooltip use the same numbers. A faction without a ruler has no mandates, so none of this changes an M1
# battle.

const IRON_DISCIPLINE := "iron_discipline"
const DRILLED_RANKS := "drilled_ranks"
const VETERAN_LEVIES := "veteran_levies"
const ROYAL_ARMORIES := "royal_armories"
const BLOOD_FRENZY := "blood_frenzy"
const FEAST_OF_VICTORY := "feast_of_victory"
## The Great Thornmane's ability (§1.4): enemy sides in its province battles lose morale.
const DREAD := "dread"
## The mandate areas that work in battle (data/mandates.gd "area").
const BATTLE_AREAS := ["battle", "units"]


## What `faction_id`'s mandates do in battle, with their numbers from data/mandates.gd (§2.3):
## {"mandates": [the battle mandates it owns, in the order taken], "base_hit" (its fighters' base hit
## chance: AutoBattleResolver.BASE_HIT, or Drilled Ranks' base_hit), "base_hit_key" ("mandate_<id>" of the
## mandate that sets it, or ""), "wounded_attack" (attack for every fighter below its maximum hp: Blood
## Frenzy's, or 0), "wounded_attack_key", "iron_discipline" and "feast_of_victory" (whether it has them)}.
## `state` may be null (no mandates). Unit stat mandates (Royal Armories, Veteran Levies) are in unit_stats.
static func battle_effects(state: GameState, faction_id: String) -> Dictionary:
	var out := {"mandates": [], "base_hit": AutoBattleResolver.BASE_HIT, "base_hit_key": "", "wounded_attack": 0,
		"wounded_attack_key": "", "iron_discipline": false, "feast_of_victory": false}
	if state == null:
		return out
	for mid in mandates(state, faction_id):
		var md := mandate_data(mid)
		if not BATTLE_AREAS.has(String(md.get("area", ""))):
			continue
		out.mandates.append(mid)
		if md.has("base_hit"):
			out.base_hit = int(md.base_hit)
			out.base_hit_key = AutoBattleResolver.MANDATE_PREFIX + mid
		if md.has("wounded_attack"):
			out.wounded_attack += int(md.wounded_attack)
			out.wounded_attack_key = AutoBattleResolver.MANDATE_PREFIX + mid
		if mid == IRON_DISCIPLINE:
			out.iron_discipline = true
		elif mid == FEAST_OF_VICTORY:
			out.feast_of_victory = true
	return out


## What a battle mandate does, in a few words that read for either side, from data/mandates.gd (the
## battle report's "Mandates in play"): "+1 attack for every regular unit", "base hit
## chance 70% instead of 60%", "+3 attack for every fighter below its full hit points". Other mandates
## give their one-line effect.
static func mandate_battle_text(mandate_id: String) -> String:
	var md := mandate_data(mandate_id)
	if md.has("base_hit"):
		return "base hit chance %d%% instead of %d%%" % [int(md.base_hit), AutoBattleResolver.BASE_HIT]
	if md.has("wounded_attack"):
		return "+%d attack for every fighter below its full hit points" % int(md.wounded_attack)
	if md.has("units"):
		return "%s for every regular unit" % units_bonus_text(mandate_id)
	match mandate_id:
		IRON_DISCIPLINE:
			return "its side never breaks while one of its commanders stands, except at the end of the last round"
		FEAST_OF_VICTORY:
			return "after a battle its side wins, its fighters still standing heal to full"
	return String(md.get("effect", ""))


## Dread (§1.4): how much morale every enemy side loses in a province battle `faction_id`'s living
## Great Thornmane fights in, while it stands (its value at the ruler's ability rank); 0 for any other
## ruler, a dead one, or a game without rulers. Not in border battles: the battle decides that.
static func dread_value(state: GameState, faction_id: String) -> int:
	return live_ability_value(state, faction_id, DREAD)


## Gives every regular unit of `faction_id` its full maximum hp (unit_max_hp, so Veteran Levies counts):
## the starting army when a build is applied before turn 1 (§2.3: "new recruits arrive at the new
## maximum", and the starting army is the first recruits). Commanders and the ruler are already full.
static func fill_regular_units(state: GameState, faction_id: String) -> void:
	for a in state.armies:
		if a.owner != faction_id:
			continue
		for u in a.units:
			u.current_hp = unit_max_hp(state, u)


# --- mandates and abilities on the map (M2-4, #32; §1.4, §2.3) -------------------------------------
# The single source the resolver, Forecast, Breakdown and the orders UI read for King's Roads, Sworn
# Vassals, Heavy Tithes, Royal Court, Muster Grounds and Warband Muster.

const KINGS_ROADS := "kings_roads"
const SWORN_VASSALS := "sworn_vassals"
const HEAVY_TITHES := "heavy_tithes"
const ROYAL_COURT := "royal_court"
const WARBAND_MUSTER := "warband_muster"
## M4-2: the mandates a transformation opens that work on the map (data/mandates.gd PATH_MANDATES).
const FORGE_TITHE := "forge_tithe"
const HYMN_OF_DAWN := "hymn_of_dawn"
const DEEP_ROOTS := "deep_roots"
## Gold Heavy Tithes adds to every province its owner holds (§2.3).
const TITHE_GOLD := 2


## The price cuts `faction_id`'s mandates make on `ut` (Muster Grounds: cost / 5, rounded down, comes
## off every recruit, commanders included): [{"mandate", "name", "value" (negative)}]. The numbers come
## from MandateData's recruit_divisor.
## M4: in a game with paths the path's price parts follow (AscensionRules.price_parts: Remount Stables -4
## on Knights, Living Iron +4), with "key" "path_<node id>" and "mandate" "".
static func price_mods(state: GameState, faction_id: String, ut: UnitType) -> Array:
	var out := []
	if ut == null:
		return out
	for mid in mandates(state, faction_id):
		var md := mandate_data(mid)
		var divisor := int(md.get("recruit_divisor", 0))
		if divisor > 0:
			out.append({"mandate": mid, "key": AutoBattleResolver.MANDATE_PREFIX + mid, "name": md.name,
				"value": -floori(float(ut.cost) / divisor)})
	out.append_array(AscensionRules.price_parts(state, faction_id, ut))
	return out


## What `faction_id` pays for one `ut`: its cost with price_mods. Every recruit button, order line,
## gold forecast and the recruitment phase charge this price (TurnResolver.recruit_cost wraps it).
static func recruit_price(state: GameState, faction_id: String, ut: UnitType) -> int:
	if ut == null:
		return -1
	var price := ut.cost
	for m in price_mods(state, faction_id, ut):
		price += int(m.value)
	return price


## "16 gold (20 - Muster Grounds 4)", or "20 gold" when no mandate changes the price. A part that raises
## the price reads "+": "24 gold (20 + Living Iron 4)" (M4).
static func price_text(state: GameState, faction_id: String, ut: UnitType) -> String:
	var mods := price_mods(state, faction_id, ut)
	var price := recruit_price(state, faction_id, ut)
	if mods.is_empty():
		return "%d gold" % price
	var text := "%d" % ut.cost
	for m in mods:
		text += " %s %s %d" % ["-" if int(m.value) <= 0 else "+", m.name, absi(int(m.value))]
	return "%d gold (%s)" % [price, text]


## True when the faction's ruler has `ability_id` (whether or not the ruler is on the map right now).
static func ruler_has_ability(state: GameState, faction_id: String, ability_id: String) -> bool:
	var f := state.find_faction(faction_id)
	return f != null and f.has_ruler() and String(ruler_data(f.ruler_type).get("ability", "")) == ability_id


## The ruler's ability effect now (Royal Court gold, Warband Muster recruits per turn, ...): 0 when the
## faction has no ruler with that ability or its ruler is not on the map (dead, or no ruler's army).
static func live_ability_value(state: GameState, faction_id: String, ability_id: String) -> int:
	if not ruler_has_ability(state, faction_id, ability_id):
		return 0
	var f := state.find_faction(faction_id)
	if f.ruler_status != ALIVE or ruler_army(state, faction_id) == null:
		return 0
	return ability_value(f.ruler_type, ability_rank(f.kept_power))


# King's Roads -------------------------------------------------------------------------------------

## The provinces a road move of `army_id` to `to` may go through, sorted by id ([] when no road move
## there is legal). Legality is TurnResolver.check_move's; the orders UI picks the first (§2.3).
static func road_vias(state: GameState, faction_id: String, army_id: String, to: String) -> Array:
	var out := []
	var army := state.find_army(army_id)
	var here: Province = state.find_province(army.location) if army else null
	if here == null or not has_road_moves(state, faction_id):
		return out
	var ids: Array = here.neighbors.duplicate()
	ids.sort()
	for via in ids:
		if TurnResolver.check_move(state, faction_id, MoveOrder.new(army_id, to, via)).is_empty():
			out.append(via)
	return out


## True when the faction can make road moves at all: King's Roads, or (M4-2) Forest Stride.
static func has_road_moves(state: GameState, faction_id: String) -> bool:
	return has_mandate(state, faction_id, KINGS_ROADS) or AscensionRules.has_forest_stride(state, faction_id)


## Why a path mandate can't be taken yet, naming the transformation that opens it: "Hymn of Dawn opens only
## when the Aurel Crown becomes the Celestial Host, and then only by sacrifice."
static func path_mandate_reason(mandate_id: String, faction_name: String) -> String:
	var md := mandate_data(mandate_id)
	var nid := String(md.get("path", ""))
	var side := AscensionRules.branch_ref(String(AscensionRules.node_data(nid).get("branch", "")))
	return "%s opens only when the %s becomes %s (a path of ascension), and then only by sacrifice." % [
		String(md.get("name", mandate_id)), faction_name.trim_prefix("the ").trim_prefix("The "), side]


## Every province two steps away that `army_id` can reach by a road move this turn and could not reach
## by a one-step move: {province id: [legal vias, sorted by id]}. Empty without King's Roads.
static func road_destinations(state: GameState, faction_id: String, army_id: String) -> Dictionary:
	var out := {}
	var army := state.find_army(army_id)
	var here: Province = state.find_province(army.location) if army else null
	if here == null or army.owner != faction_id or not has_road_moves(state, faction_id):
		return out
	var vias: Array = here.neighbors.duplicate()
	vias.sort()
	for via in vias:
		var b := state.find_province(via)
		if b == null:
			continue
		var ends: Array = b.neighbors.duplicate()
		ends.sort()
		for to in ends:
			if to == here.id or here.neighbors.has(to):
				continue
			if TurnResolver.check_move(state, faction_id, MoveOrder.new(army_id, to, via)).is_empty():
				if not out.has(to):
					out[to] = []
				out[to].append(via)
	return out


# Sworn Vassals ------------------------------------------------------------------------------------

## Which neutral province joins each faction with Sworn Vassals this turn (§2.3). `owners` maps every
## province id to its owner after this turn's army captures ("" for nobody); `occupied` holds the
## province ids with an army in them after movement and battles. A province is eligible for a faction
## when it has no owner, no army, and is next to a province the faction owns in `owners`. The best is
## the highest income; ties go to the first by id. When two factions pick the same province, neither
## gets it and neither picks again that turn. Returns {"picks": {fid: pid}, "joins": {fid: pid},
## "contested": {pid: [fids, sorted]}}. The capture phase and Forecast.vassal both call this.
static func vassal_picks(state: GameState, owners: Dictionary, occupied: Dictionary) -> Dictionary:
	var fids := []
	for f in state.factions:
		if has_mandate(state, f.id, SWORN_VASSALS):
			fids.append(f.id)
	fids.sort()
	var provinces: Array = state.provinces.duplicate()
	provinces.sort_custom(func(a, b): return a.id < b.id)
	var picks := {}
	for fid in fids:
		var best: Province = null
		for p in provinces:
			if not str(owners.get(p.id, "")).is_empty() or occupied.has(p.id):
				continue
			var borders_ours := false
			for n in p.neighbors:
				if str(owners.get(n, "")) == fid:
					borders_ours = true
					break
			if borders_ours and (best == null or p.income > best.income):
				best = p  # provinces go in id order, so a tie keeps the first
		if best != null:
			picks[fid] = best.id
	var by_province := {}
	for fid in fids:
		if picks.has(fid):
			if not by_province.has(picks[fid]):
				by_province[picks[fid]] = []
			by_province[picks[fid]].append(fid)
	var joins := {}
	var contested := {}
	for pid in by_province:
		if by_province[pid].size() == 1:
			joins[by_province[pid][0]] = pid
		else:
			contested[pid] = by_province[pid]
	return {"picks": picks, "joins": joins, "contested": contested}


## The owners and occupied provinces of the board as it stands in `state` (the capture phase's input
## to vassal_picks).
static func board_now(state: GameState) -> Dictionary:
	var owners := {}
	for p in state.provinces:
		owners[p.id] = p.owner
	var occupied := {}
	for a in state.armies:
		occupied[a.location] = true
	return {"owners": owners, "occupied": occupied}


# Heavy Tithes and Royal Court ---------------------------------------------------------------------

## What `province_id` earns its owner this turn (§1.4, §2.3): the map's base income, +1 with the owner's
## Heavy Tithes, and Royal Court's gold when the owner's King is in it. `ruler_at` may move rulers for a
## forecast: {faction id: province id where its ruler ends the turn}; by default each ruler is where
## its army is now. Returns {"owner", "base", "mods": [{"key", "name", "value", "note"}], "total"}.
## A neutral province earns nobody anything, so it has no modifiers.
static func province_income_parts(state: GameState, province_id: String, ruler_at: Dictionary = {}) -> Dictionary:
	var p := state.find_province(province_id)
	if p == null:
		return {"owner": "", "base": 0, "mods": [], "total": 0}
	var mods := []
	var fid := p.owner
	if not fid.is_empty():
		if has_mandate(state, fid, HEAVY_TITHES):
			mods.append({"key": HEAVY_TITHES, "name": mandate_name(HEAVY_TITHES), "value": TITHE_GOLD,
				"note": "mandate: every province you own earns %d more" % TITHE_GOLD})
		var court := live_ability_value(state, fid, ROYAL_COURT)
		if court > 0:
			var army := ruler_army(state, fid)
			var where: String = str(ruler_at.get(fid, army.location))
			if where == p.id:
				var f := state.find_faction(fid)
				mods.append({"key": ROYAL_COURT, "name": ability_name(f.ruler_type), "value": court,
					"note": "%s is here, ability rank %d" % [current_name(state, fid), ability_rank(f.kept_power)]})
		var fort_income := AscensionRules.mandate_value(state, fid, "fort_income", 0)  # M4-2: Forge Tithe
		if fort_income > 0 and forge_tithe_counts(state, p):
			mods.append({"key": FORGE_TITHE, "name": mandate_name(FORGE_TITHE), "value": fort_income,
				"note": ("mandate: every keep or citadel you own earns %d more" if state.sieges
					else "mandate: every province with a fort you own earns %d more") % fort_income})
	var total := p.income
	for m in mods:
		total += int(m.value)
	# M4: the path's income lines (AscensionRules.income_parts; none without paths). A province never earns
	# less than 0: a line makes up the difference, so the lines still add up to the total.
	for m in AscensionRules.income_parts(state, p):
		mods.append(m)
		total += int(m.value)
	if total < 0:
		mods.append({"key": "income_floor", "name": "Never below 0", "value": -total,
			"note": "a province never earns less than nothing"})
		total = 0
	# M3c (§3.3, §12): a cut-off province pays its owner nothing. The part is minus everything above, so the lines
	# still add up to the total; its base income goes to the besiegers (TurnResolver.income_of).
	if state.sieges and not fid.is_empty() and total > 0 and SiegeRules.is_cut_off(state, p.id):
		var cut := SiegeRules.cut_off_info(state, p.id)
		mods.append({"key": CUT_OFF, "name": "Cut off", "value": -total,
			"note": "besieged since turn %d; its income goes to the %s" % [int(cut.since), _faction_name(state, String(cut.besieger))]})
		total = 0
	return {"owner": fid, "base": p.income, "mods": mods, "total": total}


## The key of a cut-off province's income part (M3c).
const CUT_OFF := "cut_off"


## Whether Forge Tithe pays for `p` (M4-2): every province with a fort; in a game with sieges (M3c, §7) only a
## keep or a citadel, so a 30-gold palisade doesn't pay for itself.
static func forge_tithe_counts(state: GameState, p: Province) -> bool:
	if state.sieges:
		return p.fort_level >= 2
	return p.has_fort


# Warband Muster -----------------------------------------------------------------------------------

## How many regular units `faction_id` may recruit with its ruler this turn (Warband Muster: its value
## at the ruler's ability rank), or 0 when its ruler can't (another ability, or not on the map).
static func field_recruit_limit(state: GameState, faction_id: String) -> int:
	return live_ability_value(state, faction_id, WARBAND_MUSTER)


# --- mid-game sacrifice (§2.4; M2-6, #34) ---------------------------------------------------------
# A Sacrifice order names one mandate. sacrifice_check is the rule (OrderBook, TurnResolver's sacrifice
# phase and the sacrifice dialog all ask it) and apply_sacrifice the effect. The sacrifice phase runs
# first in the turn, so a faction's other orders are checked against state_after_orders: the state with
# its queued sacrifice applied. OrderBook, Forecast and the orders UI all read that copy, so a road move
# or a Muster Grounds price can rely on a mandate the ruler is sacrificing for this turn.

## What each mandate does from the moment it is bought by sacrifice, for the turn report. {faction} is
## the faction's name; {units} the regular units' bonus from data/mandates.gd; {gained} what the units
## already on the map gained (Veteran Levies).
const SACRIFICE_NOW := {
	"iron_discipline": "From now on a side of the {faction} never breaks while one of its commanders in that battle stands, except at the end of the last round.",
	"drilled_ranks": "From now on every fighter of the {faction} hits 70% of the time at base, instead of 60%.",
	"veteran_levies": "Every regular unit of the {faction} now has {units}{gained}.",
	"heavy_tithes": "Every province the {faction} owns now earns 2 more gold per turn, starting with this turn's income.",
	"muster_grounds": "Every recruit of the {faction} now costs a fifth less, starting with this turn's recruits.",
	"sworn_vassals": "From this turn on, one neutral province next to the land of the {faction} swears fealty to it each turn.",
	"royal_armories": "Every regular unit of the {faction} now has {units}.",
	"kings_roads": "From this turn on, armies of the {faction} can move two provinces in one turn inside its own land.",
	"blood_frenzy": "From now on every fighter of the {faction} below its full hit points has +3 attack.",
	"feast_of_victory": "From now on, after every battle the {faction} wins, its fighters still standing heal to full.",
	"hymn_of_dawn": "From this turn on, Hallowed Land heals the wounded of the {faction} 6 hit points a turn instead of 3.",
	"forge_tithe": "Every province with a fort the {faction} owns now earns 4 more gold per turn, starting with this turn's income.",
	"deep_roots": "From this turn on, the Wild Spreads grows two provinces of the {faction} into forest each turn instead of one.",
	"red_harvest": "From now on, after every battle the {faction} wins, it gains 1 gold for every enemy fighter lost in it.",
}
## Player-facing words for the stats a mandate's "units" bonus names.
const UNIT_BONUS_WORDS := {"hp": "maximum hit points", "attack": "attack", "defense": "defense"}


## Power a mandate costs by sacrifice: its price plus MandateData.SACRIFICE_PREMIUM (Royal Armories: 5).
static func sacrifice_cost(mandate_id: String) -> int:
	return mandate_cost(mandate_id) + MandateData.SACRIFICE_PREMIUM


## {} when `faction_id` may sacrifice for `mandate_id` now (§2.4), otherwise {"code", "reason"} with a
## plain-language reason. `already` is the mandate of a Sacrifice order the faction already gave this
## turn ("" when none). Codes: "unknown_faction", "no_ruler" (a game without rulers), "second_sacrifice",
## "no_living_ruler", "unknown_mandate", "foreign_mandate", "owned_mandate", "not_enough_power".
static func sacrifice_check(state: GameState, faction_id: String, mandate_id: String, already: String = "") -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _refusal("unknown_faction", "Those orders are for a faction that is not in this game.")
	if not f.has_ruler():
		return _refusal("no_ruler", "The %s has no ruler in this game, so nobody can sacrifice power for a mandate." % f.faction_name)
	if not already.is_empty():
		return _refusal("second_sacrifice", "You already gave a Sacrifice order this turn, for %s. A ruler can sacrifice only once per turn: cancel that order first to choose another mandate." % mandate_name(already))
	var name := _cap(current_name(state, faction_id))
	if not has_living_ruler(state, faction_id):
		var why := "%s is dead, and only a living ruler can sacrifice power." % name
		var info := succession_info(state, faction_id)
		if not info.is_empty():
			why += " %s" % successor_sentence(info)
		return _refusal("no_living_ruler", why)
	var md := mandate_data(mandate_id)
	if md.is_empty():
		return _refusal("unknown_mandate", "'%s' is not a mandate in this game." % mandate_id)
	if not String(md.faction).is_empty() and md.faction != faction_id:
		return _refusal("foreign_mandate", "%s is %s mandate, so the %s can't take it, not even by sacrifice." % [
			md.name, _a(_faction_name(state, md.faction)), f.faction_name])
	if f.mandates.has(mandate_id):
		return _refusal("owned_mandate", "The %s already has %s. Each mandate can be taken only once." % [f.faction_name, md.name])
	# M4-2 (§6): a transformation forswears one mandate and opens one, which only it can buy.
	var forsworn := AscensionRules.forsworn_by(state, faction_id, mandate_id)
	if not forsworn.is_empty():
		return _refusal("forsworn_mandate", "%s was forsworn when the %s became %s, so it can no longer be bought by sacrifice. Mandates you already have stay." % [
			md.name, f.faction_name, AscensionRules.branch_ref(String(AscensionRules.node_data(forsworn).get("branch", "")))])
	if md.get("sacrifice_only", false) and not AscensionRules.opened_mandates(state, faction_id).has(mandate_id):
		return _refusal("mandate_not_open", path_mandate_reason(mandate_id, f.faction_name))
	var cost := sacrifice_cost(mandate_id)
	if f.kept_power < cost:
		return _refusal("not_enough_power", "%s costs %d power by sacrifice (%d, +%d for a mid-game sacrifice), but %s keeps only %d." % [
			md.name, cost, int(md.cost), MandateData.SACRIFICE_PREMIUM, name, f.kept_power])
	return {}


## The Sacrifice order's effect (§2.4), applied to `state` in place, for the turn `turn` (1-based). It is
## checked first: an illegal one changes nothing and returns {"ok": false, "code", "reason"}. Otherwise
## kept power drops by sacrifice_cost, the mandate joins the faction's mandates and its sacrifices
## record ({turn, mandate, cost}), the ruler's current hp drops by as much as its maximum hp does, never
## below 1 (then refresh_ruler gives it its new stats), and a mandate that adds hit points to regular
## units (Veteran Levies) gives the regular units already on the map that many current hit points at
## once (§2.3). Returns {"ok": true, "faction", "mandate", "mandate_name", "cost", "price", "premium",
## "turn", "army", "province", "ruler_name", "kept_before", "kept_after", "hp_before", "hp_after",
## "max_hp_before", "max_hp_after", "attack_before", "attack_after", "defense_before", "defense_after",
## "rank_before", "rank_after", "units_gained", "hp_gained", "unit_hp_gain"}.
static func apply_sacrifice(state: GameState, faction_id: String, mandate_id: String, turn: int, already: String = "") -> Dictionary:
	var check := sacrifice_check(state, faction_id, mandate_id, already)
	if not check.is_empty():
		var refused := check.duplicate()
		refused["ok"] = false
		return refused
	var f := state.find_faction(faction_id)
	var army := ruler_army(state, faction_id)
	var unit := army.ruler
	var before := ruler_stats(f.ruler_type, f.kept_power, f.ruler_generation)
	var hp_before := unit.current_hp
	var kept_before := f.kept_power
	var cost := sacrifice_cost(mandate_id)
	f.kept_power = kept_before - cost
	f.mandates.append(mandate_id)
	f.sacrifices.append({"turn": turn, "mandate": mandate_id, "cost": cost})
	var after := ruler_stats(f.ruler_type, f.kept_power, f.ruler_generation)
	unit.current_hp = maxi(1, hp_before - (int(before.hp) - int(after.hp)))
	refresh_ruler(state, faction_id)
	var gain := int(mandate_data(mandate_id).get("units", {}).get("hp", 0))
	var gained := 0
	var hp_gained := 0
	if gain > 0:
		for a in state.armies:
			if a.owner != faction_id:
				continue
			for u in a.units:
				var raised := mini(u.current_hp + gain, unit_max_hp(state, u))
				if raised > u.current_hp:
					hp_gained += raised - u.current_hp
					gained += 1
					u.current_hp = raised
	return {"ok": true, "faction": faction_id, "mandate": mandate_id, "mandate_name": mandate_name(mandate_id),
		"cost": cost, "price": mandate_cost(mandate_id), "premium": MandateData.SACRIFICE_PREMIUM, "turn": turn,
		"army": army.id, "province": army.location, "ruler_name": current_name(state, faction_id),
		"kept_before": kept_before, "kept_after": f.kept_power, "hp_before": hp_before, "hp_after": unit.current_hp,
		"max_hp_before": int(before.hp), "max_hp_after": int(after.hp), "attack_before": int(before.attack),
		"attack_after": int(after.attack), "defense_before": int(before.defense), "defense_after": int(after.defense),
		"rank_before": int(before.ability_rank), "rank_after": int(after.ability_rank), "units_gained": gained,
		"hp_gained": hp_gained, "unit_hp_gain": gain}


## The first Sacrifice order in `orders`, or null.
static func queued_sacrifice(orders: Array) -> SacrificeOrder:
	for o in orders:
		if o is SacrificeOrder:
			return o
	return null


## The state `faction_id`'s other orders are checked against (§2.4): `state` itself, or, when `orders`
## hold a legal Sacrifice order, a copy with it applied, because the sacrifice phase runs first in the
## turn. OrderBook, Forecast and the orders UI read it; `state` is never changed.
static func state_after_orders(state: GameState, faction_id: String, orders: Array) -> GameState:
	var sac := queued_sacrifice(orders)
	if sac == null or not sacrifice_check(state, faction_id, sac.mandate_id).is_empty():
		return state
	return with_sacrifice(state, faction_id, sac.mandate_id)


## A copy of `state` with `faction_id`'s sacrifice for `mandate_id` applied, as the sacrifice phase of
## the turn being ordered would apply it (an illegal sacrifice leaves the copy as it was).
static func with_sacrifice(state: GameState, faction_id: String, mandate_id: String) -> GameState:
	var copy := state.deep_copy([])
	if copy == null:
		return state
	apply_sacrifice(copy, faction_id, mandate_id, state.current_turn + 1)
	return copy


## The sacrificed sentence for the turn report (§2.4), from apply_sacrifice's result `info`: "King
## Corvane I gave up 5 power for Royal Armories (4, +1 for a mid-game sacrifice). Kept power 10 → 5: hit
## points 46 of 46 → 31 of 31, attack 14 → 11, defense 13 → 10, Royal Court rank 4 → 2 (+3 gold). Every
## regular unit of the Aurel Crown now has +1 attack."
static func sacrifice_text(state: GameState, faction_id: String, info: Dictionary) -> String:
	var f := state.find_faction(faction_id)
	var rid := f.ruler_type if f else ""
	var head := "%s gave up %d power for %s (%d, +%d for a mid-game sacrifice)." % [_cap(String(info.get("ruler_name", ""))),
		int(info.get("cost", 0)), String(info.get("mandate_name", "")), int(info.get("price", 0)), int(info.get("premium", 0))]
	var rank_before := int(info.get("rank_before", 1))
	var rank_after := int(info.get("rank_after", 1))
	var ability := "%s rank %d → %d (%s)" % [ability_name(rid), rank_before, rank_after, ability_effect(rid, rank_after)]
	if rank_before == rank_after:
		ability = "%s stays at rank %d (%s)" % [ability_name(rid), rank_after, ability_effect(rid, rank_after)]
	var stats := "Kept power %d → %d: hit points %d of %d → %d of %d, attack %d → %d, defense %d → %d, %s." % [
		int(info.get("kept_before", 0)), int(info.get("kept_after", 0)), int(info.get("hp_before", 0)),
		int(info.get("max_hp_before", 0)), int(info.get("hp_after", 0)), int(info.get("max_hp_after", 0)),
		int(info.get("attack_before", 0)), int(info.get("attack_after", 0)), int(info.get("defense_before", 0)),
		int(info.get("defense_after", 0)), ability]
	return "%s %s %s" % [head, stats, sacrifice_now_text(state, faction_id, String(info.get("mandate", "")),
		int(info.get("units_gained", 0)), int(info.get("unit_hp_gain", 0)))]


## What `mandate_id` does for `faction_id` from the moment it is bought by sacrifice, in one sentence (see
## SACRIFICE_NOW). `units_gained` regular units already on the map gained `hp_gain` hit points each.
static func sacrifice_now_text(state: GameState, faction_id: String, mandate_id: String, units_gained: int = 0, hp_gain: int = 0) -> String:
	var template := String(SACRIFICE_NOW.get(mandate_id, ""))
	if template.is_empty():
		return String(mandate_data(mandate_id).get("effect", ""))
	var gained := ""
	if units_gained > 0:
		gained = ", and %s already on the map %s %d hit points at once" % [
			"the 1 unit" if units_gained == 1 else "the %d units" % units_gained, "gained", hp_gain]
	return template.format({"faction": _faction_name(state, faction_id), "units": units_bonus_text(mandate_id), "gained": gained})


## A mandate's bonus to regular units in words, from data/mandates.gd: "+1 attack",
## "+2 maximum hit points"; "" for a mandate without one.
static func units_bonus_text(mandate_id: String) -> String:
	var bonus: Dictionary = mandate_data(mandate_id).get("units", {})
	var parts := []
	for stat in ["attack", "defense", "hp"]:
		if bonus.has(stat):
			parts.append("+%d %s" % [int(bonus[stat]), UNIT_BONUS_WORDS[stat]])
	return _and_list(parts)


## A unit's maximum hit points with its faction's mandates: its type's, plus Veteran Levies for a
## regular unit (never commanders or rulers), plus the path's hp parts in a game with paths (M4).
## unit_stats' "hp" for the unit's own type.
static func unit_max_hp(state: GameState, unit: Unit) -> int:
	if unit == null or unit.type == null:
		return 0
	var hp := unit.type.hp
	if unit.type.is_commander or unit.type.is_ruler:
		return hp
	for mid in mandates(state, unit.owner):
		hp += int(mandate_data(mid).get("units", {}).get("hp", 0))
	hp += AscensionRules.unit_hp_bonus(state, unit.owner, unit.type)  # M4: Drillyard, Boar Hide, ... (0 without paths)
	return hp


## When and where a dead ruler's successor arrives, in one sentence (from succession_info): "Corvane II
## will be crowned at Crownkeep at the end of turn 6."
static func successor_sentence(info: Dictionary) -> String:
	var capital := String(info.get("capital_name", ""))
	var due := int(info.get("successor_turn", 0))
	match String(info.get("kind", "")):
		"undying":
			return "%s re-forms at %s at the end of turn %d." % [_cap(String(info.get("name", ""))), capital, due]
		"god":
			return "The god takes a new body at %s at the end of turn %d." % [capital, due]
	return "%s will be crowned at %s at the end of turn %d." % [_cap(String(info.get("heir_name", ""))), capital, due]


## Turns until a dead ruler's successor arrives, counting the turn being ordered (§5.4): 2 on the turn
## after a mortal ruler died, 1 when it arrives at the end of this turn, 0 when it is due but waits for
## the capital. -1 while the ruler lives (or without rulers).
static func successor_countdown(state: GameState, faction_id: String) -> int:
	var info := succession_info(state, faction_id)
	if info.is_empty():
		return -1
	return maxi(0, int(info.successor_turn) - state.current_turn)


## The capital's countdown badge and the ruler panel's line while a successor is pending (§5.4): "heir in
## 2 turns" (a mortal line), "re-forms in 4 turns" (undying), "returns in 1 turn" (the god), or "successor
## waits for the capital" when it is due but the capital isn't held. "" while the ruler lives.
static func countdown_text(state: GameState, faction_id: String) -> String:
	var info := succession_info(state, faction_id)
	if info.is_empty():
		return ""
	var n := successor_countdown(state, faction_id)
	if n <= 0:
		return "successor waits for the capital"
	var what := "heir in"
	match String(info.kind):
		"undying":
			what = "re-forms in"
		"god":
			what = "returns in"
	return "%s %d %s" % [what, n, "turn" if n == 1 else "turns"]


# --- validation (GameState.validate) --------------------------------------------------------------

## Checks every ruler rule a state must keep (§9): known rulers of the right faction, kept power 0..10
## and never more than the pool minus what was spent, known mandates taken once each and allowed for
## the faction, and ruler armies that hold only their own faction's living ruler (at most one each).
## Appends plain-language messages to `errors` (or push_error when it isn't an Array).
static func validate(state: GameState, errors = null) -> bool:
	var factions_ok := validate_factions(state, errors)
	return validate_armies(state, errors) and factions_ok


## The faction half of validate(): rulers, kept power, mandates, sacrifices and successors.
## GameState.from_dict runs it before loading armies, so these problems are named first.
static func validate_factions(state: GameState, errors = null) -> bool:
	var ok := true
	for f in state.factions:
		var name := f.faction_name if not f.faction_name.is_empty() else "A faction"
		if not f.has_ruler():
			if not f.mandates.is_empty():
				_report(errors, "%s has mandates but no ruler. Mandates are bought with a ruler's power." % name)
				ok = false
			continue
		var r := ruler_data(f.ruler_type)
		if r.is_empty():
			_report(errors, "%s is led by '%s', which is not a ruler in this game." % [name, f.ruler_type])
			ok = false
			continue
		if r.faction != f.id:
			_report(errors, "%s can't be led by %s, who leads the %s." % [name, ruler_name(f.ruler_type),
				_faction_name(state, r.faction)])
			ok = false
		if f.kept_power < 0 or f.kept_power > RulerData.POWER_POOL:
			_report(errors, "%s has %d kept power, but kept power is always from 0 to %d." % [name, f.kept_power, RulerData.POWER_POOL])
			ok = false
		var seen := {}
		var sacrificed := {}
		var spent := 0
		for sac in f.sacrifices:
			var smid := str(sac.get("mandate", ""))
			if not f.mandates.has(smid):
				_report(errors, "%s has a sacrifice for %s, which is not one of its mandates." % [name,
					mandate_name(smid) if not mandate_data(smid).is_empty() else "'%s'" % smid])
				ok = false
			if int(sac.get("cost", 0)) < 1 or int(sac.get("turn", 0)) < 1:
				_report(errors, "%s has a sacrifice with no turn or no cost." % name)
				ok = false
			sacrificed[smid] = true
			spent += int(sac.get("cost", 0))
		var pre_game := 0
		for mid in f.mandates:
			var md := mandate_data(mid)
			if md.is_empty():
				_report(errors, "%s has '%s', which is not a mandate in this game." % [name, mid])
				ok = false
				continue
			if seen.has(mid):
				_report(errors, "%s has %s twice. Each mandate can be taken only once." % [name, md.name])
				ok = false
			seen[mid] = true
			if not String(md.faction).is_empty() and md.faction != f.id:
				_report(errors, "%s has %s, which only the %s can take." % [name, md.name, _faction_name(state, md.faction)])
				ok = false
			if md.get("sacrifice_only", false) and not sacrificed.has(mid):
				_report(errors, "%s has %s without a sacrifice for it. %s" % [name, md.name, path_mandate_reason(mid, name)])
				ok = false
			if not sacrificed.has(mid):
				pre_game += int(md.cost)
		if pre_game > RulerData.POWER_POOL:
			_report(errors, "%s chose mandates worth %d power before the game, more than the pool of %d." % [name, pre_game, RulerData.POWER_POOL])
			ok = false
		elif f.kept_power > RulerData.POWER_POOL - pre_game - spent:
			_report(errors, "%s has %d kept power, but its mandates and sacrifices leave at most %d. Kept power never goes up." % [
				name, f.kept_power, maxi(0, RulerData.POWER_POOL - pre_game - spent)])
			ok = false
		if f.ruler_generation < 1:
			_report(errors, "%s's ruler has no generation. The first ruler is generation 1." % name)
			ok = false
		if f.ruler_status != ALIVE and f.ruler_status != DEAD:
			_report(errors, "%s's ruler is '%s', but a ruler is either alive or dead." % [name, f.ruler_status])
			ok = false
		if f.successor_turn < 0 or f.successor_power < 0 or f.successor_power > RulerData.POWER_POOL:
			_report(errors, "%s has a successor due with numbers out of range (kept power is always from 0 to %d)." % [name, RulerData.POWER_POOL])
			ok = false
	return ok


## The army half of validate(): no ruler among units or commanders, and every ruler's army holds
## only its own faction's living ruler, at most one per faction.
static func validate_armies(state: GameState, errors = null) -> bool:
	var ok := true
	var ruler_armies := {}
	for a in state.armies:
		var where := _province_name(state, a.location)
		for u in a.units:
			if u.type != null and u.type.is_ruler:
				_report(errors, "A ruler is listed among the units of an army at %s. A ruler travels alone, as its own army." % where)
				ok = false
		if a.commander != null and a.commander.type != null and a.commander.type.is_ruler:
			_report(errors, "A ruler is listed as the commander of an army at %s. Rulers are not commanders." % where)
			ok = false
		if a.ruler == null:
			continue
		var f := state.find_faction(a.owner)
		var fname := _faction_name(state, a.owner)
		if f == null or not f.has_ruler():
			_report(errors, "An army of %s at %s holds a ruler, but %s has no ruler in this game." % [fname, where, fname])
			ok = false
			continue
		if not a.units.is_empty() or a.commander != null:
			_report(errors, "The %s ruler's army at %s also holds units or a commander. A ruler travels alone, as its own army." % [fname, where])
			ok = false
		if a.ruler.type == null or a.ruler.type.id != f.ruler_type or not a.ruler.type.is_ruler:
			_report(errors, "The %s ruler's army at %s holds someone other than its ruler, %s." % [fname, where, current_name(state, f.id)])
			ok = false
		elif a.ruler.current_hp < 1 or a.ruler.current_hp > a.ruler.type.hp:
			_report(errors, "%s has %d of %d hit points. A ruler on the map has at least 1 and at most its maximum." % [
				_cap(a.ruler.type.name), a.ruler.current_hp, a.ruler.type.hp])
			ok = false
		if a.ruler.owner != a.owner:
			_report(errors, "The %s ruler's army at %s holds a ruler that belongs to someone else." % [fname, where])
			ok = false
		if f.ruler_status == DEAD:
			_report(errors, "The %s ruler is dead, but its ruler's army is still at %s." % [fname, where])
			ok = false
		if ruler_armies.has(a.owner):
			_report(errors, "%s has more than one ruler's army. A faction has at most one living ruler." % fname)
			ok = false
		ruler_armies[a.owner] = true
	return ok


# --- helpers --------------------------------------------------------------------------------------

## "Aurel Crown's", "Thornmane Clans'".
static func _possessive(name: String) -> String:
	return name + ("'" if name.ends_with("s") else "'s")


## "an Aurel Crown", "a Thornmane Clans": the name with its indefinite article.
static func _a(name: String) -> String:
	return ("an %s" if not name.is_empty() and "AEIOUaeiou".contains(name.substr(0, 1)) else "a %s") % name


## A name with its first letter capitalised, for the start of a sentence ("The Ever-Regent ...").
static func _cap(text: String) -> String:
	return text if text.is_empty() else text.substr(0, 1).to_upper() + text.substr(1)


static func _faction_display(faction_id: String) -> String:
	for f in FactionData.FACTIONS:
		if f.id == faction_id:
			return f.name
	return "that faction"


static func _faction_name(state: GameState, faction_id: String) -> String:
	var f := state.find_faction(faction_id)
	return f.faction_name if f else _faction_display(faction_id)


static func _province_name(state: GameState, province_id: String) -> String:
	var p := state.find_province(province_id)
	return p.name if p else "a place not on the map"


static func _or_list(items: Array) -> String:
	return _joined(items, "or")


static func _and_list(items: Array) -> String:
	return _joined(items, "and")


static func _joined(items: Array, word: String) -> String:
	if items.size() <= 1:
		return "".join(items)
	return "%s %s %s" % [", ".join(items.slice(0, items.size() - 1)), word, items.back()]


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)


## A refused check in the shape TurnResolver's checks use: {"code", "reason"}.
static func _refusal(code: String, reason: String) -> Dictionary:
	return {"code": code, "reason": reason}
