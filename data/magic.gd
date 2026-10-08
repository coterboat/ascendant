class_name MagicData
## Magic (M5, design/M5_MAGIC_FOG.md §3-§8): the schools, the spells and rituals, the arcana (each faction's
## magic research), the mages, the summoned creatures, the rulers' magic and mastery. Proposed by the director,
## not yet approved by Alex: names and numbers can change (M5-11 tunes them within §13.3). Same style as
## data/factions.gd and data/paths.gd: const dictionaries only. MagicRules (rules/magic_rules.gd) reads them,
## and AscensionRules reads ARCANA through its lookup hook; nothing else does math on them.
## New factions add rows: a school, its spells, a mage, a default spellbook. A new effect kind is code.

## The schools (§3.1): {id: {"id", "name", "ref" (in running text), "faction", "aligned_branch" (the side of the
## fork whose Oath opens its greater working, and whose transformation adds +1 mastery), "nodes" (the arcana
## node ids, tier I, tier II, mastery, tier III), "codex", "flavour"}}.
const SCHOOLS := {
	"sun": {"id": "sun", "name": "Sun", "ref": "the Sun", "faction": "kingdom", "aligned_branch": "celestial_host",
		"nodes": ["sunlance", "dawn_blessing", "sun_mastery", "sunburst"], "codex": "school_sun",
		"flavour": "light that smites and heals"},
	"law": {"id": "law", "name": "Law", "ref": "Law", "faction": "kingdom", "aligned_branch": "living_iron",
		"nodes": ["shield_of_law", "sanctum_ward", "law_mastery", "bastion"], "codex": "school_law",
		"flavour": "shields for armies on the march, wards against magic, stone"},
	"wild": {"id": "wild", "name": "the Wild", "ref": "the Wild", "faction": "beasts", "aligned_branch": "thorn_wild",
		"nodes": ["briar_snare", "call_the_pack", "wild_mastery", "wake_the_greenwrath"], "codex": "school_wild",
		"flavour": "thorn, beast and forest"},
	"blood": {"id": "blood", "name": "Blood", "ref": "Blood", "faction": "beasts", "aligned_branch": "blood_pact",
		"nodes": ["bloodbolt", "bloodrot", "blood_mastery", "blood_moon"], "codex": "school_blood",
		"flavour": "the price paid in life"},
}

## Each faction's schools, in the Magic tab's order.
const FACTION_SCHOOLS := {"kingdom": ["sun", "law"], "beasts": ["wild", "blood"]}

## Far Sight's school: every faction with a caster knows it, without research (§6.2).
const COMMON := "common"

## Battle spell kinds (§3.4) and ritual kinds (§6.2).
const BATTLE_KINDS := ["bolt", "hex", "shield", "drink"]
const RITUAL_KINDS := ["blessing", "ward", "curse", "summon", "raising", "global", "sight"]

## Every spell and ritual (§3.4, §5.2, §6.2), 13 rows: {"id", "name", "school", "tier" ("I", "II", "III" or ""),
## "kind", "battle" (true for a battle spell), "codex", "text" (the one plain line players read), and:
##   battle spells:  "value" (bolt damage, or the part a hex or shield gives), "stat" (the part's stat), "count"
##                   (units a hex or shield covers), "forest_count" (Briar Snare in a forest), "bleed" and
##                   "min_caster_hp" (Bloodbolt), "round" (Sunburst: round 1 only), "per_bonus" ({field: n},
##                   what each point of mastery adds)
##   rituals:        "cost" (gold; Call the Pack's is per wolf), "range" (provinces from the caster; 0 is the
##                   caster's own), "target" (the target rule, below), "duration" (turns after the cast turn:
##                   "through turn T + duration"; -1 for good or until it falls), "value" (a budget of hp a
##                   turn), "count" (wolves), "summon" (a SUMMONS id), "cap" (Bastion), "share" (Blood Moon's
##                   heal-back divisor), "per_bonus"
## Target rules: "own_with_army" (a province you own where an army of yours stands), "own" (a province you own),
## "own_no_fort" (a province you own without a fort), "caster" (the caster's own province), "caster_forest"
## (the caster's own province, which must be forest), "not_own" (a province not yours), "none" (no target),
## "any" (any province).
const SPELLS := {
	"sunlance": {"id": "sunlance", "name": "Sunlance", "school": "sun", "tier": "I", "kind": "bolt", "battle": true,
		"value": 4, "per_bonus": {"value": 1}, "codex": "spell_sunlance",
		"text": "4 sure damage to the enemy unit or creature it can reach with the highest maximum hit points, the most hurt of those first; rulers and commanders only when nothing else is in reach."},
	"shield_of_law": {"id": "shield_of_law", "name": "Shield of Law", "school": "law", "tier": "I", "kind": "shield", "battle": true,
		"value": 4, "stat": "defense", "count": 6, "per_bonus": {"count": 1}, "codex": "spell_shield_of_law",
		"text": "+4 defense this round for up to 6 of your front-rank units of one type that have no terrain or fort bonus. A field spell: it never helps a unit already behind walls, woods or hills."},
	"sunburst": {"id": "sunburst", "name": "Sunburst", "school": "sun", "tier": "III", "kind": "hex", "battle": true,
		"value": -2, "stat": "attack", "round": 1, "per_bonus": {}, "codex": "spell_sunburst",
		"text": "In round 1 only, once per side per battle: every enemy fighter in the front rank, rulers included, has -2 attack that round."},
	"briar_snare": {"id": "briar_snare", "name": "Briar Snare", "school": "wild", "tier": "I", "kind": "hex", "battle": true,
		"value": -2, "stat": "attack", "count": 6, "forest_count": 8, "per_bonus": {"count": 1}, "codex": "spell_briar_snare",
		"text": "-2 attack this round for up to 6 enemy front-rank units of one type (8 in a forest battle): the most numerous type not yet snared."},
	"bloodbolt": {"id": "bloodbolt", "name": "Bloodbolt", "school": "blood", "tier": "I", "kind": "bolt", "battle": true,
		"value": 5, "bleed": 2, "min_caster_hp": 3, "per_bonus": {"value": 1}, "codex": "spell_bloodbolt",
		"text": "5 sure damage to the enemy unit or creature it can reach with the fewest hit points left that isn't already going to die this round. The caster bleeds 2 hit points, never below 1, and needs 3 or more to cast it."},
	"dawn_blessing": {"id": "dawn_blessing", "name": "Dawn Blessing", "school": "sun", "tier": "II", "kind": "blessing", "battle": false,
		"cost": 12, "range": 2, "target": "own_with_army", "duration": 2, "value": 12, "morale": 1, "per_bonus": {"value": 4},
		"codex": "spell_dawn_blessing",
		"text": "Blesses every army of yours in a province you own within 2, through turn T + 2, wherever it goes: +1 morale in battle when at least half a side's fighters are blessed, and each blessed army heals 12 hit points a turn."},
	"sanctum_ward": {"id": "sanctum_ward", "name": "Sanctum Ward", "school": "law", "tier": "II", "kind": "ward", "battle": false,
		"cost": 8, "range": 2, "target": "own", "duration": 1, "per_bonus": {"duration": 1}, "codex": "spell_sanctum_ward",
		"text": "Wards a province you own within 2 through turn T + 1: rival rituals aimed at it are turned aside, a rival curse there ends after one more bite, and battles there are outside the Blood Moon."},
	"bastion": {"id": "bastion", "name": "Bastion", "school": "law", "tier": "III", "kind": "raising", "battle": false,
		"cost": 30, "range": 1, "target": "own_no_fort", "duration": -1, "cap": 2, "per_bonus": {}, "codex": "spell_bastion",
		"text": "Raises a fort for good in a province you own within 1 that has none. At most 2 Bastion forts per faction, ever."},
	"call_the_pack": {"id": "call_the_pack", "name": "Call the Pack", "school": "wild", "tier": "II", "kind": "summon", "battle": false,
		"cost": 5, "range": 0, "target": "caster", "duration": 4, "count": 3, "summon": "thornwolves", "per_bonus": {"count": 1},
		"codex": "spell_call_the_pack",
		"text": "Calls 3 Thornwolves (up to 3 + your Wild mastery), 5 gold each, as a new army of their own at the caster's province, through turn T + 4. One pack at a time."},
	"wake_the_greenwrath": {"id": "wake_the_greenwrath", "name": "Wake the Greenwrath", "school": "wild", "tier": "III", "kind": "summon", "battle": false,
		"cost": 30, "range": 0, "target": "caster_forest", "duration": -1, "summon": "greenwrath", "per_bonus": {},
		"codex": "spell_wake_the_greenwrath",
		"text": "Wakes the Greenwrath as a new army of its own at the caster's province, which must be forest. It stays until it falls. One at a time."},
	"bloodrot": {"id": "bloodrot", "name": "Bloodrot", "school": "blood", "tier": "II", "kind": "curse", "battle": false,
		"cost": 15, "range": 2, "target": "not_own", "duration": 2, "value": 12, "per_bonus": {"value": 4}, "codex": "spell_bloodrot",
		"text": "Curses a province not yours within 2 through turn T + 2: fighters there not of your faction can't heal, and it takes 12 hit points a turn from them, from the healthiest first, never below 1."},
	"blood_moon": {"id": "blood_moon", "name": "Blood Moon", "school": "blood", "tier": "III", "kind": "global", "battle": false,
		"cost": 26, "range": 0, "target": "none", "duration": 2, "share": 5, "per_bonus": {}, "codex": "spell_blood_moon",
		"text": "Through turn T + 2, in every battle, each of your standing fighters heals back a fifth of the damage it dealt that round, rounded down, never above its maximum - 1. Only one global ritual at a time."},
	"far_sight": {"id": "far_sight", "name": "Far Sight", "school": "common", "tier": "", "kind": "sight", "battle": false,
		"cost": 6, "range": 3, "target": "any", "duration": 2, "per_bonus": {}, "codex": "spell_far_sight",
		"text": "You see a province within 3 in clear sight at the start of your next 2 turns. On a rival's capital it also reads that rival's gold, mandates, kept power, research, spells and spellbook. Known by every faction with a caster."},
}

## Each faction's default battle spellbook (§5.1): every battle spell of its schools, in order.
const SPELLBOOK := {"kingdom": ["sunburst", "sunlance", "shield_of_law"], "beasts": ["briar_snare", "bloodbolt"]}

## The arcana (§4): each faction's magic research, two schools of four nodes, read by AscensionRules through its
## node lookup. A node: {"id", "name", "kind" ("spell" or "mastery"), "tier" ("I", "II", "mastery", "III"),
## "school", "cost", "requires" (node ids that must all be researched first; tier III also needs its school's
## aligned Oath), "requires_any" 0, "branch" "" (arcana nodes are never part of the fork), "oath_branch" (tier
## III: the side whose Oath opens it; swearing the other closes it), "codex", "text"}. A spell node's id is the
## spell's id. Nothing in the arcana closes anything; only the Oath gates tier III.
const SPELL := "spell"
const MASTERY_KIND := "mastery"
const KIND_NAMES := {"I": "tier I spell", "II": "tier II ritual", "mastery": "mastery", "III": "tier III greater working"}
const ARCANA := {
	"kingdom": [
		{"id": "sunlance", "name": "Sunlance", "kind": "spell", "tier": "I", "school": "sun", "cost": 10, "requires": [],
			"requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_sunlance",
			"text": "Battle spell (Sun): 4 sure damage to the biggest enemy creature in reach, every round."},
		{"id": "dawn_blessing", "name": "Dawn Blessing", "kind": "spell", "tier": "II", "school": "sun", "cost": 15,
			"requires": ["sunlance"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_dawn_blessing",
			"text": "Ritual (Sun): blesses your armies in a province, +1 morale and 12 hit points healed a turn, for 12 gold."},
		{"id": "sun_mastery", "name": "Sun Mastery", "kind": "mastery", "tier": "mastery", "school": "sun", "cost": 20,
			"requires": ["dawn_blessing"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "node_sun_mastery",
			"text": "+1 mastery in the Sun for every caster: Sunlance +1 damage, Dawn Blessing +4 hit points a turn."},
		{"id": "sunburst", "name": "Sunburst", "kind": "spell", "tier": "III", "school": "sun", "cost": 25,
			"requires": ["dawn_blessing", "crown_oath_dawn"], "requires_any": 0, "branch": "", "oath_branch": "celestial_host",
			"codex": "spell_sunburst",
			"text": "Greater working (Sun): in round 1, every enemy front-rank fighter has -2 attack. Needs the Oath of the Dawn."},
		{"id": "shield_of_law", "name": "Shield of Law", "kind": "spell", "tier": "I", "school": "law", "cost": 10, "requires": [],
			"requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_shield_of_law",
			"text": "Battle spell (Law): +4 defense for 6 of your front-rank units in the open, every round."},
		{"id": "sanctum_ward", "name": "Sanctum Ward", "kind": "spell", "tier": "II", "school": "law", "cost": 15,
			"requires": ["shield_of_law"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_sanctum_ward",
			"text": "Ritual (Law): wards a province of yours against rival rituals and curses, for 8 gold."},
		{"id": "law_mastery", "name": "Law Mastery", "kind": "mastery", "tier": "mastery", "school": "law", "cost": 20,
			"requires": ["sanctum_ward"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "node_law_mastery",
			"text": "+1 mastery in Law for every caster: Shield of Law covers 1 more unit, Sanctum Ward lasts 1 more turn."},
		{"id": "bastion", "name": "Bastion", "kind": "spell", "tier": "III", "school": "law", "cost": 25,
			"requires": ["sanctum_ward", "crown_oath_forge"], "requires_any": 0, "branch": "", "oath_branch": "living_iron",
			"codex": "spell_bastion",
			"text": "Greater working (Law): raises a fort in a province of yours, at most 2 ever. Needs the Oath of the Forge."},
	],
	"beasts": [
		{"id": "briar_snare", "name": "Briar Snare", "kind": "spell", "tier": "I", "school": "wild", "cost": 10, "requires": [],
			"requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_briar_snare",
			"text": "Battle spell (the Wild): -2 attack for 6 enemy front-rank units (8 in a forest), every round."},
		{"id": "call_the_pack", "name": "Call the Pack", "kind": "spell", "tier": "II", "school": "wild", "cost": 15,
			"requires": ["briar_snare"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_call_the_pack",
			"text": "Ritual (the Wild): calls a pack of 3 or more Thornwolves for 5 gold each, for 5 turns."},
		{"id": "wild_mastery", "name": "Wild Mastery", "kind": "mastery", "tier": "mastery", "school": "wild", "cost": 20,
			"requires": ["call_the_pack"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "node_wild_mastery",
			"text": "+1 mastery in the Wild for every caster: Briar Snare covers 1 more unit, the pack can be 1 wolf bigger."},
		{"id": "wake_the_greenwrath", "name": "Wake the Greenwrath", "kind": "spell", "tier": "III", "school": "wild", "cost": 25,
			"requires": ["call_the_pack", "beasts_oath_grove"], "requires_any": 0, "branch": "", "oath_branch": "thorn_wild",
			"codex": "spell_wake_the_greenwrath",
			"text": "Greater working (the Wild): wakes the Greenwrath in a forest, until it falls. Needs the Oath of the Grove."},
		{"id": "bloodbolt", "name": "Bloodbolt", "kind": "spell", "tier": "I", "school": "blood", "cost": 10, "requires": [],
			"requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_bloodbolt",
			"text": "Battle spell (Blood): 5 sure damage that finishes the weakest enemy in reach; the caster bleeds 2."},
		{"id": "bloodrot", "name": "Bloodrot", "kind": "spell", "tier": "II", "school": "blood", "cost": 15,
			"requires": ["bloodbolt"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "spell_bloodrot",
			"text": "Ritual (Blood): curses a province not yours, no healing and 12 hit points taken a turn, for 15 gold."},
		{"id": "blood_mastery", "name": "Blood Mastery", "kind": "mastery", "tier": "mastery", "school": "blood", "cost": 20,
			"requires": ["bloodrot"], "requires_any": 0, "branch": "", "oath_branch": "", "codex": "node_blood_mastery",
			"text": "+1 mastery in Blood for every caster: Bloodbolt +1 damage, Bloodrot +4 hit points a turn."},
		{"id": "blood_moon", "name": "Blood Moon", "kind": "spell", "tier": "III", "school": "blood", "cost": 25,
			"requires": ["bloodrot", "beasts_oath_blood"], "requires_any": 0, "branch": "", "oath_branch": "blood_pact",
			"codex": "spell_blood_moon",
			"text": "Greater working (Blood): for 3 turns your fighters heal back a fifth of the damage they deal. Needs the Oath of Blood."},
	],
}

## Each faction's mage (§3.2): a regular unit with the trait Mage, on the roster from turn 1 in a magic game and
## recruitable once the faction knows a spell. It fights from the second rank and casts instead of attacking.
const MAGE_TRAIT := "Mage"
const MAGES := {
	"kingdom": {"id": "adepts", "name": "Sunstone Adepts", "hp": 10, "attack": 7, "defense": 5, "morale": 9, "cost": 15, "trait": "Mage"},
	"beasts": {"id": "shamans", "name": "Thornmane Shamans", "hp": 10, "attack": 7, "defense": 4, "morale": 8, "cost": 14, "trait": "Mage"},
}

## The summoned creatures (§6.2): never recruited, never on a roster; in a magic game GameState.from_dict loads
## their types. "fades": the creature leaves at the end of the turn its Unit.until names (Thornwolves); the
## Greenwrath stays until it falls (until 0). "faction": who summons it.
const SUMMONS := {
	"thornwolves": {"id": "thornwolves", "name": "Thornwolves", "hp": 9, "attack": 11, "defense": 4, "morale": 8, "trait": "Skirmish",
		"faction": "beasts", "fades": true, "codex": "unit_thornwolves"},
	"greenwrath": {"id": "greenwrath", "name": "Greenwrath", "hp": 40, "attack": 15, "defense": 9, "morale": 14, "trait": "Rooted",
		"faction": "beasts", "fades": false, "codex": "unit_greenwrath"},
}

## The rulers' magic (§3.2, §7): {ruler id: {"schools" (whose rituals it casts, and whose mastery its rank adds
## to), "battle" (it casts battle spells: only the Ever-Regent), "own_spell" (a battle spell it always knows),
## "line" (the build screen's line)}}. A ruler with schools also knows Far Sight. King Corvane casts nothing.
const RULER_MAGIC := {
	"aurel_king": {"schools": [], "battle": false, "own_spell": "", "line": "Casts nothing: an ordinary man."},
	"ever_regent": {"schools": ["sun", "law"], "battle": true, "own_spell": "sunlance",
		"line": "Casts Sunlance in battle from turn 1, every Crown battle spell you research, and every Crown ritual you research."},
	"thornmane_avatar": {"schools": ["wild"], "battle": false, "own_spell": "",
		"line": "Casts the Wild's rituals once you research them: Call the Pack and Wake the Greenwrath."},
	"fang_chieftain": {"schools": ["blood"], "battle": false, "own_spell": "",
		"line": "Casts Blood's rituals once you research them: Bloodrot and Blood Moon."},
}

## Mastery (§3.2): a caster's skill in one school, as a bonus. A mage +0; a ruler + (ability rank - 1) in its own
## schools; the faction's transformation +1 in its aligned school; the school's mastery node +1; at most +3.
const MASTERY := {"mage": 0, "transformation": 1, "node": 1, "cap": 3}
## The school's mastery node, by school.
const MASTERY_NODES := {"sun": "sun_mastery", "law": "law_mastery", "wild": "wild_mastery", "blood": "blood_mastery"}

## How a share of the damage is said in words (Blood Moon's "share" is the divisor: 4 is a quarter, 5 a fifth). MagicRules.moon_share_word.
const SHARE_WORDS := {2: "half", 3: "a third", 4: "a quarter", 5: "a fifth"}

## Spell resistance (§5.2): each bolt on a ruler deals ability rank / RULER_RESIST less, rounded down, never below 1.
const RULER_RESIST := 2
## Research sold (§4): once nothing is left to research, RESEARCH_SOLD research become 1 gold, rounded down.
const RESEARCH_SOLD := 2
## A ritual turned aside by a ward costs 1 / TURNED_ASIDE of its price, rounded down (§6.2).
const TURNED_ASIDE := 2
## At most this many Bastion forts per faction, ever (§6.2).
const BASTION_CAP := 2
## Tithe of Blood (§7.1): hp paid for each gold of a ritual's price.
const BLOOD_PER_GOLD := 1
