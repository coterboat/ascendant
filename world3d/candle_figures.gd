## The Candlewake's figures as code primitives (CW-8, #259; design/CANDLEWAKE.md §10), until CW-9/CW-10's models are approved: the
## host's hollow shells of ivory tallow (a hood of wax round a face that is nothing, a lilac point of wick-light inside, the hem
## dripping), their commander and rulers, their mage and the Snuffed, the candlebeasts, and the Pouring's new units. They are the
## placeholders each Candlewake row in world3d/models.json falls back to ("model": ""), so the GLBs drop in without code changes.
## Every flame-bearing figure carries a soot crown wick, a black stub with no flame (ASSET_MANIFEST.md C.1: a flame baked into the
## mesh would show at flame 0); the board draws the army's flame on it in code (Armies, CandleFigures.flame_look). WICK_TOPS is
## where each wick ends, in the figure's own space (feet at the origin, facing -Z), and each row's "fx_anchor" names it. world3d/kit.gd
## calls build() from its figure() for these ids, with the Kit's own Builder. No dependency on kit.gd (it would be a cycle).
extends RefCounted

const IDS := ["wickwardens", "gleaners", "hundred_wick", "lamplighter", "half_death", "mother_tallow", "chandlers_apprentices", "snuffed",
	"wax_hounds", "tallow_stag", "guttering_bear", "amber_saints", "pyre_walkers"]
## The figures whose army's flame burns on their wick: the host's regulars (rulers, the commander, mages and summoned creatures never
## burn, design/CANDLEWAKE.md §2.1).
const BURNING := ["wickwardens", "gleaners", "hundred_wick", "wax_hounds", "tallow_stag", "guttering_bear", "amber_saints", "pyre_walkers"]

const TEAM := Color(1, 1, 1) ## a team part (alpha 0 in the mesh): the shader paints it in the player's colour
const TALLOW := Color("#D9CAA4") ## ivory tallow (§10's palette), a step warm: the board's sun would blow pure ivory to white
const TALLOW_DK := Color("#B8A781")
const SOOT := Color("#221D26") ## soot-black wicks, and the void where a face would be
const LILAC := Color("#B48CF0") ## the wick-light inside
const BRASS := Color("#B98B3A") ## brass snuffers
const WOOD := Color("#6B4A33")
const IRON := Color("#8A8F96")
const HONEY := Color("#E0B65A") ## the Golden Wake's wax
const CHERRY := Color("#C93A5B") ## the Red Wake's
const GREY_WAX := Color("#A8A296") ## the Snuffed: wax gone cold
const PLUM := Color("#4A2A5E")
const SKIN := Color("#E9B58C")
const HAIR := Color("#5B3A26")
const GOLD_FLAME := Color("#F4C64E") ## the living's warmth burns gold (Mother Tallow's taper)

## Where `type_id`'s crown (or spine) wick ends, in the figure's own space: the flame's foot (Vector3.ZERO for a figure with none).
## Measured by building the figure into a probe that draws nothing, so it can never disagree with the figure; each row's
## "fx_anchor" in world3d/models.json holds the same point (tests/test_cw8_board.gd).
static func wick_top(type_id: String) -> Vector3:
	return build(_Probe.new(), type_id)


static func has(type_id: String) -> bool:
	return IDS.has(type_id)


## True for a type whose army's flame burns on its wick (a regular of the host).
static func burns(type_id: String) -> bool:
	return BURNING.has(type_id)


## How an army's flame shows on a wick (§10: "flame height is the flame"): {} for none (-1: no flame, or a rival's out of clear
## sight), smoke at 0, a lilac flame growing with the flame to a tall one at 3, cherry-red at 4 (the Red Wake). {"h" (height),
## "w" (width), "col" (Color, alpha for the smoke), "smoke" (bool)}.
static func flame_look(flame: int) -> Dictionary:
	match flame:
		0:
			return {"h": 0.9, "w": 0.34, "col": Color(0.55, 0.52, 0.58, 0.55), "smoke": true}
		1:
			return {"h": 0.7, "w": 0.3, "col": LILAC, "smoke": false}
		2:
			return {"h": 1.25, "w": 0.36, "col": Color("#BC97F5"), "smoke": false}
		3:
			return {"h": 1.85, "w": 0.42, "col": Color("#C6A3FA"), "smoke": false}
	if flame >= 4:
		return {"h": 2.35, "w": 0.48, "col": Color("#E03A55"), "smoke": false}
	return {}


## Adds figure `type_id` to Kit builder `b` (feet on y = 0, facing -Z) and returns where its wick ends (Vector3.ZERO for none). The
## Kit adds the base.
static func build(b, type_id: String) -> Vector3:
	var top := Vector3.ZERO
	match type_id:
		"wickwardens":
			top = _shell(b, TALLOW, TALLOW, 1.0)
			b.box(Vector3(1.5, 2.6, 0.18), Vector3(0, 2.2, 0.85), TALLOW_DK) ## the pall hanging at the back
			b.cyl(0.08, 0.08, 4.6, Vector3(1.05, 2.7, -0.25), WOOD, 6) ## the snuffer's pole
			b.cyl(0.0, 0.32, 0.5, Vector3(1.05, 5.15, -0.25), BRASS, 7) ## the brass snuffer
		"gleaners":
			top = _shell(b, TALLOW, TALLOW, 0.97, 0.88)
			b.cyl(0.07, 0.07, 2.6, Vector3(0.95, 2.6, -0.3), WOOD, 6, Basis(Vector3.RIGHT, 0.4)) ## the sickle's haft
			for k in 4: ## and its blade, a hook of iron
				var a := -0.4 + k * 0.5
				b.box(Vector3(0.14, 0.12, 0.55), Vector3(0.95 + sin(a) * 0.5, 3.75 + cos(a) * 0.35, -0.9 - k * 0.12), IRON, Basis(Vector3.UP, a))
		"hundred_wick":
			var crown := _shell(b, TALLOW, TALLOW, 1.28, 1.0, true, false)
			for k in 7: ## the crest of many wicks across the hood, the middle one the tallest (its flame's foot)
				var a := (k - 3) * 0.32
				var hk := 0.7 - absf(k - 3) * 0.12
				var at := Vector3(sin(a) * 0.62, crown.y - absf(k - 3) * 0.08 + hk * 0.5, crown.z)
				b.cyl(0.07, 0.09, hk, at, SOOT, 5)
				if k == 3:
					top = at + Vector3(0, hk * 0.5, 0)
			b.cyl(0.13, 0.13, 6.0, Vector3(-1.45, 3.4, -0.2), WOOD, 6) ## a great guttering torch-staff
			b.ball(0.45, Vector3(-1.45, 6.5, -0.2), TALLOW_DK, Vector3(1.0, 1.4, 1.0), 8)
		"lamplighter":
			top = _shell(b, TALLOW, TALLOW, 1.1)
			b.cyl(0.1, 0.1, 7.6, Vector3(1.25, 4.1, -0.1), WOOD, 6) ## the lamp-pole, taller than he is
			b.box(Vector3(0.9, 0.12, 0.12), Vector3(0.95, 7.7, -0.1), BRASS) ## its crossbar
			b.box(Vector3(0.5, 0.7, 0.5), Vector3(0.6, 7.2, -0.1), BRASS) ## the lantern
			b.ball(0.18, Vector3(0.6, 7.2, -0.1), LILAC, Vector3.ONE, 6)
			b.box(Vector3(0.75, 1.3, 0.12), Vector3(0, 3.0, -1.0), TEAM, Basis(), true) ## a tabard in his host's colour
		"half_death":
			## what is left of the Wright, who died at noon mid-stroke: half ivory wax, half soot, a smith's hammer still raised
			top = _shell(b, TALLOW, TALLOW, 1.0)
			b.box(Vector3(0.95, 3.1, 1.95), Vector3(0.52, 1.95, 0.0), SOOT) ## the dead half of the robe
			b.ball(0.74, Vector3(0.18, 4.23, 0.05), SOOT, Vector3(0.6, 1.06, 1.06), 10) ## and of the hood
			b.cyl(0.1, 0.1, 3.4, Vector3(-1.15, 3.6, -0.3), WOOD, 6, Basis(Vector3.FORWARD, 0.35))
			b.box(Vector3(0.9, 0.6, 0.6), Vector3(-1.75, 5.1, -0.3), IRON, Basis(Vector3.FORWARD, 0.35)) ## the hammer's head
		"mother_tallow":
			## the Ninth Chandler, the one living woman among the dead: plum robes, an ivory shawl, her taper burning gold
			b.cyl(0.6, 1.1, 3.2, Vector3(0, 1.98, 0), PLUM, 10)
			b.cyl(0.95, 0.7, 0.6, Vector3(0, 3.5, 0), TALLOW, 10) ## the shawl
			b.ball(0.52, Vector3(0, 4.35, 0), SKIN, Vector3.ONE, 10)
			b.ball(0.56, Vector3(0, 4.55, 0.12), HAIR, Vector3(1.0, 0.9, 1.0), 10)
			b.cyl(0.22, 0.22, 1.6, Vector3(0.85, 3.6, -0.3), PLUM, 6, Basis(Vector3.FORWARD, 0.5)) ## the arm raised to the taper
			b.cyl(0.13, 0.13, 1.4, Vector3(1.25, 4.9, -0.35), TALLOW, 6) ## the taper
			b.ball(0.22, Vector3(1.25, 5.75, -0.35), GOLD_FLAME, Vector3(1.0, 1.7, 1.0), 6) ## burning gold
			b.box(Vector3(0.7, 1.2, 0.12), Vector3(0, 2.6, -0.98), TEAM, Basis(), true)
		"chandlers_apprentices":
			top = _shell(b, TALLOW, TALLOW, 0.86)
			b.box(Vector3(1.1, 1.8, 0.14), Vector3(0, 1.85, -0.92), SOOT) ## the soot apron
			b.cyl(0.07, 0.07, 1.2, Vector3(0.95, 4.1, -0.4), TALLOW_DK, 5) ## a lilac taper held up
			b.ball(0.13, Vector3(0.95, 4.8, -0.4), LILAC, Vector3(1.0, 1.6, 1.0), 6)
		"snuffed":
			top = _shell(b, GREY_WAX, GREY_WAX, 1.0, 1.0, false) ## wax gone cold: no light inside
			b.box(Vector3(1.5, 2.4, 0.18), Vector3(0, 2.0, 0.85), GREY_WAX.darkened(0.15))
		"wax_hounds":
			top = _beast(b, TALLOW, 1.6, 1.05, 0.95, 0.7)
			b.cyl(0.08, 0.14, 1.1, Vector3(0, 2.0, 1.85), TALLOW_DK, 5, Basis(Vector3.RIGHT, -0.9)) ## the tail, a drip
		"tallow_stag":
			top = _beast(b, TALLOW, 2.5, 1.35, 1.25, 0.95)
			for side in [-1.0, 1.0]: ## antlers of wax, branching
				var root := Vector3(side * 0.35, 4.0, -2.0)
				b.cyl(0.08, 0.12, 1.6, root + Vector3(side * 0.3, 0.7, 0.1), TALLOW_DK, 5, Basis(Vector3.FORWARD, -side * 0.45))
				b.cyl(0.05, 0.08, 0.9, root + Vector3(side * 0.85, 1.35, 0.0), TALLOW_DK, 5, Basis(Vector3.FORWARD, -side * 0.9))
				b.cyl(0.05, 0.08, 0.9, root + Vector3(side * 0.45, 1.6, -0.25), TALLOW_DK, 5, Basis(Vector3.RIGHT, 0.5))
		"guttering_bear":
			## mid-melt, slumping as it walks: one shoulder lower, wax pooling at its feet
			top = _beast(b, TALLOW, 2.55, 1.85, 1.15, 1.1)
			b.ball(0.9, Vector3(0.85, 2.2, -0.9), TALLOW_DK, Vector3(1.0, 0.75, 1.1), 8) ## the sagging shoulder
			for k in 5:
				var a := TAU * float(k) / 5.0
				b.cyl(0.25, 0.4, 0.3, Vector3(cos(a) * 1.4, 0.5, sin(a) * 1.4), TALLOW_DK, 6) ## the pooled wax
		"amber_saints":
			top = _shell(b, HONEY, HONEY, 1.0)
			for k in 10: ## a halo of honey drops behind the hood
				var a := TAU * float(k) / 10.0
				b.ball(0.11, Vector3(cos(a) * 0.95, 4.25 + sin(a) * 0.95, 0.55), HONEY.lightened(0.3), Vector3.ONE, 5)
			b.box(Vector3(1.6, 1.0, 0.16), Vector3(-1.0, 2.8, -0.6), HONEY.darkened(0.2), Basis(Vector3.UP, 0.4)) ## an amber shield
		"pyre_walkers":
			top = _shell(b, TALLOW, TALLOW, 1.03)
			b.cyl(1.05, 0.85, 0.75, Vector3(0, 3.55, 0), CHERRY, 10) ## a scorched cherry mantle
			b.box(Vector3(0.18, 2.4, 0.5), Vector3(1.0, 3.2, -0.5), IRON, Basis(Vector3.FORWARD, 0.25)) ## a hacking blade
	return top


## A hollow shell of wax (§10): a slumped robe dripping at the hem, wide sunken shoulders, a hood round a face of nothing with a lilac
## point of wick-light inside (`lit`), and the soot crown wick on top (`crown`). `k` scales it; `lean` narrows the robe (a Gleaner is
## leaner). Returns the crown wick's top (with no wick: where its foot would be, the hood's top).
static func _shell(b, robe: Color, hood: Color, k: float, lean: float = 1.0, lit: bool = true, crown: bool = true) -> Vector3:
	var foot := 0.38 ## stand on the base
	b.cyl(0.72 * k * lean, 1.15 * k * lean, 3.0 * k, Vector3(0, foot + 1.5 * k, 0), robe, 10)
	for i in 6: ## drips at the hem
		var a := TAU * float(i) / 6.0 + 0.3
		b.cyl(0.11 * k, 0.05 * k, 0.55 * k, Vector3(cos(a) * 1.1 * k * lean, foot + 0.2 * k, sin(a) * 1.1 * k * lean), robe.darkened(0.12), 5)
	b.cyl(1.0 * k, 0.8 * k, 0.7 * k, Vector3(0, foot + 3.05 * k, 0), robe, 10) ## the shoulders, sunk
	var hy := foot + 3.85 * k
	b.ball(0.72 * k, Vector3(0, hy, 0.05 * k), hood, Vector3(1.0, 1.05, 1.05), 10)
	b.ball(0.42 * k, Vector3(0, hy - 0.05 * k, -0.38 * k), SOOT, Vector3(1.0, 1.1, 0.5), 8) ## the face that is nothing
	if lit:
		b.ball(0.1 * k, Vector3(0, hy - 0.03 * k, -0.48 * k), LILAC, Vector3.ONE, 6) ## the wick-light inside
	var hood_top := hy + 0.756 * k - 0.05
	if not crown:
		return Vector3(0, hood_top, 0.05 * k)
	b.cyl(0.07, 0.09, 0.55, Vector3(0, hood_top + 0.275, 0.05 * k), SOOT, 5) ## the crown wick: a black stub, no flame
	return Vector3(0, hood_top + 0.55, 0.05 * k)


## A candlebeast (§4.5): the wax remembers a beast's shape and fills it. A body `length` long at `height` (its back's middle), `girth`
## round, four legs, a head with no eyes, and the wick along its spine. Returns the spine wick's top.
static func _beast(b, wax: Color, height: float, length: float, girth: float, head: float) -> Vector3:
	b.ball(girth, Vector3(0, height, 0), wax, Vector3(0.95, 0.8, length / girth), 10)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg_h := height - 0.38
			b.cyl(0.2 * girth / 0.95, 0.24 * girth / 0.95, leg_h, Vector3(sx * girth * 0.55, 0.38 + leg_h * 0.5, sz * length * 0.6), wax.darkened(0.08), 6)
	var hz := -length * 1.05
	b.ball(head * 0.55, Vector3(0, height + 0.35, hz), wax, Vector3(0.85, 0.85, 1.25), 9)
	for sx in [-1.0, 1.0]:
		b.ball(head * 0.1, Vector3(sx * head * 0.22, height + 0.45, hz - head * 0.55), SOOT, Vector3.ONE, 5) ## hollow where the eyes would be
	for i in 4: ## drips along the belly
		b.cyl(0.08, 0.04, 0.45, Vector3((i - 1.5) * 0.3, height - girth * 0.75, (i % 2) * 0.4 - 0.2), wax.darkened(0.12), 5)
	var back := height + girth * 0.8 - 0.05
	b.cyl(0.07, 0.09, 0.55, Vector3(0, back + 0.275, 0.2 * girth / 0.95), SOOT, 5) ## the spine wick
	return Vector3(0, back + 0.55, 0.2 * girth / 0.95)


## A builder that draws nothing: wick_top() runs a figure through it to read where its wick ends.
class _Probe:
	func cyl(_r_top: float, _r_bot: float, _height: float, _pos: Vector3, _col: Color, _segs := 10, _rot := Basis(), _team := false) -> void:
		pass

	func box(_size: Vector3, _pos: Vector3, _col: Color, _rot := Basis(), _team := false) -> void:
		pass

	func ball(_r: float, _pos: Vector3, _col: Color, _scl := Vector3.ONE, _segs := 10, _team := false) -> void:
		pass
