class_name UnitStrip
extends HFlowContainer
## UX-3 (design/UX_WAR_TABLE.md §3.1): an army's portraits, one per fighter, each with its hit-point bar under it: the
## commander first, framed in gilt as every commander is, and a ruler's army as its ruler, gilt-ringed. A wounded fighter is a
## shorter bar (and a different colour: the length says it without the colour). Hovering a portrait says who it is and how
## many hit points it has left, with the unit's full card; right-click opens the codex.
##
## The army card shows it at full size and the rows of "your other armies here" show it small (the place ARM-1's drag, Split,
## Merge all and Swap commanders will use: each chip is one fighter, `unit_ref` is its Unit, so a later drag has something to hold).
##
## Only for an army the viewer sees exactly: a rival's stand-in under fog has no true fighters, so it never gets a strip.

const BAR_H := 5.0
const BAR_GAP := 2.0
const GAP := 4

var portrait_size := Vector2(40, 40)
var bars := true


## The strip for `army` as `state` shows it. `size` is each portrait's size; `with_bars` draws the hit-point bars.
static func make(state: GameState, army: Army, portrait: Vector2 = Vector2(40, 40), request_codex: Callable = Callable(),
		with_bars: bool = true) -> UnitStrip:
	var strip := UnitStrip.new()
	strip.name = "UnitStrip"
	strip.portrait_size = portrait
	strip.bars = with_bars
	strip.add_theme_constant_override("h_separation", GAP)
	strip.add_theme_constant_override("v_separation", GAP)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if army.ruler != null:
		strip.add_child(strip._ruler_chip(state, army, request_codex))
		return strip
	if army.commander != null:
		strip.add_child(strip._unit_chip(state, army, army.commander, true, request_codex))
	for u in army.units:
		strip.add_child(strip._unit_chip(state, army, u, false, request_codex))
	return strip


## The chips, in order (commander first): tests and ARM-1 read them.
func chips() -> Array:
	return get_children().filter(func(c): return c is Chip)


func _unit_chip(state: GameState, army: Army, u: Unit, is_commander: bool, request_codex: Callable) -> Chip:
	var chip := Chip.new()
	chip.name = "Chip_%s" % u.type.id.validate_node_name()
	chip.unit_ref = u
	chip.army_id = army.id
	chip.is_commander = is_commander
	var card := Art.portrait_card(u.type.id, portrait_size, army.owner, Art.Crop.FACE)
	card.texture = Art.unit_portrait(state, army.owner, u.type.id)
	chip.setup(card, u.current_hp, u.type.hp, bars)
	var who := ("%s, the commander" % u.type.name) if is_commander else u.type.name
	# Hit points are only said where they are shown: the bar and the tooltip go together (under fog a rival's are not ours to see).
	chip.tooltip_text = TooltipText.plain("%s: %d of %d hit points" % [who, u.current_hp, u.type.hp] if bars else who,
		"%s%s" % [Breakdown.unit_type_description(u.type), " Hit points are what a fighter can lose before it falls; they stay between battles until healing mends them." if bars else ""])
	CodexLink.attach(chip, "commander" if is_commander else "units", request_codex if request_codex.is_valid() else func(_k): pass)
	return chip


func _ruler_chip(state: GameState, army: Army, request_codex: Callable) -> Chip:
	var f := state.find_faction(army.owner)
	var chip := Chip.new()
	chip.name = "Chip_ruler"
	chip.unit_ref = army.ruler
	chip.army_id = army.id
	chip.is_ruler = true
	var ruler_name := RulerRules.current_name(state, army.owner) if f != null else "the ruler"
	var card: Art.PortraitCard
	var max_hp := army.ruler.current_hp
	if f != null and f.has_ruler():
		card = Art.ruler_card(f.ruler_type, ruler_name, portrait_size, Art.Crop.FACE)
		max_hp = maxi(int(Breakdown.ruler_stat(state, army.owner, "hp").total), army.ruler.current_hp)
	else:
		card = Art.portrait_card(army.ruler.type.id, portrait_size, army.owner, Art.Crop.FACE, UiPalette.GILT)
	chip.setup(card, army.ruler.current_hp, max_hp, bars)
	chip.tooltip_text = TooltipText.plain("%s: %d of %d hit points" % [RulerRules._cap(ruler_name), army.ruler.current_hp, max_hp] if bars else RulerRules._cap(ruler_name),
		"A ruler fights in person: an army of its own that holds no other fighters. If it falls, a successor follows.")
	CodexLink.attach(chip, "ruler_army", request_codex if request_codex.is_valid() else func(_k): pass)
	return chip


## One fighter: its portrait and, under it, its hit-point bar. Takes the mouse so its tooltip shows.
class Chip extends Control:
	var unit_ref: Unit = null
	var army_id := ""
	var is_commander := false
	var is_ruler := false
	var hp := 0
	var max_hp := 0
	var bar_h := 0.0
	var _portrait: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func setup(card: Control, current_hp: int, max_hit_points: int, with_bar: bool) -> void:
		_portrait = card
		hp = current_hp
		max_hp = max_hit_points
		bar_h = (UnitStrip.BAR_H + UnitStrip.BAR_GAP) if with_bar and max_hit_points > 0 else 0.0
		add_child(card)
		card.position = Vector2.ZERO
		custom_minimum_size = Vector2(card.custom_minimum_size.x, card.custom_minimum_size.y + bar_h)

	## The fraction of its hit points the fighter has left, 0 to 1.
	func fraction() -> float:
		return clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)

	func has_bar() -> bool:
		return bar_h > 0.0

	func _draw() -> void:
		if bar_h <= 0.0 or _portrait == null:
			return
		var f := fraction()
		var bar := Rect2(1.0, _portrait.custom_minimum_size.y + UnitStrip.BAR_GAP, size.x - 2.0, UnitStrip.BAR_H)
		draw_rect(bar, UiPalette.KEYLINE_INK)
		var colour := UiPalette.POSITIVE if f > 0.5 else (UiPalette.GILT if f > 0.25 else UiPalette.NEGATIVE)
		var inner := bar.grow(-1.0)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * f, inner.size.y)), colour)
