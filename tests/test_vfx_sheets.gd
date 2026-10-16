extends "res://tests/test_case.gd"
## VFX-WIRE (#242; design/STYLE_BIBLE.md §4.2): the effect sheets on the stage, the Simple view and the board, against fixture sheets this
## file writes to user:// (the real ones land in lane Art's install PR; their .json follows the same schema):
## - each moment picks its sheet, and each code mark a sheet replaces maps to one;
## - a missing sheet falls back to the code effect (the impact star, the spell marks), and a sheet-only entry draws nothing;
## - the frame timing comes from the sheet's .json (fps, frames, hit_frame, loop), and an impact's hit_frame meets its blow;
## - no effect uses an additive blend;
## - ground effects take their unit's facing, derived from the unit (the stage's figures), not hardcoded;
## - a fallen ruler's sheet bursts from its model's staff head, not the figure's middle.

const BFx := preload("res://tests/battle_playback_fixtures.gd")
const SpellFx := preload("res://world3d/spell_fx.gd")
const SpellPlan := preload("res://world3d/spell_plan.gd")
const Models := preload("res://world3d/models.gd")
const FIXTURE := "user://vfx_fixture"
const EMPTY := "user://vfx_fixture_empty"
## The fixture sheets' timing: one-shots and loops, each a 4 x 2 grid of 16 px cells.
const ONE_SHOT := {"frames": 8, "columns": 4, "frame_size": [16, 16], "fps": 10, "hit_frame": 3}
const LOOP := {"frames": 8, "columns": 4, "frame_size": [16, 16], "fps": 8, "loop": [1, 6]}

var _root := ""


func _write_fixture() -> void:
	_root = VfxSheets.root
	for id in VfxSheets.IDS:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [FIXTURE, id])
		var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0.8, 0.3, 0.9))
		img.save_png("%s/%s/%s.png" % [FIXTURE, id, id])
		var meta: Dictionary = LOOP if VfxSheets.LOOPS.has(id) else ONE_SHOT
		var f := FileAccess.open("%s/%s/%s.json" % [FIXTURE, id, id], FileAccess.WRITE)
		f.store_string(JSON.stringify(meta))
		f.close()
	DirAccess.make_dir_recursive_absolute(EMPTY)
	VfxSheets.root = FIXTURE
	VfxSheets.clear_cache()


func _restore() -> void:
	VfxSheets.root = _root if not _root.is_empty() else "res://assets/vfx"
	VfxSheets.clear_cache()


func _use(root: String) -> void:
	VfxSheets.root = root
	VfxSheets.clear_cache()


func test_each_moment_picks_its_sheet() -> void:
	for moment in VfxSheets.MOMENTS:
		assert_true(VfxSheets.IDS.has(VfxSheets.for_moment(moment)), "%s plays one of the sheets" % moment)
	for k in VfxSheets.ELEMENTS:
		assert_true(VfxSheets.IDS.has(String(VfxSheets.ELEMENTS[k])), "the %s mark is a sheet's placeholder" % k)
	assert_eq(BattleEffects.impact_sheet({}), "hit_impact", "a hit")
	assert_eq(BattleEffects.impact_sheet({"big": true}), "big_impact", "a big hit")
	assert_eq(BattleEffects.impact_sheet({"first_charge": true}), "big_impact", "a Charge's first hit")
	assert_false(VfxSheets.IDS.has("dust_puff"), "dust_puff is held: the code puffs stay")
	for id in VfxSheets.GROUND:
		assert_true(VfxSheets.IDS.has(id))
	assert_eq(VfxSheets.GROUND, ["briar_burst", "summon_ring", "cast_channel"], "the rings, channels and bursts lie on the ground")


func test_frame_timing_comes_from_the_sheets_json() -> void:
	_write_fixture()
	var s := VfxSheets.sheet("hit_impact")
	assert_false(s.is_empty(), "the fixture sheet loads")
	assert_eq(int(s.frames), int(ONE_SHOT.frames))
	assert_eq(float(s.fps), float(ONE_SHOT.fps))
	assert_true(is_equal_approx(VfxSheets.lead(s), float(ONE_SHOT.hit_frame) / float(ONE_SHOT.fps)), "the lead-in is hit_frame / fps")
	assert_true(is_equal_approx(VfxSheets.life(s), float(ONE_SHOT.frames) / float(ONE_SHOT.fps)), "a one-shot lasts frames / fps")
	for i in int(ONE_SHOT.frames):
		assert_eq(VfxSheets.frame_at(s, (i + 0.5) / float(ONE_SHOT.fps)), i, "frame %d at its time" % i)
	assert_eq(VfxSheets.frame_at(s, VfxSheets.life(s) + 0.01), -1, "a one-shot plays once")
	assert_eq(VfxSheets.frame_at(s, -0.01), -1, "and not before it starts")
	assert_eq(VfxSheets.region(s, 5), Rect2(16, 16, 16, 16), "frame 5 is the second row's second cell")
	var loop := VfxSheets.sheet("cast_channel")
	var span: Array = LOOP.loop
	var n := int(span[1]) - int(span[0]) + 1
	for i in n * 2:
		assert_eq(VfxSheets.frame_at(loop, (i + 0.5) / float(LOOP.fps)), int(span[0]) + i % n, "a loop plays its loop frames, over and over")
	_restore()


func test_an_impact_meets_its_blow_and_a_missing_sheet_leaves_the_code_star() -> void:
	_write_fixture()
	var fx := BattleEffects.new()
	var s := VfxSheets.sheet("hit_impact")
	var delay := 0.5
	assert_true(fx.add_impact(Vector2(10, 10), 1.0, false, true, false, "hit_impact", VfxSheets.lead(s) - delay))
	var it: Dictionary = fx.impacts.items[0]
	assert_eq(String(it.sheet), "hit_impact", "the impact plays its sheet")
	assert_true(is_equal_approx(float(it.life), VfxSheets.life(s)), "for the sheet's length")
	fx.step(delay)
	assert_eq(VfxSheets.frame_at(s, float(it.age)), int(s.hit_frame), "its hit_frame shows when the blow lands, %ss after it started" % delay)
	# A ring (reduced motion) never plays a sheet.
	fx.add_impact(Vector2.ZERO, 1.0, false, false, true, "hit_impact", 0.0)
	assert_false((fx.impacts.items[1] as Dictionary).has("sheet"))
	fx.free()
	_use(EMPTY)
	var plain := BattleEffects.new()
	plain.add_impact(Vector2(10, 10), 1.0, false, true, false, "hit_impact", -0.3)
	var p: Dictionary = plain.impacts.items[0]
	assert_false(p.has("sheet"), "no sheet: the code star")
	assert_eq(float(p.life), BattleEffects.IMPACT_LIFE)
	assert_eq(float(p.age), 0.0, "starting with its blow, as today")
	plain.free()
	_restore()


func test_spell_marks_play_their_sheets_or_today_s_code_marks() -> void:
	var c := {"foot": Vector3(0, 0, 0), "head": Vector3(0, 6, 0), "r": 3.0, "yaw": 0.4}
	var t := {"foot": Vector3(20, 0, 0), "head": Vector3(20, 6, 0), "r": 3.0, "yaw": 2.0}
	var plan := SpellPlan.battle("sunlance", 0, {"caster": c, "target": t, "targets": [t], "damage": 5})
	var burst: Dictionary = {}
	for e in plan.elements:
		if String(e.k) == "burst":
			burst = e
	assert_false(burst.is_empty(), "Sunlance's hit has its burst mark")
	_write_fixture()
	var s := VfxSheets.sheet("sun_flare")
	var m := SpellFx.sheet_mark("sun_flare", burst, float(burst.t0), true, 0)
	assert_eq(int(m.frame), int(s.hit_frame), "the flare's hit_frame on the burst's start")
	var fx := SpellFx.new()
	fx.play(plan.duplicate(true))
	fx.step(float(burst.t0))
	var with_sheets: Dictionary = fx.stats()
	assert_true(int(with_sheets.sheets) > 0, "the sheets draw: %s" % with_sheets)
	fx.free()
	_use(EMPTY)
	assert_eq(SpellFx.sheet_mark("sun_flare", burst, float(burst.t0), true, 0), {}, "no sheet: the code mark draws")
	var plain := SpellFx.new()
	plain.play(plan.duplicate(true))
	plain.step(float(burst.t0))
	var without: Dictionary = plain.stats()
	assert_eq(int(without.sheets), 0, "no sheets drawn without their files")
	assert_true(int(without.sprites) > int(with_sheets.sprites), "the burst is today's code sprite again (%d against %d)" % [without.sprites, with_sheets.sprites])
	plain.free()
	_restore()


func test_no_effect_uses_an_additive_blend() -> void:
	var shader := FileAccess.get_file_as_string("res://world3d/shaders/vfx_sheet.gdshader")
	assert_true(shader.contains("blend_mix"), "the sheet shader blends with the sheet's own alpha")
	for path in ["res://world3d/shaders/vfx_sheet.gdshader", "res://world3d/shaders/spell_fx_top.gdshader", "res://world3d/shaders/spell_fx_ground.gdshader",
			"res://world3d/vfx_sheets.gd", "res://world3d/spell_fx.gd", "res://ui/battle/battle_effects.gd", "res://world3d/battle_stage.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s reads" % path)
		for banned in ["blend_add", "BLEND_MODE_ADD", "BLEND_ADD"]:
			assert_false(text.contains(banned), "%s never blends additively (%s)" % [path, banned])


func test_ground_effects_take_their_units_facing() -> void:
	_write_fixture()
	for yaws in [[0.4, 2.0], [-1.1, 0.25]]:
		var c := {"foot": Vector3(0, 0, 0), "head": Vector3(0, 6, 0), "r": 3.0, "yaw": float(yaws[0])}
		var t := {"foot": Vector3(20, 0, 0), "head": Vector3(20, 6, 0), "r": 3.0, "yaw": float(yaws[1])}
		var plan := SpellPlan.battle("briar_snare", 0, {"caster": c, "targets": [t], "target": t, "life": 2.0})
		var by := {}
		for e in plan.sheets:
			by[String(e.sheet)] = e
		assert_true(is_equal_approx(float(by["cast_channel"].yaw), float(yaws[0])), "the channel turns with its caster (%s)" % yaws[0])
		assert_true(is_equal_approx(float(by["briar_burst"].yaw), float(yaws[1])), "the briars with the fighter they snare (%s)" % yaws[1])
		var m := SpellFx.sheet_mark("cast_channel", by["cast_channel"], 0.5, false, 0)
		assert_true(bool(m.ground) and is_equal_approx(float(m.yaw), float(yaws[0])), "laid on the ground, turned to that facing")
	var ring := SpellPlan.board("summoned", 0, {"at": Vector3(5, 0, 5), "r": 8.0, "school": "wild", "yaw": 1.3})
	var sr: Dictionary = {}
	for e in ring.elements:
		if String(e.k) == "summon_ring":
			sr = e
	assert_true(is_equal_approx(float(sr.yaw), 1.3), "a summoning ring on the board turns with its summons")
	# On the stage the facing is the figure's own (BattleStage3D._spell_ends), never a constant.
	var fx := BFx.battle("king_falls_wins")
	var stage := BattleStage3D.new()
	stage.controls.remember = false
	assert_eq(stage.show_battle(fx.log, fx.report), "")
	var checked := 0
	var yaws_seen := {}
	for f in stage.figures.figs:
		if int(f.fid) < 0:
			continue
		var ends: Dictionary = stage._spell_ends(int(f.fid))
		assert_true(is_equal_approx(float(ends.yaw), float(f.yaw)), "fighter %d's effects face as its figure does" % int(f.fid))
		yaws_seen[snappedf(float(f.yaw), 0.01)] = true
		checked += 1
	assert_true(checked > 0 and yaws_seen.size() >= 2, "both sides' facings were read (%d figures, %d facings)" % [checked, yaws_seen.size()])
	stage.free()
	_restore()


func test_a_fallen_rulers_sheet_bursts_from_its_staff() -> void:
	var top := Models.fx_top("ever_regent")
	var aabb: AABB = (Models.figure_mesh("ever_regent", true, "ready").mesh as Mesh).get_aabb()
	assert_true(top.y >= aabb.end.y * (1.0 - Models.FX_TOP_BAND) - 0.01, "at the model's top (%s of %s)" % [top.y, aabb.end.y])
	var side := Vector2(top.x - aabb.get_center().x, top.z - aabb.get_center().z).length()
	assert_true(side > aabb.size.y * 0.1, "off the figure's middle, at the staff's head (%.2f to the side of %.2f)" % [side, aabb.size.y])
	var fx := BFx.battle("king_falls_wins")
	var stage := BattleStage3D.new()
	stage.controls.remember = false
	assert_eq(stage.show_battle(fx.log, fx.report), "")
	for f in stage.figures.figs:
		if int(f.fid) < 0 or not Models.is_ruler(String(f.type)):
			continue
		var p: Vector2 = f.home
		var want := Vector3(p.x, float(f.y), p.y) + Basis(Vector3.UP, float(f.yaw)) * Models.fx_top(String(f.type))
		assert_true(stage.staff_head(int(f.fid)).is_equal_approx(want), "%s's fall bursts from its staff, turned with it" % f.type)
	stage.free()
