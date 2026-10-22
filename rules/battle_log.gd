class_name BattleLog
## The battle event log (M3-1, #56; design/M3_BATTLES.md §2). Pure rules code: no nodes, no scenes.
##
## AutoBattleResolver.fight(sides, ctx, rng, record = true) writes the log while it fights, from the same
## values it uses (see the resolver's _log_* functions); TurnResolver._fight gives it its id, turn and
## index, adds the "aftermath" event and keeps it in the battle event's numbers.log, beside
## numbers.report. GameSession keeps only the last resolved turn's events, so logs live in memory with
## the last turn's report and are never in record() or history(): any older battle's log is rebuilt
## from the game record and the seed with regenerate().
##
## The log is a JSON-safe Dictionary (schema version VERSION, §2.2). 64-bit values (the RNG seed and
## states) are strings. Fighters and sides are integer ids into the log's own "fighters" and "sides".
##   {"v", "id": "t<turn>b<index>", "turn", "index", "kind": "province" | "border", "provinces",
##    "terrain", "fort", "defender", "round_cap", "rng": {"seed", "before", "after"},
##    "sides": [SIDE], "fighters": [FIGHTER], "events": [EVENT], "truncated"}
## Events, in the exact order the resolver did things (every one but end, feast and aftermath has "n",
## its round): round, attack, wound, death, morale, rout, destroyed, round_end, end, feast, aftermath.
## Within a round: round, every attack, the wounds and deaths, the morale checks, rout or destroyed,
## round_end. design/M3_BATTLES.md §2.2 lists every field.
##
## Functions:
##   validate(log)            plain-language reasons the log is malformed or inconsistent ([] when fine)
##   verify_draws(log)        re-draws every recorded roll from rng.before; [] when every roll and the
##                            final state rng.after match, otherwise plain-language reasons
##   cross_check(log, report) design/M3_BATTLES.md §2.5's cross-checks between a log and its report
##   regenerate(record, turn, index) -> {"log", "report", "errors"}: rebuilds a battle from a game record
##   to_json(log) / from_json(text) -> {"log", "errors"}: exact round trip (numbers come back as ints,
##                            except the "expected" and "impact" values, which are floats)
##   final_hp(log)            each fighter's hp after every event
##   without_logs(events)     a deep copy of turn report events with every numbers.log removed
## MAX_EVENTS caps a log: past it recording stops and the log gets "truncated": true, while the battle
## is fought to the end as usual (recording is passive). No measured battle comes near it.
##
## Paths (M4-3, #68; design/M4_ASCENSION.md §9.6). A battle in a game with paths, or with a path trait on
## the field, writes "paths": true at the top level and these additions to the same version-1 schema (every
## other log is exactly M3-1's, byte for byte, so M1-M3 fixtures and records never change):
##   side       "people" ({"id", "name"} or {}), "base_morale_parts" ({path part key: what it added to
##              base_morale}), "dread_lands" (morale every enemy side loses here), "red_harvest" (gold per
##              enemy fighter lost when this side wins)
##   round      each reach entry gains "wings_tiers": the ranks Wings can reach on that side (its commanders
##              while one stands, otherwise every rank). Wings goes only for commanders while any enemy
##              side has one standing.
##   attack     "reach" can be "wings" (only Wings could reach the target); "bonus" can hold "Iron Hide"
##              (a negative damage part); attack and defense parts can hold "path_<node>" and "Rooted"
##   heal       {n, f, from, to, dealt, trait}: Lifedrinker healing a fighter at the end of round n, after
##              the wounds and deaths and before the morale checks ("dealt": the damage its hits dealt
##              that round). Playback shows it as a green number.
##   harvest    {side, fighters, gold}: Red Harvest's gold after the battle (after feast, before aftermath)
## A reader that folds hp must apply heal events (final_hp and BattleTimeline do).
##
## Forts and sieges (M3c S-2, #100; design/M3C_SIEGES.md §4.4). A battle at a fort in a game with sieges writes a
## "siege" block at the top level, in the same version-1 schema (every other log is unchanged, byte for byte):
##   siege      {"kind": "storm" | "open" | "breach", "why" (§3.9's last column: storm, sally, gate, relief,
##              relief_sally, rivals, empty, breach), "fort" (palisade, keep or citadel), "walls", "walls_max" (the
##              walls never change during a battle), "walls_defense" (the part each stormed garrison fighter gets:
##              2 x ceil(walls / 3) in a storm, 0 otherwise), "cover_defense" (2 for the from_inside fighters of a
##              sally or breach battle, 0 otherwise), "garrison" (the fort owner's side index, -1 when the owner
##              has no side), "from_inside" (the owner's armies fighting from inside: stormed, sallying or breach
##              defenders; never a relief army), "turn_of_siege" (0 when there was no siege at the start of turn)}
##   attack     in a storm every attack on a fighter of a from_inside army carries defense part "walls"; in a sally
##              or breach battle it carries "cover". A siege battle never has the flat "fort" part.
##
## Battle spells (M5-7, #118; design/M5_MAGIC_FOG.md §5.4). A battle in a game with magic writes "magic": true at the
## top level and these additions to the same version-1 schema (every other log is unchanged, byte for byte):
##   side       "casters" (fighter ids of its mages and a ruler that casts), "spellbook" (its on spells, in order),
##              "enchantments" ([{"id", "ritual", "effect"}]: Dawn Blessing, the Blood Moon, a rival's curse in play)
##   fighter    "mastery" ({school: bonus}) for a caster; "summoned": true for a summoned creature
##   cast       {n, by, spell, school, kind ("bolt" | "hex" | "shield"), bonus, targets (fighter ids, in order),
##              value and resist (bolt: its damage with mastery, and a ruler's spell resistance), part ({"stat",
##              "value"}: hex and shield, for the round), damage (bolt: per target, after resistance; else 0), self
##              (Bloodbolt's bleed, else 0), why (plain words), skipped ([{"spell", "reason"}] when it passed over
##              spells that weren't useful)}. After the round event and before the round's attacks, one per cast.
##              Casts draw nothing. A caster that casts makes no attack that round.
##   attack     attack and defense parts can hold "spell_<id>" (Briar Snare, Sunburst; Shield of Law)
##   wound      "by" names the casters whose bolt hit it, and a bleeding caster itself; "bled": the hp it bled
##   morale     "bled": hp the side's own casters bled so far, which lost_pct leaves out
##   heal       "spell": "blood_moon" in place of "trait" when the moon's share was the one used
##   bleed_closed {side, closed: [[fighter, from, to]]}: after the end, before feast, the winner's bled hp come back

const VERSION := 1
## M3c: what a battle at a fort can be (the siege block's "kind"), and the "why" each kind allows (§3.9).
const SIEGE_WHYS := {"storm": ["storm"], "breach": ["breach"], "open": ["sally", "gate", "relief", "relief_sally", "rivals", "empty"]}
const SIEGE_FORTS := ["palisade", "keep", "citadel"]
const MAX_EVENTS := 12000
const EVENT_TYPES := ["round", "attack", "wound", "death", "morale", "rout", "destroyed", "round_end", "end", "feast", "aftermath",
	"heal", "harvest", "cast", "bleed_closed", "flare"]
## Events without a round number.
const UNROUNDED := ["end", "feast", "aftermath", "harvest", "bleed_closed"]
## M5-7: the battle spell kinds a cast event can have.
const CAST_KINDS := ["bolt", "hex", "shield"]
const ROLES := ["unit", "commander", "ruler"]
const REACH_WORDS := ["front", "second", "back", "skirmish", "wings"]
const MORALE_RESULTS := ["holds", "breaks", "held"]
const ENDS := ["rout", "destroyed", "mutual", "round_cap"]
const TIE_BREAKS := ["none", "defender", "roll"]
## Keys whose values are floats in a log (everything else numeric is an int): from_json restores them.
const FLOAT_KEYS := ["expected", "impact"]
## The report's "why" factors that are not measured in the resolver's impact accumulator (so they have no
## per-round worth in the log): morale and rout factors, the bigger force, luck and the round cap.
const NON_IMPACT_FACTORS := ["rout", "Fury", "ability_dread", "morale_commander", "morale_Inspire", "morale_ruler",
	"mandate_iron_discipline", "numbers", "luck", "round_cap", "dread_lands"]
## M4-3: path morale factors ("morale_path_<node>") are measured from the morale checks too.
const NON_IMPACT_PREFIXES := ["morale_"]
## At most this many reasons from validate() and cross_check(): the first ones say what is wrong.
const MAX_REASONS := 25


# --- building (the resolver and TurnResolver call these) ----------------------------------------------

## Appends `ev` unless the log already holds `cap` events: then recording stops and the log is marked
## "truncated". Returns true when the event was added.
static func append(battle_log: Dictionary, ev: Dictionary, cap: int = MAX_EVENTS) -> bool:
	if battle_log.get("truncated", false):
		return false
	if battle_log.events.size() >= cap:
		battle_log.truncated = true
		return false
	battle_log.events.append(ev)
	return true


## TurnResolver's part (§2.3): sets the log's id "t<turn>b<index>", turn (as players count turns) and
## index (0-based, in resolution order), and adds the aftermath event: the armies destroyed, the fighters
## still standing on a losing side (destroyed with their armies), every ruler fighter that dies from this
## battle (it fell, or was lost with its side: a ruler_died event follows for each) and the report's
## aftermath sentence.
static func attach(battle_log: Dictionary, turn: int, index: int, winner: String, destroyed_armies: Array, text: String) -> void:
	battle_log.id = "t%db%d" % [turn, index]
	battle_log.turn = turn
	battle_log.index = index
	var winner_side := -1
	for s in battle_log.sides:
		if s.faction == winner:
			winner_side = int(s.index)
	var hp := final_hp(battle_log)
	var lost := []
	var fallen := []
	for f in battle_log.fighters:
		var on_loser: bool = int(f.side) != winner_side
		if on_loser and hp[int(f.id)] > 0:
			lost.append(int(f.id))
		if f.role == "ruler" and (on_loser or hp[int(f.id)] == 0):
			fallen.append(int(f.id))
	append(battle_log, {"t": "aftermath", "destroyed_armies": destroyed_armies.duplicate(), "lost": lost, "fallen_rulers": fallen,
		"text": text})


# --- reading ------------------------------------------------------------------------------------------

## Each fighter's hp after every event of the log (wounds, Lifedrinker's heals, then Feast of Victory's
## healing), by fighter id.
static func final_hp(battle_log: Dictionary) -> Array:
	var hp := []
	for f in battle_log.fighters:
		hp.append(int(f.hp))
	for e in battle_log.events:
		if e.t == "wound" or e.t == "heal":
			hp[int(e.f)] = int(e.to)
		elif e.t == "feast":
			for h in e.healed:
				hp[int(h[0])] = int(h[2])
		elif e.t == "bleed_closed":
			for h in e.closed:
				hp[int(h[0])] = int(h[2])
	return hp


## Index of the first event of type `t`, or -1.
static func find_event(battle_log: Dictionary, t: String) -> int:
	var events: Array = battle_log.events
	for i in events.size():
		if events[i].t == t:
			return i
	return -1


## A deep copy of turn report `events` with the battle logs taken out of every numbers dictionary, for
## anything that stores a turn report (logs are regenerated, never saved: §2.4).
static func without_logs(events: Array) -> Array:
	var out := []
	for e in events:
		var copy = e.duplicate(true) if e is Dictionary else e
		if copy is Dictionary and copy.get("numbers") is Dictionary:
			copy.numbers.erase("log")
		out.append(copy)
	return out


# --- JSON ---------------------------------------------------------------------------------------------

## The log as compact JSON, keys in schema order. The same log always gives the same bytes.
static func to_json(battle_log: Dictionary) -> String:
	return JSON.stringify(battle_log, "", false)


## Reads a log written by to_json: {"log": Dictionary ({} when unreadable), "errors": plain reasons}.
## Numbers come back exactly as the resolver wrote them (ints, and floats for "expected" and "impact"),
## so from_json(to_json(log)).log == log.
static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	var parsed = json.data if json.parse(text) == OK else null  # parse() reports no engine error on bad text
	if not (parsed is Dictionary):
		return {"log": {}, "errors": ["This is not a battle log: it isn't readable JSON with named values at the top."]}
	var out = normalize(parsed)
	return {"log": out, "errors": validate(out)}


## `data` (parsed JSON) with whole-number floats turned back into ints, except the values under
## FLOAT_KEYS, which are all floats in a log.
static func normalize(data, floats := false):
	match typeof(data):
		TYPE_DICTIONARY:
			var out := {}
			for k in data:
				out[k] = normalize(data[k], floats or FLOAT_KEYS.has(String(k)))
			return out
		TYPE_ARRAY:
			var out := []
			for v in data:
				out.append(normalize(v, floats))
			return out
		TYPE_FLOAT:
			if floats:
				return data
			return int(data) if data == floorf(data) and absf(data) < 9.0e15 else data
		TYPE_INT:
			return float(data) if floats else data
	return data


# --- validate -----------------------------------------------------------------------------------------

## Plain-language reasons `battle_log` is not a well-formed, self-consistent version-1 log, [] when it
## is: the header's fields and types, every fighter and side reference, each event's fields, rounds in
## order, and each attack's arithmetic (its attack and defense values are their parts' sums, its chance
## and damage follow the battle rules, "hit" is roll <= chance, "expected" is chance x damage).
static func validate(battle_log) -> Array:
	var r := []
	if not (battle_log is Dictionary):
		return ["This is not a battle log: it should be a group of named values."]
	if int(_num(battle_log.get("v"), -1)) != VERSION:
		return ["This battle log has version %s; this game reads version %d." % [str(battle_log.get("v")), VERSION]]
	for key in ["id", "kind", "terrain", "defender"]:
		if not (battle_log.get(key) is String):
			_add(r, "The battle log's '%s' should be text." % key)
	for key in ["turn", "index", "round_cap"]:
		if not _is_int(battle_log.get(key)):
			_add(r, "The battle log's '%s' should be a whole number." % key)
	for key in ["fort", "truncated"]:
		if not (battle_log.get(key) is bool):
			_add(r, "The battle log's '%s' should be true or false." % key)
	for key in ["provinces", "sides", "fighters", "events"]:
		if not (battle_log.get(key) is Array):
			_add(r, "The battle log's '%s' should be a list." % key)
	if not r.is_empty():
		return r
	if not ["province", "border"].has(battle_log.kind):
		_add(r, "The battle log's kind is '%s'; it should be province or border." % battle_log.kind)
	var rng = battle_log.get("rng")
	if not (rng is Dictionary):
		_add(r, "The battle log has no random number state.")
	else:
		for key in ["seed", "before", "after"]:
			if not (rng.get(key) is String and String(rng.get(key)).is_valid_int()):
				_add(r, "The battle log's random number '%s' should be a whole number written as text." % key)
	var sides: Array = battle_log.sides
	var fighters: Array = battle_log.fighters
	var ns := sides.size()
	var nf := fighters.size()
	if ns < 2:
		_add(r, "A battle needs at least two sides; this log has %d." % ns)
	for i in nf:
		var f = fighters[i]
		if not (f is Dictionary):
			_add(r, "Fighter %d should be a group of named values." % i)
			continue
		if int(_num(f.get("id"), -1)) != i:
			_add(r, "Fighter %d has id %s; each fighter's id should be its place in the list." % [i, str(f.get("id"))])
		if not _in_range(f.get("side"), ns):
			_add(r, "Fighter %d is on side %s, but the log has %d sides." % [i, str(f.get("side")), ns])
		if not ROLES.has(f.get("role")):
			_add(r, "Fighter %d has role '%s'; it should be unit, commander or ruler." % [i, str(f.get("role"))])
		if not _in_range(f.get("tier"), 3):
			_add(r, "Fighter %d stands in rank %s; ranks are 0 (front), 1 (second) and 2 (back)." % [i, str(f.get("tier"))])
		for key in ["hp", "max_hp", "attack", "defense", "morale", "cost"]:
			if not _is_int(f.get(key)):
				_add(r, "Fighter %d's '%s' should be a whole number." % [i, key])
		for key in ["type", "name", "trait", "army"]:
			if not (f.get(key) is String):
				_add(r, "Fighter %d's '%s' should be text." % [i, key])
	for i in ns:
		var s = sides[i]
		if not (s is Dictionary):
			_add(r, "Side %d should be a group of named values." % i)
			continue
		if int(_num(s.get("index"), -1)) != i:
			_add(r, "Side %d has index %s; each side's index should be its place in the list." % [i, str(s.get("index"))])
		if not (s.get("fighters") is Array):
			_add(r, "Side %d's fighters should be a list." % i)
			continue
		for fid in s.fighters:
			if not _in_range(fid, nf):
				_add(r, "Side %d lists fighter %s, but the log has %d fighters." % [i, str(fid), nf])
			elif int(_num(fighters[int(fid)].get("side"), -1)) != i:
				_add(r, "Side %d lists fighter %d, but that fighter is on side %s." % [i, int(fid), str(fighters[int(fid)].get("side"))])
		for key in ["hp_start", "base_morale", "base_hit", "frenzy", "dread"]:
			if not _is_int(s.get(key)):
				_add(r, "Side %d's '%s' should be a whole number." % [i, key])
	if not r.is_empty():
		return r
	_validate_siege(r, battle_log)  # M3c: the siege block, when there is one
	var round_no := 0
	var cap := int(battle_log.round_cap)
	var events: Array = battle_log.events
	for i in events.size():
		var e = events[i]
		if not (e is Dictionary):
			_add(r, "Event %d should be a group of named values." % i)
			continue
		var t = e.get("t")
		if not EVENT_TYPES.has(t):
			_add(r, "Event %d has type '%s', which a battle log doesn't have." % [i, str(t)])
			continue
		var what := "Event %d (%s)" % [i, t]
		if not UNROUNDED.has(t):
			if not _is_int(e.get("n")) or int(e.n) < 1 or int(e.n) > cap:
				_add(r, "%s should have a round number from 1 to %d." % [what, cap])
				continue
			what = "Event %d (%s in round %d)" % [i, t, int(e.n)]
			if t == "round":
				if int(e.n) != round_no + 1:
					_add(r, "%s comes after round %d; rounds should go 1, 2, 3 and so on." % [what, round_no])
				round_no = int(e.n)
			elif int(e.n) != round_no:
				_add(r, "%s belongs to round %d, but it comes during round %d." % [what, int(e.n), round_no])
		match t:
			"round":
				for entry in e.get("reach", []):
					if not (entry is Dictionary) or not _in_range(entry.get("side"), ns) or not (entry.get("tiers") is Array) \
							or not (entry.get("skirmish_tiers") is Array):
						_add(r, "%s has a reach entry without a side and its tiers." % what)
			"attack":
				_validate_attack(r, what, e, nf)
			"wound":
				if not _in_range(e.get("f"), nf):
					_add(r, "%s names fighter %s, but the log has %d fighters." % [what, str(e.get("f")), nf])
				elif not _is_int(e.get("from")) or not _is_int(e.get("to")) or int(e.to) < 0 or int(e.to) >= int(e.from):
					_add(r, "%s should take hit points from a number down to a smaller one, not below 0." % what)
				if not (e.get("by") is Array) or e.by.is_empty():
					_add(r, "%s should name the fighters whose hits wounded it." % what)
			"death":
				if not _in_range(e.get("f"), nf):
					_add(r, "%s names fighter %s, but the log has %d fighters." % [what, str(e.get("f")), nf])
				elif i == 0 or events[i - 1].get("t") != "wound" or int(_num(events[i - 1].get("f"), -1)) != int(e.f) \
						or int(_num(events[i - 1].get("to"), -1)) != 0:
					_add(r, "%s should come right after the wound that took fighter %d to 0 hit points." % [what, int(e.f)])
			"morale":
				if not _in_range(e.get("side"), ns):
					_add(r, "%s names side %s, but the log has %d sides." % [what, str(e.get("side")), ns])
				elif not MORALE_RESULTS.has(e.get("result")):
					_add(r, "%s has result '%s'; it should be holds, breaks or held." % [what, str(e.get("result"))])
				elif not (e.get("parts") is Dictionary) or not _is_int(e.get("morale")) or not _is_int(e.get("base")):
					_add(r, "%s should have its morale, base and parts." % what)
				else:
					var total := int(e.base)
					for p in e.parts:
						total += int(e.parts[p])
					if total != int(e.morale):
						_add(r, "%s has morale %d, but its base and parts add up to %d." % [what, int(e.morale), total])
					if int(_num(e.get("break_pct"), -1)) != AutoBattleResolver.break_pct(int(e.morale)):
						_add(r, "%s breaks at %s%%, but morale %d breaks at %d%%." % [what, str(e.get("break_pct")), int(e.morale),
							AutoBattleResolver.break_pct(int(e.morale))])
					var breaks: bool = int(_num(e.get("lost_pct"), 0)) >= int(_num(e.get("break_pct"), 0))
					if breaks != (e.result != "holds"):
						_add(r, "%s says the side %s, but it lost %s%% and breaks at %s%%." % [what, e.result, str(e.get("lost_pct")),
							str(e.get("break_pct"))])
			"rout", "destroyed":
				if not _in_range(e.get("side"), ns):
					_add(r, "%s names side %s, but the log has %d sides." % [what, str(e.get("side")), ns])
				if t == "rout":
					for fid in e.get("fled", []):
						if not _in_range(fid, nf):
							_add(r, "%s lists fighter %s as fled, but the log has %d fighters." % [what, str(fid), nf])
			"round_end":
				for key in ["hp", "attacks", "hits", "dealt", "expected", "impact"]:
					if not (e.get(key) is Array) or e.get(key).size() != ns:
						_add(r, "%s should give '%s' for each of the %d sides." % [what, key, ns])
			"end":
				if not _in_range(e.get("winner"), ns):
					_add(r, "%s names side %s as the winner, but the log has %d sides." % [what, str(e.get("winner")), ns])
				if not ENDS.has(e.get("how")):
					_add(r, "%s ended by '%s'; it should be rout, destroyed, mutual or round_cap." % [what, str(e.get("how"))])
				if not TIE_BREAKS.has(e.get("tie_break")):
					_add(r, "%s has tie break '%s'; it should be none, defender or roll." % [what, str(e.get("tie_break"))])
				elif e.tie_break == "roll" and (not _is_int(e.get("tied")) or int(e.tied) < 2 or not _in_range(e.get("roll"), int(e.tied))):
					_add(r, "%s was decided by a roll, so it needs the number of tied sides and a roll below it." % what)
				if int(_num(e.get("rounds"), -1)) != round_no:
					_add(r, "%s says %s rounds were fought, but the log has %d." % [what, str(e.get("rounds")), round_no])
			"feast":
				if not _in_range(e.get("side"), ns):
					_add(r, "%s names side %s, but the log has %d sides." % [what, str(e.get("side")), ns])
				for h in e.get("healed", []):
					if not (h is Array) or h.size() != 3 or not _in_range(h[0], nf) or int(_num(h[2], 0)) <= int(_num(h[1], 0)):
						_add(r, "%s should list [fighter, hit points before, hit points after] for each fighter it healed." % what)
			"cast":
				_validate_cast(r, what, e, battle_log)
			"bleed_closed":
				if not _in_range(e.get("side"), ns):
					_add(r, "%s names side %s, but the log has %d sides." % [what, str(e.get("side")), ns])
				for h in e.get("closed", []):
					if not (h is Array) or h.size() != 3 or not _in_range(h[0], nf) or int(_num(h[2], 0)) <= int(_num(h[1], 0)) \
							or int(_num(h[2], 0)) > int(_num(fighters[int(h[0])].get("max_hp"), 0)):
						_add(r, "%s should list [fighter, hit points before, hit points after] for each caster whose bleeding closed." % what)
			"flare":
				# CW-2: a fallen Hundred-Wick's fire: sure damage to standing enemies of the front rank, then their wounds.
				if not _in_range(e.get("f"), nf):
					_add(r, "%s names fighter %s, but the log has %d fighters." % [what, str(e.get("f")), nf])
				if not (e.get("targets") is Array) or e.targets.is_empty() or e.targets.size() > AutoBattleResolver.FLARE_TARGETS \
						or not e.targets.all(func(x): return _in_range(x, nf)):
					_add(r, "%s should name 1 to %d fighters it burned." % [what, AutoBattleResolver.FLARE_TARGETS])
				if not _is_int(e.get("damage")) or int(_num(e.get("damage"), 0)) < 1:
					_add(r, "%s should say the damage each target took." % what)
			"heal":
				# M4-3: Lifedrinker (M5-7: or the Blood Moon, "spell"; CW-2: or Siphon). Up, never past the fighter's maximum.
				if not _in_range(e.get("f"), nf):
					_add(r, "%s names fighter %s, but the log has %d fighters." % [what, str(e.get("f")), nf])
				elif not _is_int(e.get("from")) or not _is_int(e.get("to")) or int(e.to) <= int(e.from) \
						or int(e.to) > int(_num(fighters[int(e.f)].get("max_hp"), 0)):
					_add(r, "%s should raise hit points from a number to a bigger one, no higher than the fighter's maximum." % what)
				if not _is_int(e.get("dealt")) or int(_num(e.get("dealt"), 0)) < 1:
					_add(r, "%s should say how much damage the fighter's hits dealt that round." % what)
			"harvest":
				if not _in_range(e.get("side"), ns):
					_add(r, "%s names side %s, but the log has %d sides." % [what, str(e.get("side")), ns])
				if not _is_int(e.get("fighters")) or not _is_int(e.get("gold")) or int(_num(e.get("gold"), -1)) < 0:
					_add(r, "%s should give the enemy fighters lost and the gold they paid." % what)
			"aftermath":
				for key in ["lost", "fallen_rulers"]:
					for fid in e.get(key, []):
						if not _in_range(fid, nf):
							_add(r, "%s lists fighter %s, but the log has %d fighters." % [what, str(fid), nf])
				if not (e.get("text") is String):
					_add(r, "%s should carry the report's aftermath sentence." % what)
	if not battle_log.truncated and find_event(battle_log, "end") < 0:
		_add(r, "The battle log has no end event, but it isn't marked as cut short.")
	if r.is_empty():
		_validate_siege_parts(r, battle_log)  # M3c: walls, cover and fort parts agree with the siege block
	return r


## M3c (§4.4): the siege block's fields and their agreement with the header: a storm has a garrison side that
## defends behind standing walls and gets 2 x ceil(walls / 3); open and breach battles have no defender and give
## cover exactly when armies fight from inside; the armies from inside are the garrison side's.
static func _validate_siege(r: Array, battle_log: Dictionary) -> void:
	if not battle_log.has("siege"):
		return
	var sg = battle_log.siege
	if not (sg is Dictionary):
		_add(r, "The battle log's siege should be a group of named values.")
		return
	for key in ["kind", "why", "fort"]:
		if not (sg.get(key) is String):
			_add(r, "The battle log's siege '%s' should be text." % key)
			return
	for key in ["walls", "walls_max", "walls_defense", "cover_defense", "garrison", "turn_of_siege"]:
		if not _is_int(sg.get(key)):
			_add(r, "The battle log's siege '%s' should be a whole number." % key)
			return
	if not (sg.get("from_inside") is Array):
		_add(r, "The battle log's siege 'from_inside' should be a list of army ids.")
		return
	var kind := String(sg.kind)
	if not SIEGE_WHYS.has(kind):
		_add(r, "The battle log's siege kind is '%s'; it should be storm, open or breach." % kind)
		return
	if not Array(SIEGE_WHYS[kind]).has(String(sg.why)):
		_add(r, "A %s battle can't be one of kind '%s' (§3.9)." % [kind, String(sg.why)])
	if not SIEGE_FORTS.has(String(sg.fort)):
		_add(r, "The battle log's siege fort is '%s'; it should be a palisade, a keep or a citadel." % String(sg.fort))
	if not bool(battle_log.fort):
		_add(r, "The battle log has a siege, but its header says there is no fort.")
	var walls := int(sg.walls)
	if walls < 0 or walls > int(sg.walls_max) or int(sg.walls_max) <= 0:
		_add(r, "The siege's walls are %d of %d; they should be from 0 to the most the fort has." % [walls, int(sg.walls_max)])
	var ns: int = battle_log.sides.size()
	var gi := int(sg.garrison)
	if gi < -1 or gi >= ns:
		_add(r, "The siege's garrison is side %d, but the log has %d sides." % [gi, ns])
		return
	var inside: Array = sg.from_inside
	if not inside.is_empty():
		if gi < 0:
			_add(r, "The siege has armies fighting from inside, but the fort's owner has no side.")
		else:
			var own := Array(battle_log.sides[gi].armies).map(func(a): return String(a.id))
			for id in inside:
				if not own.has(String(id)):
					_add(r, "Army '%s' fights from inside, but it isn't on the garrison's side." % str(id))
	var per_step := AutoBattleResolver.WALLS_DEFENSE_PER_STEP
	var expected_walls := per_step * ceili(float(maxi(walls, 0)) / AutoBattleResolver.WALL_STEP) if kind == "storm" else 0
	if int(sg.walls_defense) != expected_walls:
		_add(r, "A %s with walls %d gives the garrison +%d defense, but the log says +%d." % [kind, walls, expected_walls, int(sg.walls_defense)])
	var expected_cover := AutoBattleResolver.COVER_DEFENSE if kind != "storm" and not inside.is_empty() else 0
	if int(sg.cover_defense) != expected_cover:
		_add(r, "A %s battle gives cover %d, but the log says %d." % [String(sg.why), expected_cover, int(sg.cover_defense)])
	if kind == "storm":
		if gi < 0 or walls <= 0:
			_add(r, "A storm needs a garrison side behind standing walls.")
		elif String(battle_log.defender) != String(battle_log.sides[gi].faction):
			_add(r, "In a storm the garrison defends, but the log's defender is '%s'." % String(battle_log.defender))
	elif sg.has("holder"):
		# MVP-3 (#177): a neutral fort's Free Holds garrison holds the ground in the open (IND-1): the one open battle at a
		# fort with a defender, named by the block's "holder" side.
		var hi := int(sg.holder) if _is_int(sg.holder) else -1
		if kind != "open" or String(sg.why) != "empty":
			_add(r, "Only an open battle at an empty fort has a holder, but this one is a %s (%s)." % [kind, String(sg.why)])
		elif hi < 0 or hi >= ns:
			_add(r, "The siege's holder is side %s, but the log has %d sides." % [str(sg.holder), ns])
		elif String(battle_log.defender) != String(battle_log.sides[hi].faction):
			_add(r, "The holder defends, but the log's defender is '%s'." % String(battle_log.defender))
	elif not String(battle_log.defender).is_empty():
		_add(r, "A battle %s has no defender, but the log names '%s'." % ["through the breach" if kind == "breach" else "outside the walls",
			String(battle_log.defender)])
	if kind == "breach" and walls != 0:
		_add(r, "A battle through the breach needs walls at 0, but they are %d." % walls)


## M3c: every attack's walls, cover and fort parts agree with the siege block (none of them without one).
static func _validate_siege_parts(r: Array, battle_log: Dictionary) -> void:
	var sg: Dictionary = battle_log.get("siege", {})
	var inside: Array = sg.get("from_inside", [])
	var storm: bool = String(sg.get("kind", "")) == "storm"
	var fighters: Array = battle_log.fighters
	for i in battle_log.events.size():
		var e: Dictionary = battle_log.events[i]
		if String(e.t) != "attack":
			continue
		var parts: Dictionary = e.defense.parts
		var from_inside := inside.has(String(fighters[int(e.to)].army))
		var walls := int(parts.get(AutoBattleResolver.WALLS, 0))
		var cover := int(parts.get(AutoBattleResolver.COVER, 0))
		var want_walls := int(sg.walls_defense) if storm and from_inside else 0
		var want_cover := int(sg.get("cover_defense", 0)) if not storm and from_inside else 0
		if walls != want_walls or parts.has(AutoBattleResolver.WALLS) != (want_walls > 0):
			_add(r, "Event %d (attack in round %d): the target's walls part is %d, but it should be %d." % [i, int(e.n), walls, want_walls])
		if cover != want_cover or parts.has(AutoBattleResolver.COVER) != (want_cover > 0):
			_add(r, "Event %d (attack in round %d): the target's cover part is %d, but it should be %d." % [i, int(e.n), cover, want_cover])
		if not sg.is_empty() and parts.has("fort"):
			_add(r, "Event %d (attack in round %d): a battle at a fort with sieges has no flat fort part; the walls replace it." % [i, int(e.n)])


## M5-7: a cast event's fields and what they must agree with: a known battle spell of its school and kind, cast by one
## of its side's casters, a bolt on exactly one enemy for at least 1, a hex on enemies and a shield on its own side with
## their part.
static func _validate_cast(r: Array, what: String, e: Dictionary, battle_log: Dictionary) -> void:
	var fighters: Array = battle_log.fighters
	var nf := fighters.size()
	if not battle_log.get("magic", false):
		_add(r, "%s is a cast in a battle without magic." % what)
		return
	if not _in_range(e.get("by"), nf):
		_add(r, "%s names fighter %s as its caster, but the log has %d fighters." % [what, str(e.get("by")), nf])
		return
	var sid := str(e.get("spell", ""))
	var sp := MagicRules.spell_data(sid)
	if sp.is_empty() or not MagicRules.is_battle_spell(sid):
		_add(r, "%s casts '%s', which is not a battle spell." % [what, sid])
		return
	if str(e.get("school", "")) != String(sp.school) or str(e.get("kind", "")) != String(sp.kind) or not CAST_KINDS.has(String(sp.kind)):
		_add(r, "%s gives %s school '%s' and kind '%s'; it is %s's %s." % [what, String(sp.name), str(e.get("school")), str(e.get("kind")),
			String(sp.school), String(sp.kind)])
	var side: Dictionary = battle_log.sides[int(fighters[int(e.by)].side)]
	if not Array(side.get("casters", [])).map(func(x): return int(x)).has(int(e.by)):
		_add(r, "%s is cast by fighter %d, who is not one of its side's casters." % [what, int(e.by)])
	for key in ["bonus", "damage", "self"]:
		if not _is_int(e.get(key)) or int(e.get(key)) < 0:
			_add(r, "%s should have a whole number, 0 or more, for '%s'." % [what, key])
			return
	if not (e.get("targets") is Array) or e.targets.is_empty():
		_add(r, "%s should name its targets." % what)
		return
	for t in e.targets:
		if not _in_range(t, nf):
			_add(r, "%s targets fighter %s, but the log has %d fighters." % [what, str(t), nf])
			return
		var own: bool = int(fighters[int(t)].side) == int(fighters[int(e.by)].side)
		if own != (String(sp.kind) == "shield"):
			_add(r, "%s puts %s on fighter %d; a %s goes on %s." % [what, String(sp.name), int(t), String(sp.kind),
				"its own side" if String(sp.kind) == "shield" else "the enemy"])
	match String(sp.kind):
		"bolt":
			if e.targets.size() != 1 or int(e.damage) < 1:
				_add(r, "%s is a bolt: one target, at least 1 damage." % what)
			elif int(e.get("value", -1)) - int(e.get("resist", -1)) != int(e.damage) or int(e.get("resist", -1)) < 0:
				_add(r, "%s deals %d, but its value %s less resistance %s isn't that." % [what, int(e.damage), str(e.get("value")), str(e.get("resist"))])
		"hex", "shield":
			var part = e.get("part")
			if not (part is Dictionary) or str(part.get("stat", "")) != String(sp.get("stat", "")) or int(_num(part.get("value"), 0)) != int(sp.get("value", 0)):
				_add(r, "%s should carry its part: %s %+d." % [what, String(sp.get("stat", "")), int(sp.get("value", 0))])


static func _validate_attack(r: Array, what: String, e: Dictionary, nf: int) -> void:
	for key in ["by", "to"]:
		if not _in_range(e.get(key), nf):
			_add(r, "%s names fighter %s as '%s', but the log has %d fighters." % [what, str(e.get(key)), key, nf])
			return
	for key in ["pool", "pick", "chance", "roll", "damage", "base_hit"]:
		if not _is_int(e.get(key)):
			_add(r, "%s should have a whole number for '%s'." % [what, key])
			return
	if not (e.get("hit") is bool) or not (e.get("bonus") is Dictionary) or not (e.get("attack") is Dictionary) \
			or not (e.get("defense") is Dictionary) or not REACH_WORDS.has(e.get("reach")) or not (e.get("screened") is bool):
		_add(r, "%s should have hit, bonus, attack, defense, reach and screened." % what)
		return
	if int(e.pool) < 1 or int(e.pick) < 0 or int(e.pick) >= int(e.pool):
		_add(r, "%s picked target %d of %d; it should be from 0 to %d." % [what, int(e.pick), int(e.pool), int(e.pool) - 1])
	if int(e.roll) < 1 or int(e.roll) > 100:
		_add(r, "%s rolled %d; a hit roll is from 1 to 100." % [what, int(e.roll)])
	if bool(e.hit) != (int(e.roll) <= int(e.chance)):
		_add(r, "%s rolled %d against a %d%% chance, so it should be a %s." % [what, int(e.roll), int(e.chance),
			"hit" if int(e.roll) <= int(e.chance) else "miss"])
	var values := {}
	for key in ["attack", "defense"]:
		var stat: Dictionary = e[key]
		if not _is_int(stat.get("value")) or not _is_int(stat.get("base")) or not (stat.get("parts") is Dictionary):
			_add(r, "%s should give its %s value, base and parts." % [what, key])
			return
		var total := int(stat.base)
		for p in stat.parts:
			total += int(stat.parts[p])
		if total != int(stat.value):
			_add(r, "%s has %s %d, but its base and parts add up to %d." % [what, key, int(stat.value), total])
		values[key] = int(stat.value)
	var pall := int(_num(e.get("pall"), 0))  # CW-2: Pall's cut, inside the clamp (only on an attack on Pall)
	var chance := AutoBattleResolver.hit_chance(values.attack, values.defense, int(e.base_hit) + pall)
	if chance != int(e.chance):
		_add(r, "%s has a %d%% chance, but attack %d against defense %d from base %d%s gives %d%%." % [what, int(e.chance),
			values.attack, values.defense, int(e.base_hit), " with Pall's %d" % pall if pall != 0 else "", chance])
	var bonus := 0
	for p in e.bonus:
		bonus += int(e.bonus[p])
	var dmg := AutoBattleResolver.damage(values.attack, values.defense) + bonus
	if dmg != int(e.damage):
		_add(r, "%s does %d damage, but attack %d against defense %d (bonus %d) gives %d." % [what, int(e.damage), values.attack,
			values.defense, bonus, dmg])
	if absf(float(_num(e.get("expected"), -100.0)) - int(e.chance) / 100.0 * int(e.damage)) > 0.051:
		_add(r, "%s expects %s damage, but a %d%% chance of %d is %.2f." % [what, str(e.get("expected")), int(e.chance), int(e.damage),
			int(e.chance) / 100.0 * int(e.damage)])


# --- verify_draws -------------------------------------------------------------------------------------

## Replays the log's rolls from the seed (§2.1): starting from rng.before, re-draws every target roll and
## hit roll and the tie-break roll exactly as the resolver drew them, and checks each against the log and
## the final state against rng.after. [] when everything matches, otherwise plain-language reasons (the
## first wrong roll stops the check: every roll after it would be drawn from a different state).
static func verify_draws(battle_log) -> Array:
	var problems := validate(battle_log)
	if not problems.is_empty():
		return problems
	if battle_log.truncated:
		return ["This battle log was cut short at %d events, so its rolls can't all be checked." % battle_log.events.size()]
	var rng := SeededRNG.new(Serial.to_int(battle_log.rng.seed))
	rng.set_state(Serial.to_int(battle_log.rng.before))
	var events: Array = battle_log.events
	for i in events.size():
		var e: Dictionary = events[i]
		if e.t == "attack":
			var pick := rng.randi_range(0, int(e.pool) - 1)
			if pick != int(e.pick):
				return ["Round %d, event %d: fighter %d's target roll comes out as %d of %d from the saved state, but the log says %d. The rolls after it can't be checked." % [
					int(e.n), i, int(e.by), pick, int(e.pool), int(e.pick)]]
			var roll := rng.randi_range(1, 100)
			if roll != int(e.roll):
				return ["Round %d, event %d: fighter %d's hit roll comes out as %d from the saved state, but the log says %d. The rolls after it can't be checked." % [
					int(e.n), i, int(e.by), roll, int(e.roll)]]
		elif e.t == "end" and e.tie_break == "roll":
			var r := rng.randi_range(0, int(e.tied) - 1)
			if r != int(e.roll):
				return ["The tie-break roll comes out as %d of %d from the saved state, but the log says %d." % [r, int(e.tied), int(e.roll)]]
	var after := Serial.int64_to_str(rng.get_state())
	if after != String(battle_log.rng.after):
		return ["After re-drawing every roll, the random numbers are at state %s, but the log says the battle ended at %s." % [
			after, battle_log.rng.after]]
	return []


# --- regenerate ---------------------------------------------------------------------------------------

## Rebuilds battle `index` (0-based, in resolution order) of `turn` (1-based, as players count turns)
## from a game record (GameSession.record(), also after a JSON round trip): replays the record to the
## start of that turn and resolves it with its recorded orders and seed (GameSession.replay's
## up_to_turn). Returns {"log", "report", "errors"}; "log" and "report" are {} when there is no such
## battle, and "errors" says why in plain words ("This game record has no turn 9.").
static func regenerate(game_record, turn: int, index: int) -> Dictionary:
	var out := {"log": {}, "report": {}, "errors": []}
	if not (game_record is Dictionary) or not (game_record.get("history") is Array):
		out.errors.append("This is not a game record: it has no list of turns.")
		return out
	var turns: int = game_record.history.size()
	if turn < 1 or turn > turns:
		out.errors.append("This game record has no turn %d. It has %d %s." % [turn, turns, "turn" if turns == 1 else "turns"])
		return out
	var replayed := GameSession.replay(game_record, null, turn)
	out.errors.append_array(replayed.errors)
	if replayed.state == null:
		return out
	var battles: Array = replayed.events.filter(func(e): return GameSession.BATTLE_TYPES.has(e.get("type", "")))
	if index < 0 or index >= battles.size():
		out.errors.append("Turn %d had %d %s, so there is no battle %d." % [turn, battles.size(),
			"battle" if battles.size() == 1 else "battles", index + 1])
		return out
	var numbers: Dictionary = battles[index].numbers
	out.report = numbers.get("report", {})
	out.log = numbers.get("log", {})
	if out.log.is_empty():
		out.errors.append("Battle %d of turn %d has no log." % [index + 1, turn])
	return out


# --- cross_check --------------------------------------------------------------------------------------

## design/M3_BATTLES.md §2.5's cross-checks between `battle_log` and its `report` (numbers.report; also
## after a JSON round trip of either). [] when they agree, otherwise plain-language reasons:
##   - the final state (BattleTimeline) equals the report: each side's hp_end, its lost fighters' names
##     in order, routed / destroyed / out_round, rounds_fought, the winner and how it ended; each round's
##     hp, attacks, hits and dealt (the round line's "dealt N damage (H of A hits)"); the totals, hit
##     rates and hit chance ranges; the morale log; the ruler's fell / fell_round / hp_end / damage; the
##     Feast's healing
##   - every wound is the sum of that round's hits on the fighter (capped at its hp), by those attackers
##   - the rounds' impact plus the end's impact equals each side's impact in the report's all_factors,
##     within 0.1
##   - the derived statuses (BattleTimeline.statuses) agree with every attack's parts and "screened"
##   - every attack's target is a standing enemy in a tier its attacker could reach that round, and the
##     pool is the number of such enemies
static func cross_check(battle_log: Dictionary, report: Dictionary) -> Array:
	var r := validate(battle_log)
	if not r.is_empty():
		return r
	if battle_log.truncated:
		return ["This battle log was cut short, so it can't be checked against its report."]
	var sides: Array = battle_log.sides
	var fighters: Array = battle_log.fighters
	var rep_sides: Array = report.get("sides", [])
	if rep_sides.size() != sides.size():
		return ["The log has %d sides but the report has %d." % [sides.size(), rep_sides.size()]]
	if JSON.stringify(battle_log.get("siege", {})) != JSON.stringify(report.get("siege", {})):
		r.append("The log's siege block and the report's differ.")  # M3c (§4.5): the report carries the same block
	var events: Array = battle_log.events
	var tl := BattleTimeline.build(battle_log)
	var frenzy_key: String = AutoBattleResolver.MANDATE_PREFIX + RulerRules.BLOOD_FRENZY

	# One pass over the events: per-attack checks on the running state, and the round's tallies.
	var state := BattleTimeline.initial_state(battle_log)
	var reach := {}  # side index -> {"tiers", "skirmish_tiers"} for the current round
	var pending := {}  # fighter id -> hits this round: {"dmg", "by": []}
	var tally := []  # per side this round: [attacks, hits, dealt]
	var totals := []  # per side: {"attacks", "hits", "dealt", "chance_sum", "chance_min", "chance_max", "ruler_dealt"}
	var deaths := []  # per side: names in death order
	var out_round := []
	var morale := []  # per side: morale events
	var impact := []  # per side: {key: summed worth}
	for i in sides.size():
		totals.append({"attacks": 0, "hits": 0, "dealt": 0, "chance_sum": 0, "chance_min": 100, "chance_max": 0, "ruler_dealt": 0})
		deaths.append([])
		out_round.append(0)
		morale.append([])
		impact.append({})
	var end_state := {}
	var end_event := {}
	var feast_healed := -1
	var round_dealt := {}  # M4-3: fighter id -> damage its hits dealt this round (Lifedrinker's heal)
	var cast_now := {}  # M5-7: caster id -> true when it cast this round (so it makes no attack)
	var self_bleed := {}  # M5-7: caster id -> the bleed its cast this round asks for
	var moon_sides := {}  # M5-7: side index -> true when the Blood Moon shines on it in this battle
	for sd in sides:
		for en in sd.get("enchantments", []):
			if String(en.get("ritual", "")) == "blood_moon" and not String(en.get("effect", "")).begins_with("outside"):
				moon_sides[int(sd.index)] = true
	for i in events.size():
		var e: Dictionary = events[i]
		match e.t:
			"round":
				reach = {}
				for entry in e.reach:
					reach[int(entry.side)] = entry
				pending = {}
				round_dealt = {}
				cast_now = {}
				self_bleed = {}
				tally = []
				for s in sides:
					tally.append([0, 0, 0])
			"cast":
				# M5-7: a standing caster casts on standing targets; a bolt's damage waits for the wounds like a hit.
				var by := int(e.by)
				if not state.fighters[by].alive or state.fighters[by].fled:
					_add(r, "Round %d, event %d: fighter %d casts, but it isn't standing." % [int(e.n), i, by])
				if cast_now.has(by):
					_add(r, "Round %d, event %d: fighter %d casts twice in one round." % [int(e.n), i, by])
				cast_now[by] = true
				for t in e.targets:
					if not state.fighters[int(t)].alive or state.fighters[int(t)].fled:
						_add(r, "Round %d, event %d: %s lands on fighter %d, who isn't standing." % [int(e.n), i, String(e.spell), int(t)])
				if String(e.kind) == "bolt":
					var p: Dictionary = pending.get(int(e.targets[0]), {"dmg": 0, "by": []})
					p.dmg += int(e.damage)
					p.by.append(by)
					pending[int(e.targets[0])] = p
				if int(e.self) > 0:
					self_bleed[by] = int(e.self)
			"attack":
				if cast_now.has(int(e.by)):
					_add(r, "Round %d, event %d: fighter %d attacks in a round it cast a spell." % [int(e.n), i, int(e.by)])
				_check_spell_parts(r, i, e, state)
				_check_attack(r, i, e, battle_log, state, reach, tl, frenzy_key)
				var a: Dictionary = fighters[int(e.by)]
				var si := int(a.side)
				tally[si][0] += 1
				var tot: Dictionary = totals[si]
				tot.attacks += 1
				tot.chance_sum += int(e.chance)
				tot.chance_min = mini(tot.chance_min, int(e.chance))
				tot.chance_max = maxi(tot.chance_max, int(e.chance))
				if e.hit:
					tally[si][1] += 1
					tally[si][2] += int(e.damage)
					tot.hits += 1
					tot.dealt += int(e.damage)
					if a.role == "ruler":
						tot.ruler_dealt += int(e.damage)
					var p: Dictionary = pending.get(int(e.to), {"dmg": 0, "by": []})
					p.dmg += int(e.damage)
					p.by.append(int(e.by))
					pending[int(e.to)] = p
					round_dealt[int(e.by)] = int(round_dealt.get(int(e.by), 0)) + int(e.damage)
			"wound":
				var p: Dictionary = pending.get(int(e.f), {"dmg": 0, "by": []})
				var want := maxi(0, int(e.from) - int(p.dmg))
				var by_want: Array = p.by.duplicate()
				# M5-7: a Bloodbolt's bleed lands after the round's damage, never below 1 hp.
				var bled := mini(int(self_bleed.get(int(e.f), 0)), maxi(0, want - 1))
				want -= bled
				if bled > 0:
					by_want.append(int(e.f))
				if int(e.get("bled", 0)) != bled:
					_add(r, "Round %d: fighter %d's wound says it bled %d, but its cast asked for %d and it could bleed %d." % [int(e.n), int(e.f),
						int(e.get("bled", 0)), int(self_bleed.get(int(e.f), 0)), bled])
				if int(e.from) != int(state.fighters[int(e.f)].hp) or int(e.to) != want:
					_add(r, "Round %d: fighter %d's wound goes from %d to %d hp, but it had %d hp and took %d damage in hits." % [
						int(e.n), int(e.f), int(e.from), int(e.to), int(state.fighters[int(e.f)].hp), int(p.dmg)])
				if _ints(e.by) != by_want:
					_add(r, "Round %d: fighter %d's wound names %s as its attackers, but the hits on it came from %s." % [
						int(e.n), int(e.f), str(_ints(e.by)), str(by_want)])
				pending.erase(int(e.f))
				self_bleed.erase(int(e.f))
			"death":
				deaths[int(fighters[int(e.f)].side)].append(String(fighters[int(e.f)].name))
			"flare":
				# CW-2: a fallen Hundred-Wick burns standing enemies of the front rank; its damage waits for their wounds.
				var fw := int(e.f)
				if state.fighters[fw].alive or String(fighters[fw].trait) != AutoBattleResolver.FLARE:
					_add(r, "Round %d, event %d: fighter %d flares, but only a fallen fighter with Flare does." % [int(e.n), i, fw])
				for x in e.targets:
					var tx := int(x)
					if not state.fighters[tx].alive or state.fighters[tx].fled or int(fighters[tx].side) == int(fighters[fw].side) \
							or int(fighters[tx].tier) != 0:
						_add(r, "Round %d, event %d: the Flare burns fighter %d, who isn't a standing enemy in the front rank." % [int(e.n), i, tx])
					var p: Dictionary = pending.get(tx, {"dmg": 0, "by": []})
					p.dmg += int(e.damage)
					p.by.append(fw)
					pending[tx] = p
			"heal":
				# M4-3: Lifedrinker heals a standing fighter 1/LIFEDRINK_DIVISOR of what its hits dealt this
				# round, rounded up, up to its maximum.
				var hf: Dictionary = fighters[int(e.f)]
				var drunk := int(round_dealt.get(int(e.f), 0))
				# M5-7: under the Blood Moon a quarter, rounded down ("spell"), and never above maximum - 1.
				var moon: bool = moon_sides.has(int(hf.side))
				var top := int(hf.max_hp) - (1 if moon else 0)
				var by_moon := String(e.get("spell", "")) == "blood_moon"
				var share := floori(float(drunk) / int(MagicData.SPELLS.blood_moon.share)) if by_moon \
					else ceili(float(drunk) / AutoBattleResolver.LIFEDRINK_DIVISOR)
				var want := mini(top, int(e.from) + share)
				if String(e.get("trait", "")) == AutoBattleResolver.SIPHON:
					# CW-2: Siphon heals a standing fighter that landed a hit this round SIPHON_HEAL, up to its maximum.
					if String(hf.trait) != AutoBattleResolver.SIPHON or not state.fighters[int(e.f)].alive or drunk <= 0:
						_add(r, "Round %d: fighter %d siphons, but only a standing fighter with Siphon that landed a hit this round does." % [int(e.n), int(e.f)])
					elif int(e.from) != int(state.fighters[int(e.f)].hp) or int(e.to) != mini(int(hf.max_hp), int(e.from) + AutoBattleResolver.SIPHON_HEAL) \
							or int(e.dealt) != drunk:
						_add(r, "Round %d: fighter %d siphons from %d to %d, but it had %d hp and Siphon heals %d." % [int(e.n), int(e.f),
							int(e.from), int(e.to), int(state.fighters[int(e.f)].hp), AutoBattleResolver.SIPHON_HEAL])
				elif (by_moon and not moon) or (not by_moon and String(hf.trait) != AutoBattleResolver.LIFEDRINKER) or not state.fighters[int(e.f)].alive:
					_add(r, "Round %d: fighter %d heals, but only a standing fighter with Lifedrinker, or under the Blood Moon, does." % [int(e.n), int(e.f)])
				elif int(e.from) != int(state.fighters[int(e.f)].hp) or int(e.to) != want or int(e.dealt) != drunk:
					_add(r, "Round %d: fighter %d heals from %d to %d after dealing %d, but it had %d hp and its hits dealt %d this round." % [
						int(e.n), int(e.f), int(e.from), int(e.to), int(e.dealt), int(state.fighters[int(e.f)].hp), drunk])
			"morale":
				morale[int(e.side)].append(e)
			"rout", "destroyed":
				out_round[int(e.side)] = int(e.n)
			"round_end":
				if not pending.is_empty():
					_add(r, "Round %d: fighters %s were hit but have no wound." % [int(e.n), str(pending.keys())])
				var rr: Dictionary = _report_round(report, int(e.n))
				for si in sides.size():
					if int(e.attacks[si]) != tally[si][0] or int(e.hits[si]) != tally[si][1] or int(e.dealt[si]) != tally[si][2]:
						_add(r, "Round %d: side %d's round totals (%d attacks, %d hits, %d dealt) don't match its attacks (%d, %d, %d)." % [
							int(e.n), si, int(e.attacks[si]), int(e.hits[si]), int(e.dealt[si]), tally[si][0], tally[si][1], tally[si][2]])
					var s_hp := int(state.sides[si].hp)
					if int(e.hp[si]) != s_hp:
						_add(r, "Round %d: side %d ends the round with %d hp in round_end, but its wounds leave %d." % [int(e.n), si, int(e.hp[si]), s_hp])
					for k in e.impact[si]:
						impact[si][k] = float(impact[si].get(k, 0.0)) + float(e.impact[si][k])
					if rr.is_empty():
						continue
					var faction := String(sides[si].faction)
					if int(_num(rr.get("hp", {}).get(faction), -1)) != int(e.hp[si]):
						_add(r, "Round %d: the report gives %s %s hp after the round, the log %d." % [int(e.n), faction,
							str(rr.get("hp", {}).get(faction)), int(e.hp[si])])
					var rdealt = _keyed(rr.get("dealt", {}), si)
					if rdealt != null:
						if int(_num(rdealt, -1)) != int(e.dealt[si]):
							_add(r, "Round %d: the report says %s dealt %s, the log %d." % [int(e.n), faction, str(rdealt), int(e.dealt[si])])
						var phrase := "%s dealt %d damage (%d of %d hits)" % [sides[si].name, int(e.dealt[si]), int(e.hits[si]), int(e.attacks[si])]
						if not String(rr.get("line", "")).contains(phrase):
							_add(r, "Round %d: the report's line doesn't say \"%s\"." % [int(e.n), phrase])
			"end":
				end_event = e
				end_state = tl.state_at(i + 1)
				for si in sides.size():
					for k in e.impact[si]:
						impact[si][k] = float(impact[si].get(k, 0.0)) + float(e.impact[si][k])
			"feast":
				feast_healed = 0
				for h in e.healed:
					feast_healed += int(h[2]) - int(h[1])
		BattleTimeline.apply(battle_log, state, i)

	# The end and the report.
	if end_event.is_empty():
		return r + ["The battle log has no end event."]
	if int(end_event.rounds) != int(_num(report.get("rounds_fought"), -1)):
		_add(r, "The log fought %d rounds, the report %s." % [int(end_event.rounds), str(report.get("rounds_fought"))])
	if String(sides[int(end_event.winner)].faction) != String(report.get("winner", "")):
		_add(r, "The log's winner is %s, the report's %s." % [sides[int(end_event.winner)].faction, str(report.get("winner"))])
	if String(end_event.how) != String(report.get("end", "")):
		_add(r, "The log's battle ended by %s, the report's by %s." % [end_event.how, str(report.get("end"))])
	for si in sides.size():
		var s: Dictionary = sides[si]
		var sr: Dictionary = rep_sides[si]
		var name := String(s.faction)
		if String(sr.get("faction", "")) != name:
			_add(r, "Side %d is %s in the log but %s in the report." % [si, name, str(sr.get("faction"))])
			continue
		var es: Dictionary = end_state.sides[si]
		var checks := [["hp_start", int(s.hp_start)], ["fighters_start", s.fighters.size()], ["base_morale", int(s.base_morale)],
			["hp_end", int(es.hp)], ["fighters_lost", deaths[si].size()], ["routed", es.out == "routed"],
			["destroyed", es.out == "destroyed"], ["out_round", out_round[si]],
			["attacks", int(totals[si].attacks)], ["hits", int(totals[si].hits)], ["damage_dealt", int(totals[si].dealt)]]
		var tot: Dictionary = totals[si]
		if tot.attacks > 0:
			checks.append(["hit_rate", roundi(100.0 * tot.hits / tot.attacks)])
			checks.append(["expected_hit_rate", roundi(float(tot.chance_sum) / tot.attacks)])
		for c in checks:
			var want = sr.get(c[0])
			if want is bool or c[1] is bool:
				if bool(want) != bool(c[1]):
					_add(r, "%s: the report's %s is %s, the log's %s." % [name, c[0], str(want), str(c[1])])
			elif int(_num(want, -999999)) != int(c[1]):
				_add(r, "%s: the report's %s is %s, the log's %s." % [name, c[0], str(want), str(c[1])])
		if tot.attacks > 0:
			var hcr = sr.get("hit_chance_range", [])
			if not (hcr is Array) or hcr.size() != 2 or int(hcr[0]) != int(tot.chance_min) or int(hcr[1]) != int(tot.chance_max):
				_add(r, "%s: the report's hit chances range %s, the log's [%d, %d]." % [name, str(hcr), tot.chance_min, tot.chance_max])
		var expected := 0.0
		for e in events:
			if e.t == "round_end":
				expected += float(e.expected[si])
		if absf(expected - float(_num(sr.get("damage_expected"), -1000.0))) > 0.1:
			_add(r, "%s: the report expected %s damage, the log's rounds %.2f." % [name, str(sr.get("damage_expected")), expected])
		if _strings(sr.get("lost", [])) != deaths[si]:
			_add(r, "%s: the report's fallen are %s, the log's %s." % [name, str(sr.get("lost")), str(deaths[si])])
		_check_morale_log(r, name, sr.get("morale_log", []), morale[si])
		_check_ruler(r, battle_log, si, sr, end_state, tot.ruler_dealt)
		# Impact: each factor measured in the resolver's accumulator equals the log's rounds plus its end.
		for f in report.get("all_factors", []):
			if String(f.get("faction", "")) != name or _non_impact(String(f.get("id", ""))):
				continue
			var got := float(impact[si].get(String(f.id), 0.0))
			if absf(got - float(_num(f.get("impact"), 0.0))) > 0.1:
				_add(r, "%s: the report's factor %s is worth %s, but the log's rounds add up to %.2f." % [name, f.id, str(f.get("impact")), got])
	var feast = report.get("feast", {})
	if feast is Dictionary and not feast.is_empty():
		if feast_healed != int(_num(feast.get("healed"), -1)):
			_add(r, "The report's Feast healed %s hp, the log's %d." % [str(feast.get("healed")), feast_healed])
	elif feast_healed >= 0:
		_add(r, "The log has a Feast of Victory the report doesn't.")
	return r


static func _check_attack(r: Array, i: int, e: Dictionary, battle_log: Dictionary, state: Dictionary, reach: Dictionary, tl: BattleTimeline,
		frenzy_key: String) -> void:
	var fighters: Array = battle_log.fighters
	var a: Dictionary = fighters[int(e.by)]
	var t: Dictionary = fighters[int(e.to)]
	var where := "Round %d, event %d (%s attacking %s)" % [int(e.n), i, a.name, t.name]
	var fa: Dictionary = state.fighters[int(e.by)]
	var ft: Dictionary = state.fighters[int(e.to)]
	if not fa.alive or fa.fled:
		_add(r, "%s: the attacker isn't standing." % where)
	if not ft.alive or ft.fled or int(t.side) == int(a.side):
		_add(r, "%s: the target isn't a standing enemy." % where)
	if not reach.has(int(t.side)):
		_add(r, "%s: the round gives no reach for the target's side." % where)
		return
	var skirmish: bool = a.trait == AutoBattleResolver.SKIRMISH
	var wings: bool = a.trait == AutoBattleResolver.WINGS
	if wings and not reach[int(t.side)].has("wings_tiers"):
		_add(r, "%s: the attacker has Wings, but the round gives no reach for Wings." % where)
		return
	# M4-3: Wings goes only for commanders while any enemy side it could reach has one standing.
	var wings_cmd := false
	if wings:
		for s in battle_log.sides:
			var si := int(s.index)
			if si != int(a.side) and state.sides[si].out == "" and reach.has(si) and _ints(reach[si].wings_tiers) == [2]:
				wings_cmd = true
	var tiers: Array = _side_reach(reach[int(t.side)], skirmish, wings, wings_cmd)
	if not tiers.has(int(t.tier)):
		_add(r, "%s: the target stands in rank %d, which the attacker couldn't reach this round (%s)." % [where, int(t.tier), str(tiers)])
	var ordinary: Array = _ints(reach[int(t.side)].tiers)
	var word: String = ("wings" if wings else "skirmish") if not ordinary.has(int(t.tier)) else REACH_WORDS[int(t.tier)]
	if String(e.reach) != word:
		_add(r, "%s: the attack's reach is %s, but it should be %s." % [where, e.reach, word])
	# M4-3: Rooted only in a province battle in a forest; Iron Hide only on a fighter with it, and always
	# unless the hit was already at the minimum.
	var rooted: bool = String(t.trait) == AutoBattleResolver.ROOTED and battle_log.kind == "province" and battle_log.terrain == "forest"
	if rooted != e.defense.parts.has(AutoBattleResolver.ROOTED):
		_add(r, "%s: Rooted %s the defense, but the target %s rooted in a forest province." % [where,
			"is in" if e.defense.parts.has(AutoBattleResolver.ROOTED) else "is not in", "is" if rooted else "is not"])
	var hide: bool = String(t.trait) == AutoBattleResolver.IRON_HIDE
	if e.bonus.has(AutoBattleResolver.IRON_HIDE) and not hide:
		_add(r, "%s: the damage has Iron Hide, but the target doesn't." % where)
	elif hide and not e.bonus.has(AutoBattleResolver.IRON_HIDE) and int(e.damage) > AutoBattleResolver.MIN_DAMAGE:
		_add(r, "%s: the target has Iron Hide, but the damage doesn't count it." % where)
	var pool := 0
	for s in battle_log.sides:
		var si := int(s.index)
		if si == int(a.side) or state.sides[si].out != "" or not reach.has(si):
			continue
		var st: Array = _side_reach(reach[si], skirmish, wings, wings_cmd)
		for fid in s.fighters:
			var fs: Dictionary = state.fighters[int(fid)]
			if fs.alive and st.has(int(fighters[int(fid)].tier)):
				pool += 1
	if pool != int(e.pool):
		_add(r, "%s: the attacker could reach %d enemies, but the log says %d." % [where, pool, int(e.pool)])
	var st_a := tl.statuses(state, int(e.by))
	var st_t := tl.statuses(state, int(e.to))
	var parts: Dictionary = e.attack.parts
	var dparts: Dictionary = e.defense.parts
	for c in [["Berserk", st_a.berserk, parts.has(AutoBattleResolver.BERSERK)],
			["Blood Frenzy", st_a.blood_frenzy, parts.has(frenzy_key)],
			["Pack Leader", st_a.pack_leader, parts.has(AutoBattleResolver.PACK_LEADER)],
			["Shield Wall", st_t.shield_wall, dparts.has(AutoBattleResolver.SHIELD_WALL)],
			["shielded", st_a.shielded, bool(e.screened)]]:
		if bool(c[1]) != bool(c[2]):
			_add(r, "%s: the derived %s status is %s, but the attack says %s." % [where, c[0], str(c[1]), str(c[2])])


## M5-7: an attack's spell parts are exactly the hexes on its attacker and the shields on its target this round.
static func _check_spell_parts(r: Array, i: int, e: Dictionary, state: Dictionary) -> void:
	for c in [["attack", int(e.by)], ["defense", int(e.to)]]:
		var got := {}
		for p in e[c[0]].parts:
			if String(p).begins_with(AutoBattleResolver.SPELL_PREFIX):
				got[String(p)] = int(e[c[0]].parts[p])
		var want := {}
		var on: Dictionary = state.fighters[int(c[1])].get("spells", {})
		for p in on:
			if String(on[p].stat) == c[0]:
				want[String(p)] = int(on[p].value)
		if got != want:
			_add(r, "Round %d, event %d: the %s's spell parts are %s, but the casts this round put %s on it." % [int(e.n), i,
				"attacker" if c[0] == "attack" else "target", str(got), str(want)])


static func _check_morale_log(r: Array, name: String, morale_log, events: Array) -> void:
	if not (morale_log is Array) or morale_log.size() != events.size():
		_add(r, "%s: the report has %d morale checks, the log %d." % [name, morale_log.size() if morale_log is Array else 0, events.size()])
		return
	for k in events.size():
		var m: Dictionary = morale_log[k]
		var e: Dictionary = events[k]
		for key in [["round", "n"], ["morale", "morale"], ["break_pct", "break_pct"], ["lost_pct", "lost_pct"], ["hp", "hp"]]:
			if int(_num(m.get(key[0]), -1)) != int(e[key[1]]):
				_add(r, "%s: morale check %d has %s %s in the report, %d in the log." % [name, k + 1, key[0], str(m.get(key[0])), int(e[key[1]])])
		var parts: Dictionary = m.get("parts", {})
		if parts.size() != e.parts.size():
			_add(r, "%s: morale check %d has parts %s in the report, %s in the log." % [name, k + 1, str(parts), str(e.parts)])
			continue
		for p in parts:
			if int(_num(e.parts.get(p), -999)) != int(parts[p]):
				_add(r, "%s: morale check %d has parts %s in the report, %s in the log." % [name, k + 1, str(parts), str(e.parts)])
				break
		if (e.result == "held") != m.has("held_by"):
			_add(r, "%s: morale check %d is %s in the log, but the report %s Iron Discipline holding it." % [name, k + 1, e.result,
				"has" if m.has("held_by") else "doesn't have"])


static func _check_ruler(r: Array, battle_log: Dictionary, si: int, sr: Dictionary, end_state: Dictionary, ruler_dealt: int) -> void:
	var rep = sr.get("ruler")
	var ruler_id := -1
	for fid in battle_log.sides[si].fighters:
		if battle_log.fighters[int(fid)].role == "ruler":
			ruler_id = int(fid)
	if not (rep is Dictionary):
		if ruler_id >= 0:
			_add(r, "%s: the log has a ruler the report doesn't." % battle_log.sides[si].faction)
		return
	if ruler_id < 0:
		_add(r, "%s: the report has a ruler the log doesn't." % battle_log.sides[si].faction)
		return
	var fell_round := 0
	for e in battle_log.events:
		if e.t == "death" and int(e.f) == ruler_id:
			fell_round = int(e.n)
	var hp := int(end_state.fighters[ruler_id].hp)
	for c in [["fell", fell_round > 0], ["fell_round", fell_round], ["hp_end", hp], ["damage_dealt", ruler_dealt],
			["hp_start", int(battle_log.fighters[ruler_id].hp)]]:
		var want = rep.get(c[0])
		if (c[1] is bool and bool(want) != c[1]) or (not (c[1] is bool) and int(_num(want, -1)) != int(c[1])):
			_add(r, "%s's ruler: the report's %s is %s, the log's %s." % [battle_log.sides[si].faction, c[0], str(want), str(c[1])])


## The ranks an attacker can reach on a side, from the round's reach entry: Skirmish's, Wings' (only the
## commanders, and nothing on a side without one, while `wings_cmd`: an enemy commander stands) or the
## ordinary ones.
static func _side_reach(entry: Dictionary, skirmish: bool, wings: bool, wings_cmd: bool) -> Array:
	if wings:
		var wt := _ints(entry.get("wings_tiers", []))
		return wt if not wings_cmd or wt == [2] else []
	return _ints(entry.skirmish_tiers if skirmish else entry.tiers)


## The report's round `n` ({} when it has none).
static func _report_round(report: Dictionary, n: int) -> Dictionary:
	var rounds = report.get("rounds", [])
	if rounds is Array and n >= 1 and n <= rounds.size() and rounds[n - 1] is Dictionary:
		return rounds[n - 1]
	return {}


## `d[key]` where `d` is keyed by an int side index, or by its string after a JSON round trip; null if absent.
static func _keyed(d, key: int):
	if not (d is Dictionary):
		return null
	if d.has(key):
		return d[key]
	if d.has(str(key)):
		return d[str(key)]
	return null


# --- small helpers ------------------------------------------------------------------------------------

## True for a "why" factor measured outside the resolver's impact accumulator (NON_IMPACT_FACTORS, and
## every morale factor).
static func _non_impact(factor_id: String) -> bool:
	if NON_IMPACT_FACTORS.has(factor_id):
		return true
	for p in NON_IMPACT_PREFIXES:
		if factor_id.begins_with(p):
			return true
	return false


static func _add(reasons: Array, text: String) -> void:
	if reasons.size() < MAX_REASONS:
		reasons.append(text)


static func _num(v, default = 0):
	return v if v is int or v is float else default


static func _is_int(v) -> bool:
	return v is int or (v is float and v == floorf(v))


static func _in_range(v, n: int) -> bool:
	return _is_int(v) and int(v) >= 0 and int(v) < n


static func _ints(a) -> Array:
	var out := []
	if a is Array:
		for v in a:
			out.append(int(v))
	return out


static func _strings(a) -> Array:
	var out := []
	if a is Array:
		for v in a:
			out.append(String(v))
	return out
