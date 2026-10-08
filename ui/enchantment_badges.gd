class_name EnchantmentBadges
extends VBoxContainer
## The enchantments on a province's plate (M5-8, #119; design/M5_MAGIC_FOG.md §6.4, §11.2: "an enchantment on the map: its
## decal and a badge 'through turn 7'; hover gives the exact effect, who cast it, and when it ends"). One small badge for
## each ward, curse or Far Sight on the province, in the colour of its kind, with the ritual's name and the last turn it
## lasts; the hover gives the effect with the numbers it has, whose it is and when it ends, and right-click or F1 opens the
## ritual's codex entry. A blessing follows its armies, so it is on the army's panel (Map screen), and a global ritual
## (the Blood Moon) has no province: the Magic chip names it.
##
## Reads the GameState only: under fog it is the viewer's view, so a rival's enchantment shows only where you can see it
## (FogRules builds the view's enchantments). Like FortChip, make() is the one seam for every plate: the 2D map's regions
## and the 3D board's plates both add EnchantmentBadges.make(...), so they cannot disagree.
##
##   badges(state, viewer, pid)      [{"id", "ritual", "name", "kind", "faction", "until_turn", "text", "tooltip", "codex", "mine"}]
##   effect_text(state, e)           what an enchantment does, with its numbers, in words (the province panel's lines too)
##   make(state, pid, viewer, open)  the row of badges, or null when the province has none

## A badge's colour by kind of enchantment (never the only channel: the name and the turn are on it).
const KIND_COLOURS := {
	"ward": Color("#8FA6BF"),
	"curse": Color("#C0303A"),
	"sight": Color("#E6B84E"),
}
const BADGE_SIZE := 12


## The badges of `province_id` as `viewer` sees them, in enchantment id order (the state keeps them sorted).
static func badges(state: GameState, viewer: String, province_id: String) -> Array:
	var out := []
	if state == null or not MagicRules.has_magic(state):
		return out
	for e in state.enchantments:
		if String(e.province) != province_id or String(e.kind) == "blessing" or String(e.kind) == "global":
			continue
		var until := int(e.until_turn)
		var name := MagicRules.spell_name(String(e.ritual))
		var who := MagicRules._faction_display(state, String(e.faction))
		var mine := String(e.faction) == viewer
		out.append({"id": String(e.id), "ritual": String(e.ritual), "name": name, "kind": String(e.kind), "faction": String(e.faction),
			"until_turn": until, "text": "%s · through turn %d" % [name, until], "mine": mine,
			"tooltip": TooltipText.plain("%s (%s%s)" % [name, "yours: " if mine else "", who],
				"%s Cast by the %s. It lasts through turn %d and ends in that turn's enchantments phase. %s" % [effect_text(state, e), who, until,
				RulesCodex.text(String(e.kind))]),
			"codex": MagicRules.spell_codex(String(e.ritual))})
	return out


## What an enchantment does, in words with its numbers (§6.4): the line the badge's hover and the province panel share.
static func effect_text(state: GameState, e: Dictionary) -> String:
	var n := MagicRules.spell_numbers(String(e.ritual), int(e.bonus))
	var who := MagicRules._faction_display(state, String(e.faction))
	match String(e.kind):
		"curse":
			var text := "Fighters here not of the %s can't heal, and it takes %d hit points from them at the end of every turn, the healthiest first, never below 1." % [who, int(n.value)]
			if e.ending == true:
				text += " A Sanctum Ward ends it at the end of this turn."
			return text
		"ward":
			return "Rival rituals aimed here are turned aside while the %s hold it, and battles here are outside the Blood Moon." % who
		"sight":
			return "The %s see it in clear sight through Far Sight." % who
	return ""


## The row of badges for `province_id`, or null when it has none. `open` is called with a codex key on a right-click or F1.
static func make(state: GameState, province_id: String, viewer: String, open: Callable = Callable()) -> EnchantmentBadges:
	var list := badges(state, viewer, province_id)
	if list.is_empty():
		return null
	var row := EnchantmentBadges.new()
	row.name = "EnchantmentBadges"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 1)
	for b in list:
		row.add_child(_badge(b, open))
	return row


static func _badge(b: Dictionary, open: Callable) -> Control:
	var pill := PanelContainer.new()
	pill.name = "Badge_%s" % String(b.id).validate_node_name()
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.92)
	style.border_color = KIND_COLOURS.get(String(b.kind), UiPalette.GILT)
	style.border_width_left = 5
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 5
	style.content_margin_top = 0
	style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", style)
	var l := Label.new()
	l.name = "Text"
	l.text = String(b.text)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("rule_text", true)  # a date and a name; the hover has the effect and the codex link
	l.add_theme_font_size_override("font_size", BADGE_SIZE)
	l.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	pill.add_child(l)
	pill.tooltip_text = String(b.tooltip)
	if open.is_valid():
		CodexLink.attach(pill, String(b.codex), open)
	return pill
