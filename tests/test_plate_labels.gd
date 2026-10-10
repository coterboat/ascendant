extends "res://tests/test_case.gd"
## UX-2 (#205; design/UX_WAR_TABLE.md 2.1, 2.2, 2.3 and the UX-2 row of section 9): labels and sight.
##   * Vision.look: four looks that differ in lightness (stepped, by at least a set amount) and in texture, with veiled and never seen
##     told apart; the shaders' arrays carry the same numbers; the words name each look
##   * the label diet on the 3D board's plates: the name, the owner's emblem, the crown and the marks that warn are always there; the
##     gold, garrison and walls (an icon and a number each) and the enchantments appear on hover, keyboard focus or selection, or
##     where a lens asks (set_always)
##   * the plate carries the province's tooltip (its level in words and why) and the codex link that the sight line carried, by mouse
##     (its own hover, right-click) and by keyboard focus (the focus tip, F1, Enter)
##   * nothing is printed about sight under a plate any more
##   * the fort scale: palisade, keep and citadel are told apart by size alone at the whole-map zoom
##   * the kept legend of the retired Vision map mode (FogView.legend_rows) for the Sight lens
## Expected values come from the data (Vision, FogView, FortData, Breakdown) and the states, never hardcoded.

const Vision := preload("res://world3d/vision.gd")
const Kit := preload("res://tests/fog_test_kit.gd")
const F := preload("res://tests/siege_fixtures.gd")
const WorldKit := preload("res://world3d/kit.gd")
const Models := preload("res://world3d/models.gd")
const BOARD_SIZE := Vector2(1200, 836)
const CR := "kingdom"
const CL := "beasts"
const LEVELS := ["clear", "glimpse", "veiled", "never"]
## The least a look's lightness drops from the one before, and the least the luminance it leaves on a mean ground does (Vision.lit).
const MIN_LIGHTNESS_STEP := 0.12
const MIN_LIT_STEP := 0.07


# --- fixtures --------------------------------------------------------------------------------------------

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## A board standing `state` as `viewer` sees it, its map in the tree (so the plates can take the keyboard focus).
func _board(state: GameState, viewer: String, memory: Dictionary = {}, intel: Dictionary = {}, before: GameState = null) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	_root().add_child(map)
	if not memory.is_empty():
		map.set_fog(memory, intel, before)
	map.set_state(state, viewer)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


func _drop(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


## The Crown besieges Stonegate (a keep) and raises a palisade at Rivermarch, after one real turn (the sieges story's first).
func _siege_state() -> GameState:
	var force := F.force_to_breach(SiegeRules.walls_max(2), 2, 22, 2)
	assert_false(force.is_empty(), "some force breaches a keep on the siege's second turn")
	var s: GameState = F.state([
		["k_siege", CR, "westwatch", F.units("spearmen", force[0]), force[1]],
		["k_rm", CR, "rivermarch", F.units("spearmen", 6)],
		["k_home", CR, "crownkeep", F.units("crossbowmen", 4)],
		["b_gar", CL, "stonegate", F.units("tuskers", 8)],
		["b_bw", CL, "blackwood", F.units("tuskers", 10)],
		["b_home", CL, "fangridge", F.units("fangthrowers", 4)],
	], {"westwatch": CR, "rivermarch": CR, "stonegate": CL, "blackwood": CL})
	F.rich(s, CR)
	F.rich(s, CL)
	var orders := {CR: [MoveOrder.new("k_siege", "stonegate"), FortifyOrder.new("rivermarch")], CL: []}
	var res: Dictionary = TurnResolver.resolve(s, orders, 7, AutoBattleResolver.new())
	assert_true(res.get("new_state") != null, "the turn resolves")
	return res["new_state"]


static func _flat(text: String) -> String:
	return " ".join(text.replace("\n", " ").split(" ", false))


func _plate(b: Board3D, pid: String) -> Dictionary:
	return b.overlay._plates[pid]


# --- Vision.look -----------------------------------------------------------------------------------------

func test_the_four_looks_differ_in_lightness_and_in_texture() -> void:
	var looks := {}
	for level in LEVELS:
		looks[level] = Vision.look(level)
		assert_eq(String(looks[level].level), level, "%s's look names its level" % level)
	# four distinct parameter sets
	var seen := {}
	for level in LEVELS:
		seen[var_to_str(looks[level])] = true
	assert_eq(seen.size(), 4, "four distinct parameter sets")
	# lightness: strictly darker with each level, by at least a set amount (the parameter, and what it leaves on a mean ground)
	for i in range(1, LEVELS.size()):
		var up: Dictionary = looks[LEVELS[i - 1]]
		var down: Dictionary = looks[LEVELS[i]]
		assert_true(float(up.lightness) - float(down.lightness) >= MIN_LIGHTNESS_STEP, "%s is at least %.2f darker than %s (%.2f to %.2f)" % [LEVELS[i], MIN_LIGHTNESS_STEP, LEVELS[i - 1], up.lightness, down.lightness])
		assert_true(Vision.lit(LEVELS[i - 1]) - Vision.lit(LEVELS[i]) >= MIN_LIT_STEP, "and leaves a mean ground at least %.2f darker (%.3f to %.3f)" % [MIN_LIT_STEP, Vision.lit(LEVELS[i - 1]), Vision.lit(LEVELS[i])])
	assert_eq(float(looks.clear.lightness), 1.0, "clear sight leaves the ground as it is")
	# texture: none, a drifting mist, a hatch, a flat parchment: each its own, so the levels read without colour
	var textures := LEVELS.map(func(l): return String(looks[l].texture))
	assert_eq(textures, ["none", "mist", "hatch", "parchment"], "each level its own texture")
	assert_eq(float(looks.clear.mist) + float(looks.clear.hatch) + float(looks.clear.grain), 0.0, "clear has none of them")
	assert_true(float(looks.glimpse.mist) > 0.0 and float(looks.glimpse.hatch) == 0.0, "glimpsed land is misted, not hatched")
	assert_true(float(looks.veiled.hatch) > 0.0 and float(looks.veiled.mist) == 0.0, "land out of sight is hatched, not misted")
	assert_true(float(looks.never.grain) > 0.0 and float(looks.never.hatch) == 0.0 and float(looks.never.mist) == 0.0, "land never seen is plain parchment")
	# the veiled and never-seen levels no longer look alike: lightness, texture, detail and colour all differ
	assert_true(float(looks.veiled.lightness) - float(looks.never.lightness) >= MIN_LIGHTNESS_STEP, "veiled is lighter than never")
	assert_true(float(looks.veiled.detail) > 0.0 and float(looks.never.detail) == 0.0, "veiled keeps the terrain, never has none")
	assert_ne(looks.veiled.texture, looks.never.texture)
	assert_ne(looks.veiled.tint, looks.never.tint)
	# veiled is "toward sepia" (warm: red over green over blue) and glimpsed is a cool step
	var sepia: Color = looks.veiled.tint
	assert_true(sepia.r > sepia.g and sepia.g > sepia.b, "out of sight leans to sepia")
	var cool: Color = looks.glimpse.tint
	assert_true(cool.b > cool.r, "glimpsed land leans cool")
	# the flat parchment IS its lightness of a mean ground (the shader's flat tone and the parameter agree)
	assert_true(absf((looks.never.tint as Color).get_luminance() - float(looks.never.lightness) * Vision.REF_LUMA) < 0.03, "never's tone is its lightness of a mean ground")
	# unknown levels and no fog are the clear look; a look is a copy
	assert_eq(Vision.look(""), looks.clear)
	assert_eq(Vision.look("nonsense"), looks.clear)
	var copy := Vision.look("never")
	copy["lightness"] = 9.0
	assert_eq(float(Vision.look("never").lightness), float(looks.never.lightness), "changing a copy changes nothing")


func test_the_shaders_arrays_carry_the_same_looks_by_texel() -> void:
	var arrays := Vision.look_arrays()
	for k in ["look_tone", "look_lift", "look_tex"]:
		assert_eq((arrays[k] as PackedVector4Array).size(), 4, "%s has one entry per level" % k)
	for level in LEVELS:
		var i: int = int(Vision.TEXEL[level]) / 85
		assert_eq(Vision.LOOK_ORDER[i], level, "the texel of %s indexes its look" % level)
		var lk := Vision.look(level)
		var tone: Vector4 = (arrays["look_tone"] as PackedVector4Array)[i]
		var lift: Vector4 = (arrays["look_lift"] as PackedVector4Array)[i]
		var tex: Vector4 = (arrays["look_tex"] as PackedVector4Array)[i]
		assert_true(is_equal_approx(lift.x, float(lk.lightness)) and is_equal_approx(lift.y, float(lk.drain)) and is_equal_approx(lift.z, float(lk.detail)) and is_equal_approx(lift.w, float(lk.grain)), "%s: lightness, drain, detail and grain" % level)
		assert_true(is_equal_approx(tone.x, (lk.tint as Color).r) and is_equal_approx(tone.w, float(lk.tint_k)), "%s: tint" % level)
		assert_true(is_equal_approx(tex.x, float(lk.mist)) and is_equal_approx(tex.y, float(lk.hatch)), "%s: mist and hatch" % level)


func test_the_words_name_what_each_look_shows() -> void:
	var key := {"glimpse": "mist", "veiled": "hatch", "never": "parchment"}
	for level in LEVELS:
		var words := Vision.words(level)
		assert_true(words.begins_with(String(FogView.LEVEL_TITLES[level])), "%s's words begin with its name" % level)
		if key.has(level):
			assert_true(words.to_lower().contains(String(key[level])), "%s's words name its texture (%s): %s" % [level, key[level], words])
	assert_false(Vision.legend_lines(GameState.new(3)).contains("glimpsed"), "no fog, no fog legend")


# --- the 2D map's veil is the same four looks --------------------------------------------------------------

func test_the_2d_veil_follows_the_looks() -> void:
	assert_eq(ProvinceRegion.veil_of("clear"), {}, "clear land is not veiled")
	assert_eq(ProvinceRegion.veil_of(""), {}, "nor is a game without fog")
	var darkness := {}
	for level in ["glimpse", "veiled", "never"]:
		var v := ProvinceRegion.veil_of(level)
		assert_false(v.is_empty(), "%s is veiled" % level)
		darkness[level] = (v.colour as Color).a
	assert_true(darkness.glimpse < darkness.veiled and darkness.veiled < darkness.never, "each level darker than the one before: %s" % darkness)
	assert_true(bool(ProvinceRegion.veil_of("glimpse").streaks) and not bool(ProvinceRegion.veil_of("glimpse").hatch), "glimpsed: streaks")
	assert_true(bool(ProvinceRegion.veil_of("veiled").hatch) and not bool(ProvinceRegion.veil_of("veiled").streaks), "out of sight: hatch")
	assert_false(bool(ProvinceRegion.veil_of("never").hatch) or bool(ProvinceRegion.veil_of("never").streaks), "never seen: flat")
	assert_true(float(ProvinceRegion.veil_of("never").colour.a) > 0.9, "and it hides the terrain")


# --- the label diet --------------------------------------------------------------------------------------

func test_a_plate_always_shows_what_warns_and_shows_the_rest_on_hover_focus_or_selection() -> void:
	var st := _siege_state()
	var b := _board(st, CR)
	var o: Control = b.overlay
	b.hover_id = ""
	b.map.selected_province_id = ""
	o._poll_detail()
	var besieged := 0
	for p in st.provinces:
		if not o._plates.has(p.id):
			continue
		var pl := _plate(b, p.id)
		var plate: Control = pl.root
		assert_true((pl.name as Label).visible and (pl.name as Label).text == p.name, "%s: its name" % p.id)
		var dot: SeatEmblem = pl.dot
		assert_eq(dot.seat, UiPalette.seat_index(st, p.owner, b.map.seat_order()), "%s: its owner's emblem" % p.id)
		assert_eq(pl.glyph != null and pl.glyph.kind == "crown", p.is_capital, "%s: the crown is a capital's" % p.id)
		var state_of := FortView.state_of(st, p.id)
		var warns: bool = state_of in ["besieged", "breached", "building"]
		besieged += 1 if warns else 0
		assert_eq(o.has_fort_chip(p.id), warns, "%s: the fort chip is there while it warns (%s)" % [p.id, state_of])
		if warns:
			assert_true((pl.chip as Control).visible and plate.is_ancestor_of(pl.chip), "%s: and it is on the plate" % p.id)
		assert_eq(o.has_cut_mark(p.id), SiegeRules.is_cut_off(st, p.id), "%s: the cut-off mark exactly when it is cut off" % p.id)
		# nothing static shows with nothing hovered, focused or selected
		for part in pl.parts:
			assert_false((pl.parts[part] as Control).visible, "%s: %s waits for hover, focus or selection" % [p.id, part])
		assert_false((pl.detail as Control).visible, "%s: the detail box is closed" % p.id)
	assert_true(besieged > 0, "the siege marks are on show")
	# selecting a province opens its plate and only its plate
	var pid := "blackwood"
	b.map.select_province(pid)
	o._poll_detail()
	for id in o._plates:
		var shown: bool = (_plate(b, id).parts.gold as Control).visible
		assert_eq(shown, id == pid, "%s: the gold shows only on the selected plate" % id)
	_check_detail(b, st, pid)
	# hover (the ground's, then the plate's own) and its end
	b.map.selected_province_id = ""
	o._poll_detail()
	assert_false((_plate(b, pid).parts.gold as Control).visible, "deselected: closed again")
	b.hover_id = "stonegate"
	o._poll_detail()
	assert_true((_plate(b, "stonegate").parts.gold as Control).visible, "the province under the mouse opens its plate")
	b.hover_id = ""
	o._poll_detail()
	assert_false((_plate(b, "stonegate").parts.gold as Control).visible)
	var plate: Control = _plate(b, "crownkeep").root
	plate.mouse_entered.emit()
	o._poll_detail()
	assert_true((_plate(b, "crownkeep").parts.gold as Control).visible, "the mouse over a plate opens it")
	plate.mouse_exited.emit()
	o._poll_detail()
	assert_false((_plate(b, "crownkeep").parts.gold as Control).visible, "and leaving closes it")
	# the keyboard focus opens it too (the real Tab, arrows and clicks are tests/plate_probe.gd's: nothing here is in a started tree)
	assert_eq(plate.focus_mode, Control.FOCUS_ALL, "a plate can take the keyboard focus")
	plate.focus_entered.emit()
	assert_true((_plate(b, "crownkeep").parts.gold as Control).visible, "the focused plate is open")
	plate.focus_exited.emit()
	assert_false((_plate(b, "crownkeep").parts.gold as Control).visible, "and closes when the focus leaves")
	_drop(b)


## The stats of an open plate: the gold, the garrison and the walls, each an icon (UiIcons, 16 px) and the number the state gives.
func _check_detail(b: Board3D, st: GameState, pid: String) -> void:
	var pl := _plate(b, pid)
	var p := st.find_province(pid)
	var gold: Control = pl.parts.gold
	assert_eq((gold.get_node("IncomeLabel") as Label).text, str(int(Breakdown.province_income(st, pid).total)), "%s: the gold is the province's income" % pid)
	assert_eq((gold.get_node("Icon") as TextureRect).texture, UiIcons.icon("gold", UiIcons.SIZE_SMALL), "an icon from the set")
	var gar: Control = pl.parts.garrison
	var units := 0
	for a in st.armies:
		if a.location == pid and a.owner == p.owner:
			units += a.units.size()
	assert_eq((gar.get_node("Number") as Label).text, str(units), "%s: the garrison counts its owner's units standing there" % pid)
	assert_eq((gar.get_node("Icon") as TextureRect).texture, UiIcons.icon("garrison", UiIcons.SIZE_SMALL))
	assert_true(p.fort_level > 0 and pl.parts.has("walls"), "%s is a fort with walls" % pid)
	var walls: Control = pl.parts.walls
	assert_eq((walls.get_node("Number") as Label).text, "%d/%d" % [p.walls, SiegeRules.walls_max(p.fort_level)], "the walls are n of the most")
	assert_eq((walls.get_node("Icon") as TextureRect).texture, UiIcons.icon("walls", UiIcons.SIZE_SMALL))
	for part in ["gold", "garrison", "walls"]:
		var c: Control = pl.parts[part]
		assert_false(c.tooltip_text.is_empty(), "%s: the %s explains itself" % [pid, part])
		var key := String(c.get_meta(CodexLink.META, ""))
		assert_true(RulesCodex.ENTRIES.has(key), "%s: and links a codex entry (%s)" % [part, key])
	var tip := _flat((walls as Control).tooltip_text)
	assert_true(tip.contains("Walls"), "the walls' hover is the walls breakdown")


func test_a_lens_can_ask_for_a_part_on_every_plate_and_enchantments_show_on_hover() -> void:
	var st := _siege_state()
	st.magic = true
	st.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CR, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 9, "bonus": 0, "ending": false})
	var b := _board(st, CR)
	var o: Control = b.overlay
	b.hover_id = ""
	b.map.selected_province_id = ""
	o._poll_detail()
	var ench: Control = _plate(b, "crownkeep").parts.get("enchantments")
	assert_true(ench != null, "the capital has its badge")
	assert_false(ench.visible, "hidden until hover")
	assert_false(_plate(b, "highcrag").parts.has("enchantments"), "no badge where nothing lies")
	b.hover_id = "crownkeep"
	o._poll_detail()
	assert_true(ench.visible and (_plate(b, "crownkeep").parts.gold as Control).visible, "on hover: the badges and the stats")
	b.hover_id = ""
	o._poll_detail()
	# the hook UX-7's lenses use: one part on every plate, the others still hover-only
	o.set_always("enchantments", true)
	assert_true(ench.visible, "the Magic lens shows the enchantments always")
	assert_false((_plate(b, "crownkeep").parts.gold as Control).visible, "and only them")
	o.set_always("enchantments", false)
	assert_false(ench.visible, "and takes them back")
	o.set_always("gold", true)
	for id in o._plates:
		assert_true((_plate(b, id).parts.gold as Control).visible, "%s: the Income lens shows the gold on every plate" % id)
		assert_false((_plate(b, id).parts.garrison as Control).visible, "%s: and not the garrison" % id)
	o.set_always("gold", false)
	o.set_always("all", true)
	for id in o._plates:
		assert_true(o.shows_part(id, "walls") or not _plate(b, id).parts.has("walls"), "%s: every part with 'all'" % id)
	o.set_always("all", false)
	assert_false((_plate(b, "crownkeep").parts.gold as Control).visible)
	_drop(b)


# --- the plate's tooltip and codex link, by mouse and by keyboard focus ------------------------------------

func test_every_plate_carries_its_tooltip_and_codex_link_by_mouse_and_by_focus() -> void:
	var levels_seen := {}
	var checked := 0
	for g in Kit.games():
		var t: Dictionary = g.turns.back()
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			var memory: Dictionary = t.memory_after[v]
			var b := _board(view, v, memory, t.intel_after[v], t.view_before[v])
			var o: Control = b.overlay
			var asked := []
			b.map.codex_requested.connect(func(key: String): asked.append(key))
			for pid in b.vision_levels:
				var level: String = b.vision_levels[pid]
				levels_seen[level] = true
				var pl := _plate(b, pid)
				var plate: Control = pl.root
				var where := "%s %s, %s" % [g.name, pid, level]
				# no words about sight under the plate
				assert_true(plate.find_child("SightLabel", true, false) == null, "%s: no sight line under the plate" % where)
				# by mouse: the plate's own hover, which the engine asks for (Control.get_tooltip)
				var tip: String = plate.get_tooltip(Vector2.ZERO)
				assert_false(tip.is_empty(), "%s: the plate has a hover" % where)
				assert_eq(tip, o.plate_tooltip(pid), "%s: it is the plate's tooltip" % where)
				var flat := _flat(tip)
				assert_true(flat.contains(_flat(Vision.words(level))), "%s: the hover says how the ground shows the level" % where)
				assert_true(flat.contains(String(FogView.LEVEL_TITLES[level])), "%s: and names it" % where)
				var why := _flat(FogView.province_text(view, v, pid, memory))
				assert_true(why.is_empty() or flat.contains(why), "%s: and why you see it, or what you remember" % where)
				assert_true(flat.contains(_flat(view.find_province(pid).name)), "%s: and the province" % where)
				var want_key: String = TooltipText.codex_for("province") if level == "clear" else String(FogView.LEVEL_CODEX[level])
				assert_eq(String(plate.get_meta(CodexLink.META)), want_key, "%s: the codex link" % where)
				assert_true(RulesCodex.ENTRIES.has(want_key), "%s: is an entry" % where)
				assert_true(tip.ends_with(CodexLink.with_link("", want_key).strip_edges()), "%s: and the hover ends with it" % where)
				assert_eq(CodexLink.key_at(plate), want_key, "%s: F1 over the plate finds it" % where)
				# right-click on the plate opens it
				asked.clear()
				plate.gui_input.emit(CodexLink.right_click())
				assert_eq(asked, [want_key], "%s: a right-click opens the codex there" % where)
				# by keyboard focus: the plate opens, the focus tip shows the same words, F1 and Enter work
				plate.focus_entered.emit()
				assert_true(o.plate_active(pid) and o._focus_tip != null and o._focus_tip.visible, "%s: focus opens it and shows the tip" % where)
				assert_eq(o._focus_label.text, o.plate_tooltip(pid), "%s: the focus tip is the plate's tooltip" % where)
				asked.clear()
				var f1 := InputEventKey.new()
				f1.keycode = KEY_F1
				f1.pressed = true
				plate.gui_input.emit(f1)
				assert_eq(asked, [want_key], "%s: F1 with the focus on the plate opens the codex there" % where)
				var enter := InputEventKey.new()
				enter.keycode = KEY_ENTER
				enter.physical_keycode = KEY_ENTER
				enter.pressed = true
				b.map.selected_province_id = ""
				plate.gui_input.emit(enter)
				assert_eq(b.map.selected_province_id, pid, "%s: Enter selects the province" % where)
				plate.focus_exited.emit()
				assert_false(o._focus_tip.visible, "%s: the tip goes with the focus" % where)
				checked += 1
			_drop(b)
	for level in LEVELS:
		assert_true(levels_seen.has(level), "the games showed %s" % level)
	assert_true(checked >= 50, "many plates were checked (%d)" % checked)


func test_a_plain_game_plate_links_province_and_has_no_sight_words() -> void:
	var st := _siege_state()
	var b := _board(st, CR)
	for id in b.overlay._plates:
		var plate: Control = _plate(b, id).root
		assert_eq(String(plate.get_meta(CodexLink.META)), TooltipText.codex_for("province"), "%s links Province without fog" % id)
		assert_true(plate.get_tooltip(Vector2.ZERO).contains(st.find_province(id).name), "%s's hover names it" % id)
		assert_false(plate.get_tooltip(Vector2.ZERO).contains("In clear sight"), "%s: no sight words without fog" % id)
	_drop(b)


# --- garrison: the viewer's own knowledge ------------------------------------------------------------------

func test_the_garrison_stat_is_only_what_the_viewer_may_say() -> void:
	var checked := 0
	for g in Kit.games():
		var t: Dictionary = g.turns.back()
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			var b := _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
			var o: Control = b.overlay
			for pid in b.vision_levels:
				var level: String = b.vision_levels[pid]
				var facts: Dictionary = o._plates[pid].get("garrison_facts", {})
				assert_false(facts.is_empty(), "%s has garrison facts" % pid)
				var gar: Control = o._plates[pid].garrison
				assert_eq((gar.get_node("Number") as Label).text, String(facts.text))
				if level in ["veiled", "never"]:
					assert_eq(String(facts.text), "?", "%s (%s): out of sight the garrison is not known" % [pid, level])
					assert_true(_flat(gar.tooltip_text).contains("can't see"), "and the hover says why")
				else:
					assert_true(bool(facts.known), "%s: in sight it is known" % pid)
					assert_eq(bool(facts.approx), String(facts.text).begins_with("≈"), "a rough count wears its ≈")
					if level == "clear":
						assert_false(bool(facts.approx), "%s: in clear sight it is exact" % pid)
				checked += 1
			_drop(b)
	assert_true(checked >= 30, "many provinces were checked (%d)" % checked)


# --- the 2D map follows the same diet ----------------------------------------------------------------------

func test_the_2d_plates_follow_the_label_diet() -> void:
	var st := _siege_state()
	st.magic = true
	st.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CR, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 9, "bonus": 0, "ending": false})
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(st, CR)
	var seen_warn := 0
	var seen_quiet := 0
	for id in map.regions:
		var region: ProvinceRegion = map.regions[id]
		assert_false(region.detail_shown(), "%s: the gold waits for hover or selection" % id)
		assert_true(region.name_label.visible and region.army_box.visible, "%s: the name and the army badges stay" % id)
		if region.enchantment_badges != null:
			assert_false(region.enchantment_badges.visible, "%s: the enchantments wait too" % id)
		if region.fort_chip != null:
			var warns: bool = region.fort_chip.kind in ["besieged", "breached", "building"]
			assert_eq(region.fort_chip.visible, warns, "%s: a fort's chip shows while it warns (%s), else on hover" % [id, region.fort_chip.kind])
			seen_warn += 1 if warns else 0
			seen_quiet += 0 if warns else 1
		if region.countdown_badge != null:
			assert_true(region.countdown_badge.visible, "%s: the heir countdown never hides" % id)
	assert_true(seen_warn > 0 and seen_quiet > 0, "the siege had a chip that warns (%d) and a quiet one (%d)" % [seen_warn, seen_quiet])
	var region: ProvinceRegion = map.regions["crownkeep"]
	region.mouse_entered.emit()
	assert_true(region.detail_shown() and region.income_label.visible, "hover opens the plate")
	assert_true(region.enchantment_badges.visible, "and the enchantments")
	region.mouse_exited.emit()
	assert_false(region.detail_shown(), "and leaving closes it")
	region.selected = true
	assert_true(region.detail_shown() and region.enchantment_badges.visible, "selection opens it")
	region.selected = false
	assert_false(region.detail_shown())
	region.always_detail = true
	assert_true(region.detail_shown(), "a lens can keep it open")
	region.always_detail = false
	var quiet: ProvinceRegion = map.regions["blackwood"]
	assert_true(quiet.fort_chip != null and not quiet.fort_chip.visible, "a quiet keep's chip is hidden")
	quiet.mouse_entered.emit()
	assert_true(quiet.fort_chip.visible, "and shows on hover")
	map.free()


# --- army plates keep their text under fog ---------------------------------------------------------------

func test_armies_under_fog_keep_their_plate_text() -> void:
	var glimpsed := 0
	var remembered := 0
	for g in Kit.games():
		for t in g.turns:
			if t.turn < 4:
				continue
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				var b := _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				for a in view.armies:
					if not Vision.is_stand_in(a):
						continue
					var pc: PanelContainer = b.overlay._army_plates.get(a.id)
					assert_true(pc != null, "%s has a plate" % a.id)
					if pc == null:
						continue
					var texts := pc.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
					var want: String = b.overlay.plate_text(view, a)
					assert_true(texts.has(want), "%s's plate says \"%s\" (it says %s)" % [a.id, want, texts])
					if Vision.is_memory(a):
						remembered += 1
						assert_true(want.contains(Vision.ago_text(view, int(a.seen.get("turn", 0)))), "a remembered army says when: %s" % want)
					elif String(a.seen.get("level", "")) == FogRules.GLIMPSE and a.ruler == null and not a.units.is_empty():
						glimpsed += 1
						assert_true(want.begins_with("≈"), "a glimpsed army's number is an estimate: %s" % want)
				_drop(b)
	assert_true(glimpsed > 0 and remembered > 0, "the games had glimpsed (%d) and remembered (%d) armies" % [glimpsed, remembered])


# --- forts told apart at the whole-map zoom ---------------------------------------------------------------

func test_the_fort_levels_are_told_apart_by_size_at_the_whole_map_zoom() -> void:
	# the scale table: the citadel as it is, the kit's keep and palisade drawn bigger, a damage look's kind scaling with its level
	assert_eq(WorldKit.fort_scale("fortress"), 1.0, "the citadel keeps its size")
	assert_true(WorldKit.fort_scale("fort") > 1.0 and WorldKit.fort_scale("palisade") > 1.0, "the keep and the palisade are drawn bigger")
	assert_eq(WorldKit.fort_scale("fort_damaged"), WorldKit.fort_scale("fort"), "a damaged keep is a keep's size")
	assert_eq(WorldKit.fort_scale("palisade_breached"), WorldKit.fort_scale("palisade"))
	assert_eq(WorldKit.fort_scale("fortress_breached"), 1.0)
	assert_eq(WorldKit.fort_scale("tree_pine"), 1.0, "any other piece is not scaled")
	var st := _siege_state()
	var b := _board(st, CR)
	var kit := String(b.wv.map_kits().get("stonegate", ""))
	var palisade: Dictionary = b.wv.fort_geom("rivermarch", "palisade", String(b.wv.map_kits().get("rivermarch", "")))
	var keep: Dictionary = b.wv.fort_geom("stonegate", "fort", kit)
	var citadel: Dictionary = b.wv.yard_of("crownkeep", st)
	assert_false(citadel.is_empty(), "the capital's citadel")
	# wider with each level, by a margin that shows at the whole-map zoom (about a pixel to the world unit)
	assert_true(float(palisade.radius) * 1.25 <= float(keep.radius) and float(keep.radius) * 1.25 <= float(citadel.radius),
		"each level's footprint is at least a quarter wider than the one below: %.1f, %.1f, %.1f" % [palisade.radius, keep.radius, citadel.radius])
	# the geometry follows the drawing: the keep's footprint is its model's side, scaled; its yard and gate scale with it
	var row := Models.building_row("fort", kit)
	var prim_row := Models.building_row("fort", "")
	var has_model := not Models.building_model("fort", kit).is_empty()
	var side: float = float(row.get("side", prim_row.get("side", 24.0))) if has_model else float(WorldKit.FORT_YARD["side"])
	assert_true(absf(float(keep.radius) - side * WorldKit.fort_scale("fort") * 0.5) < 0.01, "the keep's radius is its side, scaled, halved")
	var court: Rect2 = keep.court
	assert_true(court.size.x * 0.5 < float(keep.radius) and absf(court.position.y) < float(keep.radius), "its yard lies inside its walls")
	assert_true(Vector2(keep.gate_z).y <= -float(keep.radius) * 0.5, "and its gate stands out at the wall")
	# the pieces' heights too: a stockade lower than a keep lower than a citadel
	var hp: float = b.wv._fort_piece("palisade", String(b.wv.map_kits().get("rivermarch", "")))["h"]
	var hk: float = b.wv._fort_piece("fort", kit)["h"]
	var hc: float = float(b.wv.fortresses["crownkeep"]["h"])
	assert_true(hp < hk and hk < hc, "taller with each level: %.1f, %.1f, %.1f" % [hp, hk, hc])
	_drop(b)


# --- the kept legend of the retired Vision map mode -------------------------------------------------------

func test_the_vision_legend_text_is_kept_for_the_sight_lens() -> void:
	var g: Dictionary = Kit.games()[0]
	var t: Dictionary = g.turns.back()
	var view: GameState = t.view_after[CR]
	var rows := FogView.legend_rows(view)
	var keys := rows.map(func(r): return String(r.key))
	for k in ["clear", "glimpse", "veiled", "never", "plate", "ghost"]:
		assert_true(keys.has(k), "the legend keeps its %s row" % k)
	for r in rows:
		assert_false(String(r.title).is_empty() or String(r.short).is_empty() or String(r.text).is_empty(), "%s has its words" % r.key)
		assert_true(RulesCodex.ENTRIES.has(String(r.codex)), "%s links a codex entry that exists" % r.key)
		assert_true(ProvinceRegion.legend_swatch(String(r.key)) != null, "%s has a swatch" % r.key)
	for level in LEVELS:
		var row: Dictionary = rows[keys.find(level)]
		assert_eq(String(row.title), String(FogView.LEVEL_TITLES[level]), "%s's row is named as the plate's hover names it" % level)
		assert_eq(String(row.codex), String(FogView.LEVEL_CODEX[level]), "and links what the plate links")
	assert_true(_flat(String(rows[keys.find("glimpse")].text)).to_lower().contains("mist"), "the glimpsed row says its texture")
	assert_true(_flat(String(rows[keys.find("veiled")].text)).to_lower().contains("hatch"), "the out-of-sight row says its texture")
	assert_true(_flat(String(rows[keys.find("never")].text)).to_lower().contains("parchment"), "the never-seen row says its texture")
	assert_eq(FogView.legend_rows(GameState.new(3)).filter(func(r): return r.key == "eye").size(), 0, "no eye without magic")


# --- the real input paths, in a started scene tree ---------------------------------------------------------

## tests/plate_probe.gd stands a fog game's board in a viewport and pushes real key and mouse events at its plates, in a subprocess
## (the runner calls tests before the tree has started, so nothing it builds can take the keyboard focus).
func test_tab_arrows_f1_enter_and_the_mouse_reach_the_plates() -> void:
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/plate_probe.gd"]
	var output := []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var r := {}
	for line in text.split("\n"):
		if line.begins_with("PLATE_REPORT "):
			var parsed = JSON.parse_string(line.trim_prefix("PLATE_REPORT "))
			if parsed is Dictionary:
				r = parsed
	assert_true(not r.is_empty() and bool(r.get("ok", false)), "the probe reported (exit code %d): %s" % [code, text.right(600)])
	if r.is_empty():
		return
	assert_true(int(r.plates) > 0 and r.viewport == [1600.0, 900.0], "plates were built (%s)" % r.plates)
	assert_false(String(r.tab_focus).is_empty(), "Tab puts the keyboard focus on a plate")
	assert_true(bool(r.tab_detail) and bool(r.tab_tip), "and its detail and the focus tip open, the tip holding the plate's tooltip")
	assert_true(bool(r.arrows_keep_focus), "the arrow keys keep panning the board: they don't hop the focus to another plate")
	assert_eq(r.f1, [r.f1_want], "F1 with the focus on a plate opens its codex entry")
	assert_eq(String(r.enter_selected), String(r.tab_focus), "Enter selects the focused plate's province")
	assert_true(bool(r.released_tip_hidden), "the focus tip goes with the focus")
	assert_false(String(r.mouse_plate).is_empty(), "a plate is the control under the mouse")
	assert_true(bool(r.mouse_tip_is_plates) and bool(r.mouse_tip_names_province), "its hover is the plate's own tooltip")
	assert_true(bool(r.mouse_detail), "the mouse over a plate opens its detail")
	assert_eq(r.right_click, [r.right_click_want], "a right-click on it opens its codex entry")
	assert_true(bool(r.mouse_left_closes), "and the detail closes when the mouse leaves")
	assert_true(bool(r.left_click_releases_focus), "a left click leaves the keyboard focus out of it")
