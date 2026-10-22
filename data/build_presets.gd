class_name BuildPresetData
## Ready-made ruler builds, three per faction (design/M2_RULER.md §6.1). They are the build screen's
## quick buttons (M2-5) and the builds AI seats pick from (M2-7). Until the build screen exists, a game
## set up with rulers gives each faction without a chosen build its "balanced" preset
## (RulerRules.balanced_preset). Proposed by the director; Alex can change any of them.
##
## Each preset:
##   id, name, style    style is "keep" | "spend" | "balanced"
##   ruler, mandates    the build itself: a RulerData id and MandateData ids, in the order taken
##   ai_role            "field" (the ruler marches with the strongest army) | "home" (it stays home).
##                      #131: the spend presets march too (they were "home"): their 0-kept ruler costs nothing
##                      to lose, since mandates outlive it, and kept home it never fought
##   ai_sacrifices      mandates an AI seat sacrifices for, in this order (§6.3)
## The order inside each faction's list matters: an AI seat picks presets[faction][roll 0..2].

const BALANCED := "balanced"

## CW-2 (#253, design/CANDLEWAKE.md §4.4): the Candlewake's presets, behind their faction's preview (FactionData.
## PREVIEW_FACTIONS), kept apart from PRESETS so the shipped lists and everything that walks them stay as they are; RulerRules
## reads both. In the same order as the others: keep, spend, balanced. The computer's play of them is CW-6 (lane AI).
const PREVIEW_PRESETS := {
	"candlewake": [
		{"id": "the_long_procession", "name": "the Long Procession", "style": "keep", "ruler": "half_death",
			"mandates": [], "ai_role": "field", "ai_sacrifices": ["kindling", "iron_discipline"]},
		{"id": "ninth_chandlers_vigil", "name": "the Ninth Chandler's Vigil", "style": "spend", "ruler": "mother_tallow",
			"mandates": ["kindling", "tallow_levy", "heavy_tithes"], "ai_role": "home", "ai_sacrifices": []},
		{"id": "harvest_moot", "name": "the Harvest Moot", "style": "balanced", "ruler": "half_death",
			"mandates": ["kindling", "iron_discipline"], "ai_role": "field", "ai_sacrifices": ["tallow_levy", "veteran_levies"]},
	],
}

const PRESETS := {
	"kingdom": [
		{"id": "warrior_king", "name": "Warrior King", "style": "keep", "ruler": "aurel_king",
			"mandates": [], "ai_role": "field", "ai_sacrifices": ["royal_armories", "veteran_levies"]},
		{"id": "iron_crown", "name": "Iron Crown", "style": "spend", "ruler": "aurel_king",
			"mandates": ["royal_armories", "heavy_tithes", "veteran_levies"], "ai_role": "field", "ai_sacrifices": []},
		{"id": "regents_court", "name": "Regent's Court", "style": "balanced", "ruler": "ever_regent",
			"mandates": ["royal_armories", "kings_roads"], "ai_role": "field", "ai_sacrifices": ["drilled_ranks", "veteran_levies"]},
	],
	"beasts": [
		{"id": "beast_god_unbound", "name": "Beast-God Unbound", "style": "keep", "ruler": "thornmane_avatar",
			"mandates": [], "ai_role": "field", "ai_sacrifices": ["iron_discipline", "blood_frenzy"]},
		{"id": "clan_moot", "name": "Clan Moot", "style": "spend", "ruler": "fang_chieftain",
			"mandates": ["iron_discipline", "blood_frenzy", "sworn_vassals"], "ai_role": "field", "ai_sacrifices": []},
		{"id": "blood_of_the_fang", "name": "Blood of the Fang", "style": "balanced", "ruler": "fang_chieftain",
			"mandates": ["iron_discipline", "drilled_ranks"], "ai_role": "field", "ai_sacrifices": ["blood_frenzy", "veteran_levies"]},
	],
}
