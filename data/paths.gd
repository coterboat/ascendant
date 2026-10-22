class_name PathData
## The paths of ascension (M4, design/M4_ASCENSION.md §2.1, §3, §4): one path of 8 nodes per faction,
## with one fork. Proposed by the director, not yet approved by Alex: names, costs and effects can change
## (M4-6 tunes them within §10.3). Same style as data/factions.gd: const dictionaries only. AscensionRules
## (rules/ascension_rules.gd) reads them; nothing else does math on them.
##
## Each node:
##   id, name           e.g. "crown_drillyard", "Drillyard"
##   kind               "tier1" | "tier2" | "oath" | "transformation" (KIND_NAMES has the words)
##   cost               research points
##   requires           node ids that must all be researched first
##   requires_any       how many ordinary (tier I and II) nodes must be researched first, in any mix
##                      (the Oaths: any two); 0 for the others
##   branch             the side of the fork ("celestial_host", ...) for an Oath and its transformation,
##                      "" for an ordinary node. Swearing one Oath closes every node of the other branch.
##   effects            what it does, in the vocabulary of §3.2 (below)
##   codex              its RulesCodex entry
##   text               the one-line effect for cards, tooltips and the turn report
##
## Effects (§3.2). In play from M4-1 (#66): unit (hp, attack, defense, morale and cost parts of regular
## units), income_terrain and tithe_per_province. Stored for later tickets: capture_gold, blood_levy,
## forest_stride, new_unit, rename, province_rule, opens_mandate and forswears (M4-2), and the new units'
## traits in battle (M4-3).
##   unit               {unit type id: {stat: n}}: a named part "path_<node>" on that regular unit type's
##                      "hp", "attack", "defense", "morale" or "cost" (never commanders or rulers)
##   income_terrain     {terrain: n}: every province of that terrain you own earns n more gold (or less;
##                      a province's income is never below 0)
##   tithe_per_province n: your capital earns n gold for every province you own, the capital included
##   capture_gold       n: when your armies capture a province, you gain n x its base income, once
##   blood_levy         n: regular recruits cost cost - floor(cost / n) and arrive missing floor(max hp / n)
##   forest_stride      true: road moves through a forest you own into another forest (§4.8)
##   new_unit           a NEW_UNITS id added to the faction's roster
##   rename             {unit type id: new name}
##   province_rule      {"id": rule id, "value": n}: the transformation's province rule (§4.6, §4.7)
##   opens_mandate      a mandate that can now be bought by sacrifice (MandateData rows come with M4-2)
##   forswears          a mandate that can no longer be bought by sacrifice

## Research per turn (§2.1): the capital you hold yields "capital", every other province you own "province".
const RESEARCH := {"capital": 5, "province": 1}

const TIER1 := "tier1"
const TIER2 := "tier2"
const OATH := "oath"
const TRANSFORMATION := "transformation"
## The ordinary nodes, which an Oath's requires_any counts. They are never closed.
const ORDINARY := [TIER1, TIER2]
const KIND_NAMES := {"tier1": "tier I", "tier2": "tier II", "oath": "Oath", "transformation": "transformation"}

## The sides of the forks: {branch id: {"name" (the people it makes), "ref" (the name in running text), "faction",
## "oath", "transformation", "colour" (the fork's colour word for placeholder frames, §12.3)}}.
const BRANCHES := {
	"celestial_host": {"name": "Celestial Host", "ref": "the Celestial Host", "faction": "kingdom", "oath": "crown_oath_dawn",
		"transformation": "crown_celestial_host", "colour": "gilt"},
	"living_iron": {"name": "Living Iron", "ref": "Living Iron", "faction": "kingdom", "oath": "crown_oath_forge",
		"transformation": "crown_living_iron", "colour": "iron"},
	"thorn_wild": {"name": "Thorn Wild", "ref": "the Thorn Wild", "faction": "beasts", "oath": "beasts_oath_grove",
		"transformation": "beasts_thorn_wild", "colour": "moss"},
	"blood_pact": {"name": "Blood Pact", "ref": "the Blood Pact", "faction": "beasts", "oath": "beasts_oath_blood",
		"transformation": "beasts_blood_pact", "colour": "crimson"},
}

## One path per faction, nodes in the panel's order: tier I, tier II, then each side of the fork (its
## Oath, then its transformation).
const PATHS := {
	"kingdom": {
		"id": "sunstone_path", "name": "the Sunstone Path", "codex": "path_kingdom",
		"nodes": [
			{"id": "crown_drillyard", "name": "Drillyard", "kind": "tier1", "cost": 10, "requires": [], "requires_any": 0,
				"branch": "", "effects": {"unit": {"spearmen": {"hp": 3}}}, "codex": "node_crown_drillyard",
				"text": "Spearmen +3 maximum hit points."},
			{"id": "crown_charters", "name": "Market Charters", "kind": "tier1", "cost": 10, "requires": [], "requires_any": 0,
				"branch": "", "effects": {"income_terrain": {"plains": 2}}, "codex": "node_crown_charters",
				"text": "Every plains province you own earns 2 more gold."},
			{"id": "crown_arbalests", "name": "Arbalests", "kind": "tier2", "cost": 15, "requires": ["crown_drillyard"],
				"requires_any": 0, "branch": "", "effects": {"unit": {"crossbowmen": {"attack": 2}}},
				"codex": "node_crown_arbalests", "text": "Crossbowmen +2 attack."},
			{"id": "crown_stables", "name": "Remount Stables", "kind": "tier2", "cost": 15, "requires": ["crown_charters"],
				"requires_any": 0, "branch": "", "effects": {"unit": {"knights": {"cost": -4}}},
				"codex": "node_crown_stables", "text": "Knights cost 4 gold less."},
			{"id": "crown_oath_dawn", "name": "Oath of the Dawn", "kind": "oath", "cost": 20, "requires": [], "requires_any": 2,
				"branch": "celestial_host", "effects": {"tithe_per_province": 1}, "codex": "node_crown_oath_dawn",
				"text": "Swears to the Celestial Host. Tithe of Light: your capital earns 1 more gold for every province you own."},
			{"id": "crown_celestial_host", "name": "Celestial Host", "kind": "transformation", "cost": 30,
				"requires": ["crown_oath_dawn"], "requires_any": 0, "branch": "celestial_host",
				"effects": {"unit": {"spearmen": {"hp": 2, "morale": 2}}, "rename": {"spearmen": "Sunspears"},
					"new_unit": "seraphs", "province_rule": {"id": "hallowed_land", "value": 3},
					"opens_mandate": "hymn_of_dawn", "forswears": "heavy_tithes"},
				"codex": "node_crown_celestial_host",
				"text": "Spearmen become Sunspears (+2 maximum hit points, +2 morale), Seraphs join the roster, and your wounded heal 3 hit points a turn on your land (Hallowed Land)."},
			{"id": "crown_oath_forge", "name": "Oath of the Forge", "kind": "oath", "cost": 20, "requires": [], "requires_any": 2,
				"branch": "living_iron", "effects": {"income_terrain": {"hills": 4}}, "codex": "node_crown_oath_forge",
				"text": "Swears to Living Iron. Deep Mines: every hills province you own earns 4 more gold."},
			{"id": "crown_living_iron", "name": "Living Iron", "kind": "transformation", "cost": 30,
				"requires": ["crown_oath_forge"], "requires_any": 0, "branch": "living_iron",
				"effects": {"unit": {"knights": {"defense": 4, "cost": 1}}, "rename": {"knights": "Iron Knights"},
					"new_unit": "iron_colossus", "province_rule": {"id": "forges", "value": 0},
					"opens_mandate": "forge_tithe", "forswears": "kings_roads"},
				"codex": "node_crown_living_iron",
				"text": "Knights become Iron Knights (+4 defense, cost 1 gold more), the Iron Colossus joins the roster, and your wounded in your forts heal to full each turn (the Forges)."},
		],
	},
	"beasts": {
		"id": "old_ways", "name": "the Old Ways", "codex": "path_beasts",
		"nodes": [
			{"id": "beasts_boar_hide", "name": "Boar Hide", "kind": "tier1", "cost": 10, "requires": [], "requires_any": 0,
				"branch": "", "effects": {"unit": {"tuskers": {"hp": 3}}}, "codex": "node_beasts_boar_hide",
				"text": "Tuskers +3 maximum hit points."},
			{"id": "beasts_raiding", "name": "Raiding Parties", "kind": "tier1", "cost": 10, "requires": [], "requires_any": 0,
				"branch": "", "effects": {"capture_gold": 2}, "codex": "node_beasts_raiding",
				"text": "When your armies capture a province, you take gold equal to twice its income, once."},
			{"id": "beasts_bone_fangs", "name": "Bone Fangs", "kind": "tier2", "cost": 15, "requires": ["beasts_boar_hide"],
				"requires_any": 0, "branch": "", "effects": {"unit": {"fangthrowers": {"attack": 2}}},
				"codex": "node_beasts_bone_fangs", "text": "Fangthrowers +2 attack."},
			{"id": "beasts_forest_stride", "name": "Forest Stride", "kind": "tier2", "cost": 15, "requires": ["beasts_raiding"],
				"requires_any": 0, "branch": "", "effects": {"forest_stride": true}, "codex": "node_beasts_forest_stride",
				"text": "Your armies can move two provinces in a turn through a forest you own into another forest."},
			{"id": "beasts_oath_grove", "name": "Oath of the Grove", "kind": "oath", "cost": 20, "requires": [], "requires_any": 2,
				"branch": "thorn_wild", "effects": {"income_terrain": {"forest": 2}}, "codex": "node_beasts_oath_grove",
				"text": "Swears to the Thorn Wild. Bounty of the Wild: every forest province you own earns 2 more gold."},
			{"id": "beasts_thorn_wild", "name": "Thorn Wild", "kind": "transformation", "cost": 30,
				"requires": ["beasts_oath_grove"], "requires_any": 0, "branch": "thorn_wild",
				"effects": {"unit": {"fangthrowers": {"defense": 3}}, "rename": {"fangthrowers": "Thornthrowers"},
					"new_unit": "briarwardens", "province_rule": {"id": "wild_spreads", "value": 1},
					"opens_mandate": "deep_roots", "forswears": "blood_frenzy"},
				"codex": "node_beasts_thorn_wild",
				"text": "Fangthrowers become Thornthrowers (+3 defense), Briarwardens join the roster, and one province you own turns to forest each turn (the Wild Spreads)."},
			{"id": "beasts_oath_blood", "name": "Oath of Blood", "kind": "oath", "cost": 20, "requires": [], "requires_any": 2,
				"branch": "blood_pact", "effects": {"blood_levy": 5}, "codex": "node_beasts_oath_blood",
				"text": "Swears to the Blood Pact. Blood Levy: your regular recruits cost a fifth less and arrive missing a fifth of their hit points."},
			{"id": "beasts_blood_pact", "name": "Blood Pact", "kind": "transformation", "cost": 30,
				"requires": ["beasts_oath_blood"], "requires_any": 0, "branch": "blood_pact",
				"effects": {"unit": {"tuskers": {"attack": 2, "hp": -4}}, "rename": {"tuskers": "Bloodtuskers"},
					"new_unit": "bloodsworn", "province_rule": {"id": "dread_lands", "value": 1},
					"opens_mandate": "red_harvest", "forswears": "feast_of_victory"},
				"codex": "node_beasts_blood_pact",
				"text": "Tuskers become Bloodtuskers (+2 attack, 4 fewer maximum hit points), Bloodsworn join the roster, and invaders of your land have 1 less morale (Dread Lands)."},
		],
	},
}

## The units the transformations add (§4.1-4.4). M4-2 puts them on the roster and M4-3 gives their
## traits effects in battle; until then they are data only.
const NEW_UNITS := {
	"seraphs": {"id": "seraphs", "name": "Seraphs", "hp": 16, "attack": 13, "defense": 9, "morale": 12, "cost": 22, "trait": "Wings"},
	"iron_colossus": {"id": "iron_colossus", "name": "Iron Colossus", "hp": 28, "attack": 15, "defense": 9, "morale": 12, "cost": 29, "trait": "Iron Hide"},
	"briarwardens": {"id": "briarwardens", "name": "Briarwardens", "hp": 26, "attack": 11, "defense": 9, "morale": 10, "cost": 21, "trait": "Rooted"},
	"bloodsworn": {"id": "bloodsworn", "name": "Bloodsworn", "hp": 16, "attack": 13, "defense": 5, "morale": 9, "cost": 16, "trait": "Lifedrinker"},
}

## The transformations' province rules (§4.6, §4.7), with their names for text. "value": Hallowed Land
## heals that many hp (Hymn of Dawn doubles it), the Forges heal to full (0 = "to full"), the Wild Spreads
## grows that many provinces a turn (Deep Roots: 2), Dread Lands takes that much enemy morale.
const PROVINCE_RULES := {
	"hallowed_land": {"name": "Hallowed Land", "codex": "hallowed_land"},
	"forges": {"name": "the Forges", "codex": "the_forges"},
	"wild_spreads": {"name": "the Wild Spreads", "codex": "wild_spreads"},
	"dread_lands": {"name": "Dread Lands", "codex": "dread_lands"},
}

## The economy rules the Oaths bring, by node id: their names, for income lines and text.
const ECONOMY_RULES := {
	"crown_oath_dawn": {"name": "Tithe of Light", "codex": "tithe_of_light"},
	"crown_oath_forge": {"name": "Deep Mines", "codex": "deep_mines"},
	"beasts_oath_grove": {"name": "Bounty of the Wild", "codex": "bounty_of_the_wild"},
	"beasts_oath_blood": {"name": "Blood Levy", "codex": "blood_levy"},
}


## CW-4 (#255, design/CANDLEWAKE.md §6): the Candlewake's path, behind their faction's preview (FactionData.PREVIEW_FACTIONS),
## kept apart from PATHS, BRANCHES, NEW_UNITS, PROVINCE_RULES and ECONOMY_RULES so the shipped tables, and everything that walks
## them, stay exactly as they are. AscensionRules reads both (path_data, node_data, branch_data, branches_for, new_unit_data,
## province_rule_data, economy_rule_name). As in M4 (§1, §3), each Oath brings its side's economy rule whole and at once: the
## Oath of the Kept Meadow Wake, the Oath of the Snuffed Pyre Roads. The transformation brings the rest, with the mandate it
## forswears (the director, Q CW-4 1). The path's name, "the Pouring", is the director's, provisional until Alex names it.
## Effects beyond §3.2's vocabulary, read by MarkRules, WickRules and the battle:
##   wake_sooner      n: the Wake-Line comes n turns sooner (MarkRules.threshold; never before 1 turn held)
##   wake_gold        n: a Wake stage that changes a province's gold changes it by n instead (Meadow Wake: +1, not -1)
##   risen            {"from": a stage id, "every": n}: the dead rise from that stage on, every n turns (the Long Sleep)
##   flare_damage     n: a Hundred-Wick's Flare deals n more (Brighter Flare)
##   siphon_heal      {unit type id: n}: those units' Siphon heals n (Red Gleaners: 2)
##   flame_cap        n: the flame's cap (the Red Wake: 4); above the row's cap an army that doesn't win drops to it
##   idle_loss        n: what an army idle outside a harbour loses (the Red Wake: 2)
##   harvest_bonus    n: every Harvest raises n more (the Swelling)
##   pyre_roads       n: a win in a province of yours that stood at the Wake-Line or deeper when the battles began gives n flame
##                    instead of 1, never above the flame's cap (Pyre Roads)
const PREVIEW_BRANCHES := {
	"golden_wake": {"name": "Golden Wake", "ref": "the Golden Wake", "faction": "candlewake", "oath": "wake_oath_kept",
		"transformation": "wake_golden_wake", "colour": "honey"},
	"red_wake": {"name": "Red Wake", "ref": "the Red Wake", "faction": "candlewake", "oath": "wake_oath_snuffed",
		"transformation": "wake_red_wake", "colour": "cherry"},
}

const PREVIEW_PATHS := {
	"candlewake": {
		"id": "the_pouring", "name": "the Pouring", "codex": "path_candlewake",
		"nodes": [
			{"id": "wake_thicker_tallow", "name": "Thicker Tallow", "kind": "tier1", "cost": 10, "requires": [], "requires_any": 0,
				"branch": "", "effects": {"unit": {"wickwardens": {"hp": 3}}}, "codex": "node_wake_thicker_tallow",
				"text": "Wickwardens +3 maximum hit points."},
			{"id": "wake_sitting_up_early", "name": "Sitting Up Early", "kind": "tier1", "cost": 10, "requires": [], "requires_any": 0,
				"branch": "", "effects": {"wake_sooner": 1}, "codex": "node_wake_sitting_up_early",
				"text": "The Wake-Line comes 1 turn sooner."},
			{"id": "wake_brighter_flare", "name": "Brighter Flare", "kind": "tier2", "cost": 15, "requires": ["wake_thicker_tallow"],
				"requires_any": 0, "branch": "", "effects": {"flare_damage": 1}, "codex": "node_wake_brighter_flare",
				"text": "A Hundred-Wick's Flare deals 1 more damage to each enemy it burns."},
			{"id": "wake_hungry_gleaners", "name": "Hungry Gleaners", "kind": "tier2", "cost": 15, "requires": ["wake_sitting_up_early"],
				"requires_any": 0, "branch": "", "effects": {"unit": {"gleaners": {"attack": 2}}}, "codex": "node_wake_hungry_gleaners",
				"text": "Gleaners +2 attack."},
			{"id": "wake_oath_kept", "name": "Oath of the Kept", "kind": "oath", "cost": 20, "requires": [], "requires_any": 2,
				"branch": "golden_wake", "effects": {"wake_gold": 1, "wake_sooner": 1}, "codex": "node_wake_oath_kept",
				"text": "Swears to the Golden Wake. Meadow Wake: your Wake pays 1 gold where it cost 1, and the Wake-Line comes 1 turn sooner."},
			{"id": "wake_golden_wake", "name": "Golden Wake", "kind": "transformation", "cost": 30,
				"requires": ["wake_oath_kept"], "requires_any": 0, "branch": "golden_wake",
				"effects": {"unit": {"wickwardens": {"hp": 2, "morale": 1}}, "rename": {"wickwardens": "Combwardens"},
					"new_unit": "amber_saints", "province_rule": {"id": "the_long_sleep", "value": 3},
					"risen": {"from": "wake_line", "every": 3}, "forswears": "muster_grounds"},
				"codex": "node_wake_golden_wake",
				"text": "Wickwardens become Combwardens (+2 maximum hit points, +1 morale), Amber Saints join the roster, and the dead rise from the Wake-Line too, every 3 turns (the Long Sleep)."},
			{"id": "wake_oath_snuffed", "name": "Oath of the Snuffed", "kind": "oath", "cost": 20, "requires": [], "requires_any": 2,
				"branch": "red_wake", "effects": {"pyre_roads": 2}, "codex": "node_wake_oath_snuffed",
				"text": "Swears to the Red Wake. Pyre Roads: a win in your own Wake gives +2 flame instead of +1, never above the flame's cap."},
			{"id": "wake_red_wake", "name": "Red Wake", "kind": "transformation", "cost": 30,
				"requires": ["wake_oath_snuffed"], "requires_any": 0, "branch": "red_wake",
				"effects": {"unit": {"gleaners": {"attack": 2, "hp": -2}}, "rename": {"gleaners": "Red Gleaners"},
					"siphon_heal": {"gleaners": 2}, "new_unit": "pyre_walkers", "flame_cap": 4, "idle_loss": 2, "harvest_bonus": 1,
					"forswears": "iron_discipline"},
				"codex": "node_wake_red_wake",
				"text": "Gleaners become Red Gleaners (+2 attack, 2 fewer maximum hit points, Siphon heals 2), Pyre-Walkers join the roster, your flame burns to 4 (above 3 it drops to 3 unless it wins, and idle outside a harbour it loses 2), and every Harvest raises one more (the Swelling)."},
		],
	},
}

## The units the Candlewake's transformations add (§6.2, §6.3), with reused traits.
const PREVIEW_NEW_UNITS := {
	"amber_saints": {"id": "amber_saints", "name": "Amber Saints", "hp": 24, "attack": 11, "defense": 9, "morale": 11, "cost": 22, "trait": "Iron Hide"},
	"pyre_walkers": {"id": "pyre_walkers", "name": "Pyre-Walkers", "hp": 16, "attack": 13, "defense": 5, "morale": 9, "cost": 18, "trait": "Berserk"},
}

## The Golden Wake's province rule (§6.2, §3.6): the Long Sleep ("value" the turns between risers). The Red Wake's
## transformation has none: the Swelling is Harvest's and the flame's cap is Wick's.
const PREVIEW_PROVINCE_RULES := {
	"the_long_sleep": {"name": "the Long Sleep", "codex": "the_long_sleep"},
}

## The economy rules the Candlewake's Oaths bring, by node id (as ECONOMY_RULES): Meadow Wake and Pyre Roads.
const PREVIEW_ECONOMY_RULES := {
	"wake_oath_kept": {"name": "Meadow Wake", "codex": "meadow_wake"},
	"wake_oath_snuffed": {"name": "Pyre Roads", "codex": "pyre_roads"},
}
