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
##
## The effects are stored and shown in M2-1 (#29); battles (M2-2, #30) and the map and economy
## (M2-4, #32) put them into play.

## A mandate bought by a mid-game sacrifice costs its price plus this (§2.4).
const SACRIFICE_PREMIUM := 1

## In the build screen's order: the six shared mandates, then each faction's two.
const MANDATES: Array[Dictionary] = [
	{
		"id": "iron_discipline", "name": "Iron Discipline", "faction": "", "cost": 3, "area": "battle",
		"effect": "Your side never breaks (routs) while one of your commanders in that battle stands.",
		"codex": "mandate_iron_discipline",
	},
	{
		"id": "drilled_ranks", "name": "Drilled Ranks", "faction": "", "cost": 2, "area": "battle",
		"effect": "Your fighters' base hit chance is 70% instead of 60%.",
		"codex": "mandate_drilled_ranks",
	},
	{
		"id": "veteran_levies", "name": "Veteran Levies", "faction": "", "cost": 2, "area": "units",
		"effect": "Your regular units have +2 maximum hit points.",
		"codex": "mandate_veteran_levies",
		"units": {"hp": 2},
	},
	{
		"id": "heavy_tithes", "name": "Heavy Tithes", "faction": "", "cost": 4, "area": "economy",
		"effect": "Every province you own earns +1 gold per turn.",
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
		"id": "royal_armories", "name": "Royal Armories", "faction": "kingdom", "cost": 4, "area": "units",
		"effect": "Your regular units have +1 attack and +1 defense.",
		"codex": "mandate_royal_armories",
		"units": {"attack": 1, "defense": 1},
	},
	{
		"id": "kings_roads", "name": "King's Roads", "faction": "kingdom", "cost": 2, "area": "map",
		"effect": "Armies can move two provinces in one turn inside your own territory.",
		"codex": "mandate_kings_roads",
	},
	{
		"id": "blood_frenzy", "name": "Blood Frenzy", "faction": "beasts", "cost": 3, "area": "battle",
		"effect": "Your fighters below full hit points have +3 attack. A Tusker's Berserk adds to it, for +6.",
		"codex": "mandate_blood_frenzy",
	},
	{
		"id": "feast_of_victory", "name": "Feast of Victory", "faction": "beasts", "cost": 3, "area": "battle",
		"effect": "After each battle you win, your fighters still standing heal to full hit points.",
		"codex": "mandate_feast_of_victory",
	},
]
