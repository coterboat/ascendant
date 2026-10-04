class_name MapLayout
## UI-only screen layout of the M1 map. The rules data (data/map.gd) has no coordinates, so where
## each province is drawn lives here, never in the rules. Coordinates are in a SIZE-sized design
## space that the map view scales to fit its rect.
## The map is an exact mirror, so only the west half is placed by hand. Each east province sits at
## the mirror image (x -> SIZE.x - x) of its west twin, which makes the fairness visible.

const SIZE := Vector2(1000, 600)

## West half: province id -> centre in design space.
const WEST := {
	"crownkeep": Vector2(95, 300),
	"westwatch": Vector2(215, 130),
	"highcrag": Vector2(235, 300),
	"rivermarch": Vector2(215, 470),
	"stonegate": Vector2(370, 105),
	"thornvale": Vector2(405, 300),
	"greenglade": Vector2(370, 495),
}

## West province -> its east mirror twin (same terrain, income and fort in data/map.gd).
const MIRROR := {
	"crownkeep": "fangridge",
	"westwatch": "ebonpeak",
	"highcrag": "ironspike",
	"rivermarch": "bloodfen",
	"stonegate": "blackwood",
	"thornvale": "wildmoor",
	"greenglade": "deepwood",
}

const REGION_RADIUS := 62.0
const CAPITAL_RADIUS := 74.0


## Centre of a province in design space, or Vector2(-1, -1) if the layout does not know it.
static func position_of(province_id: String) -> Vector2:
	if WEST.has(province_id):
		return WEST[province_id]
	for west_id in MIRROR:
		if MIRROR[west_id] == province_id:
			var w: Vector2 = WEST[west_id]
			return Vector2(SIZE.x - w.x, w.y)
	return Vector2(-1, -1)


## True for provinces on the east half (mirror twins), whose markers are drawn mirrored too.
static func is_east(province_id: String) -> bool:
	return MIRROR.values().has(province_id)


static func has_position(province_id: String) -> bool:
	return position_of(province_id) != Vector2(-1, -1)


## Radius of a province's placeholder region in design space (capitals are drawn larger).
static func radius_of(province: Province) -> float:
	return CAPITAL_RADIUS if province.is_capital else REGION_RADIUS


## Placeholder region outline: a rounded 12-sided shape around `center`, slightly irregular per
## province so it reads as land rather than a token. The wobble is mirrored too, so twins match.
static func region_polygon(province_id: String, center: Vector2, radius: float) -> PackedVector2Array:
	var west_id := province_id
	var flip := false
	for w in MIRROR:
		if MIRROR[w] == province_id:
			west_id = w
			flip = true
	var points := PackedVector2Array()
	var sides := 12
	var h := west_id.hash()
	for i in sides:
		var angle := TAU * float(i) / sides
		var wobble := 0.9 + 0.1 * float((h >> (i * 2)) & 3) / 3.0
		var offset := Vector2(cos(angle), sin(angle)) * radius * wobble
		if flip:
			offset.x = -offset.x
		points.append(center + offset)
	if flip:
		points.reverse()
	return points
