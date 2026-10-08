class_name MandateData
## The ten M2 mandates (design/M2_RULER.md §2.2-2.3). Proposed by the director, not yet approved by
## Alex: names, costs and effects can change. Same style as data/factions.gd: const dictionaries only;
## RulerRules (rules/ruler_rules.gd) reads them.
##
## Each mandate:
##   id, name, cost   cost in ruler power
##   faction          "" for a shared mandate, otherwise the one faction id that can take it
##   area             what it changes: "battle" | "units" | "economy" | "map"
##   effect           the one-line rule (§2.2) for the build screen, tooltips and the codex
##   codex            its RulesCodex entry
## Effects that are plain numbers live here too, so RulerRules.unit_stats has no numbers of its own:
##   units            added to every regular unit's stats (not commanders, not rulers)
##   recruit_divisor  every recruit, commanders included, costs cost - (cost / divisor, rounded down)
##   base_hit         its side's base hit chance in battle, instead of AutoBattleResolver.BASE_HIT
##   wounded_attack   attack every fighter of its side (units, commanders, the ruler) gets in battle
##                    while below its maximum hit points
##
## The effects are stored and shown in M2-1 (#29); battles (M2-2, #30) and the map and economy
## (M2-4, #32) put them into play. Battles read them through RulerRules.battle_effects and unit_stats.

## A mandate bought by a mid-game sacrifice costs its price plus this (§2.4).
const SACRIFICE_PREMIUM := 1
## Blood Frenzy's attack for every fighter below its maximum hp (§2.3). #131: 3 -> 2. Once the computer judged
## battles fairly (the morale-aware guess), the Clans' Blood Frenzy builds won more than their share; +2 keeps a
## wounded Tusker's damage step (attack 11 + 2 = 13, like 14, deals 7) and only lowers its hit chance.
const BLOOD_FRENZY_ATTACK := 2

## In the build screen's order: the six shared mandates, then each faction's two.
const MANDATES: Array[Dictionary] = [
	{
		"id": "iron_discipline", "name": "Iron Discipline", "faction": "", "cost": 3, "area": "battle",
		"effect": "Your side never breaks (routs) while one of your commanders in that battle stands, except at the end of the last round.",
		"codex": "mandate_iron_discipline",
	},
	{
		"id": "drilled_ranks", "name": "Drilled Ranks", "faction": "", "cost": 2, "area": "battle",
		"effect": "Your fighters' base hit chance is 70% instead of 60%.",
		"codex": "mandate_drilled_ranks",
		"base_hit": 70,
	},
	{
		"id": "veteran_levies", "name": "Veteran Levies", "faction": "", "cost": 3, "area": "units",
		"effect": "Your regular units have +2 maximum hit points.",
		"codex": "mandate_veteran_levies",
		"units": {"hp": 2},
	},
	{
		"id": "heavy_tithes", "name": "Heavy Tithes", "faction": "", "cost": 4, "area": "economy",
		"effect": "Every province you own earns +2 gold per turn.",
		"codex": "mandate_heavy_tithes",
	},
	{
		"id": "muster_grounds", "name": "Muster Grounds", "faction": "", "cost": 4, "area": "economy",
		"effect": "Recruits cost a fifth less: a fifth of the price, rounded down, comes off.",
		"codex": "mandate_muster_grounds",
		"recruit_divisor": 5,
	},
	{
		"id": "sworn_vassals", "name": "Sworn Vassals", "faction": "", "cost": 4, "area": "map",
		"effect": "Each turn, one neutral province next to your land swears fealty and joins you.",
		"codex": "mandate_sworn_vassals",
	},
	{
		"id": "royal_armories", "name": "Royal Armories", "faction": "kingdom", "cost": 3, "area": "units",
		"effect": "Your regular units have +1 attack.",
		"codex": "mandate_royal_armories",
		"units": {"attack": 1},
	},
	{
		"id": "kings_roads", "name": "King's Roads", "faction": "kingdom", "cost": 2, "area": "map",
		"effect": "Armies can move two provinces in one turn inside your own territory.",
		"codex": "mandate_kings_roads",
	},
	{
		"id": "blood_frenzy", "name": "Blood Frenzy", "faction": "beasts", "cost": 3, "area": "battle",
		"effect": "Your fighters below full hit points have +2 attack. A Tusker's Berserk adds to it, for +5.",
		"codex": "mandate_blood_frenzy",
		"wounded_attack": BLOOD_FRENZY_ATTACK,
	},
	{
		"id": "feast_of_victory", "name": "Feast of Victory", "faction": "beasts", "cost": 3, "area": "battle",
		"effect": "After each battle you win, your fighters still standing heal to full hit points.",
		"codex": "mandate_feast_of_victory",
	},
]

## The four mandates a transformation opens (M4, design/M4_ASCENSION.md §4.10, §6; M4-2). Kept apart from
## MANDATES, so the pre-game build list, the presets and every M2 game are exactly as before. They can be
## bought only by mid-game sacrifice (at cost + SACRIFICE_PREMIUM), and only once the faction has become
## `path` (a PathData transformation node id). RulerRules.mandate_data reads both lists.
##   sacrifice_only   true: never in a pre-game build
##   path             the transformation that opens it
## Effect numbers, read by AscensionRules and RulerRules:
##   heal_multiplier  Hallowed Land heals this many times its value (Hymn of Dawn: 3 → 6)
##   fort_income      every province with a fort you own earns this much more gold (Forge Tithe)
##   wild_spreads     the Wild Spreads grows this many provinces a turn instead of one (Deep Roots)
## Red Harvest works in battle's aftermath (AutoBattleResolver, M4-3).
const PATH_MANDATES: Array[Dictionary] = [
	{
		"id": "hymn_of_dawn", "name": "Hymn of Dawn", "faction": "kingdom", "cost": 3, "area": "map",
		"effect": "Hallowed Land heals 6 hit points a turn instead of 3.",
		"codex": "mandate_hymn_of_dawn", "sacrifice_only": true, "path": "crown_celestial_host",
		"heal_multiplier": 2,
	},
	{
		"id": "forge_tithe", "name": "Forge Tithe", "faction": "kingdom", "cost": 3, "area": "economy",
		"effect": "Every province with a fort you own earns +4 gold per turn.",
		"codex": "mandate_forge_tithe", "sacrifice_only": true, "path": "crown_living_iron",
		"fort_income": 4,
	},
	{
		"id": "deep_roots", "name": "Deep Roots", "faction": "beasts", "cost": 3, "area": "map",
		"effect": "The Wild Spreads into two provinces each turn instead of one.",
		"codex": "mandate_deep_roots", "sacrifice_only": true, "path": "beasts_thorn_wild",
		"wild_spreads": 2,
	},
	{
		"id": "red_harvest", "name": "Red Harvest", "faction": "beasts", "cost": 3, "area": "battle",
		"effect": "After each battle you win, you gain 1 gold for every enemy fighter lost in it.",
		"codex": "mandate_red_harvest", "sacrifice_only": true, "path": "beasts_blood_pact",
	},
]

## The mandates of magic (M5, design/M5_MAGIC_FOG.md §7.1; M5-5). Kept apart from MANDATES and PATH_MANDATES, so the
## M2 build screen, the presets and every game without magic are exactly as before: they can be taken only in a game
## with magic (GameState.magic), before the game or by sacrifice. RulerRules.mandate_data reads this list too.
##   magic            true: only in a game with magic
##   excludes         a mandate it can't be held with, either way round, in a build or by sacrifice
##   excludes_why     why, in a few words
const MAGIC_MANDATES: Array[Dictionary] = [
	{
		"id": "tithe_of_blood", "name": "Tithe of Blood", "faction": "beasts", "cost": 3, "area": "economy",
		"effect": "Lets rituals your Shamans cast be paid in hit points instead of gold: 1 hit point a gold, from the regular units in the Shamans' own army, one soldier at a time. You choose gold or blood on each cast. Rituals your ruler casts always cost gold, because a ruler stands alone. Can't be taken with Feast of Victory.",
		"codex": "mandate_tithe_of_blood", "magic": true, "excludes": "feast_of_victory",
		"excludes_why": "blood given is not taken back",
	},
]
