class_name IndependentData
## The Free Holds (IND-1, #142): the independents who hold every neutral province at the start of a game with
## independents. They answer to no ruler. They are never a player: no seat, no orders, no gold, no income, no
## research, and they never take a province. Each neutral province starts with one garrison army of theirs, and
## taking the province means beating it (an ordinary province battle, the garrison holding the ground). A
## garrison never moves, recruits or heals; a beaten one is gone, and one that wins keeps its wounds.
##
## The garrison follows the land (GARRISONS): the plains raise a Free Company of spears and slings, the hills a
## Hillguard of slingers behind a few spears, and the forests the Wildkin, unaligned beastfolk of the deep woods.
## Richer provinces hold more of them (garrison_size: 3, 4 or 5 units by income), so expanding costs troops and
## which province to take next is a real choice.
##
## Stats follow FactionData's breakpoint rules (odd attack; defense, counting Shield Wall, at 4, 5, 8, 9, 12, 13)
## and sit under the factions' regulars of the same role: a garrison is local levies, not a standing army.
##
## The faction object (faction()) exists so every name, colour and unit-type lookup that goes through
## GameState.find_faction keeps working for a garrison's battles and reports. It is never in GameState.factions,
## so every loop over the players (orders, income, research, rulers, victory, seats) never sees it.

const FACTION_ID := "independents"
const FACTION_NAME := "Free Holds"
## A garrison's army id is this prefix and its province's id ("free-stonegate"): one per neutral province, fixed.
const ARMY_PREFIX := "free-"

## Morale is high on purpose: a hold fights for its own fields and rarely breaks. Tuned on 2026-10-04 (PR for #142,
## 160 battles each) so a starting army takes a small hold for about half a unit, a 4-unit forest hold for about two,
## and the rich plains hold beside each capital only some of the time (Crown 35%, Clans 46%): on turn 1 the choice is
## the sure small fight, the gamble, or waiting a turn to recruit. The hill forts mid-map stay hard (17% / 48%).
const UNIT_TYPES: Array[Dictionary] = [
	{"id": "free_spears", "name": "Free Spears", "hp": 10, "attack": 9, "defense": 7, "morale": 11, "trait": "Shield Wall"},
	{"id": "hill_slingers", "name": "Hill Slingers", "hp": 8, "attack": 11, "defense": 5, "morale": 11, "trait": "Skirmish"},
	{"id": "wildkin", "name": "Wildkin", "hp": 16, "attack": 11, "defense": 4, "morale": 11, "trait": "Berserk"},
]
## A rich hold (income CAPTAIN_FROM and more) is led by a Hold Captain.
## No trait: with Inspire the rich holds were a shut door (a starting army won 12% / 33%).
const COMMANDER := {"id": "hold_captain", "name": "Hold Captain", "hp": 20, "attack": 11, "defense": 8, "morale": 11, "trait": ""}
const CAPTAIN_FROM := 8

## Per terrain: the garrison's name and its units in order; a garrison of n units takes the first n.
const GARRISONS := {
	"plains": {"name": "Free Company", "units": ["free_spears", "hill_slingers", "free_spears", "hill_slingers", "free_spears"]},
	"hills": {"name": "Hillguard", "units": ["hill_slingers", "free_spears", "hill_slingers", "free_spears", "hill_slingers"]},
	"forest": {"name": "Wildkin", "units": ["wildkin", "wildkin", "hill_slingers", "wildkin", "hill_slingers"]},
}

## Income at or above each step adds a unit to the base 3: 3 units up to 6 gold, 4 at 7-8, 5 at 9 and more.
const BASE_SIZE := 3
const MID_FROM := 7  # income from which a hold has BASE_SIZE + 1 units
const RICH_FROM := 9  # income from which it has BASE_SIZE + 2
const SIZE_STEPS := [MID_FROM, RICH_FROM]


## How many units hold a neutral province of this income.
static func garrison_size(income: int) -> int:
	var n := BASE_SIZE
	for step in SIZE_STEPS:
		if income >= step:
			n += 1
	return n


## The unit type ids of the garrison of a province with this terrain and income, in order.
static func garrison_units(terrain: String, income: int) -> Array:
	var row: Dictionary = GARRISONS.get(terrain, GARRISONS.plains)
	return Array(row.units).slice(0, mini(garrison_size(income), row.units.size()))


## "Hillguard": what the garrison of a province with this terrain is called.
static func garrison_kind(terrain: String) -> String:
	return String(GARRISONS.get(terrain, GARRISONS.plains).name)


## The army id of `province_id`'s garrison.
static func army_id(province_id: String) -> String:
	return ARMY_PREFIX + province_id


## True for the id of a faction that is the Free Holds.
static func is_independent(faction_id: String) -> bool:
	return faction_id == FACTION_ID


## True when a neutral province of this income has a Hold Captain leading its garrison.
static func has_captain(income: int) -> bool:
	return income >= CAPTAIN_FROM


## A new Free Holds faction: its name, unit types and the Hold Captain. No gold and no capital.
static func faction() -> Faction:
	var f := Faction.new()
	f.id = FACTION_ID
	f.faction_name = FACTION_NAME
	for u in UNIT_TYPES:
		f.unit_types.append(_unit_type(u))
	f.commander_type = _unit_type(COMMANDER)
	f.commander_type.is_commander = true
	return f


static func _unit_type(u: Dictionary) -> UnitType:
	var ut := UnitType.new()
	ut.id = u.id
	ut.name = u.name
	ut.hp = u.hp
	ut.attack = u.attack
	ut.defense = u.defense
	ut.morale = u.morale
	ut.cost = 0
	ut.trait_id = u.trait
	ut.trait_description = AutoBattleResolver.TRAIT_TEXT.get(u.trait, "")
	return ut
