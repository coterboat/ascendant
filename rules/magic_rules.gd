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
## Healing and sight: can_heal(state, fid, province), vision_grants(state, fid) (M5-6: Far Sight's provinces).
## Research sold (§4): research_sold(pool) {"gold", "research", "left"}.
## Text: mage_gate_reason, pinned_reason, sold_text, mastery_text, caster_name.
## The saved form of enchantments (enchantment_copy, enchantment_from_dict) and validate (every magic field
## checked against GameState.magic and MagicData).
## M5-6 (#117), the ritual half (§6.2-§6.4, §7.1): the rituals phase and the enchantments phase run these.
##   ritual_queue(casts)                       the phase's order: kinds (KIND_ORDER), faction id, order given
##   ritual_effect(state, fid, order)          one ritual, in place: re-checked, turned aside (half price), failed (no
##                                             price) or paid (gold or blood) and applied; the rituals phase and the
##                                             forecast both call it
##   forecast_ritual(state, fid, order, orders)  ritual_effect on a copy, with the sentences the player reads
##   place_summon(...), enchantment_step(state, turn)  summons; blessings heal, curses bite, endings, fading
##   ward_on, blessing_of, reading, spell_codex, and the report's sentences (cast_text, turned_aside_text, blood_text,
##   fell_text, reading_text, healed_text, bit_text, ended_text, faded_text)
## M5-7 adds the battle spells.

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

## The Blood Moon's share in words ("a fifth"): MagicData.SPELLS.blood_moon.share, which every text about the moon reads.
static func moon_share_word() -> String:
	return String(MagicData.SHARE_WORDS.get(int(MagicData.SPELLS.blood_moon.get("share", 4)), "a share"))


static func has_magic(state: GameState) -> bool:
	return state != null and state.magic


## The spell or ritual with this id (MagicData.SPELLS), or {}.
static func spell_data(spell_id: String) -> Dictionary:
	return MagicData.SPELLS.get(spell_id, {})


static func spell_name(spell_id: String) -> String:
	return String(spell_data(spell_id).get("name", "an unknown spell"))


## The RulesCodex entry of a spell or ritual ("spell_bloodrot"), or "ritual" for an unknown id.
static func spell_codex(spell_id: String) -> String:
	return String(spell_data(spell_id).get("codex", "ritual"))


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


## The province ids `faction_id` sees in clear sight through magic (Far Sight, §6.2, §6.4), sorted: the provinces of its
## "sight" enchantments. FogRules.sight calls it. A Far Sight cast on turn T lasts through turn T + 2 and ends in that
## turn's enchantments phase, so it is in the state at the start of turns T + 1 and T + 2: "your next 2 turns". [] without
## magic (M5-6 turned M5-0's stub on together with Far Sight).
static func vision_grants(state: GameState, faction_id: String) -> Array:
	var out := []
	if not has_magic(state):
		return out
	for e in state.enchantments:
		if String(e.kind) == "sight" and String(e.faction) == faction_id and not out.has(String(e.province)):
			out.append(String(e.province))
	out.sort()
	return out


# --- the rituals phase and the enchantments phase (M5-6, §6.2-§6.4, §7.1) ----------------------------
#
# The resolver's rituals phase (after orders, before movement) casts every cast order that passed its checks, in
# ritual_queue's order, each through ritual_effect; its enchantments phase (last in the turn) runs enchantment_step.
# forecast_ritual runs the same ritual_effect on a copy, so a forecast can't disagree with its result unless a rival's
# ward turns the ritual aside. Texts: the turn report's sentences (third person: hotseat reports are shared) and the
# forecast's (to the player). Fog decides who reads which event (FogData.AUDIENCE); nothing here reads the fog flag.

## The rituals phase's order of kinds (§6.3): wards, curses, blessings, summons, raisings, the global ritual, sight.
## Within a kind, by faction id, then in the order each player gave them.
const KIND_ORDER := ["ward", "curse", "blessing", "summon", "raising", "global", "sight"]
## A ritual's three outcomes (§6.3).
const CAST := "cast"
const TURNED := "turned_aside"
const FAILED := "failed"


## The order the rituals phase casts in: [{"faction", "order", "index", "kind" (its place in KIND_ORDER)}], sorted by
## kind, then faction id, then the order given. `casts`: {faction id: [CastOrder, in the order given]}.
static func ritual_queue(casts: Dictionary) -> Array:
	var out := []
	for fid in casts:
		var list: Array = casts[fid]
		for i in list.size():
			out.append({"faction": String(fid), "order": list[i], "index": i,
				"kind": KIND_ORDER.find(String(spell_data(list[i].ritual).get("kind", "")))})
	out.sort_custom(func(a, b):
		if a.kind != b.kind:
			return a.kind < b.kind
		if a.faction != b.faction:
			return a.faction < b.faction
		return a.index < b.index)
	return out


## The rival ward that turns a ritual of `faction_id` aimed at `province_id` aside (§6.2, §6.4), or {}: a ward of
## another faction on that province, while its faction still owns it (a ward protects only its caster's faction, so
## it stops protecting a province that changes hands). Wards cast earlier in the same rituals phase count.
static func ward_on(state: GameState, province_id: String, faction_id: String) -> Dictionary:
	var p := state.find_province(province_id) if not province_id.is_empty() else null
	if p == null or not has_magic(state):
		return {}
	for e in state.enchantments:
		if String(e.kind) == "ward" and String(e.province) == province_id and String(e.faction) != faction_id and p.owner == String(e.faction):
			return e
	return {}


## The blessing on army `army_id` (a "blessing" enchantment that lists it), or {}.
static func blessing_of(state: GameState, army_id: String) -> Dictionary:
	if not has_magic(state):
		return {}
	for e in state.enchantments:
		if String(e.kind) == "blessing" and e.get("armies", []).has(army_id):
			return e
	return {}


## Far Sight's reading of `faction_id` (§6.2): everything private but its research target, as it stands now.
## {"faction", "gold", "mandates", "kept_power", "research_points", "nodes" (researched, in order), "spells", "spellbook"}.
static func reading(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return {}
	return {"faction": faction_id, "gold": f.gold, "mandates": Array(f.mandates).duplicate(), "kept_power": f.kept_power,
		"research_points": f.research_points, "nodes": AscensionRules.researched(state, faction_id),
		"spells": known_spells(state, faction_id), "spellbook": spellbook(state, faction_id)}


## A new army of `faction_id` at `province_id` holding `count` creatures of summoned type `summon_id`, each fading at the
## end of turn `until` (0: it stays until it falls) (§6.2). It is added to `state` and returned. A summoned army is new
## this turn, so no move order can name it: it holds the turn it arrives.
static func place_summon(state: GameState, faction_id: String, summon_id: String, count: int, province_id: String, until: int) -> Army:
	var ut := summon_type(summon_id)
	var a := Army.new()
	a.id = state.new_army_id(faction_id)
	a.owner = faction_id
	a.location = province_id
	for _i in count:
		var u := Unit.new(ut, faction_id)
		u.until = until
		a.units.append(u)
	state.armies.append(a)
	return a


## One ritual in the rituals phase (§6.3), applied to `state` in place: the resolver calls it on the turn's state and
## forecast_ritual on a copy. `order` is a CastOrder of `faction_id` that passed its checks in the orders phase; it is
## checked again here against `state` as the phase has left it (check_cast with no other orders: the running budget was
## settled in the orders phase). Returns, always: "outcome" (CAST, TURNED or FAILED), "ritual", "kind", "faction",
## "army", "caster" ("mage" | "ruler" | ""), "caster_name", "target", "pay", "price" (its full gold price), "turn", and:
##   FAILED  "code", "reason": nothing is paid and nothing happens.
##   paid    "gold" and "hp" (what was paid, in gold or in blood under Tithe of Blood), "gives" (who bled: blood_plan's).
##   TURNED  "ward" (the ward's id) and "warder" (its faction): half the price was paid (rounded down), nothing else.
##   CAST    "until_turn" (the last turn it lasts: an enchantment's, or the turn a summoned pack fades; 0 for good or
##           until it falls), "bonus" (the caster's mastery in the ritual's school), "enchantment" (its id, or ""),
##           "restarted" (the same ritual on the same target restarted it), "global"; a ward's "ends" (the rival curses
##           there it ends after one more bite), a blessing's "blessed" (army ids), a summon's "summon" ({"army",
##           "type", "count", "until"}), Bastion's "fort" (the province), Far Sight on a rival's capital: "read" (that
##           rival), "blocked" (the name of the rival caster there that blocked the reading, or "") and "reading".
static func ritual_effect(state: GameState, faction_id: String, order) -> Dictionary:
	var sp := spell_data(order.ritual)
	var kind := String(sp.get("kind", ""))
	var out := {"outcome": FAILED, "ritual": order.ritual, "kind": kind, "faction": faction_id, "army": order.army_id,
		"caster": "", "caster_name": "", "target": order.target, "pay": order.pay, "price": 0, "gold": 0, "hp": 0, "gives": [],
		"turn": state.current_turn + 1, "until_turn": 0, "bonus": 0, "enchantment": "", "restarted": false,
		"global": kind == "global", "ends": [], "blessed": [], "summon": {}, "fort": "", "read": "", "blocked": "", "reading": {},
		"ward": "", "warder": "", "code": "", "reason": ""}
	var check := check_cast(state, faction_id, order, [])
	if not check.is_empty():
		out.code = String(check.code)
		out.reason = String(check.reason)
		return out
	var f := state.find_faction(faction_id)
	var army := state.find_army(order.army_id)
	var caster := caster_for(state, faction_id, army, order.ritual)
	out.caster = String(caster.kind)
	out.caster_name = String(caster.name)
	var school := String(sp.school)
	var bonus := 0 if school == MagicData.COMMON else int(mastery_bonus(state, faction_id, school, String(caster.kind)).value)
	var full := int(price(state, faction_id, order.ritual, order.size).gold)
	out.price = full
	var ward := ward_on(state, order.target, faction_id)
	# The price: gold, or under Tithe of Blood 1 hp a gold from the caster's army, one soldier at a time (§7.1); turned
	# aside, half of it, rounded down.
	var gold := full if ward.is_empty() else floori(float(full) / MagicData.TURNED_ASIDE)
	if order.pay == CastOrder.BLOOD:
		var hp := full * MagicData.BLOOD_PER_GOLD
		if not ward.is_empty():
			hp = floori(float(hp) / MagicData.TURNED_ASIDE)
		var plan := blood_plan(state, army.id, hp)
		for g in plan.gives:
			army.units[int(g.index)].current_hp = int(g.to)
		out.hp = hp
		out.gives = plan.gives.duplicate(true)
	else:
		f.gold -= gold
		out.gold = gold
	if not ward.is_empty():
		out.outcome = TURNED
		out.ward = String(ward.id)
		out.warder = String(ward.faction)
		return out
	out.outcome = CAST
	out.bonus = bonus
	var turn := int(out.turn)
	var lasts := int(spell_numbers(order.ritual, bonus).duration)
	var until := turn + lasts if int(sp.get("duration", 0)) >= 0 else 0
	out.until_turn = until
	match kind:
		"ward":
			var began := _begin(state, faction_id, order.ritual, kind, order.target, turn, until, bonus, [])
			out.enchantment = began.id
			out.restarted = began.restarted
			for e in state.enchantments:
				if String(e.kind) == "curse" and String(e.province) == order.target and String(e.faction) != faction_id and e.ending != true:
					e.ending = true
					out.ends.append(String(e.id))
		"curse", "global", "sight":
			var began := _begin(state, faction_id, order.ritual, kind, order.target, turn, until, bonus, [])
			out.enchantment = began.id
			out.restarted = began.restarted
			if kind == "sight":
				_read_capital(state, faction_id, order.target, out)
		"blessing":
			var blessed := []
			for a in state.armies:
				if a.owner == faction_id and a.location == order.target:
					blessed.append(a.id)
			blessed.sort()
			# One blessing per army: a blessing on exactly these armies, wherever it was cast, is restarted (_begin); these
			# armies leave every other blessing of the faction (one left empty ends quietly).
			var same := ""
			for e in state.enchantments:
				if String(e.kind) == "blessing" and String(e.faction) == faction_id and Array(e.armies) == blessed and same.is_empty():
					same = String(e.id)
			var kept := []
			for e in state.enchantments:
				if String(e.kind) == "blessing" and String(e.faction) == faction_id and String(e.id) != same:
					e.armies = e.armies.filter(func(aid): return not blessed.has(String(aid)))
					if e.armies.is_empty():
						continue
				kept.append(e)
			state.enchantments = kept
			var began := _begin(state, faction_id, order.ritual, kind, order.target, turn, until, bonus, blessed)
			out.enchantment = began.id
			out.restarted = began.restarted
			out.blessed = blessed
		"summon":
			var summon := String(sp.summon)
			var count: int = order.size if summon_fades(summon) else 1
			var fades: int = until if summon_fades(summon) else 0
			var pack := place_summon(state, faction_id, summon, count, army.location, fades)
			out.until_turn = fades
			out.summon = {"army": pack.id, "type": summon, "count": count, "until": fades}
		"raising":
			var p := state.find_province(order.target)
			p.has_fort = true
			if state.sieges:
				# M3c (§16): Bastion builds the lowest level at once, at full walls; a palisade being built there is done.
				p.fort_level = 1
				p.walls = SiegeRules.walls_max(1)
				p.fort_by = faction_id
				if not p.works.is_empty() and int(p.works.get("to", 0)) <= 1:
					p.works = {}
			f.bastions.append(order.target)
			out.fort = order.target
	return out


## Starts an enchantment, or restarts the same ritual of the same faction on the same target (one curse per province,
## one ward, one sight, one global; a blessing on exactly the same armies, wherever it was cast): {"id", "restarted"}. A new one takes the
## faction's next enchantment number ("beasts-e3"), and the list stays in id order.
static func _begin(state: GameState, faction_id: String, ritual: String, kind: String, province_id: String, turn: int, until: int,
		bonus: int, armies: Array) -> Dictionary:
	for e in state.enchantments:
		var same: bool = Array(e.armies) == armies if kind == "blessing" else String(e.province) == province_id
		if String(e.faction) == faction_id and String(e.ritual) == ritual and same:
			e.province = province_id if kind != "global" else ""
			e.cast_turn = turn
			e.until_turn = until
			e.bonus = bonus
			e.ending = false
			e.armies = armies.duplicate()
			return {"id": String(e.id), "restarted": true}
	var f := state.find_faction(faction_id)
	f.enchant_counter += 1
	var id := "%s-e%d" % [faction_id, f.enchant_counter]
	state.enchantments.append({"id": id, "ritual": ritual, "faction": faction_id, "kind": kind,
		"province": province_id if kind != "global" else "", "armies": armies.duplicate(), "cast_turn": turn, "until_turn": until,
		"bonus": bonus, "ending": false})
	state.enchantments.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return {"id": id, "restarted": false}


## Far Sight on a rival's capital (§6.2): a reading of that rival, unless one of its casters stands there, which blocks
## the reading, not the sight. Fills `out` ("read", "blocked", "reading").
static func _read_capital(state: GameState, faction_id: String, province_id: String, out: Dictionary) -> void:
	for f in state.factions:
		if f.id == faction_id or f.capital != province_id:
			continue
		out.read = f.id
		for a in state.armies:
			if a.owner == f.id and a.location == province_id:
				var found := casters(state, a)
				if not found.is_empty():
					out.blocked = String(found[0].name)
					return
		out.reading = reading(state, f.id)
		return


## The forecast of a cast order (§11.2), from the same ritual_effect the rituals phase runs, on a copy of the state as
## the faction's queued sacrifice leaves it, after the faction's own casts the phase resolves first (so a summoned
## army's name is exact). `orders` are the faction's queued orders (the order may be among them or not yet).
## Forecast equals result unless a rival's ward turns it aside: a ward you can see is counted (on a fog view, only the
## wards in sight), and the text says the risk. Returns {"ok", "code", "reason" (when not ok), "effect" (ritual_effect's
## result), "lines" (the sentences), "sections" (the same, each with its kind: effect, blood, risk or pin), "text" (them
## joined), "effect_text" (what it does in one sentence, for the orders list)}.
static func forecast_ritual(state: GameState, faction_id: String, order, orders: Array = [], veiled: Dictionary = {}) -> Dictionary:
	var board := RulerRules.state_after_orders(state, faction_id, orders)
	var before := []
	for o in orders:
		if o == order:
			break
		before.append(o)
	var check := check_cast(board, faction_id, order, before)
	if not check.is_empty():
		return {"ok": false, "code": String(check.code), "reason": String(check.reason), "effect": {}, "lines": [String(check.reason)],
			"sections": [], "text": String(check.reason)}
	var copy := board.deep_copy([])
	var mine := []  # the faction's legal casts in the order given, as the rituals phase takes them (the order among them)
	var given := []
	for o in orders:
		if o is CastOrder and (o == order or check_cast(board, faction_id, o, given).is_empty()):
			mine.append(o)
		given.append(o)
	if not mine.has(order):
		mine.append(order)  # a new order is queued last
	var effect := {}
	for item in ritual_queue({faction_id: mine}):
		var fx := ritual_effect(copy, faction_id, item.order)
		if item.order == order:
			effect = fx
			break
	var sections := forecast_sections(board, faction_id, effect, copy, orders, veiled)
	var lines := sections.map(func(s): return String(s.text))
	var short := String(lines[0]) if String(effect.outcome) != CAST else brief_words(board, copy, faction_id, effect)
	return {"ok": true, "code": "", "reason": "", "effect": effect, "lines": lines, "sections": sections, "text": " ".join(lines),
		"effect_text": short}


## The forecast's sentences for a ritual_effect result (to the player, §11.2): what it will do with your numbers, the
## price (or the soldiers who bleed), the risk of a ward, and the pin. `state` is the state before; `after` the copy
## the effect was applied to.
static func forecast_lines(state: GameState, faction_id: String, fx: Dictionary, after: GameState, orders: Array = [], veiled: Dictionary = {}) -> Array:
	return forecast_sections(state, faction_id, fx, after, orders, veiled).map(func(s): return String(s.text))


## forecast_lines with what each sentence is, for the cast dialog's headings (M5-8): [{"kind" ("effect", "blood", "risk" or
## "pin"), "text"}], in the order the player reads them.
static func forecast_sections(state: GameState, faction_id: String, fx: Dictionary, after: GameState, orders: Array = [], veiled: Dictionary = {}) -> Array:
	var out := []
	var ritual := String(fx.ritual)
	var name := spell_name(ritual)
	var where := _province_name(state, String(fx.target))
	var head := name + _target_words(state, fx)
	if String(fx.outcome) == TURNED:
		out.append({"kind": "effect", "text": "%s will be turned aside: %s's Sanctum Ward lies on %s, so half its price (%s) is spent and nothing else happens." % [
			head, _the(state, String(fx.warder)), where, _price_words(fx)]})
	else:
		out.append({"kind": "effect", "text": "%s for %s: %s" % [head, _price_words(fx), _effect_words(state, after, faction_id, fx, true)]})
	if int(fx.hp) > 0:
		out.append({"kind": "blood", "text": _blood_words(state, faction_id, fx, true)})
	var risk := ward_risk_line(state, faction_id, fx, veiled)
	if not risk.is_empty():
		out.append({"kind": "risk", "text": risk})
	out.append({"kind": "pin", "text": pin_line(state, faction_id, fx, orders)})
	return out


## The risk of a rival's ward, from what the caster can see (§11.2): "" when none applies. A ward seen turns the cast aside
## (the forecast's first line says so); with none seen, one cast this turn would still turn it aside (wards resolve first),
## and out of sight the ward can't be seen at all: `veiled` ({province id: true}, Forecast.veiled_provinces: the provinces a
## fog view can't see, {} without fog) is the caller's, so no rule here reads the fog.
static func ward_risk_line(state: GameState, faction_id: String, fx: Dictionary, veiled: Dictionary = {}) -> String:
	if String(fx.outcome) != CAST or String(fx.target).is_empty():
		return ""
	var p := state.find_province(String(fx.target))
	if p == null or p.owner.is_empty() or p.owner == faction_id or not _has_ward_ritual(p.owner):
		return ""
	var half := floori(float(int(fx.price)) / MagicData.TURNED_ASIDE)
	var costs := "%d hit points in blood" % (half * MagicData.BLOOD_PER_GOLD) if int(fx.hp) > 0 else "%d gold" % half
	var rival := _the(state, p.owner)
	if veiled.has(p.id):
		return "%s is out of sight, so you can't see whether %s has warded it: if it has, %s will be turned aside and half its price (%s) is spent." % [
			p.name, rival, spell_name(String(fx.ritual)), costs]
	return "No ward seen on %s at the start of the turn; one cast this turn would still turn %s aside, for half its price (%s)." % [
		p.name, spell_name(String(fx.ritual)), costs]


## The pin (§6.1, §11.2): "Your army at Fangridge (24 fighters) holds this turn; this cancels its move to Thornvale."
static func pin_line(state: GameState, faction_id: String, fx: Dictionary, orders: Array = []) -> String:
	var army := state.find_army(String(fx.army))
	var home := _province_name(state, army.location) if army != null else ""
	var text := "Your army at %s%s holds this turn" % [home, " (%s)" % fighters_words(state, army) if army != null else ""]
	for o in orders:
		if o is MoveOrder and o.army_id == String(fx.army):
			return "%s; this cancels its move to %s." % [text, _province_name(state, o.to)]
	return text + "."


## "24 fighters", "1 fighter", or "the Ever-Regent alone" for an army: its regular units, commander and ruler.
static func fighters_words(state: GameState, army: Army) -> String:
	if army.ruler != null and army.units.is_empty() and army.commander == null:
		return "%s alone" % RulerRules.current_name(state, army.owner)
	var n := army.units.size() + (1 if army.commander != null else 0) + (1 if army.ruler != null else 0)
	return _count(n, "fighter", "fighters")


## How many fighters of other factions than `faction_id` stand at `province_id` that `state` shows, as words for the
## curse forecast: "30 you can see", or "about 30 you can see" when any are only glimpsed, "none you can see" for none.
## An army only remembered (a fog ghost) is not counted: it may be gone.
static func seen_there_words(state: GameState, faction_id: String, province_id: String) -> String:
	var n := 0
	var rough := false
	for a in state.armies:
		if a.location != province_id or a.owner == faction_id:
			continue
		var level := String(a.seen.get("level", ""))  # Army.seen: "clear", "glimpse" or "memory" (a ghost)
		if level == "memory":
			continue
		rough = rough or level == "glimpse"
		n += a.units.size() + (1 if a.commander != null else 0) + (1 if a.ruler != null else 0)
	if n == 0:
		return "none you can see"
	return "%s%d you can see" % ["about " if rough else "", n]


## "15 gold" or "15 hit points in blood": what a ritual_effect result paid.
static func _price_words(fx: Dictionary) -> String:
	if int(fx.hp) > 0:
		return "%d hit points in blood" % int(fx.hp)
	return "%d gold" % int(fx.gold)


## Whether `faction_id` has a ward ritual among its schools (Sanctum Ward for the Crown).
static func _has_ward_ritual(faction_id: String) -> bool:
	for school in schools(faction_id):
		for nid in school_data(school).nodes:
			if String(spell_data(String(nid)).get("kind", "")) == "ward":
				return true
	return false


## What a cast ritual does, in words with its numbers: to the player (`own`: "your", future) for the forecast, or about
## its faction ("their", past) for the turn report.
static func _effect_words(state: GameState, after: GameState, faction_id: String, fx: Dictionary, own: bool) -> String:
	var ritual := String(fx.ritual)
	var where := _province_name(state, String(fx.target))
	var until := int(fx.until_turn)
	var bonus := int(fx.bonus)
	var your := "your" if own else "their"
	var n := spell_numbers(ritual, bonus)
	match String(fx.kind):
		"ward":
			var text := "rival rituals aimed at %s %s turned aside through turn %d." % [where, "are" if own else "will be", until]
			for cid in fx.ends:
				var c := _enchantment(state, String(cid))
				text += " %s there (%s) bites once more at the end of this turn, then ends." % [spell_name(String(c.get("ritual", ""))),
					_faction_display(state, String(c.get("faction", "")))]
			return text
		"curse":
			return "the fighters there not of %s%s can't heal, and it takes %d hit points from them at the end of every turn through turn %d, the healthiest first, never below 1. It first bites after this turn's battles; only fighters still there at the end of a turn are hit." % [
				"yours" if own else "theirs", " (%s)" % seen_there_words(state, faction_id, String(fx.target)) if own else "", int(n.value), until]
		"blessing":
			var names := Array(fx.blessed).map(func(aid): return TurnReportText.army_name(after, String(aid), faction_id))
			var effect := "each heals %d hit points a turn, wherever it goes, and a side at least half blessed fights with +1 morale." % int(n.value)
			if own:
				# §11.2: each army with its size ("the Crown's 3rd (24 fighters)").
				names = Array(fx.blessed).map(func(aid): return "%s (%s)" % [TurnReportText.army_name(after, String(aid), faction_id),
					fighters_words(after, after.find_army(String(aid))) if after.find_army(String(aid)) != null else "gone"])
				return "blesses %s there, %s, through turn %d: %s Armies arriving this turn aren't blessed." % [
					_count(names.size(), "army of yours", "armies of yours"), _and_list(names), until, effect]
			return "%s %s blessed through turn %d: %s" % [Serial.cap(_and_list(names)), "is" if names.size() == 1 else "are", until, effect]
		"summon":
			var summon: Dictionary = fx.summon
			var pack := TurnReportText.army_name(after, String(summon.army), faction_id)
			if summon_fades(String(summon.type)):
				return "%d %s form a new army at %s, %s. It holds this turn, can move from next turn, and fades at the end of turn %d." % [
					int(summon.count), String(MagicData.SUMMONS[summon.type].name), where, pack, int(summon.until)]
			return "the %s wakes at %s as a new army of its own, %s. It holds this turn, can move from next turn, and stays until it falls." % [
				String(MagicData.SUMMONS[summon.type].name), where, pack]
		"raising":
			var f := after.find_faction(faction_id)
			var used := f.bastions.size() if f != null else 0
			var fort := "a fort" if not state.sieges else "a fort (%s, walls %d)" % [SiegeRules.level_word(1), SiegeRules.walls_max(1)]
			return "raises %s at %s for good: %d of %d Bastion forts used, ever." % [fort, where, used, MagicData.BASTION_CAP]
		"global":
			return "through turn %d, in every battle %s standing fighters heal back %s of the damage their attacks deal, rounded down, never above their maximum - 1. Battles in a rival's warded province are outside the moon." % [
				until, your, moon_share_word()]
		"sight":
			var text := "%s %s in clear sight at the start of %s next 2 turns, through turn %d." % ["you see" if own else "they see", where,
				your, until]
			if not String(fx.read).is_empty() and own:
				var rival := _the(state, String(fx.read))
				if not String(fx.blocked).is_empty():
					text += " It is %s's capital, but %s stands there, a caster: it will block the reading of their secrets, not the sight." % [
						rival, String(fx.blocked)]
				else:
					text += " It is %s's capital: you also read their gold, mandates, kept power, research, spells and spellbook, unless one of their casters stands there (it blocks the reading, not the sight)." % rival
			return text
	return ""


## What a cast ritual will do, in one short sentence for the orders list (the forecast's hover has the rest): "No healing at
## Crownkeep, and 12 hit points a turn taken there, through turn 3."
static func brief_words(state: GameState, after: GameState, faction_id: String, fx: Dictionary) -> String:
	var where := _province_name(state, String(fx.target))
	var until := int(fx.until_turn)
	var n := spell_numbers(String(fx.ritual), int(fx.bonus))
	match String(fx.kind):
		"ward":
			return "Rival rituals aimed at %s are turned aside through turn %d." % [where, until]
		"curse":
			return "No healing at %s for anyone not yours, and %d hit points a turn taken there, through turn %d." % [where, int(n.value), until]
		"blessing":
			return "Blesses %s through turn %d: %d hit points a turn each." % [_count(Array(fx.blessed).size(), "army", "armies"), until, int(n.value)]
		"summon":
			var summon: Dictionary = fx.summon
			var pack := TurnReportText.army_name(after, String(summon.army), faction_id)
			if summon_fades(String(summon.type)):
				return "%d %s at %s, %s, until the end of turn %d." % [int(summon.count), String(MagicData.SUMMONS[summon.type].name), where,
					pack, int(summon.until)]
			return "The %s wakes at %s, %s, until it falls." % [String(MagicData.SUMMONS[summon.type].name), where, pack]
		"raising":
			var f := after.find_faction(faction_id)
			return "A fort at %s for good (%d of %d Bastion forts)." % [where, f.bastions.size() if f != null else 0, MagicData.BASTION_CAP]
		"global":
			return "Your fighters heal back %s of the damage they deal, in every battle through turn %d." % [moon_share_word(), until]
		"sight":
			return "%s in clear sight on your next 2 turns, through turn %d." % [where, until]
	return ""


## The blood a ritual_effect result took (§7.1): who gave what, and what it means. `own`: the forecast's words.
static func _blood_words(state: GameState, faction_id: String, fx: Dictionary, own: bool) -> String:
	var army := state.find_army(String(fx.army))
	var regulars := 0
	if army != null:
		for u in army.units:
			if not (u.type.summoned or u.type.is_commander or u.type.is_ruler):
				regulars += 1
	var bits := []
	var traits := {}
	var low_mage := false
	var min_hp := int(spell_data("bloodbolt").get("min_caster_hp", 0))
	for g in fx.gives:
		bits.append("%s %d to %d" % [String(g.name), int(g.from), int(g.to)])
		var u: Unit = army.units[int(g.index)] if army != null and int(g.index) < army.units.size() else null
		if u != null and not u.type.trait_id.is_empty() and u.type.trait_id != MagicData.MAGE_TRAIT:
			traits[u.type.trait_id] = true
		if u != null and is_mage(u.type) and int(g.to) < min_hp:
			low_mage = true
	var n: int = fx.gives.size()
	var text := "Paid in blood%s: %d of the %d soldiers in %s at %s %s %d hit points (%s), one soldier at a time, never below 1." % [
		"" if own else " for %s" % spell_name(String(fx.ritual)), n, regulars,
		"your army" if own else TurnReportText.army_name(state, String(fx.army), faction_id),
		_province_name(state, army.location) if army != null else "", "give" if own else "gave", int(fx.hp), ", ".join(bits)]
	if traits.has(AutoBattleResolver.BERSERK):
		text += " %s wounded: Berserk on." % ("They will be" if own else "They are")
	if low_mage and knows(state, faction_id, "bloodbolt"):
		text += " %s %s can't cast Bloodbolt below %d hit points, and one of them %s left lower." % ["Your" if own else "Their",
			String(mage_data(faction_id).get("name", "mages")), min_hp, "will be" if own else "is"]
	return text


# --- the report's sentences (third person: in hotseat everyone reads the same report) ------------------

## The ritual_cast sentence: who cast what from where, the price, and what it does, with its "through turn".
static func cast_text(state: GameState, fx: Dictionary) -> String:
	var fid := String(fx.faction)
	var who := Serial.cap(_the(state, fid))
	var name := spell_name(String(fx.ritual))
	var army := state.find_army(String(fx.army))
	var from := "%s at %s" % [TurnReportText.army_name(state, String(fx.army), fid), _province_name(state, army.location) if army else ""]
	var paid := "for %s" % _price_words(fx)
	return "%s cast %s%s from %s, %s: %s" % [who, name, _target_words(state, fx), from, paid, _effect_words(state, state, fid, fx, false)]


## The ritual_turned_aside sentence (§6.3): "The Aurel Crown's Sanctum Ward turned aside the Thornmane Clans' Bloodrot
## at Crownkeep: half its price (7 gold) was spent, and nothing else happened."
static func turned_aside_text(state: GameState, fx: Dictionary) -> String:
	return "%s's Sanctum Ward turned aside %s's %s at %s: half its price (%s) was spent, and nothing else happened." % [
		Serial.cap(_the(state, String(fx.warder))), _the(state, String(fx.faction)), spell_name(String(fx.ritual)),
		_province_name(state, String(fx.target)), _price_words(fx)]


## The blood_paid sentence (§7.1): "Paid in blood for Bloodrot: 2 of the 5 soldiers in the Clans' 3rd at Thornvale gave 15
## hit points (Tuskers 14 to 1, Tuskers 14 to 12), ..."
static func blood_text(state: GameState, fx: Dictionary) -> String:
	return _blood_words(state, String(fx.faction), fx, false)


## " on Crownkeep", or " at Fangridge" for a summon (cast where the caster stands), or "" for no target.
static func _target_words(state: GameState, fx: Dictionary) -> String:
	if String(fx.target).is_empty():
		return ""
	return " %s %s" % ["at" if String(fx.kind) == "summon" else "on", _province_name(state, String(fx.target))]


## The ritual_fell sentence (§2.8, §11.2), for the faction whose land the ritual fell on: the ritual, the caster's
## faction, the effect and how to stop it, never the caster's province.
static func fell_text(state: GameState, fx: Dictionary, owner: String) -> String:
	var name := spell_name(String(fx.ritual))
	var where := _province_name(state, String(fx.target))
	var by := _the(state, String(fx.faction))
	var victim := _the(state, owner)
	var until := int(fx.until_turn)
	var text := "%s fell on %s, cast by %s" % [name, where, by]
	match String(fx.kind):
		"curse":
			text += ": %s's fighters there can't heal, and it takes %d hit points from them at the end of every turn through turn %d, the healthiest first, never below 1. Only fighters still in %s at the end of a turn are hit. " % [
				victim, int(spell_numbers(String(fx.ritual), int(fx.bonus)).value), until, where]
			text += _stop_curse(state, owner, where, until)
		"sight":
			text += ": they see %s in clear sight at the start of their next 2 turns, through turn %d." % [where, until]
			if not String(fx.blocked).is_empty():
				text += " %s stands there, a caster, and blocked their reading of %s's secrets; the sight stands all the same." % [
					Serial.cap(String(fx.blocked)), victim]
			elif not String(fx.read).is_empty():
				text += " It is %s's capital, so they also read its gold, mandates, kept power, research, spells and spellbook." % victim
			if _has_ward_ritual(owner):
				text += " A Sanctum Ward on it turns such rituals aside."
		_:
			text += "."
	return text


## How the owner of a cursed province can stop the curse: its ward, or what it lacks to cast one.
static func _stop_curse(state: GameState, owner: String, where: String, until: int) -> String:
	var ward := ""
	for school in schools(owner):
		for nid in school_data(school).nodes:
			if String(spell_data(String(nid)).get("kind", "")) == "ward":
				ward = String(nid)
	if ward.is_empty():
		return "Nothing of %s's ends a curse: move out, or wait for the end of turn %d." % [_the(state, owner), until]
	if knows(state, owner, ward):
		return "To stop it, %s can cast %s on %s (it bites once more, then ends), or move out." % [_the(state, owner), spell_name(ward), where]
	return "%s (%s: %d research to reach) would end it. Until then, move out or wait for the end of turn %d." % [spell_name(ward),
		school_name(String(spell_data(ward).school)), reach_cost(state, owner, ward), until]


## When Tithe of Blood first gets used (§7.1, the build screen's row): "First use: Far Sight once you have Shamans (with fog on),
## otherwise your first tier II ritual, Call the Pack (about turn 5)." The turns come from the research rules: the research the
## first tier II ritual needs (its tier I first) at the faction's research rate and pool now, so they follow the land you start on.
## `state` is the starting state; `fog` whether the game has fog of war. "" when the faction has no school.
static func tithe_first_use(state: GameState, faction_id: String, fog: bool) -> String:
	var first_school := schools(faction_id)
	if first_school.is_empty():
		return ""
	var nodes: Array = school_data(String(first_school[0])).nodes
	var tier1 := String(nodes[0])
	var tier2 := String(nodes[1])
	var pool := AscensionRules.research_points(state, faction_id)
	var rate := int(AscensionRules.research_rate(state, faction_id).rate)
	var turns2 := AscensionRules.eta(reach_cost(state, faction_id, tier2), pool, rate)
	var when2 := "about turn %d" % (state.current_turn + turns2) if turns2 > 0 else "out of reach at this pace"
	if fog:
		var turns1 := AscensionRules.eta(reach_cost(state, faction_id, tier1), pool, rate)
		return "First use: Far Sight once you have %s (with fog on): they can be recruited after your first spell, %s (about turn %d); then your first tier II ritual, %s (%s)." % [
			String(mage_data(faction_id).get("name", "mages")), spell_name(tier1), state.current_turn + turns1 + 1 if turns1 > 0 else 0,
			spell_name(tier2), when2]
	return "First use: your first tier II ritual, %s (%s), once its tier I spell, %s, is known." % [spell_name(tier2), when2, spell_name(tier1)]


## The research still needed to reach arcana node `node_id`: its cost and its arcana prerequisites' not yet researched.
static func reach_cost(state: GameState, faction_id: String, node_id: String) -> int:
	var total := 0
	for nid in reach_chain(state, faction_id, node_id):
		total += AscensionRules.node_cost(String(nid))
	return total


## The arcana nodes still to research to reach `node_id`, in the order to take them: its unresearched arcana prerequisites
## first (each once), the node last. [] when it is researched already or isn't an arcana node. (A tier III node's Oath is a
## path node: the path's own forecast counts it.)
static func reach_chain(state: GameState, faction_id: String, node_id: String) -> Array:
	var out := []
	if AscensionRules.has_node(state, faction_id, node_id) or not is_arcana(node_id):
		return out
	for req in arcana_node(node_id).get("requires", []):
		for nid in reach_chain(state, faction_id, String(req)):
			if not out.has(nid):
				out.append(nid)
	out.append(node_id)
	return out


## The far_sight_reading sentence (§6.2): what Far Sight read of a rival's capital, or who blocked it.
static func reading_text(state: GameState, fx: Dictionary) -> String:
	var where := _province_name(state, String(fx.target))
	var rival := _the(state, String(fx.read))
	if not String(fx.blocked).is_empty():
		return "Far Sight on %s: %s stands there, a caster, and blocked the reading of %s. %s see %s all the same." % [where,
			Serial.cap(String(fx.blocked)), rival, Serial.cap(_the(state, String(fx.faction))), where]
	var r: Dictionary = fx.reading
	var mandates := Array(r.mandates).map(func(m): return RulerRules.mandate_name(String(m)))
	var nodes := Array(r.nodes).map(func(n): return AscensionRules.node_name(String(n)))
	var spells := Array(r.spells).map(func(s): return spell_name(String(s)))
	var book: Dictionary = r.spellbook
	return "Far Sight read %s at %s: %d gold; mandates %s; kept power %d; %d research in hand; researched %s; spells %s; battle spellbook %s." % [
		rival, where, int(r.gold), _and_list(mandates) if not mandates.is_empty() else "none", int(r.kept_power), int(r.research_points),
		_and_list(nodes) if not nodes.is_empty() else "nothing", _and_list(spells) if not spells.is_empty() else "none",
		spellbook_text(book.order, book.off)]


## The summoned sentence (a board beat; the ritual_cast line says it too).
static func summoned_text(state: GameState, fx: Dictionary) -> String:
	var s: Dictionary = fx.summon
	var army := state.find_army(String(s.army))
	return "%d %s answered %s at %s: %s." % [int(s.count), String(MagicData.SUMMONS[s.type].name), _the(state, String(fx.faction)),
		_province_name(state, army.location if army else ""), TurnReportText.army_name(state, String(s.army), String(fx.faction))]


## The enchantment_began sentence (a board beat; the ritual_cast line says it too).
static func began_text(state: GameState, fx: Dictionary) -> String:
	var on := "every battle" if String(fx.target).is_empty() else _province_name(state, String(fx.target))
	return "%s (%s) lies on %s through turn %d." % [spell_name(String(fx.ritual)), _faction_display(state, String(fx.faction)), on, int(fx.until_turn)]


## The enchantments phase (§6.3), applied to `state` in place, for the turn `turn` (as players count it): province by
## province in id order, 1. each blessing heals the blessed armies standing there (one hit point at a time to the
## wounded fighter with the fewest left, its budget per army; a cursed army heals nothing), 2. each curse there bites
## (its budget from the fighters there not of its faction, one hit point at a time from the one with the most left,
## never below 1; fighters in order: armies by id, units, the commander, the ruler); then 3. the endings: summoned
## creatures whose time is up fade (an army left empty is removed), blessings forget armies that are gone, and every
## enchantment that lasted through this turn ends, with a curse a ward ended and a blessing with no army left.
## Returns {"healed": [...], "bit": [...], "ended": [...], "faded": [...]}, in that order, for the turn report.
static func enchantment_step(state: GameState, turn: int) -> Dictionary:
	var out := {"healed": [], "bit": [], "ended": [], "faded": []}
	if not has_magic(state):
		return out
	var provinces := state.provinces.map(func(p): return p.id)
	provinces.sort()
	var armies: Array = state.armies.duplicate()
	armies.sort_custom(func(a, b): return a.id < b.id)
	for pid in provinces:
		for e in state.enchantments:
			if String(e.kind) != "blessing":
				continue
			for aid in e.armies:
				var a := state.find_army(String(aid))
				if a == null or a.location != pid or not can_heal(state, a.owner, pid):
					continue
				var budget := int(spell_numbers(String(e.ritual), int(e.bonus)).value)
				var healed := _give(state, [a], budget)
				if not healed.is_empty():
					out.healed.append({"enchantment": String(e.id), "ritual": String(e.ritual), "faction": String(e.faction), "army": a.id,
						"province": pid, "budget": budget, "total": healed.reduce(func(t, h): return t + int(h.to) - int(h.from), 0),
						"healed": healed, "until_turn": int(e.until_turn)})
		for e in state.enchantments:
			if String(e.kind) != "curse" or String(e.province) != pid:
				continue
			var victims := armies.filter(func(a): return a.location == pid and a.owner != String(e.faction) and state.find_army(a.id) != null)
			var budget := int(spell_numbers(String(e.ritual), int(e.bonus)).value)
			var taken := _take(victims, budget)
			var by_faction := {}
			for t in taken:
				if not by_faction.has(t.owner):
					by_faction[t.owner] = []
				by_faction[t.owner].append(t)
			var owners: Array = by_faction.keys()
			owners.sort()
			for owner in owners:
				var list: Array = by_faction[owner]
				var ids := []
				for t in list:
					if not ids.has(String(t.army)):
						ids.append(String(t.army))
				out.bit.append({"enchantment": String(e.id), "ritual": String(e.ritual), "faction": String(e.faction), "victim": String(owner),
					"province": pid, "budget": budget, "total": list.reduce(func(s, t): return s + int(t.from) - int(t.to), 0),
					"taken": list, "armies": ids, "until_turn": int(e.until_turn), "ending": e.ending == true})
	# Summoned creatures whose time is up fade.
	for a in armies:
		var gone: Array = a.units.filter(func(u): return u.until > 0 and u.until <= turn)
		if gone.is_empty():
			continue
		var stay: Array[Unit] = []
		for u in a.units:
			if not gone.has(u):
				stay.append(u)
		a.units = stay
		var removed: bool = a.units.is_empty() and a.commander == null and a.ruler == null
		var engines: int = a.engines if removed else 0  # M3c: siege engines ride only with a fighter, so they go with the army
		if removed:
			state.armies.erase(a)
		out.faded.append({"army": a.id, "faction": a.owner, "province": a.location, "type": gone[0].type.id, "count": gone.size(),
			"until": gone[0].until, "removed": removed, "engines_lost": engines})
	# The endings.
	var kept := []
	for e in state.enchantments:
		if String(e.kind) == "blessing":
			e.armies = e.armies.filter(func(aid): return state.find_army(String(aid)) != null)
		var cause := ""
		if int(e.until_turn) <= turn:
			cause = "time"
		elif String(e.kind) == "curse" and e.ending == true:
			cause = "ward"
		elif String(e.kind) == "blessing" and e.armies.is_empty():
			cause = "no_armies"
		if cause.is_empty():
			kept.append(e)
		else:
			var ended := enchantment_copy(e)
			ended["cause"] = cause
			out.ended.append(ended)
	state.enchantments = kept
	return out


## Gives `budget` hit points to the armies' wounded fighters, one at a time to the one with the fewest left (ties: the
## first in fighter order), never above its maximum. Returns [{"army", "index" (in fighter order), "name", "from", "to"}].
static func _give(state: GameState, armies: Array, budget: int) -> Array:
	var fighters := []
	for a in armies:
		var members := _members(a)
		for i in members.size():
			fighters.append({"army": a.id, "index": i, "unit": members[i], "max": _max_hp(state, members[i])})
	var changed := {}
	for _i in budget:
		var pick := -1
		for k in fighters.size():
			var u: Unit = fighters[k].unit
			if u.current_hp < int(fighters[k].max) and (pick < 0 or u.current_hp < fighters[pick].unit.current_hp):
				pick = k
		if pick < 0:
			break
		if not changed.has(pick):
			changed[pick] = fighters[pick].unit.current_hp
		fighters[pick].unit.current_hp += 1
	return _changes(fighters, changed)


## Takes `budget` hit points from the armies' fighters, one at a time from the one with the most left (ties: the first
## in fighter order), never below 1. Returns [{"army", "owner", "index", "name", "from", "to"}].
static func _take(armies: Array, budget: int) -> Array:
	var fighters := []
	for a in armies:
		var members := _members(a)
		for i in members.size():
			fighters.append({"army": a.id, "owner": a.owner, "index": i, "unit": members[i]})
	var changed := {}
	for _i in budget:
		var pick := -1
		for k in fighters.size():
			var u: Unit = fighters[k].unit
			if u.current_hp > 1 and (pick < 0 or u.current_hp > fighters[pick].unit.current_hp):
				pick = k
		if pick < 0:
			break
		if not changed.has(pick):
			changed[pick] = fighters[pick].unit.current_hp
		fighters[pick].unit.current_hp -= 1
	return _changes(fighters, changed)


static func _changes(fighters: Array, changed: Dictionary) -> Array:
	var out := []
	var picks: Array = changed.keys()
	picks.sort()
	for k in picks:
		var row := {"army": String(fighters[k].army), "index": int(fighters[k].index), "name": fighters[k].unit.type.name,
			"from": int(changed[k]), "to": fighters[k].unit.current_hp}
		if fighters[k].has("owner"):
			row["owner"] = String(fighters[k].owner)
		out.append(row)
	return out


## An army's fighters in fighter order: its units, then the commander, then the ruler.
static func _members(a: Army) -> Array:
	var out: Array = a.units.duplicate()
	if a.commander != null:
		out.append(a.commander)
	if a.ruler != null:
		out.append(a.ruler)
	return out


static func _max_hp(state: GameState, u: Unit) -> int:
	return u.type.hp if u.type.is_ruler else RulerRules.unit_max_hp(state, u)


## The enchantment with this id in `state`, or {}.
static func _enchantment(state: GameState, eid: String) -> Dictionary:
	for e in state.enchantments:
		if String(e.id) == eid:
			return e
	return {}


## The blessing_healed sentence.
static func healed_text(state: GameState, h: Dictionary) -> String:
	return "%s healed %s at %s: %d hit points to %s, the most wounded first (up to %d a turn, through turn %d)." % [
		spell_name(String(h.ritual)), TurnReportText.army_name(state, String(h.army), String(h.faction)), _province_name(state, String(h.province)),
		int(h.total), _count(h.healed.size(), "wounded fighter", "wounded fighters"), int(h.budget), int(h.until_turn)]


## The curse_bit sentence: what the curse took, from whom, and when it ends.
static func bit_text(state: GameState, b: Dictionary) -> String:
	var names := Array(b.armies).map(func(aid): return TurnReportText.army_name(state, String(aid), String(b.victim)))
	var text := "%s (%s) bit at %s: %d hit points from %s of %s (%s), the healthiest first, never below 1. %s's fighters there can't heal while it lies there." % [
		spell_name(String(b.ritual)), _faction_display(state, String(b.faction)), _province_name(state, String(b.province)), int(b.total),
		_count(b.taken.size(), "fighter", "fighters"), _the(state, String(b.victim)), _and_list(names), Serial.cap(_the(state, String(b.victim)))]
	if bool(b.get("ending", false)):
		return text + " A Sanctum Ward ends it now."
	return text + " It lasts through turn %d." % int(b.until_turn)


## The enchantment_ended sentence.
static func ended_text(state: GameState, e: Dictionary) -> String:
	var on := "" if String(e.province).is_empty() else " on %s" % _province_name(state, String(e.province))
	var what := "%s%s (%s)" % [spell_name(String(e.ritual)), on, _faction_display(state, String(e.faction))]
	match String(e.cause):
		"ward":
			return "%s ended early: a Sanctum Ward ended it after one more bite." % what
		"no_armies":
			return "%s ended: no army it blessed is left." % what
	return "%s ended: it lasted through turn %d." % [what, int(e.until_turn)]


## The summon_faded sentence.
static func faded_text(state: GameState, f: Dictionary) -> String:
	var army := TurnReportText.army_name(state, String(f.army), String(f.faction))
	var text := "%d %s of %s faded at %s at the end of turn %d, as Call the Pack said." % [int(f.count),
		String(MagicData.SUMMONS.get(f.type, {}).get("name", f.type)), army, _province_name(state, String(f.province)), int(f.until)]
	if bool(f.removed) and int(f.get("engines_lost", 0)) > 0:
		return text + " %s is gone, and %s it carried %s lost with it: siege engines ride only with fighters." % [Serial.cap(army),
			SiegeRules.engines_text(String(f.faction), int(f.engines_lost)), "is" if int(f.engines_lost) == 1 else "are"]
	return text + (" %s is gone." % Serial.cap(army) if bool(f.removed) else " %s goes on without them." % Serial.cap(army))


## "the Aurel Crown", "the Free Holds".
static func _the(state: GameState, faction_id: String) -> String:
	return AscensionRules._the_faction(state, faction_id)


static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


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


## The same event as its own faction reads it (M5-8, §11.2's first-spell text): "You researched Sunlance. You can now recruit
## Sunstone Adepts at Crownkeep, from turn 3. In battle, each Adept casts a spell every round instead of attacking, ..."
## `state` is the state after the node is done, at the end of `turn`.
static func done_own_text(state: GameState, faction_id: String, node_id: String, turn: int) -> String:
	var n := arcana_node(node_id)
	var school := String(n.get("school", ""))
	if String(n.get("kind", "")) == MagicData.MASTERY_KIND:
		return "You researched %s: +%d mastery in %s for every caster of yours (at most +%d). %s" % [AscensionRules.node_name(node_id),
			int(MagicData.MASTERY.node), school_ref(school), int(MagicData.MASTERY.cap), String(n.get("text", "")).get_slice(": ", 1)]
	var sp := spell_data(node_id)
	if is_ritual(node_id):
		var price := "%d gold a wolf" % int(sp.cost) if String(sp.get("summon", "")) == "thornwolves" else "%d gold" % int(sp.cost) if int(sp.get("cost", 0)) > 0 else "no price"
		return "You researched %s, a ritual of %s. Cast it from any army that holds a caster (its panel has Cast a ritual…), for %s. %s" % [
			AscensionRules.node_name(node_id), school_ref(school), price, String(sp.text)]
	var text := "You researched %s, a battle spell of %s." % [AscensionRules.node_name(node_id), school_ref(school)]
	if known_spells(state, faction_id) == [node_id]:
		var mage := String(mage_data(faction_id).get("name", ""))
		var f := state.find_faction(faction_id)
		var cap := state.find_province(f.capital) if f != null else null
		if not mage.is_empty():
			text += " You can now recruit %s at %s, from turn %d. In battle, each %s casts a spell every round instead of attacking, from your battle spellbook (the Magic tab): %s: %s" % [
				mage, cap.name if cap else "your capital", turn + 1, mage_word(faction_id), spell_name(node_id), String(sp.text)]
			return text
	return "%s In battle your casters cast it from your battle spellbook (the Magic tab): %s" % [text, String(sp.text)]


## A mage in the singular, for "each Adept casts": the last word of the mage's name without its plural s.
static func mage_word(faction_id: String) -> String:
	var words := String(mage_data(faction_id).get("name", "mage")).split(" ", false)
	var w := String(words[words.size() - 1]) if not words.is_empty() else "mage"
	return w.trim_suffix("s")


## "the Sun", "Law", "the Wild", "Blood": a school as running text reads it (MagicData.SCHOOLS "ref").
static func school_ref(school_id: String) -> String:
	return String(school_data(school_id).get("ref", school_name(school_id)))


# --- text -------------------------------------------------------------------------------------------

const NO_MAGIC := "This game is played without magic, so there are no spells or rituals. Tick Magic when you set up a new game to play with it."


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
