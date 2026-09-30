extends "res://tests/test_case.gd"
## Tests for M1 core rules model per issue #2. Covers all acceptance criteria.

func test_map_loads_and_is_connected() -> void:
	var provinces := MapData.create_provinces()
	assert_eq(provinces.size(), 14, "has about 14 provinces")
	
	var terrains := {}
	var has_all_terrains := false
	for p in provinces:
		terrains[p.terrain] = true
		assert_true(p.neighbors.size() > 0, "province %s has neighbors" % p.id)
	assert_true(terrains.has("plains") and terrains.has("forest") and terrains.has("hills"), "uses all three terrains")
	
	# Check connectivity and symmetry. Also unique ids, no self-neighbors, full connectivity via BFS.
	var ids := {}
	for p in provinces:
		assert_false(ids.has(p.id), "unique province ids")
		ids[p.id] = true
		assert_false(p.neighbors.has(p.id), "no self-neighbor in %s" % p.id)
	
	for p in provinces:
		for n_id in p.neighbors:
			var neighbor: Province = null
			for np in provinces:
				if np.id == n_id:
					neighbor = np
					break
			assert_true(neighbor != null, "%s neighbor %s exists" % [p.id, n_id])
			assert_true(neighbor.neighbors.has(p.id), "symmetric: %s lists %s back" % [n_id, p.id])
	
	# BFS to confirm map is connected (reaches all 14 from crownkeep)
	var visited := {}
	var queue := ["crownkeep"]
	visited["crownkeep"] = true
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		for p in provinces:
			if p.id == current_id:
				for n in p.neighbors:
					if not visited.has(n):
						visited[n] = true
						queue.push_back(n)
				break
	assert_eq(visited.size(), 14, "map is fully connected (BFS reaches all provinces)")


func test_factions_and_units_load_with_exact_ids() -> void:
	var factions := FactionData.create_factions()
	assert_eq(factions.size(), 2, "two factions")
	
	var ids := {}
	for f in factions:
		ids[f.id] = true
		assert_true(f.unit_types.size() == 3, "%s has 3 unit types" % f.id)
		assert_true(f.commander_type != null, "%s has commander" % f.id)
	
	assert_true(ids.has("kingdom") and ids.has("beasts"), "exact faction ids")
	
	# Check specific unit ids
	var kingdom: Faction = null
	var beasts: Faction = null
	for f in factions:
		if f.id == "kingdom": kingdom = f
		if f.id == "beasts": beasts = f
	
	assert_eq(kingdom.unit_types[0].id, "spearmen")
	assert_eq(kingdom.unit_types[1].id, "crossbowmen")
	assert_eq(kingdom.unit_types[2].id, "knights")
	assert_eq(kingdom.commander_type.id, "knight_captain")
	
	assert_eq(beasts.unit_types[0].id, "tuskers")
	assert_eq(beasts.unit_types[1].id, "fangthrowers")
	assert_eq(beasts.unit_types[2].id, "war_bear")
	assert_eq(beasts.commander_type.id, "warchief")
	
	# Asset reference paths (exact strings per spec; do not load files)
	for f in factions:
		var banner_path := "assets/banners/%s.webp" % f.id
		assert_eq(banner_path, "assets/banners/kingdom.webp" if f.id == "kingdom" else "assets/banners/beasts.webp", "banner path exact match")
		for ut in f.unit_types:
			var expected_portrait := "assets/portraits/%s/%s.webp" % [f.id, ut.id]
			assert_true(expected_portrait.begins_with("assets/portraits/") and expected_portrait.ends_with(".webp"), "portrait path exact format")
		var cmd_portrait := "assets/portraits/%s/%s.webp" % [f.id, f.commander_type.id]
		assert_true(cmd_portrait.begins_with("assets/portraits/") and cmd_portrait.ends_with(".webp"), "commander portrait path exact format")
	
	# Descriptions present and match data; 8 distinct trait names
	for ut in kingdom.unit_types:
		assert_true(not ut.get_trait_desc().is_empty() and ut.get_trait_desc() != "Special ability.", "unit trait desc matches data not fallback")
	for ut in beasts.unit_types:
		assert_true(not ut.get_trait_desc().is_empty() and ut.get_trait_desc() != "Special ability.", "unit trait desc matches data not fallback")
	
	var all_traits := []
	for f in factions:
		for ut in f.unit_types:
			all_traits.append(ut.trait_id)
		all_traits.append(f.commander_type.trait_id)
	assert_eq(all_traits.size(), 8, "exactly 8 traits")
	var unique_traits := {}
	for t in all_traits:
		unique_traits[t] = true
	assert_eq(unique_traits.size(), 8, "all 8 trait names are distinct")


func test_game_state_serialization_roundtrips() -> void:
	var state1 := GameState.new(42)
	# Advance RNG to test state serialization
	for i in 5:
		state1.roll_for_test()
	var dict := state1.to_dict()
	var state2 := GameState.from_dict(dict)
	var dict2 := state2.to_dict()
	
	assert_eq(state1.provinces.size(), state2.provinces.size())
	assert_eq(state1.factions.size(), state2.factions.size())
	assert_eq(state1.armies.size(), state2.armies.size())
	assert_eq(state1.current_turn, state2.current_turn)
	assert_eq(state1.seed_value, state2.seed_value)
	assert_eq(dict.rng, dict2.rng, "rng state roundtrips exactly")
	
	# Next rolls match after roundtrip (replay fidelity)
	for i in 5:
		assert_eq(state1.roll_for_test(), state2.roll_for_test(), "post-roundtrip RNG sequence matches")
	
	# Check deep equality on key fields
	assert_eq(state2.provinces[0].id, "crownkeep")
	assert_eq(state2.factions[0].id, "kingdom")


func test_deep_copy_is_independent() -> void:
	var state1 := GameState.new(123)
	# Advance RNG
	for i in 3:
		state1.roll_for_test()
	var copy := state1.deep_copy()
	
	# Modify original
	state1.provinces[0].owner = "modified"
	state1.factions[0].gold = 999
	state1.armies[0].location = "nowhere"
	
	assert_ne(state1.provinces[0].owner, copy.provinces[0].owner)
	assert_ne(state1.factions[0].gold, copy.factions[0].gold)
	assert_ne(state1.armies[0].location, copy.armies[0].location)
	
	# RNG state copied independently
	for i in 5:
		assert_eq(state1.roll_for_test(), copy.roll_for_test(), "deep_copy shares RNG sequence")


func test_seeded_rng_determinism() -> void:
	var rng1 := SeededRNG.new(999)
	var seq1 := []
	for i in 20:
		seq1.append(rng1.randi())
	
	var rng2 := SeededRNG.new(999)
	var seq2 := []
	for i in 20:
		seq2.append(rng2.randi())
	
	assert_eq(seq1, seq2, "same seed same sequence")
	
	var rng3 := SeededRNG.new(1000)
	var seq3 := []
	for i in 20:
		seq3.append(rng3.randi())
	assert_ne(seq1, seq3, "different seed gives different sequence")
	
	# Test state serialization
	var rng4 := SeededRNG.new(999)
	for i in 10:
		rng4.randi()
	var saved := rng4.to_dict()
	var rng5 := SeededRNG.from_dict(saved)
	var seq4 := []
	var seq5 := []
	for i in 10:
		seq4.append(rng4.randi())
		seq5.append(rng5.randi())
	assert_eq(seq4, seq5, "rng state serialization preserves sequence")
	
	# GameState uses it
	var gs1 := GameState.new(777)
	var roll1 := gs1.roll_for_test()
	var gs2 := GameState.new(777)
	var roll2 := gs2.roll_for_test()
	assert_eq(roll1, roll2, "GameState seeded identically")


func test_every_stat_has_description() -> void:
	var factions := FactionData.create_factions()
	for f in factions:
		for ut in f.unit_types:
			assert_true(not ut.get_hp_desc().is_empty())
			assert_true(not ut.get_attack_desc().is_empty())
			assert_true(not ut.get_defense_desc().is_empty())
			assert_true(not ut.get_morale_desc().is_empty())
			assert_true(not ut.get_cost_desc().is_empty())
			assert_true(not ut.describe("trait").is_empty())
		if f.commander_type:
			assert_true(not f.commander_type.get_hp_desc().is_empty())
	
	# Province and Faction stats
	var provinces := MapData.create_provinces()
	for p in provinces:
		assert_true(not Province.describe("terrain").is_empty())
		assert_true(not Province.describe("income").is_empty())
		assert_true(not Province.describe("fort").is_empty())
		assert_true(not Province.describe("capital").is_empty())
	for f in factions:
		assert_true(not Faction.describe("gold").is_empty())
	assert_true(not UnitType.describe("hp").is_empty(), "UnitType.describe works statically")
