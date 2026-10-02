class_name TooltipText
## Turns a Breakdown dictionary (rules/breakdown.gd) into multi-line tooltip text:
##   Income of Crownkeep
##     Base income of Crownkeep: 12  (set by the map)
##     Modifiers: +0  (none yet: ...)
##     = Income per turn: 12
##   <plain-language description, wrapped>
## Plain Control.tooltip_text is used everywhere, so lines are wrapped here to keep tooltips narrow.
##
## Codex links (#8): Breakdown dictionaries carry no codex key, so CODEX below says which RulesCodex
## entry explains each kind of number or term the UI shows. CodexLink.attach() puts that entry's name
## at the end of the tooltip and opens it on right-click (or F1 while hovering).

const WRAP := 64

## The RulesCodex entry behind each kind of number or term on screen. A breakdown that carries its own
## "codex" key wins over this table (codex_for). tests/test_codex_links_ui.gd checks every entry exists.
const CODEX := {
	# map top bar and side panel (MapScreen), regions and their badges (ProvinceRegion)
	"gold": "gold",
	"turn": "phase_order",
	"faction": "hotseat",
	"province": "province",
	"province_income": "income",
	"owner": "province",
	"owner_neutral": "neutral",
	"terrain": "battle_terrain",  # a terrain without an entry of its own (terrain_kind)
	"terrain_plains": "terrain_plains",
	"terrain_forest": "terrain_forest",
	"terrain_hills": "terrain_hills",
	"capital": "capital",
	"fort": "fort",
	"neighbors": "province",
	"army_units": "army",
	"army_strength": "army_strength",
	"commander": "commander",
	"unit_count": "units",
	"no_armies": "undefended",
	# orders (OrdersController via MapScreen)
	"move_order": "move",
	"move_odds": "battle_odds",
	"recruit": "recruit",
	"gold_after_recruits": "recruit",
	"order_check": "orders",
	# victory screen
	"game_over": "victory",
	"draw": "simultaneous_capture",
	"turns_played": "phase_order",
	"battles": "battle_rounds",
	"provinces_held": "province",
	"captures": "victory",
}


static func from_breakdown(b: Dictionary) -> String:
	var out := PackedStringArray()
	out.append(String(b.get("title", "")))
	var first := true
	for l in b.get("lines", []):
		var value: int = int(l.value)
		var shown := str(value) if first else ("%+d" % value)
		var note: String = l.get("note", "")
		out.append("  %s: %s%s" % [l.label, shown, "" if note.is_empty() else "  (%s)" % note])
		first = false
	out.append("  = %s: %d" % [b.get("total_label", "Total"), int(b.get("total", 0))])
	var desc: String = b.get("description", "")
	if not desc.is_empty():
		out.append("")
		out.append(wrap_text(desc))
	return "\n".join(out)


## The codex entry for a kind of number (a CODEX key), or the breakdown's own "codex" key when it
## has one. "" when neither names an entry that exists.
static func codex_for(kind: String, breakdown: Dictionary = {}) -> String:
	var key := String(breakdown.get("codex", CODEX.get(kind, "")))
	return key if RulesCodex.ENTRIES.has(key) else ""


## The CODEX kind for a province's terrain ("forest" -> "terrain_forest"), or the general "terrain"
## (Terrain in battle) for a terrain that has no entry of its own.
static func terrain_kind(terrain: String) -> String:
	var kind := "terrain_" + terrain
	return kind if CODEX.has(kind) else "terrain"


## The CODEX kind for a province's owner: "owner_neutral" when nobody owns it, otherwise "owner".
static func owner_kind(owner_id: String) -> String:
	return "owner_neutral" if owner_id.is_empty() else "owner"


## Plain text of the codex entry behind a kind of number or term, "" if it has none (for tooltips
## that explain a term with the codex's own words).
static func codex_text(kind: String) -> String:
	return RulesCodex.text(codex_for(kind))


## Word-wraps plain text to at most `width` characters per line (longer single words stay whole).
static func wrap_text(text: String, width: int = WRAP) -> String:
	var lines := PackedStringArray()
	var current := ""
	for word in text.split(" ", false):
		if current.is_empty():
			current = word
		elif current.length() + 1 + word.length() <= width:
			current += " " + word
		else:
			lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return "\n".join(lines)


## Title plus wrapped description, for labels that explain a fact rather than a number.
static func plain(title: String, description: String) -> String:
	return "%s\n\n%s" % [title, wrap_text(description)]


## "1 unit", "3 units", "0 units": a count with its noun in the right number. Pass `plural` for
## nouns that don't just take an "s".
static func count(n: int, singular: String, plural: String = "") -> String:
	var noun := singular if n == 1 else (plural if not plural.is_empty() else singular + "s")
	return "%d %s" % [n, noun]
