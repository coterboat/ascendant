extends SceneTree
## CW-0's byte gate (#251, design/CANDLEWAKE.md §1.1): every Crown–Clans game stays byte-identical once the engine takes a
## third faction. This writes tests/fixtures/cw0_legacy_digests.json from the engine as it is, and tests/test_cw0_byte_gate.gd
## compares the engine against it.
##   godot --headless --path . -s tools/cw0_gate.gd -- --record [--turns N]    write the fixture (default 12 turns a game)
##   godot --headless --path . -s tools/cw0_gate.gd                            compare the engine with the fixture
## Record it only on the commit before the change it guards, with FIXTURE_COMMIT set so the note names it:
##   FIXTURE_COMMIT=a40d43e godot --headless --path . -s tools/cw0_gate.gd -- --record
## A change meant to move some old games (#183: a preset's mandates) re-records the file in a commit of its own, keeping the
## first commit and saying why with `--note TEXT` (as tools/replay_fixture.gd does). Every game is played again, so the games the
## change doesn't touch come out byte-identical; the run prints which entries moved, for the PR to list:
##   FIXTURE_COMMIT=a40d43e godot --headless --path . -s tools/cw0_gate.gd -- --record --note "for #183: ..."
##
## One entry per old feature combination (configs()): no system, rulers, rulers and paths, or rulers, paths and magic, each
## with and without forts and sieges, independents and fog of war, in both seat orders, with the builds the new game screen
## gives computer seats (BuildScreen.computer_build), plus balanced presets, preset ids and a Tithe of Blood build. For each:
##   "start"   md5 of the raw JSON of the starting state GameScreen.starting_state builds from the config;
##   "record", "final", "turns"   md5 of the session's record(), of the final state's JSON and, per turn, of the state's and
##             the resolver's events' JSON and of the computer's dice (AISeat.rng_state, so a change in how many draws the
##             computer makes shows the turn it happens, before any order changes), after the computer plays both seats for
##             N turns or until the game ends (AISeat, as watch mode does). "dice" is the dice before the first turn (the
##             build draws).
## legacy_state() is a frozen copy of how GameScreen.starting_state picked a constructor before CW-0, so the test can check the
## legacy constructors too, whatever starting_state does now.

const OUT := "res://tests/fixtures/cw0_legacy_digests.json"
const TURNS := 12
const CROWN := "kingdom"
const CLANS := "beasts"
const LEVEL := "normal"
## The rulers chain: each step needs the ones before it (magic needs paths, paths need rulers).
const CHAINS := ["none", "rulers", "paths", "magic"]
const FIRST_NOTE := "Recorded on next (%s) by tools/cw0_gate.gd for CW-0 (#251), before the engine took a third faction. Do not edit by hand."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var turns := TURNS
	var i := args.find("--turns")
	if i >= 0 and i + 1 < args.size():
		turns = int(args[i + 1])
	if args.has("--record"):
		var commit := OS.get_environment("FIXTURE_COMMIT")
		var note := ""
		var at := args.find("--note")
		if at >= 0 and at + 1 < args.size():
			note = args[at + 1]
		var old := _recorded_games()
		var games := {}
		var t0 := Time.get_ticks_msec()
		for c in configs():
			games[String(c.name)] = entry(c, turns)
			print("%s: start %s, record %s" % [c.name, games[c.name].start, games[c.name].record])
		var first := FIRST_NOTE % (commit if not commit.is_empty() else "commit not given")
		var out := {"note": first if note.is_empty() else "%s Re-recorded: %s Do not edit by hand." % [first.trim_suffix(" Do not edit by hand."), note],
			"turns": turns, "games": games}
		var f := FileAccess.open(OUT, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "\t") + "\n")
		f.close()
		print("cw0_gate: wrote %d games (%d turns each) in %.1f s" % [games.size(), turns, (Time.get_ticks_msec() - t0) / 1000.0])
		if not old.is_empty():
			var moved := moved_entries(old, games)
			print("cw0_gate: %d of %d entries moved from the fixture before: %s" % [moved.size(), games.size(), ", ".join(moved) if not moved.is_empty() else "none"])
		quit(0)
		return
	var problems := check()
	for p in problems:
		printerr(p)
	print("cw0_gate: %s" % ("every game matches the fixture" if problems.is_empty() else "%d mismatches" % problems.size()))
	quit(0 if problems.is_empty() else 1)


## Every old feature combination, as the configs GameScreen.start_game takes: {"name", "players", "seed", "ai", and the
## system keys that are on, and "builds" when the new game screen would give some}.
static func configs() -> Array:
	var out := []
	var n := 0
	for chain in CHAINS:
		for sieges in [false, true]:
			for independents in [false, true]:
				for fog in [false, true]:
					for order in [0, 1]:
						n += 1
						var seats: Array = [CROWN, CLANS] if order == 0 else [CLANS, CROWN]
						var c := _config(seats, 5100 + 37 * n, chain, sieges, independents, fog)
						if chain != "none":
							c["builds"] = _computer_builds(seats, int(c.seed))
						c["name"] = "%s%s%s%s_%s" % [chain, "_sieges" if sieges else "", "_ind" if independents else "",
							"_fog" if fog else "", "crown_first" if order == 0 else "clans_first"]
						out.append(c)
	# The other ways builds arrive: none at all (balanced presets), preset ids, and a mandate of magic held back until magic
	# is on (GameState.with_magic).
	for chain in ["rulers", "paths", "magic"]:
		var c := _config([CROWN, CLANS], 7300 + chain.length(), chain, chain == "paths", false, chain == "magic")
		c["name"] = "%s_balanced_presets" % chain
		out.append(c)
		var p := _config([CLANS, CROWN], 7400 + chain.length(), chain, false, chain != "rulers", false)
		p["builds"] = {CROWN: "regents_court", CLANS: "blood_of_the_fang"}
		p["name"] = "%s_preset_ids" % chain
		out.append(p)
	for sieges in [false, true]:
		var t := _config([CROWN, CLANS], 7500 + (1 if sieges else 0), "magic", sieges, true, true)
		t["builds"] = {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}}
		t["name"] = "magic_tithe%s" % ("_sieges" if sieges else "")
		out.append(t)
	return out


static func _config(seats: Array, game_seed: int, chain: String, sieges: bool, independents: bool, fog: bool) -> Dictionary:
	var c := {"players": seats.duplicate(), "seed": game_seed, "ai": {}}
	for fid in seats:
		c.ai[fid] = LEVEL
	var on := CHAINS.find(chain)
	for k in ["rulers", "paths", "magic"]:
		if on >= CHAINS.find(k):
			c[k] = true
	for pair in [["sieges", sieges], ["independents", independents], ["fog", fog]]:
		if pair[1]:
			c[pair[0]] = true
	return c


## The builds the new game screen gives computer seats (BuildScreen.computer_build: the seat RNG's first draw).
static func _computer_builds(seats: Array, game_seed: int) -> Dictionary:
	var out := {}
	for i in seats.size():
		out[seats[i]] = BuildScreen.computer_build(String(seats[i]), game_seed, i)
	return out


## The systems `config` asks for, as GameState.create takes them: the six keys, each true or false. Builds (even none, as
## an empty "builds") ask for rulers, as GameScreen.starting_state has always read them.
static func flags_of(config: Dictionary) -> Dictionary:
	var out := {}
	for k in ["rulers", "paths", "magic", "sieges", "independents", "fog"]:
		out[k] = bool(config.get(k, false))
	if config.has("builds"):
		out.rulers = true
	return out


## The starting state as GameScreen.starting_state picked its constructor before CW-0 (ui/game_screen.gd at a40d43e), without
## the command-line switches. Frozen: it stays the legacy constructors' path whatever starting_state does now.
static func legacy_state(config: Dictionary) -> GameState:
	var seed_value := int(config.get("seed", 0))
	var state: GameState
	if config.get("magic", false):
		state = GameState.with_magic(seed_value, config.get("builds", {}), [])
		if state != null and config.get("sieges", false):
			state.setup_sieges([])
	elif config.get("sieges", false):
		var paths: bool = config.get("paths", false)
		var rulers: bool = paths or config.get("rulers", false) or config.has("builds")
		state = GameState.with_sieges(seed_value, config.get("builds", {}), {"rulers": rulers, "paths": paths}, [])
	elif config.get("paths", false):
		state = GameState.with_paths(seed_value, config.get("builds", {}), [])
	elif config.get("rulers", false) or config.has("builds"):
		state = GameState.with_rulers(seed_value, config.get("builds", {}), [])
	else:
		state = GameState.new(seed_value)
	if state != null and config.get("independents", false):
		state.setup_independents([])
	if state != null and config.get("fog", false):
		state.setup_fog([])
	return state


## md5 of a starting state's raw JSON ("" for no state).
static func state_digest(state: GameState) -> String:
	return JSON.stringify(state.to_dict()).md5_text() if state != null else ""


## The fixture entry for `config`: its starting state through GameScreen.starting_state, then `turns` turns of the computer
## playing both seats from it.
static func entry(config: Dictionary, turns: int) -> Dictionary:
	var start := GameScreen.starting_state(config)
	var out := {"start": state_digest(start)}
	out.merge(play(start, config, turns))
	return out


## The computer plays both seats of `config` from `start` for `turns` turns (or until the game ends), as watch mode does:
## {"record", "final", "dice", "turns": [{"state", "events", "dice"}], "refused" (orders the session refused: expected none)}.
static func play(start: GameState, config: Dictionary, turns: int) -> Dictionary:
	if start == null:
		return {"record": "", "final": "", "turns": [], "refused": 0}
	var game_seed := int(config.seed)
	var session := GameSession.new(start, config.players, game_seed, AutoBattleResolver.new(), config.ai)
	var computer := AISeat.new(session, game_seed)
	var dice := JSON.stringify(computer.rng_state()).md5_text()
	var per_turn := []
	while not session.is_over() and session.turns_played() < turns:
		var before := session.turns_played()
		computer.play(session)
		if session.turns_played() == before:
			break
		var d := turn_digest(session.state(), session.turn_report().get("events", []))
		d["dice"] = JSON.stringify(computer.rng_state()).md5_text()
		per_turn.append(d)
	return {"record": JSON.stringify(session.record()).md5_text(), "final": state_digest(session.state()), "dice": dice,
		"turns": per_turn, "refused": computer.rejections().size()}


## One resolved turn, as tools/replay_fixture.gd digests it: the state's JSON and the resolver's events (without the victory
## event GameSession adds on the last turn).
static func turn_digest(state: GameState, events: Array) -> Dictionary:
	var resolved := events.filter(func(e): return str(e.get("phase", "")) != "victory")
	return {"state": state_digest(state), "events": JSON.stringify(resolved).md5_text()}


## Compares the engine with the fixture: every starting state through GameScreen.starting_state and the legacy constructors,
## and every played game. Plain lines, one per mismatch; [] when everything matches.
static func check() -> Array:
	var problems := []
	if not FileAccess.file_exists(OUT):
		return ["There is no fixture at %s: record it on the base commit first." % OUT]
	var data = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var games: Dictionary = data.get("games", {}) if data is Dictionary else {}
	var turns := int(data.get("turns", TURNS)) if data is Dictionary else TURNS
	for c in configs():
		var want: Dictionary = games.get(String(c.name), {})
		if want.is_empty():
			problems.append("%s: not in the fixture." % c.name)
			continue
		var got := entry(c, turns)
		var legacy := state_digest(legacy_state(c))
		if String(got.start) != String(want.start):
			problems.append("%s: the starting state's JSON differs from the fixture (GameScreen.starting_state)." % c.name)
		if legacy != String(want.start):
			problems.append("%s: the legacy constructors' starting state differs from the fixture." % c.name)
		for key in ["record", "final", "dice"]:
			if String(got[key]) != String(want[key]):
				problems.append("%s: the played game's %s differs from the fixture (first different turn: %s)." % [c.name, key,
					_first_diff(got.turns, want.get("turns", []))])
		if JSON.stringify(got.turns) != JSON.stringify(want.get("turns", [])):
			problems.append("%s: a turn's state, events or computer's dice differ from the fixture (first: turn %s)." % [c.name,
				_first_diff(got.turns, want.get("turns", []))])
	return problems


## The games of the fixture on disk ({} when there is none), read before a re-record overwrites it.
static func _recorded_games() -> Dictionary:
	if not FileAccess.file_exists(OUT):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	return data.get("games", {}) if data is Dictionary else {}


## The names of the entries of `now` that differ from `before` in any digest (or are new), sorted: what a re-record moved.
## Digests are compared as text, so a number read back from JSON as a float compares equal to the int it was written from.
static func moved_entries(before: Dictionary, now: Dictionary) -> Array:
	var out := []
	for name in now:
		var a: Dictionary = before.get(name, {})
		var b: Dictionary = now[name]
		var same := not a.is_empty() and int(a.get("refused", -1)) == int(b.get("refused", -1)) \
			and JSON.stringify(a.get("turns", [])) == JSON.stringify(b.get("turns", []))
		for key in ["start", "record", "final", "dice"]:
			same = same and String(a.get(key, "")) == String(b.get(key, ""))
		if not same:
			out.append(String(name))
	out.sort()
	return out


static func _first_diff(got: Array, want: Array) -> String:
	for t in maxi(got.size(), want.size()):
		if t >= got.size() or t >= want.size() or JSON.stringify(got[t]) != JSON.stringify(want[t]):
			return str(t + 1)
	return "none"
