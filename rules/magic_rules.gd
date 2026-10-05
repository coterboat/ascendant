class_name MagicRules
## The magic rules (M5 "magic and fog of war", design/M5_MAGIC_FOG.md §3-§8). Pure functions over GameState and
## data/magic.gd (MagicData): no nodes, no scenes, no randomness (spells and rituals never draw). This is the single
## source the resolver, OrderBook, Forecast, Breakdown, the AI and every screen read, so a number can never
## disagree with itself. Player-facing text: RulesCodex "magic", "school_*", "spell_*", "node_*_mastery",
## "caster", "mage", "mastery", "spellbook", "ritual", "cast_order", "pinned" and the rest of the magic block.
##
## Magic is OPT-IN at game setup, as paths are: GameState.with_magic(seed, builds) is the paths game plus magic
## (GameState.magic). Without it every function here reads "no magic": no spells, no casters, no rituals, and no
## magic key is saved, so M1, M2 and M4 games are byte-identical to before.
##
## M5-0 (#111) made the state's fields (GameState.magic, enchantments; Faction.spellbook, enchant_counter,
## bastions; UnitType.summoned; Unit.until) and their checks. M5-5 (#116), the first half of the rules:
## Data and reading a game:
##   has_magic(state), spell_data(id), spell_name(id), school_data(id), school_name(id), schools(fid)
##   is_ritual(id), is_battle_spell(id), arcana_ids(fid), arcana_node(id)
##   mage_data(fid), mage_type(fid), is_mage(ut), summon_type(id), summon_types(), ruler_magic(ruler id)
##   known_spells(state, fid), knows(state, fid, spell), knows_a_spell(state, fid)   researched spells (Far Sight
##                                             needs no research); a mage can be recruited once one is known
##   battle_spells(state, fid, caster_kind)    the battle spells a mage or the ruler casts (the Ever-Regent's own
##                                             Sunlance from turn 1)
##   spellbook(state, fid), check_spellbook(state, fid, order), set_spellbook(state, fid, order)
## Casters and mastery (§3.2):
##   casters(state, army)                      [{"kind" ("mage" | "ruler"), "unit", "type", "schools", "battle"}]
##   caster_for(state, fid, army, ritual)      the caster that casts a ritual from that army, or {}
##   mastery_bonus(state, fid, school, kind)   {"value", "raw", "parts", "capped"}: per school, with the +3 cap
##   army_bonus(state, fid, army, school)      the best caster's bonus in that army
##   spell_numbers(spell, bonus, forest)       {"value", "count", "duration"} with mastery added
## Rituals and their orders (§6.1, §7.1):
##   distances(state, from), ritual_targets(state, fid, ritual, army id), check_target(...)
##   price(state, fid, ritual, size)           {"gold", "parts"}; only the wolves' price scales
##   pack_sizes(state, fid, army)              [least, most] wolves Call the Pack may call
##   blood_plan(state, army id, amount)        Tithe of Blood: who bleeds what, one soldier at a time
##   check_cast(state, fid, order, existing)   {} or {"code", "reason"}, with the running budget
##   pinned_armies(state, fid, orders)         {army id: ritual} for every legal cast in the list: those hold
##   queued_gold(state, fid, orders)           the gold the legal gold-paid casts in the list reserve
## Healing and sight: can_heal(state, fid, province), vision_grants(state, fid).
## Research sold (§4): research_sold(pool) {"gold", "research", "left"}.
## Text: mage_gate_reason, pinned_reason, sold_text, mastery_text, caster_name.
## The saved form of enchantments (enchantment_copy, enchantment_from_dict) and validate (every magic field
## checked against GameState.magic and MagicData).
## M5-6 adds the rituals phase and the enchantments phase; M5-7 the battle spells.

## The kinds of ritual that leave an enchantment in GameState.enchantments (§3.4, §6.2-§6.4). Summons leave
## creatures (Unit.until) and raisings leave a fort (Faction.bastions) instead.
const ENCHANTMENT_KINDS := ["blessing", "ward", "curse", "global", "sight"]
## An enchantment's fields, in the order they are saved (§6.4). Nothing else is saved, so nothing else can leak
## into a view.
const ENCHANTMENT_KEYS := ["id", "ritual", "faction", "kind", "province", "armies", "cast_turn", "until_turn", "bonus", "ending"]
const MAGE := "mage"
const RULER := "ruler"
## The mandate that lets a mage's army pay for rituals in blood (§7.1).
const TITHE_OF_BLOOD := "tithe_of_blood"
const FOREST := "forest"
## Part keys for mastery breakdowns.
const PART_MAGE := "mastery_mage"
const PART_RANK := "mastery_rank"
const PART_TRANSFORMATION := "mastery_transformation"
const PART_NODE := "mastery_node"
const PART_CAP := "mastery_cap"


# --- data lookups ---------------------------------------------------------------------------------

static func has_magic(state: GameState) -> bool:
	return state != null and state.magic


## The spell or ritual with this id (MagicData.SPELLS), or {}.
static func spell_data(spell_id: String) -> Dictionary:
	return MagicData.SPELLS.get(spell_id, {})


static func spell_name(spell_id: String) -> String:
	return String(spell_data(spell_id).get("name", "an unknown spell"))


static func is_battle_spell(spell_id: String) -> bool:
	return spell_data(spell_id).get("battle", false) == true


static func is_ritual(spell_id: String) -> bool:
	return not spell_data(spell_id).is_empty() and not is_battle_spell(spell_id)


static func school_data(school_id: String) -> Dictionary:
	return MagicData.SCHOOLS.get(school_id, {})


## "Sun", "Law", "the Wild", "Blood"; "common" for Far Sight's.
static func school_name(school_id: String) -> String:
	if school_id == MagicData.COMMON:
		return "common"
	return String(school_data(school_id).get("name", school_id))


## The faction's schools, in the Magic tab's order ([] for a faction without magic data).
static func schools(faction_id: String) -> Array:
	return MagicData.FACTION_SCHOOLS.get(faction_id, []).duplicate()


## Whether `faction_id` can ever cast spells of `school_id` (its own schools, and Far Sight's common magic).
static func faction_has_school(faction_id: String, school_id: String) -> bool:
	return school_id == MagicData.COMMON or schools(faction_id).has(school_id)


## The arcana node ids of the faction (§4), in the Magic tab's order.
static func arcana_ids(faction_id: String) -> Array:
	var out := []
	for n in MagicData.ARCANA.get(faction_id, []):
		out.append(String(n.id))
	return out


## The arcana node with this id, with its "faction" added, or {}. AscensionRules.node_data falls back to it.
static func arcana_node(node_id: String) -> Dictionary:
	for fid in MagicData.ARCANA:
		for n in MagicData.ARCANA[fid]:
			if String(n.id) == node_id:
				var copy: Dictionary = n.duplicate(true)
				copy["faction"] = fid
				return copy
	return {}


static func is_arcana(node_id: String) -> bool:
	return not arcana_node(node_id).is_empty()


## The faction's mage row (MagicData.MAGES), or {}.
static func mage_data(faction_id: String) -> Dictionary:
	return MagicData.MAGES.get(faction_id, {})


## The faction's mage as a roster UnitType (a regular unit with the trait Mage), or null.
static func mage_type(faction_id: String) -> UnitType:
	var d := mage_data(faction_id)
	if d.is_empty():
		return null
	var ut := UnitType.new()
	ut.id = String(d.id)
	ut.name = String(d.name)
	ut.hp = int(d.hp)
	ut.attack = int(d.attack)
	ut.defense = int(d.defense)
	ut.morale = int(d.morale)
	ut.cost = int(d.cost)
	ut.trait_id = String(d.trait)
	ut.trait_description = String(AutoBattleResolver.TRAIT_TEXT.get(ut.trait_id, MAGE_TEXT))
	return ut


## What the Mage trait does, should the battle rules ever not name it: since M5-7 AutoBattleResolver.TRAIT_TEXT does,
## and mage_type reads that first.
const MAGE_TEXT := "Mage: casts a spell from your battle spellbook every round instead of attacking, from the second rank (safe while your front rank is at least as big; Fangthrowers and Seraphs can always reach it)."


## True for a mage: a regular unit with the trait Mage.
static func is_mage(ut: UnitType) -> bool:
	return ut != null and not ut.is_commander and not ut.is_ruler and ut.trait_id == MagicData.MAGE_TRAIT


## The ids of every mage type (any faction's).
static func is_mage_id(type_id: String) -> bool:
	for fid in MagicData.MAGES:
		if String(MagicData.MAGES[fid].id) == type_id:
			return true
	return false


## A summoned creature's UnitType (MagicData.SUMMONS), or null: never recruited (cost 0), `summoned` true.
static func summon_type(summon_id: String) -> UnitType:
	var d: Dictionary = MagicData.SUMMONS.get(summon_id, {})
	if d.is_empty():
		return null
	var ut := UnitType.new()
	ut.id = String(d.id)
	ut.name = String(d.name)
	ut.hp = int(d.hp)
	ut.attack = int(d.attack)
	ut.defense = int(d.defense)
	ut.morale = int(d.morale)
	ut.cost = 0
	ut.trait_id = String(d.trait)
	ut.trait_description = String(AutoBattleResolver.TRAIT_TEXT.get(ut.trait_id, ""))
	ut.summoned = true
	return ut


## {summon id: UnitType} for every summoned creature: what GameState.from_dict loads in a magic game.
static func summon_types() -> Dictionary:
	var out := {}
	for sid in MagicData.SUMMONS:
		out[sid] = summon_type(sid)
	return out


## Whether summoned creatures of this type fade (Thornwolves) or stay until they fall (the Greenwrath).
static func summon_fades(type_id: String) -> bool:
	return MagicData.SUMMONS.get(type_id, {}).get("fades", false) == true


## The build screen's magic line for ruler `ruler_id` at `kept` power (§7.3), one short sentence with its number at the
## start of a game (mastery = ability rank - 1, at most the cap): "Magic: casts Sunlance in battle (5 damage now) and
## every Crown spell you research." / "Magic: casts Wild rituals, up to 4 wolves (20 gold) once you research Call the
## Pack." / "Magic: casts nothing, an ordinary man." The card's tooltip and the codex say the rest.
static func ruler_line(ruler_id: String, kept: int) -> String:
	var rm := ruler_magic(ruler_id)
	var own: Array = rm.get("schools", [])
	if own.is_empty():
		return "Magic: casts nothing, an ordinary man."
	var bonus := mini(RulerRules.ability_rank(kept) - 1, int(MagicData.MASTERY.cap))
	var faction := String(school_data(String(own[0])).get("faction", ""))
	var who := _faction_display(null, faction).get_slice(" ", _faction_display(null, faction).get_slice_count(" ") - 1)
	if not String(rm.get("own_spell", "")).is_empty():
		var sid := String(rm.own_spell)
		return "Magic: casts %s in battle (%d damage now) and every %s spell you research." % [spell_name(sid),
			int(spell_numbers(sid, bonus).value), who]
	var ritual := String(school_data(String(own[0])).nodes[1])
	var n := spell_numbers(ritual, bonus)
	var school := school_name(String(own[0]))
	if ritual == "call_the_pack":
		return "Magic: casts %s rituals, up to %d wolves (%d gold) once you research Call the Pack." % [school.trim_prefix("the "),
			n.count, n.count * int(spell_data(ritual).cost)]
	return "Magic: casts %s rituals; %s takes %d hit points a turn once researched." % [school.trim_prefix("the "), spell_name(ritual), n.value]


## The ruler's magic (MagicData.RULER_MAGIC): {"schools", "battle", "own_spell", "line"}, or {}.
static func ruler_magic(ruler_id: String) -> Dictionary:
	return MagicData.RULER_MAGIC.get(ruler_id, {})


# --- reading a game -------------------------------------------------------------------------------

## The spells and rituals `faction_id` has researched, in the order done ([] without magic). Far Sight needs no
## research, so it is never listed here (knows() answers for it).
static func known_spells(state: GameState, faction_id: String) -> Array:
	if not has_magic(state):
		return []
	var out := []
	for nid in AscensionRules.researched(state, faction_id):
		if not spell_data(nid).is_empty():
			out.append(nid)
	return out


## Whether `faction_id` knows `spell_id`: researched, or Far Sight (every faction in a magic game knows it; casting
## it still needs a caster).
static func knows(state: GameState, faction_id: String, spell_id: String) -> bool:
	if not has_magic(state):
		return false
	if spell_id == "far_sight":
		return true
	return known_spells(state, faction_id).has(spell_id)


## The mage gate (§3.2): a faction can recruit its mage once it has researched a spell. The Ever-Regent's own
## Sunlance doesn't count.
static func knows_a_spell(state: GameState, faction_id: String) -> bool:
	return not known_spells(state, faction_id).is_empty()


## The battle spells a caster of `faction_id` casts (§5.1, §7.2): for a mage, the faction's researched battle
## spells; for the ruler, those of its schools if it casts in battle (only the Ever-Regent), plus its own spell
## (Sunlance) from turn 1. In MagicData.SPELLBOOK order.
static func battle_spells(state: GameState, faction_id: String, caster_kind: String = MAGE) -> Array:
	if not has_magic(state):
		return []
	var known := known_spells(state, faction_id)
	var rm := {}
	if caster_kind == RULER:
		var f := state.find_faction(faction_id)
		rm = ruler_magic(f.ruler_type) if f != null else {}
		if rm.get("battle", false) != true:
			return []
	var out := []
	for sid in MagicData.SPELLBOOK.get(faction_id, []):
		if known.has(sid) or (caster_kind == RULER and String(rm.get("own_spell", "")) == sid):
			out.append(sid)
	return out


## The faction's battle spellbook (§5.1): {"order": every battle spell of its schools, in the order its casters
## try them, "off": the ones switched off}. Faction.spellbook, or MagicData.SPELLBOOK's default when it is {}.
static func spellbook(state: GameState, faction_id: String) -> Dictionary:
	var f: Faction = state.find_faction(faction_id) if state != null else null
	var default: Array = MagicData.SPELLBOOK.get(faction_id, [])
	if f == null or f.spellbook.is_empty():
		return {"order": default.duplicate(), "off": []}
	return {"order": Serial.to_string_array(f.spellbook.get("order", default)), "off": Serial.to_string_array(f.spellbook.get("off", []))}


## {} when `order` (a SpellbookOrder) may set `faction_id`'s spellbook now, otherwise {"code", "reason"}: the game
## has magic, and the order lists every battle spell of the faction's schools once, with only those switched off.
static func check_spellbook(state: GameState, faction_id: String, order) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _refusal("unknown_faction", "Those orders are for a faction that is not in this game.")
	if not has_magic(state):
		return _refusal("no_magic", NO_MAGIC)
	var spells: Array = MagicData.SPELLBOOK.get(faction_id, [])
	var names := spells.map(func(s): return spell_name(String(s)))
	var listed := {}
	for sid in order.order:
		if not spells.has(sid):
			var what := "'%s' is not a spell in this game" % sid if spell_data(sid).is_empty() \
				else ("%s is a ritual, cast with an order" % spell_name(sid) if is_ritual(sid) else "%s is not one of your battle spells" % spell_name(sid))
			return _refusal("unknown_spell", "%s. Your spellbook lists your battle spells: %s." % [Serial.cap(what), _and_list(names)])
		if listed.has(sid):
			return _refusal("spell_twice", "%s is in the spellbook twice. List each battle spell once, in the order your casters should try them." % spell_name(sid))
		listed[sid] = true
	for sid in spells:
		if not listed.has(sid):
			return _refusal("spell_missing", "The spellbook leaves out %s. List every battle spell (%s) and switch off the ones you don't want cast." % [
				spell_name(String(sid)), _and_list(names)])
	for sid in order.off:
		if not listed.has(sid):
			return _refusal("unknown_spell", "Only spells in the spellbook can be switched off, and '%s' isn't one." % sid)
	return {}


## Sets `faction_id`'s spellbook from a checked SpellbookOrder (the orders phase). The default order with nothing
## off is stored as {}, so a spellbook set back to the default saves as one that was never changed.
static func set_spellbook(state: GameState, faction_id: String, order) -> void:
	var f := state.find_faction(faction_id)
	if f == null:
		return
	var default: Array = MagicData.SPELLBOOK.get(faction_id, [])
	if order.order == default and order.off.is_empty():
		f.spellbook = {}
	else:
		var off := []
		for sid in order.order:
			if order.off.has(sid) and not off.has(sid):
				off.append(sid)
		f.spellbook = {"order": order.order.duplicate(), "off": off}


# --- casters and mastery (§3.2) -------------------------------------------------------------------

## The casters in `army`, in fighter order: each standing mage, then the ruler if it can cast (every ruler but King
## Corvane). [{"kind": "mage" | "ruler", "unit", "type" (type id), "name", "schools" (whose rituals it casts),
## "battle" (whether it casts in battle)}]. [] without magic.
static func casters(state: GameState, army: Army) -> Array:
	var out := []
	if not has_magic(state) or army == null:
		return out
	for u in army.units:
		if is_mage(u.type) and u.current_hp > 0:
			out.append({"kind": MAGE, "unit": u, "type": u.type.id, "name": u.type.name, "schools": schools(army.owner), "battle": true})
	if army.ruler != null:
		var f := state.find_faction(army.owner)
		var rm := ruler_magic(f.ruler_type) if f != null else {}
		var own: Array = rm.get("schools", [])
		if not own.is_empty():
			out.append({"kind": RULER, "unit": army.ruler, "type": army.ruler.type.id, "name": RulerRules.current_name(state, army.owner),
				"schools": own.duplicate(), "battle": rm.get("battle", false) == true})
	return out


## The caster in `army` that casts `ritual` (§6.1): a mage for any of the faction's schools and Far Sight, the ruler
## for its own schools and Far Sight. With several, the one with the highest mastery in the ritual's school (the
## ruler first among equals). {} when none can.
static func caster_for(state: GameState, faction_id: String, army: Army, ritual: String) -> Dictionary:
	var school := String(spell_data(ritual).get("school", ""))
	var best := {}
	var best_bonus := -1
	for c in casters(state, army):
		if school != MagicData.COMMON and not c.schools.has(school):
			continue
		var bonus := int(mastery_bonus(state, faction_id, school, String(c.kind)).value)
		if bonus > best_bonus or (bonus == best_bonus and c.kind == RULER):
			best = c
			best_bonus = bonus
	return best


## A caster's mastery in one school (§3.2), as a bonus with its parts: a mage +0; a ruler + (ability rank - 1) in its
## own schools; the faction's transformation +1 in its aligned school; the school's mastery node +1; at most +3
## (a part "capped at +3" takes off the rest, so the parts always sum to the value). Far Sight's common magic has no
## mastery. Returns {"school", "kind", "value", "raw", "capped", "parts": [{"key", "name", "value", "note"}]}.
static func mastery_bonus(state: GameState, faction_id: String, school: String, caster_kind: String = MAGE) -> Dictionary:
	var out := {"school": school, "kind": caster_kind, "value": 0, "raw": 0, "capped": false, "parts": []}
	if not has_magic(state) or school_data(school).is_empty():
		return out
	var f := state.find_faction(faction_id)
	if f == null:
		return out
	var parts := []
	if caster_kind == RULER:
		var own: Array = ruler_magic(f.ruler_type).get("schools", [])
		var rank := RulerRules.ability_rank(f.kept_power)
		if own.has(school):
			parts.append({"key": PART_RANK, "name": "ability rank %d" % rank, "value": rank - 1,
				"note": "a ruler's mastery is its ability rank - 1"})
		else:
			parts.append({"key": PART_RANK, "name": "%s's schools" % Serial.cap(RulerRules.current_name(state, faction_id)), "value": 0,
				"note": "%s is not of its schools" % school_name(school)})
	else:
		parts.append({"key": PART_MAGE, "name": "a mage", "value": int(MagicData.MASTERY.mage), "note": "a mage starts at +0"})
	var aligned := String(school_data(school).get("aligned_branch", ""))
	var trans := AscensionRules.transformation(state, faction_id)
	if not trans.is_empty() and String(AscensionRules.node_data(trans).get("branch", "")) == aligned:
		parts.append({"key": PART_TRANSFORMATION, "name": AscensionRules.branch_name(aligned), "value": int(MagicData.MASTERY.transformation),
			"note": "the transformation adds +1 in its aligned school"})
	var node := String(MagicData.MASTERY_NODES.get(school, ""))
	if AscensionRules.has_node(state, faction_id, node):
		parts.append({"key": PART_NODE, "name": AscensionRules.node_name(node), "value": int(MagicData.MASTERY.node),
			"note": "the mastery node adds +1 for every caster"})
	var raw := 0
	for p in parts:
		raw += int(p.value)
	var cap := int(MagicData.MASTERY.cap)
	if raw > cap:
		parts.append({"key": PART_CAP, "name": "capped at +%d" % cap, "value": cap - raw, "note": "mastery is at most +%d" % cap})
	out.raw = raw
	out.value = mini(raw, cap)
	out.capped = raw > cap
	out.parts = parts
	return out


## The best mastery in `school` among `army`'s casters that cast that school (0 when none does).
static func army_bonus(state: GameState, faction_id: String, army: Army, school: String) -> int:
	var best := 0
	for c in casters(state, army):
		if c.schools.has(school):
			best = maxi(best, int(mastery_bonus(state, faction_id, school, String(c.kind)).value))
	return best


## A spell's numbers with `bonus` points of mastery in its school (§3.2): {"value" (bolt damage, a part, or a
## ritual's hp budget), "count" (units covered, or the most wolves), "duration" (turns after the cast turn)}.
## `forest`: a battle in a forest province (Briar Snare covers more there).
static func spell_numbers(spell_id: String, bonus: int = 0, forest: bool = false) -> Dictionary:
	var sp := spell_data(spell_id)
	var per: Dictionary = sp.get("per_bonus", {})
	var count := int(sp.get("forest_count", sp.get("count", 0))) if forest else int(sp.get("count", 0))
	return {"value": int(sp.get("value", 0)) + int(per.get("value", 0)) * bonus,
		"count": count + int(per.get("count", 0)) * bonus,
		"duration": int(sp.get("duration", 0)) + (int(per.get("duration", 0)) * bonus if int(sp.get("duration", 0)) >= 0 else 0)}


# --- rituals and their orders (§6.1, §6.2, §7.1) ---------------------------------------------------

## Steps from `from` to every province, along the map's neighbour links: {province id: steps}.
static func distances(state: GameState, from: String) -> Dictionary:
	var out := {}
	if state.find_province(from) == null:
		return out
	out[from] = 0
	var frontier := [from]
	while not frontier.is_empty():
		var next := []
		for pid in frontier:
			var p := state.find_province(pid)
			for n in p.neighbors:
				if not out.has(n):
					out[n] = int(out[pid]) + 1
					next.append(n)
		frontier = next
	return out


## The provinces `ritual` may target when cast from `army_id` now (range and target rule, §6.2), sorted. ["" ] for a
## ritual with no target (the Blood Moon). [] when the army can't cast it at all.
static func ritual_targets(state: GameState, faction_id: String, ritual: String, army_id: String) -> Array:
	var army := state.find_army(army_id)
	if army == null or not is_ritual(ritual):
		return []
	if String(spell_data(ritual).target) == "none":
		return [""] if check_target(state, faction_id, ritual, army, "").is_empty() else []
	var out := []
	for p in state.provinces:
		if check_target(state, faction_id, ritual, army, p.id).is_empty():
			out.append(p.id)
	out.sort()
	return out


## {} when `target` fits `ritual` cast from `army` (§6.2): in range, and the target rule. Only public facts and the
## faction's own state are read (§2.10): owners, forts, terrain, the map, its own armies, packs and Bastion forts,
## and the global ritual in the sky.
static func check_target(state: GameState, faction_id: String, ritual: String, army: Army, target: String) -> Dictionary:
	var sp := spell_data(ritual)
	var rule := String(sp.get("target", ""))
	var f := state.find_faction(faction_id)
	if rule == "none":
		if not target.is_empty():
			return _refusal("bad_target", "%s has no target: it covers every battle." % spell_name(ritual))
		for e in state.enchantments:
			if String(e.kind) == "global" and String(e.ritual) != ritual:
				return _refusal("global_up", "%s is already up, through turn %d. Only one global ritual can be up at a time." % [
					spell_name(String(e.ritual)), int(e.until_turn)])
		return {}
	var p := state.find_province(target)
	if p == null:
		return _refusal("unknown_target", "%s needs a province to aim at, and '%s' is not a province on this map." % [spell_name(ritual), target])
	var reach := int(sp.get("range", 0))
	if rule == "caster" or rule == "caster_forest":
		if target != army.location:
			return _refusal("bad_target", "%s is cast on the caster's own province, %s." % [spell_name(ritual), _province_name(state, army.location)])
	else:
		var steps := int(distances(state, army.location).get(target, -1))
		if steps < 0 or steps > reach:
			return _refusal("out_of_range", "%s reaches %d %s from the caster. %s is %s from your army at %s." % [spell_name(ritual), reach,
				"province" if reach == 1 else "provinces", p.name, "out of reach" if steps < 0 else str(steps), _province_name(state, army.location)])
	match rule:
		"own", "own_with_army", "own_no_fort":
			if p.owner != faction_id:
				return _refusal("not_own", "%s is cast on a province you own, and %s is %s." % [spell_name(ritual), p.name,
					"neutral" if p.owner.is_empty() else "held by the %s" % _faction_display(state, p.owner)])
			if rule == "own_with_army":
				var mine := false
				for a in state.armies:
					if a.owner == faction_id and a.location == p.id:
						mine = true
				if not mine:
					return _refusal("no_army_there", "%s blesses your armies standing in a province, and no army of yours stands at %s." % [spell_name(ritual), p.name])
			if rule == "own_no_fort":
				if p.has_fort:
					return _refusal("has_fort", "%s already has a fort, and %s raises one only where there is none." % [p.name, spell_name(ritual)])
				var cap := int(sp.get("cap", MagicData.BASTION_CAP))
				if f != null and f.bastions.size() >= cap:
					return _refusal("bastion_cap", "You have raised %d Bastion forts, the most a faction can ever raise." % f.bastions.size())
		"not_own":
			if p.owner == faction_id:
				return _refusal("own_province", "%s is cast on a province that isn't yours, and %s is yours." % [spell_name(ritual), p.name])
		"caster_forest":
			if p.terrain != FOREST:
				return _refusal("not_forest", "%s wakes only in a forest, and %s is %s." % [spell_name(ritual), p.name, p.terrain])
	var summon := String(sp.get("summon", ""))
	if not summon.is_empty():
		for a in state.armies:
			if a.owner != faction_id:
				continue
			for u in a.units:
				if u.type.id == summon:
					if summon_fades(summon):
						return _refusal("pack_out", "Your pack at %s is still out: a new pack can be called once the last has faded or fallen." % _province_name(state, a.location))
					return _refusal("summon_awake", "The %s is already awake, at %s. One at a time." % [u.type.name, _province_name(state, a.location)])
	return {}


## The wolves Call the Pack may call from `army` (§6.2): [3, 3 + the best caster's Wild mastery].
static func pack_sizes(state: GameState, faction_id: String, army: Army) -> Array:
	var least := int(spell_data("call_the_pack").get("count", 3))
	return [least, least + army_bonus(state, faction_id, army, "wild")]


## A ritual's price in gold (§6.2): its cost, or Call the Pack's 5 a wolf. Mastery changes no price but the pack's
## size. {"gold", "parts": [{"label", "value", "note"}]}.
static func price(state: GameState, faction_id: String, ritual: String, size: int = 0) -> Dictionary:
	var sp := spell_data(ritual)
	var cost := int(sp.get("cost", 0))
	if String(sp.get("summon", "")) == "thornwolves":
		var wolves := maxi(size, int(sp.get("count", 3)))
		return {"gold": cost * wolves, "parts": [{"label": "%d Thornwolves" % wolves, "value": cost * wolves, "note": "%d gold a wolf" % cost}]}
	return {"gold": cost, "parts": [{"label": spell_name(ritual), "value": cost, "note": "the ritual's price"}]}


## Tithe of Blood's payment plan (§7.1): `amount` hp (1 a gold) from the regular units in the army, one soldier at a
## time: the unit with the most hp left gives until it is at 1, then the next; ties go in army order. Summoned
## creatures and commanders never give. {"ok" (the army can give it all), "amount", "available" (every soldier
## down to 1), "gives": [{"index", "type", "name", "from", "to", "gave"}]}, in the order they give.
static func blood_plan(state: GameState, army_id: String, amount: int) -> Dictionary:
	var army := state.find_army(army_id)
	var out := {"ok": false, "amount": amount, "available": 0, "gives": []}
	if army == null:
		return out
	var hp := {}
	var order := []
	for i in army.units.size():
		var u: Unit = army.units[i]
		if u.type.summoned or u.type.is_commander or u.type.is_ruler:
			continue
		hp[i] = u.current_hp
		order.append(i)
		out.available = int(out.available) + maxi(0, u.current_hp - 1)
	var left := amount
	var given := {}
	while left > 0:
		var pick := -1
		for i in order:
			if int(hp[i]) > 1 and (pick < 0 or int(hp[i]) > int(hp[pick])):
				pick = i
		if pick < 0:
			break
		var give := mini(left, int(hp[pick]) - 1)
		if not given.has(pick):
			given[pick] = {"index": pick, "type": army.units[pick].type.id, "name": army.units[pick].type.name,
				"from": int(hp[pick]), "to": 0, "gave": 0}
			out.gives.append(given[pick])
		hp[pick] = int(hp[pick]) - give
		given[pick].to = int(hp[pick])
		given[pick].gave = int(given[pick].gave) + give
		left -= give
	out.ok = left <= 0
	return out


## {} when `order` (a CastOrder) may join `existing` (the faction's other orders so far, in the order given),
## otherwise {"code", "reason"} with a plain reason (§6.1). Checked against `state` as the faction's sacrifice
## leaves it (OrderBook passes RulerRules.state_after_orders). In order: magic, the ritual (a ritual of your
## schools, known), the army (yours, holding a caster for it), one cast per army and each ritual once per faction,
## the target (range and rule), Call the Pack's size, and the price: gold within the running budget (queued
## recruits and gold-paid rituals together must fit your gold), or blood under Tithe of Blood.
static func check_cast(state: GameState, faction_id: String, order, existing: Array = []) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _refusal("unknown_faction", "Those orders are for a faction that is not in this game.")
	if not has_magic(state):
		return _refusal("no_magic", NO_MAGIC)
	var sp := spell_data(order.ritual)
	if sp.is_empty():
		return _refusal("unknown_ritual", "'%s' is not a ritual in this game." % order.ritual)
	if is_battle_spell(order.ritual):
		return _refusal("battle_spell", "%s is a battle spell: your casters cast it by themselves in battle, from your spellbook. Only rituals are cast with an order." % spell_name(order.ritual))
	var school := String(sp.school)
	if not faction_has_school(faction_id, school):
		return _refusal("foreign_ritual", "%s is a ritual of %s, a school of the %s, so the %s can't cast it." % [spell_name(order.ritual),
			school_name(school), _faction_display(state, String(school_data(school).get("faction", ""))), f.faction_name])
	if not knows(state, faction_id, order.ritual):
		var st := AscensionRules.node_state(state, faction_id, order.ritual)
		var how := " %s" % String(st.reason) if String(st.state) == AscensionRules.NEEDS else \
			" Research it in the Magic tab (%d research)." % AscensionRules.node_cost(order.ritual)
		return _refusal("not_known", "You don't know %s yet.%s" % [spell_name(order.ritual), how])
	var army := state.find_army(order.army_id)
	if army == null:
		return _refusal("unknown_army", "That army is not on the map, so it can't cast %s." % spell_name(order.ritual))
	if army.owner != faction_id:
		return _refusal("not_your_army", "That army is not yours, so it can't cast for you.")
	var caster := caster_for(state, faction_id, army, order.ritual)
	if caster.is_empty():
		return _refusal("no_caster", "Your army at %s holds no caster for %s: %s." % [_province_name(state, army.location),
			spell_name(order.ritual), _who_casts(state, faction_id, school)])
	for o in existing:
		if not (o is CastOrder):
			continue
		if o.army_id == order.army_id:
			return _refusal("one_per_army", "Your army at %s is already casting %s this turn. An army casts one ritual a turn." % [
				_province_name(state, army.location), spell_name(o.ritual)])
		if o.ritual == order.ritual:
			var other := state.find_army(o.army_id)
			return _refusal("once_per_faction", "You are already casting %s this turn, from your army at %s. Each ritual can be cast once a turn." % [
				spell_name(order.ritual), _province_name(state, other.location) if other else "another province"])
	var target := check_target(state, faction_id, order.ritual, army, order.target)
	if not target.is_empty():
		return target
	if String(sp.get("summon", "")) == "thornwolves":
		var sizes := pack_sizes(state, faction_id, army)
		if order.size < int(sizes[0]) or order.size > int(sizes[1]):
			return _refusal("pack_size", "You can call %s Thornwolves from your army at %s (3, +1 for each point of Wild mastery)." % [
				str(sizes[0]) if sizes[0] == sizes[1] else "%d to %d" % [sizes[0], sizes[1]], _province_name(state, army.location)])
	elif order.size != 0:
		return _refusal("no_size", "Only Call the Pack takes a size: how many wolves to call.")
	var cost := int(price(state, faction_id, order.ritual, order.size).gold)
	match order.pay:
		CastOrder.BLOOD:
			if not RulerRules.has_mandate(state, faction_id, TITHE_OF_BLOOD):
				return _refusal("no_tithe", "Paying in blood needs the mandate %s. Pay in gold instead." % RulerRules.mandate_name(TITHE_OF_BLOOD))
			if String(caster.kind) == RULER:
				return _refusal("ruler_pays_gold", "Rituals your ruler casts always cost gold: a ruler stands alone, with no soldiers to bleed.")
			var plan := blood_plan(state, army.id, cost * MagicData.BLOOD_PER_GOLD)
			if not plan.ok:
				return _refusal("short_of_blood", "%s costs %d hit points in blood, but your army at %s can give only %d (each soldier keeps 1)." % [
					spell_name(order.ritual), cost * MagicData.BLOOD_PER_GOLD, _province_name(state, army.location), int(plan.available)])
		CastOrder.GOLD:
			var budget := _gold_left(state, faction_id, existing)
			if cost > int(budget.left):
				return _refusal("not_enough_gold", "%s costs %d gold, but %s." % [spell_name(order.ritual), cost, _left_text(budget)])
		_:
			return _refusal("bad_pay", "A ritual is paid in gold, or in blood under Tithe of Blood.")
	return {}


## {army id: ritual id} for every legal cast in `orders`, each checked against the orders before it (as OrderBook
## takes them): those armies hold this turn (§6.1). {} when there is no cast.
static func pinned_armies(state: GameState, faction_id: String, orders: Array) -> Dictionary:
	var out := {}
	if not orders.any(func(o): return o is CastOrder):
		return out
	var before := []
	for o in orders:
		if o is CastOrder:
			if check_cast(state, faction_id, o, before).is_empty():
				out[o.army_id] = o.ritual
				before.append(o)
		else:
			before.append(o)
	return out


## The gold the legal gold-paid casts in `orders` reserve (the running budget: recruits are priced from what's left).
static func queued_gold(state: GameState, faction_id: String, orders: Array) -> int:
	var total := 0
	if not orders.any(func(o): return o is CastOrder):
		return total
	var before := []
	for o in orders:
		if o is CastOrder:
			if check_cast(state, faction_id, o, before).is_empty():
				before.append(o)
				if o.pay == CastOrder.GOLD:
					total += int(price(state, faction_id, o.ritual, o.size).gold)
		else:
			before.append(o)
	return total


## Why an army can't move: "Your army at Fangridge is casting Bloodrot this turn, so it holds." `lower` starts it
## with a small letter, for "Move to Thornvale removed: ..." lines.
static func pinned_reason(state: GameState, army_id: String, ritual: String, lower: bool = false) -> String:
	var army := state.find_army(army_id)
	var where := _province_name(state, army.location) if army else "its province"
	var text := "your army at %s is casting %s this turn, so it holds." % [where, spell_name(ritual)]
	return text if lower else Serial.cap(text)


# --- healing and sight ------------------------------------------------------------------------------

## Whether `faction_id`'s fighters in `province_id` can heal now (§6.3): not while a rival's Bloodrot lies on it. A
## border battle is in no province (""), so nobody there is cursed. True in every game without magic.
static func can_heal(state: GameState, faction_id: String, province_id: String) -> bool:
	if not has_magic(state) or province_id.is_empty():
		return true
	for e in state.enchantments:
		if String(e.kind) == "curse" and String(e.province) == province_id and String(e.faction) != faction_id:
			return false
	return true


## The province ids `faction_id` sees in clear sight through magic (Far Sight, §6.2, §6.4), sorted. FogRules.sight
## (M5-1) calls it. Still M5-0's stub, which grants nothing: Far Sight is cast only once the rituals phase exists
## (M5-6), and M5-6 turns this on with it (reading the faction's "sight" enchantments), so no fog game sees anything
## through magic before a ritual can put it there.
static func vision_grants(_state: GameState, _faction_id: String) -> Array:
	return []


# --- research sold (§4) -----------------------------------------------------------------------------

## What a pool of `pool` research sells for once nothing is left to research: {"gold" (pool / RESEARCH_SOLD,
## rounded down), "research" (what that gold took), "left" (the spare points, carried)}.
static func research_sold(pool: int) -> Dictionary:
	var gold := floori(float(maxi(0, pool)) / MagicData.RESEARCH_SOLD)
	return {"gold": gold, "research": gold * MagicData.RESEARCH_SOLD, "left": pool - gold * MagicData.RESEARCH_SOLD}


## The research_sold sentence (§4), for the turn report, which names the faction (in hotseat every seat reads it;
## under fog only its own, FogData.AUDIENCE): "Nothing is left for the Aurel Crown to research, so its scholars
## sold their learning: 10 research for 5 gold (2 research a gold). 1 research is carried to next turn." `sold` is
## a research_sold() result.
static func sold_text(state: GameState, faction_id: String, sold: Dictionary) -> String:
	var text := "Nothing is left for %s to research, so its scholars sold their learning: %d research for %d gold (%d research a gold)." % [
		AscensionRules._the_faction(state, faction_id), int(sold.research), int(sold.gold), MagicData.RESEARCH_SOLD]
	if int(sold.left) > 0:
		text += " %d research is carried to next turn." % int(sold.left)
	return text


## The research_done sentence for an arcana node (§4, §11.2), for the turn report: what it is, its one plain line
## (MagicData), and, for the faction's first spell, the mage gate opening. `state` is the state after the node is
## done, at the end of `turn`. "Sunlance researched by the Aurel Crown: a battle spell of the Sun. 4 sure damage to
## ... The Aurel Crown can now recruit Sunstone Adepts at Crownkeep, from turn 3."
static func done_text(state: GameState, faction_id: String, node_id: String, turn: int) -> String:
	var n := arcana_node(node_id)
	var who := AscensionRules._the_faction(state, faction_id)
	var school := String(n.get("school", ""))
	var text := "%s researched by %s: " % [AscensionRules.node_name(node_id), who]
	if String(n.get("kind", "")) == MagicData.MASTERY_KIND:
		text += "+%d mastery in %s for every caster of theirs (at most +%d)." % [int(MagicData.MASTERY.node), school_ref(school), int(MagicData.MASTERY.cap)]
		return text
	var sp := spell_data(node_id)
	if is_battle_spell(node_id):
		text += "a battle spell of %s. %s" % [school_ref(school), String(sp.text)]
	else:
		text += "a ritual of %s, cast on the map with an order. %s" % [school_ref(school), String(sp.text)]
	if known_spells(state, faction_id) == [node_id]:
		var mage := String(mage_data(faction_id).get("name", ""))
		var f := state.find_faction(faction_id)
		var cap := state.find_province(f.capital) if f != null else null
		if not mage.is_empty():
			text += " %s can now recruit %s at %s, from turn %d." % [Serial.cap(who), mage, cap.name if cap else "their capital", turn + 1]
	return text


## "the Sun", "Law", "the Wild", "Blood": a school as running text reads it (MagicData.SCHOOLS "ref").
static func school_ref(school_id: String) -> String:
	return String(school_data(school_id).get("ref", school_name(school_id)))


# --- text -------------------------------------------------------------------------------------------

const NO_MAGIC := "This game is played without magic, so there are no spells or rituals. Magic is a preview: tick Magic (M5 preview) when you set up a new game."


## Why a mage can't be recruited yet (§3.2): "The Sunstone Adepts can be recruited once the Aurel Crown knows a
## spell. Research Sunlance or Shield of Law (10 research). The Ever-Regent's own Sunlance doesn't count."
static func mage_gate_reason(state: GameState, faction_id: String, ut: UnitType) -> String:
	var firsts := []
	for school in schools(faction_id):
		var first := String(school_data(school).nodes[0])
		firsts.append(spell_name(first))
	var cost := AscensionRules.node_cost(String(school_data(schools(faction_id)[0]).nodes[0])) if not schools(faction_id).is_empty() else 0
	var text := "The %s can be recruited once the %s knows a spell. Research %s (%d research)." % [ut.name if ut else "mages",
		_faction_display(state, faction_id), _or_list(firsts), cost]
	var f := state.find_faction(faction_id)
	var own := String(ruler_magic(f.ruler_type).get("own_spell", "")) if f != null else ""
	if not own.is_empty():
		text += " %s's own %s doesn't count." % [Serial.cap(RulerRules.current_name(state, faction_id)), spell_name(own)]
	return text


## "Mastery in the Sun +2: ability rank 2 (+1) and Celestial Host (+1)" from a mastery_bonus() result.
static func mastery_text(bonus: Dictionary) -> String:
	var bits := []
	for p in bonus.parts:
		bits.append("%s (%s)" % [p.name, _signed(int(p.value))])
	return "Mastery in %s %s: %s" % [school_name(String(bonus.school)), _signed(int(bonus.value)), _and_list(bits)]


## A spellbook as a list: "Sunburst (off), Sunlance and Shield of Law" (`order` in order, `off` switched off).
static func spellbook_text(order: Array, off: Array) -> String:
	var names := []
	for sid in order:
		names.append("%s%s" % [spell_name(String(sid)), " (off)" if off.has(sid) else ""])
	return _and_list(names)


## A caster for messages: "your Thornmane Shamans" or "the Ninth Fang".
static func caster_name(caster: Dictionary) -> String:
	if caster.is_empty():
		return "no caster"
	return String(caster.name) if String(caster.kind) == RULER else "your %s" % String(caster.name)


## Who can cast a ritual of `school` for the faction: "a Thornmane Shaman, or the Ninth Fang (Blood rituals)".
static func _who_casts(state: GameState, faction_id: String, school: String) -> String:
	var mage := String(mage_data(faction_id).get("name", "a mage"))
	var f := state.find_faction(faction_id)
	var rm := ruler_magic(f.ruler_type) if f != null and f.has_ruler() else {}
	var own: Array = rm.get("schools", [])
	if school == MagicData.COMMON:
		return "%s, or a ruler who casts rituals" % mage if own.is_empty() else "%s, or %s" % [mage, RulerRules.current_name(state, faction_id)]
	if own.has(school):
		return "%s, or %s (%s rituals)" % [mage, RulerRules.current_name(state, faction_id), school_name(school)]
	return mage


## {"left" (gold not yet spoken for), "gold", "recruits" (what the queued recruits and Fortify orders spend),
## "rituals" (what the queued gold-paid casts reserve)} for the running budget.
static func _gold_left(state: GameState, faction_id: String, existing: Array) -> Dictionary:
	var f := state.find_faction(faction_id)
	var spending := []
	for o in existing:
		if o is RecruitOrder or o is FortifyOrder:
			spending.append(o)
	var recruits := 0
	if not spending.is_empty():
		recruits = int(TurnResolver.price_recruits(state, faction_id, spending).spent)
	var rituals := queued_gold(state, faction_id, existing)
	return {"gold": f.gold, "recruits": recruits, "rituals": rituals, "left": f.gold - recruits - rituals}


static func _left_text(budget: Dictionary) -> String:
	var spoken := []
	if int(budget.recruits) > 0:
		spoken.append("your queued recruits (%d)" % int(budget.recruits))
	if int(budget.rituals) > 0:
		spoken.append("your queued rituals (%d)" % int(budget.rituals))
	if spoken.is_empty():
		return "you have only %d gold" % int(budget.gold)
	return "after %s you have %d gold left" % [_and_list(spoken), maxi(0, int(budget.left))]


# --- the saved form -------------------------------------------------------------------------------

## Enchantment `e` in its saved form: exactly ENCHANTMENT_KEYS in that order, texts as text, turns and the bonus as
## ints (JSON reads them back as floats), `armies` as a list of ids and `ending` as true or false.
static func enchantment_copy(e: Dictionary) -> Dictionary:
	return {
		"id": _text(e, "id"),
		"ritual": _text(e, "ritual"),
		"faction": _text(e, "faction"),
		"kind": _text(e, "kind"),
		"province": _text(e, "province"),
		"armies": Serial.to_string_array(e.get("armies", [])),
		"cast_turn": Serial.to_int(e.get("cast_turn", 0)),
		"until_turn": Serial.to_int(e.get("until_turn", 0)),
		"bonus": Serial.to_int(e.get("bonus", 0)),
		"ending": e.get("ending") == true,
	}


## Reads one saved enchantment (GameState.from_dict). Returns null when a field has the wrong type, with a
## plain-language reason in `errors` (Serial load checks); validate checks what the values mean.
static func enchantment_from_dict(data: Dictionary, errors = null, who: String = "") -> Variant:
	if who.is_empty():
		who = Serial.label("enchantment", data)
	for key in ["id", "ritual", "faction", "kind", "province"]:
		if Serial.expect(data, key, TYPE_STRING, errors, who, "") == null:
			return null
	if Serial.expect(data, "armies", TYPE_ARRAY, errors, who, []) == null:
		return null
	if Serial.expect(data, "ending", TYPE_BOOL, errors, who, false) == null:
		return null
	return enchantment_copy(data)


# --- checks ---------------------------------------------------------------------------------------

## Checks the magic fields (GameState.validate calls it). Without magic the game carries none of them: no
## enchantment, spellbook, enchantment count, Bastion fort, summoned creature, fading unit, mage on a roster,
## researched spell or magic mandate. With magic, the game has paths, every roster holds its faction's mage and no
## summoned creature, and every spellbook, Bastion entry, enchantment, summoned unit and magic mandate is well formed
## against MagicData (§5.1, §6.4, §7.1). Appends plain-language messages to `errors` (or push_error when it isn't
## an Array).
static func validate(state: GameState, errors = null) -> bool:
	if not state.magic:
		return _validate_without_magic(state, errors)
	var ok := true
	if not state.paths:
		_report(errors, "This game has magic, but magic needs paths (and paths need rulers), and it is played without them.")
		ok = false
	var provinces := {}
	for p in state.provinces:
		provinces[p.id] = true
	for f in state.factions:
		if not _validate_faction(f, provinces, errors):
			ok = false
	if not _validate_enchantments(state, provinces, errors):
		ok = false
	for a in state.armies:
		for i in a.units.size():
			var u: Unit = a.units[i]
			if u.until == 0:
				continue  # a creature that stays until it falls, or a view's stand-in (§2.7: they carry 0)
			var who := "%s (unit %d of army '%s')" % [u.type.name, i + 1, a.id]
			if not u.type.summoned:
				_report(errors, "%s fades at the end of turn %d, but only summoned creatures fade." % [Serial.cap(who), u.until])
				ok = false
			elif not summon_fades(u.type.id):
				_report(errors, "%s fades at the end of turn %d, but the %s stays until it falls." % [Serial.cap(who), u.until, u.type.name])
				ok = false
			elif u.until <= state.current_turn:
				_report(errors, "%s should have faded at the end of turn %d, and turn %d is over." % [Serial.cap(who), u.until, state.current_turn])
				ok = false
	return ok


static func _validate_without_magic(state: GameState, errors) -> bool:
	var ok := true
	if not state.enchantments.is_empty():
		_report(errors, "This game has %d enchantments, but it is played without magic." % state.enchantments.size())
		ok = false
	for f in state.factions:
		var name := _faction_name(f)
		if not f.spellbook.is_empty():
			_report(errors, "%s has a battle spellbook, but this game is played without magic." % name)
			ok = false
		if f.enchant_counter != 0:
			_report(errors, "%s has begun %d enchantments, but this game is played without magic." % [name, f.enchant_counter])
			ok = false
		if not f.bastions.is_empty():
			_report(errors, "%s has raised Bastion forts, but this game is played without magic." % name)
			ok = false
		for ut in _types(f):
			if ut.summoned:
				_report(errors, "%s has the summoned creature %s, but this game is played without magic, and only a ritual summons creatures." % [name, ut.name])
				ok = false
			elif is_mage(ut) or is_mage_id(ut.id):
				_report(errors, "%s can recruit %s, but this game is played without magic." % [name, ut.name])
				ok = false
		for r in f.researched:
			var nid := String(r.get("node", ""))
			if is_arcana(nid):
				_report(errors, "%s has researched %s, but this game is played without magic." % [name, String(arcana_node(nid).name)])
				ok = false
		for mid in f.mandates:
			if RulerRules.mandate_data(mid).get("magic", false) == true:
				_report(errors, "%s has %s, a mandate of magic, but this game is played without magic." % [name, RulerRules.mandate_name(mid)])
				ok = false
	for a in state.armies:
		for i in a.units.size():
			var u: Unit = a.units[i]
			if u.type.summoned or u.until != 0:
				_report(errors, "Army '%s' holds %s (unit %d), a summoned creature, but this game is played without magic." % [a.id, u.type.name, i + 1])
				ok = false
		for u in [a.commander, a.ruler]:
			if u != null and (u.type.summoned or u.until != 0):
				_report(errors, "Army '%s' is led by %s, a summoned creature, but this game is played without magic." % [a.id, u.type.name])
				ok = false
	return ok


static func _validate_faction(f: Faction, provinces: Dictionary, errors) -> bool:
	var ok := true
	var name := _faction_name(f)
	var book := f.spellbook
	if not book.is_empty():
		for key in book:
			if not ["order", "off"].has(str(key)):
				_report(errors, "%s's battle spellbook holds '%s'; a spellbook is its order and the spells switched off." % [name, key])
				ok = false
		var order = book.get("order", [])
		var off = book.get("off", [])
		if not (order is Array and off is Array):
			_report(errors, "%s's battle spellbook should list its order and the spells switched off." % name)
			return false
		var spells: Array = MagicData.SPELLBOOK.get(f.id, [])
		var listed := {}
		for sid in order:
			if not (sid is String) or String(sid).is_empty():
				_report(errors, "%s's battle spellbook has a spell with no id." % name)
				ok = false
			elif listed.has(sid):
				_report(errors, "%s's battle spellbook lists '%s' twice." % [name, sid])
				ok = false
			elif not spells.has(sid):
				_report(errors, "%s's battle spellbook lists '%s', which is not one of its battle spells." % [name, sid])
				ok = false
			listed[sid] = true
		for sid in spells:
			if not listed.has(sid):
				_report(errors, "%s's battle spellbook leaves out %s; it lists every battle spell of its schools." % [name, spell_name(String(sid))])
				ok = false
		var switched := {}
		for sid in off:
			if not listed.has(sid):
				_report(errors, "%s's battle spellbook switches off '%s', which is not in its order." % [name, str(sid)])
				ok = false
			elif switched.has(sid):
				_report(errors, "%s's battle spellbook switches off '%s' twice." % [name, sid])
				ok = false
			switched[sid] = true
	if f.enchant_counter < 0:
		_report(errors, "%s has begun %d enchantments, but the count is never below 0." % [name, f.enchant_counter])
		ok = false
	var raised := {}
	for pid in f.bastions:
		if not provinces.has(pid):
			_report(errors, "%s raised a Bastion fort at '%s', which is not a province on this map." % [name, pid])
			ok = false
		elif raised.has(pid):
			_report(errors, "%s lists its Bastion fort at '%s' twice." % [name, pid])
			ok = false
		raised[pid] = true
	if f.bastions.size() > MagicData.BASTION_CAP:
		_report(errors, "%s has raised %d Bastion forts, but a faction can raise at most %d, ever." % [name, f.bastions.size(), MagicData.BASTION_CAP])
		ok = false
	for mid in f.mandates:
		var md := RulerRules.mandate_data(mid)
		var excludes := String(md.get("excludes", ""))
		if not excludes.is_empty() and f.mandates.has(excludes):
			_report(errors, "%s has both %s and %s, which can't be held together: %s." % [name, String(md.name),
				RulerRules.mandate_name(excludes), String(md.get("excludes_why", "they exclude each other"))])
			ok = false
	return ok


static func _validate_enchantments(state: GameState, provinces: Dictionary, errors) -> bool:
	var ok := true
	var ids := {}
	var last := ""
	for e in state.enchantments:
		var eid := _text(e, "id")
		var what := "Enchantment '%s'" % eid
		if eid.is_empty():
			_report(errors, "An enchantment has no id.")
			ok = false
		elif ids.has(eid):
			_report(errors, "Two enchantments share the id '%s'." % eid)
			ok = false
		elif not last.is_empty() and eid < last:
			_report(errors, "The enchantments are kept in id order, but '%s' comes after '%s'." % [eid, last])
			ok = false
		ids[eid] = true
		last = eid
		var fid := _text(e, "faction")
		var f := state.find_faction(fid)
		if f == null:
			_report(errors, "%s belongs to '%s', which is not a faction in this game." % [what, fid])
			ok = false
		elif eid.begins_with(fid + "-e") and eid.substr(fid.length() + 2).is_valid_int():
			var n := eid.substr(fid.length() + 2).to_int()
			if n < 1 or n > f.enchant_counter:
				_report(errors, "%s is numbered %d, but %s has begun %d enchantments." % [what, n, _faction_name(f), f.enchant_counter])
				ok = false
		var ritual := _text(e, "ritual")
		var kind := _text(e, "kind")
		if ritual.is_empty():
			_report(errors, "%s names no ritual." % what)
			ok = false
		elif not is_ritual(ritual):
			_report(errors, "%s names '%s', which is not a ritual in this game." % [what, ritual])
			ok = false
		else:
			if String(spell_data(ritual).kind) != kind and ENCHANTMENT_KINDS.has(kind):
				_report(errors, "%s is a %s, but %s is a %s." % [what, kind, spell_name(ritual), String(spell_data(ritual).kind)])
				ok = false
		if not ENCHANTMENT_KINDS.has(kind):
			_report(errors, "%s is of kind '%s', but an enchantment is a blessing, a ward, a curse, a global or a sight." % [what, kind])
			ok = false
		var pid := _text(e, "province")
		if kind == "global" and not pid.is_empty():
			_report(errors, "%s is global, so it lies on no province, but it names '%s'." % [what, pid])
			ok = false
		elif kind != "global" and not provinces.has(pid):
			_report(errors, "%s lies on '%s', which is not a province on this map." % [what, pid])
			ok = false
		var blessed = e.get("armies", [])
		if not (blessed is Array):
			_report(errors, "%s should list the armies it blesses." % what)
			ok = false
			blessed = []
		if kind != "blessing" and not blessed.is_empty():
			_report(errors, "%s lists armies, but only a blessing is on armies." % what)
			ok = false
		var seen := {}
		for aid in blessed:
			var a := state.find_army(str(aid))
			if a == null or a.owner != fid:
				_report(errors, "%s blesses army '%s', which is not an army of '%s' in this game." % [what, aid, fid])
				ok = false
			elif seen.has(aid):
				_report(errors, "%s blesses army '%s' twice." % [what, aid])
				ok = false
			seen[aid] = true
		var cast := Serial.to_int(e.get("cast_turn", 0))
		var until := Serial.to_int(e.get("until_turn", 0))
		if cast < 1:
			_report(errors, "%s was cast on turn %d, but turns count from 1." % [what, cast])
			ok = false
		if until < cast:
			_report(errors, "%s lasts through turn %d, before turn %d, when it was cast." % [what, until, cast])
			ok = false
		elif until <= state.current_turn:
			_report(errors, "%s lasted through turn %d, and turn %d is over, so it should have ended." % [what, until, state.current_turn])
			ok = false
		var bonus := Serial.to_int(e.get("bonus", 0))
		if bonus < 0:
			_report(errors, "%s has a mastery bonus of %d, but a bonus is never below 0." % [what, bonus])
			ok = false
		elif bonus > int(MagicData.MASTERY.cap):
			_report(errors, "%s has a mastery bonus of %d, but mastery is at most +%d." % [what, bonus, int(MagicData.MASTERY.cap)])
			ok = false
		if e.get("ending") == true and kind != "curse":
			_report(errors, "%s is ending early, but only a curse is ended early (by a ward)." % what)
			ok = false
	return ok


# --- helpers --------------------------------------------------------------------------------------

## Every unit type a faction knows: its roster, its commander and its ruler.
static func _types(f: Faction) -> Array:
	var out: Array = f.unit_types.duplicate()
	for ut in [f.commander_type, f.ruler_unit_type]:
		if ut != null:
			out.append(ut)
	return out


static func _faction_name(f: Faction) -> String:
	return f.faction_name if not f.faction_name.is_empty() else f.id


## "Aurel Crown" for a faction id, from the state or the faction data.
static func _faction_display(state: GameState, faction_id: String) -> String:
	var f: Faction = state.find_faction(faction_id) if state != null else null
	if f != null and not f.faction_name.is_empty():
		return f.faction_name
	for d in FactionData.FACTIONS:
		if d.id == faction_id:
			return String(d.name)
	return faction_id


static func _province_name(state: GameState, province_id: String) -> String:
	var p := state.find_province(province_id)
	return p.name if p else province_id


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


static func _and_list(items: Array) -> String:
	return _joined(items, "and")


static func _or_list(items: Array) -> String:
	return _joined(items, "or")


static func _joined(items: Array, word: String) -> String:
	var parts := items.map(func(s): return str(s))
	if parts.size() <= 1:
		return "".join(parts)
	return "%s %s %s" % [", ".join(parts.slice(0, parts.size() - 1)), word, parts.back()]


static func _text(e: Dictionary, key: String) -> String:
	var v = e.get(key)
	return "" if v == null else str(v)


static func _refusal(code: String, reason: String) -> Dictionary:
	return {"code": code, "reason": reason}


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
