class_name RulerPanel
## The ruler's army on the map (M2, #29): its badge text, its summary tooltip, and the lines the map's
## side panel shows for it, with a breakdown behind every number (hit points, attack, defense, morale,
## kept power, ability rank) and a codex link on each. UI only: every number and sentence comes from
## RulerRules and Breakdown, so nothing here can disagree with the rules.


## The ruler's badge on its province (instead of "3 units"): a ruler's army holds only the ruler.
static func badge_text(_army: Army) -> String:
	return "Ruler"


## A few lines about the ruler for the badge and the side panel header:
##   Aurel Crown ruler King Corvane I at Crownkeep
##     mortal line, fights in the front rank
##     Hit points 46 of 46, attack 14, defense 13, morale 10 (+2 to its side while it stands)
##     Kept power 10 of 10, ability rank 4: Royal Court +5 gold
##     Mandates: none
##   <the succession rule>
static func summary(state: GameState, army: Army) -> String:
	if army == null or army.ruler == null:
		return ""
	var f := state.find_faction(army.owner)
	if f == null or not f.has_ruler():
		return TurnResolver.army_label(state, army)
	var s := RulerRules.ruler_stats(f.ruler_type, f.kept_power, f.ruler_generation)
	var lines := PackedStringArray()
	lines.append(TurnResolver.army_label(state, army))
	lines.append("  %s" % RulerRules.kind_line(f.ruler_type))
	lines.append("  Hit points %d of %d, attack %d, defense %d, morale %d (+%d to its side while it stands)" % [
		army.ruler.current_hp, s.hp, s.attack, s.defense, s.morale, s.morale_bonus])
	lines.append("  Kept power %d of %d, ability rank %d: %s %s" % [f.kept_power, RulerData.POWER_POOL, s.ability_rank,
		s.ability_name, RulerRules.ability_short(f.ruler_type, s.ability_rank)])
	lines.append("  Mandates: %s" % _mandate_names(f))
	lines.append("")
	lines.append(TooltipText.wrap_text(RulerRules.succession_text(f.ruler_type, f.kept_power, f.ruler_generation,
		_province_name(state, f.capital))))
	return "\n".join(lines)


## Adds the ruler's lines under the army header in the map's side panel. Each line's tooltip is its
## breakdown (or rule) and links its codex entry; right-clicks call `request_codex`.
static func fill(box: Control, state: GameState, army: Army, request_codex: Callable) -> void:
	var f := state.find_faction(army.owner)
	if f == null or not f.has_ruler() or army.ruler == null:
		return
	var fid := f.id
	var rid := f.ruler_type
	var name := RulerRules.current_name(state, fid)
	var ruler_label := _text(box, "Ruler: %s" % name, TooltipText.plain("%s, ruler of the %s" % [RulerRules._cap(name), f.faction_name],
		"%s It %s. %s" % [String(RulerRules.ruler_data(rid).get("flavour", "")), RulerData.BATTLE_RANKS.get(RulerRules.battle_rank(rid), ""),
			RulesCodex.text("ruler_army")]), UiPalette.GILT)
	ruler_label.name = "RulerLabel"
	CodexLink.attach(ruler_label, "ruler_" + rid, request_codex)

	var hp := Breakdown.ruler_stat(state, fid, "hp")
	var hp_label := _text(box, "Hit points: %d of %d" % [army.ruler.current_hp, int(hp.total)], "%s\n\n%s" % [
		TooltipText.from_breakdown(hp), TooltipText.wrap_text("%s has %d of its %d hit points now." % [
			RulerRules._cap(name), army.ruler.current_hp, int(hp.total)])])
	hp_label.name = "RulerHpLabel"
	_link(hp_label, hp, request_codex)
	for stat in ["attack", "defense", "morale"]:
		var b := Breakdown.ruler_stat(state, fid, stat)
		var shown := "Morale: %d alone, +%d to its side" % [int(b.total), RulerData.RULER_MORALE] if stat == "morale" \
			else "%s: %d" % [stat.capitalize(), int(b.total)]
		var l := _text(box, shown, TooltipText.from_breakdown(b))
		l.name = "Ruler%sLabel" % stat.capitalize()
		_link(l, b, request_codex)

	var kept := Breakdown.kept_power(state, fid)
	var kept_label := _text(box, "Kept power: %d of %d" % [int(kept.total), RulerData.POWER_POOL], TooltipText.from_breakdown(kept))
	kept_label.name = "KeptPowerLabel"
	_link(kept_label, kept, request_codex)

	var rank := Breakdown.ability_rank(state, fid)
	var ability_label := _text(box, "Ability: %s, rank %d (%s)" % [RulerRules.ability_name(rid), int(rank.total),
		RulerRules.ability_short(rid, int(rank.total))], TooltipText.from_breakdown(rank))
	ability_label.name = "AbilityLabel"
	_link(ability_label, rank, request_codex)

	var mandate_lines := PackedStringArray()
	for mid in f.mandates:
		var md := RulerRules.mandate_data(mid)
		mandate_lines.append(TooltipText.wrap_text("%s (%d power): %s" % [md.get("name", ""), int(md.get("cost", 0)), md.get("effect", "")]))
	var mandates_tip := TooltipText.plain("Mandates of the %s" % f.faction_name, RulesCodex.text("mandates"))
	if not mandate_lines.is_empty():
		mandates_tip = "%s\n\n%s" % [mandates_tip, "\n".join(mandate_lines)]
	var mandates_label := _text(box, "Mandates: %s" % _mandate_names(f), mandates_tip, UiPalette.TEXT_SECONDARY)
	mandates_label.name = "MandatesLabel"
	CodexLink.attach(mandates_label, "mandates", request_codex)

	var kind_key := String(RulerData.KINDS.get(String(RulerRules.ruler_data(rid).get("kind", "")), {}).get("codex", "succession"))
	var succession_label := _text(box, "Succession: %s" % RulerRules.kind_name(rid), TooltipText.plain("Succession",
		RulerRules.succession_text(rid, f.kept_power, f.ruler_generation, _province_name(state, f.capital))), UiPalette.TEXT_SECONDARY)
	succession_label.name = "SuccessionLabel"
	CodexLink.attach(succession_label, kind_key, request_codex)


static func _mandate_names(f: Faction) -> String:
	var names := []
	for mid in f.mandates:
		names.append(RulerRules.mandate_name(mid))
	return "none" if names.is_empty() else ", ".join(names)


static func _link(control: Control, breakdown: Dictionary, request_codex: Callable) -> void:
	CodexLink.attach(control, String(breakdown.get("codex", "")), request_codex)


static func _province_name(state: GameState, pid: String) -> String:
	var p := state.find_province(pid)
	return p.name if p else "the capital"


## A line of text in the side panel's style (MapScreen._add_text): wraps, and takes the mouse when it
## has a tooltip so the tooltip shows.
static func _text(parent: Control, text: String, tooltip: String, color: Color = UiPalette.TEXT_PRIMARY) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
