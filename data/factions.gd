class_name FactionData
## Data for the two M1 factions using exact ids/names from ASSET_MANIFEST.
## Unit types and commanders as specified. Each has one distinct trait. Its description (the unit
## type's trait_description, shown in tooltips) is AutoBattleResolver.TRAIT_TEXT, built from the same
## constants the battle rules use, so the text players read always matches what the trait does. It is
## filled in by create_factions(), not written here, so the two can't drift apart.
## Stats and costs were tuned in the M1 balance pass (#4): tools/balance/matchups.gd prints the
## win rates they give, and tests/test_balance.gd keeps the starting armies within 40-60%.
## Two rules keep battles from swinging on damage breakpoints (a hit deals ceil(attack / 2) minus
## floor(defense / 4)): attack values are odd, and defense values, counting Spearmen's Shield Wall,
## are a multiple of 4 or one more (4, 5, 8, 9, 12, 13). Then a +2 forest, fort or Shield Wall bonus
## and the hills' +1 change only the hit chance, never a whole damage step, so holding ground is a
## real edge that doesn't decide the battle. The two starting armies cost about the same, and both
## factions start with the same gold.
## Portraits and banners referenced but not loaded here.

const FACTIONS: Array[Dictionary] = [
	{
		"id": "kingdom",
		"name": "Aurel Crown",
		"gold": 45,
		"capital": "crownkeep",
		"unit_types": [
			{"id": "spearmen", "name": "Spearmen", "hp": 8, "attack": 9, "defense": 7, "morale": 6, "cost": 8, "trait": "Shield Wall"},
			{"id": "crossbowmen", "name": "Crossbowmen", "hp": 8, "attack": 11, "defense": 9, "morale": 7, "cost": 10, "trait": "Volley"},
			{"id": "knights", "name": "Knights", "hp": 18, "attack": 11, "defense": 9, "morale": 12, "cost": 20, "trait": "Charge"},
		],
		"commander": {"id": "knight_captain", "name": "Knight Captain", "hp": 26, "attack": 13, "defense": 13, "morale": 12, "cost": 35, "trait": "Inspire"}
	},
	{
		"id": "beasts",
		"name": "Thornmane Clans",
		"gold": 45,
		"capital": "fangridge",
		"unit_types": [
			{"id": "tuskers", "name": "Tuskers", "hp": 14, "attack": 11, "defense": 4, "morale": 7, "cost": 11, "trait": "Berserk"},
			{"id": "fangthrowers", "name": "Fangthrowers", "hp": 8, "attack": 11, "defense": 5, "morale": 7, "cost": 8, "trait": "Skirmish"},
			{"id": "war_bear", "name": "War Bear", "hp": 23, "attack": 13, "defense": 8, "morale": 9, "cost": 22, "trait": "Fury"},
		],
		"commander": {"id": "warchief", "name": "Warchief", "hp": 31, "attack": 15, "defense": 9, "morale": 12, "cost": 35, "trait": "Pack Leader"}
	}
]

static func create_factions() -> Array[Faction]:
	var factions: Array[Faction] = []
	for f in FACTIONS:
		var faction := Faction.new()
		faction.id = f.id
		faction.faction_name = f.name
		faction.gold = f.gold
		faction.capital = f.capital
		
		for u in f.unit_types:
			var ut := UnitType.new()
			ut.id = u.id
			ut.name = u.name
			ut.hp = u.hp
			ut.attack = u.attack
			ut.defense = u.defense
			ut.morale = u.morale
			ut.cost = u.cost
			ut.trait_id = u.trait
			ut.trait_description = AutoBattleResolver.TRAIT_TEXT.get(u.trait, "")
			faction.unit_types.append(ut)
		
		var cmd := UnitType.new()
		cmd.id = f.commander.id
		cmd.name = f.commander.name
		cmd.hp = f.commander.hp
		cmd.attack = f.commander.attack
		cmd.defense = f.commander.defense
		cmd.morale = f.commander.morale
		cmd.cost = f.commander.cost
		cmd.trait_id = f.commander.trait
		cmd.trait_description = AutoBattleResolver.TRAIT_TEXT.get(f.commander.trait, "")
		cmd.is_commander = true
		faction.commander_type = cmd
		
		factions.append(faction)
	return factions
