class_name FactionData
## Data for the factions using exact ids/names from ASSET_MANIFEST.
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
##
## CW-0 (#251, design/CANDLEWAKE.md §1): three factions in the engine, two seats in a game. FACTIONS are the factions that
## ship; PREVIEW_FACTIONS sit behind a preview box (the Candlewake, until CW-11's balance bands pass) and are seated only when
## a config names them. A game holds the factions its players chose (GameState.create), in rows() order whatever the seat
## order, and GameState.new(seed) and the with_* constructors stay the Crown and the Clans (LEGACY_PAIR) byte for byte.
## Capitals are derived from the seated factions (capitals_for): a row with a `capital` keeps it, and a row without one (the
## Candlewake) takes the map's free capital and shows it by its `capital_name` ("the Long Vigil"). A row's optional
## `start_army` names its starting units; without it the start army is one of each unit type. A row's `wick` (CW-1) gives its
## armies a flame (WickRules). Names are bare proper nouns
## ("Candlewake", as "Aurel Crown"): the sentences add "the" ("the Candlewake capital", "the Candlewake's 1st").

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

## CW-0: the factions behind a preview box (design/CANDLEWAKE.md §12: the Candlewake's box, off by default). The Candlewake's
## §4.1 stat lines without their traits: Pall, Siphon, Flare and Toll come with their code and words in CW-2 (#253), with the
## rulers, mandates, presets and the Guttering Ram; their path is CW-4 and their magic CW-5. Ids from the CW-9 manifest.
const PREVIEW_FACTIONS: Array[Dictionary] = [
	{
		"id": "candlewake",
		"name": "Candlewake",
		"gold": 45,
		"capital": "",
		"capital_name": "the Long Vigil",
		"unit_types": [
			{"id": "wickwardens", "name": "Wickwardens", "hp": 7, "attack": 9, "defense": 8, "morale": 8, "cost": 7, "trait": ""},
			{"id": "gleaners", "name": "Gleaners", "hp": 6, "attack": 11, "defense": 4, "morale": 7, "cost": 8, "trait": ""},
			{"id": "hundred_wick", "name": "Hundred-Wick", "hp": 20, "attack": 13, "defense": 5, "morale": 9, "cost": 18, "trait": ""},
		],
		"commander": {"id": "lamplighter", "name": "Lamplighter", "hp": 22, "attack": 11, "defense": 9, "morale": 12, "cost": 30, "trait": ""},
		"start_army": ["wickwardens", "wickwardens", "gleaners", "hundred_wick"],
		# CW-1 (#252, §2.1): every army but a ruler's burns at a flame from 0 to "cap", starting at "start" (WickRules)
		"wick": {"start": 1, "cap": 3},
	},
]

## The two factions the legacy constructors seat (GameState.new and the with_* factories), frozen byte for byte, and the
## pair a config gets when it names no players (GameScreen.default_config).
const LEGACY_PAIR := ["kingdom", "beasts"]
## Players in a game: always two (§1.1, §13: three-player maps are out of scope). GameSession checks it.
const SEATS := 2


## Every faction row, the shipped ones first: the order a game lists its factions in.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(FACTIONS)
	out.append_array(PREVIEW_FACTIONS)
	return out


## The row of `faction_id`, or {}.
static func row(faction_id: String) -> Dictionary:
	for f in rows():
		if String(f.id) == faction_id:
			return f
	return {}


## Every faction id, in rows() order.
static func ids() -> Array:
	return rows().map(func(f): return String(f.id))


static func is_preview(faction_id: String) -> bool:
	return PREVIEW_FACTIONS.any(func(f): return String(f.id) == faction_id)


## The factions a player may seat: the shipped ones, and the preview ones when `preview` is on.
static func playable(preview: bool) -> Array:
	return ids().filter(func(fid): return preview or not is_preview(fid))


## Each faction's capital in a game of `faction_ids` ({faction id: province id}), derived and never stored apart from the
## faction: a row with a `capital` keeps it, whatever the seat order; each row without one takes the first map capital (in
## map order) no other seated faction holds. An id with no row, or one left without a free capital, is not in the result.
static func capitals_for(faction_ids: Array) -> Dictionary:
	var out := {}
	var taken := {}
	for fid in faction_ids:
		var cap := String(row(String(fid)).get("capital", ""))
		if not cap.is_empty():
			out[String(fid)] = cap
			taken[cap] = true
	for fid in faction_ids:
		var r := row(String(fid))
		if r.is_empty() or out.has(String(fid)):
			continue
		for p in MapData.PROVINCES:
			if p.is_capital and not taken.has(String(p.id)):
				out[String(fid)] = String(p.id)
				taken[String(p.id)] = true
				break
	return out


## The Faction objects of `faction_ids` (the legacy pair by default), in rows() order whatever order they are asked in, each
## with its derived capital (capitals_for).
static func create_factions(faction_ids: Array = LEGACY_PAIR) -> Array[Faction]:
	var factions: Array[Faction] = []
	var capitals := capitals_for(faction_ids)
	for f in rows():
		if not faction_ids.has(f.id):
			continue
		var faction := Faction.new()
		faction.id = f.id
		faction.faction_name = f.name
		faction.gold = f.gold
		faction.capital = capitals.get(f.id, String(f.get("capital", "")))

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
