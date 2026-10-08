## The four figures magic adds, as code primitives (M5-9, #120; design/M5_MAGIC_FOG.md §15.1, §15.3): the Crown's Sunstone Adepts, the
## Clans' Thornmane Shamans, and the Shamans' summoned Thornwolves and Greenwrath. They are the placeholders each model row in
## world3d/models.json falls back to ("model": ""), so the GLBs drop in without code changes; the 24 px silhouette gate (bible §8.9)
## is what they are drawn to pass: a mage is a caster with a staff overhead, a wolf is wider than it is tall, the Greenwrath stands
## taller than a War Bear. world3d/kit.gd calls build() from its figure() for these ids (a contiguous arm), with the Kit's own
## Builder, and `has()` is how Kit.has_figure knows them. No dependency on kit.gd (it would be a cycle): the colours are copied.
extends RefCounted

const IDS := ["adepts", "shamans", "thornwolves", "greenwrath"]

const TEAM := Color(1, 1, 1) ## a team part (alpha 0 in the mesh): the shader paints it in the player's colour
const LINEN := Color("#EDE6D6")
const ROYAL := Color("#2F57C2")
const GOLD := Color("#E2B23C")
const SKIN := Color("#E9B58C")
const LEATHER := Color("#6B4429")
const WOOD := Color("#7A5232")
const FUR := Color("#B9813F")
const FUR_DK := Color("#6E4A2C")
const BONE := Color("#EFE6CF")
const MOSS := Color("#5E7F35")
const MOSS_DK := Color("#35521F")
const CRIMSON := Color("#B8262B")
const SUNSTONE := Color("#F6D96B")


static func has(type_id: String) -> bool:
	return IDS.has(type_id)


## Adds the figure `type_id` to Kit builder `b` (feet on y = 0, facing -Z). The Kit adds the base.
static func build(b, type_id: String) -> void:
	match type_id:
		"adepts":
			_adept(b)
		"shamans":
			_shaman(b)
		"thornwolves":
			_wolf(b)
		"greenwrath":
			_thicket(b)


## A robed caster in white linen and royal blue with a gold sash, a hood, and a sunstone staff held overhead.
static func _adept(b) -> void:
	b.cyl(0.62, 1.18, 3.5, Vector3(0, 1.95, 0), LINEN, 10) ## the long robe
	b.cyl(1.2, 1.2, 0.28, Vector3(0, 0.5, 0), ROYAL, 10) ## its hem
	b.cyl(0.74, 0.74, 0.22, Vector3(0, 2.65, 0), GOLD, 10) ## the sash
	b.cyl(0.95, 0.72, 0.95, Vector3(0, 3.95, 0), ROYAL, 10) ## the mantle
	b.box(Vector3(0.7, 2.3, 0.12), Vector3(0, 2.5, -0.92), TEAM, Basis(), true) ## the tabard
	b.ball(0.55, Vector3(0, 4.9, 0.02), SKIN, Vector3.ONE, 10)
	b.ball(0.68, Vector3(0, 5.05, 0.1), ROYAL, Vector3(1.0, 0.95, 1.05), 10) ## the hood
	b.cyl(0.24, 0.24, 1.7, Vector3(-0.95, 3.7, 0.0), LINEN, 6, Basis(Vector3.FORWARD, -0.2)) ## the arm at the side
	b.cyl(0.24, 0.24, 2.0, Vector3(1.0, 4.4, -0.2), LINEN, 6, Basis(Vector3.FORWARD, 0.25)) ## the arm raised to the staff
	b.cyl(0.11, 0.11, 8.6, Vector3(1.35, 4.3, -0.25), WOOD, 6) ## the staff, far above its head
	b.cyl(0.4, 0.16, 0.45, Vector3(1.35, 8.75, -0.25), GOLD, 6) ## its cup
	b.ball(0.5, Vector3(1.35, 9.2, -0.25), SUNSTONE, Vector3.ONE, 8) ## the sunstone
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		b.cyl(0.0, 0.1, 0.7, Vector3(1.35 + cos(a) * 0.68, 9.2 + sin(a) * 0.68, -0.25), GOLD, 4, Basis(Vector3.BACK, a - PI * 0.5)) ## rays


## A Clans caster: a furred beastman in a moss cloak, antlers and a bone mask, a skull-and-briar staff, crimson paint.
static func _shaman(b) -> void:
	var s := 0.95
	b.box(Vector3(0.6, 1.8, 0.7) * s, Vector3(-0.42 * s, 1.1 * s, 0.0), FUR_DK)
	b.box(Vector3(0.6, 1.8, 0.7) * s, Vector3(0.42 * s, 1.1 * s, 0.0), FUR_DK)
	b.cyl(1.05, 1.35, 2.3, Vector3(0, 2.7, 0), MOSS, 10) ## the moss cloak
	b.cyl(1.37, 1.37, 0.22, Vector3(0, 1.65, 0), CRIMSON, 10)
	b.box(Vector3(0.8, 2.0, 0.12), Vector3(0, 2.9, -1.18), TEAM, Basis(), true)
	b.ball(1.1 * s, Vector3(0, 4.45, 0), FUR, Vector3(1.0, 1.05, 0.9), 10)
	b.box(Vector3(0.95, 0.9, 0.3), Vector3(0, 4.45, -0.95), BONE) ## the bone mask
	b.box(Vector3(0.22, 0.2, 0.1), Vector3(-0.28, 4.6, -1.12), Color("#1A1612"))
	b.box(Vector3(0.22, 0.2, 0.1), Vector3(0.28, 4.6, -1.12), Color("#1A1612"))
	for sx in [-1.0, 1.0]:
		b.cyl(0.06, 0.12, 1.5, Vector3(sx * 0.55, 5.55, 0.0), BONE, 5, Basis(Vector3.FORWARD, sx * 0.45)) ## the antlers
		b.cyl(0.04, 0.08, 0.8, Vector3(sx * 0.95, 6.1, 0.0), BONE, 5, Basis(Vector3.FORWARD, sx * 1.0))
	b.box(Vector3(0.18, 0.9, 0.12), Vector3(-0.5, 3.9, -1.12), CRIMSON) ## war paint
	b.cyl(0.3, 0.3, 1.9, Vector3(-1.25, 3.1, 0.0), FUR, 7, Basis(Vector3.FORWARD, -0.3))
	b.cyl(0.3, 0.3, 2.2, Vector3(1.3, 4.0, -0.2), FUR, 7, Basis(Vector3.FORWARD, 0.3)) ## the arm raised to the staff
	b.cyl(0.12, 0.12, 8.4, Vector3(1.5, 4.2, -0.3), WOOD, 5) ## the staff
	b.ball(0.55, Vector3(1.5, 8.65, -0.3), BONE, Vector3(1.0, 0.9, 1.15), 8) ## the skull on it
	b.box(Vector3(0.2, 0.2, 0.1), Vector3(1.36, 8.7, -0.82), Color("#1A1612"))
	b.box(Vector3(0.2, 0.2, 0.1), Vector3(1.64, 8.7, -0.82), Color("#1A1612"))
	for k in 5:
		var a := TAU * float(k) / 5.0
		b.cyl(0.0, 0.1, 0.9, Vector3(1.5 + cos(a) * 0.5, 7.6 + sin(a) * 0.12, -0.3 + sin(a) * 0.5), MOSS_DK, 4, Basis(Vector3.RIGHT, a)) ## briars on the staff
	b.box(Vector3(0.7, 0.14, 0.14), Vector3(1.5, 7.3, -0.3), CRIMSON)


## A low four-legged wolf grown of briars: wider than tall, a long body, a snout, thorns down its back.
static func _wolf(b) -> void:
	b.box(Vector3(1.5, 1.45, 3.4), Vector3(0, 2.15, 0.2), FUR_DK)
	b.ball(0.95, Vector3(0, 2.3, 1.4), FUR_DK, Vector3(1.0, 0.95, 1.1), 8) ## the haunch
	b.box(Vector3(1.2, 1.1, 1.2), Vector3(0, 2.55, -1.5), FUR) ## the shoulders
	for lx in [-0.55, 0.55]:
		for lz in [-1.4, 1.5]:
			b.box(Vector3(0.42, 1.7, 0.45), Vector3(lx, 0.85, lz), FUR_DK)
	b.box(Vector3(0.95, 0.95, 1.15), Vector3(0, 3.05, -2.4), FUR) ## the head
	b.box(Vector3(0.55, 0.5, 0.9), Vector3(0, 2.8, -3.3), FUR_DK) ## the snout
	b.box(Vector3(0.3, 0.12, 0.2), Vector3(0, 3.05, -3.78), Color("#1A1612"))
	for sx in [-1.0, 1.0]:
		b.cyl(0.0, 0.2, 0.7, Vector3(sx * 0.32, 3.75, -2.2), FUR_DK, 4) ## the ears
		b.box(Vector3(0.14, 0.12, 0.1), Vector3(sx * 0.3, 3.2, -2.95), CRIMSON) ## eyes
	b.cyl(0.08, 0.2, 1.7, Vector3(0, 2.75, 2.2), FUR_DK, 5, Basis(Vector3.RIGHT, 1.0)) ## the tail
	for k in 6:
		b.cyl(0.0, 0.17, 0.95, Vector3(0, 3.1 + 0.0 * k, -1.6 + 0.62 * k), MOSS, 4) ## briar thorns down the back
	b.box(Vector3(0.12, 0.7, 0.9), Vector3(0, 3.4, 0.0), TEAM, Basis(), true) ## a team pennant on its back


## A walking thicket: stacked trunks of briar, long thorned arms, and a stag's skull for a head; much taller than a War Bear.
static func _thicket(b) -> void:
	b.cyl(2.1, 3.2, 3.8, Vector3(0, 1.9, 0), MOSS_DK, 10) ## the roots
	b.cyl(2.7, 2.2, 3.6, Vector3(0, 5.6, 0), MOSS, 10)
	b.cyl(1.7, 2.7, 3.2, Vector3(0, 8.9, 0), MOSS_DK, 10)
	for k in 8:
		var a := TAU * float(k) / 8.0
		b.cyl(0.0, 0.3, 1.8, Vector3(cos(a) * 2.5, 4.6 + 0.5 * (k % 3), sin(a) * 2.5), BONE, 4, Basis(Vector3.UP, 0.0) * Basis(Vector3(-sin(a), 0, cos(a)), PI * 0.5 * 0.7)) ## thorns
	for sx in [-1.0, 1.0]:
		b.cyl(0.55, 0.85, 5.2, Vector3(sx * 3.2, 7.2, 0.2), MOSS, 7, Basis(Vector3.FORWARD, sx * 0.55)) ## the long arms
		b.cyl(0.0, 0.5, 1.6, Vector3(sx * 5.2, 4.9, -0.2), BONE, 5, Basis(Vector3.FORWARD, sx * 0.5)) ## claws
	b.ball(1.15, Vector3(0, 11.3, -0.2), BONE, Vector3(1.0, 1.1, 1.2), 10) ## the stag's skull
	b.box(Vector3(0.45, 0.4, 0.2), Vector3(-0.5, 11.45, -1.3), Color("#1A1612"))
	b.box(Vector3(0.45, 0.4, 0.2), Vector3(0.5, 11.45, -1.3), Color("#1A1612"))
	b.box(Vector3(0.6, 0.9, 0.5), Vector3(0, 10.4, -1.3), BONE)
	for sx in [-1.0, 1.0]:
		b.cyl(0.1, 0.22, 2.6, Vector3(sx * 1.1, 13.2, 0.0), BONE, 5, Basis(Vector3.FORWARD, sx * 0.4)) ## antlers
		b.cyl(0.07, 0.14, 1.5, Vector3(sx * 2.0, 14.0, 0.0), BONE, 5, Basis(Vector3.FORWARD, sx * 1.0))
		b.cyl(0.07, 0.14, 1.2, Vector3(sx * 1.5, 14.6, 0.0), BONE, 5, Basis(Vector3.FORWARD, sx * 0.1))
	b.box(Vector3(0.12, 2.0, 1.4), Vector3(0, 9.4, 1.8), TEAM, Basis(), true) ## a team banner grown on its back
