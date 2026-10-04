## The 3D battle stage's camera, the pure part (no nodes): the rig that frames a battle (design/3D_DIRECTION.md
## 7.4, CONCURRENT's land_field.gd _battle_rig), and the projection that goes with it, computed here rather
## than asked of a Camera3D so the framing, the plates and the picking work the same headless (tests).
##
## A rig is world_view.gd's: {"target": Vector3, "pitch" (degrees above the horizon), "yaw" (degrees round
## from the south), "fov" (vertical, degrees), "span" (world units top to bottom of the screen)}.
##
##   BattleCamera.frame(t, points, band, view, axis, opts)   the rig that frames `points`
##
## Framing: it tries the yaws from which the two sides spread across the screen rather than towards it (the
## two flanks of the battle's axis, and up to 30 degrees either way), raises the pitch at each until no hill
## and no building stands between the eye and any of the points, then fits the points into `band` (the part
## of the screen the battle UI leaves clear) and centres them in it. Of those it keeps the closest, a little
## in favour of the sun behind the camera (faces lit) and of the defender on the right (M3's convention).
extends RefCounted

const PITCH_MIN := 34.0
const PITCH_MAX := 70.0
const PITCH_STEP := 4.0
const FOV := 30.0
const MIN_SPAN := 38.0 ## never closer than this (world units up the screen): a 1-on-1 still shows its ground
const MAX_SPAN := 900.0
## where the sun stands, seen from above (world_view.gd's sun: from the south-west, behind the default view)
const SUN_FROM := Vector2(-0.795, 0.607)
const OFFSETS := [0.0, 12.0, -12.0, 24.0, -24.0]
const RAY_STEPS := 22


## The camera's transform for `rig` (world_view.gd apply_rig's).
static func xform_of(rig: Dictionary) -> Transform3D:
	var d: float = float(rig["span"]) / (2.0 * tan(deg_to_rad(float(rig["fov"])) * 0.5))
	var pitch: float = deg_to_rad(float(rig["pitch"]))
	var yaw: float = deg_to_rad(float(rig["yaw"]))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var z: Vector3 = (back * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var x: Vector3 = Vector3.UP.cross(back).normalized()
	var y: Vector3 = z.cross(x)
	return Transform3D(Basis(x, y, z), (rig["target"] as Vector3) + z * d)


static func eye_of(rig: Dictionary) -> Vector3:
	return xform_of(rig).origin


## A world point to view pixels (Vector2(-99999, -99999) behind the camera).
static func project(rig: Dictionary, view: Vector2, p: Vector3, xf: Variant = null) -> Vector2:
	var cx: Transform3D = xf if xf != null else xform_of(rig)
	var pv: Vector3 = cx.affine_inverse() * p
	if pv.z > -0.001:
		return Vector2(-99999, -99999)
	var th: float = tan(deg_to_rad(float(rig["fov"])) * 0.5)
	var aspect: float = view.x / maxf(view.y, 1.0)
	return Vector2((pv.x / (-pv.z * th * aspect) * 0.5 + 0.5) * view.x, (0.5 - pv.y / (-pv.z * th) * 0.5) * view.y)


## The ray from the eye through view pixel `s`: [origin, direction].
static func ray(rig: Dictionary, view: Vector2, s: Vector2) -> Array:
	var cx := xform_of(rig)
	var th: float = tan(deg_to_rad(float(rig["fov"])) * 0.5)
	var aspect: float = view.x / maxf(view.y, 1.0)
	var nx: float = (s.x / maxf(view.x, 1.0)) * 2.0 - 1.0
	var ny: float = 1.0 - (s.y / maxf(view.y, 1.0)) * 2.0
	return [cx.origin, (cx.basis * Vector3(nx * th * aspect, ny * th, -1.0)).normalized()]


## The screen's right, as a ground direction, for a rig's yaw.
static func right_of(yaw_deg: float) -> Vector2:
	var y := deg_to_rad(yaw_deg)
	return Vector2(cos(y), -sin(y))


## The yaw whose camera stands on the `back` side of the target (a ground direction from the target).
static func yaw_toward(back: Vector2) -> float:
	return rad_to_deg(atan2(back.x, back.y))


## True when nothing stands between the rig's eye and every point: the land (terrain3d.gd height_at) and
## `obstacles` ([{"pos": Vector2, "r", "top"}]: a fortress or a fort as a squat cylinder).
static func sees_all(t, rig: Dictionary, points: Array, obstacles: Array = []) -> bool:
	var eye := eye_of(rig)
	for p in points:
		var q0: Vector3 = p
		for i in range(1, RAY_STEPS):
			var q: Vector3 = eye.lerp(q0, float(i) / float(RAY_STEPS))
			var g := Vector2(q.x, q.z)
			if t.height_at(g) > q.y + 0.6:
				return false
			for ob in obstacles:
				if i < RAY_STEPS - 2 and g.distance_to(ob["pos"]) < float(ob["r"]) and q.y < float(ob["top"]):
					return false
	return true


## The rig that frames `points` (world, Vector3: feet and heads) inside `band` (view pixels) of a view of
## size `view`. `axis` is the battle's axis (from the near side to the far side); `opts`: {"yaws": [only
## these yaws], "obstacles", "defender_right": +1 when the far side defends, -1 the near, 0 nobody,
## "min_span", "los": the points that must be seen (default `points`; the stage passes upper bodies),
## "pitch": the pitch to start from, "near_left": only yaws that keep the near side on that half}. Returns the rig plus "left_near": whether the near side stands on the screen's left.
static func frame(t, points: Array, band: Rect2, view: Vector2, axis: Vector2, opts: Dictionary = {}) -> Dictionary:
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= maxf(1.0, float(points.size()))
	var yaws: Array = opts.get("yaws", [])
	if yaws.is_empty():
		var flank := Vector2(-axis.y, axis.x)
		for side in [flank, -flank]:
			var base := yaw_toward(side)
			for off in OFFSETS:
				yaws.append(base + off)
	var obstacles: Array = opts.get("obstacles", [])
	var min_span: float = float(opts.get("min_span", MIN_SPAN))
	var best := {}
	var best_score := INF
	for yaw in yaws:
		if opts.has("near_left") and bool(opts["near_left"]) != ((-axis).dot(right_of(float(yaw))) < 0.0):
			continue
		var r := {"target": Vector3(c.x, c.y, c.z), "pitch": float(opts.get("pitch", PITCH_MIN)), "yaw": float(yaw), "fov": FOV, "span": 120.0}
		var los: Array = opts.get("los", points)
		var see_pts := los if los.size() <= 48 else _thin(los, 48)
		while float(r["pitch"]) < PITCH_MAX and not sees_all(t, r, see_pts, obstacles):
			r["pitch"] = float(r["pitch"]) + PITCH_STEP
		## then everyone, not just the sample (a crowd's every fighter)
		while see_pts.size() < los.size() and float(r["pitch"]) < PITCH_MAX and not sees_all(t, r, los, obstacles):
			r["pitch"] = float(r["pitch"]) + PITCH_STEP
		fit(r, points, band, view, min_span)
		var back := Vector2(sin(deg_to_rad(float(yaw))), cos(deg_to_rad(float(yaw))))
		var score := float(r["span"]) * (1.0 + 0.22 * (1.0 - back.dot(SUN_FROM)) + 0.004 * absf(float(r["pitch"]) - 40.0))
		var right := right_of(float(yaw))
		var near_left := (-axis).dot(right) < 0.0
		if opts.has("near_left") and bool(opts["near_left"]) != near_left:
			continue ## a reframe keeps each side on the half of the screen its strength bar is on
		var dr := int(opts.get("defender_right", 0))
		if dr != 0 and ((dr > 0) != near_left):
			score *= 1.3 ## the defender on the left: allowed when nothing else sees everyone, but M3 keeps it right
		if score < best_score - 0.001:
			best_score = score
			best = r
			best["left_near"] = near_left
	return best


## Fits `points` into `band` in place: moves the rig's target so their middle sits in the band's middle and
## sets its span so they fill it (never below `min_span`).
static func fit(r: Dictionary, points: Array, band: Rect2, view: Vector2, min_span: float = MIN_SPAN) -> void:
	for it in 6:
		var xf := xform_of(r)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in points:
			var s := project(r, view, p, xf)
			if s.x < -90000.0:
				continue
			lo = lo.min(s)
			hi = hi.max(s)
		if lo.x == INF:
			return
		var mid := (lo + hi) * 0.5
		var px_world: float = float(r["span"]) / maxf(view.y, 1.0)
		var off: Vector2 = band.get_center() - mid
		var right := right_of(float(r["yaw"]))
		var fwd := Vector2(-sin(deg_to_rad(float(r["yaw"]))), -cos(deg_to_rad(float(r["yaw"]))))
		var sp := maxf(sin(deg_to_rad(float(r["pitch"]))), 0.3)
		var tg: Vector3 = r["target"]
		## a point right of the middle moves the target right (the picture moves left); down the screen = nearer
		var shift: Vector2 = right * (-off.x * px_world) + fwd * (off.y * px_world / sp)
		r["target"] = tg + Vector3(shift.x, 0.0, shift.y)
		var size := hi - lo
		var k := maxf(size.x / maxf(band.size.x, 1.0), size.y / maxf(band.size.y, 1.0)) * 1.06
		r["span"] = clampf(float(r["span"]) * maxf(k, 0.05), min_span, MAX_SPAN)


## An even pick of at most `n` of `points` (always the first and the last).
static func _thin(points: Array, n: int) -> Array:
	var out := []
	var step := float(points.size() - 1) / float(maxi(1, n - 1))
	for k in n:
		out.append(points[int(round(k * step))])
	return out


## The rig between `a` and `b` at `k` (0..1, eased by the caller): the target, the pitch, the span and the
## shorter way round for the yaw.
static func lerp_rig(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var ya := float(a["yaw"])
	var yb := float(b["yaw"])
	var dy := fposmod(yb - ya + 180.0, 360.0) - 180.0
	return {"target": (a["target"] as Vector3).lerp(b["target"], k), "pitch": lerpf(float(a["pitch"]), float(b["pitch"]), k),
		"yaw": ya + dy * k, "fov": lerpf(float(a["fov"]), float(b["fov"]), k), "span": exp(lerpf(log(float(a["span"])), log(float(b["span"])), k))}
