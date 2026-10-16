class_name VfxSheets
extends RefCounted
## VFX-WIRE (#242; design/STYLE_BIBLE.md §4.2; #229's sheets, Alex's verdicts 10-13 and 10-15): the effect sheets the battle stage, the
## Simple view and the board draw. A sheet is two files, assets/vfx/<id>/<id>.webp (its frames in a grid, left to right, then top to
## bottom) and assets/vfx/<id>/<id>.json:
##   {"frames": 16, "columns": 4, "frame_size": [192, 192], "fps": 24, "hit_frame": 6, "loop": [1, 15]}
## "loop" is the frames a looping sheet plays, 0-based, both ends in (cast_channel and summon_ring skip frame 0, the dark input still);
## a one-shot has none. A field left out takes its kind's default from the bible (DEFAULTS). A sheet whose files are missing is {}: the
## caller draws today's code effect instead, so nothing breaks before the files land.
##
## Every sheet draws with its own alpha (normal blend), never additive (Alex 10-13: additive washed the bright cel board to white).
##
## Where each plays (MOMENTS):
##   hit_impact    every hit that lands
##   big_impact    a hit of 8 or more (BattlePlayer.BIG_HIT), or a Charge's hit
##   ruler_fall    a ruler falls, from the head of its staff (the model's highest point: Models.fx_top), not the figure's middle
##   sun_flare     Sunlance's hit, and Sunburst's flare
##   blood_spray   Bloodbolt's hit
##   briar_burst   Briar Snare on its targets: on the ground at their feet, turned to their facing
##   cast_channel  a caster channelling, looping while it casts: on the ground under it, turned to its facing
##   summon_ring   Call the Pack and Wake the Greenwrath, where the summons stand: on the ground, turned to their facing
## dust_puff is held (Alex 10-15): the code puffs stay.
##
## Playback: a one-shot lines its hit_frame up with the moment of contact. Playback knows each blow's time in advance, so an impact
## starts hit_frame / fps before its blow (lead); what can't be known ahead starts on its hit_frame (the director's call, provisional).
##
##   sheet(id) -> {} or {"id", "texture", "frames", "columns", "rows", "size", "fps", "hit_frame", "loop", "ground"}
##   frame_at(s, t) -> int        the frame `t` seconds after the sheet started (-1: not yet, or a one-shot over)
##   lead(s), life(s)             seconds from start to hit_frame, and a one-shot's whole length
##   region(s, frame) -> Rect2    the frame's cell in the texture
##   draw(ci, s, frame, centre, edge, alpha)   one frame in 2D, `edge` px a side

const IDS := ["hit_impact", "big_impact", "ruler_fall", "sun_flare", "briar_burst", "blood_spray", "summon_ring", "cast_channel"]
## The sheets drawn on the ground plane, turned to their unit's facing (Alex 10-15 on cast_channel: "note this for all similar effects").
const GROUND := ["briar_burst", "summon_ring", "cast_channel"]
## The bible's §4.2 defaults, by kind: impacts and bursts are one-shots at 24 fps, channels and rings loops at 12.
const DEFAULTS := {
	"impact": {"frames": 16, "columns": 4, "fps": 24, "hit_frame": 6},
	"loop": {"frames": 16, "columns": 4, "fps": 12, "hit_frame": 0, "loop": [1, 15]},
}
const LOOPS := ["summon_ring", "cast_channel"]
## The moments of a battle and of the board, and the sheet each plays (#229's table).
const MOMENTS := {"hit": "hit_impact", "big_hit": "big_impact", "ruler_fall": "ruler_fall", "sunlance": "sun_flare", "sunburst": "sun_flare",
	"bloodbolt": "blood_spray", "briar_snare": "briar_burst", "channel": "cast_channel", "summon": "summon_ring"}
## SpellPlan's code marks a sheet replaces when it is there (its element kind -> the sheet); "channel" is the sheet alone.
const ELEMENTS := {"burst": "sun_flare", "blood_spray": "blood_spray", "briar_burst": "briar_burst", "summon_ring": "summon_ring",
	"channel": "cast_channel"}

## Where the sheets are: tests point it at a fixture folder (user://) and back.
static var root := "res://assets/vfx"
static var _cache := {}


## The sheet for a moment of MOMENTS ("" when the moment has none).
static func for_moment(moment: String) -> String:
	return String(MOMENTS.get(moment, ""))


## The sheet `id`, loaded once: {} when its files are missing or unreadable (the caller draws its code effect).
static func sheet(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var out := _load(id)
	_cache[id] = out
	return out


static func clear_cache() -> void:
	_cache.clear()


static func _load(id: String) -> Dictionary:
	var base := "%s/%s/%s" % [root, id, id]
	var tex := _texture(base)
	if tex == null or not FileAccess.file_exists(base + ".json"):
		return {}
	var meta = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	if not (meta is Dictionary):
		return {}
	var d: Dictionary = DEFAULTS["loop" if LOOPS.has(id) else "impact"]
	var frames := maxi(1, int(meta.get("frames", d["frames"])))
	var columns := clampi(int(meta.get("columns", d["columns"])), 1, frames)
	var rows := ceili(float(frames) / columns)
	var size := Vector2(tex.get_width() / float(columns), tex.get_height() / float(rows))
	var fs: Variant = meta.get("frame_size")
	if fs is Array and (fs as Array).size() == 2:
		size = Vector2(float(fs[0]), float(fs[1]))
	var loop: Array = []
	var lp: Variant = meta.get("loop", d.get("loop"))
	if lp is Array and (lp as Array).size() == 2:
		loop = [clampi(int(lp[0]), 0, frames - 1), clampi(int(lp[1]), 0, frames - 1)]
	return {"id": id, "texture": tex, "frames": frames, "columns": columns, "rows": rows, "size": size,
		"fps": maxf(1.0, float(meta.get("fps", d["fps"]))), "hit_frame": clampi(int(meta.get("hit_frame", d["hit_frame"])), 0, frames - 1),
		"loop": loop, "ground": GROUND.has(id)}


## The sheet's texture: the imported .webp in the game, or a plain image file (a test's fixture, a sheet not imported yet).
static func _texture(base: String) -> Texture2D:
	for ext in [".webp", ".png"]:
		var path: String = base + ext
		if path.begins_with("res://") and ResourceLoader.exists(path):
			var t = load(path)
			if t is Texture2D:
				return t
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null and not img.is_empty():
				return ImageTexture.create_from_image(img)
	return null


## The frame `t` seconds after the sheet started: a one-shot runs once (-1 before its start and after its last frame), a loop runs its
## loop frames over and over.
static func frame_at(s: Dictionary, t: float) -> int:
	if s.is_empty() or t < 0.0:
		return -1
	var i := int(floor(t * float(s["fps"]) + 0.0001))
	var loop: Array = s["loop"]
	if not loop.is_empty():
		var a := int(loop[0])
		var n := int(loop[1]) - a + 1
		return a + posmod(i, maxi(n, 1))
	return i if i < int(s["frames"]) else -1


## Seconds from a one-shot's start to its hit_frame: how far ahead of a blow it starts.
static func lead(s: Dictionary) -> float:
	return 0.0 if s.is_empty() else float(s["hit_frame"]) / float(s["fps"])


## A one-shot's length in seconds.
static func life(s: Dictionary) -> float:
	return 0.0 if s.is_empty() else float(s["frames"]) / float(s["fps"])


## The frame's cell in the texture.
static func region(s: Dictionary, frame: int) -> Rect2:
	var cols := int(s["columns"])
	var size: Vector2 = s["size"]
	return Rect2(Vector2(posmod(frame, cols) * size.x, int(frame / cols) * size.y), size)


## One frame in 2D (the Simple view, the stage's overlay): the cell drawn `edge` px a side, centred on `centre`, with the sheet's own
## alpha times `alpha` (a CanvasItem's normal blend).
static func draw(ci: CanvasItem, s: Dictionary, frame: int, centre: Vector2, edge: float, alpha: float = 1.0) -> void:
	if s.is_empty() or frame < 0:
		return
	var size: Vector2 = s["size"]
	var h := edge * size.y / maxf(size.x, 1.0)
	ci.draw_texture_rect_region(s["texture"], Rect2(centre - Vector2(edge, h) * 0.5, Vector2(edge, h)), region(s, frame), Color(1, 1, 1, alpha))
