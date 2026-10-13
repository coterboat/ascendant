class_name ChronicleStore
extends RefCounted
## UX-6 (design/UX_WAR_TABLE.md §5.2): what the Chronicle remembers OUTSIDE the game. Pins and dismissals live in a UI sidecar file beside the
## saves, keyed by the game's identity, the seat and the announcement id. They are never in GameSession, a save's game state, a record or
## a digest, so nothing here can change a game, and a save loaded without its sidecar simply has no pins.
##
## FOG AND HOTSEAT. Every read and write names a seat, and a seat is handed back only its own entries: seat 2 never sees seat 1's pins
## (tests/test_chronicle_store.gd). A pinned card keeps the payload it was shown with, its rendered, fog-filtered text and its focus
## province (ChronicleModel.pin_payload), and it is never re-rendered against a later state, so it can't reveal anything learned since.
##
## FILE. `chronicle_<identity>.json` in the saves folder (SaveStore.default_root), which SaveStore never lists (it reads only auto_ and
## save_ files). {"format": "ascendant-chronicle", "version": 1, "game": identity, "seats": {seat: {"pins": {id: payload},
## "dismissed": [id]}}}. Unreadable or foreign files are ignored (an empty store), never an error on screen.
##
## API:
##   ChronicleStore.identity(seed, players) -> String   the game's identity: its seed and its seats
##   open_game(identity, fresh)      start on a game: its sidecar is read, or (fresh: a new game) any old one is cleared
##   pin(seat, payload) / unpin(seat, id) / is_pinned(seat, id) / pinned(seat) -> Array (oldest turn first) / payload_of(seat, id)
##   dismiss(seat, id) / restore(seat, id) / is_dismissed(seat, id) / dismissed(seat) -> Array / restore_all(seat, ids)
##   save() -> String                "" or why not
##   path() -> String                the sidecar's path for the open game ("" when none)
##   forget_seat(seat)               drop one seat's entries (tests)

const FORMAT := "ascendant-chronicle"
const VERSION := 1
const PREFIX := "chronicle_"

var root := ""
var game := ""
var _seats := {}  # seat -> {"pins": {id: payload}, "dismissed": {id: true}}


func _init(folder: String = "") -> void:
	root = folder if not folder.is_empty() else SaveStore.default_root


## A game's identity: its seed and its seats in order, as a file-safe word.
static func identity(seed_text: String, players: Array) -> String:
	var seats := PackedStringArray()
	for p in players:
		seats.append(String(p).validate_filename())
	return ("%s_%s" % [seed_text.validate_filename(), "-".join(seats)]).strip_edges()


func path() -> String:
	return root.path_join("%s%s.json" % [PREFIX, game]) if not game.is_empty() else ""


## Starts on `identity`'s sidecar. `fresh` (a new game) clears whatever an earlier game with the same identity left; otherwise the file is
## read (a missing, unreadable or foreign file gives an empty store).
func open_game(identity_text: String, fresh: bool = false) -> void:
	game = identity_text
	_seats = {}
	if game.is_empty():
		return
	if fresh:
		if FileAccess.file_exists(path()):
			DirAccess.remove_absolute(path())
		return
	_read()


func pin(seat: String, payload: Dictionary) -> void:
	var id := String(payload.get("id", ""))
	if seat.is_empty() or id.is_empty():
		return
	_seat(seat).pins[id] = payload.duplicate(true)


func unpin(seat: String, id: String) -> void:
	if _seats.has(seat):
		_seats[seat].pins.erase(id)


func is_pinned(seat: String, id: String) -> bool:
	return _seats.has(seat) and _seats[seat].pins.has(id)


## The payload `seat` pinned under `id` ({} when none): as it was shown, never re-rendered.
func payload_of(seat: String, id: String) -> Dictionary:
	if not is_pinned(seat, id):
		return {}
	return ChronicleModel.from_payload(_seats[seat].pins[id])


## `seat`'s pinned payloads, oldest turn first (then by id).
func pinned(seat: String) -> Array:
	var out := []
	if not _seats.has(seat):
		return out
	for id in _seats[seat].pins:
		out.append(ChronicleModel.from_payload(_seats[seat].pins[id]))
	out.sort_custom(func(a, b):
		if int(a.get("turn", 0)) != int(b.get("turn", 0)):
			return int(a.get("turn", 0)) < int(b.get("turn", 0))
		return String(a.get("id", "")) < String(b.get("id", "")))
	return out


func dismiss(seat: String, id: String) -> void:
	if seat.is_empty() or id.is_empty():
		return
	_seat(seat).dismissed[id] = true


func restore(seat: String, id: String) -> void:
	if _seats.has(seat):
		_seats[seat].dismissed.erase(id)


func restore_all(seat: String, ids: Array) -> void:
	for id in ids:
		restore(seat, String(id))


func is_dismissed(seat: String, id: String) -> bool:
	return _seats.has(seat) and _seats[seat].dismissed.has(id)


func dismissed(seat: String) -> Array:
	return _seats[seat].dismissed.keys() if _seats.has(seat) else []


func forget_seat(seat: String) -> void:
	_seats.erase(seat)


## Writes the sidecar. "" or why it could not be saved (the game goes on either way). An empty store removes its file.
func save() -> String:
	if game.is_empty():
		return ""
	var data := {"format": FORMAT, "version": VERSION, "game": game, "seats": {}}
	var any := false
	for seat in _seats:
		var s: Dictionary = _seats[seat]
		if s.pins.is_empty() and s.dismissed.is_empty():
			continue
		any = true
		data.seats[seat] = {"pins": s.pins, "dismissed": s.dismissed.keys()}
	if not any:
		if FileAccess.file_exists(path()):
			DirAccess.remove_absolute(path())
		return ""
	var made := DirAccess.make_dir_recursive_absolute(root)
	if made != OK and not DirAccess.dir_exists_absolute(root):
		return "The Chronicle's notes could not be saved: the save folder could not be created."
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file == null:
		return "The Chronicle's notes could not be saved."
	file.store_string(JSON.stringify(data))
	file.close()
	return ""


# --- internals ------------------------------------------------------------------------------------

func _seat(seat: String) -> Dictionary:
	if not _seats.has(seat):
		_seats[seat] = {"pins": {}, "dismissed": {}}
	return _seats[seat]


func _read() -> void:
	if not FileAccess.file_exists(path()):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path())) != OK or not (json.data is Dictionary):
		return
	var data: Dictionary = json.data
	if String(data.get("format", "")) != FORMAT or String(data.get("game", "")) != game or not (data.get("seats") is Dictionary):
		return
	for seat in data.seats:
		var s = data.seats[seat]
		if not (s is Dictionary):
			continue
		var mine := _seat(String(seat))
		if s.get("pins") is Dictionary:
			for id in s.pins:
				if s.pins[id] is Dictionary:
					mine.pins[String(id)] = s.pins[id]
		if s.get("dismissed") is Array:
			for id in s.dismissed:
				mine.dismissed[String(id)] = true
