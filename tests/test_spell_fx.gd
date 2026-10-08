extends "res://tests/test_case.gd"
## M5-9, "Magic in 3D" (#120; design/M5_MAGIC_FOG.md §12.2, §12.3, §15.3; design/3D_DIRECTION.md §3.4): the spell and ritual effects of
## the 3D battle stage and the 3D board, headless. Nothing renders, but every plan, pool, limiter and beat is computed exactly as the
## windowed game runs them.
##   * every battle spell and every cast kind, every map event and every enchantment has a beat on every rung of the quality ladder
##     (thinned, never dropped), with reduced motion too; the ladder thins as the spec's table says
##   * effects never change the state (the game, the log, the report stand as they were), and the new files use no random numbers and
##     read no truth accessor
##   * a full pool skips a new effect (it is not queued); the flash limiter counts Sunburst; a bright mark never stays above 80% once
##     the limiter said no or after two frames; reduced motion plays every effect as a still mark with no flash and no shake
##   * on the stage: each cast beat plays its effect with the spell's name over the caster, hexes and shields last the round and a
##     seek leaves them standing, the Blood Moon's heal has its motes, Sunburst shakes within M3's limits
##   * on the board: a turn's ritual beats and enchantment beats all play (each event of §12.3), in the rituals and enchantments
##     phases; a ritual from a caster the viewer can't see arrives at its target with no direction; the enchantments' decals follow the
##     state; Bastion's fort stands from the state
##   * the four new figures have rows and pass the silhouette gate; the legend explains each spell
## Expected values come from the data and the plans, never hardcoded.

const SpellPlan := preload("res://world3d/spell_plan.gd")
const SpellFx := preload("res://world3d/spell_fx.gd")
const MagicBeats := preload("res://world3d/magic_beats.gd")
const EnchantDecals := preload("res://world3d/enchant_decals.gd")
const Playback := preload("res://world3d/playback.gd")
const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const Choreo := preload("res://world3d/choreo.gd")
const W3D := preload("res://world3d/battle_watch3d.gd")
const MSF := preload("res://tests/magic_stage_fixtures.gd")
const MB := preload("res://tests/magic_battle_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const STEP := 1.0 / 60.0
const BOARD_SIZE := Vector2(1200, 836)
const CPU_AVG_MS := 2.0
const CPU_MAX_MS := 4.0
const NEW_FILES := ["res://world3d/spell_plan.gd", "res://world3d/spell_fx.gd", "res://world3d/battle_spells.gd", "res://world3d/enchant_decals.gd",
	"res://world3d/magic_beats.gd", "res://world3d/spell_figures.gd", "res://world3d/shaders/spell_fx.gdshaderinc", "res://world3d/shaders/spell_fx_ground.gdshader",
	"res://world3d/shaders/spell_fx_top.gdshader"]
## M5-3's truth accessors (design §2.1): nothing in world3d/ may call them.
const TRUTH := ["state", "turn_report", "battle_events", "builds", "record", "history", "victory"]


# --- fixtures ----------------------------------------------------------------------------------------------

func _fighter(x: float, z: float) -> Dictionary:
	return {"foot": Vector3(x, 0, z), "head": Vector3(x, 6, z), "r": 3.2}


## Arguments every battle effect can read: a caster, a target, six targets in a front, a round to last, a side colour.
func _battle_args() -> Dictionary:
	var ts := []
	for i in 6:
		ts.append(_fighter(40.0 + 4.0 * (i % 3), 4.0 * i))
	return {"caster": _fighter(0, 0), "target": ts[0], "targets": ts, "col": Color("#D84427"), "life": 3.0, "name": "Spell", "damage": 4,
		"part": {"stat": "attack", "value": -2}, "self": 2, "reach": 50.0, "fighters": [{"foot": Vector3(0, 0, 0), "head": Vector3(0, 6, 0), "healed": 3}]}


## Arguments every map effect can read: a target, a visible caster, a road, two armies, a school.
func _board_args(school: String = "blood") -> Dictionary:
	return {"at": Vector3(100, 0, 100), "from": Vector3(0, 0, 0), "path": PackedVector3Array([Vector3(0, 2, 0), Vector3(50, 2, 50), Vector3(100, 2, 100)]),
		"r": 40.0, "school": school, "col": Color("#D84427"), "armies": [{"at": Vector3(100, 0, 100), "r": 10.0}, {"at": Vector3(120, 0, 90), "r": 8.0}],
		"ekind": "curse", "rkind": "curse", "map": Vector3(500, 0, 300), "height": 16.0, "global": false}


## Every event type of a plan's elements by kind.
func _kinds(plan: Dictionary) -> Dictionary:
	var out := {}
	for e in plan["elements"]:
		out[e["k"]] = int(out.get(e["k"], 0)) + 1
	return out


func _count(plan: Dictionary, kinds: Array) -> int:
	var k := _kinds(plan)
	var n := 0
	for kind in kinds:
		n += int(k.get(kind, 0))
	return n


# --- every effect on every rung -----------------------------------------------------------------------------

func test_every_battle_spell_and_cast_kind_has_a_beat_on_every_rung() -> void:
	var args := _battle_args()
	# every battle effect, every rung, still or moving: something is drawn or said, and the 3D marks thin as the rung rises
	for effect in SpellPlan.BATTLE_EFFECTS:
		var last := 1 << 30
		for rung in SpellPlan.RUNGS:
			for reduced in [false, true]:
				var p := SpellPlan.battle(effect, rung, args, reduced)
				assert_true(SpellPlan.has_beat(p), "%s has a beat on rung %d (reduced motion %s)" % [effect, rung, reduced])
				if effect != "heal_back":
					assert_true(SpellPlan.size(p) >= 1, "%s still draws a mark on rung %d (reduced %s)" % [effect, rung, reduced])
			var n := SpellPlan.size(SpellPlan.battle(effect, rung, args, false))
			assert_true(n <= last, "%s: rung %d draws %d marks, no more than rung %d's %d (thinned, never grown)" % [effect, rung, n, rung - 1, last])
			last = n
	# every spell the data says is a battle spell, and every kind of cast, has an effect
	for id in MagicData.SPELLS:
		var row: Dictionary = MagicData.SPELLS[id]
		if bool(row.battle):
			assert_true(SpellPlan.BATTLE_EFFECTS.has(SpellPlan.effect_of(String(row.kind), String(id))), "%s (%s) has an effect" % [id, row.kind])
	for kind in MagicData.BATTLE_KINDS:
		assert_true(SpellPlan.BATTLE_EFFECTS.has(SpellPlan.effect_of(String(kind), "")), "the %s cast kind has an effect" % kind)
	# and every cast of every battle the stage's fixtures fight, on every rung, becomes a plan with marks to draw
	var seen := {}
	for name in ["magic_all", "magic_snare", "magic_bloodbolt", "magic_moon"]:
		var fx := MSF.battle(name)
		var player := BattlePlayer.new(fx.log, fx.report)
		for b in player.beats():
			if String(b.kind) != "cast":
				continue
			for rung in SpellPlan.RUNGS:
				var ctx := {"ends": func(_fid): return _fighter(float(_fid), 0.0), "col": Color.WHITE, "life": 2.0, "rung": rung, "reduced": false, "log": fx.log}
				var p := BattleSpells.plan_for_beat(b, ctx)
				assert_false(p.is_empty(), "%s: the %s cast has a plan on rung %d" % [name, b.data.spell, rung])
				assert_true(SpellPlan.size(p) >= 1, "%s: and it draws marks on rung %d" % [name, rung])
				seen[String(b.data.spell)] = true
	for spell in ["sunburst", "sunlance", "shield_of_law", "briar_snare", "bloodbolt"]:
		assert_true(seen.has(spell), "the fixtures cast %s" % spell)


func test_every_map_event_and_enchantment_has_a_beat_on_every_rung() -> void:
	var args := _board_args()
	for key in SpellPlan.BOARD_KEYS:
		var last := 1 << 30
		for rung in SpellPlan.RUNGS:
			for reduced in [false, true]:
				var p := SpellPlan.board(key, rung, args, reduced)
				assert_true(SpellPlan.size(p) >= 1, "%s draws a mark on rung %d (reduced motion %s)" % [key, rung, reduced])
			var n := SpellPlan.size(SpellPlan.board(key, rung, args, false))
			assert_true(n <= last, "%s: rung %d draws %d marks, no more than rung %d's %d" % [key, rung, n, rung - 1, last])
			last = n
	for kind in SpellPlan.STANDING_KINDS:
		for rung in SpellPlan.RUNGS:
			for reduced in [false, true]:
				var els := SpellPlan.standing(kind, rung, {"at": Vector3(10, 0, 10), "r": 40.0, "armies": [{"at": Vector3(5, 0, 5), "r": 9.0}]}, reduced)
				assert_false(els.is_empty(), "a standing %s is drawn on rung %d (reduced %s)" % [kind, rung, reduced])
	# every event §12.3 lists is a beat the playback plans, split by the cast's ritual kind, and every kind of ritual has its cast
	assert_eq(Array(Playback.RITUAL_EVENTS), SpellPlan.EARLY_EVENTS + SpellPlan.LATE_EVENTS, "the playback plans exactly the events the effects know")
	for t in Playback.RITUAL_EVENTS:
		assert_true(SpellPlan.BOARD_KEYS.has(SpellPlan.board_key({"kind": t, "rkind": "ward"})), "%s has a board effect" % t)
	for kind in MagicData.RITUAL_KINDS:
		assert_true(SpellPlan.BOARD_KEYS.has("cast:" + String(kind)), "a %s ritual's cast has an effect" % kind)
	for id in MagicData.SPELLS:
		var row: Dictionary = MagicData.SPELLS[id]
		if not bool(row.battle):
			var key := SpellPlan.board_key({"kind": "ritual_cast", "rkind": SpellPlan.rkind_of(String(id))})
			assert_true(SpellPlan.BOARD_KEYS.has(key), "%s (%s) casts with %s" % [id, row.kind, key])
			assert_true(SpellPlan.SCHOOL_COLOURS.has(SpellPlan.school_of(String(id))), "%s has a school's colours" % id)


func test_the_ladder_thins_effects_the_way_the_spec_says() -> void:
	var args := _battle_args()
	# bolts (§12.2): beam, trail and glow on rung 0-1; no glow on 2; no trail on 3; a straight line on 4-5, its impact sheet half size
	for effect in ["sunlance", "bloodbolt"]:
		var sheet := []
		for rung in SpellPlan.RUNGS:
			var p := SpellPlan.battle(effect, rung, args, false)
			var beams: Array = p["elements"].filter(func(e): return e["k"] == "beam")
			var trails := beams.filter(func(e): return float(e["w"]) == 3.0)
			var cores := beams.filter(func(e): return float(e["w"]) != 3.0)
			assert_eq(cores.size(), 1, "%s rung %d: one beam" % [effect, rung])
			assert_eq(trails.size(), 1 if rung <= 2 else 0, "%s rung %d: the trail is on rung 0-2" % [effect, rung])
			assert_eq(_count(p, ["glow"]) > 0, rung <= 1, "%s rung %d: the glow is on rung 0-1" % [effect, rung])
			assert_eq(int(cores[0]["w"]), 0 if rung <= 2 else (1 if rung == 3 else 2), "%s rung %d: full beam, plain beam, then a straight line" % [effect, rung])
			var impact: Array = p["elements"].filter(func(e): return e["k"] in ["burst", "blood_spray"])
			assert_eq(impact.size(), 1, "%s rung %d: an impact sheet" % [effect, rung])
			sheet.append(float(impact[0]["r"]))
		assert_eq([sheet[0], sheet[1], sheet[2], sheet[3]], [sheet[0], sheet[0], sheet[0], sheet[0]], "%s: the impact sheet is full size to rung 3" % effect)
		assert_true(is_equal_approx(sheet[4], sheet[0] * 0.5) and is_equal_approx(sheet[5], sheet[0] * 0.5), "%s: and half size on rung 4-5" % effect)
	# Briar Snare: a ring under each target on every rung; vines and briars to rung 2, one briar to rung 3; 32, 16 then no particles
	var n: int = (args["targets"] as Array).size()
	var particles := [32, 32, 16, 0, 0, 0]
	for rung in SpellPlan.RUNGS:
		var p2 := SpellPlan.battle("briar_snare", rung, args, false)
		assert_eq(_count(p2, ["thorn_ring"]), n, "Briar Snare rung %d: a thorn ring under each target" % rung)
		assert_eq(_count(p2, ["vine"]), 2 * n if rung <= 2 else 0, "rung %d: vines on rung 0-2" % rung)
		assert_eq(_count(p2, ["briar"]), n if rung <= 3 else 0, "rung %d: a billboard briar on rung 0-3" % rung)
		assert_eq(_count(p2, ["mote", "leaf"]), particles[rung], "rung %d: %d particles" % [rung, particles[rung]])
	# Shield of Law: a translucent shield quad on rung 0-3, its rim pulsing on 0-2; a triangle decal under each from rung 4
	for rung in SpellPlan.RUNGS:
		var p3 := SpellPlan.battle("shield_of_law", rung, args, false)
		assert_eq(_count(p3, ["shield"]), n if rung <= 3 else 0, "Shield of Law rung %d: quads on rung 0-3" % rung)
		assert_eq(_count(p3, ["tri"]), n if rung >= 4 else 0, "rung %d: a ▲ decal from rung 4" % rung)
		for e in p3["elements"]:
			if e["k"] == "shield":
				assert_eq(float(e["w"]) > 0.5, rung <= 2, "rung %d: the rim pulses on rung 0-2 only" % rung)
	# Sunburst: the glare ring on every rung, the flare to rung 3, the bloom on 0-1, the shake on 0-2; Sunburst counts as a flash to rung 3
	for rung in SpellPlan.RUNGS:
		var p4 := SpellPlan.battle("sunburst", rung, args, false)
		assert_eq(_count(p4, ["glare_ring"]), 1, "Sunburst rung %d: the glare ring" % rung)
		assert_eq(_count(p4, ["flare"]), 1 if rung <= 3 else 0, "rung %d: the flare sheet is on rung 0-3" % rung)
		var bloom: Array = p4["elements"].filter(func(e): return e["k"] == "glow" and float(e["r"]) >= 20.0)
		assert_eq(bloom.size(), 1 if rung <= 1 else 0, "rung %d: the bloom is on rung 0-1" % rung)
		assert_eq(float(p4["shake"]) > 0.0, rung <= 2, "rung %d: the 4 px shake is on rung 0-2" % rung)
		assert_eq(bool(p4["flash"]), rung <= 3, "rung %d: it asks the flash limiter on rung 0-3" % rung)
		if rung <= 2:
			assert_true(is_equal_approx(float(p4["shake"]), 4.0), "the shake is 4 px")
	# the Blood Moon's heal: 24 rising motes on rung 0-1, 12 on 2, the number alone from 3
	for rung in SpellPlan.RUNGS:
		var p5 := SpellPlan.battle("heal_back", rung, args, false)
		assert_eq(SpellPlan.size(p5), [24, 24, 12, 0, 0, 0][rung], "heal back rung %d: its motes" % rung)
		assert_eq((p5["labels"] as Array).size(), 1, "rung %d: and its green number" % rung)


func test_map_effects_thin_the_way_the_spec_says() -> void:
	var args := _board_args()
	for kind in ["blessing", "ward", "curse", "summon", "raising"]:
		var kinds := {"blessing": "sun", "ward": "law", "curse": "blood", "summon": "wild", "raising": "law"}
		args["school"] = kinds[kind]
		for rung in SpellPlan.RUNGS:
			var p := SpellPlan.board("cast:" + kind, rung, args, false)
			var has_beam: bool = _count(p, ["column"]) > 0
			var has_mote: bool = p["elements"].any(func(e): return e.has("path"))
			assert_eq(has_mote, rung <= 2, "%s cast rung %d: the mote along the roads is on rung 0-2" % [kind, rung])
			assert_eq(has_beam, rung <= 3, "rung %d: the beam at a visible caster is on rung 0-3" % rung)
			if rung >= 4:
				assert_eq(SpellPlan.counts(p)["sprites"] + SpellPlan.counts(p)["beams"], 0, "rung %d: the decal alone" % rung)
				assert_true(SpellPlan.counts(p)["ground"] >= 1, "rung %d: the decal is there" % rung)
		# a caster the viewer can't see: no beam and no road at all, whatever the rung
		var hidden := args.duplicate()
		hidden.erase("from")
		hidden.erase("path")
		for rung in SpellPlan.RUNGS:
			var p2 := SpellPlan.board("cast:" + kind, rung, hidden, false)
			assert_false(p2["elements"].any(func(e): return e.has("path") or (e["k"] == "column" and (e["at"] as Vector3).distance_to(Vector3.ZERO) < 1.0)),
				"%s from a hidden caster, rung %d: nothing starts anywhere but the target" % [kind, rung])
	# standing decals: animated on rung 0-1, still from rung 2
	for kind in SpellPlan.STANDING_KINDS:
		for rung in SpellPlan.RUNGS:
			for e in SpellPlan.standing(kind, rung, {"at": Vector3.ZERO, "r": 40.0, "armies": [{"at": Vector3.ZERO, "r": 9.0}]}, false):
				if e["k"] != "ring":
					assert_eq(float(e["w"]) > 0.5, rung <= 1, "a standing %s, rung %d: animated only on rung 0-1" % [kind, rung])
	# a summoning's ring and a raised fort: fade in (rung 3), pop in (rung 4-5)
	for key in ["summoned", "fort_raised"]:
		var fins := []
		for rung in SpellPlan.RUNGS:
			var ring: Array = SpellPlan.board(key, rung, args, false)["elements"].filter(func(e): return e["k"] in ["summon_ring", "dust_ring"])
			assert_eq(ring.size(), 1, "%s rung %d: its ring" % [key, rung])
			fins.append(float(ring[0]["fin"]))
		assert_true(fins[0] > fins[3] and fins[3] > fins[4], "%s: a ring that rises slowly, fades in on rung 3 and pops in from rung 4" % key)
		assert_eq(fins[4], fins[5], "%s: pops in on rung 4 and 5 alike" % key)


# --- reduced motion -------------------------------------------------------------------------------------------

func test_reduced_motion_plays_every_effect_as_a_still_mark() -> void:
	var plans := []
	for effect in SpellPlan.BATTLE_EFFECTS:
		for rung in SpellPlan.RUNGS:
			plans.append(SpellPlan.battle(effect, rung, _battle_args(), true))
	for key in SpellPlan.BOARD_KEYS:
		for rung in SpellPlan.RUNGS:
			plans.append(SpellPlan.board(key, rung, _board_args(), true))
	for p in plans:
		var what := "%s rung %d" % [p["effect"], p["rung"]]
		assert_eq(float(p["shake"]), 0.0, "%s: no shake" % what)
		assert_false(bool(p["flash"]), "%s: no flash" % what)
		for e in p["elements"]:
			assert_false(e["k"] in ["mote", "leaf"], "%s: no particles (%s)" % [what, e["k"]])
			assert_eq(float(e["up"]), 0.0, "%s: nothing rises (%s)" % [what, e["k"]])
			if not (e["k"] in ["beam", "column"]): ## a beam's variant is its look, not an animation
				assert_eq(float(e["w"]), 0.0, "%s: nothing pulses or turns (%s)" % [what, e["k"]])
			assert_false(e.has("path"), "%s: no mote runs the road" % what)
			assert_eq(float(e.get("head", 0.0)), 0.0, "%s: a beam is there at once" % what)
			if e.has("r0"):
				assert_eq(float(e["r0"]), float(e["r"]), "%s: a ring does not sweep (%s)" % [what, e["k"]])
	for kind in SpellPlan.STANDING_KINDS:
		for e in SpellPlan.standing(kind, 0, {"at": Vector3.ZERO, "r": 40.0, "armies": [{"at": Vector3.ZERO, "r": 9.0}]}, true):
			assert_eq(float(e["w"]), 0.0, "a standing %s is still with reduced motion" % kind)


# --- pool and flash limiter ---------------------------------------------------------------------------------

func test_a_full_pool_skips_a_new_effect_it_does_not_queue_it() -> void:
	var fx := SpellFx.new()
	var args := _battle_args()
	for i in SpellPlan.POOL_CAP:
		var got := fx.play(SpellPlan.battle("sunlance", 0, args, false), 0.0)
		assert_false(got.has("skipped"), "effect %d of %d is taken" % [i + 1, SpellPlan.POOL_CAP])
	assert_eq(fx.stats()["alive"], SpellPlan.POOL_CAP, "the pool holds 32 effects")
	var over := fx.play(SpellPlan.battle("sunlance", 0, args, false), 0.0)
	assert_true(bool(over.get("skipped", false)), "the 33rd is skipped")
	assert_true((over["elements"] as Array).is_empty() and (over["labels"] as Array).is_empty(), "a skipped effect draws and says nothing")
	assert_eq(fx.stats()["alive"], SpellPlan.POOL_CAP, "the pool is still full")
	assert_eq(fx.stats()["skipped"], 1, "one skip is counted")
	assert_eq(float(over["shake"]), 0.0, "and it shakes nothing")
	# not queued: once the pool empties the skipped effect does not turn up
	fx.step(10.0)
	assert_eq(fx.stats()["alive"], 0, "every effect ran its course")
	fx.step(0.1)
	assert_eq(fx.stats()["alive"], 0, "and the skipped one never comes")
	assert_false(fx.play(SpellPlan.battle("sunlance", 0, args, false), 0.0).has("skipped"), "an empty pool takes a new effect again")
	# the draw calls stay at three layers however many effects are alive
	var layers := 0
	for c in fx.get_children():
		if c is MultiMeshInstance3D:
			layers += 1
	assert_eq(layers, 3, "spells cost three draw calls (ground decals, sprites, beams), far under the 150 allowed")
	fx.free()


func test_the_flash_limiter_counts_sunburst() -> void:
	var lim := BattleFx.FlashLimiter.new()
	var fx := SpellFx.new()
	fx.flash = lim
	var args := _battle_args()
	var sunburst := SpellPlan.battle("sunburst", 0, args, false)
	assert_true(bool(sunburst["flash"]), "Sunburst asks the flash limiter")
	var got := fx.play(sunburst, 5.0)
	assert_eq(lim.count(5.0), 1, "Sunburst counts as a flash")
	assert_true(bool(got["bright"]), "and the first flash is allowed")
	# two more flashes in the same second fill the window (3 a second), the next is refused: it plays without bright frames
	fx.play(SpellPlan.battle("sunburst", 0, args, false), 5.1)
	fx.play(SpellPlan.battle("sunlance", 0, args, false), 5.2)
	assert_eq(lim.count(5.3), 3, "three flashes in a second")
	var refused := fx.play(SpellPlan.battle("sunburst", 0, args, false), 5.3)
	assert_false(bool(refused["bright"]), "the fourth in the same second plays without bright frames")
	assert_eq(fx.stats()["flashes_refused"], 1, "one refusal is counted")
	assert_eq(lim.count(5.3), 3, "and the limiter still holds three")
	assert_true(_count(refused, ["glare_ring"]) == 1 and _count(refused, ["flare"]) == 1, "a refused Sunburst is still a ring and a flare, never dropped")
	for e in refused["elements"]:
		if bool(e["bright"]):
			var m := SpellFx.mark(e, float(e["t0"]) + 0.2 * float(e["dur"]), false, 1)
			assert_true(float(m["alpha"]) <= SpellFx.BRIGHT_CAP + 0.0001, "a bright %s the limiter refused stays at or under 80%%" % e["k"])
	# a second later the window has cleared and a flash is allowed again
	assert_true(bool(fx.play(SpellPlan.battle("sunburst", 0, args, false), 6.4)["bright"]), "a flash is allowed again once the window has passed")
	# an allowed bright mark may rise above 80% for at most BRIGHT_FRAMES real frames
	var flare: Dictionary = {}
	for e in sunburst["elements"]:
		if e["k"] == "flare":
			flare = e
	var mid := float(flare["t0"]) + float(flare["fin"]) + 0.01
	assert_true(float(SpellFx.mark(flare, mid, true, 1)["alpha"]) > SpellFx.BRIGHT_CAP, "the flare is above 80% while its bright frames last")
	assert_true(float(SpellFx.mark(flare, mid, true, BattleFx.BRIGHT_FRAMES)["alpha"]) > SpellFx.BRIGHT_CAP, "up to the second frame")
	assert_true(float(SpellFx.mark(flare, mid, true, BattleFx.BRIGHT_FRAMES + 1)["alpha"]) <= SpellFx.BRIGHT_CAP + 0.0001, "and no longer")
	# reduced motion asks nothing of the limiter
	var fx2 := SpellFx.new()
	var lim2 := BattleFx.FlashLimiter.new()
	fx2.flash = lim2
	fx2.reduced_motion = true
	var calm := fx2.play(SpellPlan.battle("sunburst", 0, args, true), 1.0)
	assert_eq(lim2.count(1.0), 0, "reduced motion never asks to flash")
	assert_false(bool(calm["flash"]) or bool(calm["bright"]), "and plays no bright frames")
	fx.free()
	fx2.free()


# --- effects change nothing -------------------------------------------------------------------------------------

func test_effects_never_change_the_game() -> void:
	for name in MSF.NAMES:
		if name == "magic_big":
			continue
		var fx := MSF.battle(name)
		var state_before := var_to_str(fx.state.to_dict())
		var log_before := var_to_str(fx.log)
		var report_before := var_to_str(fx.report)
		var s := BattleStage3D.new()
		assert_eq(s.play(fx.log, fx.report, fx.state), "", "%s plays on the stage" % name)
		_play_out(s, 4)
		s.player.seek_round(2)
		s.tick(STEP)
		s.player.skip_to_end()
		s.tick(STEP)
		s.free()
		assert_eq(var_to_str(fx.state.to_dict()), state_before, "%s: the game state stands as it was" % name)
		assert_eq(var_to_str(fx.log), log_before, "%s: and the battle log" % name)
		assert_eq(var_to_str(fx.report), report_before, "%s: and its report" % name)


func test_the_new_files_roll_no_dice_and_read_no_truth() -> void:
	var re := RegEx.new()
	re.compile("\\.(%s)\\(\\)|\\bOBSERVER\\b|\\bGameSession\\b|\\.session\\b" % "|".join(TRUTH))
	for path in NEW_FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s can be read" % path)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf", "randi", "randomize(", "rand_from_seed", "seed(", "TurnResolver", ".end_turn(",
				".queue_order(", ".acknowledge_handoff(", "AutoBattleResolver"]:
			assert_false(text.contains(banned), "%s never uses %s" % [path, banned])
		for line in text.split("\n"):
			var code: String = line.split("##")[0].split("#")[0]
			assert_true(re.search(code) == null, "%s reads no truth accessor: %s" % [path, line.strip_edges()])
	for path in ["res://world3d/playback.gd", "res://world3d/choreo.gd", "res://world3d/kit.gd"]:
		var text2 := FileAccess.get_file_as_string(path)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf(", "randi(", "randomize("]:
			assert_false(text2.contains(banned), "%s (edited for magic) never uses %s" % [path, banned])


# --- the stage ----------------------------------------------------------------------------------------------------

func _stage(name: String, reduced := false) -> BattleStage3D:
	var fx := MSF.battle(name)
	var s := BattleStage3D.new()
	s.reduced_motion = reduced
	assert_eq(s.play(fx.log, fx.report, fx.state), "", "%s plays" % name)
	return s


func _play_out(s: BattleStage3D, speed: int) -> int:
	s.player.set_speed(speed)
	s.player.play()
	var frames := 0
	while not s.player.is_finished() and frames < 100000:
		s.tick(STEP)
		frames += 1
	for k in 150:
		s.tick(STEP)
	return frames


## Fires beat `b` (and those sharing its time) from a seek just before it, as the stage tests do.
func _fire(s: BattleStage3D, b: Dictionary) -> void:
	s.player.seek_beat(int(b.i))
	s.player.play()
	s.tick(0.0001)
	s.player.pause()


## Fires beat `b` and lets `seconds` of playback pass, then pauses: the marks that start a moment after the cast are up.
func _fire_for(s: BattleStage3D, b: Dictionary, seconds: float) -> void:
	s.player.seek_beat(int(b.i))
	s.player.play()
	var guard := 0
	while s.player.time() < float(b.t) + seconds and guard < 4000:
		s.tick(STEP)
		guard += 1
	s.player.pause()


func _cast_beat(s: BattleStage3D, spell: String) -> Dictionary:
	for b in s.player.beats():
		if String(b.kind) == "cast" and String(b.data.spell) == spell:
			return b
	return {}


func _words(s: BattleStage3D) -> Array:
	return s._numbers.filter(func(n): return bool(n.get("tag", false))).map(func(n): return String(n["text"]))


func test_a_cast_beat_plays_its_effect_with_the_spells_name_over_the_caster() -> void:
	var s := _stage("magic_all")
	assert_true(s.sfx != null, "the stage has its spell effects")
	for spell in ["sunburst", "sunlance", "shield_of_law", "briar_snare", "bloodbolt"]:
		var b := _cast_beat(s, spell)
		assert_false(b.is_empty(), "the battle casts %s" % spell)
		s.sfx.clear()
		s._numbers.clear()
		_fire(s, b)
		var st: Dictionary = s.sfx.stats()
		assert_true(int(st["alive"]) >= 1, "%s: an effect is alive" % spell)
		assert_true(int(st["ground"]) + int(st["sprites"]) + int(st["beams"]) >= 1, "%s: and drawing marks" % spell)
		var name := MagicRules.spell_name(spell)
		assert_true(_words(s).any(func(t): return String(t).begins_with(name)), "%s: its name is over the caster (%s)" % [spell, _words(s)])
	# a bolt draws a beam, a hex and a shield draw their marks under and before the targets
	var lance := _cast_beat(s, "sunlance")
	s.sfx.clear()
	_fire(s, lance)
	assert_true(int(s.sfx.stats()["beams"]) >= 1, "Sunlance draws a beam")
	var snare := _cast_beat(s, "briar_snare")
	s.sfx.clear()
	_fire_for(s, snare, 0.6)
	assert_true(int(s.sfx.stats()["ground"]) >= int(snare.data.targets.size()), "Briar Snare draws a ring under each target")
	s.free()


func test_the_stage_thins_its_effects_with_the_quality_ladder() -> void:
	var s := _stage("magic_all")
	s.auto_quality = false
	var drawn := []
	for q in range(0, BattleStage3D.MAX_RUNG + 1):
		s.set_quality(q)
		assert_eq(s.sfx.rung, SpellPlan.rung_of(q), "rung %d reaches the effects" % q)
		var total := 0
		for spell in ["sunburst", "sunlance", "shield_of_law", "briar_snare", "bloodbolt"]:
			s.sfx.clear()
			_fire(s, _cast_beat(s, spell))
			var st: Dictionary = s.sfx.stats()
			var n := int(st["ground"]) + int(st["sprites"]) + int(st["beams"])
			assert_true(n >= 1, "%s still draws on rung %d" % [spell, q])
			total += n
		drawn.append(total)
	for q in range(1, drawn.size()):
		assert_true(int(drawn[q]) <= int(drawn[q - 1]), "rung %d draws %d marks, no more than rung %d's %d" % [q, drawn[q], q - 1, drawn[q - 1]])
	assert_true(int(drawn[drawn.size() - 1]) < int(drawn[0]), "and the lowest rung draws less than the highest")
	s.free()


func test_sunburst_shakes_within_the_limits_and_never_with_reduced_motion() -> void:
	var s := _stage("magic_all")
	var before := s.shakes_started
	_fire(s, _cast_beat(s, "sunburst"))
	assert_eq(s.shakes_started, before + 1, "Sunburst shakes the camera once")
	assert_eq(float(s._shake_cam.get("amp", 0.0)), 4.0, "by 4 px")
	assert_true(float(s._shake_cam.get("dur", 1.0)) <= 0.25, "briefly")
	s.free()
	var calm := _stage("magic_all", true)
	_fire(calm, _cast_beat(calm, "sunburst"))
	assert_eq(calm.shakes_started, 0, "no shake with reduced motion")
	assert_true(int(calm.sfx.stats()["alive"]) >= 1, "but Sunburst still plays, as a still ring")
	assert_eq(calm.sfx.flashes_asked, 0, "and asks for no flash")
	calm.free()
	var low := _stage("magic_all")
	low.auto_quality = false
	low.set_quality(3)
	_fire(low, _cast_beat(low, "sunburst"))
	assert_eq(low.shakes_started, 0, "no shake from rung 3")
	low.free()


func test_hexes_and_shields_last_the_round_and_a_seek_leaves_them_standing() -> void:
	var s := _stage("magic_all")
	var snare := _cast_beat(s, "briar_snare")
	var round_end: float = float(s._round_ends[int(snare.round)])
	assert_true(round_end > float(snare.t), "the round ends after the cast")
	s.player.seek_beat(int(snare.i))
	s.player.play()
	var guard := 0
	while s.player.time() < float(snare.t) + 1.0 and guard < 4000:
		s.tick(STEP)
		guard += 1
	var mid: Dictionary = s.sfx.stats()
	assert_true(int(mid["ground"]) >= int(snare.data.targets.size()), "a second into the round the snared fighters' rings still stand")
	s.player.pause()
	# a seek into the middle of the round, after the casts: the state says who is snared and shielded, and the marks stand
	var live_before := int(s.sfx.stats()["alive"])
	s.player.seek_time(float(snare.t) + 1.5)
	var groups := BattleSpells.standing_groups(s.player.live_state())
	assert_false(groups.is_empty(), "the state has hexes and shields on fighters")
	assert_eq(int(s.sfx.stats()["alive"]), groups.size(), "one standing effect for each hex or shield group the state names")
	assert_true(int(s.sfx.stats()["ground"]) + int(s.sfx.stats()["sprites"]) > 0, "and they are drawn (%d before the seek)" % live_before)
	# a seek to before the first cast: nothing is standing
	s.player.seek_time(0.0)
	assert_eq(int(s.sfx.stats()["alive"]), 0, "before the first cast no effect stands")
	# played through the round's end, the hexes and shields are gone with it
	s.player.seek_beat(int(snare.i))
	s.player.play()
	guard = 0
	while s.player.time() < round_end + 0.15 and guard < 8000:
		s.tick(STEP)
		guard += 1
	assert_eq(int(s.sfx.stats()["alive"]), 0, "with the round over, nothing is left standing")
	s.free()


func test_the_blood_moons_heal_has_its_motes_and_its_number() -> void:
	var s := _stage("magic_moon")
	var moon := {}
	var other := {}
	for b in s.player.beats():
		if String(b.kind) == "heal":
			if BattleSpells.is_moon_heal(b, s._log):
				if moon.is_empty():
					moon = b
			elif other.is_empty():
				other = b
	assert_false(moon.is_empty(), "the Blood Moon heals in this battle")
	s.sfx.clear()
	s._numbers.clear()
	_fire_for(s, moon, 0.3)
	assert_true(int(s.sfx.stats()["sprites"]) > 0, "green motes rise from the healed fighter")
	assert_true(s._numbers.any(func(n): return String(n["text"]).begins_with("+")), "with its +hp number")
	var foot: Vector3 = s._ends_home(int(moon.fighter))[0]
	assert_false(s._fx.any(func(e): return e["kind"] == "heal" and (e["at"] as Vector3).distance_to(foot) < 0.01), "the moon's heal replaces the generic rise")
	s.auto_quality = false
	s.set_quality(3)
	s.sfx.clear()
	_fire_for(s, moon, 0.3)
	assert_eq(int(s.sfx.stats()["sprites"]), 0, "from rung 3 the number alone")
	assert_true(s._numbers.any(func(n): return String(n["text"]).begins_with("+")), "and it is there")
	if not other.is_empty():
		s.set_quality(0)
		s.sfx.clear()
		s._fx.clear()
		_fire(s, other)
		assert_true(s._fx.any(func(e): return e["kind"] == "heal"), "any other heal keeps the generic green rise")
	s.free()


func test_every_stage_fixture_plays_to_its_end_and_leaves_no_effect_standing() -> void:
	for name in MSF.NAMES:
		var fx := MSF.battle(name)
		assert_false(fx.is_empty(), "%s is fought" % name)
		var s := BattleStage3D.new()
		assert_eq(s.play(fx.log, fx.report, fx.state), "", "%s plays on the stage" % name)
		_play_out(s, 4)
		assert_eq(s.player.state(), s.player.timeline().final_state(), "%s: the player ends on the final state" % name)
		assert_eq(int(s.sfx.stats()["alive"]), 0, "%s: no effect is left standing" % name)
		assert_true(int(s.sfx.stats()["spawned"]) >= (fx.log.events as Array).filter(func(e): return e.t == "cast").size() or name == "magic_moon",
			"%s: every cast was played" % name)
		s.free()


func test_the_big_battle_with_six_casters_plays_inside_the_cpu_budget() -> void:
	var fx := MSF.battle("magic_big")
	assert_true(fx.log.fighters.size() >= 270, "the battle has the big count of fighters (%d)" % fx.log.fighters.size())
	var casters := 0
	for side in fx.log.sides:
		casters += (side.casters as Array).size()
	assert_eq(casters, 6, "and six casters")
	var s := BattleStage3D.new()
	assert_eq(s.play(fx.log, fx.report, fx.state), "", "it plays")
	var times := []
	var peak := 0
	s.player.set_speed(4)
	s.player.play()
	var frames := 0
	while not s.player.is_finished() and frames < 20000:
		var t0 := Time.get_ticks_usec()
		s.tick(STEP)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		var st: Dictionary = s.sfx.stats()
		peak = maxi(peak, int(st["ground"]) + int(st["sprites"]) + int(st["beams"]))
		frames += 1
	var total := 0.0
	var worst := 0.0
	for ms in times:
		total += float(ms)
		worst = maxf(worst, float(ms))
	var avg := total / maxf(1.0, float(times.size()))
	print("     magic_big on the 3D stage at 4x, headless, %d frames: stage CPU avg %.2f ms, worst %.2f ms, at most %d spell marks at once" % [times.size(), avg, worst, peak])
	assert_true(s.player.is_finished(), "the battle plays to its end")
	assert_true(peak <= SpellFx.MAX_GROUND + SpellFx.MAX_SPRITES + SpellFx.MAX_BEAMS, "the marks stay inside the layers' capacity")
	assert_perf(avg <= CPU_AVG_MS, "average %.2f ms per frame (budget %.1f ms)" % [avg, CPU_AVG_MS])
	assert_perf(worst <= CPU_MAX_MS, "worst frame %.2f ms (budget %.1f ms)" % [worst, CPU_MAX_MS])
	s.free()


# --- the legend and the figures -------------------------------------------------------------------------------------

func test_the_legend_names_each_spell_from_what_it_draws() -> void:
	var rows := BattleSpells.legend_rows()
	var ids := {}
	for r in rows:
		assert_false(ids.has(r.id), "row %s is listed once" % r.id)
		ids[r.id] = true
		assert_true(RulesCodex.ENTRIES.has(String(r.codex)), "%s links a codex entry that exists (%s)" % [r.id, r.codex])
		assert_false(String(r.title).is_empty() or String(r.text).is_empty(), "%s has a title and a meaning" % r.id)
		assert_false(String(r.get("reduced", "")).is_empty(), "%s says what reduced motion does to it" % r.id)
		var parts := String(r.drawn_by).split(".")
		assert_eq(parts.size(), 2, "%s names its drawing function" % r.id)
		assert_eq(parts[0], "BattleSpells", "%s is drawn by BattleSpells" % r.id)
		var is_static := false
		for m in BattleSpells.new().get_script().get_script_method_list():
			if String(m.name) == parts[1] and (int(m.flags) & METHOD_FLAG_STATIC) != 0:
				is_static = true
		assert_true(is_static, "%s: %s is a static function" % [r.id, r.drawn_by])
		assert_true((r.draw as Callable).is_valid(), "%s draws something" % r.id)
	for want in ["spell_sunlance", "spell_bloodbolt", "spell_snare", "spell_shield", "spell_sunburst", "spell_moon"]:
		assert_true(ids.has(want), "the legend has a row for %s" % want)
	# the numbers on the rows are the data's
	assert_true(String(rows[0].text).contains(str(int(MagicData.SPELLS["sunlance"].value))), "Sunlance's row has its damage")
	assert_true(String(rows[2].text).contains(str(int(MagicData.SPELLS["briar_snare"].value))), "Briar Snare's row has its part")
	var s := BattleStage3D.new()
	assert_true(s.legend.rows.any(func(r): return r.id == "spell_sunburst"), "the stage's legend lists the spells' rows")
	s.free()


func test_the_boards_legend_explains_magic_only_in_a_game_with_magic() -> void:
	assert_eq(EnchantDecals.legend_lines(GameState.new(3)), "", "a game without magic has the legend it had")
	assert_eq(EnchantDecals.legend_lines(null), "", "no state, no lines")
	var s := MB.game()
	var lines := EnchantDecals.legend_lines(s)
	for word in ["gilt ring", "blue band", "Crimson veins", "eye", "pillar of light", "no direction", "thorns", "scaffolding", "Blood Moon", "Rituals phase", "Enchantments phase"]:
		assert_true(lines.contains(word), "the magic legend says %s" % word)
	var b := _board_for(s)
	assert_true(b.overlay.legend_text().contains("Magic (the M5 preview)"), "the board's legend carries it in a game with magic")
	assert_eq(b.overlay.LEGEND % [Models.block_rule_text(), lines], b.overlay.legend_text(), "and it is the old legend plus those lines")
	_free_board(b)


func test_the_four_new_figures_have_rows_and_pass_the_silhouette_gate() -> void:
	assert_eq(Models.problems(), [], "the model table's rows are all sound")
	var ids: Array = []
	for fid in MagicData.MAGES:
		ids.append(String(MagicData.MAGES[fid].id))
	for sid in MagicData.SUMMONS:
		ids.append(String(MagicData.SUMMONS[sid].id))
	assert_eq(ids.size(), 4, "magic adds four figures")
	var boxes := {}
	for id in ids:
		assert_false(Models.figure_row(id).is_empty(), "%s has a row in world3d/models.json" % id)
		assert_true(Kit.has_figure(String(Models.figure_row(id).get("fallback", ""))), "%s falls back to a Kit figure" % id)
		var fm: Dictionary = Models.figure_mesh(id)
		assert_true(fm.get("mesh") is Mesh, "%s draws a mesh (%s)" % [id, fm.get("source", "?")])
		boxes[id] = (fm["mesh"] as Mesh).get_aabb()
		assert_true(Models.figure_mesh(id, false, "strike").get("mesh") is Mesh, "%s draws in every pose" % id)
	var bear: AABB = Kit.figure("war_bear").get_aabb()
	var man := Kit.FIG
	for id in ["adepts", "shamans"]:
		assert_true((boxes[id] as AABB).size.y > man * 1.25, "%s reads as a caster: its staff stands above a man's head" % id)
	var wolf: AABB = boxes["thornwolves"]
	assert_true(maxf(wolf.size.x, wolf.size.z) > wolf.size.y, "Thornwolves are wider than they are tall (a quadruped)")
	assert_true((boxes["greenwrath"] as AABB).size.y > bear.size.y, "the Greenwrath stands taller than a War Bear")
	assert_true(Models.rank_of("adepts") == 1 and Models.rank_of("shamans") == 1, "mages stand in the second rank")


# --- the playback's beats ---------------------------------------------------------------------------------------------

func _event(type: String, phase: String, provinces: Array, factions: Array, armies: Array, numbers: Dictionary, rebuilt := false) -> Dictionary:
	return {"type": type, "phase": phase, "provinces": provinces, "factions": factions, "armies": armies, "cause": "test", "numbers": numbers,
		"text": "The resolver's own words.", "codex": "orders", "rebuilt": rebuilt}


## A magic game with an army of each side, and the same game after a pack of wolves was summoned.
func _two_states() -> Array:
	var s := MB.game({CROWN: MB.REGENT, CLANS: MB.FANG})
	MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "adepts"])
	var after := GameState.from_dict(s.to_dict())
	MB.army(after, CLANS, "beasts-8", "bloodfen", ["thornwolves", "thornwolves", "thornwolves"])
	return [s, after]


## Every §12.3 event, as the viewer's own report would carry it: the rituals phase's, then the enchantments phase's.
func _magic_events() -> Array:
	var cast := {"ritual": "dawn_blessing", "kind": "blessing", "global": false}
	return [
		_event("ritual_cast", "rituals", ["rivermarch", "crownkeep"], [CROWN], ["kingdom-1"], cast),
		_event("ritual_cast", "rituals", ["rivermarch", "crownkeep"], [CROWN], ["kingdom-1"], {"ritual": "sanctum_ward", "kind": "ward", "global": false}),
		_event("ritual_cast", "rituals", ["bloodfen", "rivermarch"], [CLANS], ["beasts-8"], {"ritual": "bloodrot", "kind": "curse", "global": false}),
		_event("ritual_cast", "rituals", ["bloodfen"], [CLANS], ["beasts-8"], {"ritual": "call_the_pack", "kind": "summon", "global": false}),
		_event("ritual_cast", "rituals", ["crownkeep", "highcrag"], [CROWN], ["kingdom-1"], {"ritual": "bastion", "kind": "raising", "global": false}),
		_event("ritual_cast", "rituals", ["bloodfen"], [CLANS], [], {"ritual": "blood_moon", "kind": "global", "global": true}, true),
		_event("ritual_cast", "rituals", ["rivermarch", "stonegate"], [CROWN], ["kingdom-1"], {"ritual": "far_sight", "kind": "sight", "global": false}),
		_event("ritual_turned_aside", "rituals", ["crownkeep"], [CLANS, CROWN], ["beasts-8"], {"ritual": "bloodrot", "kind": "curse", "global": false}),
		_event("ritual_fell", "rituals", ["rivermarch"], [CROWN, CLANS], [], {"ritual": "bloodrot", "faction": CLANS, "until_turn": 4}),
		_event("blood_paid", "rituals", ["rivermarch"], [CROWN], ["kingdom-1"], {"ritual": "dawn_blessing", "army": "kingdom-1", "hp": 4}),
		_event("enchantment_began", "rituals", ["rivermarch"], [CROWN], ["kingdom-1"], {"enchantment": "kingdom-e1", "ritual": "dawn_blessing", "kind": "blessing",
			"province": "rivermarch", "until_turn": 4, "bonus": 0, "armies": ["kingdom-1"]}),
		_event("fort_raised", "rituals", ["highcrag"], [CROWN], [], {"province": "highcrag", "bastions": 1}),
		_event("far_sight_reading", "rituals", ["stonegate"], [CROWN, CLANS], [], {"province": "stonegate", "of": CLANS, "blocked": false}),
		_event("summoned", "rituals", ["bloodfen"], [CLANS], ["beasts-8"], {"ritual": "call_the_pack", "army": "beasts-8", "type": "thornwolves", "count": 3, "until": 6,
			"province": "bloodfen"}),
		_event("blessing_healed", "enchantments", ["rivermarch"], [CROWN], ["kingdom-1"], {"army": "kingdom-1", "province": "rivermarch", "ritual": "dawn_blessing"}),
		_event("curse_bit", "enchantments", ["rivermarch"], [CROWN, CLANS], ["kingdom-1"], {"province": "rivermarch", "ritual": "bloodrot", "armies": ["kingdom-1"]}),
		_event("enchantment_ended", "enchantments", ["rivermarch"], [CLANS], [], {"id": "beasts-e1", "ritual": "bloodrot", "kind": "curse", "province": "rivermarch", "cause": "time"}),
		_event("enchantment_ended", "enchantments", [], [CROWN], ["kingdom-1"], {"id": "kingdom-e1", "ritual": "dawn_blessing", "kind": "blessing", "cause": "time"}),
		_event("summon_faded", "enchantments", ["bloodfen"], [CLANS], ["beasts-8"], {"army": "beasts-8", "province": "bloodfen", "type": "thornwolves", "count": 3, "removed": true}),
	]


func test_the_playback_plans_every_magic_event_and_the_board_model_follows_the_summons() -> void:
	var two := _two_states()
	var before: GameState = two[0]
	var after: GameState = two[1]
	var events := _magic_events()
	var plan := Playback.plan(before, events, after)
	assert_eq((plan["rituals"] as Array).size(), events.size(), "every magic event is a beat")
	var kinds := {}
	for b in plan["rituals"]:
		kinds[b["kind"]] = true
	for t in Playback.RITUAL_EVENTS:
		assert_true(kinds.has(t), "the plan has a %s beat" % t)
	assert_false(Playback.is_empty(plan), "a turn with only rituals is played")
	assert_true(Playback.is_empty(Playback.plan(before, [], after)), "a turn with nothing in it still is not")
	assert_eq(MagicBeats.early(plan["rituals"]).size() + MagicBeats.late(plan["rituals"]).size(), events.size(), "each beat plays in one phase")
	assert_true(MagicBeats.late(plan["rituals"]).all(func(b): return SpellPlan.LATE_EVENTS.has(b["kind"])), "the enchantments' beats play after the battles")
	var hidden: Array = plan["rituals"].filter(func(b): return b["kind"] == "ritual_cast" and bool(b["global"]))
	assert_eq(hidden.size(), 1, "the heralded Blood Moon is one beat")
	assert_eq(String(hidden[0]["from"]), "", "and it starts nowhere")
	# the board model after the events is the board model of the state after (a summoned army is there, a faded one is gone)
	var model := Playback.apply_events(Playback.model_of(before), [events[13]])
	assert_eq(model["armies"], Playback.model_of(after)["armies"], "summoning puts the pack on the board model")
	var gone := Playback.apply_events(Playback.model_of(after), [events[18]])
	assert_eq(gone["armies"], Playback.model_of(before)["armies"], "and its fading takes the pack off")


# --- the board ----------------------------------------------------------------------------------------------------------

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


func test_a_turns_ritual_and_enchantment_beats_all_play_on_the_board() -> void:
	var two := _two_states()
	var before: GameState = two[0]
	var after: GameState = two[1]
	var b := _board_for(before)
	assert_true(b.decals != null, "the board has its magic")
	var events := _magic_events()
	var plan := Playback.plan(before, events, after)
	b.armies.snap_at_end = false
	b.decals.played.clear()
	b.rituals_played.clear()
	assert_true(b.play_turn(before, events, after), "the turn plays")
	var phases: Array = b.armies.phases()
	var keys: Array = phases.map(func(p): return p["key"])
	assert_eq(keys.front(), "rituals", "the rituals phase opens the turn")
	assert_eq(keys.back(), "enchantments", "the enchantments phase closes it")
	var order: Array = Choreo.PHASES.filter(func(k): return keys.has(k))
	assert_eq(keys, order, "the phases play in the report's order")
	for p in phases:
		assert_true(TurnReportPanel.PHASE_TITLES.has(p["key"]), "%s is one of the report's phases" % p["key"])
		assert_true(Choreo.CAPTION_HELP.has(p["key"]) and String(Choreo.CAPTION_HELP[p["key"]]).length() > 20, "%s explains itself" % p["key"])
	var early := MagicBeats.early(plan["rituals"]).size()
	assert_true(float(phases.filter(func(p): return p["key"] == "rituals")[0]["t1"]) >= MagicBeats.span(early) - 0.2, "the rituals phase takes its span")
	var guard := 0
	while b.is_playing() and guard < 9000:
		b.armies.step_playback(1.0 / 10.0)
		guard += 1
	assert_false(b.is_playing(), "the playback ends")
	var played: Array = b.decals.played
	assert_eq(played.size(), events.size(), "every beat drew its effect")
	var got := {}
	for p in played:
		got[p["key"]] = true
		assert_false(bool(p["skipped"]), "%s was not turned away by the pool" % p["key"])
	for key in SpellPlan.BOARD_KEYS:
		assert_true(got.has(key), "the board played %s" % key)
	# a caster the viewer can't see has no direction: the heralded moon and the fall start nowhere
	for p in played:
		if p["key"] in ["ritual_fell", "cast:global"]:
			assert_false(bool(p["from"]), "%s has no caster to start from" % p["key"])
	# the order: every beat of the rituals phase plays before the first of the enchantments phase's
	var first_late := played.size()
	for i in played.size():
		if SpellPlan.LATE_EVENTS.has(String(played[i]["key"])):
			first_late = mini(first_late, i)
	assert_eq(first_late, early, "the enchantments' beats come after all %d of the rituals' (the first is beat %d)" % [early, first_late])
	# the three original ritual beats are still the board's (M5-3's contract)
	assert_eq(b.rituals_played.size(), 9, "the cast, turned-aside and fell beats still fire ritual_beat")
	_free_board(b)


## Games with magic the real AI plays through the real resolver: every turn's board model follows its events (a summoned pack, a fading one),
## and every turn with a ritual or an enchantment's beat plays it on a real board, each beat drawing its effect.
func test_the_ais_real_rituals_and_enchantments_play_on_the_board() -> void:
	var magic_turns := 0
	var b: Board3D = null
	var kinds := {}
	for game_seed in [2, 4, 6, 1, 3, 5, 7, 8]:
		if magic_turns >= 3:
			break
		var st: GameState = GameState.with_magic(game_seed, {}, [])
		for t in 24:
			var orders := {}
			var seat := 0
			for f in st.factions:
				var rng := SeededRNG.new(game_seed * 7919 + (seat + 1) * 104729 + t * 31)
				orders[f.id] = AIPlayer.new().plan_orders(st, f.id, rng, "normal")
				seat += 1
			var res: Dictionary = TurnResolver.resolve(st, orders, TurnResolver.seed_for_turn(st))
			if res.get("new_state") == null:
				break
			var after: GameState = res["new_state"]
			var events: Array = res["events"]
			var model := Playback.apply_events(Playback.model_of(st), events)
			var built := Playback.model_of(after)
			assert_eq(model["armies"], built["armies"], "seed %d turn %d: the board model follows the events' armies" % [game_seed, t + 1])
			assert_eq(model["owners"], built["owners"], "seed %d turn %d: and the owners" % [game_seed, t + 1])
			var plan := Playback.plan(st, events, after)
			if not (plan["rituals"] as Array).is_empty() and magic_turns < 3:
				magic_turns += 1
				if b == null:
					b = _board_for(st)
				b.map.set_state(after, st.factions[0].id)
				b.armies.snap_at_end = false
				b.decals.played.clear()
				assert_true(b.play_turn(st, events, after), "seed %d turn %d: a turn with rituals plays" % [game_seed, t + 1])
				var guard := 0
				while b.is_playing() and guard < 9000:
					b.armies.step_playback(1.0 / 10.0)
					guard += 1
				assert_false(b.is_playing(), "the playback ends")
				assert_eq(b.decals.played.size(), (plan["rituals"] as Array).size(), "seed %d turn %d: every beat drew its effect" % [game_seed, t + 1])
				for p in b.decals.played:
					kinds[p["key"]] = true
					assert_true(SpellPlan.BOARD_KEYS.has(String(p["key"])), "%s is one of the effects" % p["key"])
				b.armies.snap_at_end = true
			st = after
			var over := false
			for f in st.factions:
				var cap := st.find_province(f.capital)
				over = over or cap == null or cap.owner != f.id
			if over:
				break
	assert_true(magic_turns >= 1, "the AI cast something in these games (%d turns with magic beats, effects %s)" % [magic_turns, kinds.keys()])
	if b != null:
		_free_board(b)


func test_ritual_beats_from_hidden_casters_start_at_the_target_and_reveal_nothing() -> void:
	var two := _two_states()
	var before: GameState = two[0]
	var b := _board_for(before)
	b.armies.show_state(before, UiPalette.seat_order(before))
	var own := {"kind": "ritual_cast", "ritual": "bloodrot", "rkind": "curse", "faction": CLANS, "from": "bloodfen", "at": "rivermarch", "global": false,
		"armies": ["beasts-9"], "ekind": "", "army": "", "removed": false, "phase": "rituals"}
	var seen := own.duplicate()
	seen["from"] = ""
	var fell := {"kind": "ritual_fell", "ritual": "bloodrot", "rkind": "curse", "faction": CLANS, "from": "", "at": "rivermarch", "global": false, "armies": [],
		"ekind": "", "army": "", "removed": false, "phase": "rituals"}
	var plan_own: Dictionary = b.decals.plan_of(own)
	var plan_hidden: Dictionary = b.decals.plan_of(seen)
	var plan_fell: Dictionary = b.decals.plan_of(fell)
	assert_true(plan_own["elements"].any(func(e): return e["k"] == "column" and e.has("to")), "a cast the viewer sees has its pillar at the caster")
	assert_true(plan_own["elements"].any(func(e): return e.has("path")), "and a mote along the roads")
	assert_false(plan_hidden["elements"].any(func(e): return e.has("path")), "a hidden caster's ritual has no mote along any road")
	var caster_at: Vector3 = b.decals.prov_pos("bloodfen")
	for e in plan_hidden["elements"] + plan_fell["elements"]:
		assert_true((e["at"] as Vector3).distance_to(caster_at) > 30.0, "no mark is near the hidden caster's province (%s)" % e["k"])
		assert_false(e.has("path"), "and none runs from it")
	# the same hidden ritual from two different places is the same plan: nothing in it depends on where the caster stood
	var other := seen.duplicate()
	other["armies"] = ["beasts-12"]
	assert_eq(var_to_str(b.decals.plan_of(other)), var_to_str(plan_hidden), "whichever hidden place it came from, the plan is the same")
	assert_eq(var_to_str(plan_fell["elements"].map(func(e): return e["k"])), var_to_str(b.decals.plan_of(fell)["elements"].map(func(e): return e["k"])), "and stable")
	_free_board(b)


func test_enchantment_decals_follow_the_state_and_never_change_it() -> void:
	var s := MB.game({CROWN: MB.REGENT, CLANS: MB.FANG})
	var army := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "adepts"])
	var b := _board_for(s)
	b.armies.show_state(s, UiPalette.seat_order(s))
	MB.enchant(s, "sanctum_ward", CROWN, "crownkeep")
	MB.enchant(s, "bloodrot", CLANS, "rivermarch")
	MB.enchant(s, "far_sight", CROWN, "stonegate")
	MB.enchant(s, "dawn_blessing", CROWN, "", [army.id])
	MB.enchant(s, "blood_moon", CLANS)
	var before := var_to_str(s.to_dict())
	b.decals.sync(s)
	assert_eq(var_to_str(s.to_dict()), before, "drawing the enchantments changed nothing in the state")
	var keys: Array = b.decals.fx.standing_keys()
	assert_eq(keys.size(), 4, "a decal for the ward, the curse, the sight and the blessing (the moon has none on the land): %s" % [keys])
	var kinds := {}
	for key in keys:
		for e in b.decals.fx._standing[key]:
			kinds[e["k"]] = true
	for k in ["band", "veins", "eye", "sun_ring"]:
		assert_true(kinds.has(k), "the decals include the %s" % k)
	# still on rung 2, and drawn
	b.decals.set_rung(2)
	b.decals.sync(s)
	for key in b.decals.fx.standing_keys():
		for e in b.decals.fx._standing[key]:
			assert_eq(float(e["w"]), 0.0, "rung 2: %s stands still" % e["k"])
	assert_true(int(b.decals.fx.stats()["ground"]) + int(b.decals.fx.stats()["sprites"]) > 0, "the decals are drawn")
	# the enchantments end: their decals go
	s.enchantments = []
	b.decals.sync(s)
	assert_eq(b.decals.fx.standing_keys(), [], "a decal is gone with its enchantment")
	_free_board(b)


func test_a_bastions_fort_stands_from_the_state_and_goes_with_it() -> void:
	var s := MB.game({CROWN: MB.REGENT, CLANS: MB.FANG})
	var b := _board_for(s)
	var pid := ""
	for p in s.provinces:
		var i: int = b.wv.terrain.index_of(p.id)
		if i >= 0 and not b.wv.terrain.has_fort[i] and not b.wv.terrain.is_capital[i]:
			pid = p.id
			break
	assert_false(pid.is_empty(), "there is a province with no fort")
	assert_false(b.wv.forts.has(pid), "none stands there")
	s.find_province(pid).has_fort = true
	var before := var_to_str(s.to_dict())
	b.decals.sync(s)
	assert_true(b.wv.forts.has(pid), "Bastion's fort stands on the board from the state")
	assert_eq(var_to_str(s.to_dict()), before, "drawing it changed nothing")
	s.find_province(pid).has_fort = false
	b.decals.sync(s)
	assert_false(b.wv.forts.has(pid), "and it is gone when the state has none")
	s.find_province(pid).has_fort = true
	s.sieges = true
	b.decals.sync(s)
	assert_false(b.wv.forts.has(pid), "in a game with sieges the siege board draws every fort, not this")
	_free_board(b)


func test_a_bastion_rises_behind_scaffolding_and_the_scaffolding_comes_down() -> void:
	var s := MB.game({CROWN: MB.REGENT, CLANS: MB.FANG})
	var b := _board_for(s)
	var beat := {"kind": "fort_raised", "ritual": "", "rkind": "", "faction": CROWN, "from": "", "at": "highcrag", "global": false, "armies": [], "ekind": "", "army": "",
		"removed": false, "phase": "rituals"}
	for rung in [0, 3, 5]:
		b.decals.set_rung(rung)
		b.decals.on_beat(beat, 0)
		assert_true(b.decals.rising_at("highcrag"), "rung %d: the fort goes up" % rung)
		b.decals._step_rising(5.0)
		assert_true(b.decals._dress != null and b.decals._dress.get_child_count() >= 1, "rung %d: its scaffolding stands" % rung)
		b.decals.end_play()
		assert_false(b.decals.rising_at("highcrag"), "rung %d: the scaffolding comes down at the end of the playback" % rung)
	_free_board(b)
