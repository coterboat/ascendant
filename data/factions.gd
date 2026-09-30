class_name FactionData
## Data for the two M1 factions using exact ids/names from ASSET_MANIFEST.
## Unit types and commanders as specified. Each has one distinct trait.
## Portraits and banners referenced but not loaded here.

const FACTIONS: Array[Dictionary] = [
	{
		"id": "kingdom",
		"name": "Aurel Crown",
		"gold": 50,
		"capital": "crownkeep",
		"unit_types": [
			{"id": "spearmen", "name": "Spearmen", "hp": 10, "attack": 6, "defense": 5, "morale": 8, "cost": 8, "trait": "Shield Wall", "trait_desc": "Gains +2 defense when adjacent to friendly units."},
			{"id": "crossbowmen", "name": "Crossbowmen", "hp": 8, "attack": 9, "defense": 3, "morale": 6, "cost": 10, "trait": "Volley", "trait_desc": "Can fire over friendly units without penalty."},
			{"id": "knights", "name": "Knights", "hp": 15, "attack": 12, "defense": 8, "morale": 10, "cost": 20, "trait": "Charge", "trait_desc": "Deals bonus damage on first attack of battle."},
		],
		"commander": {"id": "knight_captain", "name": "Knight Captain", "hp": 25, "attack": 14, "defense": 12, "morale": 12, "cost": 35, "trait": "Inspire", "trait_desc": "Nearby units gain +2 morale."}
	},
	{
		"id": "beasts",
		"name": "Thornmane Clans",
		"gold": 40,
		"capital": "fangridge",
		"unit_types": [
			{"id": "tuskers", "name": "Tuskers", "hp": 14, "attack": 10, "defense": 7, "morale": 7, "cost": 12, "trait": "Berserk", "trait_desc": "Gains attack when damaged."},
			{"id": "fangthrowers", "name": "Fangthrowers", "hp": 9, "attack": 8, "defense": 4, "morale": 9, "cost": 9, "trait": "Skirmish", "trait_desc": "High mobility, ignores some terrain penalties."},
			{"id": "war_bear", "name": "War Bear", "hp": 20, "attack": 15, "defense": 10, "morale": 11, "cost": 25, "trait": "Fury", "trait_desc": "Roars to reduce enemy morale."},
		],
		"commander": {"id": "warchief", "name": "Warchief", "hp": 30, "attack": 16, "defense": 10, "morale": 14, "cost": 40, "trait": "Pack Leader", "trait_desc": "Commands more units effectively."}
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
			ut.trait_description = u.trait_desc
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
		cmd.trait_description = f.commander.trait_desc
		cmd.is_commander = true
		faction.commander_type = cmd
		
		factions.append(faction)
	return factions
