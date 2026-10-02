class_name UiPalette
## Colours from design/STYLE_BIBLE.md used by the map screen. Read-only copies; the bible is the source.

## Player colours in seat order: P1 Vermilion, P2 Cobalt, P3 Gold, P4 Sky, P5 Jade, P6 Magenta.
const PLAYER_COLORS := [
	Color("#D8432C"), Color("#2D5BD1"), Color("#F1C232"), Color("#62C3F0"), Color("#2E9E6A"), Color("#D14FA8"),
]
const NEUTRAL := Color("#5B5750")  # IND slate (independents / unowned)

const TERRAIN := {
	"plains": Color("#B3B86A"),
	"forest": Color("#3F7A55"),
	"hills": Color("#B08A5E"),
}
const TERRAIN_UNKNOWN := Color("#8D88A0")

const SEA := Color("#244E6E")
const MAP_INK := Color("#2A231C")
const KEYLINE_INK := Color("#1A1612")
const KEYLINE_HALO := Color(0.957, 0.941, 0.910, 0.7)  # #F4F0E8 at 70%

const PANEL_BG := Color("#1C1B2A")
const PANEL_RAISED := Color("#282740")
const PANEL_BORDER := Color("#4E4A70")
const GILT := Color("#E6B84E")
const TEXT_PRIMARY := Color("#F1ECE0")
const TEXT_SECONDARY := Color("#BDB6CF")
const POSITIVE := Color("#72C47A")
const SELECTION := Color("#FFFFFF")


## Seat colour of a faction: its position in state.factions picks P1, P2, ... Unowned is slate.
static func owner_color(state: GameState, faction_id: String) -> Color:
	if faction_id.is_empty():
		return NEUTRAL
	for i in state.factions.size():
		if state.factions[i].id == faction_id:
			return PLAYER_COLORS[i % PLAYER_COLORS.size()]
	return NEUTRAL


static func terrain_color(terrain: String) -> Color:
	return TERRAIN.get(terrain, TERRAIN_UNKNOWN)
