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
##
## M5-8 (#119) on screen: every card says what researching it first costs your transformation (Forecast.arcana_delay), what a
## hex or shield is worth against a typical foe (Forecast.spell_worth) and what your mages would cast once it is known, from the
## real cast step (Forecast.spell_outlook); Shield of Law's card starts with its field-spell line; a tier III card names what it
## still needs, the Oath included. The spellbook is previewed per army from the real cast step (spellbook_preview), an army
## panel names its casters' spells with their numbers (army_line), a mage's card lists the spellbook in order (mage_card), a
## recruit says when the second rank would be exposed (recruit_note) and the lock-in preview gets a magic row (lock_in_row).
##
##   spellbook_preview(state, fid, orders)   [{"title", "lines", "tooltip", "province"}] for each province with casters
##   army_line(state, army)                  "Casters: 2 Sunstone Adepts. Sunlance 4 damage, Shield of Law 6 units (mastery +0)."
##   mage_card(state, fid)                   the lines of a mage's card: casts instead of attacking, the spellbook in order
##   recruit_note(state, fid, type, at, orders)  the second-rank warning for a recruit, or ""
##   lock_in_row(state, fid, nid, orders)    the lock-in preview's magic row for the side `nid` is on

## Shield of Law's card starts with this (§11.2): the spell does nothing for a defender behind walls, woods or hills.
const FIELD_LINE := "Field spell: never on units that already have a terrain or fort bonus. It does nothing for defenders in a fort, forest or hills; it helps when you attack and on open plains."


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


## One arcana card: PathView.card (state, reason, cost, ETA, the button), with `detail` (the hover) rewritten for magic, and
## (M5-8) "delay" (Forecast.arcana_delay) with "delay_line" for the card's face, and, for a tier III card in need of more than
## one thing, a state line that names them all.
static func card(state: GameState, fid: String, nid: String, orders: Array = []) -> Dictionary:
	var c := PathView.card(state, fid, nid, orders, true)
	var view := PathView.view_state(state, fid, orders)
	var lines := PackedStringArray()
	lines.append(String(AscensionRules.node_data(nid).get("text", "")))
	var school := String(AscensionRules.node_data(nid).get("school", ""))
	var delay := Forecast.arcana_delay(state, fid, nid, orders)
	c["delay"] = delay
	c["delay_line"] = delay_line(delay) if String(c.state) != AscensionRules.RESEARCHING or bool(c.queued) else ""
	if String(AscensionRules.node_data(nid).get("kind", "")) == MagicData.MASTERY_KIND:
		lines.append(_mastery_change(view, fid, school, nid))
	else:
		var sp := MagicRules.spell_data(nid)
		lines.append(String(sp.get("text", "")))
		if String(sp.get("kind", "")) == "shield":
			lines.insert(0, FIELD_LINE)
		var numbers := spell_numbers_text(view, fid, nid)
		if not numbers.is_empty():
			lines.append(numbers)
		var worth := Forecast.spell_worth(view, fid, nid)
		if bool(worth.ok):
			lines.append(String(worth.text))
			c["worth"] = worth
		var outlook := Forecast.spell_outlook(state, fid, nid, orders)
		if bool(outlook.ok):
			lines.append(String(outlook.text))
		lines.append(who_casts_text(view, fid, nid))
	if String(c.state) == AscensionRules.NEEDS:
		var needs := needs_line(view, fid, nid)
		if not needs.is_empty():
			c.state_line = needs
			c.reason = needs_reason(view, fid, nid)
	if bool(delay.applies):
		lines.append(String(delay.text))
	if not String(c.reason).is_empty() and String(c.state) != AscensionRules.AVAILABLE:
		lines.append(String(c.reason))
	c.detail = "\n\n".join(lines)
	c["compact"] = true  # the research panel puts the kind on the name's line, so a school's four cards fit
	return c


## The card face's delay line (§4, §11.2): "Delays your transformation by about 2 turns (ETA turn 14 → 16)", or that it doesn't.
## "" when the card has none (researched, closed, or the road is walked).
static func delay_line(delay: Dictionary) -> String:
	if not bool(delay.get("applies", false)):
		return ""
	if int(delay.delay) > 0:
		return "Delays your transformation by about %s (ETA turn %d → %d)" % [TooltipText.count(int(delay.delay), "turn"), int(delay.before), int(delay.after)]
	return "Doesn't move your transformation (still turn %d)" % int(delay.before)


## Why a card can't be researched yet, with everything it needs and what each costs: "Sunburst needs Dawn Blessing (15
## research) and the Oath of the Dawn first. Only that Oath opens it: swearing the other closes it."
static func needs_reason(state: GameState, fid: String, nid: String) -> String:
	var parts := []
	var oath_note := ""
	for r in AscensionRules.node_data(nid).get("requires", []):
		var rid := String(r)
		if AscensionRules.has_node(state, fid, rid):
			continue
		if AscensionRules.is_oath(rid):
			parts.append(AscensionRules.node_ref(rid))
			oath_note = " Only that Oath opens %s: swearing the other Oath closes it for good." % AscensionRules.node_name(nid)
		else:
			parts.append("%s (%d research)" % [AscensionRules.node_name(rid), AscensionRules.node_cost(rid)])
	return "%s needs %s first.%s" % [AscensionRules.node_name(nid), MagicRules._and_list(parts), oath_note]


## What a card still needs, all at once ("Needs Dawn Blessing and the Oath of the Dawn"), or "" when nothing is missing. A tier
## III card also needs its school's aligned Oath, which the research rules count among its requirements.
static func needs_line(state: GameState, fid: String, nid: String) -> String:
	var missing := []
	for r in AscensionRules.node_data(nid).get("requires", []):
		if not AscensionRules.has_node(state, fid, String(r)):
			missing.append(AscensionRules.node_ref(String(r)) if AscensionRules.is_oath(String(r)) else AscensionRules.node_name(String(r)))
	if missing.is_empty():
		return ""
	return "Needs %s" % MagicRules._and_list(missing)


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
	bits.append("your mages %s" % number_words(mage))
	var f := state.find_faction(fid)
	if f != null and f.has_ruler() and MagicRules.ruler_magic(f.ruler_type).get("schools", []).has(String(sp.school)):
		var ruler := Breakdown.spell_number(state, fid, spell_id, MagicRules.RULER)
		bits.append("%s %s" % [RulerRules.current_name(state, fid), number_words(ruler)])
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
		parts.append("%s (recruit at your capital)" % mage)
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
			var refs: Array = rm.schools.map(func(sc): return MagicRules.school_ref(String(sc)))
			parts.append("%s (%s%s)" % [name, "casts in battle and " if rm.get("battle", false) == true else "casts ", "the rituals of %s" % MagicRules._and_list(refs)])
	return "Your casters: %s." % "; ".join(parts)


static func number_words(b: Dictionary) -> String:
	var label := String(b.total_label)
	var unit := label.get_slice("(", 1).trim_suffix(")") if label.contains("(") else ""
	if unit == "most wolves":
		return "up to %d wolves" % int(b.total)
	return "%d %s" % [int(b.total), unit] if not unit.is_empty() else str(int(b.total))


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


# --- the battle spellbook, previewed per army (§5.1, §11.2) --------------------------------------------------------

## One row for each province where an army of yours holds a caster that casts in battle: {"province", "title" ("Highcrag: the
## Ever-Regent and 2 Sunstone Adepts"), "lines" (In the open: ...; Defending ...: ...), "tooltip" (why each cast is what it
## is, from the resolver's own reasons), "preview" (Forecast.spellbook_preview's row)}. The real cast step, with your queued
## spellbook: what the preview says is what the battle's cast step does with those armies against that force.
static func spellbook_preview(state: GameState, fid: String, orders: Array = []) -> Array:
	var out := []
	for row in Forecast.spellbook_preview(state, fid, orders):
		var rival := Forecast.rival_of(state, fid)
		var tip := PackedStringArray()
		tip.append("Previewed by fighting the real cast step in round 1 against a typical force of %s (%d each of %d of its unit types). Spells never roll, so this is what these casters will cast: the first useful spell in your spellbook that nobody on their side has cast yet, as the battle's own rule picks it." % [
			TurnReportText.faction_short(state, rival), Forecast.STAND_IN_EACH, Forecast.STAND_IN_TYPES])
		for key in ["open", "defend"]:
			var r: Dictionary = row[key]
			if r.is_empty():
				continue
			tip.append("")
			tip.append("In the open:" if key == "open" else "Defending %s:" % String(row.name))
			for c in r.casts:
				if String(c.faction) == fid:
					tip.append("%s casts %s: %s." % [Serial.cap(Forecast._one_of(String(c.caster), bool(c.ruler))), String(c.name), String(c.why)])
		out.append({"province": String(row.province), "title": String(row.title), "lines": row.lines, "tooltip": "\n".join(tip), "preview": row})
	return out


## An army of yours that holds casters, as its panel says it (§11.2: "Casters: 2 Sunstone Adepts. Sunlance 4 damage, Shield of
## Law 6 units (mastery +0)."): {"header" ("Casters: 2 Sunstone Adepts"), "spells": [{"spell", "text" ("Sunlance 4 damage"),
## "breakdown" (Breakdown.spell_number), "codex", "on"}], "text" (all in one line), "mastery_text"}. {} when the army holds no
## caster that casts in battle. A spell your spellbook switches off is listed as off; one nobody there can cast is left out.
static func army_line(state: GameState, army: Army) -> Dictionary:
	if army == null or not MagicRules.has_magic(state):
		return {}
	var fid := army.owner
	var battle := MagicRules.casters(state, army).filter(func(c): return c.battle == true)
	if battle.is_empty():
		return {}
	var names := {}
	var order := []
	for c in battle:
		var nm := String(c.name)
		if not names.has(nm):
			names[nm] = {"n": 0, "ruler": String(c.kind) == MagicRules.RULER}
			order.append(nm)
		names[nm].n += 1
	var who := []
	for nm in order:
		who.append(nm if names[nm].ruler else ("%d %s" % [names[nm].n, nm]))
	var book := MagicRules.spellbook(state, fid)
	var spells := []
	var top := 0
	for sid in book.order:
		var school := String(MagicRules.spell_data(sid).get("school", ""))
		var best_kind := ""
		var best := -1
		for c in battle:
			if not MagicRules.battle_spells(state, fid, String(c.kind)).has(sid):
				continue
			var bonus := int(MagicRules.mastery_bonus(state, fid, school, String(c.kind)).value)
			if bonus > best:
				best = bonus
				best_kind = String(c.kind)
		if best < 0:
			continue
		top = maxi(top, best)
		var on: bool = not book.off.has(sid)
		var n := MagicRules.spell_numbers(sid, best)
		var kind := String(MagicRules.spell_data(sid).kind)
		var number := "%d damage" % int(n.value) if kind == "bolt" else ("every front-rank fighter in round 1" if MagicRules.spell_data(sid).has("round") else "%d units" % int(n.count))
		var text := "%s %s" % [MagicRules.spell_name(sid), number] if on else "%s (off)" % MagicRules.spell_name(sid)
		if best > 0 and on:
			text += " (+%d)" % best
		spells.append({"spell": sid, "text": text, "on": on, "breakdown": Breakdown.spell_number(state, fid, sid, best_kind),
			"codex": MagicRules.spell_codex(sid)})
	var header := "Casters: %s" % MagicRules._and_list(who)
	var mastery := "(mastery +%d)" % top
	var bits := spells.map(func(s): return String(s.text))
	return {"header": header, "spells": spells, "mastery_text": mastery,
		"text": "%s.%s" % [header, " %s %s." % [", ".join(bits), mastery] if not bits.is_empty() else " No spell known yet: research one in the Magic tab."]}


# --- a mage's card and the second rank (§3.2, §11.2) -------------------------------------------------------------

## The lines a mage's card adds to the unit description (§11.2): the battle spellbook in the order your mages try it, one line
## each, with what each is now (known and its number, not researched and what it costs, off), then the rule in one line. "" in
## a game without magic.
static func mage_card(state: GameState, fid: String) -> String:
	if not MagicRules.has_magic(state):
		return ""
	var book := MagicRules.spellbook(state, fid)
	var lines := PackedStringArray()
	lines.append("Your battle spellbook, in the order your %s try it:" % String(MagicRules.mage_data(fid).get("name", "mages")))
	var i := 1
	for sid in book.order:
		var status := ""
		if book.off.has(sid):
			status = "switched off"
		elif MagicRules.knows(state, fid, sid):
			var kind := String(MagicRules.spell_data(sid).kind)
			var n := MagicRules.spell_numbers(sid, int(MagicRules.mastery_bonus(state, fid, String(MagicRules.spell_data(sid).school), MagicRules.MAGE).value))
			status = "known: %s" % ("%d damage" % int(n.value) if kind == "bolt" else ("every front-rank fighter in round 1" if MagicRules.spell_data(sid).has("round") else "%d units" % int(n.count)))
		else:
			var st := AscensionRules.node_state(state, fid, sid)
			status = "closed" if String(st.state) == AscensionRules.CLOSED else "not researched (%d research)" % AscensionRules.node_cost(sid)
		lines.append("%d. %s: %s" % [i, MagicRules.spell_name(sid), status])
		i += 1
	lines.append("Casts instead of attacking; fights from the second rank: safe while your front rank is at least as big; Fangthrowers and Seraphs can always reach it.")
	return "\n".join(lines)


## The second-rank warning for a recruit (§3.2, §11.2: "This army will have 8 second-rank and 6 front-rank fighters: its
## second rank is exposed"), or "": always for a mage (the counts), for any other second-rank unit only when the rank would be
## exposed. `at` and `orders` as Forecast.second_rank takes them.
static func recruit_note(state: GameState, fid: String, unit_type_id: String, at: String = "", orders: Array = []) -> String:
	if not MagicRules.has_magic(state):
		return ""
	var f := state.find_faction(fid)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f != null else null
	if ut == null or (not MagicRules.is_mage(ut) and ut.trait_id != AutoBattleResolver.VOLLEY):
		return ""
	var r := Forecast.second_rank(state, fid, unit_type_id, at, orders)
	if not bool(r.ok):
		return ""
	if bool(r.exposed) or MagicRules.is_mage(ut):
		return String(r.text)
	return ""


## The warning a recruit button shows in plain sight: the second-rank note of recruit_note, only when the rank would be
## exposed ("" otherwise).
static func recruit_warning(state: GameState, fid: String, unit_type_id: String, at: String = "", orders: Array = []) -> String:
	if not MagicRules.has_magic(state):
		return ""
	var f := state.find_faction(fid)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f != null else null
	if ut == null or (not MagicRules.is_mage(ut) and ut.trait_id != AutoBattleResolver.VOLLEY):
		return ""  # a front-rank recruit joins the rank that shields the second: it never exposes it
	var r := Forecast.second_rank(state, fid, unit_type_id, at, orders)
	return String(r.text) if bool(r.ok) and bool(r.exposed) else ""


## The casters an army holds, as a phrase: "your 2 Sunstone Adepts", "the Ever-Regent", "your Thornmane Shamans and the Ninth Fang"
## (each kind once, with its count: never "your Sunstone Adepts and your Sunstone Adepts").
static func casters_phrase(state: GameState, army: Army) -> String:
	var counts := {}
	var listed := []
	for c in MagicRules.casters(state, army):
		var nm := MagicRules.caster_name(c)
		if not counts.has(nm):
			counts[nm] = 0
			listed.append(nm)
		counts[nm] += 1
	var bits := listed.map(func(nm): return nm if int(counts[nm]) == 1 else "your %d %s" % [int(counts[nm]), String(nm).trim_prefix("your ")])
	return MagicRules._and_list(bits)


# --- the HUD chip (M5-8) ---------------------------------------------------------------------------------------------

## The top bar's Magic chip: {"text" (two short lines: "Magic: 3 spells" and "2 mages · 1 cast ordered"), "breakdown" (one line for
## each spell your realm can cast), "tooltip" (casters, queued casts, the gold they leave, a global ritual in play, what a click does),
## "attention" (nothing to cast yet: the chip draws the eye to the Magic tab), "codex"}. Your own faction only.
## UI-POLISH-1 (#239): it counts what the realm can cast, the ruler's own spells too: on turn 1 it said "no spell yet" while the
## Ever-Regent cast Sunlance in battle 1. Each line says who knows it ("researched" or "the Ever-Regent's own").
static func chip(state: GameState, fid: String, orders: Array = []) -> Dictionary:
	var view := PathView.view_state(state, fid, orders)
	var known := MagicRules.known_spells(view, fid)
	var lines := []
	for sid in known:
		var tier := String(MagicRules.spell_data(String(sid)).tier)
		lines.append({"label": MagicRules.spell_name(String(sid)), "value": 1,
			"note": ("researched: battle spell, tier %s" if MagicRules.is_battle_spell(String(sid)) else "researched: ritual, tier %s") % tier})
	var ruler_name := ""
	var ruler_own := []  # what the ruler casts that nobody researched: its own spell (Sunlance, from turn 1)
	if RulerRules.ruler_alive(view, fid):
		ruler_name = RulerRules.current_name(view, fid)
		for sid in MagicRules.battle_spells(view, fid, MagicRules.RULER):
			if not known.has(sid):
				ruler_own.append(sid)
				lines.append({"label": MagicRules.spell_name(String(sid)), "value": 1, "note": "%s's own: battle spell, from turn 1" % ruler_name})
	var ruler_casts := not ruler_name.is_empty() and not MagicRules.battle_spells(view, fid, MagicRules.RULER).is_empty()
	var mages := 0
	for a in view.armies:
		if a.owner == fid:
			for u in a.units:
				if MagicRules.is_mage(u.type):
					mages += 1
	var spells := known.size() + ruler_own.size()
	var casters := TooltipText.count(mages, "mage")
	if ruler_casts:
		casters = "ruler + %s" % casters if mages > 0 else "your ruler casts"
	var casts := MagicRules.pinned_armies(view, fid, orders).size()
	var text := "Magic: %s\n%s%s" % [TooltipText.count(spells, "spell") if spells > 0 else "no spell yet",
		casters, " · %s ordered" % TooltipText.count(casts, "cast") if casts > 0 else ""]
	var parts := PackedStringArray()
	parts.append(casters_text(view, fid))
	if casts > 0:
		parts.append("%s queued: each holds its army this turn. %s" % [TooltipText.count(casts, "ritual"), String(Forecast.cast_budget(state, fid, orders).text)])
	for e in view.enchantments:
		if String(e.kind) == "global":
			parts.append("%s (%s) is up through turn %d: in every battle %s fighters heal back %s of the damage they deal." % [
				MagicRules.spell_name(String(e.ritual)), MagicRules._faction_display(view, String(e.faction)), int(e.until_turn),
				"your" if String(e.faction) == fid else "its", MagicRules.moon_share_word()])
	parts.append("Click to open the Magic tab: your arcana, mastery and the battle spellbook.")
	var who := "Every spell and ritual your realm can cast: the ones you researched%s; the Magic tab has what is left." % (
		", and %s's own" % ruler_name if not ruler_own.is_empty() else "")
	if known.is_empty():
		who = ("%s casts %s, its own; you have researched no spell yet: research one in the Magic tab, and your mages can be recruited." % [
			RulerRules._cap(ruler_name), MagicRules._and_list(ruler_own.map(func(sid): return MagicRules.spell_name(String(sid))))]) if not ruler_own.is_empty() \
			else "You know no spell yet: research one in the Magic tab, and your mages can be recruited."
	var desc := "%s %s" % [who, RulesCodex.text("magic")]
	return {"text": text, "breakdown": {"title": "Your spells", "description": desc, "lines": lines, "total_label": "Spells your realm can cast",
		"total": spells, "codex": "magic"}, "tooltip": "\n\n".join(parts), "attention": spells == 0, "codex": "magic"}


# --- the lock-in preview's magic row (§8.5) -----------------------------------------------------------------------

## What the side of the fork `p` previews (PathView.preview's result) does for magic, as two lines for the lock-in dialog:
## {"gain": {"text", "breakdown", "tooltip", "codex"} or {}, "lose": {... "strike": true} or {}}. The gain says what the Oath
## opens (its school's greater working) and what the transformation's +1 mastery changes for your casters ("Opens Sunburst
## (Sun, greater working). Sunlance: Adepts 4 → 5, the Ever-Regent 5 → 6. Dawn Blessing heals 16 a turn instead of 12."); the
## lose is the other side's greater working, struck through. Nothing in a game without magic.
static func lock_in_rows(p: Dictionary, fid: String) -> Dictionary:
	var out := {"gain": {}, "lose": {}}
	if not bool(p.get("ok", false)):
		return out
	var before: GameState = p.before
	var after: GameState = p.after
	if not MagicRules.has_magic(before):
		return out
	var side := String(p.branch)
	var school := _aligned_school(fid, side)
	if school.is_empty():
		return out
	var sd := MagicRules.school_data(school)
	var bits := []
	if String(p.mode) == "oath":
		var greater := String(sd.nodes[3])
		bits.append("Opens %s (%s, greater working)." % [MagicRules.spell_name(greater), MagicRules.school_name(school)])
	var ruler_kind := _ruler_casts(before, fid, school)
	for sid in sd.nodes:
		var sp := MagicRules.spell_data(String(sid))
		if sp.is_empty() or String(sp.get("kind", "")) == "":
			continue
		var per: Dictionary = sp.get("per_bonus", {})
		if per.is_empty():
			continue
		var words := _change_words(before, after, fid, String(sid), ruler_kind)
		if not words.is_empty():
			bits.append(words)
	if bits.is_empty():
		return out
	var texts := []
	for b in bits:
		texts.append(String(b))
	out.gain = {"text": " ".join(texts), "breakdown": Breakdown.mastery(after, fid, school, MagicRules.MAGE), "tooltip": "",
		"codex": String(sd.codex), "rule": false}
	if String(p.mode) == "oath":
		var other_school := _aligned_school(fid, String(p.other))
		if not other_school.is_empty():
			var closed := String(MagicRules.school_data(other_school).nodes[3])
			out.lose = {"text": "%s, the greater working of %s." % [MagicRules.spell_name(closed), MagicRules.school_ref(other_school)],
				"breakdown": {}, "tooltip": TooltipText.plain("Closed for good", "%s %s" % [String(MagicRules.spell_data(closed).get("text", "")),
					RulesCodex.text("greater_working")]), "codex": "greater_working", "strike": true, "rule": true}
	return out


## The school of `fid` whose aligned side of the fork is `side` ("" when none).
static func _aligned_school(fid: String, side: String) -> String:
	for sc in MagicRules.schools(fid):
		if String(MagicRules.school_data(sc).get("aligned_branch", "")) == side:
			return String(sc)
	return ""


## Whether `fid`'s ruler casts `school` (so its own mastery changes show): the ruler kind, or "".
static func _ruler_casts(state: GameState, fid: String, school: String) -> String:
	var f := state.find_faction(fid)
	if f != null and f.has_ruler() and MagicRules.ruler_magic(f.ruler_type).get("schools", []).has(school):
		return MagicRules.RULER
	return ""


## What the mastery the transformation adds changes in `spell_id`'s number, for your mages and (bolts) your ruler:
## "Sunlance: Adepts 4 → 5, the Ever-Regent 5 → 6.", "Dawn Blessing heals 16 a turn instead of 12.", or "" when nothing changes.
static func _change_words(before: GameState, after: GameState, fid: String, spell_id: String, ruler_kind: String) -> String:
	var sp := MagicRules.spell_data(spell_id)
	var school := String(sp.school)
	var kind := String(sp.kind)
	var mage_was := MagicRules.spell_numbers(spell_id, int(MagicRules.mastery_bonus(before, fid, school, MagicRules.MAGE).value))
	var mage_now := MagicRules.spell_numbers(spell_id, int(MagicRules.mastery_bonus(after, fid, school, MagicRules.MAGE).value))
	var field := "value"
	for key in ["value", "count", "duration"]:
		if sp.get("per_bonus", {}).has(key):
			field = key
	var name := MagicRules.spell_name(spell_id)
	if kind == "bolt":
		var mage_name := String(MagicRules.mage_data(fid).get("name", "your mages")).get_slice(" ", 1)
		var bits := []
		if int(mage_was[field]) != int(mage_now[field]):
			bits.append("%s %d → %d" % [mage_name, int(mage_was[field]), int(mage_now[field])])
		if not ruler_kind.is_empty() and MagicRules.battle_spells(after, fid, MagicRules.RULER).has(spell_id):
			var rw := MagicRules.spell_numbers(spell_id, int(MagicRules.mastery_bonus(before, fid, school, MagicRules.RULER).value))
			var rn := MagicRules.spell_numbers(spell_id, int(MagicRules.mastery_bonus(after, fid, school, MagicRules.RULER).value))
			if int(rw[field]) != int(rn[field]):
				bits.append("%s %d → %d" % [RulerRules.current_name(after, fid), int(rw[field]), int(rn[field])])
		return "%s: %s." % [name, ", ".join(bits)] if not bits.is_empty() else ""
	if int(mage_was[field]) == int(mage_now[field]):
		return ""
	match kind:
		"hex", "shield":
			return "%s covers %d units instead of %d." % [name, int(mage_now.count), int(mage_was.count)]
		"blessing":
			return "%s heals %d a turn instead of %d." % [name, int(mage_now.value), int(mage_was.value)]
		"curse":
			return "%s takes %d a turn instead of %d." % [name, int(mage_now.value), int(mage_was.value)]
		"ward":
			return "%s lasts %d turns instead of %d." % [name, int(mage_now.duration) + 1, int(mage_was.duration) + 1]
		"summon":
			return "%s calls up to %d wolves instead of %d." % [name, int(mage_now.count), int(mage_was.count)]
	return ""
