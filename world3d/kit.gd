## The spike's placeholder pieces, built from primitives in code: a figure for every M1 unit type,
## a fortress for a capital (walls, towers, a keep, a gate, a courtyard), a small fort, cottages,
## trees and rocks. Each piece is one ArrayMesh surface with vertex colours (linear), so one material
## draws it in either look. A vertex colour with alpha 0 is a "team" part (a figure's base, a pennon)
## that the model shaders paint in the player's colour: identity is drawn in code, never baked in.
##
## Figures face -Z, stand on y = 0 and are FIG units tall (a man); world units are MapLayout units.
extends RefCounted

const FIG := 6.0 ## a man's height, base included (world units)
## The banner emblem of nobody's army (a Free Holds garrison): the independents' heater shield (STYLE_BIBLE 1.1), after the
## six seat emblems (world3d/shaders/banner.gdshader).
const EMBLEM_SHIELD := 6
const SpellFigures := preload("res://world3d/spell_figures.gd") ## M5-9: the mages and the summoned creatures

## faction palettes (style bible 1.3: worn in art, independent of the player's colour)
const STEEL := Color("#B9C3CE")
const STEEL_DK := Color("#7D8794")
const LINEN := Color("#EDE6D6")
const ROYAL := Color("#2F57C2")
const GOLD := Color("#E2B23C")
const SKIN := Color("#E9B58C")
const LEATHER := Color("#6B4429")
const WOOD := Color("#7A5232")
const HORSE := Color("#E4DDCF")
const HORSE_DK := Color("#8A6A4C")
const FUR := Color("#B9813F")
const FUR_DK := Color("#6E4A2C")
const BONE := Color("#EFE6CF")
const MOSS := Color("#5E7F35")
const CRIMSON := Color("#B8262B")
const STONE := Color("#9A9389")
const STONE_LT := Color("#D2C8B4")
const ROOF := Color("#3E5FB5")
const DOOR := Color("#3A2A1E")
const TEAM := Color(1, 1, 1) ## placeholder: a team part (alpha 0) is painted in the player's colour
## The Free Holds' palette (IND-2, #161; STYLE_BIBLE 1.1: slate is the independents' colour): plain local militia in undyed
## wool and weathered grey, apart from the Crown's blue and gold and the Clans' tawny and moss. Never blue, gold, tawny, moss
## or crimson.
const WOOL := Color("#8E8570") ## undyed bone-cream wool (any lighter and the board's light blows it out to white)
const WOOL_DK := Color("#6E6758") ## the same, in shadow or worn
const SLATE := Color("#5B5750") ## UiPalette.NEUTRAL: the independents' own colour
const GREY := Color("#66625B") ## weathered grey cloth and leather
const GREY_LT := Color("#85817A")
const IRON := Color("#565A62") ## plain grey iron: caps, spear heads, axe blades
const BADGER := Color("#7C7E82") ## a Wildkin's silver-grey fur
const BADGER_DK := Color("#2B2C2F")
const NO_COLOUR := Color(0, 0, 0, 0) ## "leave this part out" for the helpers that take an optional colour

## how many figures stand for one unit of each type (the army is readable at a glance: one
## company block per unit), and the block's columns
const FIGS := {
	"spearmen": [6, 3], "crossbowmen": [6, 3], "knights": [3, 3],
	"tuskers": [4, 2], "fangthrowers": [6, 3], "war_bear": [1, 1],
	"free_spears": [6, 3], "hill_slingers": [6, 3], "wildkin": [4, 2],
}
const SPACING := {
	"spearmen": Vector2(4.2, 4.4), "crossbowmen": Vector2(4.2, 4.4), "knights": Vector2(5.2, 7.0),
	"tuskers": Vector2(5.0, 5.2), "fangthrowers": Vector2(4.2, 4.4), "war_bear": Vector2(9.0, 11.0),
	"knight_captain": Vector2(6.0, 8.0), "warchief": Vector2(6.0, 6.0), "bearer": Vector2(4.0, 4.0),
	"free_spears": Vector2(4.2, 4.4), "hill_slingers": Vector2(4.2, 4.4), "wildkin": Vector2(5.0, 5.2),
	"hold_captain": Vector2(6.0, 6.0), "free_bearer": Vector2(4.0, 4.0),
}
## the order blocks stand in from the front: melee, then ranged, then the big and the mounted
const RANK_ORDER := ["spearmen", "free_spears", "tuskers", "wildkin", "crossbowmen", "hill_slingers", "fangthrowers", "knights", "war_bear"]


class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(prim: PrimitiveMesh, xf: Transform3D, col: Color, team := false) -> void:
		var arr: Array = prim.get_mesh_arrays()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var puv = arr[Mesh.ARRAY_TEX_UV]
		var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb: Basis = xf.basis.inverse().transposed()
		var lc: Color = col.srgb_to_linear()
		lc.a = 0.0 if team else 1.0
		var base: int = v.size()
		for k in pv.size():
			v.append(xf * pv[k])
			n.append((nb * pn[k]).normalized())
			c.append(lc)
			uv.append(puv[k] if puv != null else Vector2.ZERO)
		for k in pi:
			idx.append(base + k)

	func box(size: Vector3, pos: Vector3, col: Color, rot := Basis(), team := false) -> void:
		var b := BoxMesh.new()
		b.size = size
		add(b, Transform3D(rot, pos), col, team)

	func cyl(r_top: float, r_bot: float, height: float, pos: Vector3, col: Color, segs := 10, rot := Basis(), team := false) -> void:
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = height
		m.radial_segments = segs
		m.rings = 1
		add(m, Transform3D(rot, pos), col, team)

	func ball(r: float, pos: Vector3, col: Color, scl := Vector3.ONE, segs := 10, team := false) -> void:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = segs
		m.rings = maxi(4, segs / 2)
		add(m, Transform3D(Basis().scaled(scl), pos), col, team)

	func prism(size: Vector3, pos: Vector3, col: Color, rot := Basis()) -> void:
		var m := PrismMesh.new()
		m.size = size
		add(m, Transform3D(rot, pos), col)

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return am


# ------------------------------------------------------------------ figures

const FIGURES := ["spearmen", "crossbowmen", "knights", "knight_captain", "tuskers", "fangthrowers", "war_bear", "warchief", "bearer",
	"free_spears", "hill_slingers", "wildkin", "hold_captain", "free_bearer"]
## The Free Holds' figures (IND-2, #161), by unit id (data/independents.gd): the independents "style" of the kit. The
## board and the stage stand these in a garrison until its Ludo models are installed (world3d/models.json rows).
const INDEPENDENTS := ["free_spears", "hill_slingers", "wildkin", "hold_captain"]
## The figure that stands for each of an army's colour party (the bearer, the musician) in the independents' style.
const INDEPENDENTS_PARTY := "free_bearer"


## True for a figure id figure() draws (anything else gets the generic figure).
static func has_figure(type_id: String) -> bool:
	return FIGURES.has(type_id) or SpellFigures.has(type_id) ## M5-9: the mages and the summoned (world3d/spell_figures.gd)


## A primitive figure. `s` scales the whole figure (a ruler or a monster stands bigger); `ruler` adds
## the bible's second, gilt ring round the base (STYLE_BIBLE.md 2.4, "ruler present").
static func figure(type_id: String, s: float = 1.0, ruler: bool = false) -> ArrayMesh:
	var b := Builder.new()
	match type_id:
		"spearmen":
			_human(b, ROYAL, STEEL)
			b.cyl(0.11, 0.11, 7.4, Vector3(0.95, 3.7, -0.15), WOOD, 6)
			b.cyl(0.0, 0.26, 0.9, Vector3(0.95, 7.85, -0.15), STEEL, 6)
			_shield_round(b, Vector3(-0.95, 2.7, -0.45))
		"crossbowmen":
			_human(b, LINEN, STEEL, ROYAL)
			b.box(Vector3(1.9, 0.22, 0.3), Vector3(0.0, 3.0, -0.95), WOOD)
			b.box(Vector3(0.28, 0.28, 1.5), Vector3(0.0, 3.0, -0.6), WOOD)
			b.cyl(0.32, 0.32, 1.6, Vector3(-0.75, 3.2, 0.45), LEATHER, 6, Basis(Vector3.RIGHT, 0.25))
		"knights":
			_horse(b, HORSE, ROYAL)
			_rider(b, ROYAL, STEEL)
			b.cyl(0.1, 0.12, 7.0, Vector3(0.75, 7.2, -0.4), WOOD, 6)
			b.box(Vector3(0.06, 0.7, 1.1), Vector3(0.75, 10.1, -0.95), TEAM, Basis(), true)
		"knight_captain":
			_horse(b, HORSE, GOLD, 1.12)
			_rider(b, ROYAL, GOLD, 1.12)
			b.box(Vector3(0.6, 1.4, 0.25), Vector3(0.0, 9.1, 0.0), CRIMSON) ## plume
			b.cyl(0.07, 0.09, 3.2, Vector3(0.95, 8.3, -0.6), STEEL, 6, Basis(Vector3.RIGHT, -0.5))
		"tuskers":
			_beastman(b, 1.25, FUR, MOSS)
			_boar_head(b, Vector3(0.0, 6.0, -0.35), 1.25)
			b.cyl(0.16, 0.14, 3.0, Vector3(1.55, 3.0, -0.6), WOOD, 6, Basis(Vector3.RIGHT, 0.9))
			b.ball(0.75, Vector3(1.55, 2.0, -1.8), STONE, Vector3(1.0, 0.9, 1.1), 7)
		"fangthrowers":
			_beastman(b, 0.95, FUR, MOSS)
			_wolf_head(b, Vector3(0.0, 5.0, -0.25))
			b.cyl(0.07, 0.07, 5.2, Vector3(1.05, 4.4, 0.1), WOOD, 5, Basis(Vector3.RIGHT, -0.35))
			b.cyl(0.0, 0.18, 0.7, Vector3(1.05, 6.9, -0.85), BONE, 5, Basis(Vector3.RIGHT, -0.35))
			for k in 3:
				b.cyl(0.05, 0.05, 3.6, Vector3(-0.35 + k * 0.2, 4.0, 0.75), WOOD, 4, Basis(Vector3.FORWARD, 0.3))
		"war_bear":
			_bear(b)
		"warchief":
			_beastman(b, 1.4, FUR_DK, CRIMSON)
			_boar_head(b, Vector3(0.0, 6.7, -0.35), 1.35)
			for k in 5: ## a crown of bone
				var a: float = -0.9 + k * 0.45
				b.cyl(0.0, 0.16, 0.9, Vector3(sin(a) * 0.75, 8.1, -0.35 + cos(a) * -0.2), BONE, 5)
			b.cyl(0.12, 0.12, 9.5, Vector3(1.7, 4.75, 0.0), WOOD, 6)
			b.ball(0.7, Vector3(1.7, 9.6, 0.0), BONE, Vector3(1.0, 1.1, 1.0), 8)
			b.box(Vector3(0.08, 1.6, 1.4), Vector3(1.7, 8.3, -0.75), TEAM, Basis(), true)
		"bearer":
			_human(b, LINEN, STEEL)
		## the independents' style (IND-2, #161): undyed wool, slate and weathered grey, no plume and no gold
		"free_spears":
			_human(b, WOOL, IRON, SLATE, NO_COLOUR, GREY)
			b.cyl(0.11, 0.11, 7.0, Vector3(0.95, 3.5, -0.15), WOOD, 6)
			b.cyl(0.0, 0.24, 0.8, Vector3(0.95, 7.4, -0.15), IRON, 6)
			_shield_kite(b, Vector3(-0.95, 2.8, -0.5))
		"hill_slingers":
			_human(b, WOOL_DK, WOOL, GREY, NO_COLOUR, GREY)
			b.cyl(0.62, 0.95, 0.7, Vector3(0, 3.95, 0), WOOL, 10) ## the hood's cowl
			b.cyl(0.04, 0.04, 2.3, Vector3(0.95, 1.7, -0.1), LEATHER, 4) ## the sling's cord, hanging from the right hand
			b.ball(0.2, Vector3(0.95, 0.5, -0.1), GREY, Vector3.ONE, 6) ## and its stone
			b.box(Vector3(0.7, 0.8, 0.5), Vector3(-0.75, 1.9, 0.55), LEATHER) ## the pouch of stones at the hip
		"wildkin":
			_beastman(b, 1.2, BADGER, WOOL, BADGER_DK, GREY, NO_COLOUR)
			_badger_head(b, Vector3(0.0, 6.0, -0.35), 1.2)
			b.cyl(0.13, 0.13, 6.2, Vector3(1.6, 3.6, -0.4), WOOD, 6, Basis(Vector3.RIGHT, 0.35)) ## a woodcutter's axe
			b.box(Vector3(1.3, 0.95, 0.2), Vector3(1.6, 6.9, -1.4), IRON, Basis(Vector3.RIGHT, 0.35))
		"hold_captain":
			_human(b, SLATE, IRON, WOOL, NO_COLOUR, GREY)
			b.box(Vector3(1.7, 2.7, 0.22), Vector3(0, 3.0, 0.7), WOOL) ## the bone-white cloak, hanging at the back
			b.box(Vector3(0.22, 0.7, 0.9), Vector3(0, 5.3, 0.1), WOOL) ## a short white horsehair crest
			b.cyl(0.12, 0.12, 9.0, Vector3(1.1, 4.5, -0.1), WOOD, 6) ## the war axe's long haft
			b.box(Vector3(1.2, 0.9, 0.18), Vector3(1.55, 8.4, -0.1), IRON)
			b.cyl(0.0, 0.34, 1.0, Vector3(-0.95, 1.8, 0.1), WOOL, 7, Basis(Vector3.FORWARD, 0.9)) ## the war horn at his belt
		"free_bearer":
			_human(b, WOOL, GREY, SLATE, NO_COLOUR, GREY)
		"adepts", "shamans", "thornwolves", "greenwrath": ## M5-9 (#120): the mages and the summoned (world3d/spell_figures.gd)
			SpellFigures.build(b, type_id)
		_:
			_human(b, Color("#8D88A0"), STEEL)
	if not is_equal_approx(s, 1.0):
		for k in b.v.size():
			b.v[k] = b.v[k] * s
	_base(b, type_id, ruler, s)
	return b.mesh()


static func _base(b: Builder, type_id: String, ruler: bool = false, s: float = 1.0) -> void:
	## the miniature's base, in the player's colour (team part), with an ink-dark rim under it
	var r := 1.35
	var sc := Vector3.ONE
	match type_id:
		"knights", "knight_captain":
			r = 1.6
			sc = Vector3(1.0, 1.0, 1.9)
		"tuskers", "warchief":
			r = 1.75
		"wildkin":
			r = 1.6
		"hold_captain":
			r = 1.5
		"war_bear":
			r = 2.6
			sc = Vector3(1.0, 1.0, 1.7)
		"thornwolves": ## M5-9
			r = 2.1
			sc = Vector3(1.0, 1.0, 1.9)
		"greenwrath":
			r = 3.6
	r *= s
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r * 1.06
	m.height = 0.38
	m.radial_segments = 14
	m.rings = 1
	b.add(m, Transform3D(Basis().scaled(sc), Vector3(0, 0.19, 0)), TEAM, true)
	if ruler:
		## the ruler's gilt ring, just outside the player-coloured base, over an ink rim
		var ink := CylinderMesh.new()
		ink.top_radius = r * 1.32
		ink.bottom_radius = r * 1.36
		ink.height = 0.22
		ink.radial_segments = 18
		ink.rings = 1
		b.add(ink, Transform3D(Basis().scaled(sc), Vector3(0, 0.11, 0)), Color("#1A1612"))
		var gilt := CylinderMesh.new()
		gilt.top_radius = r * 1.26
		gilt.bottom_radius = r * 1.28
		gilt.height = 0.3
		gilt.radial_segments = 18
		gilt.rings = 1
		b.add(gilt, Transform3D(Basis().scaled(sc), Vector3(0, 0.15, 0)), GOLD)


static func _human(b: Builder, coat: Color, helm: Color, trim := GOLD, plume := ROYAL, legs := LEATHER) -> void:
	b.box(Vector3(0.45, 1.55, 0.5), Vector3(-0.3, 1.15, 0.0), legs)
	b.box(Vector3(0.45, 1.55, 0.5), Vector3(0.3, 1.15, 0.0), legs)
	b.cyl(0.72, 0.98, 2.1, Vector3(0, 2.85, 0), coat, 10)
	b.cyl(0.99, 0.99, 0.2, Vector3(0, 1.9, 0), trim, 10)
	b.cyl(0.25, 0.25, 1.6, Vector3(-0.9, 3.0, 0.0), coat, 6, Basis(Vector3.FORWARD, -0.15))
	b.cyl(0.25, 0.25, 1.6, Vector3(0.9, 3.0, 0.0), coat, 6, Basis(Vector3.FORWARD, 0.15))
	b.ball(0.55, Vector3(0, 4.45, 0), SKIN, Vector3.ONE, 10)
	b.ball(0.62, Vector3(0, 4.68, 0.03), helm, Vector3(1.0, 0.78, 1.0), 10)
	if plume.a > 0.0:
		b.box(Vector3(0.18, 0.6, 0.8), Vector3(0, 5.25, 0.15), plume)


static func _shield_round(b: Builder, at: Vector3) -> void:
	var rot := Basis(Vector3.RIGHT, PI * 0.5)
	b.cyl(1.0, 1.0, 0.16, at, GOLD, 14, rot)
	b.cyl(0.84, 0.84, 0.18, at + Vector3(0, 0, -0.03), ROYAL, 14, rot)


## The Free Holds' kite-shaped shield: a bone-white face in a slate rim with one stitched grey sign, its point down.
static func _shield_kite(b: Builder, at: Vector3) -> void:
	b.box(Vector3(1.5, 1.5, 0.16), at + Vector3(0, 0.55, 0), SLATE)
	b.box(Vector3(1.26, 1.26, 0.2), at + Vector3(0, 0.55, -0.02), WOOL)
	var down := Basis(Vector3.BACK, PI)
	b.prism(Vector3(1.5, 1.2, 0.16), at + Vector3(0, -0.8, 0), SLATE, down)
	b.prism(Vector3(1.26, 1.0, 0.2), at + Vector3(0, -0.75, -0.02), WOOL, down)
	b.box(Vector3(0.34, 0.34, 0.24), at + Vector3(0, 0.5, -0.05), GREY)


static func _horse(b: Builder, coat: Color, trim: Color, s := 1.0) -> void:
	var y: float = 2.6 * s
	b.box(Vector3(1.5, 1.5, 3.6) * s, Vector3(0, y, 0), coat)
	b.box(Vector3(1.56, 0.7, 3.0) * s, Vector3(0, y - 0.35 * s, 0), trim) ## caparison
	for lx in [-0.5, 0.5]:
		for lz in [-1.3, 1.3]:
			b.box(Vector3(0.38, 2.0, 0.42) * s, Vector3(lx * s, 1.25 * s, lz * s), coat)
	b.box(Vector3(0.75, 1.9, 0.9) * s, Vector3(0, y + 1.0 * s, -1.75 * s), coat, Basis(Vector3.RIGHT, 0.45))
	b.box(Vector3(0.7, 0.7, 1.5) * s, Vector3(0, y + 1.8 * s, -2.45 * s), coat)
	b.box(Vector3(0.2, 1.4, 0.5) * s, Vector3(0, y + 1.2 * s, -1.4 * s), HORSE_DK, Basis(Vector3.RIGHT, 0.45)) ## mane
	b.box(Vector3(0.3, 1.5, 0.3) * s, Vector3(0, y - 0.1 * s, 1.95 * s), HORSE_DK, Basis(Vector3.RIGHT, -0.4)) ## tail


static func _rider(b: Builder, coat: Color, helm: Color, s := 1.0) -> void:
	var y: float = 3.4 * s
	b.cyl(0.6 * s, 0.85 * s, 1.9 * s, Vector3(0, y + 1.1 * s, 0.2 * s), coat, 10)
	b.box(Vector3(1.9, 0.5, 0.5) * s, Vector3(0, y + 0.3 * s, 0.2 * s), coat)
	b.ball(0.58 * s, Vector3(0, y + 2.6 * s, 0.2 * s), helm, Vector3(1.0, 1.15, 1.0), 10)
	b.cyl(0.25 * s, 0.25 * s, 1.4 * s, Vector3(-0.8 * s, y + 1.3 * s, 0.0), coat, 6)
	b.cyl(0.25 * s, 0.25 * s, 1.4 * s, Vector3(0.8 * s, y + 1.3 * s, -0.2 * s), coat, 6)


static func _beastman(b: Builder, s: float, fur: Color, harness: Color, legs := FUR_DK, plate := BONE, paint := CRIMSON) -> void:
	b.box(Vector3(0.6, 1.8, 0.7) * s, Vector3(-0.42 * s, 1.1 * s, 0.0), legs)
	b.box(Vector3(0.6, 1.8, 0.7) * s, Vector3(0.42 * s, 1.1 * s, 0.0), legs)
	b.cyl(0.95 * s, 1.0 * s, 0.9 * s, Vector3(0, 2.2 * s, 0), harness, 10) ## kilt
	b.ball(1.2 * s, Vector3(0, 3.6 * s, 0), fur, Vector3(1.0, 1.05, 0.85), 10)
	b.box(Vector3(2.0, 0.35, 0.3) * s, Vector3(0, 3.9 * s, -0.75 * s), harness, Basis(Vector3.FORWARD, 0.5))
	b.box(Vector3(0.9, 0.6, 0.25) * s, Vector3(0, 3.5 * s, -1.02 * s), plate)
	b.cyl(0.32 * s, 0.38 * s, 2.3 * s, Vector3(-1.3 * s, 3.1 * s, 0.0), fur, 7, Basis(Vector3.FORWARD, -0.25))
	b.cyl(0.32 * s, 0.38 * s, 2.3 * s, Vector3(1.3 * s, 3.1 * s, 0.0), fur, 7, Basis(Vector3.FORWARD, 0.25))
	if paint.a > 0.0:
		b.box(Vector3(0.18, 0.9, 0.12) * s, Vector3(-0.55 * s, 3.9 * s, -1.0 * s), paint) ## war paint


static func _boar_head(b: Builder, at: Vector3, s: float) -> void:
	b.ball(0.85 * s, at, FUR, Vector3(1.0, 0.95, 1.05), 10)
	b.box(Vector3(0.75, 0.6, 0.9) * s, at + Vector3(0, -0.15, -0.85) * s, Color("#D48A7A"))
	for sx in [-1.0, 1.0]:
		b.cyl(0.0, 0.14 * s, 0.9 * s, at + Vector3(sx * 0.42, -0.05, -1.05) * s, BONE, 5, Basis(Vector3.RIGHT, -0.6))
		b.box(Vector3(0.2, 0.5, 0.35) * s, at + Vector3(sx * 0.55, 0.75, 0.05) * s, FUR_DK, Basis(Vector3.FORWARD, sx * 0.5))
	b.box(Vector3(0.35, 0.1, 0.12) * s, at + Vector3(0, 0.35, -0.8) * s, CRIMSON)


static func _wolf_head(b: Builder, at: Vector3) -> void:
	b.ball(0.65, at, FUR, Vector3(1.0, 1.0, 1.1), 10)
	b.cyl(0.12, 0.38, 0.9, at + Vector3(0, -0.1, -0.75), FUR, 7, Basis(Vector3.RIGHT, PI * 0.5))
	for sx in [-1.0, 1.0]:
		b.cyl(0.0, 0.2, 0.6, at + Vector3(sx * 0.32, 0.65, 0.05), FUR_DK, 4)
	b.box(Vector3(1.0, 0.12, 0.1), at + Vector3(0, 0.2, -0.6), CRIMSON)


## A Wildkin's badger head: silver-grey, a pale stripe down the face between two dark eye bands, a dark snout.
static func _badger_head(b: Builder, at: Vector3, s: float) -> void:
	b.ball(0.85 * s, at, BADGER, Vector3(1.0, 0.95, 1.05), 10)
	b.cyl(0.16 * s, 0.42 * s, 0.95 * s, at + Vector3(0, -0.15, -0.8) * s, BADGER_DK, 7, Basis(Vector3.RIGHT, PI * 0.5))
	b.box(Vector3(0.3, 0.14, 1.2) * s, at + Vector3(0, 0.78, -0.18) * s, WOOL) ## the stripe, from the crown to the snout
	b.box(Vector3(0.26, 0.1, 0.8) * s, at + Vector3(0, 0.18, -0.95) * s, WOOL)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.28, 0.3, 0.7) * s, at + Vector3(sx * 0.42, 0.3, -0.5) * s, BADGER_DK) ## the eye bands
		b.ball(0.26 * s, at + Vector3(sx * 0.6, 0.78, 0.1) * s, BADGER_DK, Vector3.ONE, 6) ## the ears


static func _bear(b: Builder) -> void:
	b.ball(2.0, Vector3(0, 4.0, 0.4), FUR_DK, Vector3(1.0, 0.95, 1.55), 12)
	b.ball(1.5, Vector3(0, 4.8, -2.3), FUR_DK, Vector3(1.0, 1.0, 1.0), 10)
	b.ball(1.05, Vector3(0, 5.2, -3.6), FUR_DK, Vector3(1.0, 0.95, 1.05), 10)
	b.box(Vector3(0.8, 0.7, 0.9), Vector3(0, 4.9, -4.6), FUR, Basis())
	for sx in [-1.0, 1.0]:
		b.ball(0.32, Vector3(sx * 0.75, 6.1, -3.4), FUR_DK, Vector3.ONE, 6)
		for lz in [-1.6, 1.9]:
			b.cyl(0.55, 0.6, 2.6, Vector3(sx * 1.15, 1.4, lz), FUR_DK, 8)
	b.box(Vector3(2.6, 0.5, 2.6), Vector3(0, 6.0, 0.2), BONE) ## armour plates
	b.box(Vector3(2.2, 0.45, 1.4), Vector3(0, 5.9, 2.3), BONE)
	b.box(Vector3(2.65, 0.25, 0.4), Vector3(0, 6.3, -0.9), CRIMSON)
	b.box(Vector3(0.12, 1.4, 1.0), Vector3(0.0, 7.0, 1.0), TEAM, Basis(), true) ## a war banner on its back


# ------------------------------------------------------------------ buildings

## A capital's fortress, square, gate on -Z (the builder turns it to face the roads). `side` is the
## curtain wall's outer size. Returns the mesh; the courtyard is |x|, |z| < side/2 - 5 minus the keep.
static func fortress(side := 76.0) -> ArrayMesh:
	var b := Builder.new()
	var hs: float = side * 0.5
	var wall_h := 9.0
	var wall_t := 3.2
	## the courtyard floor: packed earth, a stone apron by the gate
	b.box(Vector3(side - 2.0, 2.4, side - 2.0), Vector3(0, 0.0, 0), Color("#CDB78E"))
	## curtain walls with a walk and merlons; the front wall has the gate gap
	var gate_w := 11.0
	for s in 4:
		var rot := Basis(Vector3.UP, s * PI * 0.5)
		var seg_len: float = side - 8.0
		var pieces: Array = [[0.0, seg_len]] if s != 0 else [[-(seg_len + gate_w) * 0.25 - gate_w * 0.25, (seg_len - gate_w) * 0.5], [(seg_len + gate_w) * 0.25 + gate_w * 0.25, (seg_len - gate_w) * 0.5]]
		for pc in pieces:
			var cx: float = pc[0]
			var ln: float = pc[1]
			b.box(Vector3(ln, wall_h, wall_t), rot * Vector3(cx, wall_h * 0.5, -hs + wall_t * 0.5), STONE_LT, rot)
			b.box(Vector3(ln, 0.5, wall_t + 0.6), rot * Vector3(cx, wall_h + 0.25, -hs + wall_t * 0.5), STONE, rot)
			var nm: int = int(ln / 2.4)
			for m in nm:
				var mx: float = cx - ln * 0.5 + (m + 0.5) * ln / nm
				if m % 2 == 0:
					b.box(Vector3(1.2, 1.3, 0.9), rot * Vector3(mx, wall_h + 1.15, -hs + 0.45), STONE_LT, rot)
	## four round corner towers with conical roofs (the roofs are team parts: the owner's colour)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var at := Vector3(cx * (hs - 3.0), 0, cz * (hs - 3.0))
			b.cyl(5.2, 5.6, 15.0, at + Vector3(0, 7.5, 0), STONE_LT, 14)
			b.cyl(5.9, 5.9, 1.2, at + Vector3(0, 15.4, 0), STONE, 14)
			b.cyl(0.0, 6.2, 8.0, at + Vector3(0, 20.0, 0), TEAM, 14, Basis(), true)
			b.cyl(0.0, 0.5, 2.0, at + Vector3(0, 24.8, 0), GOLD, 6)
	## the gatehouse: two towers and an arch over the gap, a dark doorway
	for gx in [-1.0, 1.0]:
		var at := Vector3(gx * (gate_w * 0.5 + 2.6), 0, -hs + 1.0)
		b.box(Vector3(5.2, 13.0, 6.5), at + Vector3(0, 6.5, 0), STONE_LT)
		b.box(Vector3(5.8, 0.8, 7.0), at + Vector3(0, 13.4, 0), STONE)
		b.cyl(0.0, 4.2, 5.5, at + Vector3(0, 16.5, 0), TEAM, 4, Basis(Vector3.UP, PI * 0.25), true)
	b.box(Vector3(gate_w + 1.0, 4.0, 6.0), Vector3(0, 11.0, -hs + 1.0), STONE_LT)
	b.box(Vector3(gate_w + 1.4, 0.7, 6.4), Vector3(0, 13.3, -hs + 1.0), STONE)
	## the keep at the back of the courtyard, a tall square tower with a hipped roof
	var keep_z: float = hs - 17.0
	b.box(Vector3(20.0, 24.0, 18.0), Vector3(0, 12.0, keep_z), STONE_LT)
	b.box(Vector3(21.0, 1.2, 19.0), Vector3(0, 24.4, keep_z), STONE)
	b.cyl(0.0, 15.0, 11.0, Vector3(0, 30.5, keep_z), TEAM, 4, Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 0.9)), true)
	b.box(Vector3(4.0, 7.0, 0.5), Vector3(0, 3.5, keep_z - 9.1), DOOR)
	for wx in [-6.0, 6.0]:
		b.box(Vector3(1.5, 3.0, 0.4), Vector3(wx, 16.0, keep_z - 9.05), DOOR)
	b.box(Vector3(1.0, 2.6, 0.4), Vector3(0, 16.0, keep_z - 9.05), DOOR)
	return b.mesh()


## The courtyard where a capital's army musters, in the fortress's own frame (gate on -Z): centre
## and size of the clear ground between the gate and the keep.
static func courtyard_rect(side := 76.0) -> Rect2:
	var hs: float = side * 0.5
	var front: float = -hs + 6.5
	var back: float = hs - 27.5
	return Rect2(Vector2(-hs + 7.0, front), Vector2(side - 14.0, back - front))


## A small fort for a province with has_fort: a square stone tower inside a ring of palisade.
static func fort() -> ArrayMesh:
	var b := Builder.new()
	b.cyl(11.0, 11.5, 0.6, Vector3(0, 0.3, 0), Color("#C9B48A"), 18)
	for k in 26:
		var a: float = TAU * k / 26.0
		if k == 19 or k == 20:
			continue ## the gap of the gate, to the north-west
		b.cyl(0.55, 0.6, 4.6 + (k % 3) * 0.4, Vector3(cos(a) * 11.0, 2.3, sin(a) * 11.0), WOOD, 5)
	b.box(Vector3(8.0, 13.0, 8.0), Vector3(0, 6.5, 0), STONE_LT)
	b.box(Vector3(9.0, 1.0, 9.0), Vector3(0, 13.5, 0), STONE)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			b.box(Vector3(1.4, 1.4, 1.4), Vector3(cx * 3.8, 14.6, cz * 3.8), STONE_LT)
	b.box(Vector3(2.4, 4.0, 0.4), Vector3(0, 2.0, -4.05), DOOR)
	return b.mesh()


## M3c S-4 (#102): the yards of the primitive forts, in their own frame (gate on -Z): the court [x, z, w, d] where
## the garrison stands, the gate's [inner, outer] z, the footprint's side. A fort's model row overrides them.
const FORT_YARD := {"court": [-8.6, -10.2, 17.2, 5.4], "gate_z": [-10.6, -15.0], "side": 24.0}
const PALISADE_R := 12.5
const PALISADE_YARD := {"court": [-8.2, -9.4, 16.4, 12.0], "gate_z": [-11.0, -16.0], "side": 27.0}


## M3c S-4: the level 1 kit's placeholder (design/M3C_SIEGES.md §13.3): a ring of timber stakes round a packed-earth
## yard, open at the gate on -Z. "kingdom": an earth bank under the stockade and a small gate tower with a roof in the
## owner's colour; "beasts": sharpened stakes with bone tips and a lookout platform at the back.
static func palisade_fort(style: String = "kingdom") -> ArrayMesh:
	var b := Builder.new()
	var r := PALISADE_R
	b.cyl(r + 0.6, r + 1.0, 0.5, Vector3(0, 0.25, 0), Color("#C9B48A"), 20)
	var n: int = int(TAU * r / 1.5)
	for k in n:
		var a: float = TAU * k / n
		var dir := Vector2(sin(a), -cos(a)) ## a = 0 is the gate (-Z)
		if absf(wrapf(a, -PI, PI)) < 0.2:
			continue
		var hgt: float = 4.4 + float(k % 3) * 0.45
		var at := Vector3(dir.x * r, 0.0, dir.y * r)
		b.cyl(0.5, 0.56, hgt, at + Vector3(0, hgt * 0.5, 0), WOOD, 5)
		if style == "beasts":
			b.cyl(0.0, 0.5, 1.1, at + Vector3(0, hgt + 0.55, 0), BONE, 5)
	if style == "beasts":
		## a lookout at the back: four poles and a platform with a hide roof
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				b.cyl(0.3, 0.34, 9.0, Vector3(cx * 1.8, 4.5, r - 4.0 + cz * 1.8), WOOD, 5)
		b.box(Vector3(5.0, 0.5, 5.0), Vector3(0, 8.0, r - 4.0), WOOD)
		b.cyl(0.0, 3.6, 2.6, Vector3(0, 10.3, r - 4.0), FUR, 8)
		b.box(Vector3(0.12, 1.4, 1.8), Vector3(0, 12.2, r - 4.0), TEAM, Basis(), true)
	else:
		## an earth bank under the stockade, and a timber gate tower over the gap with a roof in the owner's colour
		for k in 20:
			var a2: float = TAU * (k + 0.5) / 20.0
			if absf(wrapf(a2, -PI, PI)) < 0.3:
				continue
			var d2 := Vector2(sin(a2), -cos(a2))
			b.box(Vector3(TAU * r / 20.0 + 0.6, 1.0, 2.6), Vector3(d2.x * (r + 0.6), 0.4, d2.y * (r + 0.6)), Color("#8A6A44"), Basis(Vector3.UP, -a2))
		for gx in [-1.0, 1.0]:
			b.box(Vector3(1.2, 7.5, 1.2), Vector3(gx * 2.4, 3.75, -r), WOOD)
		b.box(Vector3(6.4, 1.6, 2.4), Vector3(0, 7.0, -r), WOOD)
		b.cyl(0.0, 3.4, 2.4, Vector3(0, 9.0, -r), TEAM, 4, Basis(Vector3.UP, PI * 0.25), true)
	return b.mesh()


## M3c S-4: construction scaffolding (§13.3: "a code lattice of thin boxes"), round a footprint of `side` (gate on
## -Z), `height` tall: posts every few units on the four sides, ledgers at three heights and a brace on each side.
static func scaffold(side: float, height: float, style: String = "kingdom") -> ArrayMesh:
	var b := Builder.new()
	var hs: float = side * 0.5 + 1.2
	var wood: Color = WOOD if style != "beasts" else FUR_DK
	var posts: int = maxi(3, int(side / 6.0))
	for s in 4:
		var rot := Basis(Vector3.UP, s * PI * 0.5)
		for k in posts + 1:
			var x: float = -hs + 2.0 * hs * k / posts
			b.box(Vector3(0.4, height, 0.4), rot * Vector3(x, height * 0.5, -hs), wood, rot)
		for lv in 3:
			var y: float = height * (0.3 + 0.33 * lv)
			b.box(Vector3(2.0 * hs, 0.3, 0.5), rot * Vector3(0, y, -hs), wood, rot)
			b.box(Vector3(2.0 * hs, 0.15, 1.6), rot * Vector3(0, y - 0.25, -hs + 0.7), Color("#A5784A"), rot)
		var diag := Vector2(2.0 * hs, height).length()
		b.box(Vector3(diag, 0.25, 0.25), rot * Vector3(0, height * 0.5, -hs - 0.1), wood, rot * Basis(Vector3.BACK, atan2(height, 2.0 * hs)))
	if style == "beasts":
		for k in 6:
			var a: float = TAU * k / 6.0
			b.cyl(0.05, 0.05, height * 0.9, Vector3(cos(a) * hs, height * 0.45, sin(a) * hs), LEATHER, 3, Basis(Vector3(sin(a), 0, -cos(a)), 0.5))
	## the site's materials: a stack of timber and a pile of dressed stone by the gate side, a hoist's mast
	for k in 4:
		b.cyl(0.35, 0.35, 5.0, Vector3(-hs + 3.0, 0.35 + (k % 2) * 0.6, -hs + 2.0 + k * 0.75), wood, 6, Basis(Vector3.BACK, PI * 0.5))
	for k in 5:
		b.box(Vector3(1.4, 0.9, 1.0), Vector3(hs - 3.0 + (k % 2) * 1.5, 0.45 + (k / 2) * 0.9, -hs + 2.5 + (k % 3) * 1.1), STONE)
	b.box(Vector3(0.4, height + 3.0, 0.4), Vector3(hs - 1.5, (height + 3.0) * 0.5, hs - 1.5), wood)
	b.box(Vector3(5.0, 0.3, 0.3), Vector3(hs - 3.6, height + 2.6, hs - 1.5), wood)
	return b.mesh()


## M3c S-4: a besieger's siege works before the gate (§13.3), facing the walls on -Z. "kingdom": mantlets on wheels
## and two ladders; "beasts": an earth mound, a line of stakes and a rack of logs.
static func siege_works(style: String = "kingdom") -> ArrayMesh:
	var b := Builder.new()
	if style == "beasts":
		b.ball(4.0, Vector3(0, 0.0, 1.0), Color("#8A6A44"), Vector3(1.6, 0.55, 0.8), 10)
		for k in 7:
			var x: float = -6.0 + 2.0 * k
			b.cyl(0.0, 0.4, 3.4, Vector3(x, 1.4, -2.6), WOOD, 5, Basis(Vector3.RIGHT, -0.5))
		for lv in 3:
			for k in 3 - lv:
				b.cyl(0.55, 0.55, 7.0, Vector3(-1.1 + k * 1.1 + lv * 0.55, 0.55 + lv * 0.95, 3.6), WOOD, 7, Basis(Vector3.BACK, PI * 0.5))
		b.box(Vector3(0.12, 1.2, 1.6), Vector3(4.6, 3.8, 1.0), TEAM, Basis(), true)
		b.cyl(0.08, 0.08, 3.0, Vector3(4.6, 2.5, 1.8), WOOD, 4)
	else:
		for k in 3:
			var x2: float = -5.0 + 5.0 * k
			b.box(Vector3(4.0, 3.2, 0.5), Vector3(x2, 2.0, -1.0), WOOD, Basis(Vector3.RIGHT, -0.18))
			b.box(Vector3(4.2, 0.4, 0.6), Vector3(x2, 3.6, -1.3), LEATHER)
			for wx in [-1.5, 1.5]:
				b.cyl(0.55, 0.55, 0.3, Vector3(x2 + wx, 0.55, -0.5), DOOR, 8, Basis(Vector3.BACK, PI * 0.5))
		for lx in [-3.0, 3.0]:
			for side in [-0.6, 0.6]:
				b.box(Vector3(0.18, 0.18, 8.0), Vector3(lx + side, 0.25, 3.0), WOOD)
			for rung in 6:
				b.box(Vector3(1.2, 0.12, 0.12), Vector3(lx, 0.3, 0.0 + rung * 1.25), WOOD)
		b.box(Vector3(0.12, 1.0, 1.6), Vector3(0, 4.6, -1.3), TEAM, Basis(), true)
	return b.mesh()


## M3c S-4: a siege engine (§13.3), its business end on -Z. "kingdom", the Siege Ram: a roofed housing on four wheels
## with an iron-headed ram log; "beasts", the Wallbreakers: a great trunk slung on a sled with ropes.
static func siege_engine(style: String = "kingdom") -> ArrayMesh:
	var b := Builder.new()
	if style == "beasts":
		for sx in [-1.2, 1.2]:
			b.box(Vector3(0.4, 0.4, 7.0), Vector3(sx, 0.2, 0.0), WOOD)
		for sz in [-2.4, 0.0, 2.4]:
			b.box(Vector3(3.0, 0.3, 0.4), Vector3(0, 0.45, sz), WOOD)
		for sz2 in [-1.8, 1.8]:
			b.cyl(0.12, 0.12, 2.6, Vector3(0, 1.8, sz2), LEATHER, 4)
		b.cyl(0.75, 0.9, 7.6, Vector3(0, 2.9, -0.4), FUR_DK, 9, Basis(Vector3.RIGHT, PI * 0.5))
		b.ball(0.95, Vector3(0, 2.9, -4.2), BONE, Vector3(1.0, 1.0, 0.7), 8)
		b.box(Vector3(0.1, 0.9, 1.2), Vector3(0, 3.9, 2.0), TEAM, Basis(), true)
	else:
		for wx in [-1.6, 1.6]:
			for wz in [-2.2, 2.2]:
				b.cyl(0.8, 0.8, 0.35, Vector3(wx, 0.8, wz), DOOR, 10, Basis(Vector3.BACK, PI * 0.5))
		b.box(Vector3(3.0, 0.4, 6.2), Vector3(0, 1.2, 0.0), WOOD)
		for px in [-1.3, 1.3]:
			b.box(Vector3(0.3, 2.6, 5.6), Vector3(px, 2.6, 0.0), WOOD)
		b.prism(Vector3(3.6, 1.6, 6.4), Vector3(0, 4.6, 0.0), LEATHER)
		b.cyl(0.42, 0.42, 7.4, Vector3(0, 2.5, -1.0), WOOD, 8, Basis(Vector3.RIGHT, PI * 0.5))
		b.cyl(0.0, 0.65, 1.1, Vector3(0, 2.5, -5.2), STEEL_DK, 8, Basis(Vector3.RIGHT, -PI * 0.5))
		b.box(Vector3(0.1, 0.8, 1.2), Vector3(0, 6.0, 1.8), TEAM, Basis(), true)
	return b.mesh()


## M3c S-4: a rubble pile (the shared prop for breaches and badly damaged walls): a low heap of earth and dust
## under tumbled blocks of weathered stone, darker than the walls they fell from.
static func rubble() -> ArrayMesh:
	var b := Builder.new()
	var cols: Array = [Color("#7E776D"), Color("#8C857B"), Color("#6B655D"), Color("#9A9083")]
	b.ball(2.6, Vector3(0, -0.6, 0), Color("#8A7A62"), Vector3(1.3, 0.55, 1.0), 9)
	for k in 14:
		var a: float = TAU * k / 14.0 + float(k % 3) * 0.4
		var d: float = 0.4 + float((k * 7) % 5) * 0.5
		var s: float = 0.6 + float((k * 3) % 4) * 0.22
		b.box(Vector3(s * 1.3, s * 0.8, s * 1.0), Vector3(cos(a) * d, 0.4 + s * 0.3 + float(k % 2) * 0.35, sin(a) * d * 0.8), cols[k % 4],
			Basis(Vector3(0.3, 1.0, 0.2).normalized(), a * 1.7))
	return b.mesh()


## M3c S-4: a besieger's chevron banner (the bible's "besieged" marker, drawn in code): a staff with a pennant in the
## besieger's colour (a team part) bearing a white chevron, the cloth to +X.
static func chevron_banner() -> ArrayMesh:
	var b := Builder.new()
	b.cyl(0.12, 0.15, 7.0, Vector3(0, 3.5, 0), WOOD, 5)
	b.cyl(0.0, 0.26, 0.6, Vector3(0, 7.3, 0), GOLD, 5)
	b.box(Vector3(3.0, 2.0, 0.12), Vector3(1.6, 5.8, 0), TEAM, Basis(), true)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(1.5, 0.34, 0.16), Vector3(1.6 + sx * 0.55, 5.85 + 0.25, 0), LINEN, Basis(Vector3.BACK, sx * 0.6))
	return b.mesh()


## A ring of sharpened timber stakes round a fortress (the Clans' kit variant), open at the gate on -Z,
## with bone-white tips and a low earth bank under it.
static func palisade(radius: float) -> ArrayMesh:
	var b := Builder.new()
	var n: int = int(TAU * radius / 2.2)
	for k in n:
		var a: float = TAU * k / n
		var dir := Vector2(sin(a), -cos(a)) ## a = 0 is the gate (-Z)
		if absf(wrapf(a, -PI, PI)) < 0.24:
			continue
		var hgt: float = 6.2 + float(k % 3) * 0.7
		var at := Vector3(dir.x * radius, 0.0, dir.y * radius)
		b.cyl(0.62, 0.7, hgt, at + Vector3(0, hgt * 0.5, 0), WOOD, 6)
		b.cyl(0.0, 0.62, 1.3, at + Vector3(0, hgt + 0.65, 0), BONE, 6)
	for k in 24:
		var a2: float = TAU * (k + 0.5) / 24.0
		if absf(wrapf(a2, -PI, PI)) < 0.3:
			continue
		var d2 := Vector2(sin(a2), -cos(a2))
		b.box(Vector3(TAU * radius / 24.0 + 1.0, 1.2, 3.4), Vector3(d2.x * radius, 0.4, d2.y * radius), Color("#8A6A44"), Basis(Vector3.UP, -a2))
	return b.mesh()


## A war camp's tent (design/3D_DIRECTION.md 6.3), door on -Z: "kingdom" a linen ridge tent with royal
## trim, "beasts" a hide cone on bone poles. Its pennant is a team part (the owner's colour).
static func tent(style: String = "kingdom") -> ArrayMesh:
	var b := Builder.new()
	if style == "beasts":
		b.cyl(3.6, 3.8, 0.25, Vector3(0, 0.12, 0), Color("#8A6A44"), 12)
		b.cyl(0.25, 3.4, 5.4, Vector3(0, 2.95, 0), FUR, 9)
		b.cyl(0.0, 0.5, 0.9, Vector3(0, 5.9, 0), FUR_DK, 7)
		for k in 4:
			var a: float = TAU * (k + 0.5) / 4.0
			b.cyl(0.08, 0.1, 2.2, Vector3(cos(a) * 0.35, 6.4, sin(a) * 0.35), BONE, 4, Basis(Vector3(sin(a), 0, -cos(a)).normalized(), 0.35))
		b.box(Vector3(1.4, 2.2, 0.3), Vector3(0, 1.1, -2.6), DOOR, Basis(Vector3.RIGHT, -0.5))
		b.box(Vector3(0.12, 0.9, 1.3), Vector3(0, 7.4, -0.65), TEAM, Basis(), true)
		b.box(Vector3(0.2, 0.25, 2.6), Vector3(0, 3.0, -2.7), CRIMSON, Basis(Vector3.RIGHT, 0.55))
	elif style == "independents":
		## the Free Holds' (IND-2, #161): a plain ridge tent of undyed wool with a slate hem, under a team pennant
		b.box(Vector3(6.6, 0.2, 7.4), Vector3(0, 0.1, 0), Color("#B9A27A"))
		b.prism(Vector3(5.8, 3.6, 6.6), Vector3(0, 2.0, 0), WOOL)
		b.prism(Vector3(5.9, 0.5, 6.7), Vector3(0, 0.45, 0), SLATE)
		b.box(Vector3(1.4, 2.0, 0.12), Vector3(0, 1.0, -3.32), DOOR)
		b.cyl(0.08, 0.08, 2.2, Vector3(0, 5.0, -3.0), WOOD, 5)
		b.box(Vector3(0.08, 0.7, 1.2), Vector3(0, 5.7, -2.4), TEAM, Basis(), true)
	else:
		b.box(Vector3(6.6, 0.2, 7.4), Vector3(0, 0.1, 0), Color("#B9A27A"))
		b.prism(Vector3(5.8, 3.8, 6.6), Vector3(0, 2.1, 0), LINEN)
		b.prism(Vector3(5.9, 0.5, 6.7), Vector3(0, 0.45, 0), ROYAL)
		b.box(Vector3(1.4, 2.0, 0.12), Vector3(0, 1.0, -3.32), DOOR)
		b.cyl(0.08, 0.08, 2.2, Vector3(0, 5.0, -3.0), WOOD, 5)
		b.box(Vector3(0.08, 0.7, 1.2), Vector3(0, 5.7, -2.4), TEAM, Basis(), true)
	return b.mesh()


## A camp fire: a ring of stones, crossed logs and a flame (its smoke is world_view.gd's).
static func campfire() -> ArrayMesh:
	var b := Builder.new()
	for k in 7:
		var a: float = TAU * k / 7.0
		b.ball(0.32, Vector3(cos(a) * 1.05, 0.18, sin(a) * 1.05), STONE, Vector3(1.0, 0.7, 1.0), 6)
	b.box(Vector3(2.0, 0.3, 0.32), Vector3(0, 0.3, 0), WOOD, Basis(Vector3.UP, 0.5))
	b.box(Vector3(2.0, 0.3, 0.32), Vector3(0, 0.4, 0), WOOD, Basis(Vector3.UP, -0.7))
	b.cyl(0.0, 0.62, 1.5, Vector3(0, 1.05, 0), Color("#F2862E"), 7)
	b.cyl(0.0, 0.34, 1.0, Vector3(0, 0.95, 0), Color("#FFD35A"), 6)
	return b.mesh()


static func cottage(variant: int) -> ArrayMesh:
	var b := Builder.new()
	var walls: Color = [Color("#EFE3C8"), Color("#E3D2AE"), Color("#D9C7A5")][variant % 3]
	var roof: Color = [Color("#B5583A"), Color("#8E6B3E"), Color("#C9A456")][variant % 3]
	var l: float = 6.0 + (variant % 2) * 2.0
	b.box(Vector3(l, 3.6, 4.6), Vector3(0, 1.8, 0), walls)
	b.prism(Vector3(5.4, 2.8, l + 0.8), Vector3(0, 5.0, 0), roof, Basis(Vector3.UP, PI * 0.5))
	b.box(Vector3(1.0, 1.9, 0.2), Vector3(l * 0.2, 0.95, -2.35), DOOR)
	b.box(Vector3(0.8, 2.2, 0.8), Vector3(-l * 0.3, 6.0, 0.6), STONE)
	return b.mesh()


# ------------------------------------------------------------------ the land's growth

static func broadleaf() -> ArrayMesh:
	var b := Builder.new()
	b.cyl(0.45, 0.65, 3.0, Vector3(0, 1.5, 0), Color("#6E4B2E"), 6)
	b.ball(2.9, Vector3(0, 5.3, 0), Color("#357A40"), Vector3(1.0, 0.9, 1.0), 8)
	b.ball(1.9, Vector3(1.1, 6.6, 0.5), Color("#448C47"), Vector3.ONE, 7)
	return b.mesh()


static func pine() -> ArrayMesh:
	var b := Builder.new()
	b.cyl(0.35, 0.5, 2.0, Vector3(0, 1.0, 0), Color("#5E4128"), 6)
	for k in 3:
		b.cyl(0.0, 2.7 - k * 0.7, 3.8 - k * 0.6, Vector3(0, 3.4 + k * 2.1, 0), Color("#2A6A47").lerp(Color("#3A8455"), k * 0.4), 7)
	return b.mesh()


static func rock() -> ArrayMesh:
	var b := Builder.new()
	b.ball(1.0, Vector3(0, 0.35, 0), Color("#A7A096"), Vector3(1.4, 0.9, 1.0), 6)
	b.ball(0.6, Vector3(0.9, 0.2, 0.4), Color("#958E84"), Vector3(1.0, 0.8, 1.0), 5)
	return b.mesh()


# ------------------------------------------------------------------ formations (pure)

## Figure slots for an army, in its own frame: facing -Z, the front rank on z = 0, x centred.
## Returns [{"type": type id, "pos": Vector2 (x, z), "role": "unit"/"commander"/"bearer"}].
## Blocks stand in RANK_ORDER from the front, packed into rows no wider than `max_w`; the commander
## and the banner bearer stand in front of the middle.
static func formation(type_ids: Array, commander_type: String, max_w: float) -> Array:
	var blocks: Array = []
	var sorted_types: Array = type_ids.duplicate()
	sorted_types.sort_custom(func(a, b): return _rank(a) < _rank(b) or (_rank(a) == _rank(b) and a < b))
	for t in sorted_types:
		var f: Array = FIGS.get(t, [4, 2])
		var sp: Vector2 = SPACING.get(t, Vector2(4.2, 4.4))
		var cols: int = f[1]
		var rows: int = int(ceil(float(f[0]) / cols))
		blocks.append({"type": t, "n": f[0], "cols": cols, "rows": rows, "sp": sp,
			"w": cols * sp.x, "d": rows * sp.y})
	## pack the blocks into rows
	var lines: Array = []
	var cur: Array = []
	var cur_w := 0.0
	var gap := 2.0
	for bl in blocks:
		var need: float = bl["w"] + (gap if not cur.is_empty() else 0.0)
		if not cur.is_empty() and cur_w + need > max_w:
			lines.append(cur)
			cur = []
			cur_w = 0.0
			need = bl["w"]
		cur.append(bl)
		cur_w += need
	if not cur.is_empty():
		lines.append(cur)
	var out: Array = []
	var z := 0.0
	if commander_type != "":
		var csp: Vector2 = SPACING.get(commander_type, Vector2(6, 6))
		out.append({"type": commander_type, "pos": Vector2(-1.6, csp.y * 0.5), "role": "commander"})
		out.append({"type": "bearer", "pos": Vector2(3.4, csp.y * 0.35), "role": "bearer"})
		z = csp.y + 1.0
	for line in lines:
		var lw := 0.0
		var ld := 0.0
		for bl in line:
			lw += bl["w"]
			ld = maxf(ld, bl["d"])
		lw += gap * (line.size() - 1)
		var x: float = -lw * 0.5
		for bl in line:
			var sp: Vector2 = bl["sp"]
			for i in int(bl["n"]):
				var c: int = i % int(bl["cols"])
				var r: int = i / int(bl["cols"])
				out.append({"type": bl["type"], "pos": Vector2(x + (c + 0.5) * sp.x, z + (r + 0.5) * sp.y), "role": "unit"})
			x += bl["w"] + gap
		z += ld + 1.0
	return out


static func _rank(t: String) -> int:
	var i := RANK_ORDER.find(t)
	return i if i >= 0 else RANK_ORDER.size()


## The depth (z extent) of a formation from formation().
static func formation_depth(slots: Array) -> float:
	var d := 0.0
	for s in slots:
		d = maxf(d, (s["pos"] as Vector2).y + 3.0)
	return d


## The board's formation (design/3D_DIRECTION.md 6.1-6.2), in the army's own frame: facing -Z, the
## front rank on z = 0, x centred. One block per unit type in `blocks` ([{"type", "n" figures, "rank"
## 0 front / 1 second (Volley), "sp": Vector2 spacing}]), front rank first, packed into rows no wider
## than `max_w`. `leaders` ([{"type", "role": "commander" or "ruler", "rank", "sp"}]) stand with their
## rank: a front-rank ruler leads from the front, a commander (rank 2) stands at the back with the
## banner bearer, who carries the army's banner in every army, and the army's other `extras` (M3a.2:
## its musician). Returns [{"type", "pos", "role"}].
static func formation_blocks(blocks: Array, leaders: Array, max_w: float, extras: Array = ["bearer"]) -> Array:
	var out: Array = []
	var z := 0.0
	var gap := 2.0
	for rank in [0, 1, 2]:
		var row_items: Array = []
		for ld in leaders:
			if int(ld.get("rank", 2)) == rank and rank < 2:
				row_items.append({"type": ld["type"], "n": 1, "cols": 1, "sp": ld["sp"], "role": ld["role"]})
		for bl in blocks:
			if int(bl.get("rank", 0)) != rank:
				continue
			var n: int = int(bl["n"])
			var big: bool = (bl["sp"] as Vector2).x > 5.0
			var cols: int = n if n <= (3 if big else 4) else int(ceil(n / 2.0))
			row_items.append({"type": bl["type"], "n": n, "cols": cols, "sp": bl["sp"], "role": "unit"})
		if rank == 2:
			for ld in leaders:
				if int(ld.get("rank", 2)) >= 2:
					row_items.append({"type": ld["type"], "n": 1, "cols": 1, "sp": ld["sp"], "role": ld["role"]})
			for ex in extras:
				row_items.append({"type": ex, "n": 1, "cols": 1, "sp": SPACING["bearer"], "role": ex})
		if row_items.is_empty():
			continue
		## pack this rank's blocks into lines no wider than max_w
		var lines: Array = []
		var cur: Array = []
		var cur_w := 0.0
		for it in row_items:
			var w: float = int(it["cols"]) * (it["sp"] as Vector2).x
			var need: float = w + (gap if not cur.is_empty() else 0.0)
			if not cur.is_empty() and cur_w + need > max_w:
				lines.append(cur)
				cur = []
				cur_w = 0.0
				need = w
			cur.append(it)
			cur_w += need
		if not cur.is_empty():
			lines.append(cur)
		for line in lines:
			var lw := 0.0
			var ld_depth := 0.0
			for it in line:
				var sp: Vector2 = it["sp"]
				lw += int(it["cols"]) * sp.x
				ld_depth = maxf(ld_depth, ceil(float(it["n"]) / int(it["cols"])) * sp.y)
			lw += gap * (line.size() - 1)
			var x: float = -lw * 0.5
			for it in line:
				var sp: Vector2 = it["sp"]
				var cols: int = it["cols"]
				for i in int(it["n"]):
					var c: int = i % cols
					var r: int = i / cols
					out.append({"type": it["type"], "pos": Vector2(x + (c + 0.5) * sp.x, z + (r + 0.5) * sp.y), "role": it["role"]})
				x += cols * sp.x + gap
			z += ld_depth + 1.0
	return out
