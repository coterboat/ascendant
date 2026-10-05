extends "res://tests/test_case.gd"
## M3c S-4 (#102): sieges on the 3D board (design/M3C_SIEGES.md §10.1, §10.2; world3d/siege_board.gd and the board
## files). Headless: nothing renders, but every fort the board draws, every camp, chevron, scaffold and figure is
## computed exactly as the windowed game computes it.
##   * the board model built from a state matches its levels, damage looks, construction and camp rings, and the
##     board draws exactly that (kits, looks, scaffolds, chevrons, the camp ring, the garrison inside the walls)
##   * playback equals state: applying a turn's events to the board model of the state before gives the board model
##     of the state after, over 5 seeds x 15 autoplayed turns with sieges on and a scripted siege that has every fort
##     event; a played board stands exactly as one built from the state after
##   * the game state is deep-equal before and after a played turn
##   * the board's code never rolls dice or resolves a turn (every file in world3d/)
##   * a covered hotseat screen draws no private scaffold ghost
##   * the beats of §10.2 play in their phases, and the legend, captions and tooltips explain what the land shows
## Expected values come from the data (FortData, SiegeRules, the model table) and the states, never hardcoded.

const GAME_SCENE := "res://ui/game_screen.tscn"
const Playback := preload("res://world3d/playback.gd")
const SiegeBoard := preload("res://world3d/siege_board.gd")
const Models := preload("res://world3d/models.gd")
const Choreo := preload("res://world3d/choreo.gd")
const F := preload("res://tests/siege_fixtures.gd")
const BOARD_SIZE := Vector2(1200, 836)
const CR := "kingdom"
const CL := "beasts"


# --- fixtures -------------------------------------------------------------------------------------

## A board standing `state` with no game screen around it.
func _board_for(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, state.factions[0].id)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


func _free_board(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


func _game_with_board(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return game


## `turns` turns of a game with sieges the real AI plays for both sides, through the real resolver.
func _autoplay(game_seed: int, turns: int, rulers: bool) -> Array:
	var out: Array = []
	var st: GameState = GameState.with_sieges(game_seed, {}, {"rulers": rulers})
	for t in turns:
		var orders := {}
		var seat := 0
		for f in st.factions:
			var rng := SeededRNG.new(game_seed * 7919 + (seat + 1) * 104729 + t * 31)
			orders[f.id] = AIPlayer.new().plan_orders(st, f.id, rng, "normal")
			seat += 1
		var res: Dictionary = TurnResolver.resolve(st, orders, TurnResolver.seed_for_turn(st))
		if res.get("new_state") == null:
			break
		out.append({"before": st, "events": res["events"], "after": res["new_state"]})
		st = res["new_state"]
		var over := false
		for f in st.factions:
			var cap := st.find_province(f.capital)
			if cap == null or cap.owner != f.id:
				over = true
		if over:
			break
	return out


## The scripted siege (real rules, real battles): the Crown besieges Stonegate with 22 troops and 2 Siege Rams to
## the breach and takes it through the breach battle; a Crown raid on Blackwood is beaten by a sally and the siege
## lifts; the Crown raises a palisade at Rivermarch and starts a keep, which a Clans siege halts and, once the
## garrison leaves, razes. Between them, every fort event the board plays.
func _story() -> Array:
	var s: GameState = F.state([
		["k_siege", CR, "westwatch", F.units("spearmen", 22), 2],
		["k_raid", CR, "wildmoor", F.units("spearmen", 5)],
		["k_rm", CR, "rivermarch", F.units("spearmen", 6)],
		["k_home", CR, "crownkeep", F.units("crossbowmen", 4)],
		["b_gar", CL, "stonegate", F.units("tuskers", 8)],
		["b_bw", CL, "blackwood", F.units("tuskers", 10)],
		["b_gg", CL, "greenglade", F.units("tuskers", 12)],
		["b_home", CL, "fangridge", F.units("fangthrowers", 4)],
	], {"westwatch": CR, "wildmoor": CR, "rivermarch": CR, "stonegate": CL, "blackwood": CL, "greenglade": CL})
	F.rich(s, CR)
	F.rich(s, CL)
	var script := [
		{CR: [MoveOrder.new("k_siege", "stonegate"), MoveOrder.new("k_raid", "blackwood"), FortifyOrder.new("rivermarch")]},
		{CL: [SiegeOrder.sally("b_bw")]},
		{},
		{CR: [FortifyOrder.new("rivermarch")]},
		{CL: [MoveOrder.new("b_gg", "rivermarch")]},
		{CR: [MoveOrder.new("k_rm", "crownkeep")]},
	]
	var out: Array = []
	for i in script.size():
		var orders := {CR: [], CL: []}
		for k in script[i].keys():
			orders[k] = script[i][k]
		var res: Dictionary = TurnResolver.resolve(s, orders, 7 + i, AutoBattleResolver.new())
		if res.get("new_state") == null:
			break
		out.append({"before": s, "events": res["events"], "after": res["new_state"]})
		s = res["new_state"]
	return out


func _types(events: Array) -> Dictionary:
	var out := {}
	for e in events:
		out[String(e.get("type", ""))] = true
	return out


func _siege_battle(events: Array, why: String) -> Dictionary:
	for e in events:
		if e.type == "battle" and String(((e.get("numbers", {}) as Dictionary).get("siege", {}) as Dictionary).get("why", "")) == why:
			return e
	return {}


## Plays a turn on `b` to the end (stepping), with the board left standing as played (snap_at_end off).
func _play_out(b: Board3D, turn: Dictionary) -> bool:
	var before: GameState = turn["before"]
	var after: GameState = turn["after"]
	b.stand(before)
	b.map.set_state(after, before.factions[0].id)
	b.armies.snap_at_end = false
	if not b.play_turn(before, turn["events"], after):
		return false
	var guard := 0
	while b.is_playing() and guard < 8000:
		b.armies.step_playback(1.0 / 30.0)
		b.wv.step_fx(1.0 / 30.0)
		guard += 1
	return true


# --- the board model of a state ----------------------------------------------------------------------

func test_the_board_model_of_a_state_has_its_levels_looks_sites_and_camp_rings() -> void:
	var turns := _story()
	assert_true(turns.size() >= 6, "the scripted siege resolves every turn")
	var checked := {"looks": {}, "sites": 0, "sieges": 0}
	for turn in turns:
		var st: GameState = turn["after"]
		var m := SiegeBoard.model_of(st)
		for p in st.provinces:
			if p.fort_level > 0:
				var f: Dictionary = m["forts"][p.id]
				assert_eq(int(f["level"]), p.fort_level, "%s: the level is the state's" % p.id)
				assert_eq(int(f["walls"]), p.walls, "%s: the walls are the state's" % p.id)
				assert_eq(String(f["look"]), SiegeRules.damage_look(p.fort_level, p.walls), "%s: the damage look follows the walls" % p.id)
				assert_eq(String(f["kit"]), p.fort_by, "%s: a built fort wears its builder's kit" % p.id)
				checked["looks"][String(f["look"])] = true
			else:
				assert_false((m["forts"] as Dictionary).has(p.id), "%s has no fort on the board" % p.id)
			assert_eq((m["works"] as Dictionary).has(p.id), not p.works.is_empty(), "%s: a site on the board exactly when the state has one" % p.id)
			if not p.works.is_empty():
				assert_eq(int(m["works"][p.id]["to"]), int(p.works.to), "%s: the site raises the level the state says" % p.id)
				assert_eq(int(m["works"][p.id]["left"]), int(p.works.left), "%s: with the turns of work left" % p.id)
				checked["sites"] += 1
			assert_eq((m["sieges"] as Dictionary).has(p.id), SiegeRules.is_besieged(st, p.id), "%s: a camp ring exactly when the fort is besieged" % p.id)
			if SiegeRules.is_besieged(st, p.id):
				var want: Array = SiegeRules.besiegers(st, p.id).map(func(a): return a.id)
				want.sort()
				assert_eq(m["sieges"][p.id]["camps"], want, "%s: one camp for each besieging army" % p.id)
				assert_eq(m["sieges"][p.id]["besieger"], SiegeRules.besieging_faction(st, p.id), "%s: in the besieger's colours" % p.id)
				checked["sieges"] += 1
	assert_true(checked["looks"].has("intact") and checked["looks"].has("breached"), "the story shows whole and breached walls (%s)" % str(checked["looks"].keys()))
	assert_true(checked["sites"] > 0 and checked["sieges"] > 0, "and sites and sieges")
	## the looks change exactly where the storm defense does (§10.1): one step of WALL_STEP lost per look
	for level in range(1, FortData.MAX_LEVEL + 1):
		var top := SiegeRules.walls_max(level)
		for w in range(0, top + 1):
			var look := SiegeRules.damage_look(level, w)
			var lost: int = SiegeRules.wall_steps(top) - SiegeRules.wall_steps(w)
			var want := "breached" if w == 0 else ("intact" if lost == 0 else ("damaged" if lost == 1 else "battered"))
			assert_eq(look, want, "level %d at walls %d" % [level, w])
			if w > 0 and w < top:
				assert_eq(SiegeRules.damage_look(level, w) != SiegeRules.damage_look(level, w + 1),
					SiegeRules.walls_defense(w) != SiegeRules.walls_defense(w + 1), "level %d: the look changes at %d exactly when the storm defense does" % [level, w])
	## nothing of it in a game without sieges
	assert_true(SiegeBoard.model_of(GameState.new(4242)).is_empty(), "a game without sieges has no forts part")
	assert_false(Playback.model_of(GameState.new(4242)).has("forts"), "and its board model is M3a's")


func test_the_board_draws_the_forts_camps_and_garrisons_of_the_state() -> void:
	var turns := _story()
	var b: Board3D = null
	var saw := {"kinds": {}, "looks": {}, "scaffold": 0, "rings": 0}
	for turn in turns:
		var st: GameState = turn["after"]
		if b == null:
			b = _board_for(st)
		b.map.set_state(st, st.factions[0].id)
		b.stand(st)
		var want := SiegeBoard.board_table(SiegeBoard.model_of(st), b.wv.map_kits())
		var drawn: Dictionary = b.wv.fort_table()
		assert_eq(drawn, want, "turn %d: the board draws every fort's kit, level, look, scaffold and chevrons as the state says" % st.current_turn)
		for pid in drawn.keys():
			var row: Dictionary = drawn[pid]
			var p := st.find_province(pid)
			assert_eq(String(row["kind"]), SiegeBoard.kind_of(p.fort_level), "%s: the kit of its level" % pid)
			if p.fort_level > 0:
				saw["kinds"][row["kind"]] = true
				saw["looks"][row["look"]] = true
			if not p.works.is_empty():
				var turns_needed := int(SiegeRules.level_data(int(p.works.to)).turns)
				assert_true(absf(float(row["scaffold"]["rise"]) - float(turns_needed - int(p.works.left)) / turns_needed) < 0.001,
					"%s: the next level stands as high as the work done (%d of %d)" % [pid, turns_needed - int(p.works.left), turns_needed])
				saw["scaffold"] += 1
		## the camp ring: one camp per besieging army, the garrison inside the walls
		for p in st.provinces:
			var ring: Array = b.armies.ring_of(p.id)
			if not SiegeRules.is_besieged(st, p.id):
				assert_true(ring.is_empty(), "%s: no camp ring without a siege" % p.id)
				continue
			saw["rings"] += 1
			var want_ring: Array = SiegeRules.besiegers(st, p.id).map(func(a): return a.id)
			want_ring.sort()
			assert_eq(ring, want_ring, "%s: every besieging army camps in the ring round the walls" % p.id)
			assert_eq(b.wv.chevrons_at(p.id), SiegeBoard.CHEVRONS, "%s: chevron banners round the walls" % p.id)
			var yard: Dictionary = b.wv.yard_of(p.id, st)
			assert_false(yard.is_empty(), "%s: a besieged fort has a yard" % p.id)
			var centre: Vector2 = yard["centre"]
			var r: float = float(yard["radius"])
			var snap: Dictionary = b.armies.full_snapshot_by_army()
			for a in SiegeRules.owner_armies(st, p.id):
				for fig in snap[a.id]:
					assert_true((fig["pos"] as Vector2).distance_to(centre) < r, "%s: the garrison %s stands inside the walls" % [p.id, a.id])
			for aid in want_ring:
				for fig in snap[aid]:
					assert_true((fig["pos"] as Vector2).distance_to(centre) > r, "%s: the besieger %s camps outside the walls" % [p.id, aid])
			assert_true(b.armies.ring_tents(p.id) >= want_ring.size(), "%s: a tent for every camp" % p.id)
	assert_true(saw["kinds"].has("palisade") and saw["kinds"].has("fort") and saw["kinds"].has("fortress"), "every level's kit drawn (%s)" % str(saw["kinds"].keys()))
	assert_true(saw["looks"].has("breached") and saw["scaffold"] > 0 and saw["rings"] > 0, "breached walls, scaffolds and camp rings drawn")
	_free_board(b)


func test_a_fort_on_the_map_wears_the_nearest_capitals_kit_and_a_built_one_its_builders() -> void:
	var s: GameState = F.state([["k1", CR, "rivermarch", F.units("spearmen", 3)]], {"rivermarch": CR, "greenglade": CL})
	F.set_fort(s, "rivermarch", 1)
	s.find_province("rivermarch").fort_by = CL ## built by the Clans, then taken: it keeps its look
	var b := _board_for(s)
	b.stand(s)
	var kits: Dictionary = b.wv.map_kits()
	var drawn: Dictionary = b.wv.fort_table()
	for p in s.provinces:
		if p.fort_level <= 0:
			continue
		var want := p.fort_by if not p.fort_by.is_empty() else String(kits[p.id])
		assert_eq(String(drawn[p.id]["kit"]), want, "%s wears %s's kit" % [p.id, want])
	for f in s.factions:
		assert_eq(String(kits[f.capital]), f.id, "a capital wears its own faction's kit")
	assert_eq(String(drawn["rivermarch"]["kit"]), CL, "a captured fort keeps its builder's look")
	_free_board(b)


# --- playback equals state ----------------------------------------------------------------------------

func test_playback_equals_state_over_autoplayed_siege_games() -> void:
	var turns := 0
	var fort_beats := 0
	for game_seed in [3, 4242, 90210, 77, 5150]:
		for turn in _autoplay(game_seed, 15, game_seed % 2 == 0):
			var before: GameState = turn["before"]
			var played := Playback.apply_events(Playback.model_of(before), turn["events"])
			var built := Playback.model_of(turn["after"])
			assert_eq(played, built, "seed %d turn %d: the events lead to the state after's board, forts included" % [game_seed, before.current_turn + 1])
			assert_true(built.has("forts") and built.has("inside"), "a siege game's board model has its forts part")
			fort_beats += (Playback.plan(before, turn["events"], turn["after"])["forts"] as Array).size()
			turns += 1
	assert_true(turns >= 60, "checked over many turns (%d)" % turns)
	assert_true(fort_beats > 0, "with fort beats among them (%d)" % fort_beats)


func test_playback_equals_state_through_a_whole_siege() -> void:
	var seen := {}
	for turn in _story():
		var before: GameState = turn["before"]
		var played := Playback.apply_events(Playback.model_of(before), turn["events"])
		assert_eq(played, Playback.model_of(turn["after"]), "turn %d: the events lead to the state after" % (before.current_turn + 1))
		var plan := Playback.plan(before, turn["events"], turn["after"])
		## the fort beats come in report order, each with the report's own line
		var want: Array = []
		for e in turn["events"]:
			if SiegeBoard.FORT_EVENTS.has(String(e.type)):
				want.append(String(e.type))
		assert_eq((plan["forts"] as Array).map(func(fb): return fb["kind"]), want, "turn %d: every fort event is a beat, in report order" % (before.current_turn + 1))
		for fb in plan["forts"]:
			seen[fb["kind"]] = true
			assert_false(String(fb["text"]).is_empty(), "%s: the beat carries its report line" % fb["kind"])
			assert_false(String(fb["label"]).is_empty(), "%s: and its caption" % fb["kind"])
		for bt in plan["battles"]:
			if bt["provinces"][0] in ["stonegate", "blackwood"]:
				assert_false((bt["siege"] as Dictionary).is_empty(), "a battle at a fort carries its siege block")
	for kind in SiegeBoard.FORT_EVENTS:
		assert_true(seen.has(kind), "the scripted siege plays a %s beat" % kind)


func test_a_played_board_stands_as_one_built_from_the_state_after_and_the_states_are_untouched() -> void:
	var played := 0
	var b: Board3D = null
	var turns: Array = _story()
	turns.append_array(_autoplay(77, 12, false))
	for turn in turns:
		var before: GameState = turn["before"]
		var after: GameState = turn["after"]
		if b == null:
			b = _board_for(before)
		var dict_before: Dictionary = before.to_dict()
		var dict_after: Dictionary = after.to_dict()
		if not _play_out(b, turn):
			continue
		played += 1
		assert_false(b.is_playing(), "the playback ends by itself")
		var label := "turn %d" % after.current_turn
		var snap: Dictionary = b.armies.snapshot()
		var forts: Dictionary = b.wv.fort_table()
		var rings := {}
		var tents: int = b.armies.tent_count()
		for p in after.provinces:
			rings[p.id] = b.armies.ring_of(p.id)
		assert_eq(forts, SiegeBoard.board_table(SiegeBoard.model_of(after), b.wv.map_kits()), "%s: the played forts are the state after's" % label)
		b.armies.snap_at_end = true
		b.stand(after)
		assert_eq(snap, b.armies.snapshot(), "%s: every army stands where a board built from the state after puts it" % label)
		assert_eq(forts, b.wv.fort_table(), "%s: every fort, look, scaffold and chevron is the state after's" % label)
		for p in after.provinces:
			assert_eq(rings[p.id], b.armies.ring_of(p.id), "%s: %s's camp ring is the state after's" % [label, p.id])
		assert_eq(tents, b.armies.tent_count(), "%s: the camps are the state after's" % label)
		assert_eq(before.to_dict(), dict_before, "%s: the state before is deep-equal after the playback" % label)
		assert_eq(after.to_dict(), dict_after, "%s: the state after is deep-equal after the playback" % label)
	assert_true(played >= 10, "many turns played out (%d)" % played)
	if b != null:
		_free_board(b)


# --- the beats of §10.2 ------------------------------------------------------------------------------

func test_the_sieges_phase_plays_each_fort_beat_between_battles_and_captures() -> void:
	var turns := _story()
	var b := _board_for(turns[0]["before"])
	var kinds := {}
	for turn in turns:
		var before: GameState = turn["before"]
		var after: GameState = turn["after"]
		b.stand(before)
		b.map.set_state(after, before.factions[0].id)
		assert_true(b.play_turn(before, turn["events"], after), "turn %d plays" % after.current_turn)
		var keys: Array = []
		for ph in b.armies.phases():
			if not keys.has(ph["key"]):
				keys.append(ph["key"])
		var plan := Playback.plan(before, turn["events"], after)
		var sieges_beats: Array = (plan["forts"] as Array).filter(func(fb): return fb["phase"] == "sieges")
		if not sieges_beats.is_empty():
			assert_true(keys.has("sieges"), "turn %d: a Sieges phase plays" % after.current_turn)
			var order: Array = Choreo.PHASES.filter(func(k): return keys.has(k))
			assert_eq(keys, order, "turn %d: the phases play in the report's order (%s)" % [after.current_turn, str(keys)])
			assert_eq(Choreo.caption("sieges"), "Sieges", "under its caption")
		for bt in b.armies.beats():
			kinds[bt["kind"]] = true
		## each fort beat lights up its report line while it plays
		var lines := {}
		while b.is_playing():
			b.armies.step_playback(1.0 / 20.0)
			b.wv.step_fx(1.0 / 20.0)
			var now: Dictionary = b.armies.phase_now()
			if String(now.get("key", "")) == "sieges" and not String(now.get("line", "")).is_empty():
				lines[now["line"]] = true
		for fb in sieges_beats:
			assert_true(lines.has(fb["text"]), "turn %d: the %s beat shows its report line" % [after.current_turn, fb["kind"]])
	for kind in ["siege", "wall_hit", "breach", "siege_over", "repair", "scaffold", "built", "razed"]:
		assert_true(kinds.has(kind), "a %s beat plays somewhere in the siege" % kind)
	_free_board(b)


func test_the_garrison_spills_out_of_the_gate_on_a_sally() -> void:
	var turns := _story()
	var turn: Dictionary = turns[1]
	var sally := _siege_battle(turn["events"], "sally")
	assert_false(sally.is_empty(), "the story's second turn has a sally")
	var b := _board_for(turn["before"])
	b.stand(turn["before"])
	b.map.set_state(turn["after"], CR)
	b.armies.snap_at_end = false
	assert_true(b.play_turn(turn["before"], turn["events"], turn["after"]))
	var pid: String = sally.provinces[0]
	var yard: Dictionary = b.wv.yard_of(pid, turn["before"])
	var gates: Array = yard["gate"]
	var from_inside: Array = sally.numbers.siege.from_inside
	assert_false(from_inside.is_empty(), "armies came out")
	for aid in from_inside:
		var through := 0
		var figs: Array = b.armies.armies[aid]["figs"]
		for f in figs:
			for leg in f.get("legs", []):
				if leg.get("kind", "") == "column" and (leg["way"] as PackedVector2Array).size() >= 2 \
						and (leg["way"][0] as Vector2).distance_to(gates[0]) < 0.5 and (leg["way"][1] as Vector2).distance_to(gates[1]) < 0.5:
					through += 1
		assert_eq(through, figs.size(), "%s: every figure files out through the gate, two abreast" % aid)
	_free_board(b)


func test_recruits_at_a_fort_march_in_through_its_gate() -> void:
	## the Crown recruits at Stonegate (a keep it holds) once it has held it since the start of the previous turn
	var s: GameState = F.state([["k1", CR, "stonegate", F.units("spearmen", 3)]], {"stonegate": CR})
	F.rich(s, CR)
	var types: Array = s.find_faction(CR).unit_types.filter(func(ut): return SiegeRules.may_recruit(2, ut) and not SiegeRules.is_engine(ut) and not ut.is_commander)
	var res: Dictionary = TurnResolver.resolve(s, {CR: [RecruitOrder.new(types[0].id, "stonegate")], CL: []}, 3)
	var after: GameState = res["new_state"]
	var rec: Array = (res["events"] as Array).filter(func(e): return e.type == "recruited")
	assert_eq(rec.size(), 1, "the recruit at the fort is made")
	assert_eq(rec[0].provinces[0], "stonegate", "at Stonegate")
	var b := _board_for(s)
	b.stand(s)
	b.map.set_state(after, CR)
	b.armies.snap_at_end = false
	assert_true(b.play_turn(s, res["events"], after))
	while b.is_playing() and not b.armies._play.get("reformed", false):
		b.armies.step_playback(1.0 / 30.0)
	var gates: Array = b.wv.yard_of("stonegate", after)["gate"]
	var through := 0
	for f in b.armies.armies[rec[0].armies[0]]["figs"]:
		if f.has("in_path"):
			var path: PackedVector2Array = f["in_path"]
			assert_true(path.has(gates[1]), "a recruit comes in by the fort's own gate")
			through += 1
	assert_true(through > 0, "the recruits march in through Stonegate's gate into its yard")
	_free_board(b)


# --- hotseat privacy ------------------------------------------------------------------------------------

func test_a_covered_hotseat_screen_draws_no_private_scaffold_ghost() -> void:
	var game := _game_with_board({"players": [CR, CL], "seed": 4242, "sieges": true})
	var b: Board3D = game.map.board
	var me := game.map.viewing_faction_id
	## turn 1: the first seat marches out of its capital and takes a neighbouring province (the second seat holds)
	var st: GameState = game.map.state
	var cap := st.find_province(st.find_faction(me).capital)
	var march := ""
	for a in st.armies:
		if a.owner == me and a.ruler == null:
			march = a.id
	var to := ""
	for n in cap.neighbors:
		if st.find_province(n).owner.is_empty() and st.find_province(n).fort_level == 0:
			to = n
	assert_eq(game.map.queue_move(march, to), "", "the first seat marches to %s" % to)
	game.end_turn()
	game.handoff._on_ready_pressed()
	game.end_turn()
	game.handoff._on_ready_pressed()
	if b.is_playing():
		b.skip_playback()
	game.close_turn_report() ## the report covers the board too: close it to give orders
	assert_false(game._board_covered(), "nothing covers the board while the first seat gives orders")
	assert_eq(game.map.viewing_faction_id, me, "turn 2: the first seat is at the controls")
	st = game.map.state
	assert_eq(st.find_province(to).owner, me, "and holds %s" % to)
	var target := to
	assert_eq(game.map.queue_fortify(target), "", "a Fortify order is queued")
	assert_eq(b.wv.fortify_ghosts(), [target], "its owner sees the ghost scaffold where the fort will rise")
	game.end_turn()
	assert_true(game.handoff.visible, "the handoff covers the board")
	b._process(1.0 / 60.0) ## a frame passes under the cover (headless, the board isn't in the tree: it isn't live)
	assert_true(b.wv.fortify_ghosts().is_empty(), "the covered screen draws no private scaffold ghost")
	game.handoff._on_ready_pressed()
	assert_ne(game.map.viewing_faction_id, me, "the second seat is at the controls")
	assert_true(b.wv.fortify_ghosts().is_empty(), "and the second seat never sees the first seat's scaffold ghost")
	assert_false(b.plan_of_orders().has("fortify"), "the board's plan is the second seat's own")
	game.free()


# --- the board only reads the game --------------------------------------------------------------------

func test_the_board_code_never_rolls_dice_or_resolves_turns() -> void:
	## every board file: all of world3d/ but the spike preview's own autoplay (scenario.gd plays a real game for the
	## dev preview to show, world3d/README.md; nothing the game loads uses it)
	var files: Array = []
	for f in DirAccess.get_files_at("res://world3d"):
		if String(f).ends_with(".gd") and f != "scenario.gd":
			files.append("res://world3d/" + f)
	assert_true(files.has("res://world3d/siege_board.gd"), "the siege board is checked")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s can be read" % path)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf(", "randi(", "randomize(", "TurnResolver.resolve",
				".end_turn(", ".queue_order(", ".acknowledge_handoff(", "_sieges_phase", "siege_step(", "repair_step(", "works_step("]:
			assert_false(text.contains(banned), "%s never uses %s" % [path, banned])


# --- the model table and explanations ---------------------------------------------------------------

func test_the_model_table_has_every_siege_kind_ready_for_its_model() -> void:
	var rows: Dictionary = Models.table().get("buildings", {})
	for f in FactionData.FACTIONS:
		var fid := String(f.id)
		var kinds: Array = ["palisade", "scaffold", "siege_works", "siege_engine"]
		for level in range(1, FortData.MAX_LEVEL + 1):
			for look in ["damaged", "breached"]:
				var k := SiegeBoard.look_kind(level, look)
				var top := SiegeRules.walls_max(level)
				## a look kind exists for every look the level can show (a palisade is only ever whole or breached)
				var can := false
				for w in range(0, top + 1):
					if SiegeBoard.look_kind(level, SiegeRules.damage_look(level, w)) == k:
						can = true
				if can and not kinds.has(k):
					kinds.append(k)
		for kind in kinds:
			assert_true(rows.has(kind + "." + fid), "the table has %s.%s" % [kind, fid])
			var row: Dictionary = rows.get(kind + "." + fid, {})
			assert_true(row.has("model") and row.has("fallback"), "%s.%s has a model field and a primitive fallback" % [kind, fid])
			assert_true(Models.building_primitive(kind, fid) != null, "%s.%s draws without its model" % [kind, fid])
	assert_true(rows.has("rubble"), "the shared rubble pile has a row")
	assert_eq(Models.problems(), [], "every row's fallback is a Kit piece and every named model is on disk")


func test_the_legend_captions_and_tooltips_explain_the_siege_board() -> void:
	var turns := _story()
	var st: GameState = turns[0]["after"] ## Stonegate besieged, a palisade rising at Rivermarch
	var b := _board_for(st)
	b.stand(st)
	b.overlay.refresh()
	var legend: String = b.overlay.legend_text()
	for words in ["palisade", "keep", "citadel", "scaffold", "camp", "chevron", "siege works", "breach", "gate"]:
		assert_true(legend.to_lower().contains(words), "the legend explains the %s" % words)
	var tip: String = " ".join(b.overlay.province_tooltip("stonegate").split("\n"))
	var said: String = SiegeBoard.describe(st, "stonegate", st.find_faction(CR).faction_name)
	assert_false(said.is_empty(), "the board has something to say at besieged Stonegate")
	assert_true(" ".join(tip.split(" ", false)).contains(" ".join(said.split(" ", false))), "Stonegate's tooltip says what the board shows there")
	assert_true(tip.contains("chevron"), "including the chevrons")
	var site_tip: String = b.overlay.province_tooltip("rivermarch")
	assert_true(site_tip.contains("scaffolding"), "a site's tooltip names the scaffolding")
	assert_true(b.overlay.has_fort_chip("stonegate"), "the plate carries the fort chip with the exact walls")
	for pid in ["stonegate", "blackwood"]:
		assert_eq(b.overlay.has_cut_mark(pid), SiegeRules.is_cut_off(st, pid), "%s: the siege mark beside its gold exactly when it is cut off" % pid)
	assert_true(b.overlay.has_cut_mark("stonegate"), "the story's besieged Stonegate is cut off from its second turn, and its plate says so")
	assert_true(Choreo.CAPTION_HELP.has("sieges") and String(Choreo.CAPTION_HELP["sieges"]).contains("walls"), "the Sieges caption explains itself")
	_free_board(b)
