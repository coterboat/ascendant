extends "res://tests/test_case.gd"
## M5-1 (#112) acceptance, the fog rules (design/M5_MAGIC_FOG.md §2.3, §2.4, §2.7, §18):
## - sight levels and sources on constructed boards, and §2.3's start, with the counts derived by breadth-first search
##   from MapData;
## - round_count for every n from 0 to 200, its ranges checked against brute force;
## - sharing out: it sums to the shown total, everyone present gets at least 1, ties go in roster order;
## - stand-ins have the fixed shape;
## - setup_fog, and the Fog of war box on the new game screen.

const CROWN := "kingdom"
const CLANS := "beasts"


## Provinces at most `max_range` steps from `from`, by breadth-first search over MapData's neighbour lists alone.
func _bfs(from: String, max_range: int) -> Dictionary:
	var nbrs := {}
	for p in MapData.PROVINCES:
		nbrs[p.id] = p.neighbors
	var out := {from: 0}
	var frontier := [from]
	for d in range(1, max_range + 1):
		var next := []
		for pid in frontier:
			for n in nbrs[pid]:
				if not out.has(n):
					out[n] = d
					next.append(n)
		frontier = next
	return out


func _capital(fid: String) -> String:
	for f in FactionData.FACTIONS:
		if f.id == fid:
			return f.capital
	return ""


func _army_of(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid and a.ruler == null:
			return a
	return null


func _scout_range() -> int:
	return int(FogData.SIGHT.scout)


# --- sight (§2.3) ----------------------------------------------------------------------------------

func test_the_start_glimpses_the_rivals_border_not_its_heart() -> void:
	for s in [GameState.new(3), GameState.with_rulers(3), GameState.with_paths(3), GameState.with_sieges(3)]:
		for fid in [CROWN, CLANS]:
			var home := _capital(fid)
			# The capital's fort and the starting army (Knights or Fangthrowers, and a commander) both see 2.
			var reach := _bfs(home, maxi(int(FogData.SIGHT.fort), _scout_range()))
			var sight := FogRules.sight(s, fid)
			var counts := {"clear": 0, "glimpse": 0, "veiled": 0}
			for pid in sight:
				var want := "clear" if pid == home else ("glimpse" if reach.has(pid) else "veiled")
				assert_eq(sight[pid], want, "%s sees %s" % [fid, pid])
				counts[sight[pid]] += 1
			assert_eq(counts.clear, 1, "only its capital is in clear sight")
			assert_eq(counts.glimpse, reach.size() - 1, "everything within 2 of it is glimpsed")
			assert_eq(counts.veiled, MapData.PROVINCES.size() - reach.size(), "the rest is out of sight")
			assert_eq(sight[_capital(_rival(fid))], "veiled", "the rival's capital is out of sight")
	# §2.3's example, as words: the Crown glimpses Westwatch, Highcrag, Rivermarch, Stonegate, Thornvale and Greenglade.
	var crown := FogRules.sight(GameState.new(3), CROWN)
	var glimpsed := []
	for pid in crown:
		if crown[pid] == "glimpse":
			glimpsed.append(pid)
	assert_eq(glimpsed, ["greenglade", "highcrag", "rivermarch", "stonegate", "thornvale", "westwatch"])


func _rival(fid: String) -> String:
	return CLANS if fid == CROWN else CROWN


func test_each_source_sees_as_far_as_its_range() -> void:
	# A constructed board: the Crown owns only Crownkeep's neighbour Highcrag, its capital is someone else's, and one
	# army of it stands at Thornvale. Each kind of army source is tried there in turn.
	var s := GameState.new(3)
	for p in s.provinces:
		p.owner = ""
	s.find_province("highcrag").owner = CROWN
	var army := _army_of(s, CROWN)
	army.location = "thornvale"
	var spear: Unit = army.units.filter(func(u): return u.type.id == "spearmen")[0]
	army.units.clear()
	army.units.append(spear)
	army.commander = null
	_army_of(s, CLANS).location = "ebonpeak"
	assert_true(s.validate([]))
	var sight := FogRules.sight(s, CROWN)
	assert_eq(sight.highcrag, "clear", "owned")
	assert_eq(sight.thornvale, "clear", "its army stands there")
	# Range 1 from Highcrag (owned) and from the army at Thornvale (Spearmen only).
	var near := _bfs("highcrag", int(FogData.SIGHT.owned))
	var army_near := _bfs("thornvale", int(FogData.SIGHT.army))
	for pid in sight:
		var want := "clear" if pid in ["highcrag", "thornvale"] else ("glimpse" if near.has(pid) or army_near.has(pid) else "veiled")
		assert_eq(sight[pid], want, "range 1: %s" % pid)
	assert_eq(sight.crownkeep, "glimpse", "next to its land")
	assert_eq(sight.wildmoor, "glimpse", "next to its army")
	assert_eq(sight.blackwood, "veiled", "two away from the army, which sees 1")
	# A scout, a commander or a ruler makes the army see 2.
	for how in ["scout", "commander", "ruler"]:
		var t := s.deep_copy()
		var a := _army_of(t, CROWN)
		match how:
			"scout":
				a.units.append(Unit.new(t.find_faction(CROWN).unit_types.filter(func(ut): return ut.id == "knights")[0], CROWN))
			"commander":
				a.commander = Unit.new(t.find_faction(CROWN).commander_type, CROWN)
		if how == "ruler":
			t = GameState.with_rulers(3)
			for p in t.provinces:
				p.owner = ""
			t.find_province("highcrag").owner = CROWN
			for b in t.armies.duplicate():
				if b.owner == CROWN and b.ruler == null:
					t.armies.erase(b)
			RulerRules.ruler_army(t, CROWN).location = "thornvale"
			RulerRules.ruler_army(t, CLANS).location = "ebonpeak"
			for b in t.armies:
				if b.owner == CLANS:
					b.location = "ebonpeak"
		assert_true(t.validate([]), how)
		var far := _bfs("thornvale", 2)
		var ts := FogRules.sight(t, CROWN)
		for pid in ts:
			var want := "clear" if pid in ["highcrag", "thornvale"] else ("glimpse" if near.has(pid) or far.has(pid) else "veiled")
			assert_eq(ts[pid], want, "%s sees 2: %s" % [how, pid])
		var why := FogRules.sources(t, CROWN, "blackwood")
		assert_eq(why.size(), 1, "%s: one source sees Blackwood" % how)
		assert_eq(why[0].kind, "army")
		assert_eq(int(why[0].distance), 2)
		assert_eq(why[0].why, how)
		assert_true(String(why[0].text).begins_with("Glimpsed from your army at Thornvale"), why[0].text)
		assert_true(String(why[0].text).ends_with("(range 2)."), why[0].text)
	# A fort the Crown owns sees 2, an owned province without one 1.
	var f := s.deep_copy()
	f.find_province("stonegate").owner = CROWN
	var fs := FogRules.sight(f, CROWN)
	for pid in _bfs("stonegate", int(FogData.SIGHT.fort)):
		assert_ne(fs[pid], "veiled", "Stonegate's fort sees %s" % pid)
	var by_fort := FogRules.sources(f, CROWN, "blackwood").filter(func(x): return x.kind == "fort")
	assert_eq(by_fort.size(), 1, "the fort is named as the source")
	assert_eq(by_fort[0].text, "Glimpsed from your fort at Stonegate (range 2).")


func test_sources_say_why_and_the_observer_sees_everything() -> void:
	var s := GameState.new(3)
	assert_eq(FogRules.sources(s, CROWN, "crownkeep")[0].text, "In clear sight: you own it.")
	assert_eq(FogRules.sight_text(s, CROWN, "crownkeep"), "In clear sight: you own it.")
	assert_true(FogRules.sight_text(s, CROWN, "fangridge").begins_with("Out of sight"), "out of sight says so")
	assert_eq(FogRules.sources(s, CROWN, "fangridge"), [])
	for line in FogRules.sources(s, CROWN, "thornvale"):
		assert_true(String(line.text).begins_with("Glimpsed from your"), line.text)
	var all := FogRules.sight(s, FogRules.OBSERVER)
	for pid in all:
		assert_eq(all[pid], "clear", "the observer sees %s" % pid)
	assert_eq(FogRules.OBSERVER, "@observer", "a named constant, never \"\"")


# --- estimates (§2.4) ------------------------------------------------------------------------------

func test_round_count_for_every_n_from_0_to_200_against_brute_force() -> void:
	var shown := {}
	for n in 301:
		shown[n] = FogRules.shown_for(n)
	for n in 201:
		var rc := FogRules.round_count(n)
		assert_eq(rc.keys(), ["shown", "low", "high", "text"], "the round count's shape")
		# Brute force: the smallest and largest true totals (0..300) that show the same number.
		var low := n
		var high := n
		for m in 301:
			if shown[m] == shown[n]:
				low = mini(low, m)
				high = maxi(high, m)
		assert_eq(int(rc.shown), shown[n], "n=%d" % n)
		assert_eq(int(rc.low), low, "n=%d: low" % n)
		assert_eq(int(rc.high), high, "n=%d: high" % n)
		assert_true(low <= n and n <= high, "n=%d lies in its range" % n)
		# The rule itself: 1-2 count as 2, 3-49 to the nearest 5 (at least 5), 50+ to the nearest 10.
		var want: int
		if n == 0:
			want = 0
		elif n <= 2:
			want = 2
		elif n < 50:
			want = maxi(5, 5 * floori((n + 2) / 5.0))
		else:
			want = maxi(10, 10 * floori((n + 5) / 10.0))
		assert_eq(int(rc.shown), want, "n=%d: §2.4's rule" % n)
		var text := "none" if n == 0 else ("1-2" if n <= 2 else "about %d" % want)
		assert_eq(rc.text, text, "n=%d: its words" % n)
	# §2.4's examples.
	for ex in [[5, 3, 7], [15, 13, 17], [50, 48, 54], [60, 55, 64], [2, 1, 2]]:
		var rc := FogRules.round_count(ex[0])
		assert_eq([int(rc.low), int(rc.high)], [ex[1], ex[2]], "about %d is %d-%d" % ex)
	assert_eq(FogRules.exact_count(7), {"shown": 7, "low": 7, "high": 7, "text": "7"}, "clear sight is exact")


func test_sharing_out_sums_to_the_total_gives_everyone_one_and_breaks_ties_in_roster_order() -> void:
	var rng := SeededRNG.new(112)
	for trial in 400:
		var k := rng.randi_range(1, 6)
		var weights := []
		var total := 0
		for i in k:
			var c := rng.randi_range(1, 30)
			weights.append(["t%d" % i, c])
			total += c
		var rc := FogRules.round_count(total)
		var shares := FogRules.share_out(int(rc.shown), weights)
		assert_eq(shares.keys(), weights.map(func(w): return w[0]), "every type present, in roster order")
		var sum := 0
		for key in shares:
			sum += int(shares[key])
			assert_true(int(shares[key]) >= 1, "trial %d: %s gets at least 1" % [trial, key])
		assert_eq(sum, maxi(int(rc.shown), k), "trial %d: the shares sum to the shown total" % trial)
		# Largest remainders: no share is more than one away from its exact share of the total.
		for w in weights:
			var exact := float(maxi(int(rc.shown), k)) * int(w[1]) / total
			assert_true(absf(int(shares[w[0]]) - exact) < 1.0 or int(shares[w[0]]) == 1, "trial %d: %s is a fair share" % [trial, w[0]])
	# Ties go in roster order: two types of 1 shown as 5 give 3 and 2, the first type the larger share.
	assert_eq(FogRules.share_out(5, [["tuskers", 1], ["fangthrowers", 1]]), {"tuskers": 3, "fangthrowers": 2})
	assert_eq(FogRules.share_out(5, [["fangthrowers", 1], ["tuskers", 1]]), {"fangthrowers": 3, "tuskers": 2})
	# §2.4: 3 of each of 5 types (15) shows "about 15 fighters", about 3 of each; many small groups can't hide fighters.
	var five := []
	for i in 5:
		five.append(["t%d" % i, 3])
	assert_eq(FogRules.share_out(15, five).values(), [3, 3, 3, 3, 3])
	var g := FogRules.glimpse_counts([["tuskers", 14], ["fangthrowers", 6]])
	assert_eq(g.total.text, "about 20")
	assert_eq(g.shares, {"tuskers": 14, "fangthrowers": 6})
	assert_eq(int(g.counts.tuskers.shown) + int(g.counts.fangthrowers.shown), 20)
	assert_eq(int(g.counts.tuskers.high) + int(g.counts.fangthrowers.high), int(g.total.high), "the top of the range is shared out too")


# --- stand-ins (§2.7) ------------------------------------------------------------------------------

## A rulers game where the Clans, glimpsed by the Crown at Thornvale, have three armies there (two with a commander)
## and their ruler, and one army in clear sight at Highcrag (which the Crown also holds an army in, so it is a fight
## waiting to happen: a constructed board, not a reachable one).
func _pooled_board() -> GameState:
	var s := GameState.with_rulers(3)
	s.setup_fog([])
	var clans := s.find_faction(CLANS)
	var tusk: UnitType = clans.unit_types[0]
	var fang: UnitType = clans.unit_types[1]
	for a in s.armies.duplicate():
		if a.owner == CLANS:
			s.armies.erase(a)
	var specs := [["thornvale", [tusk, tusk, tusk, fang], true], ["thornvale", [fang, fang], true], ["thornvale", [tusk], false]]
	for sp in specs:
		var a := Army.new()
		a.id = s.new_army_id(CLANS)
		a.owner = CLANS
		a.location = sp[0]
		for ut in sp[1]:
			a.units.append(Unit.new(ut, CLANS))
		if sp[2]:
			a.commander = Unit.new(clans.commander_type, CLANS)
		s.armies.append(a)
	var ruler := Army.new()
	ruler.id = s.new_army_id(CLANS)
	ruler.owner = CLANS
	ruler.location = "thornvale"
	ruler.ruler = Unit.new(clans.ruler_unit_type, CLANS)
	s.armies.append(ruler)
	s.find_province("thornvale").owner = CLANS
	assert_true(s.validate([]), "the constructed board is a valid state")
	return s


func test_stand_ins_have_the_fixed_shape() -> void:
	var s := _pooled_board()
	var view := FogRules.view_state(s, CROWN)
	assert_true(view != null, "the view builds")
	if view == null:
		return
	assert_true(view.is_view and view.view_of == CROWN)
	var ids := []
	for a in view.armies:
		if a.owner == CLANS:
			ids.append(a.id)
	ids.sort()
	assert_eq(ids, ["seen-beasts-thornvale", "seen-beasts-thornvale-c2", "seen-beasts-thornvale-ruler"],
		"one stand-in for the units and the first commander, one per further commander, the ruler alone")
	var main := view.find_army("seen-beasts-thornvale")
	var c2 := view.find_army("seen-beasts-thornvale-c2")
	var ruler := view.find_army("seen-beasts-thornvale-ruler")
	assert_true(main.commander != null and c2.commander != null and c2.units.is_empty(), "each commander has a stand-in")
	assert_true(ruler.ruler != null and ruler.units.is_empty() and ruler.commander == null, "the ruler stands alone")
	# Glimpsed: 7 fighters (4 Tuskers, 3 Fangthrowers) show as about 5, shared 3 and 2, at full hp.
	var note: Dictionary = main.seen
	assert_eq(note.level, "glimpse")
	assert_eq(note.turn, s.current_turn)
	assert_eq(note.total, FogRules.round_count(7))
	var shares := FogRules.share_out(int(note.total.shown), [["tuskers", 4], ["fangthrowers", 3]])
	assert_eq(int(note.counts.tuskers.shown), int(shares.tuskers))
	assert_eq(int(note.counts.fangthrowers.shown), int(shares.fangthrowers))
	assert_eq(main.units.size(), int(note.total.shown), "the stand-in holds the shown total")
	for u in main.units:
		assert_eq(u.current_hp, RulerRules.unit_max_hp(view, u), "glimpsed units are at full hp")
	assert_eq(c2.seen, note, "every stand-in of the pool carries the pool's note")
	assert_eq(ruler.seen.counts, {}, "the ruler's note holds only itself")
	for a in view.armies:
		if not a.seen.is_empty():
			assert_true(a.validate_seen([]), "%s: the note has the fixed shape" % a.id)
	# Clear sight: on a constructed board the Clans' armies stand at Highcrag with a Crown army: exact hp and counts.
	var c := s.deep_copy()
	for a in c.armies:
		if a.owner == CLANS:
			a.location = "highcrag"
			if a.units.size() == 4:
				a.units[0].current_hp = 3
	c.find_province("highcrag").owner = CLANS
	_army_of(c, CROWN).location = "highcrag"
	assert_true(c.validate([]))
	var cv := FogRules.view_state(c, CROWN)
	assert_true(cv != null, "a view with clear sight builds")
	if cv != null:
		var m := cv.find_army("seen-beasts-highcrag")
		assert_eq(m.seen.level, "clear")
		assert_eq(m.seen.total, FogRules.exact_count(7))
		var order := FogRules.type_order(c, CLANS)
		var truth := []
		for a in c.armies:
			if a.owner == CLANS:
				for u in a.units:
					truth.append([u.type.id, u.current_hp])
		truth.sort_custom(func(x, y): return order[x[0]] < order[y[0]] or (order[x[0]] == order[y[0]] and x[1] > y[1]))
		assert_eq(m.units.map(func(u): return [u.type.id, u.current_hp]), truth,
			"exact hp, in roster order and hp from the highest: nothing of the true order survives")
		assert_true(truth.any(func(x): return x[1] == 3), "the wounded Tusker is shown wounded")
		assert_eq(cv.find_army("seen-beasts-highcrag-ruler").ruler.current_hp, RulerRules.ruler_army(c, CLANS).ruler.current_hp)


func test_setup_fog_is_a_lens_on_any_game() -> void:
	for s in [GameState.new(4), GameState.with_rulers(4), GameState.with_paths(4), GameState.with_sieges(4)]:
		var before: Dictionary = s.to_dict()
		assert_true(s.setup_fog([]), "fog works with any game")
		var after: Dictionary = s.to_dict()
		assert_eq(after.get("fog"), true)
		after.erase("fog")
		assert_eq(JSON.stringify(after), JSON.stringify(before), "fog adds its key and nothing else")
	var late := GameState.new(4)
	late.current_turn = 2
	var errors := []
	assert_false(late.setup_fog(errors))
	assert_eq(errors, ["Fog of war is chosen before the game starts."])


func test_the_new_game_screen_has_the_fog_box() -> void:
	var screen := load("res://ui/new_game_screen.tscn").instantiate() as NewGameScreen
	assert_true(screen.fog_toggle != null and screen.fog_toggle.text == "Fog of war")
	assert_true(screen.fog_on(), "on by default (MVP-2)")
	assert_eq(screen.config().get("fog"), true, "so config() asks for fog")
	screen.set_all_systems(false)
	assert_false(screen.config().has("fog"), "no fog key while off")
	screen.set_fog(true)
	assert_eq(screen.config().get("fog"), true, "ticked, config() asks for fog")
	assert_false(screen.paths_on() or screen.sieges_on() or screen.rulers_on(), "it ticks no other box")
	var tip := String(screen.fog_toggle.tooltip_text)
	assert_true(NewGameScreen.fog_tooltip().begins_with("You see exactly only where you own land or have an army; next to that, roughly; beyond, only what you saw last. In hotseat, each player sees only their own view."),
		"§1.3's tooltip")
	assert_true(tip.contains(TooltipText.wrap_text(NewGameScreen.fog_tooltip())), "the box shows it")
	assert_false(tip.contains("_"), "no raw ids")
	screen.prefill({"players": ["kingdom", "beasts"], "seed": 5, "fog": true})
	assert_true(screen.fog_on(), "a rematch of a fog game keeps fog")
	screen.prefill({"players": ["kingdom", "beasts"], "seed": 5})
	assert_false(screen.fog_on(), "and of a game without it doesn't")
	# The config starts a fog game on top of whatever the other boxes ask for.
	var start := GameScreen.starting_state({"players": ["kingdom", "beasts"], "seed": 7, "rulers": true, "fog": true})
	assert_true(start.fog and RulerRules.has_rulers(start), "fog on a rulers game")
	assert_false(GameScreen.starting_state({"players": ["kingdom", "beasts"], "seed": 7}).fog, "no fog unless asked")
	screen.free()
