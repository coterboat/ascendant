extends "res://tests/test_case.gd"
## UX-7 (#217; design/UX_WAR_TABLE.md §4, the §9 test table): the six map lenses. Headless: nothing renders, so the ground's compositing is
## checked through MapLens.ground_probe (the shader's sums on the CPU, as UX-2's Vision.lit is for the veil); everything else (the lens
## texture, the plates, the legend card, the keys, the picker, both boards) is built exactly as the windowed game builds it.
##   * the lenses: six, in key order, registered with UX-1's LensHost; off at every session start and for each hotseat seat
##   * every lens scale runs in lightness, never hue alone
##   * the four province textures: one width (Vision.WIDTH), exact bytes, in the terrain's province order; a wider map is rejected
##   * compositing per lens against each fog level, with a selection and a move target on: the veil's four looks still read
##   * a fog-leak test for every lens (tests/fog_test_kit.gd): hidden changes change no entry, texture byte, plate value or legend line
##   * Threat is indistinguishable under hidden changes, and counts only what the viewer has seen or remembers
##   * Making's counts, derived from the data
##   * plates show the lens value on both boards; the legend card sits bottom left with the question, the scale and the totals
##   * keys 1-6, the same key, Esc and `; the picker; the ? panel; the codex page; the first-game guide leaves lenses out
##   * no rules change: building and showing every lens leaves the state as it was
## Expected values come from the data and the states, never hardcoded.

const Kit := preload("res://tests/fog_test_kit.gd")
const Vision := preload("res://world3d/vision.gd")
const WorldView := preload("res://world3d/world_view.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const BOARD_SIZE := Vector2(1200, 836)
const ALL := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}, "rulers": true, "paths": true, "sieges": true, "fog": true,
	"magic": true, "independents": true}
const LEVELS := ["clear", "glimpse", "veiled", "never"]


# --- fixtures -------------------------------------------------------------------------------------------

func _game(config: Dictionary = ALL) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


func _game_with_board(config: Dictionary = ALL) -> GameScreen:
	var game := _game(config)
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return game


## A map screen (and, with `board`, the 3D board) standing `view` as `viewer` sees it.
func _map(view: GameState, viewer: String, memory: Dictionary = {}, intel: Dictionary = {}, before: GameState = null, board: bool = false) -> MapScreen:
	var map := load(MAP_SCENE).instantiate() as MapScreen
	map.set_fog(memory, intel, before)
	map.set_state(view, viewer)
	if board:
		var b := Board3D.new()
		map.set_board(b)
		b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		b.size = BOARD_SIZE
		b.build_now()
	return map


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


## What a lens build shows a player, as text: the texture bytes, every plate's text and hover, and the legend.
func _dump(result: Dictionary, ids: Array) -> String:
	var plates := {}
	for pid in result.entries:
		var e: Dictionary = result.entries[pid]
		plates[pid] = [String(e.text), String(e.tooltip), int(e.pips), bool(e.far_sight)]
	return JSON.stringify({"tex": Array(MapLens.texels(result.entries, ids)), "plates": plates, "legend": result.legend}, "", true)


## What the board shows of the active lens: the ground's texture and mode, every plate's chip and hover, and the legend card.
func _board_dump(map: MapScreen) -> String:
	var b: Board3D = map.board
	var chips := {}
	for pid in b.overlay._plates:
		var c: LensChip = b.overlay.lens_chip(String(pid))
		chips[pid] = [c.label.text if c != null else "", c.tooltip_text if c != null else "", b.overlay.plate_tooltip(String(pid))]
	return JSON.stringify({"tex": Array(b.wv.lens_bytes()), "mode": b.wv.lens_mode(), "chips": chips, "legend": map.lens_ui.legend.text(),
		"regions": map.regions.keys().map(func(pid): return map.regions[pid].lens_chip.label.text if map.regions[pid].lens_chip != null else "")}, "", true)


static func _ids(state: GameState) -> Array:
	return state.provinces.map(func(p): return p.id)


# --- the six lenses on the host -------------------------------------------------------------------------

func test_six_lenses_in_key_order_on_the_lens_host_and_off_at_the_start() -> void:
	var game := _game()
	var host := game.map.lens_host
	assert_eq(host.ids(), MapLens.IDS, "Owner, Income, Threat, Magic, Making, Sight")
	assert_eq(MapLens.IDS, ["owner", "income", "threat", "magic", "making", "sight"])
	for i in MapLens.IDS.size():
		var id: String = MapLens.IDS[i]
		assert_eq(host.key_of(id), KEY_1 + i, "%s is key %d" % [id, i + 1])
		assert_eq(MapLens.mode_of(id), i + 1, "and the shader's lens_mode %d" % (i + 1))
		assert_eq(host.title_of(id), MapLens.title_of(id))
		assert_false(String(MapLens.lens(id).question).is_empty(), "%s asks its question" % id)
		assert_true(RulesCodex.ENTRIES.has(String(MapLens.lens(id).codex)), "%s has its codex entry" % id)
	assert_eq(host.active_id(), "", "every session starts with lenses off")
	assert_false(game.map.lens_ui.legend.visible, "no legend with no lens")
	game.free()


func test_a_new_session_and_a_hotseat_seat_start_with_lenses_off() -> void:
	var game := _game()
	game.map.lens_host.activate("income")
	assert_eq(game.map.lens_host.active_id(), "income")
	game.start_game(ALL)
	assert_eq(game.map.lens_host.active_id(), "", "a new game starts with lenses off")
	game.free()
	var hot := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true})
	hot.close_turn_report()
	hot.map.lens_host.activate("owner")
	hot.end_turn()  # seat 1 hands over
	hot.handoff.ready_button.pressed.emit()
	assert_eq(hot.session.current_player(), CLANS)
	assert_eq(hot.map.lens_host.active_id(), "", "the next seat starts with lenses off")
	hot.free()


# --- every scale runs in lightness ----------------------------------------------------------------------

func test_every_lens_scale_runs_in_lightness_not_hue_alone() -> void:
	for pair in [["income", MapLens.INCOME_RAMP, 1], ["threat", MapLens.THREAT_RAMP, -1], ["magic", MapLens.MAGIC_RAMP, 1], ["sight", MapLens.SIGHT_RAMP, 1]]:
		var stops: Array = pair[1]
		var dir: int = pair[2]
		var last := MapLens.luminance(MapLens.ramp(stops, 0.0))
		for k in range(1, 21):
			var l := MapLens.luminance(MapLens.ramp(stops, float(k) / 20.0))
			assert_true((l - last) * dir > 0.0, "%s's ramp runs one way in lightness (step %d: %.3f then %.3f)" % [pair[0], k, last, l])
			last = l
		var span := absf(MapLens.luminance(stops.back()) - MapLens.luminance(stops.front()))
		assert_true(span >= 0.4, "%s's ends are far apart in lightness (%.2f)" % [pair[0], span])
	# Making deepens with its marks, in every seat colour
	for seat in UiPalette.PLAYER_COLORS.size():
		var c: Color = UiPalette.seat_color(seat)
		var prev := 2.0
		for n in range(1, MapLens.MAKING_MAX + 1):
			var tint := c.lerp(Color.WHITE, MapLens.MAKING_PALE * float(MapLens.MAKING_MAX - n))
			assert_true(MapLens.luminance(tint) < prev, "seat %d: %d marks are deeper than %d" % [seat, n, n - 1])
			prev = MapLens.luminance(tint)
	# and on a real map, a bigger value is never drawn the wrong way
	var s := GameState.with_sieges(77, {}, {"paths": true})
	for id in ["income", "threat", "magic", "sight"]:
		var r := MapLens.build(id, s, CROWN)
		var by := []
		for pid in r.entries:
			by.append(r.entries[pid])
		by.sort_custom(func(a, b): return float(a.value) < float(b.value))
		for i in range(1, by.size()):
			if float(by[i].value) > float(by[i - 1].value):
				var d := MapLens.luminance(by[i].tint) - MapLens.luminance(by[i - 1].tint)
				assert_true(d * (-1.0 if id == "threat" else 1.0) > 0.0, "%s: %s over %s is drawn %s" % [id, by[i].text, by[i - 1].text, "darker" if id == "threat" else "lighter"])


# --- the textures -----------------------------------------------------------------------------------------

func test_the_four_province_textures_have_one_width_and_their_exact_bytes_in_province_order() -> void:
	var game := _game_with_board()
	var map := game.map
	var b: Board3D = map.board
	var wv = b.wv
	var ids: Array = wv.terrain.ids
	var w := Vision.WIDTH
	assert_true(ids.size() <= w, "the map fits the width")
	assert_eq(ids, _ids(map.state).filter(func(pid): return ids.has(pid)), "the textures' columns are the provinces in the map's data order")
	for pair in [[wv.owner_img, Image.FORMAT_RGBA8, 1], [wv.mark_img, Image.FORMAT_RGBA8, 1], [wv.vision_img, Image.FORMAT_R8, 1], [wv.lens_img, Image.FORMAT_RGBA8, 2]]:
		var img: Image = pair[0]
		assert_eq(img.get_width(), w, "every province texture is Vision.WIDTH wide")
		assert_eq(img.get_format(), pair[1])
		assert_eq(img.get_height(), pair[2])
	# owner: rgb the owner's colour, a 255 owned, in the terrain's order; the columns past the map stay 0
	var own: PackedByteArray = wv.owner_bytes()
	var seats := map.seat_order()
	for i in w:
		var want := [0, 0, 0, 0]
		if i < ids.size():
			var p := map.state.find_province(String(ids[i]))
			if not p.owner.is_empty():
				var c := UiPalette.owner_color(map.state, p.owner, seats)
				want = [c.r8, c.g8, c.b8, 255]
		assert_eq([own[i * 4], own[i * 4 + 1], own[i * 4 + 2], own[i * 4 + 3]], want, "owner texel %d (%s)" % [i, ids[i] if i < ids.size() else "-"])
	# mark: a selection's army marks its neighbours as move targets (g), in the same order
	var cap := map.state.find_province(map.state.find_faction(CROWN).capital)
	var army: Army = null
	for a in map.state.armies:
		if a.owner == CROWN and a.location == cap.id:
			army = a
	map.select_army(army.id)
	var mk: PackedByteArray = wv.mark_bytes()
	for i in ids.size():
		assert_eq(mk[i * 4 + 1], 255 if cap.neighbors.has(ids[i]) else 0, "mark texel %d's move target (%s)" % [i, ids[i]])
	# vision: Vision.texels of the board's levels
	assert_eq(wv.vision_bytes(), Vision.texels(b.vision_levels, ids), "vision texels")
	# lens: none, then each lens's MapLens.texels, two rows
	assert_eq(wv.lens_bytes(), MapLens.no_texels(), "no lens: an empty lens texture")
	assert_eq(wv.lens_mode(), 0)
	for id in MapLens.IDS:
		map.lens_host.activate(id)
		var r := map.lens_ui.result()
		var bytes: PackedByteArray = wv.lens_bytes()
		assert_eq(bytes, MapLens.texels(r.entries, ids), "%s's texels" % id)
		assert_eq(wv.lens_mode(), MapLens.mode_of(id))
		for i in ids.size():
			var e: Dictionary = r.entries[ids[i]]
			var c: Color = e.tint
			assert_eq([bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2]], [c.r8, c.g8, c.b8], "%s column %d is %s's tint" % [id, i, ids[i]])
			assert_eq(bytes[(w + i) * 4 + 3], 255, "row 1 marks a province with an entry")
		for i in range(ids.size(), w):
			assert_eq(bytes[i * 4 + 3], 0, "a column with no province draws nothing")
	map.lens_host.clear()
	assert_eq(wv.lens_bytes(), MapLens.no_texels(), "off again: the texture is emptied")
	assert_eq(wv.lens_mode(), 0)
	game.free()


func test_a_map_wider_than_the_textures_is_rejected_before_any_texture_is_built() -> void:
	assert_eq(WorldView.width_error(Vision.WIDTH), "", "a map of Vision.WIDTH provinces fits")
	assert_false(WorldView.width_error(Vision.WIDTH + 1).is_empty(), "one more is turned away")
	var wide := _WideTerrain.new()
	for i in Vision.WIDTH + 1:
		wide.ids.append("p%d" % i)
	var wv = WorldView.new()
	wv.setup(wide)
	assert_false(wv.rejected.is_empty(), "rejected: %s" % wv.rejected)
	assert_true(wv.gmat == null and wv.owner_tex == null and wv.mark_tex == null and wv.vision_tex == null and wv.lens_tex == null, "before any texture is built")
	wv.free()
	# the shaders read the width from the texture itself: no second number
	for path in ["res://world3d/shaders/ground_common.gdshaderinc", "res://world3d/shaders/model_common.gdshaderinc"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.contains("+ 0.5) / 16.0"), "%s divides by the texture's width, not a number" % path)
		assert_true(src.contains("textureSize("), path)


class _WideTerrain extends RefCounted:
	var ids: Array = []


# --- compositing: the veil reads under every lens ---------------------------------------------------------

func test_compositing_per_lens_against_each_fog_level_with_a_selection_and_a_move_target() -> void:
	var s := GameState.with_sieges(91, {}, {"paths": true})
	var seats := UiPalette.seat_order(s)
	var bases := [UiPalette.terrain_color("plains"), UiPalette.terrain_color("forest"), UiPalette.terrain_color("hills")]
	for id in MapLens.IDS:
		var r := MapLens.build(id, s, CROWN, seats)
		var samples := []
		for pid in r.entries:
			if float((r.entries[pid] as Dictionary).strength) > 0.0:
				samples.append(r.entries[pid])
		if samples.is_empty():
			samples.append(MapLens.build("income", s, CROWN, seats).entries.values()[0])  # a lens with nothing to show: any tint
		for e in samples.slice(0, 4):
			for base: Color in bases:
				var l := []
				for level in LEVELS:
					l.append(MapLens.luminance(MapLens.ground_probe(id, e, level, base)))
				for k in range(1, l.size()):
					assert_true(l[k - 1] - l[k] >= 0.02 and l[k] <= l[k - 1] * 0.93, "%s: %s reads darker than %s under the lens (%.3f, %.3f)" % [id, LEVELS[k], LEVELS[k - 1], l[k - 1], l[k]])
				var off := MapLens.ground_probe("", {}, "clear", base)
				assert_ne(MapLens.ground_probe(id, e, "clear", base), off, "%s changes the land" % id)
				for level in LEVELS:
					var plain := MapLens.ground_probe(id, e, level, base)
					var sel := MapLens.ground_probe(id, e, level, base, Color(0, 0, 0, 0), {"selected": true})
					assert_true(MapLens.luminance(sel) > MapLens.luminance(plain), "%s, %s: the selection lifts the land over the lens" % [id, level])
					var band := MapLens.ground_probe(id, e, level, base, Color(0, 0, 0, 0), {"band": true})
					assert_true(MapLens.luminance(band) > 0.9, "%s, %s: the selection's band is white over everything" % [id, level])
					var move := MapLens.ground_probe(id, e, level, base, Color(0, 0, 0, 0), {"move": true})
					var gilt := Color(0.98, 0.80, 0.36)
					assert_true(Vector3(move.r, move.g, move.b).distance_to(Vector3(gilt.r, gilt.g, gilt.b)) < Vector3(plain.r, plain.g, plain.b).distance_to(Vector3(gilt.r, gilt.g, gilt.b)),
						"%s, %s: the move target's gilt glow goes on top" % [id, level])
	# the shader composes in §4.0's order: the lens wash or glow, the veil after it, then the hatch or ring, the sweep and the marks
	var src := FileAccess.get_file_as_string("res://world3d/shaders/ground_common.gdshaderinc")
	var at := func(t: String) -> int: return src.find(t)
	assert_true(at.call("if (lens_mode > 0 && g.id < 255) {") > at.call("veil_mist = mist"), "the lens colour is veiled after the look")
	assert_true(at.call("vec4 st = texture(owner_tex") > at.call("lens_a = texture(lens_tex"), "the owner wash (or its band) after the lens")
	assert_true(at.call("// a capture's sweep front") > at.call("Threat: red-pencil hatching"), "the hatch and ring before the sweep")
	assert_true(at.call("if (g.id == select_id)") > at.call("// a capture's sweep front"), "and the interaction marks last")


# --- fog safety: a leak test for every lens -----------------------------------------------------------------

func test_no_lens_leaks_anything_hidden() -> void:
	var checks := 0
	var built := {}
	for g in Kit.games():
		for i in g.turns.size():
			if i % 4 != 3 and i != g.turns.size() - 1:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var view: GameState = t.view_before[v]
				var mine: Array = t.orders[v]
				var seats := UiPalette.seat_order(view)
				var base := {}
				for id in MapLens.IDS:
					base[id] = _dump(MapLens.build(id, view, v, seats, mine, t.memory_before[v]), _ids(view))
				for k in 2:
					var p := Kit.perturb_hidden(t.before, v, hash([g.seed, t.turn, v, k, "lens"]))
					if p.state == null:
						continue
					var view2 := FogRules.view_state(p.state, v, t.memory_before[v], t.intel_before[v])
					for id in MapLens.IDS:
						var d := _dump(MapLens.build(id, view2, v, seats, mine, t.memory_before[v]), _ids(view2))
						assert_eq(d, base[id], "%s turn %d, %s, perturbation %d: the %s lens is identical" % [g.name, t.turn, v, k, id])
						built[id] = int(built.get(id, 0)) + 1
						checks += 1
	assert_true(checks >= 20 * 2 * 6, "many lenses compared (%d)" % checks)
	_notes.append("%d lens builds compared under hidden changes: %s" % [checks, built])


func test_the_boards_lens_texture_plates_and_legend_dont_change_under_hidden_changes() -> void:
	var map: MapScreen = null
	var checks := 0
	for g in Kit.games().slice(0, 4):
		var t: Dictionary = g.turns.back()
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			if map == null:
				map = _map(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v], true)
			else:
				map.set_fog(t.memory_after[v], t.intel_after[v], t.view_before[v])
				map.set_state(view, v)
			for id in MapLens.IDS:
				map.lens_host.activate(id)
				var base := _board_dump(map)
				var p := Kit.perturb_hidden(t.after, v, hash([g.seed, v, id, "board"]))
				if p.state == null:
					continue
				map.set_state(FogRules.view_state(p.state, v, t.memory_after[v], t.intel_after[v]), v)
				assert_eq(map.lens_host.active_id(), id, "the same viewer keeps the lens on")
				assert_eq(_board_dump(map), base, "%s, %s, %s: the board's lens texture, plates and legend are identical" % [g.name, v, id])
				checks += 1
				map.set_state(view, v)
	assert_true(checks >= 4 * 2 * 6, "boards compared (%d)" % checks)
	map.free()


# --- Threat -------------------------------------------------------------------------------------------------

func test_threat_is_indistinguishable_under_hidden_changes_and_counts_only_sightings() -> void:
	var checks := 0
	var seen_threat := 0
	for g in Kit.games():
		var t: Dictionary = g.turns.back()
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			var base := MapLens.build("threat", view, v)
			for pid in base.entries:
				seen_threat += 1 if float(base.entries[pid].value) > 0.0 else 0
			# every rival army counted is one the view holds, at its view strength; the truth is never read
			var want := {}
			for a in view.armies:
				if a.owner == v or a.owner == IndependentData.FACTION_ID:
					continue
				for pid in [a.location] + Array(view.find_province(a.location).neighbors):
					want[pid] = int(want.get(pid, 0)) + MapLens.threat_strength(a)
			for pid in base.entries:
				assert_eq(int(base.entries[pid].value), int(want.get(pid, 0)), "%s, %s: %s's threat is the view's armies one step away" % [g.name, v, pid])
			for k in 3:
				var p := Kit.perturb_hidden(t.after, v, hash([g.seed, v, k, "threat"]))
				if p.state == null:
					continue
				var r := MapLens.build("threat", FogRules.view_state(p.state, v, t.memory_after[v], t.intel_after[v]), v)
				assert_eq(_dump(r, _ids(view)), _dump(base, _ids(view)), "%s, %s, perturbation %d: Threat can't tell the truths apart" % [g.name, v, k])
				checks += 1
	assert_true(checks >= 20 * 2 * 2, "threat compared (%d)" % checks)
	assert_true(seen_threat > 0, "and some threat was seen")


func test_threat_in_a_built_case_estimates_with_its_turn_and_pulses_amber_where_you_can_reach() -> void:
	var s := GameState.new(31)
	s.setup_fog([])
	var crown_army: Army = null
	for a in s.armies:
		if a.owner == CROWN:
			crown_army = a
	var cap := s.find_province(s.find_faction(CROWN).capital)
	var near: String = cap.neighbors[0]
	var clan_army: Army = null
	for a in s.armies:
		if a.owner == CLANS:
			clan_army = a
	clan_army.location = near  # a rival army right next to the capital: in sight
	var view := FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	var r := MapLens.build("threat", view, CROWN)
	var stand_in: Army = null
	for a in view.armies:
		if a.owner == CLANS and a.location == near:
			stand_in = a
	assert_true(stand_in != null, "the view holds the rival next door")
	var e: Dictionary = r.entries[cap.id]
	assert_eq(int(e.value), MapLens.threat_strength(stand_in), "the capital's threat is that army's strength as seen")
	assert_eq(e.flag, 1.0, "your army at the capital can be there: amber")
	assert_true(String(e.tooltip).contains(view.find_province(near).name), "the hover names where it stands")
	assert_true(r.legend.notes[0].contains("one step; roads may reach further"), "the legend says it is an estimate, one step")
	var far := ""
	for p in view.provinces:
		var reach := MapLens.own_reach(view, CROWN)
		if not reach.has(p.id) and float(r.entries[p.id].value) > 0.0:
			far = p.id
	if not far.is_empty():
		assert_eq(r.entries[far].flag, 0.0, "threat your armies can't reach doesn't pulse")
	# watching (no side): nothing is threatened
	var w := MapLens.build("threat", s, "")
	for pid in w.entries:
		assert_eq(w.entries[pid].text, "–")
		assert_eq(w.entries[pid].mark, 0.0)


# --- Making ------------------------------------------------------------------------------------------------

func test_making_counts_follow_the_first_count_from_the_data() -> void:
	var s := GameState.with_sieges(57, {}, {"paths": true})
	s.current_turn = 7
	var held_for := [0, 2, 3, 5, 6, 7]
	var k := 0
	for p in s.provinces:
		if p.is_capital:
			continue
		p.owner = CROWN if k % 2 == 0 else CLANS
		p.owned_since = maxi(0, s.current_turn - int(held_for[k % held_for.size()]))
		k += 1
	s.find_faction(CROWN).researched.append({"node": "crown_living_iron", "turn": 2})  # the Forges: +1 at a fort
	s.find_faction(CLANS).researched.append({"node": "beasts_thorn_wild", "turn": 3})  # the Wild Spreads: +1 in a forest
	var r := MapLens.build("making", s, CROWN)
	var counted := {}
	for p in s.provinces:
		var want := 0
		if not p.owner.is_empty():
			var f := s.find_faction(p.owner)
			if f.capital == p.id:
				want = MapLens.MAKING_MAX
			else:
				var held := s.current_turn - p.owned_since
				want = 1
				for need in MapLens.MAKING_HELD:
					want += 1 if held >= need else 0
				var rule := String(AscensionRules.province_rule(s, p.owner).get("id", ""))
				if (rule == AscensionRules.FORGES and p.has_fort) or (rule == AscensionRules.WILD_SPREADS and p.terrain == AscensionRules.FOREST) \
						or rule == AscensionRules.HALLOWED_LAND or rule == AscensionRules.DREAD_LANDS:
					want += 1
				want = mini(want, MapLens.MAKING_MAX)
		var e: Dictionary = r.entries[p.id]
		assert_eq(int(e.pips), want, "%s: making %d" % [p.name, want])
		assert_eq(String(e.text), "%d of %d" % [want, MapLens.MAKING_MAX])
		assert_true(String(e.tooltip).contains("Making lens"), "the hover says why")
		counted[want] = true
	assert_true(counted.size() >= 3, "the case has several counts (%s)" % [counted.keys()])
	assert_true(r.legend.notes[0].contains("What it will do comes later"), "the legend says it has no rules effect yet")
	# without forts and sieges turns held aren't kept: no tenure marks, and the hover says so
	var plain := GameState.new(57)
	plain.current_turn = 9
	var pl := plain.provinces.filter(func(p): return not p.is_capital)[0] as Province
	pl.owner = CROWN
	var e2: Dictionary = MapLens.build("making", plain, CROWN).entries[pl.id]
	assert_eq(int(e2.pips), 1)
	assert_true(String(e2.tooltip).contains("not kept in a game without forts and sieges"))
	# under fog a rival's path counts only once it is known: the view keeps only known path nodes
	var fogged := GameState.with_sieges(57, {}, {"paths": true})
	fogged.setup_fog([])
	fogged.find_faction(CLANS).researched.append({"node": "beasts_blood_pact", "turn": 1})  # Dread Lands
	var clan_land := ""
	for p in fogged.provinces:
		if p.owner.is_empty() and not p.is_capital:
			p.owner = CLANS
			clan_land = p.id
			break
	var view := FogRules.view_state(fogged, CROWN, FogRules.new_memory(fogged, CROWN), FogRules.new_intel(fogged, CROWN))
	var known: bool = AscensionRules.researched(view, CLANS).has("beasts_blood_pact")
	assert_eq(int(MapLens.build("making", view, CROWN).entries[clan_land].pips), 2 if known else 1, "a rival's path counts only when you know it")


# --- plates, the legend, keys and the picker ----------------------------------------------------------------

func test_plates_show_the_lens_value_on_both_boards_with_its_breakdown_on_hover() -> void:
	var game := _game_with_board()
	var map := game.map
	var b: Board3D = map.board
	for id in MapLens.IDS:
		map.lens_host.activate(id)
		var r := map.lens_ui.result()
		for pid in b.overlay._plates:
			var chip: LensChip = b.overlay.lens_chip(String(pid))
			var e: Dictionary = r.entries[pid]
			assert_true(chip != null, "%s: %s's plate shows the lens value" % [id, pid])
			assert_eq(chip.label.text, String(e.text))
			assert_true(chip.tooltip_text.begins_with(String(e.tooltip).substr(0, 40)), "%s: the chip's hover is the lens value with its breakdown" % id)
			assert_eq(CodexLink.key_at(chip), String(MapLens.lens(id).codex), "and links the lens's codex entry")
			assert_true(b.overlay.plate_tooltip(String(pid)).begins_with("%s lens:" % MapLens.title_of(id)), "the plate's own hover starts with the lens value")
			var region: ProvinceRegion = map.regions[pid]
			assert_true(region.lens_chip != null and region.lens_chip.label.text == String(e.text), "the 2D map's plate shows it too")
		for pid in b.overlay._plates:
			if not b.overlay.plate_active(String(pid)):
				assert_eq(b.overlay.shows_part(String(pid), "enchantments"), id == "magic", "only the Magic lens shows every plate's enchantments (%s, %s)" % [id, pid])
	map.lens_host.clear()
	for pid in b.overlay._plates:
		assert_true(b.overlay.lens_chip(String(pid)) == null, "off: no chip on %s" % pid)
		assert_true(map.regions[pid].lens_chip == null)
		assert_false(b.overlay.plate_tooltip(String(pid)).contains(" lens:"))
	game.free()


func test_the_2d_map_draws_a_flat_lens_colour_under_the_veil_and_the_plate_value() -> void:
	var src := FileAccess.get_file_as_string("res://ui/province_region.gd")
	var lens_at := src.find("	_draw_lens()  #")
	assert_true(lens_at > 0 and lens_at < src.find("	_draw_veil()  #"), "the 2D lens colour is drawn under the veil, so sight still reads")
	assert_eq(ProvinceRegion.lens_fill("", {}), {}, "no lens, no colour")
	for id in MapLens.IDS:
		var weak: Dictionary = ProvinceRegion.lens_fill(id, {"tint": Color.RED, "strength": 0.2})
		var strong: Dictionary = ProvinceRegion.lens_fill(id, {"tint": Color.RED, "strength": 0.9})
		assert_true((strong.colour as Color).a > (weak.colour as Color).a, "%s: a stronger value lies more strongly on the 2D map" % id)
	var game := _game()
	var map := game.map
	assert_true(map.board == null, "the 2D map")
	map.lens_host.activate("making")
	var r := map.lens_ui.result()
	for pid in map.regions:
		var region: ProvinceRegion = map.regions[pid]
		assert_eq(region.lens_id, "making")
		assert_eq(region.lens_chip.pips.marks, int(r.entries[pid].pips), "%s's plate shows its marks" % pid)
	map.lens_host.clear()
	for pid in map.regions:
		assert_eq((map.regions[pid] as ProvinceRegion).lens_id, "")
	game.free()


func test_the_legend_card_sits_bottom_left_with_the_question_the_scale_and_the_totals() -> void:
	var game := _game()
	var map := game.map
	var hud := map.table()
	for size in [Vector2(1600, 900), Vector2(1280, 720)]:
		hud.viewport_override = size
		for id in MapLens.IDS:
			map.lens_host.activate(id)
			var legend := map.lens_ui.legend
			assert_true(legend.visible, "%s shows its legend" % id)
			var r := map.lens_ui.result()
			var text := legend.text()
			assert_true(text.contains(String(MapLens.lens(id).question)), "%s's legend asks its question" % id)
			for line in r.legend.totals:
				assert_true(text.contains(String(line)), "%s's legend has its total: %s" % [id, line])
			for step in (r.legend.scale as Dictionary).get("steps", []):
				if not String(step.label).is_empty():
					assert_true(text.contains(String(step.label)), "%s's legend labels its scale: %s" % [id, step.label])
			assert_true(text.contains("again, Esc or ` turns it off"), "and says how to turn it off")
			assert_true(legend.find_child("Scale", true, false) != null, "and draws its scale")
			assert_true(text.contains(String(r.legend.notes_2d[0])), "on the 2D map it names what the 3D board adds")
			for note in r.legend.notes:
				assert_true(legend.tooltip_text.replace("\n", " ").contains(String(note).substr(0, 30)), "%s's notes are the card's hover" % id)
			assert_eq(CodexLink.key_at(legend), String(MapLens.lens(id).codex), "and it links the lens's codex entry")
			hud.relayout()
			var rect: Rect2 = hud.placed()["legend"]
			var safe := hud.safe_area()
			assert_true(safe.grow(0.5).encloses(rect), "%s's legend is in the safe area at %s" % [id, size])
			var card: Rect2 = hud.placed().get("card", Rect2())
			var at_left := rect.position.x <= safe.position.x + TableLayout.GAP + 0.5
			var at_bottom := rect.end.y >= safe.end.y - TableLayout.GAP - 0.5
			assert_true((at_left and at_bottom) or (at_left and rect.end.y <= card.position.y) or (at_bottom and absf(rect.position.x - card.end.x - TableLayout.GAP) < 0.5),
				"%s's legend is bottom left, or above the card docked there, or beside it (%s, card %s)" % [id, rect, card])
			assert_false(hud.overflowed().has("legend"), "with room")
			if not hud.placed().has("guide") and not hud.placed().has("notice"):
				assert_eq(rect.position.x, safe.position.x + TableLayout.GAP, "%s's legend is short enough for the left column at %s (%d px tall), clear of the map" % [id, size, rect.size.y])
			for other in hud.placed():
				if other != "legend":
					assert_false(TableLayout.overlaps(rect, hud.placed()[other]), "%s's legend doesn't overlap the %s" % [id, other])
	map.lens_host.activate("sight")
	var rows := FogView.legend_rows(map.state)
	for row in rows:
		assert_true(map.lens_ui.legend.text().contains(LensLegend.row_label(row)), "the Sight lens carries the sight legend's %s" % row.title)
	map.lens_host.clear()
	assert_false(map.lens_ui.legend.visible)
	game.free()


func test_keys_toggle_a_lens_and_the_same_key_esc_or_backquote_turn_it_off() -> void:
	var game := _game()
	var map := game.map
	var host := map.lens_host
	map._unhandled_key_input(_key(KEY_2))
	assert_eq(host.active_id(), "income")
	map._unhandled_key_input(_key(KEY_2))
	assert_eq(host.active_id(), "", "the same key brings the art back")
	map._unhandled_key_input(_key(KEY_3))
	map._unhandled_key_input(_key(KEY_5))
	assert_eq(host.active_id(), "making", "one lens at a time")
	assert_eq(map.ui_cancel.cancel(), "card", "Esc closes the topmost thing first: the capital's card")
	assert_eq(host.active_id(), "making")
	assert_eq(map.ui_cancel.cancel(), "lens", "then the lens (UiCancel's order)")
	assert_eq(host.active_id(), "")
	map._unhandled_key_input(_key(KEY_6))
	map._unhandled_key_input(_key(KEY_QUOTELEFT))
	assert_eq(host.active_id(), "", "` turns it off")
	# the same keys on another layout (AZERTY's top row gives ' on the 4 key; a German one ^ left of the 1): their physical place counts
	var four := _key(KEY_APOSTROPHE)
	four.physical_keycode = KEY_4
	map._unhandled_key_input(four)
	assert_eq(host.active_id(), "magic", "the key where 4 is turns Magic on, whatever it types")
	var left_of_one := _key(KEY_ASCIICIRCUM)
	left_of_one.physical_keycode = KEY_QUOTELEFT
	map._unhandled_key_input(left_of_one)
	assert_eq(host.active_id(), "", "and the key left of 1 turns it off")
	game.open_controls_help()  # a modal is open: the keys are the modal's
	map._unhandled_key_input(_key(KEY_1))
	assert_eq(host.active_id(), "", "no lens under a modal")
	game.help_overlay.visible = false
	map._unhandled_key_input(_key(KEY_7))
	assert_eq(host.active_id(), "", "7 is no lens")
	game.free()


func test_the_lenses_button_opens_a_picker_and_says_what_it_does() -> void:
	var game := _game()
	var map := game.map
	var b := map.table().system_button("lenses")
	assert_eq(b, game.lenses_button)
	assert_false(b.disabled, "the Lenses button is live")
	assert_true(b.tooltip_text.contains("Extra map views (1–6). Off by default."), b.tooltip_text)
	assert_eq(CodexLink.key_at(b), "map_lenses")
	var picker := map.lens_ui.picker
	assert_eq(picker.item_count, MapLens.IDS.size() + 2, "six lenses, a separator and Off")
	map.lens_ui.open_picker()
	for i in MapLens.IDS.size():
		assert_true(picker.get_item_text(picker.get_item_index(i)).begins_with(MapLens.title_of(MapLens.IDS[i])))
		assert_false(picker.is_item_checked(picker.get_item_index(i)))
	map.lens_ui.choose(1)
	assert_eq(map.lens_host.active_id(), "income")
	assert_eq(String(b.get_meta("label", b.text)), "Lenses: Income", "the button names the lens that is on")
	map.lens_ui.open_picker()
	assert_true(picker.is_item_checked(picker.get_item_index(1)), "and the picker ticks it")
	map.lens_ui.choose(LensUi.OFF_ITEM)
	assert_eq(map.lens_host.active_id(), "")
	assert_eq(String(b.get_meta("label", b.text)), "Lenses")
	game.free()


func test_the_help_lists_the_lens_keys_and_the_codex_has_the_page() -> void:
	var game := _game()
	game.open_controls_help()
	var text := ""
	for l in game.help_overlay.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	for id in MapLens.IDS:
		assert_true(text.contains("%s lens" % MapLens.title_of(id)), "the ? lists the %s lens" % id)
	assert_true(text.contains("` (or Esc)"), "and ` to turn it off")
	game.free()
	assert_true(RulesCodex.ENTRIES.has("map_lenses"), "the codex page Map lenses")
	var page := RulesCodex.text("map_lenses")
	for id in MapLens.IDS:
		var entry := RulesCodex.entry(String(MapLens.lens(id).codex))
		assert_eq(String(entry.title), "%s lens" % MapLens.title_of(id), "one entry per lens")
		assert_true(page.contains(String(entry.title)), "the page names the %s" % entry.title)
		assert_true(String(entry.text).contains(String(MapLens.lens(id).question)), "and the entry asks its question")
	assert_true(RulesCodex.text("lens_income").contains("base income only"))
	assert_true(RulesCodex.text("lens_making").contains("no rules effect yet"))


func test_the_first_game_guide_leaves_lenses_out() -> void:
	var game := _game(ALL)
	var guide := game.first_game_guide
	var text := ""
	if guide != null:
		for l in guide.find_children("*", "Label", true, false):
			text += (l as Label).text
		for l in guide.find_children("*", "RichTextLabel", true, false):
			text += (l as RichTextLabel).text
	var src := FileAccess.get_file_as_string("res://ui/first_game_guide.gd").to_lower()
	assert_false(src.contains("lens"), "the guide's steps never mention lenses")
	assert_false(text.to_lower().contains("lens"))
	game.free()


# --- no rules change -------------------------------------------------------------------------------------------

func test_lenses_change_nothing_in_the_game() -> void:
	var game := _game_with_board()
	var before := JSON.stringify(game.session.state().to_dict())
	var shown := JSON.stringify(game.map.state.to_dict())
	for id in MapLens.IDS:
		game.map.lens_host.activate(id)
		game.map._sync_board()
	game.map.lens_host.clear()
	assert_eq(JSON.stringify(game.session.state().to_dict()), before, "the game's state is untouched")
	assert_eq(JSON.stringify(game.map.state.to_dict()), shown, "and so is the view the map shows")
	var src := FileAccess.get_file_as_string("res://ui/map_lens.gd")
	for word in ["randi", "randf", "SeededRNG", "resolve_turn", "TurnResolver.resolve"]:
		assert_false(src.contains(word), "MapLens rolls no dice and resolves nothing (%s)" % word)
	var assigns := RegEx.create_from_string("\\.(owner|gold|location|income|terrain|units|armies|provinces|current_turn)\\s*(=[^=]|\\+=|-=)")
	assert_eq(assigns.search_all(src).map(func(m): return m.get_string()), [], "MapLens assigns nothing in the game")
	game.free()
