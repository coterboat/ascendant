## A battle's spells on the 3D stage, the pure part (no nodes): turns the player's `cast` beats (ui/battle/battle_player.gd) and a
## Blood Moon heal into the plans world3d/spell_plan.gd draws, and keeps the legend rows for them (M5-9, #120;
## design/M5_MAGIC_FOG.md §5, §12.2). The stage gives it where a fighter stands (`ends`) and the node that draws is
## world3d/spell_fx.gd; nothing here reads or changes the game: a cast beat is the log's own event, already resolved.
##
##   plan_for_beat(b, ctx)         the plan a `cast` beat plays ({} for a spell this stage has no effect for)
##   heal_plan(b, ctx)             the Blood Moon's heal: green motes and the +hp number
##   standing(state, ctx)          a plan for every hex and shield still on its targets in a timeline state (after a seek)
##   round_ends(beats)             {round: playback time its round_end beat fires}: how long a hex or shield lasts
##   legend_rows(seat)             the stage's legend rows for the spells' marks
## `ctx`: {"ends": Callable(fid) -> {"foot", "head", "r"} or {}, "col": Color (the caster's side), "life": seconds left of the
## round, "rung", "reduced", "log": the battle log}.
class_name BattleSpells
extends RefCounted

const SpellPlan := preload("res://world3d/spell_plan.gd")


static func plan_for_beat(b: Dictionary, ctx: Dictionary) -> Dictionary:
	var d: Dictionary = b.get("data", {})
	return build(String(d.get("spell", "")), String(d.get("kind", "")), int(b.get("fighter", -1)), d.get("targets", []), d, ctx)


## The plan of `spell` (a MagicData battle spell id) cast by fighter `caster` on `targets` (fighter ids). `d` carries "name", "damage",
## "part" and "self" as the cast beat's data does.
static func build(spell: String, kind: String, caster: int, targets: Array, d: Dictionary, ctx: Dictionary) -> Dictionary:
	var effect := SpellPlan.effect_of(kind, spell)
	if effect.is_empty() or effect == "heal_back":
		return {}
	var ends: Callable = ctx["ends"]
	var c: Dictionary = ends.call(caster)
	if c.is_empty():
		return {}
	var args := {"caster": c, "col": ctx.get("col", Color.WHITE), "life": float(ctx.get("life", 2.0)), "name": String(d.get("name", MagicRules.spell_name(spell))),
		"damage": int(d.get("damage", 0)), "part": d.get("part", {}), "self": int(d.get("self", 0))}
	var list := []
	var seen := {}
	for t in targets:
		var e: Dictionary = ends.call(int(t))
		if e.is_empty():
			continue
		var key := Vector2i(int(round(float((e["foot"] as Vector3).x) * 4.0)), int(round(float((e["foot"] as Vector3).z) * 4.0)))
		if seen.has(key):
			continue ## a file's fighters share one figure: one mark for it
		seen[key] = true
		list.append(e)
	if list.is_empty():
		return {}
	args["targets"] = list
	args["target"] = list[0]
	if effect == "sunburst":
		var reach := 0.0
		for e2 in list:
			var dv: Vector3 = (e2["foot"] as Vector3) - (c["foot"] as Vector3)
			reach = maxf(reach, Vector2(dv.x, dv.z).length())
		args["reach"] = reach
	return SpellPlan.battle(effect, int(ctx.get("rung", 0)), args, bool(ctx.get("reduced", false)))


## The Blood Moon's heal beat: the healed fighter's rising motes, and its +hp.
static func heal_plan(b: Dictionary, ctx: Dictionary) -> Dictionary:
	var ends: Callable = ctx["ends"]
	var e: Dictionary = ends.call(int(b.get("fighter", -1)))
	if e.is_empty():
		return {}
	var f := e.duplicate()
	f["healed"] = int((b.get("data", {}) as Dictionary).get("healed", 0))
	return SpellPlan.battle("heal_back", int(ctx.get("rung", 0)), {"fighters": [f]}, bool(ctx.get("reduced", false)))


## True when the heal beat `b` is the Blood Moon's (its log event names the spell instead of a trait).
static func is_moon_heal(b: Dictionary, battle_log: Dictionary) -> bool:
	var i := int(b.get("event", -1))
	var events: Array = battle_log.get("events", [])
	return i >= 0 and i < events.size() and String((events[i] as Dictionary).get("spell", "")) == "blood_moon"


## The hexes and shields on their targets in timeline state `st`: [{"spell", "kind", "by", "targets"}], in spell and caster order.
## (A hex or shield is a part named "spell_<id>" on the fighter, with the caster in "by"; BattleTimeline.apply sets and clears it.)
static func standing_groups(st: Dictionary) -> Array:
	var groups := {}
	for fid in st.fighters.size():
		var fs: Dictionary = st.fighters[fid]
		if not fs.alive or not fs.has("spells"):
			continue
		for key in fs.spells:
			var sp: Dictionary = fs.spells[key]
			var gk := "%s|%d" % [key, int(sp.get("by", -1))]
			if not groups.has(gk):
				groups[gk] = {"spell": String(key).trim_prefix("spell_"), "by": int(sp.get("by", -1)), "targets": []}
			groups[gk]["targets"].append(fid)
	var keys: Array = groups.keys()
	keys.sort()
	var out := []
	for k in keys:
		var g: Dictionary = groups[k]
		g["kind"] = String(MagicData.SPELLS.get(g["spell"], {}).get("kind", ""))
		out.append(g)
	return out


## The plans for what a seek leaves standing: one per hex or shield group still on its targets, with `ctx`'s life.
static func standing(st: Dictionary, ctx: Dictionary) -> Array:
	var out := []
	var battle_log: Dictionary = ctx.get("log", {})
	for g in standing_groups(st):
		var caster := int(g["by"])
		var col: Color = ctx.get("col_of", func(_fid): return Color.WHITE).call(caster)
		var c2 := ctx.duplicate()
		c2["col"] = col
		var name := MagicRules.spell_name(String(g["spell"]))
		var p := build(String(g["spell"]), String(g["kind"]), caster, g["targets"], {"name": name,
			"part": _part_of(st, int(g["targets"][0]), "spell_" + String(g["spell"]))}, c2)
		if not p.is_empty():
			out.append(p)
	return out


static func _part_of(st: Dictionary, fid: int, key: String) -> Dictionary:
	var sp: Dictionary = (st.fighters[fid].spells as Dictionary).get(key, {})
	return {"stat": String(sp.get("stat", "")), "value": int(sp.get("value", 0))} if not sp.is_empty() else {}


## {round: the playback time its round_end beat fires}: a hex or shield lasts to there.
static func round_ends(beats: Array) -> Dictionary:
	var out := {}
	for b in beats:
		if String(b.kind) == "round_end":
			out[int(b.round)] = float(b.t)
	return out


# ------------------------------------------------------------------ the legend (BattleLegend row format)

## The stage's legend rows for the spells' marks: how to name each spell from what it draws. Each draws a sketch with one of the
## static sketch_* functions below (BattleLegend's rows are drawn by static functions, so the legend and the tests can call them) and
## links the spell's codex entry. The numbers come from the data.
static func legend_rows(seat: int = 0) -> Array:
	var lance: Dictionary = MagicData.SPELLS["sunlance"]
	var bolt: Dictionary = MagicData.SPELLS["bloodbolt"]
	var snare: Dictionary = MagicData.SPELLS["briar_snare"]
	var shield: Dictionary = MagicData.SPELLS["shield_of_law"]
	var burst: Dictionary = MagicData.SPELLS["sunburst"]
	return [
		BattleLegend._row("spell_sunlance", "Sunlance", "A gilt beam from the caster to its target and a starburst where it lands: %d sure damage, never missing. The words over the caster name the spell and its damage." % int(lance.value),
			"spell_sunlance", "BattleSpells.sketch_sunlance", func(ci: CanvasItem, r: Rect2): sketch_sunlance(ci, r, seat),
			"With reduced motion the beam shows at once and holds still, with no flash."),
		BattleLegend._row("spell_bloodbolt", "Bloodbolt", "A crimson bolt from the caster, a red splash where it lands and a mist where the caster bled: %d sure damage, and the caster loses %d hit points." % [int(bolt.value), int(bolt.bleed)],
			"spell_bloodbolt", "BattleSpells.sketch_bloodbolt", func(ci: CanvasItem, r: Rect2): sketch_bloodbolt(ci, r, seat),
			"With reduced motion the bolt shows at once and holds still, with no flash."),
		BattleLegend._row("spell_snare", "Briar Snare", "A ring of thorns on the ground under each snared unit and a briar climbing it, for the round: %d attack. The ring wears the caster's side colour; on the lowest qualities only the ring stands." % int(snare.value),
			"spell_briar_snare", "BattleSpells.sketch_snare", func(ci: CanvasItem, r: Rect2): sketch_snare(ci, r, seat),
			"With reduced motion the ring and briar stand still, with no leaves."),
		BattleLegend._row("spell_shield", "Shield of Law", "A pale blue shield with a gold rim before each covered unit for the round: +%d defense. On the lowest qualities a triangle on the ground under the unit stands in for the shield." % int(shield.value),
			"spell_shield_of_law", "BattleSpells.sketch_shield", func(ci: CanvasItem, r: Rect2): sketch_shield(ci, r, seat),
			"With reduced motion the shield's rim does not pulse."),
		BattleLegend._row("spell_sunburst", "Sunburst", "A ring of gilt light sweeps out over the enemy front rank and a flare lights the caster, once, in round 1: every front-rank enemy has %d attack that round. It is never a white-out, and it counts as a flash." % int(burst.value),
			"spell_sunburst", "BattleSpells.sketch_sunburst", func(ci: CanvasItem, r: Rect2): sketch_sunburst(ci, r, seat),
			"With reduced motion the ring shows whole at once, with no flare and no shake."),
		BattleLegend._row("spell_moon", "Blood Moon's heal", "Green motes rise from a fighter that healed back under the Blood Moon, with its green +hp.",
			"spell_blood_moon", "BattleSpells.sketch_moon_heal", func(ci: CanvasItem, r: Rect2): sketch_moon_heal(ci, r, seat),
			"With reduced motion there are no motes, only the number."),
	]


## A beam from the caster's side to the right and a starburst where it lands, in `col`.
static func _beam(ci: CanvasItem, r: Rect2, col: Color, hot: Color) -> void:
	var a := r.position + Vector2(10, r.size.y * 0.62)
	var b := r.end - Vector2(18, r.size.y * 0.38)
	ci.draw_line(a, b, Color(col, 0.35), 9.0)
	ci.draw_line(a, b, Color(UiPalette.KEYLINE_INK, 0.9), 5.0)
	ci.draw_line(a, b, col, 3.5)
	ci.draw_line(a, b, hot, 1.5)
	var star := PackedVector2Array()
	for j in 12:
		var ang := TAU * j / 12.0
		star.append(b + Vector2(cos(ang), sin(ang)) * (9.0 if j % 2 == 0 else 4.0))
	ci.draw_colored_polygon(star, hot)


static func sketch_sunlance(ci: CanvasItem, r: Rect2, _seat: int = 0) -> void:
	_beam(ci, r, SpellPlan.GILT, SpellPlan.GILT_HOT)


static func sketch_bloodbolt(ci: CanvasItem, r: Rect2, _seat: int = 0) -> void:
	_beam(ci, r, SpellPlan.BLOOD, Color("#FFB0A8"))


## A ring of thorns on the ground in the caster's side colour, a briar standing in it.
static func sketch_snare(ci: CanvasItem, r: Rect2, seat: int = 0) -> void:
	var c := r.get_center() + Vector2(0, 8)
	var ring := _ellipse(c, Vector2(26, 9))
	ci.draw_polyline(ring, Color(UiPalette.KEYLINE_INK, 0.9), 5.0, true)
	ci.draw_polyline(ring, UiPalette.seat_color(seat), 3.0, true)
	for k in 14:
		var a := TAU * k / 14.0
		var p0 := c + Vector2(cos(a) * 26.0, sin(a) * 9.0)
		ci.draw_line(p0, p0 + Vector2(cos(a) * 6.0, sin(a) * 4.0 - 3.0), SpellPlan.WILD, 2.0)
	ci.draw_circle(c + Vector2(0, -8), 5.0, SpellPlan.WILD_DEEP)


## A heater shield, pale blue with a gold rim and Law's square.
static func sketch_shield(ci: CanvasItem, r: Rect2, _seat: int = 0) -> void:
	var c := r.get_center()
	var pts := PackedVector2Array([c + Vector2(-11, -13), c + Vector2(11, -13), c + Vector2(11, 0), c + Vector2(0, 14), c + Vector2(-11, 0)])
	ci.draw_colored_polygon(pts, Color(SpellPlan.LAW, 0.7))
	ci.draw_polyline(PackedVector2Array(Array(pts) + [pts[0]]), Color("#E8C86A"), 2.5)
	ci.draw_rect(Rect2(c + Vector2(-3, -6), Vector2(6, 6)), Color("#E8C86A"))


## Rings of gilt light sweeping out from a flare.
static func sketch_sunburst(ci: CanvasItem, r: Rect2, _seat: int = 0) -> void:
	var c := r.get_center() + Vector2(-12, 8)
	for k in 3:
		ci.draw_arc(c, 10.0 + 9.0 * k, -0.9, 0.9, 16, Color(SpellPlan.GILT, 0.9 - 0.25 * k), 3.0)
	ci.draw_circle(c, 4.0, SpellPlan.GILT_HOT)


## Green plus signs rising.
static func sketch_moon_heal(ci: CanvasItem, r: Rect2, _seat: int = 0) -> void:
	var c := r.get_center() + Vector2(0, 6)
	for k in 4:
		var p := c + Vector2((k - 1.5) * 9.0, -9.0 * fposmod(0.3 + k * 0.23, 1.0) * 2.0)
		ci.draw_rect(Rect2(p - Vector2(4.5, 1.8), Vector2(9, 3.6)), UiPalette.POSITIVE)
		ci.draw_rect(Rect2(p - Vector2(1.8, 4.5), Vector2(3.6, 9)), UiPalette.POSITIVE)


static func _ellipse(c: Vector2, rad: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return pts
