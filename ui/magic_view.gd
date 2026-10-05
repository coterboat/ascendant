class_name MagicView
## The words and numbers of the research panel's Magic tab (M5-5, #116; design/M5_MAGIC_FOG.md §4, §5.1, §11.2): the
## arcana as two school columns of four cards, each school's mastery for your casters, and the battle spellbook. A UI
## model only, like PathView: pure static functions over a GameState that read AscensionRules, MagicRules, Forecast
## and Breakdown and do no rules math of their own, so every number on screen is the number the rules use. Builds no
## nodes, so it is tested headless. Own faction only: a faction's arcana target and spellbook are its own.
##
##   columns(state, fid, orders)          [{"school", "title", "codex", "flavour", "mastery": [line], "cards": [card]}]
##   card(state, fid, nid, orders)        PathView.card, with the arcana's own hover: the spell with your numbers now,
##                                        who casts it, its price, or what a mastery node changes for each caster
##   spellbook(state, fid, orders)        the battle spellbook now (a queued SpellbookOrder, or the faction's)
##   spellbook_rows(state, fid, orders)   one row per battle spell, in order: on or off, known or not, and why
##   moved(book, spell, step), toggled(book, spell, on)   the spellbook after a change, for a SpellbookOrder
##   casters_text(state, fid)             who casts for the faction, and the mage gate
##   preview_note()                       what this build of the preview does with spells (honest about it)
##
## Magic is a preview still being built (M5-5): spells are researched, mages recruited and the spellbook set, but
## battle spells and rituals take effect only in later builds (M5-6, M5-7). preview_note() says so wherever it matters.

const PREVIEW_NOTE := "Magic is a preview still being built: battle spells and rituals don't take effect yet. You can research spells, recruit mages and set your spellbook now; it is kept, and used once battle spells arrive."


## The school columns of `fid`'s arcana, in MagicData.FACTION_SCHOOLS order, each with its four cards in data order
## (tier I, tier II, mastery, tier III) and its mastery for each kind of caster.
static func columns(state: GameState, fid: String, orders: Array = []) -> Array:
	var out := []
	for school in MagicRules.schools(fid):
		var sd := MagicRules.school_data(school)
		var col := {"school": school, "title": String(sd.name), "codex": String(sd.codex), "flavour": String(sd.flavour),
			"mastery": mastery_lines(state, fid, school, orders), "cards": []}
		for nid in sd.nodes:
			col.cards.append(card(state, fid, String(nid), orders))
		out.append(col)
	return out


## One arcana card: PathView.card (state, reason, cost, ETA, the button), with `detail` (the hover) rewritten for magic.
static func card(state: GameState, fid: String, nid: String, orders: Array = []) -> Dictionary:
	var c := PathView.card(state, fid, nid, orders, true)
	var view := PathView.view_state(state, fid, orders)
	var lines := PackedStringArray()
	lines.append(String(AscensionRules.node_data(nid).get("text", "")))
	var school := String(AscensionRules.node_data(nid).get("school", ""))
	if String(AscensionRules.node_data(nid).get("kind", "")) == MagicData.MASTERY_KIND:
		lines.append(_mastery_change(view, fid, school, nid))
	else:
		var sp := MagicRules.spell_data(nid)
		lines.append(String(sp.get("text", "")))
		var numbers := spell_numbers_text(view, fid, nid)
		if not numbers.is_empty():
			lines.append(numbers)
		lines.append(who_casts_text(view, fid, nid))
	if not String(c.reason).is_empty() and String(c.state) != AscensionRules.AVAILABLE:
		lines.append(String(c.reason))
	lines.append(PREVIEW_NOTE)
	c.detail = "\n\n".join(lines)
	return c


## Each kind of caster's mastery in `school`: [{"text": "Your mages +0", "breakdown"}, {"text": "The Ever-Regent +1",
## ...}]. A ruler is listed only when the school is one of its own.
static func mastery_lines(state: GameState, fid: String, school: String, orders: Array = []) -> Array:
	var view := PathView.view_state(state, fid, orders)
	var out := []
	var mage := MagicRules.mastery_bonus(view, fid, school, MagicRules.MAGE)
	out.append({"text": "Your mages %s" % _signed(int(mage.value)), "breakdown": Breakdown.mastery(view, fid, school, MagicRules.MAGE)})
	var f := view.find_faction(fid)
	if f != null and f.has_ruler() and MagicRules.ruler_magic(f.ruler_type).get("schools", []).has(school):
		var ruler := MagicRules.mastery_bonus(view, fid, school, MagicRules.RULER)
		out.append({"text": "%s %s%s" % [Serial.cap(RulerRules.current_name(view, fid)), _signed(int(ruler.value)), " (capped)" if ruler.capped else ""],
			"breakdown": Breakdown.mastery(view, fid, school, MagicRules.RULER)})
	return out


## A spell's main number for each kind of caster, with mastery now: "With your mastery now: your mages 4 damage; the
## Ever-Regent 5 damage." "" for a spell whose number mastery never changes (the greater workings, Far Sight).
static func spell_numbers_text(state: GameState, fid: String, spell_id: String) -> String:
	var sp := MagicRules.spell_data(spell_id)
	var per: Dictionary = sp.get("per_bonus", {})
	if per.is_empty():
		return ""
	var bits := []
	var mage := Breakdown.spell_number(state, fid, spell_id, MagicRules.MAGE)
	bits.append("your mages %s" % _number_words(mage))
	var f := state.find_faction(fid)
	if f != null and f.has_ruler() and MagicRules.ruler_magic(f.ruler_type).get("schools", []).has(String(sp.school)):
		var ruler := Breakdown.spell_number(state, fid, spell_id, MagicRules.RULER)
		bits.append("%s %s" % [RulerRules.current_name(state, fid), _number_words(ruler)])
	return "With your mastery now: %s." % "; ".join(bits)


## Who casts `spell_id` for `fid`, in one sentence: battle spells in battle, rituals with a cast order and their price.
static func who_casts_text(state: GameState, fid: String, spell_id: String) -> String:
	var mage := String(MagicRules.mage_data(fid).get("name", "your mages"))
	var f := state.find_faction(fid)
	var rm := MagicRules.ruler_magic(f.ruler_type) if f != null and f.has_ruler() else {}
	var ruler := RulerRules.current_name(state, fid) if f != null and f.has_ruler() else ""
	var school := String(MagicRules.spell_data(spell_id).get("school", ""))
	if MagicRules.is_battle_spell(spell_id):
		var who := "your %s" % mage
		if rm.get("battle", false) == true and rm.get("schools", []).has(school):
			who += " and %s" % ruler
		return "Cast in battle by %s, each round, in your spellbook's order. Spells never roll: they always land." % who
	var price := MagicRules.price(state, fid, spell_id, 0)
	var casters := "your %s" % mage
	if rm.get("schools", []).has(school):
		casters += " or %s" % ruler
	var cost := "%d gold a wolf" % int(MagicRules.spell_data(spell_id).cost) if String(MagicRules.spell_data(spell_id).get("summon", "")) == "thornwolves" \
		else "%d gold" % int(price.gold)
	return "Cast on the map with a cast order by %s, for %s. The casting army holds that turn." % [casters, cost]


## What a mastery node changes for each of `fid`'s casters: "Your mages: +0 → +1 in the Sun (Sunlance 4 → 5 damage).
## The Ever-Regent: already at the +3 cap, no change."
static func _mastery_change(state: GameState, fid: String, school: String, nid: String) -> String:
	var after := AscensionRules.with_nodes(state, fid, [nid]) if not AscensionRules.has_node(state, fid, nid) else state
	var bits := []
	var kinds := [MagicRules.MAGE]
	var f := state.find_faction(fid)
	if f != null and f.has_ruler() and MagicRules.ruler_magic(f.ruler_type).get("schools", []).has(school):
		kinds.append(MagicRules.RULER)
	var spell := String(MagicRules.school_data(school).nodes[0])
	for kind in kinds:
		var who := "Your mages" if kind == MagicRules.MAGE else Serial.cap(RulerRules.current_name(state, fid))
		var was := MagicRules.mastery_bonus(state, fid, school, kind)
		var now := MagicRules.mastery_bonus(after if after != null else state, fid, school, kind)
		if int(now.value) == int(was.value):
			bits.append("%s: already at the %s cap, no change." % [who, _signed(int(MagicData.MASTERY.cap))])
		else:
			var a := Breakdown.spell_number(state, fid, spell, kind)
			var b := Breakdown.spell_number(after, fid, spell, kind)
			bits.append("%s: %s → %s in %s (%s %d → %d)." % [who, _signed(int(was.value)), _signed(int(now.value)),
				MagicRules.school_ref(school), MagicRules.spell_name(spell), int(a.total), int(b.total)])
	return " ".join(bits)


# --- the battle spellbook (§5.1) ------------------------------------------------------------------------

## The spellbook as it stands this turn: the queued SpellbookOrder's, or the faction's ({"order", "off"}).
static func spellbook(state: GameState, fid: String, orders: Array = []) -> Dictionary:
	for i in range(orders.size() - 1, -1, -1):
		if orders[i] is SpellbookOrder:
			return {"order": orders[i].order.duplicate(), "off": orders[i].off.duplicate()}
	return MagicRules.spellbook(state, fid)


## One row per battle spell, in the spellbook's order: {"spell", "name", "on", "known", "status", "tooltip", "codex",
## "first", "last"}. "status" says whether your casters can cast it now: known, the Ever-Regent's own, or what to
## research.
static func spellbook_rows(state: GameState, fid: String, orders: Array = []) -> Array:
	var book := spellbook(state, fid, orders)
	var view := PathView.view_state(state, fid, orders)
	var f := view.find_faction(fid)
	var own := String(MagicRules.ruler_magic(f.ruler_type).get("own_spell", "")) if f != null and f.has_ruler() else ""
	var out := []
	var order: Array = book.order
	for i in order.size():
		var sid := String(order[i])
		var known := MagicRules.knows(view, fid, sid)
		var status := "known"
		if not known and sid == own:
			status = "%s: always known" % Serial.cap(RulerRules.current_name(view, fid))
		elif not known:
			var st := AscensionRules.node_state(view, fid, sid)
			status = "closed" if String(st.state) == AscensionRules.CLOSED else "not researched (%d research)" % AscensionRules.node_cost(sid)
		var on: bool = not book.off.has(sid)
		var tip := "%s\n\n%s\n\n%s" % [String(MagicRules.spell_data(sid).text), who_casts_text(view, fid, sid),
			"On: your casters try it in this place each round." if on else "Off: your casters never cast it."]
		out.append({"spell": sid, "name": MagicRules.spell_name(sid), "on": on, "known": known or sid == own, "status": status,
			"tooltip": tip, "codex": String(MagicRules.spell_data(sid).codex), "first": i == 0, "last": i == order.size() - 1})
	return out


## The spellbook after moving `spell` one place up (step -1) or down (+1): {"order", "off"}. Unchanged at an end.
static func moved(book: Dictionary, spell: String, step: int) -> Dictionary:
	var order: Array = book.order.duplicate()
	var i := order.find(spell)
	var j := i + step
	if i < 0 or j < 0 or j >= order.size():
		return {"order": order, "off": book.off.duplicate()}
	order[i] = order[j]
	order[j] = spell
	return {"order": order, "off": book.off.duplicate()}


## The spellbook with `spell` switched on or off: {"order", "off"}.
static func toggled(book: Dictionary, spell: String, on: bool) -> Dictionary:
	var off: Array = book.off.duplicate()
	if on:
		off.erase(spell)
	elif not off.has(spell):
		off.append(spell)
	return {"order": book.order.duplicate(), "off": off}


## Who casts for `fid`, and the mage gate: "Your casters: Sunstone Adepts (recruit them at your capital once you know
## a spell: research Sunlance or Shield of Law) and the Ever-Regent (Sunlance from turn 1)."
static func casters_text(state: GameState, fid: String) -> String:
	var mage := String(MagicRules.mage_data(fid).get("name", ""))
	var parts := []
	if MagicRules.knows_a_spell(state, fid):
		parts.append("%s (recruit them at your capital)" % mage)
	else:
		var firsts := []
		for school in MagicRules.schools(fid):
			firsts.append(MagicRules.spell_name(String(MagicRules.school_data(school).nodes[0])))
		parts.append("%s (on your roster; recruitable once you know a spell: research %s)" % [mage, MagicRules._or_list(firsts)])
	var f := state.find_faction(fid)
	if f != null and f.has_ruler():
		var rm := MagicRules.ruler_magic(f.ruler_type)
		var name := RulerRules.current_name(state, fid)
		if rm.get("schools", []).is_empty():
			parts.append("%s casts nothing: an ordinary man" % name)
		else:
			parts.append("%s: %s" % [name, String(rm.line).trim_suffix(".")])
	return "Your casters: %s." % "; ".join(parts)


static func preview_note() -> String:
	return PREVIEW_NOTE


static func _number_words(b: Dictionary) -> String:
	var label := String(b.total_label)
	var unit := label.get_slice("(", 1).trim_suffix(")") if label.contains("(") else ""
	if unit == "most wolves":
		return "up to %d wolves" % int(b.total)
	return "%d %s" % [int(b.total), unit] if not unit.is_empty() else str(int(b.total))


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)
