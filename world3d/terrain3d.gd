## The land of the M1 map in 3D (spike). Pure data: no nodes, no scene, seeded, so the same map
## always gives the same land and it can be built off the main thread and unit-tested.
##
## World units are MapLayout design units: x east (0..1000), z south (0..600), y up. The land is
## baked on a grid of `cell` units over a rect a sea margin wider than the design space.
##
## Build steps (build()):
##   1. territories  a jittered (domain-warped) Voronoi of the province centres. The warp's noise is
##                   read mirrored across x = 500, so the land is as mirror-symmetric as the rules.
##   2. coast        a smooth union of discs round the centres, warped, is the continent; its signed
##                   distance is the coast distance (+ inland, - out to sea).
##   3. borders      distance to the nearest other territory. A border between two provinces that are
##                   NOT neighbours in data/map.gd is a "wall": it is raised into a rocky ridge, so the
##                   land shows which moves are legal. A border between neighbours gets a crossing.
##   4. heights      plains low and gentle, forest a little higher, hills raised and craggy (terrain
##                   weights blurred across borders), a shelf dropping into the sea.
##   5. stages       a level stage round every centre (a wide one for a capital's fortress).
##   6. roads        centre -> middle of the shared border -> neighbour's centre, carved into the land.
##
## Outputs: heights (PackedFloat32Array W*H), height_image (RF), data_image (RGBA8: r province index
## or 255 for sea, g coast distance, b border distance, a wall), ground_image (RGBA8: rgb bare ground,
## a woods), owner state lives in the scene (world_view.gd).
extends RefCounted

const ORIGIN := Vector2(-100, -100)
const EXTENT := Vector2(1200, 800)
const AXIS_X := 500.0 ## the mirror line
const WARP := 40.0 ## how far the borders wander (units)
const LAND_R := 112.0 ## continent disc radius round each centre
const SEA := 255

const TERRAINS := ["plains", "forest", "hills"]
## bare ground, sRGB (from the style bible's terrain anchors, a little lifted for lit 3D)
const GROUND := [Color("#ADC25E"), Color("#4F8A57"), Color("#ABA45E")]
const ROAD_COL := Color("#D2B07A")

var cell := 2.5
var w := 0
var h := 0
var ids: Array = [] ## province ids in data order (index = the data image's red channel)
var names: Array = []
var terrain_of: Array = [] ## index -> "plains" / "forest" / "hills"
var centres: Array = [] ## index -> Vector2 (design units)
var is_capital: Array = []
var has_fort: Array = []
var neighbours: Array = [] ## index -> Array of indices
var stage_h := PackedFloat32Array() ## index -> the stage's height
var stage_r := PackedFloat32Array() ## index -> the flat stage's radius
var crossings := {} ## "a|b" (ids sorted) -> Vector2: the middle of the border two neighbours share
var roads: Array = [] ## [{"a": id, "b": id, "pts": [Vector2, Vector2, Vector2]}]
var heights := PackedFloat32Array()
var idx := PackedByteArray() ## per cell: province index or SEA
var coast := PackedFloat32Array() ## per cell: signed distance to the coast (+ inland)
var border := PackedFloat32Array() ## per cell: distance to the nearest other territory
var second := PackedByteArray() ## per cell: the nearest other territory's index
var wall := PackedByteArray() ## per cell: 1 where the nearest border is between non-neighbours
var road_d := PackedFloat32Array() ## per cell: distance to the nearest road
var woods := PackedFloat32Array() ## per cell: 0..1 how wooded
var height_image: Image
var weights_image: Image ## RGBA8, blurred: r plains, g forest, b hills (the ground tiles' blend)
var data_image: Image
var ground_image: Image
var lo := 0.0
var hi := 0.0
var millis := 0
var seed_value := 7


static func build(p_cell: float = 2.5, p_seed: int = 7) -> RefCounted:
	var t = load("res://world3d/terrain3d.gd").new()
	t._build(p_cell, p_seed)
	return t


# ------------------------------------------------------------------ queries (CPU, match the GPU)

func index_of(id: String) -> int:
	return ids.find(id)


func centre_of(id: String) -> Vector2:
	var i := ids.find(id)
	return centres[i] if i >= 0 else Vector2.ZERO


func height_at(p: Vector2) -> float:
	## bilinear, exactly as the GPU samples height_image (texel centres at (i + 0.5) * cell)
	var fx: float = (p.x - ORIGIN.x) / cell - 0.5
	var fy: float = (p.y - ORIGIN.y) / cell - 0.5
	var x0: int = clampi(floori(fx), 0, w - 1)
	var y0: int = clampi(floori(fy), 0, h - 1)
	var x1: int = mini(x0 + 1, w - 1)
	var y1: int = mini(y0 + 1, h - 1)
	var tx: float = clampf(fx - floorf(fx), 0.0, 1.0)
	var ty: float = clampf(fy - floorf(fy), 0.0, 1.0)
	var a: float = lerpf(heights[y0 * w + x0], heights[y0 * w + x1], tx)
	var b: float = lerpf(heights[y1 * w + x0], heights[y1 * w + x1], tx)
	return lerpf(a, b, ty)


func ground_at(p: Vector2) -> Vector3:
	return Vector3(p.x, maxf(height_at(p), 0.0), p.y)


func normal_at(p: Vector2) -> Vector3:
	var e := cell
	var dx: float = height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0))
	var dz: float = height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _k(p: Vector2) -> int:
	var x: int = clampi(int((p.x - ORIGIN.x) / cell), 0, w - 1)
	var y: int = clampi(int((p.y - ORIGIN.y) / cell), 0, h - 1)
	return y * w + x


func province_at(p: Vector2) -> String:
	var i: int = idx[_k(p)]
	return ids[i] if i != SEA else ""


func coast_at(p: Vector2) -> float:
	return coast[_k(p)]


func border_at(p: Vector2) -> float:
	return border[_k(p)]


func road_at(p: Vector2) -> float:
	return road_d[_k(p)]


func woods_at(p: Vector2) -> float:
	return woods[_k(p)]


func crossing(a: String, b: String) -> Variant:
	return crossings.get(pair(a, b), null)


static func pair(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## The way from province a to its neighbour b: [centre a, the border crossing, centre b].
func road_path(a: String, b: String) -> PackedVector2Array:
	var pa := centre_of(a)
	var pb := centre_of(b)
	var x: Variant = crossing(a, b)
	if x == null:
		return PackedVector2Array([pa, pb])
	return PackedVector2Array([pa, x, pb])


# ------------------------------------------------------------------ generation

func _build(p_cell: float, p_seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	cell = p_cell
	seed_value = p_seed
	w = int(ceil(EXTENT.x / cell))
	h = int(ceil(EXTENT.y / cell))
	_load_map()
	var n := w * h
	idx.resize(n)
	coast.resize(n)
	border.resize(n)
	second.resize(n)
	wall.resize(n)
	heights.resize(n)
	woods.resize(n)
	var warp_a := _noise(seed_value + 11, FastNoiseLite.FRACTAL_FBM, 1.0 / 150.0, 3)
	var warp_b := _noise(seed_value + 12, FastNoiseLite.FRACTAL_FBM, 1.0 / 150.0, 3)
	var coast_n := _noise(seed_value + 13, FastNoiseLite.FRACTAL_FBM, 1.0 / 120.0, 4)
	var wig_a := _noise(seed_value + 14, FastNoiseLite.FRACTAL_FBM, 1.0 / 48.0, 2) ## a finer wiggle on the borders
	var wig_b := _noise(seed_value + 15, FastNoiseLite.FRACTAL_FBM, 1.0 / 48.0, 2)
	var pn := centres.size()
	var cx := PackedFloat32Array()
	var cy := PackedFloat32Array()
	var wgt := PackedFloat32Array()
	for i in pn:
		cx.append(centres[i].x)
		cy.append(centres[i].y)
		wgt.append(0.88 if is_capital[i] else 1.0) ## capitals hold a little more land
	var is_nb := {} ## i*32+j -> true
	for i in pn:
		for j in neighbours[i]:
			is_nb[i * 32 + j] = true
	## 1-3: territories, the coast, borders (one pass)
	var tw := PackedByteArray() ## terrain one-hot for the blur (r plains, g forest, b hills)
	tw.resize(n * 4)
	var wallf := PackedByteArray() ## how near a wall each cell is, blurred below into the ridges
	wallf.resize(n)
	var cross_sum := {} ## pair -> [Vector2 sum, count, Array of points]
	for y in h:
		var py: float = ORIGIN.y + (y + 0.5) * cell
		for x in w:
			var px: float = ORIGIN.x + (x + 0.5) * cell
			var k: int = y * w + x
			var sx: float = minf(px, 2.0 * AXIS_X - px)
			var east: bool = px > AXIS_X
			var wx: float = (warp_a.get_noise_2d(sx, py) * WARP + wig_a.get_noise_2d(sx, py) * 11.0) * clampf(absf(px - AXIS_X) / 40.0, 0.0, 1.0)
			var wy: float = warp_b.get_noise_2d(sx, py) * WARP + wig_b.get_noise_2d(sx, py) * 11.0
			if east:
				wx = -wx
			var qx: float = px + wx
			var qy: float = py + wy
			var d1 := 1.0e9
			var d2 := 1.0e9
			var i1 := 0
			var i2 := 0
			var sdf := 0.0
			var sdf_acc := 0.0
			for i in pn:
				var dx: float = qx - cx[i]
				var dy: float = qy - cy[i]
				var dr: float = sqrt(dx * dx + dy * dy)
				var dw: float = dr * wgt[i]
				if dw < d1:
					d2 = d1
					i2 = i1
					d1 = dw
					i1 = i
				elif dw < d2:
					d2 = dw
					i2 = i
				## smooth union of the continent discs (log-sum-exp smooth min, k = 34)
				sdf_acc += exp(-(dr - LAND_R) / 34.0)
			sdf = -34.0 * log(maxf(sdf_acc, 1.0e-12))
			sdf += coast_n.get_noise_2d(sx, py) * 22.0
			var c: float = -sdf
			coast[k] = c
			var bd: float = (d2 - d1) * 0.5
			border[k] = bd
			second[k] = i2
			var walled: bool = not is_nb.has(i1 * 32 + i2)
			wall[k] = 1 if walled else 0
			if walled and c > -10.0:
				wallf[k] = clampi(int((1.0 - smoothstep(0.0, 24.0, bd)) * 255.0), 0, 255)
			if c < 0.0:
				idx[k] = SEA
			else:
				idx[k] = i1
				var ti: int = TERRAINS.find(terrain_of[i1])
				tw[k * 4 + ti] = 255
				tw[k * 4 + 3] = 255
				if not walled and bd < cell * 0.75 and c > 10.0:
					var key := pair(ids[i1], ids[i2])
					if not cross_sum.has(key):
						cross_sum[key] = [Vector2.ZERO, 0, []]
					var e: Array = cross_sum[key]
					e[0] += Vector2(px, py)
					e[1] += 1
					(e[2] as Array).append(Vector2(px, py))
	## the crossings: the border cell nearest the middle of each shared border
	for key in cross_sum.keys():
		var e: Array = cross_sum[key]
		var mean: Vector2 = e[0] / float(e[1])
		var best: Vector2 = e[2][0]
		for p in e[2]:
			if (p as Vector2).distance_squared_to(mean) < best.distance_squared_to(mean):
				best = p
		crossings[key] = best
	## neighbours in the rules that the land doesn't make touch still get a crossing (midway)
	for i in pn:
		for j in neighbours[i]:
			var key := pair(ids[i], ids[j])
			if not crossings.has(key):
				crossings[key] = (centres[i] + centres[j]) * 0.5
	## 4: heights
	weights_image = _blur(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, tw), 3)
	var weights := weights_image.get_data()
	## the walls, rounded off where they end (at a coast or where a neighbours' border takes over)
	var walls := _blur(Image.create_from_data(w, h, false, Image.FORMAT_L8, wallf), 2).get_data()
	var fbm := _noise(seed_value + 21, FastNoiseLite.FRACTAL_FBM, 1.0 / 70.0, 4)
	var ridged := _noise(seed_value + 22, FastNoiseLite.FRACTAL_RIDGED, 1.0 / 90.0, 3)
	var crag := _noise(seed_value + 23, FastNoiseLite.FRACTAL_RIDGED, 1.0 / 26.0, 3)
	var fine := _noise(seed_value + 24, FastNoiseLite.FRACTAL_FBM, 1.0 / 18.0, 2)
	var clump := _noise(seed_value + 25, FastNoiseLite.FRACTAL_FBM, 1.0 / 30.0, 3)
	var gimg := PackedByteArray()
	gimg.resize(n * 4)
	for y in h:
		var py: float = ORIGIN.y + (y + 0.5) * cell
		for x in w:
			var px: float = ORIGIN.x + (x + 0.5) * cell
			var sx: float = minf(px, 2.0 * AXIS_X - px)
			var k: int = y * w + x
			var c: float = coast[k]
			var tot: float = maxf(float(weights[k * 4]) + float(weights[k * 4 + 1]) + float(weights[k * 4 + 2]), 1.0)
			var wp: float = float(weights[k * 4]) / tot
			var wf: float = float(weights[k * 4 + 1]) / tot
			var wh: float = float(weights[k * 4 + 2]) / tot
			var hv := 0.0
			if c < 0.0:
				hv = maxf(c * 0.42 - 0.8, -26.0)
			else:
				var shore: float = smoothstep(0.0, 26.0, c)
				var inland: float = smoothstep(12.0, 90.0, c)
				var fb: float = fbm.get_noise_2d(sx, py) * 0.5 + 0.5
				var rg: float = ridged.get_noise_2d(sx, py) * 0.5 + 0.5
				hv = 0.8 + 3.4 * shore + 3.5 * inland
				hv += (wp * 2.6 + wf * 5.0 + wh * 13.0) * fb * shore
				hv += wf * 2.0 * inland
				hv += wh * (8.0 + 30.0 * pow(rg, 1.5)) * inland
				hv += fine.get_noise_2d(sx, py) * (0.35 + 1.4 * wh)
				var bd: float = border[k]
				## a wall between provinces that are not neighbours: a rocky ridge you can't cross
				var wv: float = float(walls[k]) / 255.0
				if wv > 0.004:
					var cr: float = crag.get_noise_2d(sx, py) * 0.5 + 0.5
					hv += pow(wv, 2.0) * (20.0 + 38.0 * cr * cr + 10.0 * rg) * smoothstep(-6.0, 30.0, c)
				if wall[k] == 0:
					var bv: float = 1.0 - smoothstep(0.0, 9.0, bd)
					hv -= bv * bv * 1.6 * shore
			heights[k] = hv
			var col := Color(0, 0, 0)
			col += GROUND[0] * wp + GROUND[1] * wf + GROUND[2] * wh
			var dv: float = fine.get_noise_2d(px * 1.9, py * 1.9) * 0.05
			gimg[k * 4] = clampi(int((col.r + dv) * 255.0), 0, 255)
			gimg[k * 4 + 1] = clampi(int((col.g + dv) * 255.0), 0, 255)
			gimg[k * 4 + 2] = clampi(int((col.b + dv * 0.6) * 255.0), 0, 255)
			var wd := 0.0
			if c > 6.0:
				var cl: float = clump.get_noise_2d(sx, py) * 0.5 + 0.5
				wd = wf * smoothstep(0.40, 0.62, cl + 0.04) + wp * 0.08 * smoothstep(0.62, 0.8, cl) + wh * 0.12 * smoothstep(0.55, 0.75, cl)
			woods[k] = clampf(wd, 0.0, 1.0)
			gimg[k * 4 + 3] = clampi(int(woods[k] * 255.0), 0, 255)
	## 5: stages, 6: roads
	_stages()
	_roads()
	for k in n:
		var rd: float = road_d[k]
		if rd < 4.5:
			var f: float = (1.0 - smoothstep(1.6, 4.5, rd)) * 0.85
			gimg[k * 4] = int(lerpf(gimg[k * 4], ROAD_COL.r8, f))
			gimg[k * 4 + 1] = int(lerpf(gimg[k * 4 + 1], ROAD_COL.g8, f))
			gimg[k * 4 + 2] = int(lerpf(gimg[k * 4 + 2], ROAD_COL.b8, f))
		if rd < 9.0:
			woods[k] = 0.0
			gimg[k * 4 + 3] = 0
	lo = 1.0e9
	hi = -1.0e9
	for v in heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	height_image = Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array())
	ground_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, gimg)
	var dimg := PackedByteArray()
	dimg.resize(n * 4)
	## the border distance for the shader, signed near the border (+ on the lower-indexed province's
	## side) so its bilinear filtering crosses zero exactly on the border and the ink line is crisp;
	## unsigned further in, where the second-nearest province changes
	var bsign := PackedFloat32Array()
	bsign.resize(n)
	for k in n:
		var bd: float = border[k]
		bsign[k] = clampf(bd if bd >= 4.0 or second[k] > idx[k] else -bd, -12.7, 12.7)
	for k in n:
		dimg[k * 4] = idx[k]
		dimg[k * 4 + 1] = clampi(int(128.0 + coast[k] * 2.0), 0, 255)
		dimg[k * 4 + 2] = clampi(int(round(128.0 + bsign[k] * 10.0)), 0, 255)
		dimg[k * 4 + 3] = 255 if wall[k] == 1 else 0
	data_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dimg)
	millis = Time.get_ticks_msec() - t0


func _load_map() -> void:
	ids.clear()
	for p in MapData.PROVINCES:
		ids.append(p.id)
	for p in MapData.PROVINCES:
		names.append(p.name)
		terrain_of.append(p.terrain)
		centres.append(MapLayout.position_of(p.id))
		is_capital.append(p.is_capital)
		has_fort.append(p.has_fort)
		var nb: Array = []
		for q in p.neighbors:
			nb.append(ids.find(q))
		neighbours.append(nb)


func _stages() -> void:
	## a level stage round every centre: the floor of the ground there, eased out to the wild land
	stage_h.resize(ids.size())
	stage_r.resize(ids.size())
	for i in ids.size():
		var c: Vector2 = centres[i]
		var r0: float = 48.0 if is_capital[i] else 24.0
		var r1: float = r0 + (40.0 if is_capital[i] else 30.0)
		stage_r[i] = r0
		var vals := PackedFloat32Array()
		var rc: int = int(r0 / cell) + 1
		var kc: int = _k(c)
		var ccx: int = kc % w
		var ccy: int = kc / w
		for y in range(maxi(0, ccy - rc), mini(h, ccy + rc + 1)):
			for x in range(maxi(0, ccx - rc), mini(w, ccx + rc + 1)):
				var p := ORIGIN + Vector2((x + 0.5) * cell, (y + 0.5) * cell)
				if p.distance_to(c) <= r0:
					vals.append(heights[y * w + x])
		vals.sort()
		var floor_h := 0.0
		var nlow: int = maxi(1, int(vals.size() * 0.4))
		for j in nlow:
			floor_h += vals[j]
		floor_h = maxf(floor_h / nlow, 3.0)
		stage_h[i] = floor_h
		rc = int(r1 / cell) + 1
		for y in range(maxi(0, ccy - rc), mini(h, ccy + rc + 1)):
			for x in range(maxi(0, ccx - rc), mini(w, ccx + rc + 1)):
				var k: int = y * w + x
				if coast[k] < 2.0:
					continue
				var p := ORIGIN + Vector2((x + 0.5) * cell, (y + 0.5) * cell)
				var d: float = p.distance_to(c)
				var f: float = 1.0 - smoothstep(r0, r1, d)
				if idx[k] != i:
					f *= smoothstep(0.0, 12.0, -border[k] + 12.0) * 0.0 ## another province: leave it
				heights[k] = lerpf(heights[k], floor_h, f)


func _roads() -> void:
	road_d.resize(w * h)
	road_d.fill(1.0e9)
	var done := {}
	for i in ids.size():
		for j in neighbours[i]:
			var key := pair(ids[i], ids[j])
			if done.has(key):
				continue
			done[key] = true
			var a: String = ids[i] if ids[i] < ids[j] else ids[j]
			var b: String = ids[j] if a == ids[i] else ids[i]
			var ia := ids.find(a)
			var ib := ids.find(b)
			var x: Vector2 = crossings[key]
			var pa: Vector2 = centres[ia]
			var pb: Vector2 = centres[ib]
			var fa: float = stage_h[ia]
			var fb: float = stage_h[ib]
			var saddle: float = maxf(fa, fb) * 0.55 + minf(fa, fb) * 0.45 + 1.0
			roads.append({"a": a, "b": b, "pts": [pa, x, pb]})
			_carve(pa, x, fa, saddle)
			_carve(x, pb, saddle, fb)


func _carve(p0: Vector2, p1: Vector2, h0: float, h1: float) -> void:
	var r := 16.0
	var lo_p := Vector2(minf(p0.x, p1.x) - r, minf(p0.y, p1.y) - r)
	var hi_p := Vector2(maxf(p0.x, p1.x) + r, maxf(p0.y, p1.y) + r)
	var seg: Vector2 = p1 - p0
	var len2: float = maxf(seg.length_squared(), 1.0)
	for y in range(maxi(0, int((lo_p.y - ORIGIN.y) / cell)), mini(h, int((hi_p.y - ORIGIN.y) / cell) + 1)):
		for x in range(maxi(0, int((lo_p.x - ORIGIN.x) / cell)), mini(w, int((hi_p.x - ORIGIN.x) / cell) + 1)):
			var k: int = y * w + x
			if coast[k] < 0.0:
				continue
			var p := ORIGIN + Vector2((x + 0.5) * cell, (y + 0.5) * cell)
			var t: float = clampf((p - p0).dot(seg) / len2, 0.0, 1.0)
			var d: float = p.distance_to(p0 + seg * t)
			if d >= r:
				continue
			road_d[k] = minf(road_d[k], d)
			var floor_h: float = lerpf(h0, h1, t * t * (3.0 - 2.0 * t))
			var keep: float = smoothstep(r * 0.3, r, d)
			heights[k] = lerpf(floor_h, heights[k], keep) if heights[k] > floor_h else lerpf(floor_h, heights[k], maxf(keep, 0.5))


func _noise(sd: int, fractal: int, freq: float, octaves: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = sd
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = fractal
	nz.frequency = freq
	nz.fractal_octaves = octaves
	return nz


func _blur(img: Image, levels: int) -> Image:
	var ow: int = img.get_width()
	var oh: int = img.get_height()
	var out: Image = img.duplicate()
	for i in levels:
		out.shrink_x2()
	out.resize(maxi(1, ow / 2), maxi(1, oh / 2), Image.INTERPOLATE_CUBIC)
	out.resize(ow, oh, Image.INTERPOLATE_BILINEAR)
	return out
