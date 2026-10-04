class_name VictoryCheck
extends RefCounted
## Win condition for M1 (#8): capturing the enemy capital ends the game. Pure rules code.
##
##   VictoryCheck.check(state, player_ids) -> {"over", "winner", "draw", "fallen", "standing"}
##
## Checked by GameSession on the new state after every turn's resolution. A player has lost when
## their capital is owned by another faction. Capitals only change hands through capture, so this
## is the same as "an enemy captured it". The game is over as soon as at most one player still holds
## their capital: that player wins. If every player's capital fell in the same turn (in M1's
## two-player game: both capitals captured in one simultaneous resolution), the game is a draw.
## Player-facing text: RulesCodex "victory" and "simultaneous_capture".
##
## Determinism: players are checked in sorted id order; nothing depends on Dictionary order.


## Returns {"over": bool, "winner": faction id or "", "draw": bool,
##          "fallen": [{"faction", "capital", "captor"}] sorted by faction id,
##          "standing": [faction ids that still hold their capital], sorted}.
static func check(state: GameState, player_ids: Array) -> Dictionary:
	var ids := player_ids.duplicate()
	ids.sort()
	var fallen := []
	var standing := []
	for fid in ids:
		var f := state.find_faction(str(fid))
		if f == null:
			continue
		var capital := state.find_province(f.capital)
		var owner: String = capital.owner if capital != null else ""
		if not owner.is_empty() and owner != f.id:
			fallen.append({"faction": f.id, "capital": f.capital, "captor": owner})
		else:
			standing.append(f.id)
	var over := not fallen.is_empty() and standing.size() <= 1
	return {
		"over": over,
		"winner": standing[0] if over and standing.size() == 1 else "",
		"draw": over and standing.is_empty(),
		"fallen": fallen,
		"standing": standing,
	}


## Victory summary for the victory screen and the final turn report.
## `players` is the seat order (used to list provinces held), `turn` the 1-based turn the game
## ended on, `turns_played` and `battles` count the whole game.
## Returns {"over", "winner", "draw", "turn", "turns_played", "battles", "provinces_held": {id: n},
##          "captures": [{"captor", "capital", "of"}], "text", "event"}, plus "builds" (see builds())
## in a game with rulers, whose `text` then ends with builds_text().
## `text` names factions and provinces only by their display names.
static func summary(state: GameState, players: Array, result: Dictionary, turn: int, turns_played: int, battles: int) -> Dictionary:
	var held := {}
	var held_parts := []
	for fid in players:
		var count := 0
		for p in state.provinces:
			if p.owner == fid:
				count += 1
		held[fid] = count
		held_parts.append("%s %d" % [_faction_name(state, fid), count])

	var captures := []
	var clauses := []
	var capital_ids := []
	for f in result.get("fallen", []):
		captures.append({"captor": f.captor, "capital": f.capital, "of": f.faction})
		capital_ids.append(f.capital)
		clauses.append("%s captured %s, the %s capital" % [_faction_name(state, f.captor),
			_province_name(state, f.capital), _faction_name(state, f.faction)])

	var winner: String = result.get("winner", "")
	var draw: bool = result.get("draw", false)
	var length := "%d %s and %d %s" % [turns_played, "turn" if turns_played == 1 else "turns",
		battles, "battle" if battles == 1 else "battles"]
	var text: String
	var cause: String
	var codex: String
	var involved := []
	if draw:
		text = "%s, both on turn %d. Both capitals fell in the same turn, so the game is a draw after %s." % [
			", and ".join(clauses), turn, length]
		cause = "both_capitals_captured"
		codex = "simultaneous_capture"
		involved = players.duplicate()
		involved.sort()
	else:
		text = "%s, on turn %d. %s wins after %s." % [", and ".join(clauses), turn, _faction_name(state, winner), length]
		cause = "capital_captured"
		codex = "victory"
		involved = [winner]
	text += " Provinces held: %s." % ", ".join(held_parts)
	# M2: in a game with rulers, each player's build, so players can argue about builds afterwards.
	var player_builds := builds(state, players)
	if not player_builds.is_empty():
		text += " " + _builds_sentence(state, players, player_builds)

	var event := {
		"type": "game_over", "phase": "victory", "provinces": capital_ids, "factions": involved, "armies": [],
		"cause": cause,
		"numbers": {"winner": winner, "draw": draw, "turn": turn, "turns_played": turns_played,
			"battles": battles, "provinces_held": held.duplicate()},
		"text": text, "codex": codex,
	}
	var out := {
		"over": true, "winner": winner, "draw": draw, "turn": turn, "turns_played": turns_played,
		"battles": battles, "provinces_held": held, "captures": captures, "text": text, "event": event,
	}
	if not player_builds.is_empty():
		out["builds"] = player_builds
		event.numbers["builds"] = player_builds.duplicate(true)
	return out


## Each player's ruler build at the end of the game (design/M2_RULER.md §5.3), in seat order:
## {faction id: RulerRules.build_of(...) plus "starting_kept_power" and "rulers_lost" (deaths so far)}.
## {} in a game without rulers, so an M1 summary is unchanged.
static func builds(state: GameState, players: Array) -> Dictionary:
	var out := {}
	for fid in players:
		var b := RulerRules.build_of(state, str(fid))
		if b.is_empty():
			continue
		var f := state.find_faction(str(fid))
		b["starting_kept_power"] = RulerRules.starting_kept_power(state, f.id)
		b["rulers_lost"] = f.ruler_generation - 1 + (1 if f.ruler_status == RulerRules.DEAD else 0)
		out[f.id] = b
	return out


## The builds as one sentence per player, for the victory screen and the final turn report:
## "Builds: Aurel Crown, King Corvane II (alive, 1 ruler lost), 5 kept power (10 at the start), no
## mandates. Thornmane Clans, the Ninth Fang (dead, 1 ruler lost), 5 kept power, mandates: Iron
## Discipline and Drilled Ranks." "" in a game without rulers.
static func builds_text(state: GameState, players: Array) -> String:
	return _builds_sentence(state, players, builds(state, players))


## builds_text() from builds() already worked out (`all`).
static func _builds_sentence(state: GameState, players: Array, all: Dictionary) -> String:
	var parts := []
	for fid in players:
		if not all.has(str(fid)):
			continue
		var b: Dictionary = all[str(fid)]
		var status: String = "alive" if b.status == RulerRules.ALIVE else "dead"
		var lost := int(b.rulers_lost)
		if lost > 0:
			status += ", %d %s lost" % [lost, "ruler" if lost == 1 else "rulers"]
		var kept := "%d kept power" % int(b.kept_power)
		if int(b.starting_kept_power) != int(b.kept_power):
			kept += " (%d at the start)" % int(b.starting_kept_power)
		var names: Array = b.mandate_names
		var mandates := "no mandates" if names.is_empty() else "mandates: %s" % RulerRules._and_list(names)
		parts.append("%s, %s (%s), %s, %s." % [_faction_name(state, str(fid)), b.ruler_name, status, kept, mandates])
	if parts.is_empty():
		return ""
	return "Builds: %s" % " ".join(parts)



# Player-facing names come from TurnResolver's label helpers, so every text names things the same way.
static func _faction_name(s: GameState, fid: String) -> String:
	return TurnResolver._faction_name(s, fid)


static func _province_name(s: GameState, pid: String) -> String:
	return TurnResolver._province_name(s, pid)
