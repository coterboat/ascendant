class_name RulerData
## The four M2 rulers (design/M2_RULER.md §1.2-1.4 and §5.2). Proposed by the director, not yet
## approved by Alex: every name and number here can change. Same style as data/factions.gd: const
## dictionaries only. RulerRules (rules/ruler_rules.gd) holds all the math that reads them.
##
## Each ruler:
##   id, faction       the ruler's id and the faction id it can lead
##   name              the name of the line (the first ruler's name comes from `naming`)
##   naming            how generation n is named (RulerRules.ruler_name):
##                       "fixed"    always `name`
##                       "regnal"   `ruler` with a roman numeral: King Corvane I, King Corvane II, ...
##                                  `heir` is the successor's name before the crowning: Corvane II
##                       "ordinal"  `ruler` with an ordinal word, counting from `first`:
##                                  the Ninth Fang, the Tenth Fang, ...
##   kind              "mortal" | "undying" | "god" (KINDS), which decides succession
##   battle_rank       "front" (attacked from round 1) | "second" (behind the front, like Volley)
##   morale            its morale when it fights with no regular units beside it
##   stats             hp (maximum hp), attack, defense at kept power k:
##                       base + gain x (k / per, rounded down)          (§1.3)
##   ability           its province ability, an ABILITIES id
##   succession        {"delay": turns until the successor arrives,
##                      "power": "half" (rounded down) | "same" | "minus" (by `minus`, never below 0)}
##   flavour           one line for the codex and the build screen
##
## M2-8 may tune (spec §8.3): hp gain ±1, base stats ±2, ability values ±1 per rank, succession
## delays ±1 turn. Tests read the numbers from here, except the §1.3 table they check against.

## Every ruler's power pool (§1.1). Kept power is 0..POWER_POOL.
const POWER_POOL := 10
## Morale a living ruler gives its side in battle (§1.3). Stacks with a commander's +2.
const RULER_MORALE := 2
## Ability rank = 1 + kept power / ABILITY_RANK_PER, rounded down, at most MAX_ABILITY_RANK (§1.1).
const ABILITY_RANK_PER := 3
const MAX_ABILITY_RANK := 4

const RULERS: Array[Dictionary] = [
	{
		"id": "aurel_king",
		"faction": "kingdom",
		"name": "King Corvane",
		"naming": {"style": "regnal", "ruler": "King Corvane %s", "heir": "Corvane %s"},
		"kind": "mortal",
		"battle_rank": "front",
		"morale": 10,
		"stats": {
			"hp": {"base": 18, "gain": 2, "per": 1},
			"attack": {"base": 9, "gain": 1, "per": 2},
			"defense": {"base": 8, "gain": 1, "per": 2},
		},
		"ability": "royal_court",
		"succession": {"delay": 2, "power": "half"},
		"flavour": "An ordinary man of the Aurel line. Spend his power and he governs the best-equipped kingdom in the land. Keep it and he rides to war as a paladin.",
	},
	{
		"id": "ever_regent",
		"faction": "kingdom",
		"name": "the Ever-Regent",
		"naming": {"style": "fixed"},
		"kind": "undying",
		"battle_rank": "second",
		"morale": 10,
		"stats": {
			"hp": {"base": 14, "gain": 1, "per": 1},
			"attack": {"base": 8, "gain": 1, "per": 1},
			"defense": {"base": 6, "gain": 1, "per": 2},
		},
		"ability": "mending_light",
		"succession": {"delay": 4, "power": "same"},
		"flavour": "An archmage who bound his life to the sunstone in Crownkeep. He cannot die, only be broken, and he re-forms slowly. His spells count as attacks until magic comes to the game.",
	},
	{
		"id": "thornmane_avatar",
		"faction": "beasts",
		"name": "the Great Thornmane",
		"naming": {"style": "fixed"},
		"kind": "god",
		"battle_rank": "front",
		"morale": 14,
		"stats": {
			"hp": {"base": 24, "gain": 3, "per": 1},
			"attack": {"base": 8, "gain": 1, "per": 1},
			"defense": {"base": 7, "gain": 1, "per": 2},
		},
		"ability": "dread",
		"succession": {"delay": 1, "power": "minus", "minus": 3},
		"flavour": "The clans' beast-god, walking among them in a body of briar and fur. When the body is slain, the god takes a new one, a little less of itself each time.",
	},
	{
		"id": "fang_chieftain",
		"faction": "beasts",
		"name": "the Ninth Fang",
		"naming": {"style": "ordinal", "ruler": "the %s Fang", "first": 9},
		"kind": "mortal",
		"battle_rank": "front",
		"morale": 12,
		"stats": {
			"hp": {"base": 20, "gain": 2, "per": 1},
			"attack": {"base": 9, "gain": 1, "per": 1},
			"defense": {"base": 7, "gain": 1, "per": 2},
		},
		"ability": "warband_muster",
		"succession": {"delay": 2, "power": "half"},
		"flavour": "The high chieftain of the old fang bloodline. When one Fang falls, the next of the blood takes the mantle.",
	},
]

## Province abilities (§1.4). `values` is the effect at ability rank 1..4. `effect` is the plain rule
## with {ruler} (the ruler's name) and {value} filled in by RulerRules.ability_text.
const ABILITIES := {
	"royal_court": {
		"name": "Royal Court",
		"values": [2, 3, 4, 5],
		"short": "+{value} gold",
		"effect": "In the income phase, the province {ruler} is in earns {value} more gold, if you own it.",
	},
	"mending_light": {
		"name": "Mending Light",
		"values": [3, 6, 9, 12],
		"short": "heal {value}",
		"effect": "At the end of each turn, each of your wounded units and commanders in the province {ruler} is in heals {value} hit points, up to its maximum. Rulers heal on their own instead.",
	},
	"dread": {
		"name": "Dread",
		"values": [1, 1, 1, 1],
		"short": "-{value} enemy morale",
		"effect": "Every enemy side in a province battle {ruler} fights in has {value} less morale. Not in border battles. It adds to a War Bear's Fury.",
	},
	"warband_muster": {
		"name": "Warband Muster",
		"values": [1, 2, 3, 4],
		"short": "{value} recruits in the field",
		"effect": "Each turn you may recruit up to {value} regular units with {ruler}, at the usual prices. They gather where {ruler} starts the turn and join your armies there at the end of the turn, if you still own that province then. Commanders still come only from the capital.",
	},
}

## Kinds of ruler and how each is succeeded (§5.2). `codex` is the RulesCodex entry for the rule.
const KINDS := {
	"mortal": {"name": "mortal line", "codex": "succession_mortal"},
	"undying": {"name": "undying", "codex": "succession_undying"},
	"god": {"name": "god", "codex": "succession_god"},
}

## Player-facing words for the battle ranks (§1.6).
const BATTLE_RANKS := {
	"front": "fights in the front rank",
	"second": "fights in the second rank",
}
