extends SceneTree
## Rig lab (10-11): our own animation clips, written as code, on a rigged Bake3D model.
## Future-state testing ground, not wired into the game. See tools/rig_lab/README.md.
##
##   godot --path . -s tools/rig_lab/lab.gd --always-on-top --resolution 960x720 -- \
##       --clip=gallop --frames=24 --yaw=55 [--glb=<path>] [--out=<dir>]
##
## clips: rest, gallop, strike, idle, fall. Frames land in <out>/<clip>/NNNN.png
## (default out: /tmp/rig_lab). The GLB is loaded at runtime, so it never needs a Godot import.

const DEFAULT_GLB := "res://tools/rig_lab/models/iron_knight.glb"

var sk: Skeleton3D
var rest := {}   # name -> local rest rotation
var gbas := {}   # name -> global rest basis (orthonormal)
var idx := {}


func _init() -> void:
	var opt := {"clip": "rest", "frames": "1", "yaw": "55", "glb": DEFAULT_GLB, "out": "/tmp/rig_lab"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opt[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var clip: String = opt["clip"]
	var nframes := int(opt["frames"])
	var yaw := float(opt["yaw"])
	root.gui_disable_input = true
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.83, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	w.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	ground.mesh = pm
	w.add_child(ground)
	var knight := _load_glb(ProjectSettings.globalize_path(String(opt["glb"])))
	if knight == null:
		push_error("rig_lab: could not load %s" % opt["glb"])
		quit(1)
		return
	w.add_child(knight)
	for n in knight.find_children("*", "Skeleton3D", true, false):
		sk = n
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		idx[nm] = i
		rest[nm] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		gbas[nm] = sk.get_bone_global_rest(i).basis.orthonormalized()
	var cam := Camera3D.new()
	cam.fov = 35
	var r := deg_to_rad(yaw)
	w.add_child(cam)
	# root's children aren't inside the tree yet during _init, so look_at() would fail silently
	cam.look_at_from_position(Vector3(sin(r) * 3.6, 1.2, cos(r) * 3.6), Vector3(0, 0.7, 0))
	await process_frame
	var dir := String(opt["out"]).path_join(clip)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in nframes:
		var t := float(f) / float(max(nframes, 1))
		_reset()
		knight.transform = Transform3D.IDENTITY
		match clip:
			"gallop": _gallop(t, knight)
			"strike": _strike(t, knight)
			"idle": _idle(t, knight)
			"fall": _fall(t, knight)
		for k in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("%04d.png" % f))
	print("rig_lab: %d frame(s) in %s" % [nframes, dir])
	quit()


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _reset() -> void:
	for nm in rest:
		sk.set_bone_pose_rotation(idx[nm], rest[nm])
		sk.set_bone_pose_position(idx[nm], sk.get_bone_rest(idx[nm]).origin)

## Rotate bone `nm` by `deg` about a WORLD axis (correct while its parents turn about parallel axes).
func rot(nm: String, axis: Vector3, deg: float) -> void:
	var la: Vector3 = (gbas[nm].inverse() * axis).normalized()
	var i: int = idx[nm]
	sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion(la, deg_to_rad(deg)))

func s(x: float) -> float:
	return sin(TAU * x)

## Transverse gallop, one stride per loop. Pitch about X: negative = swing forward (toward +Z).
func _leg(pre: String, side: String, ph: float, fore: bool) -> void:
	var sw := s(ph)                      # +1 = fully back, -1 = fully forward
	var lift: float = max(0.0, -s(ph + 0.25))  # flex while the leg travels forward
	if fore:
		rot("thigh%s0" % side, Vector3.RIGHT, sw * 34.0 - 6.0)
		rot("shin%s0" % side, Vector3.RIGHT, lift * 80.0)
		rot("foot%s0" % side, Vector3.RIGHT, lift * 40.0)
	else:
		rot("thigh%s1" % side, Vector3.RIGHT, sw * 32.0)
		rot("shin%s1" % side, Vector3.RIGHT, lift * 55.0)
		rot("foot%s1" % side, Vector3.RIGHT, -lift * 45.0)

func _gallop(t: float, k: Node3D) -> void:
	_leg("", "L", t + 0.00, false)
	_leg("", "R", t + 0.12, false)
	_leg("", "R", t + 0.42, true)
	_leg("", "L", t + 0.54, true)
	var pitch := s(t + 0.1) * 5.0
	rot("hips", Vector3.RIGHT, pitch)
	rot("neck", Vector3.RIGHT, -s(t + 0.25) * 9.0)
	rot("head", Vector3.RIGHT, s(t + 0.25) * 6.0)
	for i in 4:
		rot("tail%d" % i, Vector3.RIGHT, -8.0 + s(t - 0.1 * i) * 6.0)
	k.position.y = 0.05 * (0.5 + 0.5 * s(t + 0.35))
	# rider: rises in the stirrups, absorbs the pitch, lance couched and steady
	rot("riderPelvis", Vector3.RIGHT, -pitch * 0.8)
	rot("riderTorso", Vector3.RIGHT, 12.0 + s(t + 0.2) * 3.0)
	rot("riderHead", Vector3.RIGHT, -10.0)

func _idle(t: float, k: Node3D) -> void:
	var b := s(t)
	rot("chest", Vector3.RIGHT, b * 1.2)
	rot("neck", Vector3.RIGHT, 6.0 + b * 3.0)
	rot("head", Vector3.UP, s(t * 0.5) * 8.0)
	rot("earL", Vector3.RIGHT, max(0.0, s(t * 2.0)) * 20.0)
	for i in 4:
		rot("tail%d" % i, Vector3.UP, s(t - 0.12 * i) * 10.0)
	rot("riderTorso", Vector3.RIGHT, b * 2.0)
	rot("riderHead", Vector3.UP, s(t * 0.5 + 0.3) * 12.0)
	rot("thighR0", Vector3.RIGHT, max(0.0, s(t * 1.0 - 0.1)) * -14.0)
	rot("shinR0", Vector3.RIGHT, max(0.0, s(t * 1.0 - 0.1)) * -40.0)

func _pivot(k: Node3D, axis: Vector3, deg: float, piv: Vector3) -> void:
	var b := Basis(axis, deg_to_rad(deg))
	k.transform = Transform3D(b, piv - b * piv) * k.transform

func _strike(t: float, k: Node3D) -> void:
	# 0-0.35 rear (front hooves up, lance raised), 0.35-0.55 come down and drive the lance, 0.55-1 recover
	var wind: float = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.35, 0.5, t))
	var drive: float = smoothstep(0.35, 0.5, t) * (1.0 - smoothstep(0.6, 1.0, t))
	var ang := -wind * 24.0 + drive * 5.0
	for side in ["L", "R"]:
		rot("thigh%s1" % side, Vector3.RIGHT, -ang)       # hind legs stay planted
	rot("thighL0", Vector3.RIGHT, -wind * 60.0 + drive * 12.0)
	rot("shinL0", Vector3.RIGHT, wind * 95.0)
	rot("thighR0", Vector3.RIGHT, -wind * 45.0 - drive * 20.0)
	rot("shinR0", Vector3.RIGHT, wind * 80.0)
	rot("neck", Vector3.RIGHT, -wind * 10.0 + drive * 14.0)
	for i in 4:
		rot("tail%d" % i, Vector3.RIGHT, wind * 10.0 - drive * 8.0)
	rot("riderPelvis", Vector3.RIGHT, -ang * 0.6)
	rot("riderTorso", Vector3.RIGHT, -wind * 6.0 + drive * 24.0)
	rot("upperArmL", Vector3.RIGHT, -wind * 30.0 + drive * 18.0)
	k.position.z = drive * 0.3
	_pivot(k, Vector3.RIGHT, ang, Vector3(0, 0, -0.45))

func _fall(t: float, k: Node3D) -> void:
	# stumble: front legs buckle, then the horse rolls onto its side; the rider slumps
	var a: float = smoothstep(0.0, 0.5, t)
	var roll: float = smoothstep(0.3, 1.0, t)
	rot("thighL0", Vector3.RIGHT, -a * 30.0)
	rot("shinL0", Vector3.RIGHT, a * 110.0)
	rot("thighR0", Vector3.RIGHT, -a * 25.0)
	rot("shinR0", Vector3.RIGHT, a * 100.0)
	rot("thighL1", Vector3.RIGHT, roll * 30.0)
	rot("thighR1", Vector3.RIGHT, roll * 40.0)
	rot("neck", Vector3.RIGHT, a * 20.0 - roll * 30.0)
	rot("riderTorso", Vector3.RIGHT, a * 30.0)
	rot("riderTorso", Vector3.BACK, roll * 20.0)
	rot("riderHead", Vector3.RIGHT, a * 25.0)
	_pivot(k, Vector3.RIGHT, a * 12.0, Vector3(0, 0, 0.45))   # nose dips as the front buckles
	_pivot(k, Vector3.BACK, roll * 78.0, Vector3(-0.27, 0, 0))
	k.position.y -= roll * 0.18
