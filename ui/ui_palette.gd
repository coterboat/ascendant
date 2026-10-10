class_name UiPalette
## Colours from design/STYLE_BIBLE.md used by every screen. Read-only copies; the bible is the source.
##
## Player colours follow the SEAT, never the faction (bible 1.1, director's call for M1): Player 1 is
## Vermilion and Player 2 is Cobalt whichever faction they picked, so swapping seats on the new game
## screen swaps the colours everywhere. This file is the one place that decides a faction's colour:
## screens pass the session's seat order (GameSession.players()) to faction_color() / owner_color().
## Without a session (map preview, standalone tests) the seat order is the state's faction order,
## which is the default seating of a new game.

## Player colours in seat order: P1 Vermilion, P2 Cobalt, P3 Gold, P4 Sky, P5 Jade, P6 Magenta.
const PLAYER_COLORS := [
	Color("#D8432C"), Color("#2D5BD1"), Color("#F1C232"), Color("#62C3F0"), Color("#2E9E6A"), Color("#D14FA8"),
]
const PLAYER_COLOR_NAMES := ["Vermilion", "Cobalt", "Gold", "Sky", "Jade", "Magenta"]
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
const TEXT_DISABLED := Color("#7E7896")
const POSITIVE := Color("#72C47A")
const NEGATIVE := Color("#F06A64")
const LINK := Color("#86C1F0")
const SELECTION := Color("#FFFFFF")

## The type scale (design/UX_WAR_TABLE.md section 7), font sizes in logical pixels at a 1600-wide
## viewport. The window's content scale does the rest, so the same numbers serve every supported
## window. Pair each with its font in UiFonts: TYPE_TITLE with title(), TYPE_NAME with name(),
## TYPE_BODY and TYPE_SMALL with body(), TYPE_NUMBER with number(). New War Table pieces use these;
## the existing screens still set their own sizes and are not changed to match. The least is
## TYPE_SMALL, above the bible's 12 px floor (section 2.1).
const TYPE_TITLE := 28
const TYPE_NAME := 20
const TYPE_BODY := 16
const TYPE_SMALL := 14
const TYPE_NUMBER := 18


## Colour of a 0-based seat (0 is Player 1). A negative seat (nobody) is slate.
static func seat_color(seat_index: int) -> Color:
	if seat_index < 0:
		return NEUTRAL
	return PLAYER_COLORS[seat_index % PLAYER_COLORS.size()]


## Player-facing name of a seat's colour: "Vermilion" for Player 1.
static func seat_color_name(seat_index: int) -> String:
	if seat_index < 0:
		return "Slate"
	return PLAYER_COLOR_NAMES[seat_index % PLAYER_COLOR_NAMES.size()]


## Faction ids in seat order, for colouring: the session's players when there is a session,
## otherwise the state's faction order (a new game's default seats), otherwise the faction data order.
static func seat_order(state: GameState = null, session: GameSession = null) -> Array:
	if session != null and not session.players().is_empty():
		return session.players()
	var out := []
	if state != null:
		for f in state.factions:
			out.append(f.id)
	else:
		for f in FactionData.FACTIONS:
			out.append(f.id)
	return out


## Seat colour of a faction, given the seat order (faction ids, seat 1 first). Unowned is slate.
static func faction_color(seats: Array, faction_id: String) -> Color:
	if faction_id.is_empty():
		return NEUTRAL
	return seat_color(seats.find(faction_id))


## Seat colour of a faction in `state`. Pass the session's seat order as `seats`; without it the
## state's faction order stands in for the seats.
static func owner_color(state: GameState, faction_id: String, seats: Array = []) -> Color:
	return faction_color(seats if not seats.is_empty() else seat_order(state), faction_id)


## 0-based seat of a faction (0 is Player 1), or -1 for nobody, with the same seat order as
## owner_color(). The seat picks the emblem (SeatEmblem) as well as the colour.
static func seat_index(state: GameState, faction_id: String, seats: Array = []) -> int:
	if faction_id.is_empty():
		return -1
	return (seats if not seats.is_empty() else seat_order(state)).find(faction_id)


static func terrain_color(terrain: String) -> Color:
	return TERRAIN.get(terrain, TERRAIN_UNKNOWN)


## The opaque overlay panel: panel background with a keyline border (bible 1.3). Used under the codex
## and every modal panel, so the map never shows through their text.
static func panel_style(margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(margin)
	return style
