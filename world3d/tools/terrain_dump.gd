extends SceneTree
## Headless: bake the land and save its data as pictures (relief, territories, borders, ground).
##   godot --headless --path . -s world3d/tools/terrain_dump.gd -- out=/some/dir
const Terrain3D := preload("res://world3d/terrain3d.gd")


func _initialize() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var t = Terrain3D.build()
	print("baked %dx%d cells (cell %.1f) in %d ms; heights %.1f..%.1f; crossings %d, roads %d" % [t.w, t.h, t.cell, t.millis, t.lo, t.hi, t.crossings.size(), t.roads.size()])
	var relief := Image.create(t.w, t.h, false, Image.FORMAT_RGB8)
	var terr := Image.create(t.w, t.h, false, Image.FORMAT_RGB8)
	for y in t.h:
		for x in t.w:
			var k: int = y * t.w + x
			var hv: float = t.heights[k]
			var c: Color
			if hv < 0.0:
				c = Color(0.1, 0.25, 0.4).lerp(Color(0.02, 0.06, 0.12), clampf(-hv / 26.0, 0, 1))
			else:
				c = Color(0.3, 0.5, 0.2).lerp(Color(0.95, 0.9, 0.8), clampf(hv / 50.0, 0, 1))
			var nb: Vector3 = t.normal_at(Terrain3D.ORIGIN + Vector2((x + 0.5) * t.cell, (y + 0.5) * t.cell))
			c = c * (0.55 + 0.45 * clampf(nb.dot(Vector3(-0.5, 0.8, -0.3).normalized()), 0, 1))
			relief.set_pixel(x, y, c)
			var i: int = t.idx[k]
			var tc := Color(0.1, 0.2, 0.35)
			if i != 255:
				tc = Color.from_hsv(float(i) / 14.0, 0.5, 0.9)
				if t.border[k] < 2.0:
					tc = Color.BLACK if t.wall[k] == 1 else Color.WHITE
				if t.road_d[k] < 2.0:
					tc = Color(0.6, 0.4, 0.2)
			terr.set_pixel(x, y, tc)
	relief.save_png(out.path_join("terrain_relief.png"))
	terr.save_png(out.path_join("terrain_territories.png"))
	t.ground_image.save_png(out.path_join("terrain_ground.png"))
	for i in t.ids.size():
		print("%-11s stage %.1f coast %.0f" % [t.ids[i], t.stage_h[i], t.coast_at(t.centres[i])])
	quit(0)
