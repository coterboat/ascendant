extends SceneTree
## CW-0 (#251, design/CANDLEWAKE.md §1.2): the generated two-faction audit. It greps data/, rules/, ai/, ui/, world3d/, tools/
## and tests/ for every faction id, capital id and roster unit id (from FactionData's rows, MagicData's mages and summons),
## `size() == 2`, `factions[0]` and `factions[1]`, `FactionData.FACTIONS` and "a|b" pair keys of faction ids, and prints each
## hit with what was done about it: fixed, safe and why, or the ticket that handles it.
##   godot --headless --path . -s tools/faction_audit.gd                 the table, as markdown, on stdout
##   godot --headless --path . -s tools/faction_audit.gd -- --md PATH    the same table written to PATH
##   godot --headless --path . -s tools/faction_audit.gd -- --check      exit 1 when an engine file's hits don't match its mark
## Comment lines are not code and are skipped; a comment after code is part of its line.
##
## A mark is per file: the number of hits it has and what was done about all of them (MARKS). tests/test_faction_audit.gd
## checks the engine's directories (ENGINE_DIRS: data/, rules/, ai/), so a new hit there, or one gone, has to be looked at
## and the mark updated with its reason. Files in the other directories carry marks too, for the report, but the test leaves
## them to their lanes. tests/ is marked as a whole: its games are the Crown and the Clans on purpose. SEMANTIC lists the
## places that assume two factions without naming one, found by reading the code rather than by the grep.

const DIRS := ["data", "rules", "ai", "ui", "world3d", "tools", "tests"]
const ENGINE_DIRS := ["data", "rules", "ai"]
const KIND_NAMES := {"faction": "faction id", "capital": "capital id", "unit": "roster unit id", "two": "size() == 2",
	"index": "factions[0] or [1]", "table": "FactionData.FACTIONS", "pair": "a|b pair key"}

const UI_7 := "lane UI, CW-7 (#258): the screens name and seat three factions"
const UI_8 := "lane UI, CW-8 (#259): the Candlewake's 3D look"
const BATTLES := "lane UI, #265: the battle views draw N sides (they say 'can't be watched yet' for 3 until then)"
const CROWN_CLANS_TOOL := "safe: a Crown–Clans tool, its matrices and bands are the two shipped factions; pair-keyed bands are CW-11 (#262)"
const TESTS := "safe: tests build Crown–Clans games on purpose; the Candlewake's own tests seat them through GameState.create"

## {path: [hits, disposition]}: what was done about every hit in the file.
const MARKS := {
	# --- the engine: tests/test_faction_audit.gd checks these counts ---
	"ai/ai_paths.gd": [6, "safe: the Crown's and the Clans' path plans by preset; the Candlewake's are CW-6 (#257, lane AI), after their path (CW-4)"],
	"data/build_presets.gd": [2, "safe: presets by faction; the Candlewake's three are CW-2 (#253)"],
	"data/factions.gd": [19, "fixed: the faction rows themselves, the Candlewake's behind the preview (PREVIEW_FACTIONS), LEGACY_PAIR, and capitals derived from the seated factions (capitals_for)"],
	"data/fog.gd": [1, "CW-2 (#253): the Gleaners join SCOUTS with the host (§4.1: the Candlewake's scouts)"],
	"data/forts.gd": [2, "safe until CW-2 (#253) adds the Guttering Ram: a faction with no engine row recruits none (SiegeRules.engine_type is null and the computer plans no engines; tests/test_three_factions.gd)"],
	"data/magic.gd": [16, "safe: the Crown's and the Clans' schools, mages, spellbooks and summons by faction; the Candlewake's Wick and Wax are CW-5 (#256). Fixed: the Thornwolves' row says it is a pack (summons from data)"],
	"data/mandates.gd": [10, "safe: mandates by faction; Kindling and Tallow Levy are CW-2 (#253)"],
	"data/map.gd": [8, "safe: the map's two capitals and their neighbours; the Candlewake take whichever is free (FactionData.capitals_for)"],
	"data/paths.gd": [15, "safe: the Crown's and the Clans' paths by faction and unit; the Candlewake's is CW-4 (#255)"],
	"data/rulers.gd": [5, "safe: rulers by faction (one hit is the word 'kingdom' in a ruler's flavour); Half-Death and Mother Tallow are CW-2 (#253)"],
	"rules/army.gd": [1, "safe: a comment's example army id"],
	"rules/auto_battle_resolver.gd": [1, "safe: a border battle's two provinces, not two factions"],
	"rules/battle_captions.gd": [1, "safe: 'both sides' for two routing sides and 'every side' for more: already N-sided"],
	"rules/battle_log.gd": [1, "safe: a hit-chance range [least, most], not factions"],
	"rules/faction.gd": [1, "safe: a comment's example enchantment id"],
	"rules/fog_rules.gd": [11, "safe: an event's own faction list (who acted first, who it was done to second), not the game's factions"],
	"rules/rules_codex.gd": [7, "safe: the Crown's and the Clans' own entries (engines, rulers, units in prose); the Candlewake's come with their mechanics, CW-2 to CW-5"],
	"rules/turn_report_text.gd": [11, "safe: an event's own faction list (who acted first), and 'both' for a two-faction battle with 'all of them' for more"],
	# --- the screens, the board and the tools: in the report for their lanes, not checked by the test ---
	"ui/art.gd": [3, "lane UI, CW-7 (#258): unit names and portraits found by id in FactionData.FACTIONS; the Candlewake's art is CW-10, and these read FactionData.rows() then"],
	"ui/battle/battle_backdrop.gd": [1, "safe: a border's two province names"],
	"ui/battle/battle_host.gd": [1, BATTLES],
	"ui/battle/battle_layout.gd": [1, "lane UI, CW-7 (#258): a roster's rank order from FactionData.FACTIONS; FactionData.rows() has the Candlewake's"],
	"ui/battle/battle_simple_view.gd": [1, BATTLES],
	"ui/chronicle/chronicle_model.gd": [6, "safe: an event's own faction list (who acted first), not the game's"],
	"ui/fort_panel.gd": [1, "safe: 'both of your armies' for two armies"],
	"ui/map_layout.gd": [2, "safe: the 2D map's positions and its west-east mirror, by province"],
	"ui/map_screen.gd": [1, "safe: with no session the map shows the state's first faction (data order), for any pair"],
	"ui/siege_chronicle.gd": [1, "safe: an event's own faction list"],
	"ui/title_screen.gd": [1, UI_7],
	"ui/turn_report_panel.gd": [2, "lane UI, CW-7 (#258): a recruit line's unit found in FactionData.FACTIONS by the event's faction; FactionData.rows() has the Candlewake's"],
	"ui/ui_palette.gd": [1, "safe: seat colours follow the session's or the state's players; with neither it lists the shipped factions"],
	"ui/victory_screen.gd": [1, "safe: a faction's name from FactionData.FACTIONS only without a state; every game has one (lane UI, CW-7 #258, may switch it to FactionData.rows())"],
	"world3d/battle_formation.gd": [3, UI_8 + ": roads home and rosters from FactionData.FACTIONS' capitals; the Candlewake's capital is derived, so read the state's"],
	"world3d/battle_stage.gd": [1, BATTLES],
	"world3d/battle_walls.gd": [7, UI_8 + ": the Crown's and the Clans' wall kits (the Candlewake's fort kit)"],
	"world3d/battle_watch3d.gd": [1, "safe: a window size [w, h]"],
	"world3d/board3d.gd": [1, UI_8 + ": buildings and colour parties baked for the shipped factions"],
	"world3d/board_overlay.gd": [1, "safe: the Free Holds legend's prose"],
	"world3d/kit.gd": [33, UI_8 + ": figure, fort and camp styles by unit and faction"],
	"world3d/scenario.gd": [1, UI_8 + ": every commander not the Crown's is drawn as a Warchief"],
	"world3d/spell_figures.gd": [5, "lane UI, CW-8 (#259) with CW-5: the mages' and summons' figures (the Chandler's Apprentices, the Snuffed)"],
	"world3d/vfx_sheets.gd": [2, "safe: [frames, size] pairs of an effect sheet"],
	"world3d/world_preview.gd": [17, "safe: the map preview's tour of the two map capitals and its Crown–Clans figure row; CW-8 (#259) may add the Candlewake's"],
	"world3d/world_view.gd": [5, UI_8 + ": capitals from FactionData.FACTIONS (the Long Vigil's look); the size() hits are 2D vectors"],
	"tools/autoplay/autoplay.gd": [6, "CW-6 (#257, lane AI): seats the Crown and the Clans; seat the Candlewake through GameState.create for the smoke run"],
	"tools/autoplay/magic_matrix.gd": [20, CROWN_CLANS_TOOL],
	"tools/autoplay/matrix.gd": [13, CROWN_CLANS_TOOL],
	"tools/autoplay/path_matrix.gd": [12, CROWN_CLANS_TOOL],
	"tools/autoplay/siege_matrix.gd": [8, CROWN_CLANS_TOOL],
	"tools/autoplay/simulator.gd": [5, "CW-6 (#257, lane AI): builds Crown–Clans games with the legacy constructors (GameState.create seats any pair); a siege's two owners hold with two seats, the Free Holds never besiege"],
	"tools/balance/balance.gd": [18, CROWN_CLANS_TOOL],
	"tools/balance/matchups.gd": [1, "CW-2 (#253): the micro-benchmarks add the Candlewake's units (§9)"],
	"tools/battle_log/games.gd": [1, "safe: Crown–Clans example games for the battle log"],
	"tools/battle_log/scenarios.gd": [63, "safe: Crown–Clans battle scenarios for the battle log and its tests"],
	"tools/cw0_gate.gd": [2, "safe: CW-0's byte gate is about the Crown and the Clans"],
	"tools/faction_audit.gd": [10, "safe: this audit's own pattern names and marks"],
	"tools/fixtures/sheet.gd": [2, "safe: a Crown–Clans fixture sheet"],
	"tools/replay_fixture.gd": [1, "safe: the M1 to M5 fixtures are Crown–Clans games"],
	"tools/replay_fixture_paths.gd": [1, "safe: the M4 fixtures are Crown–Clans games"],
	"tools/shots/magic_shots.gd": [5, "safe: Crown–Clans magic shots"],
	"tools/shots/model_compare.gd": [1, "safe: the model sheet's Crown–Clans figures"],
	"tools/shots/play_shots.gd": [2, "safe: the play shots' Crown–Clans game; CW-7 (#258) may add a Candlewake walk"],
}

## Places that assume two factions without naming one: [path, where, disposition].
const SEMANTIC := [
	["rules/game_state.gd", "_load_data and place_starting_armies built every faction row", "fixed: GameState.new and the with_* constructors build the Crown and the Clans (FactionData.LEGACY_PAIR) byte for byte; GameState.create seats any two, each start army from its row"],
	["rules/game_session.gd", "_check_players asked only for at least two players", "fixed: exactly two (GameSession.SEATS)"],
	["ui/game_screen.gd", "default_config seated every row of FactionData.FACTIONS; starting_state never read the players", "fixed: the Crown and the Clans by default; starting_state seats the config's players through GameState.create"],
	["ui/new_game_screen.gd", "quick_start_config picked from every row", "fixed: quick_start_factions, the playable factions that play every system Quick start turns on (the dice are as before with the preview off); SEAT_COUNT stays 2"],
	["rules/magic_rules.gd", "Call the Pack's price, size and words asked whether the summon is the Thornwolves", "fixed: summons from data (MagicData.SUMMONS \"pack\"), as are ui/orders_controller.gd and ui/magic_view.gd"],
	["rules/turn_report_text.gd", "faction_short gave a 'the' only to a name of two words or more", "fixed: 'the Candlewake's 1st'"],
	["rules/victory_check.gd", "the draw says both capitals fell (§1.2 listed it)", "safe: a game seats two (GameSession.SEATS), so 'both' is exact"],
	["rules/siege_rules.gd", "besieging_faction is the first other faction there, by id", "safe: with two seats one faction besieges (Free Holds garrisons never leave their province)"],
	["ai/ai_player.gd", "_collect_armies counts every army not its own (nor the Free Holds') as a foe", "safe: two seats, so the foes are the one rival's"],
	["ai/ai_player.gd", "_plan_branch takes its seat from its faction's place in state.factions when it was given none", "safe: a state lists its factions in data order (FactionData.rows), whatever the seat order"],
	["data/forts.gd", "one siege engine per faction", "safe in CW-0: the Candlewake recruit none until the Guttering Ram (CW-2, #253)"],
	["ui/battle/battle_simple_view.gd", "the battle views refuse a battle log with other than two sides (also ui/battle/battle_host.gd, world3d/battle_stage.gd)", BATTLES],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var hits := scan()
	var md := report(hits)
	var i := args.find("--md")
	if i >= 0 and i + 1 < args.size():
		var f := FileAccess.open(args[i + 1], FileAccess.WRITE)
		f.store_string(md)
		f.close()
	else:
		print(md)
	if args.has("--check"):
		var problems := check(hits)
		for p in problems:
			printerr(p)
		quit(1 if not problems.is_empty() else 0)
		return
	quit(0)


## The ids the audit looks for: {"faction": [...], "capital": [...], "unit": [...]}.
static func ids() -> Dictionary:
	var factions := []
	var capitals := []
	var units := []
	for row in FactionData.rows():
		factions.append(String(row.id))
		if not String(row.get("capital", "")).is_empty():
			capitals.append(String(row.capital))
		for u in row.unit_types:
			units.append(String(u.id))
		units.append(String(row.commander.id))
	for fid in MagicData.MAGES:
		units.append(String(MagicData.MAGES[fid].id))
	for sid in MagicData.SUMMONS:
		units.append(String(sid))
	return {"faction": factions, "capital": capitals, "unit": units}


## The patterns, one RegEx per kind: [{"kind", "regex"}].
static func patterns() -> Array:
	var found := ids()
	var word := func(list: Array) -> String: return "\\b(%s)\\b" % "|".join(list)
	var f: String = "|".join(found.faction)
	var out := []
	for spec in [["faction", word.call(found.faction)], ["capital", word.call(found.capital)], ["unit", word.call(found.unit)],
			["two", "size\\(\\)\\s*[!=]=\\s*2\\b"], ["index", "\\bfactions\\[[01]\\]"], ["table", "FactionData\\.FACTIONS\\b"],
			["pair", "\"(%s)\\|(%s)\"" % [f, f]]]:
		var re := RegEx.new()
		re.compile(spec[1])
		out.append({"kind": spec[0], "regex": re})
	return out


## Every hit in `dirs`: [{"file" (res:// path without the prefix), "line" (1-based), "text" (the line, trimmed), "kinds"}],
## by file and line. A line with several kinds of hit is one hit.
static func scan(dirs: Array = DIRS) -> Array:
	var pats := patterns()
	var out := []
	var files := []
	for d in dirs:
		_collect("res://" + String(d), files)
	files.sort()
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for n in lines.size():
			var text := String(lines[n]).strip_edges()
			if text.is_empty() or text.begins_with("#"):
				continue
			var kinds := []
			for p in pats:
				if (p.regex as RegEx).search(text) != null:
					kinds.append(String(p.kind))
			if not kinds.is_empty():
				out.append({"file": String(path).trim_prefix("res://"), "line": n + 1, "text": text, "kinds": kinds})
	return out


static func _collect(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for sub in da.get_directories():
		if sub.begins_with("."):
			continue
		_collect(dir.path_join(sub), out)
	for name in da.get_files():
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))


## The mark of `file`: [hits, disposition], or [] when it has none. tests/ is marked as a whole.
static func mark_of(file: String) -> Array:
	if MARKS.has(file):
		return MARKS[file]
	if file.begins_with("tests/"):
		return [-1, TESTS]
	return []


## The engine's files whose hits don't match their marks, in plain lines; [] when every one does.
static func check(hits: Array) -> Array:
	var per := {}
	for h in hits:
		if ENGINE_DIRS.has(String(h.file).get_slice("/", 0)):
			per[h.file] = int(per.get(h.file, 0)) + 1
	var problems := []
	for file in per:
		var mark := mark_of(String(file))
		if mark.is_empty():
			problems.append("%s has %d two-faction hits and no mark: fix them for any two of the factions, or add a mark to tools/faction_audit.gd with the reason." % [file, per[file]])
		elif int(mark[0]) != int(per[file]):
			problems.append("%s has %d two-faction hits, but its mark in tools/faction_audit.gd counts %d: look at what changed and update the mark and its reason." % [file, per[file], int(mark[0])])
	for file in MARKS:
		if ENGINE_DIRS.has(String(file).get_slice("/", 0)) and not per.has(file):
			problems.append("%s has a mark in tools/faction_audit.gd but no hits any more: remove the mark." % file)
	problems.sort()
	return problems


## The audit as markdown: a summary by directory, then every file with its disposition and its hits, then SEMANTIC.
static func report(hits: Array) -> String:
	var by_file := {}
	var order := []
	for h in hits:
		if not by_file.has(h.file):
			by_file[h.file] = []
			order.append(h.file)
		by_file[h.file].append(h)
	var lines := ["# The two-faction audit (CW-0, #251)", "",
		"Generated by `tools/faction_audit.gd` from the tree: %d hits in %d files. Each file's disposition says what was done about every hit in it." % [hits.size(), order.size()], ""]
	var dirs := {}
	for file in order:
		var d := String(file).get_slice("/", 0)
		dirs[d] = int(dirs.get(d, 0)) + by_file[file].size()
	lines.append("| directory | hits |")
	lines.append("|---|---|")
	for d in DIRS:
		lines.append("| `%s/` | %d |" % [d, int(dirs.get(d, 0))])
	lines.append("")
	lines.append("## Files")
	for file in order:
		if String(file).begins_with("tests/"):
			continue
		var mark := mark_of(String(file))
		lines.append("")
		lines.append("**`%s`** (%d): %s" % [file, by_file[file].size(), String(mark[1]) if not mark.is_empty() else "NOT MARKED"])
		for h in by_file[file]:
			lines.append("- %d (%s): `%s`" % [int(h.line), ", ".join(h.kinds.map(func(k): return KIND_NAMES[k])), String(h.text).left(140)])
	var test_hits := hits.filter(func(h): return String(h.file).begins_with("tests/"))
	lines.append("")
	lines.append("**`tests/`** (%d hits in %d files): %s" % [test_hits.size(), order.filter(func(f): return String(f).begins_with("tests/")).size(), TESTS])
	lines.append("")
	lines.append("## Assumptions the grep can't see")
	for s in SEMANTIC:
		lines.append("- `%s`, %s: %s" % [s[0], s[1], s[2]])
	return "\n".join(lines) + "\n"
