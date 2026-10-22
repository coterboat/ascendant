## The spell and ritual effects of the 3D world, the pure part (no nodes): what each effect draws on each rung of the quality
## ladder (design/M5_MAGIC_FOG.md §12.2, §12.3, §15.3; design/3D_DIRECTION.md §3.4), as lists of elements that world3d/spell_fx.gd
## draws with code (rings, beams, billboards and motes: the placeholders the VFX sheets will replace, §15.3). Nothing here
## touches the game: an effect only ever reads a battle log's cast beat or a turn report's ritual beat, and a plan is a plain
## Dictionary, so the tests check every effect on every rung without a renderer.
##
##   battle(effect, rung, args, reduced)  -> a plan for a battle spell: sunlance, bloodbolt, briar_snare, shield_of_law, sunburst,
##                                           or heal_back (the Blood Moon's heal)
##   board(key, rung, args, reduced)      -> a plan for a map beat: BOARD_KEYS (a ritual cast by its kind, a fizzle, a fall, a
##                                           payment in blood, a summoning, a fort raised, an enchantment beginning or ending, a
##                                           blessing healing, a curse biting, a summon fading, a reading)
##   standing(kind, rung, args, reduced)  -> the elements an enchantment keeps on the map while it lasts: blessing, ward, curse, sight
##   a plan is {"effect", "rung", "elements": [...], "labels": [...], "shake" (px, 0 for none), "flash" (it asks the flash
##   limiter once), "life" (seconds it lasts)}; an element is {"k" (a KINDS name), "at", "to" (a beam's end), "r", "r1", "t0", "dur",
##   "col" (its alpha is the peak), "up", "yaw", "seed", "w" (the shader's variant: 1 animates a standing decal), "fin", "fout",
##   "bright" (may flash: world3d/spell_fx.gd asks the limiter), "path" (a mote's way)}.
##
## VFX-WIRE (#242): a plan's "sheets" are effect sheets that have no code mark (world3d/spell_fx.gd draws them only when their sheet is
## there): [{"sheet", "at", "r", "t0", "dur", "col", "yaw", "fin", "fout"}]. cast_channel lies under a caster while it casts and
## briar_burst at a snared fighter's feet; both are on the ground, turned to that fighter's facing (its "yaw", from the stage).
## Every effect has a beat on every rung: the ladder thins an effect (no trail, no glow, fewer particles, a still decal), it never
## drops it (the tests). Reduced motion keeps each effect as a still mark: no sweep, no travel, no pulse, no particles, no shake,
## no flash. Nothing here draws a random number: a particle's place comes from a hash of its index (h01).
extends RefCounted

const RUNGS := 6 ## 0 Full .. 5 Compatibility (3D_DIRECTION §3.4)
const POOL_CAP := 32 ## §12.2: at most 32 spell effects alive; a full pool skips a new one
const BOLT_PARTICLES := 6
## How wide a province's decals are, as a share of its radius (EnchantDecals.prov_r): a ward's band and a curse's veins fill most of the
## province (a capital's fortress stands inside the band), a Far Sight's ring is smaller, under its eye.
const WARD_K := 0.9
const VEIN_K := 0.85
const SIGHT_K := 0.5

## The shader's kind numbers (world3d/shaders/spell_fx.gdshaderinc): ground decals, then camera-facing sprites, then the beam.
const KINDS := {
	"ring": 0, "thorn_ring": 1, "sun_ring": 2, "band": 3, "tri": 4, "veins": 5, "glare_ring": 6, "dust_ring": 7, "summon_ring": 8,
	"fizzle_ring": 9, "glow": 10, "flare": 11, "burst": 12, "blood_spray": 13, "briar_burst": 14, "shield": 15, "briar": 16, "vine": 17,
	"mote": 18, "leaf": 19, "mist": 20, "puff": 21, "eye": 22, "moon": 23, "plus": 24, "beam": 30, "column": 31,
}
const GROUND_MAX := 9
const BEAM := 30

## The schools' flat cel colours ("effects are untinted": a school's own colour, never the caster's; ownership is the decal's
## colour and the caster's ring, §12.2).
const GILT := Color("#E6B84E")
const GILT_HOT := Color("#FFF1B8")
const LAW := Color("#6FA0F5")
const LAW_DEEP := Color("#3E63B8")
const WILD := Color("#79C84F")
const WILD_DEEP := Color("#2F6B2A")
const BLOOD := Color("#C8323C")
const BLOOD_DEEP := Color("#7A1020")
const SIGHT := Color("#F2E6B8")
const SMOKE := Color("#9C968C")
## CW-5 (#256): the Candlewake's schools in the director's colours: the Wick lilac, Wax honey with its ivory.
const WICK := Color("#B48CF0")
const WAX := Color("#E0B65A")
const SCHOOL_COLOURS := {
	"sun": {"main": GILT, "hot": GILT_HOT}, "law": {"main": LAW, "hot": Color("#E6F0FF")},
	"wild": {"main": WILD, "hot": Color("#D6F5B0")}, "blood": {"main": BLOOD, "hot": Color("#FFB0A8")},
	"wick": {"main": WICK, "hot": Color("#EADCFF")}, "wax": {"main": WAX, "hot": Color("#EADFC4")},
	"common": {"main": SIGHT, "hot": Color.WHITE},
}

## Every battle effect and the cast kinds (MagicData.BATTLE_KINDS) that play it.
const BATTLE_EFFECTS := ["sunlance", "bloodbolt", "briar_snare", "shield_of_law", "sunburst", "heal_back", "draw_the_warmth", "wax_skin"]
const KIND_EFFECT := {"bolt": "sunlance", "hex": "briar_snare", "shield": "shield_of_law", "drink": "heal_back"}

## Every map effect: the events §12.3 lists, a ritual cast split by its kind.
const BOARD_KEYS := ["cast:blessing", "cast:ward", "cast:curse", "cast:summon", "cast:raising", "cast:global", "cast:sight", "cast:flame",
	"ritual_turned_aside", "ritual_fell", "blood_paid", "summoned", "fort_raised", "enchantment_began", "enchantment_ended",
	"blessing_healed", "curse_bit", "summon_faded", "far_sight_reading"]
const STANDING_KINDS := ["blessing", "ward", "curse", "sight"]
## The turn report's events the board plays as beats (Playback.plan's "rituals"), by the phase they play in.
const EARLY_EVENTS := ["ritual_cast", "ritual_turned_aside", "ritual_fell", "blood_paid", "enchantment_began", "fort_raised", "far_sight_reading"]
const LATE_EVENTS := ["summoned", "blessing_healed", "curse_bit", "enchantment_ended", "summon_faded"]


# ------------------------------------------------------------------ helpers

## A 0..1 number from two integers: a particle's place, never the game's dice (an integer hash).
static func h01(a: int, b: int = 0) -> float:
	var x: int = (a * 374761393 + b * 668265263 + 1274126177) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float((x ^ (x >> 16)) & 0xffff) / 65535.0


static func clamp_rung(rung: int) -> int:
	return clampi(rung, 0, RUNGS - 1)


## The rung the ladder shows: the quality rung, or the bottom one on the Compatibility renderer (the automatic fallback is rung 5).
static func rung_of(quality: int, compatibility: bool = false) -> int:
	return RUNGS - 1 if compatibility else clamp_rung(quality)


static func _plan(effect: String, rung: int) -> Dictionary:
	return {"effect": effect, "rung": rung, "elements": [], "labels": [], "shake": 0.0, "flash": false, "life": 0.0, "sheets": []}


## VFX-WIRE: appends a sheet-only entry (see "sheets" above).
static func _sheet(plan: Dictionary, sheet: String, at: Vector3, r: float, t0: float, dur: float, col: Color, yaw: float, opts: Dictionary = {}) -> void:
	var e := {"sheet": sheet, "at": at, "r": r, "t0": t0, "dur": dur, "col": col, "yaw": yaw, "fin": 0.08, "fout": 0.3}
	for key in opts:
		e[key] = opts[key]
	plan["sheets"].append(e)


## Appends an element: kind `k` at `at`, half-size `r`, from `t0` for `dur` seconds, in `col` (its alpha is the peak).
static func _add(plan: Dictionary, k: String, at: Vector3, r: float, t0: float, dur: float, col: Color, opts: Dictionary = {}) -> Dictionary:
	var e := {"k": k, "at": at, "r": r, "r1": r, "t0": t0, "dur": dur, "col": col, "up": 0.0, "yaw": 0.0, "seed": 0.0, "w": 0.0,
		"fin": 0.08, "fout": 0.3, "bright": false}
	for key in opts:
		e[key] = opts[key]
	plan["elements"].append(e)
	plan["life"] = maxf(float(plan["life"]), t0 + dur)
	return e


static func _label(plan: Dictionary, text: String, at: Vector3, col: Color, life: float = 1.4) -> void:
	plan["labels"].append({"text": text, "at": at, "col": col, "life": life})


static func _foot(f: Dictionary) -> Vector3:
	return f.get("foot", Vector3.ZERO)


static func _head(f: Dictionary) -> Vector3:
	return f.get("head", _foot(f) + Vector3.UP * 6.0)


static func _mid(f: Dictionary, k: float) -> Vector3:
	return _foot(f).lerp(_head(f), k)


static func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## True when a plan draws or says something.
static func has_beat(plan: Dictionary) -> bool:
	return not (plan["elements"] as Array).is_empty() or not (plan["labels"] as Array).is_empty()


## A plan's instance count by layer: {"ground", "sprites", "beams"} (the budget tests and the rung comparisons).
static func counts(plan: Dictionary) -> Dictionary:
	var out := {"ground": 0, "sprites": 0, "beams": 0}
	for e in plan["elements"]:
		var k: int = int(KINDS[String(e["k"])])
		if k >= BEAM:
			out["beams"] += 1
		elif k <= GROUND_MAX:
			out["ground"] += 1
		else:
			out["sprites"] += 1
	return out


## All of a plan's instances.
static func size(plan: Dictionary) -> int:
	return (plan["elements"] as Array).size()


# ------------------------------------------------------------------ battle spells (§12.2)

## `args`: "caster" and "target"/"targets" ({"foot", "head", "r"?} each), "col" (the caster's side colour, for its ring),
## "life" (seconds left of the round, for a hex or shield), "name", "damage", "part" ({"stat", "value"}), "self" (a bolt's
## bleeding), "front" ([a, b], Sunburst's enemy front), "reach" (how far its ring runs), "fighters" (heal_back's healed).
static func battle(effect: String, rung: int, args: Dictionary, reduced: bool = false) -> Dictionary:
	rung = clamp_rung(rung)
	var plan := _plan(effect, rung)
	match effect:
		"sunlance":
			_bolt(plan, args, "sun", reduced)
		"bloodbolt":
			_bolt(plan, args, "blood", reduced)
		"briar_snare":
			_snare(plan, args, reduced)
		"shield_of_law":
			_shield(plan, args, reduced)
		"draw_the_warmth":  # CW-5: the Wick's bolt, in its own lilac, with no self-bleed
			_bolt(plan, args, "wick", reduced)
		"wax_skin":  # CW-5: Wax's shield, in honey
			_shield(plan, args, reduced, "wax")
		"sunburst":
			_sunburst(plan, args, reduced)
		"heal_back":
			_heal_back(plan, args, reduced)
	return plan


## The effect a `cast` event of `kind` and `spell` plays ("" for none).
static func effect_of(kind: String, spell: String) -> String:
	if BATTLE_EFFECTS.has(spell):
		return spell
	return String(KIND_EFFECT.get(kind, ""))


## The caster's ring: its side's colour under its feet while it casts (ownership of an untinted effect, §12.2).
static func _caster_ring(plan: Dictionary, args: Dictionary, life: float) -> void:
	var c: Dictionary = args.get("caster", {})
	if c.is_empty():
		return
	var col: Color = args.get("col", Color.WHITE)
	_add(plan, "ring", _foot(c) + Vector3.UP * 0.25, float(c.get("r", 3.2)), 0.0, life, _alpha(col, 0.95), {"fin": 0.06, "fout": life * 0.5})
	## VFX-WIRE: the channel loops on the ground under the caster while it casts, turned to its facing (the ring stays: it is the owner's)
	_sheet(plan, "cast_channel", _foot(c) + Vector3.UP * 0.2, float(c.get("r", 3.2)), 0.0, life, Color(1, 1, 1, 0.95), float(c.get("yaw", 0.0)),
		{"fin": 0.06, "fout": life * 0.5})


static func _bolt(plan: Dictionary, args: Dictionary, school: String, reduced: bool) -> void:
	var rung: int = plan["rung"]
	var c: Dictionary = args.get("caster", {})
	var t: Dictionary = args.get("target", {})
	var pal: Dictionary = SCHOOL_COLOURS[school]
	var main: Color = pal["main"]
	var hot: Color = pal["hot"]
	var from := _mid(c, 0.78)
	var to := _mid(t, 0.58)
	var blood := school == "blood"
	var style := 0 if rung <= 2 else (1 if rung == 3 else 2) ## full glow beam, plain beam, a straight line
	var life := 0.42
	_caster_ring(plan, args, 0.7)
	if rung <= 2:
		## the beam's trail: a wider, fainter copy that lingers
		_add(plan, "beam", from, 2.6, 0.0, 0.8, _alpha(main, 0.45), {"to": to, "w": 3.0, "fin": 0.03, "fout": 0.6, "head": 0.0 if reduced else 0.2})
	_add(plan, "beam", from, 1.05 if style == 0 else (0.75 if style == 1 else 0.32), 0.0, life, _alpha(hot if style == 0 else main, 0.95),
		{"to": to, "w": float(style), "fin": 0.02, "fout": 0.28, "head": 0.0 if reduced else 0.22, "bright": style == 0})
	if rung <= 1:
		_add(plan, "glow", from, 4.6, 0.0, 0.5, _alpha(main, 0.7), {"fin": 0.05, "fout": 0.35})
		_add(plan, "glow", to, 4.2, 0.1, 0.45, _alpha(main, 0.65), {"fin": 0.04, "fout": 0.35})
	## the impact sheet (art: sun_flare, blood_spray): a starburst, half size from rung 4
	var sheet := 5.6 if rung <= 3 else 2.8
	_add(plan, "blood_spray" if blood else "burst", to, sheet, 0.1, 0.34, _alpha(main if blood else GILT_HOT, 0.85), {"fin": 0.03, "fout": 0.25, "bright": true,
		"seed": h01(int(to.x * 10.0), int(to.z * 10.0))})
	if not reduced:
		var motes := BOLT_PARTICLES if rung <= 1 else (3 if rung == 2 else 0)
		for i in motes:
			var a := h01(i, 11) * TAU
			_add(plan, "mote", to + Vector3(cos(a), 0.3, sin(a)) * 0.8, 0.5 + h01(i, 3) * 0.4, 0.12 + h01(i, 5) * 0.08, 0.4 + h01(i, 7) * 0.25,
				_alpha(hot if i % 2 == 0 else main, 0.9), {"up": 2.0 + h01(i, 9) * 2.5, "yaw": a, "fin": 0.02, "fout": 0.25})
	if blood and int(args.get("self", 0)) > 0:
		## the caster bleeds: a crimson mist rising from it
		_add(plan, "mist", _mid(c, 0.5), 2.4, 0.05, 0.7, _alpha(BLOOD_DEEP, 0.55), {"up": 3.0 if not reduced else 0.0, "fin": 0.1, "fout": 0.45})
		_label(plan, "-%d hp" % int(args["self"]), _head(c) + Vector3.UP * 1.4, BLOOD, 1.0)
	var dmg := int(args.get("damage", 0))
	var nm := String(args.get("name", "Sunlance" if school == "sun" else "Bloodbolt"))
	_label(plan, "%s %d" % [nm, dmg] if dmg > 0 else nm, _head(c) + Vector3.UP * 3.2, hot if not blood else Color("#FFB0A8"))
	plan["flash"] = true
	if reduced:
		plan["flash"] = false


static func _snare(plan: Dictionary, args: Dictionary, reduced: bool) -> void:
	var rung: int = plan["rung"]
	var c: Dictionary = args.get("caster", {})
	var targets: Array = args.get("targets", [])
	var life := maxf(float(args.get("life", 2.0)), 0.6)
	var col: Color = args.get("col", Color.WHITE)
	plan["life"] = life
	_caster_ring(plan, args, 0.7)
	if rung <= 2:
		_add(plan, "glow", _mid(c, 0.78), 3.2, 0.0, 0.5, _alpha(WILD, 0.55), {"fin": 0.05, "fout": 0.3})
	var n := targets.size()
	for i in n:
		var tg: Dictionary = targets[i]
		var foot := _foot(tg) + Vector3.UP * 0.3
		var r := float(tg.get("r", 3.2))
		var t0 := 0.1 + 0.03 * mini(i, 8)
		## the decal ring at the target's feet: the caster's side colour under green thorns, for the round
		_add(plan, "ring", foot, r * 1.05, t0, life - t0, _alpha(col, 0.9), {"fin": 0.2, "fout": 0.25})
		## VFX-WIRE: the briars burst from the ground at its feet as the snare lands, turned to its facing
		_sheet(plan, "briar_burst", foot + Vector3.UP * 0.05, r, t0, 0.0, Color(1, 1, 1, 1.0), float(tg.get("yaw", 0.0)))
		_add(plan, "thorn_ring", foot + Vector3.UP * 0.05, r * 1.0, t0, life - t0, _alpha(WILD, 0.95), {"fin": 0.25, "fout": 0.25, "yaw": h01(i, 4) * TAU,
			"w": 0.0 if reduced else 1.0, "seed": float(i)})
		if rung <= 2:
			for v in 2:
				var a := (float(v) + h01(i, 2)) * PI
				_add(plan, "vine", foot + Vector3(cos(a), 0.0, sin(a)) * r * 0.7, 3.6, t0 + 0.05, life - t0 - 0.05, _alpha(WILD_DEEP, 0.95),
					{"fin": 0.45, "fout": 0.25, "seed": h01(i, 13 + v), "w": 0.0 if reduced else 1.0, "up": 0.0})
		if rung <= 3:
			## the billboard briar over the fighter's legs
			_add(plan, "briar", _mid(tg, 0.32), 3.0, t0 + 0.12, life - t0 - 0.12, _alpha(WILD, 0.95), {"fin": 0.3, "fout": 0.25, "seed": h01(i, 6)})
	if rung <= 2 and not reduced and n > 0:
		## 32 particles on rung 0-1, 16 on rung 2, shared out over the targets
		var total := 32 if rung <= 1 else 16
		for p in total:
			var tg2: Dictionary = targets[p % n]
			var a2 := h01(p, 21) * TAU
			var rr := float(tg2.get("r", 3.2)) * (0.3 + 0.7 * h01(p, 23))
			_add(plan, "leaf" if p % 3 == 0 else "mote", _foot(tg2) + Vector3(cos(a2) * rr, 0.6, sin(a2) * rr), 0.45 + h01(p, 25) * 0.3,
				0.2 + h01(p, 27) * 0.9, 0.9 + h01(p, 29) * 0.5, _alpha(WILD if p % 2 == 0 else Color("#D6F5B0"), 0.9),
				{"up": 3.0 + h01(p, 31) * 3.0, "yaw": a2, "fin": 0.1, "fout": 0.4})
	var part: Dictionary = args.get("part", {})
	var txt := String(args.get("name", "Briar Snare"))
	if not part.is_empty():
		txt += " %d %s" % [int(part.get("value", 0)), String(part.get("stat", "attack"))]
	if not c.is_empty():
		_label(plan, txt, _head(c) + Vector3.UP * 3.2, Color("#D6F5B0"))
	plan["flash"] = false


static func _shield(plan: Dictionary, args: Dictionary, reduced: bool, school: String = "law") -> void:
	var rung: int = plan["rung"]
	var main: Color = SCHOOL_COLOURS[school]["main"]  # CW-5: Wax Skin's honey; Law's blue for Shield of Law, as before
	var c: Dictionary = args.get("caster", {})
	var targets: Array = args.get("targets", [])
	var life := maxf(float(args.get("life", 2.0)), 0.6)
	var col: Color = args.get("col", Color.WHITE)
	var pulse := rung <= 2 and not reduced
	plan["life"] = life
	_caster_ring(plan, args, 0.7)
	if rung <= 1:
		_add(plan, "glow", _mid(c, 0.78), 3.2, 0.0, 0.5, _alpha(main, 0.55), {"fin": 0.05, "fout": 0.3})
	for i in targets.size():
		var tg: Dictionary = targets[i]
		var t0 := 0.1 + 0.03 * mini(i, 8)
		if rung <= 3:
			## a translucent shield quad before each covered fighter: a rim that pulses on rung 0-2
			_add(plan, "shield", _mid(tg, 0.5), 3.8, t0, life - t0, _alpha(main, 0.8), {"fin": 0.25, "fout": 0.25, "w": 1.0 if pulse else 0.0, "seed": h01(i, 8)})
		else:
			## a ▲ decal under each covered fighter, in the caster's side colour (ownership is the decal's colour)
			_add(plan, "tri", _foot(tg) + Vector3.UP * 0.3, float(tg.get("r", 3.2)) * 1.0, t0, life - t0, _alpha(col, 0.95), {"fin": 0.2, "fout": 0.25,
				"yaw": float(args.get("yaw", 0.0))})
	var part: Dictionary = args.get("part", {})
	var txt := String(args.get("name", "Shield of Law"))
	if not part.is_empty():
		txt += " +%d %s" % [int(part.get("value", 0)), String(part.get("stat", "defense"))]
	if not c.is_empty():
		_label(plan, txt, _head(c) + Vector3.UP * 3.2, SCHOOL_COLOURS[school]["hot"])
	plan["flash"] = false


static func _sunburst(plan: Dictionary, args: Dictionary, reduced: bool) -> void:
	var rung: int = plan["rung"]
	var c: Dictionary = args.get("caster", {})
	var targets: Array = args.get("targets", [])
	var reach := maxf(float(args.get("reach", 40.0)), 8.0)
	var life := maxf(float(args.get("life", 2.0)), 0.6)
	var from := _foot(c)
	plan["life"] = life
	_caster_ring(plan, args, 0.9)
	## the glare ring sweeping the enemy front: a ring on the ground running out from the caster past the front (still with reduced motion)
	var sweep := 0.9
	_add(plan, "glare_ring", from + Vector3.UP * 0.35, reach + 14.0, 0.05, sweep, _alpha(GILT, 0.95),
		{"r0": reach + 14.0 if reduced else 3.0, "fin": 0.06, "fout": 0.4 if not reduced else 0.7, "w": 0.0})
	## the flare sheet at the caster (rung 0-3): a four-point flare, asked of the flash limiter, never a white-out
	if rung <= 3:
		_add(plan, "flare", _mid(c, 0.9), 17.0, 0.0, 0.6, _alpha(GILT, 0.95), {"fin": 0.04, "fout": 0.45, "bright": not reduced})
	if rung <= 1:
		## the bloom: a big soft glow, never above 45% so it brightens the field without whiting it out
		_add(plan, "glow", _mid(c, 0.9), 34.0, 0.0, 0.8, _alpha(GILT, 0.45), {"fin": 0.08, "fout": 0.6})
	if rung <= 2 and not reduced:
		## the enemy fighters it passes over take a small glare as the ring reaches them (a sample of the front)
		var cap := 16 if rung <= 1 else 8
		var n := targets.size()
		var step := maxi(1, int(ceil(float(n) / float(cap)))) if n > 0 else 1
		var k := 0
		while k < n and (k / step) < cap:
			var tg: Dictionary = targets[k]
			var d := (_foot(tg) - from).length()
			_add(plan, "glow", _mid(tg, 0.65), 4.2, 0.05 + clampf(d / (reach + 14.0), 0.0, 1.0) * sweep * 0.9, 0.7, _alpha(GILT_HOT, 0.75), {"fin": 0.05, "fout": 0.5})
			k += step
	plan["shake"] = 4.0 if rung <= 2 and not reduced else 0.0
	plan["flash"] = rung <= 3 and not reduced
	var part: Dictionary = args.get("part", {})
	var txt := String(args.get("name", "Sunburst"))
	if not part.is_empty():
		txt += " %d %s" % [int(part.get("value", 0)), String(part.get("stat", "attack"))]
	if not c.is_empty():
		_label(plan, txt, _head(c) + Vector3.UP * 3.6, GILT_HOT, 1.8)


static func _heal_back(plan: Dictionary, args: Dictionary, reduced: bool) -> void:
	var rung: int = plan["rung"]
	var fighters: Array = args.get("fighters", [])
	for fi in fighters.size():
		var f: Dictionary = fighters[fi]
		var foot := _foot(f)
		var healed := int(f.get("healed", 0))
		if not reduced:
			## rising motes from the feet: 24 on rung 0-1, 12 on rung 2, numbers only from rung 3
			var total := 24 if rung <= 1 else (12 if rung == 2 else 0)
			for p in total:
				var a := h01(p, 41 + fi) * TAU
				_add(plan, "plus" if p % 4 == 0 else "mote", foot + Vector3(cos(a), 0.4, sin(a)) * (0.4 + 1.8 * h01(p, 43)), 0.5 + h01(p, 45) * 0.35,
					0.05 + h01(p, 47) * 0.55, 0.7 + h01(p, 49) * 0.4, _alpha(Color("#7FE08A") if p % 2 == 0 else Color("#C8F5CC"), 0.9),
					{"up": 5.0 + h01(p, 51) * 4.0, "yaw": a, "fin": 0.1, "fout": 0.4})
		_label(plan, "+%d hp" % healed if healed > 0 else "heals back", _head(f) + Vector3.UP * 1.0, Color("#7FE08A"), 0.9)
	plan["flash"] = false


# ------------------------------------------------------------------ the map (§12.2, §12.3)

## The board key of a beat of Playback.plan's "rituals": a cast by its ritual's kind, else the event's type.
static func board_key(beat: Dictionary) -> String:
	var t := String(beat.get("kind", ""))
	if t == "ritual_cast":
		var kind := String(beat.get("rkind", ""))
		return "cast:%s" % (kind if not kind.is_empty() else "ward")
	return t


## The school of a ritual (its colours): its school (MagicRules.spell_data: CW-5, the preview's spells too), "common" for Far
## Sight and anything unknown.
static func school_of(ritual: String) -> String:
	var row: Dictionary = MagicRules.spell_data(ritual)
	var s := String(row.get("school", "common"))
	return s if SCHOOL_COLOURS.has(s) else "common"


## The kind of a ritual (its "kind", MagicRules.spell_data: CW-5, the preview's spells too), "" when unknown.
static func rkind_of(ritual: String) -> String:
	return String(MagicRules.spell_data(ritual).get("kind", ""))


## `args`: "at" (the target's point), "from" (the visible caster's, or absent), "path" (a PackedVector3Array along the roads),
## "r" (the province's radius), "school", "col" (the caster's side colour), "armies" ([{"at", "r"}]), "global" (no place),
## "count" (creatures), "height" (a fort's), "ward" (the band that turned a ritual aside: {"at", "r"}), "rkind" (the ritual's kind),
## "ekind" (an enchantment's kind), "map" (a point over the middle of the map, for a moon). For "summoned" and "summon_faded" `r` is the
## army's radius, not the province's.
static func board(key: String, rung: int, args: Dictionary, reduced: bool = false) -> Dictionary:
	rung = clamp_rung(rung)
	var plan := _plan(key, rung)
	var school := String(args.get("school", "common"))
	if not SCHOOL_COLOURS.has(school):
		school = "common"
	var pal: Dictionary = SCHOOL_COLOURS[school]
	var main: Color = pal["main"]
	var hot: Color = pal["hot"]
	var at: Vector3 = args.get("at", Vector3.ZERO)
	var r: float = float(args.get("r", 40.0))
	match key:
		"ritual_turned_aside":
			## a fizzle at the caster (when the viewer sees it) and the ward's band flashing at the target
			if args.has("from"):
				var f: Vector3 = args["from"]
				_add(plan, "puff", f + Vector3.UP * 4.0, 5.0, 0.0, 0.9, _alpha(SMOKE, 0.7), {"up": 0.0 if reduced else 5.0, "fin": 0.08, "fout": 0.6})
				_add(plan, "fizzle_ring", f + Vector3.UP * 0.3, 9.0, 0.0, 0.8, _alpha(main, 0.8), {"r0": 9.0 if reduced else 2.0, "fin": 0.05, "fout": 0.5})
			var ward: Dictionary = args.get("ward", {"at": at, "r": r * WARD_K})
			_add(plan, "band", (ward["at"] as Vector3) + Vector3.UP * 0.3, float(ward["r"]), 0.15, 1.1, _alpha(LAW, 0.85), {"fin": 0.08, "fout": 0.7, "w": 0.0})
			if rung <= 2 and not reduced:
				_add(plan, "glow", at + Vector3.UP * 5.0, 9.0, 0.15, 0.7, _alpha(LAW, 0.5), {"fin": 0.05, "fout": 0.5})
		"ritual_fell":
			## the effect arrives at the target with no direction: a column coming down from above, then the decal
			var fk := String(args.get("rkind", ""))
			_arrive(plan, rung, reduced, school, fk if not fk.is_empty() else "curse", at, r, 0.0)
		"blood_paid":
			var src: Vector3 = args.get("from", at)
			var n := 12 if rung <= 1 else (6 if rung == 2 else 0)
			if not reduced:
				for i in n:
					var a := h01(i, 61) * TAU
					_add(plan, "mist", src + Vector3(cos(a), 0.5, sin(a)) * (1.0 + 3.0 * h01(i, 63)), 1.8 + h01(i, 65) * 1.2, 0.05 + h01(i, 67) * 0.5, 1.0 + h01(i, 69) * 0.5,
						_alpha(BLOOD_DEEP, 0.5), {"up": 6.0 + h01(i, 71) * 4.0, "fin": 0.15, "fout": 0.6})
			_add(plan, "mist", src + Vector3.UP * 1.5, 4.5, 0.0, 1.0, _alpha(BLOOD, 0.45), {"up": 0.0 if reduced else 5.0, "fin": 0.12, "fout": 0.7})
			_add(plan, "ring", src + Vector3.UP * 0.3, 6.0, 0.0, 0.9, _alpha(BLOOD, 0.8), {"fin": 0.05, "fout": 0.5})
		"summoned":
			## a briar ring the creatures step out of; thorns shoot up from it (CW-5: the Snuffed's in Wax's honey)
			_summon_ring(plan, rung, reduced, at, maxf(r, 6.0), WILD if school == "wild" or school == "common" else main,
				float(args.get("yaw", 0.0)))  # VFX-WIRE: turned to the summons' facing
		"summon_faded":
			## the creatures dissolve into leaves (CW-5: the Snuffed into flakes of Wax's honey)
			var wild := school == "wild" or school == "common"
			var nl := 16 if rung <= 1 else (8 if rung == 2 else 0)
			if not reduced:
				for i in nl:
					var a2 := h01(i, 81) * TAU
					_add(plan, "leaf", at + Vector3(cos(a2), 0.4, sin(a2)) * (h01(i, 83) * maxf(r, 4.0)), 0.7 + h01(i, 85) * 0.4, h01(i, 87) * 0.5, 1.0 + h01(i, 89) * 0.5,
						_alpha((WILD if wild else main) if i % 2 == 0 else (Color("#D6F5B0") if wild else hot), 0.9), {"up": 5.0 + h01(i, 91) * 5.0, "yaw": a2, "fin": 0.1, "fout": 0.6})
			_add(plan, "thorn_ring", at + Vector3.UP * 0.3, maxf(r, 5.0), 0.0, 1.0, _alpha(WILD if wild else main, 0.85), {"fin": 0.05, "fout": 0.8, "w": 0.0})
			_add(plan, "puff", at + Vector3.UP * 3.0, maxf(r, 5.0) * 0.8, 0.0, 0.9, _alpha(WILD_DEEP if wild else main.darkened(0.4), 0.5), {"fin": 0.1, "fout": 0.6, "up": 0.0 if reduced else 3.0})
		"fort_raised":
			_raise(plan, rung, reduced, at, r, float(args.get("height", 16.0)))
		"enchantment_began":
			_began(plan, rung, reduced, String(args.get("ekind", "")), args, school)
		"enchantment_ended":
			_ended(plan, rung, reduced, String(args.get("ekind", "")), args, school)
		"blessing_healed":
			var arm: Array = args.get("armies", [])
			if arm.is_empty():
				arm = [{"at": at, "r": maxf(r * 0.3, 6.0)}]
			for ai in arm.size():
				var ar: Dictionary = arm[ai]
				var ac: Vector3 = ar["at"]
				_add(plan, "sun_ring", ac + Vector3.UP * 0.3, float(ar["r"]), 0.0, 1.1, _alpha(GILT, 0.85), {"fin": 0.08, "fout": 0.6})
				var nm := (10 if rung <= 1 else (5 if rung == 2 else 0)) if not reduced else 0
				for i in nm:
					var a3 := h01(i, 101 + ai) * TAU
					var rr := float(ar["r"]) * h01(i, 103)
					_add(plan, "plus" if i % 3 == 0 else "mote", ac + Vector3(cos(a3) * rr, 0.5, sin(a3) * rr), 0.7 + h01(i, 105) * 0.4, h01(i, 107) * 0.5, 0.9 + h01(i, 109) * 0.4,
						_alpha(GILT_HOT if i % 2 == 0 else GILT, 0.9), {"up": 5.0 + h01(i, 111) * 4.0, "yaw": a3, "fin": 0.1, "fout": 0.5})
				if rung >= 3 or reduced:
					_add(plan, "plus", ac + Vector3.UP * 4.0, 2.2, 0.1, 0.9, _alpha(GILT_HOT, 0.9), {"fin": 0.1, "fout": 0.6})
		"curse_bit":
			var arm2: Array = args.get("armies", [])
			if arm2.is_empty():
				arm2 = [{"at": at, "r": maxf(r * 0.3, 6.0)}]
			_add(plan, "veins", at + Vector3.UP * 0.3, r * VEIN_K, 0.0, 1.0, _alpha(BLOOD, 0.9), {"fin": 0.08, "fout": 0.6, "w": 0.0})
			for ai2 in arm2.size():
				var ar2: Dictionary = arm2[ai2]
				var ac2: Vector3 = ar2["at"]
				var nb := (8 if rung <= 1 else (4 if rung == 2 else 0)) if not reduced else 0
				for i in nb:
					var a4 := h01(i, 121 + ai2) * TAU
					var rr2 := float(ar2["r"]) * h01(i, 123)
					_add(plan, "mote", ac2 + Vector3(cos(a4) * rr2, 6.0, sin(a4) * rr2), 0.6 + h01(i, 125) * 0.4, h01(i, 127) * 0.4, 0.8, _alpha(BLOOD, 0.9),
						{"up": -5.0, "yaw": a4, "fin": 0.05, "fout": 0.4})
				_add(plan, "ring", ac2 + Vector3.UP * 0.3, float(ar2["r"]), 0.05, 0.9, _alpha(BLOOD, 0.8), {"fin": 0.06, "fout": 0.5})
		"far_sight_reading":
			## the eye opens over the rival capital
			_add(plan, "eye", at + Vector3.UP * 24.0, 13.0, 0.0, 1.8, _alpha(SIGHT, 0.95), {"fin": 0.25, "fout": 0.6, "w": 0.0 if rung >= 2 or reduced else 1.0})
			_add(plan, "ring", at + Vector3.UP * 0.3, r * SIGHT_K, 0.0, 1.5, _alpha(SIGHT, 0.8), {"fin": 0.1, "fout": 0.8})
			if rung <= 1 and not reduced:
				_add(plan, "glow", at + Vector3.UP * 20.0, 18.0, 0.0, 1.5, _alpha(SIGHT, 0.35), {"fin": 0.2, "fout": 0.8})
		_:
			if key.begins_with("cast:"):
				_cast(plan, key.trim_prefix("cast:"), rung, reduced, school, args)
	return plan


## A ritual cast (§12.2): a beam at a visible caster, a mote along the roads to the target, then the decal. Rung 3 has no mote, rung
## 4-5 the decal alone. A cast with no place (a global ritual) is a moon over the map.
static func _cast(plan: Dictionary, kind: String, rung: int, reduced: bool, school: String, args: Dictionary) -> void:
	var pal: Dictionary = SCHOOL_COLOURS[school]
	var main: Color = pal["main"]
	var hot: Color = pal["hot"]
	var at: Vector3 = args.get("at", Vector3.ZERO)
	var r: float = float(args.get("r", 40.0))
	var travel := 0.0
	if args.has("from") and rung <= 3:
		var f: Vector3 = args["from"]
		## the caster's pillar of light: a beam going up, in the school's colour
		_add(plan, "column", f, 4.2, 0.0, 1.1, _alpha(main, 0.95), {"to": f + Vector3.UP * 46.0, "fin": 0.08, "fout": 0.8})
		_add(plan, "glow", f + Vector3.UP * 2.0, 10.0, 0.0, 0.9, _alpha(hot, 0.75), {"fin": 0.05, "fout": 0.7})
		if rung <= 2 and not reduced:
			var path: PackedVector3Array = args.get("path", PackedVector3Array([f, at]))
			travel = 1.1
			## the mote along the roads, with a short tail of fading glows behind it
			for tail in 4:
				_add(plan, "glow" if tail == 0 else "mote", f, 2.6 - 0.45 * tail, 0.45 + 0.05 * tail, travel, _alpha(hot if tail == 0 else main, 0.9 - 0.18 * tail),
					{"path": path, "up": 4.0, "fin": 0.04, "fout": 0.2})
	if bool(args.get("global", false)) or not args.has("at"):
		_moon(plan, rung, reduced, args.get("map", at), school)
		return
	_arrive(plan, rung, reduced, school, kind, at, r, travel, float(args.get("yaw", 0.0)))  # VFX-WIRE: a summoning ring turns with its summons


## What arrives at the target: the ritual's decal, in its `kind`'s look, after `delay` seconds.
static func _arrive(plan: Dictionary, rung: int, reduced: bool, school: String, kind: String, at: Vector3, r: float, delay: float, yaw: float = 0.0) -> void:
	var pal: Dictionary = SCHOOL_COLOURS[school]
	var main: Color = pal["main"]
	var hot: Color = pal["hot"]
	var land := at + Vector3.UP * 0.3
	if rung <= 2 and not reduced:
		## a shaft of light coming down onto the target
		_add(plan, "column", at + Vector3.UP * 46.0, 4.5, delay, 0.8, _alpha(main, 0.9), {"to": at, "fin": 0.05, "fout": 0.5, "head": 0.3})
	match kind:
		"blessing":  # CW-5: Candlemass's in Wax's honey; Dawn Blessing's gilt, as before
			_add(plan, "sun_ring", land, r * 0.6, delay, 1.4, _alpha(GILT if school == "sun" or school == "common" else main, 0.9),
				{"r0": r * 0.6 if reduced else r * 0.1, "fin": 0.1, "fout": 0.8})
		"flame":  # CW-5, Kindle: a ring at the army it warms, and a lick of flame rising from it
			_add(plan, "ring", land, r * 0.3, delay, 1.4, _alpha(main, 0.9), {"fin": 0.1, "fout": 0.8})
			_add(plan, "column", land, 3.0, delay + 0.1, 1.1, _alpha(hot, 0.9), {"to": land + Vector3.UP * 16.0, "fin": 0.1, "fout": 0.6})
		"ward":
			_add(plan, "band", land, r * WARD_K, delay, 1.4, _alpha(LAW, 0.9), {"r0": r * WARD_K if reduced else r * 0.2, "fin": 0.1, "fout": 0.8})
		"curse":
			_add(plan, "veins", land, r * VEIN_K, delay, 1.4, _alpha(BLOOD, 0.9), {"r0": r * VEIN_K if reduced else r * 0.2, "fin": 0.1, "fout": 0.8})
		"summon":
			_add(plan, "summon_ring", land, r * 0.35, delay, 1.4, _alpha(WILD, 0.9), {"fin": 0.1, "fout": 0.8, "yaw": yaw})
		"raising":
			_add(plan, "dust_ring", land, r * 0.35, delay, 1.4, _alpha(GILT, 0.85), {"fin": 0.1, "fout": 0.8})
		"sight":
			_add(plan, "ring", land, r * SIGHT_K, delay, 1.4, _alpha(SIGHT, 0.9), {"fin": 0.1, "fout": 0.8})
			_add(plan, "eye", at + Vector3.UP * 24.0, 11.0, delay + 0.2, 1.2, _alpha(SIGHT, 0.95), {"fin": 0.2, "fout": 0.6})
		_:
			_add(plan, "ring", land, r * 0.45, delay, 1.4, _alpha(main, 0.9), {"fin": 0.1, "fout": 0.8})
	if rung <= 1 and not reduced:
		_add(plan, "glow", at + Vector3.UP * 5.0, r * 0.35, delay, 0.9, _alpha(hot, 0.4), {"fin": 0.08, "fout": 0.6})
	plan["life"] = maxf(float(plan["life"]), delay + 1.4)


## A global ritual (the Blood Moon): a moon over the map, in the school's colour; it starts nowhere (§12.1).
static func _moon(plan: Dictionary, rung: int, reduced: bool, over: Vector3, school: String) -> void:
	var main: Color = SCHOOL_COLOURS[school]["main"]
	_add(plan, "moon", over + Vector3.UP * 60.0, 62.0, 0.0, 2.6, _alpha(main, 0.9), {"fin": 0.5, "fout": 1.2, "up": 0.0 if reduced else 6.0})
	if rung <= 1 and not reduced:
		_add(plan, "glow", over + Vector3.UP * 60.0, 90.0, 0.0, 2.6, _alpha(main, 0.25), {"fin": 0.6, "fout": 1.2})
	if rung >= 4 or reduced:
		_add(plan, "ring", over + Vector3.UP * 0.3, 60.0, 0.0, 2.0, _alpha(main, 0.7), {"fin": 0.2, "fout": 1.2})


## A summoning ring (the creatures step out of it) or a Bastion's: fade in from rung 3, pop in from rung 4.
static func _summon_ring(plan: Dictionary, rung: int, reduced: bool, at: Vector3, r: float, col: Color, yaw: float = 0.0) -> void:
	var fin := 0.7 if (rung <= 2 and not reduced) else (0.3 if rung == 3 else 0.02)
	_add(plan, "summon_ring", at + Vector3.UP * 0.3, r, 0.0, 2.0, _alpha(col, 0.95), {"fin": fin, "fout": 0.9, "r0": r if (rung >= 3 or reduced) else r * 0.3,
		"yaw": yaw})
	if rung <= 2 and not reduced:
		var n := 14 if rung <= 1 else 7
		for i in n:
			var a := TAU * float(i) / float(n)
			_add(plan, "briar", at + Vector3(cos(a), 0.0, sin(a)) * r * 0.85, 2.4, 0.2 + 0.04 * i, 1.6, _alpha(WILD_DEEP, 0.95), {"fin": 0.3, "fout": 0.6, "seed": h01(i, 131)})
		for i in (10 if rung <= 1 else 5):
			var a2 := h01(i, 133) * TAU
			_add(plan, "leaf", at + Vector3(cos(a2), 0.3, sin(a2)) * r * 0.6, 0.6, 0.3 + h01(i, 135) * 0.6, 1.0, _alpha(WILD, 0.9), {"up": 5.0, "yaw": a2, "fin": 0.1, "fout": 0.5})


## A fort raised (Bastion): it rises behind scaffolding (the board's own rising fort draws the building, §12.2): here the dust ring
## and motes round it. Fade in from rung 3, pop in from rung 4.
static func _raise(plan: Dictionary, rung: int, reduced: bool, at: Vector3, r: float, height: float) -> void:
	_add(plan, "dust_ring", at + Vector3.UP * 0.3, maxf(r, 14.0), 0.0, 1.8, _alpha(GILT, 0.85), {"fin": 0.7 if (rung <= 2 and not reduced) else (0.3 if rung == 3 else 0.02), "fout": 0.9,
		"r0": maxf(r, 14.0) if (rung >= 4 or reduced) else 6.0})
	if rung <= 2 and not reduced:
		for i in (12 if rung <= 1 else 6):
			var a := h01(i, 141) * TAU
			_add(plan, "puff", at + Vector3(cos(a), 0.2, sin(a)) * maxf(r, 14.0) * 0.8, 3.0 + h01(i, 143) * 2.0, h01(i, 145) * 0.8, 1.0, _alpha(Color("#CFC6B2"), 0.55),
				{"up": height * 0.5, "fin": 0.2, "fout": 0.6})
	_add(plan, "glow", at + Vector3.UP * height * 0.6, maxf(r, 14.0) * 0.8, 0.0, 1.2, _alpha(GILT, 0.35), {"fin": 0.2, "fout": 0.8})


static func _began(plan: Dictionary, rung: int, reduced: bool, ekind: String, args: Dictionary, school: String) -> void:
	## an enchantment's decal comes on: the standing decal grows in from the cast (the elements here are the flash that marks it)
	var main: Color = SCHOOL_COLOURS[school]["main"]
	var at: Vector3 = args.get("at", Vector3.ZERO)
	var r: float = float(args.get("r", 40.0))
	if ekind == "global":
		_moon(plan, rung, reduced, args.get("map", at), school)
		return
	var kind := ekind if STANDING_KINDS.has(ekind) else "ward"
	var pl := standing(kind, rung, args, reduced)
	for e in pl:
		var el: Dictionary = (e as Dictionary).duplicate()
		el["t0"] = 0.0
		el["dur"] = 1.2
		el["fin"] = 0.3 if rung <= 3 else 0.02
		el["fout"] = 0.7
		el["w"] = 0.0
		plan["elements"].append(el)
	plan["life"] = 1.2
	_add(plan, "glow", at + Vector3.UP * 4.0, maxf(r * 0.4, 8.0), 0.0, 0.8, _alpha(main, 0.4), {"fin": 0.1, "fout": 0.6})


static func _ended(plan: Dictionary, rung: int, reduced: bool, ekind: String, args: Dictionary, school: String) -> void:
	## an enchantment ends: its decal fades out (a blessing's rings on its armies, a global's moon setting)
	var main: Color = SCHOOL_COLOURS[school]["main"]
	var at: Vector3 = args.get("at", Vector3.ZERO)
	var r: float = float(args.get("r", 40.0))
	var armies: Array = args.get("armies", [])
	if ekind == "global":
		var over: Vector3 = args.get("map", at)
		_add(plan, "moon", over + Vector3.UP * 60.0, 40.0, 0.0, 1.6, _alpha(main, 0.5), {"fin": 0.05, "fout": 1.2, "up": 0.0 if reduced else -10.0})
		return
	if ekind == "blessing" and not armies.is_empty():
		for ar in armies:
			_add(plan, "sun_ring", (ar["at"] as Vector3) + Vector3.UP * 0.3, float(ar["r"]), 0.0, 1.0, _alpha(GILT, 0.8), {"fin": 0.02, "fout": 0.9})
		return
	var kind := ekind if STANDING_KINDS.has(ekind) else "ward"
	for e in standing(kind, rung, args, reduced):
		var el: Dictionary = (e as Dictionary).duplicate()
		el["t0"] = 0.0
		el["dur"] = 1.0
		el["fin"] = 0.02
		el["fout"] = 0.9
		el["w"] = 0.0
		plan["elements"].append(el)
	plan["life"] = 1.0
	if rung <= 2 and not reduced:
		_add(plan, "puff", at + Vector3.UP * 3.0, maxf(r * 0.3, 6.0), 0.0, 0.8, _alpha(SMOKE, 0.35), {"fin": 0.08, "fout": 0.6, "up": 3.0})


## The elements an enchantment keeps on the map while it lasts (§12.2): a gilt ring under a blessed army, a blue band for a ward,
## crimson veins for a curse, an eye plate for Far Sight. Animated on rung 0-1 (`w` 1: the shader pulses them), still from rung 2.
## `args`: "at", "r" (the province's), or for a blessing "armies" ([{"at", "r"}]). Returns the elements (no labels, no pool).
static func standing(kind: String, rung: int, args: Dictionary, reduced: bool = false) -> Array:
	rung = clamp_rung(rung)
	var plan := _plan("standing:" + kind, rung)
	var anim := 1.0 if rung <= 1 and not reduced else 0.0
	var at: Vector3 = args.get("at", Vector3.ZERO)
	var r: float = float(args.get("r", 40.0))
	var land := at + Vector3.UP * 0.3
	match kind:
		"blessing":
			for ar in args.get("armies", []):
				_add(plan, "sun_ring", (ar["at"] as Vector3) + Vector3.UP * 0.3, float(ar["r"]), 0.0, 1.0, _alpha(GILT, 0.85), {"w": anim, "fin": 0.0, "fout": 0.0, "hold": true})
		"ward":
			_add(plan, "band", land, r * WARD_K, 0.0, 1.0, _alpha(LAW, 0.85), {"w": anim, "fin": 0.0, "fout": 0.0, "hold": true})
		"curse":
			_add(plan, "veins", land, r * VEIN_K, 0.0, 1.0, _alpha(BLOOD, 0.85), {"w": anim, "fin": 0.0, "fout": 0.0, "hold": true})
		"sight":
			_add(plan, "eye", at + Vector3.UP * 24.0, 11.0, 0.0, 1.0, _alpha(SIGHT, 0.95), {"w": anim, "fin": 0.0, "fout": 0.0, "hold": true})
			_add(plan, "ring", land, r * SIGHT_K, 0.0, 1.0, _alpha(SIGHT, 0.6), {"fin": 0.0, "fout": 0.0, "hold": true})
	return plan["elements"]


# ------------------------------------------------------------------ the sound of it (legend, tests)

## The one line a legend row or a tooltip says of an effect.
const LINES := {
	"sunlance": "Sunlance: a gilt beam from the caster to its target, and a starburst where it lands.",
	"bloodbolt": "Bloodbolt: a crimson bolt from the caster, a red splash where it lands, and a mist where the caster bled.",
	"briar_snare": "Briar Snare: a ring of thorns on the ground under each snared unit, and briars climbing it, for the round.",
	"shield_of_law": "Shield of Law: a pale blue shield before each covered unit for the round, with a gold rim.",
	"sunburst": "Sunburst: a ring of gilt light sweeps out over the enemy front rank, and a flare lights the caster.",
	"heal_back": "Blood Moon: green motes rise from a fighter that healed back, with its green +hp.",
}
