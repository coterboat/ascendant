class_name SaveGame
extends RefCounted
## Saved games: what a save holds, its header, and turning a save back into a game. Pure code: no nodes,
## no files (SaveStore reads and writes them), and the time comes in as an argument, so saves are
## testable and the same game always makes the same save.
##
## A save is a GameSession.record() (JSON-safe, and it replays deterministically) plus a header and the
## computer seats' dice:
##   {"format": "ascendant-save", "version": 1,
##    "header": {"version", "kind" ("auto" or "manual"), "name", "saved_at" (unix seconds, UTC), "turn",
##               "seed" (text), "rulers", "over", "seats": [{"faction", "faction_name", "kind", "level"}],
##               "factions": [faction names in seat order], "summary": one plain line},
##    "record": GameSession.record(),
##    "computer": {"rng": AISeat.rng_state() at the start of the turn, "turn": the last resolved turn,
##                 "notes": {faction id: the computer's notes for that turn}}}
## Loading (restore) replays the record through GameSession.from_record, so the session comes back at
## the start of the saved turn with seat 1 to act, then gives each computer seat its dice back
## (AISeat.restore), so the computer plays on exactly as it would have. Orders queued during a turn are
## never in a save: a game is always saved as it stood when the turn began.
## Every problem (not a save, a newer version, a damaged record) comes back as plain-language reasons
## (the #49 load checks), never a script error.

const FORMAT := "ascendant-save"
const VERSION := 1
const AUTO := "auto"
const MANUAL := "manual"
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## The first line of every reason a save can't be loaded.
const NOT_A_SAVE := "This file is not a saved game Ascendant can read."
const DAMAGED := "This saved game is damaged, so it can't be loaded."
## Shown wherever a game is saved or loaded (save dialog, load screen, quit question, load notice).
const ORDERS_NOTE := "A game is saved as it stood at the start of the turn: orders given during a turn are not saved."


## The computer's part of a save, taken at the start of a turn, before any computer seat plans it:
## {"rng": AISeat.rng_state(), "turn": the session's last resolved turn, "notes": {faction id: notes}}.
## {} for a game without computer seats.
static func computer_snapshot(computer: AISeat, session: GameSession) -> Dictionary:
	if computer == null or session == null or computer.factions().is_empty():
		return {}
	var notes := {}
	for entry in computer.report_notes(session):
		notes[String(entry.faction)] = Array(entry.notes).duplicate()
	return {"rng": computer.rng_state(), "turn": int(session.turn_report().get("turn", 0)), "notes": notes}


## A save of `session` (see the class comment). `computer` is computer_snapshot() from the start of the
## turn being played; `kind` AUTO or MANUAL; `save_name` what the player called it ("" gives the
## timestamped default); `unix_time` when it is saved (UTC seconds).
static func make(session: GameSession, computer: Dictionary, kind: String, save_name: String, unix_time: int) -> Dictionary:
	var title := save_name.strip_edges()
	if title.is_empty():
		title = default_name(kind, unix_time)
	var record := session.record()
	return {"format": FORMAT, "version": VERSION, "header": header(session, kind, title, unix_time, record),
		"record": record, "computer": computer.duplicate(true)}


## The header the load screen lists. See the class comment.
static func header(session: GameSession, kind: String, save_name: String, unix_time: int, record: Dictionary = {}) -> Dictionary:
	var state := session.state()
	var seats := []
	var names := []
	for fid in session.players():
		var f := state.find_faction(fid) if state else null
		var faction_name := f.faction_name if f else "An unknown faction"
		names.append(faction_name)
		seats.append({"faction": fid, "faction_name": faction_name,
			"kind": "computer" if session.is_computer(fid) else "human", "level": session.computer_level(fid)})
	if record.is_empty():
		record = session.record()
	return {"version": VERSION, "kind": kind, "name": save_name, "saved_at": unix_time, "turn": session.turn_number(),
		"seed": String(record.game_seed), "rulers": state != null and RulerRules.has_rulers(state), "over": session.is_over(),
		"seats": seats, "factions": names, "summary": summary_line(session)}


## "Turn 5: Aurel Crown holds 6 provinces, Thornmane Clans 5." Once the game is over: "Game over on turn
## 9: Aurel Crown won." (or "...: a draw.").
static func summary_line(session: GameSession) -> String:
	var state := session.state()
	if state == null:
		return "A game that could not start."
	if session.is_over():
		var winner := session.winner()
		var f := state.find_faction(winner)
		return "Game over on turn %d: %s." % [session.turn_number(), "%s won" % f.faction_name if f else "a draw"]
	var parts := []
	for fid in session.players():
		var held := 0
		for p in state.provinces:
			if p.owner == fid:
				held += 1
		var f := state.find_faction(fid)
		var faction_name := f.faction_name if f else "An unknown faction"
		parts.append("%s holds %s" % [faction_name, _provinces(held)] if parts.is_empty() else "%s %d" % [faction_name, held])
	return "Turn %d: %s." % [session.turn_number(), ", ".join(parts)]


## The name of a save the player did not name: "Saved 4 Oct 2026, 14:32" (when it was made) for a
## manual save, "Autosave" for an autosave.
static func default_name(kind: String, unix_time: int) -> String:
	return "Autosave" if kind == AUTO else "Saved %s" % when_text(unix_time)


## "4 Oct 2026, 14:32" in the computer's local time.
static func when_text(unix_time: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix_time + bias)
	return "%d %s %d, %02d:%02d" % [d.day, MONTHS[clampi(int(d.month) - 1, 0, 11)], d.year, d.hour, d.minute]


## "Aurel Crown (you) vs Thornmane Clans (Computer, Normal)", from a header's seats. With two people:
## "Aurel Crown vs Thornmane Clans, two players at one computer". With nobody: "...: watching the computer".
static func seats_text(header_data: Dictionary) -> String:
	var seats: Array = header_data.get("seats", []) if header_data.get("seats") is Array else []
	var humans := 0
	for s in seats:
		if s is Dictionary and String(s.get("kind", "")) == "human":
			humans += 1
	var parts := []
	for s in seats:
		if not (s is Dictionary):
			continue
		var who := String(s.get("faction_name", "An unknown faction"))
		if String(s.get("kind", "")) == "computer":
			who += " (Computer, %s)" % AISeat.level_name(String(s.get("level", "normal")))
		elif humans == 1:
			who += " (you)"
		parts.append(who)
	var text := " vs ".join(parts)
	if humans > 1:
		text += ", %d players at one computer" % humans
	elif humans == 0 and not parts.is_empty():
		text += ", watching the computer"
	return text


## [] when `save` looks like a save this version can load, otherwise why not (plain language).
static func check(save) -> Array:
	if not (save is Dictionary) or String(save.get("format", "")) != FORMAT:
		return [NOT_A_SAVE]
	var version := Serial.to_int(save.get("version"), -1)
	if version > VERSION:
		return ["This game was saved by a newer version of Ascendant (save version %d). This version can load saves up to version %d." % [version, VERSION]]
	if version < 1:
		return ["This save does not say which version of Ascendant made it, so it can't be loaded."]
	if not (save.get("record") is Dictionary):
		return [DAMAGED, "The save has no game in it."]
	if save.get("header") != null and not (save.get("header") is Dictionary):
		return [DAMAGED, "Its description should be a group of named values, but the saved data has %s there." % Serial._type_words(typeof(save.header))]
	return []


## The header of `save`, {} when it has none.
static func header_of(save) -> Dictionary:
	if save is Dictionary and save.get("header") is Dictionary:
		return save.header
	return {}


## Turns `save` back into a game: {"session": GameSession, "computer": AISeat with each computer seat's
## dice restored, "config": the GameScreen config for the game (for a rematch), "header", "errors"}.
## With errors, session and computer are null and the first error says, in plain words, why.
static func restore(save, battle_resolver: BattleResolver = null) -> Dictionary:
	var out := {"session": null, "computer": null, "config": {}, "header": header_of(save), "errors": []}
	var errors := check(save)
	if not errors.is_empty():
		out.errors = errors
		return out
	var loaded := GameSession.from_record(save.record, battle_resolver)
	if loaded.session == null:
		out.errors = [DAMAGED] + loaded.errors
		return out
	var session: GameSession = loaded.session
	var game_seed := Serial.to_int(save.record.game_seed)
	var computer := AISeat.new(session, game_seed)
	var part = save.get("computer", {})
	if not (part is Dictionary):
		part = {}
	var rng = part.get("rng", {})
	var notes = part.get("notes", {})
	var problems := computer.restore(rng if rng is Dictionary else {}, Serial.to_int(part.get("turn", 0)),
		notes if notes is Dictionary else {})
	if not problems.is_empty():
		out.errors = [DAMAGED] + problems
		return out
	out.session = session
	out.computer = computer
	out.config = config_for(session, game_seed)
	return out


## The GameScreen config of a loaded game ({"players", "seed"}, "ai" for computer seats, "rulers" and
## "builds" in a game with rulers, and "paths", "sieges", "magic", "fog", "independents" for the systems it has), which is
## what a rematch (NewGameScreen.prefill) starts from.
static func config_for(session: GameSession, game_seed: int) -> Dictionary:
	var config := {"players": session.players(), "seed": game_seed}
	if not session.computer_seats().is_empty():
		config["ai"] = session.computer_seats()
	var builds := session.builds()
	if not builds.is_empty():
		config["rulers"] = true
		var plain := {}
		for fid in builds:
			plain[fid] = {"ruler": builds[fid].get("ruler", ""), "mandates": Array(builds[fid].get("mandates", [])).duplicate()}
		config["builds"] = plain
	# MVP-2 (#163): the systems the loaded game has, so a rematch of it starts from the same boxes (a game without
	# them stays the basic game, whatever the new game screen's defaults are).
	var state := session.state()
	for key in ["paths", "sieges", "magic", "fog", "independents"]:
		if state.get(key) == true:
			config[key] = true
	return config


## The reasons as one or two sentences for the screen: the first reason, and the detail after it.
static func error_text(errors: Array) -> String:
	if errors.is_empty():
		return ""
	return " ".join(PackedStringArray(errors.slice(0, 2).map(func(e): return str(e))))


static func _provinces(n: int) -> String:
	return "1 province" if n == 1 else "%d provinces" % n
