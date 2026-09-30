class_name MapData
## Hand-authored map for M1. ~14 provinces, three terrains, symmetric neighbors, incomes.
## Referenced by GameState. Data-driven, no assets loaded here.
## Layout mirrors across the center so the hotseat start is fair. Each capital has 3 neighbors:
##   crownkeep -> westwatch / highcrag / rivermarch   mirrors   fangridge -> ebonpeak / ironspike / bloodfen
##   westwatch -> stonegate  <-> blackwood <- ebonpeak     (northern road)
##   highcrag  -> thornvale  <-> wildmoor  <- ironspike    (central road)
##   rivermarch -> greenglade <-> deepwood <- bloodfen     (southern road)
## thornvale and wildmoor are the center hubs and also touch their side's other two roads.
## Every capital-to-capital path is 5 moves long.

const PROVINCES: Array[Dictionary] = [
	# id, name, terrain (plains/forest/hills), income, neighbors (ids), is_capital, has_fort
	{"id": "crownkeep", "name": "Crownkeep", "terrain": "plains", "income": 12, "neighbors": ["westwatch", "highcrag", "rivermarch"], "is_capital": true, "has_fort": true},
	{"id": "westwatch", "name": "Westwatch", "terrain": "hills", "income": 6, "neighbors": ["crownkeep", "stonegate"], "is_capital": false, "has_fort": false},
	{"id": "stonegate", "name": "Stonegate", "terrain": "hills", "income": 8, "neighbors": ["westwatch", "thornvale", "blackwood"], "is_capital": false, "has_fort": true},
	{"id": "highcrag", "name": "Highcrag", "terrain": "hills", "income": 5, "neighbors": ["crownkeep", "thornvale"], "is_capital": false, "has_fort": false},
	{"id": "rivermarch", "name": "Rivermarch", "terrain": "plains", "income": 9, "neighbors": ["crownkeep", "greenglade"], "is_capital": false, "has_fort": false},
	{"id": "greenglade", "name": "Greenglade", "terrain": "forest", "income": 7, "neighbors": ["rivermarch", "thornvale", "deepwood"], "is_capital": false, "has_fort": false},
	{"id": "thornvale", "name": "Thornvale", "terrain": "forest", "income": 6, "neighbors": ["highcrag", "stonegate", "greenglade", "wildmoor"], "is_capital": false, "has_fort": false},
	{"id": "deepwood", "name": "Deepwood", "terrain": "forest", "income": 5, "neighbors": ["bloodfen", "wildmoor", "greenglade"], "is_capital": false, "has_fort": false},
	{"id": "wildmoor", "name": "Wildmoor", "terrain": "forest", "income": 4, "neighbors": ["ironspike", "blackwood", "deepwood", "thornvale"], "is_capital": false, "has_fort": false},
	{"id": "blackwood", "name": "Blackwood", "terrain": "forest", "income": 7, "neighbors": ["ebonpeak", "wildmoor", "stonegate"], "is_capital": false, "has_fort": false},
	{"id": "ebonpeak", "name": "Ebonpeak", "terrain": "hills", "income": 6, "neighbors": ["fangridge", "blackwood"], "is_capital": false, "has_fort": true},
	{"id": "ironspike", "name": "Ironspike", "terrain": "hills", "income": 8, "neighbors": ["fangridge", "wildmoor"], "is_capital": false, "has_fort": false},
	{"id": "bloodfen", "name": "Bloodfen", "terrain": "plains", "income": 5, "neighbors": ["fangridge", "deepwood"], "is_capital": false, "has_fort": false},
	{"id": "fangridge", "name": "Fangridge", "terrain": "hills", "income": 7, "neighbors": ["ebonpeak", "ironspike", "bloodfen"], "is_capital": true, "has_fort": true},  # beasts capital
]

static func create_provinces() -> Array[Province]:
	var provinces: Array[Province] = []
	for p in PROVINCES:
		var province := Province.new()
		province.id = p.id
		province.name = p.name
		province.terrain = p.terrain
		province.income = p.income
		province.neighbors = p.neighbors.duplicate()
		province.is_capital = p.is_capital
		province.has_fort = p.has_fort
		provinces.append(province)
	return provinces

static func get_terrain_description(terrain: String) -> String:
	match terrain:
		"plains": return "Open grassland. Good for movement and farming."
		"forest": return "Dense woodland. Provides ambush cover but slows heavy units."
		"hills": return "Rugged high ground. Defensive bonus, harder to traverse."
		_: return "Unknown terrain."
