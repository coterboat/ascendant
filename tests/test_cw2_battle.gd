extends "res://tests/test_case.gd"
## CW-2 (#253, design/CANDLEWAKE.md §2.1, §4.1): the Candlewake in battle. A regular of an army that keeps a flame fights at
## flame - 1 attack; Pall takes PALL_HIT off an attack's hit chance inside the clamp; a Gleaner that hit heals SIPHON_HEAL at the
## round's end; a fallen Hundred-Wick flares on the healthiest standing enemies of the front rank; a standing Lamplighter's Toll
## lifts morale for every enemy that has fallen. Every number comes from AutoBattleResolver's constants and the rows, and every
## recorded battle validates and cross-checks (BattleLog). A Crown–Clans battle logs exactly as before (tests/test_cw0_byte_gate.gd).

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
const SEEDS := 24


func _state() -> GameState:
	var errors := []
	var s := GameState.create(41, [CROWN, WAKE], {}, {}, errors)
	assert_eq(errors, [])
	return s


func _army(s: GameState, owner: String, at: String, types: Array, flame: int = -1) -> Army:
	var f := s.find_faction(owner)
	var a := Army.new()
	a.id = s.new_army_id(owner)
	a.owner = owner
	a.location = at
	for type_id in types:
		var ut := TurnResolver.recruitable_type(f, String(type_id))
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			a.units.append(Unit.new(ut, owner))
	a.flame = flame
	return a


## A recorded battle at Thornvale between `wake` (attacking) and `foe`, checked by BattleLog: {"log", "report"}.
func _battle(s: GameState, wake: Army, foe: Army, game_seed: int) -> Dictionary:
	var r := AutoBattleResolver.resolve(wake, foe, s.find_province("thornvale"), SeededRNG.new(game_seed), s, true)
	assert_eq(BattleLog.validate(r.log), [], "seed %d: the log validates" % game_seed)
	assert_eq(BattleLog.cross_check(r.log, r.report), [], "seed %d: the log agrees with the report" % game_seed)
	return r


func _fighter(battle_log: Dictionary, i) -> Dictionary:
	return battle_log.fighters[int(i)]


func test_regulars_fight_at_flame_minus_one_and_nobody_else_does() -> void:
	for flame in [0, 1, 2, 3]:
		var s := _state()
		var wake := _army(s, WAKE, "thornvale", ["wickwardens", "gleaners", "hundred_wick", "lamplighter"], flame)
		var foe := _army(s, CROWN, "thornvale", ["spearmen", "spearmen", "crossbowmen", "knight_captain"])
		var r := _battle(s, wake, foe, 100 + flame)
		assert_true(bool(r.log.get("wick", false)), "the log says it has Wick")
		var seen := 0
		for e in r.log.events:
			if String(e.t) != "attack":
				continue
			var by := _fighter(r.log, e.by)
			if int(by.side) != _side_of(r.log, WAKE):
				continue
			var parts: Dictionary = e.attack.parts
			if String(by.role) == "unit":
				seen += 1
				assert_eq(int(parts.get(AutoBattleResolver.FLAME, 0)), flame - 1, "flame %d: a regular fights at %d" % [flame, flame - 1])
			else:
				assert_false(parts.has(AutoBattleResolver.FLAME), "flame %d: a commander fights without it" % flame)
		assert_true(seen > 0, "flame %d: the regulars attacked" % flame)


func _side_of(battle_log: Dictionary, fid: String) -> int:
	for s in battle_log.sides:
		if String(s.faction) == fid:
			return int(s.index)
	return -1


func test_pall_takes_its_cut_inside_the_clamp() -> void:
	var on_pall := 0
	for game_seed in SEEDS:
		var s := _state()
		var wake := _army(s, WAKE, "thornvale", ["wickwardens", "wickwardens", "wickwardens"], 1)
		var foe := _army(s, CROWN, "thornvale", ["spearmen", "crossbowmen", "knights"])
		var r := _battle(s, wake, foe, 200 + game_seed)
		for e in r.log.events:
			if String(e.t) != "attack":
				continue
			var target := _fighter(r.log, e.to)
			if String(target.trait) == AutoBattleResolver.PALL:
				on_pall += 1
				assert_eq(int(e.get("pall", 0)), -AutoBattleResolver.PALL_HIT, "an attack on Pall logs its cut")
				assert_eq(int(e.chance), AutoBattleResolver.hit_chance(int(e.attack.value), int(e.defense.value), int(e.base_hit) - AutoBattleResolver.PALL_HIT),
					"the cut is inside the clamp")
			else:
				assert_false(e.has("pall"), "no cut on anyone else")
	assert_true(on_pall > 0, "Pall was attacked")


func test_a_gleaner_that_hit_siphons_at_the_round_end() -> void:
	var siphoned := 0
	for game_seed in SEEDS:
		var s := _state()
		var wake := _army(s, WAKE, "thornvale", ["gleaners", "gleaners", "gleaners", "wickwardens"], 1)
		var foe := _army(s, CROWN, "thornvale", ["spearmen", "spearmen", "crossbowmen"])
		var r := _battle(s, wake, foe, 300 + game_seed)
		var hit_this_round := {}
		for e in r.log.events:
			match String(e.t):
				"round":
					hit_this_round = {}
				"attack":
					if bool(e.hit):
						hit_this_round[int(e.by)] = true
				"heal":
					if String(e.get("trait", "")) == AutoBattleResolver.SIPHON:
						siphoned += 1
						assert_true(hit_this_round.has(int(e.f)), "a Gleaner siphons only after a round it hit")
						assert_eq(int(e.to), mini(int(_fighter(r.log, e.f).max_hp), int(e.from) + AutoBattleResolver.SIPHON_HEAL))
	assert_true(siphoned > 0, "the Gleaners siphoned")


func test_a_fallen_hundred_wick_flares_on_the_healthiest_front_rank_enemies() -> void:
	var flares := 0
	for game_seed in SEEDS:
		var s := _state()
		var wake := _army(s, WAKE, "thornvale", ["hundred_wick"], 0)
		var foe := _army(s, CROWN, "thornvale", ["knights", "knights", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
			"crossbowmen", "knight_captain"])
		var r := _battle(s, wake, foe, 400 + game_seed)
		var tl := BattleTimeline.build(r.log)
		var events: Array = r.log.events
		for i in events.size():
			var e: Dictionary = events[i]
			if String(e.t) != "flare":
				continue
			flares += 1
			assert_eq(String(_fighter(r.log, e.f).trait), AutoBattleResolver.FLARE)
			assert_eq(int(e.damage), AutoBattleResolver.FLARE_DAMAGE)
			var before := tl.state_at(i)
			var standing := []
			for j in r.log.fighters.size():
				var fs: Dictionary = before.fighters[j]
				if fs.alive and not fs.fled and int(r.log.fighters[j].side) != int(_fighter(r.log, e.f).side) and int(r.log.fighters[j].tier) == 0:
					standing.append(j)
			standing.sort_custom(func(a, b): return int(before.fighters[a].hp) > int(before.fighters[b].hp) \
				or (int(before.fighters[a].hp) == int(before.fighters[b].hp) and a < b))
			assert_eq(Array(e.targets).map(func(x): return int(x)), standing.slice(0, AutoBattleResolver.FLARE_TARGETS),
				"the healthiest standing front-rank enemies, at most %d" % AutoBattleResolver.FLARE_TARGETS)
			for x in e.targets:
				assert_false(int(r.log.fighters[int(x)].tier) == 2, "never a commander behind the line")
	assert_true(flares > 0, "the Hundred-Wick fell and flared")


func test_toll_lifts_morale_for_each_fallen_enemy_while_the_lamplighter_stands() -> void:
	var tolled := 0
	for game_seed in SEEDS:
		var s := _state()
		var wake := _army(s, WAKE, "thornvale", ["wickwardens", "wickwardens", "gleaners", "lamplighter"], 2)
		var foe := _army(s, CROWN, "thornvale", ["spearmen", "spearmen", "crossbowmen"])
		var r := _battle(s, wake, foe, 500 + game_seed)
		var mine := _side_of(r.log, WAKE)
		var fallen := 0
		for e in r.log.events:
			match String(e.t):
				"death":
					if int(_fighter(r.log, e.f).side) != mine:
						fallen += 1
				"morale":
					if int(e.side) == mine:
						var parts: Dictionary = e.parts
						if parts.has(AutoBattleResolver.TOLL):
							tolled += 1
							assert_eq(int(parts[AutoBattleResolver.TOLL]), mini(AutoBattleResolver.TOLL_MAX, AutoBattleResolver.TOLL_MORALE * fallen),
								"Toll counts the enemies fallen so far, up to its cap")
	assert_true(tolled > 0, "Toll lifted morale")


func test_crown_clans_battles_log_no_wick() -> void:
	var s := GameState.new(5)
	var a := _army(s, CROWN, "thornvale", ["spearmen", "knights"])
	var d := _army(s, CLANS, "thornvale", ["tuskers", "war_bear"])
	var r := AutoBattleResolver.resolve(a, d, s.find_province("thornvale"), SeededRNG.new(3), s, true)
	assert_false(r.log.has("wick"), "a battle without a flame or a Candlewake trait logs as before")
	for e in r.log.events:
		assert_ne(String(e.t), "flare")
		assert_false(e.has("pall"))
